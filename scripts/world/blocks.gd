class_name Blocks
## Blok kimlikleri ve özellikleri. Kimlikler kayıt dosyalarında ve ağda kullanılır; sırayı değiştirmeyin.

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
const COBBLE := 11
const COAL_ORE := 12
const IRON_ORE := 13
const GOLD_ORE := 14
const DIAMOND_ORE := 15
const CRAFTING_TABLE := 16
const FURNACE := 17
const COUNT := 18

const NAMES := [
	"Hava", "Çim", "Toprak", "Taş", "Tahta", "Kütük", "Yaprak", "Su", "Meşale", "Kum", "Katman Kayası",
	"Kırık Taş", "Kömür Cevheri", "Demir Cevheri", "Altın Cevheri", "Elmas Cevheri", "Çalışma Masası", "Fırın",
]

## Alet türleri (INFO tablosundaki 2. sütun)
const TOOL_NONE := 0
const TOOL_PICKAXE := 1
const TOOL_AXE := 2
const TOOL_SHOVEL := 3

## Her blok için: [elle kırma süresi (sn; -1 kırılamaz), uygun alet türü,
##                 eşya düşürmesi için gereken alet seviyesi (-1: elle de düşer), düşen eşya (0: yok)]
const INFO := [
	[0.0, 0, -1, 0],                   # hava
	[0.9, 3, -1, 2],                   # çim -> toprak
	[0.75, 3, -1, 2],                  # toprak
	[6.0, 1, 0, 11],                   # taş -> kırık taş
	[3.0, 2, -1, 4],                   # tahta
	[3.0, 2, -1, 5],                   # kütük
	[0.35, 0, -1, 0],                  # yaprak (bazen çubuk düşer)
	[0.0, 0, -1, 0],                   # su
	[0.0, 0, -1, 8],                   # meşale
	[0.75, 3, -1, 9],                  # kum
	[-1.0, 0, -1, 0],                  # katman kayası
	[6.0, 1, 0, 11],                   # kırık taş
	[7.0, 1, 0, 101],                  # kömür cevheri -> kömür
	[7.0, 1, 1, 13],                   # demir cevheri (taş kazma ve üstü)
	[7.0, 1, 2, 14],                   # altın cevheri (demir kazma ve üstü)
	[7.0, 1, 2, 104],                  # elmas cevheri -> elmas (demir kazma ve üstü)
	[3.0, 2, -1, 16],                  # çalışma masası
	[7.0, 1, 0, 17],                   # fırın
]

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
	[12, 12, 12], # kırık taş
	[13, 13, 13], # kömür cevheri
	[14, 14, 14], # demir cevheri
	[15, 15, 15], # altın cevheri
	[16, 16, 16], # elmas cevheri
	[17, 18, 10], # çalışma masası
	[20, 19, 20], # fırın
]


## Işığı/komşu yüzleri tamamen kapatan ve içinden geçilemeyen bloklar.
static func is_solid(id: int) -> bool:
	return id != AIR and id != WATER and id != TORCH


## Dokununca (yerleştirme hareketiyle) arayüz açan bloklar.
static func is_interactive(id: int) -> bool:
	return id == CRAFTING_TABLE or id == FURNACE


static func key(p: Vector3i) -> String:
	return "%d_%d_%d" % [p.x, p.y, p.z]


static func parse_key(k: String) -> Variant:
	var parts := k.split("_")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
