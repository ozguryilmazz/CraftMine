extends Node3D
## Oyun sahnesi: dünyayı, oyuncuyu ve arayüzü kurar; blok kırma/yerleştirme, düşen eşyalar,
## envanter ve çok oyunculu eşitlemeyi yönetir.

const REACH := 6.0
const DAY_LENGTH := 720.0        # saniye; saat cihaz saatinden türetildiği için tüm oyuncularda aynıdır
const REMOTE_TIMEOUT := 12.0
const MINE_STAGES := 8
const MINE_COOLDOWN := 0.2       # art arda kırmalar arasındaki bekleme
const PICKUP_RADIUS := 1.5
const ATTRACT_RADIUS := 2.6
const MAX_DROPS := 150
const MENU_SCENE := "res://scenes/main_menu.tscn"
const SAFE_FALL := 3.0           # bu kadar bloğa kadar düşmek zararsız
const FALL_DAMAGE := 2.0         # güvenli yüksekliğin üzerindeki her blok için can kaybı
const ATTACK_REACH := 4.5        # mobla dövüş mesafesi (blok)
const ATTACK_COOLDOWN := 0.45    # iki vuruş arası bekleme (sn)
const MAX_PASSIVE := 12          # pasif moblar: sık ve dağınık doğar
const PASSIVE_TYPES := ["chicken", "pig", "cow", "sheep"]
const SEMI_TYPES := ["wolf", "bee", "angry_villager", "wizard_villager"]
const ACTIVE_TYPES := ["zombie", "skeleton", "creeper"]
const SEMI_GROUP := 5            # yarı pasif moblar 5'li gruplar halinde doğar
const ACTIVE_GROUP := 4          # aktif moblar 4'lü gruplar halinde doğar
const MAX_SEMI := 10
const MAX_ACTIVE := 8
const SEMI_INTERVAL := 10.0      # grup doğma denemeleri arası süre (sn): "dengeli"
const ACTIVE_INTERVAL := 16.0    # "dengeliden az"
const SAFE_RADIUS := 48.0        # başlangıç noktasının çevresinde aktif mob ve boss doğmaz
const BOSS_TYPES := ["golem", "giant_spider"]
const BOSS_INTERVAL := 45.0      # boss doğma denemeleri arası süre (sn)
const BOSS_CHANCE := 0.3         # her denemede doğma ihtimali: nadir
const MOB_DESPAWN := 72.0        # oyuncudan bu kadar uzaklaşan mob silinir

var world: World
var player: Player
var hud: Hud
var ui: InventoryUI
var stats_ui: StatsUI
var inv := Inventory.new()
## Oyuncuya ait kalıcı veriler (kakacoin; ileride statlar, level, XP). Dünya kaydıyla birlikte saklanır.
var pdata := {"coins": 0}
var stats := PlayerStats.new()
var hurt_flash := 0.0       # hasar alınca ekranın kızarması (HUD okur)
var death_timer := 0.0      # > 0 iken "Öldün" yazısı gösterilir
var toast_text := ""        # ekranın üstünde kısa süreli bildirim (level atlama vb.)
var toast_timer := 0.0
var ui_closed_frame := -1   # envanter / karakter ekranının kapandığı kare (HUD aynı dokunuşu yok sayar)
var selected := 0           # seçili hotbar yuvası
var paused := false
var info_text := ""

var _env: Environment
var _sun: DirectionalLight3D
var _highlight: MeshInstance3D
var _remotes := {}             # uid -> PlayerModel
var _pause_panel: Control
var _pause_label: Label
## Test aracı: 0..1 arası verilirse günün saati buna sabitlenir (0.25 = öğle).
var sky_time_override := -1.0
var _quality_button: Button
var _fps_button: Button
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
var _drops: Array[ItemDrop] = []
var mobs: Array[Mob] = []
var _attack_cd := 0.0
var _spawn_timer := 0.0
var _semi_timer := 0.0
var _boss_timer := 0.0
var chests: Array[LootChest] = []
var _active_timer := 0.0


func _ready() -> void:
	_online = Session.mode != "solo"
	_setup_environment()

	world = World.new()
	add_child(world)
	world.setup(Session.world_seed, Session.render_distance())
	if Session.mode != "join":
		world.import_edits(Session.world_edits)
	world.block_changed.connect(_on_local_block)
	_apply_quality()
	Session.quality_changed.connect(_apply_quality)

	player = Player.new()
	player.world = world
	player.auto_jump = Session.touch_mode
	add_child(player)
	if Session.mode != "join" and Session.saved_pos is Vector3:
		player.position = Session.saved_pos
		inv.from_array(Session.saved_inv)
		pdata.merge(Session.saved_player, true)
		stats.from_dict(pdata.get("stats"))
	else:
		var a := randf() * TAU if _online else 0.0
		var sx := int(cos(a) * 3.0)
		var sz := int(sin(a) * 3.0)
		player.position = Vector3(sx + 0.5, maxi(world.gen.height_at(sx, sz), WorldGen.SEA) + 2.0, sz + 0.5)

	player.fell.connect(_on_fell)
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
	ui = InventoryUI.new()
	ui.game = self
	ui.inv = inv
	layer.add_child(ui)
	stats_ui = StatsUI.new()
	stats_ui.game = self
	stats_ui.stats = stats
	layer.add_child(stats_ui)
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


## Grafik kalitesi ayarını uygular: görüş mesafesi, sis ve kenar yumuşatma.
func _apply_quality() -> void:
	world.set_render_distance(Session.render_distance())
	_env.fog_depth_begin = world.render_distance * 16.0 * 0.55
	_env.fog_depth_end = world.render_distance * 16.0 - 6.0
	get_viewport().msaa_3d = Viewport.MSAA_2X if Session.quality == 2 else Viewport.MSAA_DISABLED
	if _quality_button != null:
		_quality_button.text = "Grafik: %s" % Session.QUALITY_NAMES[Session.quality]
		_fps_button.text = "FPS Sayacı: %s" % ("Açık" if Session.show_fps else "Kapalı")


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
	_pause_panel.theme = Session.theme
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
	_quality_button = Button.new()
	_quality_button.custom_minimum_size = Vector2(360, 76)
	_quality_button.pressed.connect(func() -> void: Session.set_quality((Session.quality + 1) % 3))
	box.add_child(_quality_button)
	_fps_button = Button.new()
	_fps_button.custom_minimum_size = Vector2(360, 76)
	_fps_button.pressed.connect(func() -> void:
		Session.show_fps = not Session.show_fps
		Session.save_settings()
		_apply_quality())
	box.add_child(_fps_button)
	_apply_quality()
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
	player.swinging = _mine_requested and _mine_pos != null
	_mine_requested = false
	_mine_cooldown = maxf(_mine_cooldown - delta, 0.0)
	player.set_held(inv.id_at(selected))
	stats.equip_hp = inv.equip_hp()
	if not paused:
		stats.tick(delta)
	player.speed_mult = stats.speed_mult()
	hurt_flash = maxf(hurt_flash - delta * 2.5, 0.0)
	death_timer = maxf(death_timer - delta, 0.0)
	toast_timer = maxf(toast_timer - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_update_mobs(delta)
	_update_chests()
	_update_drops(delta)
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
	if sky_time_override >= 0.0:
		t = sky_time_override
	var day := smoothstep(0.0, 1.0, clampf(sin(t * TAU) * 2.5 + 1.25, 0.0, 1.0))
	var sky := Color(0.02, 0.03, 0.08).lerp(Color(0.52, 0.74, 0.96), day)
	_env.background_color = sky
	_env.fog_light_color = sky
	_env.ambient_light_energy = lerpf(0.12, 0.75, day)
	_sun.light_energy = lerpf(0.0, 0.55, day)


func _update_highlight() -> void:
	_highlight.visible = false
	if Session.touch_mode or paused or menu_open():
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
	if paused or menu_open():
		return
	if try_open_chest(p):
		_mine_reset()
		return
	if try_attack(p):   # parmağın altında mob varsa kırmak yerine saldır
		_mine_reset()
		return
	if _mine_cooldown > 0.0:
		return
	var hit := _target(p)
	if hit.is_empty():
		_mine_reset()
		return
	var pos: Vector3i = hit["pos"]
	var block: int = hit["id"]
	var hardness := Items.mine_time(block, inv.id_at(selected))
	if hardness < 0.0:
		_mine_reset()
		return
	if _mine_pos == null or _mine_pos != pos:
		_mine_pos = pos
		_mine_progress = 0.0
	_mine_progress += delta
	if _mine_progress >= hardness:
		_break(pos, block)
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


func _break(pos: Vector3i, block: int) -> void:
	# Yanında ya da üstünde su varsa kırılan bloğun yeri suyla dolar.
	var fill := Blocks.AIR
	for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
		if world.get_block(pos.x + d.x, pos.y + d.y, pos.z + d.z) == Blocks.WATER:
			fill = Blocks.WATER
			break
	world.set_block(pos, fill)
	# Taş ve cevherler yalnızca uygun kazmayla eşya düşürür.
	if Items.can_harvest(block, inv.id_at(selected)):
		spawn_drop(Items.drop_of(block), 1, Vector3(pos) + Vector3(0.5, 0.4, 0.5))
	var above := pos + Vector3i(0, 1, 0)
	if world.get_block(above.x, above.y, above.z) == Blocks.TORCH:
		world.set_block(above, Blocks.AIR)   # dayanağı kalmayan meşale düşer
		spawn_drop(Blocks.TORCH, 1, Vector3(above) + Vector3(0.5, 0.3, 0.5))


## Kısa dokunuş / sağ tık: çalışma masası ve fırını açar, yoksa eldeki bloğu yerleştirir.
func place_at(p: Vector2) -> void:
	if paused or menu_open():
		return
	if try_open_chest(p) or try_attack(p):
		return
	var hit := _target(p)
	if not hit.is_empty() and Blocks.is_interactive(hit["id"]):
		open_ui(InventoryUI.MODE_TABLE if hit["id"] == Blocks.CRAFTING_TABLE else InventoryUI.MODE_FURNACE)
		return
	if _use_item():
		return
	if hit.is_empty():
		return
	if hit["normal"] == Vector3i.ZERO:
		return
	var block := inv.id_at(selected)
	if not Items.is_block(block):
		return
	var pos: Vector3i = hit["pos"] + hit["normal"]
	if pos.y < 1 or pos.y >= World.CH:
		return
	var existing := world.get_block(pos.x, pos.y, pos.z)
	if existing != Blocks.AIR and existing != Blocks.WATER:
		return
	if Blocks.is_solid(block) and player.intersects_block(pos):
		return
	world.set_block(pos, block)
	inv.take(selected, 1)
	player.swing_once()


## Eldeki eşya tüketilebiliyorsa (yiyecek, iksir) kullanır. Kullanıldıysa true döner.
func _use_item() -> bool:
	var id := inv.id_at(selected)
	if Items.kind(id) == "potion":
		# Süreli iksir: statı 5 dakikalığına artırır; aynı iksir tekrar içilirse süre yenilenir.
		var stat := str(Items.prop(id, "stat", ""))
		var amount := int(Items.prop(id, "amount", 0))
		var time := float(Items.prop(id, "time", 300.0))
		stats.add_buff(stat, amount, time)
		inv.take(selected, 1)
		player.swing_once()
		toast("%s: %s +%d (%d dakika)" % [Items.item_name(id), PlayerStats.STAT_NAMES[stat], amount, roundi(time / 60.0)])
		return true
	if Items.kind(id) != "food":
		return false
	if stats.hp < stats.max_hp():
		stats.eat(id)
		inv.take(selected, 1)
		player.swing_once()
	return true


# ---------- Moblar ve dövüş ----------

func spawn_mob(type: String, pos: Vector3) -> Mob:
	var m := Mob.new()
	add_child(m)
	m.player = player
	m.setup(world, type, pos)
	m.hit_player.connect(_on_mob_hit)
	mobs.append(m)
	return m


func _update_mobs(delta: float) -> void:
	var i := mobs.size() - 1
	while i >= 0:
		var m := mobs[i]
		if not is_instance_valid(m) or m.dead:
			mobs.remove_at(i)
		elif m.position.distance_to(player.position) > MOB_DESPAWN:
			m.queue_free()
			mobs.remove_at(i)
		i -= 1
	if paused:
		return
	_spawn_timer += delta
	if _spawn_timer >= 1.5:
		_spawn_timer = 0.0
		if count_mobs("passive") < MAX_PASSIVE:
			_try_spawn()
	_semi_timer += delta
	if _semi_timer >= SEMI_INTERVAL:
		_semi_timer = 0.0
		if count_mobs("semi") + SEMI_GROUP <= MAX_SEMI:
			_try_spawn_group(SEMI_TYPES[randi() % SEMI_TYPES.size()], SEMI_GROUP, false)
	_active_timer += delta
	if _active_timer >= ACTIVE_INTERVAL:
		_active_timer = 0.0
		if count_mobs("active") + ACTIVE_GROUP <= MAX_ACTIVE:
			_try_spawn_group(ACTIVE_TYPES[randi() % ACTIVE_TYPES.size()], ACTIVE_GROUP, true)
	_boss_timer += delta
	if _boss_timer >= BOSS_INTERVAL:
		_boss_timer = 0.0
		if count_mobs("boss") == 0 and randf() < BOSS_CHANCE:   # boss tek doğar, aynı anda en fazla bir tane
			_try_spawn_group(BOSS_TYPES[randi() % BOSS_TYPES.size()], 1, true)


## Ekranın üstünde can çubuğu gösterilecek boss: dövüşe girmiş ve yakındaki boss (yoksa null).
func boss_shown() -> Mob:
	for m in mobs:
		if is_instance_valid(m) and not m.dead and m.def["k"] == "boss" and (m.aggro or m.hp < m.max_hp) \
				and m.position.distance_to(player.position) < 40.0:
			return m
	return null


## Oyuncudan uzakta bir noktada (spot) aynı türden bir grup doğurur.
## keep_safe: başlangıç noktasının çevresindeki güvenli bölgede doğmaz.
func _try_spawn_group(type: String, n: int, keep_safe: bool) -> void:
	var a := randf() * TAU
	var r := randf_range(26.0, 40.0)
	var cx := floori(player.position.x + cos(a) * r)
	var cz := floori(player.position.z + sin(a) * r)
	if keep_safe and Vector2(cx, cz).length() < SAFE_RADIUS:
		return
	if not world.is_ready_at(Vector3(cx, 0, cz)) or _surface_y(cx, cz) < 0:
		return
	for i in n:
		var x := cx + randi_range(-3, 3)
		var z := cz + randi_range(-3, 3)
		if world.is_ready_at(Vector3(x, 0, z)):
			var y := _surface_y(x, z)
			if y > 0:
				spawn_mob(type, Vector3(x + 0.5, y, z + 0.5))


## Belirli sınıftaki (passive / semi / active / boss) canlı mob sayısı.
func count_mobs(kind: String) -> int:
	var n := 0
	for m in mobs:
		if is_instance_valid(m) and not m.dead and m.def["k"] == kind:
			n += 1
	return n


## Oyuncunun çevresinde, çim ya da kum üzerinde rastgele bir noktada pasif mob doğurur.
func _try_spawn() -> void:
	var a := randf() * TAU
	var r := randf_range(14.0, 30.0)
	var x := floori(player.position.x + cos(a) * r)
	var z := floori(player.position.z + sin(a) * r)
	if not world.is_ready_at(Vector3(x, 0, z)):
		return
	var y := _surface_y(x, z)
	if y > 0:
		spawn_mob(PASSIVE_TYPES[randi() % PASSIVE_TYPES.size()], Vector3(x + 0.5, y, z + 0.5))


## (x, z) sütununda üzerinde durulabilecek çim / kum yüzeyinin y değeri; uygun değilse -1.
func _surface_y(x: int, z: int) -> int:
	var top := mini(world.gen.height_at(x, z) + 3, World.CH - 3)
	for y in range(top, maxi(top - 6, 1), -1):
		var b := world.get_block(x, y, z)
		if b == Blocks.AIR:
			continue
		if (b == Blocks.GRASS or b == Blocks.SAND) and world.get_block(x, y + 1, z) == Blocks.AIR \
				and world.get_block(x, y + 2, z) == Blocks.AIR:
			return y + 1
		return -1
	return -1


## Ekran noktasının altındaki (bloklardan önce gelen) en yakın mob.
func _mob_at(p: Vector2) -> Mob:
	if mobs.is_empty():
		return null
	var ray := screen_ray(p)
	var limit := ATTACK_REACH + (4.0 if player.third_person else 0.0)
	var hit := world.raycast(ray[0], ray[1], limit)
	if not hit.is_empty():
		limit = minf(limit, float(hit["dist"]))
	var best: Mob = null
	for m in mobs:
		if is_instance_valid(m) and not m.dead:
			var t := m.ray_hit(ray[0], ray[1])
			if t >= 0.0 and t < limit:
				limit = t
				best = m
	return best


## Ekran noktasında mob varsa ona saldırır. Mob hedeflendiyse (bekleme süresinde olsa bile) true döner.
func try_attack(p: Vector2) -> bool:
	var m := _mob_at(p)
	if m == null:
		return false
	if _attack_cd <= 0.0:
		attack_mob(m)
	return true


## Tek vuruş: sekme / kritik zarı, kılıç bonusu ve yıpranması, XP ödülü.
func attack_mob(m: Mob) -> void:
	_attack_cd = ATTACK_COOLDOWN
	player.swing_once()
	var held := inv.id_at(selected)
	var weapon := 0
	if Items.kind(held) == "sword":
		var need := int(Items.prop(held, "lvl", 0))
		if stats.level >= need:
			weapon = int(Items.prop(held, "dmg", 0))
		else:
			toast("%s için level %d gerekli" % [Items.item_name(held), need])
	var r := stats.roll_attack(weapon)
	var at := m.position + Vector3(0, m.height + 0.8, 0)
	if r["miss"]:
		float_text("Sekti", Color(0.8, 0.8, 0.8), at)
		m.provoke(player.position)
	else:
		var died := m.hurt(float(r["dmg"]), player.position)
		if r["crit"]:
			float_text("Kritik -%d" % r["dmg"], Color(1.0, 0.85, 0.2), at)
		else:
			float_text("-%d" % r["dmg"], Color(1.0, 0.35, 0.3), at)
		if died:
			var xp := int(m.def["xp"])
			float_text("+%d XP" % xp, Color(0.45, 1.0, 0.4), at + Vector3(0, 0.45, 0))
			add_xp(xp)
			spawn_chest(m.position + Vector3(0, 0.3, 0), Loot.roll(m.type))
			mobs.erase(m)
			m.queue_free()
	if weapon > 0 and inv.wear(selected):
		toast("%s kırıldı" % Items.item_name(held))


# ---------- Ganimet sandıkları ----------

## items: [[eşya kimliği, adet, dayanıklılık (-1: tam)], ...]. Boşsa sandık düşmez.
func spawn_chest(pos: Vector3, items: Array) -> LootChest:
	if items.is_empty():
		return null
	var c := LootChest.new()
	add_child(c)
	c.setup(world, pos, items)
	chests.append(c)
	return c


func _update_chests() -> void:
	var i := chests.size() - 1
	while i >= 0:
		var c := chests[i]
		if not is_instance_valid(c) or c.expired:
			chests.remove_at(i)
		i -= 1


## Ekran noktasının altındaki (bloklardan önce gelen) en yakın sandık.
func _chest_at(p: Vector2) -> LootChest:
	if chests.is_empty():
		return null
	var ray := screen_ray(p)
	var limit := REACH + (4.0 if player.third_person else 0.0)
	var hit := world.raycast(ray[0], ray[1], limit)
	if not hit.is_empty():
		limit = minf(limit, float(hit["dist"]) + 0.3)
	var best: LootChest = null
	for c in chests:
		if is_instance_valid(c) and not c.expired:
			var t := _ray_box(ray[0], ray[1], c.position + Vector3(-0.45, -0.15, -0.45), c.position + Vector3(0.45, 0.75, 0.45))
			if t >= 0.0 and t < limit:
				limit = t
				best = c
	return best


## Işının kutuya çarptığı uzaklık; çarpmıyorsa -1.
func _ray_box(origin: Vector3, dir: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := 0.0
	var t1 := 1.0e9
	for a in 3:
		if absf(dir[a]) < 1.0e-6:
			if origin[a] < lo[a] or origin[a] > hi[a]:
				return -1.0
		else:
			var ta := (lo[a] - origin[a]) / dir[a]
			var tb := (hi[a] - origin[a]) / dir[a]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return -1.0
	return t0


## Ekran noktasında sandık varsa içeriğini açar.
func try_open_chest(p: Vector2) -> bool:
	var c := _chest_at(p)
	if c == null:
		return false
	open_chest(c)
	return true


## Sandığın içeriğini gösterir; oyuncu istediği eşyaları alır. Ekran açıkken sandığın süresi işlemez.
func open_chest(c: LootChest) -> void:
	if paused or menu_open() or death_timer > 0.0:
		return
	hud.release_all()
	_mine_reset()
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.open_chest(c)


## Dünyada yükselip kaybolan yazı (hasar, XP).
func float_text(text: String, color: Color, pos: Vector3) -> void:
	var f := FloatText.new()
	add_child(f)
	f.setup(text, color, pos)


# ---------- Can, hasar ve ölüm ----------

func _on_fell(height: float) -> void:
	if height > SAFE_FALL:
		hurt(floorf((height - SAFE_FALL) * FALL_DAMAGE))


## Mob oyuncuya vurdu: hasar uygulanır ve takılı zırh / kalkan 1'er yıpranır.
func _on_mob_hit(amount: float) -> void:
	if death_timer > 0.0:
		return
	hurt(amount)
	if death_timer > 0.0:
		return   # öldü: ekipman zaten silindi
	var broken := inv.wear_equipment()
	if not broken.is_empty():
		var names: PackedStringArray = []
		for id in broken:
			names.append(Items.item_name(id))
		toast(", ".join(names) + " kırıldı")


## Oyuncuya hasar verir; can biterse ölüm cezası uygulanır.
func hurt(amount: float) -> void:
	if amount <= 0.0 or death_timer > 0.0:
		return
	hurt_flash = 1.0
	if stats.damage(amount):
		var totem := inv.find(Items.TOTEM)
		if totem >= 0:
			# Ölümsüzlük totemi: ölümü bir kez engeller, canı doldurur, ceza uygulanmaz.
			inv.take(totem, 1)
			stats.hp = float(stats.max_hp())
			for m in mobs:
				if is_instance_valid(m):
					m.calm()
			toast("Ölümsüzlük Totemi seni kurtardı!")
		else:
			_die()


## Ölüm: tüm eşyalar yok olur, XP ve level sıfırlanır, her stattan 1 puan düşer, oyuncu başlangıç noktasında doğar.
func _die() -> void:
	ui.close()
	stats_ui.close()
	hud.release_all()
	_mine_reset()
	inv.clear()
	stats.die()
	for m in mobs:
		if is_instance_valid(m):
			m.calm()
	player.teleport(_spawn_point())
	death_timer = 4.0
	_save()


func _spawn_point() -> Vector3:
	return Vector3(0.5, maxi(world.gen.height_at(0, 0), WorldGen.SEA) + 2.0, 0.5)


func select_slot(i: int) -> void:
	selected = clampi(i, 0, Inventory.HOTBAR - 1)


# ---------- Düşen eşyalar ----------

func spawn_drop(id: int, n: int, pos: Vector3, dur := -1) -> void:
	if id <= 0 or n <= 0:
		return
	if _drops.size() >= MAX_DROPS:
		_drops.pop_front().queue_free()
	var d := ItemDrop.new()
	add_child(d)
	d.setup(world, id, n, pos, dur)
	_drops.append(d)


## Envantere sığmayan eşyayı oyuncunun önüne bırakır.
func drop_from_player(id: int, n: int, dur := -1) -> void:
	spawn_drop(id, n, player.eye_position() + player.look_dir() * 1.2, dur)


func _update_drops(delta: float) -> void:
	var center := player.position + Vector3(0, 0.9, 0)
	var i := _drops.size() - 1
	while i >= 0:
		var d := _drops[i]
		if not is_instance_valid(d):
			_drops.remove_at(i)
		elif d.age > ItemDrop.PICKUP_DELAY and inv.can_add(d.item_id, 1):
			var dist := d.position.distance_to(center)
			if dist < PICKUP_RADIUS:
				d.count = inv.add(d.item_id, d.count, d.dur)
				if d.count <= 0:
					d.queue_free()
					_drops.remove_at(i)
			elif dist < ATTRACT_RADIUS:
				d.attract(center, delta)
		i -= 1


# ---------- Envanter / crafting ekranı ----------

## Envanter ya da karakter ekranı açık mı?
func menu_open() -> bool:
	return ui.visible or stats_ui.visible


## XP kazandırır; level atlanırsa bildirim gösterir.
func add_xp(n: int) -> void:
	if stats.add_xp(n) > 0:
		toast("Level %d oldun!" % stats.level if stats.points <= 0 else "Level %d oldun! Dağıtılacak puan: %d" % [stats.level, stats.points])


func toast(text: String) -> void:
	toast_text = text
	toast_timer = 4.0


## Karakter ekranı: level, XP ve stat puanı dağıtma.
func open_stats() -> void:
	if paused or menu_open():
		return
	hud.release_all()
	_mine_reset()
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stats_ui.open()


func open_ui(mode: int) -> void:
	if paused or menu_open():
		return
	hud.release_all()
	_mine_reset()
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.open(mode)


func on_ui_closed() -> void:
	ui_closed_frame = Engine.get_process_frames()
	player.controls_enabled = not paused
	if not Session.touch_mode and not paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	ui.close()
	stats_ui.close()
	paused = true
	player.controls_enabled = false
	hud.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_label.text = reason
	_pause_panel.visible = true
	_resume_button.visible = false


# ---------- Duraklatma / çıkış / kayıt ----------

func toggle_pause() -> void:
	if menu_open():
		ui.close()
		stats_ui.close()
		return
	paused = not paused
	hud.release_all()
	player.controls_enabled = not paused
	_pause_panel.visible = paused
	_pause_label.text = ("Oda Kodu: %s" % Session.room_code) if _online else "Oyun Duraklatıldı"
	if not Session.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _save() -> void:
	_save_timer = 0.0
	pdata["stats"] = stats.to_dict()
	if Session.mode != "join":
		Session.save_world(world.export_edits(), player.position, inv.to_array(), pdata)


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
