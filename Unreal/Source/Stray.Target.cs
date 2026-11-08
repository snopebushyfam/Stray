// STRAY game target.
using UnrealBuildTool;

public class StrayTarget : TargetRules
{
	public StrayTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("Stray");
	}
}
