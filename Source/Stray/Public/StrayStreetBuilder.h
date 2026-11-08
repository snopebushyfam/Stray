// STRAY - Prototype 001 "The Street": builds the Hohenzollernring segment from data.
// Data: Content/Stray/Data/P001_Layout.json + LoD2_P001_Hohenzollernring.obj (tools/geodata/build_p001.py).
// Design: docs/STRAY_GDD.md (Prototype 001), docs/TECHNICAL_PLAN.md.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "StrayStreetLayout.h"
#include "StrayStreetBuilder.generated.h"

class UDirectionalLightComponent;
class UExponentialHeightFogComponent;
class UInstancedStaticMeshComponent;
class UMaterialInstanceDynamic;
class UMaterialInterface;
class UPostProcessComponent;
class UProceduralMeshComponent;
class USkyAtmosphereComponent;
class USkyLightComponent;
class UStaticMesh;
class UStaticMeshComponent;

/** Result of the last build; logged as a STRAY_DIAG line and read by tests / auto-shots. */
USTRUCT(BlueprintType)
struct STRAY_API FStrayBuildStats
{
	GENERATED_BODY()

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) bool bLayoutLoaded = false;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) bool bLod2Loaded = false;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 Lod2Buildings = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 Lod2Triangles = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) bool bTerrainLoaded = false;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 TerrainTriangles = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 StreetTriangles = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 Lights = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 ShadowCastingLights = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) int32 Components = 0;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) bool bUsingProjectMaterials = false;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) FString Error;
};

/**
 * Places the whole street at runtime and in the editor (OnConstruction):
 * real LoD2 buildings with collision, road / sidewalks / kerbs / markings,
 * street lamps, shopfronts, lit windows, KIOSK, NACHTFLUG entrance, end barriers
 * and a fully dynamic night lighting rig (no baked lighting anywhere).
 *
 * Generated components are transient: they are rebuilt on construction and on
 * BeginPlay, never saved into the map, so the JSON stays the single source of truth.
 */
UCLASS(config = Game)
class STRAY_API AStrayStreetBuilder : public AActor
{
	GENERATED_BODY()

public:
	AStrayStreetBuilder();

	/** Rebuilds everything from the layout file. */
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "Stray|Street")
	void Rebuild();

	/** Switches between the night preset (default) and the day preset (debug / lighting check). */
	UFUNCTION(BlueprintCallable, Category = "Stray|Street")
	void SetDayMode(bool bDay);

	UFUNCTION(BlueprintPure, Category = "Stray|Street")
	bool IsDayMode() const { return bDayMode; }

	/** Spawn transform for a capsule of the given half height (cm). */
	FTransform GetSpawnTransform(double CapsuleHalfHeightCm) const;

	const FStrayP001Layout& GetLayout() const { return Layout; }
	const FStrayBuildStats& GetStats() const { return Stats; }

	/** Layout file, relative to the project Content directory. */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Street")
	FString LayoutFile = TEXT("Stray/Data/P001_Layout.json");

	/** Material with a "Color" vector and "Roughness" scalar parameter (created by Content/Python/stray_setup_p001.py). */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Street")
	FSoftObjectPath SurfaceMaterialPath = FSoftObjectPath(TEXT("/Game/Stray/Materials/M_Stray_Surface.M_Stray_Surface"));

	/** Unlit material with "Color" vector and "Intensity" scalar parameter (nits). */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Street")
	FSoftObjectPath EmissiveMaterialPath = FSoftObjectPath(TEXT("/Game/Stray/Materials/M_Stray_Emissive.M_Stray_Emissive"));

	/**
	 * Adds back faces to the procedural meshes (buildings, terrain, street surface).
	 * Safety net while the triangle winding has not been confirmed in the editor; switch
	 * off in Config/DefaultGame.ini once confirmed (halves the triangle count).
	 */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Street")
	bool bDoubleSidedProceduralMeshes = true;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Stray|Street")
	FStrayBuildStats Stats;

protected:
	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Stray|Lighting") TObjectPtr<USceneComponent> Root;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Lighting") TObjectPtr<UDirectionalLightComponent> KeyLight;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Lighting") TObjectPtr<USkyLightComponent> SkyLight;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Lighting") TObjectPtr<USkyAtmosphereComponent> SkyAtmosphere;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Lighting") TObjectPtr<UExponentialHeightFogComponent> HeightFog;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Lighting") TObjectPtr<UPostProcessComponent> PostProcess;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Street") TObjectPtr<UProceduralMeshComponent> Buildings;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Street") TObjectPtr<UProceduralMeshComponent> Terrain;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Street") TObjectPtr<UProceduralMeshComponent> StreetSurface;

private:
	void ClearGenerated();
	void BuildGround();
	void BuildTerrain();
	void BuildStreetSurface();
	void BuildMarkings();
	void BuildLod2();
	void BuildLamps();
	void BuildShopfronts();
	void BuildWindows();
	void BuildKiosk();
	void BuildClub();
	void BuildEndBarriers();
	void ApplyLighting();

	UMaterialInterface* Surface(const FLinearColor& Color, float Roughness = 0.8f);
	UMaterialInterface* Emissive(const FLinearColor& Color, float Nits);

	UStaticMeshComponent* AddMesh(UStaticMesh* Mesh, const FVector& LocationCm, const FRotator& Rotation,
		const FVector& Scale, UMaterialInterface* Material, bool bCollision);
	/** Box with size in metres; Location = box centre in cm. */
	UStaticMeshComponent* AddBox(const FVector& CenterCm, const FVector& SizeM, double Yaw, UMaterialInterface* Material, bool bCollision);
	/** Box spanning street-frame ranges (metres), between ZBottom and ZTop (metres). */
	/** Walkable ground height (metres, actor-relative) at a local EN point: profile-aware. */
	double GroundM(const FVector2D& PosEN) const { return Layout.GroundZAt(PosEN); }
	UInstancedStaticMeshComponent* AddInstanced(UStaticMesh* Mesh, UMaterialInterface* Material, bool bCollision);
	void AddText(const FString& Text, const FVector& LocationCm, double Yaw, float WorldSizeCm, const FColor& Color);
	void CountLight(bool bShadows);

	template <class T>
	T* NewGenerated(const TCHAR* BaseName);

	UPROPERTY(Transient) TArray<TObjectPtr<USceneComponent>> Generated;
	UPROPERTY(Transient) TMap<FString, TObjectPtr<UMaterialInstanceDynamic>> MaterialCache;
	UPROPERTY(Transient) TObjectPtr<UMaterialInterface> SurfaceBase;
	UPROPERTY(Transient) TObjectPtr<UMaterialInterface> EmissiveBase;
	UPROPERTY() TObjectPtr<UStaticMesh> CubeMesh;
	UPROPERTY() TObjectPtr<UStaticMesh> CylinderMesh;
	UPROPERTY() TObjectPtr<UStaticMesh> SphereMesh;

	FStrayP001Layout Layout;
	bool bDayMode = false;
	bool bEmissiveIsUnlit = false;
};
