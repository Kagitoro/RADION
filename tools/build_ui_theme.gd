extends SceneTree
## Writes ui/theme.tres from UIKit.build_theme() (the low-poly UI theme).
## Run from the project root after changing UIKit:
##   godot --headless --path . --script res://tools/build_ui_theme.gd

const PATH := "res://ui/theme.tres"

func _init() -> void:
	# Keep the file's UID so scenes that reference the theme still resolve it.
	var uid := ResourceLoader.get_resource_uid(PATH)
	var error := ResourceSaver.save(UIKit.build_theme(),PATH)
	if error!=OK:
		push_error("theme: save failed (%d)" % error)
		quit(1)
		return
	if uid!=ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(PATH,uid)
	print("UI_THEME saved ",PATH)
	quit()
