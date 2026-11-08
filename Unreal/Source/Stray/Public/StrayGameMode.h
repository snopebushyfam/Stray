// STRAY - game mode for Prototype 001. Guarantees a street exists in whatever map is
// loaded, spawns the player from the layout data, and (with -StrayAutoShots) captures
// reproducible evidence screenshots from the layout's viewpoints, then quits.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "StrayGameMode.generated.h"

class ACameraActor;
class AStrayStreetBuilder;

UCLASS()
class STRAY_API AStrayGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AStrayGameMode();

	virtual void InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage) override;
	virtual AActor* ChoosePlayerStart_Implementation(AController* Player) override;
	virtual void StartPlay() override;

	AStrayStreetBuilder* GetStreet() const { return Street; }

private:
	void NextAutoShot();

	UPROPERTY(Transient) TObjectPtr<AStrayStreetBuilder> Street;
	UPROPERTY(Transient) TObjectPtr<AActor> SpawnPoint;
	UPROPERTY(Transient) TObjectPtr<ACameraActor> ShotCamera;

	int32 ShotIndex = -1;
	FTimerHandle ShotTimer;
};
