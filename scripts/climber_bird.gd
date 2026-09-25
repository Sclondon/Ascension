class_name ClimberBird
extends Player
# A rival bird trying to get up the tower too. It follows the same guaranteed
# route you do, with the same physics and stamina, steered by a simple AI:
# walk toward the next ledge, rest until there's stamina for the jump, jump,
# and flap when it's dropping below where it wants to land. It's not perfect,
# so rivals sometimes slip and fall.
#
# Flyers are the showoffs: a bottomless stamina bucket, so they never rest,
# aim a few ledges ahead and just flap their way up past you.

# Rivals are crows too, tinted a touch so they don't look like you; flyers
# have a blue-black sheen
const TINTS := [Color(0.3, 0.3, 0.34), Color(0.32, 0.27, 0.26), Color(0.28, 0.3, 0.3)]
const FLYER_TINT := Color(0.22, 0.27, 0.42)

var target: Dictionary = {}
var since_flap := 0.0
var grounded_time := 0.0
var patience := 0.0                  # a little random hesitation before each jump
var flyer := false
var patience_max := 0.35
var flap_every := 0.18              # flyers: seconds between flaps (their climb rate)
var retarget_timer := 0.0

func _init() -> void:
	is_npc = true
	active = true

# Climbers are quicker and hardier than you; flyers barely need to land
func make(is_flyer: bool) -> void:
	flyer = is_flyer
	dress(FLYER_TINT if flyer else TINTS[randi_range(0, TINTS.size() - 1)])
	max_stamina = 99999.0 if flyer else randf_range(170.0, 250.0)
	stamina = max_stamina
	# Each bird is its own climber: some dawdle, some race
	regen_rate = randf_range(60.0, 160.0)
	speed_mult = randf_range(1.1, 1.6) if flyer else randf_range(0.85, 1.5)
	patience_max = randf_range(0.05, 1.0)
	flap_every = randf_range(0.14, 0.34)

# Somewhere to say things (the Climbers manager decides what and when)
var bubble: SpeechBubble
var chatter_cool := 3.0
var was_above := false               # relative to the player, for passing remarks

func say(line: String) -> void:
	if bubble == null:
		bubble = SpeechBubble.new()
		bubble.position = Vector3(0, 1.6, 0)
		add_child(bubble)
	bubble.say(line, 2.6)
	chatter_cool = randf_range(4.0, 7.0)

func dress(tint: Color) -> void:
	frames_idle = Npc.recoloured(IDLE_FRAMES, tint)
	frames_flap = Npc.recoloured(FLAP_FRAMES, tint)
	frames_fall = Npc.recoloured(FALL_FRAMES, tint)

func _physics_process(delta: float) -> void:
	since_flap += delta
	grounded_time = grounded_time + delta if grounded else 0.0
	retarget_timer -= delta
	if (grounded and retarget_timer <= 0.0) or target.is_empty():
		retarget_timer = 0.2
		_retarget()
	elif flyer and y > target.top - 1.0:
		# Flyers don't wait to land: once level with the target, aim higher
		var path := tower.path_around(y)
		var above := path.filter(func(s): return s.top > y + 2.0)
		if not above.is_empty():
			target = above[min(2, above.size() - 1)]
	super(delta)

func _retarget() -> void:
	var path := tower.path_around(y)
	var from := -1
	if grounded and ground.has("id"):
		for i in path.size():
			if path[i].id == ground.id:
				from = i
	var next: Dictionary = {}
	var ahead := 3 if flyer else 1
	if from >= 0 and from + 1 < path.size():
		next = path[min(from + ahead, path.size() - 1)]
	else:
		for s in path:
			if s.top > y + 0.3:
				next = s
				break
	if next.get("id", "") != target.get("id", "-"):
		target = next
		patience = randf_range(0.0, patience_max)

func read_input() -> Dictionary:
	var out := {"ax": 0.0, "ar": 0.0, "jump_pressed": false, "jump_held": vy > 0.0}
	if target.is_empty():
		return out
	var t := target
	var c: float = (t.a0 + t.a1) * 0.5
	if t.kind != ChunkPlanner.Kind.RING:
		var inside := wrapf(theta - t.a0, -PI, PI) > 0.05 and wrapf(t.a1 - theta, -PI, PI) > 0.05
		if not inside:
			# Full speed until over the ledge (easing in made every hop slow)
			var off := wrapf(c - theta, -PI, PI) * r
			out.ax = sign(off) if abs(off) > 0.3 else off / 0.3
	var d_goal: float = (t.d0 + t.d1) * 0.5 if ChunkPlanner.is_outer(t) else min(1.0, (t.d1 - t.d0) * 0.5) + t.d0
	var want_r := TowerShape.wall_r(TowerShape.chunk_at(y + 0.05), theta, max(d_goal, Tuning.WALL_MARGIN))
	out.ar = clamp((want_r - r) * 4.0, -1.0, 1.0)
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
		if flyer:
			rested = true
			reach = 99.0
		if not rested or grounded_time < patience:
			out.ax = 0.0
			out.ar = 0.0
		elif (reach > 0.0 and arc < reach * 0.8) or grounded_time > 6.0:
			out.jump_pressed = true
	elif flyer and vy < 2.0 and y < t.top + 2.5 and since_flap > flap_every:
		out.jump_pressed = true
		since_flap = 0.0
	elif vy < 0.0 and y < t.top + 0.6 and since_flap > 0.2 and stamina >= Tuning.FLAP_COST and not TowerChunk.contains(t, theta, r, 0.1):
		# Flap to stay up only when it isn't already over its landing spot
		out.jump_pressed = true
		since_flap = 0.0
	return out
