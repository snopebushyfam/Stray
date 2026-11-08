// STRAY - Prototype 001 street layout parsing and math. See StrayStreetLayout.h.
#include "StrayStreetLayout.h"

#include "Dom/JsonObject.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

FVector2D FStrayStreetDef::AxisEN() const
{
	const double B = FMath::DegreesToRadians(BearingDeg);
	return FVector2D(FMath::Sin(B), FMath::Cos(B));
}

FVector2D FStrayStreetDef::RightEN() const
{
	const FVector2D U = AxisEN();
	return FVector2D(U.Y, -U.X);
}

FVector2D FStrayStreetDef::ToEN(double S, double V) const
{
	return OriginEN + AxisEN() * S + RightEN() * V;
}

namespace
{
	/** Returns a sub-object or an invalid pointer (no log spam for optional sections). */
	TSharedPtr<FJsonObject> Field(const TSharedPtr<FJsonObject>& Obj, const FString& Name)
	{
		const TSharedPtr<FJsonObject>* Out = nullptr;
		if (Obj.IsValid() && Obj->TryGetObjectField(Name, Out) && Out)
		{
			return *Out;
		}
		return nullptr;
	}

	bool ReadVec2(const TSharedPtr<FJsonObject>& Obj, const FString& Key, FVector2D& Out)
	{
		const TArray<TSharedPtr<FJsonValue>>* Arr = nullptr;
		if (!Obj.IsValid() || !Obj->TryGetArrayField(Key, Arr) || Arr->Num() < 2)
		{
			return false;
		}
		Out = FVector2D((*Arr)[0]->AsNumber(), (*Arr)[1]->AsNumber());
		return true;
	}

	bool ReadColor(const TSharedPtr<FJsonObject>& Obj, const FString& Key, FLinearColor& Out)
	{
		const TArray<TSharedPtr<FJsonValue>>* Arr = nullptr;
		if (!Obj.IsValid() || !Obj->TryGetArrayField(Key, Arr) || Arr->Num() < 3)
		{
			return false;
		}
		Out = FLinearColor((float)(*Arr)[0]->AsNumber(), (float)(*Arr)[1]->AsNumber(), (float)(*Arr)[2]->AsNumber());
		return true;
	}

	double Num(const TSharedPtr<FJsonObject>& Obj, const FString& Key, double Default)
	{
		double V = Default;
		if (Obj.IsValid())
		{
			Obj->TryGetNumberField(Key, V);
		}
		return V;
	}

	bool ReadFeature(const TSharedPtr<FJsonObject>& Obj, FStrayFacadeFeature& Out)
	{
		if (!Obj.IsValid() || !ReadVec2(Obj, TEXT("en"), Out.PosEN) || !ReadVec2(Obj, TEXT("normal_en"), Out.NormalEN))
		{
			return false;
		}
		Obj->TryGetStringField(TEXT("label"), Out.Label);
		Out.Z = Num(Obj, TEXT("z"), 0.0);
		Out.Width = Num(Obj, TEXT("width"), 0.0);
		Out.Height = Num(Obj, TEXT("height"), 0.0);
		ReadColor(Obj, TEXT("color"), Out.Color);
		Obj->TryGetBoolField(TEXT("warm"), Out.bWarm);
		Out.NormalEN = Out.NormalEN.GetSafeNormal();
		return true;
	}

	void ReadPreset(const TSharedPtr<FJsonObject>& Obj, bool bDay, FStrayLightingPreset& Out)
	{
		if (!Obj.IsValid())
		{
			return;
		}
		Out.KeyLux = Num(Obj, bDay ? TEXT("sun_lux") : TEXT("moon_lux"), Out.KeyLux);
		Out.KeyPitchDeg = Num(Obj, bDay ? TEXT("sun_pitch_deg") : TEXT("moon_pitch_deg"), Out.KeyPitchDeg);
		Out.KeyYawDeg = Num(Obj, bDay ? TEXT("sun_yaw_deg") : TEXT("moon_yaw_deg"), Out.KeyYawDeg);
		Out.SkyLightIntensity = Num(Obj, TEXT("skylight_intensity"), Out.SkyLightIntensity);
		Out.ExposureMinEV100 = Num(Obj, TEXT("exposure_min_ev100"), Out.ExposureMinEV100);
		Out.ExposureMaxEV100 = Num(Obj, TEXT("exposure_max_ev100"), Out.ExposureMaxEV100);
		Out.FogDensity = Num(Obj, TEXT("fog_density"), Out.FogDensity);
		ReadColor(Obj, TEXT("fog_inscatter"), Out.FogInscatter);
	}
}

bool FStrayP001Layout::FromJsonString(const FString& Json, FStrayP001Layout& Out, FString& OutError)
{
	TSharedPtr<FJsonObject> Root;
	const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Json);
	if (!FJsonSerializer::Deserialize(Reader, Root) || !Root.IsValid())
	{
		OutError = TEXT("layout is not valid JSON");
		return false;
	}

	FString Schema;
	if (!Root->TryGetStringField(TEXT("schema"), Schema) || Schema != TEXT("stray.p001.layout/2"))
	{
		OutError = FString::Printf(TEXT("unexpected schema '%s'"), *Schema);
		return false;
	}
	if (!Root->TryGetStringField(TEXT("lod2_mesh"), Out.Lod2MeshRelPath))
	{
		OutError = TEXT("missing lod2_mesh");
		return false;
	}

	Root->TryGetStringField(TEXT("terrain_mesh"), Out.TerrainMeshRelPath);
	if (const TSharedPtr<FJsonObject> Prof = Field(Root, TEXT("profile")))
	{
		const TArray<TSharedPtr<FJsonValue>>* Rows = nullptr;
		if (Prof->TryGetArrayField(TEXT("samples"), Rows))
		{
			for (const TSharedPtr<FJsonValue>& R : *Rows)
			{
				const TArray<TSharedPtr<FJsonValue>>& C = R->AsArray();
				if (C.Num() >= 6)
				{
					FStrayProfileSample P;
					P.S = C[0]->AsNumber();
					P.RoadCentre = C[1]->AsNumber();
					P.RoadEdgeWest = C[2]->AsNumber();
					P.RoadEdgeEast = C[3]->AsNumber();
					P.SidewalkWest = C[4]->AsNumber();
					P.SidewalkEast = C[5]->AsNumber();
					P.FacadeWest = C.Num() >= 8 ? C[6]->AsNumber() : P.SidewalkWest;
					P.FacadeEast = C.Num() >= 8 ? C[7]->AsNumber() : P.SidewalkEast;
					Out.Profile.Add(P);
				}
			}
			Out.Profile.Sort([](const FStrayProfileSample& A, const FStrayProfileSample& B) { return A.S < B.S; });
		}
		const TArray<TSharedPtr<FJsonValue>>* FacadeV = nullptr;
		if (Prof->TryGetArrayField(TEXT("facade_v"), FacadeV) && FacadeV->Num() == 2)
		{
			Out.ProfileFacadeVWest = (*FacadeV)[0]->AsNumber();
			Out.ProfileFacadeVEast = (*FacadeV)[1]->AsNumber();
		}
	}

	const TSharedPtr<FJsonObject> Geo = Field(Root, TEXT("georef"));
	const TArray<TSharedPtr<FJsonValue>>* Utm = nullptr;
	if (Geo.IsValid() && Geo->TryGetArrayField(TEXT("local_origin_utm"), Utm) && Utm->Num() == 3)
	{
		Out.UtmOrigin = FVector((*Utm)[0]->AsNumber(), (*Utm)[1]->AsNumber(), (*Utm)[2]->AsNumber());
	}

	const TSharedPtr<FJsonObject> St = Field(Root, TEXT("street"));
	if (!ReadVec2(St, TEXT("origin_en"), Out.Street.OriginEN))
	{
		OutError = TEXT("missing street.origin_en");
		return false;
	}
	FStrayStreetDef& S = Out.Street;
	S.BearingDeg = Num(St, TEXT("bearing_deg"), S.BearingDeg);
	S.SStart = Num(St, TEXT("s_start"), S.SStart);
	S.SEnd = Num(St, TEXT("s_end"), S.SEnd);
	S.MedianHalfWidth = Num(St, TEXT("median_half_width"), S.MedianHalfWidth);
	S.LaneDividerOffset = Num(St, TEXT("lane_divider_offset"), S.LaneDividerOffset);
	S.CarriagewayHalfWidth = Num(St, TEXT("carriageway_half_width"), S.CarriagewayHalfWidth);
	S.KerbHalfWidth = Num(St, TEXT("kerb_half_width"), S.KerbHalfWidth);
	S.KerbHeight = Num(St, TEXT("kerb_height"), S.KerbHeight);
	S.SidewalkWestOuter = Num(St, TEXT("sidewalk_west_outer"), S.SidewalkWestOuter);
	S.SidewalkEastOuter = Num(St, TEXT("sidewalk_east_outer"), S.SidewalkEastOuter);
	if (S.Length() <= 1.0 || S.KerbHalfWidth <= S.CarriagewayHalfWidth - 0.01)
	{
		OutError = TEXT("street segment is degenerate");
		return false;
	}

	const TSharedPtr<FJsonObject> Ground = Field(Root, TEXT("ground_plane"));
	ReadVec2(Ground, TEXT("min_en"), Out.GroundMinEN);
	ReadVec2(Ground, TEXT("max_en"), Out.GroundMaxEN);
	Out.GroundZ = Num(Ground, TEXT("z"), Out.GroundZ);

	const TSharedPtr<FJsonObject> Lamps = Field(Root, TEXT("lamps"));
	Out.LampHeight = Num(Lamps, TEXT("height"), Out.LampHeight);
	Out.LampIntensityCd = Num(Lamps, TEXT("intensity_cd"), Out.LampIntensityCd);
	Out.LampTemperatureK = Num(Lamps, TEXT("temperature_k"), Out.LampTemperatureK);
	Out.LampAttenuationRadius = Num(Lamps, TEXT("attenuation_radius"), Out.LampAttenuationRadius);
	Out.LampOuterConeDeg = Num(Lamps, TEXT("outer_cone_deg"), Out.LampOuterConeDeg);
	if (Lamps.IsValid())
	{
		Lamps->TryGetBoolField(TEXT("cast_shadows"), Out.bLampShadows);
		const TArray<TSharedPtr<FJsonValue>>* Positions = nullptr;
		if (Lamps->TryGetArrayField(TEXT("positions"), Positions))
		{
			for (const TSharedPtr<FJsonValue>& V : *Positions)
			{
				FStrayLampDef L;
				if (ReadVec2(V->AsObject(), TEXT("en"), L.PosEN) && ReadVec2(V->AsObject(), TEXT("arm_dir_en"), L.ArmDirEN))
				{
					Out.Lamps.Add(L);
				}
			}
		}
	}

	auto ReadFeatureList = [](const TSharedPtr<FJsonObject>& Obj, TArray<FStrayFacadeFeature>& List)
	{
		const TArray<TSharedPtr<FJsonValue>>* Items = nullptr;
		if (Obj.IsValid() && Obj->TryGetArrayField(TEXT("items"), Items))
		{
			for (const TSharedPtr<FJsonValue>& V : *Items)
			{
				FStrayFacadeFeature F;
				if (ReadFeature(V->AsObject(), F))
				{
					List.Add(F);
				}
			}
		}
	};

	const TSharedPtr<FJsonObject> Shops = Field(Root, TEXT("shopfronts"));
	Out.ShopfrontIntensityCd = Num(Shops, TEXT("intensity_cd"), Out.ShopfrontIntensityCd);
	Out.ShopfrontEmissiveNits = Num(Shops, TEXT("emissive_nits"), Out.ShopfrontEmissiveNits);
	ReadFeatureList(Shops, Out.Shopfronts);

	const TSharedPtr<FJsonObject> Win = Field(Root, TEXT("upper_windows"));
	Out.WindowEmissiveNits = Num(Win, TEXT("emissive_nits"), Out.WindowEmissiveNits);
	Out.WindowWidth = Num(Win, TEXT("width"), Out.WindowWidth);
	Out.WindowHeight = Num(Win, TEXT("height"), Out.WindowHeight);
	ReadFeatureList(Win, Out.Windows);

	if (!ReadFeature(Field(Root, TEXT("kiosk")), Out.Kiosk) || !ReadFeature(Field(Root, TEXT("club")), Out.Club))
	{
		OutError = TEXT("missing kiosk or club feature");
		return false;
	}

	const TSharedPtr<FJsonObject> Spawn = Field(Root, TEXT("spawn"));
	if (!ReadVec2(Spawn, TEXT("en"), Out.SpawnEN) || !ReadVec2(Spawn, TEXT("yaw_dir_en"), Out.SpawnDirEN))
	{
		OutError = TEXT("missing spawn");
		return false;
	}

	const TArray<TSharedPtr<FJsonValue>>* Views = nullptr;
	if (Root->TryGetArrayField(TEXT("viewpoints"), Views))
	{
		for (const TSharedPtr<FJsonValue>& V : *Views)
		{
			const TSharedPtr<FJsonObject> O = V->AsObject();
			FStrayViewpoint VP;
			FVector2D Eye, Look;
			if (O.IsValid() && ReadVec2(O, TEXT("en"), Eye) && ReadVec2(O, TEXT("look_en"), Look))
			{
				O->TryGetStringField(TEXT("name"), VP.Name);
				VP.EyeEN = FVector(Eye.X, Eye.Y, Num(O, TEXT("h"), 1.7));
				VP.TargetEN = FVector(Look.X, Look.Y, Num(O, TEXT("look_h"), 1.7));
				Out.Viewpoints.Add(VP);
			}
		}
	}

	const TSharedPtr<FJsonObject> Lighting = Field(Root, TEXT("lighting"));
	if (Lighting.IsValid())
	{
		ReadPreset(Field(Lighting, TEXT("night")), false, Out.Night);
		ReadPreset(Field(Lighting, TEXT("day")), true, Out.Day);
	}
	return true;
}

bool FStrayP001Layout::LoadFromFile(const FString& AbsolutePath, FStrayP001Layout& Out, FString& OutError)
{
	FString Json;
	if (!FFileHelper::LoadFileToString(Json, *AbsolutePath))
	{
		OutError = FString::Printf(TEXT("cannot read %s"), *AbsolutePath);
		return false;
	}
	Out.SourceDir = FPaths::GetPath(AbsolutePath);
	return FromJsonString(Json, Out, OutError);
}

FString FStrayP001Layout::ResolveDataPath(const FString& Relative) const
{
	return FPaths::ConvertRelativePathToFull(SourceDir / Relative);
}

FString FStrayP001Layout::DefaultLayoutPath()
{
	return FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir() / TEXT("../../data/p001/P001_Layout.json"));
}

FTransform FStrayP001Layout::ComputeSpawnTransform(double CapsuleHalfHeightCm, double SpawnClearanceCm) const
{
	const double GroundTopCm = GroundZAt(SpawnEN) * 100.0;
	FVector Loc = StrayGeo::EnuToUnreal(SpawnEN.X, SpawnEN.Y, 0.0);
	Loc.Z = GroundTopCm + CapsuleHalfHeightCm + SpawnClearanceCm;
	return FTransform(FRotator(0.0, StrayGeo::EnDirToYaw(SpawnDirEN), 0.0), Loc);
}

FVector2D FStrayP001Layout::ToStreetFrame(const FVector2D& PosEN) const
{
	const FVector2D D = PosEN - Street.OriginEN;
	return FVector2D(FVector2D::DotProduct(D, Street.AxisEN()), FVector2D::DotProduct(D, Street.RightEN()));
}

FStrayProfileSample FStrayP001Layout::ProfileAt(double S) const
{
	if (Profile.Num() == 0)
	{
		FStrayProfileSample Flat;
		Flat.S = S;
		Flat.SidewalkWest = Flat.SidewalkEast = Flat.FacadeWest = Flat.FacadeEast = Street.KerbHeight;
		return Flat;
	}
	if (S <= Profile[0].S)
	{
		return Profile[0];
	}
	if (S >= Profile.Last().S)
	{
		return Profile.Last();
	}
	int32 I = 1;
	while (Profile[I].S < S)
	{
		++I;
	}
	const FStrayProfileSample& A = Profile[I - 1];
	const FStrayProfileSample& B = Profile[I];
	const double T = (S - A.S) / FMath::Max(B.S - A.S, 1e-6);
	FStrayProfileSample R;
	R.S = S;
	R.RoadCentre = FMath::Lerp(A.RoadCentre, B.RoadCentre, T);
	R.RoadEdgeWest = FMath::Lerp(A.RoadEdgeWest, B.RoadEdgeWest, T);
	R.RoadEdgeEast = FMath::Lerp(A.RoadEdgeEast, B.RoadEdgeEast, T);
	R.SidewalkWest = FMath::Lerp(A.SidewalkWest, B.SidewalkWest, T);
	R.SidewalkEast = FMath::Lerp(A.SidewalkEast, B.SidewalkEast, T);
	R.FacadeWest = FMath::Lerp(A.FacadeWest, B.FacadeWest, T);
	R.FacadeEast = FMath::Lerp(A.FacadeEast, B.FacadeEast, T);
	return R;
}

double FStrayP001Layout::RoadZ(double S, double V) const
{
	const FStrayProfileSample P = ProfileAt(S);
	const double T = FMath::Clamp(FMath::Abs(V) / FMath::Max(Street.KerbHalfWidth, 1e-6), 0.0, 1.0);
	return FMath::Lerp(P.RoadCentre, V < 0.0 ? P.RoadEdgeWest : P.RoadEdgeEast, T);
}

double FStrayP001Layout::SidewalkZ(double S, double V) const
{
	const FStrayProfileSample P = ProfileAt(S);
	const double Kerb = Street.KerbHalfWidth + KerbStoneWidth;
	if (V < 0.0)
	{
		const double T = FMath::Clamp((-V - Kerb) / FMath::Max(-ProfileFacadeVWest - Kerb, 1e-6), 0.0, 1.0);
		return FMath::Lerp(P.SidewalkWest, P.FacadeWest, T);
	}
	const double T = FMath::Clamp((V - Kerb) / FMath::Max(ProfileFacadeVEast - Kerb, 1e-6), 0.0, 1.0);
	return FMath::Lerp(P.SidewalkEast, P.FacadeEast, T);
}

double FStrayP001Layout::GroundZAt(const FVector2D& PosEN) const
{
	const FVector2D SV = ToStreetFrame(PosEN);
	const FStrayProfileSample P = ProfileAt(SV.X);
	if (FMath::Abs(SV.Y) >= Street.KerbHalfWidth)
	{
		return SidewalkZ(SV.X, SV.Y);
	}
	if (FMath::Abs(SV.Y) <= Street.MedianHalfWidth)
	{
		return P.RoadCentre + MedianRise;
	}
	return RoadZ(SV.X, SV.Y);
}

bool FStrayP001Layout::IsOnSidewalk(const FVector2D& PosEN) const
{
	const FVector2D SV = ToStreetFrame(PosEN);
	const double S = SV.X;
	const double V = SV.Y;
	if (S < Street.SStart || S > Street.SEnd)
	{
		return false;
	}
	return (V >= Street.SidewalkWestOuter && V <= -Street.KerbHalfWidth)
		|| (V >= Street.KerbHalfWidth && V <= Street.SidewalkEastOuter);
}
