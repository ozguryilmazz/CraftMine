class_name Updater
extends Node
## Güncelleme kontrolü: GitHub Releases'teki en son sürümü okur, olmazsa depodaki version.json'a bakar.

## result: { ok: bool, newer: bool, latest: String, url: String, error: String }
signal finished(result: Dictionary)

const API_URL := "https://api.github.com/repos/%s/releases/latest"
const RAW_URL := "https://raw.githubusercontent.com/%s/main/version.json"
const RELEASES_URL := "https://github.com/%s/releases/latest"

var _req: HTTPRequest
var _stage := 0
var busy := false


func _ready() -> void:
	_req = HTTPRequest.new()
	_req.timeout = 12.0
	add_child(_req)
	_req.request_completed.connect(_on_done)


func check() -> void:
	if busy:
		return
	busy = true
	_stage = 0
	var headers := ["User-Agent: CraftMine-Game", "Accept: application/vnd.github+json"]
	if _req.request(API_URL % Session.REPO, headers) != OK:
		_fallback()


func _fallback() -> void:
	_stage = 1
	if _req.request(RAW_URL % Session.REPO, ["User-Agent: CraftMine-Game"]) != OK:
		_finish({"ok": false, "error": "İstek gönderilemedi."})


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var j: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		j = JSON.parse_string(body.get_string_from_utf8())
	if _stage == 0:
		if j is Dictionary and j.has("tag_name"):
			var url := str(j.get("html_url", RELEASES_URL % Session.REPO))
			for a: Variant in j.get("assets", []):
				if a is Dictionary and str(a.get("name", "")).ends_with(".apk"):
					url = str(a.get("browser_download_url", url))   # doğrudan APK indirme bağlantısı
					break
			_report(str(j["tag_name"]), url)
		else:
			_fallback()   # henüz release yok veya API sınırı aşıldı
	elif j is Dictionary and j.has("version"):
		_report(str(j["version"]), RELEASES_URL % Session.REPO)
	else:
		_finish({"ok": false, "error": "Sürüm bilgisi alınamadı. İnternet bağlantınızı kontrol edin."})


func _report(latest: String, url: String) -> void:
	latest = latest.trim_prefix("v")
	_finish({"ok": true, "latest": latest, "url": url, "newer": is_newer(latest, Session.version)})


func _finish(r: Dictionary) -> void:
	busy = false
	finished.emit(r)


## "1.2.0" > "1.1.9" gibi anlamsal sürüm karşılaştırması.
static func is_newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false
