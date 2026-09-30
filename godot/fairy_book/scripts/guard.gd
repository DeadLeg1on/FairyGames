class_name Guard
## «Звёздная стража» — данные режима tower defense: тропа, башни и волны.
##
## Вся логика боя живёт в scripts/game.gd (_update_guard), а здесь только
## табличные данные и чистая геометрия тропы, чтобы их можно было проверить
## тестом без графики и без запуска режима.

## сколько волн нужно отбить
const WAVES := 10
## прочность сердца поляны
const HEART_HP := 10
## росы на старте — хватает на две башни-василька
const START_DEW := 90
## пауза между волнами (секунды): в это время строят и улучшают
const WAVE_BREAK := 6.0
## доплата росой за каждую отбитую волну
const WAVE_BONUS := 22

## тропа в долях поля: x — от ширины, y — от игровой области
const PATH: Array[Vector2] = [
	Vector2(-0.06, 0.22), Vector2(0.20, 0.22), Vector2(0.20, 0.72),
	Vector2(0.46, 0.72), Vector2(0.46, 0.16), Vector2(0.70, 0.16),
	Vector2(0.70, 0.58), Vector2(0.90, 0.58),
]

## башни-цветы: у каждой своя роль
## rate = 0 — не стреляет, а держит ауру (светлячок замедляет тени)
const TOWERS: Array[Dictionary] = [
	{
		"id": "cornflower", "icon": "❁", "name": "Василёк", "cost": 40,
		"range": 132.0, "rate": 0.7, "dmg": 1, "col": Color("#7aa7d8"),
		"desc": "Быстро стреляет лепестками по одной тени. Дёшев и везде уместен.",
	},
	{
		"id": "glow", "icon": "✺", "name": "Светлячок", "cost": 55,
		"range": 150.0, "rate": 0.0, "dmg": 0, "slow": 0.45, "col": Color("#f2c230"),
		"desc": "Не бьёт, но держит тени в кругу света: они идут вдвое медленнее.",
	},
	{
		"id": "thorn", "icon": "❃", "name": "Шиповник", "cost": 80,
		"range": 114.0, "rate": 1.6, "dmg": 2, "splash": 56.0, "col": Color("#d8708a"),
		"desc": "Бьёт редко, зато шипами по площади — хорошо против толпы.",
	},
]

## максимум улучшений башни
const MAX_LEVEL := 3


static func count() -> int:
	return TOWERS.size()


## описание башни как есть — его читают каждый кадр в бою, поэтому без перевода
static func tower(i: int) -> Dictionary:
	return TOWERS[clampi(i, 0, TOWERS.size() - 1)]


## то же описание с переведёнными строками — только для надписей и кнопок
static func tower_text(i: int) -> Dictionary:
	return I18n.tree(tower(i))


## строка башни под текущий язык (для HUD и подсказок)
static func stat(i: int, key: String, dflt: float = 0.0) -> float:
	return float(tower(i).get(key, dflt))


## тропа в пикселях: top/bottom — границы игровой области по вертикали
static func path(W: float, top: float, bottom: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in PATH:
		out.append(Vector2(p.x * W, top + p.y * (bottom - top)))
	return out


## длина тропы в пикселях
static func path_len(pts: Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += (pts[i + 1] - pts[i]).length()
	return total


## точка тропы на расстоянии dist от начала (дальше конца — последняя точка)
static func at(pts: Array, dist: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var left := dist
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := (b - a).length()
		if left <= seg or i == pts.size() - 2:
			if seg < 0.001:
				return a
			return a + (b - a) * clampf(left / seg, 0.0, 1.0)
		left -= seg
	return pts[pts.size() - 1]


## кратчайшее расстояние от точки до тропы — для проверки, не на тропе ли башня
static func dist_to_path(pts: Array, pos: Vector2) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var k := 0.0 if l2 < 0.0001 else clampf((pos - a).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, (a + ab * k - pos).length())
	return best


## сколько росы стоит улучшение башни до следующего уровня
static func upgrade_cost(type: int, level: int) -> int:
	if level >= MAX_LEVEL:
		return -1
	var base := int(tower(type).get("cost", 40))
	return int(round(base * (0.9 + 0.5 * level)))


## состав волны: чем дальше, тем разнообразнее, каждая пятая — с громадной тенью
static func wave_table(n: int) -> Array:
	var w := clampi(n, 1, WAVES)
	var out: Array = []
	for i in 3 + w:
		out.append("foe")
	if w >= 4:
		for i in (w - 1) / 3:
			out.append("fleet")
		for i in w / 4:
			out.append("brute")
	if w % 5 == 0:
		out.append("wight")
	return out


## интервал появления теней внутри волны
static func spawn_gap(n: int) -> float:
	return maxf(0.45, 1.15 - clampi(n, 1, WAVES) * 0.055)


static func enemy_hp(kind: String, n: int) -> int:
	var w := clampi(n, 1, WAVES)
	match kind:
		"fleet":
			return 1 + int(w * 0.6)
		"brute":
			return 4 + w * 2
		"wight":
			return 16 + w * 6
		_:
			return 2 + w


static func enemy_speed(kind: String, n: int) -> float:
	var w := clampi(n, 1, WAVES)
	match kind:
		"fleet":
			return 92.0 + w * 3.5
		"brute":
			return 40.0 + w * 1.5
		"wight":
			return 34.0 + w
		_:
			return 58.0 + w * 3.0


static func enemy_radius(kind: String) -> float:
	match kind:
		"fleet":
			return 10.0
		"brute":
			return 17.0
		"wight":
			return 26.0
		_:
			return 13.0


## сколько урона сердцу поляны нанесёт прорвавшаяся тень
static func enemy_bite(kind: String) -> int:
	match kind:
		"brute":
			return 2
		"wight":
			return 4
		_:
			return 1


static func enemy_dew(kind: String) -> int:
	match kind:
		"fleet":
			return 2
		"brute":
			return 5
		"wight":
			return 14
		_:
			return 3


static func enemy_score(kind: String) -> int:
	match kind:
		"fleet":
			return 20
		"brute":
			return 45
		"wight":
			return 160
		_:
			return 25


## названия теней для подсказок и итогов
static func enemy_name(kind: String) -> String:
	match kind:
		"fleet":
			return I18n.t("Быстрая тень")
		"brute":
			return I18n.t("Толстая тень")
		"wight":
			return I18n.t("Громадная тень")
		_:
			return I18n.t("Тень")
