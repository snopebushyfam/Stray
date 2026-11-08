// STRAY runtime module. C++20 is the engine default in UE 5.8 - do not override CppStandard.
using UnrealBuildTool;

public class Stray : ModuleRules
{
	public Stray(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput",
			"ProceduralMeshComponent", "Json"
		});
	}
}
