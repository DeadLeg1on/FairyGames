extends Node
## Интерфейс и игровой поток «Книги Фей» — порт src/FairyBook.tsx (с режимами).

const GameScript := preload("res://scripts/game.gd")
const PortraitScript := preload("res://scripts/portrait.gd")
const SETTINGS := "user://settings.cfg"

const PINK := Color("#c9446f")
const GOLD := Color("#e0a526")
const WINE := Color("#8a3b3b")
const RED := Color("#c8433b")
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const POLLEN_COL := Color("#b08810")

## поводы для полноэкранной рекламы: как часто её можно показывать
const AD_EVERY := {"chapter": 2, "restart": 1, "menu": 3, "hotel": 3}
## перезарядки рекламных наград (секунды)
const AD_CHEST_CD := 180.0
const AD_BLESS_CD := 300.0
const AD_KEY_CD := 1800.0
## «Отель фей»: перезарядки рекламных наград отеля
const AD_HOTEL_CD := 180.0
const AD_STAR_CD := 600.0
const AD_PROCS_CD := 300.0
## сколько времени игрок должен отсутствовать, чтобы считать это новой сессией
const RETURN_AFTER := 600.0

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
## колода сказок: какие карты собраны и какая выпала последней
var deck := Cards.empty()
var last_card := ""
var final_score := 0
var final_chapter := 0
var final_progress := 0
var scores: Array = []
var scores_tab := "story"
var rank := -1
var player_name := I18n.t("Фея")
var unlocked := 1
var continues := 0
var time_adds := 0
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
var settings_back := "menu"
var shop_flash := ""
var small := false
## наряды и мета-прогресс
var skin := "classic"
var skins := {}
var shop_tab := "up"
var garden := {}
var daily := {}
var blessing := false
var ad_counts := {}
var chest_flash := ""
var ad_hint: Label
var return_after_break := false
## выбран ли язык интерфейса (первый запуск показывает экран выбора)
var lang_chosen := false
## «Отель фей»: состояние idle-режима и служебные поля экрана
var hotel_state := {}
var hotel_tab := "guests"
var hotel_live: Array[Callable] = []
var hotel_flash := ""
var hotel_welcome := ""
var hotel_sel_i := -1
## выбор курсором на сцене отеля: "" | "q:<гостья на ресепшене>" | "r:<номер>:<место>"
var hotel_sel := ""
## открыт ли отель прямо сейчас (музыка отеля держится и в его окнах)
var hotel_open := false
var hotel_theme_for := -1
var hotel_proc_for := -1
var hotel_sig := ""
var hotel_clock := 0.0
## сцена отеля: узел живёт дольше перестроек окна, иначе феи на ней «моргают»
var hotel_view: HotelView = null
var hotel_proc_slot := 0
var seen_t := 0.0


func mode_def(m: String) -> Dictionary:
	return Modes.def(m)


## режим начинается с выбора главы
func is_single() -> bool:
	return Modes.pick(mode)


## открыт ли режим при текущем прогрессе
func mode_open(id: String) -> bool:
	return unlocked >= int(mode_def(id)["unlock"])


func _read_setting(section: String, key: String, def: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return cfg.get_value(section, key, def)
	return def


func _ready() -> void:
	randomize()
	# язык интерфейса: помним выбор игрока, при первом запуске — спрашиваем
	I18n.load_saved()
	lang_chosen = I18n.has_saved()
	player_name = I18n.t("Фея")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		player_name = str(cfg.get_value("player", "name", I18n.t("Фея")))
		unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, Chapters.story_count())
	pollen = Shop.load_pollen()
	upgrades = Shop.load_upgrades()
	skins = Shop.load_skins()
	skin = Shop.load_skin()
	garden = Shop.load_garden()
	daily = Shop.load_daily()
	deck = Cards.load_owned()
	blessing = bool(_read_setting("ads", "blessed", false))
	return_after_break = Time.get_unix_time_from_system() - Shop.last_seen() > RETURN_AFTER
	Shop.mark_seen()
	scores = Scores.load_all("story")

	game = GameScript.new()
	add_child(game)
	game.upgrades = upgrades.duplicate()
	game.skin = skin
	game.blessing = 0.15 if blessing else 0.0
	# собранные наборы колоды добавляют очков на весь забег
	game.card_bonus = Cards.score_bonus(deck)
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

	ad_hint = Label.new()
	ad_hint.text = I18n.t("✦ Реклама…")
	ad_hint.add_theme_font_size_override("font_size", 26)
	ad_hint.add_theme_color_override("font_color", Color("#b08810"))
	ad_hint.visible = false
	ad_hint.z_index = 8
	ui.add_child(ad_hint)
	Ads.platform_pause.connect(_pause)
	get_viewport().size_changed.connect(_on_resize)
	game.preview(0)
	_go("menu" if lang_chosen else "lang")
	await get_tree().process_frame
	Ads.mark_ready()
	# «реклама при возвращении»: игрок отсутствовал больше 10 минут —
	# показываем один полноэкранный ролик в меню (платформа это разрешает)
	if return_after_break:
		await get_tree().create_timer(3.0).timeout
		if screen == "menu" and not ad_busy:
			_set_busy(true)
			await Ads.show_fullscreen()
			_set_busy(false)


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for w in wobblers:
		if is_instance_valid(w):
			w.pivot_offset = w.size * 0.5
			w.rotation = sin(t * 2.1) * 0.026
	var vs := ui.get_viewport_rect().size
	top_bar.position = Vector2(vs.x - top_bar.size.x - 12, 12)
	if ad_hint and is_instance_valid(ad_hint):
		ad_hint.size = Vector2(vs.x, 40)
		ad_hint.position = Vector2(0, vs.y - 44)
	# idle-режим «Отель фей» живёт своими часами
	if screen == "hotel":
		_hotel_tick(dt)
	# раз в полминуты отмечаем, что игрок ещё здесь (для «награды за возвращение»)
	seen_t += dt
	if seen_t > 30.0:
		seen_t = 0.0
		Shop.mark_seen()


func _on_resize() -> void:
	if screen != "play":
		_build_overlay()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()


# ================================================================= поток

func _go(s: String) -> void:
	screen = s
	_sync_music()
	if s == "play":
		Ads.gameplay_start()
	else:
		Ads.gameplay_stop()
	pause_btn.visible = s == "play"
	# липкий баннер живёт только вне геймплея; настройки открываются и из паузы,
	# поэтому баннер там тоже скрыт — иначе он мигает при каждом входе в паузу
	if s == "play" or s == "paused" or s == "lang" or s == "settings":
		Ads.hide_banner()
	else:
		Ads.show_banner()
	_build_overlay()


## музыка: меню, главы и отель — три темы, каждая в своём настроении
func _sync_music() -> void:
	Music.play(Music.want_for(screen, mode, hotel_open))


func _toggle_music() -> void:
	Music.toggle()
	if Music.enabled and Music.track == "":
		_sync_music()
	Sfx.play("click")
	_build_overlay()


func _music_label() -> String:
	return I18n.t("♪ Музыка: включена") if Music.enabled else I18n.t("♪ Музыка: выключена")


func _set_busy(on: bool) -> void:
	ad_busy = on
	if ad_hint and is_instance_valid(ad_hint):
		var vs := ui.get_viewport_rect().size
		ad_hint.size = Vector2(vs.x, 40)
		ad_hint.position = Vector2(0, vs.y - 44)
		ad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ad_hint.visible = on
	if overlay:
		for b in overlay.find_children("*", "Button", true, false):
			if not b.has_meta("locked"):
				(b as Button).disabled = on


## полноэкранная реклама (если платформа разрешит), затем действие
func _with_ad(action: Callable) -> void:
	if ad_busy:
		return
	_set_busy(true)
	var shown: bool = await Ads.show_fullscreen()
	_set_busy(false)
	if shown:
		Shop.add_counter("fullscreen_total")
	action.call()


## полноэкранная реклама по правилам повода: «каждый N-й раз» + лимиты платформы
func _interstitial(context: String, action: Callable) -> void:
	ad_counts[context] = int(ad_counts.get(context, 0)) + 1
	var every := int(AD_EVERY.get(context, 1))
	if every <= 0 or int(ad_counts[context]) % every != 0 or not Ads.interstitial_ok():
		action.call()
		return
	_with_ad(action)


## реклама с вознаграждением: true — награда засчитана
func _rewarded(tag: String) -> bool:
	_set_busy(true)
	var ok: bool = await Ads.show_rewarded(tag)
	_set_busy(false)
	if ok:
		Shop.add_counter("rewarded_" + tag)
		Shop.add_counter("rewarded_total")
	return ok


func _save_setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS)


func _unlock(n: int) -> void:
	var v := clampi(maxi(unlocked, n), 1, Chapters.story_count())
	if v != unlocked:
		unlocked = v
		_save_setting("progress", "unlocked", v)


func _record(score: int, chapter: int) -> void:
	var entry := {"name": player_name.substr(0, 14) if player_name != "" else I18n.t("Фея"), "score": score, "chapter": chapter, "wave": game.wave, "date": int(Time.get_unix_time_from_system() * 1000.0) * 10 + randi() % 10}
	var res := Scores.save(entry, mode)
	scores = res[0]
	scores_tab = mode
	# пыльца за очки с прошлого начисления (после «второго шанса» — только прирост)
	last_pollen = Shop.pollen_for(score - granted_score, int(upgrades["bag"]))
	# «Ночные сказки» в колоде прибавляют пыльцы
	var card_pollen := Cards.pollen_bonus(deck)
	if card_pollen > 0.0 and last_pollen > 0:
		last_pollen = int(round(float(last_pollen) * (1.0 + card_pollen)))
	granted_score = score
	doubled = false
	# «Ежедневный вызов» платит двойную пыльцу и ведёт серию дней
	if mode == "daily":
		last_pollen *= 2
		Shop.daily_best(score)
		daily = Shop.load_daily()
	_add_pollen(last_pollen)
	rank = res[1]
	last_entry_date = int(entry["date"])
	final_score = score
	final_chapter = chapter
	# благословение фей действует ровно один забег
	if blessing:
		_set_blessing(false)


func _on_chapter_cleared(idx: int, bonus: int, score: int) -> void:
	_unlock(idx + 2)
	_draw_card()
	if _single_run():
		# одиночные режимы заканчиваются на первой пройденной главе
		_record(score, idx)
		_go("result")
		return
	if idx >= Chapters.story_count() - 1:
		_record(score, Chapters.story_count())
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
	if not mode_open(m):
		Sfx.play("nocharge")
		shop_flash = "locked"
		return
	Sfx.play("click")
	mode = m
	continues = 0
	if Modes.hotel(m):
		_open_hotel()
		return
	prev_clear = {}
	granted_score = 0
	if m == "duel":
		# «Дуэль» всегда идёт на фоне звёздной главы
		game.new_run(m)
		game.preview(Modes.NO_BOSS_CHAPTER)
		story_idx = Modes.NO_BOSS_CHAPTER
		_go("story")
	elif m == "guard":
		# «Звёздная стража»: поляна одна и та же, главу выбирать не нужно
		game.new_run(m)
		game.preview(Modes.GUARD_CHAPTER)
		story_idx = Modes.GUARD_CHAPTER
		_go("story")
	elif m == "daily":
		# глава дня выбирается жребием от даты
		story_idx = Modes.daily_chapter(unlocked)
		game.new_run(m)
		game.preview(story_idx)
		_go("story")
	elif Modes.story(m):
		game.new_run(m)
		game.preview(0)
		story_idx = 0
		_go("story")
	else:
		_go("select")


## одиночный забег (не «сказка» на много глав)
func _single_run() -> bool:
	return not Modes.story(mode)


## сколько раз за забег можно «продолжить за рекламу»
func max_continues() -> int:
	return 2 if (mode == "endless" or mode == "marathon" or mode == "duel" or mode == "race" or mode == "guard") else 1


## выбор главы (одиночные режимы)
func _pick_chapter(idx: int) -> void:
	if ad_busy or idx >= unlocked or Modes.chapter_blocked(mode, idx):
		return
	Sfx.play("click")
	game.new_run(mode)
	game.preview(idx)
	story_idx = idx
	prev_clear = {}
	continues = 0
	granted_score = 0
	_go("story")


func _begin_chapter() -> void:
	if ad_busy:
		return
	if mode == "daily" and Shop.daily_attempts_left() <= 0:
		Sfx.play("nocharge")
		return
	if mode == "daily":
		Shop.daily_use()
	var run := func() -> void:
		if is_single() or mode == "daily" or mode == "duel":
			game.new_run(mode)
		game.skin = skin
		game.blessing = 0.15 if blessing else 0.0
		game.start_chapter(story_idx)
		rank = -1
		_go("play")
	# полноэкранная реклама — только в естественных паузах между главами
	_interstitial("chapter", run)


func _restart() -> void:
	if ad_busy:
		return
	if mode == "daily" and Shop.daily_attempts_left() <= 0:
		# «Ещё раз» в режиме дня — только за рекламу
		_daily_extra_attempt(true)
		return
	_interstitial("restart", func() -> void:
		game.skin = skin
		game.blessing = 0.15 if blessing else 0.0
		game.restart()
		rank = -1
		continues = 0
		prev_clear = {}
		granted_score = 0
		_go("play"))


func _next_chapter() -> void:
	if story_idx + 1 < Chapters.story_count():
		_pick_chapter(story_idx + 1)


## реклама с вознаграждением: второй шанс в текущем забеге
func _continue_for_ad() -> void:
	if ad_busy or continues >= max_continues():
		return
	var ok: bool = await _rewarded("continue")
	if not ok:
		return
	continues += 1
	scores = Scores.remove(last_entry_date, mode)
	rank = -1
	if game.is_race() and game.time_failed:
		# в «Гонке» вместо сердца даём запас секунд
		game.continue_race(20.0)
		time_adds += 1
	else:
		game.revive()
	_go("play")


## +1 сердце за рекламу прямо в паузе
func _heal_for_ad() -> void:
	if ad_busy or game.heals_used >= 3 or game.hearts >= 5:
		return
	var ok: bool = await _rewarded("heal")
	if not ok:
		return
	game.heal(true)
	_resume()


## +20 секунд за рекламу в «Гонке»
func _time_for_ad() -> void:
	if ad_busy or not game.is_race():
		return
	var ok: bool = await _rewarded("time")
	if not ok:
		return
	game.time_left += 20.0
	game.time_adds += 1
	game.pop_text(game.px, game.py - 44, I18n.t("+20 секунд!"), Color("#5cc7c0"), 28)
	Sfx.play("bloom")
	_resume()


## «Ежедневный вызов»: перейти к главе дня (или взять попытку за рекламу)
func _daily_play() -> void:
	if ad_busy:
		return
	if Shop.daily_attempts_left() <= 0:
		_daily_extra_attempt(false)
		return
	mode = "daily"
	story_idx = Modes.daily_chapter(unlocked)
	game.new_run(mode)
	game.preview(story_idx)
	prev_clear = {}
	granted_score = 0
	_go("story")


## «Ежедневный вызов»: ещё одна попытка за рекламу
func _daily_extra_attempt(from_restart: bool = false) -> void:
	if ad_busy or Shop.daily_used_ad_attempt():
		return
	var ok: bool = await _rewarded("daily")
	if not ok:
		return
	Shop.daily_use(true)
	game.new_run(mode)
	game.preview(story_idx)
	if from_restart:
		_go("story")
	else:
		_build_overlay()


func _pause() -> void:
	if screen == "play" and not ad_busy:
		game.pause()
		_go("paused")


func _resume() -> void:
	if screen == "paused":
		game.resume()
		_go("play")


func _to_menu() -> void:
	last_card = ""
	hotel_open = false
	game.preview(0)
	_go("menu")


## выход в меню после забега: каждый третий раз — полноэкранная реклама
func _to_menu_after_run() -> void:
	_interstitial("menu", _to_menu)


func _to_select() -> void:
	game.preview(story_idx)
	_go("select")


## выбор языка на самом первом экране
func _pick_lang(id: String) -> void:
	I18n.set_lang(id)
	lang_chosen = true
	_rename_default()
	Sfx.play("click")
	_to_menu()


## быстрая смена языка из меню (кнопка «Язык: …» или клавиша L)
func _toggle_lang() -> void:
	I18n.set_lang(I18n.EN if I18n.lang == I18n.RU else I18n.RU)
	_rename_default()
	Sfx.play("click")
	_build_overlay()


## имя по умолчанию переводится вместе с языком, пока игрок не назвал фею сам
func _rename_default() -> void:
	if player_name == "Фея" or player_name == "Fairy":
		player_name = I18n.t("Фея")
	_save_setting("player", "name", player_name)


func _open_modes() -> void:
	if ad_busy:
		return
	Sfx.play("click")
	_go("modes")


func _open_rewards() -> void:
	if ad_busy:
		return
	Sfx.play("click")
	_go("rewards")


# ---------------------------------------------------------------- колода сказок

## за пройденную главу вытягиваем одну карту: зерно — от времени, пыльцы и колоды
func _draw_card() -> void:
	var seed_int := int(Time.get_unix_time_from_system() * 1000.0) % 1000003 + pollen + Cards.count(deck) * 31
	last_card = Cards.take(seed_int)
	if last_card == "":
		return
	deck = Cards.load_owned()
	game.card_bonus = Cards.score_bonus(deck)
	Sfx.play("bloom")


func _open_cards() -> void:
	Sfx.play("click")
	_go("cards")


func _close_cards() -> void:
	Sfx.play("click")
	_to_menu()


## экран «Колода сказок»: три набора по пять карт и бонусы за сбор
func _build_cards(box: VBoxContainer, w: float) -> void:
	box.add_child(_lbl(I18n.t("✧ Колода сказок"), 44 if small else 52, GOLD, true))
	box.add_child(_lbl(I18n.t("Карты выпадают за пройденные главы. Собери набор — и маленький бонус останется навсегда."), 19, Color(Sketch.INK, 0.8)))
	box.add_child(_lbl(I18n.t("Собрано карт: %d из %d") % [Cards.count(deck), Cards.CARDS.size()], 22, POLLEN_COL, true))
	box.add_child(_lbl(Cards.bonus_text(deck), 19, Color(Sketch.INK, 0.75)))
	box.add_child(_gap(6))
	for s in Cards.sets():
		var sid := str(s["id"])
		var got := Cards.set_count(deck, sid)
		var total := Cards.cards_of(sid).size()
		var full := got == total and total > 0
		var head := "%s %s · %d/%d" % [str(s["icon"]), str(s["title"]), got, total]
		head += ("  ✓ " + str(s["bonus"])) if full else ("  — " + str(s["bonus"]))
		box.add_child(_lbl(head, 22, GOLD if full else Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		var grid := GridContainer.new()
		# пять карт набора в ряд, если места хватает, иначе три
		grid.columns = 5 if w > 520.0 else 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for c in Cards.cards_of(sid):
			grid.add_child(_card_cell(c, bool(deck.get(str(c["id"]), false))))
		box.add_child(grid)
		box.add_child(_gap(4))
	box.add_child(_btn_row([_small_btn(I18n.t("← Назад"), _close_cards)], 460))


## одна карта: найденная показана целиком, ненайденная — рубашкой
func _card_cell(c: Dictionary, owned: bool) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0, 96)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.99, 0.97, 0.92, 0.92) if owned else Color(Sketch.INK, 0.06)
	st.set_border_width_all(2)
	st.border_color = Color(GOLD, 0.85) if owned else Color(Sketch.INK, 0.22)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(6)
	cell.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	cell.add_child(v)
	if owned:
		v.add_child(_lbl(str(c["icon"]), 30, GOLD, true))
		v.add_child(_lbl(str(c["title"]), 16, Sketch.INK, true))
		v.add_child(_lbl(str(c["desc"]), 13, Color(Sketch.INK, 0.7)))
	else:
		v.add_child(_lbl("?", 30, Color(Sketch.INK, 0.3), true))
		v.add_child(_lbl(I18n.t("ещё не найдена"), 15, Color(Sketch.INK, 0.45)))
	return cell


## строчка о прогрессе, саде и вызове дня на главном экране
func _progress_hint() -> String:
	var parts := [I18n.t("Открыто глав: %d из %d") % [unlocked, Chapters.story_count()]]
	daily = Shop.load_daily()
	var today := str(daily["date"]) == Modes.daily_key()
	parts.append(I18n.t("★ Вызов дня %s") % (I18n.t("пройден, серия %d дн.") % int(daily["streak"]) if today else I18n.t("ждёт")))
	if int(upgrades["garden"]) > 0:
		var pending := Shop.garden_now(int(upgrades["garden"]), garden)
		if pending > 0:
			parts.append(I18n.t("☀ В саду %d ✦") % pending)
	return " · ".join(parts)


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
	if code == KEY_M and k.shift_pressed:
		_toggle_mute()
	elif code == KEY_M:
		_toggle_music()
	if s == "lang" and code == KEY_2:
		_pick_lang(I18n.EN)
	elif s == "lang" and (code == KEY_1 or code == KEY_ENTER or code == KEY_SPACE):
		_pick_lang(I18n.RU)
	elif s == "menu" and code == KEY_L:
		_toggle_lang()
	elif s == "hotel" and code == KEY_ESCAPE:
		_leave_hotel()
	elif s == "hotel" and code >= KEY_1 and code <= KEY_4:
		_hotel_set_tab(["guests", "rooms", "spa", "up"][code - KEY_1])
	if s == "modes" and code == KEY_ESCAPE:
		_to_menu()
	elif s == "rewards" and code == KEY_ESCAPE:
		_to_menu()
	elif s == "cards" and code == KEY_ESCAPE:
		_close_cards()
	elif s == "play" and (code == KEY_ESCAPE or code == KEY_P):
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
	elif s == "select" and code >= KEY_1 and code <= KEY_9:
		_pick_chapter(code - KEY_1)
	elif s == "result" and (code == KEY_ENTER or code == KEY_SPACE):
		if story_idx < Chapters.story_count() - 1:
			_next_chapter()
		else:
			_restart()
	elif s == "shop" and code == KEY_ESCAPE:
		_close_shop()
	elif s == "settings" and code == KEY_ESCAPE:
		_close_settings()
	elif s == "scores" and code == KEY_ESCAPE:
		_go("menu")
	if (s == "over" or s == "win" or s == "paused" or s == "result") and code == KEY_R:
		_restart()
	elif (s == "over" or s == "win") and (code == KEY_ENTER or code == KEY_SPACE):
		_restart()
	elif (s == "over" or s == "win" or s == "result") and code == KEY_ESCAPE:
		_to_menu()


# ================================================================= построение экранов

func _build_overlay() -> void:
	# сцена отеля переживает перестройку окна: уносим её из старого оверлея
	# до удаления, иначе она удалится вместе с ним и картинка заметно мигает
	if hotel_view != null and is_instance_valid(hotel_view) and hotel_view.get_parent() != null:
		hotel_view.get_parent().remove_child(hotel_view)
	if screen != "hotel" and hotel_view != null and is_instance_valid(hotel_view):
		hotel_view.queue_free()
		hotel_view = null
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
		"menu", "lang":
			dim.color = Color(0.937, 0.91, 0.847, 0.35)
		"story", "scores", "select", "shop", "modes", "rewards", "settings", "cards":
			dim.color = Color(0.118, 0.094, 0.078, 0.25)
		"hotel":
			dim.color = Color(0.298, 0.196, 0.118, 0.3)
		"win", "result":
			dim.color = Color(1, 0.94, 0.78, 0.3)
		_:
			dim.color = Color(0.118, 0.094, 0.078, 0.38)
	overlay.add_child(dim)

	var maxw := 540.0
	match screen:
		"menu":
			maxw = 860.0 if wide else 540.0
		"lang":
			maxw = 520.0
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
		"modes":
			maxw = 980.0 if wide else 560.0
		"rewards":
			maxw = 900.0 if wide else 560.0
		"cards":
			maxw = 940.0 if wide else 560.0
		"hotel":
			maxw = 980.0 if wide else 560.0
		"settings":
			maxw = 700.0 if wide else 520.0
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
		"lang":
			_build_lang(box, inner_w)
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
		"modes":
			_build_modes(box, inner_w)
		"rewards":
			_build_rewards(box, inner_w)
		"cards":
			_build_cards(box, inner_w)
		"hotel":
			_build_hotel(box, inner_w)
		"settings":
			_build_settings(box, inner_w)
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

	left.add_child(_lbl(I18n.t("карандашная сказка в девяти главах"), 22, Color(Sketch.INK, 0.7)))
	var title := _lbl(I18n.t("Книга Фей"), 72, PINK, true)
	left.add_child(title)
	wobblers.append(title)
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", -20)
	for i in Chapters.story_count():
		prow.add_child(_portrait(Chapters.get_ch(i), 50))
	left.add_child(prow)
	left.add_child(_lbl(_progress_hint(), 20, Color(Sketch.INK, 0.75)))
	left.add_child(_lbl(I18n.t("Как тебя зовут?"), 22, Color(Sketch.INK, 0.8)))
	var name_edit := LineEdit.new()
	name_edit.text = player_name
	name_edit.max_length = 14
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_edit.text_changed.connect(_set_name)
	name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
	left.add_child(name_edit)

	# одна главная кнопка вместо сетки из четырёх режимов: все режимы живут
	# на своём экране, а меню осталось таким же, только свободнее
	var story := mode_def("story")
	var play_btn := _btn("%s %s\n%s" % [str(story["icon"]), str(story["title"]), str(story["desc"])], _choose_mode.bind("story"), true)
	play_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.custom_minimum_size = Vector2(0, 80)
	play_btn.add_theme_font_size_override("font_size", 24)
	right.add_child(play_btn)
	# глава «Отель фей» — вход прямо с главного экрана
	var hch := Chapters.get_ch(Chapters.hotel_index())
	var hs := Hotel.load_state()
	var hcard := PanelContainer.new()
	hcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hst := StyleBoxFlat.new()
	hst.bg_color = Color(hch["wing"], 0.8)
	hst.set_border_width_all(2)
	hst.border_color = Color(hch["main"], 0.8)
	hst.set_corner_radius_all(10)
	hst.set_content_margin_all(6)
	hcard.add_theme_stylebox_override("panel", hst)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hcard.add_child(hrow)
	var hp := _portrait(hch, 58)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(hp)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 0)
	var hbtn := _btn("%s %s · %s" % [str(hch["num"]), str(hch["title"]), I18n.t("гости, номера, процедуры")], _open_hotel, true)
	hbtn.add_theme_font_size_override("font_size", 24)
	hbtn.custom_minimum_size = Vector2(0, 44)
	if not mode_open("idle"):
		hbtn.disabled = true
		hbtn.set_meta("locked", true)
	hv.add_child(hbtn)
	var hline := I18n.t("рейтинг ★%.1f · гостей %d") % [Hotel.stars(hs), int(hs["served"])]
	# сколько пыльцы уже накопилось без игрока — считаем на копии состояния
	var hres := Hotel.settle(hs.duplicate(true))
	if int(hres["pollen"]) > 0:
		hline += I18n.t(" · в кассе ждёт %d ✦") % int(hres["pollen"])
	if not mode_open("idle"):
		hline = I18n.t("нужно открыть глав: %d") % int(mode_def("idle")["unlock"])
	hv.add_child(_lbl(hline, 18, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	hrow.add_child(hv)
	right.add_child(hcard)
	var modes_btn := _btn(I18n.t("✦ Все режимы (%d) · награды за рекламу") % Modes.count(), _open_modes, true)
	modes_btn.add_theme_font_size_override("font_size", 24)
	modes_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(modes_btn)
	var foot: Array = [_small_btn(I18n.t("✿ Лавка · ✦ %d") % pollen, _open_shop)]
	foot.append(_small_btn(I18n.t("✧ Колода · %d/%d") % [Cards.count(deck), Cards.CARDS.size()], _open_cards))
	foot.append(_small_btn(I18n.t("⚙ Настройки"), _open_settings))
	foot.append(_small_btn(I18n.t("Рекорды"), _open_scores.bind("story")))
	if not OS.has_feature("web"):
		foot.append(_small_btn(I18n.t("Выход"), func() -> void: get_tree().quit()))
	right.add_child(_btn_row(foot, 460))
	# одна короткая строка вместо двух длинных: остальное — в настройках
	right.add_child(_lbl(I18n.t("Стрелки / WASD — полёт, Пробел — рывок. Звук, язык и управление — в настройках"), 19, Color(Sketch.INK, 0.8)))


## рекорд режима (для карточек режимов)
func _best_of(m: String) -> int:
	var list := Scores.load_all(m)
	return int(list[0].get("score", 0)) if not list.is_empty() else 0


## первый запуск: вопрос о языке — оба варианта написаны на своём языке
func _build_lang(box: VBoxContainer, w: float) -> void:
	box.add_child(_lbl("Книга Фей · Fairy Book", 46, PINK, true))
	box.add_child(_lbl("Выбери язык  ·  Choose your language", 26, WINE, true))
	box.add_child(_gap(4))
	for d in I18n.LANGS:
		var b := _btn(str(d["title"]), _pick_lang.bind(str(d["id"])), str(d["id"]) == I18n.lang)
		b.add_theme_font_size_override("font_size", 32)
		b.custom_minimum_size = Vector2(240, 52)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(b)
		box.add_child(_lbl(str(d["sub"]), 18, Color(Sketch.INK, 0.65)))
	box.add_child(_gap(4))
	box.add_child(_lbl("Язык всегда можно сменить в меню · You can change the language later in the menu", 18, Color(Sketch.INK, 0.7)))


## экран «Настройки»: громкость музыки и звуков, язык, управление
func _build_settings(box: VBoxContainer, w: float) -> void:
	box.add_child(_lbl(I18n.t("Настройки"), 54, Sketch.INK, true))
	box.add_child(_lbl(I18n.t("Музыка и звуки сведены к одному уровню: ни то, ни другое не перекрикивает друг друга."), 20, Color(Sketch.INK, 0.75)))
	box.add_child(_gap(6))
	box.add_child(_volume_row(I18n.t("♪ Музыка"), Music.volume, _set_music_volume, _toggle_music,
		I18n.t("♪ Музыка: включена") if Music.enabled else I18n.t("♪ Музыка: выключена")))
	box.add_child(_volume_row(I18n.t("✦ Звуки"), Sfx.volume, _set_sfx_volume, _toggle_mute_here,
		I18n.t("✦ Звуки: включены") if not Sfx.muted else I18n.t("✦ Звуки: выключены")))
	box.add_child(_btn_row([
		_small_btn(I18n.t("Сбросить звук"), _reset_audio),
		_small_btn(I18n.t("Язык: %s") % I18n.title_of(I18n.EN if I18n.lang == I18n.RU else I18n.RU), _toggle_lang),
	], 420))
	box.add_child(_gap(6))
	box.add_child(_lbl(I18n.t("Управление"), 26, Color(Sketch.INK, 0.85), true, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(_lbl(I18n.t("Клавиатура: стрелки / WASD — полёт, Пробел / Shift — рывок, Esc — пауза, R — заново, M — музыка, Shift+M — звуки"), 19, Color(Sketch.INK, 0.75), false, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(_lbl(I18n.t("Касание: веди пальцем — полёт, «Рывок» или второй палец — рывок"), 19, Color(Sketch.INK, 0.75), false, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(_gap(6))
	box.add_child(_btn_row([_small_btn(I18n.t("← Назад"), _close_settings)], 200))


## строка громкости: подпись, ползунок, проценты и кнопка вкл/выкл.
## Ползунок не перестраивает экран (иначе ручка «прыгает» под пальцем) —
## проценты обновляются на месте, а кнопка вкл/выкл перерисовывает окно.
func _volume_row(title: String, value: float, slide: Callable, toggle: Callable, toggle_text: String) -> Control:
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.45)
	st.set_border_width_all(2)
	st.border_color = Color(Sketch.INK, 0.4)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", st)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(_lbl(title, 24, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT, false))
	var pct := _lbl("%d%%" % roundi(clampf(value, 0.0, 1.0) * 100.0), 22, POLLEN_COL, true, HORIZONTAL_ALIGNMENT_RIGHT, false)
	head.add_child(pct)
	head.add_child(_small_btn(toggle_text, toggle))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 1.0
	sl.value = roundf(clampf(value, 0.0, 1.0) * 100.0)
	sl.custom_minimum_size = Vector2(0, 34)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	v.add_child(sl)
	sl.value_changed.connect(func(p: float) -> void:
		slide.call(clampf(p / 100.0, 0.0, 1.0))
		pct.text = "%d%%" % roundi(p))
	return pc


## выключить/включить звуки и обновить подписи на экране настроек
func _toggle_mute_here() -> void:
	_toggle_mute()
	_build_overlay()


func _set_music_volume(v: float) -> void:
	Music.set_volume(v)
	if Music.enabled and Music.track == "":
		_sync_music()


func _set_sfx_volume(v: float) -> void:
	Sfx.set_volume(v)
	# короткий щелчок на каждом движении ползунка: громкость слышно сразу
	Sfx.play("click")


## вернуть громкость к той, что была задумана (музыка и звуки поровну)
func _reset_audio() -> void:
	# порядок важен: громкость выставляем до включения, тогда музыка
	# возвращается плавным фейдом и сразу на нужный уровень
	Music.set_volume(Music.DEFAULT_VOLUME)
	Music.set_enabled(true)
	Sfx.set_volume(Sfx.DEFAULT_VOLUME)
	Sfx.set_muted(false)
	Sfx.play("click")
	_build_overlay()


func _open_settings() -> void:
	if ad_busy:
		return
	Sfx.play("click")
	settings_back = screen
	_go("settings")


func _close_settings() -> void:
	Sfx.play("click")
	_go(settings_back if settings_back != "settings" else "menu")


## экран «Все режимы»: все игры под одной обложкой
func _build_modes(box: VBoxContainer, w: float) -> void:
	box.add_child(_lbl(I18n.t("Режимы игры"), 54, Sketch.INK, true))
	box.add_child(_lbl(I18n.t("У каждого режима своя таблица рекордов. Новые открываются вместе с главами."), 20, Color(Sketch.INK, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 3 if wide else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for d in Modes.list():
		var id: String = d["id"]
		var open := mode_open(id)
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := StyleBoxFlat.new()
		st.bg_color = Color(1, 1, 1, 0.5) if open else Color(0.88, 0.85, 0.8, 0.4)
		st.set_border_width_all(2)
		st.border_color = Color(Sketch.INK, 0.45)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(6)
		cell.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		v.add_child(_lbl("%s %s" % [d["icon"], d["title"]], 22, Sketch.INK if open else Color(Sketch.INK, 0.5), true, HORIZONTAL_ALIGNMENT_LEFT))
		v.add_child(_lbl(str(d["desc"]), 17, Color(Sketch.INK, 0.75), false, HORIZONTAL_ALIGNMENT_LEFT))
		var b := _btn(I18n.t("Играть"), _choose_mode.bind(id), id == "story")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		if open:
			var best := _best_of(id)
			v.add_child(_lbl(I18n.t("рекорд: %d") % best if best > 0 else I18n.t("ещё не играли"), 17, POLLEN_COL, false, HORIZONTAL_ALIGNMENT_LEFT))
		else:
			v.add_child(_lbl("🔒 " + Modes.unlock_text(d), 17, RED, false, HORIZONTAL_ALIGNMENT_LEFT))
			b.disabled = true
			b.set_meta("locked", true)
		v.add_child(b)
		grid.add_child(cell)
	box.add_child(grid)
	box.add_child(_gap(4))
	box.add_child(_btn_row([
		_small_btn(I18n.t("✦ Награды за рекламу"), _open_rewards),
		_small_btn(I18n.t("Лавка фей · ✦ %d") % pollen, _open_shop),
		_small_btn(I18n.t("← В меню"), _to_menu),
	], 560))


## экран «Награды за рекламу»: все добровольные просмотры в одном месте
func _build_rewards(box: VBoxContainer, w: float) -> void:
	box.add_child(_lbl(I18n.t("Награды за рекламу"), 52, POLLEN_COL, true))
	box.add_child(_lbl(I18n.t("Короткая реклама — и подарок. Смотреть её или нет, решаешь только ты: игра проходится и без неё."), 20, Color(Sketch.INK, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 3 if wide else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	# сундук фей
	var chest_left := Shop.cooldown_left("chest", AD_CHEST_CD)
	grid.add_child(_reward_card(
		I18n.t("✿ Сундук фей"),
		I18n.t("Случайная пыльца: от 40 до 130 ✦. Открывается раз в 3 минуты."),
		chest_flash if chest_flash != "" else (I18n.t("готово к открытию") if chest_left <= 0.0 else I18n.t("снова через %d мин") % (int(chest_left) / 60 + 1)),
		I18n.t("▶ Открыть сундук"),
		_chest_for_ad,
		chest_left > 0.0,
		chest_flash != ""))
	chest_flash = ""
	# благословение
	var bless_left := Shop.cooldown_left("bless", AD_BLESS_CD)
	grid.add_child(_reward_card(
		I18n.t("❀ Благословение фей"),
		I18n.t("+1 щит в начале и +15% очков на следующий забег."),
		I18n.t("✓ Активно") if blessing else (I18n.t("готово") if bless_left <= 0.0 else I18n.t("снова через %d мин") % (int(bless_left) / 60 + 1)),
		I18n.t("▶ Получить благословение"),
		_bless_for_ad,
		blessing or bless_left > 0.0,
		blessing))
	# ключ главы
	var key_left := Shop.cooldown_left("key", AD_KEY_CD)
	var all_open := unlocked >= Chapters.story_count()
	grid.add_child(_reward_card(
		I18n.t("❧ Ключ главы"),
		I18n.t("Открывает следующую главу, не проходя предыдущую. Раз в полчаса."),
		I18n.t("все главы открыты") if all_open else (I18n.t("готово: откроет главу %d") % (unlocked + 1) if key_left <= 0.0 else I18n.t("снова через %d мин") % (int(key_left) / 60 + 1)),
		I18n.t("▶ Открыть главу"),
		_key_for_ad,
		all_open or key_left > 0.0,
		false))
	# попытка дня
	var daily_left := Shop.daily_attempts_left()
	var ad_daily := Shop.daily_used_ad_attempt()
	grid.add_child(_reward_card(
		I18n.t("★ Вторая попытка дня"),
		I18n.t("«Ежедневный вызов» — ещё один забег сегодня. Очки и пыльца ×2."),
		(I18n.t("попытка ещё не потрачена — играй!") if daily_left > 0 else (I18n.t("использована") if ad_daily else I18n.t("можно взять за рекламу"))),
		I18n.t("▶ Принять вызов") if daily_left > 0 else I18n.t("▶ Ещё попытка"),
		_daily_play,
		daily_left <= 0 and ad_daily,
		false))
	# сад фей
	var glvl := int(upgrades["garden"])
	var pending := Shop.garden_now(glvl, garden)
	grid.add_child(_reward_card(
		I18n.t("☀ Сад фей"),
		(I18n.t("Пока тебя нет, сад копит пыльцу. Внутри: %d ✦ (копилка до %d ✦).") % [pending, Shop.garden_cap(glvl)]) if glvl > 0 else I18n.t("Купи «Сад фей» в лавке — и он начнёт копить пыльцу сам."),
		(I18n.t("можно собрать %d ✦") % pending) if pending > 0 else I18n.t("пусто, заходи позже"),
		I18n.t("▶ Собрать ×2"),
		_claim_garden.bind(true),
		glvl <= 0 or pending <= 0,
		false))
	# отель фей: свои награды живут на его экране
	grid.add_child(_reward_card(
		I18n.t("♨ Отель фей"),
		I18n.t("Idle-глава: приглашение редкой гостьи, мгновенные процедуры и ×2 к кассе — на экране отеля."),
		(I18n.t("открыт: глав открыто %d") % unlocked) if mode_open("idle") else I18n.t("нужно открыть глав: %d") % 2,
		I18n.t("▶ Открыть отель"),
		_open_hotel,
		not mode_open("idle"),
		false))
	# лечение в бою
	grid.add_child(_reward_card(
		I18n.t("♥ Лечение в бою"),
		I18n.t("+1 сердце прямо в забеге. Бывает очень кстати — доступно на паузе."),
		I18n.t("открой паузу (Esc) во время игры"),
		I18n.t("Понятно"),
		func() -> void: _build_overlay(),
		false,
		false))
	box.add_child(grid)
	box.add_child(_lbl(I18n.t("Полноэкранная реклама показывается только между главами и забегами, никогда — во время игры."), 18, Color(Sketch.INK, 0.7)))
	box.add_child(_gap(4))
	box.add_child(_btn_row([_small_btn(I18n.t("Лавка фей"), _open_shop), _small_btn(I18n.t("← В меню"), _to_menu)], 420))


## карточка-награда: заголовок, описание, состояние и кнопка
func _reward_card(title: String, desc: String, state: String, btn_text: String, cb: Callable, disabled: bool, done: bool) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.969, 0.816, 0.376, 0.55) if done else Color(1, 1, 1, 0.55)
	st.set_border_width_all(2)
	st.border_color = Color(Sketch.INK, 0.5)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(8)
	cell.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	cell.add_child(v)
	v.add_child(_lbl(title, 23, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(_lbl(desc, 17, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(_lbl(state, 17, POLLEN_COL, true, HORIZONTAL_ALIGNMENT_LEFT))
	var b := _btn(btn_text, cb, not disabled)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	if disabled:
		b.disabled = true
		b.set_meta("locked", true)
	v.add_child(b)
	return cell


func _build_select(box: VBoxContainer, w: float) -> void:
	var md := mode_def(mode)
	box.add_child(_lbl("%s %s" % [md["icon"], md["title"]], 22, Color(Sketch.INK, 0.7)))
	box.add_child(_lbl(I18n.t("Выбери главу"), 50, Sketch.INK, true))
	box.add_child(_lbl(str(md["desc"]) + I18n.t(" Новые главы открываются по мере прохождения."), 20, Color(Sketch.INK, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 5 if wide else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var all := Scores.load_all(mode)
	for i in Chapters.story_count():
		var c := Chapters.get_ch(i)
		var blocked := Modes.chapter_blocked(mode, i)
		var locked := i >= unlocked or blocked
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
		var cap := I18n.t("🔒 пройди предыдущую") if i >= unlocked else (I18n.t("в этом режиме главы нет") if blocked else (I18n.t("рекорд %d") % best if best >= 0 else str(c["kind"])))
		if not locked and mode == "race":
			cap = (I18n.t("рекорд %d · ⏱ %d с") % [best, int(game.chapter_time(i))]) if best >= 0 else I18n.t("⏱ %d секунд на задание") % int(game.chapter_time(i))
		cell.add_child(_lbl(cap, 17, Color(Sketch.INK, 0.7)))
		grid.add_child(cell)
	# десятая глава — отдельный режим-отель, живёт вне сюжета
	if mode == "story":
		var hc := Chapters.get_ch(Chapters.hotel_index())
		var hrow := PanelContainer.new()
		var hst := StyleBoxFlat.new()
		hst.bg_color = Color(1.0, 0.92, 0.82, 0.55)
		hst.set_border_width_all(2)
		hst.border_color = Color(hc["main"], 0.7)
		hst.set_corner_radius_all(8)
		hst.set_content_margin_all(6)
		hrow.add_theme_stylebox_override("panel", hst)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hrow.add_child(hb)
		var hp := _portrait(hc, 56)
		hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not mode_open("idle"):
			hp.modulate = Color(0.6, 0.6, 0.6, 0.5)
		hb.add_child(hp)
		var hpick := _btn("%s\n%s" % [str(hc["num"]), str(hc["title"])], _open_hotel, true)
		hpick.add_theme_font_size_override("font_size", 20)
		hpick.custom_minimum_size = Vector2(0, 64)
		if not mode_open("idle"):
			hpick.disabled = true
			hpick.set_meta("locked", true)
		hb.add_child(hpick)
		var hcap := I18n.t("отдельная idle-глава: гости, номера, процедуры")
		if not mode_open("idle"):
			hcap = I18n.t("нужно открыть глав: %d") % int(mode_def("idle")["unlock"])
		hb.add_child(_lbl(hcap, 17, Color(Sketch.INK, 0.7), false, HORIZONTAL_ALIGNMENT_LEFT))
		box.add_child(hrow)
	box.add_child(grid)
	# ключ главы: следующую главу можно открыть за рекламу
	if unlocked < Chapters.story_count():
		var key_left := Shop.cooldown_left("key", AD_KEY_CD)
		var key := _small_btn(I18n.t("▶ Открыть главу %d за рекламу%s") % [unlocked + 1, "" if key_left <= 0.0 else I18n.t(" (через %d мин)") % (int(key_left) / 60 + 1)], _key_for_ad)
		if key_left > 0.0:
			key.disabled = true
			key.set_meta("locked", true)
		box.add_child(_gap(4))
		box.add_child(key)
	box.add_child(_gap(4))
	box.add_child(_btn_row([_small_btn(I18n.t("Рекорды режима"), _open_scores.bind(mode)), _small_btn(I18n.t("← В меню"), _to_menu)], 400))


func _build_story(box: VBoxContainer, w: float) -> void:
	var ch := Chapters.get_ch(story_idx)
	var main: Color = ch["main"]
	var tsz := 21 if small else 24
	if not prev_clear.is_empty():
		var pc := Chapters.get_ch(int(prev_clear["idx"]))
		box.add_child(_lbl("«" + str(pc["outro"]) + "»", tsz))
		box.add_child(_lbl(I18n.t("Бонус за главу: +%d · Всего очков: %d%s") % [prev_clear["bonus"], prev_clear["score"], " · +1 ♥" if mode == "story" else ""], 19, Color(Sketch.INK, 0.8)))
		if last_card != "":
			var cl := _lbl(Cards.found_text(last_card), 21, GOLD, true)
			box.add_child(cl)
			wobblers.append(cl)
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
		qb.add_child(_lbl(I18n.t("Бесконечная охота: цель не кончается — копи очки, пока есть сердца. Каждые 10 целей +1 ♥, а враги с каждой минутой злее."), tsz, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		qb.add_child(_lbl(I18n.t("Как играть: ") + str(ch["quest"]), 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	else:
		qb.add_child(_lbl(I18n.t("Задание: ") + str(ch["quest"]), tsz, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "hard":
		qb.add_child(_lbl(I18n.t("✧ Одно перо: одно сердце на всю сказку, очки ×2."), 19, RED, false, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "race":
		qb.add_child(_lbl(I18n.t("⏱ Гонка: на главу %d секунд. Успей выполнить задание — каждая сэкономленная секунда даёт 10 очков.") % int(game.chapter_time(story_idx)), tsz, Color("#5cc7c0"), true, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "marathon":
		qb.add_child(_lbl(I18n.t("◷ Марафон: волны врагов без конца, каждые 3 волны — сердце. От выбранной главы зависит, кто именно полетит навстречу."), tsz, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		qb.add_child(_lbl(I18n.t("Волну можно продлить за рекламу — сердце в паузе или продолжение после гибели."), 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "choir":
		qb.add_child(_lbl(I18n.t("♬ Хор фей: две подружки летят с тобой — собирают добычу и закрывают от удара (сами закружатся, но выручат). Соперницы воруют всё, до чего долетят раньше: спугни их рывком, и они бросят находку. Держись рядом с подружками — запоёт хор, очки ×2."), tsz, Color("#5cc7c0"), true, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "guard":
		qb.add_child(_lbl(I18n.t("✤ Звёздная стража: тени идут тропой к сердцу поляны. Ставь башни-цветы на свободные круги, собирай росу с побеждённых теней и улучшай башни. Десять волн — и поляна спасена."), tsz, Color("#8a5aa8"), true, HORIZONTAL_ALIGNMENT_LEFT))
		qb.add_child(_lbl(I18n.t("Василёк бьёт быстро, Шиповник — по площади, Светлячок замедляет тени. Рывок феи тоже бьёт: влетай в тень, чтобы отбросить её назад по тропе."), 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "duel":
		qb.add_child(_lbl(I18n.t("❂ Дуэль: Король Теней возвращается волна за волной. Собери 3 звёздных осколка и бей его рывком — каждый следующий босс крепче."), tsz, Color("#b58cff"), true, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "zen":
		qb.add_child(_lbl(I18n.t("☀ Тихий полёт: врагов и урона нет — гуляй, собирай и слушай ветер. Пять сердец, можно не спешить."), tsz, Color("#c8842a"), true, HORIZONTAL_ALIGNMENT_LEFT))
	if mode == "daily":
		var attempts_left := Shop.daily_attempts_left()
		qb.add_child(_lbl(I18n.t("★ Вызов дня: «%s». Глава дня — %s. Очки и пыльца ×2.") % [Modes.daily_rule(), str(ch["title"])], tsz, Color("#b08810"), true, HORIZONTAL_ALIGNMENT_LEFT))
		qb.add_child(_lbl(I18n.t("Осталось попыток сегодня: %d. Серия: %d дн. Все игроки проходят ровно эту же главу.") % [attempts_left + (1 if Shop.daily_used_ad_attempt() else 0), int(Shop.load_daily()["streak"])], 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	qb.add_child(_lbl("✎ " + str(ch["hint"]), 19, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
	quest.add_child(qb)
	body.add_child(quest)
	var go_text := I18n.t("Лететь! ➜")
	if mode == "marathon":
		go_text = I18n.t("В бой! ➜")
	elif mode == "duel":
		go_text = I18n.t("Начать дуэль ➜")
	elif mode == "zen":
		go_text = I18n.t("Полетели! ➜")
	elif mode == "daily":
		go_text = I18n.t("Принять вызов ➜")
	elif mode == "choir":
		go_text = I18n.t("Запевать! ➜")
	elif mode == "guard":
		go_text = I18n.t("В стражу! ➜")
	elif mode == "race":
		go_text = I18n.t("На старт! ➜")
	var no_attempts := mode == "daily" and Shop.daily_attempts_left() <= 0
	var go_btn := _btn(I18n.t("▶ Ещё попытка за рекламу") if no_attempts else go_text, _daily_extra_attempt.bind(false) if no_attempts else _begin_chapter, true)
	go_btn.add_theme_font_size_override("font_size", 28 if small else 34)
	var foot: Array = [go_btn]
	if is_single():
		foot.push_front(_small_btn(I18n.t("← Главы"), _to_select))
	body.add_child(_gap(4))
	var frow := HBoxContainer.new()
	frow.alignment = BoxContainer.ALIGNMENT_CENTER
	frow.add_theme_constant_override("separation", 12)
	for b in foot:
		frow.add_child(b)
	body.add_child(frow)
	if not OS.has_feature("mobile"):
		body.add_child(_lbl(I18n.t("Enter / Пробел"), 17, Color(Sketch.INK, 0.6)))

	if wide:
		# две колонки: слева фея и название, справа история
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		head.custom_minimum_size = Vector2(w * 0.28, 0)
		head.add_child(p)
		head.add_child(_lbl(sub, 20, Color(Sketch.INK, 0.7)))
		head.add_child(_lbl(ch["title"], 40, main, true))
		head.add_child(_lbl(I18n.t("Героиня: фея ") + str(ch["name"]), 20))
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
		tb.add_child(_lbl(I18n.t("Героиня: фея ") + str(ch["name"]), 22, Sketch.INK, false, HORIZONTAL_ALIGNMENT_LEFT))
		hrow.add_child(tb)
		box.add_child(hrow)
		box.add_child(body)


func _build_paused(box: VBoxContainer) -> void:
	box.add_child(_lbl(I18n.t("Пауза"), 64, Sketch.INK, true))
	box.add_child(_lbl(I18n.t("Фея присела на листок отдохнуть…"), 24, Color(Sketch.INK, 0.7)))
	box.add_child(_lbl(I18n.t("Очки: %d  ·  ♥ %d  ·  %s") % [game.score, game.hearts, Modes.def(mode)["short"]], 20, Color(Sketch.INK, 0.75)))
	box.add_child(_gap(6))
	box.add_child(_btn(I18n.t("Продолжить"), _resume, true))
	# «добрые дела» за рекламу прямо в бою
	if game.hearts < 5 and game.heals_used < 3:
		box.add_child(_btn(I18n.t("♥ Полечиться за рекламу (+1 ♥)"), _heal_for_ad))
	if game.is_race():
		var race_btn := _btn(I18n.t("⏳ +20 секунд за рекламу"), _time_for_ad)
		if game.time_adds >= 3:
			race_btn.disabled = true
			race_btn.set_meta("locked", true)
		box.add_child(race_btn)
	box.add_child(_btn(I18n.t("Заново (R)"), _restart))
	if is_single():
		box.add_child(_btn(I18n.t("К главам"), _to_select))
	box.add_child(_btn(I18n.t("В меню"), _to_menu))
	box.add_child(_gap(4))
	# звук и управление — в настройках, их можно поправить не выходя из забега
	box.add_child(_btn_row([
		_small_btn(_music_label(), _toggle_music),
		_small_btn(I18n.t("⚙ Настройки"), _open_settings),
	], 340))


func _build_over(box: VBoxContainer, w: float) -> void:
	var ch := Chapters.get_ch(story_idx)
	var md := mode_def(mode)
	var title := ""
	var text := ""
	var col := WINE
	if screen == "win":
		title = I18n.t("И жили они долго и счастливо!")
		text = I18n.t("Все девять фей спасены — и всего с одним пером! Легенда.") if mode == "hard" else I18n.t("Все девять фей спасены, а последний осколок тени погас.")
		col = GOLD
	elif screen == "result" and mode == "guard":
		title = I18n.t("Поляна отстояна!")
		text = I18n.t("Все %d волн отбиты, сердце поляны цело: %d из %d. Тени ушли до следующей ночи.") % [Guard.WAVES, int(game.guard_hp), Guard.HEART_HP]
		col = Color("#8a5aa8")
	elif screen == "result":
		title = I18n.t("Глава пройдена!")
		text = "%s · %s. %s" % [ch["num"], ch["title"], ch["outro"]]
		col = ch["main"]
	elif mode == "endless":
		title = I18n.t("Охота окончена!")
		text = I18n.t("%s: %s — %d. Враги оказались сильнее… пока что.") % [ch["kind"], str(ch["goal_label"]).to_lower(), final_progress]
	elif mode == "race" and game.time_failed:
		title = I18n.t("Время вышло!")
		text = I18n.t("%s: %d из %d. Часы быстрее феи — но её можно догнать.") % [ch["goal_label"], final_progress, int(ch["goal"])]
		col = Color("#5cc7c0")
	elif mode == "marathon":
		title = I18n.t("Марафон окончен!")
		text = I18n.t("Продержалась волн: %d. Крылья устали, но рекорд ждёт новой попытки.") % int(game.wave)
	elif mode == "duel":
		title = I18n.t("Дуэль окончена!")
		text = I18n.t("Королей Теней побеждено: %d. Тень вернётся — и снова будет сильнее.") % maxi(0, int(game.boss_wave) - 1)
	elif mode == "daily":
		title = I18n.t("Вызов дня не покорился…")
		text = I18n.t("Сегодня всем досталась глава «%s». Попробуешь ещё раз — соперники уже ждут.") % str(ch["title"])
	elif mode == "guard":
		title = I18n.t("Стража пала…")
		text = I18n.t("Волн отбито: %d, теней развеяно: %d, башен построено: %d. Сердце поляны ещё можно отстоять.") % [maxi(0, int(game.wave) - 1), int(game.guard_kills), int(game.guard_built)]
		col = Color("#8a5aa8")
	elif mode == "choir":
		title = I18n.t("Хор рассыпался…")
		text = I18n.t("Подружки выручили %d раз, соперницы унесли %d находок. Соберитесь снова — и запоёте громче.") % [int(game.choir_saved), int(game.rival_score)]
		col = Color("#5cc7c0")
	elif mode == "chapter" or mode == "zen":
		title = I18n.t("Глава не удалась…")
		text = I18n.t("%s · %s. Попробуй ещё раз!") % [ch["num"], ch["title"]]
	else:
		title = I18n.t("Сказка оборвалась…")
		text = I18n.t("Пройдено глав: %d из %d. Но любую сказку можно рассказать заново.") % [final_chapter, Chapters.story_count()]

	var a := VBoxContainer.new()
	var b := VBoxContainer.new()
	a.add_theme_constant_override("separation", 4)
	b.add_theme_constant_override("separation", 8)
	a.add_child(_lbl("%s %s" % [md["icon"], md["title"]], 21, Color(Sketch.INK, 0.7)))
	a.add_child(_lbl(title, 40 if small else 50, col, true))
	a.add_child(_lbl(text, 20 if small else 23))
	a.add_child(_lbl(I18n.t("%d очков") % final_score, 40 if small else 48, Sketch.INK, true))
	if rank == 0:
		var rec := _lbl(I18n.t("✦ Новый рекорд! ✦"), 32, PINK, true)
		a.add_child(rec)
		wobblers.append(rec)
	elif rank > 0:
		a.add_child(_lbl(I18n.t("Место в таблице: %d") % (rank + 1), 24))
	a.add_child(_lbl(I18n.t("+%d ✦ пыльцы%s · всего %d") % [last_pollen * (2 if doubled else 1), " (×2)" if doubled else "", pollen], 22, POLLEN_COL))
	if last_card != "" and screen != "over":
		a.add_child(_lbl(Cards.found_text(last_card), 22, GOLD, true))
	b.add_child(_score_table(rank, 5 if small else 7))
	if screen == "over" and continues < max_continues():
		if mode == "race" and game.time_failed:
			b.add_child(_btn(I18n.t("▶ +20 секунд за рекламу"), _continue_for_ad, true))
		elif mode == "daily" and Shop.daily_attempts_left() <= 0 and not Shop.daily_used_ad_attempt():
			b.add_child(_btn(I18n.t("▶ Ещё попытка за рекламу"), _daily_extra_attempt.bind(false), true))
		else:
			b.add_child(_btn(I18n.t("▶ %s за рекламу") % (I18n.t("Продолжить охоту") if (mode == "endless" or mode == "marathon" or mode == "duel") else (I18n.t("Продолжить оборону") if mode == "guard" else I18n.t("Продолжить главу"))), _continue_for_ad, true))
	if screen == "over" and not blessing and Shop.cooldown_left("bless", AD_BLESS_CD) <= 0.0:
		b.add_child(_small_btn(I18n.t("❀ Благословение фей на новый забег за рекламу"), _bless_for_ad))
	if screen == "result" and story_idx < Chapters.story_count() - 1:
		b.add_child(_btn(I18n.t("Следующая глава ➜"), _next_chapter, true))
	var btns: Array = [_small_btn(I18n.t("Ещё раз (R)"), _restart)]
	btns.append(_small_btn(I18n.t("✦ Награды"), _open_rewards))
	if is_single():
		btns.append(_small_btn(I18n.t("Главы"), _to_select))
	btns.append(_small_btn(I18n.t("Лавка"), _open_shop))
	btns.append(_small_btn(I18n.t("В меню"), _to_menu_after_run))
	if not doubled and last_pollen > 0:
		b.add_child(_small_btn(I18n.t("▶ Удвоить пыльцу за рекламу (+%d ✦)") % last_pollen, _double_pollen))
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
	box.add_child(_lbl(I18n.t("Рекорды"), 64, Sketch.INK, true))
	box.add_child(_lbl(I18n.t("Летопись самых храбрых фей"), 22, Color(Sketch.INK, 0.7)))
	var tabs := HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for d in Modes.list():
		var t := _small_btn("%s %s" % [d["icon"], d["title"]], _open_scores.bind(d["id"]))
		t.add_theme_font_size_override("font_size", 19)
		if d["id"] == scores_tab:
			t.theme_type_variation = "PrimaryButton"
		tabs.add_child(t)
	box.add_child(tabs)
	box.add_child(_score_table(-1, 10))
	box.add_child(_gap(6))
	var back := _btn(I18n.t("Назад"), func() -> void:
		Sfx.play("click")
		_go("menu"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)


## в одноглавевых режимах в таблице показываем номер главы, а не «3/9»
func is_single_tab(tab: String) -> bool:
	return Modes.pick(tab) or tab == "daily" or tab == "duel" or tab == "guard"


func _score_table(highlight: int, max_rows: int = 10) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	if scores.is_empty():
		v.add_child(_lbl(I18n.t("Пока пусто — стань первой легендой!"), 24, Color(Sketch.INK, 0.7)))
		return v
	var tab := scores_tab
	var md := mode_def(tab)
	var single := is_single_tab(tab)
	v.add_child(_score_row("#", "Имя", md["col"], "Очки", false, true))
	# показываем верх таблицы, но выделенная (новая) запись всегда видна
	var rows := range(mini(scores.size(), max_rows))
	if highlight >= max_rows:
		rows[rows.size() - 1] = highlight
	for i in rows:
		var s: Dictionary = scores[i]
		var chn := int(s.get("chapter", 0))
		var colv: String = str(ROMAN[clampi(chn, 0, ROMAN.size() - 1)]) if single else "%d/%d" % [chn, Chapters.story_count()]
		if tab == "marathon" or tab == "duel" or tab == "guard":
			colv = I18n.t("в. %d") % int(s.get("wave", 0))
		elif tab == "idle":
			colv = I18n.t("г. %d") % int(s.get("wave", 0))
		v.add_child(_score_row("♛" if i == 0 else str(i + 1), str(s.get("name", I18n.t("Фея"))), colv, str(int(s.get("score", 0))), i == highlight, false))
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
	for d in Shop.upgrades():
		if d["id"] == id:
			def = d
	var lvl := int(upgrades[id])
	var price := Shop.price_of(def, lvl)
	if price < 0:
		return
	if via_ad:
		var ok: bool = await _rewarded("upgrade")
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
	var ok: bool = await _rewarded("pollen2")
	if not ok:
		return
	_add_pollen(last_pollen)
	doubled = true
	Sfx.play("bloom")
	_build_overlay()


## благословение фей: щит и +15% очков на следующий забег
func _set_blessing(on: bool) -> void:
	blessing = on
	_save_setting("ads", "blessed", on)
	if on:
		game.blessing = 0.15
	else:
		game.blessing = 0.0


func _bless_for_ad() -> void:
	if ad_busy or blessing:
		return
	if Shop.cooldown_left("bless", AD_BLESS_CD) > 0.0:
		Sfx.play("nocharge")
		return
	var ok: bool = await _rewarded("bless")
	if not ok:
		return
	Shop.touch_cooldown("bless")
	_set_blessing(true)
	Sfx.play("bloom")
	_build_overlay()


## сундук фей: случайная пыльца за рекламу
func _chest_for_ad() -> void:
	if ad_busy:
		return
	if Shop.cooldown_left("chest", AD_CHEST_CD) > 0.0:
		Sfx.play("nocharge")
		return
	var ok: bool = await _rewarded("chest")
	if not ok:
		return
	Shop.touch_cooldown("chest")
	var loot := 40 + randi() % 91
	_add_pollen(loot)
	chest_flash = "+%d ✦" % loot
	Sfx.play("bloom")
	_build_overlay()


## ключ главы: открыть следующую главу за рекламу
func _key_for_ad() -> void:
	if ad_busy or unlocked >= Chapters.story_count():
		return
	if Shop.cooldown_left("key", AD_KEY_CD) > 0.0:
		Sfx.play("nocharge")
		return
	var ok: bool = await _rewarded("key")
	if not ok:
		return
	Shop.touch_cooldown("key")
	_unlock(unlocked + 1)
	Sfx.play("bloom")
	_build_overlay()


## сад фей: собрать пыльцу (и удвоить её за рекламу)
func _claim_garden(via_ad: bool = false) -> void:
	var lvl := int(upgrades["garden"])
	var pending := Shop.garden_now(lvl, garden)
	if pending <= 0:
		return
	if via_ad:
		var ok: bool = await _rewarded("garden")
		if not ok:
			return
		pending *= 2
	Shop.save_garden(Time.get_unix_time_from_system(), 0)
	garden = Shop.load_garden()
	_add_pollen(pending)
	Sfx.play("bloom")
	_build_overlay()


## покупка наряда за пыльцу или за рекламу
func _buy_skin(id: String, via_ad: bool) -> void:
	if ad_busy or bool(skins.get(id, false)):
		return
	var price := Skins.price(id)
	if via_ad:
		var ok: bool = await _rewarded("skin")
		if not ok:
			return
	else:
		if pollen < price:
			return
		_add_pollen(-price)
	skins[id] = true
	Shop.save_skins(skins)
	skin = id
	game.skin = skin
	Shop.save_skin(id)
	Sfx.play("bloom")
	_build_overlay()


func _wear_skin(id: String) -> void:
	if ad_busy or not bool(skins.get(id, false)):
		return
	skin = id
	game.skin = skin
	Shop.save_skin(id)
	Sfx.play("click")
	_build_overlay()


func _set_shop_tab(t: String) -> void:
	shop_tab = t
	Sfx.play("click")
	_build_overlay()


func _build_shop(box: VBoxContainer) -> void:
	box.add_child(_lbl(I18n.t("Лавка фей"), 60, POLLEN_COL, true))
	box.add_child(_lbl(I18n.t("Пыльца даётся за очки в конце каждого забега. Всё купленное работает во всех режимах."), 20, Color(Sketch.INK, 0.75)))
	box.add_child(_lbl(I18n.t("✦ %d пыльцы") % pollen, 40, POLLEN_COL, true))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	var pending := Shop.garden_now(int(upgrades["garden"]), garden)
	for td in [["up", I18n.t("❖ Улучшения")], ["look", I18n.t("❀ Наряды")], ["garden", I18n.t("☀ Сад фей") + ("" if pending <= 0 else " (%d)" % pending)]]:
		var b := _small_btn(str(td[1]), _set_shop_tab.bind(str(td[0])))
		if shop_tab == str(td[0]):
			b.theme_type_variation = "PrimaryButton"
		tabs.add_child(b)
	box.add_child(tabs)
	match shop_tab:
		"look":
			_shop_looks(box)
		"garden":
			_shop_garden(box)
		_:
			_shop_upgrades(box)
	shop_flash = ""
	box.add_child(_gap(4))
	box.add_child(_btn_row([_small_btn(I18n.t("✦ Награды за рекламу"), _open_rewards), _small_btn(I18n.t("← Назад"), _close_shop)], 460))


## вкладка «Улучшения»: двенадцать полезностей за пыльцу или за рекламу
func _shop_upgrades(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4 if wide else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for d in Shop.upgrades():
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
			v.add_child(_lbl(I18n.t("✓ Максимум"), 22, Color("#5c9e3a"), true, HORIZONTAL_ALIGNMENT_LEFT))
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var b1 := _small_btn("✦ %d" % price, _buy.bind(id, false))
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if pollen < price:
				b1.disabled = true
				b1.set_meta("locked", true)
			var b2 := _btn(I18n.t("▶ Реклама"), _buy.bind(id, true), true)
			b2.add_theme_font_size_override("font_size", 20)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b1)
			row.add_child(b2)
			v.add_child(row)
		grid.add_child(cell)
	box.add_child(grid)


## вкладка «Наряды»: косметика для феи
func _shop_looks(box: VBoxContainer) -> void:
	box.add_child(_lbl(I18n.t("Наряды меняют только внешний вид — механика остаётся прежней."), 19, Color(Sketch.INK, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 3 if wide else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for d in Skins.list():
		var id: String = d["id"]
		var owned := bool(skins.get(id, false))
		var price := int(d["price"])
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.969, 0.816, 0.376, 0.6) if skin == id else Color(1, 1, 1, 0.55)
		st.set_border_width_all(2)
		st.border_color = Color(Sketch.INK, 0.5)
		st.set_corner_radius_all(10)
		st.set_content_margin_all(8)
		cell.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		var p := _portrait(Skins.preview(id, Chapters.get_ch(0), 0.0), 58)
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(p)
		v.add_child(_lbl("%s %s" % [d["icon"], d["title"]], 22, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		v.add_child(_lbl(str(d["desc"]), 17, Color(Sketch.INK, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT))
		if owned:
			if skin == id:
				v.add_child(_lbl(I18n.t("✓ Надето"), 20, Color("#5c9e3a"), true, HORIZONTAL_ALIGNMENT_LEFT))
			else:
				v.add_child(_small_btn(I18n.t("Надеть"), _wear_skin.bind(id)))
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var b1 := _small_btn("✦ %d" % price, _buy_skin.bind(id, false))
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if pollen < price:
				b1.disabled = true
				b1.set_meta("locked", true)
			var b2 := _btn(I18n.t("▶ Реклама"), _buy_skin.bind(id, true), true)
			b2.add_theme_font_size_override("font_size", 20)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b1)
			row.add_child(b2)
			v.add_child(row)
		grid.add_child(cell)
	box.add_child(grid)


## вкладка «Сад фей»: пассивная пыльца за ожидание
func _shop_garden(box: VBoxContainer) -> void:
	var lvl := int(upgrades["garden"])
	if lvl <= 0:
		box.add_child(_lbl(I18n.t("Сад фей ещё не посажен. Купи его на вкладке «Улучшения» — и он начнёт копить пыльцу, пока ты не играешь."), 22, Sketch.INK, false, HORIZONTAL_ALIGNMENT_LEFT))
		return
	var pending := Shop.garden_now(lvl, garden)
	box.add_child(_lbl(I18n.t("Уровень сада: %d · %d ✦ в час · копилка до %d ✦") % [lvl, Shop.GARDEN_RATE[lvl - 1], Shop.garden_cap(lvl)], 22, Sketch.INK))
	box.add_child(_lbl(I18n.t("В саду сейчас: %d ✦") % pending, 40, POLLEN_COL, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var b1 := _btn(I18n.t("Собрать"), _claim_garden.bind(false), true)
	b1.add_theme_font_size_override("font_size", 24)
	if pending <= 0:
		b1.disabled = true
		b1.set_meta("locked", true)
	var b2 := _btn(I18n.t("▶ Собрать ×2"), _claim_garden.bind(true), true)
	b2.add_theme_font_size_override("font_size", 24)
	if pending <= 0:
		b2.disabled = true
		b2.set_meta("locked", true)
	row.add_child(b1)
	row.add_child(b2)
	box.add_child(row)
	box.add_child(_lbl(I18n.t("Сад копит даже в выключенной игре — заглядывай почаще!"), 19, Color(Sketch.INK, 0.7)))


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

	# ползунки громкости
	th.set_stylebox("slider", "HSlider", _bar_box(Color(Sketch.INK, 0.16)))
	th.set_stylebox("grabber_area", "HSlider", _bar_box(Color(0.91, 0.416, 0.573, 0.7)))
	th.set_stylebox("grabber_area_highlight", "HSlider", _bar_box(Color(0.91, 0.416, 0.573, 0.9)))
	th.set_icon("grabber", "HSlider", _knob(Color("#fffaf0")))
	th.set_icon("grabber_highlight", "HSlider", _knob(Color("#fff3f6")))
	th.set_icon("grabber_disabled", "HSlider", _knob(Color(Sketch.INK, 0.25)))
	th.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	return th


## дорожка ползунка: тонкая карандашная линия со скруглением
func _bar_box(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(5)
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	s.content_margin_left = 4
	s.content_margin_right = 4
	return s


## круглая ручка ползунка — рисуем сами, картинок в проекте нет
func _knob(fill: Color) -> ImageTexture:
	var px := 24
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	var r := c - 1.5
	for y in px:
		for x in px:
			var d := Vector2(float(x) - c, float(y) - c).length()
			if d <= r - 2.0:
				img.set_pixel(x, y, fill)
			elif d <= r:
				img.set_pixel(x, y, Color(Sketch.INK.r, Sketch.INK.g, Sketch.INK.b, 0.85))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# ================================================================= отель фей (idle)

## вход в «Отель фей»: подхватываем состояние и доначисляем офлайн-время
func _open_hotel() -> void:
	if ad_busy:
		return
	mode = "idle"
	hotel_state = Hotel.load_state()
	var res := Hotel.settle(hotel_state)
	hotel_welcome = Hotel.settle_hint(res)
	hotel_flash = ""
	hotel_tab = "rooms"
	hotel_sel = ""
	hotel_sel_i = -1
	hotel_theme_for = -1
	hotel_proc_for = -1
	hotel_clock = 0.0
	Hotel.save_state(hotel_state)
	hotel_open = true
	game.preview(Chapters.hotel_index())
	Sfx.play("click")
	_go("hotel")


## выход из отеля: сохраняемся и (раз в несколько раз) показываем рекламу
func _leave_hotel() -> void:
	if not hotel_state.is_empty():
		Hotel.save_state(hotel_state)
	_interstitial("hotel", _to_menu)


func _hotel_set_tab(t: String) -> void:
	hotel_tab = t
	hotel_theme_for = -1
	hotel_proc_for = -1
	Sfx.play("click")
	_build_overlay()


## один такт отеля: гости, проживание, процедуры, автосохранение
func _hotel_tick(dt: float) -> void:
	if hotel_state.is_empty():
		return
	Hotel.tick(hotel_state, dt)
	hotel_clock += dt
	if hotel_clock >= 10.0:
		hotel_clock = 0.0
		Hotel.save_state(hotel_state)
	var sig := _hotel_signature()
	if sig != hotel_sig:
		hotel_sig = sig
		_build_overlay()
		return
	for u in hotel_live:
		u.call()


## подпись состояния: изменилась — значит экран надо перестроить.
## Счётчики (served, earned, cash) сюда не входят: они меняются почти каждый
## кадр и обновляются «живыми» подписями, а перестройка окна заставляет
## сцену отеля мерцать. Здесь только то, что меняет состав экрана.
func _hotel_signature() -> String:
	var beds := Hotel.beds(hotel_state)
	var parts := []
	var rooms: Array = hotel_state["rooms"]
	for r in rooms:
		parts.append(str((r["guests"] as Array).size()))
	return "%d|%d|%d|%s" % [int((hotel_state["queue"] as Array).size()), int(beds[0]), int(beds[1]),
		",".join(parts)]


## подпись, которую обновляем каждый кадр без перестройки всего окна
func _hotel_live_label(lbl: Label, fn: Callable) -> Label:
	hotel_live.append(func() -> void:
		if is_instance_valid(lbl):
			lbl.text = str(fn.call()))
	return lbl


## покупка за пыльцу: false — не хватило
func _hotel_spend(cost: int) -> bool:
	if cost <= 0:
		return true
	if pollen < cost:
		Sfx.play("nocharge")
		hotel_flash = I18n.t("Не хватает пыльцы: нужно %d ✦") % cost
		_build_overlay()
		return false
	_add_pollen(-cost)
	return true


## что делать с кликом по сцене: выбор фей и адресные действия
func _hotel_view_act(kind: String, a: Variant, b: Variant) -> void:
	if ad_busy or hotel_state.is_empty():
		return
	match kind:
		"queue":
			hotel_sel = "q:%d" % int(a)
			hotel_sel_i = int(a)
			hotel_flash = ""
			Sfx.play("click")
			_build_overlay()
		"resident":
			hotel_sel = "r:%d:%d" % [int(a), int(b)]
			hotel_sel_i = -1
			hotel_flash = ""
			Sfx.play("click")
			_build_overlay()
		"bed":
			var rooms: Array = hotel_state["rooms"]
			var room_i := int(a)
			if room_i >= rooms.size():
				return
			if hotel_sel.begins_with("q:"):
				hotel_sel_i = int(hotel_sel.substr(2))
				_hotel_check_in(room_i)
			else:
				hotel_flash = I18n.t("Сначала выбери гостью на ресепшене — она подскажет, какой номер ей подходит.")
				Sfx.play("nocharge")
				_build_overlay()
		"station":
			if hotel_sel.begins_with("r:"):
				var parts := hotel_sel.split(":")
				_hotel_send_proc(int(parts[1]), int(parts[2]), str(a))
			else:
				hotel_flash = I18n.t("Сначала выбери гостью в номере — и отправь её на процедуру.")
				Sfx.play("nocharge")
				_build_overlay()
		_:
			hotel_sel = ""
			hotel_sel_i = -1
			hotel_flash = ""
			_build_overlay()


## подсказка под сценой: что делать дальше
func _hotel_tip() -> String:
	if hotel_sel.begins_with("q:"):
		var i := int(hotel_sel.substr(2))
		var queue: Array = hotel_state["queue"]
		if i < queue.size():
			var k := Hotel.kind_of(str((queue[i] as Dictionary)["kind"]))
			return I18n.t("Выбрана %s: кликни по свободной кровати в номере под её вкус (%s).") % [str(k["title"]), Hotel.theme_title(str(k["theme"]))]
	if hotel_sel.begins_with("r:"):
		var parts := hotel_sel.split(":")
		var rooms: Array = hotel_state["rooms"]
		var ri := int(parts[1])
		if ri < rooms.size():
			var guests: Array = (rooms[ri] as Dictionary)["guests"]
			var si := int(parts[2])
			if si < guests.size():
				var k2 := Hotel.kind_of(str((guests[si] as Dictionary)["kind"]))
				return I18n.t("Выбрана %s: кликни по станции процедур (любимая — %s).") % [str(k2["title"]), Hotel.proc_title(str(k2["proc"]))]
	return I18n.t("Кликни по фее: на ресепшене — чтобы заселить, в номере — чтобы отправить на процедуру.")


func _hotel_done(msg: String) -> void:
	hotel_flash = msg
	hotel_sel = ""
	hotel_sel_i = -1
	hotel_welcome = ""
	Hotel.save_state(hotel_state)
	Sfx.play("bloom")
	_build_overlay()


# ------------------------------------------------------------------ действия

## «подобрать номер»: выбираем гостя и переходим к номерам
func _hotel_select(i: int) -> void:
	hotel_sel_i = i
	hotel_sel = "q:%d" % i
	hotel_tab = "rooms"
	hotel_theme_for = -1
	hotel_proc_for = -1
	Sfx.play("click")
	_build_overlay()


## кого подселяем в номер: выбранного гостя, иначе первого, кому номер подходит
func _hotel_guest_for_room(room: Dictionary) -> int:
	var queue: Array = hotel_state["queue"]
	if queue.is_empty():
		return -1
	if hotel_sel_i >= 0 and hotel_sel_i < queue.size():
		return hotel_sel_i
	var best := -1
	for i in queue.size():
		if Hotel.fits(str(queue[i]["kind"]), str(room["theme"])):
			best = i
			break
	return best


func _hotel_check_in(room_i: int) -> void:
	if ad_busy or hotel_state.is_empty():
		return
	var rooms: Array = hotel_state["rooms"]
	var room: Dictionary = rooms[room_i]
	var qi := _hotel_guest_for_room(room)
	if qi < 0 or Hotel.free_beds(room) <= 0:
		Sfx.play("nocharge")
		return
	if not Hotel.check_in(hotel_state, qi, room_i):
		Sfx.play("nocharge")
		return
	hotel_sel_i = -1
	_hotel_done(I18n.t("Гостья заселена в номер %d!") % (room_i + 1))


func _hotel_send_proc(room_i: int, slot: int, proc_id: String) -> void:
	if ad_busy:
		return
	if not Hotel.send_proc(hotel_state, room_i, slot, proc_id):
		Sfx.play("nocharge")
		return
	hotel_proc_for = -1
	_hotel_done(I18n.t("Гостья отправилась: %s") % Hotel.proc_title(proc_id))


func _hotel_open_theme(room_i: int) -> void:
	hotel_theme_for = room_i if hotel_theme_for != room_i else -1
	hotel_proc_for = -1
	Sfx.play("click")
	_build_overlay()


func _hotel_open_procs(room_i: int, slot: int) -> void:
	hotel_proc_for = room_i if hotel_proc_for != room_i else -1
	hotel_proc_slot = slot
	hotel_theme_for = -1
	Sfx.play("click")
	_build_overlay()


## купить (если нужно) и надеть вид окружения на свободный номер
func _hotel_apply_theme(room_i: int, theme_id: String) -> void:
	var rooms: Array = hotel_state["rooms"]
	if room_i < 0 or room_i >= rooms.size() or Hotel.free_beds(rooms[room_i]) < int(rooms[room_i]["slots"]):
		Sfx.play("nocharge")
		hotel_flash = I18n.t("В номере живут гости — сменить окружение можно после выезда.")
		_build_overlay()
		return
	if not Hotel.theme_owned(hotel_state, theme_id):
		if not _hotel_spend(Hotel.theme_price(hotel_state, theme_id)):
			return
		Hotel.buy_theme(hotel_state, theme_id)
	if not Hotel.set_theme(hotel_state, room_i, theme_id):
		Sfx.play("nocharge")
		return
	hotel_theme_for = -1
	_hotel_done(I18n.t("Номер %d теперь: %s") % [room_i + 1, Hotel.theme_title(theme_id)])


func _hotel_upgrade_room(room_i: int) -> void:
	var rooms: Array = hotel_state["rooms"]
	var lvl := int(rooms[room_i]["lvl"])
	var cost := Hotel.upgrade_price(room_i, lvl)
	if cost < 0 or not _hotel_spend(cost):
		return
	Hotel.upgrade_room(hotel_state, room_i)
	_hotel_done(I18n.t("Уют номера %d вырос до %d.") % [room_i + 1, lvl + 1])


func _hotel_expand_room(room_i: int) -> void:
	if not _hotel_spend(Hotel.expand_price(room_i)):
		return
	if not Hotel.expand_room(hotel_state, room_i):
		return
	_hotel_done(I18n.t("В номере %d появилось второе место.") % (room_i + 1))


func _hotel_new_room() -> void:
	var cost := Hotel.open_room_price(hotel_state)
	if cost < 0:
		return
	if not _hotel_spend(cost):
		return
	if not Hotel.open_room(hotel_state):
		return
	_hotel_done(I18n.t("Открыт новый номер! Всего номеров: %d.") % (hotel_state["rooms"] as Array).size())


func _hotel_buy_proc(proc_id: String) -> void:
	if not _hotel_spend(Hotel.proc_price(hotel_state, proc_id)):
		return
	if not Hotel.buy_proc(hotel_state, proc_id):
		return
	_hotel_done(I18n.t("Новая процедура: %s") % Hotel.proc_title(proc_id))


func _hotel_buy_up(id: String) -> void:
	var cost := Hotel.up_price(hotel_state, id)
	if cost < 0 or not _hotel_spend(cost):
		return
	if not Hotel.upgrade_hotel(hotel_state, id):
		return
	_hotel_done(I18n.t("Улучшение отеля: %s (ур. %d)") % [str(Hotel.upgrade_of(id)["title"]), Hotel.up_level(hotel_state, id)])


## собрать кассу в пыльцу (за рекламу — вдвое)
func _hotel_collect(via_ad: bool) -> void:
	if ad_busy or hotel_state.is_empty():
		return
	if int(hotel_state["cash"]) <= 0:
		Sfx.play("nocharge")
		hotel_flash = I18n.t("Касса пуста — гости ещё копят пыльцу.")
		_build_overlay()
		return
	if via_ad:
		if Shop.cooldown_left("hotel_cash", AD_HOTEL_CD) > 0.0:
			Sfx.play("nocharge")
			hotel_flash = I18n.t("Удвоение кассы будет доступно через %d мин.") % (int(Shop.cooldown_left("hotel_cash", AD_HOTEL_CD)) / 60 + 1)
			_build_overlay()
			return
		var ok: bool = await _rewarded("hotel_cash")
		if not ok:
			return
		Shop.touch_cooldown("hotel_cash")
	var got := Hotel.collect(hotel_state)
	if via_ad:
		got *= 2
		# реклама ещё и включает ×2 к плате за номер на две минуты
		Hotel.set_boost(hotel_state, 120.0)
	_add_pollen(got)
	_hotel_done(I18n.t("Касса собрана: +%d ✦") % got)


## пригласить редкую гостью за рекламу
func _hotel_star_guest() -> void:
	if ad_busy:
		return
	if Shop.cooldown_left("hotel_star", AD_STAR_CD) > 0.0 or (hotel_state["queue"] as Array).size() >= Hotel.guest_cap(hotel_state):
		Sfx.play("nocharge")
		hotel_flash = I18n.t("Позвать звезду можно, когда есть место на ресепшене и прошла перезарядка.")
		_build_overlay()
		return
	var ok: bool = await _rewarded("hotel_star")
	if not ok:
		return
	Shop.touch_cooldown("hotel_star")
	Hotel.add_guest(hotel_state, true)
	_hotel_done(I18n.t("Звёздная гостья уже на ресепшене!"))


## мгновенно завершить все процедуры за рекламу
func _hotel_fast_procs() -> void:
	if ad_busy:
		return
	if Shop.cooldown_left("hotel_procs", AD_PROCS_CD) > 0.0:
		Sfx.play("nocharge")
		hotel_flash = I18n.t("Ускорение процедур будет доступно через %d мин.") % (int(Shop.cooldown_left("hotel_procs", AD_PROCS_CD)) / 60 + 1)
		_build_overlay()
		return
	var ok: bool = await _rewarded("hotel_procs")
	if not ok:
		return
	Shop.touch_cooldown("hotel_procs")
	var n := Hotel.finish_procs(hotel_state)
	if n <= 0:
		Sfx.play("nocharge")
		hotel_flash = I18n.t("Сейчас никого не надо ускорять — гости просто отдыхают.")
		_build_overlay()
		return
	_hotel_done(I18n.t("Процедуры завершены сразу: %d") % n)


## записать итоги смены в таблицу рекордов режима
func _hotel_report() -> void:
	var earned := int(hotel_state["earned"])
	var reported := int(hotel_state.get("reported", 0))
	if earned <= reported:
		Sfx.play("nocharge")
		hotel_flash = I18n.t("Новых гостей пока нет — смена ещё впереди.")
		_build_overlay()
		return
	hotel_state["reported"] = earned
	var entry := {
		"name": player_name if player_name != "" else I18n.t("Фея"),
		"score": earned,
		"chapter": 0,
		"wave": int(hotel_state["served"]),
		"date": int(Time.get_unix_time_from_system() * 1000.0) * 10 + randi() % 10,
	}
	var res := Scores.save(entry, "idle")
	scores = res[0]
	scores_tab = "idle"
	rank = res[1]
	hotel_flash = I18n.t("Итоги смены записаны: %d ✦ · гостей %d") % [earned, int(hotel_state["served"])]
	Hotel.save_state(hotel_state)
	Sfx.play("bloom")
	_build_overlay()


# ------------------------------------------------------------------ сам экран

func _build_hotel(box: VBoxContainer, w: float) -> void:
	hotel_live.clear()
	var st: Dictionary = hotel_state
	if st.is_empty():
		hotel_state = Hotel.load_state()
		st = hotel_state
	var beds := Hotel.beds(st)
	box.add_child(_lbl("♨ " + I18n.t("Отель фей"), 44 if small else 50, Color("#c98a4b"), true))
	# рейтинг, касса и сбор — одной строкой, чтобы сцена занимала больше места.
	# Подпись «живая»: счётчики меняются сами по себе и не требуют перестройки окна.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var stat := _hotel_live_label(_lbl("", 21, Color("#b08810"), true, HORIZONTAL_ALIGNMENT_LEFT, false), func() -> String:
		return I18n.t("★ %.1f · гостей %d · касса %d ✦") % [Hotel.stars(hotel_state), int(hotel_state["served"]), int(hotel_state["cash"])])
	stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(stat)
	head.add_child(_small_btn(I18n.t("Собрать"), _hotel_collect.bind(false)))
	head.add_child(_small_btn(I18n.t("▶ ×2"), _hotel_collect.bind(true)))
	box.add_child(head)
	var cash_lbl := _hotel_live_label(_lbl("", 18, Color(Sketch.INK, 0.75), false, HORIZONTAL_ALIGNMENT_LEFT), func() -> String:
		var txt := I18n.t("Мест %d/%d · вытяжка %d ✦/мин · сезон дня: %s (×1.6)") % [int(Hotel.beds(hotel_state)[0]), int(Hotel.beds(hotel_state)[1]),
			Hotel.flow_per_min(hotel_state), Hotel.theme_title(Hotel.season_theme())]
		if Hotel.boost_left(hotel_state) > 0.0:
			txt += I18n.t(" · ×2 ещё %s") % Hotel.fmt_time(Hotel.boost_left(hotel_state))
		return txt)
	box.add_child(cash_lbl)
	if hotel_flash != "":
		box.add_child(_lbl("✦ " + hotel_flash, 20, PINK, true))
	elif hotel_welcome != "":
		box.add_child(_lbl(hotel_welcome, 20, POLLEN_COL, true))
	# сцена отеля: феи, номера и станции — выбираем курсором.
	# Узел не пересоздаётся: портреты фей и их tween-ы остаются живыми,
	# поэтому перестройка списка рядом не заставляет сцену «моргать».
	if hotel_view == null or not is_instance_valid(hotel_view):
		hotel_view = HotelView.new()
		hotel_view.act.connect(_hotel_view_act)
	var view := hotel_view
	view.custom_minimum_size = Vector2(0, clampf(w * 0.34, 250.0, 330.0))
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.state = hotel_state
	view.sel = hotel_sel
	box.add_child(view)
	box.add_child(_lbl(_hotel_tip(), 19, Color(Sketch.INK, 0.85), hotel_sel != ""))
	# вкладки
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	var labels := {
		"guests": I18n.t("Гости") + " (%d)" % (st["queue"] as Array).size(),
		"rooms": I18n.t("Номера") + " %d/%d" % [int(beds[0]), int(beds[1])],
		"spa": I18n.t("Спа"),
		"up": I18n.t("Отель"),
	}
	for td in [["guests", "☎"], ["rooms", "☾"], ["spa", "✿"], ["up", "✦"]]:
		var b := _small_btn("%s %s" % [str(td[1]), str(labels[str(td[0])])], _hotel_set_tab.bind(str(td[0])))
		if hotel_tab == str(td[0]):
			b.theme_type_variation = "PrimaryButton"
		tabs.add_child(b)
	box.add_child(tabs)
	match hotel_tab:
		"rooms":
			_hotel_rooms(box, w)
		"spa":
			_hotel_spa(box, w)
		"up":
			_hotel_ups(box, w)
		_:
			_hotel_guests(box, w)
	box.add_child(_gap(4))
	box.add_child(_btn_row([
		_small_btn(I18n.t("✦ Награды за рекламу"), _open_rewards),
		_small_btn(I18n.t("◷ Итоги смены"), _hotel_report),
		_small_btn(I18n.t("✿ Лавка"), _open_shop),
		_small_btn(I18n.t("← В меню"), _leave_hotel),
	], 560))
	# окно построено — подпись должна ему соответствовать, иначе следующий
	# такт перестроит отель ещё раз
	hotel_sig = _hotel_signature()


## какие гости могут прилететь при текущем рейтинге
func _hotel_open_kinds() -> String:
	var out := []
	for d in Hotel.kinds():
		if int(d["tier"]) <= Hotel.tier_max(hotel_state):
			out.append("%s %s" % [str(d["icon"]), str(d["title"])])
	return ", ".join(out)


## компактный заголовок карточки списка: название и цена/состояние
func _hotel_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _hotel_card_btn(text: String, tip: String, cb: Callable, locked: bool = false, done: bool = false) -> Button:
	var b := _btn(text, cb, not locked and not done)
	b.add_theme_font_size_override("font_size", 17)
	if tip != "":
		b.tooltip_text = tip
	if done:
		b.text = "✓ " + b.text
		b.disabled = true
		b.set_meta("locked", true)
	elif locked:
		b.disabled = true
		b.set_meta("locked", true)
	return b


## вкладка «Гости»: очередь на ресепшене одной строкой на гостью
func _hotel_guests(box: VBoxContainer, _w: float) -> void:
	var queue: Array = hotel_state["queue"]
	box.add_child(_lbl(I18n.t("Кто прилетел · прилетают: %s") % _hotel_open_kinds(), 17, Color(Sketch.INK, 0.68)))
	if queue.is_empty():
		box.add_child(_lbl(I18n.t("На ресепшене пусто. Следующая гостья прилетит через %d с.") % int(maxf(1.0, float(hotel_state["next_guest"]))), 20, Color(Sketch.INK, 0.8)))
	for i in queue.size():
		var guest: Dictionary = queue[i]
		var k := Hotel.kind_of(str(guest["kind"]))
		var row := HFlowContainer.new()
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 4)
		var idx := i
		var line := _hotel_live_label(_lbl("", 19, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT, false), func() -> String:
			var q: Dictionary = (hotel_state["queue"] as Array)[idx]
			return "%s %s · %s · %s · %s" % [str(k["icon"]), str(k["title"]),
				I18n.t("ждёт %s") % Hotel.fmt_time(float(q["patience"])),
				I18n.t(str(k["whim"])), I18n.t(" · ★") if bool(q.get("vip", false)) else ""])
		line.tooltip_text = I18n.t("ждёт номер: %s · процедура: %s") % [Hotel.theme_title(str(k["theme"])), Hotel.proc_title(str(k["proc"]))]
		row.add_child(line)
		row.add_child(_small_btn(I18n.t("Подобрать номер ➜"), _hotel_select.bind(idx)))
		box.add_child(row)
	box.add_child(_gap(2))
	var star_left := Shop.cooldown_left("hotel_star", AD_STAR_CD)
	box.add_child(_btn_row([
		_btn(I18n.t("▶ Позвать редкую гостью") + ("" if star_left <= 0.0 else I18n.t(" (через %d мин)") % (int(star_left) / 60 + 1)), _hotel_star_guest),
		_btn(I18n.t("▶ Ускорить процедуры") + ("" if Shop.cooldown_left("hotel_procs", AD_PROCS_CD) <= 0.0 else I18n.t(" (через %d мин)") % (int(Shop.cooldown_left("hotel_procs", AD_PROCS_CD)) / 60 + 1)), _hotel_fast_procs),
	], 520))


## вкладка «Номера»: одна строка на номер — уют, места и вид окружения
func _hotel_rooms(box: VBoxContainer, w: float) -> void:
	var rooms: Array = hotel_state["rooms"]
	box.add_child(_lbl(I18n.t("На сцене кликни по фее, а потом по кровати или станции. Здесь — уют, места и виды окружения."), 18, Color(Sketch.INK, 0.75)))
	for ri in rooms.size():
		var room: Dictionary = rooms[ri]
		var theme_id := str(room["theme"])
		var lvl := int(room["lvl"])
		var slots := int(room["slots"])
		var guests: Array = room["guests"]
		var season_txt := I18n.t(" · сезон ×1.6") if theme_id == Hotel.season_theme() else ""
		var row := HFlowContainer.new()
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 4)
		var info := _lbl(I18n.t("№%d · %s · уют %d/%d · мест %d/%d%s") % [ri + 1, Hotel.theme_title(theme_id), lvl,
			Hotel.ROOM_LEVEL_MAX, guests.size(), slots, season_txt], 19, Sketch.INK, true, HORIZONTAL_ALIGNMENT_LEFT, false)
		row.add_child(info)
		var up_cost := Hotel.upgrade_price(ri, lvl)
		if up_cost >= 0:
			row.add_child(_small_btn(I18n.t("✿ Уют: %d ✦") % up_cost, _hotel_upgrade_room.bind(ri)))
		row.add_child(_small_btn(I18n.t("❀ Сменить вид"), _hotel_open_theme.bind(ri)))
		if slots < 2:
			row.add_child(_small_btn(I18n.t("⌗ Второе место: %d ✦") % Hotel.expand_price(ri), _hotel_expand_room.bind(ri)))
		box.add_child(row)
	if hotel_theme_for >= 0:
		_hotel_theme_list(box, hotel_theme_for)
	elif hotel_proc_for >= 0:
		_hotel_proc_list(box, hotel_proc_for, hotel_proc_slot)
	else:
		var add_cost := Hotel.open_room_price(hotel_state)
		if add_cost < 0:
			box.add_child(_lbl(I18n.t("Все %d номеров открыты — дальше только уют и новые окружения.") % rooms.size(), 19, Color(Sketch.INK, 0.75)))
		else:
			box.add_child(_btn(I18n.t("+ Новый номер — %d ✦") % add_cost, _hotel_new_room, true))


## список видов окружения: компактные кнопки, описание — в подсказке
func _hotel_theme_list(box: VBoxContainer, room_i: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title := _lbl(I18n.t("Окружение для номера %d") % (room_i + 1), 21, WINE, true, HORIZONTAL_ALIGNMENT_LEFT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_small_btn(I18n.t("← Закрыть список"), _hotel_open_theme.bind(room_i)))
	box.add_child(row)
	var grid := _hotel_grid(4 if wide else 2)
	for d in Hotel.themes():
		var id := str(d["id"])
		var owned := Hotel.theme_owned(hotel_state, id)
		var price := Hotel.theme_price(hotel_state, id)
		var text := "%s %s" % [str(d["icon"]), str(d["title"])]
		if not owned:
			text += I18n.t(" · %d ✦") % price
		grid.add_child(_hotel_card_btn(text, I18n.t(str(d["desc"])), _hotel_apply_theme.bind(room_i, id), false, owned and str((hotel_state["rooms"] as Array)[room_i]["theme"]) == id))
	box.add_child(grid)


## список процедур для конкретной гостьи: тоже компактно
func _hotel_proc_list(box: VBoxContainer, room_i: int, slot: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title := _lbl(I18n.t("Куда отправить гостью из номера %d") % (room_i + 1), 21, WINE, true, HORIZONTAL_ALIGNMENT_LEFT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_small_btn(I18n.t("← Закрыть список"), _hotel_open_procs.bind(room_i, slot)))
	box.add_child(row)
	var grid := _hotel_grid(3)
	for d in Hotel.procs():
		var id := str(d["id"])
		var owned := Hotel.proc_owned(hotel_state, id)
		var left := Hotel.proc_room_left(hotel_state, id)
		var text := "%s %s · %d/%d" % [str(d["icon"]), str(d["title"]), int(d["cap"]) - left, int(d["cap"])]
		var tip := I18n.t("%s · %d с · +%d ✦") % [I18n.t(str(d["desc"])), int(Hotel.proc_dur(hotel_state, id)), int(d["pay"])]
		if not owned:
			tip = I18n.t("не открыто: купи на вкладке «Спа»")
		grid.add_child(_hotel_card_btn(text, tip, _hotel_send_proc.bind(room_i, slot, id), not owned or left <= 0))
	box.add_child(grid)


## вкладка «Спа»: покупка процедур и ускорения
func _hotel_spa(box: VBoxContainer, _w: float) -> void:
	box.add_child(_lbl(I18n.t("Процедуры отеля: гости платят за них отдельно, а любимую процедуру вспоминают в отзыве."), 18, Color(Sketch.INK, 0.8)))
	var grid := _hotel_grid(3 if wide else 2)
	for d in Hotel.procs():
		var id := str(d["id"])
		var owned := Hotel.proc_owned(hotel_state, id)
		var text := "%s %s" % [str(d["icon"]), str(d["title"])]
		if owned:
			text += I18n.t(" · куплено")
		else:
			text += I18n.t(" · %d ✦") % int(d["price"])
		grid.add_child(_hotel_card_btn(text, I18n.t("%s · %d с · +%d ✦ · мест %d") % [I18n.t(str(d["desc"])), int(Hotel.proc_dur(hotel_state, id)), int(d["pay"]), int(d["cap"])],
			_hotel_buy_proc.bind(id), false, owned))
	box.add_child(grid)
	box.add_child(_gap(2))
	box.add_child(_btn_row([
		_btn(I18n.t("▶ Ускорить процедуры"), _hotel_fast_procs),
		_btn(I18n.t("▶ Позвать редкую гостью"), _hotel_star_guest),
	], 520))


## вкладка «Отель»: улучшения, рекорды и итоги смены
func _hotel_ups(box: VBoxContainer, _w: float) -> void:
	var grid := _hotel_grid(3 if wide else 2)
	for d in Hotel.upgrades():
		var id := str(d["id"])
		var lvl := Hotel.up_level(hotel_state, id)
		var price := Hotel.up_price(hotel_state, id)
		var pips := ""
		for i in int(d["max"]):
			pips += "◆" if i < lvl else "◇"
		var text := "%s %s %s" % [str(d["icon"]), str(d["title"]), pips]
		if price >= 0:
			text += I18n.t(" · %d ✦") % price
		grid.add_child(_hotel_card_btn(text, I18n.t(str(d["desc"])), _hotel_buy_up.bind(id), false, price < 0))
	box.add_child(grid)
	box.add_child(_hotel_live_label(_lbl("", 19, Color(Sketch.INK, 0.75)), func() -> String:
		return I18n.t("Итоги смены уходят в таблицу рекордов режима «Отель фей»: %d ✦ и %d гостей.") % [int(hotel_state["earned"]), int(hotel_state["served"])]))
	box.add_child(_btn_row([
		_btn(I18n.t("◷ Записать итоги смены"), _hotel_report, true),
		_small_btn(I18n.t("★ Рекорды отеля"), _open_scores.bind("idle")),
	], 460))

