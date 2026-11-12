class_name SavePaths
extends RefCounted
## Single place that decides where the game writes files.
## Test runs (--smoke / --visual-smoke) get their own folder so they never touch
## the player's real saves.

const TEST_FOLDER := "user://smoke_test/"

static func is_test_run() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--smoke" in args or "--visual-smoke" in args

static func file(file_name: String) -> String:
	if is_test_run():
		DirAccess.make_dir_recursive_absolute(TEST_FOLDER)
		return TEST_FOLDER + file_name
	return "user://" + file_name

## Deletes every file a previous test run left behind.
static func clear_test_files() -> void:
	var folder := DirAccess.open(TEST_FOLDER)
	if folder == null:
		return
	for entry in folder.get_files():
		folder.remove(entry)
