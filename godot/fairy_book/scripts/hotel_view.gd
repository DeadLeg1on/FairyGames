class_name HotelView
extends Control
## Визуальный «Отель фей»: рисованная сцена вместо списка кнопок.
##
## На сцене всё то же состояние, что и в логике (scripts/hotel.gd): номера с кроватями
## и гостями, ресепшн с очередью и процедурные станции. Феи — анимированные
## портреты (scripts/portrait.gd), а здание, мебель и станции рисуются в _draw().
##
## Логику выбора держит экран (main.gd): сцена только сообщает, куда кликнули,
## сигналом act(вид, первый, второй):
##   "queue"    — гостья в очереди на ресепшене (индекс);
##   "resident" — жиличка в номере (номер, место);
##   "bed"      — пустая кровать в номере (номер, место);
##   "station"  — процедурная станция (вид процедуры);
##   "none"     — клик по пустому месту.
## Так «кликнуть по фее, а потом по станции» и «кликнуть по гостье, а потом по
## кровати» описываются одинаково и легко проверяются в тестах.

signal act(kind: String, a: Variant, b: Variant)

const PortraitScript := preload("res://scripts/portrait.gd")

## цвета номеров по видам окружения
const THEME_FILL := {
	"simple": Color("#efe3cd"),
	"meadow": Color("#dcefc6"),
	"river": Color("#cfe7f2"),
	"mushroom": Color("#e6d3b4"),
	"moon": Color("#3b3560"),
	"frost": Color("#dff0fb"),
	"garden": Color("#d8efc0"),
	"rainbow": Color("#fbe7d6"),
	"storm": Color("#9aa6c4"),
	"star": Color("#332a56"),
}
const WALL := Color("#f6e6d2")
const FLOOR := Color("#c9a273")
const WOOD := Color("#a97c4e")
const DESK := Color("#b0804f")

## состояние отеля (ссылка на словарь из main.gd) и текущий выбор
var state: Dictionary = {}
var sel := ""

var _hits: Array[Dictionary] = []
var _rooms: Array[Dictionary] = []
var _beds: Array[Dictionary] = []
var _queue_slots: Array[Dictionary] = []
var _stations: Array[Dictionary] = []
var _rec := Rect2()
var _host_pos := Vector2.ZERO
var _size_cache := Vector2.ZERO
var _hover := ""
var _portraits := {}
var _tweens := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func() -> void:
		_size_cache = Vector2.ZERO
		queue_redraw())


func _process(_dt: float) -> void:
	_place_fairies()
	var under := _hit(_local_mouse())
	_hover = str(under.get("key", ""))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover != "" else Control.CURSOR_ARROW
	queue_redraw()


# ------------------------------------------------------------------ геометрия

## пересчитать раскладку сцены (зовётся из _draw и из тестов)
func layout(force: bool = false) -> void:
	if state.is_empty() or size.x < 60.0 or size.y < 60.0:
		return
	if not force and _size_cache == size and not _rooms.is_empty():
		return
	_size_cache = size
	_rooms.clear()
	_beds.clear()
	_queue_slots.clear()
	_stations.clear()
	var W := size.x
	var H := size.y
	var rooms: Array = state.get("rooms", [])
	var bottom := clampf(H * 0.30, 96.0, 168.0)
	var top_h := clampf(H * 0.17, 44.0, 78.0)
	var rooms_top := top_h + 8.0
	var rooms_h := maxf(60.0, H - bottom - rooms_top - 4.0)
	var cols := 2 if W < 860.0 else 3
	var rows := int(ceil(float(maxi(1, rooms.size())) / float(cols)))
	var gap := 8.0
	var cw := (W - 16.0 - gap * float(cols - 1)) / float(cols)
	var chh := (rooms_h - gap * float(rows - 1)) / float(maxi(1, rows))
	for i in rooms.size():
		var r := int(i / cols)
		var c := i % cols
		var rect := Rect2(8.0 + float(c) * (cw + gap), rooms_top + float(r) * (chh + gap), cw, chh)
		_rooms.append({"i": i, "rect": rect})
		var room: Dictionary = rooms[i]
		var slots := int(room["slots"])
		var pad := 8.0
		var bed_w := (rect.size.x - pad * 2.0 - 6.0 * float(slots - 1)) / float(slots)
		var guest_row_h := rect.size.y * 0.42
		for s in slots:
			var b := Rect2(rect.position.x + pad + float(s) * (bed_w + 6.0),
				rect.position.y + rect.size.y - 22.0 - bed_w * 0.55, bed_w, bed_w * 0.55)
			_beds.append({"i": i, "s": s, "rect": b, "head": Vector2(b.position.x + b.size.x * 0.5, b.position.y - guest_row_h * 0.42)})
	# ресепшн и спа-зона в нижней полосе
	var rec_w := W * 0.5
	var zone_y := H - bottom + 4.0
	var zone_h := bottom - 8.0
	_rec = Rect2(8.0, zone_y, rec_w - 14.0, zone_h)
	var qcap := maxi(1, int(Hotel.guest_cap(state)))
	var qy := _rec.position.y + _rec.size.y * 0.66
	for i in qcap:
		var xs := _rec.position.x + 26.0 + (_rec.size.x - 40.0) * (float(i) + 0.5) / float(qcap)
		_queue_slots.append({"i": i, "pos": Vector2(xs, qy)})
	_host_pos = Vector2(_rec.position.x + _rec.size.x - 34.0, _rec.position.y + _rec.size.y * 0.42)
	var spa := Rect2(_rec.position.x + _rec.size.x + 8.0, zone_y, W - rec_w - 6.0, zone_h)
	var procs: Array = Hotel.procs()
	var pcols := 3
	var prows := int(ceil(float(maxi(1, procs.size())) / float(pcols)))
	var pw := (spa.size.x - 6.0 * float(pcols - 1)) / float(pcols)
	var ph := (spa.size.y - 6.0 * float(prows - 1)) / float(maxi(1, prows))
	for i in procs.size():
		var r2 := int(i / pcols)
		var c2 := i % pcols
		_stations.append({
			"id": str(procs[i]["id"]),
			"rect": Rect2(spa.position.x + float(c2) * (pw + 6.0), spa.position.y + float(r2) * (ph + 6.0), pw, ph),
		})


## кто что должен рисовать: собирает области нажатия (точки и прямоугольники)
func hits() -> Array[Dictionary]:
	layout()
	if not _hits.is_empty():
		return _hits
	_hits.clear()
	for q in _queue_slots:
		var queue: Array = state.get("queue", [])
		if int(q["i"]) < queue.size():
			_hits.append({"key": "q:%d" % int(q["i"]), "kind": "queue", "a": int(q["i"]), "b": 0, "rect": Rect2(q["pos"] - Vector2(20, 26), Vector2(40, 52))})
	for b in _beds:
		var ri := int(b["i"])
		var guests: Array = (state["rooms"] as Array)[ri]["guests"]
		if int(b["s"]) < guests.size():
			_hits.append({"key": "r:%d:%d" % [ri, int(b["s"])], "kind": "resident", "a": ri, "b": int(b["s"]), "rect": Rect2(b["head"] - Vector2(19, 40), Vector2(38, 52))})
		else:
			_hits.append({"key": "bed:%d:%d" % [ri, int(b["s"])], "kind": "bed", "a": ri, "b": int(b["s"]), "rect": Rect2(b["rect"].position - Vector2(0, 12), b["rect"].size + Vector2(0, 16))})
	for s in _stations:
		_hits.append({"key": "st:%s" % str(s["id"]), "kind": "station", "a": str(s["id"]), "b": 0, "rect": s["rect"]})
	return _hits


func _hit(pos: Vector2) -> Dictionary:
	for h in hits():
		if (h["rect"] as Rect2).has_point(pos):
			return h
	return {}


## сообщить наружу, куда кликнули (используется и кнопкой мыши, и касанием)
func pick(pos: Vector2) -> Dictionary:
	var h := _hit(pos)
	if h.is_empty():
		act.emit("none", 0, 0)
		return {}
	act.emit(str(h["kind"]), h["a"], h["b"])
	return h


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pick(event.position)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		pick(event.position)
		accept_event()


func _local_mouse() -> Vector2:
	return get_local_mouse_position()


# ------------------------------------------------------------------ феи (портреты)

func _look(kind: String) -> Dictionary:
	for d in Chapters.LIST:
		if str(d["id"]) == kind:
			return d
	return Chapters.get_ch(0)


## где сейчас стоит каждая фея: в очереди, на кровати, на процедуре
func _places() -> Dictionary:
	var out := {}
	var queue: Array = state.get("queue", [])
	for i in queue.size():
		if i < _queue_slots.size():
			out["q:%d" % i] = {"pos": _queue_slots[i]["pos"], "px": 46.0, "look": str(queue[i]["kind"])}
	if _rooms.is_empty():
		return out
	var rooms: Array = state.get("rooms", [])
	for ri in rooms.size():
		var guests: Array = (rooms[ri] as Dictionary)["guests"]
		for gi in guests.size():
			var key := "r:%d:%d" % [ri, gi]
			var look := str((guests[gi] as Dictionary)["kind"])
			var room: Dictionary = rooms[ri]
			var place := {}
			if str(guests[gi]["proc"]) != "" and float(guests[gi]["proc_left"]) > 0.0:
				var st := _station(str(guests[gi]["proc"]))
				if not st.is_empty():
					place = {"pos": (st["rect"] as Rect2).get_center() + Vector2(0, 6), "px": 40.0}
			if place.is_empty():
				var bed := _bed(ri, gi)
				if bed.is_empty():
					continue
				place = {"pos": bed["head"] + Vector2(0, 16), "px": 42.0 if int(room["slots"]) < 2 else 38.0}
			place["look"] = look
			out[key] = place
	return out


func _place_fairies() -> void:
	if state.is_empty() or _rooms.is_empty():
		return
	var places := _places()
	# ушли со сцены — убираем портрет
	for key in _portraits.keys():
		if not places.has(key):
			var old: Node = _portraits[key]
			_portraits.erase(key)
			if is_instance_valid(old):
				old.queue_free()
	for key in places.keys():
		var p: Control = _portraits.get(key)
		if p == null or not is_instance_valid(p):
			p = PortraitScript.new()
			add_child(p)
			var px := float(places[key]["px"])
			p.setup(_look(str(places[key]["look"])), px)
			p.size = Vector2(px, px)
			p.position = (places[key]["pos"] as Vector2) - Vector2(px * 0.5, px * 0.62)
			_portraits[key] = p
			continue
		var want := (places[key]["pos"] as Vector2) - Vector2(float(places[key]["px"]) * 0.5, float(places[key]["px"]) * 0.62)
		if p.position.distance_to(want) > 0.5:
			var old_tw: Tween = _tweens.get(key)
			if old_tw != null and old_tw.is_valid():
				old_tw.kill()
			var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(p, "position", want, 0.35)
			_tweens[key] = tw


func _bed(room_i: int, slot: int) -> Dictionary:
	for b in _beds:
		if int(b["i"]) == room_i and int(b["s"]) == slot:
			return b
	return {}


func _station(proc_id: String) -> Dictionary:
	for s in _stations:
		if str(s["id"]) == proc_id:
			return s
	return {}


# ------------------------------------------------------------------ рисование

func _draw() -> void:
	if state.is_empty():
		return
	layout()
	if _rooms.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	Sketch.set_boil(t)
	draw_rect(Rect2(Vector2.ZERO, size), WALL)
	_draw_windows(t)
	_draw_sign(t)
	_draw_rooms(t)
	_draw_reception(t)
	_draw_stations(t)
	_draw_selection(t)


func _draw_windows(t: float) -> void:
	var y := clampf(size.y * 0.045, 8.0, 18.0)
	var w := clampf(size.x * 0.13, 60.0, 110.0)
	for i in 2:
		var x := size.x * (0.30 + 0.34 * float(i))
		var rect := Rect2(x - w * 0.5, y, w, clampf(size.y * 0.11, 30.0, 54.0))
		Sketch.s_poly(self, Sketch.v([rect.position.x, rect.position.y, rect.position.x + rect.size.x, rect.position.y,
			rect.position.x + rect.size.x, rect.position.y + rect.size.y, rect.position.x, rect.position.y + rect.size.y]),
			10.0 + float(i), true, Color("#bcdcf2"), 1.6, 1.4)
		Sketch.s_circle(self, rect.position.x + rect.size.x * 0.72, rect.position.y + rect.size.y * 0.34,
			rect.size.y * 0.16, 12.0 + float(i), Color("#ffe9a6"), 1.0)
		for k in 2:
			Sketch.s_ellipse(self, rect.position.x + rect.size.x * (0.24 + 0.3 * float(k)), rect.position.y + rect.size.y * 0.62,
				rect.size.x * 0.12, rect.size.y * 0.1, 14.0 + float(i) + float(k), Color(1, 1, 1, 0.85), 1.0)
		Sketch.s_line(self, rect.position.x + rect.size.x * 0.5, rect.position.y, rect.position.x + rect.size.x * 0.5,
			rect.position.y + rect.size.y, 16.0, 1.2)
		Sketch.s_line(self, rect.position.x, rect.position.y + rect.size.y * 0.5, rect.position.x + rect.size.x,
			rect.position.y + rect.size.y * 0.5, 17.0, 1.2)
	# половицы
	var floor_y := size.y - clampf(size.y * 0.30, 96.0, 168.0)
	Sketch.s_line(self, 0.0, floor_y, size.x, floor_y, 18.0, 1.6, Sketch.GRAPHITE_SOFT, 1.5)
	var step := 42.0
	var n := int(size.x / step) + 1
	for i in n:
		Sketch.s_line(self, float(i) * step - 10.0, floor_y, float(i) * step + 16.0, size.y, 19.0 + float(i) * 0.3, 1.1, Sketch.GRAPHITE_SOFT, 3.0)


func _draw_sign(t: float) -> void:
	var ch := Chapters.get_ch(Chapters.hotel_index())
	var label := "♨ " + I18n.t("Отель фей")
	var cx := size.x * 0.5
	var y := clampf(size.y * 0.16, 34.0, 62.0)
	var w := clampf(size.x * 0.34, 150.0, 300.0)
	var rect := Rect2(cx - w * 0.5, y - 20.0, w, 30.0)
	Sketch.s_poly(self, Sketch.v([rect.position.x, rect.position.y, rect.position.x + rect.size.x, rect.position.y,
		rect.position.x + rect.size.x, rect.position.y + rect.size.y, rect.position.x, rect.position.y + rect.size.y]),
		30.0, true, WOOD, 1.8, 1.6)
	Sketch.text(self, cx, y - 5.0, label, Color("#3d2a16"), 18.0, 0)
	# рейтинг отеля звёздочками
	var stars := Hotel.stars(state)
	var shown := int(floor(stars))
	var sx := cx - 26.0
	for i in 5:
		var filled := i < shown
		Sketch.s_circle(self, sx + float(i) * 13.0, y + 16.0, 3.4, 31.0 + float(i),
			Color(1.0, 0.78, 0.29) if filled else Color(1, 1, 1, 0.5), 1.1)
	Sketch.text(self, cx + 40.0, y + 16.0, "%.1f" % stars, Color("#6b5433"), 14.0, 1)
	if ch.is_empty():
		return


func _draw_rooms(t: float) -> void:
	var rooms: Array = state.get("rooms", [])
	var season := Hotel.season_theme()
	for r in _rooms:
		var i := int(r["i"])
		if i >= rooms.size():
			continue
		var rect: Rect2 = r["rect"]
		var room: Dictionary = rooms[i]
		var theme_id := str(room["theme"])
		var fill: Color = THEME_FILL.get(theme_id, Color("#efe3cd"))
		var dark := fill.get_luminance() < 0.45
		Sketch.s_poly(self, Sketch.v([rect.position.x, rect.position.y, rect.position.x + rect.size.x, rect.position.y,
			rect.position.x + rect.size.x, rect.position.y + rect.size.y, rect.position.x, rect.position.y + rect.size.y]),
			40.0 + float(i), true, fill, 1.8, 1.6)
		# полоска «обоев» сверху — у каждого окружения свой узор
		_draw_wallpaper(rect, theme_id, i, dark)
		var ink := Color("#fff3dc") if dark else Sketch.INK
		var title := I18n.t("№%d · %s") % [i + 1, Hotel.theme_title(theme_id)]
		Sketch.text(self, rect.position.x + 8.0, rect.position.y + 15.0, title, ink, 14.0, 2)
		var pips := "◆".repeat(int(room["lvl"]))
		Sketch.text(self, rect.position.x + rect.size.x - 8.0, rect.position.y + 15.0, pips, Color(1.0, 0.85, 0.35) if dark else Color("#b08810"), 13.0, 1)
		if theme_id == season:
			Sketch.text(self, rect.position.x + 8.0, rect.position.y + rect.size.y - 8.0, I18n.t("сезон ×1.6"), Color(1.0, 0.85, 0.35) if dark else Color("#a06800"), 12.0, 2)
		# кровати
		for b in _beds:
			if int(b["i"]) != i:
				continue
			var brect: Rect2 = b["rect"]
			Sketch.s_poly(self, Sketch.v([brect.position.x, brect.position.y, brect.position.x + brect.size.x, brect.position.y,
				brect.position.x + brect.size.x, brect.position.y + brect.size.y, brect.position.x, brect.position.y + brect.size.y]),
				70.0 + float(i) * 3.0 + float(b["s"]), true, Color("#fff7e6") if not dark else Color("#cdbfe0"), 1.4, 1.2)
			Sketch.s_ellipse(self, brect.position.x + 9.0, brect.position.y + brect.size.y * 0.5, 7.0, brect.size.y * 0.32,
				74.0 + float(b["s"]), Color("#ffffff") if not dark else Color("#efe6ff"), 1.1)
			var guests: Array = room["guests"]
			var occupied := int(b["s"]) < guests.size()
			if not occupied:
				Sketch.text(self, brect.get_center().x, brect.get_center().y, I18n.t("свободно"), ink, 12.0, 0)
			elif _hover == "r:%d:%d" % [i, int(b["s"])]:
				Sketch.s_circle(self, brect.get_center().x, brect.get_center().y, 26.0, 78.0, Color(1, 1, 1, 0.25), 1.4)


func _draw_wallpaper(rect: Rect2, theme_id: String, seed_i: int, dark: bool) -> void:
	var band := Rect2(rect.position + Vector2(4, 24), Vector2(rect.size.x - 8.0, 10.0))
	match theme_id:
		"frost", "moon", "star":
			for i in 6:
				Sketch.s_circle(self, band.position.x + 6.0 + float(i) * (band.size.x - 12.0) / 5.0, band.position.y + 5.0, 2.0,
					90.0 + float(seed_i) * 7.0 + float(i), Color(1, 1, 1, 0.75), 0.9)
		"river", "rainbow":
			for i in 3:
				Sketch.s_ellipse(self, band.position.x + band.size.x * (0.2 + 0.3 * float(i)), band.position.y + 5.0,
					band.size.x * 0.11, 4.0, 100.0 + float(i), Color(1, 1, 1, 0.5), 1.0)
		"meadow", "garden":
			for i in 7:
				Sketch.s_line(self, band.position.x + 4.0 + float(i) * (band.size.x - 8.0) / 6.0, band.position.y + 9.0,
					band.position.x + 4.0 + float(i) * (band.size.x - 8.0) / 6.0, band.position.y + 2.0,
					110.0 + float(i), 1.1, Color(0.45, 0.65, 0.35, 0.7) if not dark else Color(1, 1, 1, 0.5))
		"storm":
			Sketch.s_line(self, band.position.x + 6.0, band.position.y + 2.0, band.position.x + band.size.x * 0.5, band.position.y + 6.0, 120.0, 1.2, Color(1, 1, 1, 0.6))
		"mushroom":
			for i in 4:
				Sketch.s_circle(self, band.position.x + 8.0 + float(i) * (band.size.x - 16.0) / 3.0, band.position.y + 5.0, 3.0,
					130.0 + float(i), Color(1, 1, 1, 0.55), 1.0)
		_:
			pass


func _draw_reception(t: float) -> void:
	var desk := Rect2(_rec.position.x, _rec.position.y + _rec.size.y * 0.28, _rec.size.x, _rec.size.y * 0.3)
	Sketch.s_poly(self, Sketch.v([desk.position.x, desk.position.y, desk.position.x + desk.size.x, desk.position.y,
		desk.position.x + desk.size.x, desk.position.y + desk.size.y, desk.position.x, desk.position.y + desk.size.y]),
		200.0, true, DESK, 1.8, 1.6)
	Sketch.text(self, desk.position.x + desk.size.x * 0.5, desk.position.y + desk.size.y * 0.55, I18n.t("Ресепшн"), Color("#4a3016"), 14.0, 0)
	# колокольчик
	Sketch.s_circle(self, desk.position.x + 24.0, desk.position.y - 3.0, 5.0, 202.0, Color(1.0, 0.85, 0.35), 1.3)
	Sketch.s_line(self, desk.position.x + 24.0, desk.position.y - 8.0, desk.position.x + 24.0, desk.position.y - 13.0, 203.0, 1.2)
	# звонок над стойкой, когда есть свободные места, а гостьи ждут
	var queue: Array = state.get("queue", [])
	if not queue.is_empty():
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		Sketch.s_circle(self, desk.position.x + 24.0, desk.position.y - 16.0, 2.0 + pulse * 2.5, 204.0, Color(0.95, 0.5, 0.4, 0.6), 1.0)
	# подпись хозяйки
	Sketch.text(self, _host_pos.x, _host_pos.y + 22.0, "Мелисса", Color("#6b4b28"), 13.0, 0)
	var open_beds := 0
	for room in (state.get("rooms") as Array):
		open_beds += Hotel.free_beds(room)
	if queue.is_empty():
		Sketch.text(self, _rec.position.x + _rec.size.x * 0.5, _rec.position.y + _rec.size.y * 0.94,
			I18n.t("Гости прилетят через %s") % Hotel.fmt_time(float(state["next_guest"])), Color("#7a6242"), 13.0, 0)
	else:
		Sketch.text(self, _rec.position.x + _rec.size.x * 0.5, _rec.position.y + _rec.size.y * 0.94,
			I18n.t("Свободных мест: %d · кликни по фее") % open_beds, Color("#7a6242"), 13.0, 0)
	for s in _queue_slots:
		var i := int(s["i"])
		var pos: Vector2 = s["pos"]
		Sketch.s_line(self, pos.x - 12.0, pos.y + 16.0, pos.x + 12.0, pos.y + 16.0, 210.0 + float(i), 1.3, Sketch.GRAPHITE_SOFT)
		if i >= queue.size():
			continue
		var guest: Dictionary = queue[i]
		var kind := Hotel.kind_of(str(guest["kind"]))
		# что гостья хочет: иконка вида окружения над головой
		Sketch.s_circle(self, pos.x + 14.0, pos.y - 30.0, 8.0, 220.0 + float(i), Color(1, 1, 1, 0.85), 1.2)
		Sketch.text(self, pos.x + 14.0, pos.y - 30.0, str(Hotel.theme_of(str(kind["theme"]))["icon"]), Sketch.INK, 12.0, 0)
		if bool(guest.get("vip", false)):
			Sketch.s_circle(self, pos.x - 15.0, pos.y - 30.0, 6.5, 230.0 + float(i), Color(1.0, 0.85, 0.35, 0.9), 1.1)
		# терпение гостьи
		var frac := clampf(float(guest["patience"]) / float(Hotel.PATIENCE), 0.0, 1.0)
		var bar := Rect2(pos.x - 14.0, pos.y + 20.0, 28.0, 4.0)
		Sketch.s_poly(self, Sketch.v([bar.position.x, bar.position.y, bar.position.x + bar.size.x, bar.position.y,
			bar.position.x + bar.size.x, bar.position.y + bar.size.y, bar.position.x, bar.position.y + bar.size.y]),
			240.0 + float(i), true, Color(1, 1, 1, 0.7), 1.0, 0.6)
		var fill := Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y))
		if frac > 0.02:
			draw_rect(fill, Color(0.55, 0.72, 0.35) if frac > 0.4 else Color(0.9, 0.45, 0.35))


func _draw_stations(t: float) -> void:
	if _stations.is_empty():
		return
	var head := _stations[0]["rect"] as Rect2
	var tail := _stations[_stations.size() - 1]["rect"] as Rect2
	Sketch.text(self, (head.position.x + tail.position.x + tail.size.x) * 0.5, head.position.y - 6.0, I18n.t("Процедуры"), Color("#6b4b28"), 14.0, 0)
	var procs: Array = Hotel.procs()
	for si in _stations.size():
		var st: Dictionary = _stations[si]
		var id := str(st["id"])
		var rect: Rect2 = st["rect"]
		var d := Hotel.proc_of(id)
		var owned := Hotel.proc_owned(state, id)
		var left := Hotel.proc_room_left(state, id)
		var base := Color("#fdf1dc") if owned else Color("#e4dccc")
		Sketch.s_poly(self, Sketch.v([rect.position.x, rect.position.y, rect.position.x + rect.size.x, rect.position.y,
			rect.position.x + rect.size.x, rect.position.y + rect.size.y, rect.position.x, rect.position.y + rect.size.y]),
			300.0 + float(si) * 2.0, true, base, 1.6, 1.4)
		# коврик станции
		Sketch.s_ellipse(self, rect.get_center().x, rect.position.y + rect.size.y * 0.68, rect.size.x * 0.34, rect.size.y * 0.2,
			310.0 + float(si), Color(1, 1, 1, 0.55) if owned else Color(0.8, 0.78, 0.72, 0.45), 1.2)
		_draw_station_furniture(id, rect, owned, t)
		var ink := Sketch.INK if owned else Color(0.42, 0.38, 0.34)
		Sketch.text(self, rect.get_center().x, rect.position.y + rect.size.y - 6.0, str(d["title"]), ink, 12.0, 0)
		if owned:
			Sketch.text(self, rect.position.x + rect.size.x - 6.0, rect.position.y + 12.0, "%d/%d" % [int(d["cap"]) - left, int(d["cap"])],
				Color("#7a6242"), 11.0, 1)
			if _hover == "st:%s" % id:
				draw_rect(rect.grow(-1.0), Color(1, 1, 1, 0.18))
		else:
			Sketch.text(self, rect.get_center().x, rect.position.y + 12.0, I18n.t("не открыто"), Color(0.5, 0.42, 0.36), 11.0, 0)


func _draw_station_furniture(id: String, rect: Rect2, owned: bool, t: float) -> void:
	var cx := rect.get_center().x
	var cy := rect.position.y + rect.size.y * 0.52
	var col := Color("#c98a4b") if owned else Color(0.6, 0.56, 0.5)
	var acc := Color("#8fc4b0") if owned else Color(0.65, 0.62, 0.56)
	match id:
		"tea":
			Sketch.s_ellipse(self, cx, cy, 13.0, 8.0, 400.0, col, 1.6)
			Sketch.s_circle(self, cx + 12.0, cy - 2.0, 4.0, 402.0, acc, 1.2)
			Sketch.s_line(self, cx - 4.0, cy - 12.0, cx - 2.0, cy - 6.0, 404.0, 1.2)
			Sketch.s_line(self, cx + 4.0, cy - 13.0, cx + 5.0, cy - 6.0, 405.0, 1.2)
		"massage":
			Sketch.s_poly(self, Sketch.v([cx - 16, cy + 6, cx + 16, cy + 6, cx + 14, cy - 2, cx - 14, cy - 2]), 410.0, true, col, 1.5, 1.0)
			Sketch.s_circle(self, cx, cy - 7.0, 6.0, 412.0, acc, 1.2)
			for i in 3:
				Sketch.s_line(self, cx - 8.0 + float(i) * 8.0, cy - 14.0, cx - 6.0 + float(i) * 8.0, cy - 18.0, 414.0 + float(i), 1.1, acc)
		"greenhouse":
			Sketch.s_poly(self, Sketch.v([cx - 13, cy + 7, cx + 13, cy + 7, cx + 10, cy - 3, cx - 10, cy - 3]), 420.0, true, Color("#b07c4a") if owned else col, 1.4, 1.0)
			for i in 3:
				Sketch.s_line(self, cx - 8.0 + float(i) * 8.0, cy - 3.0, cx - 10.0 + float(i) * 8.0, cy - 14.0, 422.0 + float(i), 1.2, acc)
				Sketch.s_circle(self, cx - 10.0 + float(i) * 8.0, cy - 15.0, 3.0, 426.0 + float(i), acc, 1.0)
		"bath":
			Sketch.s_ellipse(self, cx, cy, 15.0, 9.0, 430.0, col, 1.6)
			for i in 4:
				Sketch.s_circle(self, cx - 8.0 + float(i) * 5.5, cy - 6.0, 2.4 + 0.6 * sin(t * 2.0 + float(i)), 432.0 + float(i), Color(1, 1, 1, 0.8), 0.9)
		"moon":
			Sketch.s_circle(self, cx, cy, 11.0, 440.0, Color("#3b3560") if owned else col, 1.4)
			Sketch.s_circle(self, cx + 5.0, cy - 2.0, 9.0, 441.0, Color("#fdf1dc") if not owned else Color("#2c2748"), 1.2)
			for i in 3:
				Sketch.s_circle(self, cx - 12.0 + float(i) * 12.0, cy - 13.0, 1.8, 443.0 + float(i), Color(1.0, 0.9, 0.5, 0.9), 0.8)
		"star_bath":
			Sketch.s_ellipse(self, cx, cy + 2.0, 15.0, 8.0, 450.0, col, 1.6)
			for i in 3:
				Sketch.s_poly(self, Sketch.star_pts(cx - 10.0 + float(i) * 10.0, cy - 8.0, 5.0, 2.0, 5, t + float(i)), 452.0 + float(i), true, Color(1.0, 0.9, 0.5) if owned else acc, 1.0, 0.4)
		_:
			Sketch.s_circle(self, cx, cy, 11.0, 460.0, col, 1.4)


## выбор: кольцо под выбранной феей и подсветка цели
func _draw_selection(t: float) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	if sel != "":
		for h in hits():
			if str(h["key"]) != sel:
				continue
			var rect: Rect2 = h["rect"]
			var pos := rect.get_center() + Vector2(0, rect.size.y * 0.42)
			Sketch.s_ellipse(self, pos.x, pos.y, 20.0 + pulse * 3.0, 7.0 + pulse, 500.0, Color(1.0, 0.85, 0.35, 0.55), 1.8)
			Sketch.s_line(self, pos.x - 14.0, pos.y - 46.0 - pulse * 3.0, pos.x, pos.y - 54.0 - pulse * 3.0, 501.0, 1.6, Color(1.0, 0.6, 0.2))
			Sketch.s_line(self, pos.x, pos.y - 54.0 - pulse * 3.0, pos.x + 14.0, pos.y - 46.0 - pulse * 3.0, 502.0, 1.6, Color(1.0, 0.6, 0.2))
			break
	if _hover != "":
		for h in hits():
			if str(h["key"]) != _hover:
				continue
			var rect2: Rect2 = h["rect"]
			Sketch.s_poly(self, Sketch.v([rect2.position.x, rect2.position.y, rect2.position.x + rect2.size.x, rect2.position.y,
				rect2.position.x + rect2.size.x, rect2.position.y + rect2.size.y, rect2.position.x, rect2.position.y + rect2.size.y]),
				510.0, true, null, 1.6, 1.2, Color(1.0, 0.62, 0.24, 0.9))
			break
