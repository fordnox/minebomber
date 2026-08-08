class_name WorldView
extends Node2D
# Client-side terrain knowledge + rendering. Starts fully fogged; cells become
# known only when the server reveals them. Also acts as the "world" object for
# client-side prediction (get_tile / dig), where UNKNOWN blocks movement.

var known := PackedInt32Array()
var headless := false
var terrain: TileMapLayer
var fog: TileMapLayer

func _init() -> void:
	headless = DisplayServer.get_name() == "headless"
	known.resize(C.GRID_W * C.GRID_H)
	if not headless:
		var ts := Tiles.build_tileset()
		terrain = TileMapLayer.new()
		terrain.tile_set = ts
		fog = TileMapLayer.new()
		fog.tile_set = ts
		fog.z_index = 10
		add_child(terrain)
		add_child(fog)
	reset()

func reset() -> void:
	known.fill(C.Tile.UNKNOWN)
	if headless:
		return
	terrain.clear()
	fog.clear()
	for y in C.GRID_H:
		for x in C.GRID_W:
			fog.set_cell(Vector2i(x, y), 0, Vector2i(C.Tile.UNKNOWN, 0))

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < C.GRID_W and c.y < C.GRID_H

func get_tile(c: Vector2i) -> int:
	if not in_bounds(c):
		return C.Tile.WALL
	return known[c.y * C.GRID_W + c.x]

func reveal(c: Vector2i, t: int) -> void:
	if not in_bounds(c):
		return
	known[c.y * C.GRID_W + c.x] = t
	if headless:
		return
	terrain.set_cell(c, 0, Vector2i(t, 0))
	fog.erase_cell(c)

# Called by Sim when a predicted dig completes; the server's reveal message
# will confirm (or correct) this shortly after.
func dig(c: Vector2i) -> void:
	reveal(c, C.Tile.EMPTY)
