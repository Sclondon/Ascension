class_name TowerShape
# Pure geometry for the tower: which n-gon lives at which height, and helpers
# for building footprints that hug its flat faces. No nodes, so the headless
# reachability test can use it too.
#
# Angle convention: a point at angle theta and radius r sits at
# (sin(theta) * r, y, cos(theta) * r). Theta grows to the camera's right.

const CHUNK_H := 12.0
const CHUNKS_PER_BAND := 10          # 120 m per band
const BAND_H := CHUNK_H * CHUNKS_PER_BAND

# Each band picks its side count / size from these (cycled)
const BAND_SIDES := [8, 7, 6, 8, 5, 9, 6, 10]
const BAND_APOTHEM := [4.0, 3.8, 3.6, 4.2, 3.5, 4.3, 3.7, 4.4]
const BAND_TINT := [
	Color(0.95, 0.9, 0.85), Color(0.8, 0.85, 0.95), Color(0.75, 0.8, 0.9),
	Color(0.7, 0.72, 0.85), Color(0.9, 0.95, 1.0), Color(1.0, 0.95, 0.85),
	Color(0.85, 0.75, 0.95), Color(0.95, 0.85, 0.8),
]

static func chunk_at(y: float) -> int:
	return floori(max(y, 0.0) / CHUNK_H)

static func band_of_chunk(k: int) -> int:
	return floori(float(max(k, 0)) / CHUNKS_PER_BAND)

static func band_at(y: float) -> int:
	return band_of_chunk(chunk_at(y))

static func sides(band: int) -> int:
	return BAND_SIDES[band % BAND_SIDES.size()]

static func apothem(band: int) -> float:
	return BAND_APOTHEM[band % BAND_APOTHEM.size()]

static func tint(band: int) -> Color:
	return BAND_TINT[band % BAND_TINT.size()]

static func face_offset(band: int) -> float:
	# Band 0 has a face centred on theta = 0, where the climb starts
	return band * 0.37

static func difficulty(band: int) -> float:
	return clamp(band / 6.0, 0.0, 1.0)

static func face_step(band: int) -> float:
	return TAU / sides(band)

static func face_center(band: int, i: int) -> float:
	return face_offset(band) + i * face_step(band)

static func face_width(band: int) -> float:
	return 2.0 * apothem(band) * tan(PI / sides(band))

# Angle relative to the centre of the nearest face, in [-step/2, step/2)
static func rel_angle(band: int, theta: float) -> float:
	var step := face_step(band)
	return fposmod(theta - face_offset(band) + step * 0.5, step) - step * 0.5

static func nearest_face(band: int, theta: float) -> int:
	var step := face_step(band)
	return posmod(roundi((theta - face_offset(band)) / step), sides(band))

# Radius of the n-gon (offset outward by d) along the ray at theta
static func wall_r(band: int, theta: float, d := 0.0) -> float:
	return (apothem(band) + d) / cos(rel_angle(band, theta))

static func ring_point(band: int, theta: float, d: float) -> Vector2:
	var r := wall_r(band, theta, d)
	return Vector2(sin(theta) * r, cos(theta) * r)

static func polar_point(theta: float, r: float) -> Vector2:
	return Vector2(sin(theta) * r, cos(theta) * r)

# Corner angles strictly between a0 and a1 (a0 < a1)
static func corners_between(band: int, a0: float, a1: float) -> Array[float]:
	var step := face_step(band)
	var first := face_offset(band) + step * 0.5
	var out: Array[float] = []
	var j := ceili((a0 - first) / step)
	var c := first + j * step
	while c < a1:
		if c > a0 + 0.0001:
			out.append(c)
		c += step
	return out

# A simple polygon (XZ plane) covering angles a0..a1 between offsets d0 and d1
# from the wall, following the n-gon's flat faces and corners.
static func strip_polygon(band: int, a0: float, a1: float, d0: float, d1: float) -> PackedVector2Array:
	var angles: Array[float] = [a0]
	angles.append_array(corners_between(band, a0, a1))
	angles.append(a1)
	var pts := PackedVector2Array()
	for a in angles:
		pts.append(ring_point(band, a, d0))
	for i in range(angles.size() - 1, -1, -1):
		pts.append(ring_point(band, angles[i], d1))
	return pts

# An arc-shaped polygon on true circles (used for things that move around the tower)
static func arc_polygon(a0: float, a1: float, r0: float, r1: float, segments := 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		pts.append(polar_point(lerp(a0, a1, float(i) / segments), r0))
	for i in range(segments, -1, -1):
		pts.append(polar_point(lerp(a0, a1, float(i) / segments), r1))
	return pts

# Walking distance along the wall (at offset d) from a0 to a1 (a0 <= a1)
static func perimeter_len(band: int, a0: float, a1: float, d := 0.5) -> float:
	if a1 <= a0:
		return 0.0
	var prev := ring_point(band, a0, d)
	var total := 0.0
	for c in corners_between(band, a0, a1):
		var p := ring_point(band, c, d)
		total += prev.distance_to(p)
		prev = p
	return total + prev.distance_to(ring_point(band, a1, d))

# Rough metres -> radians along the wall, good enough for placing things
static func angle_for_len(band: int, length: float, d := 0.5) -> float:
	return length / (apothem(band) * 1.04 + d)
