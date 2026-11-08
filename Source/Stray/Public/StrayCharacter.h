// STRAY - third-person player character (Prototype 001).
// Input is built in C++ (Enhanced Input objects created at runtime), so the
// prototype needs no .uasset input files. Design: docs/STRAY_GDD.md (P001).
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "InputActionValue.h"
#include "StrayCharacter.generated.h"

class UCameraComponent;
class UInputAction;
class UInputMappingContext;
class USpringArmComponent;
class UStaticMeshComponent;

UCLASS(config = Game)
class STRAY_API AStrayCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	AStrayCharacter();

	/** Walking speed in cm/s (realistic pedestrian ~1.4 m/s). */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Movement") float WalkSpeed = 160.0f;
	/** Run speed in cm/s while Shift / left trigger is held. */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Movement") float RunSpeed = 450.0f;

	/**
	 * Optional real character mesh. Empty or missing = visible placeholder body.
	 * The UE Third Person template content (Add Feature or Content Pack > Third Person)
	 * provides /Game/Characters/Mannequins/Meshes/SKM_Quinn_Simple.
	 */
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Look") FSoftObjectPath CharacterMesh;
	UPROPERTY(Config, EditAnywhere, Category = "Stray|Look") FSoftClassPath CharacterAnimClass;

protected:
	virtual void BeginPlay() override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
	virtual void PawnClientRestart() override;

	UPROPERTY(VisibleAnywhere, Category = "Stray|Camera") TObjectPtr<USpringArmComponent> CameraBoom;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Camera") TObjectPtr<UCameraComponent> FollowCamera;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Look") TObjectPtr<UStaticMeshComponent> PlaceholderBody;
	UPROPERTY(VisibleAnywhere, Category = "Stray|Look") TObjectPtr<UStaticMeshComponent> PlaceholderHead;

private:
	void EnsureInput();
	void Move(const FInputActionValue& Value);
	void Look(const FInputActionValue& Value);
	void RunStart();
	void RunStop();
	void ToggleDayNight();
	/** Logs the ground under the spawn and recovers if the pawn is not standing on anything. */
	void VerifyGround();

	UPROPERTY(Transient) TObjectPtr<UInputMappingContext> MappingContext;
	UPROPERTY(Transient) TObjectPtr<UInputAction> MoveAction;
	UPROPERTY(Transient) TObjectPtr<UInputAction> LookAction;
	UPROPERTY(Transient) TObjectPtr<UInputAction> JumpAction;
	UPROPERTY(Transient) TObjectPtr<UInputAction> RunAction;
	UPROPERTY(Transient) TObjectPtr<UInputAction> DayNightAction;
};
