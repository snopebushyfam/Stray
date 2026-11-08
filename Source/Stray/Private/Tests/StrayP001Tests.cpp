// STRAY - automation tests for Prototype 001 data + math (Logic stories).
// Run: Session Frontend > Automation > "Stray.P001", or
//   UnrealEditor-Cmd.exe Stray.uproject -ExecCmds="Automation RunTests Stray.P001;Quit" -unattended -nullrhi -log
// These tests check data and math only. They are NOT a visual/play test.
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "StrayObjMesh.h"
#include "StrayStreetLayout.h"

#define STRAY_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FStrayEnuMappingTest, "Stray.P001.EnuToUnrealMapping", STRAY_TEST_FLAGS)
bool FStrayEnuMappingTest::RunTest(const FString& Parameters)
{
	// East -> +X, North -> -Y, metres -> cm.
	TestEqual(TEXT("east"), StrayGeo::EnuToUnreal(1.0, 0.0, 0.0), FVector(100.0, 0.0, 0.0));
	TestEqual(TEXT("north"), StrayGeo::EnuToUnreal(0.0, 1.0, 0.0), FVector(0.0, -100.0, 0.0));
	TestEqual(TEXT("up"), StrayGeo::EnuToUnreal(0.0, 0.0, 1.0), FVector(0.0, 0.0, 100.0));
	// Yaw of north must point to -Y in Unreal (-90 deg); east is 0 deg.
	TestTrue(TEXT("yaw north"), FMath::IsNearlyEqual(StrayGeo::EnDirToYaw(FVector2D(0, 1)), -90.0, 1e-6));
	TestTrue(TEXT("yaw east"), FMath::IsNearlyEqual(StrayGeo::EnDirToYaw(FVector2D(1, 0)), 0.0, 1e-6));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FStrayLayoutFileTest, "Stray.P001.LayoutFile", STRAY_TEST_FLAGS)
bool FStrayLayoutFileTest::RunTest(const FString& Parameters)
{
	FStrayP001Layout L;
	FString Error;
	if (!TestTrue(TEXT("layout loads: ") + Error, FStrayP001Layout::LoadFromFile(FStrayP001Layout::DefaultLayoutPath(), L, Error)))
	{
		return false;
	}
	TestTrue(TEXT("segment is ~150 m"), FMath::IsNearlyEqual(L.Street.Length(), 150.0, 5.0));
	TestTrue(TEXT("at least 10 street lamps"), L.Lamps.Num() >= 10);
	TestTrue(TEXT("kiosk label"), L.Kiosk.Label == TEXT("KIOSK"));
	TestTrue(TEXT("club label"), L.Club.Label == TEXT("NACHTFLUG"));
	TestTrue(TEXT("spawn is on a sidewalk"), L.IsOnSidewalk(L.SpawnEN));
	TestTrue(TEXT("viewpoints exist"), L.Viewpoints.Num() >= 3);
	TestTrue(TEXT("night is darker than day"), L.Night.KeyLux < L.Day.KeyLux);
	TestTrue(TEXT("night exposure range below day"), L.Night.ExposureMaxEV100 < L.Day.ExposureMinEV100);

	// Kiosk and club sit on opposite sides of the street, on the facades.
	const auto SideOf = [&L](const FVector2D& P) { return FVector2D::DotProduct(P - L.Street.OriginEN, L.Street.RightEN()); };
	TestTrue(TEXT("kiosk on east facade"), SideOf(L.Kiosk.PosEN) > L.Street.KerbHalfWidth);
	TestTrue(TEXT("club on west facade"), SideOf(L.Club.PosEN) < -L.Street.KerbHalfWidth);
	// Facade normals face the street axis.
	TestTrue(TEXT("kiosk faces street"), FVector2D::DotProduct(L.Kiosk.NormalEN, L.Street.RightEN()) < -0.8);
	TestTrue(TEXT("club faces street"), FVector2D::DotProduct(L.Club.NormalEN, L.Street.RightEN()) > 0.8);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FStraySpawnTest, "Stray.P001.SpawnAboveGround", STRAY_TEST_FLAGS)
bool FStraySpawnTest::RunTest(const FString& Parameters)
{
	FStrayP001Layout L;
	FString Error;
	if (!TestTrue(TEXT("layout loads"), FStrayP001Layout::LoadFromFile(FStrayP001Layout::DefaultLayoutPath(), L, Error)))
	{
		return false;
	}
	const double HalfHeight = 90.0;
	const FTransform T = L.ComputeSpawnTransform(HalfHeight, 5.0);
	// Capsule bottom must be exactly 5 cm above the (DGM1-derived) sidewalk surface at the spawn.
	const double Bottom = T.GetLocation().Z - HalfHeight;
	const double Sidewalk = L.GroundZAt(L.SpawnEN) * 100.0;
	TestTrue(TEXT("capsule bottom 5 cm above sidewalk"), FMath::IsNearlyEqual(Bottom, Sidewalk + 5.0, 0.01));
	// And the sidewalk is above the carriageway next to it (kerb), never below.
	const FVector2D SV = L.ToStreetFrame(L.SpawnEN);
	TestTrue(TEXT("sidewalk above road"), Sidewalk > L.RoadZ(SV.X, -L.Street.KerbHalfWidth) * 100.0);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FStrayProfileTerrainTest, "Stray.P001.ProfileFollowsTerrain", STRAY_TEST_FLAGS)
bool FStrayProfileTerrainTest::RunTest(const FString& Parameters)
{
	// Arrange
	FStrayP001Layout L;
	FString Error;
	if (!TestTrue(TEXT("layout loads"), FStrayP001Layout::LoadFromFile(FStrayP001Layout::DefaultLayoutPath(), L, Error)))
	{
		return false;
	}
	// Act
	const FStrayProfileSample South = L.ProfileAt(L.Street.SStart);
	const FStrayProfileSample North = L.ProfileAt(L.Street.SEnd);
	// Assert: profile covers the segment; the real Ring falls towards Friesenplatz (DGM1: ~0.5 m).
	TestTrue(TEXT("profile has rows"), L.Profile.Num() >= 40);
	TestTrue(TEXT("road falls to the north by 0.2..2 m"), South.RoadCentre - North.RoadCentre > 0.2 && South.RoadCentre - North.RoadCentre < 2.0);
	for (const FStrayProfileSample& P : L.Profile)
	{
		const double KerbW = P.SidewalkWest - P.RoadEdgeWest;
		const double KerbE = P.SidewalkEast - P.RoadEdgeEast;
		TestTrue(FString::Printf(TEXT("kerbs 8..30 cm at s=%.1f"), P.S), KerbW >= 0.08 && KerbW <= 0.30 && KerbE >= 0.08 && KerbE <= 0.30);
	}
	// Interpolation is continuous: halfway between two rows lies between their values.
	const FStrayProfileSample& A = L.Profile[10];
	const FStrayProfileSample& B = L.Profile[11];
	const double Mid = L.ProfileAt((A.S + B.S) * 0.5).RoadCentre;
	TestTrue(TEXT("interpolated centre between neighbours"), Mid >= FMath::Min(A.RoadCentre, B.RoadCentre) - 1e-9 && Mid <= FMath::Max(A.RoadCentre, B.RoadCentre) + 1e-9);
	TestFalse(TEXT("terrain mesh referenced"), L.TerrainMeshRelPath.IsEmpty());
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FStrayLod2MeshTest, "Stray.P001.Lod2Mesh", STRAY_TEST_FLAGS)
bool FStrayLod2MeshTest::RunTest(const FString& Parameters)
{
	FStrayP001Layout L;
	FString Error;
	if (!TestTrue(TEXT("layout loads"), FStrayP001Layout::LoadFromFile(FStrayP001Layout::DefaultLayoutPath(), L, Error)))
	{
		return false;
	}
	FString Text;
	const FString Path = FPaths::ProjectContentDir() / L.Lod2MeshRelPath;
	if (!TestTrue(TEXT("OBJ readable (git lfs pull?)"), FFileHelper::LoadFileToString(Text, *Path)))
	{
		return false;
	}
	TestFalse(TEXT("OBJ is not an LFS pointer"), Text.StartsWith(TEXT("version https://git-lfs")));
	FStrayObjMesh Mesh;
	if (!TestTrue(TEXT("OBJ parses: ") + Error, FStrayObjMesh::ParseObj(Text, false, Mesh, Error)))
	{
		return false;
	}
	TestTrue(TEXT(">100 buildings"), Mesh.ObjectCount > 100);
	TestTrue(TEXT(">5000 triangles"), Mesh.NumTriangles() > 5000);
	// Buildings rise to tens of metres, not kilometres (unit check) and start near street level.
	TestTrue(TEXT("max height < 80 m"), Mesh.Bounds.Max.Z < 8000.0);
	TestTrue(TEXT("min height within 3 m of street"), FMath::Abs(Mesh.Bounds.Min.Z) < 300.0);
	// Roof normals must point up after the handedness conversion.
	for (const FStrayObjSection& S : Mesh.Sections)
	{
		if (S.MaterialName.Contains(TEXT("roof")))
		{
			int32 Up = 0;
			for (const FVector& N : S.Normals) { Up += N.Z > 0.0 ? 1 : 0; }
			TestTrue(TEXT("roof normals point up"), Up > S.Normals.Num() * 95 / 100);
		}
	}
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
