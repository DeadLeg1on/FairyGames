extends Node
## Бот-автоплеер для headless-проверки: проходит все главы, затем проверяет урон/возрождение/проигрыш.
var game
var frame := 0
var phase := "play"
var cleared := 0
var draws_w := 0
var draws_h := 0

func _ready() -> void:
	game = preload("res://scripts/game.gd").new()
	add_child(game)
	game.chapter_cleared.connect(_on_clear)
	game.game_over.connect(func(s, c): print("GAME_OVER score=", s, " chapter=", c); phase = "done")
	game.new_run()
	game.start_chapter(0)
	game.world_node.draw.connect(func(): draws_w += 1)
	game.hud_node.draw.connect(func(): draws_h += 1)

func _on_clear(i, b, s) -> void:
	print("CLEAR chapter=", i, " bonus=", b, " score=", s, " frames=", frame)
	cleared += 1
	if i < 8:
		game.preview(i + 1)
		game.start_chapter(i + 1)
	else:
		phase = "die"
		game.start_chapter(0)
		game.hearts = 0
		game.revive()
		print("REVIVE ok hearts=", game.hearts, " state=", game.state)

func _nearest(kinds: Array, filter := Callable()) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for e in game.ents:
		if kinds.has(e.kind) and (not filter.is_valid() or filter.call(e)):
			var d := Vector2(e.x - game.px, e.y - game.py).length()
			if d < bd:
				bd = d
				best = Vector2(e.x, e.y)
	return best

func _process(_dt: float) -> void:
	frame += 1
	if phase == "done":
		print("RESULT cleared=", cleared, " parts=", game.parts.size(), " ents=", game.ents.size())
		print("DRAWS world=", draws_w, " hud=", draws_h)
		get_tree().quit()
		return
	if phase == "die":
		game.inv = 0.0
		if frame % 90 == 0 and game.state == game.St.PLAY and game.hearts == 1 and not has_meta("revived"):
			set_meta("revived", true)
			game.hearts = 0
			game.revive()
			print("REVIVE ok hearts=", game.hearts)
		# лететь прямо в ос
		var w := _nearest(["wasp"])
		_steer(w if w != Vector2.INF else Vector2(game.W / 2, game.H / 2))
		return
	game.inv = maxf(game.inv, 0.5) # режим бога для прохождения
	var id: String = game.cid()
	var target := Vector2.INF
	match id:
		"flower":
			target = _nearest(["bud"], func(e): return e.b == 0) if game.carry >= 3 else _nearest(["pollen"])
		"water":
			target = _nearest(["flame"]) if game.carry > 0 else _nearest(["drop"])
		"night":
			target = _nearest(["lantern"]) if game.followers >= 3 else _nearest(["firefly"], func(e): return e.b <= 0)
		"frost":
			target = _nearest(["crystal", "flake"])
		"star":
			target = _nearest(["boss"]) if game.carry >= 3 else _nearest(["shard"])
			if game.carry >= 3 and target != Vector2.INF and target.distance_to(Vector2(game.px, game.py)) < 150:
				game.dash_queued = true
		"mushroom":
			for e in game.ents:
				if e.kind == "shroom" and int(e.a) == game.seq_next and not e.dead:
					target = Vector2(e.x, e.y)
		"rainbow":
			target = _nearest(["bubble"], func(e): return (int(e.a) == game.paint or int(e.a) == -1) and e.y < game.gy() - 20)
			if target == Vector2.INF:
				var o := _nearest(["bubble"], func(e): return int(e.a) >= 0)
				if o != Vector2.INF:
					for e in game.ents:
						if e.kind == "bubble" and Vector2(e.x, e.y) == o:
							for pf in game.ents:
								if pf.kind == "paint" and int(pf.a) == int(e.a):
									target = Vector2(pf.x, pf.y)
		"garden":
			target = _nearest(["sprout"]) if game.carry >= 3 else _nearest(["sun"])
		"storm":
			var nest := _nearest(["nest"])
			var sd := _nearest(["seed"])
			if nest != Vector2.INF and sd != Vector2.INF:
				var back := sd + (sd - nest).normalized() * 34.0
				target = back if back.distance_to(Vector2(game.px, game.py)) > 14 else nest
	if target == Vector2.INF:
		target = Vector2(game.W / 2, game.H / 2)
	_steer(target)
	if frame % 45 == 0:
		game.dash_queued = true
	if frame > 60 * 60 * 12:
		print("TIMEOUT in chapter ", id, " progress=", game.progress)
		phase = "done"

func _steer(t: Vector2) -> void:
	game.joy_active = true
	game.joy_o = Vector2(100, 100)
	var d := t - Vector2(game.px, game.py)
	game.joy_p = game.joy_o + (d.normalized() * 50.0 if d.length() > 4 else Vector2.ZERO)
