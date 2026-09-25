class_name TouchControls
extends Control
# On-screen controls for phones: a floating joystick on the left half
# (x = around the tower, y = in / out) and a jump button on the right half.
# They press the same input actions as the keyboard.

const STICK_RADIUS := 70.0
const DEADZONE := 0.2
const TOP_MARGIN := 110.0            # leave the pause button alone

var stick_index := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var jump_index := -1
var used := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	used = DisplayServer.is_touchscreen_available()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		used = true
		var w := get_viewport_rect().size.x
		if event.pressed:
			if event.position.y < TOP_MARGIN:
				return
			if event.position.x < w * 0.5 and stick_index == -1:
				stick_index = event.index
				stick_origin = event.position
				stick_pos = event.position
			elif event.position.x >= w * 0.5 and jump_index == -1:
				jump_index = event.index
				Input.action_press("jump")
		else:
			if event.index == stick_index:
				stick_index = -1
				_apply_stick(Vector2.ZERO)
			elif event.index == jump_index:
				jump_index = -1
				Input.action_release("jump")
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == stick_index:
		stick_pos = event.position
		var v: Vector2 = (stick_pos - stick_origin) / STICK_RADIUS
		if v.length() > 1.0:
			# Drag the base along so the stick never feels stuck
			stick_origin = stick_pos - v.normalized() * STICK_RADIUS
			v = v.normalized()
		_apply_stick(v)
		queue_redraw()

func release_all() -> void:
	stick_index = -1
	jump_index = -1
	_apply_stick(Vector2.ZERO)
	Input.action_release("jump")
	queue_redraw()

func _apply_stick(v: Vector2) -> void:
	_axis("move_left", "move_right", v.x)
	_axis("move_in", "move_out", v.y)       # up the screen = toward the tower

func _axis(neg: String, pos: String, value: float) -> void:
	var s: float = 0.0 if abs(value) < DEADZONE else (abs(value) - DEADZONE) / (1.0 - DEADZONE)
	if value < 0.0 and s > 0.0:
		Input.action_press(neg, s)
		Input.action_release(pos)
	elif value > 0.0 and s > 0.0:
		Input.action_press(pos, s)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)

func _draw() -> void:
	if not used:
		return
	var size := get_viewport_rect().size
	var ink := Color(1, 1, 1, 0.25)
	var ink_strong := Color(1, 1, 1, 0.5)
	if stick_index != -1:
		draw_circle(stick_origin, STICK_RADIUS, ink, false, 4.0)
		draw_circle(stick_pos, 30.0, ink_strong)
	else:
		var hint := Vector2(size.x * 0.22, size.y - 150)
		draw_circle(hint, STICK_RADIUS, ink, false, 4.0)
		draw_circle(hint, 30.0, ink)
	var jump_at := Vector2(size.x * 0.78, size.y - 150)
	draw_circle(jump_at, 64.0, ink_strong if jump_index != -1 else ink)
	var font := get_theme_default_font()
	draw_string(font, jump_at + Vector2(-40, 10), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, 80, 26, Color(1, 1, 1, 0.8))
