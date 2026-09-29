class_name FairyDraw
## Фея и фоны глав. Порт src/game/draw.ts.

const SKIN := Color("#f6d9c0")

## цвет волос каждой феи: [основной, тень/контур, блик]
const HAIR := {
	"flower": [Color("#f2b441"), Color("#b06f16"), Color("#fff1b8")],
	"water": [Color("#56b0e6"), Color("#1d5f96"), Color("#d8f2ff")],
	"night": [Color("#d9d2ff"), Color("#7d70cc"), Color("#ffffff")],
	"frost": [Color("#f2f8ff"), Color("#86b4d6"), Color("#ffffff")],
	"star": [Color("#ffe07a"), Color("#c48f16"), Color("#fffbe0")],
	"mushroom": [Color("#b8643a"), Color("#6a2e16"), Color("#f6c49a")],
	"rainbow": [Color("#ff8fc2"), Color("#b8457e"), Color("#ffe0ef")],
	"garden": [Color("#93c85c"), Color("#46772a"), Color("#e4f7c8")],
	"storm": [Color("#8f9ac0"), Color("#3c4668"), Color("#e6ecff")],
}


static func _hair_fill(ci: CanvasItem, flat: Array, col: Array, lw: float) -> void:
	var pts := Sketch._smooth_closed(Sketch.v(flat), 4)
	ci.draw_colored_polygon(pts, col[0])
	Sketch.fill_poly(ci, pts, col[1])
	Sketch.stroke_closed(ci, pts, Sketch.GRAPHITE, lw)


static func _quad(a: Vector2, c: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 9:
		var k := i / 8.0
		out.append(a * (1 - k) * (1 - k) + c * 2.0 * (1 - k) * k + b * k * k)
	return out


## длинные волосы за головой — развеваются на ветру
static func hair_back(ci: CanvasItem, t: float, id: String) -> void:
	var col: Array = HAIR.get(id, HAIR["flower"])
	var w := func(k: float) -> float: return sin(t * 5.0 + k) * 1.7
	var flat := [
		3, -17.6, -2, -18.9, -6.8, -16.6, -9, -12, -10.5 + w.call(0) * 0.4, -6.5, -13.5 + w.call(1), -1.5, -16.5 + w.call(2), 3.5,
		-19.5 + w.call(3), 8.5, -17.5 + w.call(3), 9.8, -14.5 + w.call(2.6), 7.2, -11.5 + w.call(2), 3.2, -8.5 + w.call(1), -1, -5.5, -4.5, -3, -6.5,
	]
	_hair_fill(ci, flat, col, 1.2)
	var sc: Color = col[1]
	sc.a = 0.65
	ci.draw_polyline(_quad(Vector2(-5, -15.5), Vector2(-11 + w.call(1), -5), Vector2(-16.5 + w.call(3), 6.5)), sc, 0.9, true)
	ci.draw_polyline(_quad(Vector2(-2.5, -16.5), Vector2(-8 + w.call(1), -6), Vector2(-12.5 + w.call(2.5), 5)), sc, 0.9, true)
	ci.draw_polyline(_quad(Vector2(-7.5, -13), Vector2(-13 + w.call(1.5), -4), Vector2(-18 + w.call(3), 7.5)), sc, 0.9, true)


## чёлка поверх головы + блик
static func hair_front(ci: CanvasItem, id: String) -> void:
	var col: Array = HAIR.get(id, HAIR["flower"])
	var flat := [
		-7.3, -11, -7.7, -15, -4.2, -18.5, 1, -18.7, 5.6, -16.6, 7.7, -12.4, 6.1, -13.1, 4.6, -11.4, 3, -13.5, 1, -12.2,
		-1.1, -14.1, -3.2, -12.6, -5.2, -14.3,
	]
	_hair_fill(ci, flat, col, 1.1)
	var hl: Color = col[2]
	hl.a = 0.85
	ci.draw_arc(Vector2(-0.5, -12.2), 5.2, PI * 1.2, PI * 1.5, 8, hl, 1.3, true)


static func _t(rot: float, scl: Vector2, pos: Vector2) -> Transform2D:
	return Transform2D(rot, scl, 0.0, pos)


## base — текущее преобразование холста, к нему вернёмся после рисования
static func fairy(ci: CanvasItem, x: float, y: float, t: float, ch: Dictionary, facing: float, scale: float = 1.0, glow: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var main: Color = ch["main"]
	var wing: Color = ch["wing"]
	var accent: Color = ch["accent"]
	var m := base * _t(0.0, Vector2(facing * scale, scale), Vector2(x, y + sin(t * 5.0) * 2.0))
	ci.draw_set_transform_matrix(m)

	if glow > 0.0:
		Sketch.draw_glow(ci, Vector2.ZERO, 40.0, Color(1.0, 0.925, 0.588, 0.7 * glow))

	# крылья (взмахи)
	var flap := sin(t * 28.0)
	var wy := 0.55 + 0.45 * absf(flap)
	# верхнее крыло: от плеча назад-вверх, нижнее — назад-вниз
	ci.draw_set_transform_matrix(m * _t(0.6, Vector2(1.0, wy), Vector2(-2, -3)))
	Sketch.s_ellipse(ci, -14, 0, 14, 7, 11, wing, 1.2)
	ci.draw_set_transform_matrix(m * _t(-0.5, Vector2(1.0, wy), Vector2(-2, 0)))
	Sketch.s_ellipse(ci, -11, 0, 11, 6, 17, wing, 1.2)
	ci.draw_set_transform_matrix(m)

	# длинные волосы (за телом)
	hair_back(ci, t, ch["id"])
	# платье, ножки, ручка, голова
	Sketch.s_poly(ci, Sketch.v([0, -3, -9, 14, 9, 14]), 21, true, main, 1.5, 0.8)
	Sketch.s_line(ci, -3, 14, -4, 21, 23, 1.2)
	Sketch.s_line(ci, 3, 14, 5, 20, 24, 1.2)
	Sketch.s_line(ci, 0, 0, 9, 5 + sin(t * 6.0) * 2.0, 25, 1.2)
	Sketch.s_circle(ci, 0, -10, 7, 31, SKIN, 1.5)
	ci.draw_circle(Vector2(3, -11), 1.1, Sketch.GRAPHITE)
	ci.draw_circle(Vector2(2.5, -7.6), 1.8, Color(0.94, 0.47, 0.51, 0.35))
	hair_front(ci, ch["id"])

	# аксессуар каждого вида фей
	match ch["id"]:
		"flower":
			for i in 5:
				var a := float(i) / 5.0 * TAU
				Sketch.s_circle(ci, -1 + cos(a) * 4, -19 + sin(a) * 3, 2.8, 50 + i, main, 0.8)
			Sketch.s_circle(ci, -1, -19, 2, 56, accent, 0.8)
		"water":
			Sketch.s_poly(ci, Sketch.v([0, -26, -4, -18, 4, -18]), 60, true, wing, 1.0, 0.5)
		"night":
			var pts := PackedVector2Array()
			for i in 9:
				var a := lerpf(PI * 0.2, PI * 1.3, i / 8.0)
				pts.append(Vector2(1 + cos(a) * 5, -20 + sin(a) * 5))
			for i in 9:
				var a := lerpf(PI * 1.3, PI * 0.2, i / 8.0)
				pts.append(Vector2(3 + cos(a) * 4, -21 + sin(a) * 4))
			ci.draw_colored_polygon(pts, accent)
			Sketch.stroke_closed(ci, pts, Sketch.GRAPHITE, 1.0)
		"frost":
			Sketch.s_poly(ci, Sketch.v([-6, -16, -4, -23, -1, -17, 1, -25, 3, -17, 6, -22, 6, -15]), 70, false, null, 1.1, 0.5)
		"star":
			Sketch.s_line(ci, 9, 5, 16, -6, 80, 1.3)
			Sketch.s_poly(ci, Sketch.star_pts(17, -8, 5, 2.2, 5, t * 2.0), 81, true, accent, 1.0, 0.4)
		"mushroom":
			Sketch.s_poly(ci, Sketch.v([-9, -15, -6, -21, 0, -24, 6, -21, 9, -15]), 90, true, main, 1.2, 0.4)
			for dp in [Vector2(-3, -19), Vector2(3, -20), Vector2(0, -17)]:
				ci.draw_circle(dp, 1.3, Color("#fff4dc"))
		"rainbow":
			var cols := [Color("#e8504a"), Color("#f2c230"), Color("#3a8fd6")]
			for i in 3:
				ci.draw_arc(Vector2(0, -12), 11 - i * 2, PI * 1.1, PI * 1.9, 12, cols[i], 1.8, true)
		"garden":
			Sketch.s_line(ci, 0, -16, 2, -21, 95, 1.1)
			Sketch.s_ellipse(ci, 5, -23, 5, 2.6, 96, main, 1.0)
		"storm":
			Sketch.s_poly(ci, Sketch.v([3, -30, -3, -21, 1, -21, -2, -14, 6, -24, 2, -24]), 98, true, accent, 1.0, 0.3)
	ci.draw_set_transform_matrix(base)


const WASHES := {
	"flower": [Color(1.0, 0.863, 0.902, 0.35), Color(0.784, 0.922, 0.706, 0.35)],
	"water": [Color(0.784, 0.902, 1.0, 0.35), Color(0.588, 0.824, 0.902, 0.4)],
	"night": [Color(0.235, 0.196, 0.431, 0.5), Color(0.118, 0.118, 0.235, 0.55)],
	"frost": [Color(0.863, 0.941, 1.0, 0.5), Color(0.941, 0.98, 1.0, 0.3)],
	"star": [Color(0.157, 0.118, 0.314, 0.55), Color(0.353, 0.235, 0.471, 0.45)],
	"mushroom": [Color(0.92, 0.8, 0.667, 0.42), Color(0.588, 0.45, 0.314, 0.42)],
	"rainbow": [Color(1.0, 0.92, 0.824, 0.35), Color(0.804, 0.941, 1.0, 0.38)],
	"garden": [Color(0.941, 0.98, 0.824, 0.35), Color(0.725, 0.882, 0.549, 0.4)],
	"storm": [Color(0.412, 0.451, 0.588, 0.55), Color(0.275, 0.314, 0.431, 0.55)],
}
const HILL_FILL := {"flower": Color("#9cc97a"), "water": Color("#7fb8a0"), "night": Color("#3a3560"), "frost": Color("#bcd9ec"), "star": Color("#2c2450"), "mushroom": Color("#a88a58"), "rainbow": Color("#a8d890"), "garden": Color("#8cc063"), "storm": Color("#56648a")}
const GROUND_FILL := {"flower": Color("#7fbf5a"), "water": Color("#5aa0c8"), "night": Color("#2a2848"), "frost": Color("#e6f4ff"), "star": Color("#3b2f5c"), "mushroom": Color("#8a6a45"), "rainbow": Color("#98cf7a"), "garden": Color("#7a5a3a"), "storm": Color("#4a5a76")}


## Фон главы (рисуется один раз и кэшируется Godot до следующего queue_redraw)
static func scene(ci: CanvasItem, ch: Dictionary, W: float, H: float, ground: float) -> void:
	Sketch.freeze_boil(true)
	var id: String = ch["id"]
	var gy := H - ground
	var rnd := func(i: float) -> float: return Sketch.hash1(i * 3.3 + 1.7)
	var soft := Color(0.149, 0.133, 0.125, 0.45)

	# бумага
	ci.draw_rect(Rect2(0, 0, W, H), Sketch.PAPER)
	ci.draw_texture_rect(Sketch.paper_tex(), Rect2(0, 0, W, H), true)
	# цветная размывка
	var w: Array = WASHES[id]
	var c1: Color = w[0]
	var c2: Color = w[1]
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]), PackedColorArray([c1, c1, c2, c2]))

	# дальние холмы / горы
	var pts: Array = []
	var steps := int(ceil(W / 60.0)) + 1
	for i in steps + 1:
		var x := i * 60.0
		var y: float
		if id == "frost":
			y = gy - 120 - ((120 + rnd.call(i) * 80) if i % 2 == 0 else (20 + rnd.call(i) * 30))
		else:
			y = gy - 70 - sin(i * 0.7) * 30 - rnd.call(i) * 30
		pts.append_array([x, y])
	var hill := pts.duplicate()
	hill.append_array([W, gy, 0, gy])
	Sketch.s_poly(ci, Sketch.v(hill), 5, true, HILL_FILL[id], 1.2, 2.0, soft)
	if id == "frost":
		var i := 0
		while i < steps:
			var x: float = pts[i * 2]
			var y: float = pts[i * 2 + 1]
			Sketch.s_poly(ci, Sketch.v([x - 22, y + 30, x, y, x + 22, y + 30]), 90 + i, false, null, 1.2, 1.5, soft)
			i += 2

	# небо
	if id == "night" or id == "star":
		for i in 60:
			var x: float = rnd.call(i + 100) * W
			var y: float = rnd.call(i + 200) * (gy - 150)
			var r: float = 1.0 + rnd.call(i + 300) * 2.5
			var sc := Color("#ffe89a") if id == "star" else Color("#f5f0c0")
			Sketch.s_poly(ci, Sketch.star_pts(x, y, r * 2, r * 0.7, 4, 0), 300 + i, true, sc, 0.6, 0.3, Color(1, 0.98, 0.863, 0.6))
		Sketch.s_circle(ci, W * 0.82, 90, 42, 400, Color("#f5eeb8"), 1.5, Color(1, 0.98, 0.863, 0.8))
		Sketch.s_circle(ci, W * 0.82 + 10, 80, 8, 401, null, 1.0, Color(0.353, 0.314, 0.157, 0.4))
		Sketch.s_circle(ci, W * 0.82 - 14, 100, 5, 402, null, 1.0, Color(0.353, 0.314, 0.157, 0.4))
	else:
		if id == "rainbow":
			var rc := [Color("#e8504a"), Color("#f08a2c"), Color("#f2c230"), Color("#6fb04e"), Color("#3a8fd6"), Color("#7a6cd6")]
			for i in rc.size():
				var c: Color = rc[i]
				c.a = 0.5
				ci.draw_arc(Vector2(W * 0.5, gy + 40), minf(W * 0.45, gy * 0.9) - i * 9, PI * 1.05, PI * 1.95, 48, c, 9.0, true)
		if id == "storm":
			for i in 7:
				var cx := i / 6.0 * W
				var cy: float = 40 + rnd.call(i + 900) * 40
				for k in 3:
					Sketch.s_circle(ci, cx + k * 30 - 30, cy + (k % 2) * 10, 34 + (k % 2) * 10, 910 + i * 5 + k, Color("#56607e"), 1.4, soft)
		if id != "frost" and id != "storm":
			Sketch.s_circle(ci, W * 0.85, 80, 34, 410, Color("#f7d060"), 1.4, soft)
			for i in 10:
				var a := float(i) / 10.0 * TAU
				Sketch.s_line(ci, W * 0.85 + cos(a) * 44, 80 + sin(a) * 44, W * 0.85 + cos(a) * 58, 80 + sin(a) * 58, 420 + i, 1.2, soft)
		for i in 4:
			var cx: float = rnd.call(i + 500) * W * 0.75
			var cy: float = 60 + rnd.call(i + 510) * 120
			for k in 4:
				Sketch.s_circle(ci, cx + k * 22, cy + (k % 2) * -8, 18 + (k % 2) * 6, 520 + i * 7 + k, null, 1.1, soft)

	# земля
	var gp: Array = []
	var gx := -10.0
	while gx <= W + 20:
		gp.append_array([gx, gy + sin(gx * 0.02) * 4])
		gx += 40.0
	gp.append_array([W + 20, H + 10, -10, H + 10])
	Sketch.s_poly(ci, Sketch.v(gp), 600, true, GROUND_FILL[id], 1.8, 1.5)

	# травинки / камыши / сугробы
	var n := int(W / 18.0)
	for i in n:
		var x: float = i * 18 + rnd.call(i + 700) * 10
		var y := gy + sin(x * 0.02) * 4
		if id == "water":
			if i % 3 == 0:
				var yy: float = y + 14 + rnd.call(i) * 20
				Sketch.s_line(ci, x, yy, x + 14, yy, 700 + i, 1.0, Color(1, 1, 1, 0.7))
			if i % 5 == 0:
				Sketch.s_line(ci, x, y, x + 3, y - 30 - rnd.call(i) * 20, 710 + i, 1.4, soft)
		elif id == "frost":
			if i % 4 == 0:
				Sketch.s_line(ci, x, y + 10, x + 20, y + 12, 700 + i, 1.0, soft)
		else:
			var gc := Color(0.784, 0.745, 1.0, 0.35) if (id == "night" or id == "star") else (Color(0.843, 0.882, 0.96, 0.4) if id == "storm" else Color(0.157, 0.314, 0.118, 0.6))
			Sketch.s_line(ci, x, y, x - 3 + rnd.call(i) * 6, y - 8 - rnd.call(i + 1) * 10, 700 + i, 1.1, gc)

	if id == "garden":
		var fx := 20.0
		while fx < W:
			Sketch.s_poly(ci, Sketch.v([fx - 5, gy + 2, fx - 5, gy - 44, fx, gy - 52, fx + 5, gy - 44, fx + 5, gy + 2]), 850 + fx, true, Color("#d8c49a"), 1.2, 0.8)
			fx += 46.0
		Sketch.s_line(ci, 0, gy - 30, W, gy - 30, 870, 1.6, soft, 3)
		Sketch.s_line(ci, 0, gy - 14, W, gy - 14, 871, 1.6, soft, 3)
	if id == "mushroom":
		var mx := [W * 0.16, W * 0.84, W * 0.5]
		for k in 3:
			var x: float = mx[k]
			var h := 34.0 + k * 6
			Sketch.s_poly(ci, Sketch.v([x - 7, gy, x - 5, gy - h, x + 5, gy - h, x + 7, gy]), 880 + k, true, Color("#f3e6c8"), 1.3, 0.8)
			Sketch.s_poly(ci, Sketch.v([x - 26, gy - h + 4, x - 18, gy - h - 16, x, gy - h - 22, x + 18, gy - h - 16, x + 26, gy - h + 4]), 885 + k, true, Color("#c8643a"), 1.4, 1.0)
	# деревья
	if id == "flower" or id == "night" or id == "water" or id == "mushroom":
		var tx := [W * 0.06, W * 0.94]
		for k in 2:
			var x: float = tx[k]
			Sketch.s_poly(ci, Sketch.v([x - 8, gy, x - 5, gy - 110, x + 5, gy - 110, x + 8, gy]), 800 + k, true, Color("#8a6a4a"), 1.5, 1.5)
			var leaf := Color("#2f3a55") if id == "night" else (Color("#6fae7a") if id == "water" else (Color("#d98a3a") if id == "mushroom" else Color("#5ea34a")))
			Sketch.s_circle(ci, x, gy - 140, 46, 810 + k, leaf, 1.6)
			Sketch.s_circle(ci, x - 26, gy - 115, 28, 820 + k, leaf, 1.3)
			Sketch.s_circle(ci, x + 26, gy - 118, 30, 830 + k, leaf, 1.3)

	# виньетка
	var big := maxf(W, H) * 1.5
	ci.draw_texture_rect(Sketch.vignette_tex(), Rect2(W * 0.5 - big * 0.5, H * 0.5 - big * 0.5, big, big), false)
	Sketch.freeze_boil(false)
