"""R11 real-human prototype: builds one young adult male with MPFB 2 (MakeHuman) from CC0 assets
and exports a skinned GLB for Godot.

Run (Blender 4.5 LTS with the MPFB 2.0.18 extension and the CC0 asset packs installed into MPFB's
user data dir - see docs/R11_REAL_HUMAN_PROTOTYPE.md):
    blender -b --python tools/character/build_r11_human.py -- <out.glb>

Assets (all CC0 per the MakeHuman asset-pack pages and the .mhclo headers):
    body: MakeHuman basemesh + macro targets; skin "young_caucasian_male"
    eyes low-poly + brown, eyebrow001, eyelashes02, hair short02
    clothes male_casualsuit05 (jacket, shirt, jeans), shoes05 (white sneakers)
Rig: MPFB "game_engine" (Unreal-style bone names, same as the Quaternius UAL animations).
The rest pose is converted to a T-pose (arms horizontal) to match the UAL bind pose, so poses can be
retargeted by world-space rotation deltas in Godot.
"""
import os
import sys
import math
import bpy
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/r11_human.glb"
TEX_MAX = 1024  # px: web/tablet budget

from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402

# --- clean scene --------------------------------------------------------------------------------
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

info = HumanService._create_default_human_info_dict()
info["name"] = "stray_r11_male"
ph = info["phenotype"]
ph["gender"] = 1.0         # male
ph["age"] = 0.5            # MakeHuman scale: 0.5 = 25 years
ph["muscle"] = 0.5         # average, not athletic
ph["weight"] = 0.48
ph["height"] = 0.55
ph["proportions"] = 0.6
ph["race"] = {"african": 0.1, "asian": 0.1, "caucasian": 0.8}
info["rig"] = "game_engine"
info["eyes"] = "low-poly/low-poly.mhclo"
info["eyebrows"] = "eyebrow001/eyebrow001.mhclo"
info["eyelashes"] = "eyelashes02/eyelashes02.mhclo"
info["hair"] = "short02/short02.mhclo"
info["clothes"] = ["male_casualsuit05/male_casualsuit05.mhclo", "shoes05/shoes05.mhclo"]
info["skin_mhmat"] = "young_caucasian_male/young_caucasian_male.mhmat"
info["skin_material_type"] = "GAMEENGINE"
info["eyes_material_type"] = "MAKESKIN"
info["eyes_material_settings"] = {}

settings = HumanService.get_default_deserialization_settings()
settings.update({"feet_on_ground": False, "subdiv_levels": 0, "mask_helpers": True, "detailed_helpers": False, "extra_vertex_groups": True,
                 "override_rig": "game_engine", "clothes_deep_search": False, "bodypart_deep_search": False})
basemesh = HumanService.deserialize_from_dict(info, settings)
print("R11 basemesh", basemesh.name)

# feet_on_ground is off: MPFB lifts only the mesh, not the rig. The whole character is lifted below.
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
_zs = [(basemesh.matrix_world @ v.co).z for v in basemesh.data.vertices]
print("R11 check body z", min(_zs), max(_zs), "head bone", tuple(arm.matrix_world @ arm.data.bones["head"].head_local),
      "arm scale", tuple(arm.scale), "body parent", basemesh.parent.name if basemesh.parent else None,
      "body matrix", [list(r) for r in basemesh.matrix_world])
print("R11 objects", [(o.name, len(o.data.vertices), [m.type for m in o.modifiers]) for o in meshes])

# --- bake: shape keys (targets) and mask/delete modifiers; keep the armature modifier ----------
for o in meshes:
    bpy.context.view_layer.objects.active = o
    for s in bpy.context.selected_objects:
        s.select_set(False)
    o.select_set(True)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type in ("MASK", "SUBSURF"):
            bpy.ops.object.modifier_apply(modifier=m.name)

# --- T-pose: arms horizontal (like the Quaternius UAL bind pose) ------------------------------
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
bpy.context.view_layer.update()
# Lateral axis measured on the character (right shoulder -> left shoulder), not assumed.
_l = arm.matrix_world @ arm.pose.bones["upperarm_l"].head
_r = arm.matrix_world @ arm.pose.bones["upperarm_r"].head
lateral = (_l - _r)
lateral.z = 0.0
lateral.normalize()
print("R11 armature matrix_world", [list(r) for r in arm.matrix_world], "lateral", tuple(lateral))
for side, sx in (("l", 1.0), ("r", -1.0)):
    for bname in ("upperarm_", "lowerarm_", "hand_"):
        pb = arm.pose.bones[bname + side]
        bpy.context.view_layer.update()
        mw = arm.matrix_world @ pb.matrix
        head = mw.translation
        tail = arm.matrix_world @ (pb.matrix @ Vector((0, pb.bone.length, 0)))
        cur = (tail - head).normalized()
        want = lateral * sx
        if cur.dot(want) < 0.999:
            rot = cur.rotation_difference(want)
            # Apply the world rotation about the bone head, expressed in pose space.
            m_arm = arm.matrix_world.inverted() @ (Matrix.Translation(head) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-head)) @ mw
            pb.matrix = m_arm
        bpy.context.view_layer.update()
for side in ("l", "r"):
    pb = arm.pose.bones["hand_" + side]
    print("R11 T-pose hand_%s world" % side, tuple(arm.matrix_world @ pb.head))
bpy.ops.object.mode_set(mode="OBJECT")
# Bake the posed meshes, then make the pose the new rest pose.
for o in meshes:
    mod = next((m for m in o.modifiers if m.type == "ARMATURE"), None)
    if mod is None:
        continue
    bpy.context.view_layer.objects.active = o
    copy = o.modifiers.new("ArmatureRest", "ARMATURE")
    copy.object = arm
    # Move the copy to the top and apply it (bakes the T-pose into the mesh).
    while o.modifiers.find(copy.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=copy.name)
    bpy.ops.object.modifier_apply(modifier=copy.name)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode="OBJECT")

# --- lift armature + meshes together so the soles touch y = 0 ------------------------------------
lowest = min((o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices)
arm.location.z -= lowest
bpy.context.view_layer.update()
print("R11 lifted by", -lowest)

# --- textures: downscale for the web ------------------------------------------------------------
for img in bpy.data.images:
    if img.size[0] > TEX_MAX or img.size[1] > TEX_MAX:
        f = TEX_MAX / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
print("R11 images", [(i.name, tuple(i.size)) for i in bpy.data.images])

tris = 0
for o in meshes:
    o.data.calc_loop_triangles()
    tris += len(o.data.loop_triangles)
print("R11 triangles", tris, "materials", sorted({s.material.name for o in meshes for s in o.material_slots if s.material}))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_skins=True, export_animations=False,
                          export_apply=True, export_yup=True, export_image_format="AUTO", export_morph=False)
print("R11 exported", OUT, os.path.getsize(OUT))
