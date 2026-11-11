class_name FloatText
extends Label3D
## Dünyada yükselip kaybolan kısa yazı (hasar, sekme, XP).

const LIFE := 0.9

var _t := 0.0


func setup(p_text: String, color: Color, pos: Vector3) -> void:
	text = p_text
	position = pos
	modulate = color
	font = Session.font
	font_size = 56
	outline_size = 14
	pixel_size = 0.006
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	render_priority = 3


func _process(delta: float) -> void:
	_t += delta
	position.y += delta * 0.9
	modulate.a = clampf(1.0 - _t / LIFE, 0.0, 1.0)
	outline_modulate.a = modulate.a
	if _t >= LIFE:
		queue_free()
