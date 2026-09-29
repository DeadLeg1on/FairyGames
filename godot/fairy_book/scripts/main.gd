extends Node
## Интерфейс и игровой поток «Книги Фей» — порт src/FairyBook.tsx (с режимами).

const GameScript := preload("res://scripts/game.gd")
const PortraitScript := preload("res://scripts/portrait.gd")
const SETTINGS := "user://settings.cfg"

const PINK := Color("#c9446f")
const GOLD := Color("#e0a526")
const WINE := Color("#8a3b3b")
const RED := Color("#c8433b")
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]
const POLLEN_COL := Color("#b08810")

const MODES := [
	{"id": "story", "icon": "✎", "title": "Сказка", "desc": "Все девять глав подряд. После каждой главы +1 ♥.", "col": "Глав"},
	{"id": "chapter", "icon": "❧", "title": "Одна глава", "desc": "Любая открытая глава отдельно — побей свой рекорд.", "col": "Глава"},
	{"id": "endless", "icon": "∞", "title": "Бесконечная охота", "desc": "Глава без конца: враги всё злее, каждые 10 целей +1 ♥.", "col": "Глава"},
	{"id": "hard", "icon": "✧", "title": "Одно перо", "desc": "Сказка с одним сердцем и без лечения. Очки ×2.", "col": "Глав"},
]

var game: Node2D
var ui: Control
var overlay: Control
var top_bar: HBoxContainer
var mute_btn: Button
var pause_btn: Button

var screen := "menu"
var mode := "story"
var story_idx := 0
var prev_clear := {}
var final_score := 0
var final_chapter := 0
var final_progress := 0
var scores: Array = []
var scores_tab := "story"
var rank := -1
var player_name := "Фея"
var unlocked := 1
var revive_used := false
var ad_busy := false
var last_entry_date := 0
var wobblers: Array[Control] = []
var wide := false
var pollen := 0
var upgrades := Shop.empty()
var granted_score := 0
var last_pollen := 0
var doubled := false
var shop_back := "menu"
var shop_flash := ""
var small := false


func mode_def(m: String) -> Dictionary:
	for d in MODES:
		if d["id"] == m:
			return d
	return MODES[0]


func is_single() -> bool:
	return mode == "chapter" or mode == "endless"


func _ready() -> void:
	randomize()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		player_name = str(cfg.get_value("player", "name", "Фея"))
		unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, Chapters.count())
	pollen = Shop.load_pollen()
	upgrades = Shop.load_upgrades()
	scores = Scores.load_all("story")

	game = GameScript.new()
	add_child(game)
	game.upgrades = upgrades.duplicate()
	game.chapter_cleared.connect(_on_chapter_cleared)
	game.game_over.connect(_on_game_over)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	layer.add_child(ui)

	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	top_bar.z_index = 5
	ui.add_child(top_bar)
	mute_btn = _icon_btn("✕" if Sfx.muted else "♪", _toggle_mute)
	pause_btn = _icon_btn("❚❚", _pause)
	top_bar.add_child(mute_btn)
	top_bar.add_child(pause_btn)

	Yandex.platform_pause.connect(_pause)
	get_viewport().size_changed.connect(_on_resize)
	game.preview(0)
	_go("menu")
	await get_tree().process_frame
	Yandex.mark_ready()


func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for w in wobblers:
		if is_instance_valid(w):
			w.pivot_offset = w.size * 0.5
			w.rotation = sin(t * 2.1) * 0.026
	var vs := ui.get_viewport_rect().size
	top_bar.position = Vector2(vs.x - top_bar.size.x - 12, 12)


func _on_resize() -> void:
	if screen != "play":
		_build_overlay()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()


# ================================================================= поток

func _go(s: String) -> void:
	screen = s
	if s == "play":
		Yandex.gameplay_start()
	else:
		Yandex.gameplay_stop()
	pause_btn.visible = s == "play"
	_build_overlay()


func _set_busy(on: bool) -> void:
	ad_busy = on
	if overlay:
		for b in overlay.find_children("*", "Button", true, false):
			if not b.has_meta("locked"):
				(b as Button).disabled = on


## полноэкранная реклама (если платформа разрешит), затем действие
func _with_ad(action: Callable) -> void:
	if ad_busy:
		return
	_set_busy(true)
	await Yandex.show_fullscreen()
	_set_busy(false)
	action.call()


func _save_setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS)


func _unlock(n: int) -> void:
	var v := clampi(maxi(unlocked, n), 1, Chapters.count())
	if v != unlocked:
		unlocked = v
		_save_setting("progress", "unlocked", v)


func _record(score: int, chapter: int) -> void:
	var entry := {"name": player_name.substr(0, 14) if player_name != "" else "Фея", "score": score, "chapter": chapter, "date": int(Time.get_unix_time_from_system() * 1000.0) * 10 + randi() % 10}
	var res := Scores.save(entry, mode)
	scores = res[0]
	scores_tab = mode
	# пыльца за очки с прошлого начисления (после «второго шанса» — только прирост)
	last_pollen = Shop.pollen_for(score - granted_score, int(upgrades["bag"]))
	granted_score = score
	doubled = false
	_add_pollen(last_pollen)
	rank = res[1]
	last_entry_date = int(entry["date"])
	final_score = score
	final_chapter = chapter


func _on_chapter_cleared(idx: int, bonus: int, score: int) -> void:
	_unlock(idx + 2)
	if mode == "chapter":
		_record(score, idx)
		_go("result")
		return
	if idx >= Chapters.count() - 1:
		_record(score, Chapters.count())
		_go("win")
	else:
		prev_clear = {"idx": idx, "bonus": bonus, "score": score}
		story_idx = idx + 1
		game.preview(idx + 1)
		_go("story")


func _on_game_over(score: int, ch: int) -> void:
	final_progress = game.progress
	_record(score, ch)
	_go("over")


## выбор режима в меню
func _choose_mode(m: String) -> void:
	if ad_busy:
		return
	Sfx.play("click")
	mode = m
	revive_used = false
	prev_clear = {}
	granted_score = 0
	if m == "story" or m == "hard":
		game.new_run(m)
		game.preview(0)
		story_idx = 0
		_go("story")
	else:
		_go("select")


## выбор главы (режимы «Одна глава» и «Бесконечная охота»)
func _pick_chapter(idx: int) -> void:
	if ad_busy or idx >= unlocked:
		return
	Sfx.play("click")
	game.new_run(mode)
	game.preview(idx)
	story_idx = idx
	prev_clear = {}
	revive_used = false
	granted_score = 0
	_go("story")


func _begin_chapter() -> void:
	if ad_busy:
		return
	var run := func() -> void:
		if is_single():
			game.new_run(mode)
		game.start_chapter(story_idx)
		rank = -1
		_go("play")
	# полноэкранная реклама — только в естественных паузах
	if is_single() or story_idx > 0:
		_with_ad(run)
	else:
		run.call()


func _restart() -> void:
	if ad_busy:
		return
	_with_ad(func() -> void:
		game.restart()
		rank = -1
		revive_used = false
		prev_clear = {}
		granted_score = 0
		_go("play"))


func _next_chapter() -> void:
	if story_idx + 1 < Chapters.count():
		_pick_chapter(story_idx + 1)


## реклама с вознаграждением: второй шанс в текущей главе
func _continue_for_ad() -> void:
	if ad_busy or revive_used:
		return
	_set_busy(true)
	var ok: bool = await Yandex.show_rewarded()
	_set_busy(false)
	if not ok:
		return
	revive_used = true
	scores = Scores.remove(last_entry_date, mode)
	rank = -1
	game.revive()
	_go("play")


func _pause() -> void:
	if screen == "play":
		game.pause()
		_go("paused")


func _resume() -> void:
	if screen == "paused":
		game.resume()
		_go("play")


func _to_menu() -> void:
	game.preview(0)
	_go("menu")


func _to_select() -> void:
	game.preview(story_idx)
	_go("select")


func _open_scores(tab: String) -> void:
	Sfx.play("click")
	scores_tab = tab
	scores = Scores.load_all(tab)
	rank = -1
	_go("scores")


func _toggle_mute() -> void:
	Sfx.set_muted(not Sfx.muted)
	mute_btn.text = "✕" if Sfx.muted else "♪"


func _set_name(t: String) -> void:
	player_name = t
	_save_setting("player", "name", t)


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or ad_busy:
		return
	var code := k.physical_keycode
	var s := screen
	if code == KEY_M:
		_toggle_mute()
	if s == "play" and (code == KEY_ESCAPE or code == KEY_P):
		_pause()
	elif s == "paused" and (code == KEY_ESCAPE or code == KEY_P or code == KEY_ENTER):
		_resume()
	elif s == "story" and (code == KEY_ENTER or code == KEY_SPACE):
		_begin_chapter()
	elif s == "story" and code == KEY_ESCAPE:
		if is_single():
			_to_select()
		else:
			_to_menu()
	elif s == "menu" and code == KEY_ENTER:
		_choose_mode("story")
	elif s == "select" and code == KEY_ESCAPE:
		_to_menu()
	elif s == "select" and code >= KEY_1 and code <= KEY_5:
		_pick_chapter(code - KEY_1)
	elif s == "result" and (code == KEY_ENTER or code == KEY_SPACE):
		if story_idx < Chapters.count() - 1:
			_next_chapter()
		else:
			_restart()
	elif s == "shop" and code == KEY_ESCAPE:
		_close_shop()
	elif s == "scores" and code == KEY_ESCAPE:
		_go("menu")
	if (s == "over" or s == "win" or s == "paused" or s == "result") and code == KEY_R:
		_restart()
	elif (s == "over" or s == "win") and (code == KEY_ENTER or code == KEY_SPACE):
		_restart()


# ================================================================= построение экранов

func _build_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	wobblers.clear()
	if screen == "play":
		return
	var vs := ui.get_viewport_rect().size
	wide = vs.x >= 640 and vs.x > vs.y * 1.2
	small = wide or vs.y < 600
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	ui.move_child(overlay, 0)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match screen:
		"menu":
			dim.color = Color(0.937, 0.91, 0.847, 0.35)
		"story", "scores", "select", "shop":
			dim.color = Color(0.118, 0.094, 0.078, 0.25)
		"win", "result":
			dim.color = Color(1, 0.94, 0.78, 0.3)
		_:
			dim.color = Color(0.118, 0.094, 0.078, 0.38)
	overlay.add_child(dim)

	var maxw := 540.0
	match screen:
		"menu":
			maxw = 860.0 if wide else 540.0
		"select":
			maxw = 900.0 if wide else 560.0
		"story":
			maxw = 980.0 if wide else 680.0
		"paused":
			maxw = 380.0
		"over", "win", "result":
			maxw = 760.0 if wide else 480.0
		"scores":
			maxw = 520.0
		"shop":
			maxw = 940.0 if wide else 560.0
	var w := minf(maxw, vs.x - 24.0)

	# карточка кладётся прямо в overlay (без контейнеров), чтобы её можно было
	# измерить и уменьшить под экран
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(w, 0)
	card.modulate.a = 0.0
	card.draw.connect(_draw_card.bind(card))
	overlay.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4 if small else 6)
	card.add_child(box)
	var inner_w := w - 48.0

	match screen:
		"menu":
			_build_menu(box, inner_w)
		"select":
			_build_select(box, inner_w)
		"story":
			_build_story(box, inner_w)
		"paused":
			_build_paused(box)
		"over", "win", "result":
			_build_over(box, inner_w)
		"scores":
			_build_scores(box)
		"shop":
			_build_shop(box)
	_fit_card(card)


## Уменьшает карточку так, чтобы она целиком помещалась в экран, и центрирует её
func _fit_card(card: PanelContainer) -> void:
	for i in 2:
		await get_tree().process_frame
		if not is_instance_valid(card):
			return
		card.reset_size()
	var vs := ui.get_viewport_rect().size
	var sz := card.size
	var s := clampf(minf((vs.y - 24.0) / maxf(1.0, sz.y), (vs.x - 24.0) / maxf(1.0, sz.x)), 0.45, 1.0)
	card.pivot_offset = sz * 0.5
	card.position = (vs - sz) * 0.5
	if sz.y * s > vs.y - 12.0:
		card.position.y = 6.0 - (sz.y - sz.y * s) * 0.5
	card.set_meta("fit_scale", s)
	# появление: как pop-in в веб-версии
	card.scale = Vector2(s, s) * 0.88
	card.rotation = -0.035
	var tw := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.3)
	tw.tween_property(card, "scale", Vector2(s, s), 0.45)
	tw.tween_property(card, "rotation", 0.0, 0.45)


func _build_menu(box: VBoxContainer, w: float) -> void:
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	right.add_theme_constant_override("separation", 8)
	if wide:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.0
		left.alignment = BoxContainer.ALIGNMENT_CENTER
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_stretch_ratio = 1.25
		row.add_child(left)
		row.add_child(right)
		box.add_child(row)
	else:
		box.add_child(left)
		box.add_child(right)

	left.add_child(_lbl("карандашная сказка в девяти главах", 22, Color(Sketch.INK, 0.7)))
	var title := _lbl("Книга Фей", 72, PINK, true)
	left.add_child(title)
	wobblers.append(title)
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", -20)
	for i in Chapters.count():
		prow.add_child(_portrait(Chapters.get_ch(i), 50))
	left.add_child(prow)
	left.add_child(_lbl("Как тебя зовут?", 22, Color(Sketch.INK, 0.8)))
	var name_edit := LineEdit.new()
	name_edit.text = player_name
	name_edit.max_length = 14
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_edit.text_changed.connect(_set_name)
	name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
	left.add_child(name_edit)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for d in MODES:
		var b := _btn("%s %s\n%s" % [d["icon"], d["title"], d["desc"]], _choose_mode.bind(d["id"]), d["id"] == "story")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 86)
		b.add_theme_font_size_override("font_size", 21)
		grid.add_child(b)
	right.add_child(grid)
	var shop_btn := _btn("Лавка фей · ✦ %d" % pollen, _open_shop, true)
	shop_btn.add_theme_font_size_override("font_size", 24)
	shop_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(shop_btn)
	right.add_child(_btn_row([_small_btn("Рекорды", _open_scores.bind("story")), _small_btn("Выход", func() -> void: get_tree().quit())] if not OS.has_feature("web") else [_small_btn("Рекорды", _open_scores.bind("story"))], 400))
	right.add_child(_lbl("Клавиатура: стрелки / WASD — полёт, Пробел / Shift — рывок, Esc — пауза, R — заново", 19, Color(Sketch.INK, 0.8)))
	right.add_child(_lbl("Касание: веди пальцем — полёт, «Рывок» или второй палец — рывок", 19, Color(Sketch.INK, 0.8)))


func _build_select(box: VBoxContainer, w: float) -> void:
	var md := mode_def(mode)
	box.add_child(_lbl("%s %s" % [md["icon"], md["title"]], 22, Color(Sketch.INK, 0.7)))
	box.add_child(_lbl("Выбери главу", 50, Sketch.INK, true))
	box.add_child(_lbl(str(md["desc"]) + " Новые главы открываются по мере прохождения.", 20, Color(Sketch.INK, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 5 if wide else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var all := Scores.load_all(mode)
	for i in Chapters.count():
		var c := Chapters.get_ch(i)
		var locked := i >= unlocked
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		var p := _portrait(c, 64)
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if locked:
			p.modulate = Color(0.6, 0.6, 0.6, 0.5)
		cell.add_child(p)
		var b := _btn("%s\n%s" % [c["num"], c["title"]], _pick_chapter.bind(i))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(0, 70)
		if locked:
			b.disabled = true
			b.set_meta("locked", true)
		else:
			b.add_theme_color_override("font_color", c["main"])
			b.add_theme_color_override("font_hover_color", c["main"])
		cell.add_child(b)
		var best := -1
		for e in all:
			if int(e.get("chapter", -1)) == i:
				best = int(e.get("score", 0))
				break
		var cap := "🔒 пройди предыдущую" if locked else ("рекорд %d" % best if best >= 0 else str(c["kind"]))
		cell.add_child(_lbl(cap, 17, Color(Sketch.INK, 0.7)))
		grid.add_child(cell)
	box.add_child(grid)
	box.add_child(_gap(4))
	box.add_child(_btn_row([_small_btn("Рекорды режима", _open_scores.bind(mode)), _small_btn("← В меню", _to_menu)], 400))


func _build_story(box: VBoxContainer, w: float) -> void:
	var ch := Chapters.get_ch(story_idx)
	var main: Color = ch["main"]
	var tsz := 21 if small else 24
	if not prev_clear.is_empty():
		var pc := Chapters.get_ch(int(prev_clear["idx"]))
		box.add_child(_lbl("«" + str(pc["outro"]) + "»", tsz))
		box.add_child(_lbl("Бонус за главу: +%d · Всего очков: %d%s" % [prev_clear["bonus"], prev_clear["score"], " · +1 ♥" if mode == "story" else ""], 19, Color(Sketch.INK, 0.8)))
		var sep := HSeparator.new()
		var ss := StyleBoxLine.new()
		ss.color = Color(Sketch.INK, 0.4)
		ss.thickness = 2
		sep.add_theme_stylebox_override("separator", ss)
		box.add_child(sep)

	# шапка главы
	var head := VBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var p := _portrait(ch, 110 if not small else 90)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wobblers.append(p)
	var sub := "%s · %s" % [ch["num"], ch["kind"]]
	if mode != "story":
		sub += " · " + str(mode_def(mode)["title"])
	# текст и задание
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	for para in ch["story"]:
		body.add_child(_lbl(para, tsz, Sketch.INK, false, HORIZONTAL_ALIGNMENT_LEFT))
	var quest := PanelContainer.new()
	var qs := StyleBoxFlat.new()
	qs.bg_color = Color(1, 1, 1, 0.55)
	qs.set_border_width_all(2)
	qs.border_color = Color(Sketch.INK, 0.5)
	qs.set_corner_radius_all(8)
	qs.set_content_margin_all(8)
	quest.add_theme_stylebox_override("panel", qs)
	var qb := VBoxContainer.new()
	qb.add_theme_constant_override("separation", 2)
	if mode == "endless":
		qb.add_child(_lbl("Бесконечная охота: цель не кончается — копи очки, пока есть сердца. Каждые 10 целей +1 ♥, а враги с каждой минутой злее.", tsz, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		qb.add_child(_lbl("Как играть: " + str(ch["quest"]), 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	else:
		qb.add_child(_lbl("Задание: " + str(ch["quest"]), tsz, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "hard":
		qb.add_child(_lbl("✧ Одно перо: одно сердце на всю сказку, очки ×2.", 19, RED, false, HORIZONTAL_ALIGNMENT_LEFT))
	qb.add_child(_lbl("✎ " + str(ch["hint"]), 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	quest.add_child(qb)
	body.add_child(quest)
	var go_btn := _btn("Лететь! ➜", _begin_chapter, true)
	go_btn.add_theme_font_size_override("font_size", 28 if small else 34)
	var foot: Array = [go_btn]
	if is_single():
		foot.push_front(_small_btn("← Главы", _to_select))
	body.add_child(_gap(4))
	var frow := HBoxContainer.new()
	frow.alignment = BoxContainer.ALIGNMENT_CENTER
	frow.add_theme_constant_override("separation", 12)
	for b in foot:
		frow.add_child(b)
	body.add_child(frow)
	if not OS.has_feature("mobile"):
		body.add_child(_lbl("Enter / Пробел", 17, Color(Sketch.INK, 0.6)))

	if wide:
		# две колонки: слева фея и название, справа история
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		head.custom_minimum_size = Vector2(w * 0.28, 0)
		head.add_child(p)
		head.add_child(_lbl(sub, 20, Color(Sketch.INK, 0.7)))
		head.add_child(_lbl(ch["title"], 40, main, true))
		head.add_child(_lbl("Героиня: фея " + str(ch["name"]), 20))
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(head)
		row.add_child(body)
		box.add_child(row)
	else:
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 12)
		hrow.add_child(p)
		var tb := VBoxContainer.new()
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.alignment = BoxContainer.ALIGNMENT_CENTER
		tb.add_child(_lbl(sub, 21, Color(Sketch.INK, 0.7), false, HORIZONTAL_ALIGNMENT_LEFT))
		tb.add_child(_lbl(ch["title"], 44 if small else 50, main, true, HORIZONTAL_ALIGNMENT_LEFT))
		tb.add_child(_lbl("Героиня: фея " + str(ch["name"]), 22, Sketch.INK, false, HORIZONTAL_ALIGNMENT_LEFT))
		hrow.add_child(tb)
		box.add_child(hrow)
		box.add_child(body)


func _build_paused(box: VBoxContainer) -> void:
	box.add_child(_lbl("Пауза", 64, Sketch.INK, true))
	box.add_child(_lbl("Фея присела на листок отдохнуть…", 24, Color(Sketch.INK, 0.7)))
	box.add_child(_gap(8))
	box.add_child(_btn("Продолжить", _resume, true))
	box.add_child(_btn("Заново (R)", _restart))
	if is_single():
		box.add_child(_btn("К главам", _to_select))
	box.add_child(_btn("В меню", _to_menu))


func _build_over(box: VBoxContainer, w: float) -> void:
	var ch := Chapters.get_ch(story_idx)
	var md := mode_def(mode)
	var title := ""
	var text := ""
	var col := WINE
	if screen == "win":
		title = "И жили они долго и счастливо!"
		text = "Все девять фей спасены — и всего с одним пером! Легенда." if mode == "hard" else "Все девять фей спасены, а последний осколок тени погас."
		col = GOLD
	elif screen == "result":
		title = "Глава пройдена!"
		text = "%s · %s. %s" % [ch["num"], ch["title"], ch["outro"]]
		col = ch["main"]
	elif mode == "endless":
		title = "Охота окончена!"
		text = "%s: %s — %d. Враги оказались сильнее… пока что." % [ch["kind"], str(ch["goal_label"]).to_lower(), final_progress]
	elif mode == "chapter":
		title = "Глава не удалась…"
		text = "%s · %s. Попробуй ещё раз!" % [ch["num"], ch["title"]]
	else:
		title = "Сказка оборвалась…"
		text = "Пройдено глав: %d из %d. Но любую сказку можно рассказать заново." % [final_chapter, Chapters.count()]

	var a := VBoxContainer.new()
	var b := VBoxContainer.new()
	a.add_theme_constant_override("separation", 4)
	b.add_theme_constant_override("separation", 8)
	a.add_child(_lbl("%s %s" % [md["icon"], md["title"]], 21, Color(Sketch.INK, 0.7)))
	a.add_child(_lbl(title, 40 if small else 50, col, true))
	a.add_child(_lbl(text, 20 if small else 23))
	a.add_child(_lbl("%d очков" % final_score, 40 if small else 48, Sketch.INK, true))
	if rank == 0:
		var rec := _lbl("✦ Новый рекорд! ✦", 32, PINK, true)
		a.add_child(rec)
		wobblers.append(rec)
	elif rank > 0:
		a.add_child(_lbl("Место в таблице: %d" % (rank + 1), 24))
	a.add_child(_lbl("+%d ✦ пыльцы%s · всего %d" % [last_pollen * (2 if doubled else 1), " (×2)" if doubled else "", pollen], 22, POLLEN_COL))
	b.add_child(_score_table(rank, 5 if small else 7))
	if screen == "over" and not revive_used:
		b.add_child(_btn("▶ %s за рекламу" % ("Продолжить охоту" if mode == "endless" else "Продолжить главу"), _continue_for_ad, true))
	if screen == "result" and story_idx < Chapters.count() - 1:
		b.add_child(_btn("Следующая глава ➜", _next_chapter, true))
	var btns: Array = [_small_btn("Ещё раз (R)", _restart)]
	if is_single():
		btns.append(_small_btn("Главы", _to_select))
	btns.append(_small_btn("Лавка", _open_shop))
	btns.append(_small_btn("В меню", _to_menu))
	if not doubled and last_pollen > 0:
		b.add_child(_small_btn("▶ Удвоить пыльцу за рекламу (+%d ✦)" % last_pollen, _double_pollen))
	b.add_child(_btn_row(btns, 420))
	if wide:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a.alignment = BoxContainer.ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(a)
		row.add_child(b)
		box.add_child(row)
	else:
		box.add_child(a)
		box.add_child(b)


func _build_scores(box: VBoxContainer) -> void:
	box.add_child(_lbl("Рекорды", 64, Sketch.INK, true))
	box.add_child(_lbl("Летопись самых храбрых фей", 22, Color(Sketch.INK, 0.7)))
	var tabs := HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for d in MODES:
		var t := _small_btn("%s %s" % [d["icon"], d["title"]], _open_scores.bind(d["id"]))
		t.add_theme_font_size_override("font_size", 19)
		if d["id"] == scores_tab:
			t.theme_type_variation = "PrimaryButton"
		tabs.add_child(t)
	box.add_child(tabs)
	box.add_child(_score_table(-1, 10))
	box.add_child(_gap(6))
	var back := _btn("Назад", func() -> void:
		Sfx.play("click")
		_go("menu"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)


func _score_table(highlight: int, max_rows: int = 10) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	if scores.is_empty():
		v.add_child(_lbl("Пока пусто — стань первой легендой!", 24, Color(Sketch.INK, 0.7)))
		return v
	var tab := scores_tab
	var md := mode_def(tab)
	var single := tab == "chapter" or tab == "endless"
	v.add_child(_score_row("#", "Имя", md["col"], "Очки", false, true))
	# показываем верх таблицы, но выделенная (новая) запись всегда видна
	var rows := range(mini(scores.size(), max_rows))
	if highlight >= max_rows:
		rows[rows.size() - 1] = highlight
	for i in rows:
		var s: Dictionary = scores[i]
		var chn := int(s.get("chapter", 0))
		var colv: String = str(ROMAN[clampi(chn, 0, ROMAN.size() - 1)]) if single else "%d/%d" % [chn, Chapters.count()]
		v.add_child(_score_row("♛" if i == 0 else str(i + 1), str(s.get("name", "Фея")), colv, str(int(s.get("score", 0))), i == highlight, false))
	return v


# ================================================================= лавка

func _add_pollen(n: int) -> void:
	pollen = maxi(0, pollen + n)
	Shop.save_pollen(pollen)


func _open_shop() -> void:
	if ad_busy:
		return
	Sfx.play("click")
	shop_back = screen
	_go("shop")


func _close_shop() -> void:
	Sfx.play("click")
	_go(shop_back)


## покупка улучшения: за пыльцу или за рекламу с вознаграждением
func _buy(id: String, via_ad: bool) -> void:
	if ad_busy:
		return
	var def: Dictionary = {}
	for d in Shop.UPGRADES:
		if d["id"] == id:
			def = d
	var lvl := int(upgrades[id])
	var price := Shop.price_of(def, lvl)
	if price < 0:
		return
	if via_ad:
		_set_busy(true)
		var ok: bool = await Yandex.show_rewarded()
		_set_busy(false)
		if not ok:
			return
	else:
		if pollen < price:
			return
		_add_pollen(-price)
	upgrades[id] = lvl + 1
	Shop.save_upgrades(upgrades)
	game.upgrades = upgrades.duplicate()
	shop_flash = id
	Sfx.play("bloom")
	_build_overlay()


## удвоить пыльцу за забег (реклама с вознаграждением)
func _double_pollen() -> void:
	if ad_busy or doubled or last_pollen <= 0:
		return
	_set_busy(true)
	var ok: bool = await Yandex.show_rewarded()
	_set_busy(false)
	if not ok:
		return
	_add_pollen(last_pollen)
	doubled = true
	Sfx.play("bloom")
	_build_overlay()


func _build_shop(box: VBoxContainer) -> void:
	box.add_child(_lbl("Лавка фей", 60, POLLEN_COL, true))
	box.add_child(_lbl("Пыльца даётся за очки в конце каждого забега. Улучшения работают во всех режимах.", 20, Color(Sketch.INK, 0.75)))
	box.add_child(_lbl("✦ %d пыльцы" % pollen, 40, POLLEN_COL, true))
	var grid := GridContainer.new()
	grid.columns = 3 if wide else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for d in Shop.UPGRADES:
		var id: String = d["id"]
		var lvl := int(upgrades[id])
		var price := Shop.price_of(d, lvl)
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.969, 0.816, 0.376, 0.6) if shop_flash == id else Color(1, 1, 1, 0.55)
		st.set_border_width_all(2)
		st.border_color = Color(Sketch.INK, 0.5)
		st.corner_radius_top_left = 14
		st.corner_radius_bottom_right = 16
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 5
		st.set_content_margin_all(8)
		cell.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		v.add_child(_lbl("%s %s" % [d["icon"], d["title"]], 24, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		var pips := ""
		for i in int(d["max"]):
			pips += ("● " if i < lvl else "○ ")
		v.add_child(_lbl(pips.strip_edges(), 18, POLLEN_COL, false, HORIZONTAL_ALIGNMENT_LEFT))
		v.add_child(_lbl(d["desc"], 18, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
		if price < 0:
			v.add_child(_lbl("✓ Максимум", 22, Color("#5c9e3a"), true, HORIZONTAL_ALIGNMENT_LEFT))
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var b1 := _small_btn("✦ %d" % price, _buy.bind(id, false))
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if pollen < price:
				b1.disabled = true
				b1.set_meta("locked", true)
			var b2 := _btn("▶ Реклама", _buy.bind(id, true), true)
			b2.add_theme_font_size_override("font_size", 20)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b1)
			row.add_child(b2)
			v.add_child(row)
		grid.add_child(cell)
	box.add_child(grid)
	shop_flash = ""
	box.add_child(_gap(4))
	var back := _small_btn("← Назад", _close_shop)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)


func _small_btn(t: String, cb: Callable) -> Button:
	var b := _btn(t, cb)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _score_row(a: String, b: String, c: String, d: String, hl: bool, header: bool) -> Control:
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.91, 0.416, 0.573, 0.22) if hl else Color(0, 0, 0, 0)
	st.set_corner_radius_all(4)
	st.content_margin_left = 6
	st.content_margin_right = 6
	pc.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	pc.add_child(h)
	var col := Color(Sketch.INK, 0.6) if header else Sketch.INK
	var sz := 20 if header else 24
	var la := _lbl(a, sz, col, hl, HORIZONTAL_ALIGNMENT_LEFT, false)
	la.custom_minimum_size = Vector2(34, 0)
	var lb := _lbl(b, sz, col, hl, HORIZONTAL_ALIGNMENT_LEFT, false)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.clip_text = true
	lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lc := _lbl(c, sz, col, hl, HORIZONTAL_ALIGNMENT_CENTER, false)
	lc.custom_minimum_size = Vector2(60, 0)
	var ld := _lbl(d, sz, col, hl, HORIZONTAL_ALIGNMENT_RIGHT, false)
	ld.custom_minimum_size = Vector2(80, 0)
	for l in [la, lb, lc, ld]:
		h.add_child(l)
	return pc


# ================================================================= виджеты

func _lbl(t: String, size: int = 24, col: Color = Sketch.INK, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("line_spacing", -4)
	if bold:
		l.add_theme_font_override("font", Sketch.font())
	l.size_flags_horizontal = Control.SIZE_FILL
	return l


func _btn(t: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.disabled = ad_busy
	b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void: _hover(b, true))
	b.mouse_exited.connect(func() -> void: _hover(b, false))
	return b


func _hover(b: Button, on: bool) -> void:
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "rotation", -0.017 if on else 0.0, 0.12)


func _btn_row(btns: Array, w: float) -> Control:
	var row: BoxContainer = HBoxContainer.new() if w > 420 else VBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for b in btns:
		row.add_child(b)
	return row


func _icon_btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 48)
	b.theme_type_variation = "IconButton"
	b.pressed.connect(cb)
	return b


func _portrait(ch: Dictionary, px: float) -> Control:
	var p: Control = PortraitScript.new()
	p.setup(ch, px)
	return p


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _pop_in(card: Control) -> void:
	card.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.85, 0.85)
	card.rotation = -0.035
	var tw := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.3)
	tw.tween_property(card, "scale", Vector2.ONE, 0.45)
	tw.tween_property(card, "rotation", 0.0, 0.45)


## линованная бумага + второй карандашный контур у карточки
func _draw_card(card: Control) -> void:
	var s := card.size
	var y := 32.0
	while y < s.y - 6:
		card.draw_line(Vector2(10, y), Vector2(s.x - 10, y), Color(0.314, 0.431, 0.627, 0.13), 1.0)
		y += 32.0
	Sketch.freeze_boil(true)
	var pts := Sketch.v([-5, -4, s.x * 0.5, -6, s.x + 3, -3, s.x + 5, s.y * 0.5, s.x + 2, s.y + 4, s.x * 0.5, s.y + 5, -4, s.y + 3, -6, s.y * 0.5])
	Sketch.s_poly(card, pts, 17, true, null, 1.4, 1.2, Color(Sketch.INK, 0.4))
	Sketch.freeze_boil(false)


# ================================================================= тема

func _box(bg: Color, border: int, shadow: Vector2, radii: Array = [18, 6, 16, 5]) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border)
	s.border_color = Sketch.INK
	s.corner_radius_top_left = radii[0]
	s.corner_radius_top_right = radii[1]
	s.corner_radius_bottom_right = radii[2]
	s.corner_radius_bottom_left = radii[3]
	s.shadow_color = Color(0.165, 0.141, 0.125, 0.85)
	s.shadow_size = 1 if shadow != Vector2.ZERO else 0
	s.shadow_offset = shadow
	s.anti_aliasing = true
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 6
	s.content_margin_bottom = 9
	return s


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = Sketch.font_regular()
	th.default_font_size = 26
	th.set_color("font_color", "Label", Sketch.INK)

	# кнопки
	th.set_font("font", "Button", Sketch.font())
	th.set_font_size("font_size", "Button", 28)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(c, "Button", Sketch.INK)
	th.set_color("font_disabled_color", "Button", Color(Sketch.INK, 0.45))
	th.set_stylebox("normal", "Button", _box(Color("#fffaf0"), 3, Vector2(3, 4)))
	th.set_stylebox("hover", "Button", _box(Color("#fffdf7"), 3, Vector2(5, 6)))
	th.set_stylebox("pressed", "Button", _box(Color("#f4ecdc"), 3, Vector2.ZERO))
	th.set_stylebox("disabled", "Button", _box(Color("#efe8da"), 3, Vector2(2, 2)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", _box(Color("#f8cdd9"), 3, Vector2(3, 4)))
	th.set_stylebox("hover", "PrimaryButton", _box(Color("#fad8e2"), 3, Vector2(5, 6)))
	th.set_stylebox("pressed", "PrimaryButton", _box(Color("#f0b9c9"), 3, Vector2.ZERO))
	th.set_stylebox("disabled", "PrimaryButton", _box(Color("#eedde2"), 3, Vector2(2, 2)))

	th.set_type_variation("IconButton", "Button")
	var round := [24, 22, 26, 23]
	var ib := _box(Color(1, 0.98, 0.94, 0.9), 3, Vector2(2, 3), round)
	ib.set_content_margin_all(4)
	th.set_stylebox("normal", "IconButton", ib)
	var ibh := ib.duplicate()
	ibh.bg_color = Color("#fff3f6")
	th.set_stylebox("hover", "IconButton", ibh)
	var ibp := ib.duplicate()
	ibp.shadow_offset = Vector2.ZERO
	th.set_stylebox("pressed", "IconButton", ibp)
	th.set_font_size("font_size", "IconButton", 24)

	# карточка
	var card := _box(Color("#f7f1e3"), 3, Vector2(6, 7), [26, 10, 24, 8])
	card.shadow_color = Color(0.165, 0.141, 0.125, 0.18)
	card.content_margin_left = 24
	card.content_margin_right = 24
	card.content_margin_top = 16
	card.content_margin_bottom = 20
	th.set_stylebox("panel", "PanelContainer", card)

	# поле имени
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0, 0, 0, 0)
	le.border_width_bottom = 3
	le.border_color = Sketch.INK
	le.content_margin_bottom = 2
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", le)
	th.set_color("font_color", "LineEdit", Sketch.INK)
	th.set_color("caret_color", "LineEdit", Sketch.INK)
	th.set_font("font", "LineEdit", Sketch.font())
	th.set_font_size("font_size", "LineEdit", 28)

	# прокрутка
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Sketch.INK, 0.35)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	th.set_stylebox("grabber", "VScrollBar", sb)
	th.set_stylebox("grabber_highlight", "VScrollBar", sb)
	th.set_stylebox("grabber_pressed", "VScrollBar", sb)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return th
