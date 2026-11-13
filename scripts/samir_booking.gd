extends Node

const CLIPS := ["you","samir","you2","samir2"]
const LINES := [
	"Кир прислал меня. Сказал, что нужен человек за пультом.",
	"Ты на подмену? Хорошо. Опенер пропал, а зал уже заполняется.",
	"Треки со мной. Куда идти?",
	"Ступени справа. Сначала разогрей зал. Если к финалу будут танцевать — поговорим о следующем вечере.",
]
var game: NightGame
var camera: Camera3D
var caption: Label
var voice: AudioStreamPlayer
var worker: Node3D
var index := -1
var clock := 0.0
var next_line := 0.0

func start(owner: NightGame, samir: Node3D) -> void:
	game = owner
	worker = samir
	game.home.set_modal(true)
	camera = Camera3D.new()
	game.home.add_child(camera)
	var player_camera := game.home.player.camera
	camera.global_transform = player_camera.global_transform
	camera.cull_mask = player_camera.cull_mask
	camera.fov = player_camera.fov
	camera.make_current()
	caption = UIKit.label("",22)
	game.home.hud.root.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	caption.offset_left = -315
	caption.offset_right = 315
	caption.offset_top = -150
	caption.offset_bottom = -70
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_outline_color",Color.BLACK)
	caption.add_theme_constant_override("outline_size",8)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	advance()

func _process(delta: float) -> void:
	if camera==null:
		return
	clock += delta
	camera.fov = move_toward(camera.fov,51.0,delta*24.0)
	var face := worker.global_position+Vector3.UP*1.60
	var focus := camera.global_position+(-camera.global_basis.z)*camera.global_position.distance_to(face)
	camera.look_at(focus.lerp(face,minf(1.0,delta*4.0)))
	if clock>=next_line and not voice.playing:
		advance()

func advance() -> void:
	index += 1
	if index>=LINES.size():
		finish()
		return
	caption.text = ("%s\n%s" % [tr("Ты") if index%2==0 else tr("Самир"),tr(LINES[index])])
	voice.stream = load("res://assets/story/voice/booking_%s.mp3" % CLIPS[index]) as AudioStream
	voice.play()
	next_line = clock+voice.stream.get_length()+.35

func finish() -> void:
	game.intro.confirm_booking()
	game.home.player.camera.make_current()
	game.home.set_modal(false)
	caption.queue_free()
	camera.queue_free()
	queue_free()
