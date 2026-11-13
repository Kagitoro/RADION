@tool
extends Node3D
## House lamps, edited by hand in the Godot editor: open assets/house_lights.tscn,
## drag a light in the 3D view (its range sphere / cone shows what it reaches),
## change colour, energy and range in the Inspector, save — the game picks it up.
##
## The house model is shown underneath while editing only (not saved, not loaded
## in the game). A light with the metadata `fixture` (a house item id such as
## "base-117", the chandelier) follows that item wherever it is moved; the others
## move with their room. Shadows are managed by the game (VisualQuality), so
## leave "Shadow" off here.

const REFERENCE := "res://assets/house.glb"

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var model := (load(REFERENCE) as PackedScene).instantiate()
	model.name = "HouseReference_EditorOnly"
	# Internal: drawn in the editor, never saved into the scene.
	add_child(model,false,Node.INTERNAL_MODE_FRONT)
	var catalog := model.find_child("Catalog",true,false) as Node3D
	if catalog!=null:
		catalog.hide()
