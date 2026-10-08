// The PS1 shaders' 4x4 ordered dither and the cutout, shared by everything that dissolves: the PS1
// surface (psx_lit) and the glass (psx_glass), so they cut the same hole on the same dither.
//
// The cutout (Cutout, game/rendering/cutout.gd; user: "anything in front of the camera between the
// lens and Cross is faded/dissolved out"): whatever stands between the camera and CROSS is
// dissolved, PS1 screen-door style (pixels dropped on the same 4x4 ordered dither as the lighting,
// chunky at 270x480), so he always shows. The hole is round his chest, its radius measured at his
// depth and the same size on screen whatever it cuts through (a cone from the lens), fully open in
// the middle and dithered over its outer part. Only nearer the lens than him (less a margin, with
// a short dithered fade), never lower than just above his feet (the floor under him stays: the
// level's surfaces only; a guard or a dog between dissolves down to his boots and paws too), and only
// for the camera it was set for (so never on the rear CCTV monitor's).
// cutout_cam: xyz that camera; w 1 on, 0 off. cutout_fwd: xyz the unit way from it to his chest;
// w his depth (along that) / the radius. cutout_misc: x the floor height; y how far along the
// dissolve stops; z 1 / its fade (m); w 1 / the dithered part of the radius.
global uniform vec4 cutout_cam;
global uniform vec4 cutout_fwd;
global uniform vec4 cutout_misc;

// The 4x4 ordered dither: a threshold (0..1) for the pixel at `frag` (FRAGCOORD.xy).
float bayer4(vec2 frag) {
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// Whether the cutout drops this pixel: the surface at `at` (world space), drawn for the camera at
// `eye` (CAMERA_POSITION_WORLD), at `frag` on screen (FRAGCOORD.xy). `keep_floor`: nothing of it
// lower than the floor height dissolves (the level's surfaces: the floor under him); false for what
// stands on the floor and moves (the guards, the dogs), which dissolves to the ground. Called last in
// fragment(), after any texture read, so a dropped pixel never upsets its neighbours' mip.
bool cutout_drops(vec3 at, vec3 eye, vec2 frag, bool keep_floor) {
	if (cutout_cam.w <= 0.0 || (keep_floor && at.y <= cutout_misc.x) || distance(eye, cutout_cam.xyz) >= 0.05) {
		return false;
	}
	vec3 v = at - cutout_cam.xyz;
	float along = dot(v, cutout_fwd.xyz);
	float near = (cutout_misc.y - along) * cutout_misc.z;  // > 0: nearer than his depth less the margin
	if (near <= 0.0 || along <= 0.01) {
		return false;
	}
	// Where this pixel's line of sight meets his depth, how far that is off his chest, in radii.
	float d = length(v / along - cutout_fwd.xyz) * cutout_fwd.w;
	float cover = clamp((1.0 - d) * cutout_misc.w, 0.0, 1.0) * min(near, 1.0);
	return cover > bayer4(frag);
}
