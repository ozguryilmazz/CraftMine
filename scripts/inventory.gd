class_name Inventory
extends RefCounted
## Oyuncu envanteri: 36 yuva; ilk 9'u hotbar'dır. Her yuva (eşya kimliği, adet) tutar.

const SIZE := 36
const HOTBAR := 9

var ids := PackedInt32Array()
var counts := PackedInt32Array()


func _init() -> void:
	ids.resize(SIZE)
	counts.resize(SIZE)


## Eşya ekler; önce aynı türden yığınları doldurur, sonra boş yuvaları. Sığmayan adedi döndürür.
func add(id: int, n: int) -> int:
	if id <= 0:
		return 0
	var cap := Items.max_stack(id)
	for i in SIZE:
		if n <= 0:
			return 0
		if ids[i] == id and counts[i] < cap:
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
	return k


func id_at(slot: int) -> int:
	return ids[slot] if counts[slot] > 0 else 0


func set_slot(slot: int, id: int, n: int) -> void:
	ids[slot] = id if n > 0 else 0
	counts[slot] = n if id > 0 else 0


func to_array() -> Array:
	var out := []
	for i in SIZE:
		out.append(ids[i])
		out.append(counts[i])
	return out


func from_array(a: Variant) -> void:
	if not (a is Array) or a.size() != SIZE * 2:
		return
	for i in SIZE:
		set_slot(i, int(a[i * 2]), int(a[i * 2 + 1]))
