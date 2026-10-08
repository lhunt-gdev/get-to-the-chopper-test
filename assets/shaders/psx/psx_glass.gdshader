// See-through glass (PsxMaterials.glass: windows and glass walls, the doors out of the MAIN FLOOR
// EXIT, the guard booth's windows, the speed gates' flaps, the skylights, still water, pools of
// light on the floor): a flat tint, unlit, alpha-blended, both sides. It dissolves in the cutout as
// the PS1 surface does (the same hole on the same dither: psx_cutout.gdshaderinc), so a pane never
// hangs over CROSS once the frame round it has gone.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(1.0);
varying vec3 world_pos;

#include "res://assets/shaders/psx/psx_cutout.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	if (cutout_drops(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy, true)) {
		discard;
	}
}
