class_name Items
## Eşya kayıt defteri. 1..99 arası kimlikler bloklardır (blok kimliğiyle aynı); 100 ve üstü blok olmayan eşyalardır.

const STICK := 100
const COAL := 101
const IRON_INGOT := 102
const GOLD_INGOT := 103
const DIAMOND := 104

## Aletler: TOOL_BASE + kademe * 3 + tür
const TOOL_BASE := 110
const TIER_WOOD := 0
const TIER_STONE := 1
const TIER_IRON := 2
const TIER_GOLD := 3
const TIER_DIAMOND := 4
const PICKAXE := 0
const AXE := 1
const SHOVEL := 2

const TIER_NAMES := ["Tahta", "Taş", "Demir", "Altın", "Elmas"]
const TYPE_NAMES := ["Kazma", "Balta", "Kürek"]
## Uygun blokta kırma hızı çarpanı
const TIER_SPEED := [2.0, 4.0, 6.0, 12.0, 8.0]
## Hangi cevherleri sökebildiğini belirleyen seviye (altın hızlıdır ama tahta seviyesindedir)
const TIER_LEVEL := [0, 1, 2, 0, 3]
const NAMES := {100: "Çubuk", 101: "Kömür", 102: "Demir Külçesi", 103: "Altın Külçesi", 104: "Elmas"}


static func tool(tier: int, type: int) -> int:
	return TOOL_BASE + tier * 3 + type


static func is_block(id: int) -> bool:
	return id > 0 and id < 100


static func is_tool(id: int) -> bool:
	return id >= TOOL_BASE and id < TOOL_BASE + 15


static func tool_tier(id: int) -> int:
	return (id - TOOL_BASE) / 3


static func tool_type(id: int) -> int:
	return (id - TOOL_BASE) % 3


static func max_stack(id: int) -> int:
	return 1 if is_tool(id) else 64


static func item_name(id: int) -> String:
	if id <= 0:
		return ""
	if is_block(id):
		return Blocks.NAMES[id] if id < Blocks.COUNT else "?"
	if is_tool(id):
		return "%s %s" % [TIER_NAMES[tool_tier(id)], TYPE_NAMES[tool_type(id)]]
	return NAMES.get(id, "?")


## Eşya atlasındaki simge sırası (blok olmayan eşyalar için).
static func icon_index(id: int) -> int:
	if is_tool(id):
		return 8 + (id - TOOL_BASE)
	return id - 100


## Bir eşyanın simgesini verilen dikdörtgene çizer (HUD ve envanter ekranı).
static func draw_icon(ci: CanvasItem, r: Rect2, id: int) -> void:
	if id <= 0:
		return
	if id == Blocks.TORCH:
		r = Rect2(r.position.x + r.size.x * 0.3, r.position.y, r.size.x * 0.4, r.size.y)
		ci.draw_texture_rect_region(Atlas.texture(), r, Atlas.icon_region(id))
	elif is_block(id):
		# Minecraft envanterindeki gibi üç yüzü görünen küp
		var tex := Atlas.texture()
		var ts := Vector2(tex.get_size())
		var cx := r.position.x + r.size.x * 0.5
		var w := r.size.x * 0.5
		var y0 := r.position.y
		var h := r.size.y
		var top := Vector2(cx, y0)
		var lt := Vector2(cx - w, y0 + h * 0.25)
		var rt := Vector2(cx + w, y0 + h * 0.25)
		var mid := Vector2(cx, y0 + h * 0.5)
		var lb := Vector2(cx - w, y0 + h * 0.75)
		var rb := Vector2(cx + w, y0 + h * 0.75)
		var bot := Vector2(cx, y0 + h)
		_face(ci, tex, ts, [lt, top, rt, mid], Blocks.TILES[id][0], 1.0)
		_face(ci, tex, ts, [lt, mid, bot, lb], Blocks.TILES[id][1], 0.78)
		_face(ci, tex, ts, [mid, rt, rb, bot], Blocks.TILES[id][1], 0.58)
	else:
		ci.draw_texture_rect_region(Atlas.item_texture(), r, Atlas.item_region(icon_index(id)))


static func _face(ci: CanvasItem, tex: Texture2D, ts: Vector2, pts: Array, tile: int, shade: float) -> void:
	var reg := Atlas.tile_region(tile)
	var a := (reg.position + Vector2(0.1, 0.1)) / ts
	var b := (reg.end - Vector2(0.1, 0.1)) / ts
	var col := Color(shade, shade, shade)
	ci.draw_polygon(PackedVector2Array(pts), PackedColorArray([col, col, col, col]),
		PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]), tex)


# ---------- Kırma kuralları ----------

static func _matches(block: int, held: int) -> bool:
	return is_tool(held) and tool_type(held) + 1 == int(Blocks.INFO[block][1])


## Bloğu eldeki eşyayla kırma süresi (sn). -1: kırılamaz.
static func mine_time(block: int, held: int) -> float:
	var t: float = Blocks.INFO[block][0]
	if t > 0.0 and _matches(block, held):
		t /= TIER_SPEED[tool_tier(held)]
	return t


## Blok kırıldığında eşya düşer mi? (taş ve cevherler doğru kazmayı ister)
static func can_harvest(block: int, held: int) -> bool:
	var need: int = Blocks.INFO[block][2]
	if need < 0:
		return true
	return _matches(block, held) and TIER_LEVEL[tool_tier(held)] >= need


## Kırılan bloktan düşen eşya (0: hiçbir şey).
static func drop_of(block: int) -> int:
	if block == Blocks.LEAVES:
		return STICK if randf() < 0.12 else 0
	return int(Blocks.INFO[block][3])
