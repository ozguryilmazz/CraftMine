class_name Recipes
## Şekilli crafting tarifleri (Minecraft düzeni) ve fırın tarifleri.

## { w, h, cells: [w*h eşya kimliği], out, n }
static var _list: Array[Dictionary] = []


static func _add(rows: Array, keys: Dictionary, out: int, n: int) -> void:
	var w: int = rows[0].length()
	var cells: Array[int] = []
	for row: String in rows:
		for i in w:
			cells.append(int(keys.get(row[i], 0)))
	_list.append({"w": w, "h": rows.size(), "cells": cells, "out": out, "n": n})


static func _init_list() -> void:
	var P := Blocks.PLANKS
	var S := Items.STICK
	_add(["L"], {"L": Blocks.LOG}, Blocks.PLANKS, 4)
	_add(["P", "P"], {"P": P}, Items.STICK, 4)
	_add(["PP", "PP"], {"P": P}, Blocks.CRAFTING_TABLE, 1)
	_add(["C", "S"], {"C": Items.COAL, "S": S}, Blocks.TORCH, 4)
	_add(["CCC", "C C", "CCC"], {"C": Blocks.COBBLE}, Blocks.FURNACE, 1)
	var mats := [P, Blocks.COBBLE, Items.IRON_INGOT, Items.GOLD_INGOT, Items.DIAMOND]
	for tier in mats.size():
		var k := {"M": mats[tier], "S": S}
		_add(["MMM", " S ", " S "], k, Items.tool(tier, Items.PICKAXE), 1)
		_add(["MM", "MS", " S"], k, Items.tool(tier, Items.AXE), 1)
		_add(["M", "S", "S"], k, Items.tool(tier, Items.SHOVEL), 1)
		_add(["M", "M", "S"], k, Items.SWORD_WOOD + tier, 1)   # nether kılıç üretilemez, yalnızca ganimet


## Tüm tarifler (tarif listesi için).
static func all() -> Array[Dictionary]:
	if _list.is_empty():
		_init_list()
	return _list


## Tarifin gerektirdiği malzemeler: { eşya kimliği: adet }.
static func needs(r: Dictionary) -> Dictionary:
	var out := {}
	for id: int in r["cells"]:
		if id != 0:
			out[id] = int(out.get(id, 0)) + 1
	return out


## n x n ızgaradaki (satır satır) eşyalara uyan tarifi bulur. Yoksa boş sözlük.
## Tarif ızgaranın neresine dizilirse dizilsin ve yatay ayna görüntüsü de kabul edilir.
static func find(grid: Array, n: int) -> Dictionary:
	if _list.is_empty():
		_init_list()
	var x0 := n
	var y0 := n
	var x1 := -1
	var y1 := -1
	for y in n:
		for x in n:
			if int(grid[y * n + x]) != 0:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return {}
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	for r in _list:
		if r["w"] != w or r["h"] != h:
			continue
		var cells: Array[int] = r["cells"]
		var same := true
		var mirror := true
		for y in h:
			for x in w:
				var g := int(grid[(y0 + y) * n + x0 + x])
				if g != cells[y * w + x]:
					same = false
				if g != cells[y * w + (w - 1 - x)]:
					mirror = false
		if same or mirror:
			return r
	return {}


## Fırında pişince ne olur? (0: pişmez)
static func smelt(id: int) -> int:
	match id:
		Blocks.IRON_ORE:
			return Items.IRON_INGOT
		Blocks.GOLD_ORE:
			return Items.GOLD_INGOT
		Blocks.COBBLE:
			return Blocks.STONE
		Blocks.LOG:
			return Items.COAL   # odun kömürü
	return 0


## Yakıtın yanma süresi (sn). Bir eşya 2 sn'de pişer. 0: yakıt değil.
static func fuel(id: int) -> float:
	match id:
		Items.COAL:
			return 16.0
		Blocks.LOG, Blocks.PLANKS, Blocks.CRAFTING_TABLE:
			return 3.0
		Items.STICK:
			return 1.0
	return 0.0
