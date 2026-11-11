class_name Player
extends Node3D
## Yerel oyuncu: voxel AABB çarpışması, yürüme/zıplama/yüzme ve 1./3. şahıs kamera.
## `position` ayakların bulunduğu noktadır.

const HALF_W := 0.3
const HEIGHT := 1.8
const EYE := 1.62
const WALK_SPEED := 4.5
const SWIM_SPEED := 2.6
const GRAVITY := 28.0
const JUMP_VEL := 8.6

var world: World
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var on_ground := false
var in_water := false
var third_person := false
var auto_jump := false
## Hız statından gelen çarpan (oyun tarafından ayarlanır).
var speed_mult := 1.0

## Oyuncu yere düştüğünde, düştüğü yükseklik (blok) ile yayılır.
signal fell(height: float)

## HUD (joystick / zıplama butonu) tarafından ayarlanır. y: ileri (+) / geri (-).
var move_input := Vector2.ZERO
var jump_held := false
var controls_enabled := true

var camera: Camera3D
var model: PlayerModel

## Kırma sırasında oyun tarafından her karede ayarlanır.
var swinging := false
var _swing_timer := 0.0
var _swing_phase := 0.0
var _arm: Node3D
var _hand: Node3D           # elde tutulan eşyanın bilek ekseni
var _held_vis: MeshInstance3D
var _held_id := -1
var _spawned := false
var _pos := Vector3.ZERO
var _fall_top := -1.0e9     # havadayken ulaşılan en yüksek nokta
var _no_fall := false       # ışınlanmadan sonraki ilk inişte düşme hasarı yok


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.08
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	model = PlayerModel.new()
	model.visible = false
	add_child(model)
	# Birinci şahıs kol: kameranın sağ alt köşesinde, omuzdan dönen bir kutu
	_arm = Node3D.new()
	_arm.position = Vector3(0.5, -0.5, -0.7)
	camera.add_child(_arm)
	var arm_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.11, 0.11, 0.44)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.87, 0.68, 0.53)
	skin.roughness = 1.0
	skin.metallic_specular = 0.0
	skin.no_depth_test = true   # kol yakındaki blokların içine girmesin: her zaman üstte çizilir
	skin.render_priority = 1
	box.material = skin
	arm_mesh.mesh = box
	arm_mesh.position = Vector3(0, 0, -0.2)
	_arm.add_child(arm_mesh)
	_hand = Node3D.new()
	_hand.position = Vector3(0.52, -0.62, -0.8)
	camera.add_child(_hand)


## Tek seferlik kol sallama (blok yerleştirme).
func swing_once() -> void:
	_swing_timer = 0.25


## Elde tutulan eşyanın görselini günceller (0: boş el).
func set_held(id: int) -> void:
	if id == _held_id:
		return
	_held_id = id
	if _held_vis != null:
		_held_vis.queue_free()
		_held_vis = null
	if id <= 0:
		return
	_held_vis = ItemDrop.make_visual(id)
	var mat: StandardMaterial3D = _held_vis.material_override.duplicate()
	mat.no_depth_test = true
	mat.render_priority = 2
	_held_vis.material_override = mat
	if Items.is_block(id) and id != Blocks.TORCH:
		# Blok: sağ altta, köşesi oyuncuya dönük küp
		_held_vis.scale = Vector3.ONE * 0.24
		_held_vis.position = Vector3(0.0, 0.2, 0.0)
		_held_vis.rotation = Vector3(0.12, 0.7, 0.0)
	else:
		# Alet / eşya: sapı sağ alttaki elde, başı yukarı-ileri bakacak şekilde çapraz tutuş.
		# Simge aynalanır (sap sağ altta kalsın diye) ve uzak ucu ileri doğru yatırılır.
		_held_vis.scale = Vector3.ONE * 0.36
		_held_vis.position = Vector3(-0.06, 0.34, 0.0)
		_held_vis.rotation = Vector3(0.0, PI - 0.75, 0.12)
	_hand.add_child(_held_vis)


## Oyuncuyu verilen noktaya taşır (yeniden doğma); bu inişte düşme hasarı alınmaz.
func teleport(p: Vector3) -> void:
	position = p
	vel = Vector3.ZERO
	_no_fall = true
	_spawned = false


func add_look(dx: float, dy: float) -> void:
	yaw = wrapf(yaw - dx, -PI, PI)
	pitch = clampf(pitch - dy, -1.5, 1.5)


func toggle_view() -> void:
	third_person = not third_person
	model.visible = third_person


func eye_position() -> Vector3:
	return position + Vector3(0, EYE, 0)


func look_dir() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, -1)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	world.set_center_from(position)
	if world.is_ready_at(position):
		_pos = position
		if not _spawned:
			_spawned = true
			while _collides(_pos) and _pos.y < World.CH + 2:
				_pos.y += 1.0
		_simulate(delta)
		position = _pos
	_update_camera()
	var active := swinging or _swing_timer > 0.0
	_swing_timer -= delta
	_swing_phase = _swing_phase + delta * 13.0 if active else 0.0
	var swing := absf(sin(_swing_phase)) if active else 0.0
	_arm.rotation = Vector3(0.35 - swing * 0.7, 0.2, 0.0)
	_arm.visible = not third_person and _held_id <= 0   # eşya tutarken yalnızca eşya görünür
	_hand.rotation = Vector3(-swing * 0.85, swing * 0.25, swing * 0.2)   # bilekten öne doğru vuruş
	_hand.visible = not third_person
	model.rotation.y = yaw
	model.animate(delta, Vector2(vel.x, vel.z).length(), pitch, swing * 1.3)


func _simulate(delta: float) -> void:
	var inp := Vector2.ZERO
	var jump := false
	if controls_enabled:
		inp = move_input
		if Input.is_physical_key_pressed(KEY_W): inp.y += 1.0
		if Input.is_physical_key_pressed(KEY_S): inp.y -= 1.0
		if Input.is_physical_key_pressed(KEY_D): inp.x += 1.0
		if Input.is_physical_key_pressed(KEY_A): inp.x -= 1.0
		jump = jump_held or Input.is_physical_key_pressed(KEY_SPACE)
	if inp.length() > 1.0:
		inp = inp.normalized()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := right * inp.x + fwd * inp.y

	var feet := world.get_block(floori(_pos.x), floori(_pos.y + 0.4), floori(_pos.z))
	in_water = feet == Blocks.WATER
	var speed := (SWIM_SPEED if in_water else WALK_SPEED) * speed_mult
	var accel := 8.0 if in_water else (14.0 if on_ground else 6.0)
	var k := minf(accel * delta, 1.0)
	vel.x = lerpf(vel.x, wish.x * speed, k)
	vel.z = lerpf(vel.z, wish.z * speed, k)

	if in_water:
		vel.y = maxf(vel.y - 7.0 * delta, -3.0)
		if jump and vel.y < 3.6:
			vel.y = minf(vel.y + 22.0 * delta, 3.6)
	else:
		vel.y = maxf(vel.y - GRAVITY * delta, -50.0)
		if jump and on_ground:
			vel.y = JUMP_VEL

	var blocked := _move(0, vel.x * delta)
	if blocked:
		vel.x = 0.0
	if _move(2, vel.z * delta):
		vel.z = 0.0
		blocked = true
	var was_falling := vel.y <= 0.0
	on_ground = false
	if _move(1, vel.y * delta):
		if was_falling:
			on_ground = true
		vel.y = 0.0
	# Düşme yüksekliği: havadayken en yüksek nokta izlenir, yere inince fark bildirilir (suya düşmek zararsız).
	if on_ground or in_water:
		if on_ground and not in_water and not _no_fall and _fall_top - _pos.y > 0.5:
			fell.emit(_fall_top - _pos.y)
		_no_fall = false
		_fall_top = _pos.y
	else:
		_fall_top = maxf(_fall_top, _pos.y)
	# Önü tek blokla kapalıysa otomatik zıpla (dokunmatik kontrol kolaylığı).
	if blocked and auto_jump and wish.length() > 0.3 and (on_ground or in_water):
		var ahead := _pos + wish.normalized() * 0.7
		var ax := floori(ahead.x)
		var az := floori(ahead.z)
		var ay := floori(_pos.y + 0.1)
		if world.is_solid(ax, ay, az) and not world.is_solid(ax, ay + 1, az) and not world.is_solid(ax, ay + 2, az):
			vel.y = JUMP_VEL if not in_water else 3.6
	# Sudan karaya çıkış: kıyıya doğru yüzerken önündeki kenar erişilebilir yükseklikteyse sudan sıçrar.
	if blocked and in_water and wish.length() > 0.3:
		var wa := _pos + wish.normalized() * 0.7
		var wx := floori(wa.x)
		var wz := floori(wa.z)
		var wy := floori(_pos.y + 0.1)
		for dy in 3:
			var ty := wy + dy
			if world.is_solid(wx, ty, wz) and not world.is_solid(wx, ty + 1, wz) and not world.is_solid(wx, ty + 2, wz):
				if ty + 1.0 - _pos.y <= 1.75:
					vel.y = maxf(vel.y, 9.6)
				else:
					vel.y = maxf(vel.y, 3.6)   # kenar henüz yüksek: önce yüzeye doğru yüksel
				break
	if _pos.y < -20.0:
		_pos = Vector3(_pos.x, World.CH + 4, _pos.z)
		vel = Vector3.ZERO
		_no_fall = true


## Verilen ayak konumunda oyuncu kutusu katı bir blokla kesişiyor mu?
func _collides(p: Vector3) -> bool:
	var x0 := floori(p.x - HALF_W)
	var x1 := floori(p.x + HALF_W)
	var y0 := floori(p.y)
	var y1 := floori(p.y + HEIGHT)
	var z0 := floori(p.z - HALF_W)
	var z1 := floori(p.z + HALF_W)
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if world.is_solid(x, y, z):
					return true
	return false


## Tek eksende hareket; çarpışırsa blok sınırına yaslar ve true döner.
func _move(axis: int, d: float) -> bool:
	if d == 0.0:
		return false
	var steps := ceili(absf(d) / 0.4)
	var s := d / steps
	for i in steps:
		var p := _pos
		p[axis] += s
		if _collides(p):
			if axis == 1:
				if s < 0.0:
					p.y = floorf(p.y) + 1.0
				else:
					p.y = floorf(p.y + HEIGHT) - HEIGHT - 0.001
			elif s > 0.0:
				p[axis] = floorf(p[axis] + HALF_W) - HALF_W - 0.001
			else:
				p[axis] = floorf(p[axis] - HALF_W) + 1.0 + HALF_W + 0.001
			if not _collides(p):
				_pos = p
			return true
		_pos = p
	return false


## Oyuncu kutusu verilen blok hücresiyle kesişiyor mu? (blok yerleştirme kontrolü)
func intersects_block(b: Vector3i) -> bool:
	return position.x + HALF_W > b.x and position.x - HALF_W < b.x + 1 \
		and position.y + HEIGHT > b.y and position.y < b.y + 1 \
		and position.z + HALF_W > b.z and position.z - HALF_W < b.z + 1


func _update_camera() -> void:
	var cam_basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	var eye := Vector3(0, EYE, 0)
	if third_person:
		var back := cam_basis * Vector3(0, 0, 1)
		var dist := 4.0
		var hit := world.raycast(position + eye, back, dist + 0.3)
		if not hit.is_empty():
			dist = maxf(float(hit["dist"]) - 0.3, 0.3)
		camera.position = eye + back * dist
	else:
		camera.position = eye
	camera.basis = cam_basis
