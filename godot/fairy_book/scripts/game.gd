extends Node2D
## Движок «Книги Фей» — порт src/game/engine.ts один в один.

signal chapter_cleared(idx: int, bonus: int, score: int)
signal game_over(score: int, chapter: int)

const DrawProxy := preload("res://scripts/draw_proxy.gd")
const DarkShader := preload("res://shaders/darkness.gdshader")

const GROUND := 46.0
const MAXS := 330.0
const DASH_SPEED := 960.0
const HAZARDS := ["wasp", "flame", "spark", "moth", "icicle", "orb", "spider", "spore", "inkbub", "bug", "beetle", "bolt"]
const LIGHT_TEXT := Color("#f3ecdc")
const LIGHT_STROKE := Color(0.941, 0.902, 1.0, 0.9)
## каждые N выполненных целей в бесконечном режиме — сердце
const ENDLESS_HEART_EVERY := 10


class Ent:
	var kind := ""
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var r := 0.0
	var t := 0.0
	var seed := 0.0
	var hp := 1
	var a := 0.0
	var b := 0.0
	var d := 0.0 # доп. данные (глубина паука и т.п.)
	var dead := false


class Part:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var max_life := 1.0
	var size := 2.0
	var color := Color.WHITE
	var kind := 0 # 0 точка, 1 искра, 2 кольцо, 3 текст, 4 лепесток, 5 штрих
	var g := 0.0
	var rot := 0.0
	var text := ""


enum St { IDLE, PLAY, PAUSED, CLEAR, DYING, OVER }

var W := 960.0
var H := 540.0
var state: St = St.IDLE
var state_before_pause: St = St.PLAY
var state_t := 0.0
var time := 0.0
var ch_t := 0.0
var ch_idx := 0
var score := 0
var display_score := 0.0
var hearts := 3
## режим: "story" | "chapter" | "endless" | "hard"
var mode := "story"
## купленные в лавке улучшения
var upgrades := Shop.empty()
var shield := 0
var paint := 0 # радужная глава: текущая краска
var seq_next := 0 # грибная глава: хоровод
var ring_t := 0.0
var ring_max := 1.0
var ring_c := Vector2.ZERO
var ring_r := 100.0
var wave := 0
var next_heart_at := ENDLESS_HEART_EVERY
var combo := 0
var combo_t := 0.0
var progress := 0
var last_bonus := 0
var ents: Array[Ent] = []
var parts: Array[Part] = []
var shake := 0.0
var hitstop := 0.0
var flash := 0.0
var timers := {}
var wind := 0.0
var wind_t := 0.0
var followers := 0
var trail: Array[Vector2] = []
var seed_counter := 1

# игрок
var px := 200.0
var py := 270.0
var pvx := 0.0
var pvy := 0.0
var pr := 11.0
var facing := 1.0
var dash_t := 0.0
var dash_cd := 0.0
var inv := 0.0
var carry := 0
var pdx := 1.0
var pdy := 0.0

# ввод
var dash_queued := false
var touch_mode := false
var joy_active := false
var joy_id := -1
var joy_o := Vector2.ZERO
var joy_p := Vector2.ZERO
var dash_btn_id := -1

# слои
var bg_node: Node2D
var world_node: Node2D
var dark_rect: ColorRect
var glow_node: Node2D
var flash_rect: ColorRect
var hud_node: Node2D


func ch() -> Dictionary:
	return Chapters.get_ch(ch_idx)


func cid() -> String:
	return ch()["id"]


func gy() -> float:
	return H - GROUND


func is_dark() -> bool:
	return cid() == "night" or cid() == "star" or cid() == "storm"


func _ready() -> void:
	bg_node = DrawProxy.new()
	bg_node.fn = _draw_bg
	add_child(bg_node)
	world_node = DrawProxy.new()
	world_node.fn = _draw_world
	add_child(world_node)
	dark_rect = ColorRect.new()
	dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = DarkShader
	dark_rect.material = sm
	dark_rect.visible = false
	add_child(dark_rect)
	glow_node = DrawProxy.new()
	glow_node.fn = _draw_glow
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_node.material = add
	add_child(glow_node)
	flash_rect = ColorRect.new()
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(0.784, 0.196, 0.157, 0)
	add_child(flash_rect)
	hud_node = DrawProxy.new()
	hud_node.fn = _draw_hud
	add_child(hud_node)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _on_resize() -> void:
	var s := get_viewport_rect().size
	W = s.x
	H = s.y
	dark_rect.size = s
	flash_rect.size = s + Vector2(40, 40)
	flash_rect.position = Vector2(-20, -20)
	px = clampf(px, 20, W - 20)
	py = clampf(py, 20, gy() - 20)
	for e in ents:
		if e.kind == "sprout":
			e.x = W / 2
		if e.kind == "paint":
			e.x = W * ((e.a + 0.5) / 3.0)
			e.y = gy() - 18
		if e.kind == "nest":
			e.x = W - 70 if e.b > 0 else 70.0
			e.y = gy() - 40
		if e.kind == "bud" or e.kind == "lantern":
			e.x = minf(e.x, W - 40)
			e.y = minf(e.y, gy() - 40)
	bg_node.queue_redraw()


# ================================================================= API

func preview(idx: int) -> void:
	ch_idx = idx
	state = St.IDLE
	ents.clear()
	bg_node.queue_redraw()


func new_run(m: String = "") -> void:
	if m != "":
		mode = m
	score = 0
	display_score = 0.0
	hearts = max_start_hearts()
	combo = 0


func max_start_hearts() -> int:
	return 1 if mode == "hard" else 3 + int(upgrades["heart"])


func dash_cd_max() -> float:
	return 0.45 * (1.0 - 0.12 * int(upgrades["dash"]))


## можно ли подобрать предмет (для магнита)
func can_pick(e: Ent) -> bool:
	match e.kind:
		"pollen":
			return carry < 6
		"drop":
			return carry < 5
		"shard", "sun":
			return carry < 3
		"firefly":
			return e.b <= 0
		"flake", "crystal":
			return true
	return false


func is_endless() -> bool:
	return mode == "endless"


func score_mult() -> int:
	return 2 if mode == "hard" else 1


## перезапуск текущего режима (одиночная глава / бесконечный — та же глава)
func restart() -> void:
	var idx := ch_idx if (mode == "chapter" or mode == "endless") else 0
	new_run()
	start_chapter(idx)


func start_chapter(idx: int) -> void:
	ch_idx = idx
	bg_node.queue_redraw()
	ents.clear()
	parts.clear()
	progress = 0
	wave = 0
	next_heart_at = ENDLESS_HEART_EVERY
	followers = 0
	wind = 0.0
	wind_t = 6.0
	ch_t = 0.0
	combo = 0
	combo_t = 0.0
	shake = 0.0
	hitstop = 0.0
	timers = {}
	px = W * 0.3
	py = H * 0.5
	pvx = 0.0
	pvy = 0.0
	dash_t = 0.0
	dash_cd = 0.0
	inv = 1.2
	carry = 0
	shield = 1 if (mode != "hard" and int(upgrades["shield"]) > 0) else 0
	paint = 0
	seq_next = 0
	facing = 1.0
	trail.clear()
	dash_queued = false
	_init_chapter()
	state = St.PLAY
	burst(px, py, 24, ch()["wing"], 220, 1)
	ring(px, py, 60, ch()["main"])


## второй шанс после рекламы с вознаграждением
func revive() -> void:
	hearts = max_start_hearts()
	inv = 2.5
	pvx = 0.0
	pvy = 0.0
	dash_t = 0.0
	shake = 0.0
	flash = 0.0
	hitstop = 0.0
	dash_queued = false
	for e in ents:
		if HAZARDS.has(e.kind) and Vector2(e.x - px, e.y - py).length() < 260:
			e.dead = true
			burst(e.x, e.y, 8, ch()["wing"], 160, 1)
	state = St.PLAY
	burst(px, py, 40, ch()["wing"], 300, 1)
	ring(px, py, 120, ch()["main"])
	pop_text(px, py - 40, "Второй шанс!", ch()["main"], 32)
	Sfx.play("bloom")


func pause() -> void:
	if state == St.PLAY or state == St.CLEAR:
		state_before_pause = state
		state = St.PAUSED


func resume() -> void:
	if state == St.PAUSED:
		state = state_before_pause


# ================================================================= ввод

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.pressed and not k.echo:
			match k.physical_keycode:
				KEY_SPACE, KEY_SHIFT, KEY_J, KEY_X:
					dash_queued = true
			touch_mode = false
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and state == St.PLAY:
			dash_queued = true
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			if st.index == joy_id:
				joy_active = false
				joy_id = -1
			if st.index == dash_btn_id:
				dash_btn_id = -1
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		if joy_active and sd.index == joy_id:
			joy_p = sd.position
			var d := joy_p - joy_o
			if d.length() > 70.0:
				joy_o = joy_p - d.normalized() * 70.0


func _dash_btn() -> Vector3:
	return Vector3(W - 78, H - 92, 50)


func _touch_down(index: int, pos: Vector2) -> void:
	touch_mode = true
	var b := _dash_btn()
	if pos.distance_to(Vector2(b.x, b.y)) < b.z + 25:
		dash_queued = true
		dash_btn_id = index
		return
	if not joy_active:
		joy_active = true
		joy_id = index
		joy_o = pos
		joy_p = pos
	else:
		dash_queued = true # второй палец — рывок


# ================================================================= helpers

func spawn(kind: String, x: float, y: float, r: float) -> Ent:
	var e := Ent.new()
	e.kind = kind
	e.x = x
	e.y = y
	e.r = r
	e.seed = seed_counter * 1.618
	seed_counter += 1
	ents.append(e)
	return e


func count(kind: String) -> int:
	var n := 0
	for e in ents:
		if e.kind == kind and not e.dead:
			n += 1
	return n


func rand_pos(margin: float = 60.0) -> Vector2:
	for i in 10:
		var p := Vector2(randf_range(margin, W - margin), randf_range(110, gy() - 50))
		if p.distance_to(Vector2(px, py)) > 110:
			return p
	return Vector2(randf_range(margin, W - margin), randf_range(110, gy() - 50))


func touching(e: Ent, extra: float = 0.0) -> bool:
	var r := e.r + pr + extra
	var dx := e.x - px
	var dy := e.y - py
	return dx * dx + dy * dy < r * r


func add_particle(q: Part) -> void:
	if parts.size() > 450:
		parts.pop_front()
	parts.append(q)


func _part(x: float, y: float, vx: float, vy: float, life: float, size: float, col: Color, kind: int, g: float) -> Part:
	var q := Part.new()
	q.x = x
	q.y = y
	q.vx = vx
	q.vy = vy
	q.life = life
	q.max_life = life
	q.size = size
	q.color = col
	q.kind = kind
	q.g = g
	q.rot = randf() * 6.0
	return q


func burst(x: float, y: float, n: int, col: Color, speed: float = 180.0, kind: int = 0, g: float = 0.0) -> void:
	for i in n:
		var a := randf() * TAU
		var sp := speed * (0.3 + randf() * 0.7)
		add_particle(_part(x, y, cos(a) * sp, sin(a) * sp, 0.4 + randf() * 0.5, 2.0 + randf() * 3.0, col, kind, g))


func ring(x: float, y: float, size: float, col: Color) -> void:
	add_particle(_part(x, y, 0, 0, 0.45, size, col, 2, 0))


func pop_text(x: float, y: float, s: String, col: Color = Sketch.INK, size: float = 22.0) -> void:
	var q := _part(x, y, 0, -60, 0.9, size, col, 3, 0)
	q.text = s
	add_particle(q)


func add_score(pts: int, x: float, y: float, col: Color) -> int:
	combo += 1
	combo_t = 2.4
	var mult := mini(5, 1 + combo / 5)
	var v := pts * mult * score_mult()
	score += v
	pop_text(x, y - 14, "+" + str(v) + ((" ×" + str(mult)) if mult > 1 else ""), col, 18 + mult * 2)
	return v


func collect(e: Ent, pts: int, col: Color) -> void:
	e.dead = true
	add_score(pts, e.x, e.y, col)
	burst(e.x, e.y, 12, col, 200, 1)
	ring(e.x, e.y, 26, col)
	Sfx.pickup(combo)
	shake = maxf(shake, 2.0)


## force — урон, от которого не спасает неуязвимость (съеденный росток)
func damage(force: bool = false) -> bool:
	if (not force and (inv > 0 or dash_t > 0)) or state != St.PLAY:
		return false
	if shield > 0:
		shield = 0
		inv = 1.0
		shake = 10.0
		hitstop = 0.06
		burst(px, py, 24, Color("#e86a92"), 240, 4, 120)
		ring(px, py, 70, Color("#e86a92"))
		pop_text(px, py - 30, "Щит!", Color("#e86a92"), 26)
		Sfx.play("crash")
		return true
	hearts -= 1
	inv = 1.5
	shake = 16.0
	hitstop = 0.1
	flash = 0.35
	combo = 0
	burst(px, py, 26, Color("#d8433b"), 260, 0, 200)
	burst(px, py, 10, Sketch.INK, 200, 5)
	Sfx.play("hit")
	var id := cid()
	if id == "flower" or id == "water":
		carry = maxi(0, carry - 2)
	if id == "night" and followers > 0:
		for i in followers:
			var f := spawn("firefly", px, py, 8)
			f.a = randf() * 6.0
			var ang := randf() * TAU
			f.vx = cos(ang) * 220
			f.vy = sin(ang) * 220
			f.b = 0.8
		pop_text(px, py - 30, "Светлячки разлетелись!", Color("#7a6cd6"), 20)
		followers = 0
	if id == "star":
		carry = 0
	if id == "garden":
		carry = maxi(0, carry - 1)
	if hearts <= 0:
		state = St.DYING
		state_t = 1.1
		shake = 24.0
		burst(px, py, 50, ch()["wing"], 320, 1)
		Sfx.play("over")
	return true


func _t(k: String) -> float:
	return float(timers.get(k, 0.0))


# ================================================================= главы

func _init_chapter() -> void:
	var g := gy()
	match cid():
		"flower":
			for i in 5:
				var x := W * ((i + 0.5) / 5.0) + randf_range(-20, 20)
				var y := g - 50 - randf() * minf(160, H * 0.25)
				spawn("bud", x, y, 20)
			for i in 4:
				var a := float(i) / 4.0 * TAU
				spawn("pollen", px + cos(a) * 90 + 60, py + sin(a) * 70, 9).a = randf() * 6
			timers["wasp"] = 3.0
		"water":
			for i in 3:
				spawn("drop", px + 80 + i * 60, py - 40 + i * 30, 9).a = randf() * 6
			spawn("flame", px + 260, py + 20, 6).b = 2.0
			timers["flame"] = 1.5
		"night":
			spawn("lantern", W / 2, maxf(110, H * 0.2), 28)
			for i in 3:
				var p := rand_pos()
				spawn("firefly", p.x, p.y, 8).a = randf() * 6
			spawn("firefly", px + 90, py - 20, 8)
			timers["moth"] = 4.0
		"frost":
			for i in 5:
				var f := spawn("flake", px + 60 + i * 50, randf_range(80, 200), 10)
				f.vy = randf_range(40, 70)
				f.a = randf() * 6
			timers["icicle"] = 2.5
			timers["flake"] = 0.3
			timers["crystal"] = 7.0
		"star":
			var boss := spawn("boss", W * 0.7, H * 0.3, 46)
			boss.hp = 6
			for i in 3:
				spawn("shard", px + 70 + i * 55, py + (-40 if i % 2 == 1 else 40), 10).a = randf() * 6
			timers["attack"] = 3.0
			timers["shard"] = 1.0
		"mushroom":
			new_ring(true)
			timers["spider"] = 4.0
			timers["spore"] = 7.0
			timers["wrong"] = 0.0
		"rainbow":
			for i in 3:
				spawn("paint", W * ((i + 0.5) / 3.0), g - 18, 24).a = i
			for i in 4:
				var bb := spawn("bubble", px + 90 + i * 55, py + (30 if i % 2 == 1 else -30), 16)
				bb.a = 0 if i < 3 else 1
				bb.vy = -18
				bb.b = randf() * 6
			timers["bubble"] = 0.6
			timers["ink"] = 5.0
		"garden":
			spawn("sprout", W / 2, g - 20, 26).hp = 5
			for i in 3:
				spawn("sun", px + 70 + i * 50, py - 40 + i * 20, 10).a = randf() * 6
			timers["bug"] = 3.0
			timers["sun"] = 1.0
		"storm":
			spawn("nest", W - 70, g - 40, 38).b = 1
			spawn("seed", px + 60, py, 13)
			for i in 2:
				var p := rand_pos(90)
				spawn("seed", p.x, minf(p.y, g - 90), 13)
			timers["bolt"] = 3.5


func _update_chapter(dt: float) -> void:
	var t := ch_t
	var playing := state == St.PLAY
	for k in timers.keys():
		timers[k] = float(timers[k]) - dt

	match cid():
		"flower":
			if playing and count("pollen") < 5 and randf() < dt * 3:
				var p := rand_pos()
				spawn("pollen", p.x, p.y, 9).a = randf() * 6
			var max_w := mini(4, 1 + int(t / 12))
			if playing and _t("wasp") <= 0 and count("wasp") < max_w:
				var side := -30.0 if randf() < 0.5 else W + 30
				spawn("wasp", side, randf_range(100, gy() - 100), 14)
				timers["wasp"] = 3.5
		"water":
			if playing and count("drop") < 5 and randf() < dt * 2.5:
				var p := rand_pos()
				spawn("drop", p.x, p.y, 9).a = randf() * 6
			if playing and _t("flame") <= 0 and count("flame") < 6:
				var p := rand_pos()
				spawn("flame", p.x, maxf(p.y, H * 0.35), 6).b = randf_range(1.5, 2.5)
				timers["flame"] = maxf(1.1, 2.4 - t * 0.02)
		"night":
			if playing and count("firefly") < 3 and randf() < dt * 1.2:
				var p := rand_pos()
				spawn("firefly", p.x, p.y, 8).a = randf() * 6
			var max_m := mini(5, 2 + int(t / 15))
			if playing and _t("moth") <= 0 and count("moth") < max_m:
				var side := -30.0 if randf() < 0.5 else W + 30
				spawn("moth", side, randf_range(120, gy() - 60), 16).a = randf() * 6
				timers["moth"] = 3.0
		"frost":
			if playing and _t("flake") <= 0:
				var f := spawn("flake", randf_range(30, W - 30), -20, 10)
				f.vy = randf_range(45, 85)
				f.a = randf() * 6
				timers["flake"] = 0.5
			if playing and _t("crystal") <= 0:
				spawn("crystal", randf_range(60, W - 60), -30, 16).vy = 55
				timers["crystal"] = 8.0
			if playing and _t("icicle") <= 0:
				var rows := 3 if (t > 20 and randf() < 0.4) else 1
				var bx := (px + randf_range(-60, 60)) if randf() < 0.5 else randf_range(40, W - 40)
				for i in rows:
					var ic := spawn("icicle", clampf(bx + (i - (rows - 1) / 2.0) * 70, 20, W - 20), -10, 10)
					ic.a = 0.9
				timers["icicle"] = maxf(0.55, 1.4 - t * 0.015)
			wind_t -= dt
			if wind_t <= 0:
				if wind == 0:
					wind = (-1.0 if randf() < 0.5 else 1.0) * 190.0
					wind_t = 2.5
					pop_text(W / 2, 120, "Ветер →" if wind > 0 else "← Ветер", Color("#4fa3cf"), 28)
				else:
					wind = 0.0
					wind_t = randf_range(4, 7)
			if wind != 0 and randf() < dt * 30:
				var x := -20.0 if wind > 0 else W + 20
				add_particle(_part(x, randf_range(60, gy()), wind * 4, 0, 0.8, 40 + randf() * 40, Color(0.314, 0.471, 0.627, 0.5), 5, 0))
		"star":
			if playing and count("shard") < 2 and _t("shard") <= 0:
				var p := rand_pos()
				spawn("shard", p.x, p.y, 10).a = randf() * 6
				timers["shard"] = 1.2
		"mushroom":
			if playing:
				ring_t -= dt
				if ring_t <= 0:
					pop_text(W / 2, 120, "Хоровод рассыпался!", Color("#b0603a"), 28)
					combo = 0
					Sfx.play("crash")
					for e in ents:
						if e.kind == "shroom" and not e.dead:
							burst(e.x, e.y, 8, Color("#c8b890"), 120, 0, -40)
					new_ring()
			var max_s := mini(4, 1 + int(t / 14))
			if playing and _t("spider") <= 0 and count("spider") < max_s:
				var x := randf_range(40, W - 40)
				if absf(x - px) < 50:
					x = fmod(x + W / 2, W - 80) + 40
				var sp := spawn("spider", x, -20, 13)
				sp.d = randf_range(140, gy() - 50)
				sp.a = randf() * 6
				timers["spider"] = 3.4
			if playing and _t("spore") <= 0 and count("spore") < 2:
				var left := randf() < 0.5
				spawn("spore", -50.0 if left else W + 50, randf_range(130, gy() - 70), 48).vx = 45.0 if left else -45.0
				timers["spore"] = 8.0
		"rainbow":
			if playing and _t("bubble") <= 0 and count("bubble") < 9:
				var r := randf()
				var col := -1 if r < 0.08 else (paint if r < 0.5 else randi() % 3)
				var bb := spawn("bubble", randf_range(40, W - 40), gy() + 20, randf_range(14, 19))
				bb.a = col
				bb.vy = -randf_range(38, 60) - minf(30, t * 0.4)
				bb.b = randf() * 6
				timers["bubble"] = maxf(0.4, 0.85 - t * 0.005)
			var max_i := mini(5, 1 + int(t / 12))
			if playing and _t("ink") <= 0 and count("inkbub") < max_i:
				var ib := spawn("inkbub", randf_range(40, W - 40), gy() + 20, 16)
				ib.vy = -randf_range(50, 85)
				timers["ink"] = 3.0
		"garden":
			if playing and count("sun") < 3 and _t("sun") <= 0:
				spawn("sun", randf_range(50, W - 50), randf_range(90, maxf(120, gy() * 0.55)), 10).a = randf() * 6
				timers["sun"] = 1.4
			var max_b := mini(6, 1 + int(t / 10))
			if playing and _t("bug") <= 0 and count("bug") + count("beetle") < max_b:
				var left := randf() < 0.5
				if t > 15 and randf() < 0.4:
					spawn("beetle", -30.0 if left else W + 30, randf_range(80, gy() * 0.5), 13)
				else:
					spawn("bug", -30.0 if left else W + 30, gy() - 10, 14).vx = 1.0 if left else -1.0
				timers["bug"] = maxf(1.4, 3.2 - t * 0.03)
		"storm":
			if playing and count("seed") < 3 and randf() < dt * 0.9:
				var p := rand_pos(80)
				var sd := spawn("seed", p.x, minf(p.y, gy() - 90), 13)
				burst(sd.x, sd.y, 8, Color.WHITE, 90, 1)
			if playing and _t("bolt") <= 0:
				var n := 2 if (t > 25 and randf() < 0.45) else 1
				for i in n:
					var x := clampf(px + randf_range(-50, 50), 30, W - 30) if i == 0 else randf_range(30, W - 30)
					spawn("bolt", x, 0, 28).a = 1.1
				timers["bolt"] = maxf(1.3, 3.0 - t * 0.03)
			if randf() < dt * 45:
				add_particle(_part(randf_range(0, W + 60), -10, -60, 520, 1.2, 1, Color(0.784, 0.843, 0.941, 0.55), 6, 0))

	var main: Color = ch()["main"]
	var accent: Color = ch()["accent"]
	var mag_r := (50.0 + 28.0 * int(upgrades["magnet"])) if int(upgrades["magnet"]) > 0 else 0.0
	var sprout: Ent = null
	var nest: Ent = null
	for e in ents:
		if e.kind == "sprout":
			sprout = e
		elif e.kind == "nest":
			nest = e
	for e in ents:
		if e.dead:
			continue
		e.t += dt
		# магнит из лавки
		if mag_r > 0 and can_pick(e):
			var md := Vector2(px - e.x, py - e.y)
			var ml := md.length()
			if ml < mag_r and ml > 1:
				var mk := minf(1, dt * 7)
				e.x += md.x * mk
				e.y += md.y * mk
		match e.kind:
			"pollen", "drop", "shard":
				e.a += dt
				e.y += sin(e.a * 2.5) * 12 * dt
				if touching(e, 8):
					if e.kind == "pollen":
						if carry < 6:
							carry += 1
							collect(e, 10, accent)
					elif e.kind == "drop":
						if carry < 5:
							carry += 1
							collect(e, 10, Color("#3a8fd6"))
					else:
						if carry < 3:
							carry += 1
							collect(e, 20, Color("#e0a526"))
							if carry == 3:
								pop_text(px, py - 36, "Заряжена! Рывок в Короля!", Color("#b58cff"), 22)
								ring(px, py, 70, Color("#ffe89a"))
								Sfx.play("bloom")
			"bud":
				# бесконечный режим: цветок снова становится бутоном
				if is_endless() and e.b == 1 and e.t > 2.5:
					e.b = 0
					e.a = 0
					burst(e.x, e.y, 10, Color("#6fb04e"), 120, 4, 60)
				if e.b == 0 and carry > 0 and touching(e, 4):
					e.a += carry
					add_score(15 * carry, e.x, e.y, Color("#e86a92"))
					carry = 0
					burst(e.x, e.y, 10, Color("#f2c230"), 150, 1)
					Sfx.pickup(combo)
					if e.a >= 3:
						e.b = 1
						e.t = 0
						progress += 1
						add_score(100, e.x, e.y - 20, Color("#e86a92"))
						burst(e.x, e.y, 30, Color("#e86a92"), 280, 4, 120)
						burst(e.x, e.y, 16, Color("#f2c230"), 200, 1)
						ring(e.x, e.y, 80, Color("#e86a92"))
						shake = 8.0
						Sfx.play("bloom")
			"wasp":
				var dx := px - e.x
				var dy := py - e.y
				var d := maxf(0.001, sqrt(dx * dx + dy * dy))
				var sp := minf(230, 140 + t * 2)
				if e.b > 0:
					e.b -= dt
					e.vx *= 0.95
					e.vy *= 0.95
				else:
					e.vx += dx / d * 260 * dt
					e.vy += dy / d * 260 * dt + sin(e.t * 6) * 60 * dt
					var vv := sqrt(e.vx * e.vx + e.vy * e.vy)
					if vv > sp:
						e.vx *= sp / vv
						e.vy *= sp / vv
				e.x += e.vx * dt
				e.y += e.vy * dt
				enemy_contact(e, 25, Color("#f2c230"))
			"flame":
				e.a = minf(1, e.a + dt / 1.5)
				e.r = 6 + e.a * 16
				e.b -= dt
				if e.b <= 0 and e.a >= 1 and state == St.PLAY:
					e.b = randf_range(1.6, 2.6)
					for i in 3:
						var ang := -PI / 2 + (i - 1) * 0.6 + randf_range(-0.15, 0.15)
						var s := spawn("spark", e.x, e.y - 10, 5)
						s.vx = cos(ang) * 170
						s.vy = sin(ang) * 170
				if randf() < dt * 8:
					add_particle(_part(e.x + randf_range(-6, 6), e.y - e.r * 0.6, 0, -50, 0.5, 2, Color("#f08a2c"), 0, -20))
				if touching(e, -4):
					if carry > 0:
						carry -= 1
						e.dead = true
						progress += 1
						add_score(50, e.x, e.y, Color("#3a8fd6"))
						burst(e.x, e.y, 24, Color(0.627, 0.667, 0.706, 0.8), 160, 0, -60)
						burst(e.x, e.y, 14, Color("#9fd3f5"), 240, 1)
						ring(e.x, e.y, 60, Color("#3a8fd6"))
						shake = 7.0
						hitstop = 0.04
						Sfx.play("splash")
					else:
						damage()
			"spark":
				e.vy += 140 * dt
				e.x += e.vx * dt
				e.y += e.vy * dt
				if e.y > gy() or e.t > 4:
					e.dead = true
					burst(e.x, e.y, 4, Color("#f08a2c"), 60)
				if touching(e, -3) and damage():
					e.dead = true
			"firefly":
				e.a += dt * (0.8 + sin(e.seed) * 0.5)
				if e.b > 0:
					e.b -= dt
					e.vx *= 0.96
					e.vy *= 0.96
				else:
					e.vx = cos(e.a) * 40
					e.vy = sin(e.a * 1.3) * 30
				e.x = clampf(e.x + e.vx * dt, 20, W - 20)
				e.y = clampf(e.y + e.vy * dt, 80, gy() - 20)
				if e.b <= 0 and touching(e, 10):
					followers += 1
					collect(e, 20, Color("#f5e27a"))
			"lantern":
				if followers > 0 and touching(e, 8):
					var n := followers
					progress += n
					add_score(40 * n, e.x, e.y - 20, Color("#f5e27a"))
					followers = 0
					burst(e.x, e.y, 20 + n * 6, Color("#f5e27a"), 260, 1)
					ring(e.x, e.y, 90, Color("#f5e27a"))
					shake = 6.0 + n
					e.a = 1
					Sfx.play("bloom")
				e.a = maxf(0, e.a - dt)
			"moth":
				var light := 130.0 + followers * 14
				var dx := px - e.x
				var dy := py - e.y
				var d := maxf(0.001, sqrt(dx * dx + dy * dy))
				e.a += dt
				var tx: float
				var ty: float
				if e.b > 0:
					e.b -= dt
					tx = -dx / d * 120
					ty = -dy / d * 120
				elif d < light + 90:
					var sp := 165.0 + minf(40, t)
					tx = dx / d * sp
					ty = dy / d * sp
				else:
					tx = cos(e.a * 0.7 + e.seed) * 90 + (W / 2 - e.x) * 0.2
					ty = sin(e.a * 1.1 + e.seed) * 70 + (H / 2 - e.y) * 0.2
				e.vx += (tx - e.vx) * minf(1, dt * 2.5)
				e.vy += (ty - e.vy) * minf(1, dt * 2.5)
				e.x += e.vx * dt
				e.y += e.vy * dt
				enemy_contact(e, 30, Color("#7a6cd6"))
			"flake", "crystal":
				e.a += dt
				e.x += (sin(e.a * 2) * 30 + wind * 0.6) * dt
				e.y += e.vy * dt
				if e.y > gy() + 10:
					e.dead = true
				if touching(e, 10):
					var big := e.kind == "crystal"
					progress += 3 if big else 1
					collect(e, 60 if big else 15, Color("#4fa3cf") if big else Color("#9ad8f0"))
					if big:
						ring(e.x, e.y, 70, Color("#4fa3cf"))
						Sfx.play("bloom")
			"icicle":
				if e.a > 0:
					e.a -= dt
					if e.a <= 0:
						Sfx.play("crash")
				else:
					e.vy += 1500 * dt
					e.y += e.vy * dt
					if e.y > gy() - 10:
						e.dead = true
						burst(e.x, gy() - 5, 14, Color("#bfe6fa"), 220, 5, 400)
						burst(e.x, gy() - 5, 8, Color.WHITE, 160, 1)
						shake = maxf(shake, 3.0)
					if touching(e, -2) and damage():
						e.dead = true
			"boss":
				_update_boss(e, dt)
			# ---------- VI. грибной хоровод
			"shroom":
				if e.b == 0 and touching(e, 6) and state == St.PLAY:
					if int(e.a) == seq_next:
						e.b = 1
						e.t = 0
						seq_next += 1
						add_score(10 * seq_next, e.x, e.y, Color("#b0603a"))
						burst(e.x, e.y, 10, Color("#f7d060"), 160, 1)
						ring(e.x, e.y, 30, Color("#f7d060"))
						Sfx.pickup(combo)
						if seq_next >= 5:
							progress += 1
							add_score(150 + int(round(ring_t * 10)), ring_c.x, ring_c.y, main)
							for o in ents:
								if o.kind == "shroom":
									burst(o.x, o.y, 14, Color("#f7d060"), 220, 4, 60)
							ring(ring_c.x, ring_c.y, ring_r + 30, main)
							shake = 8.0
							Sfx.play("bloom")
							if is_endless() or progress < int(ch()["goal"]):
								new_ring()
					elif _t("wrong") <= 0:
						timers["wrong"] = 0.8
						for o in ents:
							if o.kind == "shroom":
								o.b = 0
						seq_next = 0
						combo = 0
						burst(e.x, e.y, 16, Color("#b8a878"), 150, 0, -30)
						pop_text(e.x, e.y - 30, "Не по порядку!", Color("#8a3b3b"), 22)
						shake = maxf(shake, 4.0)
						Sfx.play("nocharge")
			"spider":
				if e.t < 14:
					var target := 40.0 + (e.d - 40.0) * (0.55 + 0.45 * sin(e.t * 1.4 + e.a))
					var k := minf(1, e.t / 1.2)
					e.y = -20 + (target + 20) * k
				else:
					e.y -= 220 * dt
					if e.y < -30:
						e.dead = true
				enemy_contact(e, 30, Color("#6a4a3a"))
			"spore":
				e.x += e.vx * dt
				e.y += sin(e.t * 0.8 + e.seed) * 10 * dt
				if e.t > 2 and (e.x < -70 or e.x > W + 70):
					e.dead = true
			# ---------- VII. краски радуги
			"paint":
				if paint != int(e.a) and touching(e, 4):
					paint = int(e.a)
					var c: Color = Chapters.PAINTS[paint]["c"]
					burst(px, py, 18, c, 200, 0, 60)
					ring(px, py, 40, c)
					pop_text(px, py - 34, str(Chapters.PAINTS[paint]["n"]) + "!", c, 22)
					Sfx.play("splash")
			"bubble":
				e.y += e.vy * dt
				e.x += sin(e.t * 2 + e.b) * 22 * dt
				if e.y < -30:
					e.dead = true
				elif touching(e, 2) and state == St.PLAY:
					var ca := int(e.a)
					if ca == -1 or ca == paint:
						var rb := ca == -1
						progress += 3 if rb else 1
						collect(e, 60 if rb else 20, Color("#b58cff") if rb else Chapters.PAINTS[ca]["c"])
						if rb:
							ring(e.x, e.y, 60, Color("#f2c230"))
					else:
						e.dead = true
						progress = maxi(0, progress - 1)
						combo = 0
						var dv := Vector2(px - e.x, py - e.y).normalized()
						pvx = dv.x * 380
						pvy = dv.y * 380
						burst(e.x, e.y, 12, Chapters.PAINTS[ca]["c"], 180, 0)
						pop_text(e.x, e.y - 24, "Не тот цвет! −1", Color("#8a3b3b"), 22)
						shake = maxf(shake, 5.0)
						Sfx.play("nocharge")
			"inkbub":
				e.y += e.vy * dt
				e.x += sin(e.t * 3 + e.seed) * 26 * dt
				if e.y < -30:
					e.dead = true
				else:
					enemy_contact(e, 25, Sketch.INK)
			# ---------- VIII. первый росток
			"sun":
				e.a += dt
				e.y += sin(e.a * 2.2) * 10 * dt
				if carry < 3 and touching(e, 8):
					carry += 1
					collect(e, 15, Color("#f2a03a"))
			"sprout":
				var gr := minf(1, float(progress) / (24.0 if is_endless() else float(ch()["goal"])))
				e.r = 24 + gr * 18
				e.y = gy() - 18 - gr * 50
				e.a = maxf(0, e.a - dt)
				if carry > 0 and touching(e, 10) and state == St.PLAY:
					var n := carry
					progress += n
					e.hp = mini(5, e.hp + 1)
					add_score(30 * n, e.x, e.y - 30, Color("#5c9e3a"))
					carry = 0
					e.a = 1
					burst(e.x, e.y, 16 + n * 6, Color("#f2a03a"), 220, 1)
					burst(e.x, e.y, 10, Color("#6fb04e"), 160, 4, 80)
					ring(e.x, e.y, 70, Color("#f2a03a"))
					shake = 5.0 + n
					Sfx.play("bloom")
			"bug":
				var sp := 42.0 + minf(40, t * 0.8)
				var tx := sprout.x if sprout else W / 2
				var dir := signf(tx - e.x)
				if dir == 0:
					dir = 1.0
				e.vx = dir
				e.x += dir * sp * dt
				e.y = gy() - 10 - absf(sin(e.t * 6)) * 2
				if sprout and absf(e.x - sprout.x) < 16:
					bite_sprout(e, sprout)
				else:
					enemy_contact(e, 20, Color("#6fb04e"))
			"beetle":
				var tx := sprout.x if sprout else W / 2
				var ty := sprout.y if sprout else gy() - 30
				var dv := Vector2(tx - e.x, ty - e.y)
				var dl := maxf(0.001, dv.length())
				var sp := 80.0 + minf(40, t * 0.6)
				e.vx = dv.x / dl * sp
				e.vy = dv.y / dl * sp + sin(e.t * 5) * 30
				e.x += e.vx * dt
				e.y += e.vy * dt
				if sprout and dl < sprout.r + e.r - 6:
					bite_sprout(e, sprout)
				else:
					enemy_contact(e, 30, Color("#3a3a5a"))
			# ---------- IX. семена ветра
			"seed":
				e.vx *= 0.985
				e.vy *= 0.985
				e.vy += sin(e.t * 1.5 + e.seed) * 10 * dt
				e.x += e.vx * dt
				e.y += e.vy * dt
				if e.x < e.r:
					e.x = e.r
					e.vx = absf(e.vx) * 0.7
				if e.x > W - e.r:
					e.x = W - e.r
					e.vx = -absf(e.vx) * 0.7
				if e.y < 30:
					e.y = 30
					e.vy = absf(e.vy) * 0.7
				if e.y > gy() - e.r:
					e.y = gy() - e.r
					e.vy = -absf(e.vy) * 0.7
				var dv := Vector2(e.x - px, e.y - py)
				var dl := dv.length()
				var min_d := e.r + pr + 4
				if dl < min_d and dl > 0.01 and state != St.DYING:
					var nv := dv / dl
					e.x = px + nv.x * min_d
					e.y = py + nv.y * min_d
					var pv := pvx * nv.x + pvy * nv.y
					var push := maxf(140, pv * (1.5 if dash_t > 0 else 1.15))
					e.vx = nv.x * push + pvx * 0.15
					e.vy = nv.y * push + pvy * 0.15
					if e.a <= 0:
						burst(e.x, e.y, 5, Color.WHITE, 90, 1)
						Sfx.play("click", 1.1)
						e.a = 0.25
				e.a -= dt
				if nest and Vector2(e.x - nest.x, e.y - nest.y).length() < nest.r:
					e.dead = true
					progress += 1
					add_score(80, nest.x, nest.y - 30, main)
					burst(nest.x, nest.y, 20, Color.WHITE, 220, 1)
					ring(nest.x, nest.y, 60, accent)
					shake = 6.0
					nest.a = 1
					Sfx.play("bloom")
					if progress % 3 == 0 and (is_endless() or progress < int(ch()["goal"])):
						move_nest(nest)
			"nest":
				e.a = maxf(0, e.a - dt)
			"bolt":
				if e.a > 0:
					e.a -= dt
					if e.a <= 0:
						e.b = 0.28
						shake = maxf(shake, 7.0)
						burst(e.x, gy() - 4, 18, Color("#f7e36a"), 260, 1, 200)
						Sfx.play("boom")
						for sd in ents:
							if sd.kind == "seed" and not sd.dead and absf(sd.x - e.x) < e.r + sd.r:
								sd.dead = true
								burst(sd.x, sd.y, 10, Color("#c8c0b0"), 140, 0, -40)
								pop_text(sd.x, sd.y - 20, "Пых!", Color("#5a6fa8"), 20)
				else:
					e.b -= dt
					if absf(px - e.x) < e.r + pr - 4:
						damage()
					if e.b <= 0:
						e.dead = true
			"orb":
				e.x += e.vx * dt
				e.y += e.vy * dt
				if e.x < -40 or e.x > W + 40 or e.y < -40 or e.y > H + 40:
					e.dead = true
				if touching(e, -3) and damage():
					e.dead = true

	ents = ents.filter(func(x: Ent) -> bool: return not x.dead)
	if is_endless():
		_update_endless()
	elif state == St.PLAY and progress >= int(ch()["goal"]):
		_clear_chapter()


## бесконечный режим: сердца за прогресс, новые волны Короля Теней
func _update_endless() -> void:
	if state != St.PLAY:
		return
	if progress >= next_heart_at:
		next_heart_at += ENDLESS_HEART_EVERY
		wave += 1
		if hearts < 5:
			hearts += 1
			pop_text(px, py - 40, "+1 ♥", Color("#d8433b"), 30)
		else:
			score += 200
			pop_text(px, py - 40, "Волна %d! +200" % (wave + 1), ch()["main"], 26)
		ring(px, py, 80, Color("#d8433b"))
		Sfx.play("bloom")
	if cid() == "star" and count("boss") == 0:
		if not timers.has("boss"):
			timers["boss"] = 2.5
		if _t("boss") <= 0:
			timers.erase("boss")
			var side := W * 0.2 if randf() < 0.5 else W * 0.8
			spawn("boss", side, -60, 46).hp = 6
			pop_text(W / 2, 120, "Король Теней вернулся!", Color("#b58cff"), 30)
			shake = 10.0
			Sfx.play("boom")


## грибная глава: новый хоровод из 5 грибов
func new_ring(first: bool = false) -> void:
	for e in ents:
		if e.kind == "shroom":
			e.dead = true
	var R := maxf(70, minf(minf(120, W * 0.18), (gy() - 130) * 0.4))
	var c := Vector2(px + R + 40, py) if first else rand_pos(R + 40)
	c.x = clampf(c.x, R + 30, W - R - 30)
	c.y = clampf(c.y, R * 0.8 + 90, gy() - R * 0.8 - 30)
	# по кругу или «звёздочкой» (номера вразброс)
	var pattern := [0, 1, 2, 3, 4] if (first or randf() < 0.4) else [0, 3, 1, 4, 2]
	var off := randf() * TAU
	var dir := 1.0 if randf() < 0.5 else -1.0
	for i in 5:
		var a := off + dir * (i / 5.0) * TAU
		spawn("shroom", c.x + cos(a) * R, c.y + sin(a) * R * 0.8, 16).a = pattern[i]
	ring_c = c
	ring_r = R
	seq_next = 0
	ring_max = maxf(7, 15 - progress * 1.2)
	ring_t = ring_max
	ring(c.x, c.y, R, ch()["main"])


## садовая глава: вредитель добрался до ростка
func bite_sprout(e: Ent, sp: Ent) -> void:
	e.dead = true
	if state != St.PLAY:
		return
	sp.hp -= 1
	burst(sp.x, sp.y, 12, Color("#6fb04e"), 180, 4, 120)
	pop_text(sp.x, sp.y - 40, "Хрум! −листик", Color("#8a3b3b"), 22)
	shake = maxf(shake, 6.0)
	Sfx.play("nocharge")
	if sp.hp <= 0:
		sp.hp = 3
		pop_text(sp.x, sp.y - 64, "Росток без листьев!", Color("#c8433b"), 24)
		damage(true)


## грозовая глава: гнездо перелетает на другую сторону
func move_nest(n: Ent) -> void:
	burst(n.x, n.y, 14, Color("#d8c49a"), 160, 0)
	n.b = 0.0 if n.b > 0 else 1.0
	n.x = W - 70 if n.b > 0 else 70.0
	ring(n.x, n.y, 60, ch()["accent"])
	pop_text(n.x, n.y - 50, "Гнездо перелетело!", ch()["main"], 22)


## true — враг сбит рывком
func enemy_contact(e: Ent, pts: int, col: Color) -> bool:
	if not touching(e, -2):
		return false
	if dash_t > 0:
		e.dead = true
		add_score(pts, e.x, e.y, col)
		burst(e.x, e.y, 22, col, 280, 1)
		burst(e.x, e.y, 10, Sketch.INK, 220, 5)
		ring(e.x, e.y, 50, col)
		shake = 9.0
		hitstop = 0.06
		Sfx.play("kill")
		return true
	if damage():
		e.vx = -e.vx * 1.5
		e.vy = -e.vy * 1.5
		e.b = 0.8
	return false


func _update_boss(e: Ent, dt: float) -> void:
	var rage := 1.0 + (6 - e.hp) * 0.12 + wave * 0.1
	e.a += dt * rage
	var tx := W / 2 + cos(e.a * 0.6) * W * 0.3
	var ty := maxf(130, H * 0.28) + sin(e.a * 1.1) * minf(90, H * 0.12)
	e.x += (tx - e.x) * minf(1, dt * 2)
	e.y += (ty - e.y) * minf(1, dt * 2)
	e.b = maxf(0, e.b - dt)
	if state != St.PLAY:
		return
	if _t("attack") <= 0:
		var pat := randi() % 3
		var sp := 150.0 + (6 - e.hp) * 12
		if pat == 0:
			var n := 10 + (6 - e.hp)
			var off := randf() * 6
			for i in n:
				var a := off + float(i) / n * TAU
				var o := spawn("orb", e.x, e.y, 9)
				o.vx = cos(a) * sp
				o.vy = sin(a) * sp
		elif pat == 1:
			var base := atan2(py - e.y, px - e.x)
			for i in range(-2, 3):
				var o := spawn("orb", e.x, e.y, 9)
				o.vx = cos(base + i * 0.22) * sp * 1.3
				o.vy = sin(base + i * 0.22) * sp * 1.3
		else:
			for i in 14:
				var a := i * 0.45
				var s2 := sp * (0.6 + i * 0.05)
				var o := spawn("orb", e.x, e.y, 8)
				o.vx = cos(a) * s2
				o.vy = sin(a) * s2
		ring(e.x, e.y, 70, Color("#2a2040"))
		Sfx.play("boss_shot")
		timers["attack"] = maxf(0.9 if is_endless() else 1.2, 2.6 - (6 - e.hp) * 0.22 - wave * 0.1)
	if touching(e, -6):
		if dash_t > 0 and carry >= 3 and e.b <= 0:
			e.hp -= 1
			e.b = 0.8
			progress += 1
			carry = 0
			add_score(300, e.x, e.y - 40, Color("#b58cff"))
			burst(e.x, e.y, 40, Color("#ffe89a"), 360, 1)
			burst(e.x, e.y, 20, Color("#2a2040"), 300, 5)
			ring(e.x, e.y, 110, Color("#b58cff"))
			shake = 22.0
			hitstop = 0.16
			flash = 0.25
			Sfx.play("boom")
			var d := Vector2(px - e.x, py - e.y).normalized()
			pvx = d.x * 600
			pvy = d.y * 600
			dash_t = 0.0
			inv = 0.8
			if e.hp <= 0:
				e.dead = true
				for i in 4:
					burst(e.x, e.y, 30, Color("#ffe89a") if i % 2 == 1 else Color("#b58cff"), 420, 1)
		elif dash_t <= 0:
			if damage():
				var d := Vector2(px - e.x, py - e.y).normalized()
				pvx = d.x * 500
				pvy = d.y * 500
		elif carry < 3 and e.b <= 0:
			e.b = 0.5
			pop_text(e.x, e.y - 60, "Нужен заряд!", Sketch.INK, 22)
			Sfx.play("nocharge")


func _clear_chapter() -> void:
	state = St.CLEAR
	state_t = 2.2
	for e in ents:
		if HAZARDS.has(e.kind) or e.kind == "boss":
			e.dead = true
			burst(e.x, e.y, 8, ch()["wing"], 150, 1)
	var time_bonus := maxi(0, int((120.0 - ch_t) * 4.0))
	last_bonus = 500 + hearts * 100 + time_bonus
	score += last_bonus
	pop_text(W / 2, H / 2 - 20, "Глава пройдена!", ch()["main"], 46)
	pop_text(W / 2, H / 2 + 30, "Бонус +" + str(last_bonus), Sketch.INK, 28)
	for i in 5:
		burst(randf_range(0, W), randf_range(0, H * 0.6), 20, ch()["main"] if i % 2 == 1 else ch()["accent"], 260, 4 if i % 2 == 1 else 1, 80)
	shake = 10.0
	Sfx.play("win")


# ================================================================= цикл

func _process(delta: float) -> void:
	var dt := minf(0.033, delta)
	time += dt
	Sketch.set_boil(time)
	if state != St.PAUSED:
		if state == St.IDLE:
			_update_idle(dt)
		else:
			_update(dt)
		_update_particles(dt)
	# тряска — только мир и фон, HUD неподвижен
	var off := Vector2.ZERO
	if shake > 0:
		off = Vector2((randf() - 0.5) * shake, (randf() - 0.5) * shake)
	bg_node.position = off
	world_node.position = off
	glow_node.position = off
	var night := cid() == "night" and state != St.IDLE
	dark_rect.visible = night
	glow_node.visible = night
	if night:
		var sm := dark_rect.material as ShaderMaterial
		sm.set_shader_parameter("light_pos", Vector2(px, py))
		sm.set_shader_parameter("light_radius", 130.0 + followers * 14)
	flash_rect.color.a = flash * 0.5
	world_node.queue_redraw()
	hud_node.queue_redraw()
	if night:
		glow_node.queue_redraw()


func _update_idle(dt: float) -> void:
	var tx := W / 2 + cos(time * 0.7) * W * 0.3
	var ty := H * 0.45 + sin(time * 1.4) * H * 0.15
	pvx = (tx - px) * 3
	facing = 1.0 if pvx >= 0 else -1.0
	px += (tx - px) * minf(1, dt * 3)
	py += (ty - py) * minf(1, dt * 3)
	if randf() < dt * 30:
		_trail_spark()
	shake *= 0.9


func _trail_spark() -> void:
	var q := _part(px - facing * 8 + randf_range(-4, 4), py + randf_range(-6, 6), -pvx * 0.1 + randf_range(-20, 20), randf_range(-10, 30), 0.6, 1.5 + randf() * 2.5, ch()["wing"], 1 if randf() < 0.3 else 0, 20)
	add_particle(q)


func _update(dt: float) -> void:
	if hitstop > 0:
		hitstop -= dt
		return
	var sdt := dt
	if state == St.DYING:
		sdt *= 0.25
		state_t -= dt
		if state_t <= 0:
			state = St.OVER
			game_over.emit(score, ch_idx)
			return
	elif state == St.CLEAR:
		state_t -= dt
		if randf() < dt * 6:
			burst(randf_range(0, W), randf_range(0, H * 0.7), 14, ch()["main"] if randf() < 0.5 else ch()["accent"], 200, 1, 40)
		if state_t <= 0:
			state = St.IDLE
			if mode != "hard":
				hearts = mini(5, hearts + 1)
			chapter_cleared.emit(ch_idx, last_bonus, score)
			return
	elif state == St.OVER:
		return
	ch_t += sdt
	_update_player(sdt)
	_update_chapter(sdt)
	if combo_t > 0:
		combo_t -= sdt
		if combo_t <= 0:
			combo = 0
	shake = maxf(0, shake - dt * 60)
	flash = maxf(0, flash - dt)


func _update_player(dt: float) -> void:
	var ix := 0.0
	var iy := 0.0
	var can_control := state == St.PLAY or state == St.CLEAR
	if can_control:
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
			ix -= 1
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
			ix += 1
		if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
			iy -= 1
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
			iy += 1
		if joy_active:
			var d := joy_p - joy_o
			var l := d.length()
			if l > 6:
				var m := minf(1, l / 50)
				ix = d.x / l * m
				iy = d.y / l * m
	var len := sqrt(ix * ix + iy * iy)
	if len > 1:
		ix /= len
		iy /= len
	if len > 0.1:
		pdx = ix / len
		pdy = iy / len
	if dash_queued and dash_cd <= 0 and state == St.PLAY:
		var dx := pdx if len > 0.1 else facing
		var dy := pdy if len > 0.1 else 0.0
		pvx = dx * DASH_SPEED
		pvy = dy * DASH_SPEED
		dash_t = 0.17
		dash_cd = dash_cd_max()
		shake = maxf(shake, 3.0)
		ring(px, py, 36, ch()["wing"])
		Sfx.play("dash")
	dash_queued = false

	if dash_t > 0:
		dash_t -= dt
		add_particle(_part(px, py, 0, 0, 0.25, 14, ch()["main"], 0, 0))
		if randf() < 0.7:
			_trail_spark()
	else:
		var slow := 1.0
		if cid() == "mushroom":
			for e in ents:
				if e.kind == "spore" and Vector2(e.x - px, e.y - py).length() < e.r:
					slow = 0.5
					break
		var maxs := MAXS * (1.0 + 0.07 * int(upgrades["speed"])) * slow
		var k := 1.0 - exp(-dt * 14)
		pvx += (ix * maxs - pvx) * k
		pvy += (iy * maxs - pvy) * k
	px += (pvx + wind) * dt
	py += pvy * dt
	var r := pr + 4
	if px < r:
		px = r
		pvx = absf(pvx) * 0.3
	if px > W - r:
		px = W - r
		pvx = -absf(pvx) * 0.3
	if py < r + 10:
		py = r + 10
		pvy = absf(pvy) * 0.3
	if py > gy() - r:
		py = gy() - r
		pvy = -absf(pvy) * 0.3
	if absf(ix) > 0.15:
		facing = 1.0 if ix > 0 else -1.0
	elif dash_t > 0 and absf(pvx) > 50:
		facing = 1.0 if pvx > 0 else -1.0
	dash_cd -= dt
	inv -= dt
	if Vector2(pvx, pvy).length() > 60 and randf() < dt * 40:
		_trail_spark()
	trail.push_front(Vector2(px, py))
	if trail.size() > 200:
		trail.pop_back()


func _update_particles(dt: float) -> void:
	var alive: Array[Part] = []
	for q in parts:
		q.life -= dt
		if q.life <= 0:
			continue
		q.vy += q.g * dt
		q.x += q.vx * dt
		q.y += q.vy * dt
		if q.kind != 3 and q.kind < 5:
			q.vx *= 0.96
			q.vy *= 0.96
		q.rot += dt * 4
		alive.append(q)
	parts = alive
	display_score += (score - display_score) * minf(1, dt * 10)
	if absf(score - display_score) < 1:
		display_score = score


# ================================================================= рендер

func _draw_bg(ci: CanvasItem) -> void:
	FairyDraw.scene(ci, ch(), W, H, GROUND)


func _draw_world(ci: CanvasItem) -> void:
	_draw_under(ci)
	for e in ents:
		_draw_ent(ci, e)
	if followers > 0:
		for i in followers:
			var ti := mini(trail.size() - 1, (i + 1) * 7)
			if ti >= 0:
				var tp := trail[ti]
				_draw_firefly(ci, tp.x + sin(time * 5 + i) * 4, tp.y + cos(time * 4 + i) * 4, i + 900)
	var visible_p := state != St.OVER
	var blink := inv > 0 and state == St.PLAY and int(floor(time * 20)) % 2 == 0
	if visible_p and not blink:
		var glow := (0.7 + sin(time * 10) * 0.3) if (cid() == "star" and carry >= 3) else 0.0
		var squash := 1.15 if dash_t > 0 else 1.0
		if cid() == "rainbow":
			var ac: Color = Chapters.PAINTS[paint]["c"]
			ac.a = 0.35 + sin(time * 6) * 0.1
			ci.draw_circle(Vector2(px, py), 24, ac)
		FairyDraw.fairy(ci, px, py, time, ch(), facing, 1.25 * squash, glow)
		if shield > 0:
			for i in 6:
				var a := time * 3 + i / 6.0 * TAU
				Sketch.s_ellipse(ci, px + cos(a) * 28, py + sin(a) * 28, 6, 4, 700 + i, Color("#e86a92"), 0.9)
	_draw_particles(ci)


## подложка: таймер хоровода, подсказка к гнезду
func _draw_under(ci: CanvasItem) -> void:
	if cid() == "mushroom" and count("shroom") > 0:
		var frac := maxf(0, ring_t / ring_max)
		ci.draw_set_transform(ring_c, 0, Vector2(1, 0.8))
		ci.draw_arc(Vector2.ZERO, ring_r, 0, TAU, 48, Color(0.353, 0.235, 0.157, 0.3), 1.5, true)
		if state == St.PLAY:
			var c: Color = Color("#c8433b") if frac < 0.3 else ch()["main"]
			c.a = 0.7
			ci.draw_arc(Vector2.ZERO, ring_r + 26, -PI / 2, -PI / 2 + TAU * frac, 48, c, 4.0, true)
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if cid() == "storm" and ch_t < 7 and state == St.PLAY:
		var nest: Ent = null
		var best: Ent = null
		var bd := INF
		for e in ents:
			if e.kind == "nest":
				nest = e
			elif e.kind == "seed":
				var d := Vector2(e.x - px, e.y - py).length()
				if d < bd:
					bd = d
					best = e
		if nest and best:
			ci.draw_dashed_line(Vector2(best.x, best.y), Vector2(nest.x, nest.y), Color(0.969, 0.89, 0.416, 0.7), 2.0, 7.0)


func _draw_glow(ci: CanvasItem) -> void:
	for e in ents:
		if e.kind == "firefly" or e.kind == "lantern":
			var rr := (70 + e.a * 40) if e.kind == "lantern" else 26.0
			Sketch.draw_glow(ci, Vector2(e.x, e.y), rr, Color(1, 0.9, 0.47, 0.55))
		elif e.kind == "moth":
			ci.draw_circle(Vector2(e.x - 4, e.y - 3), 2, Color(1, 0.235, 0.314, 0.8))
			ci.draw_circle(Vector2(e.x + 4, e.y - 3), 2, Color(1, 0.235, 0.314, 0.8))


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, rot: float, col: Color) -> void:
	ci.draw_set_transform(c, rot, Vector2(rx, ry))
	ci.draw_circle(Vector2.ZERO, 1.0, col)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_firefly(ci: CanvasItem, x: float, y: float, seed: float) -> void:
	var fl := 0.6 + sin(time * 8 + seed) * 0.4
	ci.draw_circle(Vector2(x, y), 12, Color(1, 0.9, 0.43, 0.35 * fl))
	Sketch.s_circle(ci, x, y, 4, seed, Color("#f5e27a"), 1.0)
	Sketch.s_ellipse(ci, x - 3, y - 5, 4, 2, seed + 1, null, 0.8)
	Sketch.s_ellipse(ci, x + 3, y - 5, 4, 2, seed + 2, null, 0.8)


func _draw_ent(ci: CanvasItem, e: Ent) -> void:
	var t := time
	match e.kind:
		"pollen":
			ci.draw_circle(Vector2(e.x, e.y), 14 + sin(t * 5 + e.seed) * 2, Color(0.949, 0.761, 0.188, 0.25))
			Sketch.s_circle(ci, e.x, e.y, 7, e.seed, Color("#f2c230"), 1.3)
			for i in 3:
				ci.draw_rect(Rect2(e.x - 3 + i * 2.5, e.y - 1 + (i % 2) * 2, 1.4, 1.4), Sketch.GRAPHITE_SOFT)
		"bud":
			var g := gy()
			Sketch.s_line(ci, e.x, e.y + 14, e.x + sin(e.seed) * 10, g, e.seed, 1.8, Color(0.157, 0.353, 0.118, 0.85), 6)
			Sketch.s_ellipse(ci, e.x + 10, (e.y + g) / 2, 9, 4, e.seed + 2, Color("#6fb04e"), 1.1)
			if e.b == 0:
				var pulse := 1.0 + sin(t * 3 + e.seed) * 0.05
				Sketch.s_poly(ci, Sketch.v([e.x - 13 * pulse, e.y + 8, e.x - 8, e.y - 14, e.x, e.y - 20 * pulse, e.x + 8, e.y - 14, e.x + 13 * pulse, e.y + 8]), e.seed, true, Color("#e8a0b8"), 1.5, 1.0)
				Sketch.s_poly(ci, Sketch.v([e.x - 13, e.y + 8, e.x, e.y + 14, e.x + 13, e.y + 8]), e.seed + 5, false, null, 1.4, 1.0)
				for i in 3:
					var a := -PI / 2 + (i - 1) * 0.7
					Sketch.s_circle(ci, e.x + cos(a) * 32, e.y + sin(a) * 32, 4, e.seed + 10 + i, Color("#f2c230") if i < e.a else null, 1.0)
			else:
				var open := minf(1, e.t * 3)
				var sc := 0.5 + open * 0.5 + (0.0 if open < 1 else sin(t * 2 + e.seed) * 0.04)
				for i in 7:
					var a := float(i) / 7.0 * TAU + t * 0.2
					Sketch.s_ellipse(ci, e.x + cos(a) * 16 * sc, e.y + sin(a) * 16 * sc, 11 * sc, 11 * sc, e.seed + i, Color("#e86a92"), 1.2)
				Sketch.s_circle(ci, e.x, e.y, 9 * sc, e.seed + 20, Color("#f2c230"), 1.4)
		"wasp":
			var f := 1.0 if e.vx >= 0 else -1.0
			var wf := 0.4 + absf(sin(t * 40)) * 0.6
			ci.draw_set_transform(Vector2(e.x, e.y), 0, Vector2(f, wf))
			Sketch.s_ellipse(ci, -2, -12, 8, 6, e.seed + 1, Color(0.784, 0.863, 0.941), 1.0)
			ci.draw_set_transform(Vector2(e.x, e.y), 0, Vector2(f, 1))
			Sketch.s_ellipse(ci, 0, 0, 14, 8, e.seed, Color("#f2c230"), 1.6)
			Sketch.s_line(ci, -4, -7, -4, 7, e.seed + 2, 2.5, Color(0.118, 0.102, 0.094, 0.85), 1)
			Sketch.s_line(ci, 3, -7, 3, 7, e.seed + 3, 2.5, Color(0.118, 0.102, 0.094, 0.85), 1)
			Sketch.s_poly(ci, Sketch.v([-13, -2, -21, 0, -13, 3]), e.seed + 4, true, Sketch.INK, 1.2, 0.5)
			Sketch.s_circle(ci, 14, -2, 5, e.seed + 5, Color("#3a3430"), 1.2)
			ci.draw_circle(Vector2(16, -3), 1.5, Color("#d8433b"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"drop":
			var s := 1.0 + sin(t * 4 + e.seed) * 0.06
			Sketch.s_poly(ci, Sketch.v([e.x, e.y - 12 * s, e.x - 7, e.y + 1, e.x - 5, e.y + 7, e.x, e.y + 9, e.x + 5, e.y + 7, e.x + 7, e.y + 1]), e.seed, true, Color("#5aa8e6"), 1.3, 0.6)
			ci.draw_rect(Rect2(e.x - 3, e.y - 1, 2, 4), Color(1, 1, 1, 0.8))
		"flame":
			var r := e.r
			var fl := sin(t * 14 + e.seed) * 0.12
			ci.draw_circle(Vector2(e.x, e.y), r * 1.6, Color(1, 0.549, 0.157, 0.18))
			Sketch.s_poly(ci, Sketch.v([e.x, e.y - r * (1.6 + fl), e.x - r * 0.8, e.y - r * 0.1, e.x - r * 0.6, e.y + r * 0.7, e.x + r * 0.6, e.y + r * 0.7, e.x + r * 0.8, e.y - r * 0.1]), e.seed, true, Color("#f08a2c"), 1.5, 1.2)
			Sketch.s_poly(ci, Sketch.v([e.x, e.y - r * (0.8 - fl), e.x - r * 0.35, e.y + r * 0.2, e.x, e.y + r * 0.55, e.x + r * 0.35, e.y + r * 0.2]), e.seed + 3, true, Color("#f7d060"), 1.0, 0.8)
		"spark":
			Sketch.s_circle(ci, e.x, e.y, 5, e.seed, Color("#f08a2c"), 1.1)
			ci.draw_circle(Vector2(e.x, e.y), 9, Color(1, 0.627, 0.235, 0.3))
		"firefly":
			_draw_firefly(ci, e.x, e.y, e.seed)
		"lantern":
			var x := e.x
			var y := e.y
			var lc := Color(0.941, 0.902, 1.0, 0.9)
			Sketch.s_line(ci, x, y - 30, x, y - 60, e.seed + 1, 1.3, Color(0.902, 0.863, 1.0, 0.7))
			Sketch.s_poly(ci, Sketch.v([x - 16, y - 26, x + 16, y - 26, x + 20, y + 22, x - 20, y + 22]), e.seed, true, Color("#f5e27a"), 1.8, 1.0, lc)
			Sketch.s_poly(ci, Sketch.v([x - 22, y - 26, x + 22, y - 26]), e.seed + 4, false, null, 2.0, 1.0, lc)
			Sketch.s_poly(ci, Sketch.v([x - 24, y + 22, x + 24, y + 22]), e.seed + 5, false, null, 2.0, 1.0, lc)
			Sketch.text(ci, x, y + 44, str(progress) if is_endless() else "%d/%d" % [progress, int(ch()["goal"])], Color("#f5e27a"), 22)
		"moth":
			var wf := 0.5 + absf(sin(t * 12 + e.seed)) * 0.5
			var mc := Color(0.039, 0.031, 0.078, 0.8)
			ci.draw_set_transform(Vector2(e.x, e.y), 0, Vector2(wf, 1))
			Sketch.s_ellipse(ci, -14, -2, 14, 10, e.seed, Color("#3a3450"), 1.2, mc)
			Sketch.s_ellipse(ci, 14, -2, 14, 10, e.seed + 1, Color("#3a3450"), 1.2, mc)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			Sketch.scribble(ci, e.x, e.y, 7, e.seed, 12, Color(0.039, 0.031, 0.078, 0.9), 1.6)
		"flake", "crystal":
			var big := e.kind == "crystal"
			var r := 15.0 if big else 9.0
			var fc := Color(0.157, 0.353, 0.51, 0.85)
			if big:
				ci.draw_circle(Vector2(e.x, e.y), r * 1.8, Color(0.47, 0.784, 0.941, 0.25))
			ci.draw_set_transform(Vector2(e.x, e.y), e.a * 0.8, Vector2.ONE)
			for i in 6:
				var a := float(i) / 6.0 * TAU
				var cx := cos(a)
				var cy := sin(a)
				Sketch.s_line(ci, 0, 0, cx * r, cy * r, e.seed + i, 1.8 if big else 1.3, fc, 0.5)
				if big:
					Sketch.s_line(ci, cx * r * 0.6, cy * r * 0.6, cx * r * 0.6 + cos(a + 0.8) * 5, cy * r * 0.6 + sin(a + 0.8) * 5, e.seed + i + 10, 1.0, fc, 0.3)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"icicle":
			if e.a > 0:
				ci.draw_dashed_line(Vector2(e.x, 30), Vector2(e.x, gy()), Color(0.784, 0.235, 0.196, 0.35), 2.0, 7.0)
				if int(floor(t * 12)) % 2 == 0:
					Sketch.text(ci, e.x, 34, "!", Color("#c8433b"), 30)
				Sketch.s_poly(ci, Sketch.v([e.x - 9, 0, e.x + 9, 0, e.x, 18 + (0.9 - e.a) * 20]), e.seed, true, Color("#9ad8f0"), 1.4, 0.6)
			else:
				Sketch.s_poly(ci, Sketch.v([e.x - 9, e.y - 30, e.x + 9, e.y - 30, e.x, e.y + 12]), e.seed, true, Color("#9ad8f0"), 1.6, 0.6)
				Sketch.s_line(ci, e.x, e.y - 60, e.x, e.y - 34, e.seed + 1, 1.0, Color(0.314, 0.549, 0.706, 0.4))
		"shard":
			ci.draw_circle(Vector2(e.x, e.y), 16, Color(1, 0.9, 0.47, 0.25))
			Sketch.s_poly(ci, Sketch.star_pts(e.x, e.y, 11, 4.5, 5, t * 1.5 + e.seed), e.seed, true, Color("#f7d060"), 1.3, 0.5)
		"boss":
			var x := e.x
			var y := e.y
			var hurt := e.b > 0 and int(floor(t * 20)) % 2 == 0
			var dk := Color(0.039, 0.024, 0.078, 0.9)
			ci.draw_circle(Vector2(x, y), 64 + sin(t * 3) * 4, Color(0.078, 0.039, 0.157, 0.35))
			Sketch.s_circle(ci, x, y, 46, e.seed, Color("#b58cff") if hurt else Color("#2a2040"), 2.2, dk)
			Sketch.scribble(ci, x, y, 44, e.seed + 1, 24, Color(0.039, 0.024, 0.078, 0.7), 1.4)
			for i in 6:
				var a := PI * 0.15 + i / 5.0 * PI * 0.7
				var l := 30 + sin(t * 4 + i) * 10
				Sketch.s_line(ci, x + cos(a) * 40, y + sin(a) * 40, x + cos(a) * (46 + l), y + sin(a) * (46 + l), e.seed + 10 + i, 2.0, Color(0.039, 0.024, 0.078, 0.8), 8)
			Sketch.s_poly(ci, Sketch.v([x - 26, y - 38, x - 22, y - 64, x - 10, y - 46, x, y - 70, x + 10, y - 46, x + 22, y - 64, x + 26, y - 38]), e.seed + 20, true, Color("#8a6cc0"), 1.6, 1.0)
			_ellipse(ci, Vector2(x - 14, y - 6), 7, 4, -0.3, Color("#ffe89a"))
			_ellipse(ci, Vector2(x + 14, y - 6), 7, 4, 0.3, Color("#ffe89a"))
			var bw := 90.0
			Sketch.s_poly(ci, Sketch.v([x - bw / 2, y + 60, x + bw / 2, y + 60, x + bw / 2, y + 70, x - bw / 2, y + 70]), e.seed + 30, true, null, 1.2, 0.6, LIGHT_STROKE)
			ci.draw_rect(Rect2(x - bw / 2 + 2, y + 62, (bw - 4) * (e.hp / 6.0), 6), Color("#b58cff"))
		# ---------- VI
		"shroom":
			var lit := e.b == 1
			var nxt := not lit and int(e.a) == seq_next and state == St.PLAY
			var s := (1.0 + sin(t * 8) * 0.1) if nxt else 1.0
			var x := e.x
			var y := e.y
			if lit:
				ci.draw_circle(Vector2(x, y - 4), 26, Color(0.969, 0.816, 0.376, 0.35))
			if nxt:
				var hc: Color = ch()["main"]
				hc.a = 0.5 + sin(t * 8) * 0.3
				ci.draw_arc(Vector2(x, y - 2), 26 * s, 0, TAU, 32, hc, 2.0, true)
			Sketch.s_poly(ci, Sketch.v([x - 5, y + 14, x - 4, y, x + 4, y, x + 5, y + 14]), e.seed, true, Color("#f3e6c8"), 1.2, 0.6)
			Sketch.s_poly(ci, Sketch.v([x - 17 * s, y + 2, x - 12 * s, y - 10 * s, x, y - 15 * s, x + 12 * s, y - 10 * s, x + 17 * s, y + 2]), e.seed + 3, true, Color("#f7d060") if lit else Color("#d0503a"), 1.5, 0.8)
			ci.draw_circle(Vector2(x - 9, y - 4), 1.8, Color("#fff4dc"))
			ci.draw_circle(Vector2(x + 10, y - 3), 1.6, Color("#fff4dc"))
			Sketch.text(ci, x, y - 5, str(int(e.a) + 1), Color("#6a4a10") if lit else Sketch.INK, 20)
		"spider":
			ci.draw_line(Vector2(e.x, 0), Vector2(e.x, e.y - 8), Color(0.235, 0.196, 0.196, 0.5), 1.0)
			for side in [-1.0, 1.0]:
				for i in 4:
					var ly := e.y - 6 + i * 4
					ci.draw_polyline(PackedVector2Array([Vector2(e.x, e.y), Vector2(e.x + side * 10, ly - 5), Vector2(e.x + side * 16, ly + 4 + sin(t * 10 + i) * 1.5)]), Color(0.157, 0.118, 0.118, 0.85), 1.4, true)
			Sketch.s_circle(ci, e.x, e.y, 9, e.seed, Color("#3a3030"), 1.5)
			ci.draw_circle(Vector2(e.x - 3, e.y + 2), 1.6, Color("#d8433b"))
			ci.draw_circle(Vector2(e.x + 3, e.y + 2), 1.6, Color("#d8433b"))
		"spore":
			for i in 6:
				var a := i * 1.05 + e.seed
				ci.draw_circle(Vector2(e.x + cos(a) * e.r * 0.35, e.y + sin(a) * e.r * 0.3), e.r * 0.45, Color(0.588, 0.549, 0.353, 0.16))
			Sketch.scribble(ci, e.x, e.y, e.r * 0.8, e.seed, 9, Color(0.431, 0.392, 0.235, 0.4), 1.0)
		# ---------- VII
		"paint":
			var c: Color = Chapters.PAINTS[int(e.a)]["c"]
			if paint == int(e.a):
				var gc := c
				gc.a = 0.25
				ci.draw_circle(Vector2(e.x, e.y - 6), 30, gc)
			Sketch.s_line(ci, e.x, gy() + 4, e.x, e.y + 8, e.seed + 5, 1.6, Color(0.157, 0.353, 0.118, 0.85), 2)
			Sketch.s_poly(ci, Sketch.v([e.x - 18, e.y - 8, e.x - 10, e.y + 10, e.x + 10, e.y + 10, e.x + 18, e.y - 8]), e.seed, true, c, 1.5, 0.8)
			Sketch.s_ellipse(ci, e.x, e.y - 8, 18, 5, e.seed + 2, c, 1.2)
		"bubble":
			if int(e.a) == -1:
				Sketch.s_circle(ci, e.x, e.y, e.r, e.seed, null, 1.3)
				for i in 3:
					ci.draw_arc(Vector2(e.x, e.y), e.r - 3 - i * 3, PI * 1.1 + t, PI * 1.9 + t, 12, Chapters.PAINTS[i]["c"], 2.5, true)
			else:
				Sketch.s_circle(ci, e.x, e.y, e.r, e.seed, Chapters.PAINTS[int(e.a)]["c"], 1.3)
			ci.draw_arc(Vector2(e.x, e.y), e.r * 0.65, PI * 1.15, PI * 1.45, 6, Color(1, 1, 1, 0.85), 2.0, true)
		"inkbub":
			Sketch.s_circle(ci, e.x, e.y, e.r, e.seed, Sketch.INK, 1.6)
			Sketch.scribble(ci, e.x, e.y, e.r * 0.8, e.seed + 1, 10, Color(0.078, 0.063, 0.094, 0.8), 1.2)
			ci.draw_circle(Vector2(e.x - 5, e.y - 3), 2.5, Sketch.PAPER)
			ci.draw_circle(Vector2(e.x + 5, e.y - 3), 2.5, Sketch.PAPER)
		# ---------- VIII
		"sun":
			ci.draw_circle(Vector2(e.x, e.y), 16, Color(0.949, 0.627, 0.227, 0.25))
			for i in 8:
				var a := i / 8.0 * TAU + t
				Sketch.s_line(ci, e.x + cos(a) * 11, e.y + sin(a) * 11, e.x + cos(a) * 16, e.y + sin(a) * 16, e.seed + i, 1.1, Color(0.627, 0.353, 0.078, 0.7), 0.3)
			Sketch.s_circle(ci, e.x, e.y, 8, e.seed, Color("#f2a03a"), 1.3)
		"sprout":
			var gr := minf(1, float(progress) / (24.0 if is_endless() else float(ch()["goal"])))
			var base := gy()
			var top := base - 30 - gr * 110
			if e.a > 0:
				ci.draw_circle(Vector2(e.x, e.y), e.r + 20, Color(0.949, 0.627, 0.227, 0.3 * e.a))
			var sway := sin(t * 1.3) * 3
			Sketch.s_line(ci, e.x, base, e.x + sway, top, e.seed, 3 + gr * 3, Color(0.235, 0.431, 0.157, 0.9), 4)
			for i in 5:
				var ly := base - 16 - i * ((base - top - 20) / 5.0)
				var side := 1.0 if i % 2 == 1 else -1.0
				var has := i < e.hp
				Sketch.s_ellipse(ci, e.x + sway * (i / 5.0) + side * 12, ly, 11, 5, e.seed + i, Color("#6fb04e") if has else null, 1.2 if has else 0.8, Sketch.GRAPHITE if has else Color(0.157, 0.141, 0.125, 0.25))
			if gr >= 1:
				for i in 6:
					var a := i / 6.0 * TAU + t * 0.3
					Sketch.s_ellipse(ci, e.x + sway + cos(a) * 10, top + sin(a) * 10, 8, 8, e.seed + 20 + i, Color("#f7a8c4"), 1.0)
				Sketch.s_circle(ci, e.x + sway, top, 6, e.seed + 30, Color("#f2c230"), 1.2)
			else:
				Sketch.s_circle(ci, e.x + sway, top, 4 + gr * 6, e.seed + 30, Color("#8cc063"), 1.2)
		"bug":
			var dir := 1.0 if e.vx >= 0 else -1.0
			for i in range(3, -1, -1):
				Sketch.s_circle(ci, e.x - dir * i * 8, e.y - absf(sin(t * 8 + i)) * 3, 6.5 - i * 0.6, e.seed + i, Color("#6fa040") if i == 0 else Color("#9ccf63"), 1.1)
			ci.draw_circle(Vector2(e.x + dir * 3, e.y - 2), 1.4, Sketch.GRAPHITE)
		"beetle":
			var wf := 0.4 + absf(sin(t * 30)) * 0.6
			ci.draw_set_transform(Vector2(e.x, e.y), 0, Vector2(1, wf))
			Sketch.s_ellipse(ci, -6, -9, 8, 5, e.seed + 1, Color("#dfe6f0"), 1.0)
			Sketch.s_ellipse(ci, 6, -9, 8, 5, e.seed + 2, Color("#dfe6f0"), 1.0)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			Sketch.s_ellipse(ci, e.x, e.y, 12, 9, e.seed, Color("#3a3a5a"), 1.5)
			Sketch.s_line(ci, e.x, e.y - 9, e.x, e.y + 9, e.seed + 3, 1.0, Color(0.9, 0.9, 1, 0.6), 0.5)
		# ---------- IX
		"seed":
			ci.draw_circle(Vector2(e.x, e.y), e.r + 4, Color(1, 1, 1, 0.35))
			for i in 12:
				var a := i / 12.0 * TAU + e.t * 0.4
				var tip := Vector2(e.x + cos(a) * e.r, e.y + sin(a) * e.r)
				ci.draw_line(Vector2(e.x, e.y), tip, Color(0.235, 0.22, 0.275, 0.6), 0.9, true)
				ci.draw_circle(tip, 2.0, Color.WHITE)
			Sketch.s_circle(ci, e.x, e.y, 2.5, e.seed, Color("#8a6a4a"), 0.8)
		"nest":
			var x := e.x
			var y := e.y
			if e.a > 0:
				ci.draw_circle(Vector2(x, y), 50, Color(0.969, 0.89, 0.416, 0.4 * e.a))
			Sketch.s_poly(ci, Sketch.v([x - 38, y - 6, x - 30, y + 18, x + 30, y + 18, x + 38, y - 6]), e.seed, true, Color("#b08a5a"), 1.8, 1.0)
			for i in range(-3, 4):
				Sketch.s_line(ci, x + i * 9 - 4, y - 4, x + i * 8 + 4, y + 16, e.seed + i, 0.9, Color(0.235, 0.157, 0.078, 0.5), 1)
			Sketch.s_ellipse(ci, x, y - 6, 38, 8, e.seed + 9, Color("#d8b888"), 1.5)
			if ch_t < 7 or e.a > 0:
				Sketch.text(ci, x, y - 34, "Гнездо", Color("#f7e36a"), 22)
		"bolt":
			if e.a > 0:
				var k := 1.0 - e.a / 1.1
				ci.draw_rect(Rect2(e.x - e.r, 0, e.r * 2, gy()), Color(1, 0.96, 0.706, 0.12 + 0.25 * k))
				ci.draw_dashed_line(Vector2(e.x - e.r, 0), Vector2(e.x - e.r, gy()), Color(0.969, 0.89, 0.416, 0.6), 1.5, 6.0)
				ci.draw_dashed_line(Vector2(e.x + e.r, 0), Vector2(e.x + e.r, gy()), Color(0.969, 0.89, 0.416, 0.6), 1.5, 6.0)
				if int(floor(t * 10)) % 2 == 0:
					Sketch.text(ci, e.x, 34, "⚡", Color("#f7e36a"), 28)
			else:
				var pts := PackedVector2Array()
				var yy := 0.0
				while yy <= gy():
					pts.append(Vector2(e.x + (0.0 if yy == 0 else randf_range(-14, 14)), yy))
					yy += 36.0
				pts.append(Vector2(e.x, gy()))
				ci.draw_polyline(pts, Color(1, 1, 1, 0.45), 10.0)
				ci.draw_polyline(pts, Color("#f7e36a"), 3.5)
				ci.draw_rect(Rect2(e.x - e.r, 0, e.r * 2, gy()), Color(1, 0.98, 0.784, 0.35))
		"orb":
			ci.draw_circle(Vector2(e.x, e.y), e.r + 5, Color(0.314, 0.157, 0.47, 0.25))
			Sketch.s_circle(ci, e.x, e.y, e.r, e.seed, Color("#4a2d70"), 1.4, Color(0.039, 0.024, 0.078, 0.9))


func _draw_particles(ci: CanvasItem) -> void:
	for q in parts:
		var a := maxf(0, q.life / q.max_life)
		var c := q.color
		match q.kind:
			0:
				c.a *= a
				ci.draw_circle(Vector2(q.x, q.y), q.size * (0.4 + a * 0.6), c)
			1:
				c.a *= a
				var s := q.size * 1.6
				ci.draw_line(Vector2(q.x - s, q.y), Vector2(q.x + s, q.y), c, 1.6, true)
				ci.draw_line(Vector2(q.x, q.y - s), Vector2(q.x, q.y + s), c, 1.6, true)
			2:
				c.a *= a * 0.9
				Sketch.s_circle(ci, q.x, q.y, maxf(1.0, q.size * (1.15 - a * 0.85)), q.x + q.y, null, 2.0, c)
			3:
				var al := minf(1, a * 2)
				c.a *= al
				var sz := q.size * ((1 + (a - 0.85) * 3) if a > 0.85 else 1.0)
				Sketch.text(ci, q.x, q.y, q.text, c, sz, 0, Color(0.953, 0.925, 0.863, 0.85 * al))
			4:
				c.a *= a
				ci.draw_set_transform(Vector2(q.x, q.y), q.rot, Vector2(1.8, 1.0))
				ci.draw_circle(Vector2.ZERO, q.size, c)
				ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			6:
				c.a *= a
				ci.draw_line(Vector2(q.x, q.y), Vector2(q.x - q.vx * 0.03, q.y - q.vy * 0.03), c, 1.0)
			5:
				c.a *= a
				var d := signf(q.vx) if q.vx != 0 else 1.0
				ci.draw_line(Vector2(q.x, q.y), Vector2(q.x - d * q.size, q.y), c, 1.2, true)


func _draw_hud(ci: CanvasItem) -> void:
	if state == St.IDLE:
		return
	var pad := 16.0
	var light := is_dark()
	var ink := LIGHT_TEXT if light else Sketch.INK
	var stroke := LIGHT_STROKE if light else Sketch.GRAPHITE
	var main: Color = ch()["main"]
	# сердца
	var slots := maxi(max_start_hearts(), hearts)
	var mode_label := {"story": "", "chapter": "Одна глава", "endless": "∞ Бесконечная охота", "hard": "Одно перо ×2"}
	if mode_label[mode] != "":
		Sketch.text(ci, pad, H - 22, mode_label[mode], Color("#c8433b") if mode == "hard" else main, 22, -1)
	for i in slots:
		var full := i < hearts
		var bob := sin(time * 10) * 2 if (full and hearts == 1) else 0.0
		Sketch.draw_heart(ci, pad + 16 + i * 32, pad + 16 + bob, 24, 70 + i, Color("#d8433b") if full else null, stroke)
	if shield > 0:
		var sx := pad + 16 + slots * 32
		for i in 5:
			var a := i / 5.0 * TAU + time
			Sketch.s_ellipse(ci, sx + cos(a) * 6, pad + 16 + sin(a) * 6, 5, 3.5, 720 + i, Color("#e86a92"), 0.8)
	# очки и серия
	Sketch.text(ci, pad, pad + 52, "Очки: " + str(int(round(display_score))), ink, 30, -1)
	if combo >= 2:
		var mult := mini(5, 1 + combo / 5)
		Sketch.text(ci, pad, pad + 80, "Серия %d  ×%d" % [combo, mult], main, 22, -1)
		ci.draw_line(Vector2(pad, pad + 94), Vector2(pad + 110 * (combo_t / 2.4), pad + 94), main, 2.0, true)
	# прогресс задания
	var cx := W / 2
	var goal := int(ch()["goal"])
	var goal_txt := ("%s: %d  ·  до ♥ %d" % [ch()["goal_label"], progress, next_heart_at - progress]) if is_endless() else ("%s: %d / %d" % [ch()["goal_label"], mini(progress, goal), goal])
	Sketch.text(ci, cx, pad + 14, goal_txt, Color("#f5e27a") if light else Sketch.INK, 28)
	var bw := minf(220, W * 0.4)
	var bx := cx - bw / 2
	var by := pad + 34
	Sketch.s_poly(ci, Sketch.v([bx, by, bx + bw, by, bx + bw, by + 10, bx, by + 10]), 99, true, null, 1.3, 0.6, stroke)
	var frac := (1.0 - float(next_heart_at - progress) / ENDLESS_HEART_EVERY) if is_endless() else float(progress) / goal
	var fill_w := (bw - 4) * clampf(frac, 0.0, 1.0)
	if fill_w > 0:
		Sketch.fill_poly(ci, Sketch.v([bx + 2, by + 2, bx + 2 + fill_w, by + 2, bx + 2 + fill_w, by + 8, bx + 2, by + 8]), main)
	# индикатор груза
	var carry_max := {"flower": 6, "water": 5, "star": 3, "garden": 3}
	if carry_max.has(cid()):
		var cm: int = carry_max[cid()]
		var col: Color = {"flower": Color("#f2c230"), "water": Color("#5aa8e6"), "star": Color("#f7d060"), "garden": Color("#f2a03a")}[cid()]
		var label: String = {"flower": "Пыльца", "water": "Вода", "star": "Заряд", "garden": "Солнце"}[cid()]
		Sketch.text(ci, cx - cm * 16 / 2.0 - 36, by + 30, label, ink, 20)
		for i in cm:
			Sketch.s_circle(ci, cx - cm * 16 / 2.0 + 8 + i * 18, by + 30, 6, 200 + i, col if i < carry else null, 1.2, stroke)
	if cid() == "night" and followers > 0:
		Sketch.text(ci, cx, by + 30, "За тобой: %d ✦" % followers, Color("#f5e27a"), 22)
	if cid() == "mushroom" and state == St.PLAY:
		var warn := ring_t < ring_max * 0.3
		Sketch.text(ci, cx, by + 30, "Хоровод: %d/5 · %d с" % [seq_next, maxi(0, ceili(ring_t))], Color("#c8433b") if warn else ink, 22)
	if cid() == "rainbow":
		Sketch.text(ci, cx - 14, by + 30, "Цвет:", ink, 22)
		Sketch.s_circle(ci, cx + 26, by + 30, 8, 250, Chapters.PAINTS[paint]["c"], 1.4, stroke)
	# кольцо перезарядки рывка
	if dash_cd > 0 and state == St.PLAY:
		var c := main
		c.a = 0.6
		ci.draw_arc(Vector2(px, py) + world_node.position, 26, -PI / 2, -PI / 2 + TAU * (1 - dash_cd / dash_cd_max()), 32, c, 2.0, true)
	if touch_mode and (state == St.PLAY or state == St.CLEAR):
		_draw_touch(ci, light, ink, stroke)


func _draw_touch(ci: CanvasItem, _light: bool, ink: Color, stroke: Color) -> void:
	var b := _dash_btn()
	var st := stroke
	st.a *= 0.75
	var wing: Color = ch()["wing"]
	wing.a = 0.75
	Sketch.s_circle(ci, b.x, b.y, b.z * (0.92 if dash_btn_id >= 0 else 1.0), 555, wing if dash_cd <= 0 else null, 2.0, st)
	Sketch.text(ci, b.x, b.y, "Рывок", ink, 24)
	if joy_active:
		Sketch.s_circle(ci, joy_o.x, joy_o.y, 50, 556, null, 1.6, st)
		var d := joy_p - joy_o
		var l := d.length()
		var k := minf(l, 50.0) / maxf(l, 0.0001)
		var main: Color = ch()["main"]
		main.a = 0.75
		Sketch.s_circle(ci, joy_o.x + d.x * k, joy_o.y + d.y * k, 20, 557, main, 1.6, st)
	elif ch_t < 6:
		Sketch.text(ci, W * 0.3, H - 90, "Веди пальцем, чтобы лететь", ink, 22)
