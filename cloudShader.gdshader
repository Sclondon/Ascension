shader_type spatial;
//render_mode unshaded; // optional

// Noise texture
uniform sampler2D noise_texture: repeat_enable, filter_nearest;
// Fog density
uniform float density: hint_range(0.0, 10.0) = 0.25;
// Fog speed
uniform vec2 speed = vec2(0.02, 0.01);

// Alpha threshold for culling
uniform float alpha_threshold: hint_range(0.0, 1.0) = 0.1;

void fragment() {
    // Make the fog slowly move using UV coordinates and time
    vec2 uv = UV + speed * TIME;

    // Sample the noise texture to get the noise value
    float noise = texture(noise_texture, uv).r;

    // Convert noise value from (0.0, 1.0) to (-1.0, 1.0) and clamp between (0.0, 1.0)
    float fog = clamp(noise * 2.0 - 1.0, 0.0, 1.0);

    // Apply the fog density
    ALBEDO *= fog * density;

    // Apply alpha based on the fog value (or another method if desired)
    float alpha_value = fog * density;

    // Cull pixels where the alpha value is below the threshold
    if (alpha_value < alpha_threshold) {
        discard;  // Skip rendering this pixel
    }

    // Set the fragment alpha value
    ALPHA = alpha_value;
}