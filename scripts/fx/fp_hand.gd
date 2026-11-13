class_name FPHand
extends Node3D
## First-person hand and forearm: the skinned model assets/fp/arm.glb, posed
## through an invisible joint chain (the "drivers") that poses, grip fitting and
## code-built clips act on. Baked clips key the bones directly instead.
## Local frame (right hand): wrist at the origin, fingers point along -Z,
## palm faces -X, the index finger is on top (+Y). The left hand is mirrored.
## `grip` holds the item; poses blend finger curls so items look really held.

const SKIN := Color("#c99570")
const SLEEVE := Color("#3b4057")
const CUFF := Color("#2b2f40")

## Finger name -> [knuckle position, segment lengths, radius]
const FINGERS := {
	"index": [Vector3(-.004,.027,-.083), [.041,.025,.021], .0088],
	"middle": [Vector3(-.003,.009,-.087), [.045,.028,.022], .0090],
	"ring": [Vector3(-.003,-.009,-.083), [.042,.026,.021], .0085],
	"pinky": [Vector3(-.004,-.026,-.074), [.032,.020,.018], .0075],
}

## Pose name -> finger name -> [curl per joint (radians)], thumb -> [swing, curl1, curl2].
const POSES := {
	"relaxed": {
		"index": [.35,.45,.30], "middle": [.42,.55,.35], "ring": [.50,.62,.38], "pinky": [.58,.68,.40],
		"thumb": [.35,.20,.25],
	},
	"bottle": {
		"index": [1.05,.95,.55], "middle": [1.08,1.0,.6], "ring": [1.12,1.02,.62], "pinky": [1.2,1.05,.62],
		"thumb": [.95,.55,.45],
	},
	"can": {
		"index": [.95,.9,.55], "middle": [1.0,.95,.58], "ring": [1.05,.98,.6], "pinky": [1.12,1.0,.6],
		"thumb": [.9,.5,.4],
	},
	"pinch": {
		"index": [.42,.28,.12], "middle": [.48,.34,.16], "ring": [1.15,1.25,.8], "pinky": [1.25,1.3,.85],
		"thumb": [.75,.55,.35],
	},
	"lighter": {
		"index": [.95,.95,.6], "middle": [1.05,1.0,.62], "ring": [1.15,1.05,.62], "pinky": [1.25,1.1,.64],
		"thumb": [.55,.15,.05],
	},
	"fist": {
		"index": [1.45,1.5,.9], "middle": [1.5,1.55,.95], "ring": [1.5,1.55,.95], "pinky": [1.5,1.5,.9],
		"thumb": [1.05,.8,.6],
	},
	"point": {
		"index": [.12,.12,.06], "middle": [1.35,1.4,.85], "ring": [1.4,1.45,.9], "pinky": [1.4,1.4,.85],
		"thumb": [.95,.7,.5],
	},
	"brace": {
		"index": [.12,.08,.05], "middle": [.1,.06,.04], "ring": [.14,.08,.05], "pinky": [.2,.1,.06],
		"thumb": [.2,.05,.05],
	},
}

var left := false
var grip: Node3D
## Wrist joint: the forearm hangs from here, so the hand can stay level
## around an item while the arm goes down toward the screen corner.
var forearm: Node3D
var wrist_bend := Vector3(.75,.35,0):
	set(value):
		wrist_bend = value
		if forearm!=null:
			forearm.rotation = value
			sync_bones()
var joints := {}
var thumb_base: Node3D
## Two poses and the blend between them; animated by the action player.
var pose_from := "relaxed"
var pose_to := "relaxed"
var blend := 0.0:
	set(value):
		blend = value
		apply_pose()
var blend_tween: Tween
## Poses fitted to the held item (see `fit_cylinder`); they replace POSES of the same name.
var fitted := {}
var skin_material: ShaderMaterial
var nail_material: ShaderMaterial
var sleeve_material: ShaderMaterial
var cuff_material: ShaderMaterial

const ARM_MODEL := preload("res://assets/fp/arm.glb")

## Skinned arm from assets/fp/arm.glb (tools/blender/build_fp_assets.py).
var arm: Node3D
var skeleton: Skeleton3D
## Bone index -> driver node, rest data and evaluation order (parents first).
var bone_driver := {}
var bone_rest_frame := {}
var bone_rest_basis := {}
var bone_order: Array[int] = []
var skeleton_basis := Basis.IDENTITY
## When an animation keys the bones directly the drivers stop writing to them.
var drive_bones := true

func _init(is_left := false) -> void:
	left = is_left
	name = "LeftHand" if left else "RightHand"
	if left:
		scale = Vector3(-1,1,1)
	skin_material = FPProps.view_material(SKIN,.55,0.0,FPProps.skin_texture())
	skin_material.set_shader_parameter("rim_amount",.14)
	skin_material.set_shader_parameter("sss",.12)
	skin_material.set_shader_parameter("uv_scale",Vector2(1,1))
	nail_material = FPProps.view_material(Color("#e8c2b0"),.25)
	nail_material.set_shader_parameter("clearcoat_amount",.5)
	sleeve_material = FPProps.view_material(SLEEVE,.88,0.0,FPProps.fabric_texture())
	sleeve_material.set_shader_parameter("uv_scale",Vector2(3,3))
	cuff_material = FPProps.view_material(CUFF,.9,0.0,FPProps.fabric_texture())
	cuff_material.set_shader_parameter("uv_scale",Vector2(6,2))
	build()
	apply_pose()

## The invisible joint chain below is the "driver" the poses, grip fitting and
## code animations work on; `sync_bones` copies it onto the skinned model.
func build() -> void:
	forearm = Node3D.new()
	forearm.name = "Forearm"
	forearm.position = Vector3(.004,-.004,.004)
	add_child(forearm)
	for finger in FINGERS:
		build_finger(finger)
	build_thumb()
	grip = Node3D.new()
	grip.name = "Grip"
	add_child(grip)
	if left:
		# Items stay unmirrored even though the hand is.
		grip.scale = Vector3(-1,1,1)
	build_arm()
	forearm.rotation = wrist_bend

func build_arm() -> void:
	arm = ARM_MODEL.instantiate() as Node3D
	arm.name = "Arm"
	add_child(arm)
	var surfaces := {"Skin":skin_material,"Nail":nail_material,"Sleeve":sleeve_material,"Cuff":cuff_material}
	for node in arm.find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		mesh_node.layers = FPViewModel.LAYER
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The hand never leaves the camera; skip culling against stale skinned bounds.
		mesh_node.extra_cull_margin = 1.0
		for index in mesh_node.mesh.get_surface_count():
			var source := mesh_node.mesh.surface_get_material(index)
			var key := source.resource_name if source!=null else ""
			if surfaces.has(key):
				mesh_node.set_surface_override_material(index,surfaces[key])
	skeleton = arm.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var frame := Transform3D.IDENTITY
	var node: Node = skeleton
	while node!=self:
		frame = (node as Node3D).transform*frame
		node = node.get_parent()
	skeleton_basis = frame.basis.orthonormalized()
	# Rest frames of the drivers: straight fingers, thumb swing 0, forearm unbent.
	for finger in joints:
		for joint in joints[finger]:
			(joint as Node3D).rotation = Vector3.ZERO
	set_thumb_swing(0.0)
	forearm.rotation = Vector3.ZERO
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		var driver: Node3D = null
		if bone_name=="hand":
			driver = self
		elif bone_name=="forearm":
			driver = forearm
		else:
			var parts := bone_name.split("_")
			if parts.size()==2 and joints.has(parts[0]):
				driver = joints[parts[0]][int(parts[1])-1]
		if driver==null:
			continue
		bone_driver[bone] = driver
		bone_rest_frame[bone] = driver_frame(driver).basis.inverse()
		bone_rest_basis[bone] = skeleton_basis*skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var pending := range(skeleton.get_bone_count())
	while not pending.is_empty():
		for bone in pending.duplicate():
			var parent := skeleton.get_bone_parent(bone)
			if parent<0 or bone_order.has(parent):
				bone_order.append(bone)
				pending.erase(bone)

func driver_frame(node: Node3D) -> Transform3D:
	var frame := Transform3D.IDENTITY
	while node!=self:
		frame = node.transform*frame
		node = node.get_parent()
	return frame

## Copies the driver chain onto the skeleton: each bone turns by the same
## amount its driver turned away from the rest pose (in hand space).
func sync_bones() -> void:
	if skeleton==null or not drive_bones:
		return
	var global := {}
	var to_skeleton := skeleton_basis.inverse()
	for bone in bone_order:
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis: Basis = global.get(parent,Basis.IDENTITY) if parent>=0 else Basis.IDENTITY
		var bone_global: Basis
		if bone_driver.has(bone):
			var hand_space: Basis = driver_frame(bone_driver[bone]).basis*bone_rest_frame[bone]*bone_rest_basis[bone]
			bone_global = to_skeleton*hand_space
		else:
			bone_global = parent_basis*skeleton.get_bone_rest(bone).basis
		global[bone] = bone_global
		skeleton.set_bone_pose_rotation(bone,(parent_basis.inverse()*bone_global).orthonormalized().get_rotation_quaternion())

func build_finger(finger: String) -> void:
	var data: Array = FINGERS[finger]
	var parent: Node3D = self
	var at: Vector3 = data[0]
	var chain: Array[Node3D] = []
	for index in range(3):
		var joint := Node3D.new()
		joint.name = "%s_%d" % [finger,index+1]
		joint.position = at
		parent.add_child(joint)
		chain.append(joint)
		parent = joint
		at = Vector3(0,0,-float(data[1][index]))
	joints[finger] = chain

func build_thumb() -> void:
	thumb_base = Node3D.new()
	thumb_base.name = "ThumbBase"
	thumb_base.position = Vector3(-.012,.03,-.026)
	add_child(thumb_base)
	var lengths := [.036,.030,.024]
	var parent: Node3D = thumb_base
	var at := Vector3.ZERO
	var chain: Array[Node3D] = []
	for index in range(3):
		var joint := Node3D.new()
		joint.name = "thumb_%d" % (index+1)
		joint.position = at
		parent.add_child(joint)
		chain.append(joint)
		parent = joint
		at = Vector3(0,0,-float(lengths[index]))
	joints["thumb"] = chain

func set_pose(target: String, duration := 0.0) -> void:
	pose_from = current_pose_name()
	pose_to = target
	if duration<=0.0:
		pose_from = target
		blend = 1.0
		return
	blend = 0.0
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(self,"blend",1.0,duration)

func current_pose_name() -> String:
	return pose_to if blend>=.5 else pose_from

## Animation tracks call this with a "from>to" pair string to start a blend.
func blend_pose(pair: String, duration := .22) -> void:
	var parts := pair.split(">")
	pose_from = parts[0]
	pose_to = parts[1]
	blend = 0.0
	if blend_tween!=null:
		blend_tween.kill()
	blend_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	blend_tween.tween_property(self,"blend",1.0,duration)

func apply_pose() -> void:
	if joints.is_empty():
		return
	var a: Dictionary = pose_data(pose_from)
	var b: Dictionary = pose_data(pose_to)
	var t := smoothstep(0.0,1.0,blend)
	for finger in FINGERS:
		var chain: Array = joints[finger]
		for index in range(3):
			var curl := lerpf(a[finger][index],b[finger][index],t)
			# Curl toward the palm (-X): positive rotation around +Y.
			(chain[index] as Node3D).rotation = Vector3(0,curl,0)
	var thumb: Array = joints["thumb"]
	var swing := lerpf(a.thumb[0],b.thumb[0],t)
	# The thumb starts pointing forward-down along the palm and swings across it;
	# fitted poses carry their own thumb frame.
	var from_frame: Basis = a.get("thumb_frame",thumb_frame(a.thumb[0]))
	var to_frame: Basis = b.get("thumb_frame",thumb_frame(b.thumb[0]))
	thumb_base.basis = Basis(from_frame.get_rotation_quaternion().slerp(to_frame.get_rotation_quaternion(),t))
	(thumb[0] as Node3D).rotation = Vector3(0,swing*.3,0)
	(thumb[1] as Node3D).rotation = Vector3(0,lerpf(a.thumb[1],b.thumb[1],t),0)
	(thumb[2] as Node3D).rotation = Vector3(0,lerpf(a.thumb[2],b.thumb[2],t),0)
	sync_bones()

func pose_data(pose_name: String) -> Dictionary:
	return fitted.get(pose_name,POSES[pose_name])

## Re-curls `pose_name` so the hand wraps a cylinder (hand-local `center`,
## `axis`, `radius`) and rests on its surface instead of sinking into it.
## Fingers keep the pose's natural curl ratios and close until they touch;
## the thumb is laid along the surface toward `thumb_side`.
func fit_cylinder(pose_name: String, center: Vector3, axis: Vector3, radius: float, thumb_side := Vector3.ZERO) -> void:
	fitted.erase(pose_name)
	var pose: Dictionary = POSES[pose_name].duplicate(true)
	pose_from = pose_name
	pose_to = pose_name
	blend = 1.0
	axis = axis.normalized()
	for finger in FINGERS:
		var data: Array = FINGERS[finger]
		var chain: Array = joints[finger]
		var natural: Array = pose[finger]
		var best := 0.0
		var amount := 0.0
		while amount<=1.35:
			var hit := false
			for index in range(3):
				(chain[index] as Node3D).rotation = Vector3(0,natural[index]*amount,0)
			for index in range(3):
				if touches(chain[index],data[1][index],data[2]*(1.0-index*.09),center,axis,radius):
					hit = true
					break
			if hit:
				break
			best = amount
			amount += .02
		pose[finger] = [natural[0]*best,natural[1]*best,natural[2]*best]
	var thumb: Array = joints["thumb"]
	var lengths := [.036,.030,.024]
	var natural_thumb: Array = pose.thumb
	# Aim the thumb along the item's surface, opposite the fingers, a little
	# toward the top, with its bending axis parallel to the item so it wraps it.
	var natural_frame := thumb_frame(natural_thumb[0])
	var natural_dir := -(natural_frame.z)
	var base := thumb_base.position-center
	var radial := (base-axis*base.dot(axis)).normalized()
	var tangent := axis.cross(radial).normalized()
	# `thumb_side` (hand-local) picks which way round the item the thumb goes.
	var prefer := thumb_side if thumb_side!=Vector3.ZERO else natural_dir
	if tangent.dot(prefer)<0.0:
		tangent = -tangent
	var lift := axis if axis.dot(natural_dir)>=0.0 else -axis
	var direction := (tangent*cos(.35)+lift*sin(.35)).normalized()
	var z := -direction
	var x := (radial-z*radial.dot(z)).normalized()
	var frame := Basis(x,z.cross(x),z).orthonormalized()
	pose["thumb_frame"] = frame
	thumb_base.basis = frame
	(thumb[0] as Node3D).rotation = Vector3.ZERO
	var swing := 0.0
	var tip1 := fit_joint(thumb[1],lengths[1],.0103,center,axis,radius,1.5)
	var tip2 := fit_joint(thumb[2],lengths[2],.0091,center,axis,radius,1.5)
	pose.thumb = [swing,tip1,tip2]
	fitted[pose_name] = pose
	apply_pose()

func thumb_frame(swing: float) -> Basis:
	return Basis.from_euler(Vector3(.55-swing*.35,-.35+swing*.75,-.6))

func set_thumb_swing(swing: float) -> void:
	thumb_base.basis = thumb_frame(swing)
	(joints["thumb"][0] as Node3D).rotation = Vector3(0,swing*.3,0)

## Largest curl (scanning from open, up to `limit`) at which the segment still clears the item.
func fit_joint(joint: Node3D, length: float, finger_radius: float, center: Vector3, axis: Vector3, radius: float, limit := 1.7) -> float:
	var best := -.35
	var curl := -.35
	while curl<=limit:
		joint.rotation = Vector3(0,curl,0)
		if touches(joint,length,finger_radius,center,axis,radius):
			break
		best = curl
		curl += .02
	joint.rotation = Vector3(0,best,0)
	return best

## True when the segment (sampled from step `first` of 5) dips into the item.
func touches(joint: Node3D, length: float, finger_radius: float, center: Vector3, axis: Vector3, radius: float, first := 1) -> bool:
	var frame := Transform3D.IDENTITY
	var node: Node = joint
	while node!=self:
		frame = (node as Node3D).transform*frame
		node = node.get_parent()
	for step in range(first,6):
		var point := frame*Vector3(0,0,-length*float(step)/5.0)
		var offset := point-center
		var across := offset-axis*offset.dot(axis)
		if across.length()<radius+finger_radius*.85:
			return true
	return false
