extends Node
## Проверка новых режимов и лавки: гонка, марафон, дуэль, тихий полёт, хор фей,
## звёздная стража, ежедневный вызов, наряды и сад фей. Запуск:
## godot --headless --path godot/fairy_book --fixed-fps 60 res://tests/modes_check.tscn

var fails := 0
const HAZARD_KINDS := ["wasp", "moth", "spider", "spore", "flame", "spark", "icicle", "orb", "inkbub", "bug", "beetle", "bolt", "boss"]
## врагов берём из движка (game.HAZARDS), иначе цели главы — бутоны, гнёзда —
## попадали в подсчёт и «Тихий полёт» ложно падал на пяти бутонах



func _ready() -> void:
	var g = load("res://scripts/game.gd").new()
	add_child(g)
	await get_tree().process_frame
	_check_race(g)
	_check_marathon(g)
	_check_duel(g)
	_check_zen(g)
	_check_choir(g)
	_check_guard(g)
	_check_guard_balance(g)
	_check_daily()
	_check_shop()
	_check_i18n()
	print("FAILS ", fails)
	get_tree().quit()


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print(("OK   " if cond else "FAIL ") + what)


func _step(g, frames: int) -> void:
	for i in frames:
		g.inv = 2.0
		g._process(1.0 / 60.0)


func _hazards(g) -> int:
	var n := 0
	for e in g.ents:
		if g.HAZARDS.has(e.kind) and not e.dead:
			n += 1
	return n


func _check_race(g) -> void:
	g.new_run("race")
	g.start_chapter(0)
	ok(g.time_limit > 0.0, "гонка: лимит времени задан (%.0f с)" % g.time_limit)
	ok(g.hearts == 3, "гонка: три сердца на старте")
	g.time_left = 0.02
	_step(g, 5)
	ok(g.time_failed and g.state == g.St.OVER, "гонка: время вышло — забег окончен")
	ok(g.hearts == 3, "гонка: сердца за просроченное время не снимаются")
	g.continue_race(20.0)
	ok(g.state == g.St.PLAY and g.time_left >= 20.0, "гонка: продолжение за рекламу даёт секунды")
	# задания главы остались: доходим до цели и проверяем бонус за секунды
	g.progress = int(g.ch()["goal"])
	g.time_left = 30.0
	_step(g, 6)
	ok(g.state == g.St.CLEAR, "гонка: цель выполнена — глава пройдена")


func _check_marathon(g) -> void:
	g.new_run("marathon")
	g.start_chapter(3)
	ok(not g.needs_goal(), "марафон: у главы нет финиша")
	ok(g.hearts == 3, "марафон: три сердца на старте")
	g.wave_t = 0.02
	_step(g, 12)
	ok(g.wave >= 1, "марафон: волна %d началась" % g.wave)
	ok(_hazards(g) > 0, "марафон: врагов на поле %d" % _hazards(g))
	# три волны — сердце
	g.hearts = 2
	g.wave = 2
	g.wave_t = 0.02
	_step(g, 12)
	ok(g.hearts >= 3, "марафон: каждые три волны дают сердце (♥ %d)" % g.hearts)
	# и режим не заканчивается сам по себе
	_step(g, 60 * 20)
	ok(g.state == g.St.PLAY or g.state == g.St.OVER, "марафон: 20 секунд отыграно (state=%d)" % g.state)


func _check_duel(g) -> void:
	g.new_run("duel")
	g.start_chapter(4)
	ok(g.count("boss") == 1, "дуэль: Король Теней на арене")
	var boss = g.boss_ent()
	ok(boss != null and boss.hp == 6, "дуэль: первая волна — 6 ♥")
	boss.b = 0.0
	boss.hp = 1
	g.carry = 3
	g.px = boss.x
	g.py = boss.y
	g.dash_t = 0.1
	g._update_boss(boss, 0.016)
	ok(g.count("boss") == 0, "дуэль: босс повержен зарядом")
	_step(g, 60 * 4)
	ok(g.count("boss") == 1 and g.boss_wave >= 2, "дуэль: следующая волна (boss_wave=%d)" % g.boss_wave)
	var b2 = g.boss_ent()
	ok(b2 != null and b2.hp > 6, "дуэль: следующий Король крепче (♥%d)" % (0 if b2 == null else b2.hp))


func _check_zen(g) -> void:
	g.new_run("zen")
	g.start_chapter(0)
	ok(g.max_start_hearts() == 5, "тихий полёт: пять сердец")
	_step(g, 60 * 12)
	ok(_hazards(g) == 0, "тихий полёт: врагов нет (%d)" % _hazards(g))
	g.inv = 0.0
	ok(g.damage() == false, "тихий полёт: урона нет")
	ok(g.state == g.St.PLAY, "тихий полёт: забег продолжается")


## первая живая сущность вида (для «Хора фей»)
func _first(g, kind: String):
	for e in g.ents:
		if e.kind == kind and not e.dead:
			return e
	return null


## «Хор фей»: на время проверки убираем тех, кто может перехватить добычу —
## остальных подружек уводим в другой конец поля, лишних соперниц отправляем удирать
func _choir_quiet(g, keep_ally, keep_rival) -> void:
	for e in g.ents:
		if e.kind == "ally" and e != keep_ally:
			e.x = 24.0
			e.y = g.gy() - 30.0
			e.b = 0
			e.a = 0.0
		elif e.kind == "rival" and e != keep_rival:
			e.a = 6.0
			e.b = 0


## «Хор фей»: подружки помогают и прикрывают, соперницы воруют, рывок их пугает
func _check_choir(g) -> void:
	ok(Modes.has("choir"), "хор: режим есть в каталоге")
	ok(Modes.flag("choir", "choir"), "хор: у режима свой флаг")
	ok(Modes.pick("choir") and Modes.goal("choir"), "хор: главу выбираем и цель у неё есть")
	g.new_run("choir")
	g.start_chapter(0)
	ok(g.count("ally") == 2, "хор: две подружки прилетели (%d)" % g.count("ally"))
	ok(g.count("rival") == 2, "хор: две соперницы прилетели (%d)" % g.count("rival"))

	# --- подружка подбирает добычу и отдаёт фее
	var ally = _first(g, "ally")
	ok(ally != null, "хор: подружка на поле")
	if ally == null:
		return
	var pol = g.spawn("pollen", ally.x + 8, ally.y, 9)
	ally.b = 0
	_choir_quiet(g, ally, null)
	g.px = 40
	g.py = g.gy() - 40
	_step(g, 40)
	ok(pol.dead, "хор: подружка подобрала пыльцу с поля")
	ok(ally.b > 0, "хор: подружка несёт добычу фее (b=%d)" % int(ally.b))
	g.carry = 0
	# держим фею рядом с подружкой по кадрам: добыча может тут же уйти в бутон
	# (тогда carry снова 0), поэтому признаком передачи служит пустая подружка
	var given := false
	for i in 30:
		g.inv = 2.0
		g.px = ally.x
		g.py = ally.y
		g._process(1.0 / 60.0)
		if int(ally.b) == 0:
			given = true
			break
	ok(given or g.carry >= 1, "хор: добыча дошла до феи (carry=%d, подружка пуста=%s)" % [g.carry, str(given)])

	# --- соперница уносит то же самое
	var rival = _first(g, "rival")
	ok(rival != null, "хор: соперница на поле")
	if rival == null:
		return
	rival.a = 0
	rival.b = 0
	var loot = g.spawn("pollen", rival.x + 8, rival.y, 9)
	_choir_quiet(g, null, rival)
	g.px = 40
	g.py = g.gy() - 40
	var stolen: int = g.rival_score
	_step(g, 40)
	ok(loot.dead, "хор: соперница забрала пыльцу")
	ok(g.rival_score > stolen, "хор: счёт соперниц вырос (%d → %d)" % [stolen, g.rival_score])

	# --- рывок пугает соперницу, и она бросает украденное
	rival.b = 1
	rival.a = 0
	_choir_quiet(g, null, rival)
	g.px = rival.x
	g.py = rival.y
	g.dash_t = 0.2
	var scared: int = g.choir_scared
	var had: int = g.rival_score
	_step(g, 2)
	ok(g.choir_scared > scared, "хор: рывок спугнул соперницу (%d)" % g.choir_scared)
	ok(g.rival_score < had, "хор: украденное вернули (%d → %d)" % [had, g.rival_score])
	ok(rival.b == 0, "хор: соперница летит налегке")

	# --- подружка закрывает фею от удара
	g.new_run("choir")
	g.start_chapter(0)
	var guard = _first(g, "ally")
	guard.a = 0
	g.px = guard.x + 20
	g.py = guard.y
	g.inv = 0.0
	g.dash_t = 0.0
	var hearts: int = g.hearts
	ok(g.damage(), "хор: удар принят")
	ok(g.hearts == hearts, "хор: сердце цело — прикрыла подружка (♥ %d)" % g.hearts)
	ok(guard.a > 0.0, "хор: подружка закружилась (%.1f с)" % guard.a)
	ok(g.choir_saved == 1, "хор: выручила один раз (%d)" % g.choir_saved)

	# --- хор: втроём очки удваиваются
	g.chorus = 0.0
	g.chorus_t = 0.0
	ok(g.score_mult() == 1, "хор: молча очки ×1")
	g.chorus = 5.0
	ok(g.score_mult() == 2, "хор: во время пения очки ×2")
	g.chorus = 0.0
	for e in g.ents:
		if e.kind == "ally":
			e.a = 0.0
			e.x = g.px + 30
			e.y = g.py
	g._update_choir(0.1)
	ok(g.chorus_t > 0.0, "хор: рядом с подружками копится запев (%.2f)" % g.chorus_t)

	# --- бонус в конце главы
	g.progress = int(g.ch()["goal"])
	g.choir_scared = 2
	g.choir_saved = 1
	g._clear_chapter()
	ok(g.last_bonus >= 520, "хор: бонус за подружек и испуганных соперниц (%d)" % g.last_bonus)
	ok(g.state == g.St.CLEAR, "хор: глава пройдена")


func _first_guard_foe(g):
	for e in g.ents:
		if g._guard_is_foe(e.kind) and not e.dead:
			return e
	return null


func _check_guard(g) -> void:
	ok(Modes.has("guard"), "стража: режим есть в каталоге")
	ok(not Modes.pick("guard") and not Modes.story("guard"), "стража: главу не выбираем и сказку не идём")
	ok(Guard.WAVES == 10 and Guard.HEART_HP > 0, "стража: десять волн и сердце на %d ударов" % Guard.HEART_HP)

	# --- состав волн
	ok(Guard.wave_table(1).size() >= 4 and Guard.wave_table(10).size() > Guard.wave_table(1).size(),
		"стража: в первой волне есть тени и к десятой их больше (%d → %d)" % [Guard.wave_table(1).size(), Guard.wave_table(10).size()])
	ok(Guard.wave_table(5).has("wight") and Guard.wave_table(10).has("wight"), "стража: каждая пятая волна с громадной тенью")
	ok(not Guard.wave_table(3).has("wight"), "стража: в третьей волне громадной тени нет")
	ok(Guard.enemy_hp("foe", 10) > Guard.enemy_hp("foe", 1), "стража: тени крепчают от волны к волне")
	ok(Guard.upgrade_cost(0, Guard.MAX_LEVEL) < 0, "стража: выше последнего уровня башню не улучшить")
	ok(float(Guard.tower(1).get("slow", 0.0)) > 0.0, "стража: светлячок замедляет тени")

	g.new_run("guard")
	g.start_chapter(Modes.GUARD_CHAPTER)
	ok(g.is_guard() and not g.needs_goal(), "стража: цель главы не нужна — считаем волны")
	ok(g.guard_path.size() >= 2 and g.guard_len > 0.0, "стража: тропа построена (%d точек, %.0f px)" % [g.guard_path.size(), g.guard_len])
	ok(g.guard_spots.size() >= 4, "стража: есть места под башни (%d)" % g.guard_spots.size())
	# роса на старте зависит и от колоды сказок — считаем ожидаемое значение сами
	var want_dew: int = Guard.START_DEW + Cards.dew_bonus(Cards.load_owned())
	ok(g.guard_dew == want_dew and g.guard_hp == Guard.HEART_HP,
		"стража: роса и сердце на старте (%d ♥ %d)" % [g.guard_dew, g.guard_hp])
	var on_path := 0
	for p in g.guard_spots:
		if Guard.dist_to_path(g.guard_path, p) < 34.0:
			on_path += 1
	ok(on_path == 0, "стража: ни один круг не стоит на тропе (%d)" % on_path)

	# --- волна приходит после отсчёта
	g.guard_rest = 0.02
	_step(g, 4)
	ok(g.wave == 1, "стража: первая волна началась (%d)" % g.wave)
	_step(g, 120)
	ok(g._guard_foes() > 0, "стража: тени вышли на тропу (%d)" % g._guard_foes())

	# --- тень идёт по тропе
	var foe = _first_guard_foe(g)
	ok(foe != null, "стража: тень на поле")
	if foe == null:
		return
	var d0: float = foe.d
	_step(g, 30)
	ok(foe.dead or foe.d > d0, "стража: тень продвинулась по тропе (%.0f → %.0f)" % [d0, foe.d])

	# --- башня ставится за росу и стреляет
	g.guard_dew = 500
	g._guard_tap(g.guard_spots[0])
	ok(g.count("tower") == 1, "стража: башня поставлена на круг")
	ok(g.guard_dew < 500, "стража: роса списана (%d)" % g.guard_dew)
	var tw = _first(g, "tower")
	ok(tw != null, "стража: башня на поле")
	if tw != null:
		var lv0 := int(tw.hp)
		g._guard_tap(g.guard_spots[0])
		ok(int(tw.hp) > lv0, "стража: повторный тап улучшает башню (%d → %d)" % [lv0, int(tw.hp)])
	foe = _first_guard_foe(g)
	if foe != null:
		var best := 0
		var bd := INF
		for i in g.guard_spots.size():
			var dd: float = g.guard_spots[i].distance_to(Vector2(foe.x, foe.y))
			if dd < bd:
				bd = dd
				best = i
		g._guard_tap(g.guard_spots[best])
		var hp0: int = foe.hp
		var kills0: int = g.guard_kills
		_step(g, 150)
		ok(foe.dead or foe.hp < hp0 or g.guard_kills > kills0, "стража: башни бьют теней (♥ %d → %d, развеяно %d)" % [hp0, foe.hp, g.guard_kills])

	# --- роса падает с тени и собирается феей
	g.guard_dew = 0
	foe = _first_guard_foe(g)
	if foe != null:
		g.px = foe.x
		g.py = foe.y
		g._guard_hurt(foe, 999, false)
		ok(g.count("dew") > 0, "стража: с тени упала роса (%d)" % g.count("dew"))
		_step(g, 30)
		ok(g.guard_dew > 0, "стража: фея собрала росу (%d)" % g.guard_dew)

	# --- прорыв к сердцу (если всех теней уже развеяли — выпускаем свою)
	g.guard_hp = Guard.HEART_HP
	g.guard_leaks = 0
	foe = _first_guard_foe(g)
	if foe == null:
		g._guard_spawn_foe("foe")
		foe = _first_guard_foe(g)
	ok(foe != null, "стража: есть тень для проверки прорыва")
	if foe != null:
		foe.d = g.guard_len + 1.0
		var heart0: int = g.guard_hp
		_step(g, 4)
		ok(g.guard_hp < heart0, "стража: прорвавшаяся тень бьёт по сердцу (%d → %d)" % [heart0, g.guard_hp])
		ok(g.guard_leaks > 0, "стража: прорыв посчитан (%d)" % g.guard_leaks)

	# --- панель выбора башни
	var rc: Rect2 = g._guard_tool_rect(2)
	ok(g._guard_tap(rc.get_center()), "стража: тап по панели выбора башни")
	ok(g.guard_tool == 2, "стража: выбран светлячок (%d)" % g.guard_tool)

	# --- сердце погасло — забег окончен
	g.guard_hp = 1
	foe = _first_guard_foe(g)
	if foe == null:
		g._guard_spawn_foe("foe")
		foe = _first_guard_foe(g)
	if foe != null:
		foe.d = g.guard_len + 1.0
		_step(g, 4)
	ok(g.guard_failed and g.state == g.St.OVER, "стража: сердце погасло — забег окончен")

	# --- второй шанс за рекламу чинит сердце
	g.revive()
	ok(g.state == g.St.PLAY and g.guard_hp == Guard.HEART_HP, "стража: второй шанс чинит сердце (%d)" % g.guard_hp)

	# --- окно изменилось прямо во время обороны
	g.new_run("guard")
	g.start_chapter(Modes.GUARD_CHAPTER)
	g.guard_dew = 500
	g.guard_tool = 0
	g._guard_build(0)
	g.guard_tool = 2
	g._guard_build(1)
	var towers: int = g.count("tower")
	ok(towers == 2, "стража: две башни встали на круги (%d)" % towers)
	g._guard_spawn_foe("foe")
	foe = _first_guard_foe(g)
	ok(foe != null, "стража: есть тень для проверки смены окна")
	if foe != null:
		foe.d = g.guard_len * 0.5
		var w0: float = g.W
		var h0: float = g.H
		var len0: float = g.guard_len
		g.W = w0 * 0.7
		g.H = h0 * 0.85
		g._guard_layout()
		ok(g.count("tower") == towers, "стража: башни пережили смену окна (%d)" % g.count("tower"))
		var on_spot := 0
		for e in g.ents:
			if e.kind != "tower":
				continue
			for p in g.guard_spots:
				if p.distance_to(Vector2(e.x, e.y)) < 1.5:
					on_spot += 1
					break
		ok(on_spot == towers, "стража: после смены окна башни стоят на своих кругах (%d из %d)" % [on_spot, towers])
		var share: float = float(foe.d) / maxf(1.0, g.guard_len)
		ok(absf(share - 0.5) < 0.02, "стража: тень осталась на середине тропы (%.2f)" % share)
		ok(foe.d < g.guard_len, "стража: короткая тропа не довела тень до сердца")
		g.W = w0
		g.H = h0
		g._guard_layout()
		ok(absf(g.guard_len - len0) < 0.5, "стража: тропа вернулась к прежнему размеру (%.0f)" % g.guard_len)

	# --- десять волн отбиты — победа
	g.new_run("guard")
	g.start_chapter(Modes.GUARD_CHAPTER)
	g.wave = Guard.WAVES
	g.guard_queue = []
	g.guard_rest = 0.0
	for e in g.ents:
		if g._guard_is_foe(e.kind):
			e.dead = true
	g.ents = g.ents.filter(func(x) -> bool: return not x.dead)
	_step(g, 4)
	ok(g.state == g.St.CLEAR, "стража: десять волн отбиты — поляна спасена")
	ok(g.progress == Guard.WAVES, "стража: прогресс равен числу волн (%d)" % g.progress)
	ok(g.last_bonus >= Guard.HEART_HP * 60, "стража: бонус за целое сердце (%d)" % g.last_bonus)


## жадная стройка бота: сначала заполнить круги башнями, потом улучшения.
## Одна постройка за кадр — как у живого игрока.
func _guard_bot_build(g) -> void:
	var order := [0, 0, 2, 1, 0, 2, 0, 2, 1, 2, 0, 2]
	var towers: int = g.count("tower")
	for si in g.guard_spots.size():
		var p: Vector2 = g.guard_spots[si]
		if g._guard_tower_at(p) != null:
			continue
		g.guard_tool = order[mini(towers, order.size() - 1)]
		var dew0: int = g.guard_dew
		g._guard_build(si)
		if g.guard_dew < dew0:
			return
	for si in g.guard_spots.size():
		var p: Vector2 = g.guard_spots[si]
		if g._guard_tower_at(p) == null:
			continue
		var dew1: int = g.guard_dew
		g._guard_build(si)
		if g.guard_dew < dew1:
			return


## Бот отыгрывает всю оборону: от первой волны до десятой. Росу собираем без
## потерь — проверяем баланс башен и волн, а не скорость феи. Проигрыш здесь
## означал бы, что режим непроходим для живого игрока.
func _check_guard_balance(g) -> void:
	g.new_run("guard")
	g.start_chapter(Modes.GUARD_CHAPTER)
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while g.state == g.St.PLAY and frames < 60 * 360:
		for e in g.ents:
			if e.kind == "dew" and not e.dead:
				g.guard_dew += int(e.hp)
				e.dead = true
		_guard_bot_build(g)
		g._process(1.0 / 60.0)
		frames += 1
	var ms := Time.get_ticks_msec() - t0
	ok(g.state == g.St.CLEAR, "стража: бот отстоял все %d волн (игровых %.0f с, расчёт %d мс)" % [Guard.WAVES, frames / 60.0, ms])
	ok(g.guard_hp > 0, "стража: сердце поляны уцелело (%d из %d, прорывов %d)" % [g.guard_hp, Guard.HEART_HP, g.guard_leaks])
	ok(g.guard_built >= 3 and g.guard_kills >= 60,
		"стража: росы хватает на оборону (построек %d, теней развеяно %d)" % [g.guard_built, g.guard_kills])


func _check_daily() -> void:
	ok(Modes.daily_key() != "", "вызов дня: ключ даты %s" % Modes.daily_key())
	var c1 := Modes.daily_chapter(1)
	ok(c1 == Modes.daily_chapter(1) and c1 == 0, "вызов дня: при одной главе выпадает первая")
	var c2 := Modes.daily_chapter(9)
	ok(c2 >= 0 and c2 < 9, "вызов дня: глава дня в пределах открытых (%d)" % c2)
	ok(Modes.daily_rule() != "", "вызов дня: правило дня «%s»" % Modes.daily_rule())
	# таблица рекордов нового режима
	var res := Scores.save({"name": "Тест", "score": 1234, "chapter": 2, "wave": 0, "date": 1}, "race")
	ok(int(res[0][0]["score"]) == 1234, "гонка: рекорд сохраняется в свой файл")
	Scores.remove(1, "race")


## проверка локализации: у каждой русской строки данных есть английский перевод
func _check_i18n() -> void:
	var re := RegEx.new()
	re.compile("[А-Яа-яЁё]")
	I18n.set_lang("ru")
	var ru: Array = []
	_collect(Chapters.LIST, ru)
	_collect(Chapters.PAINTS, ru)
	_collect(Modes.LIST, ru)
	_collect(Modes.RULES, ru)
	_collect(Skins.LIST, ru)
	_collect(Shop.UPGRADES, ru)
	I18n.set_lang("en")
	var missing := 0
	for s in ru:
		var txt := str(s)
		if re.search(txt) == null or I18n.t(txt) != txt:
			continue
		missing += 1
		print("     нет перевода: ", txt)
	ok(missing == 0, "локализация: переведены все русские строки данных (%d)" % ru.size())
	ok(I18n.t("Книга Фей") == "Fairy Book", "локализация: английский включается")
	ok(I18n.t("Задание: ") == "Task: ", "локализация: подписи экранов переведены")
	ok(I18n.t("Сказка") == "Story", "локализация: названия режимов переведены")
	ok(Modes.hud_label("race") == "⏱ Time Race", "локализация: подпись HUD переведена")
	ok(Skins.title("moon") == "Moonsilk", "локализация: название наряда переведено")
	ok(str(Chapters.get_ch(0)["title"]) == "Petals of Dawn", "локализация: глава переведена")
	ok(Modes.daily_rule() != "", "локализация: правило дня переведено («%s»)" % Modes.daily_rule())
	I18n.set_lang("ru")


## все строки внутри данных (для проверки переводов)
func _collect(v: Variant, out: Array) -> void:
	if v is String:
		out.append(v)
	elif v is Array:
		for i in v.size():
			_collect(v[i], out)
	elif v is Dictionary:
		for k in v.keys():
			_collect(v[k], out)


func _check_shop() -> void:
	ok(Shop.upgrades().size() >= 12, "лавка: улучшений %d" % Shop.upgrades().size())
	ok(Skins.list().size() >= 6, "наряды: %d штук" % Skins.list().size())
	var u := Shop.empty()
	for d in Shop.upgrades():
		ok(u.has(d["id"]), "лавка: ползунок %s на месте" % d["id"])
	# пыльца и уровень улучшения
	Shop.save_pollen(10000)
	var price := Shop.price_of(Shop.upgrades()[0], 0)
	Shop.save_pollen(Shop.load_pollen() - price)
	u["heart"] = 1
	Shop.save_upgrades(u)
	ok(Shop.load_upgrades()["heart"] == 1, "лавка: улучшение покупается и сохраняется")
	# наряд
	var owned := Shop.load_skins()
	owned["moon"] = true
	Shop.save_skins(owned)
	Shop.save_skin("moon")
	ok(Shop.load_skin() == "moon", "наряды: наряд надевается и сохраняется")
	ok(Skins.look("rainbow", 1.0).has("wing"), "наряды: радужные крылья переливаются")
	# сад фей
	ok(Shop.garden_cap(2) > 0, "сад: копилка %d ✦" % Shop.garden_cap(2))
	var g2 := {"last": Time.get_unix_time_from_system() - 7200.0, "pending": 0}
	ok(Shop.garden_now(2, g2) > 0, "сад: за два часа накопилась пыльца (%d ✦)" % Shop.garden_now(2, g2))
	# перезарядки рекламных наград
	Shop.touch_cooldown("chest")
	ok(Shop.cooldown_left("chest", 180.0) > 0.0, "реклама: перезарядка сундука работает")
	ok(Shop.cooldown_left("key", 0.0) <= 0.0, "реклама: нулевая перезарядка не блокирует")
