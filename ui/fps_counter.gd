class_name FpsCounter
extends CanvasLayer
## Small FPS readout in the top-left corner, toggled in the settings.

static var instance: FpsCounter
var label: Label
var clock := 0.0

static func apply(enabled: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if instance == null or not is_instance_valid(instance):
		instance = FpsCounter.new()
		tree.root.add_child.call_deferred(instance)
	instance.visible = enabled

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.position = Vector2(10,8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",15)
	label.add_theme_color_override("font_color",Color("#9cf29a"))
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",4)
	add_child(label)

func _process(delta: float) -> void:
	clock -= delta
	if not visible or clock > 0.0:
		return
	clock = .25
	label.text = "FPS %d" % roundi(Engine.get_frames_per_second())
