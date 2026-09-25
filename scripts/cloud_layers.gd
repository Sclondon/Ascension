class_name CloudLayers
extends Node3D
# A deck of stepped-alpha clouds just under each band's ring, so every new
# band starts by bursting up through the clouds. Decks near the focus exist;
# the rest are freed.

const CLOUD_SHADER := preload("res://shaders/clouds.gdshader")
const DECK_SIZE := 1400.0           # follows the camera; the shader fades it out
const KEEP_BANDS := 2

var noise_tex: NoiseTexture2D
var decks := {}                      # band index -> Node3D

static func deck_height(b: int) -> float:
	return b * TowerShape.BAND_H - 5.0

func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise

func update(focus_y: float, tint: Color, cam_pos: Vector3) -> void:
	var c := roundi(focus_y / TowerShape.BAND_H)
	for b in range(max(1, c - KEEP_BANDS), c + KEEP_BANDS + 1):
		if not decks.has(b):
			decks[b] = _make_deck(b)
	for b in decks.keys():
		# Noise is sampled in world space, so sliding the plane along is invisible
		decks[b].position.x = cam_pos.x
		decks[b].position.z = cam_pos.z
		for mi in decks[b].get_children():
			mi.mesh.material.set_shader_parameter("tint", tint)
		if abs(b - c) > KEEP_BANDS + 1:
			decks[b].queue_free()
			decks.erase(b)

func clear() -> void:
	for d in decks.values():
		d.queue_free()
	decks.clear()

func _make_deck(b: int) -> Node3D:
	var below := Weather.weather_of(b - 1)
	var deck := Node3D.new()
	deck.position.y = deck_height(b)
	add_child(deck)
	# Three thin layers give the deck some thickness to fly through
	for i in 3:
		var m := ShaderMaterial.new()
		m.shader = CLOUD_SHADER
		m.set_shader_parameter("noise_tex", noise_tex)
		m.set_shader_parameter("color", below.cloud)
		m.set_shader_parameter("shade", (below.cloud as Color).darkened(0.25))
		m.set_shader_parameter("coverage", below.cover - i * 0.08)
		m.set_shader_parameter("offset", b * 0.37 + i * 0.21)
		m.set_shader_parameter("wind", Vector2(0.006, 0.002) * (1.0 + i * 0.4))
		m.render_priority = i
		var plane := PlaneMesh.new()
		plane.size = Vector2(DECK_SIZE, DECK_SIZE)
		plane.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = (i - 1) * 1.6
		deck.add_child(mi)
	return deck
