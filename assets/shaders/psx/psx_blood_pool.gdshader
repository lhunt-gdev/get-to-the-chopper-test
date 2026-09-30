// PS1-style pool of blood: deep red, as bright as the area's light allows (so it reads as blood in
// the dark, not as a shadow), with a ragged edge that's dithered in screen pixels. `spread` grows
// it from nothing (0) to its full size (1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float spread : hint_range(0.0, 1.0) = 1.0;
// Varies the ragged outline from pool to pool.
uniform float seed = 0.0;
uniform vec3 tint : source_color = vec3(0.42, 0.03, 0.025);
global uniform vec4 amb_color;
// Same grid as psx_lit, so the pool wobbles with the ground.
uniform float snap_resolution = 90.0;

const float BAYER[16] = float[](
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = round(ndc.xy * snap_resolution) / snap_resolution;
	POSITION = vec4(ndc * clip.w, clip.w);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;  // -1..1 across the quad
	float a = atan(p.y, p.x);
	// A lumpy outline, so it reads as spilt liquid, not a disc.
	float edge = 0.78 + 0.12 * sin(a * 3.0 + seed) + 0.07 * sin(a * 5.0 + seed * 2.3) + 0.04 * sin(a * 9.0 + seed * 0.7);
	float d = length(p) / max(edge * spread, 0.001);
	float coverage = clamp((1.0 - d) / 0.25, 0.0, 1.0);
	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	if (coverage <= BAYER[cell.y * 4 + cell.x]) {
		discard;
	}
	// Lit like the floor around it (roughly): brighter in lit areas, never black. Darker and deeper
	// in the middle, with a wet glint here and there.
	float light = clamp(dot(amb_color.rgb, vec3(0.33)) * 2.4, 0.45, 1.3);
	vec3 c = mix(tint, tint * 0.6, clamp(1.0 - d, 0.0, 1.0));
	if (cell.x == 1 && cell.y == 2 && d < 0.6 && fract(sin(dot(floor(FRAGCOORD.xy / 4.0), vec2(12.9, 78.2))) * 43758.5) > 0.8) {
		c = vec3(0.75, 0.12, 0.1);
	}
	ALBEDO = c * light;
}
