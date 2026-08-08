class_name Tiles
# All art is generated at runtime — no binary assets in the repo.

static func build_tileset() -> TileSet:
	var n := C.Tile.size()
	var img := Image.create_empty(C.TILE * n, C.TILE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var base := {
		C.Tile.EMPTY: Color(0.13, 0.09, 0.06),
		C.Tile.DIRT: Color(0.45, 0.30, 0.15),
		C.Tile.STONE: Color(0.46, 0.46, 0.50),
		C.Tile.GOLD: Color(0.45, 0.30, 0.15),
		C.Tile.ROCK: Color(0.24, 0.24, 0.28),
		C.Tile.WALL: Color(0.20, 0.26, 0.42),
		C.Tile.UNKNOWN: Color(0.03, 0.03, 0.045),
	}
	for t in base:
		var ox: int = t * C.TILE
		for y in C.TILE:
			for x in C.TILE:
				var col: Color = base[t]
				col = col.darkened(rng.randf_range(0.0, 0.10))
				img.set_pixel(ox + x, y, col)
		if t == C.Tile.GOLD:
			for i in 10:
				var gx := rng.randi_range(2, C.TILE - 4)
				var gy := rng.randi_range(2, C.TILE - 4)
				img.fill_rect(Rect2i(ox + gx, gy, 2, 2), Color(1.0, 0.85, 0.2))
		if t == C.Tile.WALL:
			for y2 in range(0, C.TILE, 8):
				img.fill_rect(Rect2i(ox, y2, C.TILE, 1), Color(0.12, 0.16, 0.28))
		if t == C.Tile.ROCK or t == C.Tile.STONE:
			for i in 6:
				var rx := rng.randi_range(1, C.TILE - 6)
				var ry := rng.randi_range(1, C.TILE - 3)
				img.fill_rect(Rect2i(ox + rx, ry, 5, 2), base[t].darkened(0.25))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(C.TILE, C.TILE)
	for t in n:
		src.create_tile(Vector2i(t, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(C.TILE, C.TILE)
	ts.add_source(src, 0)
	return ts

static func circle_tex(radius: int, fill: Color, outline: Color) -> ImageTexture:
	var d := radius * 2 + 2
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	var cpos := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var dist := (Vector2(x, y) + Vector2(0.5, 0.5) - cpos).length()
			if dist <= radius - 1.5:
				img.set_pixel(x, y, fill)
			elif dist <= radius:
				img.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(img)
