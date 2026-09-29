class_name Skins
## Наряды фей — косметика из «Лавки фей»: перекрашивают платье, крылья и блёстки
## героини, не меняя механику. Часть нарядов переливается (rainbow).

const LIST: Array[Dictionary] = [
	{
		"id": "classic", "icon": "❀", "title": "Родные краски",
		"desc": "Классический наряд феи — цвета своей главы.", "price": 0,
	},
	{
		"id": "moon", "icon": "☾", "title": "Лунный шёлк",
		"desc": "Платье цвета ночного неба, крылья — лунный свет.",
		"price": 400, "main": "#b9a8e8", "wing": "#efeaff", "accent": "#f5e27a",
	},
	{
		"id": "gold", "icon": "✹", "title": "Золотая пыльца",
		"desc": "Тёплое золото рассвета — заметна издалека.",
		"price": 650, "main": "#e8b23a", "wing": "#ffe89a", "accent": "#fff6cf",
	},
	{
		"id": "emerald", "icon": "❁", "title": "Изумрудный лес",
		"desc": "Зелёный наряд хранительницы сада.",
		"price": 650, "main": "#3f8f5a", "wing": "#b8ecc8", "accent": "#f2c230",
	},
	{
		"id": "ink", "icon": "✒", "title": "Чернильный плащ",
		"desc": "Тёмный наряд и алые искры — почти как у Короля Теней.",
		"price": 900, "main": "#3a3550", "wing": "#b0a8c8", "accent": "#e8504a",
	},
	{
		"id": "rainbow", "icon": "✺", "title": "Радужные крылья",
		"desc": "Крылья переливаются всеми красками радуги.",
		"price": 1200, "main": "#f07a3a", "wing": "#ffe1a8", "accent": "#6fd0ff", "rainbow": true,
	},
]


static func count() -> int:
	return LIST.size()


static func def(id: String) -> Dictionary:
	for d in LIST:
		if d["id"] == id:
			return d
	return LIST[0]


static func title(id: String) -> String:
	return str(def(id)["title"])


static func price(id: String) -> int:
	return int(def(id)["price"])


static func is_rainbow(id: String) -> bool:
	return bool(def(id).get("rainbow", false))


## Цвета-переопределения для отрисовки феи. Пустой словарь — родные цвета главы.
static func look(id: String, t: float) -> Dictionary:
	var d := def(id)
	var out := {}
	for k in ["main", "wing", "accent"]:
		if d.has(k):
			out[k] = Color(str(d[k]))
	if is_rainbow(id):
		out["wing"] = Color.from_hsv(fmod(t * 0.11, 1.0), 0.45, 1.0)
		out["accent"] = Color.from_hsv(fmod(t * 0.11 + 0.4, 1.0), 0.55, 1.0)
	return out


## Превью наряда в лавке: словарь-глава с подменёнными цветами
static func preview(id: String, chapter: Dictionary, t: float = 0.0) -> Dictionary:
	var c := chapter.duplicate()
	for k in look(id, t).keys():
		c[k] = look(id, t)[k]
	return c
