extends Node
## Процедурная музыка: три темы синтезируются в AudioStreamWAV прямо в игре —
## никаких аудиофайлов, как и у звуков в scripts/sfx.gd.
##
## Темы в одной «карандашной» палитре инструментов (музыкальная шкатулка,
## мягкая флейта, стеклянные колокольчики, щипковый бас и лёгкая щётка):
##   • menu  — «Пыльца на страницах»: тёплая колыбельная в G, 76 bpm, арфа и флейта;
##   • story — «Полёт над лугом»: бодрая тема в D, 112 bpm, маримба, флейта и щётка;
##   • hotel — «Самовар и звёзды»: уютный вальс в C с септаккордами, 96 bpm, шкатулка и бас.
##
## Каждая тема — целое число тактов, свёрнутое в петлю с заворотом «хвостов»
## в начало (последний звук дозвучивает в первых тактах), поэтому шва не слышно.
## Синтез ленивый: тема считается при первом запуске и остаётся в памяти.

const RATE := 16000
const SETTINGS := "user://settings.cfg"
const MASTER := 0.72
const TABLE := 2048

static var _sine: PackedFloat32Array
static var _tri: PackedFloat32Array
## текущий буфер сборки: голоса пишут в него напрямую (см. _voice)
static var _buf := PackedFloat32Array()

var enabled := true
var volume := 0.8
var suspended := false
var track := ""

const BUDGET_USEC := 6000
## сколько сэмплов обрабатываем за одну порцию при нормализации и кодировании
const CHUNK := 24000

var _streams := {}
var _builts := {}
## тема, которую ждём: как только она соберётся — заиграет
var _pending := ""
## текущая пошаговая сборка: {"name": String, "phase": int}
var _job := {}
var _job_name := ""
## байты собираемой темы: заполняются порциями на фазе «encode»
var _bytes := PackedByteArray()
var _player: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		enabled = bool(cfg.get_value("audio", "music_on", true))
		volume = clampf(float(cfg.get_value("audio", "music", 0.8)), 0.0, 1.0)
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = -80.0
	add_child(_player)
	_apply()


# ------------------------------------------------------------------ управление

## какая тема подходит экрану: меню, главам или отелю
## in_hotel — открыт ли отель прямо сейчас (чтобы его экраны не сбивались на меню)
static func want_for(screen: String, mode: String, in_hotel: bool = false) -> String:
	if screen == "play":
		return "hotel" if mode == "idle" else "story"
	if screen == "hotel":
		return "hotel"
	if in_hotel and ["shop", "scores", "rewards", "modes"].has(screen):
		return "hotel"
	return "menu"


func play(name: String) -> void:
	track = name
	if not _streams.has(name):
		# первая сборка идёт по кадрам, чтобы не морозить игру; как соберётся — заиграет
		_pending = name
		build_async(name)
		return
	if _player.stream == _streams[name] and _player.playing:
		return
	_player.stream = _streams[name]
	_player.play()
	_apply(true)


func is_built(name: String) -> bool:
	return _streams.has(name)


## «забыть» собранную тему (нужно проверкам: сборка снова пойдёт по кадрам)
func forget(name: String) -> void:
	_streams.erase(name)
	_builts.erase(name)
	if _pending == name:
		_pending = ""


## пошаговая сборка: движок отдаёт по кадру, пока не закончится бюджет
func _process(_dt: float) -> void:
	if _job.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _job.is_empty() and Time.get_ticks_usec() - t0 < BUDGET_USEC:
		_advance()
	if _job.is_empty():
		_finish_job()


func stop() -> void:
	track = ""
	_player.stop()


func set_enabled(on: bool) -> void:
	enabled = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "music_on", on)
	cfg.save(SETTINGS)
	_apply(true)


func toggle() -> void:
	set_enabled(not enabled)


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "music", volume)
	cfg.save(SETTINGS)
	_apply()


## заглушить на время рекламы и паузы платформы
func suspend(on: bool) -> void:
	suspended = on
	_apply()


func _apply(fade: bool = false) -> void:
	if _player == null:
		return
	var target := -80.0 if (not enabled or suspended or track == "") else linear_to_db(maxf(0.001, volume))
	if _player.volume_db == target:
		return
	if not fade:
		_player.volume_db = target
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", target, 0.6)


# ------------------------------------------------------------------ темы

## описание темы: темп, размер, аккорды, узоры и мелодия
static func themes() -> Dictionary:
	return {
		"menu": {
			"title": "Пыльца на страницах",
			"bpm": 76.0, "beats": 4, "bars": 8,
			"chords": [[55, 59, 62], [52, 55, 59], [48, 55, 60], [50, 57, 62],
				[55, 59, 62], [52, 55, 59], [48, 52, 55], [50, 54, 57, 60]],
			"arp_pattern": [0, 1, 2, 2, 1, 0, 1, 2],
			"arp_octave": 12,
			"bass": [43, 40, 36, 38, 43, 40, 36, 38],
			"bass_beats": [0.0, 2.0],
			"bells": [[0.0, 79], [16.0, 83]],
			"shaker": [],
			"melody": [
				[74, 0.0, 1.5], [76, 1.5, 0.5], [78, 2.0, 2.0],
				[74, 4.0, 1.0], [71, 5.0, 1.0], [69, 6.0, 2.0],
				[72, 8.0, 1.0], [74, 9.0, 1.0], [76, 10.0, 2.0],
				[74, 12.0, 1.0], [71, 13.0, 1.0], [69, 14.0, 2.0],
				[74, 16.0, 1.5], [76, 17.5, 0.5], [79, 18.0, 2.0],
				[78, 20.0, 1.0], [74, 21.0, 1.0], [71, 22.0, 2.0],
				[72, 24.0, 1.0], [74, 25.0, 1.0], [76, 26.0, 1.0], [74, 27.0, 1.0],
				[71, 28.0, 1.0], [69, 29.0, 3.0],
			],
		},
		"story": {
			"title": "Полёт над лугом",
			"bpm": 112.0, "beats": 4, "bars": 8,
			"chords": [[50, 57, 62], [45, 52, 57], [47, 54, 59], [43, 50, 55],
				[50, 57, 62], [45, 52, 57], [43, 50, 55], [45, 52, 57]],
			"arp_pattern": [0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1],
			"arp_octave": 12,
			"bass": [38, 45, 47, 43, 38, 45, 43, 45],
			"bass_beats": [0.0, 2.0],
			"bells": [],
			"shaker": [0.5, 1.5, 2.5, 3.5],
			"melody": [
				[74, 0.0, 1.0], [78, 1.0, 1.0], [81, 2.0, 2.0],
				[79, 4.0, 1.0], [78, 5.0, 1.0], [76, 6.0, 2.0],
				[74, 8.0, 1.0], [76, 9.0, 1.0], [78, 10.0, 2.0],
				[76, 12.0, 1.0], [74, 13.0, 3.0],
				[81, 16.0, 1.0], [83, 17.0, 1.0], [81, 18.0, 2.0],
				[79, 20.0, 1.0], [78, 21.0, 1.0], [76, 22.0, 2.0],
				[78, 24.0, 1.0], [79, 25.0, 1.0], [81, 26.0, 2.0],
				[83, 28.0, 1.0], [81, 29.0, 2.0], [78, 31.0, 1.0],
			],
		},
		"hotel": {
			"title": "Самовар и звёзды",
			"bpm": 96.0, "beats": 3, "bars": 8,
			"chords": [[48, 55, 64], [45, 52, 60, 67], [41, 48, 57], [43, 50, 59, 65],
				[48, 55, 64], [45, 52, 60, 67], [38, 45, 53, 60], [43, 50, 59, 65]],
			"arp_pattern": [1, 2, 1],
			"arp_octave": 12,
			"bass": [36, 33, 41, 43, 36, 33, 38, 43],
			"bass_beats": [0.0],
			"bells": [[0.0, 84], [12.0, 88]],
			"shaker": [1.0, 4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 22.0],
			"melody": [
				[76, 0.0, 1.0], [79, 1.0, 1.0], [76, 2.0, 1.0],
				[72, 3.0, 1.0], [76, 4.0, 1.0], [69, 5.0, 1.0],
				[77, 6.0, 1.0], [81, 7.0, 1.0], [77, 8.0, 1.0],
				[74, 9.0, 1.0], [79, 10.0, 1.0], [71, 11.0, 1.0],
				[72, 12.0, 1.0], [76, 13.0, 1.0], [79, 14.0, 1.0],
				[81, 15.0, 1.0], [76, 16.0, 1.0], [72, 17.0, 1.0],
				[74, 18.0, 1.0], [77, 19.0, 1.0], [81, 20.0, 1.0],
				[79, 21.0, 1.0], [74, 22.0, 2.0],
			],
		},
	}


static func track_names() -> Array:
	return ["menu", "story", "hotel"]


## длительность темы в секундах
static func length_of(name: String) -> float:
	var d: Dictionary = themes()[name]
	return float(d["bars"]) * float(d["beats"]) * 60.0 / float(d["bpm"])


# ------------------------------------------------------------------ синтез

static func _build_tables() -> void:
	if _sine != null and _sine.size() == TABLE:
		return
	_sine = PackedFloat32Array()
	_tri = PackedFloat32Array()
	_sine.resize(TABLE)
	_tri.resize(TABLE)
	for i in TABLE:
		var ph := float(i) / TABLE
		_sine[i] = sin(TAU * ph)
		_tri[i] = 1.0 - 4.0 * absf(ph - 0.5)


static func _wave(table: PackedFloat32Array, phase: float) -> float:
	var x := fposmod(phase, 1.0) * TABLE
	var i := int(x)
	var f := x - float(i)
	var a := table[i]
	var b := table[(i + 1) % TABLE]
	return a + (b - a) * f


static func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


## один голос: пишем ноту в общий буфер с заворотом «хвоста» в начало петли
static func _voice(note: float, at: float, dur: float, amp: float, kind: String, pan: float = 0.0) -> void:
	var n := _buf.size()
	var start := int(at * RATE)
	var count := int(dur * RATE)
	if count <= 2 or n == 0:
		return
	var f := _midi(note)
	var step := f / RATE
	var phase := 0.0
	# формы и огибающие для каждого инструмента (без трансцендентных в цикле)
	var attack := 0.006
	var decay := 3.2
	var harm := 0.35
	var table := _tri
	var third := 0.15
	match kind:
		"harp":
			attack = 0.004
			decay = 3.6
			harm = 0.4
			third = 0.18
		"bell":
			attack = 0.003
			decay = 2.1
			harm = 0.55
			third = 0.22
			table = _sine
		"flute":
			attack = 0.05
			decay = 1.1
			harm = 0.22
			third = 0.05
			table = _sine
		"bass":
			attack = 0.008
			decay = 4.6
			harm = 0.25
			third = 0.0
		"pad":
			attack = 0.35
			decay = 0.55
			harm = 0.18
			third = 0.0
		"glass":
			attack = 0.01
			decay = 5.5
			harm = 0.6
			third = 0.25
			table = _sine
	var k := exp(-decay / RATE)  # множитель затухания за один шаг
	var env := 0.0
	var peak := amp
	var hold := 0.0
	# у мягкой подушки волну считаем через сэмпл: разницы не слышно, а сборка вдвое легче
	var stride := 2 if kind == "pad" else 1
	for i in count:
		var t := float(i) / RATE
		if t < attack:
			env = peak * (t / attack)
		else:
			if i == int(attack * RATE):
				env = peak
			env *= k
		if i % stride == 0:
			phase += step * float(stride)
			var s := _wave(table, phase)
			s += harm * _wave(table, phase * 2.02 + 0.13)
			if third > 0.0:
				s += third * _wave(_sine, phase * 3.01)
			# очень мягкое «покачивание» для пада и флейты — живое дыхание
			if kind == "pad" or kind == "flute":
				s *= 1.0 + 0.12 * _wave(_sine, 4.5 * t + pan)
			hold = s
		var idx := start + i
		if idx >= n:
			idx -= n
		_buf[idx] += hold * env * (1.0 - 0.18 * pan)


## щётка: короткий шум с высокочастотным уклоном
static func _brush(at: float, amp: float, seed_i: int) -> void:
	var n := _buf.size()
	var start := int(at * RATE)
	var count := int(0.07 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed_i * 17
	var prev := 0.0
	var k := exp(-38.0 / RATE)
	var env := amp
	for i in count:
		var x := rng.randf() * 2.0 - 1.0
		var y := x - prev * 0.75  # грубый high-pass
		prev = x
		env *= k
		var idx := start + i
		if idx >= n:
			idx -= n
		_buf[idx] += y * env


## собрать тему целиком (синхронно): используется проверками и тестами
func build(name: String) -> AudioStreamWAV:
	if _builts.has(name):
		return _builts[name]
	_start_job(name)
	while not _job.is_empty():
		_advance()
	_finish_job()
	return _builts[name]


## поставить тему в очередь пошаговой сборки
func build_async(name: String) -> void:
	if _builts.has(name):
		return
	if not _job.is_empty() and str(_job["name"]) == name:
		return
	_start_job(name)


func _start_job(name: String) -> void:
	_build_tables()
	_buf = PackedFloat32Array()
	_buf.resize(int(length_of(name) * RATE) + 1)
	_buf.fill(0.0)
	_bytes = PackedByteArray()
	_job = {"name": name, "state": "notes", "i": 0, "notes": _notes_of(name), "cursor": 0, "peak": 0.0, "gain": 1.0}


## все звуки темы по отдельности: бюджет сборки считается по одной ноте
static func _notes_of(name: String) -> Array:
	var d: Dictionary = themes()[name]
	var bars := int(d["bars"])
	var beats := int(d["beats"])
	var beat_s := 60.0 / float(d["bpm"])
	var chords: Array = d["chords"]
	var bass: Array = d["bass"]
	var pattern: Array = d["arp_pattern"]
	var octave := int(d["arp_octave"])
	var out := []
	for bar in bars:
		var t0 := float(bar * beats) * beat_s
		var chord: Array = chords[bar % chords.size()]
		for n in chord:
			out.append({"kind": "pad", "note": float(n), "at": t0, "dur": float(beats) * beat_s * 0.98, "amp": 0.05, "pan": float(n % 3) * 0.4})
		for bt in d["bass_beats"]:
			out.append({"kind": "bass", "note": float(bass[bar % bass.size()]), "at": t0 + float(bt) * beat_s, "dur": beat_s * 1.6, "amp": 0.12, "pan": 0.0})
		var step := float(beats) / float(maxi(1, pattern.size()))
		for i in pattern.size():
			out.append({"kind": "harp", "note": float(chord[int(pattern[i]) % chord.size()] + octave),
				"at": t0 + float(i) * step * beat_s, "dur": step * beat_s * 1.3, "amp": 0.055, "pan": float(i % 2) * 0.3})
		for bt2 in d["shaker"]:
			out.append({"kind": "brush", "at": t0 + float(bt2) * beat_s, "amp": 0.035, "seed": bar})
	for bl in d["bells"]:
		out.append({"kind": "bell", "note": float(bl[1]), "at": float(bl[0]) * beat_s, "dur": 2.2, "amp": 0.075, "pan": 0.0})
	for m in d["melody"]:
		out.append({"kind": "flute", "note": float(m[0]), "at": float(m[1]) * beat_s, "dur": float(m[2]) * beat_s * 0.96, "amp": 0.1, "pan": 0.0})
	return out


func _advance() -> void:
	if _job.is_empty():
		return
	var name := str(_job["name"])
	_job_name = name
	var n := _buf.size()
	match str(_job["state"]):
		"notes":
			var notes: Array = _job["notes"]
			var i := int(_job["i"])
			var item: Dictionary = notes[i]
			if str(item["kind"]) == "brush":
				_brush(float(item["at"]), float(item["amp"]), int(item["seed"]))
			else:
				_voice(float(item["note"]), float(item["at"]), float(item["dur"]), float(item["amp"]), str(item["kind"]), float(item["pan"]))
			_job["i"] = i + 1
			if i + 1 >= notes.size():
				_job["state"] = "peak"
				_job["cursor"] = 0
		"peak":
			var cur := int(_job["cursor"])
			var end := mini(n, cur + CHUNK)
			var peak := float(_job["peak"])
			for i in range(cur, end):
				peak = maxf(peak, absf(_buf[i]))
			_job["peak"] = peak
			_job["cursor"] = end
			if end >= n:
				_job["gain"] = (MASTER / peak) if peak > 0.0001 else 0.0
				_job["state"] = "scale"
				_job["cursor"] = 0
		"scale":
			var cur2 := int(_job["cursor"])
			var end2 := mini(n, cur2 + CHUNK)
			var gain := float(_job["gain"])
			for i in range(cur2, end2):
				_buf[i] *= gain
			_job["cursor"] = end2
			if end2 >= n:
				_bytes.resize(n * 2)
				_job["state"] = "encode"
				_job["cursor"] = 0
		"encode":
			var cur3 := int(_job["cursor"])
			var end3 := mini(n, cur3 + CHUNK)
			for i in range(cur3, end3):
				_bytes.encode_s16(i * 2, int(clampf(_buf[i], -1.0, 1.0) * 32767.0))
			_job["cursor"] = end3
			if end3 >= n:
				_job["state"] = "seal"
		"seal":
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = RATE
			w.stereo = false
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = n
			w.data = _bytes
			_job = {}
			_store(name, w)


## тема готова: запоминаем и запускаем, если её ждали
func _store(name: String, w: AudioStreamWAV) -> void:
	_builts[name] = w
	_streams[name] = w
	if _pending == name:
		_pending = ""
		_player.stream = w
		_player.play()
		_apply(true)


func _finish_job() -> void:
	_job_name = ""


## тема готова: запоминаем и запускаем, если её ждали
func _store(name: String, w: AudioStreamWAV) -> void:
	_builts[name] = w
	_streams[name] = w
	if _pending == name:
		_pending = ""
		_player.stream = w
		_player.play()
		_apply(true)


func _finish_job() -> void:
	_job_name = ""


func _render_bar(name: String, bar: int) -> void:
	var d: Dictionary = themes()[name]
	var bpm := float(d["bpm"])
	var beats := int(d["beats"])
	var beat_s := 60.0 / bpm
	var t0 := float(bar * beats) * beat_s
	var chords: Array = d["chords"]
	var chord: Array = chords[bar % chords.size()]
	for n in chord:
		_voice(float(n), t0, float(beats) * beat_s * 0.98, 0.05, "pad", float(n % 3) * 0.4)
	var bass: Array = d["bass"]
	for bt in d["bass_beats"]:
		_voice(float(bass[bar % bass.size()]), t0 + float(bt) * beat_s, beat_s * 1.6, 0.12, "bass")
	var pattern: Array = d["arp_pattern"]
	var octave := int(d["arp_octave"])
	var step := float(beats) / float(maxi(1, pattern.size()))
	for i in pattern.size():
		var n2: float = float(chord[int(pattern[i]) % chord.size()] + octave)
		_voice(n2, t0 + float(i) * step * beat_s, step * beat_s * 1.3, 0.055, "harp", float(i % 2) * 0.3)
	for bt2 in d["shaker"]:
		_brush(t0 + float(bt2) * beat_s, 0.035, bar)
	var span := float(beats)
	for bl in d["bells"]:
		if float(bl[0]) >= float(bar) * span and float(bl[0]) < float(bar + 1) * span:
			_voice(float(bl[1]), float(bl[0]) * beat_s, 2.2, 0.075, "bell")
	for m in d["melody"]:
		if float(m[1]) >= float(bar) * span and float(m[1]) < float(bar + 1) * span:
			_voice(float(m[0]), float(m[1]) * beat_s, float(m[2]) * beat_s * 0.96, 0.1, "flute")


