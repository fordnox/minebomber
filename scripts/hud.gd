class_name Hud
extends CanvasLayer
# In-game UI: status bar, phase timer, scoreboard, kill feed, shop panel,
# center messages. Reads state straight off the Game node every frame.

var game: Game

var money_label: Label
var hp_label: Label
var inv_label: Label
var phase_label: Label
var score_label: Label
var center_label: Label
var help_label: Label
var feed: VBoxContainer
var shop_panel: PanelContainer
var shop_money: Label
var shop_rows := {}   # item id -> {label, button}

func _ready() -> void:
	layer = 20
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 8
	top.add_theme_constant_override("separation", 24)
	add_child(top)

	money_label = _mklabel(top, 18, Color(1.0, 0.85, 0.3))
	hp_label = _mklabel(top, 18, Color(0.4, 0.95, 0.4))
	inv_label = _mklabel(top, 15, Color(0.9, 0.9, 0.9))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	phase_label = _mklabel(top, 18, Color(0.95, 0.95, 1.0))

	score_label = Label.new()
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -260
	score_label.offset_top = 40
	score_label.offset_right = -12
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 13)
	add_child(score_label)

	feed = VBoxContainer.new()
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed.offset_left = -420
	feed.offset_top = 150
	feed.offset_right = -12
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(feed)

	center_label = Label.new()
	center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	center_label.offset_top = 140
	center_label.offset_left = -400
	center_label.offset_right = 400
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 26)
	center_label.add_theme_color_override("font_outline_color", Color.BLACK)
	center_label.add_theme_constant_override("outline_size", 6)
	add_child(center_label)

	help_label = Label.new()
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -30
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.modulate = Color(1, 1, 1, 0.6)
	help_label.text = "WASD/arrows move · Space plant bomb · E detonate remote · 1-3 select bomb"
	add_child(help_label)

	_build_shop()

func _mklabel(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

func _build_shop() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	shop_panel = PanelContainer.new()
	center.add_child(shop_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	shop_panel.add_child(v)
	var title := Label.new()
	title.text = "WEAPON SHOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
	shop_money = Label.new()
	shop_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_money.add_theme_font_size_override("font_size", 16)
	shop_money.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	v.add_child(shop_money)
	for item in C.CATALOG:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		v.add_child(row)
		var info := Label.new()
		info.custom_minimum_size = Vector2(420, 0)
		row.add_child(info)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 0)
		btn.pressed.connect(func(): game.buy(item))
		row.add_child(btn)
		shop_rows[item] = {"label": info, "button": btn}

func flash(text: String) -> void:
	center_label.text = text
	var tw := create_tween()
	center_label.modulate = Color.WHITE
	tw.tween_interval(2.5)
	tw.tween_property(center_label, "modulate", Color(1, 1, 1, 0), 0.8)

func killfeed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	feed.add_child(l)
	while feed.get_child_count() > 6:
		feed.get_child(0).free()
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())

func _process(_dt: float) -> void:
	if game == null:
		return
	money_label.text = "$%d" % game.my_money
	hp_label.text = "HP %d" % game.my_hp
	inv_label.text = _inv_text()
	phase_label.text = "%s  %d:%04.1f" % [C.PHASE_NAMES[game.phase],
		int(game.phase_left) / 60, fmod(game.phase_left, 60.0)]
	score_label.text = _score_text()
	shop_panel.get_parent().visible = game.phase == C.Phase.SHOP
	if game.phase == C.Phase.SHOP:
		shop_money.text = "Your gold: $%d — round starts in %ds" % [game.my_money, int(game.phase_left)]
		for item in shop_rows:
			var owned := 0
			if item == C.Item.DRILL:
				owned = 1 if game.me.get("drill", false) else 0
			else:
				owned = game.my_inv.get(item, 0)
			var cat: Dictionary = C.CATALOG[item]
			shop_rows[item].label.text = "%s — $%d   (%s)   owned: %d" % [cat.name, cat.cost, cat.desc, owned]
			shop_rows[item].button.text = "Buy"
			shop_rows[item].button.disabled = game.my_money < cat.cost
	if game.phase == C.Phase.LOBBY:
		center_label.modulate = Color.WHITE
		center_label.text = "LOBBY — %d player(s) connected\n%s" % [maxi(game.meta.size(), 1),
			"Press ENTER to start" if Net.is_server else "Waiting for host to start..."]
	elif game.phase == C.Phase.ACTIVE and not game.my_alive and game.snapshots > 0:
		center_label.modulate = Color.WHITE
		center_label.text = "You were blown up!\nSpectating until next round..."

func _inv_text() -> String:
	var parts := []
	var keys := {C.Item.SMALL_BOMB: "1:Small", C.Item.BIG_BOMB: "2:Big", C.Item.REMOTE_BOMB: "3:Remote"}
	for item in keys:
		var s: String = "%s x%d" % [keys[item], game.my_inv.get(item, 0)]
		if game.my_sel == item:
			s = "[%s]" % s
		parts.append(s)
	if game.me.get("drill", false):
		parts.append("DRILL")
	return "   ".join(parts)

func _score_text() -> String:
	var ids := game.meta.keys()
	ids.sort_custom(func(a, b): return game.meta[a].wins > game.meta[b].wins)
	var lines := []
	for id in ids:
		var m: Dictionary = game.meta[id]
		lines.append("%s   wins %d · kills %d" % [m.name, m.wins, m.kills])
	return "\n".join(lines)
