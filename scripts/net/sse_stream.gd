class_name SseStream
extends RefCounted
## Firebase Realtime Database canlı akışı (Server-Sent Events).
## Bağlantı koparsa kendiliğinden yeniden bağlanır; Firebase her bağlantıda güncel durumu baştan yollar.

const IDLE_LIMIT := 75.0   # Firebase ~30 sn'de bir keep-alive yollar

var on_event := Callable()   # on_event(name: String, data: Variant)

var _c: HTTPClient
var _host := ""
var _default_host := ""
var _path_fn := Callable()
var _redirect_path := ""
var _running := false
var _sent := false
var _checked := false
var _retry := 0.0
var _idle := 0.0
var _bytes := PackedByteArray()
var _ev := ""
var _data := ""


func start(base_url: String, path_fn: Callable) -> void:
	_default_host = base_url.trim_prefix("https://").trim_suffix("/")
	_host = _default_host
	_path_fn = path_fn
	_redirect_path = ""
	_running = true
	_retry = 0.0
	_reset()


func stop() -> void:
	_running = false
	if _c != null:
		_c.close()
		_c = null


func _reset() -> void:
	if _c != null:
		_c.close()
	_c = HTTPClient.new()
	_sent = false
	_checked = false
	_idle = 0.0
	_bytes = PackedByteArray()
	_ev = ""
	_data = ""


func _fail() -> void:
	_host = _default_host
	_redirect_path = ""
	_retry = 2.0


func poll(delta: float) -> void:
	if not _running:
		return
	if _retry > 0.0:
		_retry -= delta
		if _retry > 0.0:
			return
		_reset()
	_idle += delta
	if _idle > IDLE_LIMIT:
		_fail()
		return
	_c.poll()
	match _c.get_status():
		HTTPClient.STATUS_DISCONNECTED:
			if _sent or _c.connect_to_host(_host, 443, TLSOptions.client()) != OK:
				_fail()
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if _sent:
				_fail()   # akış sona erdi
				return
			var path: String = _redirect_path if _redirect_path != "" else _path_fn.call()
			if _c.request(HTTPClient.METHOD_GET, path, ["Accept: text/event-stream"]) != OK:
				_fail()
			_sent = true
		HTTPClient.STATUS_BODY:
			if not _checked:
				_checked = true
				var code := _c.get_response_code()
				if code in [301, 302, 307, 308]:
					var loc: String = _c.get_response_headers_as_dictionary().get("Location", "")
					var rest := loc.trim_prefix("https://")
					var slash := rest.find("/")
					if loc == "" or slash == -1:
						_fail()
						return
					_host = rest.substr(0, slash)
					_redirect_path = rest.substr(slash)
					_reset()
					return
				if code != 200:
					_running = false
					on_event.call("http_error", code)
					return
			var chunk := _c.read_response_body_chunk()
			if chunk.size() > 0:
				_idle = 0.0
				_bytes.append_array(chunk)
				_parse()
		_:
			_fail()


func _parse() -> void:
	while _running:
		var nl := _bytes.find(10)
		if nl == -1:
			return
		var line := _bytes.slice(0, nl).get_string_from_utf8().trim_suffix("\r")
		_bytes = _bytes.slice(nl + 1)
		if line == "":
			if _ev != "":
				var ev := _ev
				var data: Variant = JSON.parse_string(_data) if _data != "" else null
				_ev = ""
				_data = ""
				on_event.call(ev, data)
		elif line.begins_with("event:"):
			_ev = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			_data += line.substr(5).strip_edges()
