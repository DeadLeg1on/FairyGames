extends Node
## Роутер рекламы: одна игра — разные площадки.
##
## Веб-сборка показывает рекламу Yandex Games (scripts/yandex.gd), Android-сборка
## — AdMob (scripts/admob.gd), а в редакторе и на десктопе рекламы нет вовсе:
## награды за «добрые дела» выдаются сразу, чтобы механику можно было пройти и
## проверить. Игра обращается только к Ads и не знает, какая площадка под ней,
## поэтому добавление новой платформы не трогает main.gd.
##
## Правила показа общие для всех площадок и живут здесь: не чаще раза в минуту,
## не в первые 60 секунд сессии, никогда во время геймплея, звук на время
## ролика глушится.

signal platform_pause
signal platform_resume

const PROVIDER_LOCAL := "local"
const PROVIDER_YANDEX := "yandex"
const PROVIDER_ADMOB := "admob"

## какая площадка сейчас под игрой
var provider := PROVIDER_LOCAL
var ad_showing := false
var banner_wanted := false
var banner_shown := false
var last_reward_tag := ""

## реализация площадки: Yandex (автозагрузка) или AdMob (создаём сами)
var _impl = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		provider = PROVIDER_YANDEX
		_impl = Yandex
	elif OS.has_feature("android"):
		provider = PROVIDER_ADMOB
		# явный тип: load() для скрипта, который ещё не скомпилирован, тип не выводит
		var impl_script: GDScript = load("res://scripts/admob.gd")
		_impl = impl_script.new()
		_impl.name = "AdMob"
		add_child(_impl)
	if _impl != null:
		_impl.platform_pause.connect(func() -> void: platform_pause.emit())
		_impl.platform_resume.connect(func() -> void: platform_resume.emit())


## готова ли площадка показывать рекламу.
## AdMob без установленного плагина остаётся глухой: игра работает, награды
## выдаются сразу — то же поведение, что и в редакторе.
func has_ads() -> bool:
	if _impl == null:
		return false
	if provider == PROVIDER_ADMOB:
		return bool(_impl.has_plugin())
	return true


func wait_init() -> void:
	if _impl != null:
		await _impl.wait_init()


func mark_ready() -> void:
	if _impl != null:
		await _impl.mark_ready()


func gameplay_start() -> void:
	if _impl != null:
		_impl.gameplay_start()


func gameplay_stop() -> void:
	if _impl != null:
		_impl.gameplay_stop()


## можно ли сейчас показать межстраничную рекламу
func interstitial_ok() -> bool:
	if _impl == null:
		return false
	return bool(_impl.interstitial_ok())


## липкий баннер: только вне геймплея
func show_banner() -> void:
	banner_wanted = true
	if _impl == null:
		return
	_impl.show_banner()
	banner_shown = bool(_impl.banner_shown)


func hide_banner() -> void:
	banner_wanted = false
	banner_shown = false
	if _impl != null:
		_impl.hide_banner()


## полноэкранная реклама между сессиями; true — ролик действительно показан
func show_fullscreen() -> bool:
	if _impl == null or ad_showing:
		return false
	ad_showing = true
	var shown: bool = await _impl.show_fullscreen()
	ad_showing = false
	return shown


## реклама с наградой; true — награду можно выдавать.
## Без площадки (редактор, десктоп) награда выдаётся сразу.
func show_rewarded(tag: String = "") -> bool:
	last_reward_tag = tag
	if _impl == null:
		return true
	if ad_showing:
		return false
	ad_showing = true
	var ok: bool = await _impl.show_rewarded(tag)
	ad_showing = false
	return ok
