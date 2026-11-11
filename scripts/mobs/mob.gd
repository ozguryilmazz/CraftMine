class_name Mob
extends Node3D
## Mob: kutulardan model, voxel çarpışması ve basit yapay zeka. `position` ayakların bulunduğu noktadır.
## Davranış mob sınıfına göre değişir:
##   passive: gezinir, vurulunca kaçar, asla saldırmaz.
##   semi   : vurulana kadar zararsızdır; vurulunca ölene ya da oyuncu takip mesafesinden çıkana kadar kovalar.
##   active : oyuncu yakınına girince kendiliğinden saldırır; daha uzağa kadar kovalar.
##   boss   : vurulmadan saldırmaz (semi gibi).

## Mob oyuncuya vurduğunda yayılır.
signal hit_player(damage: float)

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
var player: Node3D           # oyuncu (hedef ve çarpışma)
var aggro := false           # oyuncuyu kovalıyor mu?
var hover := 0.0
var _atk_cd := 0.0
var _lunge := 0.0
var _leg_axis := 0           # bacakların sallandığı eksen (0: x, 1: y - yana açılan örümcek bacakları)

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
	hover = float(def.get("hover", 0.0))
	position = pos
	yaw = randf() * TAU
	_state_time = randf_range(0.5, 3.0)
	_model = Node3D.new()
	add_child(_model)
	_build_model()
	_model.position.y = hover
	_label = Label3D.new()
	_label.position = Vector3(0, hover + height + 0.3, 0)
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


## Dört ayaklı gövde: bacaklar, gövde ve baş. Baş kutusunun merkezini döndürür.
func _quadruped(body: Vector3, leg_h: float, leg_w: float, body_col: Color, leg_col: Color, head: Vector3, head_col: Color, head_up := 0.0) -> Vector3:
	var lx := body.x * 0.5 - leg_w * 0.5
	var lz := body.z * 0.5 - leg_w * 0.5
	# sıra: sol ön, sağ ön, sağ arka, sol arka (çapraz bacaklar birlikte sallanır)
	for p: Vector2 in [Vector2(-lx, -lz), Vector2(lx, -lz), Vector2(lx, lz), Vector2(-lx, lz)]:
		_leg(Vector3(p.x, leg_h, p.y), Vector3(leg_w, leg_h, leg_w), leg_col)
	_box(_model, Vector3(0, leg_h + body.y * 0.5, 0), body, body_col)
	var hc := Vector3(0, leg_h + body.y * 0.5 + head_up, -body.z * 0.5 - head.z * 0.5 + 0.06)
	_box(_model, hc, head, head_col)
	var eye := Color(0.05, 0.05, 0.05)
	_box(_model, hc + Vector3(-head.x * 0.5 - 0.005, head.y * 0.15, -head.z * 0.2), Vector3(0.02, 0.07, 0.07), eye)
	_box(_model, hc + Vector3(head.x * 0.5 + 0.005, head.y * 0.15, -head.z * 0.2), Vector3(0.02, 0.07, 0.07), eye)
	return hc


## İnsansı gövde (köylü, zombi, iskelet). thin: uzuv kalınlığı çarpanı; arms_forward: kollar öne uzanır.
func _humanoid(skin: Color, shirt: Color, pants: Color, thin := 1.0, arms_forward := false) -> void:
	var w := 0.24 * thin
	_leg(Vector3(-0.13, 0.75, 0), Vector3(w, 0.75, w), pants)
	_leg(Vector3(0.13, 0.75, 0), Vector3(w, 0.75, w), pants)
	_box(_model, Vector3(0, 1.1, 0), Vector3(0.52 * (0.6 + 0.4 * thin), 0.7, 0.26 * thin), shirt)
	var aw := 0.22 * thin
	for sx: float in [0.38, -0.38]:   # sıra: sağ kol, sol kol (bacaklarla çapraz sallanır)
		var n := Node3D.new()
		n.position = Vector3(sx * (0.7 + 0.3 * thin), 1.45, 0)
		_model.add_child(n)
		_box(n, Vector3(0, -0.35, 0), Vector3(aw, 0.7, aw), skin if arms_forward else shirt)
		if arms_forward:
			n.rotation.x = 1.45
		else:
			_legs.append(n)
	_box(_model, Vector3(0, 1.67, 0), Vector3(0.44, 0.44, 0.44), skin)


func _face(y: float, z: float, eye: Color, half := 0.1) -> void:
	_box(_model, Vector3(-half, y, z), Vector3(0.09, 0.07, 0.02), eye)
	_box(_model, Vector3(half, y, z), Vector3(0.09, 0.07, 0.02), eye)


## Modelin önü -Z yönüdür.
func _build_model() -> void:
	match type:
		"golem":
			var stone := Color(0.78, 0.76, 0.72)
			_humanoid(stone, stone.darkened(0.08), stone.darkened(0.2), 1.35)
			_face(1.72, -0.225, Color(0.8, 0.1, 0.08))
			_box(_model, Vector3(0, 1.6, -0.25), Vector3(0.12, 0.26, 0.1), stone.darkened(0.25))
			_box(_model, Vector3(0.12, 1.2, -0.185), Vector3(0.2, 0.36, 0.02), Color(0.3, 0.55, 0.25))
			_box(_model, Vector3(-0.2, 0.95, -0.185), Vector3(0.12, 0.22, 0.02), Color(0.3, 0.55, 0.25))
			_model.scale = Vector3.ONE * 1.42
		"giant_spider":
			var dark := Color(0.2, 0.17, 0.16)
			_leg_axis = 1
			_box(_model, Vector3(0, 0.72, 0.5), Vector3(1.3, 0.8, 1.3), dark)
			_box(_model, Vector3(0, 0.62, -0.5), Vector3(0.8, 0.56, 0.74), dark.lightened(0.08))
			_box(_model, Vector3(0, 1.13, 0.5), Vector3(0.5, 0.03, 0.7), Color(0.6, 0.1, 0.1))
			for ex: float in [-0.26, -0.09, 0.09, 0.26]:
				_box(_model, Vector3(ex, 0.72, -0.875), Vector3(0.1, 0.1, 0.02), Color(0.9, 0.1, 0.1))
			_box(_model, Vector3(-0.15, 0.4, -0.9), Vector3(0.08, 0.2, 0.08), Color(0.85, 0.85, 0.8))
			_box(_model, Vector3(0.15, 0.4, -0.9), Vector3(0.08, 0.2, 0.08), Color(0.85, 0.85, 0.8))
			for side: float in [-1.0, 1.0]:
				for li in 4:
					var n := Node3D.new()
					n.position = Vector3(side * 0.4, 0.62, -0.62 + li * 0.36)
					_model.add_child(n)
					var seg := Node3D.new()
					seg.rotation.z = side * -0.55
					n.add_child(seg)
					_box(seg, Vector3(side * 0.62, 0, 0), Vector3(1.2, 0.11, 0.11), dark.lightened(0.05))
					_legs.append(n)
		"wolf":
			var grey := Color(0.72, 0.72, 0.74)
			var hc := _quadruped(Vector3(0.36, 0.36, 0.8), 0.4, 0.12, grey, grey.darkened(0.15), Vector3(0.34, 0.32, 0.3), grey, 0.1)
			_box(_model, hc + Vector3(0, -0.07, -0.22), Vector3(0.16, 0.14, 0.16), grey.lightened(0.15))
			_box(_model, hc + Vector3(0, -0.03, -0.305), Vector3(0.06, 0.05, 0.02), Color(0.08, 0.08, 0.08))
			_box(_model, hc + Vector3(-0.11, 0.21, 0.04), Vector3(0.09, 0.12, 0.06), grey.darkened(0.2))
			_box(_model, hc + Vector3(0.11, 0.21, 0.04), Vector3(0.09, 0.12, 0.06), grey.darkened(0.2))
			_box(_model, Vector3(0, 0.62, 0.52), Vector3(0.1, 0.1, 0.34), grey.darkened(0.1))
		"bee":
			var yellow := Color(0.96, 0.78, 0.15)
			var black := Color(0.1, 0.09, 0.08)
			_box(_model, Vector3(0, 0.25, 0), Vector3(0.34, 0.32, 0.5), yellow)
			_box(_model, Vector3(0, 0.25, 0.02), Vector3(0.35, 0.33, 0.08), black)
			_box(_model, Vector3(0, 0.25, 0.17), Vector3(0.35, 0.33, 0.08), black)
			_box(_model, Vector3(0, 0.25, 0.29), Vector3(0.05, 0.05, 0.1), black)
			_box(_model, Vector3(-0.12, 0.46, 0.0), Vector3(0.2, 0.02, 0.28), Color(0.85, 0.93, 1.0))
			_box(_model, Vector3(0.12, 0.46, 0.0), Vector3(0.2, 0.02, 0.28), Color(0.85, 0.93, 1.0))
			_face(0.3, -0.255, black, 0.09)
		"angry_villager":
			_humanoid(Color(0.78, 0.6, 0.47), Color(0.45, 0.3, 0.2), Color(0.3, 0.22, 0.16))
			_box(_model, Vector3(0, 1.6, -0.25), Vector3(0.1, 0.2, 0.1), Color(0.68, 0.5, 0.4))
			_face(1.72, -0.225, Color(0.1, 0.3, 0.1))
			_box(_model, Vector3(0, 1.8, -0.225), Vector3(0.34, 0.05, 0.02), Color(0.6, 0.1, 0.08))
		"wizard_villager":
			var robe := Color(0.42, 0.2, 0.6)
			_humanoid(Color(0.78, 0.6, 0.47), robe, robe.darkened(0.25))
			_box(_model, Vector3(0, 1.6, -0.25), Vector3(0.1, 0.2, 0.1), Color(0.68, 0.5, 0.4))
			_face(1.72, -0.225, Color(0.55, 0.1, 0.7))
			_box(_model, Vector3(0, 1.93, 0), Vector3(0.6, 0.06, 0.6), robe.darkened(0.3))
			_box(_model, Vector3(0, 2.1, 0), Vector3(0.34, 0.3, 0.34), robe.darkened(0.3))
			_box(_model, Vector3(0, 2.33, 0), Vector3(0.18, 0.2, 0.18), robe.darkened(0.3))
		"zombie":
			_humanoid(Color(0.36, 0.56, 0.3), Color(0.15, 0.55, 0.6), Color(0.25, 0.22, 0.5), 1.0, true)
			_face(1.72, -0.225, Color(0.05, 0.05, 0.05))
			_box(_model, Vector3(0, 1.56, -0.225), Vector3(0.2, 0.05, 0.02), Color(0.15, 0.25, 0.12))
		"skeleton":
			var bone := Color(0.85, 0.85, 0.82)
			_humanoid(bone, bone.darkened(0.08), bone.darkened(0.12), 0.5)
			_face(1.72, -0.225, Color(0.1, 0.1, 0.1))
			_box(_model, Vector3(0, 1.57, -0.225), Vector3(0.24, 0.04, 0.02), Color(0.2, 0.2, 0.2))
			for ry: float in [0.95, 1.1, 1.25]:
				_box(_model, Vector3(0, ry, -0.07), Vector3(0.3, 0.04, 0.02), Color(0.3, 0.3, 0.3))
		"creeper":
			var green := Color(0.3, 0.68, 0.26)
			var dark := Color(0.06, 0.1, 0.05)
			for p: Vector2 in [Vector2(-0.15, -0.17), Vector2(0.15, -0.17), Vector2(0.15, 0.17), Vector2(-0.15, 0.17)]:
				_leg(Vector3(p.x, 0.3, p.y), Vector3(0.2, 0.3, 0.2), green.darkened(0.2))
			_box(_model, Vector3(0, 0.7, 0), Vector3(0.46, 0.8, 0.28), green)
			_box(_model, Vector3(0, 1.34, 0), Vector3(0.5, 0.5, 0.5), green.lightened(0.08))
			_face(1.42, -0.255, dark, 0.12)
			_box(_model, Vector3(0, 1.26, -0.255), Vector3(0.12, 0.16, 0.02), dark)
			_box(_model, Vector3(-0.1, 1.2, -0.255), Vector3(0.08, 0.12, 0.02), dark)
			_box(_model, Vector3(0.1, 1.2, -0.255), Vector3(0.08, 0.12, 0.02), dark)
		"pig":
			var pink := Color(0.93, 0.62, 0.62)
			var hc := _quadruped(Vector3(0.56, 0.46, 0.86), 0.3, 0.18, pink, pink.darkened(0.12), Vector3(0.44, 0.42, 0.4), pink, 0.06)
			_box(_model, hc + Vector3(0, -0.07, -0.23), Vector3(0.22, 0.15, 0.08), pink.darkened(0.2))
			_box(_model, hc + Vector3(-0.05, -0.07, -0.275), Vector3(0.04, 0.05, 0.01), Color(0.35, 0.15, 0.15))
			_box(_model, hc + Vector3(0.05, -0.07, -0.275), Vector3(0.04, 0.05, 0.01), Color(0.35, 0.15, 0.15))
		"cow":
			var brown := Color(0.36, 0.24, 0.16)
			var cream := Color(0.92, 0.9, 0.84)
			var hc := _quadruped(Vector3(0.66, 0.6, 1.08), 0.6, 0.2, brown, brown.darkened(0.15), Vector3(0.44, 0.44, 0.38), brown, 0.2)
			_box(_model, Vector3(0.15, 1.21, 0.2), Vector3(0.36, 0.02, 0.4), cream)
			_box(_model, Vector3(-0.335, 0.95, -0.15), Vector3(0.02, 0.3, 0.36), cream)
			_box(_model, Vector3(0.335, 0.85, 0.25), Vector3(0.02, 0.3, 0.3), cream)
			_box(_model, hc + Vector3(0, -0.11, -0.2), Vector3(0.3, 0.2, 0.06), cream)
			_box(_model, hc + Vector3(-0.25, 0.2, 0.05), Vector3(0.07, 0.16, 0.07), Color(0.85, 0.82, 0.75))
			_box(_model, hc + Vector3(0.25, 0.2, 0.05), Vector3(0.07, 0.16, 0.07), Color(0.85, 0.82, 0.75))
			_box(_model, Vector3(0, 0.62, 0.3), Vector3(0.26, 0.1, 0.26), Color(0.93, 0.68, 0.68))
		"sheep":
			var wool := Color(0.93, 0.93, 0.9)
			var face := Color(0.82, 0.7, 0.58)
			var hc := _quadruped(Vector3(0.62, 0.58, 0.92), 0.46, 0.17, wool, face.darkened(0.1), Vector3(0.36, 0.36, 0.36), face, 0.2)
			_box(_model, hc + Vector3(0, 0.12, 0.08), Vector3(0.42, 0.3, 0.3), wool)
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
	var lo := Vector3(position.x - half_w - g, position.y + hover - g, position.z - half_w - g)
	var hi := Vector3(position.x + half_w + g, position.y + hover + height + g, position.z + half_w + g)
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
	provoke(from)
	return false


## Saldırıya uğradı (vuruş sekse bile): pasif mob kaçar, diğerleri oyuncunun peşine düşer.
func provoke(from: Vector3) -> void:
	if def["k"] == "passive":
		_state = "flee"
		_state_time = FLEE_TIME
		_flee_from = from
	else:
		aggro = true


## Kovalamayı bırakır (oyuncu öldüğünde ya da uzaklaştığında).
func calm() -> void:
	aggro = false
	_state = "idle"
	_state_time = randf_range(1.0, 3.0)


# ---------- Döngü ----------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if dead or not world.is_ready_at(position):
		return
	var wish := _think(delta) if ai_enabled else Vector3.ZERO
	var feet := world.get_block(floori(position.x), floori(position.y + 0.2), floori(position.z))
	var in_water := feet == Blocks.WATER
	var k := minf((10.0 if on_ground else 6.0) * delta, 1.0)   # havada da ilerleyebilsin: basamak tırmanma
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
	_avoid_player()
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
		var rot := _legs[i].rotation
		rot[_leg_axis] = (swing if i % 2 == 0 else -swing) * (0.5 if _leg_axis == 1 else 1.0)
		_legs[i].rotation = rot
	_lunge = maxf(_lunge - delta, 0.0)
	_model.position = Vector3(0, hover + (sin(_phase * 0.6) * 0.08 if hover > 0.0 else 0.0), -sin(_lunge / 0.25 * PI) * 0.35)
	if _flash > 0.0:
		_flash -= delta
		var f := clampf(_flash / 0.25, 0.0, 1.0)
		for m: Array in _mats:
			m[0].albedo_color = (m[1] as Color).lerp(Color(1.0, 0.15, 0.1), f * 0.75)


## Oyuncuyla iç içe geçmemek için mobu kenara iter.
func _avoid_player() -> void:
	if player == null:
		return
	var d := Vector3(position.x - player.position.x, 0, position.z - player.position.z)
	var min_d := half_w + 0.38
	if d.length() >= min_d or absf(position.y - player.position.y) > 1.8:
		return
	var push := (d.normalized() if d.length() > 0.01 else Vector3(1, 0, 0)) * (min_d - d.length())
	_move(0, push.x)
	_move(2, push.z)


## Yapay zeka: istenen yatay hızı döndürür.
func _think(delta: float) -> Vector3:
	var speed := float(def["speed"])
	var kind: String = def["k"]
	if kind != "passive" and player != null:
		var to := player.position - position
		var dist := to.length()
		if kind == "active" and not aggro and dist < MobDB.AGGRO_RADIUS:
			aggro = true
		if aggro:
			if dist > float(MobDB.LEASH[kind]):
				calm()   # oyuncu takip mesafesinden çıktı
			else:
				_atk_cd = maxf(_atk_cd - delta, 0.0)
				var flat := Vector3(to.x, 0, to.z)
				var d := flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, -1)
				if flat.length() < half_w + MobDB.ATTACK_RANGE and absf(to.y) < 2.2:
					yaw = lerp_angle(yaw, atan2(-d.x, -d.z), minf(delta * 10.0, 1.0))
					if _atk_cd <= 0.0:
						_atk_cd = MobDB.ATTACK_INTERVAL
						_lunge = 0.25
						hit_player.emit(float(def["atk"]))
					return Vector3.ZERO
				return d * speed
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
			return _dir * speed * (1.0 if kind == "passive" else 0.4)   # kovalamayan mob ağır ağır gezinir
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
