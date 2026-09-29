class_name Shop
## Лавка фей: улучшения за пыльцу или за рекламу (порт src/game/shop.ts).
## Здесь же хранится вся «мета»: наряды, сад фей, ежедневный вызов и
## перезарядки рекламных наград — всё в user://settings.cfg.

const SETTINGS := "user://settings.cfg"
const SCORE_PER_POLLEN := 40.0

const UPGRADES: Array[Dictionary] = [
	{"id": "heart", "icon": "♥", "title": "Крепкое сердце", "desc": "+1 сердце в начале забега (кроме «Одного пера»).", "max": 2, "prices": [350, 800]},
	{"id": "speed", "icon": "➶", "title": "Быстрые крылья", "desc": "Полёт быстрее на 7% за уровень.", "max": 3, "prices": [150, 300, 550]},
	{"id": "dash", "icon": "⚡", "title": "Лёгкий рывок", "desc": "Рывок перезаряжается на 12% быстрее.", "max": 3, "prices": [150, 320, 560]},
	{"id": "magnet", "icon": "✧", "title": "Магнит", "desc": "Притягивает пыльцу, росу, звёзды, снежинки и солнца.", "max": 3, "prices": [120, 260, 450]},
	{"id": "shield", "icon": "❀", "title": "Щит из лепестков", "desc": "В начале каждой главы — щит на один удар (кроме «Одного пера»).", "max": 1, "prices": [500]},
	{"id": "bag", "icon": "✿", "title": "Волшебный мешочек", "desc": "+25% пыльцы за каждый забег.", "max": 3, "prices": [200, 420, 750]},
	{"id": "luck", "icon": "☘", "title": "Клевер удачи", "desc": "+5% очков за каждый уровень.", "max": 3, "prices": [250, 500, 900]},
	{"id": "comet", "icon": "✹", "title": "Хвост кометы", "desc": "Шлейф рывка сбивает врагов ещё 0.6 с (2-й ур. — 1.2 с).", "max": 2, "prices": [400, 800]},
	{"id": "clock", "icon": "◷", "title": "Песочные часы", "desc": "+12% времени в «Гонке со временем» и на волну в «Марафоне».", "max": 3, "prices": [300, 600, 1000]},
	{"id": "amulet", "icon": "❂", "title": "Хрустальный амулет", "desc": "Один раз за забег спасает от гибели, оставляя 1 сердце.", "max": 1, "prices": [900]},
	{"id": "bell", "icon": "◉", "title": "Колокольчик", "desc": "Каждые 10 целей дают +1 ♥ (2-й ур. — каждые 7).", "max": 2, "prices": [450, 850]},
	{"id": "garden", "icon": "☀", "title": "Сад фей", "desc": "Копит пыльцу, пока ты не играешь. Собирается в лавке.", "max": 3, "prices": [350, 700, 1200]},
]

## сколько пыльцы в час копит сад и сколько можно накопить
const GARDEN_RATE := [6, 12, 20]
const GARDEN_CAP := [40, 90, 160]


static func empty() -> Dictionary:
	var u := {}
	for d in UPGRADES:
		u[d["id"]] = 0
	return u


static func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg


static func load_upgrades() -> Dictionary:
	var u := empty()
	var cfg := _load_cfg()
	for d in UPGRADES:
		u[d["id"]] = clampi(int(cfg.get_value("shop", d["id"], 0)), 0, int(d["max"]))
	return u


static func save_upgrades(u: Dictionary) -> void:
	var cfg := _load_cfg()
	for k in u.keys():
		cfg.set_value("shop", k, u[k])
	cfg.save(SETTINGS)


static func load_pollen() -> int:
	return maxi(0, int(_load_cfg().get_value("shop", "pollen", 0)))


static func save_pollen(n: int) -> void:
	var cfg := _load_cfg()
	cfg.set_value("shop", "pollen", maxi(0, n))
	cfg.save(SETTINGS)


## цена следующего уровня или -1, если уже максимум
static func price_of(d: Dictionary, level: int) -> int:
	return -1 if level >= int(d["max"]) else int(d["prices"][level])


static func pollen_for(score_delta: int, bag: int) -> int:
	return int(floor(maxf(0.0, score_delta) / SCORE_PER_POLLEN * (1.0 + 0.25 * bag)))


# ------------------------------------------------------------------ наряды

## какие наряды уже куплены (у «Родных красок» цена 0 — он есть всегда)
static func load_skins() -> Dictionary:
	var owned := {}
	var cfg := _load_cfg()
	for d in Skins.LIST:
		var id: String = d["id"]
		owned[id] = true if int(d["price"]) <= 0 else bool(cfg.get_value("skins", id, false))
	return owned


static func save_skins(owned: Dictionary) -> void:
	var cfg := _load_cfg()
	for k in owned.keys():
		cfg.set_value("skins", k, bool(owned[k]))
	cfg.save(SETTINGS)


static func load_skin() -> String:
	var id := str(_load_cfg().get_value("skins", "wear", "classic"))
	return id if Skins.def(id)["id"] == id else "classic"


static func save_skin(id: String) -> void:
	var cfg := _load_cfg()
	cfg.set_value("skins", "wear", id)
	cfg.save(SETTINGS)


# ------------------------------------------------------------------ сад фей

## {last: unix-время последнего сбора, pending: накопленная пыльца}
static func load_garden() -> Dictionary:
	var cfg := _load_cfg()
	return {
		"last": float(cfg.get_value("garden", "last", 0.0)),
		"pending": maxi(0, int(cfg.get_value("garden", "pending", 0))),
	}


static func save_garden(last: float, pending: int) -> void:
	var cfg := _load_cfg()
	cfg.set_value("garden", "last", last)
	cfg.set_value("garden", "pending", maxi(0, pending))
	cfg.save(SETTINGS)


## накопление с последнего визита: сколько пыльцы уже лежит в саду
static func garden_now(level: int, garden: Dictionary) -> int:
	if level <= 0:
		return 0
	var lvl := clampi(level, 1, GARDEN_RATE.size()) - 1
	var last := float(garden.get("last", 0.0))
	var now := Time.get_unix_time_from_system()
	if last <= 0.0:
		return int(garden.get("pending", 0))
	var hours := maxf(0.0, (now - last) / 3600.0)
	var cap := GARDEN_CAP[lvl]
	return clampi(int(garden.get("pending", 0)) + int(floor(hours * GARDEN_RATE[lvl])), 0, cap)


static func garden_cap(level: int) -> int:
	return GARDEN_CAP[clampi(level, 1, GARDEN_CAP.size()) - 1] if level > 0 else 0


# ------------------------------------------------------------------ прочее

## перезарядка рекламной награды: сколько секунд осталось (0 — можно брать)
static func cooldown_left(key: String, seconds: float) -> float:
	var last := float(_load_cfg().get_value("ads", key + "_ts", 0.0))
	return maxf(0.0, seconds - (Time.get_unix_time_from_system() - last))


static func touch_cooldown(key: String) -> void:
	var cfg := _load_cfg()
	cfg.set_value("ads", key + "_ts", Time.get_unix_time_from_system())
	cfg.save(SETTINGS)


static func add_counter(key: String, delta: int = 1) -> int:
	var cfg := _load_cfg()
	var v := int(cfg.get_value("ads", key, 0)) + delta
	cfg.set_value("ads", key, v)
	cfg.save(SETTINGS)
	return v


static func counter(key: String) -> int:
	return int(_load_cfg().get_value("ads", key, 0))


## когда игрок последний раз был в игре (для «рекламы при возвращении»)
static func last_seen() -> float:
	return float(_load_cfg().get_value("ads", "last_seen", 0.0))


static func mark_seen() -> void:
	var cfg := _load_cfg()
	cfg.set_value("ads", "last_seen", Time.get_unix_time_from_system())
	cfg.save(SETTINGS)


## состояние «Ежедневного вызова»
static func load_daily() -> Dictionary:
	var cfg := _load_cfg()
	return {
		"date": str(cfg.get_value("daily", "date", "")),
		"attempts": int(cfg.get_value("daily", "attempts", 0)),
		"streak": int(cfg.get_value("daily", "streak", 0)),
		"best": int(cfg.get_value("daily", "best", 0)),
	}


static func save_daily(d: Dictionary) -> void:
	var cfg := _load_cfg()
	for k in d.keys():
		cfg.set_value("daily", k, d[k])
	cfg.save(SETTINGS)


## сколько попыток ещё осталось сегодня (0 или 1) без рекламы
static func daily_attempts_left() -> int:
	var d := load_daily()
	if str(d["date"]) != Modes.daily_key():
		return 1
	return 1 if int(d["attempts"]) <= 0 else 0


static func daily_used_ad_attempt() -> bool:
	var d := load_daily()
	if str(d["date"]) != Modes.daily_key():
		return false
	return int(d["attempts"]) >= 2


## отметить попытку сегодня (первая попытка дня продлевает серию)
static func daily_use(via_ad: bool = false) -> void:
	var d := load_daily()
	var today := Modes.daily_key()
	var streak := int(d["streak"])
	if str(d["date"]) != today:
		streak = streak + 1 if _days_between(str(d["date"]), today) == 1 else 1
		d["attempts"] = 0
	if via_ad:
		streak = maxi(streak, 1)
	d["attempts"] = int(d["attempts"]) + 1
	d["date"] = today
	d["streak"] = streak
	save_daily(d)


static func _days_between(a: String, b: String) -> int:
	if a == "" or b == "":
		return 999
	return absi(_day_number(a) - _day_number(b))


static func _day_number(s: String) -> int:
	var parts := s.split("-")
	if parts.size() != 3:
		return 0
	return int(Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0,
	})) / 86400


static func daily_best(score: int) -> void:
	var d := load_daily()
	d["best"] = maxi(int(d["best"]), score)
	save_daily(d)
