class_name WorldData
extends RefCounted
# Server-side authoritative terrain. Never sent to clients wholesale — the
# server reveals individual cells per player (fog of war lives here).

var tiles := PackedInt32Array()

func generate(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	tiles.resize(C.GRID_W * C.GRID_H)
	for y in C.GRID_H:
		for x in C.GRID_W:
			var t := C.Tile.DIRT
			if x == 0 or y == 0 or x == C.GRID_W - 1 or y == C.GRID_H - 1:
				t = C.Tile.WALL
			else:
				var r := rng.randf()
				if r < 0.06:
					t = C.Tile.ROCK
				elif r < 0.16:
					t = C.Tile.STONE
				elif r < 0.24:
					t = C.Tile.GOLD
			tiles[y * C.GRID_W + x] = t
	for p in spawn_cells():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				set_tile(p + Vector2i(dx, dy), C.Tile.EMPTY)

func spawn_cells() -> Array:
	var m := 3
	return [
		Vector2i(m, m),
		Vector2i(C.GRID_W - 1 - m, C.GRID_H - 1 - m),
		Vector2i(C.GRID_W - 1 - m, m),
		Vector2i(m, C.GRID_H - 1 - m),
		Vector2i(C.GRID_W / 2, m),
		Vector2i(C.GRID_W / 2, C.GRID_H - 1 - m),
		Vector2i(m, C.GRID_H / 2),
		Vector2i(C.GRID_W - 1 - m, C.GRID_H / 2),
	]

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < C.GRID_W and c.y < C.GRID_H

func get_tile(c: Vector2i) -> int:
	if not in_bounds(c):
		return C.Tile.WALL
	return tiles[c.y * C.GRID_W + c.x]

func set_tile(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		tiles[c.y * C.GRID_W + c.x] = t
