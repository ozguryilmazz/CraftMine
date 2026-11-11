class_name InventoryUI
extends Control
## Envanter, crafting ve fırın ekranı. Dokunmatik ve fare aynı şekilde çalışır:
##   - Yuvaya dokun: yığının tamamını ele al. Başka yuvaya dokun: bırak (aynı türse birleştir, farklıysa değiştir).
##   - Yuvaya basılı tut: yığının yarısını ele al (diğer yarısı yuvada kalır).
##   - Sürükle-bırak: yuvaya bas, parmağı başka yuvaya götür, bırak.
##   - Sonuç yuvasına dokun: tarifi üret, eşya envantere eklenir.
##   - Farede sağ tık: yarısını al / 1 adet bırak.

const SLOT := 62.0
const GAP := 4.0
const PAD := 24.0
const STEP := SLOT + GAP
const ICON_INSET := 8.0
const HALF_HOLD := 0.4        # yarısını almak için basılı tutma süresi (sn)
const MODE_INVENTORY := 0
const MODE_TABLE := 1
const MODE_FURNACE := 2
const SMELT_TIME := 2.0
const TITLES := ["Envanter", "Çalışma Masası", "Fırın"]

var game: Node
var inv: Inventory
var mode := MODE_INVENTORY

var _grid_ids := PackedInt32Array()     # 3x3 (2x2 modunda sol üst köşe kullanılır)
var _grid_counts := PackedInt32Array()
var _f_ids := PackedInt32Array()        # fırın: 0 girdi, 1 yakıt, 2 çıktı
var _f_counts := PackedInt32Array()
var _grid_durs := PackedInt32Array()    # ızgara ve fırındaki eşyaların kalan dayanıklılığı
var _f_durs := PackedInt32Array()
var _cur_id := 0                        # "elde" tutulan yığın
var _cur_n := 0
var _cur_dur := 0
var _fuel_left := 0.0
var _fuel_total := 1.0
var _progress := 0.0
var _slots: Array[Dictionary] = []
var _panel := Rect2()
var _close := Rect2()
var _hint := ""
var _pointer := Vector2.ZERO            # son dokunma / fare konumu
var _press_slot := -1                   # basılı tutulan yuva (_slots sırası)
var _press_time := 0.0
var _press_can_halve := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_grid_ids.resize(9)
	_grid_counts.resize(9)
	_f_ids.resize(3)
	_f_counts.resize(3)
	_grid_durs.resize(9)
	_f_durs.resize(3)
	visible = false


func open(p_mode: int) -> void:
	mode = p_mode
	_hint = ""
	_progress = 0.0
	_press_slot = -1
	visible = true


## Ekranı kapatır; ızgarada, fırında ve elde kalan eşyalar envantere (sığmazsa yere) döner.
func close() -> void:
	if not visible:
		return
	for i in 9:
		_give_back(_grid_ids[i], _grid_counts[i], _grid_durs[i])
		_grid_ids[i] = 0
		_grid_counts[i] = 0
		_grid_durs[i] = 0
	for i in 3:
		_give_back(_f_ids[i], _f_counts[i], _f_durs[i])
		_f_ids[i] = 0
		_f_counts[i] = 0
		_f_durs[i] = 0
	_give_back(_cur_id, _cur_n, _cur_dur)
	_cur_id = 0
	_cur_n = 0
	_cur_dur = 0
	_fuel_left = 0.0
	_press_slot = -1
	visible = false
	game.on_ui_closed()


func _give_back(id: int, n: int, dur := -1) -> void:
	if id <= 0 or n <= 0:
		return
	var left := inv.add(id, n, dur)
	if left > 0:
		game.drop_from_player(id, left, dur)


# ---------- Yerleşim ----------

func _layout() -> void:
	var w := 9.0 * SLOT + 8.0 * GAP + 2.0 * PAD
	var h := 56.0 + 3.0 * STEP + 20.0 + 3.0 * STEP + 10.0 + SLOT + PAD
	_panel = Rect2(((size - Vector2(w, h)) * 0.5).floor(), Vector2(w, h))
	_close = Rect2(_panel.end.x - 60.0, _panel.position.y + 6.0, 52.0, 44.0)
	_slots.clear()
	var x0 := _panel.position.x + PAD
	var top := _panel.position.y + 56.0
	if mode == MODE_FURNACE:
		var gx := x0 + 2.0 * STEP
		_slot(gx, top, "f", 0)
		_slot(gx, top + 2.0 * STEP, "f", 1)
		_slot(gx + 4.0 * STEP, top + STEP, "fout", 2)
	else:
		var n := 3 if mode == MODE_TABLE else 2
		var gx := x0 + (1.0 if n == 3 else 1.5) * STEP
		var gy := top + (0.0 if n == 3 else 0.5 * STEP)
		for y in n:
			for x in n:
				_slot(gx + x * STEP, gy + y * STEP, "grid", y * 3 + x)
		_slot(gx + (n + 1.5) * STEP, top + STEP, "result", 0)
	var inv_top := top + 3.0 * STEP + 20.0
	for row in 3:
		for col in 9:
			_slot(x0 + col * STEP, inv_top + row * STEP, "inv", 9 + row * 9 + col)
	var hot_top := inv_top + 3.0 * STEP + 10.0
	for col in 9:
		_slot(x0 + col * STEP, hot_top, "inv", col)


func _slot(x: float, y: float, kind: String, i: int) -> void:
	_slots.append({"r": Rect2(x, y, SLOT, SLOT), "kind": kind, "i": i})


func _slot_at(p: Vector2) -> int:
	for si in _slots.size():
		if _slots[si]["r"].has_point(p):
			return si
	return -1


func _get_id(kind: String, i: int) -> int:
	match kind:
		"inv":
			return inv.id_at(i)
		"grid":
			return _grid_ids[i] if _grid_counts[i] > 0 else 0
	return _f_ids[i] if _f_counts[i] > 0 else 0


func _get_n(kind: String, i: int) -> int:
	match kind:
		"inv":
			return inv.counts[i]
		"grid":
			return _grid_counts[i]
	return _f_counts[i]


func _get_dur(kind: String, i: int) -> int:
	match kind:
		"inv":
			return inv.dur_at(i)
		"grid":
			return _grid_durs[i] if _grid_counts[i] > 0 else 0
	return _f_durs[i] if _f_counts[i] > 0 else 0


## dur: kalan dayanıklılık (-1: tam). Dayanıklılığı olmayan eşyalarda yok sayılır.
func _put(kind: String, i: int, id: int, n: int, dur := -1) -> void:
	if n <= 0:
		id = 0
		n = 0
	dur = Inventory._norm_dur(id, dur) if id > 0 else 0
	match kind:
		"inv":
			inv.set_slot(i, id, n, dur)
		"grid":
			_grid_ids[i] = id
			_grid_counts[i] = n
			_grid_durs[i] = dur
		_:
			_f_ids[i] = id
			_f_counts[i] = n
			_f_durs[i] = dur


func _recipe() -> Dictionary:
	var g := []
	for i in 9:
		g.append(_grid_ids[i] if _grid_counts[i] > 0 else 0)
	return Recipes.find(g, 3)


# ---------- Girdi ----------

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer = event.position
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	accept_event()
	_pointer = event.position
	_layout()
	var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	var si := _slot_at(event.position)
	if not event.pressed:
		# Sürükle-bırak: basılan yuvadan farklı bir yuvanın üzerinde bırakıldıysa oraya koy.
		if _press_slot != -1 and si != -1 and si != _press_slot and _cur_n > 0:
			var kind: String = _slots[si]["kind"]
			if kind != "result" and kind != "fout":
				_place(kind, _slots[si]["i"], false)
		_press_slot = -1
		return
	if _close.has_point(event.position):
		close()
		return
	if si == -1:
		return
	press(_slots[si]["kind"], _slots[si]["i"], right)
	if _cur_n > 0 and not right:
		_press_slot = si
		_press_time = 0.0


## Bir yuvaya basıldı. Eli boşsa yığını alır, doluysa bırakır.
func press(kind: String, i: int, right := false) -> void:
	_press_slot = -1
	_press_can_halve = false
	if kind == "result":
		_craft()
		return
	var id := _get_id(kind, i)
	var n := _get_n(kind, i)
	if kind == "fout":
		if n > 0:
			_put(kind, i, id, inv.add(id, n))
			_hint = Items.item_name(id)
		return
	if _cur_n > 0:
		_place(kind, i, right)
		return
	if n == 0:
		return
	var k := n if not right else ceili(n / 2.0)
	_cur_id = id
	_cur_n = k
	_cur_dur = _get_dur(kind, i)
	_put(kind, i, id, n - k)
	_press_can_halve = not right and k > 1
	_hint = "%s x%d" % [Items.item_name(id), k]


## Basılı tutulan yuvadan alınan yığının yarısını yuvaya geri bırakır (elde yarısı kalır).
func halve_held(kind: String, i: int) -> void:
	if _cur_n < 2 or _get_n(kind, i) != 0:
		return
	var back := _cur_n / 2
	_put(kind, i, _cur_id, back)
	_cur_n -= back
	_press_can_halve = false
	_hint = "%s x%d" % [Items.item_name(_cur_id), _cur_n]


## Eldeki yığını yuvaya bırakır. one: yalnızca 1 adet.
func _place(kind: String, i: int, one: bool) -> void:
	var id := _get_id(kind, i)
	var n := _get_n(kind, i)
	if n == 0:
		var k := 1 if one else _cur_n
		_put(kind, i, _cur_id, k, _cur_dur)
		_cur_n -= k
	elif id == _cur_id and Items.max_stack(id) > 1:
		var k := mini(1 if one else _cur_n, Items.max_stack(id) - n)
		_put(kind, i, id, n + k)
		_cur_n -= k
	else:
		var d := _get_dur(kind, i)
		_put(kind, i, _cur_id, _cur_n, _cur_dur)
		_cur_id = id
		_cur_n = n
		_cur_dur = d
	if _cur_n <= 0:
		_cur_id = 0
		_cur_n = 0
		_cur_dur = 0
		_hint = ""
	else:
		_hint = "%s x%d" % [Items.item_name(_cur_id), _cur_n]


func _craft() -> void:
	var r := _recipe()
	if r.is_empty():
		return
	var out: int = r["out"]
	var n: int = r["n"]
	if not inv.can_add(out, n):
		_hint = "Envanter dolu"
		return
	inv.add(out, n)
	for i in 9:
		if _grid_counts[i] > 0:
			_grid_counts[i] -= 1
			if _grid_counts[i] == 0:
				_grid_ids[i] = 0
				_grid_durs[i] = 0
	_hint = "%s x%d üretildi" % [Items.item_name(out), n]


# ---------- Döngü: basılı tutma ve fırın ----------

func _process(delta: float) -> void:
	if not visible:
		return
	if _press_slot != -1 and _press_can_halve:
		_layout()
		if _slot_at(_pointer) != _press_slot:
			_press_can_halve = false   # parmak yuvadan çıktı: sürükleme
		else:
			_press_time += delta
			if _press_time >= HALF_HOLD:
				halve_held(_slots[_press_slot]["kind"], _slots[_press_slot]["i"])
	if mode == MODE_FURNACE:
		var out := Recipes.smelt(_get_id("f", 0))
		var can := out != 0 and (_f_counts[2] == 0 or (_f_ids[2] == out and _f_counts[2] < 64))
		if can and _fuel_left <= 0.0:
			var fv := Recipes.fuel(_get_id("f", 1))
			if fv > 0.0:
				_put("f", 1, _f_ids[1], _f_counts[1] - 1)
				_fuel_left = fv
				_fuel_total = fv
		if _fuel_left > 0.0:
			_fuel_left -= delta
			if can:
				_progress += delta
				if _progress >= SMELT_TIME:
					_progress = 0.0
					_put("f", 0, _f_ids[0], _f_counts[0] - 1)
					_put("f", 2, out, _f_counts[2] + 1)
		if not can:
			_progress = 0.0
	queue_redraw()


# ---------- Çizim ----------

func _draw() -> void:
	_layout()
	var font := Session.font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(_panel, Color(0.78, 0.78, 0.78))
	draw_rect(_panel, Color(0.2, 0.2, 0.2), false, 3.0)
	var ink := Color(0.18, 0.18, 0.18)
	draw_string(font, _panel.position + Vector2(PAD, 39.0), TITLES[mode], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	if _hint != "":
		draw_string(font, _panel.position + Vector2(0, 39.0), _hint, HORIZONTAL_ALIGNMENT_RIGHT, _panel.size.x - 76.0, 22, ink)
	draw_rect(_close, Color(0.62, 0.2, 0.2))
	draw_string(font, Vector2(_close.position.x, _close.position.y + 32.0), "X", HORIZONTAL_ALIGNMENT_CENTER, _close.size.x, 26, Color.WHITE)
	var recipe := {} if mode == MODE_FURNACE else _recipe()
	for si in _slots.size():
		var s := _slots[si]
		var r: Rect2 = s["r"]
		var kind: String = s["kind"]
		draw_rect(r, Color(0.55, 0.55, 0.55))
		draw_rect(r, Color(0.3, 0.3, 0.3), false, 2.0)
		if kind == "result":
			if not recipe.is_empty():
				_item(r, recipe["out"], recipe["n"])
			_arrow(Vector2(r.position.x - STEP, r.position.y + SLOT * 0.5), 1.0)
		else:
			_item(r, _get_id(kind, s["i"]), _get_n(kind, s["i"]), _get_dur(kind, s["i"]))
			if kind == "fout":
				_arrow(Vector2(r.position.x - 2.0 * STEP, r.position.y + SLOT * 0.5), _progress / SMELT_TIME)
				# Yakıt göstergesi (girdi ile yakıt yuvasının arası)
				var bar := Rect2(r.position.x - 4.0 * STEP + 22.0, r.position.y + 6.0, 18.0, SLOT - 12.0)
				draw_rect(bar, Color(0.35, 0.35, 0.35))
				var f := clampf(_fuel_left / _fuel_total, 0.0, 1.0)
				draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * f, bar.size.x, bar.size.y * f), Color(1.0, 0.55, 0.1))
		if si == _press_slot:
			draw_rect(r, Color(1, 1, 1, 0.9), false, 3.0)
			if _press_can_halve:   # "yarısını al" için dolan çubuk
				draw_rect(Rect2(r.position.x + 4.0, r.end.y - 9.0, (r.size.x - 8.0) * clampf(_press_time / HALF_HOLD, 0.0, 1.0), 5.0), Color(1.0, 0.85, 0.2))
	if _cur_n > 0:
		# Eldeki yığın: parmağın altında kalmasın diye dokunmatikte biraz yukarıda çizilir.
		var c := _pointer - (Vector2(0, SLOT * 0.75) if Session.touch_mode else Vector2.ZERO)
		var r := Rect2(c - Vector2(SLOT, SLOT) * 0.5, Vector2(SLOT, SLOT))
		draw_rect(r.grow(2.0), Color(1, 1, 1, 0.25))
		_item(r, _cur_id, _cur_n, _cur_dur)


## Eşyayı yuvanın içine sığacak şekilde (kenar boşluğuyla) çizer.
func _item(r: Rect2, id: int, n: int, dur := 0) -> void:
	if id <= 0 or n <= 0:
		return
	Items.draw_icon(self, r.grow(-ICON_INSET), id)
	Items.draw_dur_bar(self, r.grow(-ICON_INSET), id, dur)
	if n > 1:
		var pos := Vector2(r.position.x, r.end.y - 5.0)
		draw_string(Session.font, pos + Vector2(1.5, 1.5), str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0, 20, Color(0, 0, 0, 0.85))
		draw_string(Session.font, pos, str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0, 20, Color.WHITE)


## Sağa bakan ok; fill (0..1) kadarı dolu çizilir (fırın ilerlemesi).
func _arrow(left_center: Vector2, fill: float) -> void:
	var a := left_center + Vector2(8.0, 0)
	var w := STEP - 16.0
	var grey := Color(0.4, 0.4, 0.4)
	draw_line(a, a + Vector2(w - 10.0, 0), grey, 6.0)
	draw_colored_polygon(PackedVector2Array([a + Vector2(w - 14.0, -12.0), a + Vector2(w, 0), a + Vector2(w - 14.0, 12.0)]), grey)
	if fill > 0.0 and fill < 1.0:
		draw_line(a, a + Vector2((w - 10.0) * fill, 0), Color(1.0, 0.55, 0.1), 6.0)
