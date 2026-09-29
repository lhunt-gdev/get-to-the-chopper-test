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


## uv_scale sets how often the texture repeats across the mesh.
static func textured(tex: Texture2D, uv_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var key := "%d_%s" % [tex.get_rid().get_id(), uv_scale]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo_texture", tex)
		m.set_shader_parameter("uv_scale", uv_scale)
		_cache[key] = m
	return _cache[key]
