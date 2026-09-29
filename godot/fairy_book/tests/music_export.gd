extends Node
## Служебная сцена: собирает три темы и сохраняет их в wav — музыку можно послушать
## без запуска игры (жанр и стиль удобно проверять на слух, а не по коду).
## Запуск: godot --headless --path godot/fairy_book res://tests/music_export.tscn

const MusicScript := preload("res://scripts/music.gd")
const OUT := "res://music_export"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var n := 0
	var bytes := 0
	for name in MusicScript.track_names():
		var w: AudioStreamWAV = Music.build(name)
		var path := "%s/%s.wav" % [OUT, name]
		var err := w.save_to_wav(path)
		var size := 0
		if FileAccess.file_exists(path):
			size = FileAccess.get_file_as_bytes(path).size()
		bytes += size
		n += 1
		print("EXPORT %s: %s, %.2f с, %d байт" % [name, "ok" if err == OK else "ошибка %d" % err, w.data.size() / float(w.mix_rate), size])
	print("EXPORT тем=%d всего_байт=%d" % [n, bytes])
	get_tree().quit()
