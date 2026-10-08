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
// A lamp of its own, outside the nearest-12 (his muzzle flash), so it never puts out a level lamp.
global uniform vec4 lamp_pos_12; global uniform vec4 lamp_col_12;
// ...and another (the boss's muzzle flash), for the same reason.
global uniform vec4 lamp_pos_13; global uniform vec4 lamp_col_13;

// The 4x4 ordered dither (the lighting's steps below) and the cutout, which dissolves whatever stands
// between the camera and CROSS: shared with the glass (psx_glass), so both cut the same hole on the
// same dither.
#include "res://assets/shaders/psx/psx_cutout.gdshaderinc"
// false: never dissolves (CROSS himself: PsxMaterials.solid).
uniform bool cutout = true;
// false: dissolves all the way down, the cutout's floor rule (nothing lower than just above his feet)
// not for it: the guards and the dogs (PsxMaterials.figure), so no boots are left in the hole.
uniform bool cutout_floor = true;
// Over 0: dithers away as the camera comes nearer than this (m), gone at half of it: thin things
// hanging where the camera passes (a duck-under's cables, chains and rods: PsxMaterials.lens_faded),
// so the lens never flies through one.
uniform float lens_fade = 0.0;

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
		light += lamp(lamp_pos_12, lamp_col_12, p, n);
		light += lamp(lamp_pos_13, lamp_col_13, p, n);
		// Stepped light with an ordered dither between the steps: pools with crisp pixel edges.
		float steps = 12.0;
		light = floor(light * steps + bayer4(FRAGCOORD.xy)) / steps;
		ALBEDO = base * min(light, vec3(1.8));
	}
	// The cutout, last (after the texture read, so a dropped pixel never upsets its neighbours' mip).
	if (cutout && cutout_drops(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy, cutout_floor)) {
		discard;
	}
	if (lens_fade > 0.0 && clamp(2.0 - 2.0 * distance(world_pos, CAMERA_POSITION_WORLD) / lens_fade, 0.0, 1.0) > bayer4(FRAGCOORD.xy)) {
		discard;
	}
}
