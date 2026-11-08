// STRAY - minimal Wavefront OBJ reader for the LoD2 building cut-out (triangles only).
// The OBJ is written by tools/geodata/citygml_extract.py: local EN metres, CCW = outward.
#pragma once

#include "CoreMinimal.h"

/** One material slot of the mesh, already converted to Unreal space (cm), flat-shaded. */
struct STRAY_API FStrayObjSection
{
	FString MaterialName;
	TArray<FVector> Positions;   // 3 per triangle, Unreal cm
	TArray<FVector> Normals;     // per vertex (flat)
	TArray<int32> Indices;       // Unreal front-face winding
};

struct STRAY_API FStrayObjMesh
{
	TArray<FStrayObjSection> Sections;
	int32 ObjectCount = 0;
	FBox Bounds = FBox(ForceInit);

	int32 NumTriangles() const;

	/**
	 * Parses OBJ text. Positions are mapped EN(U) metres -> Unreal cm (East -> +X, North -> -Y).
	 * The handedness flip reverses the apparent winding, which is exactly what Unreal's
	 * front-face convention needs, so index order is kept and normals are mirrored.
	 * With bDoubleSided, a back-facing copy of every triangle is appended (safety net
	 * for data with inconsistent ring orientation).
	 */
	static bool ParseObj(const FString& Text, bool bDoubleSided, FStrayObjMesh& Out, FString& OutError);
};
