class_name HouseOcclusion
extends RefCounted
## Occlusion culling for the house. Godot draws everything inside the camera
## frustum, so from the hall the whole street (≈1800 meshes, 2000+ draw calls)
## was rendered through the walls. Every solid wall gets a box occluder copied
## from its collision boxes; walls with doors and windows are already split into
## boxes around the openings, so the street still shows through them.
## Needs rendering/occlusion_culling/use_occlusion_culling (project.godot).

const NAME := "HouseOccluders"
## Boxes smaller than this face area (m²) are not worth an occluder.
const MIN_AREA := .35

static func build(home: Home) -> int:
	var old := home.get_node_or_null(NAME)
	if old!=null:
		old.free()
	var root := Node3D.new()
	root.name = NAME
	home.add_child(root)
	var count := 0
	for row in home.records.values():
		if str(row.kind)!="wall" or bool(row.deleted) or not bool(row.solid):
			continue
		var body: Node3D = home.bodies.get(str(row.id))
		if not is_instance_valid(body):
			continue
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider==null or not collider.shape is BoxShape3D:
				continue
			var size := (collider.shape as BoxShape3D).size
			var faces := [size.x*size.y,size.y*size.z,size.x*size.z]
			if faces.max()<MIN_AREA:
				continue
			var occluder := OccluderInstance3D.new()
			var box := BoxOccluder3D.new()
			box.size = size
			occluder.occluder = box
			root.add_child(occluder)
			occluder.global_transform = collider.global_transform
			count += 1
	return count
