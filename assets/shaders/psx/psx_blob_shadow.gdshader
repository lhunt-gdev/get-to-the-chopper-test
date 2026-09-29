// PS1-style blob shadow: darkens whatever is under it, and fades out at the edges with a
// 4x4 ordered dither in screen pixels (the 270x480 internal resolution makes it chunky).
shader_type spatial;
render_mode blend_mul, unshaded, fog_disabled, cull_disabled, depth_draw_never, shadows_disabled;

// How much the centre darkens the ground (0 = no shadow, 1 = black).
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
// Fraction of the blob, from the edge inward, that is dithered.
uniform float softness : hint_range(0.01, 1.0) = 0.5;
// false = ellipse (player), true = rounded rectangle (obstacles).
uniform bool rectangle = false;
// Same grid as psx_lit, so the shadow wobbles with the ground.
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
	vec2 p = abs(UV * 2.0 - 1.0);  // 0 at the centre, 1 at the edge
	float d = rectangle ? max(p.x, p.y) : length(p);
	float coverage = clamp((1.0 - d) / softness, 0.0, 1.0);
	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	if (coverage <= BAYER[cell.y * 4 + cell.x]) {
		discard;
	}
	ALBEDO = vec3(1.0 - opacity);
}
