class_name FlightNav
extends Node
## Routes for flying robots (the Neon Sentinels hunting the players) over the
## level's FlightGraph. It searches the baked grid's own link bits directly
## (A*): nothing to build and almost no memory (an engine route graph of the
## same grid took 19 MB of the game's memory as the level ran - growing it
## mid-game is what iPhone Safari is least happy with). Laser gates' links
## are added as the gates open (open_gate). Hunting sentinels find it in the
## "flight_nav" group.

@export var graph: FlightGraph
## Most cells one search looks at (a phone's frame budget); past that it
## routes to the closest it got.
@export var max_search := 6000

var ready_to_route := false
var _opened := {}
## The flyer's body (a Neon Sentinel's) when finding where it can start.
const BODY := 0.9
var _body := SphereShape3D.new()
var _cast := PhysicsShapeQueryParameters3D.new()

var _links := PackedInt32Array()
var _at := PackedVector3Array()
## Per step: its index offset and length (m).
var _delta := PackedInt32Array()
var _cost := PackedFloat32Array()
## Search state (reused; `_seen` / `_done` hold the search's stamp).
var _g := PackedFloat32Array()
var _from := PackedInt32Array()
var _seen := PackedInt32Array()
var _done := PackedInt32Array()
var _stamp := 0
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0
## Cells the last search looked at (tests / tuning).
var last_searched := 0


func _ready() -> void:
	add_to_group(&"flight_nav")
	_cast.shape = _body
	_cast.collision_mask = 1 | ShaftBarrier.LAYER
	_setup()


func _setup() -> void:
	if graph == null or ready_to_route:
		return
	_links = graph.links.duplicate()
	var n := _links.size()
	var d := graph.dims
	for st in FlightGraph.STEPS:
		_delta.append(st.x + d.x * (st.z + d.z * st.y))
		_cost.append(Vector3(st).length() * graph.spacing)
	_at.resize(n)
	for i in n:
		_at[i] = graph.cell_position(graph.cell_of(i))
	_g.resize(n)
	_from.resize(n)
	_seen.resize(n)
	_done.resize(n)
	ready_to_route = true
	for g in _opened:
		_link_gate(g)


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
		if _links[l[k]] >= 0:
			_links[l[k]] |= 1 << l[k + 1]


func point_count() -> int:
	var c := 0
	for v in _links:
		if v >= 0:
			c += 1
	return c


## Cells searched per frame for the sentinels' requests (a few ms on a
## phone at most).
@export var per_frame := 250
## Waiting requests: [asker id, start cell, goal cell, goal point], one per
## asker; the first is being searched.
var _jobs: Array = []
var _job_on := false


## Ask for a route (as route()), found over the next frames: `asker`'s
## route_ready(path) is called with it. A newer request from the same asker
## replaces its waiting one.
func request(asker: Object, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> void:
	_setup()
	if not ready_to_route:
		return
	var a := _nearest(space, from, exclude, BODY)
	var b := _nearest(space, to, exclude)
	if a < 0 or b < 0:
		return
	var id := asker.get_instance_id()
	for k in range(_jobs.size() - 1, -1, -1):
		if _jobs[k][0] == id and not (k == 0 and _job_on):
			_jobs.remove_at(k)
	_jobs.append([id, a, b, to])


func pending() -> int:
	return _jobs.size()


func _process(_delta: float) -> void:
	var budget := per_frame
	while budget > 0 and not _jobs.is_empty():
		var job: Array = _jobs[0]
		if not _job_on:
			_begin(job[1], job[2])
			_job_on = true
		var before := _looked
		var over := _step(budget)
		budget -= maxi(_looked - before, 1)
		if not over:
			break
		_jobs.pop_front()
		_job_on = false
		var ids := _result()
		var asker := instance_from_id(job[0])
		if asker == null or not is_instance_valid(asker) or not asker.has_method(&"route_ready"):
			continue
		var path := PackedVector3Array()
		for i in ids:
			path.append(_at[i])
		if not ids.is_empty() and ids[ids.size() - 1] == job[2]:
			path.append(job[3])
		asker.route_ready(path)


## A route through the air from `from` to `to` (both should be in the
## open): the nearest points each can fly straight to, joined. As close as
## it gets if `to` can't be reached (then not ending at `to`). Empty if it
## can't route. All at once (tests): the game uses request().
func route(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> PackedVector3Array:
	_setup()
	if not ready_to_route:
		return PackedVector3Array()
	var a := _nearest(space, from, exclude, BODY)
	var b := _nearest(space, to, exclude)
	if a < 0 or b < 0:
		return PackedVector3Array()
	var ids := _search(a, b)
	_job_on = false  # (a sliced search in progress starts again)
	var path := PackedVector3Array()
	for i in ids:
		path.append(_pos(i))
	if not ids.is_empty() and ids[ids.size() - 1] == b:
		path.append(to)
	return path


func _pos(i: int) -> Vector3:
	return _at[i]


## A* from cell `a` to cell `b` over the link bits (each cell's bits are its
## links to the 13 "forward" neighbours; a link back is the neighbour's bit).
## The cells along the way, or to the cell nearest `b` it reached. Done in
## one go (tests); the sentinels' searches run a slice a frame (request).
func _search(a: int, b: int) -> PackedInt32Array:
	_begin(a, b)
	while not _step(max_search):
		pass
	return _result()


## Greedy weight on the distance still to go: far fewer cells looked at,
## routes a little less than the shortest (fine for a flyer).
const GREED := 1.5
var _goal := Vector3.ZERO
var _goal_i := -1
var _best := -1
var _best_h := INF
var _looked := 0


func _begin(a: int, b: int) -> void:
	_stamp += 1
	_goal = _at[b]
	_goal_i = b
	_hn = 0
	_g[a] = 0.0
	_from[a] = -1
	_seen[a] = _stamp
	_push(a, _at[a].distance_to(_goal) * GREED)
	_best = a
	_best_h = INF
	_looked = 0


## Looks at up to `budget` more cells; true when the search is over.
func _step(budget: int) -> bool:
	var n := _links.size()
	var end := mini(_looked + budget, max_search)
	while _hn > 0 and _looked < end:
		var i := _pop()
		if _done[i] == _stamp:
			continue
		_done[i] = _stamp
		_looked += 1
		var hi := _at[i].distance_to(_goal)
		if hi < _best_h:
			_best_h = hi
			_best = i
		if i == _goal_i:
			return true
		var gi := _g[i]
		var bits := _links[i]
		for s in 13:
			var bit := 1 << s
			var j := i + _delta[s]
			if bits > 0 and bits & bit and _done[j] != _stamp:
				var gj := gi + _cost[s]
				if _seen[j] != _stamp or gj < _g[j]:
					_seen[j] = _stamp
					_g[j] = gj
					_from[j] = i
					_push(j, gj + _at[j].distance_to(_goal) * GREED)
			j = i - _delta[s]
			if j >= 0 and j < n and _links[j] > 0 and _links[j] & bit and _done[j] != _stamp:
				var gj := gi + _cost[s]
				if _seen[j] != _stamp or gj < _g[j]:
					_seen[j] = _stamp
					_g[j] = gj
					_from[j] = i
					_push(j, gj + _at[j].distance_to(_goal) * GREED)
	return _hn == 0 or _looked >= max_search


func _result() -> PackedInt32Array:
	last_searched = _looked
	var out := PackedInt32Array()
	var k := _best
	while k >= 0:
		out.append(k)
		k = _from[k]
	out.reverse()
	return out


## Binary heap (min) of [key, cell].
func _push(v: int, key: float) -> void:
	if _hn >= _hk.size():
		_hk.resize(maxi(64, _hk.size() * 2))
		_hv.resize(_hk.size())
	var c := _hn
	_hn += 1
	while c > 0:
		var p := (c - 1) >> 1
		if _hk[p] <= key:
			break
		_hk[c] = _hk[p]
		_hv[c] = _hv[p]
		c = p
	_hk[c] = key
	_hv[c] = v


func _pop() -> int:
	var top := _hv[0]
	_hn -= 1
	if _hn > 0:
		var key := _hk[_hn]
		var v := _hv[_hn]
		var c := 0
		while true:
			var l := c * 2 + 1
			if l >= _hn:
				break
			var r := l + 1
			var m := r if r < _hn and _hk[r] < _hk[l] else l
			if _hk[m] >= key:
				break
			_hk[c] = _hk[m]
			_hv[c] = _hv[m]
			c = m
		_hk[c] = key
		_hv[c] = v
	return top


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
					if i < 0 or _links[i] < 0:
						continue
					tried.append([p.distance_squared_to(_pos(i)), i])
		tried.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for t in tried:
			var at := _pos(t[1])
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
