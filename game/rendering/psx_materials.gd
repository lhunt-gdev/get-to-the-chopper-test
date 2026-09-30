class_name PsxMaterials
extends RefCounted
## Shared PS1-style materials, one per colour, so batches stay cheap on mobile.

const SHADER := preload("res://assets/shaders/psx/psx_lit.gdshader")
const SHADOW_SHADER := preload("res://assets/shaders/psx/psx_blob_shadow.gdshader")

static var _cache: Dictionary = {}


static func flat(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo", color)
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
## (lit windows at night) and ignores the area's lighting.
static func textured(tex: Texture2D, uv_scale: Vector2 = Vector2.ONE, unlit: bool = false) -> ShaderMaterial:
	var key := "%d_%s_%s" % [tex.get_rid().get_id(), uv_scale, unlit]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo_texture", tex)
		m.set_shader_parameter("uv_scale", uv_scale)
		m.set_shader_parameter("unlit", unlit)
		_cache[key] = m
	return _cache[key]


## Additive, unlit and see-through: light you can see in the air (searchlight beams, lamp haze).
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
		_cache[key] = m
	return _cache[key]
