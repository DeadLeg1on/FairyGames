class_name Sketch
## Карандашный рендер: «кипящие» дрожащие линии, штриховка, каракули.
## Прямой порт src/game/sketch.ts.

const GRAPHITE := Color(0.149, 0.133, 0.125, 0.85)
const GRAPHITE_SOFT := Color(0.149, 0.133, 0.125, 0.35)
const INK := Color("#2a2420")
const PAPER := Color("#f3ecdc")
const HATCH_SIZE := 48.0

static var boil: int = 0
static var boil_frozen: bool = false
static var _hatch_tex: ImageTexture
static var _paper_tex: ImageTexture
static var _glow_tex: GradientTexture2D
static var _vignette_tex: GradientTexture2D
static var _font: Font
static var _font_regular: Font


static func set_boil(t: float) -> void:
	if not boil_frozen:
		boil = int(floor(t * 8.0))


static func freeze_boil(on: bool) -> void:
	boil_frozen = on
	if on:
		boil = 0


static func hash1(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453
	return s - floor(s)


## дрожание в диапазоне -0.5..0.5, меняется ~8 раз в секунду
static func jr(seed: float, i: float) -> float:
	return hash1(seed * 13.37 + i * 7.13 + float(boil) * 3.17) - 0.5


## плоский массив [x1, y1, x2, y2, ...] -> PackedVector2Array
static func v(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := flat.size() / 2
	out.resize(n)
	for i in n:
		out[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
	return out


# ---------------------------------------------------------------- textures

static func hatch_tex() -> ImageTexture:
	if _hatch_tex:
		return _hatch_tex
	var s := int(HATCH_SIZE)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var off := 0
	while off < s:
		var a := rng.randf_range(0.55, 0.95)
		var thick := 1 if rng.randf() < 0.5 else 2
		for y in s:
			for k in thick:
				var x := posmod(off + (s - 1 - y) + k, s)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		off += 6
	_hatch_tex = ImageTexture.create_from_image(img)
	return _hatch_tex


static func paper_tex() -> ImageTexture:
	if _paper_tex:
		return _paper_tex
	var img := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for y in 200:
		for x in 200:
			var dark := rng.randf() < 0.5
			var a := rng.randf() * 22.0 / 255.0
			if dark:
				img.set_pixel(x, y, Color(70 / 255.0, 60 / 255.0, 50 / 255.0, a))
			else:
				img.set_pixel(x, y, Color(1, 250 / 255.0, 240 / 255.0, a))
	_paper_tex = ImageTexture.create_from_image(img)
	return _paper_tex


## радиальное свечение: белый центр -> прозрачный край (модулируется цветом)
static func glow_tex() -> GradientTexture2D:
	if _glow_tex:
		return _glow_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 128
	_glow_tex.height = 128
	return _glow_tex


static func vignette_tex() -> GradientTexture2D:
	if _vignette_tex:
		return _vignette_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.35, 0.27, 0.16, 0), Color(0.35, 0.27, 0.16, 0), Color(0.35, 0.27, 0.16, 0.3)])
	_vignette_tex = GradientTexture2D.new()
	_vignette_tex.gradient = g
	_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	_vignette_tex.fill_from = Vector2(0.5, 0.5)
	_vignette_tex.fill_to = Vector2(1.05, 0.5)
	_vignette_tex.width = 256
	_vignette_tex.height = 256
	return _vignette_tex


static func draw_glow(ci: CanvasItem, pos: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(glow_tex(), Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


# ---------------------------------------------------------------- fonts / text

static var _base_font: FontFile


## Шрифт Caveat (OFL) хранится текстом в base64 — так он гарантированно
## попадает в проект и экспорт (см. include_filter в export_presets.cfg).
static func base_font() -> FontFile:
	if _base_font:
		return _base_font
	_base_font = FontFile.new()
	var f := FileAccess.open("res://fonts/caveat_ttf.b64.txt", FileAccess.READ)
	if f:
		_base_font.data = Marshalls.base64_to_raw(f.get_as_text().strip_edges())
	else:
		push_error("Не найден res://fonts/caveat_ttf.b64.txt — будет системный шрифт")
	return _base_font


static func font() -> Font:
	if _font:
		return _font
	var base: Font = base_font()
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": 700}
	_font = fv
	return _font


static func font_regular() -> Font:
	if _font_regular:
		return _font_regular
	var base: Font = base_font()
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": 500}
	_font_regular = fv
	return _font_regular


## текст с «бумажной» обводкой; align: -1 влево, 0 по центру, 1 вправо; y — центр строки
static func text(ci: CanvasItem, x: float, y: float, s: String, col: Color, size: float = 22.0, align: int = 0, outline: Color = Color(0.953, 0.925, 0.863, 0.85)) -> void:
	var f := font()
	var isz := maxi(1, int(round(size)))
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, isz).x
	var px := x
	if align == 0:
		px = x - w * 0.5
	elif align == 1:
		px = x - w
	var base_y := y + (f.get_ascent(isz) - f.get_descent(isz)) * 0.5
	var pos := Vector2(px, base_y)
	ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, isz, 4, outline)
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, isz, col)


# ---------------------------------------------------------------- geometry

## сглаженная замкнутая кривая через середины сторон (как quadraticCurveTo в TS)
static func _smooth_closed(ctrl: PackedVector2Array, steps: int = 3) -> PackedVector2Array:
	var n := ctrl.size()
	var out := PackedVector2Array()
	out.resize(n * steps)
	var k := 0
	for i in n:
		var p0 := (ctrl[(i - 1 + n) % n] + ctrl[i]) * 0.5
		var c := ctrl[i]
		var p1 := (ctrl[i] + ctrl[(i + 1) % n]) * 0.5
		for s in steps:
			var t := float(s) / steps
			var mt := 1.0 - t
			out[k] = p0 * (mt * mt) + c * (2.0 * mt * t) + p1 * (t * t)
			k += 1
	return out


static func ellipse_pts(x: float, y: float, rx: float, ry: float, seed: float, pass_i: int = 0, wob: float = 0.1) -> PackedVector2Array:
	var r := maxf(rx, ry)
	var n := clampi(int(r * 0.5), 7, 22)
	var a0 := jr(seed, pass_i * 50) * 1.2
	var ctrl := PackedVector2Array()
	ctrl.resize(n)
	for i in n:
		var a := a0 + float(i) / n * TAU
		var k := 1.0 + jr(seed, pass_i * 50 + i + 1) * wob
		ctrl[i] = Vector2(x + cos(a) * rx * k + pass_i * 0.6, y + sin(a) * ry * k - pass_i * 0.4)
	return _smooth_closed(ctrl)


static func fill_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var uvs := PackedVector2Array()
	uvs.resize(pts.size())
	for i in pts.size():
		uvs[i] = pts[i] / HATCH_SIZE
	ci.draw_colored_polygon(pts, col, uvs, hatch_tex())


static func stroke_closed(ci: CanvasItem, pts: PackedVector2Array, col: Color, lw: float) -> void:
	if pts.size() < 2:
		return
	var p := pts.duplicate()
	p.append(pts[0])
	ci.draw_polyline(p, col, lw, true)


static func s_ellipse(ci: CanvasItem, x: float, y: float, rx: float, ry: float, seed: float, fill = null, lw: float = 1.6, stroke: Color = GRAPHITE, wob: float = 0.1) -> void:
	if fill != null:
		fill_poly(ci, ellipse_pts(x, y, rx, ry, seed, 0, wob), fill)
	if lw > 0.0:
		stroke_closed(ci, ellipse_pts(x, y, rx, ry, seed + 3.0, 1, wob), stroke, lw)


static func s_circle(ci: CanvasItem, x: float, y: float, r: float, seed: float, fill = null, lw: float = 1.6, stroke: Color = GRAPHITE) -> void:
	s_ellipse(ci, x, y, r, r, seed, fill, lw, stroke)


## многоугольник/ломаная с дрожанием, два прохода карандаша
static func s_poly(ci: CanvasItem, pts: PackedVector2Array, seed: float, closed: bool, fill = null, lw: float = 1.6, amp: float = 1.6, stroke: Color = GRAPHITE) -> void:
	var n := pts.size()
	for pass_i in 2:
		var jp := PackedVector2Array()
		jp.resize(n)
		for i in n:
			jp[i] = pts[i] + Vector2(jr(seed + pass_i * 9, i * 2) * amp * 2.0, jr(seed + pass_i * 9, i * 2 + 1) * amp * 2.0)
		if pass_i == 0 and fill != null and closed:
			fill_poly(ci, jp, fill)
		if lw > 0.0:
			var w := lw if pass_i == 0 else lw * 0.6
			if closed:
				stroke_closed(ci, jp, stroke, w)
			else:
				ci.draw_polyline(jp, stroke, w, true)


static func s_line(ci: CanvasItem, x1: float, y1: float, x2: float, y2: float, seed: float, lw: float = 1.5, stroke: Color = GRAPHITE, bend: float = 2.0) -> void:
	for pass_i in 2:
		var m := Vector2((x1 + x2) * 0.5 + jr(seed, pass_i * 4) * bend * 2.0, (y1 + y2) * 0.5 + jr(seed, pass_i * 4 + 1) * bend * 2.0)
		var a := Vector2(x1 + jr(seed, pass_i * 4 + 2) * 1.5, y1 + jr(seed, pass_i * 4 + 3) * 1.5)
		var b := Vector2(x2, y2)
		var pts := PackedVector2Array()
		pts.resize(7)
		for i in 7:
			var t := i / 6.0
			var mt := 1.0 - t
			pts[i] = a * (mt * mt) + m * (2.0 * mt * t) + b * (t * t)
		ci.draw_polyline(pts, stroke, lw if pass_i == 0 else lw * 0.55, true)


## густая графитовая каракуля внутри круга — для теней
static func scribble(ci: CanvasItem, x: float, y: float, r: float, seed: float, n: int = 10, col: Color = Color(0.118, 0.102, 0.118, 0.8), lw: float = 1.3) -> void:
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var a := jr(seed, i) * PI * 4.0
		var d := (0.3 + (jr(seed, i + 30) + 0.5) * 0.7) * r
		pts[i] = Vector2(x + cos(a) * d, y + sin(a) * d)
	ci.draw_polyline(pts, col, lw, true)


static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, out: PackedVector2Array, steps: int) -> void:
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var mt := 1.0 - t
		out.append(p0 * (mt * mt * mt) + p1 * (3.0 * mt * mt * t) + p2 * (3.0 * mt * t * t) + p3 * (t * t * t))


static func heart_pts(x: float, y: float, s: float, seed: float) -> PackedVector2Array:
	var j := func(i: int) -> float: return jr(seed, i) * s * 0.12
	var start := Vector2(x + j.call(0), y + s * 0.35 + j.call(1))
	var out := PackedVector2Array([start])
	_cubic(start, Vector2(x - s * 0.1, y + s * 0.05), Vector2(x - s * 0.9 + j.call(2), y - s * 0.1), Vector2(x - s * 0.5, y - s * 0.55 + j.call(3)), out, 6)
	_cubic(out[out.size() - 1], Vector2(x - s * 0.25, y - s * 0.8), Vector2(x + j.call(4), y - s * 0.55), Vector2(x, y - s * 0.3), out, 5)
	_cubic(out[out.size() - 1], Vector2(x + j.call(5), y - s * 0.55), Vector2(x + s * 0.25, y - s * 0.8), Vector2(x + s * 0.5, y - s * 0.55 + j.call(6)), out, 5)
	_cubic(out[out.size() - 1], Vector2(x + s * 0.9 + j.call(7), y - s * 0.1), Vector2(x + s * 0.1, y + s * 0.05), start, out, 6)
	out.remove_at(out.size() - 1)
	return out


static func draw_heart(ci: CanvasItem, x: float, y: float, s: float, seed: float, fill = null, stroke: Color = GRAPHITE) -> void:
	var pts := heart_pts(x, y, s, seed)
	if fill != null:
		fill_poly(ci, pts, fill)
	stroke_closed(ci, pts, stroke, 1.6)


static func star_pts(x: float, y: float, r1: float, r2: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n * 2)
	for i in n * 2:
		var a := rot + float(i) / (n * 2) * TAU - PI / 2.0
		var r := r1 if i % 2 == 0 else r2
		pts[i] = Vector2(x + cos(a) * r, y + sin(a) * r)
	return pts
