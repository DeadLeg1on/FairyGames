extends Node
## Проверка отдельной главы-режима «Отель фей»: заселение гостей, отзывы,
## рейтинг ★ и уровни гостей, процедуры, покупки, офлайн-смена и сохранение.
##
## Логика отеля (scripts/hotel.gd) не зависит от графики, поэтому сцена
## гоняется в headless-режиме:
##   godot --headless --path godot/fairy_book --fixed-fps 60 res://tests/hotel_check.tscn

var fails := 0


func _ready() -> void:
	_check_catalog()
	_check_fresh()
	_check_fit()
	_check_pay()
	_check_stay()
	_check_procs()
	_check_buys()
	_check_rating()
	_check_offline()
	_check_save()
	_check_i18n()
	await _check_view()
	await _check_flow()
	print("FAILS ", fails)
	get_tree().quit()


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print(("OK   " if cond else "FAIL ") + what)


func _has_cyr(v: String) -> bool:
	for i in v.length():
		var c := v.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


## гостья ровно такая, какой её делает check_in в игре
func _guest(kind: String, matched: bool = false, vip: bool = false) -> Dictionary:
	return {"kind": kind, "vip": vip, "t_left": Hotel.stay_time(1), "proc": "", "proc_left": 0.0, "matched": matched}


func _room(theme: String = "simple", lvl: int = 1, slots: int = 1) -> Dictionary:
	return {"theme": theme, "lvl": lvl, "slots": slots, "guests": []}


func _reviews(s: Dictionary, value: int, count: int = Hotel.REVIEW_WINDOW) -> void:
	var rev: Array = s["reviews"]
	rev.clear()
	for i in count:
		rev.append(value)


# ------------------------------------------------------------------ каталог и режим

func _check_catalog() -> void:
	ok(Chapters.count() == 10 and Chapters.story_count() == 9,
		"каталог: девять сюжетных глав и отель (%d/%d)" % [Chapters.story_count(), Chapters.count()])
	var hi := Chapters.hotel_index()
	ok(str(Chapters.get_ch(hi)["id"]) == "hotel", "отель — отдельная запись каталога")
	ok(Modes.hotel("idle") and not Modes.hotel("story"), "режим idle помечен как отель")
	ok(Modes.count() == 10, "режимов стало десять")
	ok(Modes.daily_chapter(9) <= Chapters.story_count(), "ежедневная глава не попадает в отель")
	# целостность вкусов: у каждого гостя есть его вид окружения и его процедура
	var broken := 0
	for k in Hotel.KINDS:
		if str(Hotel.theme_of(str(k["theme"]))["id"]) != str(k["theme"]):
			broken += 1
		if str(Hotel.proc_of(str(k["proc"]))["id"]) != str(k["proc"]):
			broken += 1
	ok(broken == 0, "у всех гостей есть их окружение и процедура (%d ошибок)" % broken)


func _check_fresh() -> void:
	var s := Hotel.fresh()
	ok((s["rooms"] as Array).size() == 2, "новый отель: два номера")
	var beds := Hotel.beds(s)
	ok(int(beds[0]) == 0 and int(beds[1]) == 2, "все места свободны (%d/%d)" % [int(beds[0]), int(beds[1])])
	ok(Hotel.theme_owned(s, "simple") and (s["themes"] as Dictionary).size() == 1, "открыт только простой номер")
	ok(Hotel.proc_owned(s, "tea") and not Hotel.proc_owned(s, "massage"), "чайная есть, массаж надо покупать")
	ok(int(s["cash"]) == 0 and int(s["earned"]) == 0 and int(s["served"]) == 0, "касса и счётчики пусты")
	ok(is_equal_approx(Hotel.stars(s), 1.0) and Hotel.tier_max(s) == 1,
		"стартовый рейтинг ★1.0 открывает только первых гостей")
	ok(Hotel.guest_cap(s) == 3, "на ресепшене три места")
	ok(int(Hotel.cash_cap(s)) == 400, "касса на два номера вмещает 400 ✦")
	ok(Hotel.fmt_time(90.0) == "1:30", "время показывается как минуты:секунды")


func _check_fit() -> void:
	ok(Hotel.fits("flower", "meadow"), "луговой номер подходит цветочной фее")
	ok(not Hotel.fits("flower", "moon"), "лунный номер цветочной фее не подходит")
	ok(not Hotel.fits("flower", "simple"), "простой номер вкуса не угождает")
	ok(str(Hotel.fit_hint("flower", "meadow")) != "" and Hotel.fit_hint("flower", "meadow") != Hotel.fit_hint("flower", "moon"),
		"подсказка различает угаданный вкус и промах")


# ------------------------------------------------------------------ плата и отзывы

func _check_pay() -> void:
	var s := Hotel.fresh()
	s["rooms"] = [_room("meadow"), _room("simple")]
	var good_guest := _guest("flower", true)
	var bad_guest := _guest("flower", false)
	var room_m: Dictionary = (s["rooms"] as Array)[0]
	var room_u: Dictionary = (s["rooms"] as Array)[1]
	var good := Hotel.payout(s, good_guest, room_m)
	var bad := Hotel.payout(s, bad_guest, room_u)
	ok(good > bad * 2, "угаданный вкус платит вдвое больше: %d против %d" % [good, bad])
	ok(Hotel.review_for(good_guest, room_m) == 3 and Hotel.review_for(bad_guest, room_u) == 1,
		"отзыв: угаданный вкус 3★, промах 1★")
	var vip := Hotel.payout(s, _guest("flower", true, true), room_m)
	ok(vip > good, "редкая гостья за рекламу платит больше: %d > %d" % [vip, good])
	# процедура добавляет плату, любимая — в полтора раза
	var with_proc := good_guest.duplicate()
	s["rooms"] = [_room("simple")]
	var plain := Hotel.payout(s, _guest("mushroom", false), (s["rooms"] as Array)[0])
	with_proc = _guest("mushroom", false)
	with_proc["proc"] = "tea"
	with_proc["proc_left"] = 0.0
	var boosted_proc := Hotel.payout(s, with_proc, (s["rooms"] as Array)[0])
	ok(absf(float(boosted_proc - plain) - 18.0) < 1.5,
		"любимая процедура гостя платит +50%%: %d против %d" % [boosted_proc, plain])
	# ×2 за рекламу
	var before := Hotel.payout(s, _guest("flower", true), (s["rooms"] as Array)[0])
	Hotel.set_boost(s, 60.0)
	var after := Hotel.payout(s, _guest("flower", true), (s["rooms"] as Array)[0])
	ok(Hotel.boosted(s) and absf(float(after - before * 2)) <= 2.0,
		"реклама включает ×2 к плате: %d → %d" % [before, after])
	ok(Hotel.boost_left(s) > 55.0 and Hotel.boost_left(s) <= 60.0, "буст тикает по времени")


# ------------------------------------------------------------------ проживание и очередь

func _check_stay() -> void:
	var s := Hotel.fresh()
	s["next_guest"] = 999.0
	var room: Dictionary = (s["rooms"] as Array)[0]
	(room["guests"] as Array).append(_guest("flower", true))
	(room["guests"] as Array)[0]["t_left"] = 0.5
	var cash_before := int(s["cash"])
	ok(Hotel.tick(s, 1.0) == 1 and (room["guests"] as Array).is_empty(), "гостья уехала, когда вышло время")
	ok(int(s["cash"]) > cash_before and int(s["served"]) == 1 and (s["reviews"] as Array).size() == 1,
		"плата легла в кассу, отзыв записан")
	ok(int(s["cash"]) <= Hotel.cash_cap(s), "касса не переполняется")
	var got := Hotel.collect(s)
	ok(got > 0 and int(s["cash"]) == 0, "кассу можно собрать: +%d ✦" % got)
	# окно отзывов не растёт бесконечно
	_reviews(s, 4)
	(room["guests"] as Array).append(_guest("flower", true))
	(room["guests"] as Array)[0]["t_left"] = 0.5
	Hotel.tick(s, 1.0)
	ok((s["reviews"] as Array).size() == Hotel.REVIEW_WINDOW,
		"в рейтинге хранится последние %d отзывов" % Hotel.REVIEW_WINDOW)
	# нетерпеливая гостья уходит из очереди
	(s["queue"] as Array).append({"kind": "flower", "vip": false, "patience": 5.0})
	Hotel.tick(s, 6.0)
	ok((s["queue"] as Array).is_empty(), "гостья, которая долго ждала, уходит")
	# ресепшн не принимает больше мест, чем может
	var s2 := Hotel.fresh()
	var added := 0
	while Hotel.add_guest(s2):
		added += 1
		if added > 20:
			break
	ok(added == Hotel.guest_cap(s2), "мест на ресепшене ровно столько, сколько даёт улучшение (%d)" % added)


# ------------------------------------------------------------------ процедуры

func _check_procs() -> void:
	var s := Hotel.fresh()
	Hotel.expand_room(s, 0)
	Hotel.expand_room(s, 1)
	var rooms: Array = s["rooms"]
	for ri in 2:
		for gi in 2:
			(rooms[ri]["guests"] as Array).append(_guest("flower", true))
	ok(Hotel.proc_room_left(s, "tea") == 2, "у чайной два места")
	ok(Hotel.send_proc(s, 0, 0, "tea") and Hotel.send_proc(s, 0, 1, "tea"), "две гостьи ушли в чайную")
	ok(not Hotel.send_proc(s, 1, 0, "tea"), "третью чайная не берёт: места заняты")
	ok(not Hotel.send_proc(s, 1, 0, "massage"), "некупленную процедуру не отправить")
	ok(Hotel.proc_load(s, "tea") == 2, "загрузка чайной 2/2")
	var during := Hotel.payout(s, (rooms[0]["guests"] as Array)[0], rooms[0])
	ok(Hotel.finish_procs(s) == 2, "ускорение завершает сразу обе процедуры")
	var done := Hotel.payout(s, (rooms[0]["guests"] as Array)[0], rooms[0])
	ok(done > during, "завершённая процедура добавляет плату: %d > %d" % [done, during])
	ok(Hotel.proc_load(s, "tea") == 0 and Hotel.finish_procs(s) == 0, "повторное ускорение никого не трогает")
	# лифт сокращает процедуры
	var before_dur := Hotel.proc_dur(s, "tea")
	Hotel.upgrade_hotel(s, "lift")
	ok(Hotel.proc_dur(s, "tea") < before_dur, "лифт ускоряет процедуры: %.1f → %.1f с" % [before_dur, Hotel.proc_dur(s, "tea")])


# ------------------------------------------------------------------ покупки и расширение

func _check_buys() -> void:
	var s := Hotel.fresh()
	ok(Hotel.buy_theme(s, "meadow") and not Hotel.buy_theme(s, "meadow"), "вид окружения покупается один раз")
	ok(Hotel.set_theme(s, 0, "meadow") and str((s["rooms"] as Array)[0]["theme"]) == "meadow",
		"окружение надевается на пустой номер")
	Hotel.buy_theme(s, "river")
	((s["rooms"] as Array)[0]["guests"] as Array).append(_guest("flower", true))
	ok(not Hotel.set_theme(s, 0, "river"), "вид не меняют, пока в номере живут гости")
	ok(Hotel.set_theme(s, 1, "river"), "во второй номер окружение ставится")
	ok(Hotel.upgrade_price(0, 1) == 120, "цена уюта считается по номеру и уровню")
	var lvl_before := int((s["rooms"] as Array)[0]["lvl"])
	ok(Hotel.upgrade_room(s, 0) and int((s["rooms"] as Array)[0]["lvl"]) == lvl_before + 1, "уют номера растёт")
	ok(Hotel.upgrade_price(0, Hotel.ROOM_LEVEL_MAX) == -1, "на максимуме уюта цена не считается")
	ok(Hotel.expand_room(s, 1) and not Hotel.expand_room(s, 1), "второе место ставится один раз")
	ok(Hotel.expand_price(0) == 450 and Hotel.expand_price(1) == 600, "цена второго места считается по номеру")
	ok(int(Hotel.open_room_price(s)) == 400 and Hotel.open_room(s), "новый номер стоит 400 ✦ и открывается")
	ok(int(Hotel.open_room_price(s)) > 400, "каждый следующий номер дороже")
	# улучшения отеля
	ok(int(Hotel.up_price(s, "flow")) > 0 and Hotel.flow_per_min(s) == 0, "вытяжка сначала не работает")
	Hotel.upgrade_hotel(s, "flow")
	ok(Hotel.flow_per_min(s) == 3, "вытяжка даёт +3 ✦ в минуту за уровень")
	var cap_before := Hotel.guest_cap(s)
	var wait_before := Hotel.arrive_every(s)
	Hotel.upgrade_hotel(s, "reception")
	ok(Hotel.guest_cap(s) == cap_before + 1 and Hotel.arrive_every(s) < wait_before,
		"ресепшн расширяет очередь и ускоряет прилёт гостей")
	Hotel.upgrade_hotel(s, "kitchen")
	var no_kitchen: Dictionary = s.duplicate(true)
	no_kitchen["up"] = (s["up"] as Dictionary).duplicate()
	no_kitchen["up"]["kitchen"] = 0
	no_kitchen["rooms"] = [_room("meadow")]
	var rich := Hotel.payout(s, _guest("flower", true), _room("meadow"))
	var plain := Hotel.payout(no_kitchen, _guest("flower", true), _room("meadow"))
	ok(rich > plain, "кухня поднимает плату за номер: %d > %d" % [rich, plain])
	var levels := 0
	while Hotel.up_price(s, "flow") >= 0 and levels <= 10:
		Hotel.upgrade_hotel(s, "flow")
		levels += 1
	ok(Hotel.up_price(s, "flow") == -1 and not Hotel.upgrade_hotel(s, "flow"), "у улучшений есть предел уровня")


# ------------------------------------------------------------------ рейтинг и уровни гостей

func _check_rating() -> void:
	var s := Hotel.fresh()
	_reviews(s, 5)
	ok(is_equal_approx(Hotel.stars(s), 5.0) and Hotel.tier_max(s) == 5, "пять звёзд открывают всех гостей")
	ok((Hotel.kinds_open(s) as Array).size() == Hotel.KINDS.size(), "пятый уровень открывает все виды гостей")
	_reviews(s, 2)
	ok(Hotel.tier_max(s) == 2, "низкий рейтинг оставляет только первых гостей")
	var expected := 0
	for k in Hotel.KINDS:
		if int(k["tier"]) <= Hotel.tier_max(s):
			expected += 1
	ok((Hotel.kinds_open(s) as Array).size() == expected, "список доступных гостей совпадает с рейтингом")
	var honest := true
	for i in 20:
		var g := Hotel.roll_guest(s, false)
		if int(Hotel.kind_of(str(g["kind"]))["tier"]) > Hotel.tier_max(s):
			honest = false
	ok(honest, "при низком рейтинге прилетают только простые гости")
	var vip := Hotel.roll_guest(s, true)
	ok(bool(vip["vip"]), "редкая гостья помечена как гостья за рекламу")
	# часть отзывов: рейтинг — среднее по окну
	_reviews(s, 5, 3)
	(s["reviews"] as Array).append(1)
	ok(Hotel.stars(s) < 5.0 and Hotel.stars(s) > 1.0, "рейтинг считается средним по последним отзывам")


# ------------------------------------------------------------------ офлайн-смена

func _check_offline() -> void:
	var s := Hotel.fresh()
	Hotel.buy_theme(s, "meadow")
	Hotel.set_theme(s, 0, "meadow")
	(s["queue"] as Array).append({"kind": "flower", "vip": false, "patience": 600.0})
	s["last"] = Time.get_unix_time_from_system() - 600.0
	var res := Hotel.settle(s)
	ok(int(res["sec"]) >= 590 and int(res["pollen"]) > 0,
		"офлайн-смена приносит пыльцу: %d ✦ за %d с" % [int(res["pollen"]), int(res["sec"])])
	ok(int(s["served"]) >= 1, "без игрока отель сам принимает гостей (обслужено %d)" % int(s["served"]))
	ok(str(Hotel.settle_hint(res)) != "", "подпись офлайн-дохода готова")
	ok(int(Hotel.settle(s)["sec"]) == 0, "сразу после смены копить нечего")
	s["last"] = Time.get_unix_time_from_system() - 100000.0
	var capped := Hotel.settle(s)
	ok(float(capped["sec"]) <= Hotel.OFFLINE_CAP + 1.0,
		"офлайн копится не больше восьми часов (%d с)" % int(capped["sec"]))
	# офлайн-хозяюшка не подселяет гостью в неподходящий номер
	var s2 := Hotel.fresh()
	Hotel.buy_theme(s2, "meadow")
	Hotel.set_theme(s2, 0, "meadow")
	(s2["queue"] as Array).append({"kind": "night", "vip": false, "patience": 600.0})
	ok(Hotel.auto_host(s2) == 0, "чужая гостья в неподходящий номер не подселяется")
	(s2["queue"] as Array)[0]["kind"] = "flower"
	ok(Hotel.auto_host(s2) == 1, "подходящая гостья заселяется сама")


# ------------------------------------------------------------------ сохранение

func _check_save() -> void:
	# тест не должен трогать настоящий прогресс: исходное состояние вернём в конце
	var cfg := ConfigFile.new()
	cfg.load(Hotel.SETTINGS)
	var backup: Variant = cfg.get_value(Hotel.SAVE_SECTION, Hotel.SAVE_KEY, null)

	var s := Hotel.fresh()
	s["cash"] = 321
	Hotel.buy_theme(s, "frost")
	Hotel.open_room(s)
	Hotel.save_state(s)
	var t := Hotel.load_state()
	ok(int(t["cash"]) == 321 and (t["rooms"] as Array).size() == 3, "состояние отеля сохраняется и читается")
	ok(Hotel.theme_owned(t, "frost") and int(Hotel.up_level(t, "flow")) == 0, "купленные виды окружения на месте")
	# обрезанное сохранение добирается недостающими полями
	var cut := ConfigFile.new()
	cut.load(Hotel.SETTINGS)
	cut.set_value(Hotel.SAVE_SECTION, Hotel.SAVE_KEY, JSON.stringify({"cash": 5}))
	cut.save(Hotel.SETTINGS)
	var healed := Hotel.load_state()
	ok((healed["rooms"] as Array).size() == 2 and healed.has("reviews") and (healed["procs"] as Dictionary).has("tea"),
		"битое сохранение лечится до состояния нового отеля")

	var back := ConfigFile.new()
	back.load(Hotel.SETTINGS)
	if backup == null and back.has_section_key(Hotel.SAVE_SECTION, Hotel.SAVE_KEY):
		back.erase_section_key(Hotel.SAVE_SECTION, Hotel.SAVE_KEY)
	else:
		back.set_value(Hotel.SAVE_SECTION, Hotel.SAVE_KEY, backup)
	back.save(Hotel.SETTINGS)


# ------------------------------------------------------------------ локализация

func _check_i18n() -> void:
	var before := I18n.lang
	I18n.lang = I18n.EN
	var en := I18n.t("Отель фей")
	ok(en != "" and en != "Отель фей", "название отеля переводится: %s" % en)
	var missing := 0
	for d in Hotel.KINDS + Hotel.THEMES + Hotel.PROCS + Hotel.UPGRADES:
		for k in d.keys():
			var v: Variant = d[k]
			if v is String and _has_cyr(str(v)) and I18n.t(str(v)) == str(v):
				missing += 1
	ok(missing == 0, "все подписи отеля переведены (%d пропусков)" % missing)
	var chapter_en := I18n.t(str(Chapters.get_ch(Chapters.hotel_index())["title"]))
	ok(chapter_en != "" and chapter_en != "Отель фей", "название главы переводится: %s" % chapter_en)
	ok(I18n.t("Спа") == "Spa" and I18n.t("Гости") == "Guests", "кнопки отеля переведены")
	I18n.lang = before

# ------------------------------------------------------------------ сцена отеля (курсор)

func _find_hit(list: Array, kind: String, a: Variant) -> Dictionary:
	for h in list:
		if str(h["kind"]) == kind and h["a"] == a:
			return h
	return {}


## сцена: клик по фее, по кровати и по станции даёт правильные области
func _check_view() -> void:
	var st := Hotel.fresh()
	Hotel.buy_theme(st, "meadow")
	Hotel.set_theme(st, 0, "meadow")
	Hotel.expand_room(st, 0)
	Hotel.add_guest(st, false)
	Hotel.add_guest(st, true)
	Hotel.check_in(st, 0, 0)
	ok(((st["rooms"] as Array)[0]["guests"] as Array).size() == 1, "в первом номере живёт гостья")

	var v := HotelView.new()
	v.size = Vector2(920, 380)
	add_child(v)
	v.state = st
	v.sel = ""
	var got := []
	v.act.connect(func(k: String, a: Variant, b: Variant) -> void: got.append([k, a, b]))
	await get_tree().process_frame
	v.layout(true)
	var hs: Array = v.hits()
	ok(hs.size() >= 10, "на сцене есть кликабельные области: очередь, кровати, станции (%d)" % hs.size())

	var q := _find_hit(hs, "queue", 0)
	ok(not q.is_empty(), "гостья на ресепшене кликабельна")
	var r: Dictionary = v.pick((q["rect"] as Rect2).get_center())
	ok(str(r.get("kind", "")) == "queue" and got.size() == 1 and str(got[0][0]) == "queue",
		"клик по фее на ресепшене сообщает о выборе гостьи")

	var res := _find_hit(hs, "resident", 0)
	ok(not res.is_empty(), "жиличка в номере кликабельна")
	v.pick((res["rect"] as Rect2).get_center())
	ok(str(got[-1][0]) == "resident" and int(got[-1][1]) == 0 and int(got[-1][2]) == 0, "клик по жиличке сообщает её номер и место")

	var bed := _find_hit(hs, "bed", 1)
	ok(not bed.is_empty(), "свободная кровать кликабельна")
	v.pick((bed["rect"] as Rect2).get_center())
	ok(str(got[-1][0]) == "bed" and int(got[-1][1]) == 0 and int(got[-1][2]) == 1, "клик по свободной кровати сообщает номер и место")

	var stn := _find_hit(hs, "station", "tea")
	ok(not stn.is_empty(), "станция процедур кликабельна")
	v.pick((stn["rect"] as Rect2).get_center())
	ok(str(got[-1][0]) == "station" and str(got[-1][1]) == "tea", "клик по станции сообщает вид процедуры")

	v.pick(Vector2(3, 3))
	ok(str(got[-1][0]) == "none", "клик по пустому месту снимает выбор")
	v.queue_free()
	await get_tree().process_frame


## весь поток управления курсором: выбрал фею → кликнул, куда её деть
func _check_flow() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Hotel.SETTINGS)
	var backup: Variant = cfg.get_value(Hotel.SAVE_SECTION, Hotel.SAVE_KEY, null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Hotel.SETTINGS))

	var m = preload("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	m.unlocked = 9
	m._open_hotel()
	Hotel.add_guest(m.hotel_state, false)
	m._build_overlay()
	await get_tree().process_frame
	ok(m.hotel_sel == "", "при входе в отель никто не выбран")

	m._hotel_view_act("queue", 0, 0)
	ok(m.hotel_sel == "q:0", "клик по фее на ресепшене выбирает её")
	ok(str(m._hotel_tip()) != "", "под сценой есть подсказка, что делать дальше")

	m._hotel_view_act("bed", 0, 0)
	var rooms: Array = m.hotel_state["rooms"]
	ok((rooms[0]["guests"] as Array).size() == 1, "клик по кровати заселяет выбранную фею")
	ok(m.hotel_sel == "", "после заселения выбор сброшен")

	m._hotel_view_act("station", "tea", 0)
	ok(str((m.hotel_state["rooms"] as Array)[0]["guests"][0]["proc"]) == "",
		"без выбранной феи станция ничего не делает")
	ok(m.hotel_flash != "", "отель объясняет, что сначала нужно выбрать гостью")

	m._hotel_view_act("resident", 0, 0)
	ok(m.hotel_sel == "r:0:0", "клик по жиличке выбирает её")
	m._hotel_view_act("station", "tea", 0)
	ok(str((m.hotel_state["rooms"] as Array)[0]["guests"][0]["proc"]) == "tea",
		"клик по станции отправляет выбранную фею на процедуру")
	m.queue_free()
	await get_tree().process_frame

	var back := ConfigFile.new()
	back.load(Hotel.SETTINGS)
	if backup == null:
		if back.has_section_key(Hotel.SAVE_SECTION, Hotel.SAVE_KEY):
			back.erase_section_key(Hotel.SAVE_SECTION, Hotel.SAVE_KEY)
	else:
		back.set_value(Hotel.SAVE_SECTION, Hotel.SAVE_KEY, backup)
	back.save(Hotel.SETTINGS)
