extends Node
## Тест громкости: музыка и звуки сведены к одному уровню, настройки у них
## раздельные, ничего не клиппует и один канал не глушит другой.
##
## user://settings.cfg переживает предыдущие тесты того же прогона CI, поэтому
## состояние звука и языка задаём явно, а в конце возвращаем как было.

const CFG := "user://settings.cfg"
const TOL := 0.35        # допуск по RMS: звуки короткие, хвосты тишины влияют

var fails := 0
var was_lang := "ru"
var was_music_vol := 0.8
var was_music_on := true
var was_sfx_vol := 0.8
var was_sfx_muted := false


func ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		fails += 1
		print("FAIL  ", msg)


func _ready() -> void:
	print("== звук и музыка: громкость и настройки ==")
	# запоминаем, что оставили предыдущие тесты, и приводим каналы к известному виду
	was_lang = I18n.lang
	was_music_vol = Music.volume
	was_music_on = Music.enabled
	was_sfx_vol = Sfx.volume
	was_sfx_muted = Sfx.muted
	I18n.set_lang("ru")
	Sfx.suspend(false)
	Music.set_enabled(true)
	Sfx.set_muted(false)
	Music.set_volume(Music.DEFAULT_VOLUME)
	Sfx.set_volume(Sfx.DEFAULT_VOLUME)

	_check_levels()
	_check_parity()
	_check_volume_api()
	_check_channels_independent()
	await _check_settings_screen()

	# возвращаем то, с чем пришли, чтобы не влиять на следующие прогоны
	Music.set_enabled(was_music_on)
	Music.set_volume(was_music_vol)
	Sfx.set_muted(was_sfx_muted)
	Sfx.set_volume(was_sfx_vol)
	I18n.set_lang(was_lang)

	print("FAILS ", fails)
	get_tree().quit(0 if fails == 0 else 1)


# ================================================================= уровни громкости


## каждый звук нормализован: RMS у цели, пик не вылезает за потолок
func _check_levels() -> void:
	var target := float(Sfx.TARGET_RMS)
	var cap := float(Sfx.PEAK_MAX)
	var names: Array = Sfx.sound_names()
	ok(names.size() >= 13, "звуков собрано: %d" % names.size())
	var peak := 0.0
	var bad := ""
	for n in names:
		var lv: Dictionary = Sfx.level_of(str(n))
		if lv.is_empty():
			bad += " " + str(n) + "(нет данных)"
			continue
		peak = maxf(peak, float(lv["peak"]))
		var want := target * float(lv["weight"])
		var dev := absf(float(lv["rms"]) - want) / maxf(want, 0.0001)
		# если сработал потолок пика, звук законно тише цели
		if not bool(lv["limited"]) and dev > TOL:
			bad += " %s(%.3f≠%.3f)" % [str(n), float(lv["rms"]), want]
	ok(bad.is_empty(), "громкость каждого звука в допуске ±%d%%%s" % [int(TOL * 100.0), "" if bad.is_empty() else ": " + bad])
	ok(peak <= cap + 0.001, "пики звуков не выше потолка (%.3f <= %.2f)" % [peak, cap])
	ok(peak > 0.2, "звуки не тише воды (пик %.3f)" % peak)
	# ни один поток не должен вылезать за 1.0 — иначе хрип
	var over := ""
	for n in names:
		var st := Sfx.stream(str(n))
		if st == null:
			over += " " + str(n) + "(нет потока)"
			continue
		var p := _peak(st)
		if p > 1.0:
			over += " %s(%.3f)" % [str(n), p]
	ok(over.is_empty(), "в потоках нет перегруза%s" % ("" if over.is_empty() else ": " + over))
	for n in names:
		var lv: Dictionary = Sfx.level_of(str(n))
		if not lv.is_empty():
			print("     %-10s rms %.3f  peak %.3f  gain ×%.2f  вес %.2f%s" % [
				str(n), float(lv["rms"]), float(lv["peak"]), float(lv["gain"]),
				float(lv["weight"]), "  (ограничен пиком)" if bool(lv["limited"]) else ""])


# ================================================================= музыка ≈ звуки


## «примерно одинаковая громкость»: RMS музыки и RMS боевых звуков рядом
func _check_parity() -> void:
	var msum := 0.0
	var mcount := 0
	for tn in Music.track_names():
		var st := Music.build(str(tn))   # собирается синхронно и кэшируется
		if st == null:
			continue
		msum += _rms(st)
		mcount += 1
		print("     тема %-6s rms %.3f  peak %.3f" % [str(tn), _rms(st), _peak(st)])
	ok(mcount == 3, "музыка собрана: %d темы" % mcount)
	var music_rms := msum / maxf(1.0, float(mcount))

	# сравниваем с «боевыми» звуками (вес 1.0): короткие щелчки тише по замыслу
	var ssum := 0.0
	var scount := 0
	for n in Sfx.sound_names():
		var lv: Dictionary = Sfx.level_of(str(n))
		if lv.is_empty() or float(lv["weight"]) < 1.0:
			continue
		ssum += float(lv["rms"])
		scount += 1
	ok(scount >= 2, "боевых звуков для сравнения: %d" % scount)
	var sfx_rms := ssum / maxf(1.0, float(scount))

	var ratio := sfx_rms / maxf(music_rms, 0.0001)
	print("     музыка rms %.3f · звуки rms %.3f · соотношение %.2f" % [music_rms, sfx_rms, ratio])
	ok(ratio > 0.5 and ratio < 2.0, "музыка и звуки звучат примерно одинаково (%.2f×, допуск 0.5–2.0)" % ratio)
	ok(absf(Music.DEFAULT_VOLUME - Sfx.DEFAULT_VOLUME) < 0.001,
		"громкость по умолчанию одна: %.2f" % Music.DEFAULT_VOLUME)


# ================================================================= настройка громкости


func _check_volume_api() -> void:
	Sfx.set_volume(0.42)
	ok(absf(Sfx.volume - 0.42) < 0.001, "Sfx.set_volume меняет громкость (%.2f)" % Sfx.volume)
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	ok(absf(float(cfg.get_value("audio", "sfx", -1.0)) - 0.42) < 0.001, "громкость звуков сохраняется в settings.cfg")
	# громкость живёт в плеерах, а не в общей шине
	var want_db := linear_to_db(0.42)
	ok(absf(_sfx_db() - want_db) < 0.01, "громкость применена к игрокам (%.1f dB)" % want_db)
	Sfx.set_volume(0.0)
	ok(_sfx_db() <= -60.0, "громкость 0 полностью глушит звуки (%.1f dB)" % _sfx_db())

	Music.set_volume(0.55)
	ok(absf(Music.volume - 0.55) < 0.001, "Music.set_volume меняет громкость (%.2f)" % Music.volume)
	cfg.load(CFG)
	ok(absf(float(cfg.get_value("audio", "music", -1.0)) - 0.55) < 0.001, "громкость музыки сохраняется в settings.cfg")

	# значения вне диапазона не ломают громкость
	Sfx.set_volume(5.0)
	ok(absf(Sfx.volume - 1.0) < 0.001, "громкость звуков ограничена сверху (%.2f)" % Sfx.volume)
	Sfx.set_volume(-2.0)
	ok(absf(Sfx.volume) < 0.001, "громкость звуков ограничена снизу (%.2f)" % Sfx.volume)
	Music.set_volume(3.0)
	ok(absf(Music.volume - 1.0) < 0.001, "громкость музыки ограничена сверху (%.2f)" % Music.volume)
	Sfx.set_volume(Sfx.DEFAULT_VOLUME)
	Music.set_volume(Music.DEFAULT_VOLUME)
	ok(absf(_sfx_db() - linear_to_db(Sfx.DEFAULT_VOLUME)) < 0.01, "громкость звуков возвращается (%.1f dB)" % _sfx_db())


## выключенные звуки не тянут за собой музыку, и наоборот
func _check_channels_independent() -> void:
	Sfx.set_muted(true)
	ok(AudioServer.is_bus_mute(0) == false, "mute звуков не глушит общую шину — музыка слышна")
	ok(_sfx_db() <= -60.0, "при mute звуки молчат (%.1f dB)" % _sfx_db())

	# музыка играет, пока звуки выключены
	Music.play("menu")
	_music_now()
	ok(Music.track == "menu" and Music._player.stream != null, "тема меню поставлена на плеер")
	ok(Music._player.volume_db > -60.0, "музыка звучит, пока звуки выключены (%.1f dB)" % Music._player.volume_db)

	Sfx.set_muted(false)
	ok(_sfx_db() > -60.0, "звуки вернулись (%.1f dB)" % _sfx_db())

	# музыка глушится отдельно от звуков
	Music.suspend(true)
	ok(Music._player.volume_db <= -60.0, "музыка замолчала отдельно от звуков (%.1f dB)" % Music._player.volume_db)
	ok(_sfx_db() > -60.0, "звуки при этом остались слышны (%.1f dB)" % _sfx_db())
	Music.suspend(false)
	ok(Music._player.volume_db > -60.0, "музыка вернулась (%.1f dB)" % Music._player.volume_db)

	# реклама по-прежнему глушит оба канала сразу (Sfx.suspend тянет за собой Music)
	Sfx.suspend(true)
	ok(Music.suspended and Sfx.suspended, "реклама глушит всё сразу")
	ok(Music._player.volume_db <= -60.0 and _sfx_db() <= -60.0, "на рекламе молчат оба канала")
	Sfx.suspend(false)
	ok(not Music.suspended and not Sfx.suspended, "после рекламы звук возвращается")
	ok(Music._player.volume_db > -60.0 and _sfx_db() > -60.0, "оба канала снова слышны")


## громкость музыки применяется сразу: плавный фейд в проверке только мешает
func _music_now() -> void:
	if Music._fade != null and Music._fade.is_valid():
		Music._fade.kill()
	Music._apply()


func _sfx_db() -> float:
	var best := -80.0
	for i in Sfx.get_child_count():
		var p: AudioStreamPlayer = Sfx.get_child(i) as AudioStreamPlayer
		if p != null:
			best = maxf(best, p.volume_db)
	return best


# ================================================================= экран настроек


## экран «Настройки»: вход из меню, два ползунка, вкл/выкл, сброс, возврат
func _check_settings_screen() -> void:
	var main = preload("res://scripts/main.gd").new()
	add_child(main)
	for i in 6:
		await get_tree().process_frame
	main.ad_busy = false
	main.screen = "menu"
	main._build_overlay()
	for i in 4:
		await get_tree().process_frame

	# вход в настройки есть прямо в меню
	var btn := _find_button(main.overlay, "Настройки")
	ok(btn != null, "в меню есть кнопка настроек")
	if btn != null:
		btn.emit_signal("pressed")
	for i in 4:
		await get_tree().process_frame
	ok(main.screen == "settings", "кнопка открывает экран настроек (%s)" % main.screen)

	# два ползунка: музыка и звуки
	var sliders := _find_sliders(main.overlay)
	ok(sliders.size() == 2, "на экране настроек два ползунка (%d)" % sliders.size())

	# карточка целиком помещается в окно — считаем по масштабу, как в ui_flow
	var card := _find_card(main.overlay)
	if card == null:
		ok(false, "экран настроек: карточка не найдена")
	else:
		var vs := main.get_viewport().get_visible_rect().size
		var s: float = card.get_meta("fit_scale", 1.0)
		var top := card.position.y + card.size.y * (1.0 - s) * 0.5
		var bottom := top + card.size.y * s
		var left := card.position.x + card.size.x * (1.0 - s) * 0.5
		var right := left + card.size.x * s
		print("     settings fit(scale=%.2f, %d..%d / %d)" % [s, top, bottom, vs.y])
		ok(top >= -2.0 and bottom <= vs.y + 2.0 and left >= -2.0 and right <= vs.x + 2.0,
			"экран настроек помещается (%d×%d из %d×%d)" % [card.size.x, card.size.y, vs.x, vs.y])

	# движение ползунка меняет громкость сразу
	if sliders.size() == 2:
		sliders[0].emit_signal("value_changed", 30.0)
		sliders[1].emit_signal("value_changed", 70.0)
		ok(absf(Music.volume - 0.3) < 0.01, "ползунок музыки меняет громкость (%.2f)" % Music.volume)
		ok(absf(Sfx.volume - 0.7) < 0.01, "ползунок звуков меняет громкость (%.2f)" % Sfx.volume)

	# кнопка вкл/выкл глушит только свой канал
	var off := _find_button(main.overlay, "Звуки: включены")
	ok(off != null, "есть кнопка выключения звуков")
	if off != null:
		off.emit_signal("pressed")
	for i in 4:
		await get_tree().process_frame
	ok(Sfx.muted, "кнопка выключает звуки")
	ok(Music.enabled and AudioServer.is_bus_mute(0) == false, "музыка при этом продолжает играть")
	var on := _find_button(main.overlay, "Звуки: выключены")
	ok(on != null, "подпись кнопки обновилась")
	if on != null:
		on.emit_signal("pressed")
	for i in 4:
		await get_tree().process_frame
	ok(not Sfx.muted, "кнопка включает звуки обратно")

	# сброс возвращает задуманные уровни
	Music.set_volume(0.31)
	Sfx.set_volume(0.77)
	var reset := _find_button(main.overlay, "Сбросить")
	ok(reset != null, "есть кнопка сброса звука")
	if reset != null:
		reset.emit_signal("pressed")
	for i in 4:
		await get_tree().process_frame
	ok(absf(Music.volume - Music.DEFAULT_VOLUME) < 0.001 and absf(Sfx.volume - Sfx.DEFAULT_VOLUME) < 0.001,
		"сброс возвращает громкость по умолчанию (%.2f / %.2f)" % [Music.volume, Sfx.volume])
	ok(Music.enabled and not Sfx.muted, "сброс включает оба канала")

	# «Назад» возвращает туда, откуда пришли
	var back := _find_button(main.overlay, "Назад")
	ok(back != null, "есть кнопка «Назад»")
	if back != null:
		back.emit_signal("pressed")
	for i in 4:
		await get_tree().process_frame
	ok(main.screen == "menu", "«Назад» возвращает в меню (%s)" % main.screen)
	main.queue_free()
	for i in 2:
		await get_tree().process_frame


func _find_card(root: Node) -> PanelContainer:
	for c in root.get_children():
		if c is PanelContainer:
			return c
		var r := _find_card(c)
		if r != null:
			return r
	return null


func _find_button(root: Node, part: String) -> Button:
	for c in root.get_children():
		if c is Button and String(c.text).find(part) >= 0:
			return c
		var r := _find_button(c, part)
		if r != null:
			return r
	return null


func _find_sliders(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_sliders(c))
	return out


# ================================================================= измерения потока


func _peak(st: AudioStreamWAV) -> float:
	if st == null or st.data.is_empty():
		return 0.0
	var d := st.data
	var best := 0
	for i in range(0, d.size() - 1, 2):
		var v := int(d[i]) | (int(d[i + 1]) << 8)
		if v > 32767:
			v -= 65536
		best = maxi(best, abs(v))
	return float(best) / 32768.0


func _rms(st: AudioStreamWAV) -> float:
	if st == null or st.data.is_empty():
		return 0.0
	var d := st.data
	var acc := 0.0
	var n := 0
	for i in range(0, d.size() - 1, 2):
		var v := int(d[i]) | (int(d[i + 1]) << 8)
		if v > 32767:
			v -= 65536
		var f := float(v) / 32768.0
		acc += f * f
		n += 1
	return sqrt(acc / maxf(1.0, float(n)))
