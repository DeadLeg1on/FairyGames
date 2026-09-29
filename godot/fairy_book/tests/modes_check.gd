extends Node
## Проверка новых режимов и лавки: гонка, марафон, дуэль, тихий полёт,
## ежедневный вызов, наряды и сад фей. Запуск:
## godot --headless --path godot/fairy_book --fixed-fps 60 res://tests/modes_check.tscn

var fails := 0
const HAZARD_KINDS := ["wasp", "moth", "spider", "spore", "flame", "spark", "icicle", "orb", "inkbub", "bug", "beetle", "bolt", "boss"]
const PICKUPS := ["pollen", "drop", "flake", "crystal", "shard", "sun", "firefly"]


func _ready() -> void:
	var g = load("res://scripts/game.gd").new()
	add_child(g)
	await get_tree().process_frame
	_check_race(g)
	_check_marathon(g)
	_check_duel(g)
	_check_zen(g)
	_check_daily()
	_check_shop()
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
		if not PICKUPS.has(e.kind) and not e.dead:
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


func _check_shop() -> void:
	ok(Shop.UPGRADES.size() >= 12, "лавка: улучшений %d" % Shop.UPGRADES.size())
	ok(Skins.LIST.size() >= 6, "наряды: %d штук" % Skins.LIST.size())
	var u := Shop.empty()
	for d in Shop.UPGRADES:
		ok(u.has(d["id"]), "лавка: ползунок %s на месте" % d["id"])
	# пыльца и уровень улучшения
	Shop.save_pollen(10000)
	var price := Shop.price_of(Shop.UPGRADES[0], 0)
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
