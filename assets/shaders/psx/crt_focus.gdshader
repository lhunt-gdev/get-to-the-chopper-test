// The CRT effect, focused like a lens (the decision log's "Less texture flicker": "Cross is the focus
// and would be sharper ... the further back the stronger the effect is"). A quad over the camera's
// whole view, drawn after the solid world and before anything see-through: each pixel as an old TV
// over a composite cable showed it (blended a little with its neighbours across, the colour more than
// the brightness, and faint scanlines), by how far behind the focus it is: none at CROSS's distance
// from the camera and nearer, full from `full` metres behind him (the far walls, the sky).
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform sampler2D depth : hint_depth_texture, filter_nearest;
// CROSS's distance from the camera (m): set each frame by the level.
uniform float focus = 3.0;
// Metres behind the focus where it starts, and where it's full.
uniform float start = 0.5;
uniform float full = 4.0;
// How dark every other line is at full strength (1: no scanlines).
uniform float scanline = 0.92;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
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

void fragment() {
	float d = texture(depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float dist = length(view.xyz / view.w);
	float k = smoothstep(focus + start, focus + full, dist);
	vec3 sharp = texture(screen, SCREEN_UV).rgb;
	vec3 c = mix(sharp, composite(SCREEN_UV, 1.0 / VIEWPORT_SIZE.x), k);
	if (mod(FRAGCOORD.y, 2.0) >= 1.0) {
		c *= mix(1.0, scanline, k);
	}
	ALBEDO = c;
}
