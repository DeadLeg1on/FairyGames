extends Control
## Анимированный портрет феи для карточек сюжета и меню.

var ch: Dictionary
var size_px := 130.0


func setup(chapter: Dictionary, px: float) -> void:
	ch = chapter
	size_px = px
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ch.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	Sketch.set_boil(t)
	# фея с крыльями, волосами и аксессуаром занимает ~52×54 единиц — вписываем целиком
	var sc := size_px / 60.0
	FairyDraw.fairy(self, size.x * 0.5 + 4.0 * sc, size.y * 0.5 + 4.5 * sc, t, ch, 1.0, sc, 0.0)
