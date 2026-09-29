extends Node
## Бесконечная охота: снежная глава (сердца за прогресс) и звёздная (возвращение босса).
func _ready():
	var g = load("res://scripts/game.gd").new()
	add_child(g)
	await get_tree().process_frame
	g.new_run("endless")
	g.start_chapter(3)
	g.hearts = 2
	for i in 60 * 40:
		g.inv = 1.0
		# летим к ближайшей снежинке
		var best = null
		for e in g.ents:
			if (e.kind == "flake" or e.kind == "crystal") and (best == null or Vector2(e.x - g.px, e.y - g.py).length() < Vector2(best.x - g.px, best.y - g.py).length()):
				best = e
		if best:
			var d := Vector2(best.x - g.px, best.y - g.py)
			g.px += clampf(d.x, -6, 6)
			g.py += clampf(d.y, -6, 6)
		g._process(1.0 / 60.0)
	print("FROST endless progress=", g.progress, " hearts=", g.hearts, " wave=", g.wave, " state=", g.state, " (не должна закончиться: goal=25)")
	g.new_run("endless")
	g.start_chapter(4)
	var boss = null
	for e in g.ents:
		if e.kind == "boss":
			boss = e
	boss.hp = 1
	g.carry = 3
	g.px = boss.x
	g.py = boss.y
	g.dash_t = 0.1
	g._update_boss(boss, 0.016)
	g._process(0.016)
	print("STAR boss killed: bosses=", g.count("boss"), " state=", g.state)
	for i in 60 * 4:
		g.inv = 1.0
		g._process(1.0 / 60.0)
	print("STAR after 4s: bosses=", g.count("boss"), " (босс вернулся)")
	g.new_run("hard")
	print("HARD hearts=", g.hearts, " mult=", g.score_mult())
	get_tree().quit()
