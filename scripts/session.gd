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
## Tüm arayüzde kullanılan kalın yazı tipi.
var font: Font
## Kalın ve büyük yazılı arayüz teması (menü, duraklatma ekranı, iletişim kutuları).
var theme: Theme

## Yerel dünya (solo/host): { "x_y_z": id } ve son oyuncu konumu.
var world_edits := {}
var saved_pos: Variant = null
var saved_inv: Variant = null


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
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "id", local_id)
	cfg.save(SETTINGS_PATH)


func has_saved_world() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Kayıtlı dünyayı yükler; yoksa yeni bir tohumla başlatır.
func load_world() -> void:
	world_edits = {}
	saved_pos = null
	saved_inv = null
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


func save_world(edits: Dictionary, pos: Vector3, inv: Array) -> void:
	world_edits = edits
	saved_pos = pos
	saved_inv = inv
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var({"seed": world_seed, "edits": edits, "pos": pos, "inv": inv})


func delete_world() -> void:
	if has_saved_world():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
