// A spent casing flying out from behind the FIRE trigger (Casings, game/rendering/casings.gd), drawn
// over the game: PS1-style like psx_lit (vertices snapped to the screen's pixels, so it wobbles, and
// the light in dithered steps), but lit by a light of its own, fixed over the screen's top left, not
// the area's (it's on the HUD: it reads the same in any light), with a hard glint on the brass.
shader_type spatial;
render_mode specular_disabled, cull_back, unshaded, fog_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
// The light, in view space (towards it), and how much of it is always there.
uniform vec3 light_dir = vec3(-0.45, 0.75, 0.5);
uniform float ambient = 0.45;
// Pixels the vertices snap to (1: the screen's own).
uniform float snap_px = 1.0;
varying vec3 view_normal;

#include "res://assets/shaders/psx/psx_cutout.gdshaderinc"

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 grid = VIEWPORT_SIZE * 0.5 / snap_px;
	clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	POSITION = clip;
	view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	vec3 n = normalize(view_normal);
	vec3 l = normalize(light_dir);
	float light = ambient + (1.0 - ambient) * clamp(dot(n, l) * 0.8 + 0.2, 0.0, 1.0);
	// The glint: where the light bounces straight at the eye.
	float glint = pow(clamp(dot(reflect(-l, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 6.0);
	float steps = 6.0;
	light = floor(light * steps + bayer4(FRAGCOORD.xy)) / steps;
	glint = floor(glint * 3.0 + bayer4(FRAGCOORD.xy)) / 3.0;
	ALBEDO = base * light + vec3(1.0, 0.92, 0.7) * glint * 0.5;
}
