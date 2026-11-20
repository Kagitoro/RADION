extends Node3D

const LEVEL := 3.15
const LEVELS := 5
const ROOF := LEVEL * LEVELS
const COURT := Rect2(-8.0,-12.30,26.0,24.65)
const COURT_SURFACE := .017
const STONE := Color("#4b4c58")
const STEEL := Color("#222631")
const BRASS := Color("#ac7d52")
const CYAN := Color("#76e3e9")
const DECK := Color("#64574e")
var world: NightWorld
var stage_player := AudioStreamPlayer3D.new()
var stage_switch: Vector3

func build(city: NightWorld) -> void:
	world = city
	name = "SkylineTower"
	position = Vector3(-68, 0, -47)
	build_court()
	build_shell()
	for floor_number in range(LEVELS):
		build_floor(floor_number)
		build_stairs(floor_number)
	build_roof()

func cube(at: Vector3, size: Vector3, color: Color, solid := false) -> void:
	world.box(self, at, size, color, solid)

func add_label(text: String, at: Vector3, size := .006) -> void:
	world.add_sign(self, text, at, Vector3.ZERO, CYAN, size)

func build_court() -> void:
	var center := COURT.get_center()
	var at := Vector3(center.x,COURT_SURFACE-.11,center.y)
	# Keep the apron continuous across the seam with the district's north edge.
	var size := Vector3(COURT.size.x,.22,COURT.size.y)
	world.district.textured_box(self, at, size, world.district.walk_material)
	world.box(self, at, size, Color.TRANSPARENT, true, true)
	var asphalt := world.district.tiled_material(NightDistrict.ASPHALT_TEXTURE, Color("#5e6371"), .38)
	world.district.textured_box(self, Vector3(12.7, .02, 4.9), Vector3(7.88, .025, 14.55), asphalt)
	for index in range(5):
		cube(Vector3(12.7, .036, 10.8 - index * 2.5), Vector3(.08, .012, 1.12), BRASS)
	for side in [-1.0, 1.0]:
		cube(Vector3(5 + side * 13, .52, -.4), Vector3(.18, 1.0, 24), STEEL, true)
	cube(Vector3(5, .52, -12.3), Vector3(26, 1.0, .18), STEEL, true)
	for span in [Vector2(-8, 8.72), Vector2(16.66, 18)]:
		cube(Vector3((span.x + span.y) / 2, .52, 12), Vector3(span.y - span.x, 1.0, .18), STEEL, true)
	for at_light in [Vector3(8.8, 2.7, 8), Vector3(17.4, 2.7, -6.9)]:
		cube(at_light - Vector3.UP * 1.35, Vector3(.15, 2.7, .15), STEEL)
		world.point_light(self, at_light, CYAN, 1.25, 8)

func build_shell() -> void:
	cube(Vector3(0, ROOF / 2, -9), Vector3(16, ROOF, .28), STONE, true)
	for side in [-1.0, 1.0]:
		cube(Vector3(side * 8, ROOF / 2, 0), Vector3(.27, ROOF, 18), STONE, true)
	cube(Vector3(0, (ROOF + 3.1) / 2, 9), Vector3(16, ROOF - 3.1, .25), STONE, true)
	for span in [Vector2(-8, 1.05), Vector2(4.0, 8)]:
		cube(Vector3((span.x + span.y) / 2, 1.55, 9), Vector3(span.y - span.x, 3.1, .25), STONE, true)
	cube(Vector3(2.53, 2.97, 9.45), Vector3(5.6, .21, 1.65), STEEL)
	cube(Vector3(2.53, .035, 9.56), Vector3(3.5, .07, 1.2), DECK, true)
	add_label("SKYLINE  /  ROOFTOP", Vector3(2.53, 3.48, 9.19), .011)
	world.point_light(self, Vector3(2.53, 2.69, 9.65), Color("#ffc886"), 2.2, 6.5)
	for x in [-7.85, -4.0, .0, 4.0, 7.85]:
		cube(Vector3(x, ROOF / 2, 9.19), Vector3(.21, ROOF, .20), BRASS)
	var panes: Array[Vector3] = []
	var dark: Array[Vector3] = []
	var sills: Array[Vector3] = []
	for row in range(LEVELS):
		var y := row * LEVEL + 1.67
		for bay in range(7):
			var x := -6.45 + bay * 2.15
			if row != 0 or absf(x - 2.53) > 2.1:
				(panes if (row * 3 + bay * 7) % 5 < 2 else dark).append(Vector3(x, y, 9.16))
				sills.append(Vector3(x,y-.85,9.215))
		cube(Vector3(0, (row + 1) * LEVEL - .08, 9.23), Vector3(16.4, .17, .34), STEEL)
	batch_glass(panes, Vector3(1.56, 1.65, .065), Color("#e2ad72"), .55)
	batch_glass(dark, Vector3(1.56, 1.65, .065), Color("#476379"), .13)
	batch_glass(sills, Vector3(1.74,.085,.19), BRASS, .12)
	var side_windows: Array[Vector3] = []
	for floor_number in range(LEVELS):
		for bay in range(7):
			side_windows.append(Vector3(8.16, floor_number * LEVEL + 1.68, -7.3 + bay * 2.42))
	batch_glass(side_windows, Vector3(.065, 1.72, 1.65), Color("#637f9a"), .23)

func batch_glass(positions: Array[Vector3], size: Vector3, tint: Color, emission: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = emission
	material.roughness = .35
	var glass := BoxMesh.new()
	glass.size = size
	glass.material = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = glass
	instances.instance_count = positions.size()
	for index in positions.size():
		instances.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = instances
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)

func build_floor(floor_number: int) -> void:
	var y := floor_number * LEVEL
	if floor_number == 0:
		cube(Vector3(0,y-.07,0), Vector3(16,.23,18), DECK, true)
		for x in [-1.25,6.35]:
			cube(Vector3(x,1.47,6.8),Vector3(.29,2.94,.29),STEEL,true)
			cube(Vector3(x,.17,6.8),Vector3(.37,.26,.37),BRASS)
		cube(Vector3(2.53,.052,7.18),Vector3(2.85,.016,3.5),Color("#354654"))
		cube(Vector3(1.12,.063,7.18),Vector3(.025,.014,3.5),BRASS)
		cube(Vector3(3.94,.063,7.18),Vector3(.025,.014,3.5),BRASS)
		world.place_prop(self, "furniture/loungeSofa", Vector3(4.2,.048,-2.5), Vector3(3.0,1.02,1.1), PI)
		world.place_prop(self, "furniture/pottedPlant", Vector3(6,.05,5.9), Vector3(.72,1.43,.72))
	else:
		cube(Vector3(2.75,y-.09,0), Vector3(10.5,.18,18), DECK, true)
		cube(Vector3(-5.25,y-.09,6.22), Vector3(5.5,.18,5.56), DECK, true)
		cube(Vector3(-5.25,y-.09,-6.95), Vector3(5.5,.18,4.1), DECK, true)
		cube(Vector3(-2.54,y+.52,-.1), Vector3(.09,1.04,7.15), BRASS, true)
	if floor_number < LEVELS:
		add_label("0%d  /  ROOF  ↑" % (floor_number + 1), Vector3(-5.6,y+2.41,8.8), .008)
	if floor_number == 0:
		add_label("ROOFTOP   ←", Vector3(1.0,2.1,5.98), .008)
	world.point_light(self, Vector3(-4.95,y+2.64,4.7), Color("#ffd2a1"), 1.5, 7.8)
	world.point_light(self, Vector3(4.0,y+2.7,1.5), Color("#a9c9fd"), .95, 7.5)

func build_stairs(floor_number: int) -> void:
	var y := floor_number * LEVEL
	for flight in range(2):
		var direction := -1.0 if flight == 0 else 1.0
		var x := -6.55 if flight == 0 else -3.84
		var start_y := y + flight * LEVEL / 2
		var rise := LEVEL / 2
		var steps := 12
		var run := 6.9
		for step in steps:
			var step_height := rise * (step + 1) / steps
			var z := direction * (-run / 2 + run * (step + .5) / steps)
			cube(Vector3(x,start_y+step_height-.095,z), Vector3(2.38,.19,run/steps+.005), DECK)
			cube(Vector3(x,start_y+step_height+.001,z+direction*.22), Vector3(2.34,.009,.026), BRASS)
		var ramp := Node3D.new()
		ramp.position = Vector3(x,start_y+rise/2,0)
		ramp.rotation.x = -direction * atan2(rise,run)
		add_child(ramp)
		world.box(ramp, Vector3(0,-.065,0), Vector3(2.38,.13,Vector2(run,rise).length()), Color.TRANSPARENT, true, true)
		world.box(ramp, Vector3(1.31,.47,0), Vector3(.08,.94,run), STEEL, true, true)
		world.box(ramp, Vector3(1.31,.89,0), Vector3(.085,.085,run), BRASS)
		for z in [-3.35, -.95, 1.45, 3.35]:
			world.box(ramp, Vector3(1.31,.45,z), Vector3(.065,.90,.065), STEEL)
	cube(Vector3(-5.2,y+LEVEL/2-.09,-4.18), Vector3(5.25,.18,1.52), DECK, true)
	cube(Vector3(-5.2,y+LEVEL/2+.5,-4.92), Vector3(5.25,1.0,.12), BRASS, true)
	world.point_light(self, Vector3(-5.3,y+2.76,-4.3), CYAN, .82, 5.5)

func build_roof() -> void:
	build_floor(LEVELS)
	for side in [-1.0, 1.0]:
		cube(Vector3(side*7.92,ROOF+.58,0), Vector3(.22,1.16,18), STEEL, true)
		cube(Vector3(0,ROOF+.58,side*8.92), Vector3(16,1.16,.22), STEEL, true)
		cube(Vector3(side*7.92,ROOF+1.16,0), Vector3(.27,.065,18), BRASS)
	cube(Vector3(-5.25,ROOF+.54,-4.84), Vector3(5.5,1.08,.09), STEEL, true)
	cube(Vector3(-6.57,ROOF+.54,3.49), Vector3(2.48,1.08,.09), STEEL, true)
	cube(Vector3(2.7,ROOF+.11,-6.62), Vector3(7.7,.22,3.35), STEEL, true)
	cube(Vector3(2.70,ROOF+.055,-4.80),Vector3(2.6,.11,.36),STEEL,true)
	var blue_tiles: Array[Vector3] = []
	var pink_tiles: Array[Vector3] = []
	for x in range(8):
		for z in range(8):
			var tile := Vector3(-.56+x*.77, ROOF+.015, -4.55+z*.77)
			(blue_tiles if (x+z)%3 != 0 else pink_tiles).append(tile)
	batch_glass(blue_tiles,Vector3(.72,.025,.72),Color("#29465e"),.34)
	batch_glass(pink_tiles,Vector3(.72,.025,.72),Color("#4c315f"),.31)
	cube(Vector3(2.7,ROOF+.62,-6.7), Vector3(2.6,.80,.74), STEEL, true)
	stage_switch = Vector3(2.7,ROOF+1.12,-6.42)
	add_label("S O U N D C H E C K", Vector3(2.7,ROOF+1.18,-6.30), .005)
	for x in [-.90,6.30]:
		for z in [-8.0,-5.0]:
			cube(Vector3(x,ROOF+1.46,z), Vector3(.14,2.92,.14), STEEL, true)
		cube(Vector3(x,ROOF+2.92,-6.5), Vector3(.14,.15,3.1), BRASS)
		world.point_light(self, Vector3(x,ROOF+2.77,-5.55), CYAN if x < 0 else Color("#e78bea"), 2.2, 8.0)
	cube(Vector3(2.7,ROOF+2.92,-5.0), Vector3(7.32,.16,.14), BRASS)
	cube(Vector3(2.7,ROOF+1.28,-8.15),Vector3(7.25,2.12,.12),STEEL,true)
	var light_bars: Array[Vector3] = []
	for index in range(9):
		var x := -.3+index*.75
		light_bars.append(Vector3(x,ROOF+1.24+index*.10,-8.065))
		add_label("╱", Vector3(x,ROOF+2.72,-7.94), .014)
	batch_glass(light_bars,Vector3(.32,1.25,.035),Color("#65b8df"),.54)
	world.point_light(self, Vector3(2.7,ROOF+2.77,-5.20), Color("#a5bffc"), 1.65, 9.4)
	world.place_prop(self, "furniture/loungeSofa", Vector3(5.9,ROOF,5.8), Vector3(2.9,1.02,1.1), PI)
	world.place_prop(self, "furniture/tableRound", Vector3(5.8,ROOF,4.45), Vector3(.80,.57,.80))
	world.place_prop(self, "furniture/pottedPlant", Vector3(6.95,ROOF,7.35), Vector3(.8,1.52,.8))
	for x in [4.25,7.57]:
		cube(Vector3(x,ROOF+1.38,7.4),Vector3(.12,2.76,.12),STEEL,true)
		cube(Vector3(x,ROOF+2.76,5.73),Vector3(.12,.14,3.54),BRASS)
	for index in range(9):
		cube(Vector3(5.91,ROOF+2.8,4.16+index*.41),Vector3(3.48,.095,.15),BRASS)
	world.point_light(self, Vector3(4.4,ROOF+2.25,4.9), Color("#ffac76"), 1.85, 7.0)
	var track: AudioStreamMP3 = preload("res://assets/party/DJ Dance.mp3").duplicate()
	track.loop = true
	stage_player.stream = track
	stage_player.position = stage_switch
	stage_player.volume_db = -15
	stage_player.max_distance = 23
	add_child(stage_player)

func toggle_soundcheck() -> void:
	if stage_player.playing:
		stage_player.stop()
	else:
		stage_player.play()
