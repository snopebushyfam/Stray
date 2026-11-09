## R12: bakes the CC0 Quaternius UAL animations onto each NPC rig ONCE (offline), using the R11
## runtime retarget (StrayHumanRig) as the sampler. Result: assets/characters/r12_npc/<id>_anims.res,
## an AnimationLibrary with plain bone tracks, so NPCs need no second (driver) skeleton at runtime.
##   godot --headless --path . -s res://tools/character/bake_npc_anims.gd
extends SceneTree

const UAL := "res://assets/characters/quaternius_ual/UAL1_Standard.glb"
const DIR := "res://assets/characters/r12_npc/"
const NPCS := ["passerby_m", "passerby_f", "bouncer"]
const ANIMS := ["Idle", "Walk", "Idle_Talking"]
const FPS := 30.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for id in NPCS:
		var rig := StrayHumanRig.new()
		# Per-type retarget tuning (R12.1): tools/character/npc_specs.json -> npcs.<id>.retarget
		var specs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/character/npc_specs.json"))
		var rt: Dictionary = specs.get("npcs", {}).get(String(id), {}).get("retarget", {})
		for k in rt:
			rig.set(k, rt[k])
		root.add_child(rig)
		if not rig.setup(load(DIR + String(id) + ".glb"), load(UAL)):
			push_error("bake: setup failed for " + id)
			continue
		var sk := rig.dst
		var base_path := String(rig.human.get_path_to(sk))
		var lib := AnimationLibrary.new()
		for a in ANIMS:
			var src_anim: Animation = rig.anim.get_animation(a)
			var length := src_anim.length
			var anim := Animation.new()
			anim.length = length
			anim.loop_mode = Animation.LOOP_LINEAR
			var rot_tracks := {}
			for b in sk.get_bone_count():
				var t := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(t, NodePath("%s:%s" % [base_path, sk.get_bone_name(b)]))
				rot_tracks[b] = t
			var hip := sk.find_bone("pelvis")
			var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pos_track, NodePath("%s:pelvis" % base_path))
			# Evaluate the source tracks directly (AnimationPlayer.seek did not update the hidden driver
			# skeleton headless -> the first bake was a frozen pose).
			rig.anim.stop()
			var src_tracks := []
			for t in src_anim.get_track_count():
				var bone := rig.src.find_bone(String(src_anim.track_get_path(t).get_concatenated_subnames()))
				if bone >= 0:
					src_tracks.append([t, bone, src_anim.track_get_type(t)])
			var frames := int(ceil(length * FPS))
			for f in frames + 1:
				var time := minf(f / FPS, length)
				for st in src_tracks:
					if st[2] == Animation.TYPE_ROTATION_3D:
						rig.src.set_bone_pose_rotation(st[1], src_anim.rotation_track_interpolate(st[0], time))
					elif st[2] == Animation.TYPE_POSITION_3D:
						rig.src.set_bone_pose_position(st[1], src_anim.position_track_interpolate(st[0], time))
					elif st[2] == Animation.TYPE_SCALE_3D:
						rig.src.set_bone_pose_scale(st[1], src_anim.scale_track_interpolate(st[0], time))
				rig.src.force_update_all_bone_transforms()  # global poses are cached until the next skeleton update
				rig.retarget()
				for b in sk.get_bone_count():
					anim.rotation_track_insert_key(rot_tracks[b], time, sk.get_bone_pose_rotation(b))
				anim.position_track_insert_key(pos_track, time, sk.get_bone_pose_position(hip))
			# Drop redundant keys (static fingers etc.). Third argument is an INT precision: passing 0.01
			# (-> 0) collapsed every track to one key in the first bake.
			anim.optimize(0.005, 0.005, 3)
			lib.add_animation(a, anim)
		var out: String = DIR + String(id) + "_anims.res"
		var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
		var walk: Animation = lib.get_animation("Walk")
		var keys := 0
		for t in walk.get_track_count():
			keys += walk.track_get_key_count(t)
		print("BAKE %s anims=%s walk_keys=%d err=%d" % [id, ANIMS, keys, err])
		rig.queue_free()
		await process_frame
	quit(0)
