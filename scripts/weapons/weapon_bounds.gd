class_name WeaponBounds
extends RefCounted
## Oriented-box geometry for held weapons: overlap between two weapons
## (separating-axis test), clearance from an arm segment, and how far a
## weapon reaches back past the elbow. Used by tests and tuning tools.


## World-space oriented box of a weapon: [centre, axes (3, scaled to half
## extents)].
static func obb(w: Weapon) -> Array:
	var box := w.get_local_aabb()
	var xf := w.global_transform
	var c := xf * box.get_center()
	var h := box.size * 0.5
	return [c, [xf.basis.x * h.x, xf.basis.y * h.y, xf.basis.z * h.z]]


## Gap (m) between two oriented boxes along the best separating axis
## (negative = overlapping by that much).
static func gap(a: Array, b: Array) -> float:
	var axes: Array[Vector3] = []
	for v: Vector3 in a[1]:
		axes.append(v.normalized())
	for v: Vector3 in b[1]:
		axes.append(v.normalized())
	for u: Vector3 in a[1]:
		for v: Vector3 in b[1]:
			var cr := u.normalized().cross(v.normalized())
			if cr.length_squared() > 1e-6:
				axes.append(cr.normalized())
	var best := -INF
	var d: Vector3 = b[0] - a[0]
	for ax in axes:
		var ra := 0.0
		for v: Vector3 in a[1]:
			ra += absf(v.dot(ax))
		var rb := 0.0
		for v: Vector3 in b[1]:
			rb += absf(v.dot(ax))
		best = maxf(best, absf(d.dot(ax)) - ra - rb)
	return best


## Distance from a point to an oriented box surface (negative inside).
static func point_distance(box: Array, p: Vector3) -> float:
	var d := p - (box[0] as Vector3)
	var outside := 0.0
	var inside := INF
	for v: Vector3 in box[1]:
		var h := v.length()
		var t := absf(d.dot(v / h)) - h
		outside += maxf(t, 0.0) ** 2
		inside = minf(inside, -t)
	return sqrt(outside) if outside > 0.0 else -inside


## Clearance between a weapon box and a capsule (arm bone a..b, radius r).
static func capsule_gap(box: Array, a: Vector3, b: Vector3, r: float) -> float:
	var best := INF
	for i in 9:
		best = minf(best, point_distance(box, a.lerp(b, i / 8.0)) - r)
	return best


## How far (m) the weapon reaches back past `elbow` along the forearm
## direction `fore` (positive = sticks out behind the elbow).
static func rear_overhang(box: Array, elbow: Vector3, fore: Vector3) -> float:
	var f := fore.normalized()
	var c: Vector3 = box[0]
	var back := (c - elbow).dot(f)
	for v: Vector3 in box[1]:
		back -= absf(v.dot(f))
	return -back
