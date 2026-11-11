class_name Inventory
extends RefCounted
## Oyuncu envanteri: 36 yuva; ilk 9'u hotbar'dır. Her yuva (eşya kimliği, adet, kalan dayanıklılık) tutar.
## Dayanıklılığı olan eşyalar (kılıç, zırh, kalkan) yığınlanmaz; dayanıklılığı olmayanlarda değer 0'dır.

const SIZE := 36
const HOTBAR := 9
## Ekipman yuvaları ana envanterin ardından gelir (SIZE + 0..3): kafalık, göğüslük, pantolon, kalkan.
const EQUIP := 4
const TOTAL := SIZE + EQUIP
const EQUIP_KINDS := ["helmet", "chest", "legs", "shield"]
const EQUIP_NAMES := ["kafalık", "göğüslük", "pantolon", "kalkan"]

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var durs := PackedInt32Array()


func _init() -> void:
	ids.resize(TOTAL)
	counts.resize(TOTAL)
	durs.resize(TOTAL)


static func _norm_dur(id: int, dur: int) -> int:
	var full := Items.max_durability(id)
	if full <= 0:
		return 0
	return full if dur <= 0 else mini(dur, full)


## Eşya ekler; önce aynı türden yığınları doldurur, sonra boş yuvaları. Sığmayan adedi döndürür.
## dur: kalan dayanıklılık (-1: yeni eşya, tam dayanıklılık).
func add(id: int, n: int, dur := -1) -> int:
	if id <= 0:
		return 0
	var cap := Items.max_stack(id)
	for i in SIZE:
		if n <= 0:
			return 0
		if ids[i] == id and counts[i] > 0 and counts[i] < cap:
			var k := mini(n, cap - counts[i])
			counts[i] += k
			n -= k
	for i in SIZE:
		if n <= 0:
			return 0
		if counts[i] == 0:
			var k := mini(n, cap)
			ids[i] = id
			counts[i] = k
			durs[i] = _norm_dur(id, dur)
			n -= k
	return n


## Belirtilen adedin tamamı sığar mı?
func can_add(id: int, n: int) -> bool:
	var cap := Items.max_stack(id)
	for i in SIZE:
		if counts[i] == 0:
			n -= cap
		elif ids[i] == id:
			n -= cap - counts[i]
		if n <= 0:
			return true
	return false


## Yuvadan en fazla n adet alır; alınan adedi döndürür.
func take(slot: int, n: int) -> int:
	var k := mini(n, counts[slot])
	counts[slot] -= k
	if counts[slot] == 0:
		ids[slot] = 0
		durs[slot] = 0
	return k


func id_at(slot: int) -> int:
	return ids[slot] if counts[slot] > 0 else 0


func dur_at(slot: int) -> int:
	return durs[slot] if counts[slot] > 0 else 0


func set_slot(slot: int, id: int, n: int, dur := -1) -> void:
	if id <= 0 or n <= 0:
		ids[slot] = 0
		counts[slot] = 0
		durs[slot] = 0
		return
	ids[slot] = id
	counts[slot] = n
	durs[slot] = _norm_dur(id, dur)


## Yuvadaki eşyayı k kez yıpratır. Eşya kırılıp yok olduysa true döner.
func wear(slot: int, k := 1) -> bool:
	if counts[slot] <= 0 or Items.max_durability(ids[slot]) <= 0:
		return false
	durs[slot] -= k
	if durs[slot] <= 0:
		set_slot(slot, 0, 0)
		return true
	return false


## Eşyanın bulunduğu ilk yuva (ana envanterde); yoksa -1.
func find(id: int) -> int:
	for i in SIZE:
		if counts[i] > 0 and ids[i] == id:
			return i
	return -1


## Ekipman yuvasına (0..3) bu eşya takılabilir mi?
static func fits_equip(eq: int, id: int) -> bool:
	return Items.kind(id) == EQUIP_KINDS[eq]


## Takılı zırh ve kalkanların toplam can bonusu.
func equip_hp() -> int:
	var total := 0
	for i in EQUIP:
		total += int(Items.prop(id_at(SIZE + i), "hp", 0))
	return total


## Oyuncu darbe aldı: takılı her parça 1 yıpranır. Kırılan eşyaların kimliklerini döndürür.
func wear_equipment() -> Array[int]:
	var broken: Array[int] = []
	for i in EQUIP:
		var id := id_at(SIZE + i)
		if id > 0 and wear(SIZE + i):
			broken.append(id)
	return broken


## Tüm envanteri ve ekipmanı siler (ölüm cezası).
func clear() -> void:
	for i in TOTAL:
		set_slot(i, 0, 0)


## Kayıt: her yuva için (kimlik, adet, dayanıklılık).
func to_array() -> Array:
	var out := []
	for i in TOTAL:
		out.append(ids[i])
		out.append(counts[i])
		out.append(durs[i])
	return out


## Kayıttan yükler. Eski sürümlerin (kimlik, adet) biçimini de kabul eder.
func from_array(a: Variant) -> void:
	if not (a is Array):
		return
	if a.size() == TOTAL * 3 or a.size() == SIZE * 3:   # SIZE * 3: ekipman yuvalarından önceki kayıtlar
		for i in a.size() / 3:
			set_slot(i, int(a[i * 3]), int(a[i * 3 + 1]), int(a[i * 3 + 2]))
	elif a.size() == SIZE * 2:
		for i in SIZE:
			set_slot(i, int(a[i * 2]), int(a[i * 2 + 1]))
