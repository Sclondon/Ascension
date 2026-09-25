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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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

# --- look ------------------------------------------------------------------
# Pixel-art controls in the game's colours: a gold-rimmed stone dial with a
# gem for a knob, and a round jump button with a wing on it. Drawn from small
# generated textures scaled up with nearest filtering, like the HUD border.

const PX := 4                        # screen pixels per art pixel
const GOLD := Color(0.95, 0.75, 0.28)
const GOLD_DARK := Color(0.55, 0.35, 0.1)
const INK := Color(0.1, 0.04, 0.14)
const STONE := Color(0.16, 0.08, 0.22, 0.6)
const CREAM := Color(1.0, 0.95, 0.85)

static var _tex := {}

func _draw() -> void:
	if not used:
		return
	var screen := get_viewport_rect().size
	var base_at := stick_origin if stick_index != -1 else Vector2(screen.x * 0.22, screen.y - 150)
	var knob_at := stick_pos if stick_index != -1 else base_at
	var idle := 0.55 if stick_index == -1 else 1.0
	_blit("dial", base_at, idle)
	_blit("gem", knob_at, idle)
	var jump_at := Vector2(screen.x * 0.78, screen.y - 150)
	var pressed := jump_index != -1
	_blit("jump_down" if pressed else "jump", jump_at + (Vector2(0, PX) if pressed else Vector2.ZERO), 1.0 if pressed else 0.8)

func _blit(name: String, centre: Vector2, alpha: float) -> void:
	var tex := _texture(name)
	var s := tex.get_size() * PX
	draw_texture_rect(tex, Rect2(centre - s * 0.5, s), false, Color(1, 1, 1, alpha))

static func _texture(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var img: Image
	match name:
		"dial":
			img = _disc(36, STONE, true)
			# Four gold arrowheads: around the tower and in / out
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				for i in 3:
					for j in range(-i, i + 1):
						var along: Vector2i = d * (14 - 2 - i)
						var across := Vector2i(d.y, d.x) * j
						img.set_pixelv(Vector2i(18, 18) + along + across, GOLD)
		"gem":
			img = _disc(16, GOLD, false)
			for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]:
				img.set_pixelv(p, CREAM)
		"jump", "jump_down":
			img = _disc(34, Color(0.28, 0.12, 0.34, 0.75) if name == "jump" else Color(0.45, 0.2, 0.5, 0.85), true)
			# A wing
			var wing := [
				"......cc....",
				"....cccc....",
				"..ccccccc...",
				".ccccccccc..",
				"cccccccccccc",
				"cc.cc.cc.ccc",
				"c..c..c..c.c",
			]
			for y in wing.size():
				for x in wing[y].length():
					if wing[y][x] == "c":
						img.set_pixel(11 + x, 13 + y, CREAM)
	var tex := ImageTexture.create_from_image(img)
	_tex[name] = tex
	return tex

# A filled disc with a dark outline (and a gold rim when `rim`)
static func _disc(size: int, fill: Color, rim: bool) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var r := size * 0.5
			if d > r:
				continue
			var col := fill
			if d > r - 1.0:
				col = INK
			elif rim and d > r - 3.0:
				col = GOLD if y < c else GOLD_DARK      # lit from above
			elif rim and d > r - 4.0:
				col = INK
			img.set_pixel(x, y, col)
	return img
