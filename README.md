# Mine Bombers Remake

A multiplayer recreation of the 1996 DOS classic *Mine Bombers*: dig tunnels,
loot gold, buy bombs between rounds, and blow up your friends. Built with
**Godot 4.x** on an **authoritative server** architecture with
**client-side prediction** — nothing gameplay-critical is trusted to clients.

All art is generated procedurally at runtime; the repo contains no binary assets.

## Running it

Requires Godot 4.3+ (tested on 4.7.1). Open the project in the editor and hit
play, or from the CLI:

```sh
# Windowed game (menu: host or join)
godot --path .

# Dedicated headless server
godot --headless --path . -- --server --port 7777

# Join a server directly, skipping the menu
godot --path . -- --join 192.168.1.10 --port 7777

# Windowed listen-server (host + play in one process)
godot --path . -- --host
```

**Controls:** WASD/arrows move & dig · Space plant bomb · E detonate remote
bombs · 1–3 select bomb type · Enter starts the match (host, in lobby).

## Architecture

### Authoritative server (`scripts/game.gd`, server half)
Clients send *inputs* (`seq`, direction, action bits, selected weapon), never
positions. The server simulates every player at a fixed 60 Hz, validates every
purchase/plant against server-held money and inventory, and broadcasts binary
snapshots at 20 Hz. Input backlog is capped so bursting packets can't
speed-hack; actions are edge-triggered server-side so held keys can't spam.

### Client-side prediction & reconciliation (`scripts/game.gd`, client half)
The local player is stepped immediately through the same deterministic sim
(`scripts/sim.gd`) that the server runs, so movement feels instant. Each
snapshot carries the last acknowledged input `seq`; the client rewinds to the
server state and replays unacknowledged inputs. Any residual error becomes a
visual offset that decays smoothly instead of snapping. Remote players render
~100 ms in the past, interpolated between snapshots.

### Fog of war, done legitimately
The server never sends the map. Terrain lives only in `WorldData` on the
server; each player has a per-peer revealed set, and cells are streamed to that
client only when within `REVEAL_RADIUS` of their miner. Snapshots likewise omit
remote players beyond `VIS_RADIUS` — a wallhack client has nothing to read.

### Binary serialization
Inputs, snapshots and tile reveals are hand-packed `PackedByteArray`s via
`StreamPeerBuffer` (a full 8-player snapshot is ~130 bytes) over ENet UDP:
unreliable-ordered for inputs/snapshots, reliable for events, purchases and
reveals.

### Round state machine (server)
`LOBBY → SHOP (20 s) → ACTIVE (150 s or last-miner-standing) → CLEANUP → SHOP…`
Each round regenerates the map from a fresh seed. Gold digs pay out
immediately; kills pay a bounty; round winners get a bonus to spend in the shop
(small/big/remote bombs, drill, medkit).

### File map
| File | Role |
| --- | --- |
| `scripts/net.gd` | Autoload: ENet setup + every RPC endpoint (`rx_*` client→server, `sv_*` server→client) |
| `scripts/sim.gd` | Deterministic movement/dig sim shared by server and predicting client |
| `scripts/game.gd` | The match: server sim, phases, fog, snapshots; client prediction, interpolation, events |
| `scripts/world_data.gd` | Server-only authoritative terrain + map generation |
| `scripts/world_view.gd` | Client terrain knowledge + `TileMapLayer` rendering + fog layer |
| `scripts/constants.gd` | Autoload: tuning, enums, shop catalog |
| `scripts/hud.gd` | Status bar, scoreboard, kill feed, shop panel |
| `scripts/tiles.gd`, `*_view.gd`, `boom_fx.gd` | Procedural art & effects |
| `scripts/main.gd` | Menu + CLI arg handling (`--server`, `--join`, `--host`, `--bot`) |

## Tests

```sh
# All scripts compile
godot --headless --path . -s tests/compile_check.gd    # prints COMPILE_OK

# End-to-end smoke test: headless bot joins a dedicated server, starts a
# match, and verifies predicted movement is confirmed by server snapshots
godot --headless --path . -- --server --port 7901 &
godot --headless --path . -- --join 127.0.0.1 --port 7901 --bot   # prints BOT_OK
```

## Roadmap status

1. **Prototype local logic** — ✅ grid movement, digging, bombs, tile destruction
2. **Integrate networking** — ✅ authoritative server, input→snapshot loop, dedicated server mode
3. **Prediction & interpolation** — ✅ replay reconciliation + 100 ms interpolation buffer
4. **Meta-systems** — shop ✅; next: persistent stats & matchmaking via
   [Nakama](https://heroiclabs.com/nakama/) (round results are already
   centralized in `_srv_end_round`, the natural hook point), map editor
   (`WorldData.generate` is the seam — load painted maps instead of a seed),
   sounds, and more of the original's 20+ weapon catalog.
