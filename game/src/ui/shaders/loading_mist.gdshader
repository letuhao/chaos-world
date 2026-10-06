shader_type canvas_item;

// Drifting mountain mist, vignette, and rising qi motes for the loading
// screen. Everything is procedural in UV + TIME: no textures, so the effect
// is resolution-free and costs no art dependency. The wallpaper carries the
// painting; this carries the weather.
uniform vec4 mist_color : source_color = vec4(0.62, 0.74, 0.70, 1.0);
uniform vec4 mote_color : source_color = vec4(0.95, 0.83, 0.55, 1.0);
uniform float mist_amount : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float mote_density : hint_range(0.0, 1.0) = 0.5;

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float t = TIME;
	// Two slow sine bands sliding against each other read as fog layers
	// rather than one scrolling sheet.
	float band_a = sin(UV.y * 9.0 + t * 0.12 + sin(UV.x * 5.0 + t * 0.07));
	float band_b = sin((UV.y + UV.x * 0.6) * 14.0 - t * 0.09);
	float mist = (band_a * 0.5 + 0.5) * (band_b * 0.5 + 0.5);
	mist *= mist_amount * smoothstep(0.0, 0.35, UV.y);
	// Qi motes rise: a hashed grid drifting upward, twinkling, sparse.
	vec2 grid_uv = vec2(UV.x * 48.0, UV.y * 27.0 + t * 0.35);
	vec2 cell = floor(grid_uv);
	vec2 pos = fract(grid_uv) - 0.5;
	float sparkle = 0.5 + 0.5 * sin(t * 2.0 + hash(cell) * 40.0);
	float mote = smoothstep(0.10, 0.0, length(pos)) * step(1.0 - mote_density * 0.12, hash(cell + 7.3)) * sparkle;
	// Vignette closes the corners so the menu column reads against darkness.
	float edge = distance(UV, vec2(0.5, 0.52));
	float dark = smoothstep(0.35, 0.85, edge) * vignette_strength;
	vec3 col = mist_color.rgb * mist + mote_color.rgb * mote * 0.8;
	float alpha = clamp(mist * 0.6 + mote * 0.85 + dark, 0.0, 1.0);
	COLOR = vec4(mix(col, vec3(0.03, 0.05, 0.05), dark), alpha);
}
