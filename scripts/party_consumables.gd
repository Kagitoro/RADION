class_name PartyConsumables
extends RefCounted
## Beer, energy drinks and cigarettes in the player's hands.
## Each action is an Animation played on the first-person rig (FPViewModel):
## the item pivots are keyframed, hands are posed around them, the camera gets
## additive head motion and named events trigger sounds, particles and effects.
## A plain world copy of the item follows the body for the bathroom mirror.

## Valid while an action occupies the hands (Party.hands_busy()).
var hand_prop: Node3D
## Bottle model from assets/party used to dress the fridge and the bar.
var bottle_model: Node3D
var falling_bits: Array[Dictionary] = []
## Lit cigarette: viewmodel copy at the mouth and a world copy for the mirror.
var lip_view: Node3D
var lip_cigarette: Node3D
var ember_light: OmniLight3D
var wisp: GPUParticles3D
var ember_timer := 0.0
var cigarette_burn := 0.0
var ember_glow := 0.0
var action_audio := AudioStreamPlayer.new()
var sip_audio: AudioStreamWAV
var breath_audio: AudioStreamWAV
var sfx: Array[AudioStreamPlayer] = []
var drinks := 0
var smokes := 0
var party: Party
var reflected: Node3D
var held_item: Node3D
var lighter: Node3D
var flame_flicker: Tween

func _init(owner_node: Party) -> void:
	party = owner_node

## True while a lit cigarette exists (on the lips or in the hand).
func smoking() -> bool:
	return is_instance_valid(lip_view) or (is_instance_valid(held_item) and held_item.name=="Cigarette" and ember_glow>0.0)

func player() -> Player:
	return party.home.player

func view() -> FPViewModel:
	return party.home.player.view_model

# --- entry points -------------------------------------------------------------

func consume(beer: bool) -> void:
	var actor := player()
	if actor.collapsed or actor.vomiting or is_instance_valid(hand_prop):
		return
	if is_instance_valid(lip_view):
		if beer:
			GameEvents.notify(tr("Сначала потуши сигарету · K"))
		else:
			puff()
		return
	var shop = party.home.shop
	if beer:
		if shop.beer<=0:
			GameEvents.notify(tr("Пива нет · купи в Night Shop"))
			return
		shop.beer -= 1
	else:
		if party.cigarettes<=0:
			GameEvents.notify(tr("Сигареты закончились · купи в Night Shop"))
			return
		party.cigarettes -= 1
		cigarette_burn = 0.0
	shop.save_stock()
	if beer:
		drink_beer()
	else:
		light_cigarette()

## Called by StreetShop after it took a can from the stock.
func drink_energy() -> bool:
	var actor := player()
	if actor.collapsed or actor.vomiting or is_instance_valid(hand_prop):
		return false
	if is_instance_valid(lip_view):
		GameEvents.notify(tr("Сначала потуши сигарету · K"))
		return false
	energy_action()
	return true

func extinguish() -> void:
	if is_instance_valid(hand_prop) or not is_instance_valid(lip_view):
		return
	var actor := player()
	if actor.collapsed or actor.vomiting:
		drop_cigarette()
		return
	stub_out()

# --- shared plumbing ------------------------------------------------------------

func begin(beer_pose: bool) -> FPViewModel:
	var rig := view()
	if not rig.event.is_connected(on_event):
		rig.event.connect(on_event)
	if not rig.clip_finished.is_connected(on_finished):
		rig.clip_finished.connect(on_finished)
	hand_prop = rig.right
	var actor := player()
	actor.action_beer = beer_pose
	# The real body arm would double the viewmodel hand; the mirror still sees it.
	actor.camera.set_cull_mask_value(5,false)
	return rig

func on_finished(_clip: String) -> void:
	var rig := view()
	# A late signal from an older clip must not clear the props of a new one.
	if rig.anim.is_playing():
		return
	rig.right_pivot.visible = false
	rig.left_pivot.visible = false
	rig.retire_player()
	rig.clear_pivot(rig.right_pivot)
	rig.clear_pivot(rig.left_pivot)
	held_item = null
	lighter = null
	if flame_flicker!=null:
		flame_flicker.kill()
		flame_flicker = null
	if is_instance_valid(reflected):
		reflected.queue_free()
	reflected = null
	var actor := player()
	actor.camera.set_cull_mask_value(5,true)
	actor.action_amount = 0.0
	actor.action_look = Vector3.ZERO
	actor.action_shift = Vector3.ZERO
	actor.action_fov = 0.0
	hand_prop = null

func mirror_copy(item: Node3D, beer_pose: bool) -> void:
	var actor := player()
	reflected = item
	actor.action_grip.add_child(item)
	item.position = actor.held_item_offset(beer_pose)
	set_prop_layers(item,4)

func set_prop_layers(prop: Node3D, layers: int) -> void:
	for part in prop.find_children("*","GeometryInstance3D",true,false):
		part.layers = layers

func sound(sound_name: String, volume := -6.0, pitch := 1.0) -> void:
	if sfx.is_empty():
		for index in range(4):
			var stream := AudioStreamPlayer.new()
			party.add_child(stream)
			sfx.append(stream)
	var free_player: AudioStreamPlayer = sfx[0]
	for candidate in sfx:
		if not candidate.playing:
			free_player = candidate
			break
	free_player.stream = FPSounds.get_sound(sound_name)
	free_player.volume_db = volume
	free_player.pitch_scale = pitch*party.rng.randf_range(.95,1.05)
	free_player.play()

## Pivot position that puts `local_point` of an item (pivot space) on the lips.
## Drinks meet the lips a little further out so the bottle does not fill the view.
const DRINK_OFFSET := Vector3(.0,-.028,.015)

func at_mouth(local_point: Vector3, turn: Vector3, offset := Vector3.ZERO) -> Vector3:
	return view().mouth.position+offset-Basis.from_euler(turn)*local_point

func on_event(event_name: String) -> void:
	match event_name:
		"pop": pop_cap()
		"gulp":
			gulp_count += 1
			sound(["gulp","gulp_b","gulp_c"][gulp_count%3],-3)
		"burp": burp()
		"beer_effect": finish_sip()
		"ahh": sound("ahh",-9)
		"crack": crack_can()
		"energy_effect": party.home.shop.apply_energy()
		"crush":
			sound("can_crush",-6)
		"to_lips": place_on_lips()
		"take": take_from_lips()
		"strike": strike(false)
		"ignite": strike(true)
		"inhale": inhale()
		"flame_off": flame(false)
		"exhale": exhale()
		"ash": shed_ash()
		"throw": throw_cigarette()

# --- beer -------------------------------------------------------------------------

const BOTTLE_GRIP := .085

func drink_beer() -> void:
	var rig := begin(true)
	var bottle := FPProps.beer_bottle(true)
	bottle.position.y = -BOTTLE_GRIP
	rig.right_pivot.add_child(bottle)
	held_item = bottle
	rig.hold(rig.right,Vector3(.047,.004,.046),Vector3(0,0,0),Vector3(.95,.55,.1),"bottle",.0345)
	rig.right_pivot.visible = true
	var copy := FPProps.beer_bottle(false)
	copy.position.y = -BOTTLE_GRIP
	var holder := Node3D.new()
	holder.add_child(copy)
	mirror_copy(holder,true)
	var top := Vector3(0,.239-BOTTLE_GRIP,0)
	var hand_side := Vector3(.5,-1,.25)
	var show := FPViewModel.axis_turn(Vector3(-.08,1,.18),Vector3(1,0,.5))
	var popped := FPViewModel.axis_turn(Vector3(-.12,1,.08),Vector3(1,0,.5))
	# Bottle axis (base -> neck) for each moment of the drink: the base climbs as it empties.
	var sips := [Vector3(-.45,.0,1),Vector3(-.5,-.2,.95),Vector3(-.52,-.34,.9),Vector3(-.52,-.46,.85)]
	var turns := []
	for axis in sips:
		turns.append(FPViewModel.axis_turn(axis,hand_side))
	var clip := Animation.new()
	clip.length = 3.4
	var pivot := "Sway/Right"
	FPViewModel.track(clip,pivot+":position",[
		[0.0,Vector3(.30,-.50,-.30)],
		[.38,Vector3(.16,-.18,-.40)],
		[.55,Vector3(.162,-.176,-.40)],
		[.68,Vector3(.15,-.19,-.39)],
		[1.0,at_mouth(top,turns[0],DRINK_OFFSET)],
		[1.32,at_mouth(top,turns[1],DRINK_OFFSET)],
		[1.67,at_mouth(top,turns[2],DRINK_OFFSET)],
		[2.02,at_mouth(top,turns[3],DRINK_OFFSET)],
		[2.35,Vector3(.09,-.19,-.30)],
		[2.8,Vector3(.17,-.21,-.40)],
		[3.4,Vector3(.32,-.52,-.30)],
	])
	FPViewModel.track(clip,pivot+":rotation",[
		[0.0,Vector3(.35,0,-.25)],
		[.38,show],
		[.55,show+Vector3(-.06,0,.02)],
		[.68,popped],
		[1.0,turns[0]],
		[1.32,turns[1]],
		[1.67,turns[2]],
		[2.02,turns[3]],
		[2.35,FPViewModel.axis_turn(Vector3(-.2,1,.5),Vector3(1,-.3,.3))],
		[2.8,FPViewModel.axis_turn(Vector3(-.05,1,.1),Vector3(1,0,.6))],
		[3.4,Vector3(.3,0,-.28)],
	])
	FPViewModel.track(clip,pivot+"/Bottle/Liquid:scale",[
		[0.0,Vector3.ONE],[1.1,Vector3.ONE],[1.42,Vector3(1,.75,1)],[1.77,Vector3(1,.48,1)],[2.1,Vector3(1,.16,1)],[3.4,Vector3(1,.16,1)],
	])
	FPViewModel.track(clip,"../..:action_look",[
		[0.0,Vector3.ZERO],[.8,Vector3(.03,0,0)],[1.1,Vector3(.16,0,.02)],[1.67,Vector3(.32,0,.03)],
		[2.05,Vector3(.42,0,.04)],[2.4,Vector3(.0,0,0)],[2.6,Vector3(-.01,0,0)],[2.7,Vector3(.05,0,.015)],[3.0,Vector3(.02,0,0)],[3.4,Vector3.ZERO],
	])
	FPViewModel.track(clip,"../..:action_shift",[
		[0.0,Vector3.ZERO],[1.3,Vector3.ZERO],[1.37,Vector3(0,-.008,.004)],[1.52,Vector3.ZERO],
		[1.64,Vector3.ZERO],[1.71,Vector3(0,-.008,.004)],[1.86,Vector3.ZERO],
		[1.99,Vector3.ZERO],[2.06,Vector3(0,-.008,.004)],[2.2,Vector3.ZERO],[2.6,Vector3.ZERO],[2.67,Vector3(0,.012,-.006)],[2.85,Vector3(0,.004,-.002)],[3.3,Vector3.ZERO],
	])
	FPViewModel.track(clip,"../..:action_amount",[[0.0,0.0],[1.0,1.0],[2.1,1.0],[2.45,.25],[3.4,0.0]])
	FPViewModel.events(clip,[[.55,"pop"],[1.34,"gulp"],[1.69,"gulp"],[2.04,"gulp"],[2.1,"beer_effect"],[2.62,"burp"]])
	rig.play(clip,"beer")

var gulp_count := 0

func burp() -> void:
	sound("burp",0)

func pop_cap() -> void:
	if not is_instance_valid(held_item):
		return
	var cap := held_item.get_node_or_null("Cap") as Node3D
	if cap==null:
		return
	sound("pop",-5)
	var start := cap.global_position
	FPEffects.fizz(party,start+Vector3.UP*.01,Color(.98,.92,.8))
	# The cap flips off the thumb in a little arc and drops out of view.
	cap.reparent(view().sway,true)
	var arc := party.create_tween().set_parallel()
	arc.tween_property(cap,"position",cap.position+Vector3(.12,.1,.05),.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(cap,"rotation",cap.rotation+Vector3(7,3,2),.5)
	arc.chain().tween_property(cap,"position",cap.position+Vector3(.2,-.5,.1),.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	arc.chain().tween_callback(cap.queue_free)

func finish_sip() -> void:
	drinks += 1
	player().drink_beer()
	GameEvents.notify(tr("Опьянение · %d%%") % roundi(player().intoxication*100))

# --- energy drink -----------------------------------------------------------------

const CAN_GRIP := .062

func energy_action() -> void:
	var rig := begin(true)
	var can := FPProps.energy_can(true)
	can.position.y = -CAN_GRIP
	can.rotation.y = -.5
	rig.right_pivot.add_child(can)
	held_item = can
	rig.hold(rig.right,Vector3(.045,.006,.044),Vector3(0,0,0),Vector3(.95,.55,.1),"can",.0335)
	rig.right_pivot.visible = true
	rig.left_pivot.visible = true
	var copy_root := Node3D.new()
	var copy := FPProps.energy_can(false)
	copy.position.y = -CAN_GRIP
	copy_root.add_child(copy)
	mirror_copy(copy_root,true)
	var top := Vector3(0,.133-CAN_GRIP,0)
	var show := Vector3(.10,-.15,-.34)
	var show_turn := FPViewModel.axis_turn(Vector3(-.05,1,.5),Vector3(1,0,.3))
	# The tab sits on the lid centre; the left index finger reaches it from below-left.
	var tab := show+Basis.from_euler(show_turn)*Vector3(0,.135-CAN_GRIP,.004)
	var reach := Vector3(.55,.5,-.65)
	rig.left.set_pose("point")
	rig.left.wrist_bend = Vector3(.5,-.3,0)
	place_fingertip(rig.left,reach,Vector3(0,-1,.2))
	var hand_side := Vector3(.5,-1,.25)
	var sips := [Vector3(-.45,.05,1),Vector3(-.5,-.28,.92),Vector3(-.52,-.44,.85)]
	var turns := []
	for axis in sips:
		turns.append(FPViewModel.axis_turn(axis,hand_side))
	var clip := Animation.new()
	clip.length = 3.6
	FPViewModel.track(clip,"Sway/Right:position",[
		[0.0,Vector3(.30,-.48,-.32)],[.38,show+Vector3(.01,-.01,0)],[.75,show],[.82,show+Vector3(0,-.006,0)],
		[1.0,show+Vector3(-.02,.01,.04)],
		[1.25,at_mouth(top,turns[0],DRINK_OFFSET)],[1.6,at_mouth(top,turns[1],DRINK_OFFSET)],[1.95,at_mouth(top,turns[2],DRINK_OFFSET)],
		[2.25,Vector3(.09,-.18,-.30)],[2.5,Vector3(.11,-.19,-.33)],[2.95,Vector3(.15,-.2,-.37)],[3.6,Vector3(.32,-.5,-.3)],
	])
	FPViewModel.track(clip,"Sway/Right:rotation",[
		[0.0,Vector3(.3,0,-.25)],[.38,show_turn+Vector3(-.05,0,0)],[.75,show_turn],[1.0,show_turn+Vector3(.2,0,0)],
		[1.25,turns[0]],[1.6,turns[1]],[1.95,turns[2]],
		[2.25,FPViewModel.axis_turn(Vector3(-.2,1,.4),Vector3(1,-.3,.3))],[2.5,FPViewModel.axis_turn(Vector3(-.1,1,.3),Vector3(1,0,.3))],
		[2.95,FPViewModel.axis_turn(Vector3(.1,1,.1),Vector3(1,0,.6))],[3.6,Vector3(.3,0,-.3)],
	])
	FPViewModel.track(clip,"Sway/Left:position",[
		[0.0,tab+Vector3(-.25,-.3,.05)],[.35,tab+Vector3(-.08,-.08,.04)],[.58,tab+Vector3(-.006,.012,.008)],
		[.72,tab+Vector3(0,.002,0)],[.8,tab+Vector3(.002,.016,.006)],[.98,tab+Vector3(-.1,-.12,.04)],
		[1.3,tab+Vector3(-.3,-.36,.06)],[3.6,tab+Vector3(-.3,-.36,.06)],
	])
	FPViewModel.track(clip,"Sway/Right/Can/Tab:rotation",[[0.0,Vector3.ZERO],[.74,Vector3.ZERO],[.8,Vector3(-1.25,0,0)],[1.0,Vector3(-.35,0,0)]])
	FPViewModel.steps(clip,"Sway/Right/Can/Hole:visible",[[0.0,false],[.77,true]])
	FPViewModel.steps(clip,"Sway/Left:visible",[[0.0,true],[1.3,false]])
	FPViewModel.track(clip,"Sway/Right/Can/Body:scale",[[0.0,Vector3.ONE],[2.42,Vector3.ONE],[2.55,Vector3(.86,.93,.78)],[2.7,Vector3(.83,.9,.74)]])
	FPViewModel.track(clip,"../..:action_look",[
		[0.0,Vector3.ZERO],[.6,Vector3(-.04,0,0)],[1.0,Vector3(.02,0,0)],[1.3,Vector3(.2,0,.02)],
		[1.95,Vector3(.42,0,.03)],[2.3,Vector3(-.02,0,0)],[2.7,Vector3.ZERO],
	])
	FPViewModel.track(clip,"../..:action_shift",[
		[0.0,Vector3.ZERO],[1.3,Vector3.ZERO],[1.36,Vector3(0,-.008,.004)],[1.5,Vector3.ZERO],
		[1.62,Vector3.ZERO],[1.68,Vector3(0,-.008,.004)],[1.82,Vector3.ZERO],
		[1.94,Vector3.ZERO],[2.0,Vector3(0,-.008,.004)],[2.14,Vector3.ZERO],
	])
	FPViewModel.track(clip,"../..:action_fov",[[0.0,0.0],[2.1,0.0],[2.22,7.0],[3.6,0.0]])
	FPViewModel.track(clip,"../..:action_amount",[[0.0,0.0],[1.25,1.0],[2.0,1.0],[2.35,.2],[3.6,0.0]])
	FPViewModel.calls(clip,"Sway/Right/RightHand","blend_pose",[[2.4,["can>fist"]],[2.9,["fist>can"]]])
	FPViewModel.events(clip,[[.77,"crack"],[1.33,"gulp"],[1.65,"gulp"],[1.97,"gulp"],[2.15,"energy_effect"],[2.47,"crush"]])
	rig.play(clip,"energy")

## Aims a hand's index finger along `reach` with the palm toward `palm`,
## and shifts the hand so the fingertip sits on the pivot origin.
func place_fingertip(hand: FPHand, reach: Vector3, palm: Vector3) -> void:
	var z := -reach.normalized()
	var x := (palm-z*palm.dot(z)).normalized()
	var turn := Basis(x,z.cross(x),z)
	hand.rotation = turn.get_euler()
	var tip := Vector3(-.012,.027,-.168)
	if hand.left:
		tip.x = -tip.x
	hand.position = -(turn*tip)

func crack_can() -> void:
	if not is_instance_valid(held_item):
		return
	sound("can_open",-5)
	var tab := held_item.get_node("Tab") as Node3D
	FPEffects.fizz(party,tab.global_position+Vector3.UP*.006)

# --- cigarette ----------------------------------------------------------------------

## Cigarette in the right hand: between index and middle finger, filter toward the palm.
const CIG_IN_HAND := Vector3(-.048,.018,-.118)
const CIG_HAND_TURN := Vector3(0,-PI*.5,0)
## Hand turned so the palm faces the lips and the fingers point up-left.
const HAND_AT_LIPS := Vector3(.1,PI*.5,-.45)
## Cigarette resting on the lips, relative to the mouth anchor.
const LIPS_TURN := Vector3(-.24,-.14,0)
const FILTER_SEAT := Vector3(0,0,.009)

func cigarette_pivot_at_lips() -> Vector3:
	return at_mouth(CIG_IN_HAND,HAND_AT_LIPS)

func setup_cigarette_hand(rig: FPViewModel) -> void:
	rig.hold(rig.right,Vector3.ZERO,Vector3.ZERO,Vector3(.4,.2,.0),"pinch")
	rig.right_pivot.visible = true

func light_cigarette() -> void:
	var rig := begin(false)
	setup_cigarette_hand(rig)
	var item := FPProps.cigarette(true)
	item.position = CIG_IN_HAND
	item.rotation = CIG_HAND_TURN
	rig.right_pivot.add_child(item)
	held_item = item
	FPProps.set_cigarette_burn(item,0.0,0.0)
	lighter = FPProps.lighter(true)
	lighter.position.y = -.03
	rig.left_pivot.add_child(lighter)
	rig.hold(rig.left,Vector3(-.036,.012,.05),Vector3.ZERO,Vector3(.95,-.55,-.1),"lighter")
	rig.left_pivot.visible = true
	var copy := FPProps.cigarette(false)
	mirror_copy(copy,false)
	var lips := cigarette_pivot_at_lips()
	# Tip of the cigarette once it rests on the lips (Sway space); the flame licks it.
	var tip := rig.mouth.position+Basis.from_euler(LIPS_TURN)*(FILTER_SEAT+Vector3(0,0,-.086))
	var flame_tip := Vector3(-.004,.101-.03+.006,0)
	var lighter_at := tip-flame_tip
	var cup := tip+Vector3(.075,-.035,.06)
	var cup_turn := Vector3(.1,.45,-.35)
	var clip := Animation.new()
	clip.length = 4.2
	FPViewModel.track(clip,"Sway/Right:position",[
		[0.0,Vector3(.2,-.42,-.2)],[.38,lips+Vector3(.03,-.06,-.03)],[.55,lips],[.62,lips+Vector3(0,0,.004)],
		[.95,cup],[1.6,cup+Vector3(-.004,.003,0)],[2.4,cup+Vector3(-.003,.002,0)],[2.9,Vector3(.3,-.5,-.26)],
	])
	FPViewModel.track(clip,"Sway/Right:rotation",[
		[0.0,Vector3(.4,.6,.2)],[.3,HAND_AT_LIPS+Vector3(-.2,0,0)],[.55,HAND_AT_LIPS],
		[.95,cup_turn],[2.4,cup_turn],[2.9,Vector3(.5,.6,.4)],
	])
	FPViewModel.calls(clip,"Sway/Right/RightHand","blend_pose",[[.6,["pinch>can"]],[2.45,["can>relaxed"]]])
	FPViewModel.track(clip,"Sway/Left:position",[
		[0.0,lighter_at+Vector3(-.2,-.32,.08)],[.45,lighter_at+Vector3(-.08,-.12,.03)],[.85,lighter_at+Vector3(-.01,-.025,0)],
		[1.0,lighter_at],[1.06,lighter_at+Vector3(0,-.004,0)],[1.2,lighter_at],
		[1.42,lighter_at+Vector3(0,-.004,0)],[1.5,lighter_at],[2.35,lighter_at+Vector3(.002,.002,0)],
		[2.55,lighter_at+Vector3(-.04,-.07,.0)],[3.0,lighter_at+Vector3(-.22,-.36,.08)],
	])
	FPViewModel.track(clip,"Sway/Left:rotation",[
		[0.0,Vector3(.3,0,.3)],[.85,Vector3(0,-.2,.04)],[2.4,Vector3(0,-.2,.04)],[3.0,Vector3(.3,0,.35)],
	])
	FPViewModel.track(clip,"Sway/Left/Lighter/Wheel:rotation",[
		[0.0,Vector3(0,0,PI*.5)],[1.0,Vector3(0,0,PI*.5)],[1.08,Vector3(4,0,PI*.5)],[1.42,Vector3(4,0,PI*.5)],[1.5,Vector3(8,0,PI*.5)],
	],false)
	FPViewModel.steps(clip,"Sway/Left:visible",[[0.0,true],[3.0,false]])
	FPViewModel.track(clip,"../..:action_look",[
		[0.0,Vector3.ZERO],[.5,Vector3(-.06,0,0)],[1.0,Vector3(-.16,0,0)],[2.3,Vector3(-.15,0,.02)],
		[2.9,Vector3(-.05,0,0)],[3.3,Vector3(.08,-.03,0)],[4.2,Vector3.ZERO],
	])
	FPViewModel.track(clip,"../..:action_amount",[[0.0,0.0],[.55,1.0],[.9,.6],[2.6,.5],[3.0,0.0]])
	FPViewModel.events(clip,[[.55,"to_lips"],[1.03,"strike"],[1.45,"ignite"],[1.6,"inhale"],[2.45,"flame_off"],[3.05,"exhale"]])
	rig.play(clip,"light")
	smokes += 1

## N with a cigarette on the lips: take it, drag, exhale, flick ash, put it back.
func puff() -> void:
	var rig := begin(false)
	setup_cigarette_hand(rig)
	var lips := cigarette_pivot_at_lips()
	var away := Vector3(.13,-.12,-.29)
	var away_turn := Vector3(.3,1.05,.75)
	var clip := Animation.new()
	clip.length = 3.2
	FPViewModel.track(clip,"Sway/Right:position",[
		[0.0,Vector3(.26,-.46,-.24)],[.3,lips+Vector3(.05,-.08,-.05)],[.5,lips],[1.3,lips+Vector3(0,-.002,.002)],
		[1.65,away],[1.92,away+Vector3(0,.004,0)],[1.98,away+Vector3(.006,-.012,0)],[2.1,away],
		[2.45,lips+Vector3(.01,-.02,-.02)],[2.62,lips],[3.2,Vector3(.28,-.48,-.25)],
	])
	FPViewModel.track(clip,"Sway/Right:rotation",[
		[0.0,Vector3(.4,.6,.2)],[.3,HAND_AT_LIPS+Vector3(-.2,0,0)],[.5,HAND_AT_LIPS],[1.3,HAND_AT_LIPS],
		[1.65,away_turn],[1.92,away_turn],[1.98,away_turn+Vector3(0,0,-.25)],[2.1,away_turn],
		[2.45,HAND_AT_LIPS+Vector3(-.1,0,0)],[2.62,HAND_AT_LIPS],[3.2,Vector3(.5,.6,.4)],
	])
	FPViewModel.track(clip,"../..:action_look",[
		[0.0,Vector3.ZERO],[.5,Vector3(-.06,0,0)],[1.3,Vector3(-.05,0,0)],[1.7,Vector3(.06,-.04,0)],
		[2.3,Vector3(-.02,-.01,0)],[2.62,Vector3(-.04,0,0)],[3.2,Vector3.ZERO],
	])
	FPViewModel.track(clip,"../..:action_amount",[[0.0,0.0],[.5,1.0],[1.3,1.0],[1.7,.3],[2.4,.3],[2.62,1.0],[3.2,0.0]])
	FPViewModel.events(clip,[[.5,"take"],[.55,"inhale"],[1.62,"exhale"],[1.97,"ash"],[2.62,"to_lips"]])
	rig.play(clip,"puff")
	smokes += 1

## K: take the cigarette from the lips and flick it away.
func stub_out() -> void:
	var rig := begin(false)
	setup_cigarette_hand(rig)
	var lips := cigarette_pivot_at_lips()
	var clip := Animation.new()
	clip.length = 1.9
	var wind := Vector3(.16,-.17,-.3)
	FPViewModel.track(clip,"Sway/Right:position",[
		[0.0,Vector3(.26,-.46,-.24)],[.3,lips+Vector3(.05,-.08,-.05)],[.48,lips],
		[.85,wind],[.98,wind+Vector3(.02,.03,-.08)],[1.1,wind+Vector3(.03,.02,-.1)],[1.9,Vector3(.3,-.5,-.28)],
	])
	FPViewModel.track(clip,"Sway/Right:rotation",[
		[0.0,Vector3(.4,.6,.2)],[.48,HAND_AT_LIPS],[.85,Vector3(.4,1.2,.6)],[.98,Vector3(-.2,1.0,.2)],[1.9,Vector3(.5,.6,.4)],
	])
	FPViewModel.track(clip,"../..:action_amount",[[0.0,0.0],[.48,1.0],[.9,.3],[1.9,0.0]])
	FPViewModel.calls(clip,"Sway/Right/RightHand","blend_pose",[[.97,["pinch>relaxed"]]])
	FPViewModel.events(clip,[[.48,"take"],[.98,"throw"]])
	rig.play(clip,"stub")

func place_on_lips() -> void:
	if not is_instance_valid(held_item):
		return
	var rig := view()
	lip_view = held_item
	held_item = null
	lip_view.reparent(rig.mouth,false)
	lip_view.position = Basis.from_euler(LIPS_TURN)*FILTER_SEAT
	lip_view.rotation = LIPS_TURN
	# The mirror copy moves to the mouth too.
	var actor := player()
	if is_instance_valid(reflected):
		lip_cigarette = reflected
		reflected = null
	if not is_instance_valid(lip_cigarette):
		lip_cigarette = FPProps.cigarette(false)
		set_prop_layers(lip_cigarette,4)
		actor.mouth_anchor().add_child(lip_cigarette)
	if lip_cigarette.get_parent()!=actor.mouth_anchor():
		lip_cigarette.reparent(actor.mouth_anchor(),false)
	lip_cigarette.position = FILTER_SEAT if is_instance_valid(actor.dj_rig) else Vector3(.014,-.064,-.100)
	lip_cigarette.rotation = Vector3.ZERO
	ember_timer = 0.0

func take_from_lips() -> void:
	if not is_instance_valid(lip_view):
		return
	var rig := view()
	held_item = lip_view
	lip_view = null
	held_item.reparent(rig.right_pivot,false)
	held_item.position = CIG_IN_HAND
	held_item.rotation = CIG_HAND_TURN
	if is_instance_valid(lip_cigarette):
		reflected = lip_cigarette
		lip_cigarette = null
		reflected.reparent(player().action_grip,false)
		reflected.position = player().held_item_offset(false)
		reflected.rotation = Vector3.ZERO

func strike(lit: bool) -> void:
	if not is_instance_valid(lighter):
		return
	sound("lighter_strike",-8)
	var nozzle := lighter.to_global(Vector3(-.004,.09,0))
	FPEffects.sparks(party,nozzle,player().camera.global_basis*Vector3(0,1,.2),10 if lit else 16,.6)
	if lit:
		sound("flame_on",-10)
		flame(true)

func flame(on: bool) -> void:
	if not is_instance_valid(lighter):
		return
	var fire := lighter.get_node("Flame") as MeshInstance3D
	var light := lighter.get_node("Light") as OmniLight3D
	fire.visible = on
	if flame_flicker!=null:
		flame_flicker.kill()
	if not on:
		light.light_energy = 0.0
		return
	flame_flicker = party.create_tween().set_loops()
	for index in range(6):
		flame_flicker.tween_property(light,"light_energy",party.rng.randf_range(.18,.3),.06)

func inhale() -> void:
	sound("inhale",-9)
	var item := held_item if is_instance_valid(held_item) else lip_view
	if not is_instance_valid(item):
		return
	var glow := party.create_tween()
	glow.tween_property(self,"ember_glow",1.0,.55).set_trans(Tween.TRANS_SINE)
	glow.tween_interval(.2)
	glow.tween_property(self,"ember_glow",.12,1.1)
	var burn := party.create_tween()
	burn.tween_property(self,"cigarette_burn",minf(1.0,cigarette_burn+.13),.8)

func exhale() -> void:
	sound("exhale",-11)
	var camera := player().camera
	var mouth := camera.global_transform*Vector3(0,-.07,-.16)
	var forward := camera.global_basis*Vector3(.12,-.12,-1)
	FPEffects.exhale(party,mouth,forward,1.0)

func shed_ash() -> void:
	var item := held_item if is_instance_valid(held_item) else lip_view
	if not is_instance_valid(item):
		return
	var ash := item.get_node("Ash") as Node3D
	if not ash.visible:
		return
	spill_bits(ash.global_position,false,6)
	cigarette_burn = minf(1.0,cigarette_burn+.03)

func throw_cigarette() -> void:
	if not is_instance_valid(held_item):
		return
	sound("flick",-8)
	var butt := held_item
	held_item = null
	var start := butt.global_transform
	var world_butt := FPProps.cigarette(false)
	party.add_child(world_butt)
	world_butt.global_transform = start
	FPProps.set_cigarette_burn(world_butt,cigarette_burn,.6)
	butt.queue_free()
	var camera := player().camera
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var space := party.get_world_3d().direct_space_state
	var land := start.origin+forward*1.3+Vector3.DOWN*3.0
	var ray := PhysicsRayQueryParameters3D.create(start.origin+forward*1.3+Vector3.UP*.3,land,1,[player().get_rid()])
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		land = hit.position+Vector3.UP*.005
	var peak := start.origin.lerp(land,.4)+Vector3.UP*.35
	var arc := party.create_tween()
	arc.tween_method(func(t: float):
		if is_instance_valid(world_butt):
			world_butt.global_position = start.origin.lerp(peak,t).lerp(peak.lerp(land,t),t)
			world_butt.rotate_object_local(Vector3.RIGHT,.25)
	,0.0,1.0,.55)
	arc.tween_callback(func():
		if not is_instance_valid(world_butt):
			return
		world_butt.global_rotation = Vector3(0,party.rng.randf_range(0,TAU),PI*.5)
		world_butt.rotation.z = 0
		world_butt.rotation.x = 0
		FPEffects.sparks(party,land+Vector3.UP*.01,Vector3.UP,12,.5)
	)
	arc.tween_interval(12.0)
	arc.tween_callback(world_butt.queue_free)
	clear_lip_state()
	GameEvents.notify(tr("Сигарета потушена · осталось %d") % party.cigarettes)

## Removes the lit cigarette without an animation (used when collapsing).
func drop_cigarette() -> void:
	if not is_instance_valid(lip_view):
		return
	# It falls from the lips to the floor like a flicked butt.
	held_item = lip_view
	lip_view = null
	throw_cigarette()

func clear_lip_state() -> void:
	if is_instance_valid(lip_cigarette):
		lip_cigarette.queue_free()
	if is_instance_valid(reflected):
		reflected.queue_free()
	if is_instance_valid(wisp):
		wisp.emitting = false
		var dying := wisp
		party.get_tree().create_timer(3.0).timeout.connect(dying.queue_free)
	wisp = null
	if is_instance_valid(ember_light):
		ember_light.queue_free()
	ember_light = null
	lip_view = null
	lip_cigarette = null
	reflected = null
	ember_glow = 0.0
	player().action_amount = 0.0

## Per-frame update of the burning cigarette (called by Party._process).
func update_cigarette_length() -> void:
	var flicker := .06*sin(Time.get_ticks_msec()*.011)+.04*sin(Time.get_ticks_msec()*.023)
	var glow := clampf(ember_glow+flicker+.1,0,1)
	for item in [lip_view,lip_cigarette,held_item]:
		if is_instance_valid(item) and item.name=="Cigarette":
			FPProps.set_cigarette_burn(item,cigarette_burn,glow)
	var source := lip_view if is_instance_valid(lip_view) else (held_item if is_instance_valid(held_item) and held_item.name=="Cigarette" else null)
	if is_instance_valid(ember_light):
		ember_light.light_energy = glow*.05
	if source!=null and is_instance_valid(wisp):
		wisp.global_position = (source.get_node("Ember") as Node3D).global_position

## Keeps a thin smoke wisp rising from the ember (called a few times a second).
func ember_smoke() -> void:
	if not is_instance_valid(wisp):
		wisp = FPEffects.ember_wisp()
		party.add_child(wisp)
		wisp.emitting = true

# --- legacy world props and bits ------------------------------------------------------

func detail_surface(mesh: MeshInstance3D, dark: Color, light: Color, roughness: float) -> void:
	var key := dark.to_html()+light.to_html()
	if not party.detail_textures.has(key):
		var grain := FastNoiseLite.new()
		grain.frequency = .23
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([dark,light])
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.seamless = true
		texture.noise = grain
		texture.color_ramp = ramp
		party.detail_textures[key] = texture
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = Color.WHITE
	material.albedo_texture = party.detail_textures[key]
	material.roughness = roughness

## World bottle (fridge shelves, bar) at `item`'s origin, centred on its body.
func build_bottle(item: Node3D) -> void:
	var bottle := FPProps.beer_bottle(false)
	bottle.position.y = -.106
	bottle.scale = Vector3.ONE*(.264/.239)
	item.add_child(bottle)

func spill_bits(origin: Vector3, beer: bool, count: int) -> void:
	for index in range(count):
		if falling_bits.size()>=36:
			return
		var size := party.rng.randf_range(.003,.006) if beer else party.rng.randf_range(.0015,.004)
		var tint := Color("#b77a31") if beer else Color("#77716b").darkened(party.rng.randf_range(0,.45))
		var bit := party.oval(party,party.to_local(origin),Vector3(size,size*1.3,size),tint)
		var material := bit.material_override as StandardMaterial3D
		material.roughness = .13 if beer else .98
		var forward: Vector3 = -party.home.player.camera.global_basis.z
		var velocity := forward*party.rng.randf_range(.12,.35)+Vector3(party.rng.randf_range(-.15,.15),party.rng.randf_range(-.05,.1),party.rng.randf_range(-.14,.14))
		falling_bits.append({"node":bit,"velocity":velocity,"age":0.0,"beer":beer})

func update_falling_bits(delta: float) -> void:
	var space := party.get_world_3d().direct_space_state
	for index in range(falling_bits.size()-1,-1,-1):
		var entry := falling_bits[index]
		var bit: MeshInstance3D = entry.node
		entry.age += delta
		entry.velocity += Vector3.DOWN*delta*(8.0 if entry.beer else 3.4)
		var next: Vector3 = bit.global_position+entry.velocity*delta
		var ray := PhysicsRayQueryParameters3D.create(bit.global_position,next,1,[party.home.player.get_rid()])
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			bit.global_position = hit.position+normal*.0015
			bit.scale *= Vector3(1.75,.19,1.75)
			party.get_tree().create_timer(4.0 if entry.beer else 9.0).timeout.connect(bit.queue_free)
			falling_bits.remove_at(index)
		elif entry.age>2.2:
			bit.queue_free()
			falling_bits.remove_at(index)
		else:
			bit.global_position = next

## Legacy synthesized sip/breath, still used by Party for guests.
func action_sound(beer: bool) -> AudioStreamWAV:
	return FPSounds.get_sound("gulp" if beer else "exhale")
