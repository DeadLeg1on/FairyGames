extends Node
## Прогон всех режимов, экранов и переходов + проверка, что карточка помещается в экран.
## Новые экраны: выбор языка, «Все режимы», «Награды за рекламу», вкладки лавки, режимы дня.
var m
var fails := 0

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	for f in Modes.list():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Scores.path_for(f["id"])))
	m = preload("res://scripts/main.gd").new()
	add_child(m)
	await _wait(5)
	for size in [Vector2i(960, 540), Vector2i(540, 960), Vector2i(700, 540)]:
		get_window().size = size
		await _wait(5)
		print("== viewport ", m.ui.get_viewport_rect().size, " wide=", m.wide)
		await _run_flow()
	print("UPGRADES ", m.upgrades, " game=", m.game.upgrades, " pollen=", m.pollen, " unlocked_max=", Chapters.count())
	print("FAILS ", fails)
	get_tree().quit()

func _run_flow() -> void:
	m.unlocked = 3
	var steps := [
		["lang", func(): m.screen = "lang"; m.lang_chosen = false; m._build_overlay()],
		["menu", func(): m._pick_lang("en")],   # первый запуск: выбран английский
		["menu", func(): m._toggle_lang()],     # в меню язык меняется на русский
		["menu", func(): m._to_menu()],
		["story", func(): m._choose_mode("story")],
		["play", func(): m._begin_chapter()],
		["paused", func(): m._pause()],
		["play", func(): m._resume()],
		["over", func(): m._on_game_over(1234, 2)],
		["play", func(): m._continue_for_ad()],
		["story", func(): m._on_chapter_cleared(0, 700, 2000)],
		["menu", func(): m._to_menu()],
		["story", func(): m._choose_mode("hard")],
		["play", func(): m._begin_chapter()],
		["win", func(): m._on_chapter_cleared(8, 900, 9000)],
		["shop", func(): m._open_shop()],
		["shop", func(): m._add_pollen(1000); m._buy("speed", false)],
		["shop", func(): m._buy("magnet", true)],
		["win", func(): m._close_shop()],
		["select", func(): m._choose_mode("chapter")],
		["select", func(): m.unlocked = 3; m._pick_chapter(4)], # закрыта — остаёмся
		["story", func(): m._pick_chapter(1)],
		["play", func(): m._begin_chapter()],
		["result", func(): m._on_chapter_cleared(1, 800, 3000)],
		["story", func(): m._next_chapter()],
		["select", func(): m._choose_mode("endless")],
		["story", func(): m._pick_chapter(0)],
		["play", func(): m._begin_chapter()],
		["over", func(): m._on_game_over(4321, 0)],
		["scores", func(): m._open_scores("endless")],
		["scores", func(): m._open_scores("chapter")],
		["menu", func(): m._go("menu")],
		# --- новые экраны -------------------------------------------------
		["modes", func(): m._open_modes()],
		["menu", func(): m._to_menu()],
		["rewards", func(): m._open_rewards()],
		["rewards", func(): m.unlocked = 9; m._chest_for_ad()],
		["menu", func(): m._to_menu()],
		# --- гонка со временем --------------------------------------------
		["select", func(): m.unlocked = 9; m._choose_mode("race")],
		["story", func(): m._pick_chapter(4)], # звёздная глава — можно и в гонке
		["play", func(): m._begin_chapter()],
		["paused", func(): m._pause()],
		["play", func(): m._time_for_ad()],
		["over", func(): m._on_game_over(900, 4)],
		["play", func(): m._continue_for_ad()],
		["menu", func(): m._to_menu()],
		# --- тихий полёт ---------------------------------------------------
		["select", func(): m._choose_mode("zen")],
		["select", func(): m._pick_chapter(4)], # в тихом полёте звёздной главы нет
		["story", func(): m._pick_chapter(0)],
		["play", func(): m._begin_chapter()],
		["paused", func(): m._pause()],
		["play", func(): m._resume()],
		["menu", func(): m._to_menu()],
		# --- марафон и дуэль -----------------------------------------------
		["select", func(): m._choose_mode("marathon")],
		["story", func(): m._pick_chapter(3)],
		["play", func(): m._begin_chapter()],
		["menu", func(): m._to_menu()],
		["story", func(): m._choose_mode("duel")],
		["play", func(): m._begin_chapter()],
		["over", func(): m._on_game_over(500, 4)],
		["menu", func(): m._to_menu()],
		# --- ежедневный вызов ----------------------------------------------
		# вызов дня одноразовый: сбрасываем состояние, иначе повторные проходы
		# (на других размерах окна) остаются на экране главы
		["story", func(): Shop.save_daily({"date": "", "attempts": 0, "streak": 0, "best": 0}); m._choose_mode("daily")],
		["play", func(): m._begin_chapter()],
		["over", func(): m._on_game_over(700, 0)],
		["over", func(): m._daily_extra_attempt(false)],
		["menu", func(): m._to_menu()],
		# --- лавка: наряды и сад --------------------------------------------
		["shop", func(): m._open_shop()],
		["shop", func(): m._set_shop_tab("look")],
		["shop", func(): m._buy_skin("moon", false)],
		["shop", func(): m._wear_skin("classic")],
		["shop", func(): m._set_shop_tab("garden")],
		["shop", func(): m._set_shop_tab("up")],
		["menu", func(): m._close_shop()],
		# --- отель фей: отдельная idle-глава ---------------------------------
		["menu", func(): _reset_hotel(); m.unlocked = 9],
		["hotel", func(): m._choose_mode("idle")],
		["hotel", func(): m._hotel_open_theme(0)],
		["hotel", func(): m._hotel_apply_theme(0, "meadow")],
		["hotel", func(): Hotel.add_guest(m.hotel_state)],
		["hotel", func(): m._hotel_set_tab("guests")],
		["hotel", func(): m._hotel_select(0)],
		["hotel", func(): m._hotel_check_in(0)],
		# управление курсором на сцене: выбрал фею → выбрал, куда её деть
		["hotel", func(): m._hotel_view_act("resident", 0, 0)],
		["hotel", func(): m._hotel_view_act("station", "tea", 0)],
		["hotel", func(): m._hotel_view_act("queue", 0, 0)],
		["hotel", func(): m._hotel_view_act("bed", 1, 0)],
		["hotel", func(): m._hotel_view_act("none", 0, 0)],
		["hotel", func(): m._hotel_open_procs(0, 0)],
		["hotel", func(): m._hotel_send_proc(0, 0, "tea")],
		["hotel", func(): m._hotel_set_tab("spa")],
		["hotel", func(): m._hotel_set_tab("up")],
		["hotel", func(): m._hotel_buy_up("flow")],
		["hotel", func(): m._hotel_collect(false)],
		["hotel", func(): m._hotel_report()],
		["hotel", func(): m._hotel_tick(1.0)],
		["scores", func(): m._open_scores("idle")],
		["hotel", func(): m._go("hotel")],
		["menu", func(): m._leave_hotel()],
		# --- английский интерфейс -------------------------------------------
		["menu", func(): m._toggle_lang()],      # меню по-английски
		["shop", func(): m._open_shop()],        # лавка по-английски
		["menu", func(): m._close_shop()],
		["menu", func(): m._toggle_lang()],      # обратно на русский
	]
	for st in steps:
		st[1].call()
		await _wait(8)
		var ok: bool = m.screen == st[0]
		var fit := "-"
		if m.overlay:
			var card: Control = null
			for c in m.overlay.get_children():
				if c is PanelContainer:
					card = c
			if card:
				var vs: Vector2 = m.ui.get_viewport_rect().size
				var s: float = card.get_meta("fit_scale", 1.0)
				var top := card.position.y + card.size.y * (1.0 - s) * 0.5
				var bottom := top + card.size.y * s
				var left := card.position.x + card.size.x * (1.0 - s) * 0.5
				var right := left + card.size.x * s
				var inside := top >= -0.5 and left >= -0.5 and bottom <= vs.y + 0.5 and right <= vs.x + 0.5
				fit = "fit(scale=%.2f, %d..%d / %d)" % [s, top, bottom, vs.y]
				if not inside:
					ok = false
					fit += " OUT"
					_dump_card(card)
		if not ok:
			fails += 1
		print(("OK   " if ok else "FAIL ") + str(st[0]).rpad(7) + " mode=" + m.mode.rpad(8) + " " + fit)

## перед прогоном экрана отеля: чистый отель, чтобы карточка не разрасталась
func _reset_hotel() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Hotel.SETTINGS)
	if cfg.has_section_key(Hotel.SAVE_SECTION, Hotel.SAVE_KEY):
		cfg.erase_section_key(Hotel.SAVE_SECTION, Hotel.SAVE_KEY)
		cfg.save(Hotel.SETTINGS)


## если карточка не помещается в экран — показываем, кто её раздувает
func _dump_card(card: Control) -> void:
	print("     card size=", card.size, " min=", card.get_minimum_size())
	if card.get_child_count() == 0:
		return
	var box: Control = card.get_child(0)
	var kids := []
	for c in box.get_children():
		var cc := c as Control
		if cc != null:
			kids.append(cc)
	kids.sort_custom(func(a, b) -> bool: return a.get_minimum_size().y > b.get_minimum_size().y)
	for cc in kids.slice(0, 8):
		var text := ""
		if cc is Label:
			text = (cc as Label).text.substr(0, 46)
		print("       ", cc.get_class(), " min=", cc.get_minimum_size(), " size=", cc.size, " ", text)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
