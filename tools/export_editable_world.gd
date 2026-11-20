extends SceneTree
## Rebuilds res://city_editable.scn from the game as it runs now, so the scene you
## edit in Godot matches what F5 shows. Edits already saved in the old scene are
## applied first (EditableWorld.apply) and become the new baseline.
##
## Run from the project folder (close the editor's copy of city_editable.scn first):
##   godot --path . --script res://tools/export_editable_world.gd
## Add --headless to skip the window.

const EditableWorld := preload("res://scripts/editable_world.gd")
## Gameplay-driven nodes that are rebuilt every run and must not be baked.
const SKIP_SCRIPTS := ["player.gd", "hud.gd", "party.gd", "night_game.gd", "scene_finish.gd"]

var manifest := {}
var tagged := 0

func _initialize() -> void:
	change_scene_to_file("res://home.tscn")
	for i in 120:
		await process_frame
	var home := current_scene
	var city := Node3D.new()
	city.name = "CityEditable"
	for index in home.get_child_count():
		var live := home.get_child(index)
		if skip(live):
			continue
		var copy := live.duplicate(0)
		city.add_child(copy)
		copy.name = live.name.validate_node_name().replace("@", "_")
		bind(home, live, copy, city)
	city.set_meta("radion_manifest", manifest)
	var packed := PackedScene.new()
	var error := packed.pack(city)
	if error == OK:
		error = ResourceSaver.save(packed, EditableWorld.SCENE_PATH, ResourceSaver.FLAG_COMPRESS)
	print("EXPORT_EDITABLE_WORLD nodes=", tagged, " result=", error_string(error))
	city.free()
	quit(0 if error == OK else 1)

func skip(node: Node) -> bool:
	if not node is Node3D and not node is WorldEnvironment:
		return true
	if node is Camera3D or node is CharacterBody3D:
		return true
	var script := node.get_script() as Script
	return script != null and script.resource_path.get_file() in SKIP_SCRIPTS

## Tags each copied node with the live node it stands for. Children are matched
## by order; anything that does not line up is dropped, so it can never come
## back as a stray "addition".
func bind(home: Node, live: Node, copy: Node, city: Node) -> void:
	var target := EditableWorld.target_for(home, live)
	# UI (dialogs, labels) belongs to gameplay scripts, not to the map.
	if target.is_empty() or copy is Window or copy is Control or copy is CanvasLayer:
		copy.free()
		return
	# Bake instanced scenes (house.glb...) as local nodes so the tags are saved.
	copy.scene_file_path = ""
	copy.owner = city
	copy.set_meta(EditableWorld.TARGET, target)
	if copy is GeometryInstance3D:
		strip_viewport_textures(copy)
	if copy is Node3D:
		copy.set_meta(EditableWorld.BASE_TRANSFORM, copy.transform)
		copy.set_meta(EditableWorld.BASE_VISIBLE, copy.visible)
	manifest[target] = true
	tagged += 1
	var live_children := live.get_children()
	var copy_children := copy.get_children()
	# duplicate() keeps child order (auto-generated "@" names may differ).
	var same := live_children.size() == copy_children.size()
	for index in copy_children.size():
		if same and live_children[index].get_class() == copy_children[index].get_class():
			bind(home, live_children[index], copy_children[index], city)
		else:
			copy_children[index].free()

## Mirrors and screens render through a SubViewport that only exists in the
## running game. In the saved scene that texture has no source (black surface,
## "Viewport Texture must be set" errors), so show plain glass instead; the game
## keeps its live material, the scene only carries the transform.
func strip_viewport_textures(geometry: GeometryInstance3D) -> void:
	var materials: Array[Material] = [geometry.material_override]
	if geometry is MeshInstance3D and geometry.mesh != null:
		for index in geometry.mesh.get_surface_count():
			materials.append(geometry.get_active_material(index))
	for material in materials:
		if material != null and uses_viewport_texture(material):
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.62, 0.66, 0.7)
			glass.metallic = 0.9
			glass.roughness = 0.08
			geometry.material_override = glass
			if geometry is MeshInstance3D:
				for index in geometry.get_surface_override_material_count():
					geometry.set_surface_override_material(index, null)
			return

static func uses_viewport_texture(material: Material) -> bool:
	if material is ShaderMaterial:
		for uniform in material.shader.get_shader_uniform_list() if material.shader else []:
			if material.get_shader_parameter(uniform.name) is ViewportTexture:
				return true
		return false
	for property in material.get_property_list():
		if property.type == TYPE_OBJECT and material.get(property.name) is ViewportTexture:
			return true
	return false
