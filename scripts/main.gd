extends Node
# Entry point. Parses CLI user args (after "--"):
#   --server [--port N]        dedicated headless server
#   --join <ip> [--port N]     connect directly, skipping the menu
#   --bot                      with --join: headless smoke-test client
# With no args: shows the main menu.

var menu: CanvasLayer
var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var pending_bot := false

func _ready() -> void:
	_ensure_actions()
	Net.connected_ok.connect(_on_connected)
	Net.join_failed.connect(_on_join_failed)
	Net.server_closed.connect(_on_server_closed)
	var args := OS.get_cmdline_user_args()
	var port := Net.DEFAULT_PORT
	var pi := args.find("--port")
	if pi != -1 and pi + 1 < args.size():
		port = int(args[pi + 1])
	if args.has("--server"):
		if Net.host(port, true) != OK:
			push_error("[server] failed to bind port %d" % port)
			get_tree().quit(1)
			return
		print("[server] listening on port %d" % port)
		_start_game()
		return
	if args.has("--host"):
		pending_bot = args.has("--bot")
		if Net.host(port, false) != OK:
			push_error("failed to bind port %d" % port)
			get_tree().quit(1)
			return
		_start_game()
		return
	var ji := args.find("--join")
	if ji != -1 and ji + 1 < args.size():
		pending_bot = args.has("--bot")
		Net.player_name = "Bot" if pending_bot else Net.player_name
		if Net.join(args[ji + 1], port) != OK:
			print("BOT_FAIL connect_error")
			get_tree().quit(1)
		if pending_bot:
			get_tree().create_timer(30.0).timeout.connect(_bot_timeout)
		return
	_build_menu()

func _bot_timeout() -> void:
	print("BOT_FAIL timeout")
	get_tree().quit(1)

func _on_connected() -> void:
	_start_game()

func _on_join_failed() -> void:
	if pending_bot:
		print("BOT_FAIL connection_failed")
		get_tree().quit(1)
		return
	if status_label:
		status_label.text = "Connection failed."

func _on_server_closed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().reload_current_scene()

func _start_game() -> void:
	if menu:
		menu.queue_free()
		menu = null
	var g := Game.new()
	g.name = "Game"
	g.bot = pending_bot
	add_child(g)

func _host_pressed() -> void:
	_apply_name()
	if Net.host(Net.DEFAULT_PORT, false) != OK:
		status_label.text = "Could not bind port %d (already hosting?)" % Net.DEFAULT_PORT
		return
	_start_game()

func _join_pressed() -> void:
	_apply_name()
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	status_label.text = "Connecting to %s..." % ip
	if Net.join(ip, Net.DEFAULT_PORT) != OK:
		status_label.text = "Invalid address."

func _apply_name() -> void:
	var n := name_edit.text.strip_edges()
	if not n.is_empty():
		Net.player_name = n

func _build_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(360, 0)
	center.add_child(v)

	var title := Label.new()
	title.text = "MINE BOMBERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
	v.add_child(title)
	var sub := Label.new()
	sub.text = "dig · loot · detonate — a 1996 classic, rebuilt"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	v.add_child(sub)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.text = Net.player_name
	v.add_child(name_edit)

	var host_btn := Button.new()
	host_btn.text = "HOST GAME"
	host_btn.pressed.connect(_host_pressed)
	v.add_child(host_btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Server IP (127.0.0.1)"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ip_edit)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.pressed.connect(_join_pressed)
	row.add_child(join_btn)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(1, 0.7, 0.6)
	v.add_child(status_label)

	var help := Label.new()
	help.text = "Dedicated server:  godot --headless -- --server --port 7777"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.4)
	help.add_theme_font_size_override("font_size", 12)
	v.add_child(help)

func _ensure_actions() -> void:
	var defs := {
		"mv_up": [KEY_W, KEY_UP],
		"mv_down": [KEY_S, KEY_DOWN],
		"mv_left": [KEY_A, KEY_LEFT],
		"mv_right": [KEY_D, KEY_RIGHT],
		"plant": [KEY_SPACE],
		"detonate": [KEY_E],
		"start_match": [KEY_ENTER],
		"sel_1": [KEY_1],
		"sel_2": [KEY_2],
		"sel_3": [KEY_3],
	}
	for a in defs:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in defs[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
