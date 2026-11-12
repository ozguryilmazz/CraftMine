class_name World
extends Node3D
## Sonsuz chunk dünyası: oyuncunun çevresindeki chunk'ları arka planda üretir, mesh'ler ve uzaklaşınca boşaltır.

signal block_changed(pos: Vector3i, id: int)

const CW := 16
const CH := 64

class Chunk:
	var data := PackedByteArray()
	var node: MeshInstance3D
	var generating := false
	var meshing := false
	var dirty := true
	var version := 0
	var meshed := false

var gen: WorldGen
var render_distance := 5
var center := Vector2i.ZERO

var _chunks := {}          # Vector2i -> Chunk
var _edits := {}           # Vector2i -> { index: id }  (üretilen arazinin üzerine yazılan değişiklikler)
var _order: Array[Vector2i] = []
var _results := []
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var _gen_pending := 0
var _mesh_pending := 0
var _frame := 0
var _mat_opaque: StandardMaterial3D
var _mat_water: StandardMaterial3D


func setup(p_seed: int, p_render_distance: int) -> void:
	gen = WorldGen.new(p_seed)
	ChunkMesher.init_tables()
	_mat_opaque = Atlas.block_material()
	_mat_water = Atlas.water_material()
	set_render_distance(p_render_distance)


## Görüş mesafesini çalışırken değiştirir; uzakta kalan chunk'lar _unload_far ile boşalır.
func set_render_distance(p_render_distance: int) -> void:
	render_distance = p_render_distance
	_order.clear()
	var r := render_distance + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_order.append(Vector2i(dx, dz))
	_order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	# Mesafe küçüldüyse dışarıda kalan mesh'ler hemen kaldırılır (veri durur; yaklaşınca yeniden kurulur).
	for key: Vector2i in _chunks.keys():
		var ch: Chunk = _chunks[key]
		if ch.node != null and maxi(absi(key.x - center.x), absi(key.y - center.y)) > render_distance + 1:
			ch.node.queue_free()
			ch.node = null
			ch.dirty = true


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


func set_center_from(pos: Vector3) -> void:
	center = Vector2i(floori(pos.x / CW), floori(pos.z / CW))


func _process(_delta: float) -> void:
	if gen == null:
		return
	_frame += 1
	_collect_tasks()
	_apply_results()
	_schedule()
	if _frame % 30 == 0:
		_unload_far()


# ---------- Arka plan işleri ----------

func _collect_tasks() -> void:
	var i := _tasks.size() - 1
	while i >= 0:
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
		i -= 1


func _schedule() -> void:
	for off in _order:
		if _gen_pending >= 3 and _mesh_pending >= 2:
			return
		var key := center + off
		var ch: Chunk = _chunks.get(key)
		if ch == null:
			ch = Chunk.new()
			_chunks[key] = ch
		if ch.data.is_empty():
			if not ch.generating and _gen_pending < 3:
				ch.generating = true
				_gen_pending += 1
				_tasks.append(WorkerThreadPool.add_task(_gen_task.bind(key)))
			continue
		if not ch.dirty or ch.meshing or _mesh_pending >= 2:
			continue
		if maxi(absi(off.x), absi(off.y)) > render_distance:
			continue
		var xm: Chunk = _chunks.get(key + Vector2i(-1, 0))
		var xp: Chunk = _chunks.get(key + Vector2i(1, 0))
		var zm: Chunk = _chunks.get(key + Vector2i(0, -1))
		var zp: Chunk = _chunks.get(key + Vector2i(0, 1))
		if xm == null or xp == null or zm == null or zp == null:
			continue
		if xm.data.is_empty() or xp.data.is_empty() or zm.data.is_empty() or zp.data.is_empty():
			continue
		ch.dirty = false
		ch.meshing = true
		_mesh_pending += 1
		_tasks.append(WorkerThreadPool.add_task(_mesh_task.bind(key, ch.version, ch.data, xm.data, xp.data, zm.data, zp.data)))


func _gen_task(key: Vector2i) -> void:
	var data := gen.generate(key.x, key.y)
	_mutex.lock()
	_results.append({"gen": true, "key": key, "data": data})
	_mutex.unlock()


func _mesh_task(key: Vector2i, version: int, d: PackedByteArray, xm: PackedByteArray, xp: PackedByteArray, zm: PackedByteArray, zp: PackedByteArray) -> void:
	var mesh := ChunkMesher.build(d, xm, xp, zm, zp)
	_mutex.lock()
	_results.append({"gen": false, "key": key, "version": version, "mesh": mesh})
	_mutex.unlock()


func _apply_results() -> void:
	_mutex.lock()
	var results := _results
	_results = []
	_mutex.unlock()
	for r: Dictionary in results:
		var key: Vector2i = r["key"]
		var ch: Chunk = _chunks.get(key)
		if r["gen"]:
			_gen_pending -= 1
			if ch == null:
				continue
			ch.generating = false
			ch.data = r["data"]
			var ed: Dictionary = _edits.get(key, {})
			for idx: int in ed:
				ch.data[idx] = ed[idx]
			ch.dirty = true
		else:
			_mesh_pending -= 1
			if ch == null:
				continue
			ch.meshing = false
			if r["version"] != ch.version:
				ch.dirty = true
				continue
			_apply_mesh(key, ch, r["mesh"])


func _apply_mesh(key: Vector2i, ch: Chunk, m: Dictionary) -> void:
	if ch.node == null:
		ch.node = MeshInstance3D.new()
		ch.node.position = Vector3(key.x * CW, 0, key.y * CW)
		add_child(ch.node)
	for c in ch.node.get_children():
		c.queue_free()
	var mesh := ArrayMesh.new()
	var ob: ChunkMesher.Buf = m["o"]
	var wb: ChunkMesher.Buf = m["w"]
	if ob.v.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ob.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_opaque)
	if wb.v.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wb.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_water)
	ch.node.mesh = mesh
	ch.meshed = true
	var torches: PackedVector3Array = m["t"]
	for i in mini(torches.size(), 8):
		var l := OmniLight3D.new()
		l.position = torches[i]
		l.light_color = Color(1.0, 0.78, 0.45)
		l.light_energy = 2.0
		l.omni_range = 10.0
		l.omni_attenuation = 1.2
		ch.node.add_child(l)


func _unload_far() -> void:
	var limit := render_distance + 3
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) <= limit:
			continue
		var ch: Chunk = _chunks[key]
		if ch.generating or ch.meshing:
			continue
		if ch.node != null:
			ch.node.queue_free()
		_chunks.erase(key)


# ---------- Blok erişimi ----------

## Chunk yüklü değilse -1 döner.
func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= CH:
		return Blocks.AIR
	var ch: Chunk = _chunks.get(Vector2i(floori(x / 16.0), floori(z / 16.0)))
	if ch == null or ch.data.is_empty():
		return -1
	return ch.data[y * 256 + posmod(z, CW) * CW + posmod(x, CW)]


func is_solid(x: int, y: int, z: int) -> bool:
	var id := get_block(x, y, z)
	return id == -1 or Blocks.is_solid(id)


## Oyuncunun bulunduğu chunk hazır ve çizilmiş mi?
func is_ready_at(pos: Vector3) -> bool:
	var ch: Chunk = _chunks.get(Vector2i(floori(pos.x / CW), floori(pos.z / CW)))
	return ch != null and ch.meshed


func set_block(p: Vector3i, id: int, from_net := false) -> void:
	if p.y < 0 or p.y >= CH:
		return
	var key := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	var lx := posmod(p.x, CW)
	var lz := posmod(p.z, CW)
	var idx := p.y * 256 + lz * CW + lx
	if not _edits.has(key):
		_edits[key] = {}
	_edits[key][idx] = id
	var ch: Chunk = _chunks.get(key)
	if ch != null and not ch.data.is_empty() and ch.data[idx] != id:
		ch.data[idx] = id
		_touch(key)
		if lx == 0:
			_touch(key + Vector2i(-1, 0))
		elif lx == CW - 1:
			_touch(key + Vector2i(1, 0))
		if lz == 0:
			_touch(key + Vector2i(0, -1))
		elif lz == CW - 1:
			_touch(key + Vector2i(0, 1))
	if not from_net:
		block_changed.emit(p, id)


func _touch(key: Vector2i) -> void:
	var ch: Chunk = _chunks.get(key)
	if ch != null:
		ch.version += 1
		ch.dirty = true


## Işın izleme (voxel DDA). İsabet yoksa boş sözlük döner.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var p := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(1 if dir.x > 0 else -1, 1 if dir.y > 0 else -1, 1 if dir.z > 0 else -1)
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if absf(dir[a]) < 1e-7:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var edge := float(p[a] + (1 if dir[a] > 0 else 0))
			t_max[a] = (edge - origin[a]) / dir[a]
			t_delta[a] = absf(1.0 / dir[a])
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var id := get_block(p.x, p.y, p.z)
		if id > 0 and id != Blocks.WATER:
			# Meşale hücrenin tamamını kaplamaz: yalnızca çubuğun çevresine isabet sayılır.
			if id != Blocks.TORCH or _hits_box(origin, dir, Vector3(p) + Vector3(0.3, 0.0, 0.3), Vector3(p) + Vector3(0.7, 0.75, 0.7)):
				return {"pos": p, "normal": normal, "id": id, "dist": t}
		var a := 0
		if t_max.y < t_max.x and t_max.y <= t_max.z:
			a = 1
		elif t_max.z < t_max.x and t_max.z < t_max.y:
			a = 2
		t = t_max[a]
		t_max[a] += t_delta[a]
		p[a] += step[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	return {}


## Işın, verilen kutuyla kesişiyor mu? (slab yöntemi)
func _hits_box(origin: Vector3, dir: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var t0 := 0.0
	var t1 := INF
	for a in 3:
		if absf(dir[a]) < 1e-7:
			if origin[a] < lo[a] or origin[a] > hi[a]:
				return false
		else:
			var ta := (lo[a] - origin[a]) / dir[a]
			var tb := (hi[a] - origin[a]) / dir[a]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


# ---------- Kayıt / ağ için değişiklik dökümü ----------

## { "x_y_z": id }
func export_edits() -> Dictionary:
	var out := {}
	for key: Vector2i in _edits:
		var ed: Dictionary = _edits[key]
		for idx: int in ed:
			var y := idx >> 8
			var z := (idx >> 4) & 15
			var x := idx & 15
			out["%d_%d_%d" % [key.x * CW + x, y, key.y * CW + z]] = ed[idx]
	return out


func import_edits(d: Dictionary) -> void:
	for k: String in d:
		var p: Variant = Blocks.parse_key(k)
		var id := int(d[k])
		if p != null and id >= 0 and id < Blocks.COUNT:
			set_block(p, id, true)
