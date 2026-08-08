class_name Sim
# Deterministic movement/digging simulation.
#
# This exact code runs on BOTH sides:
#  - the authoritative server steps every player with the inputs it received
#  - the client steps its own predicted state with the same inputs, then
#    replays unacknowledged inputs on top of each server snapshot
#
# `world` is any object exposing:
#   get_tile(cell: Vector2i) -> int   (C.Tile; UNKNOWN is treated as solid)
#   dig(cell: Vector2i)               (called once when a dig completes)

const EPS := 0.00001

static func new_state(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "target": cell, "prog": 0.0, "dir": C.Dir.NONE, "drill": false}

# st: state dict (mutated). input: {dir:int, acts:int}. dt: fixed timestep.
static func step(st: Dictionary, input: Dictionary, world, dt: float) -> void:
	if st.prog > 0.0:
		_advance(st, world, dt)
		return
	var d: int = input.dir
	if d == C.Dir.NONE:
		return
	st.dir = d
	var target: Vector2i = st.cell + C.DIRV[d]
	var t: int = world.get_tile(target)
	if t == C.Tile.ROCK or t == C.Tile.WALL or t == C.Tile.UNKNOWN:
		return
	st.target = target
	st.prog = EPS
	_advance(st, world, dt)

static func _advance(st: Dictionary, world, dt: float) -> void:
	var t: int = world.get_tile(st.target)
	if t == C.Tile.ROCK or t == C.Tile.WALL or t == C.Tile.UNKNOWN:
		# tile changed under us since the move started — abort back to origin cell
		st.prog = 0.0
		st.target = st.cell
		return
	var speed := C.MOVE_SPEED
	match t:
		C.Tile.DIRT: speed = C.DIG_DIRT
		C.Tile.STONE: speed = C.DIG_STONE
		C.Tile.GOLD: speed = C.DIG_GOLD
	if st.get("drill", false) and t != C.Tile.EMPTY:
		speed *= 2.0
	st.prog += speed * dt
	if st.prog >= 1.0:
		if t != C.Tile.EMPTY:
			world.dig(st.target)
		st.cell = st.target
		st.prog = 0.0

static func pos_of(st: Dictionary) -> Vector2:
	if st.prog <= 0.0:
		return C.cell_to_pos(st.cell)
	return C.cell_to_pos(st.cell).lerp(C.cell_to_pos(st.target), minf(st.prog, 1.0))
