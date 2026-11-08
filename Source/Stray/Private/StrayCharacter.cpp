// STRAY - third-person player character. See StrayCharacter.h.
#include "StrayCharacter.h"

#include "Stray.h"
#include "StrayStreetBuilder.h"

#include "Animation/AnimInstance.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/LocalPlayer.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "EngineUtils.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/SpringArmComponent.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "InputModifiers.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "UObject/ConstructorHelpers.h"

AStrayCharacter::AStrayCharacter()
{
	GetCapsuleComponent()->InitCapsuleSize(35.0f, 90.0f);

	bUseControllerRotationPitch = false;
	bUseControllerRotationYaw = false;
	bUseControllerRotationRoll = false;

	UCharacterMovementComponent* Move = GetCharacterMovement();
	Move->bOrientRotationToMovement = true;
	Move->RotationRate = FRotator(0.0, 540.0, 0.0);
	Move->MaxWalkSpeed = WalkSpeed;
	Move->JumpZVelocity = 380.0f;
	Move->AirControl = 0.3f;
	Move->MaxStepHeight = 40.0f; // kerbs are 15 cm

	CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
	CameraBoom->SetupAttachment(RootComponent);
	CameraBoom->TargetArmLength = 320.0f;
	CameraBoom->SocketOffset = FVector(0.0, 45.0, 55.0);
	CameraBoom->bUsePawnControlRotation = true;
	CameraBoom->bEnableCameraLag = true;
	CameraBoom->CameraLagSpeed = 12.0f;

	FollowCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FollowCamera"));
	FollowCamera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
	FollowCamera->bUsePawnControlRotation = false;

	// Placeholder body (1.75 m) until a real character mesh is configured. Clearly a placeholder.
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Sphere(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	PlaceholderBody = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderBody"));
	PlaceholderBody->SetupAttachment(GetCapsuleComponent());
	PlaceholderBody->SetStaticMesh(Cylinder.Object);
	PlaceholderBody->SetRelativeLocation(FVector(0.0, 0.0, -90.0 + 75.0));
	PlaceholderBody->SetRelativeScale3D(FVector(0.45, 0.32, 1.5));
	PlaceholderBody->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	PlaceholderHead = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderHead"));
	PlaceholderHead->SetupAttachment(GetCapsuleComponent());
	PlaceholderHead->SetStaticMesh(Sphere.Object);
	PlaceholderHead->SetRelativeLocation(FVector(0.0, 0.0, -90.0 + 150.0 + 12.0));
	PlaceholderHead->SetRelativeScale3D(FVector(0.24));
	PlaceholderHead->SetCollisionEnabled(ECollisionEnabled::NoCollision);
}

void AStrayCharacter::BeginPlay()
{
	Super::BeginPlay();
	GetCharacterMovement()->MaxWalkSpeed = WalkSpeed;

	USkeletalMesh* Skel = CharacterMesh.IsValid() ? Cast<USkeletalMesh>(CharacterMesh.TryLoad()) : nullptr;
	if (Skel)
	{
		GetMesh()->SetSkeletalMesh(Skel);
		GetMesh()->SetRelativeLocationAndRotation(FVector(0.0, 0.0, -90.0), FRotator(0.0, -90.0, 0.0));
		if (UClass* Anim = CharacterAnimClass.TryLoadClass<UAnimInstance>())
		{
			GetMesh()->SetAnimInstanceClass(Anim);
		}
		PlaceholderBody->SetVisibility(false);
		PlaceholderHead->SetVisibility(false);
	}
	else
	{
		UMaterialInterface* Base = LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
		if (UMaterialInstanceDynamic* MID = Base ? UMaterialInstanceDynamic::Create(Base, this) : nullptr)
		{
			MID->SetVectorParameterValue(TEXT("Color"), FLinearColor(0.15f, 0.22f, 0.35f));
			PlaceholderBody->SetMaterial(0, MID);
			PlaceholderHead->SetMaterial(0, MID);
		}
	}
	UE_LOG(LogStray, Log, TEXT("STRAY_DIAG character=%s"), Skel ? *Skel->GetPathName() : TEXT("placeholder"));
	VerifyGround();
}

void AStrayCharacter::VerifyGround()
{
	UWorld* World = GetWorld();
	if (!World)
	{
		return;
	}
	const FVector Start = GetActorLocation();
	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(StraySpawnGround), false, this);
	const bool bGround = World->LineTraceSingleByChannel(Hit, Start, Start - FVector(0, 0, 500), ECC_Visibility, Params);
	const double Gap = bGround ? (Start.Z - GetCapsuleComponent()->GetScaledCapsuleHalfHeight()) - Hit.ImpactPoint.Z : -1.0;
	UE_LOG(LogStray, Log, TEXT("STRAY_DIAG spawn=%s ground_hit=%d ground_actor=%s gap_cm=%.1f"),
		*Start.ToCompactString(), bGround ? 1 : 0, bGround && Hit.GetActor() ? *Hit.GetActor()->GetName() : TEXT("none"), Gap);
	if (!bGround)
	{
		// Recovery: look for ground from high above (never leave the player falling forever).
		FHitResult High;
		if (World->LineTraceSingleByChannel(High, Start + FVector(0, 0, 10000), Start - FVector(0, 0, 10000), ECC_Visibility, Params))
		{
			SetActorLocation(High.ImpactPoint + FVector(0, 0, GetCapsuleComponent()->GetScaledCapsuleHalfHeight() + 5.0), false, nullptr, ETeleportType::TeleportPhysics);
			UE_LOG(LogStray, Error, TEXT("STRAY_DIAG spawn_recovered_to=%s"), *GetActorLocation().ToCompactString());
		}
		else
		{
			UE_LOG(LogStray, Error, TEXT("STRAY_DIAG spawn_failed no ground anywhere below/above the spawn point"));
		}
	}
}

void AStrayCharacter::EnsureInput()
{
	if (MappingContext)
	{
		return;
	}
	auto MakeAction = [this](const TCHAR* Name, EInputActionValueType Type)
	{
		UInputAction* A = NewObject<UInputAction>(this, Name);
		A->ValueType = Type;
		return A;
	};
	MoveAction = MakeAction(TEXT("IA_Move"), EInputActionValueType::Axis2D);
	LookAction = MakeAction(TEXT("IA_Look"), EInputActionValueType::Axis2D);
	JumpAction = MakeAction(TEXT("IA_Jump"), EInputActionValueType::Boolean);
	RunAction = MakeAction(TEXT("IA_Run"), EInputActionValueType::Boolean);
	DayNightAction = MakeAction(TEXT("IA_DayNight"), EInputActionValueType::Boolean);

	MappingContext = NewObject<UInputMappingContext>(this, TEXT("IMC_StrayDefault"));
	// Move: X = right, Y = forward.
	auto Swizzle = [this]() { return NewObject<UInputModifierSwizzleAxis>(this); }; // default order YXZ
	auto Negate = [this]() { return NewObject<UInputModifierNegate>(this); };
	MappingContext->MapKey(MoveAction, EKeys::W).Modifiers.Add(Swizzle());
	{
		FEnhancedActionKeyMapping& S = MappingContext->MapKey(MoveAction, EKeys::S);
		S.Modifiers.Add(Swizzle());
		S.Modifiers.Add(Negate());
	}
	MappingContext->MapKey(MoveAction, EKeys::A).Modifiers.Add(Negate());
	MappingContext->MapKey(MoveAction, EKeys::D);
	MappingContext->MapKey(MoveAction, EKeys::Gamepad_Left2D);

	UInputModifierNegate* InvertY = NewObject<UInputModifierNegate>(this);
	InvertY->bX = false;
	InvertY->bY = true;
	InvertY->bZ = false;
	MappingContext->MapKey(LookAction, EKeys::Mouse2D).Modifiers.Add(InvertY);
	UInputModifierNegate* PadInvertY = NewObject<UInputModifierNegate>(this);
	PadInvertY->bX = false;
	PadInvertY->bY = true;
	PadInvertY->bZ = false;
	MappingContext->MapKey(LookAction, EKeys::Gamepad_Right2D).Modifiers.Add(PadInvertY);

	MappingContext->MapKey(JumpAction, EKeys::SpaceBar);
	MappingContext->MapKey(JumpAction, EKeys::Gamepad_FaceButton_Bottom);
	MappingContext->MapKey(RunAction, EKeys::LeftShift);
	MappingContext->MapKey(RunAction, EKeys::Gamepad_LeftTrigger);
	MappingContext->MapKey(DayNightAction, EKeys::N);
}

void AStrayCharacter::PawnClientRestart()
{
	Super::PawnClientRestart();
	EnsureInput();
	if (const APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		if (UEnhancedInputLocalPlayerSubsystem* Sub = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			Sub->RemoveMappingContext(MappingContext);
			Sub->AddMappingContext(MappingContext, 0);
		}
	}
}

void AStrayCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);
	EnsureInput();
	UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(PlayerInputComponent);
	if (!EIC)
	{
		UE_LOG(LogStray, Error, TEXT("STRAY_DIAG input=failed (DefaultInputComponentClass is not EnhancedInputComponent)"));
		return;
	}
	EIC->BindAction(MoveAction, ETriggerEvent::Triggered, this, &AStrayCharacter::Move);
	EIC->BindAction(LookAction, ETriggerEvent::Triggered, this, &AStrayCharacter::Look);
	EIC->BindAction(JumpAction, ETriggerEvent::Started, this, &ACharacter::Jump);
	EIC->BindAction(JumpAction, ETriggerEvent::Completed, this, &ACharacter::StopJumping);
	EIC->BindAction(RunAction, ETriggerEvent::Started, this, &AStrayCharacter::RunStart);
	EIC->BindAction(RunAction, ETriggerEvent::Completed, this, &AStrayCharacter::RunStop);
	EIC->BindAction(DayNightAction, ETriggerEvent::Started, this, &AStrayCharacter::ToggleDayNight);
	UE_LOG(LogStray, Log, TEXT("STRAY_DIAG input=ok"));
}

void AStrayCharacter::Move(const FInputActionValue& Value)
{
	const FVector2D Axis = Value.Get<FVector2D>();
	if (!Controller)
	{
		return;
	}
	const FRotator Yaw(0.0, Controller->GetControlRotation().Yaw, 0.0);
	AddMovementInput(FRotationMatrix(Yaw).GetUnitAxis(EAxis::X), Axis.Y);
	AddMovementInput(FRotationMatrix(Yaw).GetUnitAxis(EAxis::Y), Axis.X);
}

void AStrayCharacter::Look(const FInputActionValue& Value)
{
	const FVector2D Axis = Value.Get<FVector2D>();
	AddControllerYawInput(Axis.X);
	AddControllerPitchInput(Axis.Y);
}

void AStrayCharacter::RunStart() { GetCharacterMovement()->MaxWalkSpeed = RunSpeed; }
void AStrayCharacter::RunStop() { GetCharacterMovement()->MaxWalkSpeed = WalkSpeed; }

void AStrayCharacter::ToggleDayNight()
{
	for (TActorIterator<AStrayStreetBuilder> It(GetWorld()); It; ++It)
	{
		It->SetDayMode(!It->IsDayMode());
	}
}
