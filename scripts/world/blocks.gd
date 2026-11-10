class_name Blocks
## Blok kimlikleri ve özellikleri.

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const PLANKS := 4
const LOG := 5
const LEAVES := 6
const WATER := 7
const TORCH := 8
const SAND := 9
const BEDROCK := 10
const COUNT := 11

const NAMES := ["Hava", "Çim", "Toprak", "Taş", "Tahta", "Kütük", "Yaprak", "Su", "Meşale", "Kum", "Katman Kayası"]

## Hotbar'daki bloklar (yaratıcı mod: sınırsız).
const HOTBAR := [GRASS, DIRT, STONE, PLANKS, LOG, LEAVES, WATER, TORCH, SAND]

## Her blok için atlas karoları: [üst, yan, alt]
const TILES := [
	[0, 0, 0],    # hava
	[0, 1, 2],    # çim
	[2, 2, 2],    # toprak
	[3, 3, 3],    # taş
	[10, 10, 10], # tahta
	[5, 4, 5],    # kütük
	[6, 6, 6],    # yaprak
	[7, 7, 7],    # su
	[8, 8, 8],    # meşale
	[9, 9, 9],    # kum
	[11, 11, 11], # katman kayası
]


## Işığı/komşu yüzleri tamamen kapatan ve içinden geçilemeyen bloklar.
static func is_solid(id: int) -> bool:
	return id != AIR and id != WATER and id != TORCH


static func key(p: Vector3i) -> String:
	return "%d_%d_%d" % [p.x, p.y, p.z]


static func parse_key(k: String) -> Variant:
	var parts := k.split("_")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
