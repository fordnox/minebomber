extends Node
# Autoload "Net" — connection lifecycle plus every RPC endpoint.
#
# All network messages route through this autoload so client and server always
# agree on the RPC node path, regardless of scene structure. Message bodies for
# high-rate traffic (inputs, snapshots, reveals) are hand-packed binary
# (PackedByteArray via StreamPeerBuffer), not Variant dictionaries.
#
# Convention: rx_* are client -> server, sv_* are server -> client.
# The Game node registers itself as `Net.game` and receives everything.

signal peer_joined(id: int)
signal peer_left(id: int)
signal connected_ok
signal join_failed
signal server_closed

const DEFAULT_PORT := 7777

var game: Node = null
var is_server := false
var is_dedicated := false
var player_name := "Miner"

func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	multiplayer.connected_to_server.connect(func(): connected_ok.emit())
	multiplayer.connection_failed.connect(func(): join_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_closed.emit())

func host(port: int, dedicated: bool) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	is_dedicated = dedicated
	return OK

func join(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	return OK

# ---------- client -> server ----------

@rpc("any_peer", "call_remote", "reliable")
func rx_hello(pname: String) -> void:
	if game and is_server:
		game.srv_hello(multiplayer.get_remote_sender_id(), pname)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rx_input(bytes: PackedByteArray) -> void:
	if game and is_server:
		game.srv_input(multiplayer.get_remote_sender_id(), bytes)

@rpc("any_peer", "call_remote", "reliable")
func rx_buy(item: int) -> void:
	if game and is_server:
		game.srv_buy(multiplayer.get_remote_sender_id(), item)

@rpc("any_peer", "call_remote", "reliable")
func rx_start() -> void:
	if game and is_server:
		game.srv_start_requested(multiplayer.get_remote_sender_id())

# ---------- server -> client ----------

@rpc("authority", "call_remote", "unreliable_ordered")
func sv_snapshot(bytes: PackedByteArray) -> void:
	if game:
		game.cli_snapshot(bytes)

@rpc("authority", "call_remote", "reliable")
func sv_phase(phase: int, secs: float, round_no: int) -> void:
	if game:
		game.cli_phase(phase, secs, round_no)

@rpc("authority", "call_remote", "reliable")
func sv_reveal(bytes: PackedByteArray) -> void:
	if game:
		game.cli_reveal(bytes)

@rpc("authority", "call_remote", "reliable")
func sv_bomb(bid: int, cell: Vector2i, type: int) -> void:
	if game:
		game.cli_bomb(bid, cell, type)

@rpc("authority", "call_remote", "reliable")
func sv_boom(bid: int, center: Vector2i, radius: float) -> void:
	if game:
		game.cli_boom(bid, center, radius)

@rpc("authority", "call_remote", "reliable")
func sv_inv(inv: Dictionary, money: int, hp: int, drill: bool) -> void:
	if game:
		game.cli_inv(inv, money, hp, drill)

@rpc("authority", "call_remote", "reliable")
func sv_meta(meta: Dictionary) -> void:
	if game:
		game.cli_meta(meta)

@rpc("authority", "call_remote", "reliable")
func sv_event(kind: String, data: Dictionary) -> void:
	if game:
		game.cli_event(kind, data)
