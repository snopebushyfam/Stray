"""R12.5: converts CMU motion-capture clips (BVH, cgspeed MotionBuilder-friendly release) into
in-place, looping driver GLBs for the bake (tools/character/bake_npc_anims.gd).

    blender -b --python tools/character/convert_cmu_bvh.py -- <out_dir> Name=file.bvh:mode [...]
    mode: walk | jog | idle

Source: CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu): "The motion capture data may be
copied, modified, or redistributed without permission." BVH conversion by B. Hahne (cgspeed), same
terms. See assets/characters/mocap_cmu/SOURCE.txt.

Per clip:
1. import the BVH (120 fps); frame 1 is a T-pose (added by the BVH release)
2. find the best loop: walk/jog = one full gait cycle (two steps), idle = 3-8 s of calm standing;
   cost = pose difference + velocity difference at the seam (+ foot motion for idle)
3. new armature B whose REST pose is the frame-1 T-pose; the motion is copied onto it in world
   space (Copy Transforms + bake), so animation = delta from the T-pose, as the retargeter expects
4. heading aligned to the T-pose facing; forward drift removed (in place), loop seam closed;
   idle: hip heading held constant (the actor turns while standing)
5. bones renamed to the Unreal-style names of the MPFB game_engine rig; helper finger bones
   (middle/index/pinky_01) added in the rest pose so the retargeter can measure the palm
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
SCALE = 0.056  # BVH units -> m (CMU thigh ~7.4 units ~ 0.42 m)
FPS = 120
MAP = {"Hips": "pelvis", "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
       "RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
       "LowerBack": "spine_01", "Spine": "spine_02", "Spine1": "spine_03", "Neck": "neck_01", "Head": "head",
       "LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
       "RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r"}
CYCLE_S = {"walk": (0.8, 1.6), "jog": (0.5, 1.0), "idle": (3.0, 8.0)}
FEAT = ["LeftFoot", "RightFoot", "LeftLeg", "RightLeg", "LeftHand", "RightHand", "LeftForeArm", "RightForeArm", "Head"]
scene = bpy.context.scene
scene.render.fps = FPS


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)


def activate(o, mode="OBJECT"):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for s in bpy.context.selected_objects:
        s.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    if mode != "OBJECT":
        bpy.ops.object.mode_set(mode=mode)


def sample(arm, frames):
    """World joint positions per frame -> dict name -> (n,3)."""
    names = FEAT + ["Hips", "LeftUpLeg", "RightUpLeg"]
    out = {n: np.zeros((len(frames), 3)) for n in names}
    for k, f in enumerate(frames):
        scene.frame_set(f)
        for n in names:
            out[n][k] = np.array(arm.matrix_world @ arm.pose.bones[n].head)
    return out


def yaw_of(P):
    lat = P["LeftUpLeg"] - P["RightUpLeg"]
    return np.arctan2(lat[:, 1], lat[:, 0])


def features(P):
    yaw = yaw_of(P)
    c, s = np.cos(-yaw), np.sin(-yaw)
    H = P["Hips"]
    parts = [H[:, 2:3]]
    for n in FEAT:
        d = P[n] - H
        x = c * d[:, 0] - s * d[:, 1]
        y = s * d[:, 0] + c * d[:, 1]
        parts.append(np.stack([x, y, d[:, 2]], 1))
    return np.concatenate(parts, 1)


def find_loop(P, frames, mode):
    F = features(P)
    V = np.gradient(F, axis=0)
    step = frames[1] - frames[0]
    lo, hi = (int(t * FPS / step) for t in CYCLE_S[mode])
    foot_speed = np.linalg.norm(np.gradient(P["LeftFoot"][:, :2], axis=0), axis=1) + \
        np.linalg.norm(np.gradient(P["RightFoot"][:, :2], axis=0), axis=1)
    best = (1e18, 0, 0)
    first = max(1, int(0.15 * FPS / step))  # skip the T-pose and the blend into the motion
    for s in range(first, len(frames) - lo - 1):
        for e in range(s + lo, min(s + hi, len(frames) - 1)):
            cost = np.sum((F[s] - F[e]) ** 2) + 4.0 * (step ** 0) * np.sum((V[s] - V[e]) ** 2)
            if mode == "idle":
                hip = P["Hips"][s:e, :2]
                if np.max(np.linalg.norm(hip - hip.mean(0), axis=1)) > 0.2:
                    continue
                # calm standing: little foot motion and little overall body motion (no gesturing,
                # bending or looking around - the "wait for bus" clip does all of that)
                cost += 20.0 * float(np.mean(foot_speed[s:e])) + 2.0 * float(np.mean(np.linalg.norm(V[s:e], axis=1)))
            if cost < best[0]:
                best = (cost, frames[s], frames[e])
    return best


def convert(name, path, mode):
    clear()
    bpy.ops.import_anim.bvh(filepath=path, global_scale=SCALE, frame_start=1, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=True, rotate_mode="NATIVE")
    A = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    n = int(A.animation_data.action.frame_range[1])
    step = 4 if mode == "idle" else 1
    frames = list(range(1, n + 1, step))
    P = sample(A, frames)
    cost, s, e = find_loop(P, frames, mode)
    k0, k1 = frames.index(s), frames.index(e)
    yaw = yaw_of(P)
    yaw1 = yaw[0]  # frame 1 = T-pose
    seg = yaw[k0:k1]
    mean_yaw = math.atan2(np.mean(np.sin(seg)), np.mean(np.cos(seg)))
    dyaw = yaw1 - mean_yaw
    print("CMU %s %s loop %d-%d (%.2fs) cost=%.4f heading_fix=%.1fdeg" % (name, os.path.basename(path), s, e,
          (e - s) / FPS, cost, math.degrees(dyaw)))
    # B: rest = frame-1 T-pose
    scene.frame_set(1)
    B = A.copy()
    B.data = A.data.copy()
    B.animation_data_clear()
    scene.collection.objects.link(B)
    for pb in B.pose.bones:
        pb.matrix_basis = A.pose.bones[pb.name].matrix_basis.copy()
    bpy.context.view_layer.update()
    activate(B, "POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    h1 = Vector(B.matrix_world @ B.data.bones["Hips"].head_local)
    # A: heading fix + in-place (linear drift between the loop ends removed) via object keys
    rot = Matrix.Rotation(dyaw, 4, "Z")
    A.rotation_euler = (0.0, 0.0, dyaw)
    full = list(range(s, e + 1))
    scene.frame_set(s)
    if mode == "idle":
        # Standing: the actor slowly turns (+-45 deg) - keep the hip heading constant (smoothed over
        # 0.5 s so the natural hip twist stays), rotate about the mean hip position (sway kept).
        yaw_u = np.unwrap(yaw)
        f_s = np.array(frames, dtype=float)
        win = max(1, int(0.5 * FPS / step))
        smooth = np.convolve(yaw_u, np.ones(win) / win, mode="same")
        hm = P["Hips"][k0:k1].mean(0)
        for f in full:
            r = yaw1 - float(np.interp(f, f_s, smooth))
            R = Matrix.Rotation(r, 4, "Z")
            c = R @ Vector(hm)
            A.rotation_euler = (0.0, 0.0, r)
            A.location = (h1.x - c.x, h1.y - c.y, 0.0)
            A.keyframe_insert("rotation_euler", frame=f)
            A.keyframe_insert("location", frame=f)
    else:
        hs = np.array(rot @ Vector(P["Hips"][k0]))
        he = np.array(rot @ Vector(P["Hips"][k1]))
        for f in full:
            t = (f - s) / max(e - s, 1)
            d = hs + (he - hs) * t
            A.location = (h1.x - d[0], h1.y - d[1], 0.0)
            A.keyframe_insert("location", frame=f)
    # copy world transforms onto B and bake
    for pb in B.pose.bones:
        c = pb.constraints.new("COPY_TRANSFORMS")
        c.target = A
        c.subtarget = pb.name
    activate(B, "POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=s, frame_end=e, step=1, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    act = B.animation_data.action
    act.name = name
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.co.x -= s
            kp.handle_left.x -= s
            kp.handle_right.x -= s
    bpy.data.objects.remove(A, do_unlink=True)
    for other in list(bpy.data.actions):
        if other != act:
            bpy.data.actions.remove(other)
    # rename to the game_engine names; unmapped bones get a prefix so they never match
    for b in B.data.bones:
        b.name = MAP.get(b.name, "cmu_" + b.name)
    # helper finger bones (rest only) for the palm frame
    activate(B, "EDIT")
    eb = B.data.edit_bones
    lat = (eb["thigh_l"].head - eb["thigh_r"].head)
    lat.z = 0.0
    lat.normalize()
    fwd = lat.cross(Vector((0, 0, 1))).normalized()
    for side in ("l", "r"):
        hand = eb["hand_" + side]
        along = (hand.tail - hand.head).normalized()
        base = hand.tail
        for nm, off in (("middle_01_", 0.0), ("index_01_", 0.025), ("pinky_01_", -0.025)):
            nb = eb.new(nm + side)
            nb.head = base + fwd * off
            nb.tail = nb.head + along * 0.03
            nb.parent = hand
    bpy.ops.object.mode_set(mode="OBJECT")
    scene.frame_start = 0
    scene.frame_end = e - s
    out = os.path.join(OUT_DIR, "cmu_%s.glb" % name.lower())
    activate(B)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_force_sampling=True, export_frame_range=False, export_yup=True,
                              export_apply=False, export_skins=False)
    print("CMU exported", out, os.path.getsize(out))


os.makedirs(OUT_DIR, exist_ok=True)
for spec in argv[1:]:
    name, rest = spec.split("=", 1)
    path, mode = rest.rsplit(":", 1)
    convert(name, path, mode)
