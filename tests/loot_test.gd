extends SceneTree
## Geliştirme aracı: ganimet tabloları ve sandık zarı için otomatik test.
## Kullanım: godot --headless --path . -s res://tests/loot_test.gd

var _fail := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		_fail += 1
	print(("PASS  " if cond else "FAIL  ") + what)


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _init() -> void:
	seed(20261111)
	var all_ok := true
	for type: String in MobDB.DEFS.keys():
		var t: Array = Loot.TABLES.get(type, [])
		if t.size() != 6:
			all_ok = false
		for e: Array in t:
			if Items.item_name(e[0]) == "?" or Items.item_name(e[0]) == "":
				all_ok = false
	ok(all_ok, "13 mobun hepsinde 6 sutun ve gecerli esyalar var")

	var n := 40000
	var by_count := [0, 0, 0, 0, 0, 0, 0]
	var first_col := 0
	var dup := false
	for i in n:
		var r := Loot.roll("chicken")
		by_count[r.size()] += 1
		var seen := {}
		for it: Array in r:
			if it[0] == Items.MEAT_CHICKEN:
				first_col += 1
			if seen.has(it[0]):
				dup = true
			seen[it[0]] = true
	var at_least := [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		for c in range(k + 1, 7):
			at_least[k] += by_count[c]
		at_least[k] /= n
	ok(near(at_least[0], 0.8, 0.015), "sandik dusme orani ~%%80 (olculen %.3f)" % at_least[0])
	ok(near(at_least[1], 0.4, 0.015), "en az 2 esya ~%%40 (olculen %.3f)" % at_least[1])
	ok(near(at_least[2], 0.08, 0.008), "en az 3 esya ~%%8 (olculen %.3f)" % at_least[2])
	ok(near(at_least[3], 0.008, 0.003), "en az 4 esya ~%%0.8 (olculen %.3f)" % at_least[3])
	ok(not dup, "ayni sutun bir sandikta tekrar etmiyor")
	# tek eşyalı sandıkta 1. sütun olasılığı 0.6 / 1.26 = %47.6; toplamda biraz daha yüksek
	ok(float(first_col) / n > 0.40 and float(first_col) / n < 0.60, "tavuk eti en sik cikan esya (%.3f)" % (float(first_col) / n))

	var worn_ok := true
	var saw_shield := false
	for i in 4000:
		for it: Array in Loot.roll("skeleton"):
			if it[0] == Items.SHIELD_WOOD:
				saw_shield = true
				worn_ok = worn_ok and it[2] == 5       # 15 * %30 = 4.5 -> 5
			if it[0] == Items.SWORD_WOOD:
				worn_ok = worn_ok and it[2] == 2       # 10 * %20
			if it[0] == Items.POTION_DEFENSE:
				worn_ok = worn_ok and it[2] == -1
	ok(saw_shield and worn_ok, "iskelet: %30 saglam kalkan (5/15), %20 saglam kilic (2/10)")
	var crowns := 0
	var two_potions := true
	for i in 20000:
		for it: Array in Loot.roll("golem"):
			if it[0] == Items.CROWN:
				crowns += 1
			if it[0] == Items.POTION_DEFENSE:
				two_potions = two_potions and it[1] == 2
	ok(crowns > 20 and crowns < 400 and two_potions, "golem: kral taci nadir (%d / 20000), savunma iksiri 2'li" % crowns)
	print("SONUC: %d hata" % _fail)
	quit(1 if _fail > 0 else 0)
