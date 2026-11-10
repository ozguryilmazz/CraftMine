extends Node
## Çok oyunculu bağlantı yöneticisi (autoload "Net").
##
## Firebase Realtime Database relay olarak kullanılır:
##   rooms/<4 haneli kod>/meta            -> { host, seed, proto, alive }
##   rooms/<kod>/players/<uid>            -> { n: ad, p: [x, y, z, yaw, pitch] }
##   rooms/<kod>/blocks/<"x_y_z">         -> blok kimliği (arazinin üzerine yazılan değişiklik)
## Yazmalar REST ile, okumalar tek bir canlı akış (SSE) ile yapılır. Blok değişiklikleri "durum"
## olarak tutulduğu için sonradan katılan oyuncu da dünyanın güncel halini alır.

signal room_created(code: String)
signal joined(world_seed: int)
signal failed(message: String)
signal player_update(uid: String, pname: String, p: Variant)
signal player_left(uid: String)
signal block_update(pos: Vector3i, id: int)
signal blocks_bulk(blocks: Dictionary)
signal room_closed(reason: String)

## Dünya üretimi veya veri biçimi değiştiğinde artırılır; farklı sürümler aynı odaya giremez.
const PROTO := 2
const POS_INTERVAL := 0.1
const ALIVE_INTERVAL := 60.0
const STALE_MS := 11 * 60 * 1000.0
const AUTH_PATH := "user://auth.cfg"
const MSG_DENIED := "Firebase erişimi reddedildi. API anahtarını firebase_config.gd dosyasına ekleyin ve veritabanı kurallarını yayınlayın."

var active := false
var is_host := false
var code := ""
var uid := ""

var _http: HttpQueue
var _sse := SseStream.new()
var _token := ""
var _refresh := ""
var _token_exp := 0.0
var _authing := false
var _pending_pos: Variant = null
var _pos_timer := 0.0
var _alive_timer := 0.0


func _ready() -> void:
	_http = HttpQueue.new(FirebaseConfig.DB_URL)
	_sse.on_event = _on_sse
	var cfg := ConfigFile.new()
	cfg.load(AUTH_PATH)
	_refresh = cfg.get_value("auth", "refresh", "")


func _process(delta: float) -> void:
	_http.poll(delta)
	if not active:
		return
	_sse.poll(delta)
	_pos_timer += delta
	if _pending_pos != null and _pos_timer >= POS_INTERVAL and _http.is_idle():
		_http.request(HTTPClient.METHOD_PUT, _path(code, "/players/%s/p" % uid), JSON.stringify(_pending_pos))
		_pending_pos = null
		_pos_timer = 0.0
	if is_host:
		_alive_timer += delta
		if _alive_timer >= ALIVE_INTERVAL:
			_alive_timer = 0.0
			_http.request(HTTPClient.METHOD_PUT, _path(code, "/meta/alive"), '{".sv":"timestamp"}')
	if FirebaseConfig.API_KEY != "" and not _authing and Time.get_unix_time_from_system() > _token_exp - 300.0:
		_auth(func(_ok: bool) -> void: pass)


# ---------- Genel API ----------

## Yeni oda kurar. blocks: mevcut dünyanın değişiklikleri { "x_y_z": id }.
func host(world_seed: int, blocks: Dictionary, pname: String) -> void:
	_auth(func(ok: bool) -> void:
		if not ok:
			failed.emit("Firebase kimlik doğrulaması başarısız. İnternet bağlantınızı kontrol edin.")
			return
		_try_host(world_seed, blocks, pname, 0))


## 4 haneli kodla odaya katılır.
func join(room: String, pname: String) -> void:
	_auth(func(ok: bool) -> void:
		if not ok:
			failed.emit("Firebase kimlik doğrulaması başarısız. İnternet bağlantınızı kontrol edin.")
			return
		_http.request(HTTPClient.METHOD_GET, _path(room, "/meta"), "", func(rc: int, body: String) -> void:
			if rc == 401 or rc == 403:
				failed.emit(MSG_DENIED)
				return
			if rc != 200:
				failed.emit("Sunucuya ulaşılamadı (%d)." % rc)
				return
			var meta: Variant = JSON.parse_string(body)
			if not (meta is Dictionary) or not meta.has("seed"):
				failed.emit("Oda bulunamadı: %s" % room)
				return
			if int(meta.get("proto", 0)) != PROTO:
				failed.emit("Oyun sürümünüz oda sahibininkiyle uyumlu değil. Lütfen güncelleyin.")
				return
			var me := {"n": pname, "p": [0, 40, 0, 0, 0]}
			_http.request(HTTPClient.METHOD_PUT, _path(room, "/players/" + uid), JSON.stringify(me), func(rc2: int, _b: String) -> void:
				if rc2 != 200:
					failed.emit(MSG_DENIED if rc2 == 401 or rc2 == 403 else "Odaya katılınamadı (%d)." % rc2)
					return
				code = room
				is_host = false
				_start()
				joined.emit(int(meta["seed"])))))


## Oyuncu durumu: [x, y, z, yaw, pitch]. En fazla saniyede ~10 kez, yalnızca en son değer gönderilir.
func send_pos(p: Array) -> void:
	if active:
		_pending_pos = p


func send_block(pos: Vector3i, id: int) -> void:
	if active:
		_http.request(HTTPClient.METHOD_PUT, _path(code, "/blocks/" + Blocks.key(pos)), str(id))


## Odadan ayrılır. Host ayrılırsa oda silinir.
func leave() -> void:
	if not active:
		return
	active = false
	_sse.stop()
	_pending_pos = null
	if is_host:
		_http.request(HTTPClient.METHOD_DELETE, _path(code, ""))
	else:
		_http.request(HTTPClient.METHOD_DELETE, _path(code, "/players/" + uid))
	code = ""
	is_host = false


# ---------- İç işleyiş ----------

func _path(room: String, sub: String) -> String:
	var p := "/rooms/%s%s.json" % [room, sub]
	if _token != "":
		p += "?auth=" + _token
	return p


func _start() -> void:
	active = true
	_pos_timer = 0.0
	_alive_timer = 0.0
	_sse.start(FirebaseConfig.DB_URL, func() -> String: return _path(code, ""))


func _try_host(world_seed: int, blocks: Dictionary, pname: String, attempt: int) -> void:
	var c := str(randi_range(1000, 9999))
	_http.request(HTTPClient.METHOD_GET, _path(c, "/meta"), "", func(rc: int, body: String) -> void:
		if rc == 401 or rc == 403:
			failed.emit(MSG_DENIED)
			return
		if rc != 200:
			failed.emit("Sunucuya ulaşılamadı (%d)." % rc)
			return
		var meta: Variant = JSON.parse_string(body)
		var now_ms := Time.get_unix_time_from_system() * 1000.0
		var free: bool = not (meta is Dictionary) or now_ms - float(meta.get("alive", 0)) > STALE_MS
		if not free:
			if attempt < 12:
				_try_host(world_seed, blocks, pname, attempt + 1)
			else:
				failed.emit("Boş oda kodu bulunamadı, tekrar deneyin.")
			return
		var room := {
			"meta": {"host": uid, "seed": world_seed, "proto": PROTO, "alive": {".sv": "timestamp"}},
			"players": {uid: {"n": pname, "p": [0, 40, 0, 0, 0]}},
		}
		if not blocks.is_empty():
			room["blocks"] = blocks
		_http.request(HTTPClient.METHOD_PUT, _path(c, ""), JSON.stringify(room), func(rc2: int, _b: String) -> void:
			if rc2 != 200:
				if attempt < 12 and (rc2 == 401 or rc2 == 403):
					_try_host(world_seed, blocks, pname, attempt + 1)
				else:
					failed.emit("Oda kurulamadı (%d)." % rc2)
				return
			code = c
			is_host = true
			_start()
			room_created.emit(c)))


func _on_sse(ev: String, data: Variant) -> void:
	if not active:
		return
	match ev:
		"put", "patch":
			if data is Dictionary:
				_on_data(str(data.get("path", "/")), data.get("data"))
		"cancel":
			_closed("Oda bağlantısı sunucu tarafından kesildi.")
		"http_error":
			_closed(MSG_DENIED if int(data) == 401 or int(data) == 403 else "Oda bağlantısı kurulamadı (%d)." % int(data))
		"auth_revoked":
			_sse.stop()
			_token_exp = 0.0
			_auth(func(ok: bool) -> void:
				if ok and active:
					_sse.start(FirebaseConfig.DB_URL, func() -> String: return _path(code, ""))
				elif active:
					_closed("Oturum süresi doldu."))


func _closed(reason: String) -> void:
	active = false
	_sse.stop()
	code = ""
	room_closed.emit(reason)


func _on_data(path: String, d: Variant) -> void:
	var parts := path.split("/", false)
	if parts.is_empty():
		if d == null:
			_closed("Oda kapatıldı.")
			return
		if d is Dictionary:
			if not d.has("meta"):
				_closed("Oda kapatıldı.")
				return
			_players(d.get("players"))
			if d.get("blocks") is Dictionary:
				blocks_bulk.emit(d["blocks"])
		return
	match parts[0]:
		"meta":
			if parts.size() == 1 and d == null:
				_closed("Oda kapatıldı.")
		"players":
			if parts.size() == 1:
				_players(d)
			elif parts[1] != uid:
				if parts.size() == 2:
					if d == null:
						player_left.emit(parts[1])
					elif d is Dictionary:
						player_update.emit(parts[1], str(d.get("n", "")), d.get("p"))
				elif parts[2] == "p":
					player_update.emit(parts[1], "", d)
		"blocks":
			if parts.size() == 1:
				if d is Dictionary:
					blocks_bulk.emit(d)
			elif parts.size() == 2 and d != null:
				var pos: Variant = Blocks.parse_key(parts[1])
				if pos != null:
					block_update.emit(pos, int(d))


func _players(d: Variant) -> void:
	if not (d is Dictionary):
		return
	for id: String in d:
		if id != uid and d[id] is Dictionary:
			player_update.emit(id, str(d[id].get("n", "")), d[id].get("p"))


# ---------- Anonim kimlik doğrulama ----------

func _auth(cb: Callable) -> void:
	if FirebaseConfig.API_KEY == "":
		uid = Session.local_id
		cb.call(true)
		return
	if _token != "" and Time.get_unix_time_from_system() < _token_exp - 300.0:
		cb.call(true)
		return
	_authing = true
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var refreshing := _refresh != ""
	req.request_completed.connect(func(_result: int, rc: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		_authing = false
		var j: Variant = JSON.parse_string(body.get_string_from_utf8())
		if rc != 200 or not (j is Dictionary):
			if refreshing and rc >= 400 and rc < 500:
				_refresh = ""   # yenileme anahtarı geçersiz: yeni anonim hesap aç
				_auth(cb)
			else:
				cb.call(false)
			return
		_token = str(j.get("id_token", j.get("idToken", "")))
		_refresh = str(j.get("refresh_token", j.get("refreshToken", "")))
		uid = str(j.get("user_id", j.get("localId", "")))
		_token_exp = Time.get_unix_time_from_system() + float(j.get("expires_in", j.get("expiresIn", "3600")))
		var cfg := ConfigFile.new()
		cfg.set_value("auth", "refresh", _refresh)
		cfg.save(AUTH_PATH)
		cb.call(_token != "" and uid != ""))
	var err: int
	if refreshing:
		err = req.request("https://securetoken.googleapis.com/v1/token?key=" + FirebaseConfig.API_KEY,
			["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST,
			"grant_type=refresh_token&refresh_token=" + _refresh)
	else:
		err = req.request("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + FirebaseConfig.API_KEY,
			["Content-Type: application/json"], HTTPClient.METHOD_POST, '{"returnSecureToken":true}')
	if err != OK:
		req.queue_free()
		_authing = false
		cb.call(false)
