// STRAY - Prototype 001 street layout: plain data + pure math, no UObjects.
// Source data: Content/Stray/Data/P001_Layout.json, produced by tools/geodata/build_p001.py
// from Geobasis NRW LoD2 + OpenStreetMap. Design ref: docs/TECHNICAL_PLAN.md (P001).
#pragma once

#include "CoreMinimal.h"

/**
 * Coordinate conventions.
 *  - Local "EN" frame (data files): metres, X = East, Y = North, Z = Up, right-handed.
 *    Origin = layout.georef.local_origin_utm (EPSG:25832 / DHHN2016).
 *  - Unreal: centimetres, left-handed, Z up. We map East -> +X and North -> -Y,
 *    so the level is not mirrored when seen from above.
 */
namespace StrayGeo
{
	/** Converts a local EN(U) position in metres to Unreal world space in cm. */
	inline FVector EnuToUnreal(double East, double North, double Up)
	{
		return FVector(East * 100.0, -North * 100.0, Up * 100.0);
	}

	/** Converts a horizontal EN direction to a normalised Unreal direction (Z = 0). */
	inline FVector EnDirToUnreal(const FVector2D& DirEN)
	{
		return FVector(DirEN.X, -DirEN.Y, 0.0).GetSafeNormal();
	}

	/** Unreal yaw (degrees) of a horizontal EN direction. */
	inline double EnDirToYaw(const FVector2D& DirEN)
	{
		return FMath::RadiansToDegrees(FMath::Atan2(-DirEN.Y, DirEN.X));
	}
}

/** Straight street segment described in its own frame (s along the street, v across, +v = east side). */
struct STRAY_API FStrayStreetDef
{
	FVector2D OriginEN = FVector2D::ZeroVector;
	double BearingDeg = 0.0;          // clockwise from north
	double SStart = 0.0;
	double SEnd = 0.0;
	double MedianHalfWidth = 0.6;
	double LaneDividerOffset = 3.7;
	double CarriagewayHalfWidth = 7.0;
	double KerbHalfWidth = 9.0;
	double KerbHeight = 0.15;
	double SidewalkWestOuter = -19.0; // negative = west of the axis
	double SidewalkEastOuter = 22.0;

	/** Unit vector along the street (towards Friesenplatz) in EN. */
	FVector2D AxisEN() const;
	/** Unit vector across the street, pointing to the east side, in EN. */
	FVector2D RightEN() const;
	/** Street-frame (s, v) to local EN metres. */
	FVector2D ToEN(double S, double V) const;
	/** Unreal yaw that aligns a mesh's +X axis with the street axis. */
	double AxisYaw() const { return StrayGeo::EnDirToYaw(AxisEN()); }
	double Length() const { return SEnd - SStart; }
};

/** A point feature on a facade (kiosk, club, shopfront, window). Normal points from the facade to the street. */
struct STRAY_API FStrayFacadeFeature
{
	FString Label;
	FVector2D PosEN = FVector2D::ZeroVector;
	FVector2D NormalEN = FVector2D(1, 0);
	double Z = 0.0;                   // metres above street level (windows)
	double Width = 0.0;
	double Height = 0.0;
	FLinearColor Color = FLinearColor::White;
	bool bWarm = true;
};

struct STRAY_API FStrayLampDef
{
	FVector2D PosEN = FVector2D::ZeroVector;
	FVector2D ArmDirEN = FVector2D(1, 0);
};

struct STRAY_API FStrayViewpoint
{
	FString Name;
	FVector EyeEN = FVector::ZeroVector;    // metres, Z = height above street
	FVector TargetEN = FVector::ZeroVector;
};

struct STRAY_API FStrayLightingPreset
{
	double KeyLux = 0.25;             // moon (night) or sun (day) illuminance
	double KeyPitchDeg = -28.0;
	double KeyYawDeg = 200.0;
	double SkyLightIntensity = 1.0;
	double ExposureMinEV100 = -1.5;
	double ExposureMaxEV100 = 3.0;
	double FogDensity = 0.01;
	FLinearColor FogInscatter = FLinearColor(0.08f, 0.06f, 0.05f);
};

/** Everything Prototype 001 needs to build the street. All values come from the JSON file. */
struct STRAY_API FStrayP001Layout
{
	FString Lod2MeshRelPath;          // relative to the project Content dir
	FVector UtmOrigin = FVector::ZeroVector;
	FStrayStreetDef Street;
	FVector2D GroundMinEN = FVector2D::ZeroVector;
	FVector2D GroundMaxEN = FVector2D::ZeroVector;
	double GroundZ = -0.03;

	double LampHeight = 8.0;
	double LampIntensityCd = 1800.0;
	double LampTemperatureK = 3400.0;
	double LampAttenuationRadius = 32.0;
	double LampOuterConeDeg = 62.0;
	bool bLampShadows = true;
	TArray<FStrayLampDef> Lamps;

	double ShopfrontIntensityCd = 220.0;
	double ShopfrontEmissiveNits = 35.0;
	TArray<FStrayFacadeFeature> Shopfronts;

	double WindowEmissiveNits = 6.0;
	double WindowWidth = 1.2;
	double WindowHeight = 1.5;
	TArray<FStrayFacadeFeature> Windows;

	FStrayFacadeFeature Kiosk;
	FStrayFacadeFeature Club;

	FVector2D SpawnEN = FVector2D::ZeroVector;
	FVector2D SpawnDirEN = FVector2D(0, 1);

	TArray<FStrayViewpoint> Viewpoints;
	FStrayLightingPreset Night;
	FStrayLightingPreset Day;

	/** Parses the layout JSON. Returns false and fills OutError when a required field is missing. */
	static bool FromJsonString(const FString& Json, FStrayP001Layout& Out, FString& OutError);

	/** Loads Content/Stray/Data/P001_Layout.json (or another path) from disk. */
	static bool LoadFromFile(const FString& AbsolutePath, FStrayP001Layout& Out, FString& OutError);

	/** Default location of the layout file. */
	static FString DefaultLayoutPath();

	/**
	 * Player spawn transform in Unreal space. The capsule bottom is placed
	 * SpawnClearanceCm above the sidewalk top so the pawn never starts inside geometry.
	 */
	FTransform ComputeSpawnTransform(double CapsuleHalfHeightCm, double SpawnClearanceCm = 5.0) const;

	/** True when a local EN point lies on a sidewalk of the street segment. */
	bool IsOnSidewalk(const FVector2D& PosEN) const;
};
