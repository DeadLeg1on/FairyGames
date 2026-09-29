extends Node2D
## Узел-холст: вызывает переданную функцию рисования в _draw().

var fn: Callable


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
