class_name SpeechBubble
extends Node3D
# A speech bubble that lives in the 3D world above an NPC's head: a chunky
# pixel-art balloon (generated to fit the text) with the line written on it.
# It turns to face the camera and pops open / shut.

const TEXEL := 0.05                  # balloon pixel size, to match the low-res scene
const FONT_SIZE := 40
const LABEL_PX := 0.011              # metres per font pixel: letters ~0.45 m tall
const MAX_WIDTH := 460.0             # wrap width, in font pixels (~5 m)
const PAD := 0.28
const TAIL := 6                      # tail height in texels
const PAPER := Color(1.0, 0.97, 0.9, 0.62)   # see-through, so it doesn't block the view
const EDGE := Color(0.15, 0.08, 0.2, 0.8)
const INK := Color(0.15, 0.08, 0.2)

var label: Label3D
var balloon: Sprite3D
var openness := 0.0
var hold := 0.0                      # seconds left on a timed line (say)

# Show `text` for `seconds` (for crows that pipe up now and then)
func say(text: String, seconds := 3.0) -> void:
	setup(text)
	hold = seconds

func setup(text: String) -> void:
	for c in get_children():
		c.queue_free()
	label = Label3D.new()
	label.text = text
	label.font_size = FONT_SIZE
	label.pixel_size = LABEL_PX
	label.modulate = INK
	# A pale outline keeps the text readable on the see-through balloon
	label.outline_size = 8
	label.outline_modulate = Color(1.0, 0.97, 0.9, 0.9)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.no_depth_test = true
	label.render_priority = 21

	# Measure the wrapped text so the balloon fits it
	var font: Font = ThemeDB.fallback_font
	var one_line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	label.width = min(one_line, MAX_WIDTH) + 2.0
	var text_px := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, label.width, FONT_SIZE, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	var box := Vector2(label.width, text_px.y) * LABEL_PX + Vector2(PAD, PAD) * 2.0

	balloon = Sprite3D.new()
	balloon.texture = _balloon_texture(ceili(box.x / TEXEL), ceili(box.y / TEXEL))
	balloon.pixel_size = TEXEL
	balloon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	balloon.shaded = false
	balloon.no_depth_test = true
	balloon.render_priority = 20
	# Tail tip at this node's origin
	balloon.offset = Vector2(0, balloon.texture.get_height() * 0.5)
	add_child(balloon)

	label.position = Vector3(0, (TAIL + box.y / TEXEL * 0.5) * TEXEL, 0.01)
	add_child(label)
	if openness <= 0.0:
		visible = false
		scale = Vector3.ONE * 0.01

func tick(delta: float, want_open: bool) -> void:
	hold = max(hold - delta, 0.0)
	want_open = want_open or hold > 0.0
	openness = move_toward(openness, 1.0 if want_open else 0.0, delta * 6.0)
	visible = openness > 0.01
	if not visible:
		return
	# A little overshoot as it pops open
	var s: float = ease(openness, 0.4) * (1.0 + 0.12 * sin(openness * PI))
	scale = Vector3.ONE * max(s, 0.01)
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_basis = cam.global_basis.scaled(scale)

# Rounded box with a 1-texel outline and a tail pointing down, in pixels
static func _balloon_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h + TAIL, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# Cut the corners for a pixel-rounded look
			var cx := mini(x, w - 1 - x)
			var cy := mini(y, h - 1 - y)
			if cx + cy < 2:
				continue
			var edge := cx == 0 or cy == 0 or cx + cy == 2
			img.set_pixel(x, y, EDGE if edge else PAPER)
	# Tail: a narrowing wedge below the middle
	var mid := w / 2
	for t in TAIL:
		var half := maxi(TAIL / 2 - t, 0)
		for x in range(mid - half - 1, mid + half + 2):
			var edge := x == mid - half - 1 or x == mid + half + 1
			img.set_pixel(x, h + t, EDGE if edge or half == 0 else PAPER)
		img.set_pixel(mid, h - 1, PAPER)
		for x in range(mid - TAIL / 2, mid + TAIL / 2 + 1):
			img.set_pixel(x, h - 1, PAPER)
	return ImageTexture.create_from_image(img)
