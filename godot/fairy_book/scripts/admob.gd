extends Node
## AdMob для Android-сборки: липкий баннер, межстраничная реклама и видео с
## наградой. Работает через плагин GodotAdMob (синглтон движка); если плагин не
## установлен, каждый вызов остаётся безопасной заглушкой — игра полностью
## проходима без рекламы, а награда за «доброе дело» выдаётся сразу.
##
## Идентификаторы блоков ниже — официальные тестовые ID Google: сборка с ними
## работает и не приносит дохода. Перед публикацией замените их на свои
## (README, раздел «Android-версия»).

signal platform_pause
signal platform_resume

const BANNER_ID := "ca-app-pub-3940256099942544/6300978111"
const INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"
const REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
## имя синглтона, которое регистрирует плагин AdMob
const PLUGIN := "GodotAdMob"
## пауза между межстраничными роликами — та же, что требует Yandex Games
const MIN_INTERVAL_MS := 60000
## сколько ждём инициализацию и закрытие ролика, чтобы никогда не зависнуть
const INIT_TIMEOUT_MS := 5000
const AD_TIMEOUT_MS := 120000

var ad_showing := false
var banner_wanted := false
var banner_shown := false
var last_reward_tag := ""
## настоящий плагин на месте (иначе реклама не показывается вовсе)
var plugin := false

var _sdk = null
var _session_ms := 0
var _last_fullscreen_ms := -1000000
var _gameplay_on := false
var _inited := false
var _interstitial_ready := false
var _rewarded_ready := false
## ролик открыт и мы ждём его закрытия
var _ad_open := false
## награда подтверждена сигналом user_earned_reward
var _reward_granted := false
## приложение свёрнуто — Android сообщает об этом сам, плагин не нужен
var _background := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_ms = Time.get_ticks_msec()
	if Engine.has_singleton(PLUGIN):
		_sdk = Engine.get_singleton(PLUGIN)
		plugin = true
		_link_signals()
		# плагин не рассчитан на детскую рекламу, рейтинг — обычный
		_call("init", [false, ""])
	else:
		push_warning("[admob] плагин " + PLUGIN + " не найден — реклама отключена, награды выдаются сразу")


## Android сам сообщает, что приложение свернули или развернули. Игра должна
## встать на паузу, а звук — замолчать: ровно то, что на вебе делает
## Yandex Games через game_api_pause.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_background = true
		if not ad_showing:
			Sfx.suspend(true)
		platform_pause.emit()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_background = false
		if not ad_showing:
			Sfx.suspend(false)
		platform_resume.emit()


## плагин установлен: можно показывать настоящую рекламу площадки
func has_plugin() -> bool:
	return plugin


## ждём инициализацию SDK, но не дольше INIT_TIMEOUT_MS
func wait_init() -> void:
	if not plugin:
		return
	var t0 := Time.get_ticks_msec()
	while not _inited and Time.get_ticks_msec() - t0 < INIT_TIMEOUT_MS:
		await get_tree().process_frame


## на Android «игра готова» означает, что можно грузить первые блоки
func mark_ready() -> void:
	await wait_init()
	if not plugin:
		return
	_load_interstitial()
	_load_rewarded()


func gameplay_start() -> void:
	_gameplay_on = true


func gameplay_stop() -> void:
	_gameplay_on = false


## межстраничную рекламу показываем не в первые 60 секунд и не чаще раза в
## минуту — те же правила, что и на других площадках
func interstitial_ok() -> bool:
	if not plugin or ad_showing or _gameplay_on or not _interstitial_ready:
		return false
	var now := Time.get_ticks_msec()
	return now - _session_ms > MIN_INTERVAL_MS and now - _last_fullscreen_ms > MIN_INTERVAL_MS


func show_banner() -> void:
	banner_wanted = true
	if not plugin or banner_shown:
		return
	if _call("loadBanner", [BANNER_ID, 0]):
		banner_shown = true
		_call("showBanner")


func hide_banner() -> void:
	banner_wanted = false
	if not plugin or not banner_shown:
		return
	banner_shown = false
	_call("hideBanner")
	_call("destroyBanner")


## межстраничная реклама; true — ролик действительно был показан
func show_fullscreen() -> bool:
	if not interstitial_ok():
		return false
	await wait_init()
	_begin_ad()
	_ad_open = true
	_interstitial_ready = false
	if not _call("showInterstitial"):
		_ad_open = false
		_end_ad()
		_load_interstitial()
		return false
	await _wait_closed()
	_end_ad()
	_last_fullscreen_ms = Time.get_ticks_msec()
	_load_interstitial()
	return true


## видео с наградой; true — награду можно выдавать.
## Без плагина (редактор, десктоп, сборка без AdMob) награда выдаётся сразу:
## механика «добрых дел» должна проходиться на любой площадке.
func show_rewarded(tag: String = "") -> bool:
	last_reward_tag = tag
	if not plugin:
		return true
	if ad_showing:
		return false
	await wait_init()
	if not _rewarded_ready:
		_load_rewarded()
		return false
	_begin_ad()
	_ad_open = true
	_reward_granted = false
	_rewarded_ready = false
	if not _call("showRewarded"):
		_ad_open = false
		_end_ad()
		_load_rewarded()
		return false
	await _wait_closed()
	_end_ad()
	_load_rewarded()
	# если плагин так и не сообщил о закрытии, награду всё равно выдаём:
	# игрок ролик досмотрел, а потерянное «доброе дело» обиднее ошибки SDK
	return _reward_granted or not _ad_open


func _begin_ad() -> void:
	ad_showing = true
	_gameplay_on = false
	Sfx.suspend(true)


func _end_ad() -> void:
	ad_showing = false
	_ad_open = false
	# ролик закрылся, но приложение могло остаться свёрнутым
	Sfx.suspend(_background)


## ждём закрытия ролика, но не дольше AD_TIMEOUT_MS — зависшая реклама не
## должна блокировать игру
func _wait_closed() -> void:
	var t0 := Time.get_ticks_msec()
	while _ad_open and Time.get_ticks_msec() - t0 < AD_TIMEOUT_MS:
		await get_tree().process_frame
	if _ad_open:
		push_warning("[admob] ролик не закрылся сам — продолжаем без него")
		_ad_open = false


func _load_interstitial() -> void:
	_interstitial_ready = false
	if plugin:
		_call("loadInterstitial", [INTERSTITIAL_ID])


func _load_rewarded() -> void:
	_rewarded_ready = false
	if plugin:
		_call("loadRewarded", [REWARDED_ID])


## вызов метода плагина: если метода нет (другая версия плагина), просто false
func _call(method: String, args: Array = []) -> bool:
	if _sdk == null or not _sdk.has_method(method):
		return false
	_sdk.callv(method, args)
	return true


## подключаем только те сигналы, которые у плагина действительно есть
func _link_signals() -> void:
	_link("initialization_complete", _on_init)
	_link("banner_loaded", _on_banner_loaded)
	_link("interstitial_loaded", _on_interstitial_loaded)
	_link("interstitial_closed", _on_interstitial_closed)
	_link("rewarded_loaded", _on_rewarded_loaded)
	_link("rewarded_closed", _on_rewarded_closed)
	_link("user_earned_reward", _on_reward_earned)


func _link(sig: String, cb: Callable) -> void:
	if _sdk != null and _sdk.has_signal(sig):
		_sdk.connect(sig, cb)


# обработчики терпят и ноль, и один аргумент: версии плагина шлют их по-разному
func _on_init(_v: Variant = null) -> void:
	_inited = true


func _on_banner_loaded(_v: Variant = null) -> void:
	banner_shown = banner_wanted


func _on_interstitial_loaded(_v: Variant = null) -> void:
	_interstitial_ready = true


func _on_interstitial_closed(_v: Variant = null) -> void:
	_ad_open = false


func _on_rewarded_loaded(_v: Variant = null) -> void:
	_rewarded_ready = true


func _on_rewarded_closed(_v: Variant = null) -> void:
	_ad_open = false


func _on_reward_earned(_v: Variant = null) -> void:
	_reward_granted = true
