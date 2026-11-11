class_name InventoryUI
extends Control
## Tam ekran envanter ekranı: solda tarif listesi / envanter, sağda üretim / ekipman (ya da fırın, ganimet sandığı),
## altta hotbar. Dokunmatik ve fare aynı şekilde çalışır:
##   - Yuvaya dokun: yığının tamamını ele al. Başka yuvaya dokun: bırak (aynı türse birleştir, farklıysa değiştir).
##   - Yuvaya basılı tut: yığının yarısını ele al (diğer yarısı yuvada kalır).
##   - Sürükle-bırak: yuvaya bas, parmağı başka yuvaya götür, bırak.
##   - Sonuç yuvasına dokun: ızgaradaki tarifi üret. Tarif listesinde bir tarife dokun: malzeme envanterden alınıp hızlıca üretilir.
##   - Farede sağ tık: yarısını al / 1 adet bırak.

const SLOT := 72.0
const GAP := 4.0
const STEP := SLOT + GAP
const PAD := 16.0
const TAB := 84.0
const MARGIN := 12.0
const ICON_INSET := 9.0
const HALF_HOLD := 0.4        # yarısını almak için basılı tutma süresi (sn)
const MODE_INVENTORY := 0
const MODE_TABLE := 1
const MODE_FURNACE := 2
const MODE_CHEST := 3
const SMELT_TIME := 2.0
const TITLES := ["Üretim", "Çalışma Masası", "Fırın", "Ganimet Sandığı"]
const LEFT_RECIPES := 0
const LEFT_ITEMS := 1
const RIGHT_MAIN := 0
const RIGHT_EQUIP := 1

const C_PANEL := Color(0.776, 0.776, 0.776)
const C_LIGHT := Color(1, 1, 1)
const C_SHADOW := Color(0.333, 0.333, 0.333)
const C_OUTLINE := Color(0.07, 0.07, 0.07)
const C_SLOT := Color(0.545, 0.545, 0.545)
const C_WELL := Color(0.31, 0.31, 0.31)
const C_INK := Color(0.2, 0.2, 0.2)

var game: Node
var inv: Inventory
var mode := MODE_INVENTORY
var left_tab := LEFT_RECIPES
var right_tab := RIGHT_MAIN

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
var _recipes: Array[Dictionary] = []    # sol paneldeki tarif listesi (bu ekranın ızgarasına sığanlar)
var _lp := Rect2()                      # sol panel
var _rp := Rect2()                      # sağ panel
var _hot := Rect2()                     # hotbar paneli
var _well := Rect2()                    # sol paneldeki koyu yuva alanı
var _ltabs: Array[Rect2] = []
var _ltab_ids: Array[int] = []
var _rtabs: Array[Rect2] = []
var _close := Rect2()
var _hint := ""
var _pointer := Vector2.ZERO            # son dokunma / fare konumu
var _press_slot := -1                   # basılı tutulan yuva (_slots sırası)
var _press_time := 0.0
var _press_can_halve := false
var chest: LootChest                    # MODE_CHEST'te içeriği gösterilen sandık
var _take_all := Rect2()


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
	left_tab = LEFT_RECIPES if _has_recipes() else LEFT_ITEMS
	right_tab = RIGHT_MAIN
	_hint = ""
	_progress = 0.0
	_press_slot = -1
	visible = true


## Tarif listesi yalnızca üretim ekranlarında (envanter ve çalışma masası) gösterilir.
func _has_recipes() -> bool:
	return mode == MODE_INVENTORY or mode == MODE_TABLE


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
	if chest != null and is_instance_valid(chest):
		chest.held = false
		if chest.items.is_empty():
			chest.expired = true
			chest.queue_free()
	chest = null
	visible = false
	game.on_ui_closed()


## Ganimet sandığını açar: sağda sandığın içeriği, solda envanter. Eşyaya dokununca envantere geçer.
func open_chest(c: LootChest) -> void:
	chest = c
	c.held = true
	open(MODE_CHEST)


func _chest_item(i: int) -> Array:
	if chest != null and is_instance_valid(chest) and i < chest.items.size():
		return chest.items[i]
	return [0, 0, 0]


## Sandıktaki i. eşyayı envantere alır (sığdığı kadar).
func take_from_chest(i: int) -> void:
	var it := _chest_item(i)
	if int(it[1]) <= 0:
		return
	var rest := inv.add(it[0], it[1], it[2])
	if rest >= int(it[1]):
		_hint = "Envanter dolu"
		return
	_hint = "%s alındı" % Items.item_name(it[0])
	if rest > 0:
		chest.items[i] = [it[0], rest, it[2]]
	else:
		chest.items.remove_at(i)
	if chest.items.is_empty():
		close()


func take_all() -> void:
	var i := 0
	while chest != null and is_instance_valid(chest) and i < chest.items.size():
		var before := chest.items.size()
		take_from_chest(i)
		if chest != null and chest.items.size() == before:
			i += 1   # sığmadı: sonrakine geç


func _give_back(id: int, n: int, dur := -1) -> void:
	if id <= 0 or n <= 0:
		return
	var left := inv.add(id, n, dur)
	if left > 0:
		game.drop_from_player(id, left, dur)


# ---------- Tarif listesi ve hızlı üretim ----------

## Bu ekranın ızgarasına (envanterde 2x2, masada 3x3) sığan tarifler.
func _shown_recipes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _has_recipes():
		return out
	var n := 3 if mode == MODE_TABLE else 2
	for r in Recipes.all():
		if int(r["w"]) <= n and int(r["h"]) <= n:
			out.append(r)
	return out


## Tarifin malzemeleri envanterde var mı ve level yetiyor mu?
func can_quick_craft(r: Dictionary) -> bool:
	if game.stats.level < int(Items.prop(r["out"], "lvl", 0)):
		return false
	var need := Recipes.needs(r)
	for id: int in need:
		if inv.count(id) < int(need[id]):
			return false
	return true


## Tarifi envanterdeki malzemelerle doğrudan üretir.
func quick_craft(r: Dictionary) -> void:
	var out: int = r["out"]
	var lvl := int(Items.prop(out, "lvl", 0))
	if game.stats.level < lvl:
		_hint = "%s için level %d gerekli" % [Items.item_name(out), lvl]
		return
	var need := Recipes.needs(r)
	var missing: PackedStringArray = []
	for id: int in need:
		if inv.count(id) < int(need[id]):
			missing.append("%d %s" % [int(need[id]), Items.item_name(id)])
	if not missing.is_empty():
		var all: PackedStringArray = []
		for id: int in need:
			all.append("%d %s" % [int(need[id]), Items.item_name(id)])
		_hint = "%s için gerekli: %s" % [Items.item_name(out), ", ".join(all)]
		return
	for id: int in need:
		inv.remove(id, int(need[id]))
	var left := inv.add(out, int(r["n"]))
	if left > 0:
		game.drop_from_player(out, left)
	_hint = "%s x%d üretildi" % [Items.item_name(out), int(r["n"])]


# ---------- Yerleşim ----------

func _layout() -> void:
	var hot_h := SLOT + 24.0
	var w := size.x - 2.0 * MARGIN
	var main_h := size.y - 2.0 * MARGIN - hot_h - 10.0
	var pw := floorf((w - 2.0 * TAB - 16.0) * 0.5)
	_lp = Rect2(MARGIN + TAB, MARGIN, pw, main_h)
	_rp = Rect2(_lp.end.x + 16.0, MARGIN, pw, main_h)
	var hot_w := 9.0 * STEP - GAP + 24.0
	_hot = Rect2(floorf((size.x - hot_w) * 0.5), size.y - MARGIN - hot_h, hot_w, hot_h)
	# Sekmeler: solda tarifler / envanter, sağda kapat + üretim / ekipman
	_ltabs.clear()
	_ltab_ids.clear()
	for id: int in ([LEFT_RECIPES, LEFT_ITEMS] if _has_recipes() else [LEFT_ITEMS]):
		_ltabs.append(Rect2(MARGIN, MARGIN + 10.0 + _ltabs.size() * (TAB + 10.0), TAB + 4.0, TAB))
		_ltab_ids.append(id)
	_close = Rect2(_rp.end.x - 4.0, MARGIN, TAB + 4.0, 70.0)
	_rtabs.clear()
	for i in 2:
		_rtabs.append(Rect2(_rp.end.x - 4.0, MARGIN + 90.0 + i * (TAB + 10.0), TAB + 4.0, TAB))

	_slots.clear()
	# Hotbar
	for col in Inventory.HOTBAR:
		_slot(_hot.position.x + 12.0 + col * STEP, _hot.position.y + 12.0, "inv", col)
	# Sol panel: tarifler ya da envanterin 27 yuvası
	var cols := int((pw - 2.0 * PAD + GAP) / STEP)
	var gx0 := floorf(_lp.position.x + (pw - (cols * STEP - GAP)) * 0.5)
	var gy0 := _lp.position.y + 68.0
	var rows := int((main_h - 68.0 - PAD + GAP) / STEP)
	_well = Rect2(gx0 - 8.0, gy0 - 8.0, cols * STEP - GAP + 16.0, rows * STEP - GAP + 16.0)
	if left_tab == LEFT_ITEMS:
		for k in Inventory.SIZE - Inventory.HOTBAR:
			_slot(gx0 + (k % cols) * STEP, gy0 + (k / cols) * STEP, "inv", Inventory.HOTBAR + k)
	else:
		_recipes = _shown_recipes()
		for k in mini(_recipes.size(), cols * rows):
			_slot(gx0 + (k % cols) * STEP, gy0 + (k / cols) * STEP, "recipe", k)
	# Sağ panel
	var cx := _rp.position.x + pw * 0.5
	var top := _rp.position.y + 84.0
	if right_tab == RIGHT_EQUIP:
		for i in Inventory.EQUIP:   # kafalık, göğüslük / pantolon, kalkan
			_slot(cx - STEP + GAP * 0.5 + (i % 2) * STEP, top + (i >> 1) * STEP, "eq", i)
	elif mode == MODE_CHEST:
		for i in 6:
			_slot(cx - 1.5 * STEP + GAP * 0.5 + (i % 3) * STEP, top + (i / 3) * STEP, "chest", i)
		_take_all = Rect2(cx - 140.0, top + 2.0 * STEP + 20.0, 280.0, 68.0)
	elif mode == MODE_FURNACE:
		var gx := cx - 2.5 * STEP + GAP * 0.5
		_slot(gx, top, "f", 0)
		_slot(gx, top + 2.0 * STEP, "f", 1)
		_slot(gx + 4.0 * STEP, top + STEP, "fout", 2)
	else:
		var n := 3 if mode == MODE_TABLE else 2
		var gx := cx - n * STEP * 0.5 + GAP * 0.5
		for y in n:
			for x in n:
				_slot(gx + x * STEP, top + y * STEP, "grid", y * 3 + x)
		_slot(cx - SLOT * 0.5, top + n * STEP + 62.0, "result", 0)


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
		"eq":
			return inv.id_at(Inventory.SIZE + i)
		"chest":
			return int(_chest_item(i)[0]) if int(_chest_item(i)[1]) > 0 else 0
		"recipe":
			return int(_recipes[i]["out"]) if i < _recipes.size() else 0
		"grid":
			return _grid_ids[i] if _grid_counts[i] > 0 else 0
	return _f_ids[i] if _f_counts[i] > 0 else 0


func _get_n(kind: String, i: int) -> int:
	match kind:
		"inv":
			return inv.counts[i]
		"eq":
			return inv.counts[Inventory.SIZE + i]
		"chest":
			return int(_chest_item(i)[1])
		"recipe":
			return int(_recipes[i]["n"]) if i < _recipes.size() else 0
		"grid":
			return _grid_counts[i]
	return _f_counts[i]


func _get_dur(kind: String, i: int) -> int:
	match kind:
		"inv":
			return inv.dur_at(i)
		"eq":
			return inv.dur_at(Inventory.SIZE + i)
		"chest":
			return maxi(int(_chest_item(i)[2]), 0)
		"recipe":
			return 0
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
		"eq":
			inv.set_slot(Inventory.SIZE + i, id, n, dur)
		"chest", "recipe", "result":
			pass   # bu yuvalara eşya konmaz
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


## Bu yuvaya eldeki eşya bırakılabilir mi?
func _droppable(kind: String) -> bool:
	return kind != "result" and kind != "fout" and kind != "chest" and kind != "recipe"


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
			if _droppable(kind):
				_place(kind, _slots[si]["i"], false)
		_press_slot = -1
		return
	if _close.has_point(event.position):
		close()
		return
	for t in _ltabs.size():
		if _ltabs[t].has_point(event.position):
			left_tab = _ltab_ids[t]
			_press_slot = -1
			return
	for t in _rtabs.size():
		if _rtabs[t].has_point(event.position):
			right_tab = t
			_press_slot = -1
			return
	if mode == MODE_CHEST and right_tab == RIGHT_MAIN and _take_all.has_point(event.position):
		take_all()
		return
	if si == -1:
		return
	press(_slots[si]["kind"], _slots[si]["i"], right)
	if _cur_n > 0 and not right and _droppable(_slots[si]["kind"]):
		_press_slot = si
		_press_time = 0.0


## Bir yuvaya basıldı. Eli boşsa yığını alır, doluysa bırakır.
func press(kind: String, i: int, right := false) -> void:
	_press_slot = -1
	_press_can_halve = false
	if kind == "result":
		_craft()
		return
	if kind == "recipe":
		if _recipes.is_empty():
			_recipes = _shown_recipes()
		if i < _recipes.size():
			quick_craft(_recipes[i])
		return
	if kind == "chest":
		if _cur_n == 0:
			take_from_chest(i)
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
	if not _droppable(kind):
		return
	if kind == "eq" and not Inventory.fits_equip(i, _cur_id):
		_hint = "Buraya yalnızca %s takılır" % Inventory.EQUIP_NAMES[i]
		return
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
	var need := int(Items.prop(out, "lvl", 0))
	if game.stats.level < need:
		_hint = "%s için level %d gerekli" % [Items.item_name(out), need]
		return
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
	if mode == MODE_CHEST and (chest == null or not is_instance_valid(chest)):
		close()
		return
	if _press_slot != -1 and _press_can_halve:
		_layout()
		if _press_slot >= _slots.size() or _slot_at(_pointer) != _press_slot:
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

## Kabartmalı panel: koyu dış çizgi, sol-üst ışık, sağ-alt gölge.
func _panel_box(r: Rect2, fill := C_PANEL) -> void:
	draw_rect(r.grow(3.0), C_OUTLINE)
	draw_rect(r, fill)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), C_LIGHT)
	draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), C_LIGHT)
	draw_rect(Rect2(r.position.x, r.end.y - 4.0, r.size.x, 4.0), C_SHADOW)
	draw_rect(Rect2(r.end.x - 4.0, r.position.y, 4.0, r.size.y), C_SHADOW)


## İçe gömük yuva: sol-üst gölge, sağ-alt ışık.
func _slot_box(r: Rect2, fill := C_SLOT) -> void:
	draw_rect(r, fill)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), C_LIGHT)
	draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), C_LIGHT)


## Sekme butonu; seçili olan panelle aynı renkte ve öne çıkmış görünür.
func _tab_box(r: Rect2, selected: bool) -> void:
	_panel_box(r, C_PANEL if selected else Color(0.6, 0.6, 0.6))
	if selected:
		draw_rect(r, Color(1.0, 0.85, 0.3), false, 3.0)


func _grid_icon(r: Rect2, n: int, color: Color) -> void:
	var cell := (r.size.x - (n - 1) * 4.0) / n
	for y in n:
		for x in n:
			draw_rect(Rect2(r.position + Vector2(x * (cell + 4.0), y * (cell + 4.0)), Vector2(cell, cell)), color)


func _draw() -> void:
	_layout()
	var font := Session.font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	# Sekmeler panellerin altında kalsın diye önce çizilir
	for t in _ltabs.size():
		_tab_box(_ltabs[t], _ltab_ids[t] == left_tab)
		var ir := _ltabs[t].grow(-20.0)
		if _ltab_ids[t] == LEFT_RECIPES:
			Items.draw_icon(self, ir, Blocks.CRAFTING_TABLE)
		else:
			_grid_icon(ir, 3, Color(0.3, 0.2, 0.1))
	for t in _rtabs.size():
		_tab_box(_rtabs[t], t == right_tab)
		var ir := _rtabs[t].grow(-20.0)
		if t == RIGHT_EQUIP:
			Items.draw_icon(self, ir, Items.CHESTPLATE)
		elif mode == MODE_FURNACE:
			Items.draw_icon(self, ir, Blocks.FURNACE)
		elif mode == MODE_CHEST:
			draw_rect(Rect2(ir.position.x, ir.position.y + 8.0, ir.size.x, ir.size.y - 12.0), Color(0.55, 0.36, 0.16))
			draw_rect(Rect2(ir.position.x, ir.position.y + 8.0, ir.size.x, 10.0), Color(0.4, 0.26, 0.12))
			draw_rect(Rect2(ir.get_center().x - 5.0, ir.position.y + 14.0, 10.0, 12.0), Color(0.98, 0.82, 0.22))
		else:
			_grid_icon(ir.grow(-2.0), 2 if mode == MODE_INVENTORY else 3, Color(0.45, 0.28, 0.12))
	_panel_box(_close, Color(0.7, 0.24, 0.22))
	draw_string(font, Vector2(_close.position.x, _close.position.y + 46.0), "X", HORIZONTAL_ALIGNMENT_CENTER, _close.size.x, 32, Color.WHITE)
	_panel_box(_lp)
	_panel_box(_rp)
	_panel_box(_hot)
	# Başlıklar
	var ltitle := "Tarifler" if left_tab == LEFT_RECIPES else "Envanter"
	draw_string(font, Vector2(_lp.position.x + 24.0, _lp.position.y + 44.0), ltitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, C_INK)
	if left_tab == LEFT_RECIPES:
		draw_string(font, Vector2(_lp.position.x, _lp.position.y + 42.0), "Dokun: hızlı üret", HORIZONTAL_ALIGNMENT_RIGHT, _lp.size.x - 24.0, 18, Color(0.35, 0.35, 0.35))
	var rtitle: String = "Ekipman" if right_tab == RIGHT_EQUIP else TITLES[mode]
	draw_string(font, Vector2(_rp.position.x, _rp.position.y + 48.0), rtitle, HORIZONTAL_ALIGNMENT_CENTER, _rp.size.x, 30, C_INK)
	# Sol paneldeki koyu yuva alanı
	draw_rect(_well, C_WELL)
	draw_rect(Rect2(_well.position, Vector2(_well.size.x, 3.0)), Color(0.12, 0.12, 0.12))
	draw_rect(Rect2(_well.position, Vector2(3.0, _well.size.y)), Color(0.12, 0.12, 0.12))
	draw_rect(Rect2(_well.position.x, _well.end.y - 3.0, _well.size.x, 3.0), C_LIGHT)
	draw_rect(Rect2(_well.end.x - 3.0, _well.position.y, 3.0, _well.size.y), C_LIGHT)

	var recipe := {} if mode == MODE_FURNACE or mode == MODE_CHEST else _recipe()
	for si in _slots.size():
		var s := _slots[si]
		var r: Rect2 = s["r"]
		var kind: String = s["kind"]
		var idx: int = s["i"]
		match kind:
			"recipe":
				# Malzemesi eksik tarifler kırmızı zeminde gösterilir
				_slot_box(r, C_SLOT if can_quick_craft(_recipes[idx]) else Color(0.78, 0.27, 0.25))
				_item(r, _recipes[idx]["out"], _recipes[idx]["n"])
			"result":
				_slot_box(r)
				if not recipe.is_empty():
					_item(r, recipe["out"], recipe["n"])
				_arrow_down(Vector2(r.get_center().x, r.position.y - 54.0), not recipe.is_empty())
			_:
				_slot_box(r)
				_item(r, _get_id(kind, idx), _get_n(kind, idx), _get_dur(kind, idx))
				if kind == "eq" and _get_n(kind, idx) == 0:
					# Boş ekipman yuvası: takılacak eşyanın soluk silueti
					var ghost: int = [Items.HELMET, Items.CHESTPLATE, Items.LEGGINGS, Items.SHIELD_IRON][idx]
					draw_texture_rect_region(Atlas.item_texture(), r.grow(-ICON_INSET), Atlas.item_region(Items.icon_index(ghost)), Color(0, 0, 0, 0.22))
				if kind == "fout":
					_arrow(Vector2(r.position.x - 2.0 * STEP, r.position.y + SLOT * 0.5), _progress / SMELT_TIME)
					# Yakıt göstergesi (girdi ile yakıt yuvasının arası)
					var bar := Rect2(r.position.x - 4.0 * STEP + 26.0, r.position.y + 6.0, 20.0, SLOT - 12.0)
					draw_rect(bar, Color(0.35, 0.35, 0.35))
					var f := clampf(_fuel_left / _fuel_total, 0.0, 1.0)
					draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * f, bar.size.x, bar.size.y * f), Color(1.0, 0.55, 0.1))
		if kind == "inv" and idx == game.selected:
			draw_rect(r.grow(1.0), Color(1.0, 0.85, 0.3), false, 3.0)   # elde tutulan hotbar yuvası
		if si == _press_slot:
			draw_rect(r, Color(1, 1, 1, 0.9), false, 3.0)
			if _press_can_halve:   # "yarısını al" için dolan çubuk
				draw_rect(Rect2(r.position.x + 5.0, r.end.y - 11.0, (r.size.x - 10.0) * clampf(_press_time / HALF_HOLD, 0.0, 1.0), 6.0), Color(1.0, 0.85, 0.2))

	# Sağ panelin alt yazıları
	var cx := _rp.position.x
	if right_tab == RIGHT_EQUIP:
		var st: PlayerStats = game.stats
		var y := _rp.position.y + 84.0 + 2.0 * STEP + 40.0
		draw_string(font, Vector2(cx, y), "Zırh ve kalkan can bonusu: +%d" % inv.equip_hp(), HORIZONTAL_ALIGNMENT_CENTER, _rp.size.x, 22, C_INK)
		draw_string(font, Vector2(cx, y + 34.0), "Can: %d / %d     Level: %d" % [ceili(st.hp), st.max_hp(), st.level], HORIZONTAL_ALIGNMENT_CENTER, _rp.size.x, 22, C_INK)
		draw_string(font, Vector2(cx, y + 68.0), "Mob her vurduğunda takılı parçalar 1 yıpranır", HORIZONTAL_ALIGNMENT_CENTER, _rp.size.x, 17, Color(0.35, 0.35, 0.35))
	elif mode == MODE_CHEST:
		draw_string(font, Vector2(cx, _rp.position.y + 74.0), "Almak istediğin eşyaya dokun", HORIZONTAL_ALIGNMENT_CENTER, _rp.size.x, 18, Color(0.35, 0.35, 0.35))
		_panel_box(_take_all, Color(0.27, 0.6, 0.27))
		draw_string(font, Vector2(_take_all.position.x, _take_all.position.y + 44.0), "Hepsini Al", HORIZONTAL_ALIGNMENT_CENTER, _take_all.size.x, 28, Color.WHITE)
	if _hint != "":
		draw_string(font, Vector2(_rp.position.x + 16.0, _rp.end.y - 22.0), _hint, HORIZONTAL_ALIGNMENT_CENTER, _rp.size.x - 32.0, 20, C_INK)

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
		var pos := Vector2(r.position.x, r.end.y - 7.0)
		draw_string(Session.font, pos + Vector2(2.0, 2.0), str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0, 24, Color(0, 0, 0, 0.85))
		draw_string(Session.font, pos, str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0, 24, Color.WHITE)


## Sağa bakan ok; fill (0..1) kadarı dolu çizilir (fırın ilerlemesi).
func _arrow(left_center: Vector2, fill: float) -> void:
	var a := left_center + Vector2(8.0, 0)
	var w := STEP - 16.0
	var grey := Color(0.4, 0.4, 0.4)
	draw_line(a, a + Vector2(w - 10.0, 0), grey, 8.0)
	draw_colored_polygon(PackedVector2Array([a + Vector2(w - 16.0, -14.0), a + Vector2(w, 0), a + Vector2(w - 16.0, 14.0)]), grey)
	if fill > 0.0 and fill < 1.0:
		draw_line(a, a + Vector2((w - 10.0) * fill, 0), Color(1.0, 0.55, 0.1), 8.0)


## Aşağı bakan ok (ızgaradan sonuç yuvasına); tarif geçerliyse koyu çizilir.
func _arrow_down(top_center: Vector2, active: bool) -> void:
	var col := Color(0.3, 0.3, 0.3) if active else Color(0.62, 0.62, 0.62)
	draw_rect(Rect2(top_center.x - 7.0, top_center.y, 14.0, 26.0), col)
	draw_colored_polygon(PackedVector2Array([top_center + Vector2(-20.0, 24.0), top_center + Vector2(20.0, 24.0), top_center + Vector2(0, 46.0)]), col)
