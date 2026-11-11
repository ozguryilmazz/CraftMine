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
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
