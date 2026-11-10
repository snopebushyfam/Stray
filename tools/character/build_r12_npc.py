"""R12 NPC pilot: builds one MakeHuman/MPFB NPC from tools/character/npc_specs.json and exports a
web-optimised GLB: ONE mesh, ONE material (all textures packed into an atlas), T-pose rest,
MPFB "game_engine" rig (Unreal-style bone names, like the Quaternius UAL animations).

    blender -b --python tools/character/build_r12_npc.py -- <npc_id> <out.glb>

Same setup as tools/character/build_r11_human.py (Blender 4.5 LTS + MPFB 2.0.18 + CC0 asset packs).
Animations are baked onto the exported rig afterwards in Godot (tools/character/bake_npc_anims.gd).
"""
import json
import os
import sys
import bpy
import numpy as np
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
DECIMATE = "--no-decimate" not in sys.argv
# R12.1: decimate per part BEFORE joining, without vertex groups. One collapse pass on the joined
# mesh with a weighted protect group collapsed the clothing into a few large triangles (verified
# in renders); per-part ratios are predictable. Hands/face belong to "body" (mild 0.75).
PART_RATIO = {"clothes0": 0.5, "clothes1": 0.45, "hair": 0.6, "body": 0.75}
# R12.1: keep MakeHuman's A-pose as bind pose (its weights are painted for it). Baking a T-pose
# into the mesh made linear-blend skinning rotate the shoulders ~80 deg back for every idle/walk
# frame (collapsed, pointy shoulders). Retargeting builds the T-pose virtually (human_rig.gd).
BIND_TPOSE = "--tpose" in sys.argv
NPC_ID, OUT = args[0], args[1]
SPECS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_specs.json")))["npcs"]
spec = SPECS[NPC_ID]

from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

info = HumanService._create_default_human_info_dict()
info["name"] = "stray_" + NPC_ID
info["phenotype"].update({k: v for k, v in spec["phenotype"].items()})
info["rig"] = "game_engine"
info["eyes"] = "low-poly/low-poly.mhclo"
info["eyebrows"] = spec.get("eyebrows", "")
info["eyelashes"] = spec.get("eyelashes", "")
info["hair"] = spec.get("hair", "")
info["clothes"] = spec["clothes"]
info["skin_mhmat"] = spec["skin"]
info["skin_material_type"] = "GAMEENGINE"
info["eyes_material_type"] = "MAKESKIN"
settings = HumanService.get_default_deserialization_settings()
settings.update({"feet_on_ground": False, "subdiv_levels": 0, "mask_helpers": True, "detailed_helpers": True,
                 "extra_vertex_groups": True, "override_rig": "game_engine", "clothes_deep_search": False,
                 "bodypart_deep_search": False})
basemesh = HumanService.deserialize_from_dict(info, settings)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
# R12.3: R12-R12.2 built with detailed_helpers=False, which deletes the joint-* vertex groups MPFB fits
# the rig from - every NPC got the DEFAULT joint positions (upperarm_l x 0.170, same head height for
# a 1.6 m woman and a 1.95 m man). Animations then pivoted shoulders and neck around wrong joints
# (bulging "shoulder pads", squashed neck). detailed_helpers=True above; the refit is a safety net.
from bl_ext.user_default.mpfb.services.rigservice import RigService  # noqa: E402
RigService.refit_existing_armature(arm, basemesh)
bpy.context.view_layer.update()
print("R12 rig refit: head z %.3f upperarm_l x %.3f" % ((arm.matrix_world @ arm.data.bones["head"].head_local).z,
      (arm.matrix_world @ arm.data.bones["upperarm_l"].head_local).x))
meshes =[o for o in bpy.data.objects if o.type == "MESH"]
print("R12 objects", [(o.name, len(o.data.vertices)) for o in meshes])


def activate(o):
    for s in bpy.context.selected_objects:
        s.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


# --- bake targets + helper masks; keep the armature modifier ------------------------------------
for o in meshes:
    activate(o)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type in ("MASK", "SUBSURF"):
            bpy.ops.object.modifier_apply(modifier=m.name)

# --- T-pose (lateral axis measured on the character), bake, apply as rest -----------------------
# (only with --tpose; default since R12.1: A-pose bind)
if BIND_TPOSE:
    activate(arm)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.context.view_layer.update()
    lateral = (arm.matrix_world @ arm.pose.bones["upperarm_l"].head) - (arm.matrix_world @ arm.pose.bones["upperarm_r"].head)
    lateral.z = 0.0
    lateral.normalize()
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
                pb.matrix = arm.matrix_world.inverted() @ (Matrix.Translation(head) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-head)) @ mw
            bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in meshes:
        if not any(m.type == "ARMATURE" for m in o.modifiers):
            continue
        activate(o)
        copy = o.modifiers.new("ArmatureRest", "ARMATURE")
        copy.object = arm
        while o.modifiers.find(copy.name) > 0:
            bpy.ops.object.modifier_move_up(modifier=copy.name)
        bpy.ops.object.modifier_apply(modifier=copy.name)
    activate(arm)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")


# --- texture atlas: every material's base colour (+alpha) packed into one image ----------------
def base_image(mat):
    if mat is None or not mat.use_nodes:
        return None
    imgs = [n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
    if not imgs:
        return None
    for want in ("diffuse", "color", "albedo"):
        for im in imgs:
            if want in im.name.lower():
                return im
    for im in imgs:
        if not any(k in im.name.lower() for k in ("normal", "_ao", "rough", "spec", "bump")):
            return im
    return imgs[0]


ATLAS_W, ATLAS_H = 2048, 2048
# (x, y, w, h) slots, bottom-left origin (Blender image rows go bottom-up)
SLOTS = {"body": (0, 1024, 1024, 1024), "clothes0": (1024, 1024, 1024, 1024), "clothes1": (1024, 512, 512, 512),
         "hair": (0, 512, 512, 512), "eyebrows": (512, 768, 256, 256), "eyelashes": (768, 768, 256, 256),
         "eyes": (512, 512, 256, 256)}
atlas = np.zeros((ATLAS_H, ATLAS_W, 4), dtype=np.float32)
assign = {}
clothes_i = 0
for o in meshes:
    mat = o.material_slots[0].material if o.material_slots else None
    n = o.name.lower()
    if "eyebrow" in n:
        key = "eyebrows"
    elif "eyelash" in n:
        key = "eyelashes"
    elif o == basemesh:
        key = "body"
    elif "low-poly" in n or ".eyes" in n:
        key = "eyes"
    elif any(h in n for h in ("short", "ponytail", "bob", "afro", "braid", "long0")):
        key = "hair"
    else:
        key = "clothes%d" % clothes_i
        clothes_i += 1
    img = base_image(mat)
    x, y, w, h = SLOTS[key]
    if img is not None:
        tmp = img.copy()
        tmp.scale(w, h)
        px = np.array(tmp.pixels[:], dtype=np.float32).reshape(h, w, 4)
        tint = spec.get("tint", {}).get(key)
        if tint:
            px[:, :, :3] *= np.array(tint, dtype=np.float32)  # e.g. white tee -> black tee (R12.3)
        atlas[y:y + h, x:x + w] = px
        bpy.data.images.remove(tmp)
    else:
        atlas[y:y + h, x:x + w] = (0.5, 0.5, 0.5, 1.0)
    assign[o.name] = key
    # Remap this object's UVs into its slot (clamped to 0..1 first).
    uv = o.data.uv_layers.active
    if uv is not None:
        co = np.zeros(len(uv.data) * 2, dtype=np.float32)
        uv.data.foreach_get("uv", co)
        co = co.reshape(-1, 2)
        co = np.clip(co, 0.0, 1.0)
        co[:, 0] = (x + co[:, 0] * w) / ATLAS_W
        co[:, 1] = (y + co[:, 1] * h) / ATLAS_H
        uv.data.foreach_set("uv", co.ravel())
print("R12 atlas slots", assign)
atlas_img = bpy.data.images.new("stray_%s_atlas" % NPC_ID, ATLAS_W, ATLAS_H, alpha=True)
atlas_img.pixels.foreach_set(atlas.ravel())
atlas_img.pack()

mat = bpy.data.materials.new("stray_%s" % NPC_ID)
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes.get("Principled BSDF")
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = atlas_img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
bsdf.inputs["Roughness"].default_value = 0.75
mat.blend_method = "CLIP"
mat.alpha_threshold = 0.5

# --- per-part polygon budget ------------------------------------------------------------------------
for o in meshes:
    r = PART_RATIO.get(assign.get(o.name, ""), 1.0)
    if not DECIMATE or r >= 1.0:
        continue
    before = len(o.data.polygons)
    activate(o)
    dec = o.modifiers.new("Budget", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = r
    dec.use_collapse_triangulate = True
    while o.modifiers.find(dec.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=dec.name)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    print("R12 decimate %s %s %.2f: %d -> %d faces" % (o.name, assign.get(o.name), r, before, len(o.data.polygons)))

# --- join everything into one skinned mesh with the one material ------------------------------
for o in meshes:
    o.data.materials.clear()
    o.data.materials.append(mat)
    # keep only the active UV map (the atlas one)
    for u in list(o.data.uv_layers):
        if u != o.data.uv_layers.active:
            o.data.uv_layers.remove(u)
for s in bpy.context.selected_objects:
    s.select_set(False)
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = basemesh
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "stray_%s_mesh" % NPC_ID

# --- lift so the soles touch y = 0 ---------------------------------------------------------------
lowest = min((body.matrix_world @ v.co).z for v in body.data.vertices)
arm.location.z -= lowest
bpy.context.view_layer.update()
body.data.calc_loop_triangles()
print("R12 joined mesh verts=%d tris=%d materials=%d lifted=%.3f" % (len(body.data.vertices), len(body.data.loop_triangles),
      len(body.data.materials), -lowest))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_skins=True, export_animations=False,
                          export_apply=True, export_yup=True, export_image_format="AUTO", export_morph=False)
print("R12 exported", OUT, os.path.getsize(OUT))
