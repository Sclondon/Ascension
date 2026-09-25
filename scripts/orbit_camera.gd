class_name OrbitCamera
extends Camera3D
# Orbits the tower to stay behind the bird's angle, looking in at the tower.
# The tower itself never moves, so light and weather stay put in the world.

const DISTANCE := 12.5               # from the bird's radius out to the lens
const HEIGHT := 2.2
const MIN_VIEW_WIDTH := 11.0
const MIN_VIEW_HEIGHT := 18.0         # bigger jumps need a taller view

var player: Player
var cam_theta := 0.0
var cam_y := 0.0
var cam_r := 5.8                     # follows the bird in/out, so turrets frame the same
var orbit_idle := false              # title screen: drift slowly around

func snap() -> void:
	cam_theta = player.theta
	cam_y = player.y + 1.5
	cam_r = max(player.r, 5.0)
	_apply()

func _process(delta: float) -> void:
	if player == null:
		return
	if orbit_idle:
		cam_theta += delta * 0.12
		cam_y = lerp(cam_y, player.y + 3.0, 1.0 - exp(-2.0 * delta))
	else:
		cam_theta += wrapf(player.theta - cam_theta, -PI, PI) * (1.0 - exp(-7.0 * delta))
		# Look further ahead downward during a long fall
		var target := player.y + (1.5 if player.vy > -10.0 else -2.5)
		var rate := 4.0 if target > cam_y else 7.0
		cam_y = lerp(cam_y, target, 1.0 - exp(-rate * delta))
		cam_r = lerp(cam_r, max(player.r, 5.0), 1.0 - exp(-3.0 * delta))
	_apply()

func _apply() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect: float = size.x / max(size.y, 1.0)
	var needed_h: float = max(MIN_VIEW_HEIGHT, MIN_VIEW_WIDTH / aspect)
	fov = clamp(rad_to_deg(2.0 * atan(needed_h * 0.5 / DISTANCE)), 40.0, 100.0)
	var radius := cam_r + DISTANCE
	var dir := Vector3(sin(cam_theta), 0, cos(cam_theta))
	position = dir * radius + Vector3(0, cam_y + HEIGHT, 0)
	look_at(Vector3(0, cam_y + 0.8, 0) + dir * 1.5, Vector3.UP)
