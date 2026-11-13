@tool
extends EditorPlugin
## Registers the low-poly scene import step (see lowpoly_post_import.gd).

var importer: EditorScenePostImportPlugin

func _enter_tree() -> void:
	importer = preload("res://addons/lowpoly_import/lowpoly_post_import.gd").new()
	add_scene_post_import_plugin(importer)

func _exit_tree() -> void:
	remove_scene_post_import_plugin(importer)
	importer = null
