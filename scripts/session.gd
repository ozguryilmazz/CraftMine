extends Node
## Oturum durumu (autoload): oyun modu, sürüm, ayarlar ve yerel dünya kaydı.

const REPO := "ozguryilmazz/CraftMine"
const SAVE_PATH := "user://world.dat"
const SETTINGS_PATH := "user://settings.cfg"

var version := "1.0.0"
var mode := "solo"          # "solo" | "host" | "join"
var world_seed := 0
var room_code := ""
var player_name := "Oyuncu"
var local_id := ""
var touch_mode := false
## Grafik kalitesi: 0 düşük, 1 orta, 2 yüksek. Grafik aşamaları (gölge, parçacık, sallanma) buna bakar.
signal quality_changed
const QUALITY_NAMES := ["Düşük", "Orta", "Yüksek"]
var quality := 1
var show_fps := true
## Tüm arayüzde kullanılan kalın yazı tipi.
var font: Font
## Kalın ve büyük yazılı arayüz teması (menü, duraklatma ekranı, iletişim kutuları).
var theme: Theme

## Yerel dünya (solo/host): { "x_y_z": id } ve son oyuncu konumu.
var world_edits := {}
var saved_pos: Variant = null
var saved_inv: Variant = null
var saved_player := {}


func _ready() -> void:
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.7
	font = bold
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 30
	for type: String in ["Button", "Label", "LineEdit"]:
		theme.set_font("font", type, font)
		theme.set_font_size("font_size", type, 30)
	theme.set_font("title_font", "Window", font)
	theme.set_font_size("title_font_size", "Window", 26)
	get_tree().root.theme = theme
	touch_mode = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()
	var f := FileAccess.open("res://version.json", FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary and j.has("version"):
			version = str(j["version"])
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	player_name = cfg.get_value("player", "name", "Oyuncu%d" % randi_range(100, 999))
	local_id = cfg.get_value("player", "id", "")
	if local_id == "":
		local_id = "p%08x%08x" % [randi(), randi()]
	quality = clampi(int(cfg.get_value("graphics", "quality", 1)), 0, 2)
	show_fps = bool(cfg.get_value("graphics", "fps", true))
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "id", local_id)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fps", show_fps)
	cfg.save(SETTINGS_PATH)


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	save_settings()
	quality_changed.emit()


## Görüş mesafesi (chunk): telefonda 3 / 4 / 5, bilgisayarda 4 / 6 / 8.
func render_distance() -> int:
	var table: Array = [3, 4, 5] if OS.has_feature("mobile") else [4, 6, 8]
	return table[quality]


func has_saved_world() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Kayıtlı dünyayı yükler; yoksa yeni bir tohumla başlatır.
func load_world() -> void:
	world_edits = {}
	saved_pos = null
	saved_inv = null
	saved_player = {}
	world_seed = randi() & 0x7fffffff
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = f.get_var()
	if d is Dictionary and d.has("seed"):
		world_seed = int(d["seed"])
		world_edits = d.get("edits", {})
		saved_pos = d.get("pos")
		saved_inv = d.get("inv")
		var pl: Variant = d.get("player")
		if pl is Dictionary:
			saved_player = pl


func save_world(edits: Dictionary, pos: Vector3, inv: Array, player := {}) -> void:
	world_edits = edits
	saved_pos = pos
	saved_inv = inv
	saved_player = player
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var({"v": 2, "seed": world_seed, "edits": edits, "pos": pos, "inv": inv, "player": player})


func delete_world() -> void:
	if has_saved_world():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
