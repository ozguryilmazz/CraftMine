class_name LootChest
extends Node3D
## Mob ölünce yere düşen ganimet sandığı. 10 saniye içinde toplanmazsa içindekilerle birlikte yok olur.

const LIFETIME := 10.0
const HALF := 0.25

var items := []            # [[eşya, adet, dayanıklılık], ...]
var age := 0.0
var expired := false
var world: World
var _vel := Vector3(0, 3.5, 0)
var _model: Node3D
var _label: Label3D


func setup(p_world: World, pos: Vector3, p_items: Array) -> void:
	world = p_world
	position = pos
	items = p_items
	_model = Node3D.new()
	add_child(_model)
	var wood := Color(0.55, 0.36, 0.16)
	_box(Vector3(0, 0.16, 0), Vector3(0.5, 0.32, 0.4), wood)
	_box(Vector3(0, 0.37, 0), Vector3(0.54, 0.12, 0.44), wood.darkened(0.25))
	_box(Vector3(0, 0.3, 0.205), Vector3(0.1, 0.14, 0.03), Color(0.98, 0.82, 0.22))
	_box(Vector3(-0.2, 0.2, 0), Vector3(0.06, 0.46, 0.42), Color(0.3, 0.3, 0.32))
	_box(Vector3(0.2, 0.2, 0), Vector3(0.06, 0.46, 0.42), Color(0.3, 0.3, 0.32))
	_label = Label3D.new()
	_label.position = Vector3(0, 0.75, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.font = Session.font
	_label.font_size = 44
	_label.outline_size = 12
	_label.no_depth_test = true
	add_child(_label)


func _box(pos: Vector3, size: Vector3, color: Color) -> void:
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
	_model.add_child(mi)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	age += delta
	if age >= LIFETIME:
		expired = true
		queue_free()
		return
	var left := LIFETIME - age
	_label.text = str(ceili(left))
	_label.modulate = Color(1.0, 0.4, 0.3) if left <= 3.0 else Color(1.0, 0.95, 0.6)
	# Son 3 saniyede yanıp söner
	_model.visible = left > 3.0 or fmod(left, 0.4) > 0.15
	_model.rotation.y += delta * 1.2
	_vel.y = maxf(_vel.y - 22.0 * delta, -30.0)
	var ny := position.y + _vel.y * delta
	if _vel.y <= 0.0 and world.is_solid(floori(position.x), floori(ny), floori(position.z)):
		ny = floorf(ny) + 1.0
		_vel.y = 0.0
	position.y = ny
