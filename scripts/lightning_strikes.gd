class_name LightningStrikes
extends Node3D
# In thunderstorm bands, lightning hits the tower. Strikes near the bird are
# telegraphed (crackling sparks and a glowing mark for a second) so there's
# time to get clear; the bolt then smashes whatever ledge it hits (it grows
# back like a crumbling one) and zaps the bird if it's still there.

const WARNING := 1.0                 # seconds of crackle before a nearby strike
const HIT_RADIUS := 1.8
const BOLT_TIME := 0.28

var tower: TowerGenerator
var player: Player
var weather: Weather
var timer := 4.0
var pending: Array[Dictionary] = []  # {pos, t, surface, fx}

func update(delta: float) -> void:
	for i in range(pending.size() - 1, -1, -1):
		var p: Dictionary = pending[i]
		p.t -= delta
		if p.t <= 0.0:
			_strike(p)
			pending.remove_at(i)
	if player == null or not player.active or not weather.current.get("lightning", false):
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = randf_range(4.0, 8.0)
	if randf() < 0.45:
		_aim_near_player()
	else:
		_aim_elsewhere()

# Somewhere close to the bird, with a warning
func _aim_near_player() -> void:
	var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.5)
	var pos := player.world_position() + Vector3(off.x, 0, off.y)
	var theta := atan2(pos.x, pos.z)
	var r := Vector2(pos.x, pos.z).length()
	var floor_y := tower.ground_below(theta, r, pos.y + 0.5, 30.0)
	pos.y = floor_y if floor_y > -INF else pos.y
	pending.append({"pos": pos, "t": WARNING, "fx": _warning_fx(pos)})

# A random ledge in view (no warning needed, it's not near you)
func _aim_elsewhere() -> void:
	var options := tower.path_around(player.y).filter(func(s):
		return s.kind != ChunkPlanner.Kind.RING and s.kind != ChunkPlanner.Kind.GROUND and abs(s.top - player.y) < 10.0)
	if options.is_empty():
		return
	var s: Dictionary = options[randi_range(0, options.size() - 1)]
	var a: float = (s.a0 + s.a1) * 0.5
	var r: float = Vector2(s.cx, s.cz).length() if ChunkPlanner.is_outer(s) else TowerShape.wall_r(s.k, a, s.d1 * 0.5)
	if Vector2(sin(a) * r, cos(a) * r).distance_to(Vector2(player.world_position().x, player.world_position().z)) < 4.0:
		return   # too close to be unannounced
	pending.append({"pos": Vector3(sin(a) * r, s.top, cos(a) * r), "t": 0.0, "fx": null})

func _strike(p: Dictionary) -> void:
	var pos: Vector3 = p.pos
	if p.fx:
		p.fx.queue_free()
	weather.flash_now()
	_bolt(pos)
	_burst(pos)
	# Smash the ledge it hit
	var theta := atan2(pos.x, pos.z)
	var r := Vector2(pos.x, pos.z).length()
	var hit := tower.find_landing(pos.y + 0.3, pos.y - 0.3, theta, r)
	if not hit.is_empty():
		tower.smash(hit)
	# And the bird, if it didn't get clear
	var bird := player.world_position()
	if Vector2(bird.x - pos.x, bird.z - pos.z).length() < HIT_RADIUS and abs(bird.y - pos.y) < 2.5:
		player.zap()

# Crackling sparks and a pulsing mark where it's about to hit
func _warning_fx(pos: Vector3) -> Node3D:
	var fx := Node3D.new()
	add_child(fx)
	fx.global_position = pos + Vector3(0, 0.05, 0)
	var mark := Sprite3D.new()
	mark.texture = MeshUtil.blob_texture(16, Color(0.6, 0.85, 1.0))
	mark.pixel_size = 0.14
	mark.axis = Vector3.AXIS_Y
	mark.shaded = false
	mark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fx.add_child(mark)
	var t := mark.create_tween().set_loops()
	t.tween_property(mark, "modulate:a", 0.25, 0.12)
	t.tween_property(mark, "modulate:a", 1.0, 0.12)
	var sparks := _particles(24, 0.5, Color(0.7, 0.9, 1.0), 0.09)
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.9
	sparks.direction = Vector3.UP
	sparks.spread = 40.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 3.5
	fx.add_child(sparks)
	sparks.emitting = true
	return fx

# A jagged ribbon from the clouds down to the strike point
func _bolt(pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pts: Array[Vector3] = []
	var top := pos + Vector3(randf_range(-4, 4), 45.0, randf_range(-4, 4))
	for i in 14:
		var t := i / 13.0
		var p := top.lerp(pos, t)
		if i > 0 and i < 13:
			p += Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2)) * (1.0 - t * 0.6)
		pts.append(p)
	var im := ImmediateMesh.new()
	for pass_i in 2:
		var w := 0.5 if pass_i == 0 else 0.16
		var col := Color(0.6, 0.75, 1.0, 0.35) if pass_i == 0 else Color(1, 1, 1, 1)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in pts.size():
			var along := (pts[min(i + 1, pts.size() - 1)] - pts[max(i - 1, 0)]).normalized()
			var side := along.cross(cam.global_position - pts[i]).normalized() * w
			im.surface_set_color(col)
			im.surface_add_vertex(pts[i] + side)
			im.surface_set_color(col)
			im.surface_add_vertex(pts[i] - side)
		im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Flicker, then gone
	var t := mi.create_tween()
	t.tween_property(mi, "visible", false, 0.06)
	t.tween_property(mi, "visible", true, 0.05)
	t.tween_interval(BOLT_TIME - 0.11)
	t.tween_callback(mi.queue_free)

func _burst(pos: Vector3) -> void:
	var p := _particles(30, 0.7, Color(0.85, 0.95, 1.0), 0.12)
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -12, 0)
	add_child(p)
	p.global_position = pos + Vector3(0, 0.2, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)

static func _particles(amount: int, life: float, color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	p.mesh = q
	return p
