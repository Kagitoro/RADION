class_name TargetFrames
extends RefCounted
## Wireframe boxes that highlight the aimed and the selected item.

var target_frame: MeshInstance3D
var selected_frame: MeshInstance3D
const FRAME_EDGES = [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]
var home: Home

func _init(game_home: Home) -> void:
	home = game_home

func add_target_frame(color: Color) -> MeshInstance3D:
	var frame := MeshInstance3D.new()
	frame.mesh = ImmediateMesh.new()
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	frame.material_override = material
	home.add_child(frame)
	frame.hide()
	return frame

func frame_state(frame: MeshInstance3D, item: Dictionary) -> void:
	if item.is_empty() or bool(item.get("deleted",false)) or str(item.kind)=="floor":
		frame.hide()
		return
	var size := home.dimensions(item)
	var padding := .015
	if frame.get_meta("size", Vector3.ZERO) != size:
		var lines := frame.mesh as ImmediateMesh
		lines.clear_surfaces()
		var corners: Array[Vector3] = []
		for i in range(8):
			corners.append(Vector3(
				(size.x*.5+padding)*(-1.0 if (i&1)==0 else 1.0),
				-padding if (i&2)==0 else size.y+padding,
				(size.z*.5+padding)*(-1.0 if (i&4)==0 else 1.0)))
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for edge in FRAME_EDGES:
			lines.surface_add_vertex(corners[edge[0]])
			lines.surface_add_vertex(corners[edge[1]])
		lines.surface_end()
		frame.set_meta("size",size)
	frame.position = Vector3(float(item.x),float(item.y),float(item.z))
	frame.rotation.y = deg_to_rad(float(item.r))
	frame.show()

func update_target_frames() -> void:
	if target_frame == null or selected_frame == null:
		return
	if home.game_mode:
		target_frame.hide()
		selected_frame.hide()
		return
	if home.modal:
		target_frame.hide()
		selected_frame.hide()
		return
	var hit_id := home.aimed_id()
	if not home.held.is_empty():
		target_frame.hide()
		frame_state(selected_frame,home.held)
		return
	frame_state(selected_frame,home.records.get(home.selected,{}))
	frame_state(target_frame,home.records.get(hit_id,{}) if hit_id!=home.selected else {})
