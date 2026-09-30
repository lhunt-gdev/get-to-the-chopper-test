// PS1-style surface: vertex snapping ("wobble") and affine texture warping.
// Low internal resolution comes from project.godot (270x480 viewport stretch).
shader_type spatial;
render_mode specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
// Grid that vertices snap to in screen space. Lower = more wobble.
uniform float snap_resolution = 90.0;
// PS1 had no perspective-correct texturing.
uniform bool affine_mapping = true;
varying vec3 affine_uv_w;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = round(ndc.xy * snap_resolution) / snap_resolution;
	POSITION = vec4(ndc * clip.w, clip.w);
	affine_uv_w = vec3(UV * uv_scale * clip.w, clip.w);
}

void fragment() {
	vec2 uv = affine_mapping ? affine_uv_w.xy / affine_uv_w.z : UV * uv_scale;
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = albedo.rgb * tex.rgb;
}
