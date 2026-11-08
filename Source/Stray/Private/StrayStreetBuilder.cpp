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
		TEXT("STRAY_DIAG build=ok lod2=%d buildings=%d triangles=%d lights=%d shadow_lights=%d components=%d project_materials=%d street_len_m=%.1f"),
		Stats.bLod2Loaded ? 1 : 0, Stats.Lod2Buildings, Stats.Lod2Triangles, Stats.Lights, Stats.ShadowCastingLights,
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

UStaticMeshComponent* AStrayStreetBuilder::AddStreetSlab(double S0, double S1, double V0, double V1, double ZBottom, double ZTop,
	UMaterialInterface* Material, bool bCollision)
{
	const FStrayStreetDef& St = Layout.Street;
	const FVector2D C = St.ToEN((S0 + S1) * 0.5, (V0 + V1) * 0.5);
	return AddBox(Ue(C, (ZBottom + ZTop) * 0.5), FVector(S1 - S0, FMath::Abs(V1 - V0), ZTop - ZBottom), St.AxisYaw(), Material, bCollision);
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
	const FStrayStreetDef& St = Layout.Street;
	const double S0 = St.SStart, S1 = St.SEnd, K = St.KerbHalfWidth;

	// Large ground plate under the whole LoD2 cut-out: no void between buildings or behind them.
	const FVector2D Mid = (Layout.GroundMinEN + Layout.GroundMaxEN) * 0.5;
	const FVector2D Size = Layout.GroundMaxEN - Layout.GroundMinEN;
	AddBox(Ue(Mid, Layout.GroundZ - 0.25), FVector(Size.X, Size.Y, 0.5), 0.0, Surface(GroundDark, 0.95f), true);

	// Road surface top at Z = 0, sidewalks at kerb height.
	AddStreetSlab(S0, S1, -K, K, -0.30, 0.0, Surface(Asphalt, 0.9f), true);
	AddStreetSlab(S0, S1, -St.MedianHalfWidth, St.MedianHalfWidth, 0.0, 0.12, Surface(MedianStone, 0.85f), true);
	AddStreetSlab(S0, S1, St.SidewalkWestOuter, -K, -0.30, St.KerbHeight, Surface(Paving, 0.8f), true);
	AddStreetSlab(S0, S1, K, St.SidewalkEastOuter, -0.30, St.KerbHeight, Surface(Paving, 0.8f), true);
	AddStreetSlab(S0, S1, -K - 0.18, -K, -0.30, St.KerbHeight + 0.005, Surface(KerbStone, 0.7f), true);
	AddStreetSlab(S0, S1, K, K + 0.18, -0.30, St.KerbHeight + 0.005, Surface(KerbStone, 0.7f), true);

	// Markings: solid edge lines and dashed lane dividers (3 m line / 6 m gap).
	UMaterialInterface* Paint = Surface(LanePaint, 0.6f);
	for (const double Side : { -1.0, 1.0 })
	{
		const double Edge = Side * St.CarriagewayHalfWidth;
		AddStreetSlab(S0, S1, Edge - 0.06, Edge + 0.06, 0.0, 0.006, Paint, false);
	}
	UInstancedStaticMeshComponent* Dashes = AddInstanced(CubeMesh, Paint, false);
	for (double S = S0 + 1.5; S + 3.0 < S1; S += 9.0)
	{
		for (const double Side : { -1.0, 1.0 })
		{
			const FVector2D P = St.ToEN(S + 1.5, Side * St.LaneDividerOffset);
			Dashes->AddInstance(FTransform(FRotator(0.0, St.AxisYaw(), 0.0), Ue(P, 0.003), FVector(3.0, 0.12, 0.006)));
		}
	}
}

void AStrayStreetBuilder::BuildLod2()
{
	const FString Path = FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir() / Layout.Lod2MeshRelPath);
	FString Error;
	const TSharedPtr<FStrayObjMesh> Mesh = LoadObjCached(Path, bDoubleSidedBuildings, Error);
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
	Stats.Lod2Triangles = Mesh->NumTriangles() / (bDoubleSidedBuildings ? 2 : 1);
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
		AddMesh(CylinderMesh, Ue(L.PosEN, H * 0.5), FRotator::ZeroRotator, FVector(0.16, 0.16, H), PoleMat, true);
		AddBox(Ue(L.PosEN + A * 0.8, H - 0.10), FVector(1.6, 0.08, 0.08), ArmYaw, PoleMat, false);
		AddBox(Ue(L.PosEN + A * 1.5, H - 0.20), FVector(0.70, 0.30, 0.14), ArmYaw, PoleMat, false);
		AddBox(Ue(L.PosEN + A * 1.5, H - 0.275), FVector(0.60, 0.22, 0.02), ArmYaw, LensMat, false);

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
		Spot->SetRelativeTransform(FTransform(FRotator(-90.0, 0.0, 0.0), Ue(L.PosEN + A * 1.5, H - 0.30)));
		Spot->RegisterComponent();
		CountLight(Layout.bLampShadows);
	}
}

void AStrayStreetBuilder::BuildShopfronts()
{
	const double Kerb = Layout.Street.KerbHeight;
	for (const FStrayFacadeFeature& F : Layout.Shopfronts)
	{
		const double Yaw = StrayGeo::EnDirToYaw(F.NormalEN);
		const double Zc = Kerb + 0.30 + F.Height * 0.5;
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
		const FTransform T(FRotator(0.0, StrayGeo::EnDirToYaw(W.NormalEN), 0.0), Ue(W.PosEN + W.NormalEN * 0.03, W.Z),
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
	const double Kerb = Layout.Street.KerbHeight;
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
	const double Kerb = Layout.Street.KerbHeight;
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
			(I % 2 ? White : Red)->AddInstance(FTransform(FRotator(0.0, St.AxisYaw(), 0.0), Ue(St.ToEN(S, V), 0.55), FVector(0.3, 1.2, 1.1)));
		}
		// Invisible wall: the prototype ends here (the city beyond is not built yet).
		UBoxComponent* Wall = NewGenerated<UBoxComponent>(TEXT("EndWall"));
		Wall->SetBoxExtent(FVector(25.0, (St.SidewalkEastOuter - St.SidewalkWestOuter) * 50.0 + 200.0, 600.0));
		Wall->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
		Wall->SetRelativeTransform(FTransform(FRotator(0.0, St.AxisYaw(), 0.0),
			Ue(St.ToEN(S, (St.SidewalkWestOuter + St.SidewalkEastOuter) * 0.5), 5.0)));
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
