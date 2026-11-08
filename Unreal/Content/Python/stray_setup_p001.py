"""STRAY - one-time editor setup for Prototype 001 (idempotent).

Creates, only if missing:
  /Game/Stray/Materials/M_Stray_Surface   (Color vector, Roughness scalar -> lit surface)
  /Game/Stray/Materials/M_Stray_Emissive  (Unlit; Color * Intensity -> emissive, in nits)
  /Game/Stray/Maps/L_P001_Street          (empty level + one StrayStreetBuilder at the origin)

Runs automatically on editor start (Config/DefaultEngine.ini, PythonScriptPlugin
StartupScripts), or manually:  Tools > Execute Python Script... > this file,
or headless: UnrealEditor-Cmd.exe Stray.uproject -run=pythonscript -script=stray_setup_p001.py
"""
import unreal

MAT_DIR = "/Game/Stray/Materials"
MAP_PATH = "/Game/Stray/Maps/L_P001_Street"
LOG = "STRAY_DIAG setup:"


def _exists(path):
    return unreal.EditorAssetLibrary.does_asset_exist(path)


def make_surface():
    path = f"{MAT_DIR}/M_Stray_Surface"
    if _exists(path):
        return
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    mat = tools.create_asset("M_Stray_Surface", MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
    mel = unreal.MaterialEditingLibrary
    color = mel.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -400, 0)
    color.set_editor_property("parameter_name", "Color")
    color.set_editor_property("default_value", unreal.LinearColor(0.5, 0.5, 0.5, 1.0))
    rough = mel.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -400, 200)
    rough.set_editor_property("parameter_name", "Roughness")
    rough.set_editor_property("default_value", 0.8)
    mel.connect_material_property(color, "", unreal.MaterialProperty.MP_BASE_COLOR)
    mel.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    mel.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(path)
    unreal.log(f"{LOG} created {path}")


def make_emissive():
    path = f"{MAT_DIR}/M_Stray_Emissive"
    if _exists(path):
        return
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    mat = tools.create_asset("M_Stray_Emissive", MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mel = unreal.MaterialEditingLibrary
    color = mel.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -600, 0)
    color.set_editor_property("parameter_name", "Color")
    color.set_editor_property("default_value", unreal.LinearColor(1.0, 1.0, 1.0, 1.0))
    inten = mel.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -600, 200)
    inten.set_editor_property("parameter_name", "Intensity")
    inten.set_editor_property("default_value", 10.0)
    mul = mel.create_material_expression(mat, unreal.MaterialExpressionMultiply, -300, 100)
    mel.connect_material_expressions(color, "", mul, "A")
    mel.connect_material_expressions(inten, "", mul, "B")
    mel.connect_material_property(mul, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    mel.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(path)
    unreal.log(f"{LOG} created {path}")


def make_level():
    if _exists(MAP_PATH):
        unreal.log(f"{LOG} {MAP_PATH} exists, not touched")
        return
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    if not les.new_level(MAP_PATH):
        unreal.log_error(f"{LOG} could not create {MAP_PATH}")
        return
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    builder = eas.spawn_actor_from_class(unreal.StrayStreetBuilder, unreal.Vector(0, 0, 0), unreal.Rotator(0, 0, 0))
    builder.set_actor_label("P001_Street_Hohenzollernring")
    les.save_current_level()
    unreal.log(f"{LOG} created {MAP_PATH} with StrayStreetBuilder")


def run():
    make_surface()
    make_emissive()
    make_level()


# On editor start the asset registry / editor world may not be ready yet: defer one tick.
_handle = None


def _tick(_dt):
    global _handle
    unreal.unregister_slate_post_tick_callback(_handle)
    try:
        run()
    except Exception as exc:  # report, never crash the editor
        unreal.log_error(f"{LOG} failed: {exc}")


_cmd = unreal.SystemLibrary.get_command_line().lower()
if "-run=pythonscript" in _cmd or "-executepythonscript" in _cmd:
    run()  # commandlet / explicit call: no Slate ticks, run now
else:
    _handle = unreal.register_slate_post_tick_callback(_tick)
