class_name GameReset
extends RefCounted
## "Start over": wipes the player's progress and reloads the game from scratch.
## Preferences (language, music folder) and the house-editor layout are kept.

## Files that hold progress: story, last position, money and supplies.
static func progress_files() -> Array[String]:
	return [ArrivalIntro.SAVE, MainMenu.CHECKPOINT, StreetShop.SAVE]

static func wipe_progress() -> void:
	for path in progress_files():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Wipes progress and rebuilds the whole scene, as if the game was just launched.
static func restart(tree: SceneTree) -> void:
	wipe_progress()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.reload_current_scene.call_deferred()
