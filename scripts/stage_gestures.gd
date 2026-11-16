extends Control

const GESTURES := ["Рука вверх", "В такт", "Хлопки", "Перед дропом"]
const GESTURES_EN := ["Hand up", "To the beat", "Clap", "Before the drop"]
const SECTOR := PI * 0.5

var game: NightGame
var gesture := -1
var elapsed := 0.0
var beat_length := 0.5
var lead_in := 0.3
var last_clap := -1
var clap := AudioStreamPlayer.new()

func _init(night_game: NightGame) -> void:
	game = night_game
	hide()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clap.stream = preload("res://assets/party/stage_clap.mp3")
	clap.volume_db = -18
	add_child(clap)

func open() -> void:
	var player := game.home.player
	if game.intro.active or player.dj_rig == null or player.dj_rig.arms.size() != 2:
		return
	if player.view_model.active or game.home.party.hands_busy():
		return
	gesture = -1
	show()
	game.home.set_modal(true)

func close() -> void:
	hide()
	game.home.set_modal(false)

func radius() -> float:
	return minf(174.0, minf(size.x, size.y) * 0.44)

func choice_at(point: Vector2) -> int:
	var offset := point - size * 0.5
	if offset.length() < radius() * 0.31 or offset.length() > radius():
		return -1
	return posmod(roundi((offset.angle() + SECTOR) / SECTOR), GESTURES.size())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var choice := choice_at(event.position)
			close()
			if choice >= 0:
				play_gesture(choice)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			close()
		accept_event()

func _draw() -> void:
	var center := size * 0.5
	var outer := radius()
	var choice := choice_at(get_local_mouse_position())
	var font := get_theme_default_font()
	var labels := GESTURES_EN if TranslationServer.get_locale().begins_with("en") else GESTURES
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.27))
	for index in GESTURES.size():
		var angle := (index - 1) * SECTOR
		var points := PackedVector2Array()
		for step in range(25):
			points.append(center + Vector2.from_angle(angle + lerpf(-0.76, 0.76, step / 24.0)) * outer)
		for step in range(24, -1, -1):
			points.append(center + Vector2.from_angle(angle + lerpf(-0.76, 0.76, step / 24.0)) * outer * 0.31)
		draw_colored_polygon(points, Color("#376b83") if index == choice else Color("#202639"))
		var label_width := outer * 0.84
		var label_position := center + Vector2.from_angle(angle) * outer * 0.66 + Vector2(-label_width * 0.5, 5)
		draw_string(font, label_position, labels[index], HORIZONTAL_ALIGNMENT_CENTER, label_width, 16, Color.WHITE)
	draw_string(font, center + Vector2(-22, 5), "Esc", HORIZONTAL_ALIGNMENT_CENTER, 44, 15, Color("#cabfd0"))

func play_gesture(choice: int) -> void:
	gesture = choice
	elapsed = 0.0
	last_clap = -1
	beat_length = 0.5
	lead_in = 0.3
	var station := game.current_dj()
	if station.has_playback():
		var deck := station.audible_deck()
		var bpm: float = station.bpm_fields[deck].value * station.party.music[deck].pitch_scale
		beat_length = 60.0 / clampf(bpm, 65.0, 190.0)
		lead_in += fposmod(-station.dance_phase() * beat_length - lead_in, beat_length)

## Pose the same arms the player and mirror cameras already render.
func pose(player: Player, delta: float) -> void:
	if gesture < 0:
		return
	if player.view_model.active or player.action_amount > 0.01 or player.collapsed or player.vomiting:
		gesture = -1
		return
	elapsed += delta
	var duration := lead_in + beat_length * 8.0
	if elapsed >= duration:
		gesture = -1
		return
	var weight := smoothstep(lead_in - 0.3, lead_in, elapsed) * (1.0 - smoothstep(duration - 0.48, duration, elapsed))
	var phase := (elapsed - lead_in) / beat_length
	var pulse := cos(phase * TAU)
	var rig := player.dj_rig
	var chest_roll := 0.045 * pulse if gesture == 1 else 0.018
	rig.rotate_local("Spine", Vector3(-0.035, 0.0, chest_roll) * weight)
	var side := player.arm_side
	# The shoulder and elbow stay on the body. Only the wrist target is framed
	# relative to the eye, so the hand remains in view as the player looks around.
	var wrist := Vector3(0.15, 0.045, -0.34)
	match gesture:
		0:
			wrist += Vector3(sin(phase * PI * 0.5) * 0.018, pulse * 0.012, 0.0)
		1:
			wrist = Vector3(0.14 + pulse * 0.022, -0.055 + pulse * 0.045, -0.34)
		2:
			var apart := lerpf(0.026, 0.125, (1.0 - pulse) * 0.5)
			wrist = Vector3(apart, -0.12, -0.36)
			pose_arm(player, 1 - player.drink_arm, -side, Vector3(-wrist.x, wrist.y, wrist.z), weight)
			var hit := floori(phase)
			if hit >= 0 and hit > last_clap and weight > 0.5:
				last_clap = hit
				clap.pitch_scale = [1.0, 0.96, 1.04][hit % 3]
				clap.play()
		3:
			var sweep := smoothstep(-0.15, 0.24, elapsed - lead_in)
			wrist = Vector3(lerpf(0.17, 0.10, sweep), lerpf(-0.13, 0.055 + pulse * 0.025, sweep), -0.36)
	pose_arm(player, player.drink_arm, side, wrist, weight)

func pose_arm(player: Player, index: int, side: float, target: Vector3, weight: float) -> void:
	var rig := player.dj_rig
	var arm := rig.arms[index]
	var skeleton := rig.skeleton
	var idle := skeleton.get_bone_global_pose(arm.z).origin
	var reached := skeleton.to_local(player.camera.to_global(target))
	rig.point_arm(arm, idle.lerp(reached, weight), Vector3(side, -0.7, -0.18))
	var wrist := skeleton.get_bone_global_pose(arm.z).basis.orthonormalized()
	var finger_direction := Vector3(-signf(target.x) * 0.38, 0.88, -0.12) if gesture == 2 else Vector3(0, 0.95, -0.28)
	var desired := skeleton.global_basis.inverse() * player.camera.global_basis * finger_direction
	var turn := Quaternion(wrist.y, desired.normalized())
	var bend := minf(0.65, deg_to_rad(35.0) / maxf(turn.get_angle(), 0.001))
	rig.set_joint_rotation(arm.z, Basis(Quaternion.IDENTITY.slerp(turn, bend * weight)) * wrist)
