class_name Hotel
## «Отель фей» — idle-глава: феи прилетают в отель, их надо расселить по номерам
## подходящего окружения, отправить на процедуры и за это получить пыльцу и отзывы.
##
## Модель данных (всё хранится в user://settings.cfg, секция hotel, ключ state):
##   rooms   — номера: вид окружения, уровень уюта, число мест и гости внутри;
##   queue   — очередь на ресепшене: кто прилетел и сколько ещё подождёт;
##   reviews — последние отзывы (скользящее окно, из них считается рейтинг ★);
##   themes / procs / up — что куплено: виды окружения, процедуры, улучшения отеля.
##
## Логика отделена от интерфейса: всё, что можно посчитать, считается здесь,
## а экран отеля (main.gd) только показывает состояние и зовёт эти функции.
## Поэтому и офлайн-накопление, и тесты работают без графики.

const SETTINGS := "user://settings.cfg"
const SAVE_SECTION := "hotel"
const SAVE_KEY := "state"

## сколько времени отель «работает» без игрока за один заход
const OFFLINE_CAP := 8.0 * 3600.0
## отзывов в скользящем окне рейтинга
const REVIEW_WINDOW := 12
## сколько секунд гость ждёт заселения
const PATIENCE := 60.0
## максимальное число номеров
const ROOM_MAX := 8
const ROOM_LEVEL_MAX := 5

## прилетающие феи: вид совпадает с видом глав (и с нарядом гостя).
## tier — нужный рейтинг отеля (★), pay — базовая плата, theme/proc — вкусы гостя.
const KINDS: Array[Dictionary] = [
	{"id": "flower", "icon": "❀", "title": "Лили", "kind": "Цветочные феи", "tier": 1, "pay": 1.0,
		"theme": "meadow", "proc": "massage",
		"whim": "Хочет номер у луга и массаж крыльев."},
	{"id": "water", "icon": "❃", "title": "Марина", "kind": "Водяные феи", "tier": 1, "pay": 1.1,
		"theme": "river", "proc": "bath",
		"whim": "Мечтает о номере у воды и купальне с лепестками."},
	{"id": "garden", "icon": "❁", "title": "Верба", "kind": "Садовые феи", "tier": 1, "pay": 1.05,
		"theme": "garden", "proc": "greenhouse",
		"whim": "Любит зелень и прогулки по оранжерее."},
	{"id": "mushroom", "icon": "✿", "title": "Опал", "kind": "Грибные феи", "tier": 2, "pay": 1.2,
		"theme": "mushroom", "proc": "tea",
		"whim": "Просит грибной номер и чайную с мёдом."},
	{"id": "night", "icon": "☾", "title": "Ноэль", "kind": "Лунные феи", "tier": 2, "pay": 1.3,
		"theme": "moon", "proc": "moon",
		"whim": "Спит днём: нужен лунный номер и медитация."},
	{"id": "frost", "icon": "❆", "title": "Ивия", "kind": "Снежные феи", "tier": 2, "pay": 1.25,
		"theme": "frost", "proc": "bath",
		"whim": "Хочет ледяной номер и прохладную купальню."},
	{"id": "rainbow", "icon": "✺", "title": "Ирис", "kind": "Радужные феи", "tier": 3, "pay": 1.6,
		"theme": "rainbow", "proc": "massage",
		"whim": "Просит радужную веранду и массаж крыльев."},
	{"id": "storm", "icon": "⚡", "title": "Зефира", "kind": "Грозовые феи", "tier": 4, "pay": 1.8,
		"theme": "storm", "proc": "moon",
		"whim": "После грозы хочет чердак и лунную медитацию."},
	{"id": "star", "icon": "✦", "title": "Астра", "kind": "Звёздные феи", "tier": 5, "pay": 2.4,
		"theme": "star", "proc": "star_bath",
		"whim": "Ей нужна обсерватория и звёздная ванна."},
]

## виды окружения: покупаются один раз, потом надеваются на любой номер
const THEMES: Array[Dictionary] = [
	{"id": "simple", "icon": "▪", "title": "Простой номер", "price": 0,
		"desc": "Кровать из мха и кувшин с росой. Никаких капризов не исполняет."},
	{"id": "meadow", "icon": "❀", "title": "Луговой уголок", "price": 200,
		"desc": "Балкон в ромашки: цветочным феям здесь нравится больше всего."},
	{"id": "river", "icon": "❃", "title": "Речной номер", "price": 260,
		"desc": "Кровать-кувшинка и шум воды за стеной — для водяных фей."},
	{"id": "mushroom", "icon": "✿", "title": "Грибная нора", "price": 300,
		"desc": "Тёплый номер под шляпкой боровика, пахнет осенним лесом."},
	{"id": "moon", "icon": "☾", "title": "Лунная башня", "price": 380,
		"desc": "Самый тихий номер: окно в звёздное небо и полог из тумана."},
	{"id": "frost", "icon": "❆", "title": "Ледяная горка", "price": 420,
		"desc": "Хрустальные стены и снежная постель — для снежных фей."},
	{"id": "garden", "icon": "❁", "title": "Оранжерея", "price": 460,
		"desc": "Круглый номер-теплица с ростками и солнечными зайчиками."},
	{"id": "rainbow", "icon": "✺", "title": "Радужная веранда", "price": 700,
		"desc": "Стеклянная веранда, где утром по потолку бежит радуга."},
	{"id": "storm", "icon": "⚡", "title": "Грозовой чердак", "price": 900,
		"desc": "Чердак под самой тучей: гроза слышна, но не страшна."},
	{"id": "star", "icon": "✦", "title": "Обсерватория", "price": 1200,
		"desc": "Купол с телескопом — звёздные феи считают его своим домом."},
]

## процедуры: пока гость живёт в номере, его можно отправить на одну процедуру
const PROCS: Array[Dictionary] = [
	{"id": "tea", "icon": "☕", "title": "Чайная с мёдом", "price": 0, "dur": 15.0, "pay": 12, "cap": 2,
		"desc": "Быстрая процедура для любого гостя: 15 секунд и чашка мёда."},
	{"id": "massage", "icon": "✋", "title": "Массаж крыльев", "price": 250, "dur": 20.0, "pay": 20, "cap": 2,
		"desc": "Разминает крылья после долгого перелёта. Любят цветочные и радужные феи."},
	{"id": "greenhouse", "icon": "❁", "title": "Прогулка в оранжерее", "price": 380, "dur": 20.0, "pay": 24, "cap": 3,
		"desc": "Три места: можно вести сразу несколько гостей к росткам."},
	{"id": "bath", "icon": "❃", "title": "Купальня с лепестками", "price": 420, "dur": 25.0, "pay": 28, "cap": 2,
		"desc": "Тёплая купальня. Водяные и снежные феи не вылезают оттуда."},
	{"id": "moon", "icon": "☾", "title": "Лунная медитация", "price": 600, "dur": 30.0, "pay": 34, "cap": 2,
		"desc": "Тихая комната со светлячками: успокаивает после бури."},
	{"id": "star_bath", "icon": "✦", "title": "Звёздная ванна", "price": 900, "dur": 35.0, "pay": 45, "cap": 2,
		"desc": "Самая дорогая процедура: вода с растворёнными звёздами."},
]

## улучшения самого отеля
const UPGRADES: Array[Dictionary] = [
	{"id": "reception", "icon": "☎", "title": "Ресепшн", "max": 5, "prices": [150, 320, 600, 1000, 1600],
		"desc": "Больше мест в очереди и меньше пауза между гостями (−8% за уровень)."},
	{"id": "flow", "icon": "✦", "title": "Пыльцевая вытяжка", "max": 5, "prices": [200, 420, 760, 1200, 1800],
		"desc": "Сама собирает пыльцу: +3 ✦ в минуту за уровень, даже когда никто не живёт."},
	{"id": "lift", "icon": "⇧", "title": "Хрустальный лифт", "max": 5, "prices": [180, 380, 700, 1150, 1700],
		"desc": "Гости быстрее добираются до процедур: −8% времени за уровень."},
	{"id": "kitchen", "icon": "✿", "title": "Кухня фей", "max": 5, "prices": [220, 460, 820, 1300, 1900],
		"desc": "Сытный завтрак и медовые булочки: +12% к плате за номер за уровень."},
	{"id": "safe", "icon": "❖", "title": "Хрустальный сейф", "max": 4, "prices": [200, 450, 900, 1500],
		"desc": "Касса вмещает больше пыльцы, пока ты не вернулась за ней."},
]

## сколько пыльцы в минуту даёт «Пыльцевая вытяжка» за уровень
const FLOW_PER_LEVEL := 3
## на сколько секунд сокращает проживание каждый уровень уюта
const STAY_PER_LEVEL := 3.0
## база проживания и оплаты
const STAY_BASE := 45.0
const PAY_BASE := 10
const PAY_PER_LEVEL := 6


# ------------------------------------------------------------------ данные

static func kinds() -> Array:
	return I18n.tree(KINDS)


static func themes() -> Array:
	return I18n.tree(THEMES)


static func procs() -> Array:
	return I18n.tree(PROCS)


static func upgrades() -> Array:
	return I18n.tree(UPGRADES)


static func kind_of(id: String) -> Dictionary:
	for d in KINDS:
		if d["id"] == id:
			var hit: Dictionary = d
			return hit
	var first: Dictionary = KINDS[0]
	return first


static func theme_of(id: String) -> Dictionary:
	for d in THEMES:
		if d["id"] == id:
			var hit: Dictionary = d
			return hit
	var first: Dictionary = THEMES[0]
	return first


static func proc_of(id: String) -> Dictionary:
	for d in PROCS:
		if d["id"] == id:
			var hit: Dictionary = d
			return hit
	var first: Dictionary = PROCS[0]
	return first


static func upgrade_of(id: String) -> Dictionary:
	for d in UPGRADES:
		if d["id"] == id:
			var hit: Dictionary = d
			return hit
	var first: Dictionary = UPGRADES[0]
	return first


static func theme_title(id: String) -> String:
	return str(I18n.tree(theme_of(id))["title"])


static func proc_title(id: String) -> String:
	return str(I18n.tree(proc_of(id))["title"])


static func kind_title(id: String) -> String:
	return str(I18n.tree(kind_of(id))["title"])


# ------------------------------------------------------------------ состояние

## новый отель: два простых номера, чайная на первом этаже и пустой ресепшн
static func fresh() -> Dictionary:
	return {
		"rooms": [_new_room(), _new_room()],
		"queue": [],
		"cash": 0,
		"earned": 0,
		"served": 0,
		"reviews": [],
		"themes": {"simple": true},
		"procs": {"tea": true},
		"up": _empty_up(),
		"last": Time.get_unix_time_from_system(),
		"boost_until": 0.0,
		"next_guest": 6.0,
	}


static func _new_room() -> Dictionary:
	return {"theme": "simple", "lvl": 1, "slots": 1, "guests": []}


static func _empty_up() -> Dictionary:
	var u := {}
	for d in UPGRADES:
		u[d["id"]] = 0
	return u


static func load_state() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return fresh()
	var raw := str(cfg.get_value(SAVE_SECTION, SAVE_KEY, ""))
	if raw == "":
		return fresh()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return fresh()
	var s: Dictionary = parsed
	# старые сохранения: добираем недостающие поля
	var base := fresh()
	for k in base.keys():
		if not s.has(k):
			s[k] = base[k]
	for id in _empty_up().keys():
		if not s["up"].has(id):
			s["up"][id] = 0
	return s


static func save_state(s: Dictionary) -> void:
	s["last"] = Time.get_unix_time_from_system()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(SAVE_SECTION, SAVE_KEY, JSON.stringify(s))
	cfg.save(SETTINGS)


# ------------------------------------------------------------------ доступ и цены

static func up_level(s: Dictionary, id: String) -> int:
	return int(s["up"].get(id, 0))


static func stars(s: Dictionary) -> float:
	var rev: Array = s["reviews"]
	if rev.is_empty():
		return 1.0
	var sum := 0.0
	for r in rev:
		sum += float(r)
	return sum / float(rev.size())


## какой самый «дорогой» гость может прилететь: рейтинг ★ открывает уровни
static func tier_max(s: Dictionary) -> int:
	return clampi(int(floor(stars(s))), 1, 5)


## кто вообще может прилететь сегодня (для справки игроку)
static func kinds_open(s: Dictionary) -> Array:
	var out := []
	for d in KINDS:
		if int(d["tier"]) <= tier_max(s):
			out.append(str(d["id"]))
	return out


static func arrive_every(s: Dictionary) -> float:
	return maxf(4.0, 12.0 * (1.0 - 0.08 * float(up_level(s, "reception"))))


static func guest_cap(s: Dictionary) -> int:
	return 3 + up_level(s, "reception")


static func flow_per_min(s: Dictionary) -> int:
	return FLOW_PER_LEVEL * up_level(s, "flow")


static func cash_cap(s: Dictionary) -> int:
	var rooms: Array = s["rooms"]
	return int((200 + 120 * up_level(s, "safe")) * maxi(1, rooms.size()))


static func stay_time(lvl: int) -> float:
	return maxf(18.0, STAY_BASE - STAY_PER_LEVEL * float(lvl))


static func proc_dur(s: Dictionary, proc_id: String) -> float:
	return float(proc_of(proc_id)["dur"]) * (1.0 - 0.08 * float(up_level(s, "lift")))


## базовая плата одного гостя за проживание (растёт с уровнем уюта)
static func room_pay(lvl: int) -> int:
	return PAY_BASE + PAY_PER_LEVEL * lvl


## цена следующего уровня уюта в конкретном номере
static func upgrade_price(room_i: int, lvl: int) -> int:
	if lvl >= ROOM_LEVEL_MAX:
		return -1
	return (80 + 40 * (room_i + 1)) * lvl


## цена нового номера
static func open_room_price(s: Dictionary) -> int:
	var rooms: Array = s["rooms"]
	var n := rooms.size()
	if n >= ROOM_MAX:
		return -1
	return int(round(400.0 * pow(1.7, float(n) - 2.0)))


## цена второго места в номере
static func expand_price(room_i: int) -> int:
	return 300 + 150 * (room_i + 1)


static func theme_owned(s: Dictionary, id: String) -> bool:
	return bool(s["themes"].get(id, false)) or int(theme_of(id)["price"]) <= 0


static func theme_price(s: Dictionary, id: String) -> int:
	if theme_owned(s, id):
		return 0
	return int(theme_of(id)["price"])


static func proc_owned(s: Dictionary, id: String) -> bool:
	return bool(s["procs"].get(id, false)) or int(proc_of(id)["price"]) <= 0


static func proc_price(s: Dictionary, id: String) -> int:
	if proc_owned(s, id):
		return 0
	return int(proc_of(id)["price"])


static func up_price(s: Dictionary, id: String) -> int:
	var d := upgrade_of(id)
	var lvl := up_level(s, id)
	var prices: Array = d["prices"]
	if lvl >= int(d["max"]):
		return -1
	return int(prices[lvl])


## сезон дня: раз в сутки один вид окружения приносит больше пыльцы
static func season_theme() -> String:
	var themed := []
	for d in THEMES:
		if d["id"] != "simple":
			themed.append(str(d["id"]))
	return str(themed[absi(hash("fairy-hotel-" + Modes.daily_key())) % themed.size()])


static func season_mult(theme_id: String) -> float:
	return 1.6 if theme_id == season_theme() else 1.0


## ×2 к плате за рекламу: буст на несколько минут игры
static func set_boost(s: Dictionary, sec: float) -> void:
	var now := Time.get_unix_time_from_system()
	s["boost_until"] = maxf(float(s["boost_until"]), now) + sec


static func boost_left(s: Dictionary) -> float:
	return maxf(0.0, float(s["boost_until"]) - Time.get_unix_time_from_system())


static func boosted(s: Dictionary) -> bool:
	return float(s["boost_until"]) > Time.get_unix_time_from_system()


# ------------------------------------------------------------------ гости и номера

## сколько мест занято и сколько всего
static func beds(s: Dictionary) -> Array:
	var used := 0
	var total := 0
	for r in s["rooms"]:
		total += int(r["slots"])
		used += (r["guests"] as Array).size()
	return [used, total]


## сколько мест свободно в конкретном номере
static func free_beds(room: Dictionary) -> int:
	return int(room["slots"]) - (room["guests"] as Array).size()


## подходит ли гость номеру: вид окружения совпадает с его вкусом
static func fits(kind_id: String, theme_id: String) -> bool:
	return str(kind_of(kind_id)["theme"]) == theme_id


## «красивая» причина отказа/согласия для подсказки в интерфейсе
static func fit_hint(kind_id: String, theme_id: String) -> String:
	if fits(kind_id, theme_id):
		return I18n.t("вкус гостя: плата ×1.6 и лучший отзыв")
	if theme_id == "simple":
		return I18n.t("простой номер: плата ×0.7 и отзыв ниже")
	return I18n.t("не её окружение: плата ×0.7 и отзыв ниже")


## случайный гость по рейтингу отеля (vip — гость, приглашённый за рекламу)
static func roll_guest(s: Dictionary, vip: bool = false) -> Dictionary:
	var pool := []
	for d in KINDS:
		if vip:
			pool.append(str(d["id"]))
		elif int(d["tier"]) <= tier_max(s):
			pool.append(str(d["id"]))
	if pool.is_empty():
		pool.append("flower")
	var id := str(pool[randi() % pool.size()])
	return {"kind": id, "vip": vip, "patience": PATIENCE * (0.6 if vip else 1.0)}


## прилетел новый гость: в очередь, если есть место
static func add_guest(s: Dictionary, vip: bool = false) -> bool:
	if (s["queue"] as Array).size() >= guest_cap(s):
		return false
	(s["queue"] as Array).append(roll_guest(s, vip))
	return true


static func check_in(s: Dictionary, queue_i: int, room_i: int) -> bool:
	var queue: Array = s["queue"]
	var rooms: Array = s["rooms"]
	if queue_i < 0 or queue_i >= queue.size() or room_i < 0 or room_i >= rooms.size():
		return false
	var room: Dictionary = rooms[room_i]
	if free_beds(room) <= 0:
		return false
	var guest: Dictionary = queue[queue_i]
	var kind := str(guest["kind"])
	var vip := bool(guest.get("vip", false))
	(room["guests"] as Array).append({
		"kind": kind, "vip": vip,
		"t_left": stay_time(int(room["lvl"])),
		"proc": "", "proc_left": 0.0,
		"matched": fits(kind, str(room["theme"])),
	})
	queue.remove_at(queue_i)
	return true


## меняем вид окружения у свободного номера (гости внутри не переезжают)
static func set_theme(s: Dictionary, room_i: int, theme_id: String) -> bool:
	var rooms: Array = s["rooms"]
	if room_i < 0 or room_i >= rooms.size():
		return false
	if not theme_owned(s, theme_id):
		return false
	if not (rooms[room_i]["guests"] as Array).is_empty():
		return false
	rooms[room_i]["theme"] = theme_id
	return true


static func buy_theme(s: Dictionary, theme_id: String) -> bool:
	if theme_owned(s, theme_id):
		return false
	s["themes"][theme_id] = true
	return true


static func buy_proc(s: Dictionary, proc_id: String) -> bool:
	if proc_owned(s, proc_id):
		return false
	s["procs"][proc_id] = true
	return true


static func upgrade_room(s: Dictionary, room_i: int) -> bool:
	var rooms: Array = s["rooms"]
	if room_i < 0 or room_i >= rooms.size():
		return false
	if int(rooms[room_i]["lvl"]) >= ROOM_LEVEL_MAX:
		return false
	rooms[room_i]["lvl"] = int(rooms[room_i]["lvl"]) + 1
	return true


## расширение номера: второе спальное место
static func expand_room(s: Dictionary, room_i: int) -> bool:
	var rooms: Array = s["rooms"]
	if room_i < 0 or room_i >= rooms.size():
		return false
	if int(rooms[room_i]["slots"]) >= 2:
		return false
	rooms[room_i]["slots"] = 2
	return true


static func open_room(s: Dictionary) -> bool:
	if s["rooms"].size() >= ROOM_MAX:
		return false
	(s["rooms"] as Array).append(_new_room())
	return true


static func upgrade_hotel(s: Dictionary, id: String) -> bool:
	var d := upgrade_of(id)
	if up_level(s, id) >= int(d["max"]):
		return false
	s["up"][id] = up_level(s, id) + 1
	return true


## сколько процедур этого вида уже идёт
static func proc_load(s: Dictionary, proc_id: String) -> int:
	var n := 0
	for r in s["rooms"]:
		for g in r["guests"]:
			if str(g["proc"]) == proc_id and float(g["proc_left"]) > 0.0:
				n += 1
	return n


static func proc_room_left(s: Dictionary, proc_id: String) -> int:
	return int(proc_of(proc_id)["cap"]) - proc_load(s, proc_id)


## отправить гостя из номера на процедуру
static func send_proc(s: Dictionary, room_i: int, slot: int, proc_id: String) -> bool:
	var rooms: Array = s["rooms"]
	if room_i < 0 or room_i >= rooms.size():
		return false
	var guests: Array = rooms[room_i]["guests"]
	if slot < 0 or slot >= guests.size():
		return false
	if str(guests[slot]["proc"]) != "":
		return false
	if not proc_owned(s, proc_id) or proc_room_left(s, proc_id) <= 0:
		return false
	guests[slot]["proc"] = proc_id
	guests[slot]["proc_left"] = proc_dur(s, proc_id)
	return true


## мгновенно завершить все процедуры (награда за рекламу)
static func finish_procs(s: Dictionary) -> int:
	var n := 0
	for r in s["rooms"]:
		for g in r["guests"]:
			if str(g["proc"]) != "" and float(g["proc_left"]) > 0.0:
				g["proc_left"] = 0.0
				n += 1
	return n


# ------------------------------------------------------------------ оплата и отзывы

## плата за проживание: вкус гостя, уют, кухня, сезон и реклама-ускорение
static func payout(s: Dictionary, guest: Dictionary, room: Dictionary) -> int:
	var kind := kind_of(str(guest["kind"]))
	var lvl := int(room["lvl"])
	var base := float(kind["pay"]) * float(room_pay(lvl))
	base *= 1.0 + 0.12 * float(up_level(s, "kitchen"))
	if bool(guest.get("matched", false)):
		base *= 1.6
	else:
		base *= 0.7
	if bool(guest.get("vip", false)):
		base *= 1.5
	var proc_id := str(guest["proc"])
	if proc_id != "" and float(guest["proc_left"]) <= 0.0:
		var extra := float(proc_of(proc_id)["pay"])
		base += extra * (1.5 if proc_id == str(kind["proc"]) else 1.0)
	base *= season_mult(str(room["theme"]))
	if boosted(s):
		base *= 2.0
	return int(round(base))


## отзыв гостя: 1..5 звёзд — вкус, уют номера и процедура
static func review_for(guest: Dictionary, room: Dictionary) -> int:
	var r := 1
	if bool(guest.get("matched", false)):
		r += 2
	r += int(floor(float(room["lvl"]) * 0.5))
	var proc_id := str(guest["proc"])
	if proc_id != "" and float(guest["proc_left"]) <= 0.0:
		r += 2 if proc_id == str(kind_of(str(guest["kind"]))["proc"]) else 1
	return clampi(r, 1, 5)


## гость уезжает: плата в кассу, отзыв в рейтинг
static func checkout(s: Dictionary, room_i: int, slot: int) -> int:
	var rooms: Array = s["rooms"]
	if room_i < 0 or room_i >= rooms.size():
		return 0
	var guests: Array = rooms[room_i]["guests"]
	if slot < 0 or slot >= guests.size():
		return 0
	var guest: Dictionary = guests[slot]
	var pay := payout(s, guest, rooms[room_i])
	s["cash"] = mini(cash_cap(s), int(s["cash"]) + pay)
	s["earned"] = int(s["earned"]) + pay
	s["served"] = int(s["served"]) + 1
	var reviews: Array = s["reviews"]
	reviews.append(review_for(guest, rooms[room_i]))
	while reviews.size() > REVIEW_WINDOW:
		reviews.pop_front()
	guests.remove_at(slot)
	return pay


## собрать кассу (удвоение за рекламу считает вызывающий код)
static func collect(s: Dictionary) -> int:
	var got := int(s["cash"])
	s["cash"] = 0
	return got


# ------------------------------------------------------------------ время

## один шаг в интерфейсе: очередь, проживание, процедуры, вытяжка
## возвращает, сколько гостей уехало (для перерисовки экрана)
static func tick(s: Dictionary, dt: float) -> int:
	var served_now := 0
	# вытяжка капает пыльцой постоянно
	var flow := flow_per_min(s)
	if flow > 0:
		s["_flow_acc"] = float(s.get("_flow_acc", 0.0)) + dt * float(flow) / 60.0
		var whole := int(floor(float(s["_flow_acc"])))
		if whole > 0:
			s["_flow_acc"] = float(s["_flow_acc"]) - float(whole)
			s["cash"] = mini(cash_cap(s), int(s["cash"]) + whole)
	# новые гости
	s["next_guest"] = float(s["next_guest"]) - dt
	if float(s["next_guest"]) <= 0.0:
		s["next_guest"] = arrive_every(s)
		add_guest(s)
	# очередь ждёт
	var queue: Array = s["queue"]
	for i in range(queue.size() - 1, -1, -1):
		queue[i]["patience"] = float(queue[i]["patience"]) - dt
		if float(queue[i]["patience"]) <= 0.0:
			queue.remove_at(i)
	# номера: проживание и процедуры
	for ri in (s["rooms"] as Array).size():
		var guests: Array = s["rooms"][ri]["guests"]
		for gi in range(guests.size() - 1, -1, -1):
			var g: Dictionary = guests[gi]
			if str(g["proc"]) != "" and float(g["proc_left"]) > 0.0:
				g["proc_left"] = maxf(0.0, float(g["proc_left"]) - dt)
			g["t_left"] = float(g["t_left"]) - dt
			if float(g["t_left"]) <= 0.0:
				checkout(s, ri, gi)
				served_now += 1
	return served_now


## гостеприимство без игрока: свободные номера сами принимают подходящих гостей
## (возвращает, сколько гостей заселилось)
static func auto_host(s: Dictionary) -> int:
	var queue: Array = s["queue"]
	var rooms: Array = s["rooms"]
	var seated := 0
	for ri in rooms.size():
		var room: Dictionary = rooms[ri]
		while free_beds(room) > 0 and not queue.is_empty():
			var best := -1
			for qi in queue.size():
				if fits(str(queue[qi]["kind"]), str(room["theme"])):
					best = qi
					break
			if best < 0:
				break
			if not check_in(s, best, ri):
				break
			seated += 1
	return seated


## офлайн-накопление: пока игрока нет, гости сменяются сами (без процедур)
static func settle(s: Dictionary) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var dt := clampf(now - float(s["last"]), 0.0, OFFLINE_CAP)
	s["last"] = now
	if dt < 1.0:
		return {"sec": 0, "pollen": 0, "served": 0}
	var before_cash := int(s["cash"])
	var before_served := int(s["served"])
	# гости приходят и уезжают крупными шагами, чтобы не крутить тысячи итераций
	var every := arrive_every(s)
	var steps := int(minf(600.0, dt / maxf(2.0, minf(every, stay_time(1)) * 0.5)))
	var step := dt / float(maxi(1, steps))
	for i in steps:
		auto_host(s)
		tick(s, step)
		if float(s["next_guest"]) > dt:
			break
	var gained := int(s["cash"]) - before_cash
	return {"sec": int(dt), "pollen": maxi(0, gained), "served": int(s["served"]) - before_served}


## человеческая подпись «сколько ждала»
static func fmt_time(sec: float) -> String:
	var left := maxi(0, int(ceil(sec)))
	return "%d:%02d" % [int(floor(float(left) / 60.0)), left % 60]


## подпись офлайн-дохода для экрана отеля
static func settle_hint(res: Dictionary) -> String:
	if int(res["sec"]) <= 0 or int(res["pollen"]) <= 0:
		return ""
	var mins := int(floor(float(res["sec"]) / 60.0))
	var span := I18n.t("%d мин") % mins if mins > 0 else I18n.t("%d с") % int(res["sec"])
	return I18n.t("Пока тебя не было (%s): +%d ✦, гостей обслужено %d.") % [span, int(res["pollen"]), int(res["served"])]
