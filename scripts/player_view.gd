class_name PlayerView
extends Node2D
# Visual representation of a player: colored miner + name tag.

var sprite: Sprite2D
var label: Label

func _init() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	label = Label.new()
	label.position = Vector2(-60, -36)
	label.custom_minimum_size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

func setup(pname: String, color: Color) -> void:
	label.text = pname
	label.add_theme_color_override("font_color", color.lightened(0.3))
	sprite.texture = Tiles.circle_tex(11, color, color.darkened(0.5))
