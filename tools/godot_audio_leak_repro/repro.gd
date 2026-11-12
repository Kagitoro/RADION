extends SceneTree
# Minimal repro of an engine-side leak seen in Godot 4.7.2 (not caused by game code):
# an AudioStreamPlayer playing an MP3 is stopped right before quit() and the engine
# still reports "ObjectDB instances leaked" (AudioStreamMP3 + AudioStreamPlaybackMP3).
#
#   cp <any>.mp3 track.mp3
#   godot --headless --path . -s repro.gd -- stop            # sometimes leaks
#   godot --headless --path . -s repro.gd -- bus stop        # leaks almost always
#   godot --headless --path . -s repro.gd -- layout stop     # bus from default_bus_layout.tres: leaks too
#
# Flags: bus = bus added at runtime, layout = bus from the layout file,
# stop = stop() before quit, paused = pause first, wait = wait 0.3 s, free = free the player.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamMP3.load_from_file(ProjectSettings.globalize_path("res://track.mp3"))
	stream.loop = true
	player.stream = stream
	if "layout" in args:
		player.bus = "Runtime"
	if "bus" in args:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Runtime")
		player.bus = "Runtime"
	root.add_child.call_deferred(player)
	await process_frame
	await process_frame
	player.play()
	for i in 30:
		await process_frame
	if "paused" in args:
		player.stream_paused = true
		await process_frame
	if "stop" in args:
		player.stop()
	if "wait" in args:
		await create_timer(0.3).timeout
	if "unpause" in args:
		player.stream_paused = false
		player.stop()
	if "free" in args:
		player.queue_free()
		await process_frame
		await process_frame
	if "rmbus" in args:
		AudioServer.remove_bus(AudioServer.get_bus_index("Runtime"))
		await process_frame
	quit()
