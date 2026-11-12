class_name Atlas
## Blok ve eşya dokularını çalışma anında üretir.
## Blok atlası 8x8 karo, eşya atlası 8x4 simge; her karo 16 piksel.

const TILE := 16
const GRID := 8
const TILE_COUNT := 21
## Doku varyantları: [ana karo, ilk varyant karosu, varyant sayısı]. Mesher bloğun konumuna göre birini seçer.
const VARIANTS := [[0, 21, 3], [2, 24, 3], [3, 27, 3], [6, 30, 3], [9, 33, 3], [1, 36, 2], [4, 38, 2]]
const TILE_TOTAL := 40
const ITEM_TILE := 32
const ITEM_COLS := 8
const ITEM_ROWS := 10
## RPG eşyalarının simgeleri bu sıradan başlar (eşya kimliği 130 -> simge 32).
const RPG_ICON_BASE := 32

const TIER_COLORS := [
	Color(0.62, 0.46, 0.26),   # tahta
	Color(0.55, 0.55, 0.57),   # taş
	Color(0.86, 0.86, 0.9),    # demir
	Color(0.98, 0.84, 0.25),   # altın
	Color(0.35, 0.9, 0.9),     # elmas
	Color(0.5, 0.2, 0.62),     # nether
]

static var _tex: ImageTexture
static var _item_tex: ImageTexture
static var _mat: StandardMaterial3D
static var _water_mat: StandardMaterial3D
static var _flat_mats := {}
## Çizilmekte olan karonun varyant numarası (0 = ana doku); _h'nin tohumuna karışır.
static var _voff := 0


static func texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(_build())
	return _tex


static func item_texture() -> ImageTexture:
	if _item_tex == null:
		_item_tex = ImageTexture.create_from_image(_build_items())
	return _item_tex


## Dünya ve mini blok mesh'lerinin ortak malzemesi.
static func block_material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = texture()
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 1.0
		_mat.metallic_specular = 0.0
	return _mat


static func water_material() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = block_material().duplicate()
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _water_mat


## Düz (kağıt gibi) eşya görseli için malzeme: simgenin atlas bölgesini gösterir.
static func flat_material(id: int) -> StandardMaterial3D:
	if _flat_mats.has(id):
		return _flat_mats[id]
	var tex := texture() if Items.is_block(id) else item_texture()
	var region := icon_region(id) if Items.is_block(id) else item_region(Items.icon_index(id))
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ts := Vector2(tex.get_size())
	m.uv1_scale = Vector3(region.size.x / ts.x, region.size.y / ts.y, 1.0)
	m.uv1_offset = Vector3(region.position.x / ts.x, region.position.y / ts.y, 0.0)
	_flat_mats[id] = m
	return m


static func tile_region(tile: int) -> Rect2:
	return Rect2((tile & 7) * TILE, (tile >> 3) * TILE, TILE, TILE)


## Bir bloğun simgesi için atlas bölgesi.
static func icon_region(block: int) -> Rect2:
	if block == Blocks.TORCH:
		var t := tile_region(8)
		return Rect2(t.position.x + 5, t.position.y + 5, 6, 11)
	return tile_region(Blocks.TILES[block][1])


static func item_region(icon: int) -> Rect2:
	return Rect2((icon % ITEM_COLS) * ITEM_TILE, (icon >> 3) * ITEM_TILE, ITEM_TILE, ITEM_TILE)


## Kırma animasyonu için giderek büyüyen çatlak dokuları.
static func crack_textures(stages: int) -> Array[ImageTexture]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# Ortadan dışarı doğru rastgele yürüyen çatlak kolları
	var pixels: Array[Vector2i] = []
	var heads: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	var main_dir: Array[Vector2i] = []
	for i in 5:
		heads.append(Vector2i(7 + rng.randi_range(0, 1), 7 + rng.randi_range(0, 1)))
		main_dir.append(dirs[(i * 3 + rng.randi_range(0, 1)) % dirs.size()])
	while pixels.size() < 90:
		for i in heads.size():
			var d: Vector2i = main_dir[i] if rng.randf() < 0.6 else dirs[rng.randi_range(0, dirs.size() - 1)]
			var h := heads[i] + d
			if h.x < 0 or h.x >= TILE or h.y < 0 or h.y >= TILE:
				h = Vector2i(rng.randi_range(4, 11), rng.randi_range(4, 11))
			heads[i] = h
			if not pixels.has(h):
				pixels.append(h)
	var out: Array[ImageTexture] = []
	for s in stages:
		var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		var count := int(pixels.size() * float(s + 1) / stages)
		for i in count:
			img.set_pixel(pixels[i].x, pixels[i].y, Color(0.03, 0.03, 0.03, 0.8))
		out.append(ImageTexture.create_from_image(img))
	return out


# ---------- Blok karoları ----------

static func _build() -> Image:
	var img := Image.create(TILE * GRID, TILE * GRID, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for t in TILE_TOTAL:
		var ox := (t & 7) * TILE
		var oy := (t >> 3) * TILE
		var base := t
		_voff = 0
		for v: Array in VARIANTS:
			if t >= v[1] and t < v[1] + v[2]:
				base = v[0]
				_voff = t - v[1] + 1
		for py in TILE:
			for px in TILE:
				img.set_pixel(ox + px, oy + py, _pixel(base, px, py, rng.randf()))
	_voff = 0
	return img


static func _v(c: Color, n: float, amt: float) -> Color:
	var f := 1.0 - amt + n * amt * 2.0
	return Color(c.r * f, c.g * f, c.b * f, c.a)


static func _cobble(px: int, py: int, n: float) -> Color:
	var c := Color(0.5, 0.5, 0.52)
	if py % 5 == 0 or (px + (py / 5) * 3) % 6 == 0:
		c = c.darkened(0.4)
	return _v(c, n, 0.12)


static func _planks(px: int, py: int, n: float) -> Color:
	var plank := Color(0.72, 0.56, 0.33)
	if py % 4 == 3 or px == ((py >> 2) % 2) * 8:
		plank = plank.darkened(0.25)
	return _v(plank, n, 0.06)


## Konuma bağlı sabit rastgele değer (0..1); desenlerin yeri her açılışta aynı kalır.
static func _h(a: int, b: int, c: int) -> float:
	var x := ((a + _voff * 131) * 374761393 + b * 668265263 + c * 1274126177 + 1013904223) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1103515245) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x & 0xffff) / 65535.0


## Yumuşak lekeler: karonun kenarlarında kesintisiz devam eden (döşenebilir) değer gürültüsü. cell 16'yı bölmeli.
static func _blot(t: int, px: int, py: int, cell: int) -> float:
	var cnt := TILE / cell
	var gx := px / cell
	var gy := py / cell
	var fx := float(px % cell) / cell
	var fy := float(py % cell) / cell
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var gx1 := (gx + 1) % cnt
	var gy1 := (gy + 1) % cnt
	var top := lerpf(_h(t, gx, gy), _h(t, gx1, gy), fx)
	var bot := lerpf(_h(t, gx, gy1), _h(t, gx1, gy1), fx)
	return lerpf(top, bot, fy)


static func _grass_top(px: int, py: int, n: float) -> Color:
	var b := _blot(40, px, py, 4) * 0.7 + n * 0.3
	if n > 0.94:
		return Color(0.5, 0.76, 0.3)          # güneş alan uç
	if n < 0.06:
		return Color(0.2, 0.43, 0.15)         # koyu dip
	if b < 0.36:
		return _v(Color(0.26, 0.52, 0.18), n, 0.05)
	if b < 0.62:
		return _v(Color(0.33, 0.62, 0.22), n, 0.05)
	return _v(Color(0.4, 0.69, 0.26), n, 0.05)


static func _dirt(px: int, py: int, n: float) -> Color:
	# Küçük taşlar: açık renkli tek piksel, sağ altında gölgesi.
	if _h(41, px, py) < 0.05:
		return _v(Color(0.66, 0.58, 0.5), n, 0.05)
	if _h(41, (px + 15) % 16, (py + 15) % 16) < 0.05:
		return Color(0.33, 0.22, 0.14)
	var b := _blot(42, px, py, 4) * 0.65 + n * 0.35
	if b < 0.34:
		return _v(Color(0.44, 0.3, 0.2), n, 0.05)
	if b < 0.66:
		return _v(Color(0.52, 0.37, 0.25), n, 0.05)
	return _v(Color(0.59, 0.43, 0.29), n, 0.05)


static func _stone(px: int, py: int, n: float) -> Color:
	var b := _blot(43, px, py, 4) * 0.75 + n * 0.25
	var c := Color(0.5, 0.5, 0.52)
	if b < 0.34:
		c = Color(0.42, 0.42, 0.45)
	elif b > 0.64:
		c = Color(0.57, 0.57, 0.59)
	# Kısa yatay çatlaklar ve açık lekeler
	if _h(44, px >> 2, py) < 0.1 and _h(45, px, py) < 0.8:
		c = Color(0.33, 0.33, 0.36)
	elif _h(46, px, py) < 0.035:
		c = Color(0.66, 0.66, 0.68)
	return _v(c, n, 0.04)


## Cevher: taş zemin üzerinde parlak uçlu, gölgeli mineral kümeleri.
static func _ore(px: int, py: int, n: float, ore: Color) -> Color:
	var cx := [3, 10, 6, 12, 2, 9]
	var cy := [2, 3, 7, 9, 12, 13]
	var shadow := false
	for i in 6:
		var dx: int = px - cx[i]
		var dy: int = py - cy[i]
		# Küme: 2x2 gövde + kümeye göre değişen bir çıkıntı
		var ex := 2 if i % 2 == 0 else -1
		var ey := 0 if i % 3 == 0 else 1
		var inside := (dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1) or (dx == ex and dy == ey)
		if inside:
			if dx == 0 and dy == 0:
				return ore.lightened(0.35)
			if dx == 1 and dy == 1:
				return ore.darkened(0.2)
			return _v(ore, n, 0.06)
		var sx := dx - 1
		var sy := dy - 1
		if (sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1) or (sx == ex and sy == ey):
			shadow = true
	if shadow:
		return Color(0.3, 0.3, 0.33)
	return _stone(px, py, n)


static func _pixel(t: int, px: int, py: int, n: float) -> Color:
	match t:
		0:
			return _grass_top(px, py, n)
		1:
			# Çim örtüsü sütuna göre 2-4 piksel sarkar; altında bir piksel gölge.
			var depth := 2 + int(_h(47, px, 0) * 3.0)
			if py < depth:
				var g := _grass_top(px, py, n)
				return g.lightened(0.08) if py == 0 else g
			if py == depth:
				return _dirt(px, py, n).darkened(0.28)
			return _dirt(px, py, n)
		2:
			return _dirt(px, py, n)
		3:
			return _stone(px, py, n)
		4:
			# Kabuk: sütun sütun değişen tonlar, derin oluklar, kısa yatay yarıklar.
			var hc := _h(48, px, 0)
			var bark := Color(0.4, 0.29, 0.17)
			if hc < 0.28:
				bark = Color(0.27, 0.19, 0.11)
			elif hc > 0.72:
				bark = Color(0.47, 0.35, 0.21)
			if _h(49, px, py >> 2) < 0.16:
				bark = bark.darkened(0.3)
			elif _h(50, px, py) < 0.07:
				bark = bark.lightened(0.14)
			return _v(bark, n, 0.05)
		5:
			if px == 0 or px == 15 or py == 0 or py == 15:
				return _v(Color(0.33, 0.24, 0.14), n, 0.08)
			# Yuvarlak yaş halkaları, ortada koyu öz.
			var d := Vector2(px - 7.5, py - 7.5).length()
			if d < 1.2:
				return Color(0.5, 0.37, 0.2)
			var ring := Color(0.74, 0.6, 0.38)
			if int(d * 0.9 + _h(51, px, py) * 0.3) % 2 == 0:
				ring = Color(0.62, 0.48, 0.28)
			return _v(ring, n, 0.04)
		6:
			# Dolgun yaprak: koyu boşluklar, üç ton yeşil, parlak uçlar.
			var lb := _blot(52, px, py, 4) * 0.55 + n * 0.45
			if n < 0.09:
				return Color(0.07, 0.24, 0.07)
			if n > 0.92:
				return Color(0.36, 0.66, 0.25)
			if lb < 0.38:
				return _v(Color(0.12, 0.35, 0.1), n, 0.06)
			if lb < 0.62:
				return _v(Color(0.18, 0.45, 0.14), n, 0.06)
			return _v(Color(0.25, 0.55, 0.19), n, 0.06)
		7:
			return _v(Color(0.2, 0.42, 0.85, 0.72), n, 0.06)
		8:
			if px == 7 or px == 8:
				if py >= 6 and py <= 7:
					return _v(Color(1.0, 0.85, 0.3), n, 0.08)
				if py > 7:
					return _v(Color(0.45, 0.3, 0.15), n, 0.1)
			return Color(0, 0, 0, 0)
		9:
			var sb := _blot(53, px, py, 4)
			var sand := Color(0.86, 0.8, 0.58)
			if n < 0.07:
				sand = Color(0.74, 0.67, 0.46)
			elif sb > 0.62:
				sand = Color(0.9, 0.85, 0.64)
			return _v(sand, n, 0.04)
		10:
			return _planks(px, py, n)
		11:
			return _v(Color(0.25, 0.25, 0.27), n, 0.35)
		12:
			return _cobble(px, py, n)
		13:
			return _ore(px, py, n, Color(0.12, 0.12, 0.13))
		14:
			return _ore(px, py, n, Color(0.86, 0.66, 0.52))
		15:
			return _ore(px, py, n, Color(0.98, 0.84, 0.25))
		16:
			return _ore(px, py, n, Color(0.35, 0.92, 0.9))
		17:   # çalışma masası üstü
			var c := _planks(px, py, n)
			if px == 0 or px == 15 or py == 0 or py == 15:
				return c.darkened(0.45)
			if px == 5 or px == 10 or py == 5 or py == 10:
				return c.darkened(0.3)
			return c
		18:   # çalışma masası yanı
			var c := _planks(px, py, n)
			if py < 3:
				return c.darkened(0.35)
			if py >= 6 and py <= 9 and ((px >= 3 and px <= 5) or (px >= 10 and px <= 12)):
				return Color(0.3, 0.3, 0.32)
			return c
		19:   # fırın yanı
			if px >= 4 and px <= 11 and py >= 9 and py <= 13:
				return Color(0.06, 0.05, 0.05)
			if px >= 4 and px <= 11 and py >= 4 and py <= 6:
				return Color(0.2, 0.2, 0.22)
			return _cobble(px, py, n)
		_:    # fırın üstü
			var c := _v(Color(0.42, 0.42, 0.44), n, 0.1)
			if px == 0 or px == 15 or py == 0 or py == 15:
				return c.darkened(0.3)
			return c


# ---------- Eşya simgeleri ----------
# Her simge 32x32 pikseldir: şekil + ışık yönüne göre gölgeleme + koyu dış çizgi.

static func _build_items() -> Image:
	var img := Image.create(ITEM_TILE * ITEM_COLS, ITEM_TILE * ITEM_ROWS, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for icon in ITEM_COLS * ITEM_ROWS:
		if icon > 4 and (icon < 8 or icon >= 23) and not Items.DEFS.has(Items.SWORD_WOOD + icon - RPG_ICON_BASE):
			continue
		var tile := Image.create(ITEM_TILE, ITEM_TILE, false, Image.FORMAT_RGBA8)
		for py in ITEM_TILE:
			for px in ITEM_TILE:
				var c := _item_pixel(icon, px + 0.5, py + 0.5)
				if c.a > 0.0:
					c = _v(c, rng.randf(), 0.045)
				tile.set_pixel(px, py, c)
		var ox := (icon % ITEM_COLS) * ITEM_TILE
		var oy := (icon >> 3) * ITEM_TILE
		for py in ITEM_TILE:
			for px in ITEM_TILE:
				var c := tile.get_pixel(px, py)
				if c.a > 0.0 and _edge(tile, px, py):
					c = c.darkened(0.55)
				img.set_pixel(ox + px, oy + py, c)
	return img


## Piksel şeklin kenarında mı? (dış çizgi için)
static func _edge(t: Image, x: int, y: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := x + d.x
		var ny := y + d.y
		if nx < 0 or ny < 0 or nx >= ITEM_TILE or ny >= ITEM_TILE or t.get_pixel(nx, ny).a == 0.0:
			return true
	return false


## Zırh, kalkan, yiyecek, iksir, totem ve taç simgeleri. (u, v): sol alttan sağ üste uzanan eksen.
static func _rpg_pixel(id: int, fx: float, fy: float, u: float, v: float) -> Color:
	var none := Color(0, 0, 0, 0)
	var iron := Color(0.74, 0.76, 0.82)
	var gold := Color(0.98, 0.82, 0.22)
	var dx := fx - 16.0
	var light := (-dx - (fy - 16.0)) / 16.0
	match id:
		Items.HELMET:
			var inside := false
			if fy < 17.0:
				inside = Vector2(dx, fy - 17.0).length() < 10.5
			elif fy < 23.0:
				inside = absf(dx) < 10.5 and not (absf(dx) < 5.5 and fy > 19.0)
			if not inside:
				return none
			if absf(dx) < 1.3 and fy < 19.0:
				return _lit(iron, 0.9)
			return _lit(iron, light * 1.2)
		Items.CHESTPLATE:
			if Vector2(dx, fy - 6.0).length() < 4.5:
				return none
			if (fy >= 6.0 and fy < 13.0 and absf(dx) < 12.5) or (fy >= 13.0 and fy < 27.0 and absf(dx) < 7.5):
				if fy >= 13.0 and int(fy) % 5 == 0:
					return _lit(iron, -0.5)
				return _lit(iron, light * 1.3)
			return none
		Items.LEGGINGS:
			if fy >= 4.0 and fy < 10.0 and absf(dx) < 8.5:
				return _lit(iron, light + 0.2)
			if fy >= 10.0 and fy < 23.0 and absf(dx) > 1.5 and absf(dx) < 8.5:
				return _lit(iron, light)
			if fy >= 23.0 and fy < 28.0 and absf(dx) > 1.5 and dx > -8.5 - (2.0 if dx < 0.0 else 0.0) and dx < 8.5 + (2.0 if dx > 0.0 else 0.0):
				return _lit(Color(0.45, 0.3, 0.18), light)
			return none
		Items.SHIELD_WOOD, Items.SHIELD_IRON, Items.SHIELD_DIAMOND:
			var c: Color = [Color(0.62, 0.46, 0.26), iron, TIER_COLORS[4]][id - Items.SHIELD_WOOD]
			if fy < 4.5 or fy > 28.5:
				return none
			var hw := 9.5 if fy < 17.0 else 9.5 * (1.0 - (fy - 17.0) / 11.5)
			if absf(dx) >= hw:
				return none
			if hw - absf(dx) < 1.8 or fy < 6.3:
				return _lit(c.darkened(0.35), light)
			if Vector2(dx, fy - 14.0).length() < 2.6:
				return _lit(Color(0.85, 0.85, 0.88), 0.6)
			if absf(dx) < 0.9 or absf(fy - 14.0) < 0.9:
				return _lit(c.darkened(0.2), light)
			return _lit(c, light * 1.2)
		Items.MEAT_CHICKEN, Items.MEAT_MUTTON:
			# but: beyaz kemik + ucunda et
			var meat := Color(0.83, 0.55, 0.27) if id == Items.MEAT_CHICKEN else Color(0.6, 0.33, 0.24)
			var big := 1.0 if id == Items.MEAT_CHICKEN else 1.2
			var e := pow((u - 20.0) / (8.0 * big), 2.0) + pow(v / (5.6 * big), 2.0)
			if e < 1.0:
				return _lit(meat, v / 6.0 + (0.3 if e < 0.35 else 0.0))
			if u > 2.0 and u < 14.0 and absf(v) < 1.6:
				return _lit(Color(0.93, 0.9, 0.84), v / 1.6)
			if Vector2(u - 2.5, absf(v) - 1.4).length() < 1.9:
				return Color(0.93, 0.9, 0.84)
			return none
		Items.MEAT_PORK, Items.MEAT_BEEF, Items.ROTTEN_FLESH:
			var e := pow(dx / 11.0, 2.0) + pow((fy - 16.0) / 7.5, 2.0)
			if e >= 1.0:
				return none
			if id == Items.MEAT_PORK:
				if e > 0.62 and fy < 15.0:
					return _lit(Color(0.96, 0.9, 0.8), light)
				return _lit(Color(0.86, 0.52, 0.45), light * 1.2)
			if id == Items.MEAT_BEEF:
				if Vector2(dx + 4.0, fy - 15.0).length() < 2.2:
					return Color(0.94, 0.9, 0.82)
				if int(fx + fy) % 6 == 0:
					return Color(0.3, 0.14, 0.1)
				return _lit(Color(0.56, 0.27, 0.2), light * 1.2)
			if (int(fx * 0.7) * 7 + int(fy * 0.7) * 3) % 5 == 0:
				return Color(0.28, 0.22, 0.12)
			return _lit(Color(0.47, 0.52, 0.25), light * 1.2)
		Items.POTION_ATTACK, Items.POTION_INT, Items.POTION_DEFENSE, Items.POTION_SPEED:
			var liquid: Color = [Color(0.88, 0.2, 0.2), Color(0.3, 0.42, 0.96), Color(0.3, 0.78, 0.36), Color(0.96, 0.8, 0.2)][id - Items.POTION_ATTACK]
			var glass := Color(0.82, 0.9, 0.95)
			if fy >= 3.0 and fy < 6.5 and absf(dx) < 3.0:
				return _lit(Color(0.55, 0.38, 0.2), light)
			if fy >= 6.5 and fy < 13.0 and absf(dx) < 2.6:
				return _lit(glass, -dx / 2.6)
			var rr := Vector2(dx, fy - 20.0).length()
			if rr < 8.6:
				if rr < 6.9 and fy > 16.5:
					return _lit(liquid, light * 1.4 + (0.5 if Vector2(dx + 2.5, fy - 18.5).length() < 1.6 else 0.0))
				return _lit(glass, light)
			return none
		Items.TOTEM:
			if fy >= 5.0 and fy < 13.0 and absf(dx) < 5.5:
				if fy >= 8.0 and fy < 10.0 and absf(absf(dx) - 2.5) < 1.0:
					return Color(0.15, 0.75, 0.35)
				return _lit(gold, light + 0.2)
			if fy >= 13.0 and fy < 27.0 and absf(dx) < 4.5:
				return _lit(gold, light)
			if fy >= 14.0 and fy < 18.5 and absf(dx) < 10.5:
				return _lit(gold.darkened(0.15), light)
			return none
		Items.CROWN:
			if fy >= 18.0 and fy < 26.0 and absf(dx) < 11.0:
				if Vector2(dx, fy - 22.0).length() < 2.0:
					return Color(0.85, 0.15, 0.2)
				if Vector2(absf(dx) - 6.5, fy - 22.0).length() < 1.6:
					return Color(0.25, 0.45, 0.95)
				return _lit(gold, light + 0.1)
			if fy >= 7.0 and fy < 18.0:
				for cx: float in [-8.0, 0.0, 8.0]:
					if absf(dx - cx) < (fy - 7.0) * 0.38 + 0.6:
						return _lit(gold, light + 0.3)
			return none
	return none


## l: -1 (gölge) .. +1 (ışık)
static func _lit(c: Color, l: float) -> Color:
	l = clampf(l, -1.0, 1.0)
	return c.lightened(0.32 * l) if l > 0.0 else c.darkened(-0.38 * l)


static func _item_pixel(icon: int, fx: float, fy: float) -> Color:
	var none := Color(0, 0, 0, 0)
	var wood := Color(0.56, 0.39, 0.2)
	# Sap ekseni: sol alttan sağ üste. u: sap boyunca, v: sapa dik (sol üst = ışıklı taraf).
	var dx := fx - 5.0
	var dy := fy - 27.0
	var u := (dx - dy) * 0.7071
	var v := (-dx - dy) * 0.7071
	if icon >= RPG_ICON_BASE and icon < RPG_ICON_BASE + 6:
		# Kılıç: ahşap kabza, koyu siperlik, kademeye göre renkli ve ucu sivrilen namlu
		var blade: Color = TIER_COLORS[icon - RPG_ICON_BASE]
		if u > 1.0 and u <= 7.5 and absf(v) < 1.8:
			return _lit(wood, v / 1.8)
		if u > 7.5 and u <= 10.0 and absf(v) < 5.6:
			return _lit(blade.darkened(0.45), v / 5.6)
		if u > 10.0 and u < 31.0:
			var hw := 2.9 * minf(1.0, (31.0 - u) / 4.5)
			if absf(v) < hw:
				return _lit(blade, 0.9 if absf(v) < 0.7 else v / hw * 0.8)
		return none
	if icon >= RPG_ICON_BASE:
		return _rpg_pixel(Items.SWORD_WOOD + icon - RPG_ICON_BASE, fx, fy, u, v)
	match icon:
		0:   # çubuk
			if u > 1.5 and u < 30.0 and absf(v) < 1.9:
				return _lit(wood, v / 1.9)
			return none
		1:   # kömür: üç topaktan oluşan parlak yüzeyli parça
			var inside := Vector2(fx - 13.0, fy - 18.0).length() < 7.0 \
				or Vector2(fx - 19.5, fy - 14.0).length() < 6.5 \
				or Vector2(fx - 18.5, fy - 20.5).length() < 6.0
			if not inside:
				return none
			var light := (-(fx - 16.0) - (fy - 17.0)) / 12.0
			if (int(fx / 3.0) + int(fy / 3.0)) % 3 == 0:
				light += 0.5
			return _lit(Color(0.17, 0.17, 0.19), light * 1.3)
		2, 3:   # külçe: üst, ön ve yan yüzü görünen çubuk
			var c: Color = TIER_COLORS[icon]
			if fy >= 11.0 and fy < 17.0:
				var s := 17.0 - fy
				if fx >= 5.0 + s and fx < 21.0 + s:
					return c.lightened(0.35)
			if fy >= 17.0 and fy < 23.0 and fx >= 5.0 and fx < 21.0:
				return c
			if fx >= 21.0 and fx < 27.0:
				var k := fx - 21.0
				if fy >= 17.0 - k and fy < 23.0 - k:
					return c.darkened(0.32)
			return none
		4:   # elmas: yüzeyli (fasetalı) taş
			var c: Color = TIER_COLORS[4]
			var ax := absf(fx - 16.0)
			if fy >= 7.0 and fy < 13.0:
				if ax < 6.0 + (fy - 7.0) * 0.9:
					return _lit(c, 1.0 if ax < 3.0 else (0.55 if fx < 16.0 else 0.1))
			elif fy >= 13.0 and fy < 26.0:
				var hw := 11.4 * (1.0 - (fy - 13.0) / 13.0)
				if ax < hw:
					var l := 0.15 if fx < 16.0 else -0.55
					if ax < hw * 0.35:
						l += 0.35
					return _lit(c, l)
			return none
	if icon < 8 or icon >= 23:
		return none
	# Aletler: gölgeli ahşap sap + kademeye göre renkli baş
	var tier := (icon - 8) / 3
	var type := (icon - 8) % 3
	var head: Color = TIER_COLORS[tier]
	match type:
		0:   # kazma: sapın ucunda yay biçiminde baş
			var rr := sqrt(u * u + v * v)
			var t := absf(atan2(v, u)) / 0.62
			if t < 1.0 and absf(rr - 24.0) < 2.4 * (1.0 - t * t * 0.55):
				return _lit(head, (rr - 24.0) / 2.0)
		1:   # balta: sapın bir yanında kavisli ağız
			if u > 13.5 and u < 25.0 and v > -1.8 and v < 9.5 - (u - 19.2) * (u - 19.2) * 0.13:
				return _lit(head, (v - 3.5) / 5.0)
		2:   # kürek: sapın ucunda oval ağız
			var e := pow((u - 24.5) / 5.5, 2.0) + pow(v / 4.2, 2.0)
			if e < 1.0:
				return _lit(head, v / 3.5)
	var handle_len := 22.0 if type != 2 else 20.5
	if u > 0.5 and u < handle_len and absf(v) < 1.7:
		return _lit(wood, v / 1.7)
	return none
