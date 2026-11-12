extends Node
## Geliştirme aracı: oyunu sabit bir tohumla açar, birkaç eylem yapar ve ekran görüntüsü kaydeder.
## Kullanım: godot --path . res://tests/shot.tscn -- --out=C:/klasor [--touch]

var _out := "user://"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if "--menu" in OS.get_cmdline_user_args():
		add_child(load("res://scenes/main_menu.tscn").instantiate())
		await get_tree().create_timer(4.0).timeout
		await _shot("0_menu")
		get_tree().quit()
		return
	Session.mode = "solo"
	Session.world_seed = 12345
	Session.world_edits = {}
	Session.saved_pos = null
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(7.0).timeout
	if "--ao" in OS.get_cmdline_user_args():
		game.sky_time_override = 0.25
		var pl: Player = game.player
		await _shot("g1_view")
		pl.pitch = -0.9
		await get_tree().create_timer(0.3).timeout
		await _shot("g1_down")
		# Chunk köşesine (0,0) çukur ve sütun: çapraz komşuda gölge ve yeniden mesh sınaması
		var gy: int = game.world.gen.height_at(0, 0)
		pl.teleport(Vector3(2.5, gy + 2.0, 2.5))
		pl.yaw = PI * 0.25
		pl.pitch = -0.55
		game.world.set_block(Vector3i(0, gy + 1, 0), Blocks.STONE)
		game.world.set_block(Vector3i(0, gy + 2, 0), Blocks.STONE)
		game.world.set_block(Vector3i(-2, gy, -2), Blocks.AIR)
		await get_tree().create_timer(2.0).timeout
		await _shot("g1_corner")
		var t0 := Time.get_ticks_usec()
		var nb := []
		for o: Vector2i in World.NEIGHBORS:
			nb.append(game.world._chunks[o].data)
		for i in 10:
			ChunkMesher.build(game.world._chunks[Vector2i.ZERO].data, nb)
		print("mesh ms/chunk=", (Time.get_ticks_usec() - t0) / 10000.0)
		get_tree().quit()
		return
	if "--gfx" in OS.get_cmdline_user_args():
		for q in [0, 2, 1]:
			Session.set_quality(q)
			await get_tree().create_timer(5.0).timeout
			var meshed := 0
			for ch in game.world._chunks.values():
				if ch.node != null:
					meshed += 1
			print("quality=", q, " rd=", game.world.render_distance, " meshed=", meshed, " msaa=", get_viewport().msaa_3d, " fog_end=", game._env.fog_depth_end)
			await _shot("g0_quality_%d" % q)
		game.toggle_pause()
		await get_tree().create_timer(0.3).timeout
		await _shot("g0_pause")
		get_tree().quit()
		return
	var player: Player = game.player
	print("pos=", player.position, " ground=", player.on_ground, " chunks=", game.world._chunks.size())
	await _shot("1_first_person")

	# Aşağı bak ve çimi elle kır: yarısında çatlak + kol görüntüsü al
	player.pitch = -0.6
	await get_tree().create_timer(0.3).timeout
	var c: Vector2 = game.hud.size * 0.5
	var before: Dictionary = game._target(c)
	for i in 30:
		game.mine_at(c, 1.0 / 60.0)
		await get_tree().process_frame
	game.mine_at(c, 0.0)
	await _shot("1b_cracking")
	for i in 60:
		game.mine_at(c, 1.0 / 60.0)
		await get_tree().process_frame
	var after: Dictionary = game._target(c)
	print("break: ", before.get("pos"), " -> ", after.get("pos"), " drops=", game._drops.size())
	await _shot("1c_drop")
	await get_tree().create_timer(2.5).timeout
	print("after pickup: slot0=", game.inv.id_at(0), "x", game.inv.counts[0], " drops=", game._drops.size())

	# Tarif denemeleri
	var P := Blocks.PLANKS
	var S := Items.STICK
	print("recipe planks: ", Recipes.find([Blocks.LOG, 0, 0, 0, 0, 0, 0, 0, 0], 3).get("out"))
	print("recipe sticks (shifted): ", Recipes.find([0, 0, 0, 0, 0, P, 0, 0, P], 3).get("out"))
	print("recipe wood pick: ", Recipes.find([P, P, P, 0, S, 0, 0, S, 0], 3).get("out"), " want ", Items.tool(0, 0))
	print("recipe axe mirrored: ", Recipes.find([P, P, 0, S, P, 0, S, 0, 0], 3).get("out"), " want ", Items.tool(0, 1))
	print("recipe none: ", Recipes.find([P, 0, 0, 0, S, 0, 0, 0, 0], 3))
	print("stone by hand: ", Items.mine_time(Blocks.STONE, 0), " harvest=", Items.can_harvest(Blocks.STONE, 0),
		" | wood pick: ", Items.mine_time(Blocks.STONE, Items.tool(0, 0)), " harvest=", Items.can_harvest(Blocks.STONE, Items.tool(0, 0)),
		" | iron ore w/ wood pick harvest=", Items.can_harvest(Blocks.IRON_ORE, Items.tool(0, 0)),
		" stone pick=", Items.can_harvest(Blocks.IRON_ORE, Items.tool(1, 0)))

	# Envanteri doldur, blok yerleştir, ekranları görüntüle
	game.inv.clear()   # kırılan toprak toplanmış olabilir: yuva sırası sabit kalsın
	game.inv.add(Blocks.LOG, 5)
	game.inv.add(Blocks.COBBLE, 20)
	game.inv.add(Items.COAL, 7)
	game.inv.add(Blocks.IRON_ORE, 3)
	game.inv.add(Blocks.CRAFTING_TABLE, 1)
	game.inv.add(Blocks.FURNACE, 1)
	game.inv.add(Blocks.TORCH, 4)
	for tier in 5:
		for type in 3:
			game.inv.add(Items.tool(tier, type), 1)
	game.inv.add(Items.STICK, 9)
	game.inv.add(Items.IRON_INGOT, 2)
	game.inv.add(Items.GOLD_INGOT, 2)
	game.inv.add(Items.DIAMOND, 2)
	game.inv.add(Blocks.COAL_ORE, 1)
	game.inv.add(Blocks.GOLD_ORE, 1)
	game.inv.add(Blocks.DIAMOND_ORE, 1)
	game.select_slot(4)   # çalışma masası
	game.place_at(c + Vector2(170, 0))
	game.select_slot(5)   # fırın
	game.place_at(c + Vector2(-170, 0))
	game.select_slot(6)   # meşale
	game.place_at(c + Vector2(0, 150))
	game.select_slot(7)   # tahta kazma
	print("edits after place=", game.world.export_edits())
	await get_tree().create_timer(1.0).timeout
	await _shot("2_edited")
	game.select_slot(8)
	await get_tree().create_timer(0.2).timeout
	await _shot("2b_tool")
	game.select_slot(7)
	await get_tree().create_timer(0.2).timeout
	await _shot("2c_pick")
	game.select_slot(0)
	await get_tree().create_timer(0.2).timeout
	await _shot("2d_block")
	game.select_slot(7)
	for i in 14:
		game.mine_at(c + Vector2(0, -60), 1.0 / 60.0)
		await get_tree().process_frame
	game.mine_at(c + Vector2(0, -60), 0.0)
	await _shot("2e_swing")

	# Çalışma masasına dokun -> 3x3 crafting; kazma tarifini diz
	game.place_at(c + Vector2(170, 0))
	print("ui open=", game.ui.visible, " mode=", game.ui.mode, " target=", game._target(c + Vector2(170, 0)), " / ", game._target(c + Vector2(-170, 0)), " paused=", game.paused)
	# 20 kırık taşı üç hücreye böl: tamamını koy, geri al, "basılı tut" ile yarıla
	game.ui.press("inv", 1)
	game.ui.press("grid", 0)
	game.ui.press("grid", 0)
	game.ui.halve_held("grid", 0)
	game.ui.press("grid", 1)
	game.ui.press("grid", 1)
	game.ui.halve_held("grid", 1)
	game.ui.press("grid", 2)
	print("grid cobble counts=", game.ui._grid_counts[0], ",", game.ui._grid_counts[1], ",", game.ui._grid_counts[2], " hand=", game.ui._cur_n)
	var stick_slot := -1
	for i in Inventory.SIZE:
		if game.inv.id_at(i) == Items.STICK:
			stick_slot = i
	game.ui.press("inv", stick_slot)
	game.ui.press("grid", 4)
	game.ui.press("grid", 4)
	game.ui.halve_held("grid", 4)
	game.ui.press("grid", 7)
	game.ui.press("inv", 30)
	# Dayanıklılık: yıpranmış kılıç ve kalkanı yuvalar arasında taşı, değer korunmalı
	game.inv.set_slot(33, Items.SWORD_IRON, 1, 6)
	game.inv.set_slot(34, Items.SHIELD_DIAMOND, 1, 30)
	game.ui.press("inv", 33)
	game.ui.press("inv", 34)
	game.ui.press("inv", 35)
	print("dur swap: slot34=", game.inv.id_at(34), "/", game.inv.dur_at(34), " slot35=", game.inv.id_at(35), "/", game.inv.dur_at(35), " hand=", game.ui._cur_n)
	game.ui._layout()
	game.ui._pointer = game.ui._slots[40]["r"].get_center()
	await get_tree().create_timer(0.3).timeout
	await _shot("4_crafting")
	game.ui.press("result", 0)
	print("crafted hint=", game.ui._hint)
	game.ui.close()

	# Fırın: demir cevheri + kömür
	game.place_at(c + Vector2(-170, 0))
	print("ui open=", game.ui.visible, " mode=", game.ui.mode, " target=", game._target(c + Vector2(170, 0)), " / ", game._target(c + Vector2(-170, 0)), " paused=", game.paused)
	game.ui.press("inv", 3)
	game.ui.press("f", 0)
	game.ui.press("inv", 2)
	game.ui.press("f", 1)
	await get_tree().create_timer(2.6).timeout
	await _shot("5_furnace")
	print("furnace out=", game.ui._f_ids[2], "x", game.ui._f_counts[2])
	game.ui.close()

	player.pitch = -0.25
	player.toggle_view()
	player.move_input = Vector2(0, 1)
	await get_tree().create_timer(2.0).timeout
	player.move_input = Vector2.ZERO
	print("walked to=", player.position, " ground=", player.on_ground, " dirt picked=", game.inv.to_array().slice(0, 4), " drops=", game._drops.size())
	await _shot("3_third_person")
	player.toggle_view()

	# Dövüş: kılıç tarifi, tavuğa saldırı, XP
	print("recipe wood sword: ", Recipes.find([P, 0, 0, P, 0, 0, S, 0, 0], 3).get("out"), " want ", Items.SWORD_WOOD,
		" | diamond: ", Recipes.find([0, Items.DIAMOND, 0, 0, Items.DIAMOND, 0, 0, S, 0], 3).get("out"), " want ", Items.SWORD_DIAMOND)
	for i in 6:
		game.inv.set_slot(9 + i, Items.SWORD_WOOD + i, 1)
	game.inv.set_slot(0, Items.SWORD_WOOD, 1)
	game.select_slot(0)
	player.pitch = -0.3
	var fwd := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var hen: Mob = game.spawn_mob("chicken", player.position + fwd * 2.3 + Vector3(0, 0.3, 0))
	hen.ai_enabled = false
	await get_tree().create_timer(0.8).timeout
	print("mob under crosshair=", game._mob_at(c) == hen, " hen pos=", hen.position, " mobs=", game.mobs.size())
	var xp0: int = game.stats.xp
	game.try_attack(c)
	await get_tree().create_timer(0.15).timeout
	await _shot("10_attack")
	var swings := 1
	while is_instance_valid(hen) and not hen.dead and swings < 40:
		game._attack_cd = 0.0
		game.attack_mob(hen)
		swings += 1
		await get_tree().process_frame
	print("chicken dead after swings=", swings, " xp gained=", game.stats.xp - xp0, " sword left=", game.inv.id_at(0), "/", game.inv.dur_at(0))
	game.inv.set_slot(0, Items.SWORD_DIAMOND, 1)
	var hen2: Mob = game.spawn_mob("chicken", player.position + fwd * 2.3 + Vector3(0, 0.3, 0))
	hen2.ai_enabled = false
	game._attack_cd = 0.0
	game.attack_mob(hen2)
	print("diamond sword at level 0: hen2 hp=", hen2.hp, " toast=", game.toast_text, " dur=", game.inv.dur_at(0))
	hen2.ai_enabled = true
	game.open_ui(InventoryUI.MODE_INVENTORY)
	await get_tree().create_timer(0.3).timeout
	await _shot("11_swords")
	game.ui.close()
	await get_tree().create_timer(2.0).timeout
	print("mobs alive=", game.mobs.size(), " hen2 moved to ", hen2.position if is_instance_valid(hen2) else "freed")
	await _shot("12_mobs")
	# Pasif mobların modelleri: yan yana diz ve yandan bak
	var right := Vector3(cos(player.yaw), 0, -sin(player.yaw))
	var line: Array[Mob] = []
	var kinds := ["chicken", "pig", "sheep", "cow"]
	for i in kinds.size():
		var mm: Mob = game.spawn_mob(kinds[i], player.position + fwd * 3.6 + right * (i - 1.5) * 1.5 + Vector3(0, 0.3, 0))
		mm.ai_enabled = false
		mm.yaw = player.yaw + 2.2
		line.append(mm)
	await get_tree().create_timer(1.0).timeout
	await _shot("13_passive_models")
	game.inv.set_slot(0, Items.SWORD_WOOD, 1)
	var pig := line[1]
	game._attack_cd = 0.0
	game.attack_mob(pig)
	game._attack_cd = 0.0
	game.attack_mob(pig)
	pig.ai_enabled = true
	var d0 := pig.position.distance_to(player.position)
	await get_tree().create_timer(2.0).timeout
	print("pig hp=", pig.hp, " state=", pig._state, " fled from ", d0, " to ", pig.position.distance_to(player.position), " passive count=", game.count_mobs("passive"))
	for mm in line:
		mm.queue_free()
	await get_tree().process_frame

	# Yarı pasif ve aktif modeller
	var hostile: Array[Mob] = []
	var kinds2 := ["wolf", "bee", "angry_villager", "wizard_villager", "zombie", "skeleton", "creeper"]
	for i in kinds2.size():
		var mm: Mob = game.spawn_mob(kinds2[i], player.position + fwd * 4.5 + right * (i - 3.0) * 1.15 + Vector3(0, 0.3, 0))
		mm.ai_enabled = false
		mm.yaw = player.yaw + 2.6
		hostile.append(mm)
	player.pitch = -0.12
	await get_tree().create_timer(1.0).timeout
	await _shot("14_hostile_models")
	for mm in hostile:
		mm.queue_free()
	await get_tree().process_frame

	# Kurt: vurulmadan saldırmaz; vurulunca kovalar ve hasar verir
	var wolf: Mob = game.spawn_mob("wolf", player.position + fwd * 3.0 + Vector3(0, 0.3, 0))
	await get_tree().create_timer(2.5).timeout
	print("wolf untouched: aggro=", wolf.aggro, " player hp=", game.stats.hp)
	game._attack_cd = 0.0
	game.attack_mob(wolf)
	await get_tree().create_timer(3.0).timeout
	print("wolf after hit: aggro=", wolf.aggro, " wolf hp=", wolf.hp, " player hp=", game.stats.hp, " dist=", wolf.position.distance_to(player.position))
	wolf.queue_free()
	game.stats.hp = 30.0
	# Zombi: yakına girince kendiliğinden saldırır
	var zed: Mob = game.spawn_mob("zombie", player.position + fwd * 6.0 + Vector3(0, 0.3, 0))
	for step in 6:
		await get_tree().create_timer(0.5).timeout
		print("  zed t=", (step + 1) * 0.5, " pos=", zed.position, " vel=", zed.vel, " ground=", zed.on_ground, " player=", player.position)
	print("zombie: aggro=", zed.aggro, " player hp=", game.stats.hp, " dist=", zed.position.distance_to(player.position))
	await _shot("15_zombie_attack")
	# Takip mesafesi: oyuncu uzaklaşınca bırakır
	zed.position += fwd * 40.0
	await get_tree().create_timer(0.3).timeout
	print("zombie far away: aggro=", zed.aggro)
	zed.queue_free()
	game.stats.hp = 30.0
	await get_tree().process_frame

	# Boss'lar: model, vurulmadan saldırmama, can çubuğu, XP
	var golem: Mob = game.spawn_mob("golem", player.position + fwd * 6.0 + right * -2.2 + Vector3(0, 0.3, 0))
	var spider: Mob = game.spawn_mob("giant_spider", player.position + fwd * 6.0 + right * 2.2 + Vector3(0, 0.3, 0))
	golem.ai_enabled = false
	spider.ai_enabled = false
	golem.yaw = player.yaw + 2.7
	spider.yaw = player.yaw + 2.5
	player.pitch = -0.05
	await get_tree().create_timer(1.0).timeout
	print("boss untouched: golem aggro=", golem.aggro, " shown=", game.boss_shown() != null, " count=", game.count_mobs("boss"))
	game.inv.set_slot(0, Items.SWORD_WOOD, 1)
	game.select_slot(0)
	for i in 6:
		game._attack_cd = 0.0
		game.attack_mob(spider)
	await get_tree().create_timer(0.2).timeout
	print("spider hit: aggro=", spider.aggro, " hp=", spider.hp, "/", spider.max_hp, " shown=", game.boss_shown() == spider)
	await _shot("20_bosses")
	var lvl0: int = game.stats.level
	spider.hp = 1.0
	while is_instance_valid(spider) and not spider.dead:
		game._attack_cd = 0.0
		game.inv.set_slot(0, Items.SWORD_WOOD, 1)
		game.attack_mob(spider)
	await get_tree().process_frame
	print("spider killed: level ", lvl0, " -> ", game.stats.level, " xp=", game.stats.xp, " chests=", game.chests.size(), " shown=", game.boss_shown() != null)
	golem.queue_free()
	for ch in game.chests:
		ch.queue_free()
	await get_tree().process_frame

	# Ganimet sandığı: içerik, toplama, süre dolunca yok olma, simgeler
	var chest: LootChest = game.spawn_chest(player.position + fwd * 2.5 + Vector3(0, 1.0, 0),
		[[Items.MEAT_CHICKEN, 1, -1], [Items.STICK, 2, -1], [Items.SHIELD_WOOD, 1, 5]])
	var far_chest: LootChest = game.spawn_chest(player.position + fwd * 5.0 + right * 2.0 + Vector3(0, 1.0, 0), [[Items.CROWN, 1, -1]])
	print("empty roll makes no chest: ", game.spawn_chest(player.position, []) == null)
	player.pitch = -0.35
	await get_tree().create_timer(1.2).timeout
	await _shot("16_chest")
	game.inv.clear()
	chest.position = player.position
	await get_tree().create_timer(0.5).timeout
	print("no auto pickup: chest alive=", is_instance_valid(chest), " inv empty=", game.inv.id_at(0) == 0)
	game.open_chest(chest)
	await get_tree().create_timer(0.3).timeout
	await _shot("16b_chest_ui")
	game.ui.press("chest", 1)
	print("took sticks only: slot0=", game.inv.id_at(0), "x", game.inv.counts[0], " chest left=", chest.items.size(), " ui open=", game.ui.visible, " held=", chest.held)
	game.ui.take_all()
	await get_tree().create_timer(0.3).timeout
	print("after take all: ui open=", game.ui.visible)
	print("chest collected: freed=", not is_instance_valid(chest), " toast=", game.toast_text, " slot0=", game.inv.id_at(0), " slot1=", game.inv.id_at(1), "x", game.inv.counts[1],
		" shield=", game.inv.id_at(2), "/", game.inv.dur_at(2))
	await get_tree().create_timer(9.0).timeout
	print("far chest after 10.5 s: gone=", not is_instance_valid(far_chest) or far_chest.expired, " chests=", game.chests.size())
	game.inv.clear()
	var slot := 0
	for id: int in Items.DEFS.keys():
		game.inv.set_slot(slot, id, 1)
		slot += 1
	game.open_ui(InventoryUI.MODE_INVENTORY)
	game.ui.left_tab = InventoryUI.LEFT_ITEMS
	await get_tree().create_timer(0.3).timeout
	await _shot("17_icons")
	game.ui.close()
	game.inv.clear()
	game.inv.set_slot(0, Items.SWORD_WOOD, 1)
	game.select_slot(0)

	# Ekipman: tak, yanlış yuvayı reddet, can bonusu, darbe alınca yıpranma
	game.inv.set_slot(9, Items.HELMET, 1)
	game.inv.set_slot(10, Items.CHESTPLATE, 1)
	game.inv.set_slot(11, Items.LEGGINGS, 1)
	game.inv.set_slot(12, Items.SHIELD_WOOD, 1, 2)
	game.inv.set_slot(13, Items.SHIELD_IRON, 1)
	game.open_ui(InventoryUI.MODE_INVENTORY)
	game.ui.left_tab = InventoryUI.LEFT_ITEMS
	game.ui.right_tab = InventoryUI.RIGHT_EQUIP
	game.ui.press("inv", 0)
	game.ui.press("eq", 0)
	print("sword into helmet slot: eq0=", game.inv.id_at(Inventory.SIZE), " hint=", game.ui._hint)
	game.ui.press("inv", 0)
	for i in 4:
		game.ui.press("inv", 9 + i)
		game.ui.press("eq", i)
	await get_tree().create_timer(0.3).timeout
	print("equipped: ", game.inv.id_at(Inventory.SIZE), ",", game.inv.id_at(Inventory.SIZE + 1), ",", game.inv.id_at(Inventory.SIZE + 2), ",", game.inv.id_at(Inventory.SIZE + 3),
		" max_hp=", game.stats.max_hp(), " hand=", game.ui._cur_n)
	await _shot("18_equipment")
	game.ui.close()
	game.stats.hp = float(game.stats.max_hp())
	game._on_mob_hit(7.0)
	game._on_mob_hit(7.0)
	await get_tree().process_frame
	print("after 2 hits: hp=", game.stats.hp, "/", game.stats.max_hp(), " helmet dur=", game.inv.dur_at(Inventory.SIZE), " shield=", game.inv.id_at(Inventory.SIZE + 3), " toast=", game.toast_text)
	game.hurt(3.0)
	print("fall damage does not wear armor: helmet dur=", game.inv.dur_at(Inventory.SIZE))
	game.stats.hp = float(game.stats.max_hp())

	# İksirler ve totem
	game.inv.clear()
	game.inv.set_slot(0, Items.POTION_ATTACK, 2)
	game.inv.set_slot(1, Items.POTION_DEFENSE, 1)
	game.inv.set_slot(2, Items.POTION_SPEED, 1)
	game.inv.set_slot(3, Items.POTION_INT, 1)
	var dmg0: int = game.stats.hit_damage()
	for i in 4:
		game.select_slot(i)
		game._use_item()
	game.select_slot(0)
	game._use_item()
	await get_tree().create_timer(0.5).timeout
	print("potions: damage ", dmg0, " -> ", game.stats.hit_damage(), " max_hp=", game.stats.max_hp(), " speed_mult=", player.speed_mult, " crit=", game.stats.crit_chance(),
		" attack potions left=", game.inv.counts[0], " buffs=", game.stats.buffs.size(), " toast=", game.toast_text)
	await _shot("19_potions")
	game.stats.tick(301.0)
	print("after 5 min: damage=", game.stats.hit_damage(), " max_hp=", game.stats.max_hp(), " buffs=", game.stats.buffs.size())
	game.inv.set_slot(20, Items.TOTEM, 1)
	game.inv.set_slot(5, Blocks.COBBLE, 9)
	game.stats.add_xp(40)
	game.hurt(999)
	await get_tree().process_frame
	print("totem: hp=", game.stats.hp, "/", game.stats.max_hp(), " totem left=", game.inv.find(Items.TOTEM), " cobble kept=", game.inv.counts[5], " xp kept=", game.stats.xp, " death_timer=", game.death_timer, " toast=", game.toast_text)
	game.inv.clear()
	game.inv.set_slot(0, Items.SWORD_WOOD, 1)
	game.select_slot(0)

	# Karakter ekranı: XP kazan, level atla, puan dağıt
	game.add_xp(250)
	game.open_stats()
	game.stats_ui.add_point(0)
	game.stats_ui.add_point(3)
	await get_tree().create_timer(0.3).timeout
	print("stats ui open=", game.stats_ui.visible, " level=", game.stats.level, " points=", game.stats.points, " max_hp=", game.stats.max_hp(), " toast=", game.toast_text)
	await _shot("8_stats")
	game.stats_ui.close()
	await get_tree().create_timer(0.3).timeout
	await _shot("9_hud_level")

	# Can: hasar al, et ye, sonra öl
	game.hurt(22)
	game.inv.set_slot(0, Items.MEAT_BEEF, 3)
	game.select_slot(0)
	game.place_at(c)
	await get_tree().create_timer(1.5).timeout
	print("hp after hurt 22 + 1.5s eating=", game.stats.hp, " meat left=", game.inv.counts[0], " heal_left=", game.stats.heal_left())
	await _shot("6_health")
	game.hurt(999)
	await get_tree().create_timer(1.0).timeout
	var items := 0
	for i in Inventory.SIZE:
		items += game.inv.counts[i]
	print("after death: items=", items, " hp=", game.stats.hp, "/", game.stats.max_hp(), " level=", game.stats.level, " xp=", game.stats.xp, " points=", game.stats.points, " pos=", player.position)
	await _shot("7_death")
	# Düşme hasarı: 10 blok yukarıdan bırak (3 blok güvenli, sonrası blok başına 2 can)
	await get_tree().create_timer(3.5).timeout
	var y0 := player.position.y
	player.position.y += 10.0
	await get_tree().create_timer(2.5).timeout
	print("fall 10 blocks: y ", y0, " -> ", player.position.y, " hp=", game.stats.hp, " (beklenen 16)")
	player.jump_held = true
	await get_tree().create_timer(1.5).timeout
	player.jump_held = false
	print("after jumping: hp=", game.stats.hp)

	# Level sınırı: taş kılıç level 0'da üretilemez
	game.inv.clear()
	game.inv.set_slot(0, Blocks.COBBLE, 2)
	game.inv.set_slot(1, Items.STICK, 1)
	game.open_ui(InventoryUI.MODE_TABLE)
	game.ui.press("inv", 0)
	game.ui.press("grid", 1, true)
	game.ui.press("grid", 4)
	game.ui.press("inv", 1)
	game.ui.press("grid", 7)
	game.ui.press("result", 0)
	print("stone sword at level ", game.stats.level, ": crafted=", game.inv.find(Items.SWORD_STONE) >= 0, " hint=", game.ui._hint)
	game.ui.close()

	# Tarif listesi: hızlı üretim
	game.inv.clear()
	game.inv.set_slot(0, Blocks.LOG, 3)
	game.open_ui(InventoryUI.MODE_INVENTORY)
	await get_tree().create_timer(0.2).timeout
	var rs: Array = game.ui._shown_recipes()
	print("recipes shown (2x2)=", rs.size(), " planks craftable=", game.ui.can_quick_craft(rs[0]), " table craftable=", game.ui.can_quick_craft(rs[2]))
	game.ui.press("recipe", 0)
	game.ui.press("recipe", 0)
	game.ui.press("recipe", 2)
	game.ui.press("recipe", 1)
	game.ui.press("recipe", 3)
	print("quick craft: logs=", game.inv.count(Blocks.LOG), " planks=", game.inv.count(Blocks.PLANKS), " table=", game.inv.count(Blocks.CRAFTING_TABLE), " sticks=", game.inv.count(Items.STICK), " hint=", game.ui._hint)
	await get_tree().create_timer(0.3).timeout
	await _shot("21_recipes")
	game.ui.close()
	game.inv.add(Blocks.COBBLE, 12)
	game.inv.add(Items.COAL, 2)
	game.open_ui(InventoryUI.MODE_TABLE)
	await get_tree().create_timer(0.3).timeout
	print("recipes shown (3x3)=", game.ui._shown_recipes().size())
	await _shot("22_table_recipes")
	game.ui.left_tab = InventoryUI.LEFT_ITEMS
	game.ui.press("inv", 0)
	game.ui.press("grid", 4)
	await get_tree().create_timer(0.3).timeout
	await _shot("23_table_items")
	game.ui.close()

	# Su: kıyı bloğu kırılınca suyla dolar; su yüzeyi 1 blok aşağıdayken karaya çıkılabilir
	await get_tree().create_timer(4.0).timeout
	var bx := floori(player.position.x)
	var bz := floori(player.position.z) - 3
	var gy := floori(player.position.y) - 1
	for dz in [0, -1]:
		game.world.set_block(Vector3i(bx, gy, bz + dz), Blocks.AIR)
		game.world.set_block(Vector3i(bx, gy + 1, bz + dz), Blocks.AIR)
		game.world.set_block(Vector3i(bx, gy + 2, bz + dz), Blocks.AIR)
	game.world.set_block(Vector3i(bx, gy - 1, bz), Blocks.WATER)
	game.world.set_block(Vector3i(bx, gy - 2, bz), Blocks.STONE)
	game.world.set_block(Vector3i(bx, gy - 1, bz - 1), Blocks.STONE)
	game.world.set_block(Vector3i(bx, gy, bz - 1), Blocks.STONE)
	game._break(Vector3i(bx, gy - 1, bz - 1), Blocks.STONE)
	print("broken block next to water became: ", game.world.get_block(bx, gy - 1, bz - 1), " (su=", Blocks.WATER, ")")
	game.world.set_block(Vector3i(bx, gy - 1, bz - 1), Blocks.STONE)
	player.yaw = 0.0
	player.teleport(Vector3(bx + 0.5, gy - 0.9, bz + 0.5))
	await get_tree().create_timer(0.8).timeout
	print("in pool: pos=", player.position, " in_water=", player.in_water, " shore top y=", gy + 1)
	player.move_input = Vector2(0, 1)
	await get_tree().create_timer(2.5).timeout
	player.move_input = Vector2.ZERO
	print("climbed out of water: pos=", player.position, " in_water=", player.in_water, " ok=", player.position.y >= gy + 0.99 and player.position.z < bz - 0.2)
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
