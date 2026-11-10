extends Node3D
## Oyun sahnesi: dünyayı, oyuncuyu ve arayüzü kurar; blok kırma/yerleştirme ve çok oyunculu eşitlemeyi yönetir.

const REACH := 6.0
const DAY_LENGTH := 720.0        # saniye; saat cihaz saatinden türetildiği için tüm oyuncularda aynıdır
const REMOTE_TIMEOUT := 12.0
const MINE_STAGES := 8
const MINE_COOLDOWN := 0.2       # art arda kırmalar arasındaki bekleme
const MENU_SCENE := "res://scenes/main_menu.tscn"

var world: World
var player: Player
var hud: Hud
var selected := 0
var paused := false
var info_text := ""

var _env: Environment
var _sun: DirectionalLight3D
var _highlight: MeshInstance3D
var _remotes := {}             # uid -> PlayerModel
var _pause_panel: Control
var _pause_label: Label
var _resume_button: Button
var _room_closed := false
var _save_timer := 0.0
var _net_timer := 0.0
var _last_sent := []
var _keepalive := 0.0
var _online := false
var _crack: MeshInstance3D
var _crack_mat: StandardMaterial3D
var _crack_tex: Array[ImageTexture] = []
var _mine_pos: Variant = null
var _mine_progress := 0.0
var _mine_cooldown := 0.0
var _mine_requested := false


func _ready() -> void:
	_online = Session.mode != "solo"
	var mobile := OS.has_feature("mobile")
	_setup_environment()

	world = World.new()
	add_child(world)
	world.setup(Session.world_seed, 4 if mobile else 6)
	if Session.mode != "join":
		world.import_edits(Session.world_edits)
	world.block_changed.connect(_on_local_block)
	_env.fog_depth_begin = world.render_distance * 16.0 * 0.55
	_env.fog_depth_end = world.render_distance * 16.0 - 6.0

	player = Player.new()
	player.world = world
	player.auto_jump = Session.touch_mode
	add_child(player)
	if Session.mode != "join" and Session.saved_pos is Vector3:
		player.position = Session.saved_pos
	else:
		var a := randf() * TAU if _online else 0.0
		var sx := int(cos(a) * 3.0)
		var sz := int(sin(a) * 3.0)
		player.position = Vector3(sx + 0.5, maxi(world.gen.height_at(sx, sz), WorldGen.SEA) + 2.0, sz + 0.5)

	_highlight = _make_highlight()
	add_child(_highlight)
	_make_crack()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	hud.player = player
	hud.touch_mode = Session.touch_mode
	layer.add_child(hud)
	_build_pause_panel(layer)

	if _online:
		Net.player_update.connect(_on_player_update)
		Net.player_left.connect(_on_player_left)
		Net.block_update.connect(_on_net_block)
		Net.blocks_bulk.connect(_on_net_blocks)
		Net.room_closed.connect(_on_room_closed)
	if not Session.touch_mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_info()


func _setup_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color.WHITE
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_density = 1.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(_sun)


func _make_highlight() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var lo := -0.003
	var hi := 1.003
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for u in [lo, hi]:
			for v in [lo, hi]:
				var p0 := Vector3.ZERO
				var p1 := Vector3.ZERO
				p0[a] = lo; p1[a] = hi
				p0[b] = u; p1[b] = u
				p0[c] = v; p1[c] = v
				im.surface_add_vertex(p0)
				im.surface_add_vertex(p1)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.visible = false
	return mi


## Kırılmakta olan bloğun üzerine binen çatlak kaplaması.
func _make_crack() -> void:
	_crack_tex = Atlas.crack_textures(MINE_STAGES)
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_crack_mat.uv1_scale = Vector3(3, 2, 1)   # BoxMesh 3x2 yerleşimi: her yüze dokunun tamamı
	_crack_mat.albedo_texture = _crack_tex[0]
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.008
	box.material = _crack_mat
	_crack = MeshInstance3D.new()
	_crack.mesh = box
	_crack.visible = false
	add_child(_crack)


func _build_pause_panel(layer: CanvasLayer) -> void:
	_pause_panel = ColorRect.new()
	_pause_panel.color = Color(0, 0, 0, 0.55)
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	layer.add_child(_pause_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	_pause_label = Label.new()
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 34)
	box.add_child(_pause_label)
	var resume := Button.new()
	resume.text = "Devam Et"
	resume.custom_minimum_size = Vector2(360, 76)
	resume.pressed.connect(toggle_pause)
	_resume_button = resume
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Ana Menü"
	quit.custom_minimum_size = Vector2(360, 76)
	quit.pressed.connect(exit_to_menu)
	box.add_child(quit)


# ---------- Döngü ----------

func _process(delta: float) -> void:
	# HUD her karede mine_at çağırmadıysa (parmak/tuş bırakıldı) kırma sıfırlanır.
	if not _mine_requested:
		_mine_reset()
	_mine_requested = false
	_mine_cooldown = maxf(_mine_cooldown - delta, 0.0)
	_update_sky()
	_update_highlight()
	var now := Time.get_ticks_msec() / 1000.0
	for id: String in _remotes.keys():
		var m: PlayerModel = _remotes[id]
		if now - m.last_update > REMOTE_TIMEOUT:
			_on_player_left(id)
		else:
			m.follow(delta)
	if _online:
		_net_timer += delta
		_keepalive += delta
		if _net_timer >= 0.1:
			_net_timer = 0.0
			var p := player.position
			var cur := [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(player.yaw, 0.01), snappedf(player.pitch, 0.01)]
			if cur != _last_sent or _keepalive > 4.0:
				_last_sent = cur
				_keepalive = 0.0
				Net.send_pos(cur)
	if Session.mode != "join":
		_save_timer += delta
		if _save_timer > 20.0:
			_save()


func _update_sky() -> void:
	var t := fmod(Time.get_unix_time_from_system(), DAY_LENGTH) / DAY_LENGTH
	var day := smoothstep(0.0, 1.0, clampf(sin(t * TAU) * 2.5 + 1.25, 0.0, 1.0))
	var sky := Color(0.02, 0.03, 0.08).lerp(Color(0.52, 0.74, 0.96), day)
	_env.background_color = sky
	_env.fog_light_color = sky
	_env.ambient_light_energy = lerpf(0.12, 0.75, day)
	_sun.light_energy = lerpf(0.0, 0.55, day)


func _update_highlight() -> void:
	_highlight.visible = false
	if Session.touch_mode or paused:
		return
	var hit := world.raycast(player.camera.global_position, player.look_dir(), REACH + (4.0 if player.third_person else 0.0))
	if hit.is_empty():
		return
	_highlight.position = Vector3(hit["pos"])
	_highlight.visible = true


func _update_info() -> void:
	if _online:
		info_text = "Oda: %s   Oyuncu: %d" % [Session.room_code, _remotes.size() + 1]
	else:
		info_text = ""


# ---------- Blok etkileşimi ----------

## Ekran noktasından dünyaya ışın. [başlangıç, yön]
func screen_ray(p: Vector2) -> Array:
	var cam := player.camera
	var ndc := Vector2(p.x / hud.size.x * 2.0 - 1.0, 1.0 - p.y / hud.size.y * 2.0)
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var dir := (cam.global_basis * Vector3(ndc.x * t * hud.size.x / hud.size.y, ndc.y * t, -1.0)).normalized()
	return [cam.global_position, dir]


func _target(p: Vector2) -> Dictionary:
	var ray := screen_ray(p)
	var reach := REACH + (4.0 if player.third_person else 0.0)
	return world.raycast(ray[0], ray[1], reach)


## Basılı tutulduğu sürece her karede çağrılır: hedef bloğu sertliğine göre kademeli olarak kırar.
func mine_at(p: Vector2, delta: float) -> void:
	_mine_requested = true
	if _mine_cooldown > 0.0 or paused:
		return
	var hit := _target(p)
	if hit.is_empty():
		_mine_reset()
		return
	var pos: Vector3i = hit["pos"]
	var hardness: float = Blocks.HARDNESS[hit["id"]]
	if hardness < 0.0:
		_mine_reset()
		return
	if _mine_pos == null or _mine_pos != pos:
		_mine_pos = pos
		_mine_progress = 0.0
	_mine_progress += delta
	if _mine_progress >= hardness:
		_break(pos)
		_mine_reset()
		_mine_cooldown = MINE_COOLDOWN
		return
	var stage := clampi(int(_mine_progress / hardness * MINE_STAGES), 0, MINE_STAGES - 1)
	_crack_mat.albedo_texture = _crack_tex[stage]
	_crack.position = Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	_crack.visible = true


func _mine_reset() -> void:
	_mine_pos = null
	_mine_progress = 0.0
	if _crack != null:
		_crack.visible = false


func _break(pos: Vector3i) -> void:
	world.set_block(pos, Blocks.AIR)
	var above := pos + Vector3i(0, 1, 0)
	if world.get_block(above.x, above.y, above.z) == Blocks.TORCH:
		world.set_block(above, Blocks.AIR)   # dayanağı kalmayan meşale düşer


func place_at(p: Vector2) -> void:
	var hit := _target(p)
	if hit.is_empty() or hit["normal"] == Vector3i.ZERO:
		return
	var pos: Vector3i = hit["pos"] + hit["normal"]
	if pos.y < 1 or pos.y >= World.CH:
		return
	var existing := world.get_block(pos.x, pos.y, pos.z)
	if existing != Blocks.AIR and existing != Blocks.WATER:
		return
	var block: int = Blocks.HOTBAR[selected]
	if Blocks.is_solid(block) and player.intersects_block(pos):
		return
	world.set_block(pos, block)


func select_slot(i: int) -> void:
	selected = clampi(i, 0, Blocks.HOTBAR.size() - 1)


# ---------- Çok oyunculu ----------

func _on_local_block(pos: Vector3i, id: int) -> void:
	if _online:
		Net.send_block(pos, id)


func _on_net_block(pos: Vector3i, id: int) -> void:
	if id >= 0 and id < Blocks.COUNT:
		world.set_block(pos, id, true)


func _on_net_blocks(blocks: Dictionary) -> void:
	world.import_edits(blocks)


func _on_player_update(uid: String, pname: String, p: Variant) -> void:
	var m: PlayerModel = _remotes.get(uid)
	if m == null:
		m = PlayerModel.new(Color.from_hsv(fmod(absf(float(uid.hash())) / 1000.0, 1.0), 0.6, 0.8))
		_remotes[uid] = m
		add_child(m)
		if p is Array and p.size() >= 3:
			m.position = Vector3(p[0], p[1], p[2])
		_update_info()
	if pname != "":
		m.set_player_name(pname)
	if p is Array and p.size() >= 5:
		m.target_pos = Vector3(p[0], p[1], p[2])
		m.target_yaw = p[3]
		m.target_pitch = p[4]
		m.last_update = Time.get_ticks_msec() / 1000.0
	elif m.last_update == 0.0:
		m.last_update = Time.get_ticks_msec() / 1000.0


func _on_player_left(uid: String) -> void:
	var m: PlayerModel = _remotes.get(uid)
	if m != null:
		m.queue_free()
		_remotes.erase(uid)
		_update_info()


func _on_room_closed(reason: String) -> void:
	_online = false
	_room_closed = true
	paused = true
	player.controls_enabled = false
	hud.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_label.text = reason
	_pause_panel.visible = true
	_resume_button.visible = false


# ---------- Duraklatma / çıkış / kayıt ----------

func toggle_pause() -> void:
	paused = not paused
	hud.release_all()
	player.controls_enabled = not paused
	_pause_panel.visible = paused
	_pause_label.text = ("Oda Kodu: %s" % Session.room_code) if _online else "Oyun Duraklatıldı"
	if not Session.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _save() -> void:
	_save_timer = 0.0
	if Session.mode != "join":
		Session.save_world(world.export_edits(), player.position)


func exit_to_menu() -> void:
	_save()
	Net.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _room_closed:
			exit_to_menu()
		elif world != null:
			toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if world != null and player != null:
			_save()
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			Net.leave()
