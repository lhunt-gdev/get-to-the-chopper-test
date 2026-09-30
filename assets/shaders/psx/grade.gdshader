// The whole game view, MGS1-style: cold teal shadows, a little less colour, a soft vignette,
// and PS1 15-bit colour with an ordered dither. At CAUTION / ALERT the screen edges throb
// amber / red. Sits under the HUD (see hud.gd set_grade).
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec3 shadow_tint = vec3(0.015, 0.045, 0.065);
uniform float saturation = 0.82;
uniform float contrast = 0.3;
uniform float vignette = 0.5;
// 0..1 (already pulsing): how red / amber the screen edges are.
uniform float alert = 0.0;
uniform float caution = 0.0;

float bayer4(vec2 frag) {
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c += shadow_tint * (1.0 - smoothstep(0.0, 0.45, l));
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
	vec2 d = SCREEN_UV - 0.5;
	d.x *= 0.75;
	float r = length(d);
	c *= mix(1.0, smoothstep(0.78, 0.2, r), vignette);
	float edge = smoothstep(0.28, 0.7, r);
	c = mix(c, vec3(0.85, 0.04, 0.02), edge * alert * 0.6);
	c = mix(c, vec3(0.9, 0.55, 0.1), edge * caution * 0.2);
	c = floor(c * 31.0 + bayer4(FRAGCOORD.xy)) / 31.0;
	COLOR = vec4(c, 1.0);
}
