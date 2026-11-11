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

# ---------- RPG eşyaları (mns2026 tablosu) ----------
const SWORD_WOOD := 130
const SWORD_STONE := 131
const SWORD_IRON := 132
const SWORD_GOLD := 133
const SWORD_DIAMOND := 134
const SWORD_NETHER := 135
const HELMET := 140
const CHESTPLATE := 141
const LEGGINGS := 142
const SHIELD_WOOD := 145
const SHIELD_IRON := 146
const SHIELD_DIAMOND := 147
const MEAT_CHICKEN := 150
const MEAT_PORK := 151
const MEAT_BEEF := 152
const MEAT_MUTTON := 153
const ROTTEN_FLESH := 154
const POTION_ATTACK := 160
const POTION_INT := 161
const POTION_DEFENSE := 162
const POTION_SPEED := 163
const TOTEM := 170
const CROWN := 171

## Tüm RPG eşyaları tek tablodan okunur; yeni eşya (dükkan vb.) eklemek için buraya satır eklemek yeterlidir.
##   n: ad            k: tür (sword / helmet / chest / legs / shield / food / potion / totem / misc)
##   dmg: saldırı bonusu      hp: can bonusu        dur: dayanıklılık (kaç vuruş / darbe)
##   lvl: kullanmak için gereken level
##   heal: toplam doldurduğu can, rate: saniyede doldurduğu can (yiyecek)
##   stat, amount, time: iksirin etkilediği stat, miktarı ve süresi (sn)
##   stack: en fazla yığın     price: kakacoin değeri (dükkan için; şimdilik 0)
const DEFS := {
	130: {"n": "Tahta Kılıç", "k": "sword", "dmg": 4, "dur": 10, "lvl": 0},
	131: {"n": "Taş Kılıç", "k": "sword", "dmg": 6, "dur": 15, "lvl": 2},
	132: {"n": "Demir Kılıç", "k": "sword", "dmg": 8, "dur": 20, "lvl": 4},
	133: {"n": "Altın Kılıç", "k": "sword", "dmg": 10, "dur": 25, "lvl": 6},
	134: {"n": "Elmas Kılıç", "k": "sword", "dmg": 15, "dur": 40, "lvl": 9},
	135: {"n": "Nether Kılıç", "k": "sword", "dmg": 25, "dur": 60, "lvl": 12},
	140: {"n": "Kafalık", "k": "helmet", "hp": 2, "dur": 10},
	141: {"n": "Göğüslük", "k": "chest", "hp": 5, "dur": 15},
	142: {"n": "Pantolon ve Ayakkabı", "k": "legs", "hp": 8, "dur": 15},
	145: {"n": "Tahta Kalkan", "k": "shield", "hp": 4, "dur": 15},
	146: {"n": "Demir Kalkan", "k": "shield", "hp": 8, "dur": 25},
	147: {"n": "Elmas Kalkan", "k": "shield", "hp": 10, "dur": 35},
	150: {"n": "Pişmiş Tavuk Eti", "k": "food", "heal": 10, "rate": 2.0},
	151: {"n": "Pişmiş Domuz Eti", "k": "food", "heal": 10, "rate": 2.0},
	152: {"n": "Pişmiş İnek Eti", "k": "food", "heal": 10, "rate": 2.0},
	153: {"n": "Pişmiş Koyun Eti", "k": "food", "heal": 10, "rate": 2.0},
	154: {"n": "Çürük Zombi Eti", "k": "food", "heal": 4, "rate": 2.0},
	160: {"n": "Saldırı İksiri", "k": "potion", "stat": "attack", "amount": 3, "time": 300.0, "stack": 16},
	161: {"n": "Zeka İksiri", "k": "potion", "stat": "intel", "amount": 3, "time": 300.0, "stack": 16},
	162: {"n": "Savunma İksiri", "k": "potion", "stat": "health", "amount": 3, "time": 300.0, "stack": 16},
	163: {"n": "Hız İksiri", "k": "potion", "stat": "speed", "amount": 3, "time": 300.0, "stack": 16},
	170: {"n": "Ölümsüzlük Totemi", "k": "totem", "stack": 1},
	171: {"n": "Kral Tacı", "k": "misc", "stack": 1},
}


## Tablodaki bir alanı okur (yoksa varsayılanı döndürür).
static func prop(id: int, key: String, default: Variant = 0) -> Variant:
	var d: Variant = DEFS.get(id)
	return d.get(key, default) if d != null else default


static func kind(id: int) -> String:
	return str(prop(id, "k", ""))


## Eşyanın tam dayanıklılığı (0: dayanıklılığı yok, kırılmaz).
static func max_durability(id: int) -> int:
	return int(prop(id, "dur", 0))


static func price(id: int) -> int:
	return int(prop(id, "price", 0))


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
	if is_tool(id) or max_durability(id) > 0:
		return 1
	return int(prop(id, "stack", 64))


static func item_name(id: int) -> String:
	if id <= 0:
		return ""
	if is_block(id):
		return Blocks.NAMES[id] if id < Blocks.COUNT else "?"
	if is_tool(id):
		return "%s %s" % [TIER_NAMES[tool_tier(id)], TYPE_NAMES[tool_type(id)]]
	if DEFS.has(id):
		return DEFS[id]["n"]
	return NAMES.get(id, "?")


## Eşya atlasındaki simge sırası (blok olmayan eşyalar için).
static func icon_index(id: int) -> int:
	if is_tool(id):
		return 8 + (id - TOOL_BASE)
	if DEFS.has(id):
		# simgesi henüz çizilmemiş eşyalar atlastaki boş kareyi kullanır
		return Atlas.RPG_ICON_BASE + (id - SWORD_WOOD) if has_icon(id) else 5
	return id - 100


## Simgesi çizilmiş RPG eşyası mı? (şimdilik kılıçlar)
static func has_icon(id: int) -> bool:
	return id >= SWORD_WOOD and id <= SWORD_NETHER


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
	elif DEFS.has(id) and not has_icon(id):
		# Simgesi henüz çizilmemiş eşya: türüne göre renkli geçici kare
		var cols := {"sword": Color(0.75, 0.78, 0.85), "food": Color(0.8, 0.45, 0.3), "potion": Color(0.6, 0.35, 0.8)}
		var col: Color = cols.get(kind(id), Color(0.5, 0.65, 0.55))
		ci.draw_rect(r.grow(-r.size.x * 0.12), col)
		ci.draw_rect(r.grow(-r.size.x * 0.12), Color(0.1, 0.1, 0.1), false, 2.0)
	else:
		ci.draw_texture_rect_region(Atlas.item_texture(), r, Atlas.item_region(icon_index(id)))


## Dayanıklılık çubuğu (yalnızca yıpranmış eşyalarda görünür): yeşilden kırmızıya.
static func draw_dur_bar(ci: CanvasItem, r: Rect2, id: int, dur: int) -> void:
	var full := max_durability(id)
	if full <= 0 or dur <= 0 or dur >= full:
		return
	var f := float(dur) / full
	var bar := Rect2(r.position.x, r.end.y - 5.0, r.size.x, 5.0)
	ci.draw_rect(bar, Color(0, 0, 0, 0.85))
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(1.0 - f, f, 0.1).lightened(0.2))


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
