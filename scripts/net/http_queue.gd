class_name HttpQueue
extends RefCounted
## Tek bir kalıcı (keep-alive) HTTPS bağlantısı üzerinden istekleri sırayla gönderir.
## Her istekte yeniden TLS el sıkışması yapılmadığı için sık konum güncellemelerine uygundur.

const TIMEOUT := 15.0

var _host: String
var _c := HTTPClient.new()
var _queue: Array = []
var _cur: Variant = null
var _sent := false
var _buf := PackedByteArray()
var _elapsed := 0.0
var _retries := 0
var _code := 0


func _init(base_url: String) -> void:
	_host = base_url.trim_prefix("https://").trim_suffix("/")


## cb(code: int, body: String) — bağlantı hatasında code = 0.
func request(method: int, path: String, body := "", cb := Callable()) -> void:
	_queue.append({"m": method, "p": path, "b": body, "cb": cb})


func is_idle() -> bool:
	return _cur == null and _queue.is_empty()


func poll(delta: float) -> void:
	if _cur == null:
		if _queue.is_empty():
			return
		_cur = _queue.pop_front()
		_sent = false
		_elapsed = 0.0
		_retries = 0
		_code = 0
		_buf = PackedByteArray()
	_elapsed += delta
	if _elapsed > TIMEOUT:
		_c.close()
		_finish(0)
		return
	_c.poll()
	match _c.get_status():
		HTTPClient.STATUS_DISCONNECTED:
			if _code != 0:
				_finish(_code)   # yanıt alındı, sunucu bağlantıyı kapattı
			elif _sent:
				_retry()
			elif _c.connect_to_host(_host, 443, TLSOptions.client()) != OK:
				_finish(0)
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				var headers := ["Content-Type: application/json"]
				if _c.request(_cur["m"], _cur["p"], headers, _cur["b"]) != OK:
					_retry()
				else:
					_sent = true
			else:
				_finish(_c.get_response_code())
		HTTPClient.STATUS_BODY:
			_code = _c.get_response_code()
			var chunk := _c.read_response_body_chunk()
			if chunk.size() > 0:
				_buf.append_array(chunk)
		_:
			if _code != 0:
				_c.close()
				_finish(_code)
			else:
				_retry()


## Sunucu boşta kalan bağlantıyı kapatmış olabilir: yeniden bağlanıp bir kez daha dene.
func _retry() -> void:
	_c.close()
	_c = HTTPClient.new()
	_sent = false
	_buf = PackedByteArray()
	_retries += 1
	if _retries > 2:
		_finish(0)


func _finish(code: int) -> void:
	var cur: Dictionary = _cur
	var body := _buf.get_string_from_utf8()
	_cur = null
	_sent = false
	var cb: Callable = cur["cb"]
	if cb.is_valid():
		cb.call(code, body)
