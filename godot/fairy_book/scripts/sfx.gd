extends Node
## Процедурные звуки (порт src/game/audio.ts). Синтезируются один раз при запуске
## в AudioStreamWAV — никаких аудиофайлов.

const RATE := 22050
const MASTER := 0.5
const SETTINGS := "user://settings.cfg"

var muted := false
var suspended := false
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()
	_apply_bus()


func set_muted(m: bool) -> void:
	muted = m
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "muted", m)
	cfg.save(SETTINGS)
	_apply_bus()


## глушит звук во время рекламы / паузы платформы
func suspend(on: bool) -> void:
	suspended = on
	_apply_bus()


func _apply_bus() -> void:
	AudioServer.set_bus_mute(0, muted or suspended)


func play(sound: String, pitch: float = 1.0) -> void:
	if muted or suspended or not _sounds.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[sound]
	p.pitch_scale = pitch
	p.play()


func pickup(combo: int) -> void:
	play("pickup", pow(2.0, mini(combo, 14) / 12.0))


# ---------------------------------------------------------------- synth

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE) + 1)
	b.fill(0.0)
	return b


func _tone(b: PackedFloat32Array, f: float, d: float, type: String, v: float, f2: float = 0.0, delay: float = 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(d * RATE)
	var phase := 0.0
	for i in n:
		var idx := start + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var freq := f if f2 <= 0.0 else f * pow(f2 / f, t / d)
		phase += freq / RATE
		var ph := fposmod(phase, 1.0)
		var s := 0.0
		match type:
			"sine":
				s = sin(TAU * ph)
			"triangle":
				s = 1.0 - 4.0 * absf(ph - 0.5)
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"sawtooth":
				s = 2.0 * ph - 1.0
		var env: float
		if t < 0.01:
			env = v * t / 0.01
		else:
			env = v * pow(0.0001 / v, (t - 0.01) / maxf(0.001, d - 0.01))
		b[idx] += s * env


func _noise(b: PackedFloat32Array, d: float, v: float, freq: float = 1200.0, delay: float = 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(d * RATE)
	# полосовой biquad (RBJ), Q = 1 как у BiquadFilterNode по умолчанию
	var w0 := TAU * minf(freq, RATE * 0.45) / RATE
	var alpha := sin(w0) / 2.0
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var b2 := -alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 7 + d * 1000)
	for i in n:
		var idx := start + i
		if idx >= b.size():
			break
		var x := rng.randf() * 2.0 - 1.0
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		var t := float(i) / RATE
		var env := v * pow(0.0001 / v, t / d)
		b[idx] += y * env


func _to_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		var s := clampf(b[i] * MASTER, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _build_all() -> void:
	var b: PackedFloat32Array

	b = _buf(0.2)
	_tone(b, 523, 0.12, "triangle", 0.16)
	_tone(b, 523 * 1.5, 0.12, "sine", 0.07, 0.0, 0.04)
	_sounds["pickup"] = _to_wav(b)

	b = _buf(0.18)
	_noise(b, 0.16, 0.12, 2400)
	_tone(b, 280, 0.14, "sine", 0.08, 820)
	_sounds["dash"] = _to_wav(b)

	b = _buf(0.37)
	_tone(b, 220, 0.35, "sawtooth", 0.14, 55)
	_noise(b, 0.25, 0.3, 500)
	_sounds["hit"] = _to_wav(b)

	b = _buf(0.16)
	_tone(b, 760, 0.14, "square", 0.06, 180)
	_noise(b, 0.1, 0.12, 3000)
	_sounds["kill"] = _to_wav(b)

	b = _buf(0.5)
	var notes := [523, 659, 784, 1046]
	for i in notes.size():
		_tone(b, notes[i], 0.28, "triangle", 0.13, 0.0, i * 0.06)
	_sounds["bloom"] = _to_wav(b)

	b = _buf(0.32)
	_noise(b, 0.3, 0.22, 900)
	_tone(b, 900, 0.2, "sine", 0.08, 300)
	_sounds["splash"] = _to_wav(b)

	b = _buf(0.22)
	_noise(b, 0.2, 0.15, 4000)
	_tone(b, 1400, 0.1, "triangle", 0.05, 700)
	_sounds["crash"] = _to_wav(b)

	b = _buf(0.52)
	_tone(b, 120, 0.5, "sawtooth", 0.2, 40)
	_noise(b, 0.5, 0.35, 300)
	_sounds["boom"] = _to_wav(b)

	b = _buf(0.85)
	var wn := [523, 659, 784, 1046, 1318]
	for i in wn.size():
		_tone(b, wn[i], 0.4, "triangle", 0.13, 0.0, i * 0.09)
	_sounds["win"] = _to_wav(b)

	b = _buf(0.95)
	var on := [392, 330, 262, 196]
	for i in on.size():
		_tone(b, on[i], 0.45, "triangle", 0.14, 0.0, i * 0.16)
	_sounds["over"] = _to_wav(b)

	b = _buf(0.08)
	_tone(b, 660, 0.06, "triangle", 0.08)
	_sounds["click"] = _to_wav(b)

	b = _buf(0.22)
	_tone(b, 180, 0.2, "square", 0.05, 90)
	_sounds["boss_shot"] = _to_wav(b)

	b = _buf(0.17)
	_tone(b, 150, 0.15, "square", 0.06)
	_sounds["nocharge"] = _to_wav(b)
