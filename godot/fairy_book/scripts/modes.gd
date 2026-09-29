class_name Modes
## Каталог игровых режимов: данные, правила доступа и суточный вызов.
## Порядок LIST — порядок кнопок в меню.
##
## pick  — режим начинается с выбора главы (иначе глава задаётся режимом);
## story — все открытые главы подряд с +1 ♥ после каждой;
## goal  — у главы есть цель, при её выполнении глава считается пройденной;
## timer — «Гонка»: обратный отсчёт на главу;
## wave  — «Марафон»: волны врагов без цели;
## boss  — «Дуэль»: только Король Теней, волна за волной;
## daily — «Ежедневный вызов»: одна попытка в сутки (+ за рекламу);
## zen   — «Тихий полёт»: без врагов и урона;
## unlock — сколько глав должно быть открыто, чтобы режим стал доступен.

const LIST: Array[Dictionary] = [
	{
		"id": "story", "icon": "✎", "title": "Сказка",
		"desc": "Все девять глав подряд. После каждой главы +1 ♥.",
		"short": "Сказка", "hud": "", "col": "Глав",
		"pick": false, "story": true, "goal": true, "unlock": 0,
	},
	{
		"id": "chapter", "icon": "❧", "title": "Одна глава",
		"desc": "Любая открытая глава отдельно — побей свой рекорд.",
		"short": "Одна глава", "hud": "Одна глава", "col": "Глава",
		"pick": true, "story": false, "goal": true, "unlock": 0,
	},
	{
		"id": "endless", "icon": "∞", "title": "Бесконечная охота",
		"desc": "Глава без конца: враги всё злее, каждые 10 целей +1 ♥.",
		"short": "Охота", "hud": "∞ Бесконечная охота", "col": "Глава",
		"pick": true, "story": false, "goal": false, "unlock": 0,
	},
	{
		"id": "hard", "icon": "✧", "title": "Одно перо",
		"desc": "Сказка с одним сердцем и без лечения. Очки ×2.",
		"short": "Одно перо", "hud": "Одно перо ×2", "col": "Глав",
		"pick": false, "story": true, "goal": true, "unlock": 0,
	},
	{
		"id": "race", "icon": "⏱", "title": "Гонка со временем",
		"desc": "Одна глава на секундомере. Успей выполнить задание до нуля!",
		"short": "Гонка", "hud": "⏱ Гонка со временем", "col": "Глава",
		"pick": true, "story": false, "goal": true, "unlock": 2, "timer": true,
	},
	{
		"id": "marathon", "icon": "◷", "title": "Марафон фей",
		"desc": "Волны врагов одна за другой. Каждые 3 волны — сердце. Держись!",
		"short": "Марафон", "hud": "◷ Марафон фей", "col": "Волна",
		"pick": true, "story": false, "goal": false, "unlock": 3, "wave": true,
	},
	{
		"id": "duel", "icon": "❂", "title": "Дуэль с Королём Теней",
		"desc": "Только босс: заряжайся осколками и бей рывком. Волна за волной!",
		"short": "Дуэль", "hud": "❂ Дуэль с Королём Теней", "col": "Босс",
		"pick": false, "story": false, "goal": false, "unlock": 5, "boss": true,
	},
	{
		"id": "daily", "icon": "★", "title": "Ежедневный вызов",
		"desc": "Одна попытка в сутки: глава дня по жребию, очки и пыльца ×2.",
		"short": "Вызов дня", "hud": "★ Ежедневный вызов", "col": "Глава",
		"pick": false, "story": false, "goal": true, "unlock": 2, "daily": true,
	},
	{
		"id": "idle", "icon": "♨", "title": "Отель фей",
		"desc": "Idle-глава: принимай фей, подбирай им номера и процедуры, расширяй отель. Пыльца копится даже без тебя.",
		"short": "Отель", "hud": "♨ Отель фей", "col": "Гостей",
		"pick": false, "story": false, "goal": false, "unlock": 2, "hotel": true,
	},
	{
		"id": "zen", "icon": "☀", "title": "Тихий полёт",
		"desc": "Ни врагов, ни урона — просто собирай и любуйся. Для самых маленьких.",
		"short": "Тихий полёт", "hud": "☀ Тихий полёт", "col": "Глава",
		"pick": true, "story": false, "goal": true, "unlock": 0, "zen": true,
	},
]

## главы, которые нельзя выбрать в некоторых режимах (звёздная — только боссы)
const NO_BOSS_CHAPTER := 4


## правила дня: все честно работают — очки ×2 (game.score_mult),
## пыльца ×2 (main._record) и стартовый щит (game.start_shield)
const RULES: Array[String] = [
	"Очки за забег ×2",
	"Пыльца за забег ×2",
	"Хрустальный щит на старте",
]


static func count() -> int:
	return LIST.size()


## каталог режимов с переводом под текущий язык (кнопки, карточки, HUD)
static func list() -> Array:
	return I18n.tree(LIST)


static func def(id: String) -> Dictionary:
	for d in LIST:
		if d["id"] == id:
			var hit: Dictionary = I18n.tree(d)
			return hit
	var first: Dictionary = I18n.tree(LIST[0])
	return first


static func has(id: String) -> bool:
	for d in LIST:
		if d["id"] == id:
			return true
	return false


static func flag(id: String, key: String) -> bool:
	return bool(def(id).get(key, false))


## режим начинается с выбора главы
static func pick(id: String) -> bool:
	return flag(id, "pick")


## все главы подряд
static func story(id: String) -> bool:
	return flag(id, "story")


## глава считается пройденной при выполнении цели
static func goal(id: String) -> bool:
	return flag(id, "goal")


static func hud_label(id: String) -> String:
	return str(def(id).get("hud", ""))


static func col_label(id: String) -> String:
	return str(def(id).get("col", "Очки"))


## режим-отель: не полёт, а отдельный экран управления
static func hotel(id: String) -> bool:
	return flag(id, "hotel")


## глава запрещена в режиме (например, звёздная в «Тихом полёте» и «Марафоне»)
static func chapter_blocked(id: String, chapter: int) -> bool:
	if chapter != NO_BOSS_CHAPTER:
		return false
	return flag(id, "zen") or flag(id, "wave")


static func unlock_text(d: Dictionary) -> String:
	var n := int(d.get("unlock", 0))
	return "" if n <= 1 else "нужно открыть глав: %d" % n


## ключ сегодняшнего дня для «Ежедневного вызова»
static func daily_key() -> String:
	return Time.get_date_string_from_system()


## глава дня: одинаковая для всех в течение суток
static func daily_chapter(unlocked: int) -> int:
	var n := clampi(unlocked, 1, Chapters.story_count())
	return absi(hash("fairy-daily-" + daily_key())) % n


## номер правила дня (0..2) — от него зависят бонусы «Ежедневного вызова»
static func daily_rule_id() -> int:
	return absi(hash("fairy-rule-" + daily_key())) % RULES.size()


## короткое правило дня, чтобы игрок понимал, какие бонусы его ждут
static func daily_rule() -> String:
	return str(I18n.tree(RULES)[daily_rule_id()])

