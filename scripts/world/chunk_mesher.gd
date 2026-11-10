class_name ChunkMesher
## Bir chunk'ın blok verisinden görünür yüzleri çıkarır. İş parçacığında (thread) çalışır.

const CW := 16
const CH := 64

class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		return a

# Yüz sırası: +x, -x, +y, -y, +z, -z
static var _corners := PackedVector3Array()
static var _uvs := PackedVector2Array()
static var _flip := PackedByteArray()
static var _normals := PackedVector3Array()
static var _shade := PackedColorArray()
static var _opaque := PackedByteArray()
static var _tiles := PackedByteArray()
static var _ready := false
static var _block_meshes := {}


## Ana iş parçacığında, ilk kullanımdan önce bir kez çağrılmalı.
static func init_tables() -> void:
	if _ready:
		return
	_ready = true
	var x := Vector3(1, 0, 0)
	var y := Vector3(0, 1, 0)
	var z := Vector3(0, 0, 1)
	var ns := [x, -x, y, -y, z, -z]
	var us := [z, z, x, x, x, x]
	var vs := [y, y, z, z, y, y]
	var sh := [0.8, 0.8, 1.0, 0.5, 0.65, 0.65]
	var ab := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for f in 6:
		var n: Vector3 = ns[f]
		var base := Vector3(maxf(n.x, 0), maxf(n.y, 0), maxf(n.z, 0))
		var cs := []
		for k in 4:
			var c: Vector3 = base + us[f] * ab[k].x + vs[f] * ab[k].y
			cs.append(c)
			_corners.append(c)
			_uvs.append(Vector2(ab[k].x, 1.0 - ab[k].y))
		# Godot'ta ön yüz saat yönündedir; sarım yanlışsa indeksleri çevir.
		var facing: float = (cs[2] - cs[0]).cross(cs[1] - cs[0]).dot(n)
		_flip.append(1 if facing < 0.0 else 0)
		_normals.append(n)
		_shade.append(Color(sh[f], sh[f], sh[f]))
	for id in Blocks.COUNT:
		_opaque.append(1 if Blocks.is_solid(id) else 0)
		for t in 3:
			_tiles.append(Blocks.TILES[id][t])


static func build(d: PackedByteArray, xm: PackedByteArray, xp: PackedByteArray, zm: PackedByteArray, zp: PackedByteArray) -> Dictionary:
	var ob := Buf.new()
	var wb := Buf.new()
	var torches := PackedVector3Array()
	var water_id := Blocks.WATER
	var torch_id := Blocks.TORCH
	var idx := -1
	for y in CH:
		for z in CW:
			for x in CW:
				idx += 1
				var id := d[idx]
				if id == 0:
					continue
				if id == torch_id:
					_torch(ob, x, y, z)
					torches.append(Vector3(x + 0.5, y + 0.75, z + 0.5))
					continue
				var water := id == water_id
				var top := 1.0
				if water and (y == CH - 1 or d[idx + 256] != water_id):
					top = 0.875
				var b := wb if water else ob
				for f in 6:
					var nid := 0
					if f == 0:
						nid = d[idx + 1] if x < 15 else xp[idx - 15]
					elif f == 1:
						nid = d[idx - 1] if x > 0 else xm[idx + 15]
					elif f == 2:
						nid = d[idx + 256] if y < CH - 1 else 0
					elif f == 3:
						nid = d[idx - 256] if y > 0 else Blocks.BEDROCK
					elif f == 4:
						nid = d[idx + 16] if z < 15 else zp[idx - 240]
					else:
						nid = d[idx - 16] if z > 0 else zm[idx + 240]
					if _opaque[nid] == 1 or (water and nid == water_id):
						continue
					var tile := _tiles[id * 3 + (0 if f == 2 else (2 if f == 3 else 1))]
					var tu := (tile & 7) * 0.125
					var tv := (tile >> 3) * 0.125
					var n0 := b.v.size()
					var nrm := _normals[f]
					var col := _shade[f]
					for k in 4:
						var c := _corners[f * 4 + k]
						var u := _uvs[f * 4 + k]
						b.v.append(Vector3(x + c.x, y + c.y * top, z + c.z))
						b.n.append(nrm)
						b.c.append(col)
						b.uv.append(Vector2(tu + (0.01 + u.x * 0.98) * 0.125, tv + (0.01 + u.y * 0.98) * 0.125))
					_quad(b, n0, _flip[f] == 1)
	return {"o": ob, "w": wb, "t": torches}


## Tek bir bloğun merkezlenmiş (kenarı 1 birim) küp mesh'i: düşen eşyalar ve elde tutulan blok için.
static func block_mesh(id: int) -> ArrayMesh:
	if _block_meshes.has(id):
		return _block_meshes[id]
	init_tables()
	var b := Buf.new()
	for f in 6:
		var tile := _tiles[id * 3 + (0 if f == 2 else (2 if f == 3 else 1))]
		var tu := (tile & 7) * 0.125
		var tv := (tile >> 3) * 0.125
		var n0 := b.v.size()
		for k in 4:
			var u := _uvs[f * 4 + k]
			b.v.append(_corners[f * 4 + k] - Vector3(0.5, 0.5, 0.5))
			b.n.append(_normals[f])
			b.c.append(_shade[f])
			b.uv.append(Vector2(tu + (0.01 + u.x * 0.98) * 0.125, tv + (0.01 + u.y * 0.98) * 0.125))
		_quad(b, n0, _flip[f] == 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	_block_meshes[id] = mesh
	return mesh


static func _quad(b: Buf, n0: int, flip: bool) -> void:
	if flip:
		b.i.append(n0); b.i.append(n0 + 2); b.i.append(n0 + 1)
		b.i.append(n0); b.i.append(n0 + 3); b.i.append(n0 + 2)
	else:
		b.i.append(n0); b.i.append(n0 + 1); b.i.append(n0 + 2)
		b.i.append(n0); b.i.append(n0 + 2); b.i.append(n0 + 3)


## Meşale: hücrenin ortasında ince bir çubuk.
static func _torch(b: Buf, x: int, y: int, z: int) -> void:
	var mn := Vector3(0.4375, 0.0, 0.4375)
	var sz := Vector3(0.125, 0.625, 0.125)
	var tu := 0.0   # karo 8 -> sütun 0, satır 1
	var tv := 0.125
	for f in 6:
		var n0 := b.v.size()
		var py0 := 6.1
		var py1 := 15.9
		if f == 2:
			py1 = 7.9
		elif f == 3:
			py0 = 14.1
		for k in 4:
			var c := _corners[f * 4 + k]
			var u := _uvs[f * 4 + k]
			b.v.append(Vector3(x, y, z) + mn + c * sz)
			b.n.append(_normals[f])
			b.c.append(Color(1.3, 1.3, 1.3))
			b.uv.append(Vector2(tu + (7.1 + u.x * 1.8) / 128.0, tv + (py0 + u.y * (py1 - py0)) / 128.0))
		_quad(b, n0, _flip[f] == 1)
