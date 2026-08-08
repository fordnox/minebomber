class_name BombView
extends Node2D
# A planted bomb: black sphere blinking faster-feeling red as it sits armed.

var t := 0.0
var sprite: Sprite2D

func _init() -> void:
	sprite = Sprite2D.new()
	sprite.texture = Tiles.circle_tex(8, Color(0.08, 0.08, 0.08), Color(0.5, 0.5, 0.5))
	add_child(sprite)

func _process(delta: float) -> void:
	t += delta
	sprite.modulate = Color.WHITE.lerp(Color(1.0, 0.25, 0.2), 0.5 + 0.5 * sin(t * 9.0))
