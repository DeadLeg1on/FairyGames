class_name Scores
## Локальная таблица рекордов (топ-10) в user://

const FILE := "user://fairy_book_scores.json"


## у каждого режима свой файл: story -> прежний файл (совместимость)
static func path_for(mode: String) -> String:
	return FILE if mode == "story" or mode == "" else "user://fairy_book_%s_scores.json" % mode


static func load_all(mode: String = "story") -> Array:
	var file := path_for(mode)
	if not FileAccess.file_exists(file):
		return []
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return []
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_ARRAY:
		return []
	return data


static func _write(list: Array, mode: String = "story") -> void:
	var f := FileAccess.open(path_for(mode), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(list))


static func _cmp(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("score", 0)) > float(b.get("score", 0))


## сохраняет запись, возвращает [список, индекс новой записи или -1]
static func save(entry: Dictionary, mode: String = "story") -> Array:
	var list := load_all(mode)
	list.append(entry)
	list.sort_custom(_cmp)
	if list.size() > 10:
		list.resize(10)
	_write(list, mode)
	var idx := -1
	for i in list.size():
		if int(list[i].get("date", 0)) == int(entry["date"]):
			idx = i
			break
	return [list, idx]


static func remove(date: int, mode: String = "story") -> Array:
	var list := load_all(mode).filter(func(e): return int(e.get("date", 0)) != date)
	_write(list, mode)
	return list
