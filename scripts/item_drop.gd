class_name ItemDrop
extends Node3D
## Yere düşmüş eşya: bloklar minyatür küp, diğer eşyalar düz simge olarak görünür;
## yerde döner, oyuncu yaklaşınca ona doğru çekilir.

const LIFETIME := 300.0
const PICKUP_DELAY := 0.5
const HALF := 0.14

var item_id := 0
var count := 1
var age := 0.0
var world: World
var _vel := Vector3.ZERO
var _vis: MeshInstance3D


## Bir eşyanın 3B görseli (düşen eşya ve elde tutulan eşya için ortak).
static func make_visual(id: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if Items.is_block(id) and id != Blocks.TORCH:
		mi.mesh = ChunkMesher.block_mesh(id)
		mi.material_override = Atlas.block_material()
	else:
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.6) if id != Blocks.TORCH else Vector2(0.9, 1.6)
		mi.mesh = q
		mi.material_override = Atlas.flat_material(id)
	return mi


func setup(p_world: World, id: int, n: int, pos: Vector3) -> void:
	world = p_world
	item_id = id
	count = n
	position = pos
	_vel = Vector3(randf_range(-1.2, 1.2), 3.0, randf_range(-1.2, 1.2))
	_vis = make_visual(id)
	_vis.scale = Vector3.ONE * 0.26
	add_child(_vis)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	age += delta
	if age > LIFETIME:
		queue_free()
		return
	_vel.y = maxf(_vel.y - 22.0 * delta, -30.0)
	var p := position
	var nx := p.x + _vel.x * delta
	if world.is_solid(floori(nx), floori(p.y), floori(p.z)):
		_vel.x = 0.0
	else:
		p.x = nx
	var nz := p.z + _vel.z * delta
	if world.is_solid(floori(p.x), floori(p.y), floori(nz)):
		_vel.z = 0.0
	else:
		p.z = nz
	var ny := p.y + _vel.y * delta
	if _vel.y <= 0.0 and world.is_solid(floori(p.x), floori(ny - HALF), floori(p.z)):
		ny = floorf(ny - HALF) + 1.0 + HALF
		_vel.y = 0.0
		_vel.x = lerpf(_vel.x, 0.0, minf(delta * 8.0, 1.0))
		_vel.z = lerpf(_vel.z, 0.0, minf(delta * 8.0, 1.0))
	elif _vel.y > 0.0 and world.is_solid(floori(p.x), floori(ny + HALF), floori(p.z)):
		ny = p.y
		_vel.y = 0.0
	p.y = ny
	position = p
	_vis.rotation.y += delta * 1.8
	_vis.position.y = 0.08 + sin(age * 2.5) * 0.05


## Oyuncuya doğru çekilir.
func attract(target: Vector3, delta: float) -> void:
	position = position.move_toward(target, delta * 9.0)
	_vel = Vector3.ZERO
