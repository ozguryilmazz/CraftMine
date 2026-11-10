class_name Hud
extends Control
## Oyun içi arayüz ve girdi: dokunmatik joystick, zıplama, kamera sürükleme,
## basılı tut = kır, dokun = yerleştir, hotbar. Masaüstünde fare + klavye.

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
var _jump_id := -1
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font


# ---------- Yerleşim ----------

func _slot_rect(i: int) -> Rect2:
	var x0 := (size.x - SLOT * Blocks.HOTBAR.size()) * 0.5
	return Rect2(x0 + i * SLOT, size.y - SLOT - 10.0, SLOT, SLOT)


func _jump_center() -> Vector2:
	return Vector2(size.x - 130.0, size.y - 200.0)


func _view_rect() -> Rect2:
	return Rect2(size.x - 78.0, 14.0, 64.0, 64.0)


func _menu_rect() -> Rect2:
	return Rect2(14.0, 14.0, 64.0, 64.0)


# ---------- Girdi ----------

func _input(event: InputEvent) -> void:
	if game.paused:
		return
	if touch_mode:
		if event is InputEventScreenTouch:
			if event.pressed:
				_touch_down(event.index, event.position)
			else:
				_touch_up(event.index)
		elif event is InputEventScreenDrag:
			_touch_drag(event.index, event.position, event.relative)
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
			game.select_slot((game.selected + 1) % Blocks.HOTBAR.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.select_slot((game.selected + Blocks.HOTBAR.size() - 1) % Blocks.HOTBAR.size())
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			game.select_slot(k - KEY_1)
		elif k == KEY_F5 or k == KEY_V:
			player.toggle_view()
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
	for i in Blocks.HOTBAR.size():
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
			game.place_at(_look_pos)   # kısa dokunuş: blok yerleştir
		_look_mining = false


func _touch_drag(id: int, p: Vector2, rel: Vector2) -> void:
	if id == _joy_id:
		_joy_vec = ((p - _joy_origin) / JOY_R).limit_length(1.0)
		player.move_input = Vector2(_joy_vec.x, -_joy_vec.y)
	elif id == _look_id:
		_look_pos = p
		if _look_mining:
			return   # kırarken parmağı kaydırmak hedefi değiştirir, kamerayı döndürmez
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
	if game.paused:
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
	if not touch_mode:
		var c := size * 0.5
		draw_line(c - Vector2(11, 0), c + Vector2(11, 0), white, 2.0)
		draw_line(c - Vector2(0, 11), c + Vector2(0, 11), white, 2.0)
	# Hotbar
	var tex := Atlas.texture()
	for i in Blocks.HOTBAR.size():
		var r := _slot_rect(i)
		draw_rect(r, dark)
		var block: int = Blocks.HOTBAR[i]
		var icon := r.grow(-11.0)
		if block == Blocks.TORCH:
			icon = Rect2(r.position.x + r.size.x * 0.5 - 11.0, r.position.y + 10.0, 22.0, r.size.y - 20.0)
		draw_texture_rect_region(tex, icon, Atlas.icon_region(block))
		draw_rect(r, Color(0.75, 0.75, 0.75, 0.8), false, 2.0)
	var sel := _slot_rect(game.selected).grow(3.0)
	draw_rect(sel, Color(1, 1, 1), false, 4.0)
	var bname: String = Blocks.NAMES[Blocks.HOTBAR[game.selected]]
	draw_string(_font, Vector2(0, sel.position.y - 12.0), bname, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, white)
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


func _button(r: Rect2, text: String) -> void:
	draw_rect(r, Color(0, 0, 0, 0.4))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 10.0), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, Color(1, 1, 1, 0.9))
