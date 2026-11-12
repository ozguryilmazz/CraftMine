class_name PlayerModel
extends Node3D
## Kutulardan oluşan basit oyuncu modeli (3. şahıs görünümü ve diğer oyuncular için).

var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D
var _label: Label3D
var _phase := 0.0
var _swing := 0.0

## Diğer oyuncular için ağdan gelen hedef durum.
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var last_update := 0.0


const SHIRT := Color(0.2, 0.55, 0.75)


func _init(shirt := SHIRT) -> void:
	var skin := Color(0.87, 0.68, 0.53)
	var pants := Color(0.2, 0.22, 0.5)
	_leg_l = _limb(Vector3(-0.13, 0.75, 0), Vector3(0.24, 0.75, 0.24), pants)
	_leg_r = _limb(Vector3(0.13, 0.75, 0), Vector3(0.24, 0.75, 0.24), pants)
	_arm_l = _limb(Vector3(-0.38, 1.45, 0), Vector3(0.22, 0.7, 0.22), skin)
	_arm_r = _limb(Vector3(0.38, 1.45, 0), Vector3(0.22, 0.7, 0.22), skin)
	# Tişört kolları: kolların üst kısmını saran, biraz daha kalın kutular
	for arm: Node3D in [_arm_l, _arm_r]:
		_box(arm, Vector3(0, -0.14, 0), Vector3(0.25, 0.3, 0.25), shirt)
	_box(self, Vector3(0, 1.1, 0), Vector3(0.52, 0.7, 0.26), shirt)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.45, 0)
	add_child(_head)
	_box(_head, Vector3(0, 0.22, 0), Vector3(0.44, 0.44, 0.44), skin)
	_box(_head, Vector3(0, 0.26, -0.225), Vector3(0.3, 0.08, 0.02), Color(0.15, 0.1, 0.1))
	_label = Label3D.new()
	_label.position = Vector3(0, 2.2, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.008
	_label.font_size = 40
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)


func set_player_name(n: String) -> void:
	_label.text = n
	_label.visible = n != ""


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
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
	return mi


## Üst ucundan dönen uzuv (kol/bacak).
func _limb(pivot: Vector3, size: Vector3, color: Color) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	add_child(n)
	_box(n, Vector3(0, -size.y * 0.5, 0), size, color)
	return n


## Yürüme animasyonu. speed: yatay hız (blok/sn).
func animate(delta: float, speed: float, pitch: float, swing := 0.0) -> void:
	_swing = lerpf(_swing, clampf(speed / 4.5, 0.0, 1.0), minf(delta * 10.0, 1.0))
	_phase += delta * 9.0
	var a := sin(_phase) * 0.8 * _swing
	_leg_l.rotation.x = a
	_leg_r.rotation.x = -a
	_arm_l.rotation.x = -a
	_arm_r.rotation.x = a + swing   # swing: kırma/yerleştirme sırasında sağ kolu öne kaldırır
	_head.rotation.x = pitch


## Ağdan gelen hedefe doğru yumuşak geçiş (diğer oyuncular).
func follow(delta: float) -> void:
	var k := minf(delta * 12.0, 1.0)
	var before := position
	if position.distance_to(target_pos) > 12.0:
		position = target_pos
	else:
		position = position.lerp(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	animate(delta, moved / maxf(delta, 0.001), target_pitch)
