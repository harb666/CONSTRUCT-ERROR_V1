class_name FlightGraph
extends Resource
## A level's open air for flying robots, baked by tools/bake_flight_graph.gd:
## a grid of points `spacing` apart with room for a Neon Sentinel round
## them, each linked to the neighbours it can fly straight to. The ground
## navigation mesh is no use to a flyer (up at its height the closest piece
## is often a walkway with no way off it). FlightNav finds routes over it.

## The 13 neighbour steps each cell's `links` bits stand for (the other 13
## are the same links seen from the far end).
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1),
	Vector3i(1, 1, 0), Vector3i(1, -1, 0), Vector3i(1, 0, 1), Vector3i(1, 0, -1),
	Vector3i(0, 1, 1), Vector3i(0, 1, -1),
	Vector3i(1, 1, 1), Vector3i(1, 1, -1), Vector3i(1, -1, 1), Vector3i(1, -1, -1),
]

@export var origin := Vector3.ZERO
@export var spacing := 4.0
@export var dims := Vector3i.ZERO
## Per cell (x fastest, then z, then y): -1 = no room, else the bits of the
## STEPS it links along.
@export var links := PackedInt32Array()
## Links through a laser gate (gate id -> [cell, step, cell, step...]):
## left out of `links`, made only once that gate is open.
@export var gate_links := {}


func cell_index(c: Vector3i) -> int:
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= dims.x or c.y >= dims.y or c.z >= dims.z:
		return -1
	return c.x + dims.x * (c.z + dims.z * c.y)


func cell_of(i: int) -> Vector3i:
	return Vector3i(i % dims.x, i / (dims.x * dims.z), (i / dims.x) % dims.z)


func cell_position(c: Vector3i) -> Vector3:
	return origin + Vector3(c) * spacing


func cell_at(p: Vector3) -> Vector3i:
	return Vector3i(((p - origin) / spacing).round())
