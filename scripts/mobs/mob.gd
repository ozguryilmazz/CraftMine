class_name Mob
extends Node3D
## Mob: kutulardan model, voxel çarpışması ve basit yapay zeka. `position` ayakların bulunduğu noktadır.
## Bu sürümde pasif davranış var: gezinir, vurulunca oyuncudan kaçar, asla saldırmaz.

const GRAVITY := 26.0
const JUMP_VEL := 7.6
const FLEE_TIME := 6.0

var world: World
var type := ""
var def := {}
var hp := 1.0
var max_hp := 1
var vel := Vector3.ZERO
var yaw := 0.0
var on_ground := false
var dead := false
var half_w := 0.25
var height := 0.75
var ai_enabled := true

var _model: Node3D
var _mats: Array = []          # [malzeme, asıl renk]
var _legs: Array[Node3D] = []
var _label: Label3D
var _flash := 0.0
var _state := "idle"
var _state_time := 1.0
var _dir := Vector3.ZERO
var _flee_from := Vector3.ZERO
var _phase := 0.0


func setup(p_world: World, p_type: String, pos: Vector3) -> void:
	world = p_world
	type = p_type
	def = MobDB.DEFS[type]
	max_hp = int(def["hp"])
	hp = float(max_hp)
	half_w = float(def["size"].x) * 0.5
	height = float(def["size"].y)
	position = pos
	yaw = randf() * TAU
	_state_time = randf_range(0.5, 3.0)
	_model = Node3D.new()
	add_child(_model)
	_build_model()
	_label = Label3D.new()
	_label.position = Vector3(0, height + 0.3, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.font = Session.font
	_label.font_size = 30
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)


# ---------- Model ----------

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	_mats.append([mat, color])


## Üst ucundan dönen bacak.
func _leg(pivot: Vector3, size: Vector3, color: Color) -> void:
	var n := Node3D.new()
	n.position = pivot
	_model.add_child(n)
	_box(n, Vector3(0, -size.y * 0.5, 0), size, color)
	_legs.append(n)


## Modelin önü -Z yönüdür.
func _build_model() -> void:
	match type:
		_:   # tavuk
			var white := Color(0.95, 0.95, 0.92)
			var yellow := Color(0.95, 0.75, 0.15)
			_leg(Vector3(-0.09, 0.26, 0.02), Vector3(0.05, 0.26, 0.05), yellow)
			_leg(Vector3(0.09, 0.26, 0.02), Vector3(0.05, 0.26, 0.05), yellow)
			_box(_model, Vector3(0, 0.42, 0.03), Vector3(0.34, 0.32, 0.46), white)
			_box(_model, Vector3(-0.19, 0.44, 0.03), Vector3(0.05, 0.2, 0.32), white.darkened(0.12))
			_box(_model, Vector3(0.19, 0.44, 0.03), Vector3(0.05, 0.2, 0.32), white.darkened(0.12))
			_box(_model, Vector3(0, 0.66, -0.2), Vector3(0.2, 0.26, 0.18), white)
			_box(_model, Vector3(0, 0.66, -0.33), Vector3(0.12, 0.07, 0.1), Color(0.95, 0.6, 0.1))
			_box(_model, Vector3(0, 0.57, -0.31), Vector3(0.07, 0.09, 0.05), Color(0.85, 0.12, 0.1))
			_box(_model, Vector3(0, 0.82, -0.2), Vector3(0.05, 0.07, 0.14), Color(0.85, 0.12, 0.1))
			_box(_model, Vector3(-0.105, 0.7, -0.25), Vector3(0.02, 0.05, 0.05), Color(0.05, 0.05, 0.05))
			_box(_model, Vector3(0.105, 0.7, -0.25), Vector3(0.02, 0.05, 0.05), Color(0.05, 0.05, 0.05))


# ---------- Hasar ----------

## Işının (başlangıç, yön) mob kutusuna çarptığı uzaklık; çarpmıyorsa -1.
## Dokunmatikte isabet kolay olsun diye kutu biraz büyütülür.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var g := 0.18
	var lo := Vector3(position.x - half_w - g, position.y - g, position.z - half_w - g)
	var hi := Vector3(position.x + half_w + g, position.y + height + g, position.z + half_w + g)
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


## Hasar uygular ve mobu geri iter. Öldüyse true döner.
func hurt(amount: float, from: Vector3) -> bool:
	if dead:
		return false
	hp = maxf(hp - amount, 0.0)
	_flash = 0.25
	var away := Vector3(position.x - from.x, 0, position.z - from.z)
	away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, -1)
	vel += away * 4.5 + Vector3(0, 4.0, 0)
	_label.text = "%s  %d / %d" % [def["n"], ceili(hp), max_hp]
	_label.visible = true
	if hp <= 0.0:
		dead = true
		return true
	if def["k"] == "passive":
		_state = "flee"
		_state_time = FLEE_TIME
		_flee_from = from
	return false


# ---------- Döngü ----------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if dead or not world.is_ready_at(position):
		return
	var wish := _think(delta) if ai_enabled else Vector3.ZERO
	var feet := world.get_block(floori(position.x), floori(position.y + 0.2), floori(position.z))
	var in_water := feet == Blocks.WATER
	var k := minf((10.0 if on_ground else 3.0) * delta, 1.0)
	vel.x = lerpf(vel.x, wish.x, k)
	vel.z = lerpf(vel.z, wish.z, k)
	if in_water:
		vel.y = minf(vel.y + 18.0 * delta, 2.0)
	else:
		vel.y = maxf(vel.y - GRAVITY * delta, -40.0)
	var blocked := _move(0, vel.x * delta)
	if blocked:
		vel.x = 0.0
	if _move(2, vel.z * delta):
		vel.z = 0.0
		blocked = true
	var falling := vel.y <= 0.0
	on_ground = false
	if _move(1, vel.y * delta):
		on_ground = falling
		vel.y = 0.0
	if blocked and wish.length() > 0.1 and (on_ground or in_water):
		vel.y = JUMP_VEL if not in_water else 3.0   # önündeki tek bloğun üstüne zıpla
	if position.y < -10.0:
		dead = true
		queue_free()
		return
	if wish.length() > 0.1:
		yaw = lerp_angle(yaw, atan2(-wish.x, -wish.z), minf(delta * 8.0, 1.0))
	rotation.y = yaw
	var speed := Vector2(vel.x, vel.z).length()
	_phase += delta * (6.0 + speed * 4.0)
	var swing := sin(_phase) * 0.7 * clampf(speed / 1.2, 0.0, 1.0)
	for i in _legs.size():
		_legs[i].rotation.x = swing if i % 2 == 0 else -swing
	if _flash > 0.0:
		_flash -= delta
		var f := clampf(_flash / 0.25, 0.0, 1.0)
		for m: Array in _mats:
			m[0].albedo_color = (m[1] as Color).lerp(Color(1.0, 0.15, 0.1), f * 0.75)


## Yapay zeka: istenen yatay hızı döndürür.
func _think(delta: float) -> Vector3:
	var speed := float(def["speed"])
	_state_time -= delta
	match _state:
		"flee":
			if _state_time <= 0.0:
				_state = "idle"
				_state_time = randf_range(1.0, 3.0)
				return Vector3.ZERO
			var away := Vector3(position.x - _flee_from.x, 0, position.z - _flee_from.z)
			_dir = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
			return _dir * speed * 2.2
		"walk":
			if _state_time <= 0.0 or not _safe_ahead():
				_state = "idle"
				_state_time = randf_range(1.0, 4.0)
				return Vector3.ZERO
			return _dir * speed
	if _state_time <= 0.0:
		var a := randf() * TAU
		_dir = Vector3(cos(a), 0, sin(a))
		_state = "walk"
		_state_time = randf_range(1.5, 4.5)
	return Vector3.ZERO


## Gezinirken önünde su ya da uçurum var mı?
func _safe_ahead() -> bool:
	var ax := floori(position.x + _dir.x * 0.9)
	var az := floori(position.z + _dir.z * 0.9)
	var y := floori(position.y + 0.1)
	for d in range(0, 4):
		var b := world.get_block(ax, y - d, az)
		if b == Blocks.WATER:
			return false
		if d > 0 and Blocks.is_solid(b):
			return true
	return false


func _collides(p: Vector3) -> bool:
	for y in range(floori(p.y), floori(p.y + height) + 1):
		for z in range(floori(p.z - half_w), floori(p.z + half_w) + 1):
			for x in range(floori(p.x - half_w), floori(p.x + half_w) + 1):
				if world.is_solid(x, y, z):
					return true
	return false


## Tek eksende hareket; çarpışırsa durur ve true döner.
func _move(axis: int, d: float) -> bool:
	if d == 0.0:
		return false
	var steps := ceili(absf(d) / 0.3)
	var s := d / steps
	for i in steps:
		var p := position
		p[axis] += s
		if _collides(p):
			if axis == 1 and s < 0.0:
				p.y = floorf(p.y) + 1.0
				if not _collides(p):
					position = p
			return true
		position = p
	return false
