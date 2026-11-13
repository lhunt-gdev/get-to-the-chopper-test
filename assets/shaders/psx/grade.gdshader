// The whole game view, MGS1-style: cold teal shadows, a little less colour, a soft vignette,
// and PS1 15-bit colour with an ordered dither. At CAUTION / ALERT the screen edges throb
// amber / red. Sits under the HUD (see hud.gd set_grade).
// And the CRT effect (SETTINGS' RETRO FILTER row: ON or CRT): the view as an old TV over a composite cable showed it (each pixel a
// little blended with its neighbours across, the colour more than the brightness, and faint
// scanlines), which also calms the textures' crawl. Under the HUD and the menus, so their text
// stays sharp. The two are separate settings: either on without the other.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec3 shadow_tint = vec3(0.015, 0.045, 0.065);
uniform float saturation = 0.82;
uniform float contrast = 0.15;
uniform float vignette = 0.38;
// 0..1 (already pulsing): how red / amber the screen edges are.
uniform float alert = 0.0;
uniform float caution = 0.0;
// The grade and dither (RETRO FILTER: ON or COLOUR) and the CRT effect (ON or CRT).
uniform bool grade_on = true;
uniform bool crt = true;
// How dark every other line is (1: no scanlines).
uniform float scanline = 0.92;

float bayer4(vec2 frag) {
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

vec3 px(vec2 uv, float dx, float w) {
	return texture(screen, uv + vec2(dx * w, 0.0)).rgb;
}

// The composite picture: the brightness over 3 pixels across, the colour over 5.
vec3 composite(vec2 uv, float w) {
	vec3 l2 = px(uv, -2.0, w), l1 = px(uv, -1.0, w), m = px(uv, 0.0, w), r1 = px(uv, 1.0, w), r2 = px(uv, 2.0, w);
	const vec3 Y = vec3(0.299, 0.587, 0.114);
	float y = dot(l1, Y) * 0.25 + dot(m, Y) * 0.5 + dot(r1, Y) * 0.25;
	vec3 col = l2 * 0.1 + l1 * 0.2 + m * 0.4 + r1 * 0.2 + r2 * 0.1;
	return col - vec3(dot(col, Y)) + vec3(y);
}

// The MGS grade: cold shadows, less colour, more contrast, the vignette and the alert's edges.
vec3 graded(vec3 c, vec2 uv) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c += shadow_tint * (1.0 - smoothstep(0.0, 0.45, l));
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
	vec2 d = uv - 0.5;
	d.x *= 0.75;
	float r = length(d);
	c *= mix(1.0, smoothstep(0.78, 0.2, r), vignette);
	float edge = smoothstep(0.28, 0.7, r);
	c = mix(c, vec3(0.85, 0.04, 0.02), edge * alert * 0.6);
	c = mix(c, vec3(0.9, 0.55, 0.1), edge * caution * 0.2);
	return c;
}

void fragment() {
	vec3 c = crt ? composite(SCREEN_UV, SCREEN_PIXEL_SIZE.x) : texture(screen, SCREEN_UV).rgb;
	if (grade_on) {
		c = graded(c, SCREEN_UV);
	}
	if (crt && mod(FRAGCOORD.y, 2.0) >= 1.0) {
		c *= scanline;
	}
	if (grade_on) {
		c = floor(c * 31.0 + bayer4(FRAGCOORD.xy)) / 31.0;  // PS1 15-bit colour, dithered
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
