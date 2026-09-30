// PS1-style surface: vertex snapping ("wobble") and affine texture warping.
// Low internal resolution comes from project.godot (270x480 viewport stretch).
// Lighting is our own (MGS-style: dark, lit by the lamps you can see), not Godot's: an area
// ambient, a moonlight direction, and the nearest lamps, set each frame by Ambience
// (game/rendering/ambience.gd). It's stepped and dithered, so it stays pixel-crisp.
shader_type spatial;
render_mode specular_disabled, cull_back, unshaded;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform vec2 uv_offset = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);
// Grid that vertices snap to in screen space. Lower = more wobble.
uniform float snap_resolution = 90.0;
// PS1 had no perspective-correct texturing.
uniform bool affine_mapping = true;
// Gives off its own light (lit windows, the skyline): ignores the lighting.
uniform bool unlit = false;
varying vec3 affine_uv_w;
varying vec3 world_pos;
varying vec3 world_normal;

global uniform vec4 amb_color;
global uniform vec4 moon_color;
global uniform vec4 moon_dir;
global uniform vec4 lamp_pos_0; global uniform vec4 lamp_col_0;
global uniform vec4 lamp_pos_1; global uniform vec4 lamp_col_1;
global uniform vec4 lamp_pos_2; global uniform vec4 lamp_col_2;
global uniform vec4 lamp_pos_3; global uniform vec4 lamp_col_3;
global uniform vec4 lamp_pos_4; global uniform vec4 lamp_col_4;
global uniform vec4 lamp_pos_5; global uniform vec4 lamp_col_5;
global uniform vec4 lamp_pos_6; global uniform vec4 lamp_col_6;
global uniform vec4 lamp_pos_7; global uniform vec4 lamp_col_7;
global uniform vec4 lamp_pos_8; global uniform vec4 lamp_col_8;
global uniform vec4 lamp_pos_9; global uniform vec4 lamp_col_9;
global uniform vec4 lamp_pos_10; global uniform vec4 lamp_col_10;
global uniform vec4 lamp_pos_11; global uniform vec4 lamp_col_11;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = round(ndc.xy * snap_resolution) / snap_resolution;
	POSITION = vec4(ndc * clip.w, clip.w);
	affine_uv_w = vec3(UV * uv_scale * clip.w, clip.w);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// A lamp: a soft pool that falls off to nothing at its range (pos.w; 0 = off).
vec3 lamp(vec4 pos, vec4 col, vec3 p, vec3 n) {
	if (pos.w <= 0.0) {
		return vec3(0.0);
	}
	vec3 d = pos.xyz - p;
	float dist = length(d);
	float fall = clamp(1.0 - dist / pos.w, 0.0, 1.0);
	// Wrapped, so faces turned half away still catch some light (like PS1 vertex lighting).
	float facing = clamp(dot(n, d / max(dist, 0.001)) * 0.6 + 0.4, 0.0, 1.0);
	return col.rgb * fall * fall * facing;
}

float bayer4(vec2 frag) {
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	vec2 uv = (affine_mapping ? affine_uv_w.xy / affine_uv_w.z : UV * uv_scale) + uv_offset;
	vec3 base = albedo.rgb * texture(albedo_texture, uv).rgb;
	if (unlit) {
		ALBEDO = base;
	} else {
		vec3 n = normalize(world_normal);
		vec3 light = amb_color.rgb;
		light += moon_color.rgb * clamp(dot(n, normalize(moon_dir.xyz + vec3(0.0, 0.0001, 0.0))), 0.0, 1.0);
		vec3 p = world_pos;
		light += lamp(lamp_pos_0, lamp_col_0, p, n);
		light += lamp(lamp_pos_1, lamp_col_1, p, n);
		light += lamp(lamp_pos_2, lamp_col_2, p, n);
		light += lamp(lamp_pos_3, lamp_col_3, p, n);
		light += lamp(lamp_pos_4, lamp_col_4, p, n);
		light += lamp(lamp_pos_5, lamp_col_5, p, n);
		light += lamp(lamp_pos_6, lamp_col_6, p, n);
		light += lamp(lamp_pos_7, lamp_col_7, p, n);
		light += lamp(lamp_pos_8, lamp_col_8, p, n);
		light += lamp(lamp_pos_9, lamp_col_9, p, n);
		light += lamp(lamp_pos_10, lamp_col_10, p, n);
		light += lamp(lamp_pos_11, lamp_col_11, p, n);
		// Stepped light with an ordered dither between the steps: pools with crisp pixel edges.
		float steps = 12.0;
		light = floor(light * steps + bayer4(FRAGCOORD.xy)) / steps;
		ALBEDO = base * min(light, vec3(1.8));
	}
}
