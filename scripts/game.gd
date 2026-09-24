extends Node3D
# Hemlock's Tower: Doodle Jump wrapped around a tower. The crow bounces
# automatically; steering spins the tower so the crow always stays in front.

enum State { MENU, PLAYING, DEAD }
enum Kind { NORMAL, CRUMBLE, MOVING, SPRING }

const TOWER_RADIUS := 3.75
const PLAYER_RADIUS := 4.85          # distance from the tower axis to the crow
const PLATFORM_DEPTH := 2.2
const PLATFORM_THICKNESS := 0.45
const GRAVITY := 34.0
const BOUNCE_SPEED := 18.5           # ~5 units of jump height
const SPRING_SPEED := 29.0
const MAX_TURN_SPEED := 1.9          # radians per second
const TURN_ACCEL := 14.0
const PLAYER_HALF_WIDTH := 0.3
const SEGMENT_HEIGHT := 8.0
const DEATH_MARGIN := 9.0            # how far below the camera the crow may drop
const CAMERA_DISTANCE := 12.5
const MIN_VIEW_WIDTH := 11.5
const MIN_VIEW_HEIGHT := 17.0

const WALL_MAT := preload("res://materials/brickwall_mat.tres")
const PLATFORM_MAT := preload("res://materials/brickwallsmall_mat.tres")
const DIRT_MAT := preload("res://materials/dirt_mat.tres")
const CLOUD_MAT := preload("res://materials/densecloudmat.tres")
const FENCE_TEX := preload("res://images/brickfence.png")
const IDLE_FRAMES := preload("res://animations/player_idle_SF.tres")
const JUMP_FRAMES := preload("res://animations/player_jump_SF.tres")
const FALL_FRAMES := preload("res://animations/player_fall.tres")

const BEST_PATH := "user://best.save"

var state := State.MENU
var autoplay := false
var autoplay_target: Dictionary = {}
var autoplay_from: Node3D

var tower: Node3D
var camera: Camera3D
var crow: AnimatedSprite3D
var sky_mat: ProceduralSkyMaterial
var light: DirectionalLight3D

var theta := 0.0                     # crow's angle around the tower
var turn_speed := 0.0
var y := 0.0
var vy := 0.0
var cam_y := 0.0
var max_y := 0.0
var best := 0
var dead_time := 0.0
var time := 0.0
var squash := 0.0

var pointer_down := false
var pointer_x := 0.0

var platforms: Array[Dictionary] = []
var segments: Array[Node3D] = []
var next_platform_y := 0.0
var last_path_angle := 0.0
var top_segment_y := -SEGMENT_HEIGHT * 2

var score_label: Label
var best_label: Label
var title_panel: Control
var over_panel: Control
var over_score: Label
var over_best: Label

func _ready() -> void:
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	randomize()
	if not autoplay:
		_load_best()
	_build_world()
	_build_ui()
	_reset()

# --- setup -----------------------------------------------------------------

func _build_world() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.2
	sky_mat.ground_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.4
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.65)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.35, 0.2, 0.3)
	env.fog_density = 0.012
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	tower = Node3D.new()
	add_child(tower)

	# Clouds far below: what you fall into
	for i in 3:
		var clouds := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(400, 400)
		plane.material = CLOUD_MAT
		clouds.mesh = plane
		clouds.position = Vector3(0, -16 - i * 4, 0)
		clouds.rotation.y = i * 1.3
		add_child(clouds)

	camera = Camera3D.new()
	camera.fov = 60
	add_child(camera)
	camera.make_current()

	crow = AnimatedSprite3D.new()
	crow.pixel_size = 0.12
	crow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	crow.shaded = false
	crow.no_depth_test = true    # always drawn over the ledges, 2.5D style
	crow.render_priority = 10
	crow.sprite_frames = IDLE_FRAMES
	crow.offset = Vector2(0, 8)          # feet at the node origin
	add_child(crow)

	# A soft shadow blob so the crow is readable against the bricks
	var shadow := Sprite3D.new()
	shadow.texture = _make_glow_texture()
	shadow.pixel_size = 0.035
	shadow.modulate = Color(1, 0.75, 0.45, 0.35)
	shadow.position = Vector3(0, 0.7, -0.1)
	shadow.no_depth_test = true
	shadow.render_priority = 9
	crow.add_child(shadow)

func _make_glow_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	score_label = _label(56, Color(1, 0.85, 0.6))
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label.position = Vector2(-200, 24)
	score_label.size = Vector2(400, 70)
	root.add_child(score_label)

	best_label = _label(24, Color(0.85, 0.75, 0.95))
	best_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	best_label.position = Vector2(-200, 92)
	best_label.size = Vector2(400, 32)
	root.add_child(best_label)

	title_panel = _panel(root, [
		[_label(64, Color(0.95, 0.35, 0.45)), "HEMLOCK'S\nTOWER"],
		[_label(26, Color(1, 0.9, 0.75)), "Climb out from the deep"],
		[_label(24, Color(0.85, 0.85, 1)), "← →  /  A D  to spin the tower\nor hold the left / right side"],
		[_label(30, Color(1, 1, 1)), "Tap or press any key"],
	])
	var over := _panel(root, [
		[_label(60, Color(0.95, 0.35, 0.45)), "YOU FELL"],
		[_label(44, Color(1, 0.85, 0.6)), ""],
		[_label(26, Color(0.85, 0.75, 0.95)), ""],
		[_label(28, Color(1, 1, 1)), "Tap to climb again"],
	])
	over_panel = over
	var labels := over.get_child(0).get_children()
	over_score = labels[1]
	over_best = labels[2]

func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.1))
	l.add_theme_constant_override("outline_size", max(6, font_size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel(root: Control, rows: Array) -> Control:
	var panel := CenterContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	for row in rows:
		var l: Label = row[0]
		l.text = row[1]
		box.add_child(l)
	root.add_child(panel)
	return panel

# --- run lifecycle ----------------------------------------------------------

func _reset() -> void:
	for p in platforms:
		p.node.queue_free()
	platforms.clear()
	for s in segments:
		s.queue_free()
	segments.clear()
	top_segment_y = -SEGMENT_HEIGHT * 2

	theta = 0.0
	turn_speed = 0.0
	y = 0.0
	vy = BOUNCE_SPEED
	cam_y = 0.0
	max_y = 0.0
	last_path_angle = 0.0
	next_platform_y = 0.4
	pointer_down = false

	_add_platform(0.0, 0.0, Kind.NORMAL, TAU)   # the ring at the base of the tower
	_fill_world()
	_update_score_labels()
	title_panel.visible = state == State.MENU
	over_panel.visible = false

func _start() -> void:
	if state == State.DEAD:
		_reset()
	state = State.PLAYING
	title_panel.visible = false
	over_panel.visible = false

func _die() -> void:
	state = State.DEAD
	dead_time = 0.0
	var score := int(max_y)
	if score > best and not autoplay:
		best = score
		_save_best()
	over_score.text = "%d m" % score
	over_best.text = "Best  %d m" % best
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.parent.postMessage({ type: 'PLAYER_DIED', score: %d }, '*')" % score, true)

func _load_best() -> void:
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	if f:
		best = f.get_32()

func _save_best() -> void:
	var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
	if f:
		f.store_32(best)

# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if autoplay:
		return
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_down = event.pressed
		pointer_x = event.position.x
		pressed = event.pressed
	elif event is InputEventMouseMotion:
		pointer_x = event.position.x
		# The release can happen outside the iframe and never reach us
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			pointer_down = false
	elif event is InputEventKey and event.pressed and not event.echo:
		pressed = true

	if pressed:
		if state == State.MENU:
			_start()
		elif state == State.DEAD and dead_time > 0.8:
			_start()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		pointer_down = false

func _steer_input() -> float:
	var dir := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		dir += 1.0
	dir += Input.get_joy_axis(0, JOY_AXIS_LEFT_X) if abs(Input.get_joy_axis(0, JOY_AXIS_LEFT_X)) > 0.25 else 0.0
	if pointer_down and dir == 0.0:
		# Hold anywhere (keys win over a held pointer): the further from the middle, the faster the spin
		var w := get_viewport().get_visible_rect().size.x
		dir += clamp((pointer_x - w * 0.5) / (w * 0.22), -1.0, 1.0)
	if autoplay:
		dir = _autoplay_steer()
	return clamp(dir, -1.0, 1.0)

func _autoplay_steer() -> float:
	# Demo mode (used to record the cabinet video): fly toward the target
	# picked at the last bounce
	if vy < 0.0 and (autoplay_target.is_empty() or autoplay_target.broken or y < autoplay_target.top - 0.1):
		# Missed it: steer for the closest ledge below instead
		autoplay_target = {}
		var best_diff := INF
		for p in platforms:
			var diff: float = abs(wrapf(_platform_angle(p) - theta, -PI, PI))
			if not p.broken and p.top < y and p.top > y - 6.0 and diff < best_diff:
				best_diff = diff
				autoplay_target = p
	if autoplay_target.is_empty():
		return 0.0
	var diff := wrapf(_platform_angle(autoplay_target) - theta, -PI, PI)
	return clamp(-diff * 4.0, -1.0, 1.0)

func _pick_autoplay_target(bounce: float) -> void:
	var apex := bounce * bounce / (2.0 * GRAVITY)
	var best_score := -INF
	autoplay_target = {}
	for p in platforms:
		if p.broken or p.half_width > 100.0 or p.get("ai_skip", false):
			continue
		var h: float = p.top - y
		if h < 0.5 or h > apex * 0.85:
			continue
		var t := (bounce + sqrt(bounce * bounce - 2.0 * GRAVITY * h)) / GRAVITY
		var diff: float = abs(wrapf(_platform_angle(p) - theta, -PI, PI))
		if diff > MAX_TURN_SPEED * t * 0.6:
			continue
		var score := h - diff * 1.5
		if p.kind == Kind.CRUMBLE:
			score -= 4.0
		if p.kind == Kind.SPRING:
			score += 3.0
		if score > best_score:
			best_score = score
			autoplay_target = p
	if autoplay_target.is_empty():
		# Nothing comfortably reachable: go for the nearest ledge above
		for p in platforms:
			var h: float = p.top - y
			if not p.broken and h > 0.5 and h < apex * 0.95:
				if autoplay_target.is_empty() or abs(wrapf(_platform_angle(p) - theta, -PI, PI)) < abs(wrapf(_platform_angle(autoplay_target) - theta, -PI, PI)):
					autoplay_target = p

# --- simulation -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	time += delta
	if state == State.DEAD:
		dead_time += delta
		if dead_time > 0.8:
			over_panel.visible = true
		if autoplay and dead_time > 2.0:
			_start()
	if autoplay and state == State.MENU and time > 1.5:
		_start()

	var steer := _steer_input() if state == State.PLAYING else 0.0
	var target_speed := steer * MAX_TURN_SPEED
	turn_speed = move_toward(turn_speed, target_speed, TURN_ACCEL * delta)
	theta -= turn_speed * delta      # D / right spins the tower's face to the right
	if abs(steer) > 0.1:
		crow.flip_h = steer > 0      # sprite art faces left

	var prev_y := y
	vy -= GRAVITY * delta
	y += vy * delta

	if vy <= 0.0 and state != State.DEAD:
		for p in platforms:
			if p.broken:
				continue
			if prev_y >= p.top - 0.05 and y <= p.top:
				var diff: float = abs(wrapf(_platform_angle(p) - theta, -PI, PI))
				if diff * PLAYER_RADIUS <= p.half_width + PLAYER_HALF_WIDTH:
					_land(p)
					break

	if state == State.PLAYING or state == State.MENU:
		max_y = max(max_y, y)
		if y < cam_y - DEATH_MARGIN and state == State.PLAYING:
			_die()

	_update_platforms(delta)
	_fill_world()
	_update_score_labels()

func _land(p: Dictionary) -> void:
	y = p.top
	vy = SPRING_SPEED if p.kind == Kind.SPRING else BOUNCE_SPEED
	if autoplay:
		if p.node == autoplay_from and not autoplay_target.is_empty():
			autoplay_target["ai_skip"] = true   # missed it last time, try another ledge
		autoplay_from = p.node
		_pick_autoplay_target(vy)
		if OS.has_environment("DEBUG_AI"):
			print("land y=%.1f theta=%.2f target=%s" % [y, theta, "none" if autoplay_target.is_empty() else "%.1f@%.2f k%d" % [autoplay_target.top, _platform_angle(autoplay_target), autoplay_target.kind]])
	squash = 1.0
	if p.kind == Kind.CRUMBLE:
		p.broken = true
	if p.kind == Kind.SPRING:
		var spring: Node3D = p.node.get_node("Spring")
		var t := create_tween()
		t.tween_property(spring, "scale", Vector3(1.3, 1.8, 1.3), 0.06)
		t.tween_property(spring, "scale", Vector3.ONE, 0.25)

func _platform_angle(p: Dictionary) -> float:
	if p.kind == Kind.MOVING:
		return p.angle + sin(time * p.speed + p.phase) * p.swing
	return p.angle

func _update_platforms(delta: float) -> void:
	for i in range(platforms.size() - 1, -1, -1):
		var p: Dictionary = platforms[i]
		var node: Node3D = p.node
		if p.kind == Kind.MOVING:
			node.rotation.y = _platform_angle(p)
		if p.broken:
			p.fall += delta * 22.0
			node.position.y -= p.fall * delta
			node.rotation.z += delta * 1.5
			node.scale = node.scale.lerp(Vector3.ZERO, delta * 1.5)
		if p.top < cam_y - 25.0 or node.position.y < cam_y - 25.0:
			node.queue_free()
			platforms.remove_at(i)

func _process(delta: float) -> void:
	# Camera only climbs, Doodle Jump style; it keeps the crow in the lower half
	if state != State.DEAD:
		cam_y = max(cam_y, y - 1.0)
	_update_camera()

	tower.rotation.y = -theta
	crow.position = Vector3(0, y, PLAYER_RADIUS)
	squash = move_toward(squash, 0.0, delta * 5.0)
	crow.scale = Vector3(1.0 + squash * 0.25, 1.0 - squash * 0.25, 1.0)
	var frames := JUMP_FRAMES if vy > 3.0 else (FALL_FRAMES if vy < -3.0 else IDLE_FRAMES)
	if crow.sprite_frames != frames:
		crow.sprite_frames = frames
		crow.play("default")
	crow.speed_scale = 2.0 if frames == JUMP_FRAMES else 1.5
	if state == State.DEAD:
		crow.rotation.z += delta * 6.0
	else:
		crow.rotation.z = 0.0

	# The sky darkens from dusk into night as you climb
	var night: float = clamp(max_y / 400.0, 0.0, 1.0)
	sky_mat.sky_top_color = Color(0.14, 0.17, 0.45).lerp(Color(0.03, 0.02, 0.1), night)
	sky_mat.sky_horizon_color = Color(0.76, 0.33, 0.24).lerp(Color(0.3, 0.08, 0.25), night)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.04, 0.06, 0.12)

func _update_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect: float = size.x / max(size.y, 1.0)
	# Pick a vertical FOV that shows at least MIN_VIEW_WIDTH x MIN_VIEW_HEIGHT
	var needed_h: float = max(MIN_VIEW_HEIGHT, MIN_VIEW_WIDTH / aspect)
	var dist := CAMERA_DISTANCE + PLAYER_RADIUS - 0.5
	camera.fov = clamp(rad_to_deg(2.0 * atan(needed_h * 0.5 / CAMERA_DISTANCE)), 40.0, 100.0)
	camera.position = Vector3(0, cam_y + 3.5, dist)
	camera.look_at(Vector3(0, cam_y + 2.5, 0.0), Vector3.UP)

func _update_score_labels() -> void:
	score_label.text = "%d m" % int(max_y)
	best_label.text = "Best  %d m" % best if best > 0 else ""
	score_label.visible = state != State.MENU
	best_label.visible = state != State.MENU

# --- world generation -------------------------------------------------------

func _fill_world() -> void:
	while top_segment_y < cam_y + 30.0:
		_add_segment(top_segment_y)
		top_segment_y += SEGMENT_HEIGHT
	for i in range(segments.size() - 1, -1, -1):
		if segments[i].position.y < cam_y - 30.0:
			segments[i].queue_free()
			segments.remove_at(i)
	while next_platform_y < cam_y + 28.0:
		_spawn_row()

func _add_segment(at_y: float) -> void:
	var seg := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = TOWER_RADIUS
	mesh.bottom_radius = TOWER_RADIUS
	mesh.height = SEGMENT_HEIGHT
	mesh.radial_segments = 24
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat: StandardMaterial3D = WALL_MAT.duplicate()
	mat.uv1_scale = Vector3(6, 1.5, 1)
	mesh.material = mat
	seg.mesh = mesh
	seg.position.y = at_y + SEGMENT_HEIGHT * 0.5
	tower.add_child(seg)
	segments.append(seg)

	# A few dark arrow-slit windows so the spin is easy to read
	for i in 3:
		var a := randf() * TAU
		var win := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 1.3, 0.2)
		var wm := StandardMaterial3D.new()
		var lit := randf() < 0.35
		wm.albedo_color = Color(1.0, 0.7, 0.3) if lit else Color(0.04, 0.03, 0.06)
		if lit:
			wm.emission_enabled = true
			wm.emission = Color(1.0, 0.55, 0.2)
			wm.emission_energy_multiplier = 1.5
		box.material = wm
		win.mesh = box
		win.position = Vector3(sin(a) * (TOWER_RADIUS - 0.05), randf_range(-2.5, 2.5), cos(a) * (TOWER_RADIUS - 0.05))
		win.rotation.y = a
		seg.add_child(win)

func _difficulty() -> float:
	return clamp(next_platform_y / 600.0, 0.0, 1.0)

func _spawn_row() -> void:
	var d := _difficulty()
	var gap := randf_range(lerp(1.9, 2.8, d), lerp(2.8, 4.3, d))
	next_platform_y += gap

	# The main path: always reachable from the previous path platform
	var step := randf_range(0.35, lerp(1.0, 1.35, d)) * (1.0 if randf() < 0.5 else -1.0)
	last_path_angle += step
	var roll := randf()
	var kind := Kind.NORMAL
	if next_platform_y > 35.0 and roll < lerp(0.15, 0.35, d):
		kind = Kind.MOVING
	elif roll > 0.94 and next_platform_y > 20.0:
		kind = Kind.SPRING
	var width := randf_range(lerp(3.0, 2.2, d), lerp(3.4, 2.6, d))
	_add_platform(next_platform_y, last_path_angle, kind, width)

	# Extras: sometimes a second safe ledge, sometimes a crumbling trap
	if randf() < lerp(0.3, 0.1, d):
		_add_platform(next_platform_y + randf_range(-0.6, 0.6), last_path_angle + randf_range(2.0, 4.3), Kind.NORMAL, width)
	if next_platform_y > 15.0 and randf() < lerp(0.12, 0.35, d):
		_add_platform(next_platform_y + randf_range(-1.0, 1.0), last_path_angle + randf_range(1.5, 4.8), Kind.CRUMBLE, 2.6)

func _add_platform(top: float, angle: float, kind: int, width: float) -> void:
	var pivot := Node3D.new()
	pivot.position.y = top
	pivot.rotation.y = angle
	tower.add_child(pivot)

	var p := {
		"node": pivot, "top": top, "angle": angle, "kind": kind,
		"broken": false, "fall": 0.0, "half_width": width * 0.5,
		"speed": 0.0, "phase": 0.0, "swing": 0.0,
	}

	if width >= TAU:
		# Base ring: a full circular ledge
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = TOWER_RADIUS + PLATFORM_DEPTH
		cyl.bottom_radius = TOWER_RADIUS + PLATFORM_DEPTH
		cyl.height = 1.2
		cyl.radial_segments = 32
		cyl.material = PLATFORM_MAT
		ring.mesh = cyl
		ring.position.y = -0.6
		pivot.add_child(ring)
		p.half_width = 1000.0
	else:
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, PLATFORM_THICKNESS, PLATFORM_DEPTH)
		box.material = DIRT_MAT if kind == Kind.CRUMBLE else PLATFORM_MAT
		slab.mesh = box
		slab.position = Vector3(0, -PLATFORM_THICKNESS * 0.5, TOWER_RADIUS + PLATFORM_DEPTH * 0.5 - 0.1)
		pivot.add_child(slab)
		if kind == Kind.CRUMBLE:
			var dm := StandardMaterial3D.new()
			dm.albedo_texture = DIRT_MAT.albedo_texture
			dm.albedo_color = Color(0.85, 0.6, 0.45)
			dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			dm.uv1_scale = Vector3(2, 1, 1)
			box.material = dm
		elif kind != Kind.SPRING:
			# Little brick fence along the outer edge
			var fence := Sprite3D.new()
			fence.texture = FENCE_TEX
			fence.pixel_size = width / 64.0
			fence.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			fence.position = Vector3(0, 0.15, TOWER_RADIUS + PLATFORM_DEPTH - 0.12)
			fence.shaded = true
			slab.get_parent().add_child(fence)
		if kind == Kind.MOVING:
			p.speed = randf_range(0.8, 1.5)
			p.phase = randf() * TAU
			p.swing = randf_range(0.5, 0.9)
			var glow := StandardMaterial3D.new()
			glow.albedo_texture = PLATFORM_MAT.albedo_texture
			glow.albedo_color = Color(0.7, 0.55, 1.0)
			glow.emission_enabled = true
			glow.emission = Color(0.35, 0.15, 0.6)
			glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			glow.uv1_triplanar = true
			glow.uv1_scale = Vector3(1, 0.5, 1)
			box.material = glow
		if kind == Kind.SPRING:
			var spring := MeshInstance3D.new()
			spring.name = "Spring"
			var pad := CylinderMesh.new()
			pad.top_radius = 0.45
			pad.bottom_radius = 0.55
			pad.height = 0.35
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.9, 0.2, 0.35)
			sm.emission_enabled = true
			sm.emission = Color(0.9, 0.15, 0.3)
			sm.emission_energy_multiplier = 0.6
			pad.material = sm
			spring.mesh = pad
			spring.position = Vector3(0, 0.12, PLAYER_RADIUS)
			pivot.add_child(spring)
	platforms.append(p)
