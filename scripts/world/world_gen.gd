class_name WorldGen
extends RefCounted
## Tohum (seed) tabanlı, deterministik arazi üretimi. Aynı tohum her cihazda aynı dünyayı verir.

const CW := 16
const CH := 64
const SEA := 20
const VOLUME := CW * CW * CH

var world_seed: int
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(p_seed: int) -> void:
	world_seed = p_seed
	_hills.seed = p_seed
	_hills.noise_type = FastNoiseLite.TYPE_PERLIN
	_hills.frequency = 0.008
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 3
	_detail.seed = p_seed + 7919
	_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail.frequency = 0.05
	_detail.fractal_type = FastNoiseLite.FRACTAL_NONE


## (wx, wz) sütunundaki en üst katı bloğun y değeri.
func height_at(wx: int, wz: int) -> int:
	var h := 25.0 + _hills.get_noise_2d(wx, wz) * 26.0 + _detail.get_noise_2d(wx, wz) * 2.5
	return clampi(int(h), 3, CH - 12)


## Bu sütunda ağaç varsa gövde yüksekliğini, yoksa 0 döndürür.
func tree_at(wx: int, wz: int) -> int:
	var n := wx * 374761393 + wz * 668265263 + world_seed * 1274126177
	n = ((n ^ (n >> 13)) & 0xffffffff) * 1274126177
	n = (n ^ (n >> 16)) & 0x7fffffff
	if n % 1000 >= 14:
		return 0
	return 4 + ((n >> 12) % 2)


func generate(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VOLUME)
	var bx := cx * CW
	var bz := cz * CW
	# Arazi
	for lz in CW:
		for lx in CW:
			var h := height_at(bx + lx, bz + lz)
			var col := lz * CW + lx
			var beach := h <= SEA + 1
			data[col] = Blocks.BEDROCK
			for y in range(1, h + 1):
				var id := Blocks.STONE
				if y >= h - 3:
					if beach:
						id = Blocks.SAND
					elif y == h:
						id = Blocks.GRASS
					else:
						id = Blocks.DIRT
				data[y * 256 + col] = id
			for y in range(h + 1, SEA + 1):
				data[y * 256 + col] = Blocks.WATER
	# Ağaçlar (komşu chunk'lardan taşan yapraklar için 2 blok pay)
	for tz in range(-2, CW + 2):
		for tx in range(-2, CW + 2):
			var th := tree_at(bx + tx, bz + tz)
			if th == 0:
				continue
			var h := height_at(bx + tx, bz + tz)
			if h <= SEA + 1:
				continue
			for dy in range(th - 2, th + 2):
				var r := 2 if dy < th else 1
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if absi(dx) == r and absi(dz) == r and r == 2 and dy == th - 1:
							continue
						var x := tx + dx
						var z := tz + dz
						if x < 0 or x >= CW or z < 0 or z >= CW:
							continue
						var i := (h + 1 + dy) * 256 + z * CW + x
						if data[i] == Blocks.AIR:
							data[i] = Blocks.LEAVES
			if tx >= 0 and tx < CW and tz >= 0 and tz < CW:
				for dy in th:
					data[(h + 1 + dy) * 256 + tz * CW + tx] = Blocks.LOG
	return data
