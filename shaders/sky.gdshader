shader_type sky;

// Banded gradient sky with pixel stars, an aurora curtain, a hard-edged sun
// and a lightning flash. Colours are posterized to suit the low-res render.

uniform vec3 top_color : source_color = vec3(0.14, 0.17, 0.45);
uniform vec3 horizon_color : source_color = vec3(0.76, 0.33, 0.24);
uniform vec3 bottom_color : source_color = vec3(0.1, 0.12, 0.2);
uniform vec3 sun_color : source_color = vec3(1.0, 0.8, 0.5);
uniform float sun_amount = 1.0;
uniform float stars = 0.0;
uniform float aurora = 0.0;
uniform float flash = 0.0;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = h > 0.0
		? mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55))
		: mix(horizon_color, bottom_color, pow(clamp(-h, 0.0, 1.0), 0.45));

	// Stars on a coarse direction grid so they're single pixels
	vec3 q = floor(d * 150.0);
	float n = hash(q);
	float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + n * 40.0);
	col += vec3(step(0.9972, n) * stars * twinkle * smoothstep(0.02, 0.25, h));

	// Aurora: a wavy curtain above the horizon
	float az = atan(d.x, d.z);
	float wave = sin(az * 3.0 + TIME * 0.15 + sin(az * 7.0 + TIME * 0.3) * 0.6);
	float curtain = smoothstep(0.12, 0.0, abs(h - 0.32 - 0.07 * wave)) * smoothstep(0.0, 0.1, h);
	vec3 aur = mix(vec3(0.15, 0.95, 0.55), vec3(0.65, 0.25, 0.95), 0.5 + 0.5 * sin(az * 2.0 + TIME * 0.1));
	col += aurora * curtain * aur;

	if (LIGHT0_ENABLED) {
		float s = dot(d, LIGHT0_DIRECTION);
		col = mix(col, sun_color, step(0.9975, s) * sun_amount);
		col += sun_color * smoothstep(0.96, 1.0, s) * 0.25 * sun_amount;
	}

	col += vec3(flash);
	COLOR = floor(col * 24.0 + 0.5) / 24.0;
}
