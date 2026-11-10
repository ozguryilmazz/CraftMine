extends Node
## Geliştirme aracı: Firebase bağlantısını uçtan uca dener (oda kur -> blok yaz -> akıştan geri al -> odayı sil).
## Kullanım: godot --headless --path . res://tests/net_test.tscn

func _ready() -> void:
	Net.failed.connect(func(m: String) -> void:
		print("BASARISIZ: ", m)
		get_tree().quit(1))
	Net.block_update.connect(func(pos: Vector3i, id: int) -> void:
		print("AKISTAN BLOK GELDI: ", pos, " = ", id)
		Net.leave()
		await get_tree().create_timer(3.0).timeout
		print("TAMAM")
		get_tree().quit(0))
	Net.blocks_bulk.connect(func(b: Dictionary) -> void: print("ILK DURUM: ", b))
	Net.room_created.connect(func(code: String) -> void:
		print("ODA KURULDU: ", code, " uid=", Net.uid)
		Net.send_block(Vector3i(1, 30, -2), Blocks.STONE))
	Net.host(12345, {"0_30_0": Blocks.PLANKS}, "Test")
	await get_tree().create_timer(30.0).timeout
	print("ZAMAN ASIMI")
	get_tree().quit(2)
