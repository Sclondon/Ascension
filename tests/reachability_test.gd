extends SceneTree
# Headless check that every generated chunk has a climbable path.
# Run:  godot --headless --path . -s tests/reachability_test.gd

const SEEDS := [1, 2, 3, 42, 1234, 99999, 271828, 314159]
const CHUNKS := 400

func _init() -> void:
	var failures := 0
	var steps := 0
	var worst_ratio := 0.0
	for run_seed in SEEDS:
		for k in CHUNKS:
			var plan := ChunkPlanner.plan(run_seed, k)
			if str(plan) != str(ChunkPlanner.plan(run_seed, k)):
				print("NOT DETERMINISTIC seed=%d k=%d" % [run_seed, k])
				failures += 1
			var path: Array = plan.surfaces.filter(func(s): return s.path)
			path.append(ChunkPlanner.anchor(run_seed, k + 1))
			for i in path.size() - 1:
				var a: Dictionary = path[i]
				var b: Dictionary = path[i + 1]
				var dy: float = b.top - a.top
				var reach := Tuning.air_distance(dy, Tuning.PATH_FLAPS)
				var gap := ChunkPlanner.gap_between(a, b)
				steps += 1
				# Must be possible, and leave at least a metre of height to spare
				var too_high := dy > Tuning.max_jump_height(Tuning.PATH_FLAPS) - 1.0
				# (the planner keeps to 75% of reach; anything near 100% means a bug)
				if reach < 0.0 or gap > reach * 0.8 or too_high:
					failures += 1
					if failures < 20:
						print("UNREACHABLE seed=%d k=%d step=%d dy=%.2f gap=%.2f reach=%.2f" % [run_seed, k, i, dy, gap, reach])
				elif reach > 0.0:
					worst_ratio = max(worst_ratio, gap / reach)
			for s in plan.surfaces:
				if s.kind != ChunkPlanner.Kind.GROUND and (s.top < plan.base - 0.01 or s.top >= plan.base + TowerShape.CHUNK_H):
					failures += 1
					print("OUT OF CHUNK seed=%d k=%d top=%.2f" % [run_seed, k, s.top])
	# The opening spiral must be the same whatever the seed
	for k in ChunkPlanner.START_CHUNKS:
		if str(ChunkPlanner.plan(SEEDS[0], k)) != str(ChunkPlanner.plan(SEEDS[1], k)):
			print("START DIFFERS k=%d" % k)
			failures += 1
	print("checked %d path steps, worst gap/reach %.2f, failures %d" % [steps, worst_ratio, failures])
	quit(1 if failures > 0 else 0)
