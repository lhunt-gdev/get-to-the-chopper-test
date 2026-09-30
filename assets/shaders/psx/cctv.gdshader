// Security-camera footage over the 3D view: grainy black and white with a slight green tint,
// scanlines, flickering noise, a slightly curved lens, a vignette and the odd glitch line.
// Drawn first in the HUD, so it only affects the game view, not the HUD on top.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
// 0 = off, 1 = full CCTV look.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	// Slightly curved lens.
	vec2 uv = 0.5 + c * (1.0 + 0.12 * dot(c, c));
	// Now and then a horizontal band tears sideways.
	float row = floor(uv.y * 48.0);
	float tear = step(0.985, hash(vec2(row, floor(time * 8.0))));
	uv.x += tear * 0.02;
	vec3 src = texture(screen, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
	float g = dot(src, vec3(0.3, 0.59, 0.11));
	g = g * 1.35 + 0.05;                                  // washed-out, lifted blacks
	g += (hash(FRAGCOORD.xy + floor(time * 24.0) * 17.0) - 0.5) * 0.16;  // grain
	g *= 0.8 + 0.2 * step(0.5, fract(FRAGCOORD.y * 0.5)); // scanlines
	g *= mix(0.45, 1.0, smoothstep(0.75, 0.3, length(c)));  // vignette
	g *= 0.96 + 0.04 * sin(time * 50.0);                  // flicker
	vec3 cctv = vec3(g * 0.82, g, g * 0.84);              // slight green tint
	COLOR = vec4(mix(texture(screen, SCREEN_UV).rgb, cctv, amount), 1.0);
}
