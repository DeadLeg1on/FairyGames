class_name Music
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

var _streams := {}
var _builts := {}
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
static func want_for(screen: String, mode: String) -> String:
	if screen == "play":
		return "hotel" if mode == "idle" else "story"
	if screen == "hotel" or (mode == "idle" and screen != "play"):
		return "hotel"
	return "menu"


func play(name: String) -> void:
	if not _streams.has(name):
		_streams[name] = build(name)
	if track == name and _player.playing:
		return
	track = name
	_player.stream = _streams[name]
	_player.play()
	_apply(true)


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
	for i in count:
		var t := float(i) / RATE
		if t < attack:
			env = peak * (t / attack)
		else:
			if i == int(attack * RATE):
				env = peak
			env *= k
		phase += step
		var s := _wave(table, phase)
		s += harm * _wave(table, phase * 2.02 + 0.13)
		if third > 0.0:
			s += third * _wave(_sine, phase * 3.01)
		# очень мягкое «покачивание» для пада и флейты — живое дыхание
		if kind == "pad" or kind == "flute":
			s *= 1.0 + 0.12 * _wave(_sine, 4.5 * t + pan)
		var idx := start + i
		if idx >= n:
			idx -= n
		_buf[idx] += s * env * (1.0 - 0.18 * pan)


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


static func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = buf.size()
	w.data = data
	return w


## собрать тему в петлю (кэшируется в Music)
func build(name: String) -> AudioStreamWAV:
	if _builts.has(name):
		return _builts[name]
	_build_tables()
	var d: Dictionary = themes()[name]
	var bpm := float(d["bpm"])
	var beats := int(d["beats"])
	var bars := int(d["bars"])
	var beat_s := 60.0 / bpm
	var total := int(length_of(name) * RATE) + 1
	_buf = PackedFloat32Array()
	_buf.resize(total)
	_buf.fill(0.0)
	var chords: Array = d["chords"]
	var bass: Array = d["bass"]
	var pattern: Array = d["arp_pattern"]
	var octave := int(d["arp_octave"])
	var beats_arr: Array = d["bass_beats"]
	var melody: Array = d["melody"]
	for bar in bars:
		var t0 := float(bar * beats) * beat_s
		var chord: Array = chords[bar % chords.size()]
		# подушка: аккорд на весь такт
		for n in chord:
			_voice(float(n), t0, float(beats) * beat_s * 0.98, 0.05, "pad", float(n % 3) * 0.4)
		# щипковый бас на сильных долях
		for bt in beats_arr:
			_voice(float(bass[bar % bass.size()]), t0 + float(bt) * beat_s, beat_s * 1.6, 0.12, "bass")
		# узор из терций аккорда (маримба/арфа)
		var step := float(beats) / float(maxi(1, pattern.size()))
		for i in pattern.size():
			var n2: float = float(chord[int(pattern[i]) % chord.size()] + octave)
			_voice(n2, t0 + float(i) * step * beat_s, step * beat_s * 1.3, 0.055, "harp", float(i % 2) * 0.3)
		# лёгкая щётка
		for bt2 in d["shaker"]:
			_brush(t0 + float(bt2) * beat_s, 0.035, bar)
	# колокольчики-акценты
	for bl in d["bells"]:
		_voice(float(bl[1]), float(bl[0]) * beat_s, 2.2, 0.075, "bell")
	# мелодия
	for m in melody:
		_voice(float(m[0]), float(m[1]) * beat_s, float(m[2]) * beat_s * 0.96, 0.1, "flute")
	# нормализация по пику: тема звучит ровно, клиппинга нет
	var peak := 0.0
	for i in total:
		peak = maxf(peak, absf(_buf[i]))
	var gain := (MASTER / peak) if peak > 0.0001 else 0.0
	for i in total:
		_buf[i] *= gain
	_builts[name] = _to_wav(_buf)
	return _builts[name]
