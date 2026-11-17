extends RefCounted
## Editor snapshots carry only changes back to the generated gameplay scene.

const SCENE_PATH := "res://city_editable.scn"
const TARGET := &"radion_target"
const BASE_TRANSFORM := &"radion_base_transform"
const BASE_VISIBLE := &"radion_base_visible"

static func target_for(home: Node, node: Node) -> String:
	var indices: Array[String] = []
	var current := node
	while current != home and current != null:
		for id in home.nodes:
			if home.nodes[id] == current:
				return "item:" + String(id) + "/" + "/".join(indices)
		indices.push_front(str(current.get_index()))
		current = current.get_parent()
	return "tree:/" + "/".join(indices) if current == home else ""

static func resolve(home: Node, target: String) -> Node:
	var pieces := target.split("/")
	var node: Node = home
	if pieces[0].begins_with("item:"):
		node = home.nodes.get(pieces[0].trim_prefix("item:"))
	for piece in pieces.slice(1):
		if piece.is_empty():
			continue
		var index := piece.to_int()
		if not is_instance_valid(node) or index < 0 or index >= node.get_child_count():
			return null
		node = node.get_child(index)
	return node

static func apply(home: Node) -> void:
	if "--export-editable-world" in OS.get_cmdline_user_args() or not ResourceLoader.exists(SCENE_PATH):
		return
	var scene := ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		push_error("Cannot load editable city scene.")
		return
	var edited := scene.instantiate() as Node3D
	home.add_child(edited)
	var present := {}
	var additions: Array[Node] = []
	for node in edited.find_children("*", "", true, false):
		if node.has_meta(TARGET):
			present[String(node.get_meta(TARGET))] = node
		elif node.owner == edited and (node.get_parent() == edited or node.get_parent().has_meta(TARGET)):
			additions.append(node)
	var manifest: Dictionary = edited.get_meta("radion_manifest", {})
	var live_targets := {}
	for target in manifest:
		live_targets[target] = resolve(home, target)
	var changed := 0
	for target in manifest:
		var live: Node = live_targets[target]
		if not is_instance_valid(live):
			continue
		var node: Node = present.get(target)
		if node == null:
			remove_target(home, live)
			changed += 1
			continue
		if node is Node3D and live is Node3D:
			var original: Transform3D = node.get_meta(BASE_TRANSFORM)
			if not node.transform.is_equal_approx(original):
				apply_transform(home, live, node.transform)
				changed += 1
			if node.visible != bool(node.get_meta(BASE_VISIBLE)):
				live.visible = node.visible
				if not node.visible:
					remove_target(home, live)
				changed += 1
		if node is MeshInstance3D and live is MeshInstance3D:
			if node.material_override != null and not bool(node.get_meta("radion_preview_material", false)):
				live.material_override = node.material_override
	for addition in additions:
		var parent := addition.get_parent()
		var live_parent: Node = home
		if parent.has_meta(TARGET):
			live_parent = live_targets.get(String(parent.get_meta(TARGET)))
		if is_instance_valid(live_parent):
			addition.reparent(live_parent, false)
	home.scene_finish.sync_ceilings()
	edited.queue_free()
	if changed > 0 or not additions.is_empty():
		print("EDITABLE_WORLD applied=", changed, " additions=", additions.size())

static func apply_transform(home: Node, live: Node3D, pose: Transform3D) -> void:
	for id in home.nodes:
		if home.nodes[id] != live:
			continue
		var record: Dictionary = home.records[id]
		var position := pose.origin
		var size: Vector3 = home.vector(record.dimensions) * pose.basis.get_scale()
		record.x = position.x
		record.y = position.y
		record.z = position.z
		record.r = rad_to_deg(pose.basis.get_euler().y)
		record.w = size.x
		record.h = size.y
		record.d = size.z
		home.apply_item(id)
		return
	live.transform = pose

static func remove_target(home: Node, live: Node) -> void:
	for id in home.nodes:
		if home.nodes[id] == live:
			home.records[id].deleted = true
			home.apply_item(id)
			return
	if live is Node3D:
		live.hide()
	live.process_mode = Node.PROCESS_MODE_DISABLED
	for node in [live] + live.find_children("*", "", true, false):
		if node is CollisionObject3D:
			node.collision_layer = 0
			node.collision_mask = 0
