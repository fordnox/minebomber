class_name Game
extends Node2D
# The match. One instance runs everywhere:
#  - dedicated server: server half only (headless)
#  - host (listen server): server half + client half (loopback, no RPC)
#  - client: client half only
#
# Server half: authoritative sim, phase state machine, fog of war, snapshots.
# Client half: input capture, prediction + reconciliation, interpolation, HUD.

var headless := false
var bot := false
var tick := 0

# shared / replicated
var phase: int = C.Phase.LOBBY
var phase_left := 0.0
var round_no := 0

# ---- server state ----
var world_data: WorldData
var sp := {}                  # peer id -> server player dict
var bombs := {}               # bomb id -> {cell, type, fuse, owner}
var next_bid := 1
var color_cursor := 0
var dirty_cells := {}         # terrain changed since last flush

# ---- client state ----
var view: WorldView
var cam: Camera2D
var hud: Hud
var ents: Node2D
var me := Sim.new_state(Vector2i(2, 2))
var my_alive := false
var my_hp := 0
var my_money := 0
var my_inv := {}
var my_sel: int = C.Item.SMALL_BOMB
var meta := {}                # peer id -> {name, color, wins, kills}
var seq := 0
var pending: Array = []       # inputs not yet acknowledged by the server
var view_offset := Vector2.ZERO
var snapshots := 0
var last_snap_tick := 0
var nodes := {}               # peer id -> PlayerView
var samples := {}             # peer id -> interpolation buffer
var bomb_nodes := {}          # bomb id -> BombView

# bot (headless smoke-test client)
var bot_dir: int = C.Dir.RIGHT
var bot_start_cell := Vector2i(-1, -1)
var bot_done := false

# Adapter handed to Sim on the server so completed digs are credited/broadcast.
class SrvWorld:
	var g
	var pid: int
	func _init(game_ref, id: int) -> void:
		g = game_ref
		pid = id
	func get_tile(c: Vector2i) -> int:
		return g.world_data.get_tile(c)
	func dig(c: Vector2i) -> void:
		g._srv_dug(pid, c)

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	Net.game = self
	view = WorldView.new()
	add_child(view)
	ents = Node2D.new()
	ents.z_index = 5
	add_child(ents)
	if Net.is_server:
		Net.peer_left.connect(_srv_peer_left)
		if not Net.is_dedicated:
			srv_hello(1, Net.player_name)
	else:
		Net.rx_hello.rpc_id(1, Net.player_name)
	if not Net.is_dedicated and not headless:
		hud = Hud.new()
		hud.game = self
		add_child(hud)
		cam = Camera2D.new()
		cam.zoom = Vector2(1.15, 1.15)
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = C.GRID_W * C.TILE
		cam.limit_bottom = C.GRID_H * C.TILE
		add_child(cam)
		cam.make_current()
	if Net.is_dedicated:
		print("[server] game ready, waiting for players")

func my_id() -> int:
	return multiplayer.get_unique_id()

func _physics_process(dt: float) -> void:
	tick += 1
	if Net.is_server:
		_server_tick(dt)
	if not Net.is_dedicated:
		_client_tick(dt)
	if bot:
		_bot_tick()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_match") and phase == C.Phase.LOBBY:
		request_start()
	if event.is_action_pressed("sel_1"):
		my_sel = C.Item.SMALL_BOMB
	if event.is_action_pressed("sel_2"):
		my_sel = C.Item.BIG_BOMB
	if event.is_action_pressed("sel_3"):
		my_sel = C.Item.REMOTE_BOMB

func request_start() -> void:
	if Net.is_server:
		srv_start_requested(1)
	else:
		Net.rx_start.rpc_id(1)

func buy(item: int) -> void:
	if Net.is_server:
		srv_buy(1, item)
	else:
		Net.rx_buy.rpc_id(1, item)

# =====================================================================
# SERVER
# =====================================================================

func _new_server_player(id: int, pname: String) -> Dictionary:
	var p := Sim.new_state(Vector2i(2, 2))
	p.merge({
		"id": id, "name": pname, "color": color_cursor % C.COLORS.size(),
		"hp": C.START_HP, "alive": false, "money": C.START_MONEY,
		"inv": {C.Item.SMALL_BOMB: 3}, "sel": C.Item.SMALL_BOMB,
		"last_seq": 0, "last_recv_seq": 0, "queue": [],
		"last_input": {"seq": 0, "dir": C.Dir.NONE, "acts": 0, "sel": C.Item.SMALL_BOMB},
		"prev_acts": 0, "revealed": {}, "pending_reveal": {},
		"wins": 0, "kills": 0,
	})
	color_cursor += 1
	return p

func srv_hello(id: int, pname: String) -> void:
	if sp.has(id):
		return
	var clean := pname.strip_edges().substr(0, 16)
	if clean.is_empty():
		clean = "Miner%d" % (sp.size() + 1)
	sp[id] = _new_server_player(id, clean)
	print("[server] %s joined (peer %d, %d players)" % [clean, id, sp.size()])
	_broadcast_meta()
	_send(id, &"sv_phase", [phase, phase_left, round_no])
	_send_inv(id)
	if phase == C.Phase.ACTIVE:
		_srv_spawn(id, sp.size() - 1)

func _srv_peer_left(id: int) -> void:
	if not Net.is_server or not sp.has(id):
		return
	print("[server] %s left (peer %d)" % [sp[id].name, id])
	sp.erase(id)
	_broadcast_meta()

func srv_start_requested(id: int) -> void:
	if phase != C.Phase.LOBBY:
		return
	if id != 1 and not Net.is_dedicated:
		return
	_set_phase(C.Phase.SHOP, C.SHOP_TIME)

func srv_input(id: int, bytes: PackedByteArray) -> void:
	var p = sp.get(id)
	if p == null or bytes.size() < 7:
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var s := buf.get_u32()
	if s <= p.last_recv_seq:
		return
	p.last_recv_seq = s
	var inp := {"seq": s, "dir": buf.get_u8(), "acts": buf.get_u8(), "sel": buf.get_u8()}
	if inp.dir > C.Dir.RIGHT:
		inp.dir = C.Dir.NONE
	p.queue.append(inp)
	# cap the backlog so a client can't burst inputs to move faster
	while p.queue.size() > 4:
		p.queue.pop_front()

func srv_buy(id: int, item: int) -> void:
	if phase != C.Phase.SHOP:
		return
	var p = sp.get(id)
	if p == null or not C.CATALOG.has(item):
		return
	var cost: int = C.CATALOG[item].cost
	if p.money < cost:
		return
	p.money -= cost
	match item:
		C.Item.DRILL:
			p.drill = true
		C.Item.MEDKIT:
			p.hp = mini(C.START_HP, p.hp + 50)
		_:
			p.inv[item] = p.inv.get(item, 0) + 1
	_send_inv(id)

func _server_tick(dt: float) -> void:
	match phase:
		C.Phase.SHOP:
			phase_left -= dt
			if phase_left <= 0.0:
				_srv_start_round()
		C.Phase.ACTIVE:
			phase_left -= dt
			_srv_sim(dt)
			if _srv_round_over():
				_srv_end_round()
		C.Phase.CLEANUP:
			phase_left -= dt
			if phase_left <= 0.0:
				_set_phase(C.Phase.SHOP, C.SHOP_TIME)
	if phase != C.Phase.LOBBY and tick % C.SNAPSHOT_EVERY == 0:
		_srv_flush_reveals()
		_srv_send_snapshots()

func _srv_sim(dt: float) -> void:
	for id in sp:
		var p: Dictionary = sp[id]
		if not p.alive:
			continue
		var inp: Dictionary
		if p.queue.size() > 0:
			inp = p.queue.pop_front()
			p.last_seq = inp.seq
			p.last_input = inp
		else:
			# packet loss: repeat held movement, never repeat actions
			inp = {"seq": p.last_seq, "dir": p.last_input.dir, "acts": 0, "sel": p.sel}
		p.sel = inp.sel
		var rising: int = inp.acts & ~p.prev_acts
		p.prev_acts = inp.acts
		var before: Vector2i = p.cell
		Sim.step(p, inp, SrvWorld.new(self, id), dt)
		if p.cell != before:
			_srv_reveal_around(id)
		if rising & C.ACT_PLANT:
			_srv_plant(id)
		if rising & C.ACT_DETONATE:
			_srv_detonate(id)
	for bid in bombs.keys().duplicate():
		if not bombs.has(bid):
			continue
		bombs[bid].fuse -= dt
		if bombs[bid].fuse <= 0.0:
			_srv_explode(bid)

func _srv_dug(id: int, c: Vector2i) -> void:
	var old := world_data.get_tile(c)
	world_data.set_tile(c, C.Tile.EMPTY)
	if old == C.Tile.GOLD and sp.has(id):
		sp[id].money += C.GOLD_VALUE
		_send_inv(id)
	dirty_cells[c] = true

func _srv_reveal_around(id: int) -> void:
	var p: Dictionary = sp[id]
	for dy in range(-C.REVEAL_RADIUS, C.REVEAL_RADIUS + 1):
		for dx in range(-C.REVEAL_RADIUS, C.REVEAL_RADIUS + 1):
			var c: Vector2i = p.cell + Vector2i(dx, dy)
			if world_data.in_bounds(c) and not p.revealed.has(c):
				p.revealed[c] = true
				p.pending_reveal[c] = true

func _srv_flush_reveals() -> void:
	for id in sp:
		var p: Dictionary = sp[id]
		for c in dirty_cells:
			if p.revealed.has(c):
				p.pending_reveal[c] = true
		if p.pending_reveal.size() > 0:
			var buf := StreamPeerBuffer.new()
			buf.put_u16(p.pending_reveal.size())
			for c in p.pending_reveal:
				buf.put_u8(c.x)
				buf.put_u8(c.y)
				buf.put_u8(world_data.get_tile(c))
			_send(id, &"sv_reveal", [buf.data_array])
			p.pending_reveal.clear()
	dirty_cells.clear()

func _srv_plant(id: int) -> void:
	var p: Dictionary = sp[id]
	var item: int = p.sel
	if not C.BOMB_STATS.has(item):
		return
	if p.inv.get(item, 0) <= 0:
		return
	for b in bombs.values():
		if b.cell == p.cell:
			return
	p.inv[item] -= 1
	var bid := next_bid
	next_bid += 1
	bombs[bid] = {"cell": p.cell, "type": item, "fuse": C.BOMB_STATS[item].fuse, "owner": id}
	for id2 in sp:
		if sp[id2].revealed.has(p.cell):
			_send(id2, &"sv_bomb", [bid, p.cell, item])
	_send_inv(id)

func _srv_detonate(id: int) -> void:
	for bid in bombs:
		if bombs[bid].owner == id and bombs[bid].type == C.Item.REMOTE_BOMB:
			bombs[bid].fuse = minf(bombs[bid].fuse, 0.05)

func _srv_explode(bid: int) -> void:
	var b: Dictionary = bombs[bid]
	bombs.erase(bid)
	var stats: Dictionary = C.BOMB_STATS[b.type]
	var r: float = stats.radius
	var center: Vector2i = b.cell
	var ri := int(ceilf(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if Vector2(dx, dy).length() > r:
				continue
			var c := center + Vector2i(dx, dy)
			var t := world_data.get_tile(c)
			if t == C.Tile.WALL or t == C.Tile.EMPTY:
				continue
			if t == C.Tile.ROCK and not stats.rock:
				continue
			world_data.set_tile(c, C.Tile.EMPTY)
			dirty_cells[c] = true
	for bid2 in bombs:
		if Vector2(bombs[bid2].cell - center).length() <= r:
			bombs[bid2].fuse = minf(bombs[bid2].fuse, 0.12)
	for id in sp:
		var p: Dictionary = sp[id]
		if not p.alive:
			continue
		var d := (Sim.pos_of(p) - C.cell_to_pos(center)).length() / float(C.TILE)
		if d <= r + 0.5:
			var dmg := int(stats.dmg * clampf(1.0 - d / (r + 1.0), 0.15, 1.0))
			_srv_damage(id, dmg, b.owner)
	_broadcast(&"sv_boom", [bid, center, r])

func _srv_damage(id: int, dmg: int, attacker: int) -> void:
	var p: Dictionary = sp[id]
	p.hp = maxi(0, p.hp - dmg)
	_send_inv(id)
	if p.hp == 0 and p.alive:
		p.alive = false
		var kname := "their own bomb"
		if attacker != id and sp.has(attacker):
			sp[attacker].kills += 1
			sp[attacker].money += C.KILL_BOUNTY
			_send_inv(attacker)
			kname = sp[attacker].name
		_broadcast(&"sv_event", ["death", {"victim": p.name, "killer": kname}])
		_broadcast_meta()

func _srv_spawn(id: int, idx: int) -> void:
	var p: Dictionary = sp[id]
	var spawns := world_data.spawn_cells()
	var c: Vector2i = spawns[idx % spawns.size()]
	p.cell = c
	p.target = c
	p.prog = 0.0
	p.dir = C.Dir.NONE
	p.alive = true
	p.hp = C.START_HP
	p.queue.clear()
	p.last_input = {"seq": p.last_seq, "dir": C.Dir.NONE, "acts": 0, "sel": p.sel}
	p.prev_acts = 0
	p.revealed = {}
	p.pending_reveal = {}
	_srv_reveal_around(id)

func _srv_start_round() -> void:
	round_no += 1
	world_data = WorldData.new()
	world_data.generate(randi())
	bombs.clear()
	dirty_cells.clear()
	_broadcast(&"sv_event", ["round_start", {"round": round_no}])
	var i := 0
	for id in sp:
		var p: Dictionary = sp[id]
		var total := 0
		for item in p.inv:
			total += p.inv[item]
		if total == 0:
			p.inv[C.Item.SMALL_BOMB] = 2
		_srv_spawn(id, i)
		i += 1
		_send_inv(id)
	_set_phase(C.Phase.ACTIVE, C.ROUND_TIME)

func _srv_round_over() -> bool:
	if phase_left <= 0.0:
		return true
	if sp.size() < 2:
		return false
	var alive := 0
	for id in sp:
		if sp[id].alive:
			alive += 1
	return alive <= 1

func _srv_end_round() -> void:
	var alive := []
	for id in sp:
		if sp[id].alive:
			alive.append(id)
	if alive.size() == 1 and sp.size() >= 2:
		var w: Dictionary = sp[alive[0]]
		w.wins += 1
		w.money += C.WIN_BONUS
		_send_inv(alive[0])
		_broadcast(&"sv_event", ["round_end", {"winner": w.name}])
	else:
		_broadcast(&"sv_event", ["round_end", {"winner": ""}])
	_broadcast_meta()
	_set_phase(C.Phase.CLEANUP, C.CLEANUP_TIME)

func _set_phase(p: int, dur: float) -> void:
	phase = p
	phase_left = dur
	_broadcast(&"sv_phase", [p, dur, round_no])
	if Net.is_dedicated:
		print("[server] phase -> %s" % C.PHASE_NAMES[p])

func _srv_send_snapshots() -> void:
	for id in sp:
		var p: Dictionary = sp[id]
		var list := [p]
		for id2 in sp:
			if id2 == id or not sp[id2].alive:
				continue
			var q: Dictionary = sp[id2]
			if maxi(absi(q.cell.x - p.cell.x), absi(q.cell.y - p.cell.y)) <= C.VIS_RADIUS:
				list.append(q)
		var buf := StreamPeerBuffer.new()
		buf.put_u32(tick)
		buf.put_u8(phase)
		buf.put_u16(clampi(int(maxf(phase_left, 0.0) * 10.0), 0, 65535))
		buf.put_u32(p.last_seq)
		buf.put_u8(list.size())
		for q in list:
			buf.put_32(q.id)
			buf.put_u8(1 if q.alive else 0)
			buf.put_u8(clampi(q.hp, 0, 255))
			buf.put_16(q.cell.x)
			buf.put_16(q.cell.y)
			buf.put_16(q.target.x)
			buf.put_16(q.target.y)
			buf.put_u16(int(clampf(q.prog, 0.0, 1.0) * 1000.0))
			buf.put_u8(q.dir)
		_send(id, &"sv_snapshot", [buf.data_array])

func _send_inv(id: int) -> void:
	var p: Dictionary = sp[id]
	_send(id, &"sv_inv", [p.inv, p.money, p.hp, p.get("drill", false)])

func _broadcast_meta() -> void:
	var m := {}
	for id in sp:
		var p: Dictionary = sp[id]
		m[id] = {"name": p.name, "color": p.color, "wins": p.wins, "kills": p.kills}
	_broadcast(&"sv_meta", [m])

# Route a server->client message: loopback for the host's own client half,
# RPC for remote peers.
func _send(id: int, method: StringName, args: Array) -> void:
	if id == 1 and Net.is_server:
		if not Net.is_dedicated:
			callv(String(method).replace("sv_", "cli_"), args)
		return
	Net.callv("rpc_id", [id, method] + args)

func _broadcast(method: StringName, args: Array) -> void:
	for id in sp:
		_send(id, method, args)

# =====================================================================
# CLIENT
# =====================================================================

func _client_tick(dt: float) -> void:
	phase_left = maxf(0.0, phase_left - dt)
	if phase == C.Phase.ACTIVE and my_alive and snapshots > 0:
		var inp := _gather_input()
		seq += 1
		inp.seq = seq
		pending.append(inp)
		while pending.size() > 120:
			pending.pop_front()
		Sim.step(me, inp, view, dt)
		var buf := StreamPeerBuffer.new()
		buf.put_u32(seq)
		buf.put_u8(inp.dir)
		buf.put_u8(inp.acts)
		buf.put_u8(inp.sel)
		if Net.is_server:
			srv_input(1, buf.data_array)
		else:
			Net.rx_input.rpc_id(1, buf.data_array)
	view_offset = view_offset.move_toward(Vector2.ZERO, (view_offset.length() * 6.0 + 20.0) * dt)
	_update_views()

func _gather_input() -> Dictionary:
	if bot:
		return _bot_input()
	var dir: int = C.Dir.NONE
	if Input.is_action_pressed("mv_up"):
		dir = C.Dir.UP
	elif Input.is_action_pressed("mv_down"):
		dir = C.Dir.DOWN
	elif Input.is_action_pressed("mv_left"):
		dir = C.Dir.LEFT
	elif Input.is_action_pressed("mv_right"):
		dir = C.Dir.RIGHT
	var acts := 0
	if Input.is_action_pressed("plant"):
		acts |= C.ACT_PLANT
	if Input.is_action_pressed("detonate"):
		acts |= C.ACT_DETONATE
	return {"dir": dir, "acts": acts, "sel": my_sel}

func cli_snapshot(bytes: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var t := buf.get_u32()
	if t <= last_snap_tick:
		return
	last_snap_tick = t
	snapshots += 1
	phase = buf.get_u8()
	phase_left = buf.get_u16() / 10.0
	var acked := buf.get_u32()
	var n := buf.get_u8()
	var now := Time.get_ticks_msec()
	for i in n:
		var id := buf.get_32()
		var alive := buf.get_u8() == 1
		var hp := buf.get_u8()
		var cell := Vector2i(buf.get_16(), buf.get_16())
		var target := Vector2i(buf.get_16(), buf.get_16())
		var prog := buf.get_u16() / 1000.0
		var dir := buf.get_u8()
		if id == my_id():
			_reconcile(cell, target, prog, dir, alive, hp, acked)
		else:
			if not samples.has(id):
				samples[id] = []
			var st := {"cell": cell, "target": target, "prog": prog}
			samples[id].append({"t": now, "pos": Sim.pos_of(st), "alive": alive})
			while samples[id].size() > 20:
				samples[id].pop_front()

func _reconcile(cell: Vector2i, target: Vector2i, prog: float, dir: int,
		alive: bool, hp: int, acked: int) -> void:
	my_hp = hp
	my_alive = alive
	var was_pos := Sim.pos_of(me) + view_offset
	me.cell = cell
	me.target = target
	me.prog = prog
	me.dir = dir
	while pending.size() > 0 and pending[0].seq <= acked:
		pending.pop_front()
	for inp in pending:
		Sim.step(me, inp, view, 1.0 / C.TICK_RATE)
	var err := was_pos - Sim.pos_of(me)
	view_offset = err if err.length() < C.TILE * 1.5 else Vector2.ZERO

func cli_phase(p: int, secs: float, rn: int) -> void:
	phase = p
	phase_left = secs
	round_no = rn

func cli_reveal(bytes: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var n := buf.get_u16()
	for i in n:
		var x := buf.get_u8()
		var y := buf.get_u8()
		var t := buf.get_u8()
		view.reveal(Vector2i(x, y), t)

func cli_bomb(bid: int, cell: Vector2i, type: int) -> void:
	if headless or bomb_nodes.has(bid):
		return
	var bn := BombView.new()
	bn.position = C.cell_to_pos(cell)
	ents.add_child(bn)
	bomb_nodes[bid] = bn

func cli_boom(bid: int, center: Vector2i, radius: float) -> void:
	if bomb_nodes.has(bid):
		bomb_nodes[bid].queue_free()
		bomb_nodes.erase(bid)
	if headless:
		return
	var fx := BoomFx.new()
	fx.radius_px = radius * C.TILE
	fx.position = C.cell_to_pos(center)
	fx.z_index = 11
	ents.add_child(fx)

func cli_inv(inv: Dictionary, money: int, hp: int, drill: bool) -> void:
	my_inv = inv
	my_money = money
	my_hp = hp
	me.drill = drill

func cli_meta(m: Dictionary) -> void:
	meta = m
	for id in nodes.keys().duplicate():
		if not meta.has(id):
			nodes[id].queue_free()
			nodes.erase(id)
			samples.erase(id)
	for id in nodes:
		_apply_meta(id)

func cli_event(kind: String, data: Dictionary) -> void:
	match kind:
		"round_start":
			view.reset()
			pending.clear()
			samples.clear()
			view_offset = Vector2.ZERO
			for id in nodes:
				if id != my_id():
					nodes[id].visible = false
			for bid in bomb_nodes:
				bomb_nodes[bid].queue_free()
			bomb_nodes.clear()
			if hud:
				hud.flash("Round %d — FIGHT!" % data.get("round", 1))
		"round_end":
			var w: String = data.get("winner", "")
			if hud:
				hud.flash("%s wins the round!" % w if w != "" else "Round over — draw!")
		"death":
			if hud:
				hud.killfeed("%s was blown up by %s" % [data.victim, data.killer])

func _ensure_node(id: int) -> void:
	if headless or nodes.has(id):
		return
	var pv := PlayerView.new()
	ents.add_child(pv)
	nodes[id] = pv
	_apply_meta(id)

func _apply_meta(id: int) -> void:
	if not nodes.has(id):
		return
	var info: Dictionary = meta.get(id, {})
	nodes[id].setup(info.get("name", "?"), C.COLORS[info.get("color", 7) % C.COLORS.size()])

func _update_views() -> void:
	if headless:
		return
	var mid := my_id()
	_ensure_node(mid)
	var mynode: PlayerView = nodes[mid]
	mynode.position = Sim.pos_of(me) + view_offset
	mynode.visible = my_alive
	cam.position = mynode.position
	var render_t := Time.get_ticks_msec() - C.INTERP_DELAY_MS
	for id in samples:
		_ensure_node(id)
		var node: PlayerView = nodes[id]
		var arr: Array = samples[id]
		if arr.is_empty() or arr.back().t < render_t - 400:
			node.visible = false
			continue
		var pos: Vector2 = arr.back().pos
		var alive: bool = arr.back().alive
		for i in range(arr.size() - 1, 0, -1):
			if arr[i - 1].t <= render_t and arr[i].t >= render_t:
				var a: Dictionary = arr[i - 1]
				var b: Dictionary = arr[i]
				var f := clampf(float(render_t - a.t) / maxf(1.0, float(b.t - a.t)), 0.0, 1.0)
				pos = a.pos.lerp(b.pos, f)
				alive = b.alive
				break
		node.position = pos
		node.visible = alive

# =====================================================================
# BOT — headless smoke-test client used by tests/run_smoke.sh
# =====================================================================

func _bot_input() -> Dictionary:
	if tick % 30 == 0:
		bot_dir = randi_range(C.Dir.UP, C.Dir.RIGHT)
	var acts := C.ACT_PLANT if tick % 240 == 120 else 0
	return {"dir": bot_dir, "acts": acts, "sel": C.Item.SMALL_BOMB}

func _bot_tick() -> void:
	if bot_done:
		return
	if phase == C.Phase.LOBBY and tick % 120 == 60:
		print("[bot] requesting match start")
		request_start()
	if phase == C.Phase.ACTIVE and snapshots > 0:
		if bot_start_cell == Vector2i(-1, -1):
			bot_start_cell = me.cell
			print("[bot] round active, spawned at %s" % str(bot_start_cell))
		elif me.cell != bot_start_cell and snapshots > (30 if headless else 300):
			print("[bot] moved %s -> %s after %d snapshots" % [str(bot_start_cell), str(me.cell), snapshots])
			if not headless:
				var img := get_viewport().get_texture().get_image()
				img.save_png("/tmp/mb_screenshot.png")
				print("[bot] screenshot saved")
			print("BOT_OK")
			bot_done = true
			get_tree().quit(0)
