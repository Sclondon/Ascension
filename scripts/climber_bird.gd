class_name ClimberBird
extends Player
# A rival bird trying to get up the tower too. It follows the same guaranteed
# route you do, with the same physics and stamina, steered by a simple AI:
# walk toward the next ledge, rest until there's stamina for the jump, jump,
# and flap when it's dropping below where it wants to land. It's not perfect,
# so rivals sometimes slip and fall.

const TINTS := [Color(0.6, 0.62, 0.7), Color(0.62, 0.45, 0.3), Color(0.35, 0.55, 0.9), Color(0.85, 0.85, 0.8)]

var target: Dictionary = {}
var since_flap := 0.0
var grounded_time := 0.0
var patience := 0.0                  # a little random hesitation before each jump

func _init() -> void:
	is_npc = true
	active = true

func dress(tint: Color) -> void:
	frames_idle = Npc.recoloured(IDLE_FRAMES, tint)
	frames_flap = Npc.recoloured(FLAP_FRAMES, tint)
	frames_fall = Npc.recoloured(FALL_FRAMES, tint)

func _physics_process(delta: float) -> void:
	since_flap += delta
	grounded_time = grounded_time + delta if grounded else 0.0
	if grounded or target.is_empty():
		_retarget()
	super(delta)

func _retarget() -> void:
	var path := tower.path_around(y)
	var from := -1
	if grounded and ground.has("id"):
		for i in path.size():
			if path[i].id == ground.id:
				from = i
	var next: Dictionary = {}
	if from >= 0 and from + 1 < path.size():
		next = path[from + 1]
	else:
		for s in path:
			if s.top > y + 0.3:
				next = s
				break
	if next.get("id", "") != target.get("id", "-"):
		target = next
		patience = randf_range(0.2, 1.2)

func read_input() -> Dictionary:
	var out := {"ax": 0.0, "ar": 0.0, "jump_pressed": false, "jump_held": vy > 0.0}
	if target.is_empty():
		return out
	var t := target
	var c: float = (t.a0 + t.a1) * 0.5
	if t.kind != ChunkPlanner.Kind.RING:
		var inside := wrapf(theta - t.a0, -PI, PI) > 0.05 and wrapf(t.a1 - theta, -PI, PI) > 0.05
		if not inside:
			out.ax = clamp(wrapf(c - theta, -PI, PI) * r * 1.5, -1.0, 1.0)
	var d_goal: float = (t.d0 + t.d1) * 0.5 if ChunkPlanner.is_outer(t) else min(1.0, (t.d1 - t.d0) * 0.5) + t.d0
	var want_r := TowerShape.wall_r(TowerShape.band_at(y + 0.05), theta, max(d_goal, Tuning.WALL_MARGIN))
	out.ar = clamp((want_r - r) * 2.0, -1.0, 1.0)
	if grounded:
		var arc: float = abs(wrapf(c - theta, -PI, PI)) * r - (t.a1 - t.a0) * r * 0.5
		if ChunkPlanner.is_outer(t):
			var me := TowerShape.polar_point(theta, r)
			arc = ChunkPlanner._polygon_hop(PackedVector2Array([me, me + Vector2(0.01, 0), me + Vector2(0, 0.01)]), t.polys[0])
		var reach := Tuning.air_distance(t.top - y, Tuning.PATH_FLAPS + 1)
		var need := 0
		while need < 3 and Tuning.air_distance(t.top - y, need) < 0.0:
			need += 1
		var rested := stamina >= Tuning.JUMP_COST + (need + 1) * Tuning.FLAP_COST or stamina >= max_stamina - 0.5
		if not rested or grounded_time < patience:
			out.ax = 0.0
			out.ar = 0.0
		elif (reach > 0.0 and arc < reach * 0.8) or grounded_time > 6.0:
			out.jump_pressed = true
	elif vy < 0.0 and y < t.top + 0.4 and since_flap > 0.2 and stamina >= Tuning.FLAP_COST:
		out.jump_pressed = true
		since_flap = 0.0
	return out
