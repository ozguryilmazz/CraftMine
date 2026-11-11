extends SceneTree
## Geliştirme aracı: stat, can, XP ve ölüm cezası kuralları için otomatik test.
## Kullanım: godot --headless --path . -s res://tests/stats_test.gd

var _fail := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		_fail += 1
	print(("PASS  " if cond else "FAIL  ") + what)


func _init() -> void:
	var s := PlayerStats.new()
	ok(s.max_hp() == 30 and s.hp == 30.0, "baslangic cani 30")
	ok(not s.damage(15) and s.damage(15), "zombi (15 hasar) tam 2 vurusta olduruyor")
	s.hp = 30.0
	ok(not s.damage(20) and s.damage(20), "creeper (20 hasar) 2 vurusta olduruyor")
	ok(is_equal_approx(s.miss_chance(), 0.2) and s.crit_chance() == 0.0 and s.hit_damage() == 1, "baslangic: %20 sekme, kritik yok, 1 hasar")
	ok(s.hit_damage(4) == 5, "tahta kilicla 5 hasar")

	s = PlayerStats.new()
	ok(s.add_xp(99) == 0 and s.level == 0, "99 XP: level 0")
	ok(s.add_xp(1) == 1 and s.level == 1 and s.xp == 0 and s.points == 3, "100 XP: level 1, 3 puan")
	ok(s.add_xp(120 + 130 + 140 + 200) == 4 and s.level == 5 and s.points == 3 + 3 + 3 + 3 + 5, "level 5: toplam 17 puan")
	ok(s.spend("health") and s.spend("health") and s.max_hp() == 34 and s.hp == 34.0, "2 saglik puani: 34 can")
	ok(s.spend("speed") and is_equal_approx(s.speed_mult(), 1.05), "1 hiz puani: %5 hiz")
	ok(s.spend("intel") and s.spend("intel") and is_equal_approx(s.crit_chance(), 0.04) and is_equal_approx(s.miss_chance(), 0.18), "2 zeka: %4 kritik, %18 sekme")
	ok(s.spend("attack") and s.hit_damage() == 2 and s.crit_bonus() == 1, "1 saldiri: 2 hasar, kritik +1")
	var pts := s.points
	s.die()
	ok(s.level == 0 and s.xp == 0, "olum: level ve XP sifir")
	ok(s.added["health"] == 1 and s.added["speed"] == 0 and s.added["intel"] == 1 and s.added["attack"] == 0, "olum: her stattan 1 puan dustu")
	ok(s.points == pts and s.hp == float(s.max_hp()) and s.max_hp() == 32, "olum: harcanmamis puan kaldi, can doldu")
	s.die()
	s.die()
	ok(s.added["health"] == 0 and s.added["speed"] == 0 and s.max_hp() == 30, "statlar tabanin altina inmiyor")
	s.add_xp(100 + 120 + 130 + 140 + 200)
	ok(s.level == 5 and s.points == pts, "ayni levellere tekrar cikinca puan verilmiyor")
	s.add_xp(220)
	ok(s.level == 6 and s.points == pts + 3, "ilk kez ulasilan level 6 puan veriyor")
	s.add_xp(100000)
	ok(s.level == 15 and s.xp == 0 and s.best_level == 15, "level 15 ust sinir")
	var total := 0
	for p: int in PlayerStats.POINTS:
		total += p
	ok(total == 51, "toplam kazanilabilir puan 51")

	s = PlayerStats.new()
	s.damage(25)
	s.eat(Items.MEAT_CHICKEN)
	s.tick(1.0)
	ok(is_equal_approx(s.hp, 7.0), "et: 1 saniyede +2 can")
	for i in 10:
		s.tick(1.0)
	ok(is_equal_approx(s.hp, 15.0) and s.heal_left() == 0.0, "et: toplam +10 can, sonra durur")
	s.add_buff("attack", 3, 300.0)
	ok(s.hit_damage() == 4, "saldiri iksiri: +3")
	s.add_buff("attack", 3, 300.0)
	ok(s.hit_damage() == 4, "ayni iksir ust uste binmiyor")
	s.tick(299.0)
	ok(s.hit_damage() == 4, "299. saniyede etki suruyor")
	s.tick(2.0)
	ok(s.hit_damage() == 1, "5 dakika sonra etki bitti")
	s.add_buff("health", 3, 300.0)
	ok(s.max_hp() == 36, "savunma iksiri: +6 can siniri")

	var s2 := PlayerStats.new()
	s.add_xp(150)
	s.spend("speed")
	s2.from_dict(s.to_dict())
	ok(s2.to_dict() == s.to_dict(), "kayit / yukleme ayni sonucu veriyor")
	print("SONUC: %d hata" % _fail)
	quit(1 if _fail > 0 else 0)
