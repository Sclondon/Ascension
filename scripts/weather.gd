class_name Weather
extends Node3D
# Sky, fog, sun, particles and wind for each height band, blended smoothly
# over the first stretch of every band.

signal lightning

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const BLEND_HEIGHT := 25.0

const TYPES := [
	{"name": "The Hemlock Grounds", "top": Color(0.25, 0.35, 0.7), "horizon": Color(0.95, 0.6, 0.42), "bottom": Color(0.2, 0.25, 0.3),
	 "fog": Color(0.85, 0.62, 0.55), "fog_density": 0.004, "light": Color(1.0, 0.85, 0.65), "light_energy": 1.1,
	 "ambient": Color(0.55, 0.5, 0.62), "stars": 0.0, "aurora": 0.0, "sun": 1.0, "particles": "", "wind": 0.0,
	 "glow": 0.6, "cloud": Color(1.0, 0.9, 0.85), "cover": 0.5},
	{"name": "The Misty Spires", "top": Color(0.45, 0.5, 0.6), "horizon": Color(0.72, 0.74, 0.78), "bottom": Color(0.5, 0.52, 0.56),
	 "fog": Color(0.72, 0.74, 0.78), "fog_density": 0.024, "light": Color(0.9, 0.9, 0.95), "light_energy": 0.6,
	 "ambient": Color(0.62, 0.64, 0.7), "stars": 0.0, "aurora": 0.0, "sun": 0.2, "particles": "mist", "wind": 1.2,
	 "glow": 1.0, "cloud": Color(0.9, 0.92, 0.95), "cover": 0.6},
	{"name": "The Weeping Walls", "top": Color(0.2, 0.24, 0.32), "horizon": Color(0.38, 0.42, 0.5), "bottom": Color(0.15, 0.17, 0.22),
	 "fog": Color(0.35, 0.38, 0.45), "fog_density": 0.02, "light": Color(0.7, 0.75, 0.85), "light_energy": 0.5,
	 "ambient": Color(0.5, 0.54, 0.64), "stars": 0.0, "aurora": 0.0, "sun": 0.0, "particles": "rain", "wind": 1.8,
	 "glow": 1.4, "cloud": Color(0.55, 0.58, 0.66), "cover": 0.65},
	{"name": "The Stormcrown", "top": Color(0.08, 0.08, 0.15), "horizon": Color(0.22, 0.2, 0.3), "bottom": Color(0.06, 0.06, 0.1),
	 "fog": Color(0.18, 0.17, 0.25), "fog_density": 0.018, "light": Color(0.6, 0.6, 0.8), "light_energy": 0.4,
	 "ambient": Color(0.42, 0.42, 0.58), "stars": 0.0, "aurora": 0.0, "sun": 0.0, "particles": "rain", "wind": 2.8,
	 "glow": 1.8, "cloud": Color(0.3, 0.3, 0.4), "cover": 0.7, "lightning": true},
	{"name": "The Frost Gallery", "top": Color(0.35, 0.5, 0.75), "horizon": Color(0.85, 0.9, 0.98), "bottom": Color(0.6, 0.65, 0.75),
	 "fog": Color(0.85, 0.9, 0.95), "fog_density": 0.015, "light": Color(0.95, 0.97, 1.0), "light_energy": 0.9,
	 "ambient": Color(0.7, 0.75, 0.9), "stars": 0.0, "aurora": 0.0, "sun": 0.5, "particles": "snow", "wind": 2.2,
	 "glow": 0.9, "cloud": Color(0.95, 0.97, 1.0), "cover": 0.6},
	{"name": "Above the Clouds", "top": Color(0.1, 0.3, 0.75), "horizon": Color(0.6, 0.8, 1.0), "bottom": Color(0.9, 0.92, 1.0),
	 "fog": Color(0.8, 0.88, 1.0), "fog_density": 0.002, "light": Color(1.0, 0.97, 0.9), "light_energy": 1.3,
	 "ambient": Color(0.7, 0.75, 0.9), "stars": 0.0, "aurora": 0.0, "sun": 1.0, "particles": "", "wind": 1.4,
	 "glow": 0.5, "cloud": Color(1.0, 1.0, 1.0), "cover": 0.8},
	{"name": "The Aurora Vault", "top": Color(0.02, 0.03, 0.1), "horizon": Color(0.08, 0.12, 0.25), "bottom": Color(0.05, 0.08, 0.15),
	 "fog": Color(0.05, 0.08, 0.15), "fog_density": 0.006, "light": Color(0.55, 0.7, 0.95), "light_energy": 0.45,
	 "ambient": Color(0.42, 0.46, 0.68), "stars": 1.0, "aurora": 1.0, "sun": 0.0, "particles": "sparkle", "wind": 0.8,
	 "glow": 2.0, "cloud": Color(0.35, 0.4, 0.6), "cover": 0.5},
]

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var emitters := {}
var wind_fx: CPUParticles3D           # streaks showing which way the wind blows
var current: Dictionary = {}
var band := -1
var wind := 0.0                      # tangential m/s, sampled by the player
var cloud_tint := Color.WHITE
var flash := 0.0
var time := 0.0
var lightning_timer := 5.0

static func weather_of(b: int) -> Dictionary:
	return TYPES[b % TYPES.size()]

static func band_name(b: int) -> String:
	var cycle := b / TYPES.size()
	var numerals := ["", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X"]
	return weather_of(b).name + (numerals[cycle] if cycle < numerals.size() else " %d" % (cycle + 1))

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = false       # the blob shadow does the job, and it's cheap on phones
	add_child(sun)

	emitters.rain = _emitter(500, 0.9, Vector3(0.025, 0.55, 1), Color(0.7, 0.8, 1.0, 0.55), Vector3(9, 0.5, 9), 20.0, 5.0, true)
	emitters.snow = _emitter(260, 7.0, Vector3(0.09, 0.09, 1), Color(1, 1, 1, 0.9), Vector3(10, 0.5, 10), 1.2, 35.0, false)
	emitters.mist = _emitter(36, 7.0, Vector3(3.0, 1.6, 1), Color(1, 1, 1, 0.13), Vector3(9, 6, 9), 0.25, 180.0, false)
	emitters.sparkle = _emitter(70, 3.0, Vector3(0.07, 0.07, 1), Color(0.6, 1.0, 0.8, 1.0), Vector3(9, 6, 9), 0.3, 180.0, false)

	wind_fx = CPUParticles3D.new()
	wind_fx.amount = 40
	wind_fx.lifetime = 0.9
	wind_fx.local_coords = false
	wind_fx.emitting = false
	wind_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wind_fx.emission_box_extents = Vector3(6, 5, 6)
	wind_fx.spread = 4.0
	wind_fx.gravity = Vector3.ZERO
	wind_fx.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	var streak := BoxMesh.new()
	streak.size = Vector3(0.035, 1.1, 0.035)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(1, 1, 1, 0.35)
	streak.material = sm
	wind_fx.mesh = streak
	add_child(wind_fx)
	current = weather_of(0).duplicate()

func _emitter(amount: int, life: float, quad_size: Vector3, color: Color, extents: Vector3, speed: float, spread: float, stretch: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.DOWN
	p.spread = spread
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed
	p.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(quad_size.x, quad_size.y)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if stretch else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	p.mesh = q
	add_child(p)
	return p

# Blended weather at height y
func sample(y: float) -> Dictionary:
	var b := TowerShape.band_at(y)
	var cur := weather_of(b)
	if b == 0:
		var first := cur.duplicate()
		first.lightning = false
		return first
	var t: float = clamp((y - b * TowerShape.BAND_H) / BLEND_HEIGHT, 0.0, 1.0)
	var prev := weather_of(b - 1)
	var out := {}
	for key in cur:
		var a = prev.get(key, cur[key])
		var c = cur[key]
		if c is Color or c is float:
			out[key] = lerp(a, c, t)
		else:
			out[key] = c if t > 0.5 else a
	out.lightning = cur.get("lightning", false) and t > 0.5
	return out

func update(delta: float, focus: Vector3, theta: float) -> void:
	time += delta
	band = TowerShape.band_at(focus.y)
	current = sample(focus.y)
	var w := current

	sky_mat.set_shader_parameter("top_color", w.top)
	sky_mat.set_shader_parameter("horizon_color", w.horizon)
	sky_mat.set_shader_parameter("bottom_color", w.bottom)
	sky_mat.set_shader_parameter("sun_color", w.light)
	sky_mat.set_shader_parameter("sun_amount", w.sun)
	sky_mat.set_shader_parameter("stars", w.stars)
	sky_mat.set_shader_parameter("aurora", w.aurora)

	# Fog thickens as you near a cloud deck
	var deck_band := roundi(focus.y / TowerShape.BAND_H)
	var near_deck := 0.0
	if deck_band >= 1:
		near_deck = 1.0 - clamp(abs(focus.y - CloudLayers.deck_height(deck_band)) / 10.0, 0.0, 1.0)
	env.fog_light_color = (w.fog as Color).lerp(Color(0.8, 0.82, 1.0), flash * 0.75)
	env.fog_density = w.fog_density + near_deck * 0.04
	env.ambient_light_color = w.ambient

	# Lightning
	flash = max(flash - delta * 3.0, 0.0)
	if w.lightning:
		lightning_timer -= delta
		if lightning_timer <= 0.0:
			lightning_timer = randf_range(3.5, 9.0)
			flash = 1.0
			lightning.emit()
	sky_mat.set_shader_parameter("flash", flash * 0.6)
	sun.light_color = w.light
	sun.light_energy = w.light_energy + flash * 2.0
	# How brightly lit unshaded things (clouds) should look right now
	var l: Color = w.light * (w.light_energy * 0.6) + w.ambient * 0.6
	cloud_tint = Color(min(l.r, 1.0), min(l.g, 1.0), min(l.b, 1.0)).lerp(Color.WHITE, flash * 0.5)

	# Wind: steady per band with gusts, direction alternating by band
	var dir := 1.0 if band % 2 == 0 else -1.0
	var gust: float = 0.6 + 0.4 * sin(time * 0.9) + (0.7 * max(sin(time * 2.3), 0.0) if w.lightning else 0.0)
	wind = w.wind * gust * dir
	var tangent := Vector3(cos(theta), 0, -sin(theta)) * wind

	# Wind streaks sweep past the bird in the direction it will be pushed
	var windy: bool = abs(wind) > 0.4
	if wind_fx.emitting != windy:
		wind_fx.emitting = windy
	if windy:
		var dir_w: Vector3 = Vector3(cos(theta), 0, -sin(theta)) * sign(wind)
		wind_fx.global_position = focus + Vector3(0, 1.5, 0) - dir_w * 5.0
		wind_fx.direction = dir_w
		wind_fx.initial_velocity_min = 8.0 + abs(wind) * 2.0
		wind_fx.initial_velocity_max = 11.0 + abs(wind) * 2.5
		(wind_fx.mesh.material as StandardMaterial3D).albedo_color.a = clamp(abs(wind) / 4.0, 0.15, 0.5)

	for key in emitters:
		var e: CPUParticles3D = emitters[key]
		var on: bool = w.particles == key
		if e.emitting != on:
			e.emitting = on
		if on:
			e.global_position = focus + (Vector3(0, 9, 0) if key == "rain" or key == "snow" else Vector3(0, 1, 0))
			e.gravity = tangent * (3.0 if key == "rain" else 1.0)
