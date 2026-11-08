// STRAY - Prototype 001 game mode. See StrayGameMode.h.
#include "StrayGameMode.h"

#include "Stray.h"
#include "StrayCharacter.h"
#include "StrayStreetBuilder.h"
#include "StrayStreetLayout.h"

#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerStart.h"
#include "HAL/PlatformMisc.h"
#include "Misc/CommandLine.h"
#include "Misc/Paths.h"
#include "TimerManager.h"
#include "UnrealClient.h"

AStrayGameMode::AStrayGameMode()
{
	DefaultPawnClass = AStrayCharacter::StaticClass();
}

void AStrayGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);

	for (TActorIterator<AStrayStreetBuilder> It(GetWorld()); It; ++It)
	{
		Street = *It;
		break;
	}
	if (!Street)
	{
		// Safety net: any map (even an empty one) shows the street.
		FActorSpawnParameters P;
		P.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		Street = GetWorld()->SpawnActor<AStrayStreetBuilder>(FVector::ZeroVector, FRotator::ZeroRotator, P);
		UE_LOG(LogStray, Warning, TEXT("STRAY_DIAG street_builder=spawned_by_gamemode map=%s"), *MapName);
	}
	else
	{
		UE_LOG(LogStray, Log, TEXT("STRAY_DIAG street_builder=found_in_map map=%s"), *MapName);
	}
}

AActor* AStrayGameMode::ChoosePlayerStart_Implementation(AController* Player)
{
	if (!Street || !Street->GetStats().bLayoutLoaded)
	{
		UE_LOG(LogStray, Error, TEXT("STRAY_DIAG spawn=fallback_playerstart (street layout not loaded)"));
		return Super::ChoosePlayerStart_Implementation(Player);
	}
	if (!SpawnPoint)
	{
		const AStrayCharacter* PawnCDO = GetDefault<AStrayCharacter>();
		const double HalfHeight = PawnCDO->GetCapsuleComponent()->GetUnscaledCapsuleHalfHeight();
		const FTransform T = Street->GetSpawnTransform(HalfHeight);
		FActorSpawnParameters P;
		P.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		SpawnPoint = GetWorld()->SpawnActor<APlayerStart>(T.GetLocation(), T.Rotator(), P);
		UE_LOG(LogStray, Log, TEXT("STRAY_DIAG spawn_point=%s yaw=%.1f"), *T.GetLocation().ToCompactString(), T.Rotator().Yaw);
	}
	return SpawnPoint;
}

void AStrayGameMode::StartPlay()
{
	Super::StartPlay();
	if (FParse::Param(FCommandLine::Get(), TEXT("StrayAutoShots")) && Street && Street->GetLayout().Viewpoints.Num() > 0)
	{
		UE_LOG(LogStray, Log, TEXT("STRAY_DIAG autoshots=start count=%d"), Street->GetLayout().Viewpoints.Num());
		// Let auto exposure, sky capture and Lumen settle first.
		GetWorldTimerManager().SetTimer(ShotTimer, this, &AStrayGameMode::NextAutoShot, 4.0f, false);
	}
}

void AStrayGameMode::NextAutoShot()
{
	APlayerController* PC = GetWorld()->GetFirstPlayerController();
	const TArray<FStrayViewpoint>& Views = Street->GetLayout().Viewpoints;
	const FString Dir = FPaths::ProjectSavedDir() / TEXT("Screenshots/P001");

	// Shot 0: the player's own third-person view at spawn. Then every viewpoint, then quit.
	if (ShotIndex < 0)
	{
		FScreenshotRequest::RequestScreenshot(Dir / TEXT("P001_00_player_spawn_thirdperson.png"), false, false);
		UE_LOG(LogStray, Log, TEXT("STRAY_DIAG autoshot=player_spawn_thirdperson pawn=%s"),
			PC && PC->GetPawn() ? *PC->GetPawn()->GetActorLocation().ToCompactString() : TEXT("none"));
	}
	else if (ShotIndex < Views.Num())
	{
		const FStrayViewpoint& V = Views[ShotIndex];
		const FVector Eye = StrayGeo::EnuToUnreal(V.EyeEN.X, V.EyeEN.Y, V.EyeEN.Z) + Street->GetActorLocation();
		const FVector Target = StrayGeo::EnuToUnreal(V.TargetEN.X, V.TargetEN.Y, V.TargetEN.Z) + Street->GetActorLocation();
		if (!ShotCamera)
		{
			ShotCamera = GetWorld()->SpawnActor<ACameraActor>(Eye, (Target - Eye).Rotation());
			ShotCamera->GetCameraComponent()->SetFieldOfView(75.0f);
			ShotCamera->GetCameraComponent()->bConstrainAspectRatio = false;
		}
		ShotCamera->SetActorLocationAndRotation(Eye, (Target - Eye).Rotation());
		if (PC)
		{
			PC->SetViewTarget(ShotCamera);
		}
		// Capture on the next timer tick so the new view has rendered and exposure adapted.
		GetWorldTimerManager().SetTimer(ShotTimer, FTimerDelegate::CreateWeakLambda(this, [this, Dir, Name = V.Name, Index = ShotIndex]()
		{
			FScreenshotRequest::RequestScreenshot(Dir / FString::Printf(TEXT("P001_%02d_%s.png"), Index + 1, *Name), false, false);
			UE_LOG(LogStray, Log, TEXT("STRAY_DIAG autoshot=%s"), *Name);
			GetWorldTimerManager().SetTimer(ShotTimer, this, &AStrayGameMode::NextAutoShot, 0.5f, false);
		}), 2.5f, false);
		++ShotIndex;
		return;
	}
	else
	{
		UE_LOG(LogStray, Log, TEXT("STRAY_DIAG autoshots=done dir=%s"), *FPaths::ConvertRelativePathToFull(Dir));
		FPlatformMisc::RequestExit(false);
		return;
	}
	++ShotIndex;
	GetWorldTimerManager().SetTimer(ShotTimer, this, &AStrayGameMode::NextAutoShot, 1.0f, false);
}
