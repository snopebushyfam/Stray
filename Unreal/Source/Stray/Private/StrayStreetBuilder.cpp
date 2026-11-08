// STRAY - Prototype 001 street builder. See StrayStreetBuilder.h.
#include "StrayStreetBuilder.h"

#include "Stray.h"
#include "StrayObjMesh.h"

#include "Components/BoxComponent.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/PostProcessComponent.h"
#include "Components/RectLightComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/TextRenderComponent.h"
#include "Engine/CollisionProfile.h"
#include "Engine/StaticMesh.h"
#include "HAL/FileManager.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "ProceduralMeshComponent.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	const TCHAR* FallbackMaterialPath = TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial");

	// Palette (linear albedo). Realistic night city, not cartoon.
	const FLinearColor Asphalt(0.035f, 0.035f, 0.038f);
	const FLinearColor Paving(0.22f, 0.21f, 0.20f);
	const FLinearColor KerbStone(0.32f, 0.31f, 0.30f);
	const FLinearColor MedianStone(0.12f, 0.12f, 0.12f);
	const FLinearColor LanePaint(0.65f, 0.65f, 0.62f);
	const FLinearColor GroundDark(0.05f, 0.05f, 0.05f);
	const FLinearColor Facade(0.42f, 0.38f, 0.33f);
	const FLinearColor Roof(0.12f, 0.10f, 0.10f);
	const FLinearColor Metal(0.08f, 0.08f, 0.09f);
	const FLinearColor DarkGlass(0.01f, 0.01f, 0.012f);
	const FLinearColor Chrome(0.6f, 0.6f, 0.62f);

	/** Parsed LoD2 mesh, cached by path + timestamp so editor drags do not re-parse 30k triangles. */
	TSharedPtr<FStrayObjMesh> LoadObjCached(const FString& Path, bool bDoubleSided, FString& OutError)
	{
		struct FEntry { FDateTime Stamp; bool bDouble; TSharedPtr<FStrayObjMesh> Mesh; };
		static TMap<FString, FEntry> Cache;
		const FDateTime Stamp = IFileManager::Get().GetTimeStamp(*Path);
		if (const FEntry* E = Cache.Find(Path))
		{
			if (E->Stamp == Stamp && E->bDouble == bDoubleSided)
			{
				return E->Mesh;
			}
		}
		FString Text;
		if (!FFileHelper::LoadFileToString(Text, *Path))
		{
			OutError = FString::Printf(TEXT("cannot read LoD2 mesh %s (Git LFS pointer not pulled?)"), *Path);
			return nullptr;
		}
		if (Text.StartsWith(TEXT("version https://git-lfs")))
		{
			OutError = FString::Printf(TEXT("%s is a Git LFS pointer, run 'git lfs pull'"), *Path);
			return nullptr;
		}
		TSharedPtr<FStrayObjMesh> Mesh = MakeShared<FStrayObjMesh>();
		if (!FStrayObjMesh::ParseObj(Text, bDoubleSided, *Mesh, OutError))
		{
			return nullptr;
		}
		Cache.Add(Path, { Stamp, bDoubleSided, Mesh });
		return Mesh;
	}

	FVector Ue(const FVector2D& EN, double Up) { return StrayGeo::EnuToUnreal(EN.X, EN.Y, Up); }
}

AStrayStreetBuilder::AStrayStreetBuilder()
{
	PrimaryActorTick.bCanEverTick = false;

	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = Root;

	// Night key light ("moon"). Movable: nothing in this project is baked.
	KeyLight = CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("KeyLight"));
	KeyLight->SetupAttachment(Root);
	KeyLight->SetMobility(EComponentMobility::Movable);
	KeyLight->bAtmosphereSunLight = true;
	KeyLight->SetCastShadows(true);

	SkyAtmosphere = CreateDefaultSubobject<USkyAtmosphereComponent>(TEXT("SkyAtmosphere"));
	SkyAtmosphere->SetupAttachment(Root);

	SkyLight = CreateDefaultSubobject<USkyLightComponent>(TEXT("SkyLight"));
	SkyLight->SetupAttachment(Root);
	SkyLight->SetMobility(EComponentMobility::Movable);
	SkyLight->SourceType = ESkyLightSourceType::SLS_CapturedScene;
	SkyLight->bRealTimeCapture = true;

	HeightFog = CreateDefaultSubobject<UExponentialHeightFogComponent>(TEXT("HeightFog"));
	HeightFog->SetupAttachment(Root);

	// Unbound post process: explicit exposure range, so a night scene cannot be
	// auto-exposed into a grey "day" image or crushed to black.
	PostProcess = CreateDefaultSubobject<UPostProcessComponent>(TEXT("PostProcess"));
	PostProcess->SetupAttachment(Root);
	PostProcess->bUnbound = true;

	Buildings = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("Lod2Buildings"));
	Buildings->SetupAttachment(Root);
	Buildings->bUseComplexAsSimpleCollision = true;
	Buildings->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
	Buildings->bUseAsyncCooking = false; // collision must exist on the first frame the player lands

	Terrain = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("Dgm1Terrain"));
	Terrain->SetupAttachment(Root);
	Terrain->bUseComplexAsSimpleCollision = true;
	Terrain->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
	Terrain->bUseAsyncCooking = false;

	StreetSurface = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("StreetSurface"));
	StreetSurface->SetupAttachment(Root);
	StreetSurface->bUseComplexAsSimpleCollision = true;
	StreetSurface->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
	StreetSurface->bUseAsyncCooking = false;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeFinder(TEXT("/Engine/BasicShapes/Cube.Cube"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderFinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereFinder(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	CubeMesh = CubeFinder.Object;
	CylinderMesh = CylinderFinder.Object;
	SphereMesh = SphereFinder.Object;
}

void AStrayStreetBuilder::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	Rebuild();
}

void AStrayStreetBuilder::BeginPlay()
{
	Super::BeginPlay();
	// Transient components are not duplicated into PIE / not saved in cooked maps.
	if (Generated.Num() == 0)
	{
		Rebuild();
	}
}

template <class T>
T* AStrayStreetBuilder::NewGenerated(const TCHAR* BaseName)
{
	T* C = NewObject<T>(this, MakeUniqueObjectName(this, T::StaticClass(), FName(BaseName)),
		RF_Transient | RF_TextExportTransient | RF_DuplicateTransient);
	C->SetupAttachment(Root);
	Generated.Add(C);
	return C;
}

void AStrayStreetBuilder::ClearGenerated()
{
	for (USceneComponent* C : Generated)
	{
		if (IsValid(C))
		{
			C->DestroyComponent();
		}
	}
	Generated.Reset();
	Buildings->ClearAllMeshSections();
	Terrain->ClearAllMeshSections();
	StreetSurface->ClearAllMeshSections();
}

void AStrayStreetBuilder::Rebuild()
{
	ClearGenerated();
	Stats = FStrayBuildStats();
	MaterialCache.Reset();

	SurfaceBase = Cast<UMaterialInterface>(SurfaceMaterialPath.TryLoad());
	EmissiveBase = Cast<UMaterialInterface>(EmissiveMaterialPath.TryLoad());
	Stats.bUsingProjectMaterials = SurfaceBase != nullptr && EmissiveBase != nullptr;
	bEmissiveIsUnlit = EmissiveBase != nullptr;
	UMaterialInterface* Fallback = LoadObject<UMaterialInterface>(nullptr, FallbackMaterialPath);
	if (!SurfaceBase) { SurfaceBase = Fallback; }
	if (!EmissiveBase) { EmissiveBase = Fallback; }
	if (!Stats.bUsingProjectMaterials)
	{
		UE_LOG(LogStray, Warning, TEXT("STRAY_DIAG materials=fallback (run Content/Python/stray_setup_p001.py to create M_Stray_Surface / M_Stray_Emissive)"));
	}

	const FString LayoutPath = FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir() / LayoutFile);
	FString Error;
	Layout = FStrayP001Layout();
	if (!FStrayP001Layout::LoadFromFile(LayoutPath, Layout, Error))
	{
		Stats.Error = Error;
		UE_LOG(LogStray, Error, TEXT("STRAY_DIAG build=failed layout=%s error=%s"), *LayoutPath, *Error);
		ApplyLighting();
		return;
	}
	Stats.bLayoutLoaded = true;

	BuildGround();
	BuildLod2();
	BuildLamps();
	BuildShopfronts();
	BuildWindows();
	BuildKiosk();
	BuildClub();
	BuildEndBarriers();
	ApplyLighting();
	CountLight(KeyLight->CastShadows);

	Stats.Components = Generated.Num();
	UE_LOG(LogStray, Log,
		TEXT("STRAY_DIAG build=ok lod2=%d buildings=%d triangles=%d terrain=%d terrain_tris=%d street_tris=%d profile_rows=%d lights=%d shadow_lights=%d components=%d project_materials=%d street_len_m=%.1f"),
		Stats.bLod2Loaded ? 1 : 0, Stats.Lod2Buildings, Stats.Lod2Triangles, Stats.bTerrainLoaded ? 1 : 0, Stats.TerrainTriangles,
		Stats.StreetTriangles, Layout.Profile.Num(), Stats.Lights, Stats.ShadowCastingLights,
		Stats.Components, Stats.bUsingProjectMaterials ? 1 : 0, Layout.Street.Length());
}

FTransform AStrayStreetBuilder::GetSpawnTransform(double CapsuleHalfHeightCm) const
{
	return Layout.ComputeSpawnTransform(CapsuleHalfHeightCm) * GetActorTransform();
}

// ---------------------------------------------------------------------------------------------
// Materials and primitives
// ---------------------------------------------------------------------------------------------

UMaterialInterface* AStrayStreetBuilder::Surface(const FLinearColor& Color, float Roughness)
{
	const FString Key = FString::Printf(TEXT("S_%s_%.2f"), *Color.ToString(), Roughness);
	if (TObjectPtr<UMaterialInstanceDynamic>* Found = MaterialCache.Find(Key))
	{
		return *Found;
	}
	UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(SurfaceBase, this);
	MID->SetVectorParameterValue(TEXT("Color"), Color);
	MID->SetScalarParameterValue(TEXT("Roughness"), Roughness);
	MaterialCache.Add(Key, MID);
	return MID;
}

UMaterialInterface* AStrayStreetBuilder::Emissive(const FLinearColor& Color, float Nits)
{
	const FString Key = FString::Printf(TEXT("E_%s_%.1f"), *Color.ToString(), Nits);
	if (TObjectPtr<UMaterialInstanceDynamic>* Found = MaterialCache.Find(Key))
	{
		return *Found;
	}
	UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(EmissiveBase, this);
	MID->SetVectorParameterValue(TEXT("Color"), Color);
	MID->SetScalarParameterValue(TEXT("Intensity"), Nits);
	MaterialCache.Add(Key, MID);
	return MID;
}

UStaticMeshComponent* AStrayStreetBuilder::AddMesh(UStaticMesh* Mesh, const FVector& LocationCm, const FRotator& Rotation,
	const FVector& Scale, UMaterialInterface* Material, bool bCollision)
{
	UStaticMeshComponent* C = NewGenerated<UStaticMeshComponent>(TEXT("Mesh"));
	C->SetStaticMesh(Mesh);
	C->SetRelativeTransform(FTransform(Rotation, LocationCm, Scale));
	C->SetMaterial(0, Material);
	C->SetCollisionProfileName(bCollision ? UCollisionProfile::BlockAll_ProfileName : UCollisionProfile::NoCollision_ProfileName);
	C->SetCanEverAffectNavigation(bCollision);
	C->RegisterComponent();
	return C;
}

UStaticMeshComponent* AStrayStreetBuilder::AddBox(const FVector& CenterCm, const FVector& SizeM, double Yaw,
	UMaterialInterface* Material, bool bCollision)
{
	// /Engine/BasicShapes/Cube is 100 cm with a centred pivot, so scale == size in metres.
	return AddMesh(CubeMesh, CenterCm, FRotator(0.0, Yaw, 0.0), SizeM, Material, bCollision);
}

UInstancedStaticMeshComponent* AStrayStreetBuilder::AddInstanced(UStaticMesh* Mesh, UMaterialInterface* Material, bool bCollision)
{
	UInstancedStaticMeshComponent* C = NewGenerated<UInstancedStaticMeshComponent>(TEXT("Instanced"));
	C->SetStaticMesh(Mesh);
	C->SetMaterial(0, Material);
	C->SetCollisionProfileName(bCollision ? UCollisionProfile::BlockAll_ProfileName : UCollisionProfile::NoCollision_ProfileName);
	C->RegisterComponent();
	return C;
}

void AStrayStreetBuilder::AddText(const FString& Text, const FVector& LocationCm, double Yaw, float WorldSizeCm, const FColor& Color)
{
	// A text render component faces its local +X axis.
	UTextRenderComponent* T = NewGenerated<UTextRenderComponent>(TEXT("Text"));
	T->SetText(FText::FromString(Text));
	T->SetTextRenderColor(Color);
	T->SetWorldSize(WorldSizeCm);
	T->SetHorizontalAlignment(EHTA_Center);
	T->SetVerticalAlignment(EVRTA_TextCenter);
	T->SetRelativeTransform(FTransform(FRotator(0.0, Yaw, 0.0), LocationCm));
	T->SetCollisionProfileName(UCollisionProfile::NoCollision_ProfileName);
	T->RegisterComponent();
}

void AStrayStreetBuilder::CountLight(bool bShadows)
{
	++Stats.Lights;
	Stats.ShadowCastingLights += bShadows ? 1 : 0;
}

// ---------------------------------------------------------------------------------------------
// Street
// ---------------------------------------------------------------------------------------------

void AStrayStreetBuilder::BuildGround()
{
	// Safety plate 1 m below the lowest terrain point: catches any hole, normally never seen.
	const FVector2D Mid = (Layout.GroundMinEN + Layout.GroundMaxEN) * 0.5;
	const FVector2D Size = Layout.GroundMaxEN - Layout.GroundMinEN;
	AddBox(Ue(Mid, Layout.GroundZ - 0.25), FVector(Size.X, Size.Y, 0.5), 0.0, Surface(GroundDark, 0.95f), true);

	BuildTerrain();
	BuildStreetSurface();
	BuildMarkings();
}

void AStrayStreetBuilder::BuildTerrain()
{
	if (Layout.TerrainMeshRelPath.IsEmpty())
	{
		UE_LOG(LogStray, Warning, TEXT("STRAY_DIAG terrain=none (layout has no terrain_mesh)"));
		return;
	}
	const FString Path = Layout.ResolveDataPath(Layout.TerrainMeshRelPath);
	FString Error;
	const TSharedPtr<FStrayObjMesh> Mesh = LoadObjCached(Path, bDoubleSidedProceduralMeshes, Error);
	if (!Mesh.IsValid())
	{
		UE_LOG(LogStray, Error, TEXT("STRAY_DIAG terrain=failed error=%s"), *Error);
		return;
	}
	const TArray<FVector2D> NoUV;
	const TArray<FLinearColor> NoColors;
	const TArray<FProcMeshTangent> NoTangents;
	for (int32 I = 0; I < Mesh->Sections.Num(); ++I)
	{
		const FStrayObjSection& S = Mesh->Sections[I];
		Terrain->CreateMeshSection_LinearColor(I, S.Positions, S.Indices, S.Normals, NoUV, NoColors, NoTangents, true);
		Terrain->SetMaterial(I, Surface(FLinearColor(0.07f, 0.065f, 0.06f), 0.95f));
	}
	Stats.bTerrainLoaded = true;
	Stats.TerrainTriangles = Mesh->NumTriangles() / (bDoubleSidedProceduralMeshes ? 2 : 1);
}

namespace
{
	/** Triangle soup for one material section of the street surface. */
	struct FStripBuilder
	{
		TArray<FVector> Pos;
		TArray<FVector> Nrm;
		TArray<int32> Idx;
		bool bDoubleSided = true;

		/**
		 * Adds triangle A-B-C facing Desired. Unreal's front face satisfies
		 * Normal == (C - A) ^ (B - A) (same rule StrayObjMesh relies on).
		 */
		void Tri(FVector A, FVector B, FVector C, const FVector& Desired)
		{
			FVector N = (C - A) ^ (B - A);
			if (N.SizeSquared() < 1e-6)
			{
				return;
			}
			if ((N | Desired) < 0.0)
			{
				Swap(B, C);
				N = -N;
			}
			N.Normalize();
			for (int32 Pass = 0; Pass < (bDoubleSided ? 2 : 1); ++Pass)
			{
				const int32 Base = Pos.Num();
				Pos.Append({ A, B, C });
				const FVector PN = Pass == 0 ? N : -N;
				Nrm.Append({ PN, PN, PN });
				Idx.Append(Pass == 0 ? TArray<int32>{ Base, Base + 1, Base + 2 } : TArray<int32>{ Base, Base + 2, Base + 1 });
			}
		}

		void Quad(const FVector& P00, const FVector& P10, const FVector& P11, const FVector& P01, const FVector& Desired)
		{
			Tri(P00, P10, P11, Desired);
			Tri(P00, P11, P01, Desired);
		}
	};
}

void AStrayStreetBuilder::BuildStreetSurface()
{
	const FStrayStreetDef& St = Layout.Street;
	const double K = St.KerbHalfWidth;
	const double M = St.MedianHalfWidth;
	const double KerbW = FStrayP001Layout::KerbStoneWidth;
	const double FW = Layout.ProfileFacadeVWest;
	const double FE = Layout.ProfileFacadeVEast;
	const double Skirt = 1.2; // vertical skirts below every free edge (no see-through gaps)
	const FVector Up(0, 0, 1);
	const FVector Right = StrayGeo::EnDirToUnreal(St.RightEN());
	const FVector Along = StrayGeo::EnDirToUnreal(St.AxisEN());

	TArray<double> Ss;
	for (double S = St.SStart; S < St.SEnd - 0.01; S += 1.5)
	{
		Ss.Add(S);
	}
	Ss.Add(St.SEnd);

	enum ESection { Road, Median, Walk, KerbSec, SkirtSec, Num };
	FStripBuilder B[Num];
	for (FStripBuilder& X : B)
	{
		X.bDoubleSided = bDoubleSidedProceduralMeshes;
	}
	auto P = [&](double S, double V, double Z) { return Ue(St.ToEN(S, V), Z); };
	auto Prof = [&](double S) { return Layout.ProfileAt(S); };

	// Cross-section, west -> east: (v, height function). Heights are metres.
	auto WalkW = [&](double S) { return Prof(S).SidewalkWest; };
	auto WalkE = [&](double S) { return Prof(S).SidewalkEast; };
	auto MedTop = [&](double S) { return Prof(S).RoadCentre + FStrayP001Layout::MedianRise; };

	for (int32 I = 0; I + 1 < Ss.Num(); ++I)
	{
		const double S0 = Ss[I], S1 = Ss[I + 1];
		auto Top = [&](int32 Sec, double V0, double V1, TFunctionRef<double(double, double)> Z)
		{
			B[Sec].Quad(P(S0, V0, Z(S0, V0)), P(S1, V0, Z(S1, V0)), P(S1, V1, Z(S1, V1)), P(S0, V1, Z(S0, V1)), Up);
		};
		auto Wall = [&](int32 Sec, double V, TFunctionRef<double(double)> Lo, TFunctionRef<double(double)> Hi, const FVector& Facing)
		{
			B[Sec].Quad(P(S0, V, Lo(S0)), P(S1, V, Lo(S1)), P(S1, V, Hi(S1)), P(S0, V, Hi(S0)), Facing);
		};
		const auto RoadAt = [&](double S, double V) { return Layout.RoadZ(S, V); };

		// Tops (sidewalks fall towards the kerb: kerb value -> facade value, flat beyond the facade line)
		const auto WalkAt = [&](double S, double V) { return Layout.SidewalkZ(S, V); };
		Top(Walk, St.SidewalkWestOuter, FW, WalkAt);
		Top(Walk, FW, -K - KerbW, WalkAt);
		Top(KerbSec, -K - KerbW, -K, [&](double S, double) { return WalkW(S) + 0.005; });
		Top(Road, -K, -M, RoadAt);
		Top(Median, -M, M, [&](double S, double) { return MedTop(S); });
		Top(Road, M, K, RoadAt);
		Top(KerbSec, K, K + KerbW, [&](double S, double) { return WalkE(S) + 0.005; });
		Top(Walk, K + KerbW, FE, WalkAt);
		Top(Walk, FE, St.SidewalkEastOuter, WalkAt);
		// Kerb and median faces
		Wall(KerbSec, -K, [&](double S) { return Layout.RoadZ(S, -K); }, [&](double S) { return WalkW(S) + 0.005; }, Right);
		Wall(KerbSec, K, [&](double S) { return Layout.RoadZ(S, K); }, [&](double S) { return WalkE(S) + 0.005; }, -Right);
		Wall(Median, -M, [&](double S) { return Layout.RoadZ(S, -M); }, MedTop, -Right);
		Wall(Median, M, [&](double S) { return Layout.RoadZ(S, M); }, MedTop, Right);
		// Outer skirts
		const auto OuterW = [&](double S) { return Layout.SidewalkZ(S, St.SidewalkWestOuter); };
		const auto OuterE = [&](double S) { return Layout.SidewalkZ(S, St.SidewalkEastOuter); };
		Wall(SkirtSec, St.SidewalkWestOuter, [&](double S) { return OuterW(S) - Skirt; }, OuterW, -Right);
		Wall(SkirtSec, St.SidewalkEastOuter, [&](double S) { return OuterE(S) - Skirt; }, OuterE, Right);
	}
	// End skirts: close both ends of the street body down to Skirt below the lowest point.
	for (const double S : { St.SStart, St.SEnd })
	{
		const FVector Facing = S == St.SStart ? -Along : Along;
		const FStrayProfileSample Pr = Prof(S);
		const double Bottom = FMath::Min(Pr.RoadEdgeWest, Pr.RoadEdgeEast) - Skirt;
		const double Vs[] = { St.SidewalkWestOuter, FW, -K, -M, M, K, FE, St.SidewalkEastOuter };
		// Highest surface touching v (covers the vertical kerb / median faces at the cut).
		const auto TopZMax = [&](double V)
		{
			double Z = Layout.RoadZ(S, V);
			if (FMath::Abs(V) >= K - 1e-6) { Z = FMath::Max(Z, Layout.SidewalkZ(S, V) + 0.005); }
			if (FMath::Abs(V) <= M + 1e-6) { Z = FMath::Max(Z, MedTop(S)); }
			return Z;
		};
		for (int32 J = 0; J + 1 < UE_ARRAY_COUNT(Vs); ++J)
		{
			const double Va = Vs[J], Vb = Vs[J + 1];
			B[SkirtSec].Quad(P(S, Va, Bottom), P(S, Vb, Bottom), P(S, Vb, TopZMax(Vb)), P(S, Va, TopZMax(Va)), Facing);
		}
	}

	const FLinearColor Colors[Num] = { Asphalt, MedianStone, Paving, KerbStone, GroundDark };
	const float Rough[Num] = { 0.9f, 0.85f, 0.8f, 0.7f, 0.95f };
	const TArray<FVector2D> NoUV;
	const TArray<FLinearColor> NoColors;
	const TArray<FProcMeshTangent> NoTangents;
	for (int32 Sec = 0; Sec < Num; ++Sec)
	{
		StreetSurface->CreateMeshSection_LinearColor(Sec, B[Sec].Pos, B[Sec].Idx, B[Sec].Nrm, NoUV, NoColors, NoTangents, true);
		StreetSurface->SetMaterial(Sec, Surface(Colors[Sec], Rough[Sec]));
		Stats.StreetTriangles += B[Sec].Idx.Num() / 3 / (bDoubleSidedProceduralMeshes ? 2 : 1);
	}
}

void AStrayStreetBuilder::BuildMarkings()
{
	// Solid edge lines (3 m pieces following the profile) and dashed lane dividers (3 m / 6 m gap).
	const FStrayStreetDef& St = Layout.Street;
	UMaterialInterface* Paint = Surface(LanePaint, 0.6f);
	UInstancedStaticMeshComponent* Lines = AddInstanced(CubeMesh, Paint, false);
	const FRotator Rot(0.0, St.AxisYaw(), 0.0);
	auto Piece = [&](double SMid, double V, double Len)
	{
		Lines->AddInstance(FTransform(Rot, Ue(St.ToEN(SMid, V), Layout.RoadZ(SMid, V) + 0.006), FVector(Len, 0.12, 0.02)));
	};
	for (double S = St.SStart; S + 3.0 <= St.SEnd + 1e-3; S += 3.0)
	{
		Piece(S + 1.5, -St.CarriagewayHalfWidth, 3.02);
		Piece(S + 1.5, St.CarriagewayHalfWidth, 3.02);
	}
	for (double S = St.SStart + 1.5; S + 3.0 < St.SEnd; S += 9.0)
	{
		Piece(S + 1.5, -St.LaneDividerOffset, 3.0);
		Piece(S + 1.5, St.LaneDividerOffset, 3.0);
	}
}

void AStrayStreetBuilder::BuildLod2()
{
	const FString Path = Layout.ResolveDataPath(Layout.Lod2MeshRelPath);
	FString Error;
	const TSharedPtr<FStrayObjMesh> Mesh = LoadObjCached(Path, bDoubleSidedProceduralMeshes, Error);
	if (!Mesh.IsValid())
	{
		Stats.Error = Error;
		UE_LOG(LogStray, Error, TEXT("STRAY_DIAG lod2=failed error=%s"), *Error);
		return;
	}
	const TArray<FVector2D> NoUV;
	const TArray<FLinearColor> NoColors;
	const TArray<FProcMeshTangent> NoTangents;
	for (int32 I = 0; I < Mesh->Sections.Num(); ++I)
	{
		const FStrayObjSection& S = Mesh->Sections[I];
		Buildings->CreateMeshSection_LinearColor(I, S.Positions, S.Indices, S.Normals, NoUV, NoColors, NoTangents, /*bCreateCollision*/ true);
		const FLinearColor Color = S.MaterialName.Contains(TEXT("roof")) ? Roof
			: S.MaterialName.Contains(TEXT("ground")) ? GroundDark : Facade;
		Buildings->SetMaterial(I, Surface(Color, 0.85f));
	}
	Stats.bLod2Loaded = true;
	Stats.Lod2Buildings = Mesh->ObjectCount;
	Stats.Lod2Triangles = Mesh->NumTriangles() / (bDoubleSidedProceduralMeshes ? 2 : 1);
}

void AStrayStreetBuilder::BuildLamps()
{
	UMaterialInterface* PoleMat = Surface(Metal, 0.5f);
	const FLinearColor LampColor(1.0f, 0.86f, 0.68f);
	UMaterialInterface* LensMat = Emissive(LampColor, 3000.0f);
	const double H = Layout.LampHeight;
	for (const FStrayLampDef& L : Layout.Lamps)
	{
		const FVector2D A = L.ArmDirEN.GetSafeNormal();
		const double ArmYaw = StrayGeo::EnDirToYaw(A);
		const double G = GroundM(L.PosEN);
		AddMesh(CylinderMesh, Ue(L.PosEN, G + H * 0.5), FRotator::ZeroRotator, FVector(0.16, 0.16, H), PoleMat, true);
		AddBox(Ue(L.PosEN + A * 0.8, G + H - 0.10), FVector(1.6, 0.08, 0.08), ArmYaw, PoleMat, false);
		AddBox(Ue(L.PosEN + A * 1.5, G + H - 0.20), FVector(0.70, 0.30, 0.14), ArmYaw, PoleMat, false);
		AddBox(Ue(L.PosEN + A * 1.5, G + H - 0.275), FVector(0.60, 0.22, 0.02), ArmYaw, LensMat, false);

		USpotLightComponent* Spot = NewGenerated<USpotLightComponent>(TEXT("StreetLamp"));
		Spot->SetMobility(EComponentMobility::Movable);
		Spot->IntensityUnits = ELightUnits::Candelas;
		Spot->Intensity = (float)Layout.LampIntensityCd;
		Spot->bUseTemperature = true;
		Spot->Temperature = (float)Layout.LampTemperatureK;
		Spot->AttenuationRadius = (float)(Layout.LampAttenuationRadius * 100.0);
		Spot->OuterConeAngle = (float)Layout.LampOuterConeDeg;
		Spot->InnerConeAngle = (float)(Layout.LampOuterConeDeg * 0.45);
		Spot->SourceRadius = 15.0f;
		Spot->CastShadows = Layout.bLampShadows;
		Spot->SetRelativeTransform(FTransform(FRotator(-90.0, 0.0, 0.0), Ue(L.PosEN + A * 1.5, G + H - 0.30)));
		Spot->RegisterComponent();
		CountLight(Layout.bLampShadows);
	}
}

void AStrayStreetBuilder::BuildShopfronts()
{
	for (const FStrayFacadeFeature& F : Layout.Shopfronts)
	{
		const double Yaw = StrayGeo::EnDirToYaw(F.NormalEN);
		const double Zc = GroundM(F.PosEN + F.NormalEN * 1.0) + 0.30 + F.Height * 0.5;
		AddBox(Ue(F.PosEN, Zc), FVector(0.16, F.Width + 0.35, F.Height + 0.35), Yaw, Surface(Metal, 0.4f), false);
		AddBox(Ue(F.PosEN + F.NormalEN * 0.06, Zc), FVector(0.04, F.Width, F.Height), Yaw,
			Emissive(F.Color, (float)Layout.ShopfrontEmissiveNits), false);

		URectLightComponent* Rect = NewGenerated<URectLightComponent>(TEXT("Shopfront"));
		Rect->SetMobility(EComponentMobility::Movable);
		Rect->IntensityUnits = ELightUnits::Candelas;
		Rect->Intensity = (float)Layout.ShopfrontIntensityCd;
		Rect->SetLightColor(F.Color);
		Rect->SourceWidth = (float)(F.Width * 100.0);
		Rect->SourceHeight = (float)(F.Height * 100.0);
		Rect->AttenuationRadius = 900.0f;
		Rect->CastShadows = false;
		Rect->SetRelativeTransform(FTransform(FRotator(0.0, Yaw, 0.0), Ue(F.PosEN + F.NormalEN * 0.25, Zc)));
		Rect->RegisterComponent();
		CountLight(false);
	}
}

void AStrayStreetBuilder::BuildWindows()
{
	UInstancedStaticMeshComponent* Warm = AddInstanced(CubeMesh, Emissive(FLinearColor(1.0f, 0.75f, 0.45f), (float)Layout.WindowEmissiveNits), false);
	UInstancedStaticMeshComponent* Cool = AddInstanced(CubeMesh, Emissive(FLinearColor(0.70f, 0.82f, 1.0f), (float)Layout.WindowEmissiveNits), false);
	for (const FStrayFacadeFeature& W : Layout.Windows)
	{
		const FTransform T(FRotator(0.0, StrayGeo::EnDirToYaw(W.NormalEN), 0.0), Ue(W.PosEN + W.NormalEN * 0.03, GroundM(W.PosEN + W.NormalEN * 1.0) + W.Z),
			FVector(0.04, Layout.WindowWidth, Layout.WindowHeight));
		(W.bWarm ? Warm : Cool)->AddInstance(T);
	}
}

// ---------------------------------------------------------------------------------------------
// Landmarks
// ---------------------------------------------------------------------------------------------

void AStrayStreetBuilder::BuildKiosk()
{
	const FStrayFacadeFeature& F = Layout.Kiosk;
	const FVector2D N = F.NormalEN;
	const FVector2D T(N.Y, -N.X); // along the facade
	const double Yaw = StrayGeo::EnDirToYaw(N);
	const double Kerb = GroundM(F.PosEN + N * 1.0);
	auto At = [&](double Along, double Out, double Up) { return Ue(F.PosEN + T * Along + N * Out, Kerb + Up); };

	const FLinearColor Warm(1.0f, 0.84f, 0.62f);
	// Ground-floor shop: frame, lit display window, glass door.
	AddBox(At(0.0, 0.05, 1.55), FVector(0.20, 5.2, 3.1), Yaw, Surface(Metal, 0.35f), false);
	AddBox(At(-0.7, 0.16, 1.35), FVector(0.04, 3.1, 2.2), Yaw, Emissive(Warm, 60.0f), false);
	AddBox(At(1.75, 0.16, 1.15), FVector(0.04, 1.05, 2.25), Yaw, Surface(DarkGlass, 0.05f), false);
	// Sign: lit lightbox with dark lettering in front (readable whether or not the text material is lit).
	AddBox(At(0.0, 0.20, 3.45), FVector(0.25, 4.6, 0.75), Yaw, Emissive(FLinearColor(0.95f, 0.95f, 0.92f), 120.0f), false);
	AddText(TEXT("KIOSK"), At(0.0, 0.36, 3.45), Yaw, 60.0f, FColor(150, 10, 10));
	AddText(TEXT("Getraenke - Snacks - Tabak - 24/7"), At(0.0, 0.36, 2.95), Yaw, 16.0f, FColor(255, 240, 210));
	// Awning and a drinks fridge on the sidewalk.
	AddBox(At(0.0, 0.75, 2.95), FVector(1.3, 5.2, 0.08), Yaw, Surface(FLinearColor(0.25f, 0.03f, 0.03f), 0.6f), false);
	AddBox(At(-2.4, 0.45, 0.95), FVector(0.7, 0.8, 1.9), Yaw, Emissive(FLinearColor(0.85f, 0.92f, 1.0f), 40.0f), true);

	URectLightComponent* Rect = NewGenerated<URectLightComponent>(TEXT("KioskWindow"));
	Rect->SetMobility(EComponentMobility::Movable);
	Rect->IntensityUnits = ELightUnits::Candelas;
	Rect->Intensity = 450.0f;
	Rect->SetLightColor(Warm);
	Rect->SourceWidth = 310.0f;
	Rect->SourceHeight = 220.0f;
	Rect->AttenuationRadius = 1200.0f;
	Rect->CastShadows = true;
	Rect->SetRelativeTransform(FTransform(FRotator(0.0, Yaw, 0.0), At(-0.7, 0.3, 1.35)));
	Rect->RegisterComponent();
	CountLight(true);

	UPointLightComponent* Under = NewGenerated<UPointLightComponent>(TEXT("KioskAwning"));
	Under->SetMobility(EComponentMobility::Movable);
	Under->IntensityUnits = ELightUnits::Candelas;
	Under->Intensity = 120.0f;
	Under->SetLightColor(Warm);
	Under->AttenuationRadius = 600.0f;
	Under->CastShadows = false;
	Under->SetRelativeLocation(At(0.0, 1.0, 2.7));
	Under->RegisterComponent();
	CountLight(false);
}

void AStrayStreetBuilder::BuildClub()
{
	const FStrayFacadeFeature& F = Layout.Club;
	const FVector2D N = F.NormalEN;
	const FVector2D T(N.Y, -N.X);
	const double Yaw = StrayGeo::EnDirToYaw(N);
	const double Kerb = GroundM(F.PosEN + N * 1.0);
	auto At = [&](double Along, double Out, double Up) { return Ue(F.PosEN + T * Along + N * Out, Kerb + Up); };

	const FLinearColor Magenta(1.0f, 0.05f, 0.55f);
	const FLinearColor Ice(0.25f, 0.45f, 1.0f);

	// Black portal with magenta light strips, heavy door.
	AddBox(At(0.0, 0.08, 1.6), FVector(0.25, 4.2, 3.2), Yaw, Surface(FLinearColor(0.01f, 0.01f, 0.01f), 0.3f), false);
	AddBox(At(0.0, 0.22, 1.3), FVector(0.05, 2.0, 2.6), Yaw, Surface(DarkGlass, 0.15f), false);
	for (const double Side : { -1.15, 1.15 })
	{
		AddBox(At(Side, 0.23, 1.4), FVector(0.05, 0.08, 2.8), Yaw, Emissive(Magenta, 400.0f), false);
	}
	// Canopy with the name along its street-facing edge.
	AddBox(At(0.0, 1.1, 3.35), FVector(2.2, 4.6, 0.25), Yaw, Surface(FLinearColor(0.015f, 0.015f, 0.02f), 0.4f), false);
	AddBox(At(0.0, 2.21, 3.35), FVector(0.03, 4.4, 0.2), Yaw, Emissive(Ice, 250.0f), false);
	AddBox(At(0.0, 0.20, 4.15), FVector(0.12, 4.4, 0.9), Yaw, Surface(FLinearColor(0.01f, 0.01f, 0.012f), 0.3f), false);
	AddBox(At(0.0, 0.27, 4.15), FVector(0.02, 4.2, 0.75), Yaw, Emissive(FLinearColor(0.35f, 0.0f, 0.2f), 25.0f), false);
	AddText(TEXT("NACHTFLUG"), At(0.0, 0.32, 4.15), Yaw, 62.0f, FColor(255, 70, 190));
	// Rope line on the sidewalk (posts collide, ropes do not).
	for (int32 I = 0; I < 4; ++I)
	{
		const double Along = -2.6 + I * 1.2;
		AddMesh(CylinderMesh, At(Along, 2.0, 0.5), FRotator::ZeroRotator, FVector(0.08, 0.08, 1.0), Surface(Chrome, 0.15f), true);
		if (I < 3)
		{
			AddBox(At(Along + 0.6, 2.0, 0.85), FVector(0.04, 1.15, 0.04), Yaw, Surface(FLinearColor(0.35f, 0.0f, 0.02f), 0.5f), false);
		}
	}

	URectLightComponent* Wash = NewGenerated<URectLightComponent>(TEXT("ClubWash"));
	Wash->SetMobility(EComponentMobility::Movable);
	Wash->IntensityUnits = ELightUnits::Candelas;
	Wash->Intensity = 260.0f;
	Wash->SetLightColor(Magenta);
	Wash->SourceWidth = 400.0f;
	Wash->SourceHeight = 40.0f;
	Wash->AttenuationRadius = 1400.0f;
	Wash->CastShadows = true;
	Wash->SetRelativeTransform(FTransform(FRotator(-35.0, Yaw, 0.0), At(0.0, 2.0, 3.15)));
	Wash->RegisterComponent();
	CountLight(true);

	USpotLightComponent* Door = NewGenerated<USpotLightComponent>(TEXT("ClubDoor"));
	Door->SetMobility(EComponentMobility::Movable);
	Door->IntensityUnits = ELightUnits::Candelas;
	Door->Intensity = 600.0f;
	Door->SetLightColor(Ice);
	Door->OuterConeAngle = 40.0f;
	Door->InnerConeAngle = 20.0f;
	Door->AttenuationRadius = 800.0f;
	Door->CastShadows = true;
	Door->SetRelativeTransform(FTransform(FRotator(-90.0, 0.0, 0.0), At(0.0, 1.2, 3.18)));
	Door->RegisterComponent();
	CountLight(true);
}

void AStrayStreetBuilder::BuildEndBarriers()
{
	const FStrayStreetDef& St = Layout.Street;
	UInstancedStaticMeshComponent* Red = AddInstanced(CubeMesh, Surface(FLinearColor(0.5f, 0.02f, 0.02f), 0.6f), true);
	UInstancedStaticMeshComponent* White = AddInstanced(CubeMesh, Surface(FLinearColor(0.7f, 0.7f, 0.7f), 0.6f), true);
	for (const double S : { St.SStart + 0.3, St.SEnd - 0.3 })
	{
		int32 I = 0;
		for (double V = St.SidewalkWestOuter + 0.6; V < St.SidewalkEastOuter - 0.5; V += 1.25, ++I)
		{
			const FVector2D BP = St.ToEN(S, V);
			(I % 2 ? White : Red)->AddInstance(FTransform(FRotator(0.0, St.AxisYaw(), 0.0), Ue(BP, GroundM(BP) + 0.55), FVector(0.3, 1.2, 1.1)));
		}
		// Invisible wall: the prototype ends here (the city beyond is not built yet).
		UBoxComponent* Wall = NewGenerated<UBoxComponent>(TEXT("EndWall"));
		Wall->SetBoxExtent(FVector(25.0, (St.SidewalkEastOuter - St.SidewalkWestOuter) * 50.0 + 200.0, 600.0));
		Wall->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
		Wall->SetRelativeTransform(FTransform(FRotator(0.0, St.AxisYaw(), 0.0),
			Ue(St.ToEN(S, (St.SidewalkWestOuter + St.SidewalkEastOuter) * 0.5), Layout.ProfileAt(S).RoadCentre + 5.0)));
		Wall->RegisterComponent();
	}
}

// ---------------------------------------------------------------------------------------------
// Lighting
// ---------------------------------------------------------------------------------------------

void AStrayStreetBuilder::SetDayMode(bool bDay)
{
	bDayMode = bDay;
	ApplyLighting();
	for (USceneComponent* C : Generated)
	{
		if (USpotLightComponent* Spot = Cast<USpotLightComponent>(C))
		{
			Spot->SetVisibility(!bDay);
		}
	}
	UE_LOG(LogStray, Log, TEXT("STRAY_DIAG lighting=%s"), bDay ? TEXT("day") : TEXT("night"));
}

void AStrayStreetBuilder::ApplyLighting()
{
	const FStrayLightingPreset& P = bDayMode ? Layout.Day : Layout.Night;
	KeyLight->SetIntensity((float)P.KeyLux);
	KeyLight->SetLightColor(bDayMode ? FLinearColor(1.0f, 0.97f, 0.92f) : FLinearColor(0.62f, 0.72f, 1.0f));
	KeyLight->SetWorldRotation(FRotator(P.KeyPitchDeg, P.KeyYawDeg, 0.0));

	SkyLight->SetIntensity((float)P.SkyLightIntensity);

	HeightFog->SetFogDensity((float)P.FogDensity);
	HeightFog->SetFogInscatteringColor(P.FogInscatter);

	FPostProcessSettings& S = PostProcess->Settings;
	S.bOverride_AutoExposureMethod = true;
	S.AutoExposureMethod = EAutoExposureMethod::AEM_Histogram;
	S.bOverride_AutoExposureMinBrightness = true;
	S.AutoExposureMinBrightness = (float)P.ExposureMinEV100;
	S.bOverride_AutoExposureMaxBrightness = true;
	S.AutoExposureMaxBrightness = (float)P.ExposureMaxEV100;
	S.bOverride_AutoExposureBias = true;
	S.AutoExposureBias = 0.0f;
	S.bOverride_BloomIntensity = true;
	S.BloomIntensity = bDayMode ? 0.4f : 0.8f;
	if (GetWorld() && SkyLight->IsRegistered())
	{
		SkyLight->RecaptureSky();
	}
}
