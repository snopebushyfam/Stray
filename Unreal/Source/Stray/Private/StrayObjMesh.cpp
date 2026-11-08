// STRAY - minimal OBJ reader. See StrayObjMesh.h.
#include "StrayObjMesh.h"

#include "StrayStreetLayout.h"

int32 FStrayObjMesh::NumTriangles() const
{
	int32 N = 0;
	for (const FStrayObjSection& S : Sections)
	{
		N += S.Indices.Num() / 3;
	}
	return N;
}

bool FStrayObjMesh::ParseObj(const FString& Text, bool bDoubleSided, FStrayObjMesh& Out, FString& OutError)
{
	Out = FStrayObjMesh();
	TArray<FVector> LocalEN;       // OBJ vertices, metres
	TMap<FString, int32> SectionByMaterial;
	int32 Current = INDEX_NONE;

	TArray<FString> Lines;
	Text.ParseIntoArrayLines(Lines, /*CullEmpty*/ true);
	TArray<FString> Tok;
	for (int32 LineNo = 0; LineNo < Lines.Num(); ++LineNo)
	{
		const FString& Line = Lines[LineNo];
		if (Line.IsEmpty() || Line[0] == TEXT('#'))
		{
			continue;
		}
		Tok.Reset();
		Line.ParseIntoArrayWS(Tok);
		if (Tok.Num() == 0)
		{
			continue;
		}
		if (Tok[0] == TEXT("v") && Tok.Num() >= 4)
		{
			LocalEN.Emplace(FCString::Atod(*Tok[1]), FCString::Atod(*Tok[2]), FCString::Atod(*Tok[3]));
		}
		else if (Tok[0] == TEXT("o"))
		{
			++Out.ObjectCount;
		}
		else if (Tok[0] == TEXT("usemtl") && Tok.Num() >= 2)
		{
			if (const int32* Found = SectionByMaterial.Find(Tok[1]))
			{
				Current = *Found;
			}
			else
			{
				Current = Out.Sections.AddDefaulted();
				Out.Sections[Current].MaterialName = Tok[1];
				SectionByMaterial.Add(Tok[1], Current);
			}
		}
		else if (Tok[0] == TEXT("f"))
		{
			if (Tok.Num() != 4)
			{
				OutError = FString::Printf(TEXT("line %d: only triangles are supported"), LineNo + 1);
				return false;
			}
			if (Current == INDEX_NONE)
			{
				Current = Out.Sections.AddDefaulted();
				Out.Sections[Current].MaterialName = TEXT("default");
				SectionByMaterial.Add(TEXT("default"), Current);
			}
			int32 Idx[3];
			for (int32 K = 0; K < 3; ++K)
			{
				FString IndexText = Tok[K + 1];
				int32 Slash = INDEX_NONE;
				if (IndexText.FindChar(TEXT('/'), Slash))
				{
					IndexText.LeftInline(Slash);
				}
				Idx[K] = FCString::Atoi(*IndexText) - 1;
				if (!LocalEN.IsValidIndex(Idx[K]))
				{
					OutError = FString::Printf(TEXT("line %d: vertex index out of range"), LineNo + 1);
					return false;
				}
			}
			const FVector& A = LocalEN[Idx[0]];
			const FVector& B = LocalEN[Idx[1]];
			const FVector& C = LocalEN[Idx[2]];
			// Right-handed EN normal (CCW = outward), mirrored into Unreal space (Y flip).
			FVector N = FVector::CrossProduct(B - A, C - A);
			if (N.SizeSquared() < 1e-12)
			{
				continue; // degenerate triangle
			}
			N.Normalize();
			const FVector NUe(N.X, -N.Y, N.Z);

			FStrayObjSection& S = Out.Sections[Current];
			const FVector P[3] = {
				StrayGeo::EnuToUnreal(A.X, A.Y, A.Z),
				StrayGeo::EnuToUnreal(B.X, B.Y, B.Z),
				StrayGeo::EnuToUnreal(C.X, C.Y, C.Z) };
			const int32 Base = S.Positions.Num();
			for (int32 K = 0; K < 3; ++K)
			{
				S.Positions.Add(P[K]);
				S.Normals.Add(NUe);
				Out.Bounds += P[K];
			}
			S.Indices.Append({ Base, Base + 1, Base + 2 });
			if (bDoubleSided)
			{
				const int32 Back = S.Positions.Num();
				for (int32 K = 0; K < 3; ++K)
				{
					S.Positions.Add(P[K]);
					S.Normals.Add(-NUe);
				}
				S.Indices.Append({ Back, Back + 2, Back + 1 });
			}
		}
	}
	if (Out.NumTriangles() == 0)
	{
		OutError = TEXT("OBJ contains no triangles");
		return false;
	}
	return true;
}
