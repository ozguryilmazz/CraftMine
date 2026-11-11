class_name PlayerStats
extends RefCounted
## Oyuncunun RPG durumu: can, statlar, level / XP, süreli iksir etkileri ve ölüm cezası.
## Kurallar mns2026 tablosundan gelir; sayılar aşağıdaki sabitlerden değiştirilebilir.

const STATS := ["health", "attack", "speed", "intel"]
const STAT_NAMES := {"health": "Sağlık", "attack": "Saldırı", "speed": "Hız", "intel": "Zeka"}
## Level 0'daki stat değerleri (ekranda gösterilen taban).
const BASE := {"health": 10, "attack": 1, "speed": 1, "intel": 1}
const BASE_HP := 30                 # level 0 canı: aktif moblar (15-20 hasar) 2 vuruşta öldürür
const HP_PER_POINT := 2             # her sağlık puanı
const SPEED_PER_POINT := 0.05       # her hız puanı: +%5 hareket hızı
const CRIT_PER_POINT := 0.02        # her zeka puanı: +%2 kritik ihtimali
const CRIT_DMG_PER_POINT := 0.10    # her zeka puanı: saldırı gücünün %10'u kadar ek kritik hasarı
const MISS_BASE := 0.20             # vuruşun sekme (hasar vermeme) ihtimali
const MISS_PER_POINT := 0.01        # her zeka puanı sekmeyi bu kadar düşürür
const MAX_LEVEL := 15
## Bir sonraki levele geçmek için gereken XP (level 0 -> 1: 100, ...).
const XP_NEED := [100, 120, 130, 140, 200, 220, 240, 260, 280, 400, 450, 500, 600, 700, 1000]
## O levele İLK kez ulaşıldığında kazanılan stat puanı.
const POINTS := [3, 3, 3, 3, 5, 3, 3, 3, 3, 5, 3, 3, 3, 3, 5]

var added := {"health": 0, "attack": 0, "speed": 0, "intel": 0}   # dağıtılmış puanlar
var level := 0
var xp := 0
var best_level := 0         # bugüne kadar ulaşılan en yüksek level (puanlar bir kez verilir)
var points := 0             # dağıtılmamış stat puanı
var hp := float(BASE_HP)
var equip_hp := 0           # zırh ve kalkandan gelen can bonusu
var buffs := {}             # stat -> [miktar, kalan süre (sn)]
var _heal_left := 0.0
var _heal_rate := 0.0


## Puan + iksir etkisi.
func total(stat: String) -> int:
	var b: Variant = buffs.get(stat)
	return int(added[stat]) + (int(b[0]) if b != null else 0)


## Ekranda gösterilen stat değeri (taban + puanlar + iksir).
func shown(stat: String) -> int:
	return int(BASE[stat]) + total(stat)


func max_hp() -> int:
	return BASE_HP + total("health") * HP_PER_POINT + equip_hp


func speed_mult() -> float:
	return 1.0 + SPEED_PER_POINT * total("speed")


## Silah bonusuyla birlikte tek vuruş hasarı.
func hit_damage(weapon_dmg := 0) -> int:
	return int(BASE["attack"]) + total("attack") + weapon_dmg


func miss_chance() -> float:
	return maxf(MISS_BASE - MISS_PER_POINT * total("intel"), 0.0)


func crit_chance() -> float:
	return minf(CRIT_PER_POINT * total("intel"), 1.0)


## Kritik vuruşta eklenen hasar.
func crit_bonus() -> int:
	return ceili((int(BASE["attack"]) + total("attack")) * CRIT_DMG_PER_POINT * total("intel"))


func heal_left() -> float:
	return _heal_left


## Hasar uygular. Can bittiyse true döner.
func damage(amount: float) -> bool:
	hp = maxf(hp - amount, 0.0)
	return hp <= 0.0


## Yiyecek: canı zamanla doldurur (toplam "heal", saniyede "rate").
func eat(id: int) -> void:
	_heal_left += float(Items.prop(id, "heal", 0))
	_heal_rate = maxf(_heal_rate, float(Items.prop(id, "rate", 2.0)))


## Süreli stat etkisi (iksir). Aynı stat tekrar içilirse süre yenilenir, üst üste binmez.
func add_buff(stat: String, amount: int, time: float) -> void:
	buffs[stat] = [amount, time]


func tick(delta: float) -> void:
	for stat: String in buffs.keys():
		buffs[stat][1] -= delta
		if buffs[stat][1] <= 0.0:
			buffs.erase(stat)
	var full := float(max_hp())
	if _heal_left > 0.0:
		var k := minf(_heal_rate * delta, _heal_left)
		_heal_left -= k
		hp += k
		if hp >= full or _heal_left <= 0.0:
			_heal_left = 0.0
			_heal_rate = 0.0
	hp = minf(hp, full)


## XP ekler; atlanan level sayısını döndürür. Stat puanı yalnızca ilk kez ulaşılan levellerde verilir.
func add_xp(n: int) -> int:
	var ups := 0
	if level >= MAX_LEVEL:
		return 0
	xp += n
	while level < MAX_LEVEL and xp >= int(XP_NEED[level]):
		xp -= int(XP_NEED[level])
		level += 1
		ups += 1
		if level > best_level:
			best_level = level
			points += int(POINTS[level - 1])
	if level >= MAX_LEVEL:
		xp = 0
	return ups


func xp_needed() -> int:
	return int(XP_NEED[level]) if level < MAX_LEVEL else 0


## Bir stat puanı harcar.
func spend(stat: String) -> bool:
	if points <= 0 or not added.has(stat):
		return false
	points -= 1
	added[stat] += 1
	if stat == "health":
		hp += HP_PER_POINT
	return true


## Ölüm cezası: XP ve level sıfırlanır, her stattan 1 puan düşer (tabanın altına inmez),
## iksir etkileri biter, can dolar. Envanterin silinmesi oyun tarafında yapılır.
func die() -> void:
	xp = 0
	level = 0
	for stat: String in STATS:
		added[stat] = maxi(int(added[stat]) - 1, 0)
	buffs.clear()
	_heal_left = 0.0
	_heal_rate = 0.0
	hp = float(max_hp())


func to_dict() -> Dictionary:
	return {"added": added.duplicate(), "level": level, "xp": xp, "best": best_level, "points": points,
		"hp": hp, "buffs": buffs.duplicate(true), "heal": [_heal_left, _heal_rate]}


func from_dict(d: Variant) -> void:
	if not (d is Dictionary):
		return
	var a: Variant = d.get("added")
	if a is Dictionary:
		for stat: String in STATS:
			added[stat] = maxi(int(a.get(stat, 0)), 0)
	level = clampi(int(d.get("level", 0)), 0, MAX_LEVEL)
	xp = maxi(int(d.get("xp", 0)), 0)
	best_level = maxi(int(d.get("best", level)), level)
	points = maxi(int(d.get("points", 0)), 0)
	var b: Variant = d.get("buffs")
	if b is Dictionary:
		for stat: String in STATS:
			if b.has(stat) and b[stat] is Array and b[stat].size() == 2:
				buffs[stat] = [int(b[stat][0]), float(b[stat][1])]
	var h: Variant = d.get("heal")
	if h is Array and h.size() == 2:
		_heal_left = float(h[0])
		_heal_rate = float(h[1])
	hp = clampf(float(d.get("hp", max_hp())), 1.0, float(max_hp()))
