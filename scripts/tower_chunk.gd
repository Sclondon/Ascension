class_name TowerChunk
extends Node3D
# One 12 m slice of tower built from a ChunkPlanner plan. Holds the runtime
# state of its surfaces (moving, bobbing and crumbling ones) and pickups.

const Kind = ChunkPlanner.Kind
const GLASS_SHADER := preload("res://shaders/stained_glass.gdshader")

const CRUMBLE_DELAY := 1.0           # crusty ledge: falls this long after you touch it
const FRAGILE_DELAY := 0.3           # cracked ledge: holds you, falls once you leave
const FALL_TIME := 1.6
const RESPAWN_TIME := 8.0            # both grow back, since a fall can bring you back here
const ISLAND_BOB := 0.25

const WOOD := Color(0.42, 0.28, 0.18)
const ROOF := Color(0.32, 0.22, 0.3)

const PICKUP_RESPAWN := 25.0         # seeds and poison grow back; gold feathers don't
static var _pickup_tex := {}

var plan: Dictionary
var surfaces: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var glass: Array[ShaderMaterial] = []
var drafts: Array[Dictionary] = []
var npcs: Array[Npc] = []
var wires: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var built := false

# `collected` holds ids of gold feathers already taken this run (they don't return)
func setup(p: Dictionary, collected: Dictionary) -> void:
	plan = p
	surfaces = p.surfaces
	for s in surfaces:
		s.offset = 0.0
		s.broken = false
		s.crumble = -1.0
		s.node = null
	for pk in p.pickups:
		if collected.has(pk.id):
			continue
		var d: Dictionary = pk.duplicate()
		d.taken = -1.0                   # seconds since taken, -1 while available
		d.node = null
		pickups.append(d)
	drafts = p.drafts
	for w in p.wires:
		var d: Dictionary = w.duplicate()
		d.dip = 0.0                      # how far the wire is pushed down (bounce)
		d.dip_v = 0.0
		d.tb = 0.5                       # where along it the push is
		d.line = null
		d.perched = []                   # crows sitting on it
		d.flying = []                    # crows that took off
		wires.append(d)
	for rg in p.rings:
		var d: Dictionary = rg.duplicate()
		d.cool = 0.0
		d.node = null
		rings.append(d)
	name = "Chunk%d" % p.k

# --- collision queries -------------------------------------------------------

static func contains(s: Dictionary, theta: float, r: float, tol: float) -> bool:
	if s.kind == Kind.GROUND:
		return true
	if s.broken:
		return false
	var p := TowerShape.polar_point(theta - s.offset, r)
	# Cheap bounding-box reject before the polygon tests (these run a lot)
	if not s.has("bb"):
		var bb := Rect2(s.polys[0][0], Vector2.ZERO)
		for poly: PackedVector2Array in s.polys:
			for q in poly:
				bb = bb.expand(q)
		s.bb = bb
	if not (s.bb as Rect2).grow(tol).has_point(p):
		return false
	for poly: PackedVector2Array in s.polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	for poly: PackedVector2Array in s.polys:
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_squared_to(p) < tol * tol:
				return true
	return false

# --- per-frame ---------------------------------------------------------------

func tick(time: float, delta: float) -> void:
	for s in surfaces:
		match s.kind:
			Kind.MOVER:
				s.offset = sin(time * s.speed + s.phase) * s.swing
				if s.node:
					s.node.rotation.y = s.offset
			Kind.ISLAND, Kind.PROP:
				s.top = s.base_top + sin(time * 0.8 + s.bob_phase) * ISLAND_BOB
				if s.node:
					s.node.position.y = s.top - s.base_top
					var blades: Node3D = s.node.get_node_or_null("Blades")
					if blades:
						blades.rotation.y += delta * 24.0
			Kind.ORBIT:
				# All the way round, forever
				s.offset = s.phase + time * s.speed
				if s.node:
					s.node.rotation.y = s.offset
			Kind.RETRACT:
				_tick_retract(s, time)
			_:
				# Crumbling ledges, and anything lightning has smashed
				if s.crumble >= 0.0:
					_tick_crumble(s, delta)
	for w in wires:
		_tick_wire(w, delta)
	for rg in rings:
		rg.cool = max(rg.cool - delta, 0.0)
	for pk in pickups:
		if pk.taken >= 0.0 and pk.type != "feather":
			pk.taken += delta
			if pk.taken > PICKUP_RESPAWN:
				pk.taken = -1.0
		if pk.node:
			pk.node.visible = pk.taken < 0.0
			pk.node.position.y = pk.y + sin(time * 2.5 + pk.theta * 3.0) * 0.15

func _tick_crumble(s: Dictionary, delta: float) -> void:
	s.crumble += delta
	var node: Node3D = s.node
	var delay: float = s.delay
	var t: float = s.crumble - delay
	if t < 0.0:
		# Shaking harder and harder as it's about to go
		var k: float = 0.02 + 0.08 * s.crumble / delay
		if node:
			node.position = Vector3(randf_range(-k, k), randf_range(-k, k) * 0.5, randf_range(-k, k))
	elif t < RESPAWN_TIME:
		if not s.broken:
			s.broken = true
			_dust(s)
		if node:
			node.visible = t < FALL_TIME
			node.position = Vector3(0, -t * t * 9.0, 0)
			node.rotation = Vector3(t * 0.6, 0, t * 0.9) * s.get("spin", 1.0)
	else:
		s.broken = false
		s.crumble = -1.0
		if node:
			node.position = Vector3.ZERO
			node.rotation = Vector3.ZERO
			node.visible = true
			node.scale = Vector3.ONE * 0.01
			create_tween().tween_property(node, "scale", Vector3.ONE, 0.4)

# Standing on it: crusty ledges start to go
func touch(s: Dictionary) -> void:
	if s.kind == Kind.CRUMBLE and s.crumble < 0.0:
		s.crumble = 0.0
		s.delay = CRUMBLE_DELAY
		s.spin = 1.0 if randf() < 0.5 else -1.0

# Hit by lightning: shatters straight away (and grows back like the others)
func smash(s: Dictionary) -> void:
	if s.kind in [Kind.GROUND, Kind.RING, Kind.MOVER, Kind.ISLAND, Kind.ORBIT, Kind.PROP, Kind.RETRACT] or s.crumble >= 0.0:
		return
	s.crumble = 0.0
	s.delay = 0.02
	s.spin = 1.0 if randf() < 0.5 else -1.0

# Stepping or jumping off: cracked ledges give way behind you
func leave(s: Dictionary) -> void:
	if s.kind == Kind.FRAGILE and s.crumble < 0.0:
		s.crumble = 0.0
		s.delay = FRAGILE_DELAY
		s.spin = 1.0 if randf() < 0.5 else -1.0

func _dust(s: Dictionary) -> void:
	var poly: PackedVector2Array = s.polys[0]
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 18
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.8
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -12, 0)
	var q := BoxMesh.new()
	q.size = Vector3.ONE * 0.14
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.45, 0.38) if s.kind == Kind.CRUMBLE else Color(0.7, 0.72, 0.65)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.mesh = q
	p.position = Vector3(c.x, s.top - 0.2, c.y)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# Returns the pickups the bird touched ({id, type}). Poison has a smaller
# reach than the goodies, so brushing past it is forgiven.
func collect(pos: Vector3) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	for pk in pickups:
		if pk.taken < 0.0:
			var p := Vector3(sin(pk.theta) * pk.r, pk.y, cos(pk.theta) * pk.r)
			var reach := 0.75 if pk.type == "poison" else 1.1
			if p.distance_to(pos + Vector3(0, 0.5, 0)) < reach:
				pk.taken = 0.0
				got.append({"id": pk.id, "type": pk.type})
	return got

func set_glow(g: float) -> void:
	for m in glass:
		m.set_shader_parameter("glow", g)

# --- building ----------------------------------------------------------------

func build() -> void:
	if built:
		return
	built = true
	var shape: int = plan.k
	var base: float = plan.base
	var tint := TowerShape.tint(shape)
	_build_walls(shape, base, tint)
	for s in surfaces:
		_build_surface(s, tint)
	for w in plan.windows:
		_build_window(shape, w)
	for pk in pickups:
		_build_pickup(pk)
	for d in drafts:
		_build_draft(d)
	for n in plan.npcs:
		_build_npc(n)
	for w in wires:
		_build_wire(w)
	for rg in rings:
		_build_ring(rg)

func _build_walls(shape: int, base: float, tint: Color) -> void:
	var st := MeshUtil.begin()
	var n := TowerShape.sides(shape)
	var half := TowerShape.face_step(shape) * 0.5
	var y0 := base - (2.0 if plan.ground else 0.0)
	var y1 := base + TowerShape.CHUNK_H
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.k, 3])
	for i in n:
		var c := TowerShape.face_center(shape, i)
		var p0 := TowerShape.ring_point(shape, c - half, 0.0)
		var p1 := TowerShape.ring_point(shape, c + half, 0.0)
		var shade := Color.WHITE.darkened(rng.randf_range(0.0, 0.12))
		MeshUtil.face(st, [Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y)],
			Vector3(sin(c), 0, cos(c)), shade)
	# A thin string course at the chunk's base marks height as you climb
	if not ChunkPlanner.is_band_start(plan.k) and not plan.ground:
		for half_ring in [[0.0, PI], [PI, TAU]]:
			MeshUtil.extrude(st, TowerShape.strip_polygon(shape, half_ring[0], half_ring[1], -0.02, 0.18), base - 0.12, base + 0.12, Color(0.75, 0.72, 0.7))
	# Where the thickness changes, a sloped cap (narrowing) or a corbelled
	# overhang (widening) joins this chunk to the one below
	if plan.k > 0 and not ChunkPlanner.is_band_start(plan.k):
		var step: float = TowerShape.apothem(plan.k - 1) - TowerShape.apothem(plan.k)
		if abs(step) > 0.04:
			for i in n:
				var c := TowerShape.face_center(shape, i)
				var out := Vector3(sin(c), 0, cos(c))
				var lo_d := step                # where the wall below meets this chunk
				var p0 := TowerShape.ring_point(shape, c - half, lo_d)
				var p1 := TowerShape.ring_point(shape, c + half, lo_d)
				var q0 := TowerShape.ring_point(shape, c - half, 0.0)
				var q1 := TowerShape.ring_point(shape, c + half, 0.0)
				if step > 0.0:
					# Narrowing: slope up from the wider wall below onto this one
					MeshUtil.face(st, [Vector3(p0.x, base, p0.y), Vector3(p1.x, base, p1.y), Vector3(q1.x, base + 0.7, q1.y), Vector3(q0.x, base + 0.7, q0.y)],
						out + Vector3.UP, Color(0.8, 0.77, 0.74))
				else:
					# Widening: slope out from the narrower wall below under this one
					MeshUtil.face(st, [Vector3(p0.x, base - 0.8, p0.y), Vector3(p1.x, base - 0.8, p1.y), Vector3(q1.x, base, q1.y), Vector3(q0.x, base, q0.y)],
						out + Vector3.DOWN, Color(0.62, 0.6, 0.58))
	# Where the side count changes, cap the old band's top so there's no gap
	if ChunkPlanner.is_band_start(plan.k):
		var prev: int = plan.k - 1
		var rad: float = max(TowerShape.apothem(prev) / cos(PI / TowerShape.sides(prev)), TowerShape.apothem(shape))
		var cap := PackedVector2Array()
		for i in 24:
			cap.append(TowerShape.polar_point(TAU * i / 24.0, rad + 0.05))
		MeshUtil.extrude(st, cap, base - 0.35, base - 0.1, Color(0.6, 0.58, 0.56))
	add_child(MeshUtil.commit(st, MeshUtil.stone_material(tint)))

func _build_surface(s: Dictionary, tint: Color) -> void:
	if s.kind == Kind.GROUND:
		return
	var holder := Node3D.new()
	add_child(holder)
	s.node = holder
	if s.kind == Kind.TURRET:
		_build_turret(holder, s, tint)
		return
	if s.kind == Kind.ISLAND:
		_build_island(holder, s)
		return
	if s.kind == Kind.PROP:
		_build_prop(holder, s)
		return
	if s.kind == Kind.ORBIT:
		_build_orbit(holder, s, tint)
		return
	var st := MeshUtil.begin()
	var top: float = s.top
	var mat := MeshUtil.stone_material(tint.lerp(Color(1.0, 0.93, 0.8), 0.5), "slab")
	var shape: int = s.k
	match s.kind:
		Kind.LEDGE:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.45, top, Color(0.95, 0.92, 0.88))
			# Corbel underneath
			var inset: float = (s.a1 - s.a0) * 0.15
			MeshUtil.extrude(st, TowerShape.strip_polygon(shape, s.a0 + inset, s.a1 - inset, 0.0, s.d1 * 0.45), top - 1.0, top - 0.45, Color(0.7, 0.68, 0.66))
		Kind.BALCONY:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.4, top, Color(1.0, 0.97, 0.9))
			_build_railing(st, s)
			var inset: float = (s.a1 - s.a0) * 0.1
			for a in [s.a0 + inset, s.a1 - inset * 2.0]:
				MeshUtil.extrude(st, TowerShape.strip_polygon(shape, a, a + inset, 0.0, s.d1 * 0.7), top - 1.2, top - 0.4, Color(0.7, 0.68, 0.66))
		Kind.PERCH:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.55, 0.42, 0.32))
			var tip := TowerShape.ring_point(shape, (s.a0 + s.a1) * 0.5, s.d1)
			MeshUtil.box(st, Vector3(tip.x, top - 0.15, tip.y), Vector3(0.5, 0.5, 0.5), (s.a0 + s.a1) * 0.5, Color(0.5, 0.48, 0.5))
		Kind.RING:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.7, top, Color(1.0, 0.95, 0.85))
		Kind.CRUMBLE:
			# Old crusty ledge: packed dirt with loose clods on top
			mat = MeshUtil.stone_material(Color(0.95, 0.72, 0.55), "dirt")
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.35, top, Color.WHITE, 2.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(s.id)
			for i in 5:
				var a: float = lerp(s.a0, s.a1, rng.randf_range(0.1, 0.9))
				var p := TowerShape.ring_point(shape, a, rng.randf_range(0.3, s.d1 - 0.3))
				MeshUtil.box(st, Vector3(p.x, top + 0.06, p.y), Vector3(0.28, 0.14, 0.24) * rng.randf_range(0.7, 1.3), rng.randf() * TAU, Color(0.8, 0.62, 0.5))
			# Dangling roots / crumbs underneath
			for i in 3:
				var a: float = lerp(s.a0, s.a1, rng.randf_range(0.15, 0.85))
				var p := TowerShape.ring_point(shape, a, rng.randf_range(0.3, s.d1 - 0.3))
				MeshUtil.box(st, Vector3(p.x, top - 0.5, p.y), Vector3(0.18, 0.35, 0.18), rng.randf() * TAU, Color(0.6, 0.45, 0.35))
		Kind.FRAGILE:
			# Cracked old stone: holds while you stand, gives way once you leave
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.35, top, Color(0.78, 0.82, 0.7))
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(s.id)
			for i in 3:
				var a: float = lerp(s.a0, s.a1, rng.randf_range(0.2, 0.8))
				var p := TowerShape.ring_point(shape, a, s.d1 * 0.5)
				MeshUtil.box(st, Vector3(p.x, top + 0.01, p.y), Vector3(0.07, 0.03, s.d1 * rng.randf_range(0.5, 0.9)), a + rng.randf_range(-0.5, 0.5), Color(0.2, 0.2, 0.18))
			var tip := TowerShape.ring_point(shape, lerp(s.a0, s.a1, 0.7), s.d1 - 0.3)
			MeshUtil.box(st, Vector3(tip.x, top - 0.55, tip.y), Vector3(0.3, 0.4, 0.3), 0.4, Color(0.7, 0.74, 0.62))
		Kind.MOVER:
			mat = MeshUtil.stone_material(Color(0.75, 0.62, 1.0), "glow")
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.35, top, Color.WHITE)
		Kind.RETRACT:
			# Iron-bound slab that slides in and out of a slot in the wall
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.72, 0.7, 0.78))
			var edge := TowerShape.strip_polygon(shape, s.a0, s.a1, s.d1 - 0.18, s.d1)
			MeshUtil.extrude(st, edge, top - 0.34, top + 0.04, Color(0.35, 0.33, 0.4))
	holder.add_child(MeshUtil.commit(st, mat))

# A little room hung off the tower on beams, crenellated on top (a bartizan)
func _build_turret(holder: Node3D, s: Dictionary, tint: Color) -> void:
	var shape: int = s.k
	var top: float = s.top
	var R: float = s.radius
	var c := Vector2(s.cx, s.cz)
	var out := c.normalized()
	var poly: PackedVector2Array = s.polys[0]

	var slab := MeshUtil.begin()
	MeshUtil.extrude(slab, poly, top - 0.35, top, Color(1.0, 0.96, 0.9))
	# Merlons on every other edge, low enough not to hide the bird
	for i in range(0, poly.size(), 2):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var mid := (p + q) * 0.5
		var n := (mid - c).normalized()
		var at := mid - n * 0.13
		MeshUtil.box(slab, Vector3(at.x, top + 0.2, at.y), Vector3(p.distance_to(q) * 0.6, 0.4, 0.22), atan2(n.x, n.y), Color(0.95, 0.92, 0.86))
	holder.add_child(MeshUtil.commit(slab, MeshUtil.stone_material(tint.lerp(Color(1.0, 0.93, 0.8), 0.5), "slab")))

	# The room itself, in the tower's own brick, with a pointed cap underneath
	var room := MeshUtil.begin()
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(c + (p - c) * 0.86)
	MeshUtil.extrude(room, inner, top - 2.9, top - 0.35, Color.WHITE)
	holder.add_child(MeshUtil.commit(room, MeshUtil.stone_material(tint)))

	var wood := MeshUtil.begin()
	MeshUtil.cone(wood, Vector3(c.x, top - 2.9, c.y), R * 0.95, -1.4, 8, ROOF)
	if s.get("roof", false):
		# Roofed variant: four corner posts holding up a pitched roof
		for i in range(0, poly.size(), 2):
			var p := c + (poly[i] - c) * 0.88
			MeshUtil.beam(wood, Vector3(p.x, top, p.y), Vector3(p.x, top + 2.4, p.y), 0.16, WOOD)
		MeshUtil.cone(wood, Vector3(c.x, top + 2.35, c.y), R * 1.15, 1.5, 8, ROOF)
		MeshUtil.beam(wood, Vector3(c.x, top + 3.8, c.y), Vector3(c.x, top + 4.3, c.y), 0.08, Color(0.8, 0.65, 0.3))
	# Beam straight out from the wall, and a diagonal strut below it
	var a: float = atan2(c.x, c.y)
	var w := TowerShape.ring_point(shape, a, -0.1)
	var room_in := c - out * R * 0.8
	MeshUtil.beam(wood, Vector3(w.x, top - 0.75, w.y), Vector3(room_in.x, top - 0.75, room_in.y), 0.32, WOOD)
	MeshUtil.beam(wood, Vector3(w.x, top - 3.4, w.y), Vector3(room_in.x, top - 1.6, room_in.y), 0.26, WOOD.darkened(0.15))
	holder.add_child(MeshUtil.commit(wood, MeshUtil.flat_material(Color.WHITE)))

	# A small stained-glass window facing out
	var win := ShaderMaterial.new()
	win.shader = GLASS_SHADER
	win.set_shader_parameter("style", 0)
	win.set_shader_parameter("size", Vector2(0.5, 1.0))
	win.set_shader_parameter("seed", float(hash(s.id) % 1000))
	win.set_shader_parameter("hue", fposmod(float(hash(s.id)) * 0.001, 1.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 1.0)
	quad.material = win
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var face_r := R * 0.86 * cos(PI / 8.0) + 0.02
	var wp := c + out * face_r
	mi.position = Vector3(wp.x, top - 1.8, wp.y)
	mi.rotation.y = a
	holder.add_child(mi)
	glass.append(win)

# A floating chunk of earth: grassy top, jagged rock underneath
func _build_island(holder: Node3D, s: Dictionary) -> void:
	var top: float = s.top
	var poly: PackedVector2Array = s.polys[0]
	var c := Vector2(s.cx, s.cz)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s.id)
	var st := MeshUtil.begin()
	MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.45, 0.7, 0.35), 1.0)
	var mid_y := top - 1.1
	var tip := Vector3(c.x + rng.randf_range(-0.3, 0.3), top - 2.7, c.y + rng.randf_range(-0.3, 0.3))
	var ring: Array[Vector3] = []
	for p in poly:
		var q := c + (p - c) * rng.randf_range(0.55, 0.75)
		ring.append(Vector3(q.x, mid_y + rng.randf_range(-0.2, 0.2), q.y))
	var rock := Color(0.5, 0.42, 0.36)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var a := Vector3(poly[i].x, top - 0.3, poly[i].y)
		var b := Vector3(poly[j].x, top - 0.3, poly[j].y)
		var out := ((a + b) * 0.5 - Vector3(c.x, top, c.y))
		out.y = 0.0
		MeshUtil.face(st, [a, b, ring[j]], out + Vector3.DOWN * 0.5, rock.lightened(0.08 * (i % 2)), 1.0)
		MeshUtil.face(st, [a, ring[j], ring[i]], out + Vector3.DOWN * 0.5, rock.lightened(0.08 * (i % 2)), 1.0)
		MeshUtil.face(st, [ring[i], ring[j], tip], out + Vector3.DOWN, rock.darkened(0.15), 1.0)
	# A shrub and a pebble or two drifting alongside
	var edge := c + (poly[rng.randi_range(0, poly.size() - 1)] - c) * 0.6
	MeshUtil.cone(st, Vector3(edge.x, top, edge.y), 0.35, 0.7, 5, Color(0.2, 0.45, 0.25))
	for i in 2:
		var off: Vector2 = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * (s.radius + 0.6)
		MeshUtil.box(st, Vector3(c.x + off.x, top - rng.randf_range(0.8, 2.0), c.y + off.y), Vector3.ONE * rng.randf_range(0.25, 0.45), rng.randf() * TAU, rock)
	holder.add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))

func _build_npc(d: Dictionary) -> void:
	# Stand on its ledge's own node, so it bobs / falls along with it
	var parent: Node3D = self
	var on: Dictionary = {}
	for s in surfaces:
		if s.get("id", "") == d.get("surface", "-") and s.node:
			parent = s.node
			on = s
	var npc := Npc.new()
	npc.setup(d, on)
	npc.position = Vector3(sin(d.theta) * d.r, d.y, cos(d.theta) * d.r)
	parent.add_child(npc)
	npcs.append(npc)

# A column of streaks: pale and rising for an updraft, dark and sinking for
# a downdraft
func _build_draft(d: Dictionary) -> void:
	var h: float = d.y1 - d.y0
	var speed := 7.0 if d.up else 6.0
	var p := CPUParticles3D.new()
	p.amount = Tuning.particles(int(h * 4.0))
	p.lifetime = h / speed
	p.preprocess = p.lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = d.radius
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP if d.up else Vector3.DOWN
	p.spread = 3.0
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed * 1.2
	p.gravity = Vector3.ZERO
	p.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	var ramp := Gradient.new()
	var c := Color(0.85, 0.97, 1.0, 0.45) if d.up else Color(0.3, 0.22, 0.4, 0.5)
	ramp.set_color(0, Color(c, 0.0))
	ramp.add_point(0.2, c)
	ramp.add_point(0.8, c)
	ramp.set_color(ramp.get_point_count() - 1, Color(c, 0.0))
	p.color_ramp = ramp
	var streak := BoxMesh.new()
	streak.size = Vector3(0.05, 0.9, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	streak.material = m
	p.mesh = streak
	p.position = Vector3(sin(d.theta) * d.r, d.y0 if d.up else d.y1, cos(d.theta) * d.r)
	add_child(p)

func _build_railing(st: SurfaceTool, s: Dictionary) -> void:
	var shape: int = s.k
	var top: float = s.top
	var d: float = s.d1 - 0.12
	MeshUtil.extrude(st, TowerShape.strip_polygon(shape, s.a0, s.a1, d - 0.08, d + 0.08), top + 0.55, top + 0.68, Color(0.9, 0.88, 0.85), 1.0)
	var angles: Array[float] = [s.a0]
	angles.append_array(TowerShape.corners_between(shape, s.a0, s.a1))
	angles.append(s.a1)
	for i in angles.size() - 1:
		var seg := TowerShape.perimeter_len(shape, angles[i], angles[i + 1], d)
		var count: int = max(1, roundi(seg / 0.7))
		for j in count + (1 if i == angles.size() - 2 else 0):
			var a: float = lerp(angles[i], angles[i + 1], float(j) / count)
			var p := TowerShape.ring_point(shape, a, d)
			MeshUtil.box(st, Vector3(p.x, top + 0.3, p.y), Vector3(0.12, 0.6, 0.12), a, Color(0.85, 0.83, 0.8))

func _build_window(shape: int, w: Dictionary) -> void:
	var c := TowerShape.face_center(shape, w.face)
	var r := TowerShape.apothem(shape) + 0.03
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("style", w.style)
	mat.set_shader_parameter("size", Vector2(w.w, w.h))
	mat.set_shader_parameter("seed", w.seed)
	mat.set_shader_parameter("hue", w.hue)
	var quad := QuadMesh.new()
	quad.size = Vector2(w.w, w.h)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(sin(c) * r, w.y + w.h * 0.5, cos(c) * r)
	mi.rotation.y = c
	add_child(mi)
	if w.style != 2:
		glass.append(mat)

static func _texture_for(type: String) -> Texture2D:
	if _pickup_tex.has(type):
		return _pickup_tex[type]
	var tex: Texture2D
	if type == "seed":
		tex = MeshUtil.pixel_texture([
			"..oo..",
			".obbo.",
			"obwbbo",
			"obwbbo",
			"obwbbo",
			"obbbbo",
			".obbo.",
			"..oo..",
		], {"o": Color(0.3, 0.18, 0.08), "b": Color(0.85, 0.68, 0.4), "w": Color(1.0, 0.95, 0.8)})
	elif type == "poison":
		tex = MeshUtil.pixel_texture([
			"..oooo..",
			".opwpppo",
			"opppppwo",
			"opwppppo",
			"oooooooo",
			"...os...",
			"...os...",
			"..ossso.",
		], {"o": Color(0.2, 0.05, 0.25), "p": Color(0.62, 0.2, 0.78), "w": Color(0.85, 1.0, 0.6), "s": Color(0.75, 0.88, 0.6)})
	else:
		# A proper feather: a pale quill, a lit and a shaded vane, a notch
		tex = MeshUtil.pixel_texture([
			".....o...",
			"....oho..",
			"...ohwyo.",
			"...ohwyo.",
			"..ohhwyyo",
			"..ohhwyyo",
			".ohhhwyyo",
			".ohhhwyyo",
			".ohh.wyyo",
			"..ohhwyyo",
			"..ohhwyo.",
			"..ohhwyo.",
			"...ohwo..",
			"...ohwo..",
			"....ow...",
			".....w...",
			".....w...",
			".....o...",
		], {"o": Color(0.5, 0.28, 0.05), "h": Color(1.0, 0.88, 0.4), "y": Color(0.95, 0.66, 0.15), "w": Color(1.0, 0.98, 0.85)})
	_pickup_tex[type] = tex
	return tex

func _build_pickup(pk: Dictionary) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(sin(pk.theta) * pk.r, pk.y, cos(pk.theta) * pk.r)
	add_child(holder)
	var sp := Sprite3D.new()
	sp.texture = _texture_for(pk.type)
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD    # solid, so depth decides who's in front
	sp.pixel_size = 0.075 if pk.type == "feather" else 0.09
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	holder.add_child(sp)
	if pk.type == "feather":
		_add_feather_glow(holder)
	pk.node = holder

# Gold feathers glow softly and twinkle, so they read as treasure from afar
func _add_feather_glow(holder: Node3D) -> void:
	var glow := Sprite3D.new()
	glow.texture = MeshUtil.blob_texture(16, Color(1.0, 0.82, 0.3))
	glow.pixel_size = 0.14
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glow.shaded = false
	glow.modulate = Color(1, 1, 1, 0.55)
	glow.position = Vector3(0, 0, -0.05)
	holder.add_child(glow)
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "modulate:a", 0.6, 0.7).set_trans(Tween.TRANS_SINE)
	var sparkle := CPUParticles3D.new()
	sparkle.amount = Tuning.particles(7)
	sparkle.lifetime = 1.1
	sparkle.local_coords = true
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = 0.7
	sparkle.direction = Vector3.UP
	sparkle.spread = 30.0
	sparkle.initial_velocity_min = 0.1
	sparkle.initial_velocity_max = 0.4
	sparkle.gravity = Vector3.ZERO
	var twinkle := Curve.new()
	twinkle.add_point(Vector2(0, 0))
	twinkle.add_point(Vector2(0.5, 1))
	twinkle.add_point(Vector2(1, 0))
	sparkle.scale_amount_curve = twinkle
	var star := QuadMesh.new()
	star.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_texture = _star_texture()
	star.material = m
	sparkle.mesh = star
	holder.add_child(sparkle)

static var _star: Texture2D

static func _star_texture() -> Texture2D:
	if _star == null:
		_star = MeshUtil.pixel_texture([
			"...w...",
			"...w...",
			"..wyw..",
			"wwyyyww",
			"..wyw..",
			"...w...",
			"...w...",
		], {"w": Color(1.0, 0.95, 0.7), "y": Color(1, 1, 1)})
	return _star

# The meadow round the tower's foot. Built once by the generator, not per
# chunk, so it's still down there after the first chunks unload.
static func make_ground() -> MeshInstance3D:
	var st := MeshUtil.begin()
	var disk := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		# Far bigger than you can see: fog swallows the edge, so there's no disc
		disk.append(TowerShape.polar_point(a, 1500.0))
	MeshUtil.extrude(st, disk, -3.0, 0.0, Color(0.36, 0.55, 0.3), 8.0)
	# A cobbled apron around the tower's foot
	for half_ring in [[0.0, PI], [PI, TAU]]:
		MeshUtil.extrude(st, TowerShape.strip_polygon(0, half_ring[0], half_ring[1], -0.1, 2.6), -0.2, 0.02, Color(0.6, 0.58, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Hemlocks: kept outside the camera's orbit so they never block the view
	for i in 110:
		var a := rng.randf() * TAU
		var r := 36.0 + pow(rng.randf(), 1.6) * 190.0   # clear of the camera, even with the bird far out
		var base := Vector3(sin(a) * r, 0.0, cos(a) * r)
		var h := rng.randf_range(5.0, 11.0)
		var col := Color(0.12, 0.3, 0.22).lightened(rng.randf_range(0.0, 0.15))
		MeshUtil.box(st, base + Vector3(0, 0.6, 0), Vector3(0.5, 1.2, 0.5), a, Color(0.35, 0.22, 0.15))
		MeshUtil.cone(st, base + Vector3(0, 1.0, 0), h * 0.3, h * 0.55, 6, col)
		MeshUtil.cone(st, base + Vector3(0, 1.0 + h * 0.35, 0), h * 0.22, h * 0.5, 6, col.lightened(0.06))
	# Boulders near the tower
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 20.0)
		MeshUtil.box(st, Vector3(sin(a) * r, 0.2, cos(a) * r), Vector3(1, 0.7, 0.8) * rng.randf_range(0.6, 1.3), rng.randf() * TAU, Color(0.5, 0.5, 0.52))
	return MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE))

# --- retracting ledges ----------------------------------------------------------

# Out for most of the cycle, a rattle of warning, then it slides into the
# wall for a moment and comes back out
func _tick_retract(s: Dictionary, time: float) -> void:
	var period: float = s.period
	var t := fposmod(time + s.phase, period)
	var out_until := period * 0.62
	var ext := 1.0
	var rattle := 0.0
	if t < out_until - 0.5:
		ext = 1.0
	elif t < out_until:
		rattle = 0.05
	elif t < out_until + 0.3:
		ext = 1.0 - (t - out_until) / 0.3
	elif t < period - 0.3:
		ext = 0.0
	else:
		ext = (t - (period - 0.3)) / 0.3
	s.broken = ext < 0.7
	if s.node:
		var c: float = (s.a0 + s.a1) * 0.5
		var out := Vector3(sin(c), 0, cos(c))
		s.node.position = -out * s.d1 * (1.0 - ext) + Vector3(randf_range(-rattle, rattle), 0, randf_range(-rattle, rattle))

# --- wires --------------------------------------------------------------------

const WIRE_SPRING := 70.0
const WIRE_DAMP := 5.0

# Height of wire `w` at t (0 = wall hook, 1 = post), including its sag and
# any bounce pushing it down around tb
static func wire_point(w: Dictionary, t: float) -> Vector3:
	var a: Vector3 = w.a
	var b: Vector3 = w.b
	var p := a.lerp(b, t)
	var tb: float = clamp(w.get("tb", 0.5), 0.05, 0.95)
	var shape := t / tb if t < tb else (1.0 - t) / (1.0 - tb)
	p.y -= w.sag * 4.0 * t * (1.0 - t) + w.get("dip", 0.0) * shape
	return p

func _tick_wire(w: Dictionary, delta: float) -> void:
	var was: float = w.dip
	w.dip_v += (-WIRE_SPRING * w.dip - WIRE_DAMP * w.dip_v) * delta
	w.dip += w.dip_v * delta
	if abs(w.dip) < 0.002 and abs(w.dip_v) < 0.01:
		w.dip = 0.0
		w.dip_v = 0.0
	if w.dip != was or w.line == null:
		_draw_wire(w)
		for b in w.perched:
			b.position = wire_point(w, b.get_meta("t"))
	for i in range(w.flying.size() - 1, -1, -1):
		var b: Node3D = w.flying[i]
		var v: Vector3 = b.get_meta("v")
		b.position += v * delta
		b.set_meta("v", v + Vector3(0, 2.0, 0) * delta)
		b.set_meta("life", b.get_meta("life") - delta)
		if b.get_meta("life") <= 0.0:
			b.queue_free()
			w.flying.remove_at(i)

# The bird landed on (or bounced on) this wire: every crow on it takes off
func scare_wire(w: Dictionary) -> void:
	for b: AnimatedSprite3D in w.perched:
		b.sprite_frames = Npc.recoloured(Player.FLAP_FRAMES, b.get_meta("tint"))
		b.offset = Vector2(0, 16)
		b.play("default")
		b.speed_scale = 3.0
		var away := Vector3(b.position.x, 0, b.position.z).normalized()
		b.set_meta("v", away * randf_range(2.0, 5.0) + Vector3(randf_range(-2, 2), randf_range(4.0, 7.0), randf_range(-2, 2)))
		b.set_meta("life", 2.5)
		w.flying.append(b)
	w.perched.clear()

func _draw_wire(w: Dictionary) -> void:
	if w.line == null:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.1, 0.08, 0.1)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		w.line = mi
	var im: ImmediateMesh = w.line.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 17:
		im.surface_add_vertex(wire_point(w, i / 16.0))
	im.surface_end()

func _build_wire(w: Dictionary) -> void:
	var st := MeshUtil.begin()
	var a: Vector3 = w.a
	var b: Vector3 = w.b
	# An iron hook on the wall, and a post on the platform
	MeshUtil.box(st, a, Vector3(0.18, 0.18, 0.3), atan2(a.x, a.z), Color(0.25, 0.24, 0.27))
	MeshUtil.beam(st, b - Vector3(0, 1.45, 0), b + Vector3(0, 0.12, 0), 0.14, WOOD)
	add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))
	_draw_wire(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(w.id)
	for i in w.birds:
		var tint: Color = Npc.TINTS.values()[rng.randi_range(0, Npc.TINTS.size() - 1)]
		var bird := AnimatedSprite3D.new()
		bird.sprite_frames = Npc.recoloured(Npc.IDLE_FRAMES, tint)
		bird.pixel_size = 0.085
		bird.offset = Vector2(0, 7)
		bird.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		bird.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		bird.shaded = false
		bird.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		bird.flip_h = rng.randf() < 0.5
		var t: float = (i + 1.0) / (w.birds + 1.0) + rng.randf_range(-0.05, 0.05)
		bird.set_meta("t", t)
		bird.set_meta("tint", tint)
		bird.position = wire_point(w, t)
		bird.play("default")
		bird.speed_scale = rng.randf_range(0.5, 1.0)
		add_child(bird)
		w.perched.append(bird)

# --- boost rings -----------------------------------------------------------------

func _build_ring(rg: Dictionary) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 1.2
	torus.rings = 16
	torus.ring_segments = 5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.55, 1.0, 0.95)
	torus.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The ring's hole faces along the way round the tower, so you glide through
	var theta: float = rg.theta
	var along := Vector3(cos(theta), 0, -sin(theta))
	mi.basis = Basis(Vector3.UP.cross(along).normalized(), along, Vector3.UP.cross(along).normalized().cross(along))
	mi.position = Vector3(sin(theta) * rg.r, rg.y, cos(theta) * rg.r)
	add_child(mi)
	rg.node = mi

# Returns the ring the bird just flew through (or {}), and gives it a pulse
func ring_hit(pos: Vector3) -> Dictionary:
	for rg in rings:
		if rg.cool > 0.0 or rg.node == null:
			continue
		if rg.node.position.distance_to(pos + Vector3(0, 0.6, 0)) < 1.25:
			rg.cool = 1.5
			var t := create_tween()
			t.tween_property(rg.node, "scale", Vector3.ONE * 1.5, 0.12)
			t.tween_property(rg.node, "scale", Vector3.ONE, 0.3)
			return rg
	return {}

# Where a falling bird crossed a wire this frame (or {}): {wire, t}
func wire_crossed(prev: Vector3, now: Vector3) -> Dictionary:
	for w in wires:
		var a2 := Vector2(w.a.x, w.a.z)
		var b2 := Vector2(w.b.x, w.b.z)
		var p2 := Vector2(now.x, now.z)
		var q := Geometry2D.get_closest_point_to_segment(p2, a2, b2)
		if q.distance_to(p2) > 0.45:
			continue
		var t: float = clamp(a2.distance_to(q) / max(a2.distance_to(b2), 0.01), 0.0, 1.0)
		var wy := wire_point(w, t).y
		if prev.y >= wy - 0.05 and now.y <= wy:
			return {"wire": w, "t": t}
	return {}

# A wooden deck held up by a propeller underneath (the blades spin in tick)
func _build_prop(holder: Node3D, s: Dictionary) -> void:
	var top: float = s.top
	var c := Vector2(s.cx, s.cz)
	var st := MeshUtil.begin()
	MeshUtil.extrude(st, s.polys[0], top - 0.22, top, Color(0.62, 0.44, 0.28), 1.0)
	# Plank lines and a rim
	var poly: PackedVector2Array = s.polys[0]
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		MeshUtil.beam(st, Vector3(p.x, top + 0.02, p.y), Vector3(q.x, top + 0.02, q.y), 0.1, WOOD)
	# Motor housing under the deck, with a brass cap
	MeshUtil.box(st, Vector3(c.x, top - 0.55, c.y), Vector3(0.6, 0.6, 0.6), 0.0, Color(0.35, 0.33, 0.38))
	MeshUtil.cone(st, Vector3(c.x, top - 0.85, c.y), 0.3, -0.35, 6, Color(0.8, 0.62, 0.25))
	holder.add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))
	var blades := Node3D.new()
	blades.name = "Blades"
	blades.position = Vector3(c.x, top - 1.0, c.y)
	var bt := MeshUtil.begin()
	MeshUtil.box(bt, Vector3.ZERO, Vector3(3.2, 0.06, 0.3), 0.0, Color(0.55, 0.4, 0.28))
	MeshUtil.box(bt, Vector3.ZERO, Vector3(0.3, 0.06, 3.2), 0.0, Color(0.5, 0.36, 0.25))
	blades.add_child(MeshUtil.commit(bt, MeshUtil.flat_material(Color.WHITE)))
	holder.add_child(blades)

# A brass-edged platform riding a rail round the whole tower. The rail stays
# put; the platform's holder is rotated by tick.
func _build_orbit(holder: Node3D, s: Dictionary, tint: Color) -> void:
	var top: float = s.top
	var st := MeshUtil.begin()
	for poly in s.polys:
		MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.95, 0.85, 0.6))
	holder.add_child(MeshUtil.commit(st, MeshUtil.stone_material(tint.lerp(Color(1.0, 0.93, 0.8), 0.5), "slab")))
	var rail := MeshUtil.begin()
	var n := 40
	var rr: float = s.rail_r
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		MeshUtil.beam(rail, Vector3(sin(a0) * rr, top - 0.5, cos(a0) * rr), Vector3(sin(a1) * rr, top - 0.5, cos(a1) * rr), 0.12, Color(0.55, 0.45, 0.3))
	add_child(MeshUtil.commit(rail, MeshUtil.flat_material(Color.WHITE)))
