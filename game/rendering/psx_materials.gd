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


## Tinted glass you can see through (the guard booth's windows): unlit, alpha-blended, both sides.
static func glass(color: Color) -> StandardMaterial3D:
	var key := "glass_" + color.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = color
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


## A soft glow round a light, the bloom a film camera sees (red beacons, lamps): additive, always
## facing the camera, brightest in the middle and fading to nothing at the edge.
static func halo(color: Color) -> StandardMaterial3D:
	var key := "halo_" + color.to_html()
	if not _cache.has(key):
		var m := _radial_material(color)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.disable_fog = true
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
