extends Node
## Колода сказок: каталог карт, наборы, бонусы за сбор, выпадение и хранение.
## Запуск:
## godot --headless --path godot/fairy_book --fixed-fps 60 res://tests/cards_check.tscn
##
## user://settings.cfg общий для всех тестов прогона CI, поэтому колоду в начале
## запоминаем, а в конце возвращаем как было.

var fails := 0
var was_owned := {}


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print(("OK   " if cond else "FAIL ") + what)


func _ready() -> void:
	print("== колода сказок: карты, наборы, бонусы ==")
	was_owned = Cards.load_owned()
	_check_catalog()
	_check_progress()
	_check_bonuses()
	_check_roll()
	_check_save()
	await _check_game()
	# возвращаем колоду, с которой пришли
	Cards.save_owned(was_owned)
	print("FAILS ", fails)
	get_tree().quit(0 if fails == 0 else 1)


## колода с полностью собранным набором
func _full_set(set_id: String) -> Dictionary:
	var o := Cards.empty()
	for c in Cards.cards_of(set_id):
		o = Cards.grant(o, str(c["id"]))
	return o


## колода со всеми картами
func _full_deck() -> Dictionary:
	var o := Cards.empty()
	for id in Cards.ids():
		o = Cards.grant(o, id)
	return o


# ================================================================= каталог

func _check_catalog() -> void:
	ok(Cards.CARDS.size() == 15, "колода: пятнадцать карт (%d)" % Cards.CARDS.size())
	ok(Cards.SETS.size() == 3, "колода: три набора (%d)" % Cards.SETS.size())
	var ids := Cards.ids()
	var uniq := {}
	for id in ids:
		uniq[id] = true
	ok(uniq.size() == ids.size(), "колода: все id разные (%d)" % uniq.size())
	var bad_set := 0
	var bad_text := 0
	for c in Cards.CARDS:
		if Cards.set_of(str(c["id"])).is_empty():
			bad_set += 1
		if str(c["icon"]).is_empty() or str(c["title"]).is_empty() or str(c["desc"]).is_empty():
			bad_text += 1
	ok(bad_set == 0, "колода: у каждой карты свой набор (%d ошибок)" % bad_set)
	ok(bad_text == 0, "колода: у каждой карты значок, имя и подпись (%d ошибок)" % bad_text)
	var bad_count := 0
	var kinds := {}
	for s in Cards.SETS:
		if Cards.cards_of(str(s["id"])).size() != 5:
			bad_count += 1
		kinds[str(s["kind"])] = true
	ok(bad_count == 0, "колода: в каждом наборе по пять карт (%d ошибок)" % bad_count)
	ok(kinds.has("score") and kinds.has("pollen") and kinds.has("dew"),
		"колода: наборы дают три разных бонуса (%s)" % str(kinds.keys()))
	ok(Cards.in_catalog("lily") and not Cards.in_catalog("нет-такой-карты"), "колода: каталог узнаёт свои карты")
	ok(Cards.card_of("нет-такой-карты").is_empty(), "колода: незнакомой карты нет")
	ok(Cards.cards_of("meadow").size() == 5 and Cards.cards_of("нет").is_empty(), "колода: карты набора выбираются по набору")


# ================================================================= прогресс

func _check_progress() -> void:
	var none := Cards.empty()
	ok(none.size() == 15, "колода: пустая колода знает все карты (%d)" % none.size())
	ok(Cards.count(none) == 0, "колода: на старте не собрано ничего")
	ok(Cards.missing(none).size() == 15, "колода: не хватает всех пятнадцати")
	ok(Cards.full_sets(none) == 0, "колода: полных наборов нет")
	var one := Cards.grant(none, "lily")
	ok(Cards.count(one) == 1 and Cards.set_count(one, "meadow") == 1, "колода: одна карта засчитана")
	ok(Cards.missing(one).size() == 14, "колода: после находки не хватает четырнадцати")
	var partial := Cards.grant(one, "bud")
	ok(not Cards.is_full(partial, "meadow"), "колода: две карты набором не считаются")
	var meadow := _full_set("meadow")
	ok(Cards.set_count(meadow, "meadow") == 5, "колода: луговой набор собран (5)")
	ok(Cards.is_full(meadow, "meadow") and Cards.full_sets(meadow) == 1, "колода: полный набор один")
	ok(not Cards.is_full(meadow, "night"), "колода: чужой набор не собрался")
	ok(Cards.grant(meadow, "lily").size() == meadow.size(), "колода: повторная находка ничего не меняет")
	ok(Cards.grant(meadow, "нет-такой-карты").size() == meadow.size(), "колода: незнакомая карта не добавляется")
	var all := _full_deck()
	ok(Cards.count(all) == 15 and Cards.full_sets(all) == 3, "колода: все карты и все три набора (%d)" % Cards.count(all))
	ok(Cards.missing(all).is_empty(), "колода: не хватает ничего")


# ================================================================= бонусы

func _check_bonuses() -> void:
	var none := Cards.empty()
	ok(Cards.score_bonus(none) == 0.0 and Cards.pollen_bonus(none) == 0.0 and Cards.dew_bonus(none) == 0,
		"колода: без наборов бонусов нет")
	var meadow := _full_set("meadow")
	ok(is_equal_approx(Cards.score_bonus(meadow), Cards.BONUS_SCORE),
		"колода: луговые сказки дают %.0f%% очков" % (Cards.BONUS_SCORE * 100.0))
	ok(Cards.pollen_bonus(meadow) == 0.0 and Cards.dew_bonus(meadow) == 0, "колода: луговой набор не трогает пыльцу и росу")
	var half := Cards.grant(Cards.grant(none, "lily"), "bud")
	ok(Cards.score_bonus(half) == 0.0, "колода: неполный набор бонуса не даёт")
	var night := _full_set("night")
	ok(is_equal_approx(Cards.pollen_bonus(night), Cards.BONUS_POLLEN),
		"колода: ночные сказки дают %.0f%% пыльцы" % (Cards.BONUS_POLLEN * 100.0))
	ok(Cards.score_bonus(night) == 0.0, "колода: ночной набор не трогает очки")
	var thorn := _full_set("thorn")
	ok(Cards.dew_bonus(thorn) == Cards.BONUS_DEW, "колода: колючие сказки дают %d росы" % Cards.BONUS_DEW)
	var all := _full_deck()
	ok(is_equal_approx(Cards.score_bonus(all), Cards.BONUS_SCORE) and is_equal_approx(Cards.pollen_bonus(all), Cards.BONUS_POLLEN)
		and Cards.dew_bonus(all) == Cards.BONUS_DEW, "колода: три набора — три бонуса сразу")
	ok(Cards.score_bonus(all) < 0.05, "колода: бонусы маленькие (очки +%.0f%%)" % (Cards.score_bonus(all) * 100.0))
	ok(Cards.bonus_text(none).contains("бонусов пока нет"), "колода: пустая колода честно говорит, что бонусов нет")
	ok(Cards.bonus_text(all).contains("+2% очков") and Cards.bonus_text(all).contains("+15 росы"),
		"колода: строка бонусов перечисляет собранное")


# ================================================================= выпадение

func _check_roll() -> void:
	var none := Cards.empty()
	var a := Cards.roll(none, 12345)
	var b := Cards.roll(none, 12345)
	ok(a == b and a != "", "колода: одно зерно — одна и та же карта (%s)" % a)
	ok(Cards.in_catalog(a), "колода: вытянутая карта из каталога")
	ok(Cards.missing(none).has(a), "колода: вытягиваем только недостающие")
	ok(Cards.roll(none, 999) != "", "колода: другое зерно тоже что-то даёт")
	var grown := Cards.grant(none, a)
	ok(Cards.roll(grown, 12345) != a, "колода: найденная карта больше не выпадает")
	ok(Cards.roll(_full_deck(), 1) == "", "колода: полная колода — тянуть нечего")
	ok(Cards.found_text("") == "", "колода: пустая находка ничего не печатает")
	ok(Cards.found_text("нет-такой-карты") == "", "колода: незнакомая находка ничего не печатает")
	ok(Cards.found_text(a).contains(str(Cards.card_of(a)["title"])), "колода: находка называет карту")


# ================================================================= хранение

func _check_save() -> void:
	Cards.save_owned(Cards.empty())
	ok(Cards.count(Cards.load_owned()) == 0, "колода: пустое сохранение читается пустым")
	var night := _full_set("night")
	Cards.save_owned(night)
	var back := Cards.load_owned()
	ok(Cards.count(back) == 5, "колода: сохранение держит собранный набор (%d)" % Cards.count(back))
	ok(Cards.is_full(back, "night") and not Cards.is_full(back, "meadow"), "колода: сохранился ровно нужный набор")
	Cards.save_owned(Cards.empty())
	var first := Cards.take(777)
	ok(Cards.in_catalog(first), "колода: находка за главу есть в каталоге (%s)" % first)
	ok(Cards.count(Cards.load_owned()) == 1, "колода: находка сразу легла в сохранение")
	var second := Cards.take(777)
	ok(second != first and Cards.count(Cards.load_owned()) == 2, "колода: вторая находка — другая карта (%s → %s)" % [first, second])
	Cards.save_owned(_full_deck())
	ok(Cards.take(1) == "", "колода: с полной колодой находок больше нет")
	ok(Cards.count(Cards.load_owned()) == 15, "колода: полная колода так и осталась полной")


# ================================================================= в самой игре

func _check_game() -> void:
	var g = load("res://scripts/game.gd").new()
	add_child(g)
	await get_tree().process_frame
	# колючие сказки прибавляют росы на старте обороны
	Cards.save_owned(_full_set("thorn"))
	g.new_run("guard")
	g.start_chapter(Modes.GUARD_CHAPTER)
	ok(g.is_guard(), "колода в игре: стража запустилась")
	ok(g.guard_dew == Guard.START_DEW + Cards.BONUS_DEW,
		"колода в игре: колючие сказки дали росу (%d вместо %d)" % [g.guard_dew, Guard.START_DEW])
	# луговые сказки прибавляют очков
	g.new_run("story")
	g.start_chapter(0)
	g.combo = 0
	g.card_bonus = 0.0
	var base: int = g.add_score(1000, g.px, g.py, Color.WHITE)
	g.new_run("story")
	g.start_chapter(0)
	g.combo = 0
	g.card_bonus = Cards.score_bonus(_full_set("meadow"))
	var boosted: int = g.add_score(1000, g.px, g.py, Color.WHITE)
	ok(boosted > base, "колода в игре: луговые сказки прибавили очков (%d → %d)" % [base, boosted])
	ok(boosted - base <= 40, "колода в игре: прибавка маленькая (+%d к %d)" % [boosted - base, base])
