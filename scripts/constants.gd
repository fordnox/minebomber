extends Node
# Autoload "C" — shared constants, tuning values and the shop catalog.

const TILE := 32
const GRID_W := 41
const GRID_H := 31

const TICK_RATE := 60          # fixed-step simulation rate (physics ticks/sec)
const SNAPSHOT_EVERY := 3      # server broadcasts state every N ticks (20 Hz)
const REVEAL_RADIUS := 6       # fog of war: server reveals tiles this close to you
const VIS_RADIUS := 8          # remote players farther than this are omitted from your snapshot
const INTERP_DELAY_MS := 100   # remote players render this far in the past (interpolation buffer)

enum Tile { EMPTY, DIRT, STONE, GOLD, ROCK, WALL, UNKNOWN }
enum Phase { LOBBY, SHOP, ACTIVE, CLEANUP }
enum Dir { NONE, UP, DOWN, LEFT, RIGHT }

const PHASE_NAMES := ["LOBBY", "SHOP", "ROUND", "ROUND OVER"]

const DIRV := {
	Dir.UP: Vector2i(0, -1),
	Dir.DOWN: Vector2i(0, 1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}

# input action bit flags (sent client -> server; edge-triggered server side)
const ACT_PLANT := 1
const ACT_DETONATE := 2

const MOVE_SPEED := 6.0        # cells/sec through open tunnels
const DIG_DIRT := 2.5          # cells/sec while digging dirt
const DIG_STONE := 0.8
const DIG_GOLD := 2.0

const START_HP := 100
const START_MONEY := 300
const GOLD_VALUE := 120
const KILL_BOUNTY := 250
const WIN_BONUS := 400

const SHOP_TIME := 20.0
const ROUND_TIME := 150.0
const CLEANUP_TIME := 6.0

enum Item { SMALL_BOMB, BIG_BOMB, REMOTE_BOMB, DRILL, MEDKIT }

const CATALOG := {
	Item.SMALL_BOMB: {"name": "Small Bomb", "cost": 50, "desc": "Radius 2, 3s fuse"},
	Item.BIG_BOMB: {"name": "Big Bomb", "cost": 220, "desc": "Radius 4, breaks rock"},
	Item.REMOTE_BOMB: {"name": "Remote Bomb", "cost": 180, "desc": "Detonate with E"},
	Item.DRILL: {"name": "Drill", "cost": 400, "desc": "Dig 2x faster (permanent)"},
	Item.MEDKIT: {"name": "Medkit", "cost": 150, "desc": "+50 HP instantly"},
}

const BOMB_STATS := {
	Item.SMALL_BOMB: {"radius": 2.2, "fuse": 3.0, "dmg": 60, "rock": false},
	Item.BIG_BOMB: {"radius": 4.2, "fuse": 3.0, "dmg": 120, "rock": true},
	Item.REMOTE_BOMB: {"radius": 2.2, "fuse": 30.0, "dmg": 60, "rock": false},
}

const COLORS: Array[Color] = [
	Color(0.95, 0.30, 0.25), Color(0.25, 0.60, 0.95), Color(0.30, 0.85, 0.35),
	Color(0.95, 0.85, 0.25), Color(0.80, 0.40, 0.95), Color(0.30, 0.90, 0.85),
	Color(0.95, 0.60, 0.25), Color(0.90, 0.90, 0.90),
]

static func cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5
