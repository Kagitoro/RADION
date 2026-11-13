class_name LowPolyBackdrop
extends Control
## Faceted background: a jittered triangle mesh shaded between two colours, each
## facet slowly breathing in brightness like light moving over low-poly terrain.
## `coverage` limits it to the left part of the control with a jagged right edge.

@export var top_color := Color("#1b2340")
@export var bottom_color := Color("#090c17")
@export var accent := Color("#ff4f9a")
## Share of facets tinted with the accent colour.
@export_range(0.0, 1.0) var accent_share := .06
@export_range(0.05, 1.0) var coverage := 1.0
@export var cell := 86.0
@export_range(0.0, 1.0) var opacity := 1.0
@export var shimmer := true

var points: PackedVector2Array = []
var columns := 0
var rows := 0
var tints: PackedFloat32Array = []
var phases: PackedFloat32Array = []
var accents: PackedByteArray = []
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(rebuild)
	rebuild()

func rebuild() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151
	columns = int(ceil(size.x*coverage/cell))+2
	rows = int(ceil(size.y/cell))+2
	points.resize(columns*rows)
	for row in rows:
		for column in columns:
			var jitter := Vector2(rng.randf_range(-.36,.36),rng.randf_range(-.36,.36))*cell
			if row==0 or row==rows-1:
				jitter.y = 0
			var at := Vector2(column*cell,row*cell-cell*.5)+jitter
			if column==columns-1:
				# Jagged edge: the last column juts in and out.
				at.x = size.x*coverage+rng.randf_range(-.55,.25)*cell
			points[row*columns+column] = at
	var count := (columns-1)*(rows-1)*2
	tints.resize(count)
	phases.resize(count)
	accents.resize(count)
	for index in count:
		tints[index] = rng.randf_range(-.07,.07)
		phases[index] = rng.randf()*TAU
		accents[index] = 1 if rng.randf()<accent_share else 0
	queue_redraw()

func _process(delta: float) -> void:
	if shimmer and is_visible_in_tree():
		clock += delta
		queue_redraw()

func _draw() -> void:
	if columns<2 or rows<2:
		return
	var index := 0
	for row in rows-1:
		for column in columns-1:
			var a := points[row*columns+column]
			var b := points[row*columns+column+1]
			var c := points[(row+1)*columns+column]
			var d := points[(row+1)*columns+column+1]
			# Alternate the diagonal so the mesh does not look like a grid.
			var flip := (row+column)%2==0
			var triangles := [[a,b,d],[a,d,c]] if flip else [[a,b,c],[b,d,c]]
			for triangle in triangles:
				draw_facet(triangle,index)
				index += 1

func draw_facet(triangle: Array, index: int) -> void:
	var center: Vector2 = (triangle[0]+triangle[1]+triangle[2])/3.0
	var height := clampf(center.y/maxf(size.y,1.0),0.0,1.0)
	var color := top_color.lerp(bottom_color,height)
	var light := tints[index]+(.045*sin(clock*.55+phases[index]) if shimmer else 0.0)
	color = color.lightened(light) if light>0 else color.darkened(-light)
	if accents[index]==1:
		color = color.lerp(accent,.22+.08*sin(clock*.8+phases[index]))
	# Fade towards the jagged edge.
	var fade := 1.0
	if coverage<1.0:
		fade = clampf(1.15-center.x/(size.x*coverage),0.0,1.0)
	color.a = opacity*fade*color.a
	draw_colored_polygon(PackedVector2Array(triangle),color)
