// A muzzle flash, PS1 style: hard bands of white-hot, yellow and orange flame added onto what's
// behind it (it gives off light), no fog. kind 0: a star of flame always facing the camera.
// kind 1: a tongue of flame shooting out ahead along the barrel (its quad runs from the muzzle,
// UV.y = 0, to the tip, UV.y = 1). heat fades it (1 just fired .. 0 gone) by shrinking it into its
// white-hot core; seed makes each shot's flash a different shape.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform int kind = 0;
uniform float heat = 1.0;
uniform float seed = 0.0;
uniform vec3 hot : source_color = vec3(1.0, 0.97, 0.82);
uniform vec3 mid : source_color = vec3(1.0, 0.74, 0.2);
uniform vec3 edge : source_color = vec3(0.9, 0.32, 0.05);

void vertex() {
	if (kind == 0) {
		// Facing the camera, at the node's scale (a billboard).
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float v;
	if (kind == 0) {
		// Five long spikes with five short ones between, their tips ragged, turned by the seed.
		float r = length(p);
		float a = atan(p.y, p.x) + seed * 6.2832;
		float big = pow(abs(cos(a * 2.5)), 8.0);
		float small = 0.5 * pow(abs(sin(a * 2.5)), 12.0);
		float ragged = 0.82 + 0.18 * sin(a * 9.0 + seed * 50.0);
		v = 1.0 - r / ((0.3 + 0.7 * max(big, small)) * ragged);
	} else {
		// Widest at the muzzle, narrowing to a ragged point, dimmer toward the tip.
		float along = UV.y;
		float width = (1.0 - along) * (0.7 + 0.3 * sin(along * 14.0 + seed * 30.0));
		v = (1.0 - abs(p.x) / max(width, 0.001)) * (1.0 - 0.5 * along);
	}
	v -= (1.0 - heat) * 0.45;
	if (v <= 0.0) {
		discard;
	}
	ALBEDO = (v > 0.55 ? hot : (v > 0.25 ? mid : edge)) * (0.6 + 0.4 * heat);
	ALPHA = 1.0;
}
