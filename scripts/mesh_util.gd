class_name MeshUtil
# Low-poly, flat-shaded mesh builders and the shared materials.

const BRICK_TEX := preload("res://images/brickwall.png")
const DIRT_TEX := preload("res://images/dirt.png")

static var _materials := {}
static var _textures := {}

# The brick art, recoloured: walls a little desaturated so the band tint shows,
# ledges ("slab") pale so they stand out against the walls
static func _texture(key: String) -> Texture2D:
	if key == "dirt":
		return DIRT_TEX
	if not _textures.has(key):
		var img := BRICK_TEX.get_image()
		img.decompress()
		if key == "slab" or key == "glow":
			img.adjust_bcs(1.6, 1.05, 0.2)
		else:
			img.adjust_bcs(1.25, 1.05, 0.45)
		_textures[key] = ImageTexture.create_from_image(img)
	return _textures[key]

static func stone_material(tint: Color, key := "stone") -> StandardMaterial3D:
	var id := "%s_%s" % [key, tint.to_html()]
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(key)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if key == "glow":
		m.emission_enabled = true
		m.emission = Color(0.35, 0.2, 0.7)
		m.emission_energy_multiplier = 0.8
	_materials[id] = m
	return m

static func flat_material(color: Color) -> StandardMaterial3D:
	var id := "flat_%s" % color.to_html()
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_materials[id] = m
	return m

# Emits a flat-shaded polygon (3 or 4 points, planar). `facing` is roughly the
# direction the visible side should point; the winding is fixed up to match
# (Godot treats clockwise as front-facing).
static func face(st: SurfaceTool, pts: Array, facing: Vector3, color := Color.WHITE, uv_scale := 3.0) -> void:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.dot(facing) < 0.0:
		pts = pts.duplicate()
		pts.reverse()
		n = -n
	var uvs := _uvs(n, pts, uv_scale)
	var order := [0, 2, 1] if pts.size() == 3 else [0, 2, 1, 0, 3, 2]
	st.set_color(color)
	st.set_normal(n)
	for i in order:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

# Box-projected UVs so bricks keep a constant world size
static func _uvs(n: Vector3, pts: Array, s: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var an := n.abs()
	for p: Vector3 in pts:
		if an.y > an.x and an.y > an.z:
			out.append(Vector2(p.x, p.z) / s)
		elif an.x > an.z:
			out.append(Vector2(p.z, -p.y) / s)
		else:
			out.append(Vector2(p.x, -p.y) / s)
	return out

static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

# Extrudes a simple (possibly concave) XZ polygon between y0 and y1
static func extrude(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float, color := Color.WHITE, uv_scale := 3.0) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	var side_c := color.darkened(0.12)
	var bottom_c := color.darkened(0.35)
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		face(st, [Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(c.x, y1, c.y)], Vector3.UP, color, uv_scale)
		face(st, [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y)], Vector3.DOWN, bottom_c, uv_scale)
	var sign := 1.0 if _signed_area(poly) > 0.0 else -1.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var e := q - p
		if e.length_squared() < 0.000001:
			continue
		var out := Vector3(e.y, 0, -e.x) * sign
		face(st, [Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y)], out, side_c, uv_scale)

static func box(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float, color := Color.WHITE) -> void:
	var h := size * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var poly := PackedVector2Array()
	for c in [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]:
		var p := basis * Vector3(c.x, 0, c.y)
		poly.append(Vector2(center.x + p.x, center.z + p.z))
	extrude(st, poly, center.y - h.y, center.y + h.y, color, 1.0)

# A low-poly cone (for hemlock trees)
static func cone(st: SurfaceTool, base: Vector3, radius: float, height: float, sides: int, color: Color) -> void:
	var tip := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(sin(a0), 0, cos(a0)) * radius
		var p1 := base + Vector3(sin(a1), 0, cos(a1)) * radius
		var mid := (p0 + p1) * 0.5 - base
		# A negative height points the cone down (the sides then face down too)
		face(st, [p0, p1, tip], mid + Vector3(0, radius * sign(height), 0), color.lightened(0.1 * (i % 2)), 1.0)
		face(st, [p0, p1, base], Vector3(0, -sign(height), 0), color.darkened(0.4), 1.0)

# A square-section beam between two points
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized() * thickness * 0.5
	var up := side.cross(dir).normalized() * thickness * 0.5
	var offs := [side + up, -side + up, -side - up, side - up]
	for i in 4:
		var o0: Vector3 = offs[i]
		var o1: Vector3 = offs[(i + 1) % 4]
		face(st, [a + o0, b + o0, b + o1, a + o1], o0 + o1, color.lightened(0.06 * (i % 2)), 1.0)
	face(st, [b + offs[0], b + offs[1], b + offs[2], b + offs[3]], dir, color, 1.0)
	face(st, [a + offs[0], a + offs[1], a + offs[2], a + offs[3]], -dir, color, 1.0)

static func commit(st: SurfaceTool, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# Small generated pixel textures (no extra art files needed)
static func pixel_texture(rows: Array, palette: Dictionary) -> ImageTexture:
	var h := rows.size()
	var w: int = rows[0].length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var ch: String = rows[y][x]
			img.set_pixel(x, y, palette.get(ch, Color(0, 0, 0, 0)))
	return ImageTexture.create_from_image(img)

static func blob_texture(size := 16, tint := Color.BLACK) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			# Two hard steps instead of a gradient: reads as pixel art
			var a := 0.9 if d < 0.65 else (0.65 if d < 1.0 else 0.0)
			img.set_pixel(x, y, Color(tint, a))
	return ImageTexture.create_from_image(img)
