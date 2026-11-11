class_name Loot
## Mob ganimet tabloları (mns2026) ve sandık içeriği zarı.

## Sandıktan çıkan eşya sayısı zincirleme belirlenir: %80 ile 1. eşya, çıktıysa %50 ile 2., ... (hiç çıkmazsa sandık düşmez).
const COUNT_CHAIN := [0.8, 0.5, 0.2, 0.1, 0.06, 0.01]
## Sütun ağırlıkları: hangi sütundaki eşyanın çıkacağı bu ağırlıklarla, aynı sütun tekrar etmeden seçilir.
const WEIGHTS := [0.6, 0.3, 0.2, 0.1, 0.05, 0.01]
const WEIGHTS_STRONG := [0.6, 0.4, 0.2, 0.1, 0.05, 0.01]   # aktif moblar ve boss'lar

## Her mob için 6 sütun: [eşya, adet] ya da [eşya, adet, dayanıklılık oranı].
const TABLES := {
	"chicken": [[150, 1], [100, 1], [5, 1], [11, 1], [130, 1], [145, 1]],
	"pig": [[151, 1], [100, 2], [5, 2], [11, 2], [130, 1], [145, 1]],
	"cow": [[152, 1], [100, 3], [5, 3], [11, 3], [132, 1], [146, 1]],
	"sheep": [[153, 1], [100, 4], [5, 3], [11, 4], [132, 1], [146, 1]],
	"wolf": [[5, 10], [100, 10], [140, 1], [146, 1], [132, 1], [134, 1]],
	"bee": [[11, 10], [100, 20], [141, 1], [146, 1], [132, 1], [134, 1]],
	"angry_villager": [[5, 20], [130, 1], [142, 1], [134, 1], [134, 1], [135, 1]],
	"wizard_villager": [[11, 20], [132, 1], [142, 1], [134, 1], [134, 1], [135, 1]],
	"zombie": [[154, 1], [140, 1], [163, 1], [160, 1], [146, 1], [147, 1]],
	"skeleton": [[145, 1, 0.3], [130, 1, 0.2], [162, 1], [161, 1], [146, 1], [147, 1]],
	"creeper": [[146, 1, 0.3], [132, 1, 0.2], [160, 1], [162, 1], [147, 1], [170, 1]],
	"golem": [[132, 1], [133, 1], [162, 2], [135, 1], [170, 1], [171, 1]],
	"giant_spider": [[133, 1], [134, 1], [160, 2], [134, 1], [135, 1], [171, 1]],
}


## Bir mobun sandık içeriğini zarla belirler: [[eşya, adet, dayanıklılık (-1: tam)], ...]. Boş dönebilir.
static func roll(type: String) -> Array:
	var table: Array = TABLES.get(type, [])
	if table.is_empty():
		return []
	var count := 0
	for chance: float in COUNT_CHAIN:
		if randf() >= chance:
			break
		count += 1
	var kind: String = MobDB.DEFS[type]["k"]
	var weights: Array = (WEIGHTS_STRONG if kind == "active" or kind == "boss" else WEIGHTS).duplicate()
	var out := []
	for i in mini(count, table.size()):
		var total := 0.0
		for w: float in weights:
			total += w
		var r := randf() * total
		var col := 0
		for c in weights.size():
			r -= float(weights[c])
			if r <= 0.0 and float(weights[c]) > 0.0:
				col = c
				break
			if float(weights[c]) > 0.0:
				col = c
		weights[col] = 0.0   # aynı sütun bir daha çıkmaz
		var e: Array = table[col]
		var dur := -1
		if e.size() > 2:
			dur = maxi(roundi(Items.max_durability(e[0]) * float(e[2])), 1)
		out.append([int(e[0]), int(e[1]), dur])
	return out
