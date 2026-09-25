class_name WingTrails
extends MeshInstance3D
# Two thin ribbon trails streaming from the wing tips. Points are recorded
# while `active`; each ribbon tapers and fades out over LIFE seconds, so the
# trails trail off smoothly when you stop gliding.

const LIFE := 0.45
const WIDTH := 0.07
const MIN_STEP := 0.08               # metres between recorded points

var active := false
var _trails: Array = [[], []]        # per wing: [{pos, t}]
var _time := 0.0
var _mesh := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m

# `tips` are the two wing tip positions this frame
func update(delta: float, tips: Array[Vector3]) -> void:
	_time += delta
	for i in 2:
		var pts: Array = _trails[i]
		if active and (pts.is_empty() or pts[-1].pos.distance_to(tips[i]) > MIN_STEP):
			pts.append({"pos": tips[i], "t": _time})
		while not pts.is_empty() and _time - pts[0].t > LIFE:
			pts.pop_front()
	_rebuild()

func _rebuild() -> void:
	if _trails[0].is_empty() and _trails[1].is_empty() and _mesh.get_surface_count() == 0:
		return   # nothing to draw, and nothing drawn
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for pts: Array in _trails:
		if pts.size() < 2:
			continue
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in pts.size():
			var p: Vector3 = pts[i].pos
			var along: Vector3 = (pts[min(i + 1, pts.size() - 1)].pos - pts[max(i - 1, 0)].pos).normalized()
			# Ribbon faces the camera
			var side := along.cross(cam.global_position - p).normalized()
			var life: float = 1.0 - (_time - pts[i].t) / LIFE
			var w := WIDTH * life
			_mesh.surface_set_color(Color(1, 1, 1, 0.55 * life))
			_mesh.surface_add_vertex(p + side * w)
			_mesh.surface_set_color(Color(1, 1, 1, 0.55 * life))
			_mesh.surface_add_vertex(p - side * w)
		_mesh.surface_end()
