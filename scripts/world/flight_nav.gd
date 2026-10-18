class_name FlightNav
extends Node
## Routes for flying robots (the Neon Sentinels hunting the players) over the
## level's FlightGraph. Built a slice per frame from the level's start (on a
## phone, all at once would be a hitch), finished long before the first
## sentinel needs it. Laser gates' links are made as the gates open
## (open_gate). Hunting sentinels find it in the "flight_nav" group.

@export var graph: FlightGraph
## Cells added to the route finder per frame while it builds.
@export var build_per_frame := 100

var astar := AStar3D.new()
var ready_to_route := false
var _built := 0
var _opened := {}
## The flyer's body (a Neon Sentinel's) when finding where it can start.
const BODY := 0.9
var _body := SphereShape3D.new()
var _cast := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	add_to_group(&"flight_nav")
	_cast.shape = _body
	_cast.collision_mask = 1 | ShaftBarrier.LAYER


func _process(_delta: float) -> void:
	if ready_to_route or graph == null:
		set_process(false)
		return
	build_some(build_per_frame)


## Next slice of the build: first every cell's point, then their links.
func build_some(n: int) -> void:
	var total := graph.links.size()
	var end := mini(_built + n, total * 2)
	for k in range(_built, end):
		if k < total:
			if graph.links[k] >= 0:
				astar.add_point(k, graph.cell_position(graph.cell_of(k)))
		else:
			_link_from(k - total)
	_built = end
	if _built >= total * 2:
		ready_to_route = true
		for g in _opened:
			_link_gate(g)


func build_all() -> void:
	while not ready_to_route:
		build_some(1 << 20)


func _link_from(i: int) -> void:
	var bits := graph.links[i]
	if bits <= 0:
		return
	var c := graph.cell_of(i)
	for s in FlightGraph.STEPS.size():
		if bits & (1 << s):
			var j := graph.cell_index(c + FlightGraph.STEPS[s])
			if j >= 0 and astar.has_point(j):
				astar.connect_points(i, j)


## A laser gate has opened: flyers may route through it.
func open_gate(id: String) -> void:
	if _opened.has(id):
		return
	_opened[id] = true
	if ready_to_route:
		_link_gate(id)


func _link_gate(id: String) -> void:
	var l: PackedInt32Array = graph.gate_links.get(id, PackedInt32Array())
	for k in range(0, l.size() - 1, 2):
		var i := l[k]
		var j := graph.cell_index(graph.cell_of(i) + FlightGraph.STEPS[l[k + 1]])
		if astar.has_point(i) and astar.has_point(j):
			astar.connect_points(i, j)


## A route through the air from `from` to `to` (both should be in the
## open): the nearest points each can fly straight to, joined. As close as
## it gets if `to` can't be reached (then not ending at `to`). Empty if it
## can't route (yet).
func route(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> PackedVector3Array:
	if not ready_to_route:
		return PackedVector3Array()
	var a := _nearest(space, from, exclude, BODY)
	var b := _nearest(space, to, exclude)
	if a < 0 or b < 0:
		return PackedVector3Array()
	var ids := astar.get_id_path(a, b, true)
	var path := PackedVector3Array()
	for i in ids:
		path.append(astar.get_point_position(i))
	if not ids.is_empty() and ids[ids.size() - 1] == b:
		path.append(to)
	return path


## The nearest point with a clear line from `p` (rings of cells outwards),
## or with room for a body `radius` round to fly straight there.
func _nearest(space: PhysicsDirectSpaceState3D, p: Vector3, exclude: Array[RID], radius := 0.0) -> int:
	var c := graph.cell_at(p)
	for r in 3:
		var tried: Array = []
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), maxi(absi(dy), absi(dz))) != r:
						continue
					var i := graph.cell_index(c + Vector3i(dx, dy, dz))
					if i < 0 or not astar.has_point(i):
						continue
					tried.append([p.distance_squared_to(astar.get_point_position(i)), i])
		tried.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for t in tried:
			var at := astar.get_point_position(t[1])
			if radius > 0.0:
				_body.radius = radius
				_cast.transform = Transform3D(Basis(), p)
				_cast.motion = at - p
				_cast.exclude = exclude
				var m := space.cast_motion(_cast)
				if m.is_empty() or m[0] >= 1.0:
					return t[1]
			elif space.intersect_ray(PhysicsRayQueryParameters3D.create(p, at, 1, exclude)).is_empty():
				return t[1]
	return -1
