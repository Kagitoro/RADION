@tool
extends EditorScenePostImportPlugin
## Import-time low-poly pass, so every model in the game shares the faceted look
## of the first-person props. Per file (Import dock or the .import file):
##   lowpoly/flat       flat shading: one normal per triangle (crisp facets)
##   lowpoly/detail     share of triangles to keep (1 = no simplification)
##   lowpoly/max_error  simplification stops before the shape deviates more than
##                      this share of the mesh size (keeps silhouettes intact)
## Node names, skins, bones and animations are untouched: only mesh surfaces are
## rebuilt. Meshes with blend shapes keep their topology (flat shading only).
## Normal maps are dropped (facets carry the shading) and materials are matte.

const SMALL_SURFACE := 120

func _get_import_options(path: String) -> void:
	add_import_option("lowpoly/flat",false)
	add_import_option_advanced(TYPE_FLOAT,"lowpoly/detail",1.0,PROPERTY_HINT_RANGE,"0.05,1,0.01")
	add_import_option_advanced(TYPE_FLOAT,"lowpoly/max_error",.05,PROPERTY_HINT_RANGE,"0.001,0.2,0.001")

func _pre_process(scene: Node) -> void:
	var flat := bool(get_option_value("lowpoly/flat"))
	var detail := clampf(float(get_option_value("lowpoly/detail")),.05,1.0)
	var max_error := float(get_option_value("lowpoly/max_error"))
	if not flat and detail>=1.0:
		return
	var before := 0
	var after := 0
	var done := {}
	for node in scene.find_children("*","ImporterMeshInstance3D",true,false):
		var mesh: ImporterMesh = node.get("mesh")
		if mesh==null or done.has(mesh):
			continue
		done[mesh] = true
		var counts := stylize(mesh,flat,detail,max_error)
		before += counts.x
		after += counts.y
	print("lowpoly: %d -> %d triangles (flat=%s detail=%.2f)" % [before,after,flat,detail])

## Rebuilds every surface; returns (triangles before, after).
static func stylize(mesh: ImporterMesh, flat: bool, detail: float, max_error: float) -> Vector2i:
	var surfaces := []
	for index in mesh.get_surface_count():
		surfaces.append({
			"primitive": mesh.get_surface_primitive_type(index),
			"arrays": mesh.get_surface_arrays(index),
			"material": mesh.get_surface_material(index),
			"name": mesh.get_surface_name(index),
			"format": mesh.get_surface_format(index),
		})
	# Blend shapes are stored per vertex; rebuilding the vertex list would break them.
	var morphs := mesh.get_blend_shape_count()>0
	var counts := Vector2i.ZERO
	mesh.clear()
	for surface in surfaces:
		var arrays: Array = surface.arrays
		var triangles: bool = surface.primitive==Mesh.PRIMITIVE_TRIANGLES
		counts.x += triangle_count(arrays)
		if triangles and not morphs:
			if detail<1.0:
				arrays = simplify(arrays,detail,max_error)
			if flat:
				arrays = flatten(arrays)
		counts.y += triangle_count(arrays)
		matte(surface.material)
		var flags: int = int(surface.format) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		mesh.add_surface(surface.primitive,arrays,[],{},surface.material,surface.name,flags)
	return counts

static func triangle_count(arrays: Array) -> int:
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices!=null and (indices as PackedInt32Array).size()>0:
		return (indices as PackedInt32Array).size()/3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3

## Fewer triangles via meshoptimizer: Godot builds a chain of LODs for the surface
## and the one closest to the requested share is kept as the mesh itself. A LOD
## whose error (relative to the mesh size) exceeds max_error is never used.
static func simplify(arrays: Array, detail: float, max_error: float) -> Array:
	if triangle_count(arrays)<SMALL_SURFACE:
		return arrays
	var tool := SurfaceTool.new()
	tool.create_from_arrays(arrays,Mesh.PRIMITIVE_TRIANGLES)
	tool.index()
	var indexed := tool.commit_to_arrays()
	var source := ImporterMesh.new()
	source.add_surface(Mesh.PRIMITIVE_TRIANGLES,indexed)
	# Merge normals up to 60°, split above 25°: keeps hard edges as edges.
	source.generate_lods(60.0,25.0,[])
	var target := triangle_count(indexed)*detail
	if OS.has_environment("LOWPOLY_DEBUG"):
		var info := []
		for lod in source.get_surface_lod_count(0):
			info.append("%.4f:%d" % [source.get_surface_lod_size(0,lod),source.get_surface_lod_indices(0,lod).size()/3])
		print("lowpoly-debug tris=%d lods=%s" % [triangle_count(indexed)," ".join(info)])
	var best := PackedInt32Array()
	for lod in source.get_surface_lod_count(0):
		if source.get_surface_lod_size(0,lod)>max_error:
			break
		var indices := source.get_surface_lod_indices(0,lod)
		best = indices
		if indices.size()/3<=target:
			break
	if best.size()<3:
		return arrays
	indexed[Mesh.ARRAY_INDEX] = best
	return indexed

## One normal per triangle: every corner gets its own vertex and the face normal.
static func flatten(arrays: Array) -> Array:
	var tool := SurfaceTool.new()
	tool.create_from_arrays(arrays,Mesh.PRIMITIVE_TRIANGLES)
	tool.deindex()
	var flat := tool.commit_to_arrays()
	var vertices: PackedVector3Array = flat[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for corner in range(0,vertices.size()-2,3):
		var a := vertices[corner]
		var b := vertices[corner+1]
		var c := vertices[corner+2]
		# Godot faces are clockwise when seen from the front.
		var normal := (c-a).cross(b-a)
		normal = normal.normalized() if normal.length_squared()>1e-20 else Vector3.UP
		normals[corner] = normal
		normals[corner+1] = normal
		normals[corner+2] = normal
	flat[Mesh.ARRAY_NORMAL] = normals
	# Facets do the shading: no tangents / normal maps.
	flat[Mesh.ARRAY_TANGENT] = null
	return flat

## Matte, map-free materials: low-poly surfaces read through flat colour and light.
static func matte(material: Material) -> void:
	var standard := material as BaseMaterial3D
	if standard==null:
		return
	standard.normal_enabled = false
	standard.normal_texture = null
	standard.heightmap_enabled = false
	standard.clearcoat_enabled = false
	standard.roughness = maxf(standard.roughness,.62)
	if standard.metallic<.5:
		standard.metallic = 0.0
	standard.metallic_specular = minf(standard.metallic_specular,.35)
