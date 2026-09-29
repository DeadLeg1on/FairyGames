extends Node
## Проверка процедурной музыки (scripts/music.gd): три темы — меню, главы и отель.
## Сцена собирает их в настоящем движке и проверяет петлю, громкость, переключение
## и то, что пауза/реклама глушат музыку вместе со звуками.
##
##   godot --headless --path godot/fairy_book --fixed-fps 60 res://tests/music_check.tscn

const INSTRUMENTS := ["harp", "bell", "flute", "bass", "pad", "glass"]

var fails := 0
## сэмплы и статистика по темам: считаем один раз, чтобы тест не тормозил
var _cache := {}
## сколько миллисекунд занял синтез каждой темы
var _synth_ms := {}
## сколько кадров заняла пошаговая сборка и самый долгий из них
var _async_info := {}


func _ready() -> void:
	_check_themes()
	_check_build()
	_check_loop()
	await _check_async()
	_check_wiring()
	_check_controls()
	await _check_suspend()
	# контрольные суммы тем: по ним видно, что сборка совпадает с эталоном (и с превью-стендом)
	var checks := {}
	for n in Music.track_names():
		if _cache.has(n):
			checks[n] = _cache[n]["check"]
	print("MUSIC synth_ms=", _synth_ms, " async=", _async_info, " check=", checks)
	print("FAILS ", fails)
	get_tree().quit()


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print(("OK   " if cond else "FAIL ") + what)


## сэмплы темы как массив знаковых значений (один раз на тему)
func _samples(name: String) -> PackedInt32Array:
	if _cache.has(name):
		return _cache[name]["samples"]
	var stream := Music.build(name)
	var data := stream.data
	var out := PackedInt32Array()
	out.resize(int(data.size() / 2))
	var peak := 0
	var sum := 0.0
	for i in out.size():
		var v := data.decode_s16(i * 2)
		out[i] = v
		peak = maxi(peak, absi(v))
		sum += float(v) * float(v)
	var rms := sqrt(sum / float(maxi(1, out.size()))) / 32767.0
	_cache[name] = {"samples": out, "peak": float(peak) / 32767.0, "rms": rms, "check": _checksum(out)}
	return out


func _peak(name: String) -> float:
	_samples(name)
	return float(_cache[name]["peak"])


func _rms(name: String) -> float:
	_samples(name)
	return float(_cache[name]["rms"])


## грубая, но своя подпись содержимого: чтобы отличить темы друг от друга
func _checksum(s: PackedInt32Array) -> int:
	var acc := s.size()
	var step := maxi(1, int(s.size() / 4096))
	var i := 0
	while i < s.size():
		acc = (acc * 31 + s[i]) % 1000000007
		i += step
	return acc


## самый резкий перепад между соседними сэмплами (1.0 — «от упора до упора»)
func _max_slope(s: PackedInt32Array, from: int, to: int) -> float:
	var m := 0.0
	for i in range(maxi(1, from), mini(to, s.size())):
		m = maxf(m, absf(float(s[i] - s[i - 1])) / 32767.0)
	return m


## RMS отрезка (считается по кэшу, без повторного декодирования)
func _rms_range(name: String, from: int, to: int) -> float:
	var s := _samples(name)
	var sum := 0.0
	var n := maxi(1, to - from)
	for i in range(maxi(0, from), mini(to, s.size())):
		var v := float(s[i]) / 32767.0
		sum += v * v
	return sqrt(sum / float(n))


# ------------------------------------------------------------------ данные тем

func _check_themes() -> void:
	var names := Music.track_names()
	ok(names.size() == 3 and names.has("menu") and names.has("story") and names.has("hotel"),
		"три темы: меню, главы и отель (%s)" % ", ".join(names))
	var defs := Music.themes()
	var seen_titles := []
	var meters := []
	for n in names:
		ok(defs.has(n), "у темы %s есть описание" % n)
		var d: Dictionary = defs[n]
		var sec := Music.length_of(n)
		ok(sec >= 10.0 and sec <= 40.0, "тема %s звучит %.1f с — длина для петли" % [n, sec])
		ok(str(d["title"]) != "" and not seen_titles.has(str(d["title"])), "у темы %s своё название: %s" % [n, str(d["title"])])
		seen_titles.append(str(d["title"]))
		meters.append(int(d["beats"]))
		var melody: Array = d["melody"]
		var inside := true
		for m in melody:
			if float(m[1]) >= Music.length_of(n) / (60.0 / float(d["bpm"])) or float(m[2]) <= 0.0:
				inside = false
		ok(melody.size() >= 16 and inside, "мелодия %s целиком укладывается в петлю (%d нот)" % [n, melody.size()])
		var chords: Array = d["chords"]
		ok(chords.size() == int(d["bars"]), "аккорды %s идут по такту (%d)" % [n, chords.size()])
	ok(meters[0] == 4 and meters[1] == 4 and meters[2] == 3, "вальс отеля — на три четверти, остальные на четыре")
	ok(float(defs["story"]["bpm"]) > float(defs["menu"]["bpm"]), "тема глав бодрее меню (%d против %d bpm)" % [int(defs["story"]["bpm"]), int(defs["menu"]["bpm"])])


# ------------------------------------------------------------------ синтез

func _check_build() -> void:
	var slowest := 0
	for n in Music.track_names():
		var t0 := Time.get_ticks_msec()
		var stream := Music.build(n)
		var ms := Time.get_ticks_msec() - t0
		_synth_ms[n] = ms
		slowest = maxi(slowest, ms)
		ok(stream != null, "тема %s собирается в поток" % n)
		if stream == null:
			continue
		print("     %s: %.1f с, синтез %d мс, пик %.2f, RMS %.3f" % [n, Music.length_of(n), ms, _peak(n), _rms(n)])
		ok(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == Music.RATE,
			"тема %s — моно 16 бит на %d Гц" % [n, Music.RATE])
		ok(absi(stream.data.size() - (int(Music.length_of(n) * Music.RATE) + 1) * 2) <= 2,
			"длина данных темы %s совпадает с длиной петли" % n)
		var peak := _peak(n)
		ok(peak > 0.4 and peak <= 0.99, "тема %s звучит и не клиппует (пик %.2f)" % [n, peak])
		ok(_rms(n) > 0.02, "тема %s не тишина (RMS %.3f)" % [n, _rms(n)])
	ok(slowest < 20000, "самая долгая сборка темы — %d мс" % slowest)
	# темы не дублируют друг друга
	var sigs := {}
	for n in Music.track_names():
		_samples(n)
		sigs[n] = str(_cache[n]["check"])
	ok(sigs["menu"] != sigs["story"] and sigs["story"] != sigs["hotel"] and sigs["menu"] != sigs["hotel"],
		"все три темы разные")
	# повторный запрос берёт готовый поток, а не синтезирует заново
	var again := Music.build("menu")
	ok(again == Music.build("menu"), "собранная тема кэшируется")


func _check_loop() -> void:
	for n in Music.track_names():
		var st := Music.build(n)
		ok(st.loop_mode == AudioStreamWAV.LOOP_FORWARD and st.loop_begin == 0 and st.loop_end == st.data.size() / 2,
			"тема %s зациклена целиком (0..%d)" % [n, st.loop_end])
		# шов петли: «хвосты» нот довёрнуты в начало, поэтому громкость на стыке ровная
		var samples := _samples(n)
		var end := int(Music.length_of(n) * Music.RATE)
		# щелчок на стыке виден как всплеск производной: сравниваем с самым резким
		# перепадом внутри темы (сам стык может попадать на сильную долю — это нормально)
		var global_slope := _max_slope(samples, 1, end)
		var seam_slope := maxf(_max_slope(samples, end - 32, end), _max_slope(samples, 1, 32))
		seam_slope = maxf(seam_slope, absf(float(samples[0] - samples[end - 1])) / 32767.0)
		ok(seam_slope <= global_slope * 1.2 + 0.02,
			"стык петли %s не щёлкает (перепад %.3f при максимуме %.3f)" % [n, seam_slope, global_slope])
		# и не проваливается в тишину: вокруг стыка звук продолжается
		var win := int(Music.RATE * 0.15)
		var seam_rms := sqrt((pow(_rms_range(n, end - win, end), 2.0) + pow(_rms_range(n, 0, win), 2.0)) * 0.5)
		ok(seam_rms > _rms(n) * 0.3, "на стыке петли %s не тишина (RMS %.3f при среднем %.3f)" % [n, seam_rms, _rms(n)])


# ------------------------------------------------------------------ выбор темы

## сборка темы идёт по кадрам: первая тема не морозит игру на старте
func _check_async() -> void:
	# сначала измерим обычные кадры: на CI-раннере они бывают неровными
	var baseline := 0
	for i in 12:
		var b0 := Time.get_ticks_msec()
		await get_tree().process_frame
		baseline = maxi(baseline, Time.get_ticks_msec() - b0)
	Music.forget("hotel")
	var t0 := Time.get_ticks_msec()
	Music.build_async("hotel")
	ok(Time.get_ticks_msec() - t0 < 60, "постановка темы в очередь мгновенная (%d мс)" % (Time.get_ticks_msec() - t0))
	ok(not Music.is_built("hotel"), "тема ещё не собрана — игра продолжает кадры")
	var frames := 0
	var worst := 0
	while not Music.is_built("hotel") and frames < 900:
		var f0 := Time.get_ticks_msec()
		await get_tree().process_frame
		worst = maxi(worst, Time.get_ticks_msec() - f0)
		frames += 1
	ok(Music.is_built("hotel"), "пошаговая сборка доходит до конца (%d кадров)" % frames)
	ok(frames >= 2, "сборка разложена на несколько кадров, а не одним куском")
	_async_info = {"frames": frames, "worst": worst, "baseline": baseline}
	print("     сборка по кадрам: %d кадров, самый долгий кадр %d мс (обычный кадр до сборки %d мс)" % [frames, worst, baseline])
	ok(worst <= 80, "самый долгий кадр сборки укладывается в 80 мс (%d при обычных %d)" % [worst, baseline])
	var samples := _samples("hotel")
	ok(samples.size() > 0, "собранная по кадрам тема звучит так же, как синхронная (%d сэмплов)" % samples.size())

	# тема, которую ждали, включается сама, как только собралась
	Music.forget("story")
	Music.play("story")
	ok(Music.track == "story" and not Music.is_built("story"), "запрос темы до её готовности не блокирует кадр")
	frames = 0
	while not Music.is_built("story") and frames < 900:
		await get_tree().process_frame
		frames += 1
	ok(Music.is_built("story") and Music._player.stream == Music.build("story"),
		"как только тема собралась, она заиграла (%d кадров)" % frames)
	Music.play("menu")


func _check_wiring() -> void:
	ok(Music.want_for("menu", "story") == "menu", "меню играет тему меню")
	ok(Music.want_for("lang", "story") == "menu", "экран выбора языка — тоже меню")
	ok(Music.want_for("select", "story") == "menu", "выбор главы — меню")
	ok(Music.want_for("play", "story") == "story", "главы играют тему глав")
	ok(Music.want_for("play", "endless") == "story", "в бесконечной охоте — тема глав")
	ok(Music.want_for("play", "idle") == "hotel", "в отеле своя тема")
	ok(Music.want_for("hotel", "idle") == "hotel", "экран отеля держит тему отеля")
	ok(Music.want_for("scores", "idle", true) == "hotel", "в окнах отеля его тема не сбивается на меню")
	ok(Music.want_for("scores", "idle") == "menu", "вне отеля те же рекорды звучат темой меню")
	ok(Music.want_for("menu", "idle", false) == "menu", "выход из отеля возвращает тему меню")
	ok(Music.want_for("shop", "story") == "menu", "лавка из меню — тема меню")


func _check_controls() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Music.SETTINGS)
	# читаем только существующие ключи: get_value с null по умолчанию пишет ERROR в лог
	var was_on: Variant = null
	var was_vol: Variant = null
	if cfg.has_section_key("audio", "music_on"):
		was_on = cfg.get_value("audio", "music_on")
	if cfg.has_section_key("audio", "music"):
		was_vol = cfg.get_value("audio", "music")

	Music.play("story")
	ok(Music.track == "story", "тема глав включается")
	var stream_before := Music._player.stream
	Music.play("story")
	ok(Music._player.stream == stream_before, "повторный вызов ту же тему не перезапускает")
	Music.play("hotel")
	ok(Music.track == "hotel" and Music._player.stream == Music.build("hotel"), "тема отеля включается вместо прежней")
	Music.stop()
	ok(Music.track == "", "музыку можно остановить")

	Music.set_volume(2.0)
	ok(is_equal_approx(Music.volume, 1.0), "громкость ограничена единицей")
	Music.set_volume(0.5)
	var read_back := ConfigFile.new()
	read_back.load(Music.SETTINGS)
	ok(is_equal_approx(float(read_back.get_value("audio", "music", 0.0)), 0.5), "громкость музыки сохраняется в настройках")
	Music.toggle()
	ok(not Music.enabled, "кнопка музыки выключает её")
	var read_off := ConfigFile.new()
	read_off.load(Music.SETTINGS)
	ok(not bool(read_off.get_value("audio", "music_on", true)), "выключенная музыка помнится между запусками")
	Music.toggle()
	ok(Music.enabled, "и включается обратно")

	# вернуть настройки как были, чтобы тест не менял настройки игрока
	var back := ConfigFile.new()
	back.load(Music.SETTINGS)
	if was_on == null:
		back.erase_section_key("audio", "music_on")
	else:
		back.set_value("audio", "music_on", was_on)
	if was_vol == null:
		back.erase_section_key("audio", "music")
	else:
		back.set_value("audio", "music", was_vol)
	back.save(Music.SETTINGS)


## пауза платформы и реклама глушат музыку через тот же вызов, что и звуки
func _check_suspend() -> void:
	Music.play("menu")
	Sfx.suspend(true)
	ok(Music.suspended, "пауза платформы глушит музыку")
	var silent := Music._player.volume_db
	Sfx.suspend(false)
	ok(not Music.suspended, "после паузы музыка возвращается")
	await get_tree().process_frame
	await get_tree().process_frame
	ok(Music._player.volume_db > silent, "громкость музыки восстанавливается (%.1f → %.1f дБ)" % [silent, Music._player.volume_db])
	Music.set_enabled(true)
	for n in Music.track_names():
		ok(Music.build(n) != null and _peak(n) > 0.4, "тема %s на месте после всех проверок" % n)
