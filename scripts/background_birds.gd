class_name BackgroundBirds
extends Node3D
# Flocks of black silhouettes crossing the far sky. In thunderstorms they're
# also spawned with lightning strikes, so the flash reveals them.

const FLAP_FRAMES := preload("res://animations/player_jump_SF.tres")
const LIFE := 9.0

var flocks: Array[Dictionary] = []
var silhouette: SpriteFrames
var idle_timer := 6.0

func _ready() -> void:
	silhouette = Player._derive(FLAP_FRAMES, Color(0.03, 0.02, 0.05), 0)

# `cam` looks at the tower; the flock goes behind it, far away
func spawn(cam: Camera3D, focus_y: float) -> void:
	var back := -cam.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var across := back.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	var dist := randf_range(34.0, 55.0)
	var start := Vector3(0, focus_y + randf_range(6.0, 22.0), 0) + back * dist - across * randf_range(28.0, 40.0)
	var flock := {"node": Node3D.new(), "vel": across * randf_range(9.0, 14.0) + Vector3(0, randf_range(-0.5, 1.0), 0), "age": 0.0}
	add_child(flock.node)
	flock.node.position = start
	var count := randi_range(3, 8)
	for i in count:
		var b := AnimatedSprite3D.new()
		b.sprite_frames = silhouette
		b.pixel_size = 0.12
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		b.shaded = false
		b.flip_h = across.dot(cam.global_transform.basis.x) > 0.0
		# A loose V
		var row := (i + 1) / 2
		var side := 1.0 if i % 2 == 0 else -1.0
		b.position = -across * row * 2.2 + Vector3(0, row * 0.9 * side * 0.6, row * side * 1.5) + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0)
		b.play("default")
		b.frame = randi_range(0, 3)
		b.speed_scale = randf_range(1.4, 2.2)
		flock.node.add_child(b)
	flocks.append(flock)

# Called every frame; `stormy` is whether this band has lightning
func update(delta: float, cam: Camera3D, focus_y: float, stormy: bool) -> void:
	idle_timer -= delta
	if idle_timer <= 0.0:
		idle_timer = randf_range(8.0, 16.0) if stormy else randf_range(14.0, 30.0)
		spawn(cam, focus_y)
	for i in range(flocks.size() - 1, -1, -1):
		var f: Dictionary = flocks[i]
		f.age += delta
		f.node.position += f.vel * delta
		if f.age > LIFE:
			f.node.queue_free()
			flocks.remove_at(i)
