class_name Hud
extends Control
## Oyun içi arayüz ve girdi: dokunmatik joystick, zıplama, kamera sürükleme,
## basılı tut = kır, dokun = yerleştir / kullan, hotbar. Masaüstünde fare + klavye.

const JOY_R := 90.0
const HOLD_TIME := 0.25   # bu süreden uzun basış kırmaya başlar
const TAP_MOVE := 16.0
const SLOT := 64.0
const TOUCH_SENS := 0.0055
const MOUSE_SENS := 0.0025

var game: Node
var player: Player
var touch_mode := false

var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_id := -1
var _look_start := Vector2.ZERO
var _look_pos := Vector2.ZERO
var _look_time := 0.0
var _look_moved := false
var _look_mining := false
var _mine_drag := false
var _ignored := {}   # bir ekran açıkken ya da kapanırken başlayan dokunuşlar: bırakılana kadar yok sayılır
var _jump_id := -1
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = Session.font


# ---------- Yerleşim ----------

func _slot_rect(i: int) -> Rect2:
	var x0 := (size.x - SLOT * Inventory.HOTBAR) * 0.5
	return Rect2(x0 + i * SLOT, size.y - SLOT - 10.0, SLOT, SLOT)


func _jump_center() -> Vector2:
	return Vector2(size.x - 130.0, size.y - 200.0)


func _view_rect() -> Rect2:
	return Rect2(size.x - 78.0, 14.0, 64.0, 64.0)


## Envanter butonu: hotbar'ın 9 yuvasının hemen sağında
func _inv_rect() -> Rect2:
	var last := _slot_rect(Inventory.HOTBAR - 1)
	return Rect2(last.end.x + 8.0, last.position.y, SLOT, SLOT)


## Karakter butonu: hotbar'ın hemen solunda, üzerinde level yazar
func _char_rect() -> Rect2:
	var first := _slot_rect(0)
	return Rect2(first.position.x - SLOT - 8.0, first.position.y, SLOT, SLOT)


func _menu_rect() -> Rect2:
	return Rect2(14.0, 14.0, 64.0, 64.0)


# ---------- Girdi ----------

func _blocked() -> bool:
	return game.paused or game.menu_open()


func _input(event: InputEvent) -> void:
	if touch_mode:
		# Ekranı kapatan dokunuş (ör. X butonu) aynı anda HUD'a da ulaşır; altındaki butonu tetiklememeli.
		var closing: bool = Engine.get_process_frames() - game.ui_closed_frame <= 1
		if event is InputEventScreenTouch:
			if event.pressed:
				if _blocked() or closing:
					_ignored[event.index] = true
				else:
					_ignored.erase(event.index)
					_touch_down(event.index, event.position)
			elif not _ignored.erase(event.index) and not _blocked():
				_touch_up(event.index)
		elif event is InputEventScreenDrag:
			if not _ignored.has(event.index) and not _blocked():
				_touch_drag(event.index, event.position, event.relative)
		return
	if _blocked():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		player.add_look(event.relative.x * MOUSE_SENS, event.relative.y * MOUSE_SENS)
	elif event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			game.place_at(size * 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.select_slot((game.selected + 1) % Inventory.HOTBAR)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.select_slot((game.selected + Inventory.HOTBAR - 1) % Inventory.HOTBAR)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			game.select_slot(k - KEY_1)
		elif k == KEY_F5 or k == KEY_V:
			player.toggle_view()
		elif k == KEY_E:
			game.open_ui(InventoryUI.MODE_INVENTORY)
		elif k == KEY_C:
			game.open_stats()
		elif k == KEY_ESCAPE:
			game.toggle_pause()


func _touch_down(id: int, p: Vector2) -> void:
	if _menu_rect().has_point(p):
		release_all()
		game.toggle_pause()
		return
	if _view_rect().has_point(p):
		player.toggle_view()
		return
	if _inv_rect().has_point(p):
		release_all()
		game.open_ui(InventoryUI.MODE_INVENTORY)
		return
	if _char_rect().has_point(p):
		release_all()
		game.open_stats()
		return
	for i in Inventory.HOTBAR:
		if _slot_rect(i).has_point(p):
			game.select_slot(i)
			return
	if p.distance_to(_jump_center()) < 78.0:
		_jump_id = id
		player.jump_held = true
		return
	if _joy_id == -1 and p.x < size.x * 0.4 and p.y > size.y * 0.3:
		_joy_id = id
		_joy_origin = p
		_joy_vec = Vector2.ZERO
		return
	if _look_id == -1:
		_look_id = id
		_look_start = p
		_look_pos = p
		_look_time = 0.0
		_look_moved = false
		_look_mining = false
		_mine_drag = false


func _touch_up(id: int) -> void:
	if id == _jump_id:
		_jump_id = -1
		player.jump_held = false
	elif id == _joy_id:
		_joy_id = -1
		_joy_vec = Vector2.ZERO
		player.move_input = Vector2.ZERO
	elif id == _look_id:
		_look_id = -1
		if not _look_moved and not _look_mining:
			game.place_at(_look_pos)   # kısa dokunuş: blok yerleştir / masayı-fırını aç
		_look_mining = false


func _touch_drag(id: int, p: Vector2, rel: Vector2) -> void:
	if id == _joy_id:
		_joy_vec = ((p - _joy_origin) / JOY_R).limit_length(1.0)
		player.move_input = Vector2(_joy_vec.x, -_joy_vec.y)
	elif id == _look_id:
		_look_pos = p
		if _look_mining:
			# Kazarken de parmağı sürükleyerek etrafa bakılabilir (küçük titremeler yok sayılır).
			if _mine_drag or p.distance_to(_look_start) > TAP_MOVE:
				_mine_drag = true
				player.add_look(rel.x * TOUCH_SENS, rel.y * TOUCH_SENS)
			return
		if not _look_moved and p.distance_to(_look_start) > TAP_MOVE:
			_look_moved = true
		if _look_moved:
			player.add_look(rel.x * TOUCH_SENS, rel.y * TOUCH_SENS)


func release_all() -> void:
	_joy_id = -1
	_look_id = -1
	_look_mining = false
	_jump_id = -1
	_joy_vec = Vector2.ZERO
	if player != null:
		player.move_input = Vector2.ZERO
		player.jump_held = false


func _process(delta: float) -> void:
	if _blocked():
		pass
	elif touch_mode:
		if _look_id != -1 and not _look_moved:
			_look_time += delta
			if _look_time >= HOLD_TIME:
				_look_mining = true
		if _look_mining:
			game.mine_at(_look_pos, delta)   # basılı tut: bloğu kademeli kır
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		game.mine_at(size * 0.5, delta)
	queue_redraw()


# ---------- Çizim ----------

func _draw() -> void:
	var white := Color(1, 1, 1, 0.85)
	var dark := Color(0, 0, 0, 0.45)
	if game.hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, 0.35 * game.hurt_flash))
	if not touch_mode:
		var c := size * 0.5
		draw_line(c - Vector2(11, 0), c + Vector2(11, 0), white, 2.0)
		draw_line(c - Vector2(0, 11), c + Vector2(0, 11), white, 2.0)
	# Hotbar: envanterin ilk 9 yuvası
	var inv: Inventory = game.inv
	for i in Inventory.HOTBAR:
		var r := _slot_rect(i)
		draw_rect(r, dark)
		var id := inv.id_at(i)
		if id > 0:
			Items.draw_icon(self, r.grow(-9.0), id)
			Items.draw_dur_bar(self, r.grow(-9.0), id, inv.durs[i])
			var n := inv.counts[i]
			if n > 1:
				var pos := Vector2(r.position.x, r.end.y - 6.0)
				draw_string(_font, pos + Vector2(1.5, 1.5), str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5.0, 20, Color(0, 0, 0, 0.8))
				draw_string(_font, pos, str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5.0, 20, Color.WHITE)
		draw_rect(r, Color(0.75, 0.75, 0.75, 0.8), false, 2.0)
	var sel := _slot_rect(game.selected).grow(3.0)
	draw_rect(sel, Color(1, 1, 1), false, 4.0)
	var held_id := inv.id_at(game.selected)
	var held_name := Items.item_name(held_id)
	if Items.kind(held_id) == "sword":
		var need := int(Items.prop(held_id, "lvl", 0))
		if game.stats.level >= need:
			held_name += "  (+%d hasar)" % int(Items.prop(held_id, "dmg", 0))
		else:
			held_name += "  (level %d gerekli)" % need
	if held_name != "":
		draw_string(_font, Vector2(0, sel.position.y - 40.0), held_name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, white)
	_draw_health()
	_draw_level()
	_draw_buffs()
	var boss: Mob = game.boss_shown()
	if boss != null:
		var bb := Rect2(size.x * 0.5 - 260.0, 146.0, 520.0, 30.0)
		draw_rect(bb, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bb.position, Vector2(bb.size.x * clampf(boss.hp / boss.max_hp, 0.0, 1.0), bb.size.y)), Color(0.6, 0.1, 0.55))
		draw_rect(bb, Color(1, 1, 1, 0.85), false, 2.0)
		draw_string(_font, Vector2(bb.position.x, bb.position.y + 23.0), "%s   %d / %d" % [boss.def["n"], ceili(boss.hp), boss.max_hp], HORIZONTAL_ALIGNMENT_CENTER, bb.size.x, 22, Color.WHITE)
	if game.toast_timer > 0.0:
		var ta := clampf(game.toast_timer, 0.0, 1.0)
		draw_string(_font, Vector2(2, 112.0), game.toast_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(0, 0, 0, 0.7 * ta))
		draw_string(_font, Vector2(0, 110.0), game.toast_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(1.0, 0.9, 0.3, ta))
	if game.death_timer > 0.0:
		var a := clampf(game.death_timer, 0.0, 1.0)
		draw_rect(Rect2(0, size.y * 0.5 - 90.0, size.x, 150.0), Color(0.25, 0.0, 0.0, 0.6 * a))
		draw_string(_font, Vector2(0, size.y * 0.5 - 20.0), "Öldün!", HORIZONTAL_ALIGNMENT_CENTER, size.x, 56, Color(1, 0.35, 0.3, a))
		draw_string(_font, Vector2(0, size.y * 0.5 + 30.0), "Eşyaların ve XP'n silindi, statların 1'er puan düştü", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 1, 1, a))
	# Envanter butonu: 3x3 ızgara simgesi
	var ir := _inv_rect()
	_button(ir, "")
	for gy in 3:
		for gx in 3:
			draw_rect(Rect2(ir.position + Vector2(13.0 + gx * 13.0, 13.0 + gy * 13.0), Vector2(11.0, 11.0)), Color(1, 1, 1, 0.85))
	if Session.show_fps:
		var fx := 92.0 if touch_mode else 14.0
		var fps_text := "%d FPS" % int(Engine.get_frames_per_second())
		draw_string(_font, Vector2(fx + 1.5, 43.5), fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.7))
		draw_string(_font, Vector2(fx, 42.0), fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 0.6, 0.95))
	# Üst bilgi
	if game.info_text != "":
		draw_string(_font, Vector2(0, 46.0), game.info_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, white)
	if not touch_mode:
		return
	# Dokunmatik butonlar
	_button(_menu_rect(), "II")
	_button(_view_rect(), "3." if not player.third_person else "1.")
	var jc := _jump_center()
	draw_circle(jc, 62.0, Color(0, 0, 0, 0.55 if _jump_id != -1 else 0.35))
	draw_arc(jc, 62.0, 0, TAU, 40, white, 3.0)
	draw_string(_font, jc + Vector2(-62.0, 9.0), "ZIPLA", HORIZONTAL_ALIGNMENT_CENTER, 124.0, 22, white)
	# Joystick
	var base := _joy_origin if _joy_id != -1 else Vector2(170.0, size.y - 190.0)
	draw_circle(base, JOY_R, Color(0, 0, 0, 0.3))
	draw_arc(base, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0)
	draw_circle(base + _joy_vec * JOY_R, 38.0, Color(1, 1, 1, 0.55))


## Can barı: hotbar'ın sol üstünde. Yemek can doldururken açık renkli bir uç görünür.
func _draw_health() -> void:
	var st: PlayerStats = game.stats
	var first := _slot_rect(0)
	var bar := Rect2(first.position.x, first.position.y - 30.0, SLOT * 4.0, 22.0)
	var full := float(st.max_hp())
	var f := clampf(st.hp / full, 0.0, 1.0)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	if st.heal_left() > 0.0:
		var f2 := clampf((st.hp + st.heal_left()) / full, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f2, bar.size.y)), Color(1.0, 0.6, 0.6, 0.7))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(0.85, 0.12, 0.12))
	draw_rect(bar, Color(1, 1, 1, 0.8), false, 2.0)
	draw_string(_font, Vector2(bar.position.x, bar.position.y + 17.0), "%d / %d" % [ceili(st.hp), int(full)], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 17, Color.WHITE)


## Etkin iksirler: sol üstte, menü butonunun altında kalan süreleriyle listelenir.
func _draw_buffs() -> void:
	var st: PlayerStats = game.stats
	var y := 104.0
	for stat: String in PlayerStats.STATS:
		if not st.buffs.has(stat):
			continue
		var left := ceili(float(st.buffs[stat][1]))
		var text := "%s +%d   %d:%02d" % [PlayerStats.STAT_NAMES[stat], int(st.buffs[stat][0]), left / 60, left % 60]
		var col: Color = {"attack": Color(1.0, 0.45, 0.4), "intel": Color(0.55, 0.65, 1.0), "health": Color(0.5, 0.95, 0.55), "speed": Color(1.0, 0.9, 0.4)}[stat]
		if left <= 10 and left % 2 == 0:
			col.a = 0.45   # bitmek üzere: yanıp söner
		draw_rect(Rect2(14.0, y - 22.0, 250.0, 30.0), Color(0, 0, 0, 0.4))
		draw_string(_font, Vector2(22.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		y += 34.0


## XP çubuğu (hotbar'ın sağ üstünde) ve karakter butonu.
func _draw_level() -> void:
	var st: PlayerStats = game.stats
	var s5 := _slot_rect(5)
	var bar := Rect2(s5.position.x, s5.position.y - 30.0, SLOT * 4.0, 22.0)
	var need := st.xp_needed()
	var f := clampf(float(st.xp) / need, 0.0, 1.0) if need > 0 else 1.0
	draw_rect(bar, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(0.3, 0.75, 0.2))
	draw_rect(bar, Color(1, 1, 1, 0.8), false, 2.0)
	var label := "XP %d / %d" % [st.xp, need] if need > 0 else "En yüksek level"
	draw_string(_font, Vector2(bar.position.x, bar.position.y + 17.0), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 17, Color.WHITE)
	var cr := _char_rect()
	draw_rect(cr, Color(0, 0, 0, 0.4))
	var has_points := st.points > 0
	draw_rect(cr, Color(1.0, 0.85, 0.2) if has_points else Color(1, 1, 1, 0.7), false, 4.0 if has_points else 2.0)
	draw_string(_font, Vector2(cr.position.x, cr.position.y + 22.0), "Level", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 15, Color(1, 1, 1, 0.9))
	draw_string(_font, Vector2(cr.position.x, cr.position.y + 54.0), str(st.level), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 30, Color(1, 1, 1, 0.95))
	if has_points:
		draw_circle(Vector2(cr.end.x - 4.0, cr.position.y + 4.0), 13.0, Color(1.0, 0.85, 0.2))
		draw_string(_font, Vector2(cr.end.x - 17.0, cr.position.y + 11.0), "+", HORIZONTAL_ALIGNMENT_CENTER, 26.0, 22, Color(0.15, 0.1, 0.0))


func _button(r: Rect2, text: String) -> void:
	draw_rect(r, Color(0, 0, 0, 0.4))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	if text != "":
		draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 10.0), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, Color(1, 1, 1, 0.9))
