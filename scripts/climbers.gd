class_name Climbers
extends Node3D
# Keeps a couple of rival birds climbing near the player, and handles bumps:
# birds shove each other sideways (which can knock you off a ledge), and
# landing on another bird's head bounces you up for free.

const MAX_BIRDS := 3
const KEEP_RANGE := 45.0             # rivals further than this (vertically) are dropped
const BUMP_RADIUS := 0.9
const BUMP_HEIGHT := 1.3
const SHOVE := 6.5                   # m/s knock from a sideways bump
const STOMP_BOUNCE := 11.0

var tower: TowerGenerator
var player: Player
var birds: Array[ClimberBird] = []
var spawn_timer := 5.0
var bump_cooldown := {}              # bird -> seconds until it can bump again

func clear() -> void:
	for b in birds:
		b.queue_free()
	birds.clear()
	spawn_timer = 5.0

func _physics_process(delta: float) -> void:
	if player == null or not player.active:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(8.0, 16.0)
		if birds.size() < MAX_BIRDS and player.y > 6.0:
			_spawn()
	for i in range(birds.size() - 1, -1, -1):
		if abs(birds[i].y - player.y) > KEEP_RANGE:
			bump_cooldown.erase(birds[i])
			birds[i].queue_free()
			birds.remove_at(i)
	for b in birds:
		bump_cooldown[b] = max(bump_cooldown.get(b, 0.0) - delta, 0.0)
		if bump_cooldown[b] <= 0.0 and _bump(player, b):
			bump_cooldown[b] = 0.35

# A rival appears on a route ledge a little below you, so it climbs past
func _spawn() -> void:
	var options := tower.path_around(player.y - 12.0).filter(func(s):
		return s.top < player.y - 4.0 and s.top > player.y - 20.0 and s.kind != ChunkPlanner.Kind.GROUND)
	if options.is_empty():
		return
	var s: Dictionary = options[randi_range(0, options.size() - 1)]
	var b := ClimberBird.new()
	b.tower = tower
	b.make(randf() < 0.35)              # about a third are flyers
	add_child(b)
	var a: float = (s.a0 + s.a1) * 0.5
	var r: float = Vector2(s.cx, s.cz).length() if ChunkPlanner.is_outer(s) else TowerShape.wall_r(s.k, a, min(1.0, s.d1 * 0.5))
	b.place(a, r, s.top)
	birds.append(b)

# Returns true if the two birds touched
func _bump(a: Player, b: Player) -> bool:
	var pa := a.world_position()
	var pb := b.world_position()
	var dy := pb.y - pa.y
	var flat := Vector2(pb.x - pa.x, pb.z - pa.z)
	if abs(dy) > BUMP_HEIGHT or flat.length() > BUMP_RADIUS:
		return false
	# Coming down on someone's head: bounce off it and knock them down
	if a.vy < -1.0 and dy < -0.6:
		a.bounce(STOMP_BOUNCE)
		b.vy = min(b.vy, -4.0)
		b.squash = 1.0
		return true
	if b.vy < -1.0 and dy > 0.6:
		b.bounce(STOMP_BOUNCE)
		a.vy = min(a.vy, -4.0)
		a.squash = 1.0
		return true
	# Otherwise a sideways shove, split into around / in-out for each bird
	var n := flat.normalized() if flat.length() > 0.01 else Vector2.from_angle(randf() * TAU)
	a.knock -= _polar(n, a.theta) * SHOVE
	b.knock += _polar(n, b.theta) * SHOVE
	return true

# A world XZ direction as (around, in/out) components at angle theta
static func _polar(n: Vector2, theta: float) -> Vector2:
	var around := Vector2(cos(theta), -sin(theta))
	var out := Vector2(sin(theta), cos(theta))
	return Vector2(n.dot(around), n.dot(out))
