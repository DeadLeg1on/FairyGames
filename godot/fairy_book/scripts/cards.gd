class_name Cards
## Колода сказок: карты выпадают за пройденные главы, а собранные наборы
## дают маленькие постоянные бонусы — чуть больше очков, пыльцы и росы.
## Хранится там же, где и прочая «мета»: user://settings.cfg.

const SETTINGS := "user://settings.cfg"
const SECTION := "cards"

## насколько набор усиливает игру
const BONUS_SCORE := 0.02
const BONUS_POLLEN := 0.02
const BONUS_DEW := 15

## три набора по пять карт: «kind» решает, какой бонус даёт собранный набор
const SETS: Array[Dictionary] = [
	{"id": "meadow", "icon": "❀", "title": "Луговые сказки", "kind": "score",
		"desc": "Пять карт луга: +2% очков за каждый забег.", "bonus": "+2% очков"},
	{"id": "night", "icon": "☾", "title": "Ночные сказки", "kind": "pollen",
		"desc": "Пять карт ночи: +2% пыльцы с очков.", "bonus": "+2% пыльцы"},
	{"id": "thorn", "icon": "❆", "title": "Колючие сказки", "kind": "dew",
		"desc": "Пять карт колючек: +15 росы на старте «Звёздной стражи».", "bonus": "+15 росы в страже"},
]

const CARDS: Array[Dictionary] = [
	{"id": "lily", "set": "meadow", "icon": "✿", "title": "Лили",
		"desc": "Цветочная фея, рождённая из первой капли росы."},
	{"id": "bud", "set": "meadow", "icon": "❁", "title": "Бутон",
		"desc": "Три пылинки — и он раскроется."},
	{"id": "clover", "set": "meadow", "icon": "☘", "title": "Клевер удачи",
		"desc": "Четыре листа, и ни один не лишний."},
	{"id": "bee", "set": "meadow", "icon": "✺", "title": "Пчела-подружка",
		"desc": "Помогает носить пыльцу и ворчит на ос."},
	{"id": "dragonfly", "set": "meadow", "icon": "➶", "title": "Стрекоза",
		"desc": "Первая, кто облетел весь луг."},
	{"id": "star", "set": "night", "icon": "★", "title": "Звёздная пыль",
		"desc": "Сыплется туда, где фея пролетела ночью."},
	{"id": "firefly", "set": "night", "icon": "✧", "title": "Светлячок",
		"desc": "Фонарик, который не боится темноты."},
	{"id": "moon", "set": "night", "icon": "◉", "title": "Луна над лугом",
		"desc": "Смотрит на всех сразу и никому не завидует."},
	{"id": "lullaby", "set": "night", "icon": "♬", "title": "Колыбельная",
		"desc": "Феи поют её цветам, чтобы те спали крепче."},
	{"id": "spark", "set": "night", "icon": "✦", "title": "Искорка сна",
		"desc": "Забирается в бутон и остаётся там до утра."},
	{"id": "wasp", "set": "thorn", "icon": "❂", "title": "Оса Королевы",
		"desc": "Та самая, что украла пыльцу и закрыла луг."},
	{"id": "thorn", "set": "thorn", "icon": "❃", "title": "Шиповник",
		"desc": "Колючий, но цветёт раньше всех."},
	{"id": "net", "set": "thorn", "icon": "❖", "title": "Сеть в траве",
		"desc": "Паучок плетёт её для добрых фей — те пролезают."},
	{"id": "nettle", "set": "thorn", "icon": "⚡", "title": "Крапива",
		"desc": "Жжётся, зато лечит, если попросить вежливо."},
	{"id": "queen", "set": "thorn", "icon": "❧", "title": "Королева Колючек",
		"desc": "Сердится не со зла: просто ей не спели колыбельную."},
]


# ------------------------------------------------------------------ каталог

## наборы с переводом под текущий язык
static func sets() -> Array:
	return I18n.tree(SETS)


## карты с переводом под текущий язык
static func cards() -> Array:
	return I18n.tree(CARDS)


static func ids() -> Array[String]:
	var out: Array[String] = []
	for d in CARDS:
		out.append(str(d["id"]))
	return out


## есть ли такая карта в каталоге
static func in_catalog(id: String) -> bool:
	return ids().has(id)


static func card_of(id: String) -> Dictionary:
	for d in CARDS:
		if str(d["id"]) == id:
			return d
	return {}


static func set_of(id: String) -> Dictionary:
	var c := card_of(id)
	if c.is_empty():
		return {}
	for s in SETS:
		if str(s["id"]) == str(c["set"]):
			return s
	return {}


## карты одного набора
static func cards_of(set_id: String) -> Array:
	var out: Array = []
	for d in CARDS:
		if str(d["set"]) == set_id:
			out.append(d)
	return out


# ------------------------------------------------------------------ хранение

## пустая колода: все карты ещё не собраны
static func empty() -> Dictionary:
	var o := {}
	for d in CARDS:
		o[str(d["id"])] = false
	return o


static func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg


static func load_owned() -> Dictionary:
	var o := empty()
	var cfg := _load_cfg()
	for d in CARDS:
		var id: String = str(d["id"])
		o[id] = bool(cfg.get_value(SECTION, id, false))
	return o


static func save_owned(owned: Dictionary) -> void:
	var cfg := _load_cfg()
	for d in CARDS:
		var id: String = str(d["id"])
		cfg.set_value(SECTION, id, bool(owned.get(id, false)))
	cfg.save(SETTINGS)


# ------------------------------------------------------------------ прогресс

static func count(owned: Dictionary) -> int:
	var n := 0
	for d in CARDS:
		if bool(owned.get(str(d["id"]), false)):
			n += 1
	return n


static func set_count(owned: Dictionary, set_id: String) -> int:
	var n := 0
	for d in cards_of(set_id):
		if bool(owned.get(str(d["id"]), false)):
			n += 1
	return n


static func is_full(owned: Dictionary, set_id: String) -> bool:
	var total := cards_of(set_id)
	return not total.is_empty() and set_count(owned, set_id) == total.size()


static func full_sets(owned: Dictionary) -> int:
	var n := 0
	for s in SETS:
		if is_full(owned, str(s["id"])):
			n += 1
	return n


## чего ещё не хватает (в порядке каталога)
static func missing(owned: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for d in CARDS:
		if not bool(owned.get(str(d["id"]), false)):
			out.append(str(d["id"]))
	return out


# ------------------------------------------------------------------ бонусы

static func score_bonus(owned: Dictionary) -> float:
	var b := 0.0
	for s in SETS:
		if str(s["kind"]) == "score" and is_full(owned, str(s["id"])):
			b += BONUS_SCORE
	return b


static func pollen_bonus(owned: Dictionary) -> float:
	var b := 0.0
	for s in SETS:
		if str(s["kind"]) == "pollen" and is_full(owned, str(s["id"])):
			b += BONUS_POLLEN
	return b


static func dew_bonus(owned: Dictionary) -> int:
	var b := 0
	for s in SETS:
		if str(s["kind"]) == "dew" and is_full(owned, str(s["id"])):
			b += BONUS_DEW
	return b


## одна строка про все собранные бонусы (для альбома и подсказок)
static func bonus_text(owned: Dictionary) -> String:
	var parts: Array[String] = []
	for s in SETS:
		if is_full(owned, str(s["id"])):
			parts.append(str(s["icon"]) + " " + str(s["bonus"]))
	if parts.is_empty():
		return I18n.t("Наборы ещё не собраны — бонусов пока нет")
	return I18n.t("Собрано") + ": " + " · ".join(PackedStringArray(parts))


# ------------------------------------------------------------------ выпадение

## какую карту вытянуть: детерминированно от зерна, только из недостающих
static func roll(owned: Dictionary, seed_int: int) -> String:
	var left := missing(owned)
	if left.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_int
	return str(left[rng.randi_range(0, left.size() - 1)])


## копия колоды с добавленной картой (незнакомые id игнорируются)
static func grant(owned: Dictionary, id: String) -> Dictionary:
	var o: Dictionary = owned.duplicate()
	if not in_catalog(id):
		return o
	o[id] = true
	return o


## вытянуть карту и сразу запомнить: возвращает id новой карты или ""
static func take(seed_int: int) -> String:
	var owned := load_owned()
	var id := roll(owned, seed_int)
	if id == "":
		return ""
	save_owned(grant(owned, id))
	return id


## описание вытянутой карты для экрана («Новая карта: ✿ Лили»)
static func found_text(id: String) -> String:
	if id == "":
		return ""
	var c := card_of(id)
	if c.is_empty():
		return ""
	return I18n.t("Новая карта: %s %s") % [str(c["icon"]), str(c["title"])]
