class_name TowerGenerator
extends Node3D
# Streams tower chunks in and out around a focus height, in both directions,
# and answers collision queries against their surfaces.

const KEEP_BELOW := 2                # chunks built below the focus
const KEEP_ABOVE := 3
const UNLOAD_MARGIN := 2

var run_seed := 0
var chunks := {}                     # chunk index -> TowerChunk
var time := 0.0
var glow := 1.0
var collected := {}                  # gold feather ids taken this run

func _ready() -> void:
	add_child(TowerChunk.make_ground())

func reset(new_seed: int, taken: Array = []) -> void:
	run_seed = new_seed
	collected.clear()
	for id in taken:
		collected[id] = true
	for c in chunks.values():
		c.queue_free()
	chunks.clear()

func chunk(k: int) -> TowerChunk:
	# Planning is cheap and always synchronous; meshes can follow a frame later
	if not chunks.has(k):
		var c := TowerChunk.new()
		c.setup(ChunkPlanner.plan(run_seed, k), collected)
		c.set_glow(glow)
		add_child(c)
		chunks[k] = c
	return chunks[k]

# Keeps chunks around `y` built. Builds the nearest missing chunk each call
# (or all of them when `immediate`), and frees ones far away.
func stream(y: float, immediate := false) -> void:
	var c := TowerShape.chunk_at(y)
	var wanted: Array[int] = []
	for k in range(max(0, c - KEEP_BELOW), c + KEEP_ABOVE + 1):
		wanted.append(k)
	wanted.sort_custom(func(a, b): return abs(a - c) < abs(b - c))
	var built_one := false
	for k in wanted:
		var ch := chunk(k)
		if not ch.built and (immediate or not built_one or abs(k - c) <= 1):
			ch.build()
			ch.set_glow(glow)
			built_one = true
	for k in chunks.keys():
		if k < c - KEEP_BELOW - UNLOAD_MARGIN or k > c + KEEP_ABOVE + UNLOAD_MARGIN:
			chunks[k].queue_free()
			chunks.erase(k)

func tick(delta: float) -> void:
	time += delta
	for c in chunks.values():
		c.tick(time, delta)

func set_glow(g: float) -> void:
	if abs(g - glow) < 0.01:
		return
	glow = g
	for c in chunks.values():
		c.set_glow(g)

func _surfaces_between(y_lo: float, y_hi: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in range(TowerShape.chunk_at(y_lo), TowerShape.chunk_at(y_hi) + 1):
		out.append_array(chunk(k).surfaces)
	return out

# Highest surface whose top was crossed while falling from prev_y to y
func find_landing(prev_y: float, y: float, theta: float, r: float) -> Dictionary:
	var best: Dictionary = {}
	for s in _surfaces_between(y - 0.01, prev_y + 0.01):
		if s.top <= prev_y + 0.01 and s.top >= y - 0.01 and (best.is_empty() or s.top > best.top):
			if TowerChunk.contains(s, theta, r, Tuning.FOOT_TOLERANCE):
				best = s
	return best

func supports(s: Dictionary, theta: float, r: float) -> bool:
	return TowerChunk.contains(s, theta, r, Tuning.FOOT_TOLERANCE + 0.05)

# Height of the first surface below (for the bird's shadow)
func ground_below(theta: float, r: float, y: float, max_drop := 24.0) -> float:
	var best := -INF
	for s in _surfaces_between(y - max_drop, y + 0.01):
		if s.top <= y + 0.01 and s.top > best and TowerChunk.contains(s, theta, r, 0.0):
			best = s.top
	return best

func chunk_of(s: Dictionary) -> TowerChunk:
	return chunks.get(int(String(s.id).get_slice(":", 0)))

# Types ("feather", "seed", "poison") of the pickups touched this frame.
# Gold feathers are remembered so they never come back this run.
func collect_pickups(pos: Vector3) -> Array[String]:
	var got: Array[String] = []
	var c := TowerShape.chunk_at(pos.y)
	for k in [c - 1, c]:
		if chunks.has(k):
			for pk in chunks[k].collect(pos):
				if pk.type == "feather":
					collected[pk.id] = true
				got.append(pk.type)
	return got

func touch(s: Dictionary) -> void:
	var c := chunk_of(s)
	if c:
		c.touch(s)

func leave(s: Dictionary) -> void:
	var c := chunk_of(s)
	if c:
		c.leave(s)

# Vertical push (m/s^2) from any draft the point is inside. Strongest in the
# middle of the column, easing off near its edges and ends.
func draft_at(pos: Vector3) -> float:
	var push := 0.0
	var c := TowerShape.chunk_at(pos.y)
	for k in [c - 1, c, c + 1]:
		if not chunks.has(k):
			continue
		for d in chunks[k].drafts:
			if pos.y < d.y0 or pos.y > d.y1:
				continue
			var centre := Vector2(sin(d.theta) * d.r, cos(d.theta) * d.r)
			var off := Vector2(pos.x, pos.z).distance_to(centre)
			if off > d.radius:
				continue
			var t: float = (pos.y - d.y0) / (d.y1 - d.y0)
			var fade: float = smoothstep(0.0, 0.15, t) * smoothstep(1.0, 0.8, t) * (1.0 - off / d.radius * 0.5)
			push += (Tuning.UPDRAFT if d.up else -Tuning.DOWNDRAFT) * fade
	return push

# NPCs near the bird look at it, hop about, or talk
func tick_npcs(delta: float, pos: Vector3) -> void:
	var c := TowerShape.chunk_at(pos.y)
	for k in [c - 1, c, c + 1]:
		if chunks.has(k):
			for n in chunks[k].npcs:
				n.tick(delta, pos)

# The guaranteed route through the chunks around `y`, in climbing order
func path_around(y: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := TowerShape.chunk_at(y)
	for k in range(max(0, c - 1), c + 3):
		for s in chunk(k).surfaces:
			if s.get("path", false):
				out.append(s)
	return out
