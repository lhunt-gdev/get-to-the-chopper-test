class_name PsxMaterials
extends RefCounted
## Shared PS1-style materials, one per colour, so batches stay cheap on mobile.

const SHADER := preload("res://assets/shaders/psx/psx_lit.gdshader")
const SHADOW_SHADER := preload("res://assets/shaders/psx/psx_blob_shadow.gdshader")
const GLASS_SHADER := preload("res://assets/shaders/psx/psx_glass.gdshader")
## How near the lens a thin hanging thing starts to dither away (m; gone at half of it), and how
## near it a light in the air fades out (a beam, a lamp's halo: none of it nearer than x, all of it
## from y). The camera passes through, or right by, where they hang; they would sweep across the
## screen, or flash it.
const LENS_FADE := 1.6
const BEAM_FADE := Vector2(0.3, 2.0)
const HALO_FADE := Vector2(1.0, 3.0)

static var _cache: Dictionary = {}


static func flat(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo", color)
		_cache[key] = m
	return _cache[key]


## A plain colour (flat()) that dithers away as the camera comes within LENS_FADE m: a duck-under's
## cables, chains and rods, which the camera, following him under it or past its end, flies right by.
static func lens_faded(color: Color) -> ShaderMaterial:
	var key := "lens_" + color.to_html()
	if not _cache.has(key):
		var m := flat(color).duplicate() as ShaderMaterial
		m.set_shader_parameter("lens_fade", LENS_FADE)
		_cache[key] = m
	return _cache[key]


## Unlit, full-brightness colour for things that give off light (sparks), so they pop in the dark.
static func glow(color: Color) -> StandardMaterial3D:
	var key := "glow_" + color.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.disable_fog = true
		_cache[key] = m
	return _cache[key]


## Blob shadow with dithered edges. rectangle = false gives an ellipse.
static func shadow(rectangle: bool, tuning: Tuning) -> ShaderMaterial:
	var key := "shadow_%s_%s_%s" % [rectangle, tuning.shadow_opacity, tuning.shadow_softness]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADOW_SHADER
		m.set_shader_parameter("rectangle", rectangle)
		m.set_shader_parameter("opacity", tuning.shadow_opacity)
		m.set_shader_parameter("softness", tuning.shadow_softness)
		_cache[key] = m
	return _cache[key]


## A flat shadow mesh lying on the ground, centred on its node.
static func shadow_mesh(size: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = maxi(0, ceili(size.x / 2.0) - 1)
	mesh.subdivide_depth = maxi(0, ceili(size.y / 2.0) - 1)
	return mesh


## uv_scale sets how often the texture repeats across the mesh. unlit: it gives off its own light
## (lit windows at night) and ignores the area's lighting. uv_offset shifts the texture (walls use it
## so a tile's bottom row sits on the floor).
static func textured(tex: Texture2D, uv_scale: Vector2 = Vector2.ONE, unlit: bool = false, uv_offset: Vector2 = Vector2.ZERO) -> ShaderMaterial:
	var key := "%d_%s_%s_%s" % [tex.get_rid().get_id(), uv_scale, unlit, uv_offset]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo_texture", tex)
		m.set_shader_parameter("uv_scale", uv_scale)
		m.set_shader_parameter("unlit", unlit)
		m.set_shader_parameter("uv_offset", uv_offset)
		_cache[key] = m
	return _cache[key]


## The same PS1 material, but never dissolved by the cutout (Cutout): CROSS's own, and a guard's or a
## dog's once he's down (SoldierRig.keep_solid, DogRig.keep_solid), so the live guards and the level
## keep theirs. Anything not drawn in the PS1 shader (the glow of his goggles) never is anyway, so it
## comes back as it is.
static func solid(m: Material) -> Material:
	if not (m is ShaderMaterial and (m as ShaderMaterial).shader == SHADER):
		return m
	var key := "solid_%d" % m.get_instance_id()
	if not _cache.has(key):
		var s := m.duplicate() as ShaderMaterial
		s.set_shader_parameter("cutout", false)
		_cache[key] = s
	return _cache[key]


## The same PS1 material, but dissolved by the cutout all the way down to the floor (its floor rule,
## nothing lower than just above his feet, off: Cutout): what stands on the floor and moves, the
## guards and the dogs, so one between the camera and CROSS goes boots and all instead of leaving his
## boots in the hole. The level's own materials keep the rule, so the floor under him stays. Anything
## not drawn in the PS1 shader comes back as it is.
static func figure(m: Material) -> Material:
	if not (m is ShaderMaterial and (m as ShaderMaterial).shader == SHADER):
		return m
	var key := "figure_%d" % m.get_instance_id()
	if not _cache.has(key):
		var f := m.duplicate() as ShaderMaterial
		f.set_shader_parameter("cutout_floor", false)
		_cache[key] = f
	return _cache[key]


## Tinted glass you can see through (the guard booth's windows): unlit, alpha-blended, both sides
## (psx_glass.gdshader). The cutout dissolves it as it does the PS1 surfaces round it (Cutout).
## Never a sight blocker: you see through it (is_glass).
static func glass(color: Color) -> ShaderMaterial:
	var key := "glass_" + color.to_html()
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLASS_SHADER
		m.set_shader_parameter("tint", color)
		_cache[key] = m
	return _cache[key]


## Whether `m` is the glass (glass()).
static func is_glass(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader == GLASS_SHADER

## Additive, unlit and see-through: light you can see in the air (searchlight beams, lamp haze),
## fading out near the lens.
static func beam(color: Color) -> StandardMaterial3D:
	var key := "beam_" + color.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.albedo_color = color
		# Brightest at the lamp (the mesh's top, v = 0), fading to nothing at the far end.
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = fade
		tex.fill_from = Vector2(0, 0)
		tex.fill_to = Vector2(0, 1)
		tex.width = 4
		tex.height = 32
		m.albedo_texture = tex
		# Fading out near the lens (BEAM_FADE): the camera passes through a lamp's haze.
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = BEAM_FADE.x
		m.distance_fade_max_distance = BEAM_FADE.y
		_cache[key] = m
	return _cache[key]


## A soft glow round a light, the bloom a film camera sees (red beacons, lamps): additive, always
## facing the camera, brightest in the middle and fading to nothing at the edge. keep_scale: it grows
## and shrinks with its node (the sniper's glint as he locks on).
static func halo(color: Color, keep_scale := false) -> StandardMaterial3D:
	var key := ("halo_scaled_" if keep_scale else "halo_") + color.to_html()
	if not _cache.has(key):
		var m := _radial_material(color)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = keep_scale
		m.disable_fog = true
		_cache[key] = m
	return _cache[key]


## A lamp's halo in the level (halo()), fading out near the lens (HALO_FADE): the camera passes right
## by a hanging lamp's.
static func lamp_halo(color: Color) -> StandardMaterial3D:
	var key := "lamp_halo_" + color.to_html()
	if not _cache.has(key):
		var m := halo(color).duplicate() as StandardMaterial3D
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = HALO_FADE.x
		m.distance_fade_max_distance = HALO_FADE.y
		_cache[key] = m
	return _cache[key]


## A pool of light on the ground under a lamp: the same soft radial glow, lying flat.
static func pool(color: Color) -> StandardMaterial3D:
	var key := "pool_" + color.to_html()
	if not _cache.has(key):
		_cache[key] = _radial_material(color)
	return _cache[key]


static func _radial_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = color
	if not _cache.has("_radial"):
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		fade.add_point(0.3, Color(1, 1, 1, 0.45))
		var tex := GradientTexture2D.new()
		tex.gradient = fade
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_cache["_radial"] = tex
	m.albedo_texture = _cache["_radial"]
	return m


## Falling water (the outfalls, the sewer's spouts, the weirs): streaks of water flowing down a flat
## sheet, scrolled by time, soft at the sides, unlit and see-through, both sides.
const WATER_FALL_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D streaks : filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(0.8, 0.88, 0.82, 0.7);
uniform float speed = 1.8;
uniform vec2 uv_scale = vec2(1.0, 1.0);
void fragment() {
	vec2 uv = UV * uv_scale + vec2(0.0, -TIME * speed);
	vec4 s = texture(streaks, uv);
	float sides = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	ALBEDO = tint.rgb * (0.65 + 0.55 * s.r);
	ALPHA = tint.a * s.a * sides;
}
"""


static func water_fall(tint: Color, uv_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var key := "water_fall_%s_%s" % [tint.to_html(), uv_scale]
	if not _cache.has(key):
		if not _cache.has("_water_fall_shader"):
			var sh := Shader.new()
			sh.code = WATER_FALL_CODE
			_cache["_water_fall_shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = _cache["_water_fall_shader"]
		m.set_shader_parameter("streaks", PsxTextures.water_streaks())
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("uv_scale", uv_scale)
		_cache[key] = m
	return _cache[key]


## The arrows in to a stairs door (user, 2026-10-07: "3 arrows just before that are a bit
## transparent and light up one after another"): unlit and see-through, both sides, lit one at a
## time toward the door and then a beat with none lit, over and over. Driven by TIME, so nothing
## runs per frame and rebuilding them (as the alert changes) never restarts the chase. The PS1
## snap is the same as psx_lit's. Each is pulled toward the camera along its own line of sight
## (the same pixels, nearer depth), so it never fights the floor under it however the snap wobbles
## the two (no popping). Close to the camera they fade out: the ones you've passed, and the one
## under your feet, never fill the bottom of the screen or show your legs through them.
const DOOR_ARROW_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.384, 0.839, 0.753, 1.0);
uniform float idle_alpha = 0.42;
uniform float lit_alpha = 0.9;
uniform float lit_boost = 0.35;
uniform float index = 0.0;
uniform float count = 3.0;
uniform float step_time = 0.18;
uniform float rest_time = 0.21;
uniform bool chase = true;
uniform float snap_resolution = 90.0;
uniform float pull = 0.03;
uniform float fade_near = 6.0;
uniform float fade_full = 9.0;
varying float cam_d;
void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(view.xyz);
	cam_d = d;
	view.xyz *= max(0.0, 1.0 - pull - 0.04 / max(d, 0.1));
	vec4 clip = PROJECTION_MATRIX * view;
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = round(ndc.xy * snap_resolution) / snap_resolution;
	POSITION = vec4(ndc * clip.w, clip.w);
}
void fragment() {
	float lit = 0.0;
	if (chase) {
		float period = count * step_time + rest_time;
		float t = mod(TIME, period);
		lit = (t >= index * step_time && t < (index + 1.0) * step_time) ? 1.0 : 0.0;
	}
	ALBEDO = mix(tint.rgb, mix(tint.rgb, vec3(1.0), lit_boost), lit);
	ALPHA = mix(idle_alpha, lit_alpha, lit) * clamp((cam_d - fade_near) / (fade_full - fade_near), 0.0, 1.0);
}
"""


## Arrow `index` of `count` (0 first lit, the farthest from the door), in `tint`. chase = false is
## a door that's locked: the arrow dark and still, just there on the floor. Drawn under the other
## see-through things (his blob shadow, blood, halos), so the order never flips as he runs over.
## TIME isn't slowed by the junction slowdown or by pause (like the falling water).
static func door_arrow(index: int, count: int, tint: Color, chase: bool) -> ShaderMaterial:
	var key := "door_arrow_%d_%d_%s_%s" % [index, count, tint.to_html(), chase]
	if not _cache.has(key):
		if not _cache.has("_door_arrow_shader"):
			var sh := Shader.new()
			sh.code = DOOR_ARROW_CODE
			_cache["_door_arrow_shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = _cache["_door_arrow_shader"]
		m.render_priority = -1
		# (Set even where they match the defaults: get_shader_parameter reads null for a default.)
		m.set_shader_parameter("index", float(index))
		m.set_shader_parameter("count", float(count))
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("chase", chase)
		m.set_shader_parameter("idle_alpha", 0.42 if chase else 0.2)
		_cache[key] = m
	return _cache[key]


## A copy of `m` that dithers away as the camera comes within a few metres (see-through from 3.5 m,
## solid from 6 m): the padlock at a locked stairs door, which you run right under if you carry on
## past it. alpha = true fades it smoothly instead (a halo: dithering one shows its square).
static func near_fade(m: StandardMaterial3D, alpha: bool = false) -> StandardMaterial3D:
	var key := "near_fade_%d_%s" % [m.get_instance_id(), alpha]
	if not _cache.has(key):
		var f := m.duplicate() as StandardMaterial3D
		f.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA if alpha else BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		f.distance_fade_min_distance = 3.5
		f.distance_fade_max_distance = 6.0
		_cache[key] = f
	return _cache[key]


## A far backdrop seen through windows (the night city out of the start room): unlit, no fog (it's
## the clear night out there, not the room's murk: fogged, 30 m out, it went black), its texture's
## pixels crisp. The glass in front of it is what fades it.
static func backdrop(tex: Texture2D, uv_scale: Vector2 = Vector2.ONE) -> StandardMaterial3D:
	var key := "backdrop_%d_%s" % [tex.get_rid().get_id(), uv_scale]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.albedo_texture = tex
		m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
		_cache[key] = m
	return _cache[key]
