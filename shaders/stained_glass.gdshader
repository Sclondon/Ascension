shader_type spatial;
render_mode cull_back, specular_disabled;

// Procedural stained glass on a quad: leaded Voronoi panes inside a stone
// frame. style 0 = pointed lancet window, 1 = rose window, 2 = wooden door.

uniform int style = 0;
uniform vec2 size = vec2(1.0, 2.2);      // quad size in metres
uniform float seed = 0.0;
uniform float hue = 0.0;
uniform float glow = 1.0;                // driven by the weather (night = brighter)
uniform float pixels_per_metre = 11.0;   // snap to a pixel grid

const float FRAME = 0.1;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}

vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}

// Returns (distance to lead line, cell id hash)
vec2 voronoi(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(cell + g) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = cell + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d2 - d1, fract(sin(dot(id, vec2(12.9898, 78.233)) + seed) * 43758.5453));
}

// Pointed (equilateral) arch of half-width hw, springing at height hs
bool in_arch(vec2 p, float hw, float hs, float bottom) {
	if (p.y < bottom || abs(p.x) > hw) return false;
	if (p.y < hs) return true;
	return length(p - vec2(-hw, hs)) < 2.0 * hw && length(p - vec2(hw, hs)) < 2.0 * hw;
}

bool in_round_arch(vec2 p, float hw, float hs, float bottom) {
	if (p.y < bottom || abs(p.x) > hw) return false;
	return p.y < hs || length(p - vec2(0.0, hs)) < hw;
}

vec3 glass_color(float id) {
	float pick = floor(id * 4.0);
	float h = hue + pick * 0.27 + (id > 0.93 ? 0.5 : 0.0);
	return hsv(h, 0.62, 0.9 - 0.2 * fract(id * 7.0));
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, (1.0 - UV.y) * size.y);
	p = (floor(p * pixels_per_metre) + 0.5) / pixels_per_metre;
	float hw = size.x * 0.5;
	vec3 stone = vec3(0.32, 0.3, 0.34);
	vec3 lead = vec3(0.05, 0.04, 0.07);
	vec3 col;
	float emit = 0.0;

	if (style == 1) {
		vec2 c = vec2(0.0, size.y * 0.5);
		vec2 q = p - c;
		float r = length(q);
		float R = hw;
		if (r > R) discard;
		if (r > R - FRAME) {
			col = stone;
		} else {
			float petals = 12.0;
			float a = atan(q.y, q.x);
			float sector = TAU / petals;
			float fa = abs(mod(a, sector) - sector * 0.5);
			vec2 m = vec2(cos(fa), sin(fa)) * r;
			vec2 v = voronoi(m * 2.2);
			bool ring = abs(r - R * 0.38) < 0.03 || abs(r - R * 0.7) < 0.03;
			bool spoke = fa < 0.03 / max(r, 0.05) && r > R * 0.38;
			if (v.x < 0.09 || ring || spoke) {
				col = lead;
			} else {
				col = r < R * 0.38 ? hsv(hue + 0.12, 0.8, 1.0) : glass_color(v.y);
				emit = 1.0;
			}
		}
	} else if (style == 2) {
		float hs = size.y - hw;
		if (!in_round_arch(p, hw, hs, 0.0)) discard;
		if (!in_round_arch(p, hw - FRAME, hs, 0.0)) {
			col = stone;
		} else {
			float plank = fract(p.x / 0.28 + 0.5);
			col = vec3(0.36, 0.2, 0.12) * (0.85 + 0.15 * fract(sin(floor(p.x / 0.28) * 91.7) * 43.7));
			if (plank < 0.08) col = vec3(0.15, 0.08, 0.05);
			if (abs(p.y - 0.7) < 0.06 || abs(p.y - size.y * 0.62) < 0.06) col = vec3(0.12, 0.12, 0.14);
			if (length(p - vec2(hw * 0.45, 1.1)) < 0.07) col = vec3(0.8, 0.65, 0.3);
		}
	} else {
		float hs = size.y - hw * 1.732;
		if (!in_arch(p, hw, hs, 0.0)) discard;
		if (!in_arch(p, hw - FRAME, hs, FRAME)) {
			col = stone;
		} else {
			vec2 v = voronoi(p * vec2(2.4, 1.9));
			bool mullion = abs(p.x) < 0.035 && p.y < hs;
			bool transom = abs(p.y - hs) < 0.035;
			if (v.x < 0.14 || mullion || transom) {
				col = lead;
			} else {
				col = glass_color(v.y);
				emit = 1.0;
			}
		}
	}

	ALBEDO = col * (emit > 0.5 ? 0.45 : 1.0);
	EMISSION = col * emit * glow;
	ROUGHNESS = 1.0;
}
