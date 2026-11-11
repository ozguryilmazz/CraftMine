extends SceneTree
## Geliştirme aracı: eşya tablosu ve envanter dayanıklılığı için otomatik test.
## Kullanım: godot --headless --path . -s res://tests/items_test.gd

var _fail := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		_fail += 1
	print(("PASS  " if cond else "FAIL  ") + what)


func _init() -> void:
	var inv := Inventory.new()
	ok(Items.max_stack(Items.SWORD_IRON) == 1 and Items.max_durability(Items.SWORD_IRON) == 20, "demir kilic: yigin 1, dayaniklilik 20")
	ok(Items.max_stack(Blocks.COBBLE) == 64 and Items.max_durability(Blocks.COBBLE) == 0, "kirik tas: yigin 64, dayaniklilik yok")
	ok(Items.max_stack(Items.tool(0, 0)) == 1, "kazma hala tekli")
	ok(Items.item_name(Items.SWORD_NETHER) == "Nether Kılıç" and Items.item_name(Items.STICK) == "Çubuk", "adlar")
	ok(int(Items.prop(Items.SWORD_DIAMOND, "dmg")) == 15 and int(Items.prop(Items.SHIELD_IRON, "hp")) == 8, "hasar / can degerleri")
	ok(Items.price(Items.CROWN) == 0, "fiyat alani okunuyor")

	ok(inv.add(Items.SWORD_WOOD, 2) == 0, "iki kilic eklendi")
	ok(inv.id_at(0) == Items.SWORD_WOOD and inv.id_at(1) == Items.SWORD_WOOD and inv.counts[0] == 1, "kiliclar ayri yuvalarda")
	ok(inv.dur_at(0) == 10, "yeni kilic tam dayaniklilikta")
	inv.add(Items.SHIELD_WOOD, 1, 4)
	ok(inv.dur_at(2) == 4, "yipranmis kalkan (4/15) eklendi")
	inv.add(Blocks.COBBLE, 70)
	ok(inv.counts[3] == 64 and inv.counts[4] == 6 and inv.durs[3] == 0, "bloklar yiginlaniyor")
	for i in 9:
		ok(not inv.wear(0), "kilic vurus %d: kirilmadi (kalan %d)" % [i + 1, inv.dur_at(0)])
	ok(inv.wear(0) and inv.id_at(0) == 0, "10. vurusta kilic kirildi ve yok oldu")
	ok(not inv.wear(3), "blok yipranmaz")

	var saved := inv.to_array()
	var inv2 := Inventory.new()
	inv2.from_array(saved)
	ok(inv2.to_array() == saved and inv2.dur_at(2) == 4, "kayit / yukleme ayni sonucu veriyor")
	var old := []
	for i in Inventory.SIZE:
		old.append(Items.tool(1, 0) if i == 0 else (Blocks.LOG if i == 1 else 0))
		old.append(1 if i == 0 else (12 if i == 1 else 0))
	var inv3 := Inventory.new()
	inv3.from_array(old)
	ok(inv3.id_at(0) == Items.tool(1, 0) and inv3.counts[1] == 12 and inv3.id_at(2) == 0, "eski (1.3.x) kayit bicimi okunuyor")
	# Ekipman yuvaları
	var e := Inventory.new()
	ok(Inventory.fits_equip(0, Items.HELMET) and not Inventory.fits_equip(0, Items.CHESTPLATE) and Inventory.fits_equip(3, Items.SHIELD_DIAMOND)
		and not Inventory.fits_equip(3, Items.SWORD_IRON), "ekipman yuvalari yalnizca kendi turunu kabul ediyor")
	e.set_slot(Inventory.SIZE + 0, Items.HELMET, 1)
	e.set_slot(Inventory.SIZE + 1, Items.CHESTPLATE, 1)
	e.set_slot(Inventory.SIZE + 2, Items.LEGGINGS, 1)
	e.set_slot(Inventory.SIZE + 3, Items.SHIELD_DIAMOND, 1)
	ok(e.equip_hp() == 2 + 5 + 8 + 10, "tam takim can bonusu +25")
	for i in 9:
		e.wear_equipment()
	ok(e.dur_at(Inventory.SIZE) == 1 and e.dur_at(Inventory.SIZE + 3) == 26, "9 darbe: kafalik 1/10, elmas kalkan 26/35")
	var br := e.wear_equipment()
	ok(br == [Items.HELMET] and e.id_at(Inventory.SIZE) == 0 and e.equip_hp() == 23, "10. darbede kafalik kirildi, bonus 23")
	ok(e.add(Blocks.COBBLE, 64 * 36) == 0 and e.add(Blocks.COBBLE, 1) == 1 and e.id_at(Inventory.SIZE + 1) == Items.CHESTPLATE, "toplanan esyalar ekipman yuvalarina girmiyor")
	var e2 := Inventory.new()
	e2.from_array(e.to_array())
	ok(e2.to_array() == e.to_array() and e2.dur_at(Inventory.SIZE + 3) == 25, "ekipman kayit / yukleme")
	var v14 := []
	for i in Inventory.SIZE:
		v14.append_array([Items.SWORD_WOOD if i == 0 else 0, 1 if i == 0 else 0, 7 if i == 0 else 0])
	var e3 := Inventory.new()
	e3.from_array(v14)
	ok(e3.id_at(0) == Items.SWORD_WOOD and e3.dur_at(0) == 7 and e3.equip_hp() == 0, "1.4 - 1.9 kayit bicimi okunuyor")
	e.clear()
	ok(e.equip_hp() == 0 and e.id_at(Inventory.SIZE + 1) == 0, "clear() ekipmani da siliyor")
	inv.clear()
	var empty := true
	for i in Inventory.SIZE:
		empty = empty and inv.id_at(i) == 0
	ok(empty, "clear() envanteri bosaltiyor")
	print("SONUC: %d hata" % _fail)
	quit(1 if _fail > 0 else 0)
