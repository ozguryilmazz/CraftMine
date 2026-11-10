extends Control
## Ana menü: tek oyunculu, sunucu kur (host), oda koduyla katıl, güncelleme kontrolü.

const GAME_SCENE := "res://scenes/game.tscn"

var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _updater: Updater
var _manual_check := false
var _update_dialog: ConfirmationDialog
var _new_world_dialog: ConfirmationDialog
var _update_url := ""


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.6, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.3, 0.55, 0.22)
	ground.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ground.offset_top = -90
	add_child(ground)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "CraftMine"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)

	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "İsim:"
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = Session.player_name
	_name_edit.max_length = 16
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = 52
	name_row.add_child(_name_edit)

	_button(box, "Tek Oyunculu", _on_solo)
	_button(box, "Sunucu Kur (Host)", _on_host)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Oda kodu"
	_code_edit.max_length = 4
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code_edit.custom_minimum_size = Vector2(190, 60)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	join_row.add_child(_code_edit)
	var join := _button(join_row, "Oyuna Katıl", _on_join)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_button(box, "Yeni Dünya", _on_new_world)
	_button(box, "Güncelleme Kontrolü", _on_check_update)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 64)
	_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_status)

	var ver := Label.new()
	ver.text = "v" + Session.version
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -130
	ver.offset_top = -44
	ver.add_theme_font_size_override("font_size", 20)
	add_child(ver)

	_update_dialog = ConfirmationDialog.new()
	_update_dialog.title = "Güncelleme"
	_update_dialog.ok_button_text = "İndir"
	_update_dialog.cancel_button_text = "Sonra"
	_update_dialog.confirmed.connect(func() -> void: OS.shell_open(_update_url))
	add_child(_update_dialog)
	_new_world_dialog = ConfirmationDialog.new()
	_new_world_dialog.title = "Yeni Dünya"
	_new_world_dialog.dialog_text = "Kayıtlı dünyanız silinip yeni bir dünya oluşturulacak. Emin misiniz?"
	_new_world_dialog.ok_button_text = "Sil ve Başla"
	_new_world_dialog.cancel_button_text = "Vazgeç"
	_new_world_dialog.confirmed.connect(func() -> void:
		Session.delete_world()
		_on_solo())
	add_child(_new_world_dialog)

	_updater = Updater.new()
	add_child(_updater)
	_updater.finished.connect(_on_update_result)
	Net.room_created.connect(_on_room_created)
	Net.joined.connect(_on_joined)
	Net.failed.connect(_on_failed)
	if DisplayServer.get_name() != "headless":
		_updater.check()   # açılışta sessiz kontrol


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons.append(b)
	return b


func _set_busy(busy: bool, text := "") -> void:
	for b in _buttons:
		b.disabled = busy
	_status.text = text


func _commit_name() -> String:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Oyuncu"
	Session.player_name = n
	Session.save_settings()
	return n


func _on_solo() -> void:
	_commit_name()
	Session.mode = "solo"
	Session.room_code = ""
	Session.load_world()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_new_world() -> void:
	if Session.has_saved_world():
		_new_world_dialog.popup_centered()
	else:
		_on_solo()


func _on_host() -> void:
	var n := _commit_name()
	Session.load_world()
	_set_busy(true, "Oda kuruluyor...")
	Net.host(Session.world_seed, Session.world_edits, n)


func _on_room_created(code: String) -> void:
	Session.mode = "host"
	Session.room_code = code
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_join() -> void:
	var code := _code_edit.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		_status.text = "Lütfen 4 haneli oda kodunu girin."
		return
	var n := _commit_name()
	_set_busy(true, "Odaya bağlanılıyor...")
	Net.join(code, n)


func _on_joined(world_seed: int) -> void:
	Session.mode = "join"
	Session.room_code = _code_edit.text.strip_edges()
	Session.world_seed = world_seed
	Session.world_edits = {}
	Session.saved_pos = null
	Session.saved_inv = null
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_failed(message: String) -> void:
	_set_busy(false, message)


func _on_check_update() -> void:
	_manual_check = true
	_status.text = "Güncelleme kontrol ediliyor..."
	_updater.check()


func _on_update_result(r: Dictionary) -> void:
	var manual := _manual_check
	_manual_check = false
	if not r.get("ok", false):
		if manual:
			_status.text = str(r.get("error", "Güncelleme kontrol edilemedi."))
		return
	if r["newer"]:
		_update_url = r["url"]
		_update_dialog.dialog_text = "Yeni sürüm mevcut: v%s\n(Yüklü sürüm: v%s)\n\nAPK indirme sayfası açılsın mı?" % [r["latest"], Session.version]
		_update_dialog.popup_centered()
		if manual:
			_status.text = ""
	elif manual:
		_status.text = "Oyun güncel (v%s)." % Session.version
