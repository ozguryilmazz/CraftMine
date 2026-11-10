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

	# Aşağı bak, blok kır, meşale ve tahta koy
	player.pitch = -0.6
	await get_tree().create_timer(0.3).timeout
	var c: Vector2 = game.hud.size * 0.5
	var before: Dictionary = game._target(c)
	# Çim 0.6 sn'de kırılır: yarısında çatlak görüntüsü al, sonra bitir.
	for i in 24:
		game.mine_at(c, 1.0 / 60.0)
		await get_tree().process_frame
	print("mining progress=", game._mine_progress, " crack=", game._crack.visible)
	game.mine_at(c, 0.0)
	await _shot("1b_cracking")
	for i in 40:
		game.mine_at(c, 1.0 / 60.0)
		await get_tree().process_frame
	var after: Dictionary = game._target(c)
	print("break: ", before.get("pos"), " -> ", after.get("pos"), " edits=", game.world.export_edits().size())
	game.select_slot(3)
	game.place_at(c + Vector2(160, 0))
	game.select_slot(7)
	game.place_at(c + Vector2(-160, 0))
	print("edits after place=", game.world.export_edits())
	await get_tree().create_timer(1.0).timeout
	await _shot("2_edited")

	player.pitch = -0.25
	player.toggle_view()
	player.move_input = Vector2(0, 1)
	await get_tree().create_timer(2.0).timeout
	player.move_input = Vector2.ZERO
	print("walked to=", player.position, " ground=", player.on_ground)
	await _shot("3_third_person")
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
