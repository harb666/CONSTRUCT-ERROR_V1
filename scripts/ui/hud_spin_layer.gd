class_name HudSpinLayer
extends Node2D
## One ring of an animated HUD gauge (the portrait emblem), drawn once and
## turned by rotating the layer: redrawing it every frame would remake its
## graphics buffers each time (see HudStyle.fill). Same picture: the ring's
## points rotate exactly as recomputing them at the turned angles would.

## Radians per second (HudStyle.spin_layers sets rotation = speed * t).
var speed := 0.0
## Draws the ring around (0, 0): func(ci: CanvasItem) -> void.
var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
