extends Node
## Проверка роутера рекламы: одна игра — разные площадки.
##
## Веб показывает рекламу Yandex Games, Android — AdMob, а в редакторе и на
## десктопе рекламы нет: награда за «добрые дела» выдаётся сразу. Тест
## гарантирует, что все три реализации говорят на одном языке (иначе замена
## Yandex на Ads в main.gd сломала бы сборку другой платформы), что локальная
## сборка не блокирует игру ожиданием ролика, и что Android-пресет экспорта
## действительно существует.

const AdMob := preload("res://scripts/admob.gd")

## общий API площадок: всё, что main.gd вправе вызывать у Ads
const METHODS := [
	"wait_init", "mark_ready", "gameplay_start", "gameplay_stop",
	"interstitial_ok", "show_banner", "hide_banner",
	"show_fullscreen", "show_rewarded",
]
const SIGNALS := ["platform_pause", "platform_resume"]
const STATE := ["ad_showing", "banner_wanted", "banner_shown", "last_reward_tag"]

var fails := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print(("OK   " if cond else "FAIL ") + what)


func _ready() -> void:
	await get_tree().process_frame
	print("== реклама по площадкам: роутер Ads ==")

	_check_router()
	await _check_local_stub()
	_check_api_parity()
	await _check_admob_fallback()
	_check_signal_forwarding()
	_check_android_preset()
	_check_main_routes_through_ads()

	print("FAILS ", fails)
	get_tree().quit()


## ── роутер выбирает площадку по фичам ОС ───────────────────────────────────
func _check_router() -> void:
	ok(Ads != null, "Ads доступен как автозагрузка")
	if OS.has_feature("web"):
		ok(Ads.provider == Ads.PROVIDER_YANDEX, "веб-сборка → Yandex Games")
		ok(Ads._impl == Yandex, "веб-сборка делегирует автозагрузке Yandex")
	elif OS.has_feature("android"):
		ok(Ads.provider == Ads.PROVIDER_ADMOB, "android-сборка → AdMob")
		ok(Ads._impl != null, "android-сборка создала мост AdMob")
	else:
		ok(Ads.provider == Ads.PROVIDER_LOCAL, "редактор/десктоп → локальная сборка")
		ok(Ads._impl == null, "на десктопе нет площадки")
		ok(not Ads.has_ads(), "на десктопе реклама не показывается")


## ── локальная сборка не блокирует игру ─────────────────────────────────────
## В редакторе и в CI награда обязана выдаваться сразу: иначе «добрые дела»
## (удвоение выручки, второй этаж отеля) нельзя ни пройти, ни проверить.
func _check_local_stub() -> void:
	if Ads._impl != null:
		print("     площадка активна — локальный стаб не проверяем")
		return
	var rewarded: bool = await Ads.show_rewarded("hotel_upgrade")
	ok(rewarded, "награда выдаётся сразу без площадки")
	ok(Ads.last_reward_tag == "hotel_upgrade", "тэг награды запоминается")
	var full: bool = await Ads.show_fullscreen()
	ok(not full, "полноэкранной рекламы без площадки нет")
	ok(not Ads.interstitial_ok(), "межстраничная реклама без площадки не предлагается")
	Ads.show_banner()
	ok(Ads.banner_wanted and not Ads.banner_shown, "баннер помечен желаемым, но не показан")
	Ads.hide_banner()
	ok(not Ads.banner_wanted and not Ads.banner_shown, "баннер снят")
	ok(not Ads.ad_showing, "флаг показа рекламы сброшен")


## ── все реализации говорят на одном языке ──────────────────────────────────
func _check_api_parity() -> void:
	var impls := {"Yandex": Yandex, "Ads": Ads, "AdMob": AdMob.new()}
	for title in impls:
		var node = impls[title]
		var missing := []
		for m in METHODS:
			if not node.has_method(m):
				missing.append(m)
		for s in SIGNALS:
			if not node.has_signal(s):
				missing.append("signal:" + s)
		for v in STATE:
			if node.get(v) == null:
				missing.append("var:" + v)
		ok(missing.is_empty(), "%s: полный API (%s)" % [title, ", ".join(missing) if missing else "всё на месте"])
	impls["AdMob"].free()


## ── AdMob без плагина деградирует безопасно ────────────────────────────────
## Плагин ставится отдельно от репозитория; пока его нет, Android-сборка должна
## работать как локальная: без роликов и без зависания на ожидании награды.
func _check_admob_fallback() -> void:
	var mob = AdMob.new()
	ok(not mob.has_plugin(), "в CI плагина AdMob нет")
	var rewarded: bool = await mob.show_rewarded("test")
	ok(rewarded, "без плагина награда выдаётся сразу")
	var full: bool = await mob.show_fullscreen()
	ok(not full, "без плагина полноэкранного ролика нет")
	ok(not mob.interstitial_ok(), "без плагина межстраничная реклама не предлагается")
	mob.gameplay_start()
	mob.gameplay_stop()
	mob.show_banner()
	ok(not mob.banner_shown, "без плагина баннер не показан")
	mob.free()


## ── сигналы площадки доходят до игры ───────────────────────────────────────
## main.gd паузит игру по platform_pause: если роутер не переэмитит сигнал,
## сворачивание приложения на телефоне оставит игру бежать в фоне.
func _check_signal_forwarding() -> void:
	var got := {"pause": 0, "resume": 0}
	var on_pause := func() -> void: got["pause"] += 1
	var on_resume := func() -> void: got["resume"] += 1

	var mob = AdMob.new()
	mob.platform_pause.connect(on_pause)
	mob.platform_resume.connect(on_resume)
	mob.notification(NOTIFICATION_APPLICATION_PAUSED)
	mob.notification(NOTIFICATION_APPLICATION_RESUMED)
	ok(got["pause"] == 1 and got["resume"] == 1, "AdMob: сворачивание приложения → сигналы паузы")
	mob.free()

	# роутер обязан пробрасывать сигналы текущей площадки наружу
	var routed := {"pause": 0, "resume": 0}
	Ads.platform_pause.connect(func() -> void: routed["pause"] += 1)
	Ads.platform_resume.connect(func() -> void: routed["resume"] += 1)
	if Ads._impl != null:
		Ads._impl.platform_pause.emit()
		Ads._impl.platform_resume.emit()
		ok(routed["pause"] == 1 and routed["resume"] == 1, "Ads пробрасывает сигналы площадки")
	else:
		# на десктопе площадки нет — проверяем, что сигналы хотя бы объявлены
		# и роутер не падает, когда их никто не эмитит
		Ads.platform_pause.emit()
		Ads.platform_resume.emit()
		ok(routed["pause"] == 1 and routed["resume"] == 1, "Ads: сигналы паузы объявлены и работают")


## ── Android-версия действительно собирается ────────────────────────────────
func _check_android_preset() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://export_presets.cfg")
	ok(err == OK, "export_presets.cfg читается")
	if err != OK:
		return
	ok(cfg.has_section("preset.1"), "есть второй пресет экспорта")
	ok(cfg.get_value("preset.1", "platform", "") == "Android", "пресет — Android")
	var o := "preset.1.options"
	ok(cfg.has_section(o), "у Android-пресета есть опции")
	var pkg: String = cfg.get_value(o, "package/unique_name", "")
	ok(pkg.begins_with("com.") and pkg.count(".") >= 2, "указано имя пакета: %s" % pkg)
	ok(cfg.get_value(o, "permissions/internet", false), "разрешён доступ в интернет (без него реклама не грузится)")
	ok(cfg.get_value(o, "gradle_build/use_gradle_build", false), "включена Gradle-сборка (нужна для плагина AdMob)")
	var apk: String = cfg.get_value("preset.1", "export_path", "")
	var web: String = cfg.get_value("preset.0", "export_path", "")
	ok(apk.ends_with(".apk") and apk != web, "APK пишется отдельно от веб-сборки: %s" % apk)
	# веб-пресет не должен пострадать от соседства
	ok(cfg.get_value("preset.0", "platform", "") == "Web", "веб-пресет на месте")


## ── игра обращается к роутеру, а не к конкретной площадке ──────────────────
func _check_main_routes_through_ads() -> void:
	var f := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	ok(f != null, "main.gd читается")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	ok(not src.contains("Yandex."), "main.gd не дергает Yandex напрямую")
	ok(src.contains("Ads.show_rewarded"), "награды идут через Ads")
	ok(src.contains("Ads.platform_pause"), "пауза по фокусу идёт через Ads")
