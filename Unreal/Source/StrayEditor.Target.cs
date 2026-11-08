// STRAY editor target.
using UnrealBuildTool;

public class StrayEditorTarget : TargetRules
{
	public StrayEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("Stray");
	}
}
