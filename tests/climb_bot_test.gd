extends SceneTree
# Drives a rival ClimberBird (the in-game AI, on the real Player physics) up
# the generated route, to check that movement, landing and stamina actually
# let a bird climb, and that the rivals' AI works.
# Run:  godot --headless --path . -s tests/climb_bot_test.gd

const DT := 1.0 / 60.0
const GOAL_CHUNK := 20               # 240 m, into the third band
const MAX_TIME := 600.0

func _init() -> void:
	var tower := TowerGenerator.new()
	root.add_child(tower)
	tower.reset(42)
	var bot := ClimberBird.new()
	bot.tower = tower
	bot.make(false)
	root.add_child(bot)
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.place(0.0, TowerShape.apothem(0) + 1.5, 0.0)

	var stats := {"landings": 0, "falls": 0}
	bot.landed.connect(func(h): stats.landings += 1; if h > 6.0: stats.falls += 1)
	var t := 0.0
	var min_margin := INF
	while t < MAX_TIME and TowerShape.chunk_at(bot.max_y) < GOAL_CHUNK:
		bot._physics_process(DT)
		tower.tick(DT)
		t += DT
		min_margin = min(min_margin, bot.r - TowerShape.wall_r(TowerShape.chunk_at(bot.y + 0.05), bot.theta))
		assert(bot.stamina >= -0.001 and bot.stamina <= bot.max_stamina + 0.001)
		if int(t / DT) % 3600 == 0:
			print("t=%3ds  y=%6.1f  max=%6.1f  grounded=%s  stamina=%.0f" % [t, bot.y, bot.max_y, bot.grounded, bot.stamina])
	var ok := TowerShape.chunk_at(bot.max_y) >= GOAL_CHUNK
	print("%s: reached %.1f m in %.0f s, %d landings, %d falls (>6 m), closest to wall %.2f m" % [
		"PASS" if ok else "FAIL", bot.max_y, t, stats.landings, stats.falls, min_margin])
	quit(0 if ok else 1)
