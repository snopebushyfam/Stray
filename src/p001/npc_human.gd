## R12 NPC pilot: instantiates a real-human NPC (MakeHuman/MPFB, CC0) built by
## tools/character/build_r12_npc.py: one skinned mesh, one atlas material, and an AnimationPlayer
## with animations pre-baked onto its own rig (tools/character/bake_npc_anims.gd) - no runtime
## retargeting, no second skeleton. Mesh, material and animation library are shared resources.
## Animation names match the UAL ones used by the NPC code ("Idle", "Walk", "Idle_Talking").
class_name StrayNpcHuman
extends RefCounted

const DIR := "res://assets/characters/r12_npc/"


## True when the NPC type's model and baked animations exist.
static func available(id: String) -> bool:
	return ResourceLoader.exists(DIR + id + ".glb") and ResourceLoader.exists(DIR + id + "_anims.res")


## New instance of an NPC type with its AnimationPlayer (or null when unavailable).
static func create(id: String) -> Node3D:
	if not available(id):
		return null
	var model: Node3D = (load(DIR + id + ".glb") as PackedScene).instantiate()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	var lib: AnimationLibrary = load(DIR + id + "_anims.res")
	ap.add_animation_library("", lib)
	# R12.2: measured stance-foot speed of the baked walk (playback scaling without foot sliding).
	if lib.has_meta("walk_natural_speed"):
		model.set_meta("walk_natural_speed", lib.get_meta("walk_natural_speed"))
	model.set_meta("npc_type", id)
	return model
