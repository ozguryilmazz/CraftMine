class_name Atlas
## Blok ve eşya dokularını çalışma anında üretir.
## Blok atlası 8x8 karo, eşya atlası 8x4 simge; her karo 16 piksel.

const TILE := 16
const GRID := 8
const TILE_COUNT := 21
const ITEM_COLS := 8
const ITEM_ROWS := 4

const TIER_COLORS := [
	Color(0.62, 0.46, 0.26),   # tahta
	Color(0.55, 0.55, 0.57),   # taş
	Color(0.86, 0.86, 0.9),    # demir
	Color(0.98, 0.84, 0.25),   # altın
	Color(0.35, 0.9, 0.9),     # elmas
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
	return Rect2((icon % ITEM_COLS) * TILE, (icon >> 3) * TILE, TILE, TILE)


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

static func _build_items() -> Image:
	var img := Image.create(TILE * ITEM_COLS, TILE * ITEM_ROWS, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for icon in ITEM_COLS * ITEM_ROWS:
		var ox := (icon % ITEM_COLS) * TILE
		var oy := (icon >> 3) * TILE
		for py in TILE:
			for px in TILE:
				img.set_pixel(ox + px, oy + py, _item_pixel(icon, px, py, rng.randf()))
	return img


static func _ingot(px: int, py: int, n: float, c: Color) -> Color:
	if py < 6 or py > 10:
		return Color(0, 0, 0, 0)
	var x0 := 2 + (10 - py)
	if px < x0 or px > x0 + 8:
		return Color(0, 0, 0, 0)
	if py == 6:
		c = c.lightened(0.3)
	elif py == 10 or px == x0:
		c = c.darkened(0.3)
	return _v(c, n, 0.04)


static func _item_pixel(icon: int, px: int, py: int, n: float) -> Color:
	var none := Color(0, 0, 0, 0)
	var wood := Color(0.5, 0.35, 0.18)
	match icon:
		0:   # çubuk
			if (px + py == 15 or px + py == 16) and px >= 3 and px <= 12:
				return _v(wood, n, 0.12)
			return none
		1:   # kömür
			if Vector2(px - 7.5, py - 8.0).length() < 4.6 + n * 1.2:
				return _v(Color(0.13, 0.13, 0.14), n, 0.35)
			return none
		2:
			return _ingot(px, py, n, TIER_COLORS[2])
		3:
			return _ingot(px, py, n, TIER_COLORS[3])
		4:   # elmas
			var d := absf(px - 7.5) + absf(py - 7.5)
			if d < 6.0:
				var c: Color = TIER_COLORS[4]
				if px + py < 13:
					c = c.lightened(0.35)
				elif d > 4.5:
					c = c.darkened(0.25)
				return c
			return none
	if icon < 8 or icon >= 8 + 15:
		return none
	# Aletler: çapraz sap + kademeye göre renkli baş
	var tier := (icon - 8) / 3
	var type := (icon - 8) % 3
	var head: Color = TIER_COLORS[tier]
	var is_head := false
	match type:
		0:   # kazma
			is_head = (py >= 2 and py <= 3 and px >= 5 and px <= 13) or (px >= 12 and px <= 13 and py >= 2 and py <= 10)
		1:   # balta
			is_head = px >= 8 and px <= 13 and py >= 2 and py <= 7 and not (px >= 12 and py >= 6)
		2:   # kürek
			is_head = px >= 10 and px <= 13 and py >= 2 and py <= 5
	if is_head:
		if px == 13 or py == 2:
			head = head.lightened(0.2)
		return _v(head, n, 0.06)
	if (px + py == 15 or px + py == 16) and px >= 2 and px <= 11:
		return _v(wood, n, 0.12)
	return none
