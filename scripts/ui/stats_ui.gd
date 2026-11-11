class_name StatsUI
extends Control
## Karakter ekranı: level, XP, statlar ve stat puanı dağıtma. Dokunmatik ve fare aynı şekilde çalışır.

const W := 760.0
const ROW := 78.0
const PAD := 28.0

var game: Node
var stats: PlayerStats

var _panel := Rect2()
var _close := Rect2()
var _plus: Array[Rect2] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	game.on_ui_closed()


func _layout() -> void:
	var h := 150.0 + ROW * 4.0 + 60.0
	_panel = Rect2(((size - Vector2(W, h)) * 0.5).floor(), Vector2(W, h))
	_close = Rect2(_panel.end.x - 60.0, _panel.position.y + 6.0, 52.0, 44.0)
	_plus.clear()
	for i in 4:
		_plus.append(Rect2(_panel.end.x - PAD - 84.0, _panel.position.y + 150.0 + i * ROW + 6.0, 84.0, ROW - 14.0))


## i. stata (PlayerStats.STATS sırası) bir puan ekler.
func add_point(i: int) -> void:
	stats.spend(PlayerStats.STATS[i])


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_C or event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	accept_event()
	_layout()
	if _close.has_point(event.position):
		close()
		return
	for i in 4:
		if _plus[i].has_point(event.position):
			add_point(i)
			return


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _effect(stat: String) -> String:
	match stat:
		"health":
			return "En yüksek can: %d" % stats.max_hp()
		"attack":
			return "Vuruş hasarı: %d (silahsız)" % stats.hit_damage()
		"speed":
			return "Hareket hızı: +%%%d" % roundi((stats.speed_mult() - 1.0) * 100.0)
	return "Kritik: %%%d (+%d hasar)   Sekme: %%%d" % [roundi(stats.crit_chance() * 100.0), stats.crit_bonus(), roundi(stats.miss_chance() * 100.0)]


func _draw() -> void:
	_layout()
	var font := Session.font
	var ink := Color(0.18, 0.18, 0.18)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(_panel, Color(0.78, 0.78, 0.78))
	draw_rect(_panel, Color(0.2, 0.2, 0.2), false, 3.0)
	var x := _panel.position.x + PAD
	var y := _panel.position.y
	draw_string(font, Vector2(x, y + 39.0), "Karakter", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_rect(_close, Color(0.62, 0.2, 0.2))
	draw_string(font, Vector2(_close.position.x, _close.position.y + 32.0), "X", HORIZONTAL_ALIGNMENT_CENTER, _close.size.x, 26, Color.WHITE)
	# Level ve XP
	var need := stats.xp_needed()
	draw_string(font, Vector2(x, y + 86.0), "Level %d" % stats.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	var bar := Rect2(x + 150.0, y + 62.0, W - 2.0 * PAD - 150.0, 30.0)
	draw_rect(bar, Color(0.35, 0.35, 0.35))
	var f := clampf(float(stats.xp) / need, 0.0, 1.0) if need > 0 else 1.0
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(0.3, 0.75, 0.2))
	draw_rect(bar, Color(0.2, 0.2, 0.2), false, 2.0)
	var label := "XP %d / %d" % [stats.xp, need] if need > 0 else "En yüksek level"
	draw_string(font, Vector2(bar.position.x, bar.position.y + 23.0), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 20, Color.WHITE)
	var pts_col := Color(0.55, 0.35, 0.0) if stats.points > 0 else ink
	draw_string(font, Vector2(x, y + 132.0), "Dağıtılacak puan: %d" % stats.points, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, pts_col)
	# Statlar
	for i in 4:
		var stat: String = PlayerStats.STATS[i]
		var ry := y + 150.0 + i * ROW
		draw_rect(Rect2(x - 8.0, ry, W - 2.0 * PAD + 16.0, ROW - 6.0), Color(0.68, 0.68, 0.68))
		var val := "%s: %d" % [PlayerStats.STAT_NAMES[stat], stats.shown(stat)]
		if stats.buffs.has(stat):
			val += "  (iksir +%d, %d sn)" % [int(stats.buffs[stat][0]), ceili(float(stats.buffs[stat][1]))]
		draw_string(font, Vector2(x + 6.0, ry + 32.0), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		draw_string(font, Vector2(x + 6.0, ry + 60.0), _effect(stat), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.3, 0.3, 0.3))
		var pr := _plus[i]
		var on := stats.points > 0
		draw_rect(pr, Color(0.25, 0.55, 0.25) if on else Color(0.5, 0.5, 0.5))
		draw_rect(pr, Color(0.2, 0.2, 0.2), false, 2.0)
		draw_string(font, Vector2(pr.position.x, pr.position.y + pr.size.y * 0.5 + 13.0), "+", HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 38, Color.WHITE if on else Color(0.7, 0.7, 0.7))
	draw_string(font, Vector2(x, _panel.end.y - 22.0), "Kakacoin: %d" % int(game.pdata.get("coins", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
