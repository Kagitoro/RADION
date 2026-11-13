class_name ScreenFX
extends CanvasLayer
## Full-screen state effects under the HUD: alcohol double vision, nausea and
## heaves, energy-drink rush. Gameplay code only sets targets; values ease here.

const SHADER := preload("res://assets/fx/screen_fx.gdshader")

var player: Player
var rect: ColorRect
var material: ShaderMaterial
var drunk := 0.0
var nausea := 0.0
var nausea_target := 0.0
var rush := 0.0
var heave := 0.0

func _init(owner_player: Player) -> void:
	player = owner_player
	layer = -1
	name = "ScreenFX"

func _ready() -> void:
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	rect.material = material
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.visible = false

func _process(delta: float) -> void:
	var drunk_target := smoothstep(.25,1.0,player.intoxication)
	drunk = move_toward(drunk,drunk_target,delta*.3)
	nausea = move_toward(nausea,nausea_target,delta*(1.4 if nausea_target>nausea else .45))
	var rush_target := clampf(player.energy_boost/Balance.ENERGY_DRINK_DURATION,0,1)
	rush_target = smoothstep(.75,1.0,rush_target)*.9+.1*float(player.energy_boost>0)
	rush = move_toward(rush,rush_target,delta*(2.5 if rush_target>rush else .6))
	heave = move_toward(heave,0.0,delta*2.2)
	var on := drunk>.002 or nausea>.002 or rush>.002 or heave>.002
	rect.visible = on
	if not on:
		return
	material.set_shader_parameter("drunk",drunk)
	material.set_shader_parameter("nausea",nausea)
	material.set_shader_parameter("rush",rush)
	material.set_shader_parameter("heave",heave)

## One sharp lurch, e.g. a retch.
func pulse_heave(amount := 1.0) -> void:
	heave = maxf(heave,amount)
