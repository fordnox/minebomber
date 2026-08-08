class_name BoomFx
extends Node2D
# Short-lived expanding fireball drawn procedurally.

const LIFE := 0.45

var radius_px := 64.0
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var f := age / LIFE
	var r := radius_px * (0.4 + 0.6 * f)
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.55, 0.1, 0.75 * (1.0 - f)))
	draw_circle(Vector2.ZERO, r * 0.55, Color(1.0, 0.9, 0.4, 0.9 * (1.0 - f)))
