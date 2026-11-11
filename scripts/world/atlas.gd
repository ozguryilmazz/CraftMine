class_name Atlas
## Blok ve eşya dokularını çalışma anında üretir.
## Blok atlası 8x8 karo, eşya atlası 8x4 simge; her karo 16 piksel.

const TILE := 16
const GRID := 8
const TILE_COUNT := 21
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
	for t in TILE_COUNT:
		var ox := (t & 7) * TILE
		var oy := (t >> 3) * TILE
		for py in TILE:
			for px in TILE:
				img.set_pixel(ox + px, oy + py, _pixel(t, px, py, rng.randf()))
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


static func _ore(px: int, py: int, n: float, ore: Color) -> Color:
	if (((px >> 1) * 5 + (py >> 1) * 3) % 7) == 0 and px > 0 and px < 15 and py > 0 and py < 15:
		return _v(ore, n, 0.1)
	return _v(Color(0.5, 0.5, 0.52), n, 0.16)


static func _pixel(t: int, px: int, py: int, n: float) -> Color:
	var grass := Color(0.33, 0.62, 0.22)
	var dirt := Color(0.52, 0.37, 0.25)
	match t:
		0:
			return _v(grass, n, 0.12)
		1:
			if py < 3 or (py == 3 and n > 0.5):
				return _v(grass, n, 0.12)
			return _v(dirt, n, 0.14)
		2:
			return _v(dirt, n, 0.14)
		3:
			return _v(Color(0.5, 0.5, 0.52), n, 0.16)
		4:
			var bark := Color(0.4, 0.29, 0.17)
			if px % 4 == 0:
				bark = bark.darkened(0.25)
			return _v(bark, n, 0.08)
		5:
			if px == 0 or px == 15 or py == 0 or py == 15:
				return _v(Color(0.4, 0.29, 0.17), n, 0.08)
			var d := int(maxf(absf(px - 7.5), absf(py - 7.5)))
			var ring := Color(0.72, 0.58, 0.36)
			if d % 2 == 0:
				ring = ring.darkened(0.18)
			return _v(ring, n, 0.05)
		6:
			return _v(Color(0.18, 0.45, 0.14), n, 0.25)
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
			return _v(Color(0.86, 0.8, 0.58), n, 0.08)
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
		if icon > 4 and (icon < 8 or icon >= 23) and (icon < RPG_ICON_BASE or icon >= RPG_ICON_BASE + 6):
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
