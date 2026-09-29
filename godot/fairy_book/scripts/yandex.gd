extends Node
## Yandex Games SDK через JavaScriptBridge (порт src/yandex.ts).
## JS-мост window.YB подключается в export_presets.cfg -> html/head_include.
## Вне веб-сборки (редактор, десктоп) все методы — безопасные заглушки.

signal platform_pause
signal platform_resume

var web := false
var ad_showing := false
var _yb = null # JavaScriptObject (намеренно без типа — у него динамические свойства)
var _gameplay_on := false
var _ready_sent := false
var _last_fullscreen_ms := -1000000
var _ad_pending := false
var _ad_result: Variant = null
var _cb_ad = null
var _cb_pause = null
var _cb_resume = null
var _cb_banner = null
## липкий баннер: просили показать / платформа подтвердила показ
var banner_wanted := false
var banner_shown := false
var _session_start_ms := 0
## тег последней показанной награды (для статистики и отладки)
var last_reward_tag := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_start_ms = Time.get_ticks_msec()
	web = OS.has_feature("web")
	if not web:
		return
	_yb = JavaScriptBridge.get_interface("YB")
	if _yb == null:
		push_warning("[yandex] window.YB не найден — проверьте html/head_include")
		return
	_cb_ad = JavaScriptBridge.create_callback(_on_ad_done)
	_cb_pause = JavaScriptBridge.create_callback(_on_pause)
	_cb_resume = JavaScriptBridge.create_callback(_on_resume)
	_cb_banner = JavaScriptBridge.create_callback(_on_banner)
	_yb.pauseCb = _cb_pause
	_yb.resumeCb = _cb_resume


func _has_bridge() -> bool:
	return web and _yb != null


## ждём инициализацию YaGames (не дольше 5 секунд)
func wait_init() -> void:
	if not _has_bridge():
		return
	var t0 := Time.get_ticks_msec()
	while not bool(_yb.ready) and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame


## игра загружена и готова к взаимодействию (LoadingAPI.ready)
func mark_ready() -> void:
	if _ready_sent:
		return
	_ready_sent = true
	await wait_init()
	if _has_bridge():
		_yb.loadingReady()


func gameplay_start() -> void:
	if _gameplay_on or ad_showing:
		return
	_gameplay_on = true
	if _has_bridge():
		_yb.gameplayStart()


func gameplay_stop() -> void:
	if not _gameplay_on:
		return
	_gameplay_on = false
	if _has_bridge():
		_yb.gameplayStop()


func _on_pause(_args: Array) -> void:
	Sfx.suspend(true)
	platform_pause.emit()


func _on_resume(_args: Array) -> void:
	if not ad_showing:
		Sfx.suspend(false)
	platform_resume.emit()


func _on_ad_done(args: Array) -> void:
	_ad_result = args[0] if args.size() > 0 else null
	_ad_pending = false


func _on_banner(args: Array) -> void:
	banner_shown = args.size() > 0 and bool(args[0])


func _begin_ad() -> void:
	ad_showing = true
	gameplay_stop()
	Sfx.suspend(true)


func _end_ad() -> void:
	ad_showing = false
	Sfx.suspend(false)


## Можно ли сейчас показать полноэкранную рекламу.
## Правила Яндекса: не в первые 60 секунд сессии и не чаще раза в минуту,
## и никогда — во время геймплея (GameplayAPI уже остановлен вызывающим).
func interstitial_ok() -> bool:
	if not _has_bridge() or ad_showing:
		return false
	var now := Time.get_ticks_msec()
	return now - _session_start_ms > 60000 and now - _last_fullscreen_ms > 60000


## Липкий баннер в меню: Yandex разрешает его только вне геймплея.
func show_banner() -> void:
	if not _has_bridge():
		return
	banner_wanted = true
	if banner_shown:
		return
	_yb.showBanner(_cb_banner)


func hide_banner() -> void:
	banner_wanted = false
	if not _has_bridge() or not banner_shown:
		return
	banner_shown = false
	_yb.hideBanner()


## Полноэкранная реклама между сессиями. Возвращает true, если была показана.
func show_fullscreen() -> bool:
	if not _has_bridge() or ad_showing:
		return false
	if Time.get_ticks_msec() - _last_fullscreen_ms < 60000:
		return false
	await wait_init()
	if not bool(_yb.available()):
		return false
	_begin_ad()
	_ad_pending = true
	_ad_result = null
	_yb.showFullscreen(_cb_ad)
	while _ad_pending:
		await get_tree().process_frame
	_end_ad()
	var shown: bool = _ad_result is bool and _ad_result
	if shown:
		_last_fullscreen_ms = Time.get_ticks_msec()
	return shown


## Реклама с вознаграждением. true — награда засчитана.
## tag — повод показа (continue/heal/time/chest/bless/key/garden/pollen2/...).
## Вне Яндекса награда выдаётся сразу (для тестирования механики).
func show_rewarded(tag: String = "") -> bool:
	last_reward_tag = tag
	if not _has_bridge():
		return true
	if ad_showing:
		return false
	await wait_init()
	_begin_ad()
	_ad_pending = true
	_ad_result = null
	_yb.showRewarded(_cb_ad)
	while _ad_pending:
		await get_tree().process_frame
	_end_ad()
	return _ad_result == "yes" or _ad_result == "local"
