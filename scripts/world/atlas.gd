class_name Atlas
## Blok dokularını çalışma anında üretir (4x4 karo, her karo 16 piksel).

const TILE := 16
const GRID := 4

static var _tex: ImageTexture


static func texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(_build())
	return _tex


## Bir bloğun hotbar simgesi için atlas bölgesi.
static func icon_region(block: int) -> Rect2:
	if block == Blocks.TORCH:
		return Rect2(0 * TILE + 5, 2 * TILE + 5, 6, 11)
	var tile: int = Blocks.TILES[block][1]
	return Rect2((tile % GRID) * TILE, (tile >> 2) * TILE, TILE, TILE)


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


static func _build() -> Image:
	var img := Image.create(TILE * GRID, TILE * GRID, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for t in 12:
		var ox := (t % GRID) * TILE
		var oy := (t >> 2) * TILE
		for py in TILE:
			for px in TILE:
				img.set_pixel(ox + px, oy + py, _pixel(t, px, py, rng.randf()))
	return img


static func _v(c: Color, n: float, amt: float) -> Color:
	var f := 1.0 - amt + n * amt * 2.0
	return Color(c.r * f, c.g * f, c.b * f, c.a)


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
			var plank := Color(0.72, 0.56, 0.33)
			if py % 4 == 3 or px == ((py >> 2) % 2) * 8:
				plank = plank.darkened(0.25)
			return _v(plank, n, 0.06)
		_:
			return _v(Color(0.25, 0.25, 0.27), n, 0.35)
