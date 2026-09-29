class_name Shop
## Лавка фей: улучшения за пыльцу или за рекламу (порт src/game/shop.ts).

const SETTINGS := "user://settings.cfg"
const SCORE_PER_POLLEN := 40.0

const UPGRADES: Array[Dictionary] = [
	{"id": "heart", "icon": "♥", "title": "Крепкое сердце", "desc": "+1 сердце в начале забега (кроме «Одного пера»).", "max": 2, "prices": [350, 800]},
	{"id": "speed", "icon": "➶", "title": "Быстрые крылья", "desc": "Полёт быстрее на 7% за уровень.", "max": 3, "prices": [150, 300, 550]},
	{"id": "dash", "icon": "⚡", "title": "Лёгкий рывок", "desc": "Рывок перезаряжается на 12% быстрее.", "max": 3, "prices": [150, 320, 560]},
	{"id": "magnet", "icon": "✧", "title": "Магнит", "desc": "Притягивает пыльцу, росу, звёзды, снежинки и солнца.", "max": 3, "prices": [120, 260, 450]},
	{"id": "shield", "icon": "❀", "title": "Щит из лепестков", "desc": "В начале каждой главы — щит на один удар (кроме «Одного пера»).", "max": 1, "prices": [500]},
	{"id": "bag", "icon": "✿", "title": "Волшебный мешочек", "desc": "+25% пыльцы за каждый забег.", "max": 3, "prices": [200, 420, 750]},
]


static func empty() -> Dictionary:
	return {"heart": 0, "speed": 0, "dash": 0, "magnet": 0, "shield": 0, "bag": 0}


static func load_upgrades() -> Dictionary:
	var u := empty()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		for d in UPGRADES:
			u[d["id"]] = clampi(int(cfg.get_value("shop", d["id"], 0)), 0, int(d["max"]))
	return u


static func save_upgrades(u: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	for k in u.keys():
		cfg.set_value("shop", k, u[k])
	cfg.save(SETTINGS)


static func load_pollen() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return maxi(0, int(cfg.get_value("shop", "pollen", 0)))
	return 0


static func save_pollen(n: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("shop", "pollen", maxi(0, n))
	cfg.save(SETTINGS)


## цена следующего уровня или -1, если уже максимум
static func price_of(d: Dictionary, level: int) -> int:
	return -1 if level >= int(d["max"]) else int(d["prices"][level])


static func pollen_for(score_delta: int, bag: int) -> int:
	return int(floor(maxf(0.0, score_delta) / SCORE_PER_POLLEN * (1.0 + 0.25 * bag)))
