class_name SoldierRig
extends Node3D
## The player character, Ernest Cross, codename CROSS (user). A PS1-style low-poly model (3,000
## triangles, a 512 texture) made from the user's Meshy model of their turnaround sheet: rebuilt
## into one clean skin, reduced, unwrapped and its colours baked on, then rigged with the game's 19
## joints and smooth skin weights, all in Blender (scripts in art_source/operative/tools).
##
## Posed procedurally every frame from the player's state: run, jump, slide, cover, stumble,
## surrender. The poses work on a hierarchy of joint nodes (hips, spine, chest, neck, head,
## collarbones, shoulders, elbows, wrists, hips, knees, ankles) at the skeleton's rest positions; each
## frame those nodes' transforms are copied onto the skeleton's bones. Faces -Z (away from the camera).

## The model, rigged (exported from art_source/operative/tools/stage4_rig.py): CROSS by default.
## Any character built by the same pipeline (art_source/operative/tools/build_character.sh) has the
## same skeleton, so every pose here works on him too: e.g. the guard (GuardRig).
const MODEL := preload("res://game/player/cross.glb")
## The skeleton's bones, parents before children, and each one's parent.
const TREE := {
	"Hips": "", "Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck",
	"ClavicleR": "Chest", "ShoulderR": "ClavicleR", "ElbowR": "ShoulderR", "WristR": "ElbowR",
	"ClavicleL": "Chest", "ShoulderL": "ClavicleL", "ElbowL": "ShoulderL", "WristL": "ElbowL",
	"LegHipR": "Hips", "KneeR": "LegHipR", "AnkleR": "KneeR",
	"LegHipL": "Hips", "KneeL": "LegHipL", "AnkleL": "KneeL",
}
## Where his goggle lenses are on the model (Godot axes, metres), written next to it by the Blender
## pipeline (stage 4 finds them from the green in his texture): they glow, so they show in the dark.
const LENS_FILE := "res://game/player/cross.json"
## The model stands in an A-pose with the arms out from the body; at rest the rig brings them in
## this much of the way, so a pose of zero has them hanging beside him (not into the vest).
const ARM_IN := 1.0
## ...and the legs (they stand apart on the model): more than the way in, so his feet sit a little
## inside his hips (user: legs a bit closer together). The feet are turned back flat.
const LEG_IN := 2.0
## How much bigger than the model he is in the game (user: "just a little bit bigger"): ~2.05 m.
const SIZE := 1.08
## Aiming (FIRE held, user): the right arm straight out ahead, raised this far (rad) at the shoulder
## (level), the elbow turned this much (+ bends it; the model's arm is bent ~15° at rest, so this
## straightens it to a few degrees).
const AIM_RAISE := 1.55
const AIM_ELBOW := -0.2
## ...and the gun hand turned so the gun points straight ahead and level (user: it pointed off to the
## side; the model's hand is bent in at the wrist). The wrist's turn in the rig's axes: the hand (and
## barrel, -y) forward, the top of the fist (-z) up.
const GUN_AHEAD := Basis(Vector3.RIGHT, PI / 2.0)
## A shot's recoil: how long the kick takes to settle (s).
const RECOIL_TIME := 0.16
## Where the pistol sits in his right hand (wrist space; -y runs out along the hand, -z is the top of
## his fist when aiming): the grip in the hollow of his closed fist, between the palm and the curled
## fingers, and the slide resting on top of the fist (the glove reaches ~0.195 out from the wrist).
## It's 15% bigger than life (user: "a bit bigger", after moving it forward was too far), so the
## muzzle reaches ~10 cm past his knuckles, and hanging at his side it clears his thigh.
const PISTOL_AT := Vector3(-0.004, -0.11, -0.06)
const GUN_SCALE := 1.15
## The muzzle flash (user: "a cool looking flash, not just a box"): how much of the recoil it shows
## for, and the colour and reach of the light it gives off for that moment.
const FLASH_TIME := 0.4
const FLASH_LIGHT := Color(1.0, 0.72, 0.35) * 2.2
const FLASH_LIGHT_RANGE := 4.5
const FLASH_SHADER := preload("res://assets/shaders/psx/psx_muzzle_flash.gdshader")
## Hands up when caught (user: palms forward and a little in, not facing out): how far each arm
## turns out about itself (rad), shared between the upper arm (at the shoulder) and the forearm (at
## the elbow) so no one joint twists the skin too far, and how far the elbows bend. The wrists then
## set each hand exactly: running on from the forearm, its palm facing forwards and this much in.
const HANDS_UP_SHOULDER_TURN := 0.9
const HANDS_UP_FOREARM_TURN := 0.6
const HANDS_UP_ELBOW := 0.7
const HANDS_UP_PALM_IN := 0.3
## The shrug (user: his shoulders bent out of shape with his arms up): once an upper arm is raised
## past SHRUG_FROM (rad from hanging down), the collarbone lifts SHRUG of each radian more, up to
## SHRUG_MAX, and the shoulder joint turns that much less, so the arm points the same way but the
## shoulder rises with it instead of the joint bending all that way alone.
const SHRUG_FROM := 0.9
const SHRUG := 0.4
const SHRUG_MAX := 0.4

var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var clavicles := {}  # side (-1 left, 1 right) -> joint
var shoulders := {}
var elbows := {}
var wrists := {}
var leg_hips := {}
var knees := {}
var ankles := {}

## The run cycle's phase (radians), advanced by the run speed.
var _phase := 0.0
## How much of the run is showing (0 standing .. 1 full run), eased.
var _run := 0.0
var _flash_left := 0.0
## The hips' standing height (m, feet on y = 0), and how high they sit when he's down on one knee:
## both from the skeleton (a knee pad's height plus the thigh, plus the pelvis above the hip joints).
var _hip_y := 0.95
var _kneel_y := 0.55
## How far into the aim the right arm is (0..1), eased; the recoil still to settle (1 just fired .. 0).
var _aim := 0.0
var _kick := 0.0
var _slide: Node3D
var _muzzle: Node3D
## The muzzle flash: the star of flame (facing the camera), the tongues of flame along the barrel, the
## light they give off (a lamp the level adds to its lighting), and this shot's size, reach and shape.
var _muzzle_flash: Node3D
var _flash_star: MeshInstance3D
var _flash_tongues: MeshInstance3D
var _flash_light: Node3D
var _flash_size := 1.0
var _flash_reach := 1.0
var _flash_rng := RandomNumberGenerator.new()
## The state animate() was last given, so a shot can re-pose him straight away (see recoil()).
var _last_state := {}
## Each glove's own axes, in its wrist joint's frame (side -> Vector3): which way the hand runs from
## the wrist (to the fingers), and which way its palm faces (toward his thigh at rest). Measured from
## the model when built (see _measure_hand), so the hands can be posed exactly.
var _hand_run := {}
var _hand_palm := {}
## ...and the middle of each glove (wrist frame): where a grip sits in the fist.
var _hand_mid := {}
## The measured gloves, per model (model path + side -> [run, palm, mid]): measured once, not for
## every guard on the route.
static var _hand_cache := {}
var _model: PackedScene
var _lens_file := ""
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[Material] = []
## Never dissolved by the cutout (keep_solid).
var _solid := false
var _skeleton: Skeleton3D
## Skeleton space to this rig's space.
var _sk_xf := Transform3D.IDENTITY
## Bone index -> the node whose transform (in this rig's space) poses that bone.
var _drivers := {}
## Bone index -> its rest transform in skeleton space.
var _rest := {}
## Bones, parents first.
var _order: Array[int] = []


## model: which character (CROSS by default); lens_file: where his goggle lenses are (none: "").
func _init(model: PackedScene = MODEL, lens_file: String = LENS_FILE, rig_name: String = "CROSS") -> void:
	name = rig_name
	_model = model
	_lens_file = lens_file
	_build()
	scale = Vector3.ONE * SIZE


## --- Building ---------------------------------------------------------------------------------

func _joint(parent: Node3D, pos: Vector3, joint_name: String) -> Node3D:
	var j := Node3D.new()
	j.name = joint_name
	j.position = pos
	parent.add_child(j)
	return j


## A box part on `joint` (the pistol), `size`, centred at `pos` in the joint's space. Like the rest
## of him, it has no floor rule in the cutout (PsxMaterials.figure).
func _part(joint: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = PsxMaterials.figure(PsxMaterials.flat(color))
	joint.add_child(m)
	_meshes.append(m)
	_materials.append(m.material_override)
	return m


func _build() -> void:
	var model: Node3D = _model.instantiate()
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_sk_xf = _in_rig(_skeleton)
	# His texture, through the game's PS1 shader (stepped lighting from the lamps you can see, the
	# vertex wobble, affine texturing) like everything else. A guard standing between the camera and
	# CROSS dissolves boots and all: no floor rule in the cutout for him (PsxMaterials.figure).
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var src := mi.get_active_material(0) as BaseMaterial3D
		var mat := PsxMaterials.figure(PsxMaterials.textured(src.albedo_texture if src else null))
		mi.material_override = mat
		_meshes.append(mi)
		_materials.append(mat)
	# The joint nodes the poses turn, at the bones' rest positions.
	var nodes := {}  # bone name -> joint node
	var under := {}  # bone name -> the node its children hang from (the shoulders' arm-in pivot)
	for bone: String in TREE:
		var b := _skeleton.find_bone(bone)
		_order.append(b)
		_rest[b] = _skeleton.get_bone_global_rest(b).orthonormalized()
		var at: Vector3 = _sk_xf * _rest[b].origin
		var parent: Node3D = self if TREE[bone] == "" else under[TREE[bone]]
		# Offset from the parent bone's rest point, in the parent's own (unturned) frame: every joint
		# node has no rotation of its own when built, so this offset is in the rig's axes, and the
		# arm-in / leg-in pivots above a joint carry it round with them (placing it through the
		# pivot's turned frame would cancel the turn and kink the limb at the joint).
		var parent_at := Vector3.ZERO if TREE[bone] == "" else _sk_xf * (_rest[_skeleton.find_bone(TREE[bone])] as Transform3D).origin
		var j := _joint(parent, at - parent_at, bone)
		nodes[bone] = j
		under[bone] = j
		_drivers[b] = j
		if bone.begins_with("Shoulder"):
			# Bring the A-pose arm in toward his side, about the shoulder.
			var elbow := _sk_xf * _skeleton.get_bone_global_rest(_skeleton.find_bone("Elbow" + bone.right(1))).origin
			var out := elbow - at
			var angle := atan2(out.x, -out.y)  # how far the upper arm leans out (+ toward +x)
			var fix := Node3D.new()
			fix.name = bone + "In"
			fix.rotation.z = -angle * ARM_IN
			j.add_child(fix)
			under[bone] = fix
			_drivers[b] = fix
		if bone.begins_with("LegHip"):
			# Bring the leg in toward the middle, about the hip.
			var ankle := _sk_xf * _skeleton.get_bone_global_rest(_skeleton.find_bone("Ankle" + bone.right(1))).origin
			var down := ankle - at
			var fix := Node3D.new()
			fix.name = bone + "In"
			fix.rotation.z = -atan2(down.x, -down.y) * LEG_IN
			j.add_child(fix)
			under[bone] = fix
			_drivers[b] = fix
		if bone.begins_with("Ankle"):
			# ...and turn the foot back so the sole stays flat.
			var hip_in: Node3D = under["LegHip" + bone.right(1)]
			var flat := Node3D.new()
			flat.name = bone + "Flat"
			flat.rotation.z = -hip_in.rotation.z
			j.add_child(flat)
			_drivers[b] = flat
	hips = nodes["Hips"]
	_hip_y = hips.position.y
	var leg_hip: Vector3 = _sk_xf * (_rest[_skeleton.find_bone("LegHipR")] as Transform3D).origin
	var knee: Vector3 = _sk_xf * (_rest[_skeleton.find_bone("KneeR")] as Transform3D).origin
	_kneel_y = 0.07 + leg_hip.distance_to(knee) + (_hip_y - leg_hip.y)
	spine = nodes["Spine"]
	chest = nodes["Chest"]
	neck = nodes["Neck"]
	head = nodes["Head"]
	for side in [-1, 1]:
		var s := "R" if side > 0 else "L"
		clavicles[side] = nodes["Clavicle" + s]
		shoulders[side] = nodes["Shoulder" + s]
		elbows[side] = nodes["Elbow" + s]
		wrists[side] = nodes["Wrist" + s]
		leg_hips[side] = nodes["LegHip" + s]
		knees[side] = nodes["Knee" + s]
		ankles[side] = nodes["Ankle" + s]
	_build_pistol()
	for side in [-1, 1]:
		_measure_hand(side)
		_ankle_rest[side] = _in_rig(ankles[side]).origin
	# The goggles' lenses glow green.
	var head_at := _in_rig(head).origin
	for lens: Vector3 in _lenses():
		var glow := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.016
		disc.bottom_radius = 0.016
		disc.height = 0.004
		disc.radial_segments = 8
		glow.mesh = disc
		glow.material_override = PsxMaterials.glow(Color("7aff8a"))
		head.add_child(glow)
		glow.position = lens - head_at + Vector3(0, 0, -0.004)
		glow.rotation.x = PI / 2.0
		_meshes.append(glow)
		_materials.append(glow.material_override)
	_pose_stand()
	_shrug()
	_apply()


## A glove's axes in its wrist joint's frame, from the model at rest: the hand runs from the wrist
## toward the middle of its vertices; its palm faces along its thinnest spread across that (the
## palm-to-knuckles thickness of the fist; clearly thinner than its width), signed toward his thigh.
## In the wrist joint's frame the hand sits as on the model (the joints don't carry its rest turn).
func _measure_hand(side: int) -> void:
	var key := "%s%d" % [_model.resource_path, side]
	if _hand_cache.has(key):
		_hand_run[side] = _hand_cache[key][0]
		_hand_palm[side] = _hand_cache[key][1]
		_hand_mid[side] = _hand_cache[key][2]
		return
	var wb := _skeleton.find_bone("Wrist" + ("R" if side > 0 else "L"))
	var rest: Transform3D = _rest[wb]
	var origin: Vector3 = _sk_xf * rest.origin
	var pts: Array[Vector3] = []
	for mi: MeshInstance3D in _meshes:
		if mi.skin == null or mi.mesh == null:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, verts.size())
		for vi in verts.size():
			for k in per:
				var bi: int = bones[vi * per + k]
				var b := mi.skin.get_bind_bone(bi)
				if b < 0:
					b = _skeleton.find_bone(mi.skin.get_bind_name(bi))
				if b == wb and weights[vi * per + k] >= 0.6:
					pts.append(_sk_xf * (rest * (mi.skin.get_bind_pose(bi) * verts[vi])) - origin)
	if pts.size() < 8:  # no glove found: a hand hanging down, palm in
		_hand_run[side] = Vector3.DOWN
		_hand_palm[side] = Vector3(-side, 0, 0)
		_hand_mid[side] = Vector3(0, -0.09, 0)
		_hand_cache[key] = [_hand_run[side], _hand_palm[side], _hand_mid[side]]
		return
	var mid := Vector3.ZERO
	for q in pts:
		mid += q
	mid /= pts.size()
	var run := mid.normalized()
	var u := run.cross(Vector3.FORWARD).normalized()
	var w := run.cross(u)
	var uu := 0.0
	var ww := 0.0
	var uw := 0.0
	for q in pts:
		var d := q - mid
		uu += d.dot(u) * d.dot(u)
		ww += d.dot(w) * d.dot(w)
		uw += d.dot(u) * d.dot(w)
	var thin := 0.5 * atan2(2.0 * uw, uu - ww) + PI / 2.0  # the widest spread's angle, turned a quarter
	var palm := (u * cos(thin) + w * sin(thin)).normalized()
	_hand_run[side] = run
	_hand_palm[side] = -palm if palm.x * side > 0.0 else palm
	_hand_mid[side] = mid
	_hand_cache[key] = [_hand_run[side], _hand_palm[side], _hand_mid[side]]


## The pistol in his right hand (user): a low-poly sidearm (slide, frame, raked grip, trigger
## guard), modelled with its barrel along -Z and turned so that with his arm hanging it points down
## along his hand, as on the sheet; raised to aim, it points straight ahead. The slide is its own
## node so it can snap back on a shot, and a flash bursts from the muzzle.
func _build_pistol() -> void:
	var pistol := Node3D.new()
	pistol.name = "Pistol"
	wrists[1].add_child(pistol)
	pistol.position = PISTOL_AT
	pistol.rotation.x = -PI / 2.0
	pistol.scale = Vector3.ONE * GUN_SCALE
	_pistol = pistol
	var gun := Color("1c1c1e")
	_slide = Node3D.new()
	_slide.name = "Slide"
	pistol.add_child(_slide)
	_part(_slide, Vector3(0.03, 0.034, 0.19), Vector3(0, 0.03, -0.06), Color("26282b"))
	_part(_slide, Vector3(0.006, 0.01, 0.012), Vector3(0, 0.05, -0.145), Color("3a3c40"))  # front sight
	_part(pistol, Vector3(0.026, 0.022, 0.15), Vector3(0, 0.004, -0.05), gun)  # frame
	var grip := _part(pistol, Vector3(0.03, 0.11, 0.045), Vector3(0, -0.05, 0.012), gun)
	grip.rotation.x = -0.25  # raked back: its foot toward his wrist (+Z), as a pistol grip is
	_part(pistol, Vector3(0.008, 0.028, 0.04), Vector3(0, -0.014, -0.032), gun)  # trigger guard
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	pistol.add_child(_muzzle)
	_muzzle.position = Vector3(0, 0.03, -0.16)
	_build_flash()
	if IDLE_MAG_DROP:
		# The magazine, hidden in the grip until he drops it into his palm (the pistol looks the same).
		_mag = Node3D.new()
		_mag.name = "Magazine"
		pistol.add_child(_mag)
		_part(_mag, Vector3(0.024, 0.104, 0.036), Vector3(0, -0.002, 0), Color("2b2c30"))
		_mag_at(0.0)


## The muzzle flash (user: "a cool looking flash, not just a box"), in the muzzle's space (the barrel
## along -Z): a star of flame facing the camera just ahead of the muzzle, and two crossed tongues of
## flame shooting out ahead, both PS1-style hard bands of white-hot, yellow and orange (the
## psx_muzzle_flash shader). Hidden until a shot.
func _build_flash() -> void:
	_muzzle_flash = Node3D.new()
	_muzzle_flash.name = "MuzzleFlash"
	_muzzle.add_child(_muzzle_flash)
	_muzzle_flash.visible = false
	_flash_star = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	_flash_star.mesh = quad
	_flash_star.material_override = _flash_material(0)
	_muzzle_flash.add_child(_flash_star)
	_flash_star.position = Vector3(0, 0, -0.03)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.045
	var reach := 0.2
	for across: Vector3 in [Vector3(w, 0, 0), Vector3(0, w, 0)]:  # one flat, one upright: a cross from the front
		var corners: Array[Vector3] = [-across, across, across + Vector3(0, 0, -reach), -across + Vector3(0, 0, -reach)]
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.add_vertex(corners[i])
	_flash_tongues = MeshInstance3D.new()
	_flash_tongues.mesh = st.commit()
	_flash_tongues.material_override = _flash_material(1)
	_muzzle_flash.add_child(_flash_tongues)
	_flash_light = Node3D.new()
	_flash_light.name = "FlashLight"
	_muzzle.add_child(_flash_light)
	_flash_light.position = Vector3(0, 0, -0.08)
	_flash_light.visible = false


func _flash_material(kind: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLASH_SHADER
	m.set_shader_parameter("kind", kind)
	return m


## A shot (user): the arm and pistol kick up, the slide snaps back, the muzzle flashes (a new shape,
## size and reach each time, and turned about the barrel). The level shoots in the same tick FIRE is
## pressed, before he's had a frame to raise the gun, so the arm snaps straight up here and he's
## re-posed, still level (the kick comes after the bullet): the tracer (from muzzle_position(), read
## just after) leaves the raised pistol, not the one at his side, and the kick and flash show from
## the next frame.
func recoil() -> void:
	_aim = 1.0
	_kick = 0.0
	if not _last_state.is_empty():
		animate(0.0, _last_state)
	_kick = 1.0
	_flash_light.visible = true  # the level's lighting reads it later this same tick
	var shape := _flash_rng.randf()
	(_flash_star.material_override as ShaderMaterial).set_shader_parameter("seed", shape)
	(_flash_tongues.material_override as ShaderMaterial).set_shader_parameter("seed", shape)
	_flash_size = _flash_rng.randf_range(0.85, 1.2)
	_flash_reach = _flash_rng.randf_range(0.8, 1.3)
	_flash_tongues.rotation.z = _flash_rng.randf() * TAU


## The point the muzzle flash lights from, and its light (the level adds it as a lamp; it's only
## lit while the flash shows).
func muzzle_light() -> Node3D:
	return _flash_light


## Where shots leave the pistol (world space), for the tracer.
func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle.is_inside_tree() else global_position + Vector3.UP * 1.3


## The lens positions from the lens file (none if there isn't one: the guard has no goggles).
func _lenses() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _lens_file == "":
		return out
	var f := FileAccess.open(_lens_file, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for l in data.get("lenses", []):
			out.append(Vector3(float(l[0]), float(l[1]), float(l[2])))
	return out


## `node`'s transform in this rig's space (its local transforms up to the rig, multiplied).
func _in_rig(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Copy the joint nodes' pose onto the skeleton: each bone keeps its rest orientation, turned by
## its joint's rotation, at its joint's position.
func _apply() -> void:
	var to_sk := _sk_xf.affine_inverse()
	var posed := {}
	for b in _order:
		var d: Transform3D = _in_rig(_drivers[b])
		var rest: Transform3D = _rest[b]
		var g := to_sk * Transform3D(d.basis * (_sk_xf.basis * rest.basis), d.origin)
		var p := _skeleton.get_bone_parent(b)
		var local: Transform3D = g if p < 0 or not posed.has(p) else (posed[p] as Transform3D).affine_inverse() * g
		posed[b] = g
		_skeleton.set_bone_pose_position(b, local.origin)
		_skeleton.set_bone_pose_rotation(b, local.basis.orthonormalized().get_rotation_quaternion())


## --- Posing -----------------------------------------------------------------------------------

func _reset() -> void:
	# The whole basis, not just the rotation (which keeps the old scale): the shrug, the aim and the
	# hands-up set bases directly, and a tiny scale left over would build up frame on frame.
	for j in [hips, spine, chest, neck, head]:
		j.basis = Basis.IDENTITY
	for d in [clavicles, shoulders, elbows, wrists, leg_hips, knees, ankles]:
		for k in d:
			d[k].basis = Basis.IDENTITY
	hips.position = Vector3(0, _hip_y, 0)
	rotation = Vector3.ZERO


func _pose_stand() -> void:
	_reset()
	for side in [-1, 1]:
		shoulders[side].rotation = Vector3(0.0, 0.0, side * 0.03)  # hands in by his sides (user)
		elbows[side].rotation.x = 0.25
	shoulders[1].rotation.x = 0.12  # the pistol held low, pointing down (user reference)
	elbows[1].rotation.x = 0.3


## Every frame, from the player's state: `run` 0..1 (how fast, of full speed), `airborne` (and
## `rising`), `sliding`, `cover` ("", "crouch", "stand"), `stun` 0..1, `lean` (lane change, -1..1),
## `surrender`, `aim` (FIRE held: the gun up); before the run, `ready` (his ready stance under the
## menu) and `pan` (the opening pan's progress once START is pressed, else -1). Out of the stance
## the run grows from it: the stride at once from his set, the rest of him following. Every other
## change of pose eases in (see "His pose changes eased").
## Joint signs (the model faces -Z): spine, neck, head: -x leans forward. Shoulders, leg hips:
## +x swings the limb forward. Elbows: +x bends the forearm up and forward. Knees: -x folds the
## shin back. Shoulder z: side * angle raises the arm out to its side.
func animate(delta: float, s: Dictionary) -> void:
	_last_state = s
	_flash(delta)
	if s.get("surrender", false):
		# Caught: eased down from what he showed, the aim and all (it's let go at once, so this one
		# is eased after the shrug).
		var caught := _pose_was not in ["", "ready", "surrender"]
		var shown := _pose_snapshot() if caught else []
		var low := _sole_low() if caught else -INF
		_pose_was = "surrender"
		_idle_on = false
		_pose_surrender()
		# A shot just before the catch doesn't stay frozen on: the gun settles, the flash goes.
		_aim = 0.0
		_kick = 0.0
		_slide.position.z = 0.0
		_muzzle_flash.visible = false
		_flash_light.visible = false
		_shrug()
		if caught:
			_change_begin(shown, POSE_CHANGE["surrender"], low)
		_change_step(delta)
		_apply()
		return
	if s.get("ready", false):
		_pose_was = "ready"
		_animate_ready(delta, float(s.get("pan", -1.0)))
		return
	var target_run: float = s.get("run", 0.0)
	if _idle_on:
		# Out of his ready stance (the run's begun): the stride starts at once, from his set, rear
		# leg first (no glide while he's already moving), and the rest of him follows (below).
		_idle_on = false
		_launch_from = _pose_snapshot()
		_launch_slide = _slide.position.z
		_launch_mag = _mag_out
		_launch_t = 0.0
		_run = target_run
		_phase = IDLE_LAUNCH_PHASE
		_pose_was = "ready"  # (the launch is its own blend: no change carries over into it)
		_change_t = [-1.0, -1.0, -1.0]
	if _launch_t >= 0.0:
		_launch_t += delta
	_run = move_toward(_run, target_run, delta * 4.0)
	_phase = fmod(_phase + delta * TAU * 1.55 * maxf(target_run, 0.2), TAU)
	var pose := _pose_pick(s)
	var change := pose != _pose_was and _pose_was not in ["", "ready", "surrender"]
	# (his boots as he showed them, kept off the floor through a change on the ground: the aim doesn't
	# move them)
	var low := _sole_low() if change and _grounded(pose) and _grounded(_pose_was) else -INF
	_reset()
	match pose.trim_suffix("!"):
		"crouch":
			_pose_crouch()
		"wall", "stand":
			_pose_stand()
		"slide":
			_pose_slide(float(s.get("lean", 0.0)))
		"rise", "fall":
			_pose_jump(pose.begins_with("rise"))
		_:
			_pose_run()
	var stun: float = s.get("stun", 0.0)
	if stun > 0.0:  # pitched forward, arms flung out, wobbling
		spine.rotation.x -= 0.5 * stun + 0.12 * sin(stun * 40.0)
		for side in [-1, 1]:
			shoulders[side].rotation.z = side * 0.9 * stun
	rotation.z = -float(s.get("lean", 0.0)) * 0.18  # into a lane change
	if _launch_t >= 0.0:
		# Out of the stance, not in one jump: legs and hips first, then the rest.
		var up := smoothstep(0.0, IDLE_LAUNCH_UPPER, _launch_t)
		_pose_blend(_launch_from, smoothstep(0.0, IDLE_LAUNCH_LEGS, _launch_t), up)
	if change:
		_change_begin(_shown, _change_time(_pose_was, pose), low)
	_pose_was = pose
	# Eased before the aim, so FIRE still brings the gun up level and ahead on top.
	_change_step(delta)
	_change_keep()
	_aim_and_recoil(delta, s.get("aim", false))
	if _launch_t >= 0.0:
		_slide.position.z = maxf(_slide.position.z, _launch_slide * (1.0 - smoothstep(0.0, IDLE_LAUNCH_SLIDE, _launch_t)))
		_mag_at(_launch_mag * (1.0 - smoothstep(0.0, IDLE_LAUNCH_MAG, _launch_t)))
		if _launch_t >= maxf(IDLE_LAUNCH_UPPER, IDLE_LAUNCH_MAG):
			_launch_t = -1.0
	_shrug()
	_apply()

# --- His pose changes eased ---------------------------------------------------------------------
# (user, 2026-10-06: "Cross' animations can be improved by adding easy to the key frames": his pose
# changes in the run.) His pose is picked every frame as it always was, and gameplay never sees any
# of this. When it changes (into and out of a jump, over its top, landing, a slide, cover, the
# stumble, pulling up at the boss or at the run's end, the surrender) he doesn't jump there in one
# frame: the gap between what he showed and the new pose is kept on top of the new pose and eased
# away (his hips and legs first, his body, then his arms). The new pose itself runs underneath from
# the first frame (his stride going on, the stumble's wobble), so nothing waits. See the decision
# log, "CROSS's animations eased".

## How long each change takes (s): x his hips and legs, y his body and head, z his arms. By the pose
## he's going to, a "from>to" first; "stun" the stumble's hit, "unstun" him coming out of it. 0: that
## part isn't changing, so a change it's already in goes on (his stride never stalls over the top of
## a jump or at the hit). Three quarters of the way in under half of it (see _change_ease): the new
## pose reads at once.
const POSE_CHANGE := {
	"rise": Vector3(0.12, 0.14, 0.17),  # the takeoff: his knee up at once
	"rise>fall": Vector3(0.0, 0.0, 0.24),  # over the top: only his arms drift down
	"fall": Vector3(0.12, 0.14, 0.17),
	"run": Vector3(0.12, 0.15, 0.18),  # landing, and back into his stride
	"slide>run": Vector3(0.14, 0.16, 0.2),  # up out of the slide
	"crouch>run": Vector3(0.15, 0.17, 0.2),  # up from behind a box
	"wall>run": Vector3(0.14, 0.16, 0.2),  # off a wall
	"slide": Vector3(0.12, 0.13, 0.16),  # down into it
	"crouch": Vector3(0.15, 0.17, 0.22),  # down on a knee behind a box
	"wall": Vector3(0.15, 0.17, 0.22),  # up against a wall
	"stand": Vector3(0.22, 0.26, 0.3),  # pulling up (the boss standoff, the run's end)
	"stun": Vector3(0.0, 0.07, 0.09),  # the hit: almost at once
	"unstun": Vector3(0.0, 0.14, 0.16),  # back into his stride
	"surrender": Vector3(0.18, 0.22, 0.3),  # down on his knees, hands up
}
## Which part of him each joint is (_all_joints' order): 0 his hips and legs, 1 his body and head,
## 2 his arms.
const CHANGE_PART := [0, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0]
## Through a change on the ground (down onto a knee behind a box and up again, the surrender, the
## slide, pulling up), his boots never go lower than in the pose he's leaving or the one he's going
## to (a hip and a knee half way round put a boot through the floor): his hips lift instead. Not in
## the air or landing (the jump lifts him off the floor: a lift there would pop). SOLE: the lowest
## points of his boot sole (the toe, the ball, the heel), in each foot's flat frame.
const SOLE := [Vector3(0.0, -0.07, -0.23), Vector3(0.0, -0.09, -0.15), Vector3(0.0, -0.09, 0.04)]

## The pose he's in (see _pose_pick; "": none yet; "ready" his stance, which the launch eases out
## of; "surrender": caught for good), and what he showed this frame before the aim (his hips' place
## and every joint's turn, as _pose_snapshot: what a change eases from).
var _pose_was := ""
var _shown: Array = []
## The change under way, each part on its own (see CHANGE_PART): how long since it began (s; -1:
## none), how long it takes; the gap to the new pose as it began (his hips' place, each joint's turn
## in its parent's axes), and his boots' lowest then (-INF: no floor kept).
var _change_t := [-1.0, -1.0, -1.0]
var _change_len := Vector3.ONE
var _change_hips := Vector3.ZERO
var _change_off: Array[Quaternion] = []
var _change_low := -INF
var _change_joints: Array[Node3D] = []


## The pose animate shows this frame, by priority: in cover down on a knee ("crouch") or standing
## at a wall ("wall"), the slide, the jump ("rise", "fall"), standing still, the run; "!" on the
## end while he's stumbling.
func _pose_pick(s: Dictionary) -> String:
	var pose := "run"
	match String(s.get("cover", "")):
		"crouch":
			pose = "crouch"
		"stand":
			pose = "wall"
		_:
			if s.get("sliding", false):
				pose = "slide"
			elif s.get("airborne", false):
				pose = "rise" if s.get("rising", true) else "fall"
			elif _run < 0.05 and float(s.get("run", 0.0)) <= 0.0:
				pose = "stand"  # (not while he's told to run: out of cover he's straight into it, at any frame rate)
	return pose + ("!" if float(s.get("stun", 0.0)) > 0.0 else "")


## How long a change from pose `a` to `b` takes (see POSE_CHANGE).
static func _change_time(a: String, b: String) -> Vector3:
	var from := a.trim_suffix("!")
	var to := b.trim_suffix("!")
	var hit := b.ends_with("!") and not a.ends_with("!")
	if from == to:
		return POSE_CHANGE["stun"] if hit else POSE_CHANGE["unstun"]
	var span: Vector3 = POSE_CHANGE.get(from + ">" + to, POSE_CHANGE[to])
	if a.ends_with("!") != b.ends_with("!"):
		# (the hit, or its end, as the pose changes: his body and arms always move then, as quickly
		# as the hit)
		var st: Vector3 = POSE_CHANGE["stun" if hit else "unstun"]
		for part in [1, 2]:
			if span[part] == 0.0:
				span[part] = st[part]
			elif hit:
				span[part] = minf(span[part], st[part])
	return span


## A change begins, the new pose posed: from `from` (as _pose_snapshot), each part of him over
## `span` (s; 0: that part goes on as it was); `low`, his boots' lowest in what he showed (-INF:
## the floor not kept, see SOLE).
func _change_begin(from: Array, span: Vector3, low: float) -> void:
	var js := _change_list()
	if _change_off.size() != js.size():
		_change_off.resize(js.size())
	if span.x > 0.0:
		_change_hips = (from[0] as Vector3) - hips.position
		_change_low = low
	for i in js.size():
		if span[CHANGE_PART[i]] > 0.0:
			_change_off[i] = (from[i + 1] as Quaternion) * js[i].quaternion.inverse()
	for part in 3:
		if span[part] > 0.0:
			_change_t[part] = 0.0
			_change_len[part] = span[part]


## The change under way, a frame on (`delta` 0: a shot's re-pose, no further on): the gap still to
## go on each part, eased away, on top of the new pose as it is now.
func _change_step(delta: float) -> void:
	var left := Vector3.ZERO
	for part in 3:
		var t: float = _change_t[part]
		if t < 0.0:
			continue
		t += delta
		_change_t[part] = t if t < _change_len[part] else -1.0
		left[part] = 1.0 - _change_ease(t / _change_len[part])
	if left == Vector3.ZERO:
		return
	var keep := left.x > 0.0 and _change_low > -INF
	var low_to := _sole_low() if keep else 0.0  # (the new pose's boots)
	hips.position += _change_hips * left.x
	var js := _change_list()
	for i in js.size():
		var k: float = left[CHANGE_PART[i]]
		if k > 0.0:
			js[i].quaternion = Quaternion.IDENTITY.slerp(_change_off[i], k) * js[i].quaternion
	if keep:
		hips.position.y += maxf(0.0, minf(low_to, _change_low) - _sole_low())


## 0..1 over `u` 0..1, from rest to rest: three quarters of the way by u 0.46, nine tenths by 0.58,
## then settling in (Bollo's quintic, Gears of War's inertialization, starting still).
static func _change_ease(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	var w := 1.0 - x
	return 1.0 - w * w * w * w * (1.0 + 4.0 * x)


## What he shows this frame, before the aim: what the next change eases from.
func _change_keep() -> void:
	var js := _change_list()
	_shown.resize(js.size() + 1)
	_shown[0] = hips.position
	for i in js.size():
		_shown[i + 1] = js[i].quaternion


## His joints (_all_joints), listed once.
func _change_list() -> Array[Node3D]:
	if _change_joints.is_empty():
		_change_joints = _all_joints()
	return _change_joints


## Pose `p` (see _pose_pick) is on the ground (not the jump).
static func _grounded(p: String) -> bool:
	return not (p.begins_with("rise") or p.begins_with("fall"))


## The lowest point of his boot soles (rig units, y; see SOLE).
func _sole_low() -> float:
	var low := INF
	for side in [-1, 1]:
		var an: Node3D = ankles[side]
		var flat := _in_rig(an.get_node(String(an.name) + "Flat") as Node3D)
		for p: Vector3 in SOLE:
			low = minf(low, (flat * p).y)
	return low


## Killed while his legs are part way into a new pose: they're there at once, so his death works his
## fall out from his legs as the pose has them, as it always has (from part way down into a slide or
## up off a knee, his ragdoll could flip a knee or put a hand through the floor); the rest of him it
## carries on from as he showed it. (death_start calls it.) Returns how his hips and legs were shown
## off that ("off": each joint's turn, "hips": their place) and how long they had left to get there
## ("len", s), so his death eases from what was shown onto its own rather than snapping (pose_death);
## empty if they weren't changing.
func _change_drop() -> Dictionary:
	if float(_change_t[0]) < 0.0 or _last_state.is_empty():
		return {}
	var shown := _pose_snapshot()
	var left := maxf(_change_len.x - float(_change_t[0]), DIE_SHOWN_LEAST)
	_change_t[0] = -1.0
	animate(0.0, _last_state)
	var now := _pose_snapshot()
	var off: Array[Quaternion] = []
	for k in range(1, now.size()):
		off.append((shown[k] as Quaternion) * (now[k] as Quaternion).inverse() if CHANGE_PART[k - 1] == 0 else Quaternion.IDENTITY)
	return {"hips": (shown[0] as Vector3) - (now[0] as Vector3), "off": off, "len": left}

# --- Ready under the menu ---------------------------------------------------------------------
# (user: "an active stance, alarmed mode, he checks his gun and he's looking around ... his start
# stance can't be standing still it will need to match the stance he has in this animation"). See
# the decision log, "CROSS ready under the menu". CROSS only: GuardRig has its own animate().

## His ready stance (rig units, radians; the sign rules are at animate): crouched, the hips down,
## back a little, tipped forward and turned toward his rear foot, the spine and chest turning back
## so his shoulders are square to the door; his gaze a touch down (from under his brow).
const IDLE_DROP := 0.075
const IDLE_HIPS_BACK := 0.02
const IDLE_HIPS_TURN := -0.15
const IDLE_HIPS_TIP := -0.08
const IDLE_SPINE := -0.10
const IDLE_CHEST := -0.04
const IDLE_NECK := -0.08
const IDLE_GAZE := -0.08
## His feet (ankles, x and z) planted wide and staggered, the left ahead, the right turned out
## (toe: + to his left); the ball of the foot (in the flat foot's frame) his rear heel lifts about.
const IDLE_FEET := {-1: Vector2(-0.12, -0.15), 1: Vector2(0.15, 0.12)}
const IDLE_TOES := {-1: 0.12, 1: -0.45}
const IDLE_BALL := Vector3(0.0, -0.06, -0.17)
## The pistol (from his chest, in its facing): a compressed low ready, both hands on it in front of
## his belt, the muzzle IDLE_GUN_DIP down (41°: at the floor ahead, never at the camera in front of
## him) and turned IDLE_GUN_YAW (34°) across to his left, canted IDLE_GUN_CANT (+ top to his left), so
## both forearms run into his fists with each wrist only cocked a little toward the little finger, as
## a real pistol grip has it (user: "Check his hand position/rotation it looks a little off": both
## wrists were bent ~90° sideways). Up under his chin for the check (IDLE_CHECK: a little less
## dipped and turned; its roll the R channel scaled, see _idle_roll); lifted a little at the alarm
## (IDLE_ALARM, dipped IDLE_ALARM_DIP less: never pushed, which snapped his shoulder); drawn in low
## for the set.
const IDLE_GUN := Vector3(-0.061, -0.32, -0.49)
const IDLE_GUN_DIP := 0.717
const IDLE_GUN_YAW := 0.598
const IDLE_GUN_CANT := 0.02
const IDLE_CHECK := Vector3(-0.013, -0.139, -0.487)
const IDLE_CHECK_DIP := 0.648
const IDLE_CHECK_YAW := 0.185
const IDLE_ALARM := Vector3(0.0, 0.03, 0.0)
const IDLE_ALARM_DIP := 0.063
const IDLE_SET_GUN := Vector3(-0.07, -0.439, -0.425)
const IDLE_SET_DIP := 0.672
const IDLE_SET_YAW := 0.65
## The check's roll: the R channel times IDLE_ROLL_PRESS (the press check, top to his left: the
## ejection port up) or IDLE_ROLL_MAG (rolled over onto its side, the magazine well toward his left
## hand), plus IDLE_CHECK_ROLL over the whole check; and for the magazine check (from as the gun
## starts to roll over) moved IDLE_MAG_AT, dipped IDLE_MAG_DIP more and turned IDLE_MAG_YAW more.
const IDLE_ROLL_PRESS := 1.311
const IDLE_ROLL_MAG := 1.699
const IDLE_CHECK_ROLL := -0.066
const IDLE_MAG_AT := Vector3(0.051, -0.052, 0.022)
const IDLE_MAG_DIP := -0.044
const IDLE_MAG_YAW := 0.387
## How each hand sits on its forearm (rad; x: the forearm toward the thumb's side of the hand's line,
## the hand cocked toward the little finger; y: toward the palm's side, the hand bent back): the gun
## hand's (taken unrolled: rolling the gun turns the forearm, it doesn't swing the elbow round) and
## the left's, at the ready and in the check. Each elbow goes where that puts it, as near as it can
## (see _reach_clear).
const IDLE_WRIST := Vector2(0.12, 0.32)
const IDLE_WRIST_CHECK := Vector2(0.315, -0.175)
const IDLE_WRIST_L := Vector2(0.138, 0.059)
const IDLE_WRIST_L_CHECK := Vector2(0.286, 0.194)
## Where the elbows may go: an arm raised no more than IDLE_RAISE_MOST (rad from hanging, his chest's
## axes: under SHRUG_FROM, so his collarbones never lift), and the elbow and forearm kept out of his
## vest (his chest's axes: its half-width down to y -0.2 and from y -0.35 down, its front's depth from
## the chest's middle; its top and bottom), the elbow and forearm IDLE_LIMB thick (rig units: the
## arm's own thickness less ~3 cm of give).
const IDLE_RAISE_MOST := 0.885
const IDLE_VEST := Vector3(0.17, 0.23, 0.245)
const IDLE_VEST_Y := Vector2(0.05, -0.55)
const IDLE_LIMB := Vector2(0.015, 0.01)
## The left hand over the slide for the press check (pistol space): its middle at the slide's rear,
## its run (across the slide toward the ejection port) and palm (down onto it).
const IDLE_TOP_AT := Vector3(-0.01, 0.075, 0.04)
const IDLE_TOP_RUN := Vector3(1.0, -0.114, 0.09)
const IDLE_TOP_PALM := Vector3(0.128, -1.0, 0.113)
## The support hand at the ready (pistol space): its fist's middle low on the grip's exposed left
## panel over the gun hand's fingers, thumbs forward; its run IDLE_SUPPORT_CANT below the bore (-: a
## little above it, along the frame) and its palm tipped IDLE_SUPPORT_TIP down onto the panel (the
## support wrist then canted down, IDLE_WRIST_L).
const IDLE_SUPPORT_AT := Vector3(-0.051, -0.037, 0.015)
const IDLE_SUPPORT_CANT := -0.2
const IDLE_SUPPORT_TIP := -0.538
## ...and in the check (pistol axes, from the gun hand's middle): its run canted IDLE_CANT down, its
## palm turned IDLE_PALM back and rolled IDLE_PALM_ROLL down from facing across, following
## IDLE_SUPPORT_FOLLOW of the gun's roll. The most its wrist bends off its forearm (rad): past that
## the hand turns toward the forearm.
const IDLE_SUPPORT := Vector3(-0.044, 0.002, -0.008)
const IDLE_CANT := 0.05
const IDLE_PALM := 0.201
const IDLE_PALM_ROLL := 0.113
const IDLE_SUPPORT_FOLLOW := 0.017
const IDLE_WRIST_MOST := 0.5
## The loop (s), and its breaths and sways (whole numbers of them, so it wraps cleanly).
const IDLE_LOOP := 16.0
const IDLE_BREATHS := 6.0
const IDLE_SWAYS := 2.0
## START: he settles out of whatever he was doing (s; a pulled slide let go faster), then, as the
## opening pan goes round (its progress 0..1), a nod and the sprinter's set: lower, forward, his
## weight on the front foot, the rear heel up.
const IDLE_SETTLE := 0.5
const IDLE_SLIDE_GO := 0.06
const IDLE_NOD_FROM := 0.36
const IDLE_NOD_TO := 0.50
const IDLE_NOD := 0.2
const IDLE_SET_FROM := 0.46
const IDLE_SET_TO := 0.74
const IDLE_SET_DROP := 0.035
const IDLE_SET_AHEAD := -0.07
const IDLE_SET_LEAN := -0.07
const IDLE_SET_HEEL := 0.3
## Into the run: the stride's phase he starts at (the rear, right, leg drives through first), and
## how long his legs and the rest of him take to leave the stance (s); the slide and the magazine
## home.
const IDLE_LAUNCH_PHASE := 1.7
const IDLE_LAUNCH_LEGS := 0.15
const IDLE_LAUNCH_UPPER := 0.30
const IDLE_LAUNCH_SLIDE := 0.08
const IDLE_LAUNCH_MAG := 0.15
## The magazine dropped into his palm in the check and pushed home (user, 2026-10-05: "The optional
## extras sound great, add them"): a magazine part hidden in the grip, so the pistol looks the same
## otherwise.
const IDLE_MAG_DROP := true
const MAG_RAKE := -0.25

## The loop, a channel at a time: [t (s), value, and how the move arriving at it eases (see
## IDLE_EASE; 0 or none: a move; 1 snap: out of a hold fast; 2 slap: fast into the key; 4: the hold
## arriving at it a moving hold, creeping on instead of stopping)]. G gaze yaw (+ his
## left), P gaze pitch (+ up), B torso yaw (following the eyes), Tz head tilt (+ right ear up: the
## listen), D extra sink (the startle), A the gun pushed toward the threat, H the gun up for the
## check, R its roll (+ top to his left, the ejection port up), Y its yaw, X its extra dip, O pushed
## out, L the left hand (0 support, 1 over the slide, 2 support, 3 cupped under the grip, 4 support
## again), S the slide pulled back, M the magazine out, Kd the hand dropped for the slap, J the slap's
## jolt, Ab the breath's size, W his weight onto the front foot.
## 1-5 s the gun check (a press check, then the magazine slapped home); 5.4-9 s the room (the
## window, a sweep to the high corner); 10 s the alarm over his right shoulder, the listen; 13-16 s
## his weight forward, eyes to the floor ahead.
const IDLE_KEYS := {
	"G": [[0.0, 0.0], [1.00, 0.0], [1.50, 0.12], [2.85, 0.12], [3.30, 0.22], [4.50, 0.22], [4.66, 0.0, 1],
		[5.40, 0.0], [5.65, 1.10, 1], [6.15, 1.10], [6.40, 0.95], [6.70, 0.95, 4], [7.80, -0.80], [8.70, -0.80],
		[9.15, 0.0], [10.00, 0.0], [10.20, -1.52, 1], [10.42, -1.45], [11.50, -1.45], [12.00, -0.35],
		[12.50, -0.35, 4], [12.85, 0.0], [13.60, 0.0], [14.20, 0.30], [14.80, 0.30], [15.40, 0.0], [16.0, 0.0]],
	"P": [[0.0, -0.08], [1.00, -0.08], [1.50, -0.62], [2.05, -0.62], [2.25, -0.70], [2.65, -0.70],
		[2.85, -0.62], [3.40, -0.62], [3.56, -0.75], [4.10, -0.75], [4.50, -0.62], [4.66, 0.0, 1], [4.90, -0.08],
		[5.40, -0.08], [5.65, -0.05, 1], [6.15, -0.05], [6.40, -0.18], [6.70, -0.18], [7.80, 0.22], [8.70, 0.22],
		[9.15, -0.08], [10.00, -0.08], [10.20, -0.02, 1], [11.50, -0.02], [12.00, -0.10], [12.85, -0.08],
		[13.60, -0.08], [14.20, -0.22], [14.80, -0.22], [15.40, -0.08], [16.0, -0.08]],
	"B": [[0.0, 0.0], [1.00, 0.0], [1.50, 0.08], [4.55, 0.08], [5.00, 0.0], [5.47, 0.0], [5.80, 0.42],
		[6.20, 0.42], [6.45, 0.36], [6.78, 0.36, 4], [7.88, -0.30], [8.75, -0.30], [9.20, 0.0], [10.04, 0.0],
		[10.30, -0.55, 1], [11.50, -0.55], [12.05, -0.12], [12.50, -0.12, 4], [12.90, 0.0], [13.70, 0.0],
		[14.30, 0.10], [14.80, 0.10], [15.45, 0.0], [16.0, 0.0]],
	"Tz": [[0.0, 0.0], [10.45, 0.0], [10.75, 0.07], [11.40, 0.07], [11.70, 0.0], [16.0, 0.0]],
	"D": [[0.0, 0.0], [10.00, 0.0], [10.06, 0.012, 1], [10.25, 0.035], [11.50, 0.035], [12.10, 0.0], [16.0, 0.0]],
	"A": [[0.0, 0.0], [10.02, 0.0], [10.20, 1.0, 1], [11.50, 1.0], [12.10, 0.0], [16.0, 0.0]],
	"H": [[0.0, 0.0], [1.00, 0.0], [1.50, 1.0], [4.50, 1.0], [5.00, 0.0], [16.0, 0.0]],
	"R": [[0.0, 0.0], [1.00, 0.0], [1.50, 0.6], [2.85, 0.6], [3.30, -0.95], [4.50, -0.95], [5.00, 0.0], [16.0, 0.0]],
	"Y": [[0.0, 0.0], [1.00, 0.0], [1.50, 0.25], [2.85, 0.25], [3.30, 0.10], [4.50, 0.10], [5.00, 0.0], [16.0, 0.0]],
	"X": [[0.0, 0.0], [2.85, 0.0], [3.30, 0.05], [4.50, 0.05], [5.00, 0.0], [16.0, 0.0]],
	"O": [[0.0, 0.0], [2.85, 0.0], [3.25, 0.06], [4.50, 0.06], [5.00, 0.0], [16.0, 0.0]],
	"L": [[0.0, 0.0], [1.50, 0.0], [1.85, 1.0], [2.80, 1.0], [3.15, 2.0], [3.17, 2.0], [3.40, 3.0],
		[4.50, 3.0], [4.90, 4.0], [16.0, 4.0]],
	"S": [[0.0, 0.0], [1.85, 0.0], [2.05, 0.022, 1], [2.65, 0.022], [2.80, 0.0], [16.0, 0.0]],
	"M": [[0.0, 0.0], [3.40, 0.0], [3.56, 0.045, 1], [4.10, 0.045], [4.28, 0.010], [4.45, 0.010],
		[4.49, 0.0, 2], [16.0, 0.0]],
	"Kd": [[0.0, 0.0], [4.28, 0.0], [4.40, 0.06, 1], [4.49, 0.0, 2], [16.0, 0.0]],
	"J": [[0.0, 0.0], [4.47, 0.0], [4.50, 0.012, 1], [4.67, 0.0], [16.0, 0.0]],
	"Ab": [[0.0, 1.0], [10.02, 1.0], [10.25, 0.25], [11.50, 0.25], [11.90, 1.6], [13.10, 1.6], [13.90, 1.0], [16.0, 1.0]],
	"W": [[0.0, 0.0], [13.40, 0.0], [14.20, 1.0], [15.00, 1.0], [15.70, 0.0], [16.0, 0.0]],
}
## How the keys ease (user, 2026-10-06: "adding ease to the key frames"; every move was a smoothstep
## from one dead stop to the next). A move eases out of a stop and into the next fuller, IDLE_EASE of
## the way from smoothstep to smootherstep (no jolt at either end: slower away, a longer landing,
## quicker between); a snap leaves its hold from rest but briskly (fastest a quarter of the way) and
## lands long; a slap still drives into its key. The motion carries on through a key between a lower
## and a higher one, and through a moving hold (kind 4: its ends IDLE_CREEP of the smaller move either
## side apart about the key), at most IDLE_CARRY of the slower move's speed (never past a key). On
## the IDLE_LIVE channels any other hold after a move drifts on IDLE_DRIFT of that move, easing to rest
## (never the loop's last, so it wraps), and a snap into a hold carries IDLE_SNAP_KEEP of its speed on
## into it, overshooting and settling back over about IDLE_SNAP_SETTLE s; each times the channel's
## weight (his torso, heavier, half). IDLE_STOPS keep the old eases, stopping at every key: his left
## hand's holds (hurried, his reach swings his shoulder round) and the slide, the magazine and the
## slap (the check's sounds land on them).
const IDLE_EASE := 1.0
const IDLE_CARRY := 0.75
const IDLE_CREEP := 0.2
const IDLE_DRIFT := 0.04
const IDLE_SNAP_KEEP := 0.5
const IDLE_SNAP_SETTLE := 0.07
const IDLE_LIVE := {"G": 1.0, "P": 1.0, "B": 0.5, "Tz": 1.0, "D": 1.0, "A": 1.0, "W": 1.0}
const IDLE_STOPS := ["L", "S", "M", "Kd", "J"]
## Overlapping action (s behind): his spine and then his hips taking the turn after his chest (B);
## the pistol (IDLE_LAGGED: its lift, roll, turn, dip and push out) following his eyes.
const IDLE_SPINE_LAG := 0.04
const IDLE_HIPS_LAG := 0.09
const IDLE_GUN_LAG := 0.05
const IDLE_LAGGED := ["H", "R", "Y", "X", "O"]
## The most his head and neck turn off his body together (rad, easing into it over the last
## IDLE_NECK_KNEE): the alarm's snap, his eyes there before his body has come round, waits for it.
const IDLE_NECK_MOST := 1.10
const IDLE_NECK_KNEE := 0.3
## The gun check's sounds (user: "add them"), at their moments in the loop (s): the slide eased back
## and let home, the magazine out into his palm, the slap.
const IDLE_SOUNDS := [[1.85, "slide_back"], [2.75, "slide_home"], [3.40, "mag_out"], [4.46, "mag_slap"]]
## A moment of his gun check with a sound (its name: see IDLE_SOUNDS), as the loop passes it.
signal idle_beat(sound: String)

## Where every channel settles once START is pressed: eyes on the door, the gun at the ready,
## breathing a little harder (psyched up).
const IDLE_GO := {"G": 0.0, "P": IDLE_GAZE, "B": 0.0, "Tz": 0.0, "D": 0.0, "A": 0.0, "H": 0.0, "R": 0.0,
	"Y": 0.0, "X": 0.0, "O": 0.0, "M": 0.0, "Kd": 0.0, "J": 0.0, "Ab": 1.3, "W": 0.0}

## The stance's clocks (s): the loop's, the breath's (it keeps going after START) and since START
## (-1: not pressed); the opening pan's progress (-1: not started); whether he's in the stance (the
## run then grows out of it), and this frame's channels.
var _idle_t := 0.0
var _idle_b := 0.0
var _idle_go := -1.0
var _idle_pan := -1.0
var _idle_on := false
var _idle_c := {}
## Each eased channel's keys as its curve passes them (_idle_bake), worked out the first time asked.
static var _idle_baked := {}
static var _idle_baked_of := {}
## Into the run: how long since he left the stance (s; -1: not leaving it), the stance he left, and
## the slide and magazine as they were.
var _launch_t := -1.0
var _launch_from: Array = []
var _launch_slide := 0.0
var _launch_mag := 0.0
## His pistol, and its magazine (only with IDLE_MAG_DROP) and how far it's out.
var _pistol: Node3D
var _mag: Node3D
var _mag_out := 0.0


## In his ready stance this frame: the loop on (`pan` < 0), or START pressed and the opening pan
## `pan` of the way round (settled, then the nod and the set).
func _animate_ready(delta: float, pan: float) -> void:
	_run = 0.0
	_phase = IDLE_LAUNCH_PHASE
	_launch_t = -1.0
	_idle_pan = pan
	if pan < 0.0:
		_idle_go = -1.0
		var was := _idle_t
		_idle_t = fmod(_idle_t + delta, IDLE_LOOP)
		if delta > 0.0:
			_idle_sounds(was, _idle_t)
	else:
		_idle_go = 0.0 if _idle_go < 0.0 else _idle_go + delta  # (the loop's clock stops: no new beat starts)
	_idle_b = fmod(_idle_b + delta, IDLE_LOOP)
	_pose_ready_all(delta)


func _pose_ready_all(delta: float) -> void:
	var c := _idle_values()
	_idle_c = c
	_reset()
	_pose_ready_body(c)
	_aim_and_recoil(delta, false)  # (the kick and the flash settled, as ever)
	_idle_arms(c)
	_apply()  # (no _shrug: both arms are posed by _reach, which lifts its own collarbone)
	_idle_on = true


## The check's sounds the loop passed this frame, from `a` to `b` s (across the wrap too).
func _idle_sounds(a: float, b: float) -> void:
	for k in IDLE_SOUNDS:
		var t: float = k[0]
		if (k[1] == "mag_out" and not IDLE_MAG_DROP) or not (a < t and t <= b or b < a and (t > a or t <= b)):
			continue
		idle_beat.emit(k[1])


## The set the opening pan ends on, as the pose he's built in: Retry and the bots (no menu, no pan)
## spring into the run from it, as the pan's end does.
func pose_set() -> void:
	_idle_t = 0.0
	_idle_b = 0.0
	_idle_go = IDLE_SETTLE
	_idle_pan = 1.0
	_run = 0.0
	_phase = IDLE_LAUNCH_PHASE
	_pose_ready_all(0.0)


## Channel `k` at `t` s into the loop (either side of it: a lagged channel's moment).
static func _idle_at(k: String, t: float) -> float:
	t = fposmod(t, IDLE_LOOP)
	if k in IDLE_STOPS:
		return _idle_stopping(IDLE_KEYS[k], t)
	if not is_same(_idle_baked_of, IDLE_KEYS):
		# (the keys were changed under it: a live script reload keeps static vars)
		_idle_baked = {}
		_idle_baked_of = IDLE_KEYS
	if not _idle_baked.has(k):
		_idle_baked[k] = _idle_bake(IDLE_KEYS[k], IDLE_LIVE.get(k, 0.0))
	return _idle_curve(_idle_baked[k], t)


## How far a move between two stops has gone `u` of its time (IDLE_STOPS: `kind` as in IDLE_KEYS).
static func _idle_ease(u: float, kind: int) -> float:
	match kind:
		1:
			return 1.0 - (1.0 - u) * (1.0 - u)
		2:
			return u * u
		_:
			return u * u * (3.0 - 2.0 * u)


## A channel stopping at every key (IDLE_STOPS) at `t`.
static func _idle_stopping(keys: Array, t: float) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if t < b[0]:
			var a: Array = keys[i - 1]
			var u := (t - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(a[1], b[1], _idle_ease(u, _idle_kind(b)))
	return keys[keys.size() - 1][1]


## How the move arriving at a key eases (see IDLE_KEYS).
static func _idle_kind(key: Array) -> int:
	return int(key[2]) if key.size() > 2 else 0


## A channel's keys (see IDLE_KEYS) as its eased curve passes them, its holds drifting and its snaps
## settling `live` (IDLE_LIVE; 0: not at all): each [t, value, speed (per s), a snap's overshoot (per
## s), its kind, whether a hold (not a moving one) follows it].
static func _idle_bake(keys: Array, live: float) -> Array:
	var out := []
	var n := keys.size()
	for i in n:
		var hold := i < n - 1 and _idle_kind(keys[i + 1]) != 4 and float(keys[i + 1][1]) == float(keys[i][1])
		out.append([float(keys[i][0]), _idle_key(keys, i, live), _idle_slope(keys, i, live),
				_idle_overshoot(keys, i, live), _idle_kind(keys[i]), hold])
	return out


## An eased channel's value at `t` (its keys as _idle_bake has them). A pure function of `t`: the same
## moment, the same pose.
static func _idle_curve(baked: Array, t: float) -> float:
	var n := baked.size()
	if t <= float(baked[0][0]):
		return baked[0][1]
	if t >= float(baked[n - 1][0]):
		return baked[n - 1][1]
	var i := 1
	while t >= float(baked[i][0]):
		i += 1
	var a: Array = baked[i - 1]
	var b: Array = baked[i]
	var h := float(b[0]) - float(a[0])
	var u := (t - float(a[0])) / h
	if int(b[4]) == 2:
		return lerpf(a[1], b[1], u * u)  # (a slap: from rest, driven into its key)
	if a[5]:
		# A hold: drifting on, easing to rest; after a snap, overshooting and settling back too.
		var over: float = a[3]
		var tau := u * h
		return _idle_move(u, a[1], b[1], (float(a[2]) - over) * h, 0.0, 0) \
				+ over * tau * exp(-tau / IDLE_SNAP_SETTLE) * (1.0 - u * u * (3.0 - 2.0 * u))
	return _idle_move(u, a[1], b[1], float(a[2]) * h, float(b[2]) * h, int(b[4]))


## A move `u` (0..1) of its time from `va` to `vb`, leaving at `ma` and arriving at `mb` (each per its
## whole time): eased IDLE_EASE of the way from the cubic's (smoothstep's) to the quintic's
## (smootherstep's: no jolt at either end); a snap (`kind` 1) out from rest briskly instead.
static func _idle_move(u: float, va: float, vb: float, ma: float, mb: float, kind: int) -> float:
	var v := 1.0 - u
	var u2 := u * u
	var u3 := u2 * u
	var e := lerpf(u2 * (3.0 - 2.0 * u), u3 * (10.0 + u * (6.0 * u - 15.0)), IDLE_EASE)
	if kind == 1:
		e = 1.0 - v * v * v * v * (1.0 + 4.0 * u)
	var a := lerpf(u * v * v, u - u3 * (6.0 + u * (3.0 * u - 8.0)), IDLE_EASE)
	var b := lerpf(-u2 * v, -u3 * (4.0 + u * (3.0 * u - 7.0)), IDLE_EASE)
	return va + (vb - va) * e + ma * a + mb * b


## Key `i`'s value as the curve passes it: a moving hold's ends (kind 4) IDLE_CREEP of the smaller
## move either side apart about the key, the way he's going; the end of any other hold after a move
## drifted on IDLE_DRIFT of that move, times `live` (never the loop's last key, so it wraps).
static func _idle_key(keys: Array, i: int, live: float) -> float:
	var n := keys.size()
	var v: float = keys[i][1]
	if i <= 0 or i >= n - 1:
		return v
	var j := i if _idle_kind(keys[i + 1]) == 4 else (i - 1 if _idle_kind(keys[i]) == 4 else -1)
	if j >= 1 and j + 2 < n:
		var before := v - float(keys[j - 1][1])
		var after := float(keys[j + 2][1]) - v
		if before * after <= 0.0:
			return v
		var c := IDLE_CREEP * signf(after) * minf(absf(before), absf(after))
		return v - c / 2.0 if j == i else v + c / 2.0
	if live <= 0.0 or float(keys[i - 1][1]) != v:
		return v
	var k := i - 1
	while k > 0 and float(keys[k - 1][1]) == v:
		k -= 1
	if k == 0:
		return v
	return v + live * IDLE_DRIFT * (v - float(keys[k - 1][1]))


## How fast a channel passes key `i` (per s): through a key between a lower and a higher one, or a
## moving hold's, as fast as the moves either side allow (Fritsch-Carlson's slope, at most IDLE_CARRY
## of the slower: never past either key); into another hold, its drift and a snap's overshoot; nowhere
## else (a turning point, a hold's end, the loop's ends, either side of a slap).
static func _idle_slope(keys: Array, i: int, live: float) -> float:
	var n := keys.size()
	if i <= 0 or i >= n - 1 or _idle_kind(keys[i]) == 2 or _idle_kind(keys[i + 1]) == 2:
		return 0.0
	var creep := _idle_kind(keys[i]) == 4 or _idle_kind(keys[i + 1]) == 4
	var a1: float = keys[i][1]
	if not creep and float(keys[i - 1][1]) == a1:
		return 0.0
	var h0 := float(keys[i][0]) - float(keys[i - 1][0])
	var h1 := float(keys[i + 1][0]) - float(keys[i][0])
	var v1 := _idle_key(keys, i, live)
	var d1 := (_idle_key(keys, i + 1, live) - v1) / h1
	if not creep and float(keys[i + 1][1]) == a1:
		return 2.0 * d1 + _idle_overshoot(keys, i, live)
	var d0 := (v1 - _idle_key(keys, i - 1, live)) / h0
	if d0 * d1 <= 0.0:
		return 0.0
	var w0 := 2.0 * h1 + h0
	var w1 := h1 + 2.0 * h0
	var m := (w0 + w1) / (w0 / d0 + w1 / d1)
	return signf(m) * minf(absf(m), IDLE_CARRY * minf(absf(d0), absf(d1)))


## How fast (per s) a snap into a hold at key `i` carries on into it, to overshoot and settle back
## (0: no live snap into a hold).
static func _idle_overshoot(keys: Array, i: int, live: float) -> float:
	if live <= 0.0 or i <= 0 or i >= keys.size() - 1 or _idle_kind(keys[i]) != 1 \
			or _idle_kind(keys[i + 1]) == 4 or float(keys[i + 1][1]) != float(keys[i][1]):
		return 0.0
	return live * IDLE_SNAP_KEEP * (float(keys[i][1]) - _idle_key(keys, i - 1, live)) \
			/ (float(keys[i][0]) - float(keys[i - 1][0]))


## Every channel now (the pistol's IDLE_GUN_LAG behind his eyes; "Bs" and "Bh" the turn as his spine
## and hips take it, behind his chest); after START, eased to where it settles (a pulled slide let go
## first); "w" how far settled, "set" how far into the set, "nod" the nod.
func _idle_values() -> Dictionary:
	var c := {}
	for k in IDLE_KEYS:
		c[k] = _idle_at(k, _idle_t - (IDLE_GUN_LAG if k in IDLE_LAGGED else 0.0))
	c["Bs"] = _idle_at("B", _idle_t - IDLE_SPINE_LAG)
	c["Bh"] = _idle_at("B", _idle_t - IDLE_HIPS_LAG)
	var w := 0.0
	if _idle_go >= 0.0:
		w = smoothstep(0.0, IDLE_SETTLE, _idle_go)
		c["S"] = float(c["S"]) * (1.0 - smoothstep(0.0, IDLE_SLIDE_GO, _idle_go))
		for k in IDLE_GO:
			c[k] = lerpf(c[k], IDLE_GO[k], w)
		for k in ["Bs", "Bh"]:
			c[k] = lerpf(c[k], IDLE_GO["B"], w)
	c["w"] = w
	if not IDLE_MAG_DROP:
		c["M"] = 0.0
	var pan := _idle_pan
	c["set"] = smoothstep(IDLE_SET_FROM, IDLE_SET_TO, pan) if pan >= 0.0 else 0.0
	c["nod"] = sin(PI * clampf((pan - IDLE_NOD_FROM) / (IDLE_NOD_TO - IDLE_NOD_FROM), 0.0, 1.0)) if pan >= 0.0 else 0.0
	return c


## His body in the stance: breathing and swaying a little, a turn spread down hips, spine and chest
## (the eyes lead: head and neck take the rest of the gaze), his gaze held through the lean (as the
## boss's brace does), his feet planted.
func _pose_ready_body(c: Dictionary) -> void:
	var st: float = c["set"]
	var b := float(c["Ab"]) * sin(TAU * IDLE_BREATHS * _idle_b / IDLE_LOOP)
	var sway := 0.012 * sin(TAU * IDLE_SWAYS * _idle_b / IDLE_LOOP)
	# (the turn as his chest, spine and hips each take it: the chest first)
	var turn := 0.5 * float(c["B"]) + 0.3 * float(c["Bs"]) + 0.2 * float(c["Bh"])
	var gaze: float = c["G"]
	var pitch: float = float(c["P"]) - IDLE_NOD * float(c["nod"])
	var sink: float = c["D"]
	var weight: float = c["W"]
	hips.position = Vector3(lerpf(sway, -0.02, st) - 0.015 * weight,
			_hip_y - IDLE_DROP - sink - IDLE_SET_DROP * st + 0.004 * b,
			IDLE_HIPS_BACK - 0.03 * weight + IDLE_SET_AHEAD * st)
	hips.rotation = Vector3(IDLE_HIPS_TIP - 0.02 * sink / 0.035, IDLE_HIPS_TURN + 0.2 * float(c["Bh"]), 0.0)
	spine.rotation = Vector3(IDLE_SPINE + IDLE_SET_LEAN * st, -0.55 * IDLE_HIPS_TURN + 0.3 * float(c["Bs"]), 0.0)
	chest.rotation = Vector3(IDLE_CHEST + 0.018 * b - 0.02 * st, -0.45 * IDLE_HIPS_TURN + 0.5 * float(c["B"]), 0.0)
	# (his head and neck never more than IDLE_NECK_MOST off his body: turned faster than it follows,
	# his eyes wait for it)
	var off := _idle_soft(gaze - turn, IDLE_NECK_MOST, IDLE_NECK_KNEE)
	neck.rotation = Vector3(IDLE_NECK + 0.3 * minf(0.0, pitch - IDLE_GAZE), 0.3 * off, 0.0)
	head.rotation = Vector3(pitch - (hips.rotation.x + spine.rotation.x + chest.rotation.x + neck.rotation.x),
			0.7 * off, float(c["Tz"]))
	for side in [-1, 1]:
		var f: Vector2 = IDLE_FEET[side]
		var toe: float = IDLE_TOES[side]
		_plant_ball(side, Vector3(f.x, (_ankle_rest[side] as Vector3).y, f.y), toe, IDLE_SET_HEEL * st if side > 0 else 0.0)


## `x` held within `most` either way, easing into it from `knee` short of it (unchanged short of that).
static func _idle_soft(x: float, most: float, knee: float) -> float:
	var from := most - knee
	return x if absf(x) <= from else signf(x) * (from + knee * tanh((absf(x) - from) / knee))


## A foot planted (the ankle where it stands flat, turned out by `toe`), its heel lifted `heel` rad
## about the ball of the foot, which stays where it stood.
func _plant_ball(side: int, ankle_flat: Vector3, toe: float, heel: float) -> void:
	var turn := Basis(Vector3.UP, toe)
	if heel == 0.0:
		_plant(side, ankle_flat, turn * Vector3.FORWARD, toe)
		return
	var lifted := turn * Basis(Vector3.RIGHT, -heel)
	_plant(side, ankle_flat + turn * IDLE_BALL - lifted * IDLE_BALL, turn * Vector3.FORWARD, toe)
	var an: Node3D = ankles[side]
	var flat := an.get_node(String(an.name) + "Flat") as Node3D
	an.basis = _in_rig(knees[side]).basis.inverse() * lifted * flat.basis.inverse()


## Where his pistol goes in the stance (rig space): with his chest's facing (its turn only), its
## barrel's dip set in the world, so it stays pointed at the floor whatever his lean or breath.
func idle_gun(c: Dictionary) -> Transform3D:
	var ch := _in_rig(chest)
	var back := ch.basis.z
	var facing := Basis(Vector3.UP, atan2(back.x, back.z))
	var h: float = c["H"]
	var a: float = c["A"]
	var st: float = c["set"]
	# into the magazine check: from as the press check's roll (R 0.6) starts over to the other side (-0.95)
	var mg := clampf((0.6 - float(c["R"])) / 1.55, 0.0, 1.0) * h
	var off := IDLE_GUN.lerp(IDLE_CHECK, h) + IDLE_MAG_AT * mg + IDLE_ALARM * a + Vector3(0.6, 0.0, -1.0) * float(c["O"])
	off = off.lerp(IDLE_SET_GUN, st)
	var dip := lerpf(IDLE_GUN_DIP, IDLE_CHECK_DIP, h) + IDLE_MAG_DIP * mg + float(c["X"]) - IDLE_ALARM_DIP * a
	dip = lerpf(dip, IDLE_SET_DIP, st)
	var yaw := lerpf(IDLE_GUN_YAW, IDLE_CHECK_YAW, h) + IDLE_MAG_YAW * mg + float(c["Y"])
	yaw = lerpf(yaw, IDLE_SET_YAW, st)
	var at := ch.origin + facing * off + Vector3.UP * float(c["J"])
	return Transform3D(facing * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -dip) * Basis(Vector3.BACK, _idle_roll(c)), at)


## The gun's roll about its barrel in the stance (rad, + top to his left): canted at the ready, the R
## channel scaled in the check.
static func _idle_roll(c: Dictionary) -> float:
	var r: float = c["R"]
	var h: float = c["H"]
	return IDLE_GUN_CANT * (1.0 - h) + r * (IDLE_ROLL_PRESS if r > 0.0 else IDLE_ROLL_MAG) + IDLE_CHECK_ROLL * h


## Both hands on the pistol: the right holding it where it goes; the left in its hold, moving between
## holds hand-first (the hand's place and turn blended, the arm reaching for that), settled straight
## back onto the grip after START (a check caught halfway is broken off going forward, never played
## back through the other holds). Each elbow where its forearm runs into the hand, clear of his vest
## and under the shrug (_reach_clear).
func _idle_arms(c: Dictionary) -> void:
	var ch := _in_rig(chest)
	var gun := idle_gun(c)
	var pl := _pistol.transform
	var wb := gun.basis * pl.basis.orthonormalized().inverse()
	var at := gun.origin - wb * pl.origin
	var h: float = c["H"]
	# (the elbow from the gun hand as it would be unrolled: rolling the gun turns the forearm, it
	# doesn't swing the elbow round)
	var wb0 := gun.basis * Basis(Vector3.BACK, -_idle_roll(c)) * pl.basis.orthonormalized().inverse()
	_reach_clear(1, Transform3D(wb, at), _fore_at(1, wb0, at, IDLE_WRIST.lerp(IDLE_WRIST_CHECK, h)))
	var hold: float = c["L"]
	if hold >= 4.0:
		hold = 0.0  # (4 is the support hold again: the loop wraps onto 0)
	var i := clampi(int(floor(hold)), 0, 3)
	var f := clampf(hold - i, 0.0, 1.0)
	var lh := _left_hold(i, c, ch)
	if f > 0.0001:
		lh = _hold_lerp(lh, _left_hold(i + 1, c, ch), f)
	var w: float = c["w"]
	if w > 0.0001 and not (f <= 0.0001 and i % 2 == 0):
		lh = _hold_lerp(lh, _left_hold(0, c, ch), w)
	_left_arm(lh, IDLE_WRIST_L.lerp(IDLE_WRIST_L_CHECK, h))
	_slide.position.z = maxf(_slide.position.z, float(c["S"]))
	_mag_at(float(c["M"]))


## Two hand holds [the hand's turn, where its middle goes] blended (the turn slerped).
static func _hold_lerp(a: Array, b: Array, f: float) -> Array:
	var q := Quaternion(a[0] as Basis).slerp(Quaternion(b[0] as Basis), f)
	return [Basis(q), (a[1] as Vector3).lerp(b[1], f)]


## The left hand's hold `state` on the pistol where it is now: [the hand's turn, where its middle
## goes] (rig space). 0, 2: support (at the ready its fist low on the grip's left panel over the gun
## hand's fingers; in the check alongside it); 1: over the slide's rear, palm down, riding it back;
## 3: cupped under the magazine's foot, dropped for the slap.
func _left_hold(state: int, c: Dictionary, ch: Transform3D) -> Array:
	var pr := _in_rig(_pistol)
	var pb := pr.basis.orthonormalized()
	var at: Vector3
	var run: Vector3
	var palm: Vector3
	match state:
		1:
			at = pr * (IDLE_TOP_AT + Vector3(0.0, 0.0, float(c["S"])))
			run = pb * IDLE_TOP_RUN
			palm = pb * IDLE_TOP_PALM
		3:
			var axis := Basis(Vector3.RIGHT, MAG_RAKE) * Vector3.DOWN
			var base := Vector3(0.0, -0.05, 0.012) + axis * (0.058 + float(c["M"]) + 0.03)
			at = pr * base + Vector3.DOWN * float(c["Kd"])
			palm = -(pb * axis).normalized()
			run = at - _in_rig(shoulders[-1]).origin  # (on from where his forearm comes: below)
		_:
			var h: float = c["H"]
			var r_run := pb * Vector3(0.0, -sin(IDLE_SUPPORT_CANT), -cos(IDLE_SUPPORT_CANT))
			var r_palm := pb * Vector3(cos(IDLE_SUPPORT_TIP), sin(IDLE_SUPPORT_TIP), 0.0)
			var at_ready := [_frame(r_run, r_palm) * _frame(_hand_run[-1], _hand_palm[-1]).inverse(), pr * IDLE_SUPPORT_AT]
			if h <= 0.0001:
				return at_ready
			var wr := _in_rig(wrists[1])
			var k_run := pb * Vector3(0.0, -sin(IDLE_CANT), -cos(IDLE_CANT))
			var k_palm := (pb * Vector3(cos(IDLE_PALM), 0.0, sin(IDLE_PALM))).rotated(k_run.normalized(),
					IDLE_PALM_ROLL + (1.0 - IDLE_SUPPORT_FOLLOW) * (_idle_roll(c) - IDLE_GUN_CANT * (1.0 - h)))
			var in_check := [_frame(k_run, k_palm) * _frame(_hand_run[-1], _hand_palm[-1]).inverse(),
					wr * (_hand_mid[1] as Vector3) + pb * IDLE_SUPPORT]
			return _hold_lerp(at_ready, in_check, h)
	return [_frame(run, palm) * _frame(_hand_run[-1], _hand_palm[-1]).inverse(), at]


## The left arm reaching for a hold (its elbow as _reach_clear puts it, its hand set `off` its
## forearm as IDLE_WRIST_L), its wrist kept within IDLE_WRIST_MOST of its forearm: past that the hand
## turns toward the forearm.
func _left_arm(lh: Array, off: Vector2) -> void:
	var raw: Basis = lh[0]
	var at: Vector3 = lh[1]
	var mid := _hand_mid[-1] as Vector3
	var hand := raw
	for k in 4:
		var wat := at - hand * mid
		_reach_clear(-1, Transform3D(hand, wat), _fore_at(-1, hand, wat, off))
		if k == 3:
			break
		# (each time from the hold itself, toward the forearm as the last reach left it: not on top
		# of a first reach that may have had nowhere allowed to put the elbow, whose forearm can
		# jump from one frame to the next)
		var fore := (_in_rig(wrists[-1]).origin - _in_rig(elbows[-1]).origin).normalized()
		var r := (raw * (_hand_run[-1] as Vector3)).normalized()
		var bend := fore.angle_to(r)
		var want := raw if bend <= IDLE_WRIST_MOST else Basis(r.cross(fore).normalized(), bend - IDLE_WRIST_MOST) * raw
		if want.is_equal_approx(hand):
			break
		hand = want


## Where `side`'s elbow would best go (rig space) for its forearm to run into the hand `hand` (its
## wrist joint at `at`), set off `off` (see IDLE_WRIST): the forearm's length back along that line.
func _fore_at(side: int, hand: Basis, at: Vector3, off: Vector2) -> Vector3:
	var run := (hand * (_hand_run[side] as Vector3)).normalized()
	var palm := (hand * (_hand_palm[side] as Vector3)).normalized()
	var thumb := (side * run.cross(palm)).normalized()
	var fore := (run + thumb * tan(off.x) + palm * tan(off.y)).normalized()
	return at - fore * (wrists[side] as Node3D).position.length()


## `side`'s arm reaching for `target` (the wrist joint's place and the hand's turn), its forearm
## running as near the line from `want` (where its elbow would best be, rig space) as it can with the
## arm raised no more than IDLE_RAISE_MOST and the elbow and forearm clear of his vest: round the
## circle the elbow can be on (about the shoulder-to-wrist line), the least of (the forearm's angle
## off that line)^2 + 1e5 (how badly it breaks those)^2, on a ring of 24 and then narrowed down. (Soft,
## so the elbow slides along the edge of what's allowed rather than jumping.)
func _reach_clear(side: int, target: Transform3D, want: Vector3) -> void:
	var chi := _in_rig(chest).orthonormalized().affine_inverse()
	var s := chi * (_in_rig(clavicles[side]) * (shoulders[side] as Node3D).position)
	var w := chi * target.origin
	var fore := (w - chi * want).normalized()
	var l1 := (elbows[side] as Node3D).position.length()
	var l2 := (wrists[side] as Node3D).position.length()
	var d := w - s
	var n := clampf(d.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.995)
	var u := d.normalized()
	var along := (l1 * l1 - l2 * l2 + n * n) / (2.0 * n)
	var r := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var c := s + u * along
	var v1 := chi * want - s
	v1 -= u * v1.dot(u)
	if v1.length() < 0.001:
		v1 = Vector3.DOWN - u * Vector3.DOWN.dot(u)
	v1 = v1.normalized()
	var v2 := u.cross(v1)
	var best := 0.0
	var least := INF
	for k in 24:
		var phi := -PI + TAU * k / 24.0
		var f := _elbow_cost(s, c + r * (v1 * cos(phi) + v2 * sin(phi)), w, fore)
		if f < least:
			least = f
			best = phi
	var lo := best - TAU / 24.0
	var hi := best + TAU / 24.0
	for it in 14:
		var m1 := lerpf(lo, hi, 0.382)
		var m2 := lerpf(lo, hi, 0.618)
		if _elbow_cost(s, c + r * (v1 * cos(m1) + v2 * sin(m1)), w, fore) < _elbow_cost(s, c + r * (v1 * cos(m2) + v2 * sin(m2)), w, fore):
			hi = m2
		else:
			lo = m1
	best = (lo + hi) * 0.5
	_reach(side, target, chi.basis.inverse() * (c + r * (v1 * cos(best) + v2 * sin(best)) - s))


## What an elbow at `e` costs _reach_clear (his chest's frame; the shoulder at `s`, the wrist at
## `w`, the line the forearm would best run along `fore`).
func _elbow_cost(s: Vector3, e: Vector3, w: Vector3, fore: Vector3) -> float:
	var off := (w - e).angle_to(fore)
	return off * off + 1e5 * pow(_elbow_bad(s, e, w), 2.0)


## How badly an elbow at `e` breaks the rules (0: not at all; his chest's frame, the shoulder at
## `s`, the wrist at `w`): the arm raised past IDLE_RAISE_MOST (rad; ten times over: that one
## must hold, it's the shrug), the elbow or its forearm into his vest (rig units).
func _elbow_bad(s: Vector3, e: Vector3, w: Vector3) -> float:
	var bad := 10.0 * maxf(0.0, (e - s).angle_to(Vector3.DOWN) - IDLE_RAISE_MOST)
	bad += maxf(0.0, _in_vest(e, IDLE_LIMB.x))
	for k in 3:
		bad += maxf(0.0, _in_vest(e.lerp(w, (k + 1) / 4.0), IDLE_LIMB.y))
	return bad


## How far `q` (his chest's frame), `thick` round it, is inside his vest (rig units; < 0 clear of
## it): a rounded box (a superellipse across), narrower above y -0.2 than below -0.35.
func _in_vest(q: Vector3, thick: float) -> float:
	if q.y > IDLE_VEST_Y.x or q.y < IDLE_VEST_Y.y:
		return -1.0
	var a := lerpf(IDLE_VEST.x, IDLE_VEST.y, clampf((-0.2 - q.y) / 0.15, 0.0, 1.0))
	var k := pow(pow(absf(q.x) / a, 6.0) + pow(absf(q.z) / IDLE_VEST.z, 6.0), 1.0 / 6.0)
	return (1.0 - k) * minf(a, IDLE_VEST.z) + thick


## The magazine `out` (rig units) along the grip (only with IDLE_MAG_DROP; seated, it's hidden in it).
func _mag_at(out: float) -> void:
	_mag_out = out
	if _mag == null:
		return
	_mag.basis = Basis(Vector3.RIGHT, MAG_RAKE)
	_mag.position = Vector3(0.0, -0.05, 0.012) + _mag.basis * Vector3(0.0, -out, 0.0)


## Every joint's turn and the hips' place, to blend out of (into the run).
func _pose_snapshot() -> Array:
	var out: Array = [hips.position]
	for j in _all_joints():
		out.append(j.quaternion)
	return out


## From a snapshot toward the pose now: the hips and legs `legs` of the way, the rest `upper`.
func _pose_blend(from: Array, legs: float, upper: float) -> void:
	hips.position = (from[0] as Vector3).lerp(hips.position, legs)
	var js := _all_joints()
	for i in js.size():
		var j := js[i]
		var w := legs if (j == hips or j in leg_hips.values() or j in knees.values() or j in ankles.values()) else upper
		if w < 1.0:
			j.quaternion = (from[i + 1] as Quaternion).slerp(j.quaternion, w)



## After the pose (which only turns the shoulders): the collarbones lift with an arm raised high, the
## shoulder joint taking that much less, so the arm ends up where the pose put it (see SHRUG). Turns
## both about the axis out of his back (z), the way "side * angle raises the arm out to its side".
func _shrug() -> void:
	for side in [-1, 1]:
		var sh: Node3D = shoulders[side]
		var arm_in: Node3D = elbows[side].get_parent()  # the shoulder's arm-in pivot
		var arm := sh.basis * (arm_in.basis * (elbows[side] as Node3D).position)  # the upper arm, torso axes
		var raised := acos(clampf(-arm.normalized().y, -1.0, 1.0))
		var lift := clampf((raised - SHRUG_FROM) * SHRUG, 0.0, SHRUG_MAX)
		if lift <= 0.0:
			continue
		var turn := Basis(Vector3.BACK, side * lift)
		clavicles[side].basis = turn
		sh.basis = turn.inverse() * sh.basis


## FIRE held (user): the right arm comes up straight out ahead, whatever else he's doing; each shot
## kicks it up, snaps the slide back and flashes the muzzle.
func _aim_and_recoil(delta: float, aiming: bool) -> void:
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * 9.0)
	_kick = maxf(0.0, _kick - delta / RECOIL_TIME)
	if _aim > 0.0:
		var a := _aim * _aim * (3.0 - 2.0 * _aim)  # eased in and out
		shoulders[1].rotation = shoulders[1].rotation.lerp(Vector3(AIM_RAISE, 0.0, 0.0), a)
		elbows[1].rotation = elbows[1].rotation.lerp(Vector3(AIM_ELBOW, 0.0, 0.0), a)
		# The wrist turns the gun straight ahead and level, however the rest of him is turned (the
		# stride, the lean into the run): before the kick, so the kick still flips it up.
		var ahead := (_in_rig(elbows[1]).basis.inverse() * GUN_AHEAD).orthonormalized()
		wrists[1].quaternion = wrists[1].quaternion.slerp(ahead.get_rotation_quaternion(), a)
	var k := _kick * _kick
	shoulders[1].rotation.x += 0.12 * k  # the muzzle flips up ~15 degrees at the peak
	elbows[1].rotation.x += 0.16 * k
	_slide.position.z = 0.035 * k  # back toward his hand
	# The flash: at its hottest on the shot, blooming out and burning down to its core over the first
	# part of the kick, then gone.
	var u := (1.0 - _kick) / FLASH_TIME  # 0 on the shot .. 1 gone
	var on := _kick > 0.0 and u < 1.0
	_muzzle_flash.visible = on
	# The lamp is read by the level's lighting in the next physics tick, before the next frame is
	# posed: light it if the flash will still show on that frame.
	var kick_next := _kick - delta / RECOIL_TIME
	_flash_light.visible = kick_next > 0.0 and (1.0 - kick_next) / FLASH_TIME < 1.0
	if on:
		for m: MeshInstance3D in [_flash_star, _flash_tongues]:
			(m.material_override as ShaderMaterial).set_shader_parameter("heat", 1.0 - u)
		_flash_star.scale = Vector3.ONE * _flash_size * (0.8 + 0.7 * u)
		_flash_tongues.scale = Vector3(1.0, 1.0, _flash_reach * (0.7 + 0.9 * u))


func _pose_run() -> void:
	var p := _phase
	var r := _run
	hips.position.y = _hip_y - 0.05 * r + 0.06 * r * absf(sin(p))  # the bob
	spine.rotation.x = -0.2 * r  # leaning into it
	head.rotation.x = 0.14 * r
	for side in [-1, 1]:
		var q := p + (0.0 if side < 0 else PI)  # left and right in turn
		leg_hips[side].rotation.x = 0.8 * r * sin(q)
		knees[side].rotation.x = -r * (0.3 + 1.1 * maxf(0.0, cos(q)))  # folds as it swings through
		ankles[side].rotation.x = 0.25 * r * sin(q)
		shoulders[side].rotation.x = -0.7 * r * sin(q)  # opposite to its leg
		shoulders[side].rotation.z = side * 0.12
		elbows[side].rotation.x = 1.1 + 0.3 * r  # bent, pumping
	shoulders[1].rotation.x = 0.25 + 0.5 * r * sin(p)  # opposite the left arm (user: they swung together), the pistol forward
	chest.rotation.y = 0.12 * r * sin(p)  # the shoulders turn with the arms
	hips.rotation.y = -0.08 * r * sin(p)  # ...the hips with the legs
	elbows[1].rotation.x = 1.0


func _pose_jump(rising: bool) -> void:
	spine.rotation.x = -0.12
	leg_hips[-1].rotation.x = 1.1  # the lead knee up
	knees[-1].rotation.x = -1.4
	leg_hips[1].rotation.x = -0.3  # the trailing leg back
	knees[1].rotation.x = -1.2
	for side in [-1, 1]:
		shoulders[side].rotation.x = 0.45 if rising else 0.2
		shoulders[side].rotation.z = side * 0.25
		elbows[side].rotation.x = 1.0


## The slide's legs (rad: the hip, the knee, the ankle): the lead leg (his left) out straight ahead;
## the other folded right under him, his heel up by his seat, its knee and the toe of its boot just
## clear of the floor (6 cm: folded less, the boot would be in the floor). His death from a slide
## starts from them too (_death_back_limbs); with the foot only a little pointed, his ragdoll takes
## the leg on smoothly (pointed in line with its shin, it would turn the foot over in one frame as
## he lands).
const SLIDE_LEAD := Vector3(1.45, -0.1, 0.0)
const SLIDE_FOLD := Vector3(0.85, -2.72, -0.25)
## Leaning to his right into a lane change in a slide (the whole of him tips about his feet), the
## folded leg's boot, out on that side, would dip into the floor: he's lifted this much (rig units)
## at a full lean, less for less, so it stays clear.
const SLIDE_LEAN_LIFT := 0.048


## The slide (`lean`: his lean into a lane change, as animate's). Only the look: what he slides
## under is the player's (Player.is_sliding), never the model.
func _pose_slide(lean: float = 0.0) -> void:
	# Down low, feet first: leaning back, the lead leg out straight, the other folded under him.
	hips.position.y = _kneel_y - 0.12 + SLIDE_LEAN_LIFT * maxf(0.0, lean)  # down low
	spine.rotation.x = 0.8
	head.rotation.x = -0.55
	for side in [-1, 1]:
		var leg := SLIDE_LEAD if side < 0 else SLIDE_FOLD
		leg_hips[side].rotation.x = leg.x
		knees[side].rotation.x = leg.y
		ankles[side].rotation.x = leg.z
	for side in [-1, 1]:
		shoulders[side].rotation.x = -0.4
		shoulders[side].rotation.z = side * 0.7
		elbows[side].rotation.x = 0.4


func _pose_crouch() -> void:
	# Down on one knee behind a box, the pistol up and ready.
	hips.position.y = _kneel_y  # down on a knee
	spine.rotation.x = -0.25
	head.rotation.x = 0.15
	leg_hips[-1].rotation.x = 1.5  # the front leg: thigh out level, shin down
	knees[-1].rotation.x = -1.55
	leg_hips[1].rotation.x = -0.1  # the back leg: down on its knee
	knees[1].rotation.x = -1.55
	ankles[1].rotation.x = 0.5
	shoulders[1].rotation.x = 1.25
	elbows[1].rotation.x = 0.4
	shoulders[-1].rotation.x = 1.0
	shoulders[-1].rotation.z = 0.35  # across to steady the gun hand
	elbows[-1].rotation.x = 0.9


func _pose_surrender() -> void:
	# Down on his knees, both hands up.
	_reset()
	hips.position.y = _kneel_y  # down on a knee
	for side in [-1, 1]:
		knees[side].rotation.x = -1.6
		ankles[side].rotation.x = 0.5
		# Arms up, each arm turned out about itself on the way (the upper arm, then the forearm: the
		# forearm runs down its joint's frame, so it turns the same way as -UP), the elbows bending the
		# forearms up over his head...
		shoulders[side].basis = Basis(Vector3.BACK, side * 2.3) * Basis(Vector3.UP, -side * HANDS_UP_SHOULDER_TURN)
		var forearm: Vector3 = (wrists[side] as Node3D).position.normalized()  # the forearm, in the elbow's axes
		elbows[side].basis = Basis(Vector3.RIGHT, HANDS_UP_ELBOW) * Basis(forearm, side * HANDS_UP_FOREARM_TURN)
	head.rotation.x = 0.15
	# ...then each hand set exactly (user: palms forwards and a little in): running on from its
	# forearm, palm facing forwards and turned in a little (rig axes; he faces -Z).
	for side in [-1, 1]:
		var e := _in_rig(elbows[side]).basis
		var run := (e * (wrists[side] as Node3D).position).normalized()
		var palm := Vector3(-side * HANDS_UP_PALM_IN, 0.0, -1.0)
		palm = (palm - run * palm.dot(run)).normalized()
		wrists[side].basis = e.inverse() * _frame(run, palm) * _frame(_hand_run[side], _hand_palm[side]).inverse()


## An orthonormal frame with `a` as its first axis and `b` (made square to it) as its second.
static func _frame(a: Vector3, b: Vector3) -> Basis:
	var x := a.normalized()
	var y := (b - x * b.dot(x)).normalized()
	return Basis(x, y, x.cross(y))


## Never dissolved by the cutout (Cutout) from now on: CROSS (the player sets it: his body, his pistol
## and his hit flash), and a guard once he's down (GuardRig.fall, GuardRig.death_start), so his body
## never melts away as you run past it. Their own copies of their materials, so the others keep
## theirs. Whatever else in the PS1 shader hangs on him (a guard's radio) goes solid too, and so does
## a hit flash showing now.
func keep_solid() -> void:
	if _solid:
		return
	_solid = true
	for i in _meshes.size():
		_materials[i] = PsxMaterials.solid(_materials[i])
		_meshes[i].material_override = PsxMaterials.solid(_meshes[i].material_override)
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not _meshes.has(mi):
			mi.material_override = PsxMaterials.solid(mi.material_override)


## Hit: the whole model flashes red for a moment.
func flash() -> void:
	_flash_left = 0.15
	var red := PsxMaterials.figure(PsxMaterials.flat(Color("d83a2a")))
	if _solid:
		red = PsxMaterials.solid(red)
	for m in _meshes:
		m.material_override = red


func _flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		for i in _meshes.size():
			_meshes[i].material_override = _materials[i]


# --- Death (a ragdoll) ----------------------------------------------------------------------------

## CROSS's death (user: "a momentum ragdoll": the killing hit jolts him and he goes limp mid-stride,
## his run carries him forward, he pitches over onto his front, hits the ground, slides a little and
## lies still, face down). Its timings on his death's own clock (s): the hit; his muscles let go;
## his legs go from under him; he hits the ground; it's over (the blood has spread). How low his hips
## lie (rig units: face down), how far he rolls onto a side as he goes over, and gravity (9.8 m/s² at
## his 1.08 m to the unit).
const DIE_HITS: Array[float] = [0.0]
const DIE_LET_GO := 0.04
## Killed mid-change: the least time (s, his death's clock) his legs take from as they were shown
## onto his death's own.
const DIE_SHOWN_LEAST := 0.06
const DIE_LIFT := 0.1
const DIE_LAND := 0.6
const DIE_END := 1.9
const DIE_LIE := 0.17
const DIE_ROLL := 0.35
const DIE_GRAVITY := 9.07
## His pistol: when it hits the ground (it flies from his hand at the hit, tumbling, and lands ahead).
const PISTOL_LAND := 0.45

## A death as a ragdoll (user, the boss: "he's very stiff can't you make it a little more human/rag
## doll looking?"; CROSS: "a momentum ragdoll"): his body's path is set (_death_body), but from the
## hits his muscles go slack and the rest of him moves under its own weight, worked out at this many
## steps a second of his death's clock (its timings and gravity are the death's own: _death_plan).
## The share of a limb's speed it keeps each step in the air (and once he's down, settling), and of
## its slide along the ground.
const RAG_HZ := 120.0
const RAG_DRAG := 0.996
const RAG_DRAG_DOWN := 0.85
const RAG_DRAG_STILL := 0.5
const RAG_GRIP := 0.55
## How much of the way to a pose his muscles still pull a limb each step: slack in the air, all but
## limp lying (just enough to leave him spread out); his head a little firmer.
const RAG_PULL_AIR := 0.025
const RAG_PULL_DOWN := 0.004
const RAG_PULL_HEAD := 0.07
const RAG_PULL_HEAD_DOWN := 0.01
## His waist: how stiff and how damped (his upper body lags his hips, swings past, settles), and the
## most it lags (rad: a real waist turns about this far, no further). His neck's most (from his chest).
const RAG_WAIST_K := 90.0
const RAG_WAIST_C := 7.0
const RAG_WAIST_MAX := 0.6
const RAG_NECK_MAX := 0.75
## The ragdoll's tips (their joints' own frames): his fingertips (this many times his hand's middle
## out from the wrist), the toe of each boot from the ankle (on the deck as he stands), the middle of
## his skull from the head joint.
const RAG_FINGERS := 1.8
const RAG_TOE := Vector3(0.0, -0.06, -0.21)
const RAG_SKULL := Vector3(0.0, 0.12, -0.03)
## How far each ragdoll point keeps off the deck (rig units: the limb's thickness there): elbow,
## wrist, fingertips (each arm), knee, ankle, toe (each leg), skull. And the knock each hit gives his
## arms and head (rig units/s; +z away from you).
const RAG_RADIUS: Array[float] = [0.08, 0.07, 0.03, 0.08, 0.07, 0.03, 0.12, 0.09, 0.03, 0.12, 0.09, 0.03, 0.15]
const RAG_KICK := Vector3(0.6, 0.8, 1.6)
## How much of the way to its new direction a limb's steering moves each step (see _rag_smooth).
const RAG_EASE := 0.3
## How much of a hand's turn about the forearm the forearm takes (turned at the elbow), the rest at
## the wrist, so no one joint twists the skin too far (holding the handguard palm up, the left hand
## turns over ~115 degrees): as CROSS's hands-up shares it.
const FOREARM_SHARE := 0.5

## Where each ankle joint is standing at rest (this rig's space): the feet are planted at its height.
var _ankle_rest := {}
## His ragdoll (death_start sets it up, _rag_step moves it on): the points it moves (his elbows,
## wrists, knees, ankles and head, left then right: this rig's space) and where they were a step
## before, his bones' lengths, his waist's turn and spin, how many steps it has done, and what each
## step made of him (his hips' place and every joint's turn: what the replays show).
var _rag := {}
## His ragdoll's hands' last turns about their forearms (by side; only while it's worked out).
var _twist_was := {}
var _twist_on := false

## Every joint in him (the hips first), for a death, which poses them all.
func _all_joints() -> Array[Node3D]:
	var out: Array[Node3D] = [hips, spine, chest, neck, head]
	for side in [-1, 1]:
		out.append_array([clavicles[side], shoulders[side], elbows[side], wrists[side], leg_hips[side], knees[side], ankles[side]])
	return out



## The timings, and gravity, of this rig's death (see the DIE_ constants; the boss has his own).
func _death_plan() -> Dictionary:
	return {"hits": DIE_HITS, "let_go": DIE_LET_GO, "lift": DIE_LIFT, "land": DIE_LAND, "end": DIE_END, "gravity": DIE_GRAVITY}


func _plan(key: String) -> float:
	return float(_rag["plan"][key])


## How long his death runs on its clock (s), and when he's down (0 before he's dying).
func death_end() -> float:
	return 0.0 if _rag.is_empty() else _plan("end")


func death_land() -> float:
	return 0.0 if _rag.is_empty() else _plan("land")


## Lying face down, how far his head reaches past his hips (m); lying on his back, his boots.
const HEAD_REACH := 1.0
const FEET_REACH := 1.3


## CROSS's death from how fast he was going (m/s), how far the way ahead is clear (m) and whether he
## was sliding: "travel" (m: how far it carries him), "back" (no room to go over forwards: knocked
## back the other way, onto his back, far enough for his boots to clear what's in front of him) and
## "slide" (mid-slide: he slumps back flat onto his back and skids on, feet first, already low).
## Never into what's in front of him.
static func fall_for(speed: float, free_ahead: float, sliding: bool, tt: Tuning) -> Dictionary:
	var travel := clampf(speed * tt.death_carry, 0.2, tt.death_carry_max)
	if sliding:
		return {"travel": clampf(free_ahead - FEET_REACH, 0.1, travel), "back": false, "slide": true}
	if free_ahead < tt.death_room:
		return {"travel": maxf(tt.death_knock_back, FEET_REACH - free_ahead), "back": true, "slide": false}
	return {"travel": clampf(free_ahead - HEAD_REACH, 0.1, travel), "back": false, "slide": false}


## Killed: how he is now (his hips' place, every joint's turn, what's in his hand), set up for
## pose_death to work his fall out from. opts: "lift" (rig units he was off the ground: he comes
## down first), "travel" (how far his momentum carries him), "room" (how far ahead is clear: rig units),
## "back" and "slide" (see fall_for), "lean" (his lean into a lane change, straightened out at once).
func death_start(opts: Dictionary = {}) -> Dictionary:
	var shown := _change_drop()  # (killed mid-change: his death from the pose itself, shown easing onto it)
	hips.position.y += float(opts.get("lift", 0.0))
	var joints: Array[Quaternion] = []
	for j in _all_joints():
		joints.append(j.quaternion)
	_kick = 0.0
	if _slide != null:
		_slide.position.z = 0.0  # (the pistol's slide forward again)
	_mag_at(0.0)
	_idle_on = false
	_launch_t = -1.0
	var from := {"hips": hips.position, "joints": joints, "prop": _death_prop_from(), "opts": opts, "shown": shown}
	var pts := _rag_points()
	var roots := _rag_roots()
	_rag = {"from": from, "opts": opts, "plan": _death_plan(), "pos": pts.duplicate(), "prev": pts.duplicate(), "n": 0,
			"samples": [], "bones": _rag_bones(pts, roots), "smooth": [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
			"twist": {}, "waist_q": Quaternion(_in_rig(chest).basis.orthonormalized()), "waist_w": Vector3.ZERO}
	return from


## The hit flash keeps fading while he dies (pose_death doesn't run animate).
func tick_flash(delta: float) -> void:
	_flash(delta)


## His death at `t` (s on its own clock), from `from` (death_start()): the same t, the same pose,
## so it can be shown again from any angle (the boss's KO replay). Worked out as a ragdoll a step at
## a time as it's first needed, and a little ahead each time it's shown, so the replays are ready.
func pose_death(t: float, from: Dictionary) -> void:
	if _rag.is_empty():
		return
	var last := int(ceil(_plan("end") * RAG_HZ))
	var need := mini(int(ceil(clampf(t, 0.0, _plan("end")) * RAG_HZ)) + 1, last)
	while int(_rag["n"]) <= need:
		_rag_step()
	for k in 9:  # (all of it in about half a second of the live shot: before a skip can come)
		if int(_rag["n"]) <= last:
			_rag_step()
	var samples: Array = _rag["samples"]
	var x := clampf(t * RAG_HZ, 0.0, float(samples.size() - 1))
	var i := int(x)
	var f := x - i
	var a: Array = samples[i]
	var b: Array = samples[mini(i + 1, samples.size() - 1)]
	_reset()
	rotation.z = float((from["opts"] as Dictionary).get("lean", 0.0)) * (1.0 - smoothstep(0.0, 0.15, t))
	hips.position = (a[0] as Vector3).lerp(b[0], f)
	var joints: Array[Node3D] = _all_joints()
	for k in joints.size():
		joints[k].quaternion = (a[k + 1] as Quaternion).slerp(b[k + 1], f)
	var shown: Dictionary = from.get("shown", {})
	if not shown.is_empty():
		# Killed mid-change: his hips and legs as they were shown, easing onto his death's own over the
		# time the change had left (no snap as he's hit).
		var k := 1.0 - _change_ease(t / float(shown["len"]))
		if k > 0.0:
			hips.position += (shown["hips"] as Vector3) * k
			var off: Array = shown["off"]
			for j in joints.size():
				if CHANGE_PART[j] == 0:
					joints[j].quaternion = Quaternion.IDENTITY.slerp(off[j], k) * joints[j].quaternion
	_death_prop(t, from)
	_apply()


## The pose his body's path and his muscles would give him at `t`: the set path, and out of his
## stance, not in one jump (his upper body at once, his hips and legs as he leaves the deck: until
## then his feet stay where they were).
func _death_target(t: float, from: Dictionary) -> void:
	_reset()
	_death_body(t, from["hips"])
	var up := smoothstep(0.0, 0.12, t)
	var low := smoothstep(_plan("lift") - 0.02, _plan("lift") + 0.12, t)
	var joints: Array[Node3D] = _all_joints()
	var was: Array = from["joints"]
	hips.position = (from["hips"] as Vector3).lerp(hips.position, low)
	for i in joints.size():
		var j := joints[i]
		var w := low if (j == hips or j in leg_hips.values() or j in knees.values() or j in ankles.values()) else up
		if w < 1.0:
			j.quaternion = (was[i] as Quaternion).slerp(j.quaternion, w)


## The ragdoll's points in the pose the joints hold now (this rig's space), each limb from its root
## out: for each arm (left, then right) the elbow, the wrist and the fingertips; for each leg the
## knee, the ankle and the toe; then the middle of his skull.
func _rag_points() -> Array:
	var out := []
	for side in [-1, 1]:
		var w := _in_rig(wrists[side])
		out.append_array([_in_rig(elbows[side]).origin, w.origin, w * ((_hand_mid[side] as Vector3) * RAG_FINGERS)])
	for side in [-1, 1]:
		var a := _in_rig(ankles[side])
		out.append_array([_in_rig(knees[side]).origin, a.origin, a * RAG_TOE])
	out.append(_in_rig(head) * RAG_SKULL)
	return out


## What his limbs and head hang from (this rig's space): his shoulders, his hips' leg joints, his neck.
func _rag_roots() -> Array:
	return [_in_rig(shoulders[-1]).origin, _in_rig(shoulders[1]).origin, _in_rig(leg_hips[-1]).origin, _in_rig(leg_hips[1]).origin,
			_in_rig(neck).origin]


## The ragdoll's bones (point, point, length; a point -1 is the limb's root, -2 the second root)
## from its points and roots now: each limb root to its middle joint, the middle to the end, the end
## to the tip, and the middle to the tip (which holds the wrist or ankle at its angle); his neck to
## his skull.
static func _rag_bones(pts: Array, roots: Array) -> Array:
	var out := []
	for limb in 4:
		var k := limb * 3
		var root: Vector3 = roots[limb]
		out.append([-1 - limb, k, root.distance_to(pts[k])])
		out.append([k, k + 1, (pts[k] as Vector3).distance_to(pts[k + 1])])
		out.append([k + 1, k + 2, (pts[k + 1] as Vector3).distance_to(pts[k + 2])])
		out.append([k, k + 2, (pts[k] as Vector3).distance_to(pts[k + 2])])
	out.append([-5, 12, (roots[4] as Vector3).distance_to(pts[12])])
	return out


## One step of his ragdoll (1/RAG_HZ s of his death): his body along its path, his waist bending
## after it (within limits), his slack limbs and head swinging under their own weight (each still
## pulled a little toward a pose), his elbows and knees bending only the way they bend, bones kept
## their lengths, nothing through the deck, and once he's down, settling still; then the step's
## pose kept.
func _rag_step() -> void:
	var dt := 1.0 / RAG_HZ
	var n: int = _rag["n"]
	var t := n * dt
	_death_target(t, _rag["from"])
	_rag_waist(t, dt)
	var target := _rag_points()
	var roots := _rag_roots()
	var tgt_hands := [_in_rig(wrists[-1]).basis.orthonormalized(), _in_rig(wrists[1]).basis.orthonormalized(),
			_in_rig(ankles[-1]).basis.orthonormalized(), _in_rig(ankles[1]).basis.orthonormalized()]
	# Which way each elbow and knee bends in the pose (square to its limb): the way it must bend.
	var bends := []
	for limb in 4:
		var k := limb * 3
		bends.append(_rag_bend(roots[limb], target[k], target[k + 1], Vector3.FORWARD if limb >= 2 else Vector3.DOWN))
	var pos: Array = _rag["pos"]
	var prev: Array = _rag["prev"]
	var down := smoothstep(_plan("land"), _plan("land") + 0.25, t)
	var still := smoothstep(_plan("land") + 0.4, _plan("land") + 0.9, t)
	var drag := lerpf(lerpf(RAG_DRAG, RAG_DRAG_DOWN, down), RAG_DRAG_STILL, still)
	var fall := _plan("gravity") * dt * dt * (1.0 - still)  # (lying, he stays where he fell: no slow sag)
	for i in pos.size():
		var p: Vector3 = pos[i]
		var v: Vector3 = (p - (prev[i] as Vector3)) * drag
		prev[i] = p
		pos[i] = (p + v + Vector3(0.0, -fall, 0.0)).lerp(target[i], _rag_pull(t, i))
	# Each hit knocks his arms and head back (away from you) and out.
	for h in (_rag["plan"]["hits"] as Array):
		if t >= h and t < h + dt:
			for i in [0, 1, 2, 3, 4, 5, 12]:
				var side := -1.0 if i < 3 else 1.0
				var kick := Vector3(side * RAG_KICK.x, RAG_KICK.y, RAG_KICK.z) if i != 12 else Vector3(0.0, RAG_KICK.y, RAG_KICK.z)
				prev[i] = (prev[i] as Vector3) - kick * dt
	var bones: Array = _rag["bones"]
	for it in 4:
		for bone in bones:
			var a: int = bone[0]
			_rag_stick(pos, roots[-1 - a] if a < 0 else Vector3.ZERO, a, bone[1], bone[2])
		for limb in 4:
			_rag_hinge(pos, prev, roots[limb], limb * 3, bends[limb], (target[limb * 3] as Vector3) - (roots[limb] as Vector3),
					(target[limb * 3 + 1] as Vector3) - (roots[limb] as Vector3))
		for i in pos.size():
			var p: Vector3 = pos[i]
			var r: float = RAG_RADIUS[i]
			if p.y < r:
				# On the deck: a little bounce, and its slide mostly gripped.
				var was: Vector3 = prev[i]
				var vy := p.y - was.y
				p.y = r
				prev[i] = Vector3(p.x - (p.x - was.x) * RAG_GRIP, r + vy * 0.25, p.z - (p.z - was.z) * RAG_GRIP)
				pos[i] = p
	_twist_was = _rag["twist"]
	_twist_on = true
	_rag_pose(pos, roots, target, bends, tgt_hands)
	_twist_on = false
	var sample := [hips.position]
	for j in _all_joints():
		sample.append(j.quaternion)
	(_rag["samples"] as Array).append(sample)
	_rag["n"] = n + 1


## How much of the way to the pose a ragdoll point is pulled this step: all of it while he's still
## alive (his arms and head till the first hits are done, his legs till he leaves the deck), then
## slack, then all but limp once he's down.
func _rag_pull(t: float, i: int) -> float:
	var leg := i >= 6 and i < 12
	var alive_until := _plan("lift") if leg else 0.04
	var slack_by := _plan("lift") + 0.08 if leg else 0.16
	var air := RAG_PULL_HEAD if i == 12 else RAG_PULL_AIR
	var limp := RAG_PULL_HEAD_DOWN if i == 12 else RAG_PULL_DOWN
	var p := lerpf(1.0, air, smoothstep(alive_until, slack_by, t))
	p = lerpf(p, limp, smoothstep(_plan("land"), _plan("land") + 0.3, t))
	return p * (1.0 - smoothstep(_plan("land") + 0.4, _plan("land") + 0.9, t))  # (then none: he lies where he fell)


## A bone keeps its length: `b` (a point) to `a` (a point, or the fixed `root` when a < 0).
static func _rag_stick(pos: Array, root: Vector3, a: int, b: int, length: float) -> void:
	var pa: Vector3 = root if a < 0 else pos[a]
	var pb: Vector3 = pos[b]
	var d := pb - pa
	var l := d.length()
	if l < 0.0001:
		return
	var off := d * ((l - length) / l)
	if a < 0:
		pos[b] = pb - off
	else:
		pos[a] = pa + off * 0.5
		pos[b] = pb - off * 0.5


## An elbow or knee (point `k`, between `root` and point k + 1) bends only the way it bends: `bend`
## in the pose (whose limb ran root to `line_t`'s end), turned with the limb as it is now; pushed
## out to at least a little bend that way (moved with its last place, so it gains no speed), and
## never folded right up (the end kept out from the root).
static func _rag_hinge(pos: Array, prev: Array, root: Vector3, k: int, bend: Vector3, mid_t: Vector3, end_t: Vector3) -> void:
	var end: Vector3 = pos[k + 1]
	var line := end - root
	if line.length() < 0.0001 or end_t.length() < 0.0001:
		return
	var reach := (mid_t.length() + (end_t - mid_t).length())
	if line.length() < 0.4 * reach:
		pos[k + 1] = root + line.normalized() * 0.4 * reach
		line = (pos[k + 1] as Vector3) - root
	var dir := line.normalized()
	var turn := Quaternion(end_t.normalized(), dir) if end_t.normalized().dot(dir) > -0.9999 else Quaternion.IDENTITY
	var anat := (Basis(turn) * bend)
	anat = (anat - dir * anat.dot(dir)).normalized()
	var mid: Vector3 = pos[k]
	var off := (mid - root) - dir * (mid - root).dot(dir)
	var along := off.dot(anat)
	if along < 0.03:
		var push := anat * (0.03 - along)
		pos[k] = mid + push
		prev[k] = (prev[k] as Vector3) + push


## His waist: his upper body's turn lags the pose's on a spring (stiff, a little bouncy in the air,
## settling once he's down), never more than RAG_WAIST_MAX behind (no wringing), put into his
## spine so his chest and all above it follow.
func _rag_waist(t: float, dt: float) -> void:
	var want := Quaternion(_in_rig(chest).basis.orthonormalized())
	if t < _plan("let_go"):
		_rag["waist_q"] = want
		_rag["waist_w"] = Vector3.ZERO
		return
	var q: Quaternion = _rag["waist_q"]
	var w: Vector3 = _rag["waist_w"]
	var err := want * q.inverse()
	if err.w < 0.0:
		err = -err
	var e := Vector3.ZERO
	if err.get_angle() > 0.0001:
		e = err.get_axis().normalized() * err.get_angle()
	var c := RAG_WAIST_C if t < _plan("land") else 2.0 * sqrt(RAG_WAIST_K)
	w += (e * RAG_WAIST_K - w * c) * dt
	if w.length() > 0.00001:
		q = (Quaternion(w.normalized(), w.length() * dt) * q).normalized()
	var lag := q * want.inverse()
	if lag.w < 0.0:
		lag = -lag
	if lag.get_angle() > RAG_WAIST_MAX:
		q = (Quaternion(lag.get_axis().normalized(), RAG_WAIST_MAX) * want).normalized()
	_rag["waist_q"] = q
	_rag["waist_w"] = w
	var turn := Basis(q * want.inverse())
	spine.basis = _in_rig(spine.get_parent() as Node3D).basis.inverse() * (turn * _in_rig(spine).basis)


## The ragdoll's points onto his joints: each wrist to its point, the elbow bent toward its point
## (the way it bends), the hand as in the pose, carried round with the forearm (and lifted off the
## deck); each ankle to its point, the knee likewise, the foot aimed at its toe; his head
## turned toward its point (no further than a neck turns).
func _rag_pose(pos: Array, roots: Array, target: Array, bends: Array, tgt_ends: Array) -> void:
	var tgt_hands := tgt_ends
	for side in [-1, 1]:
		var limb := 0 if side < 0 else 1
		var k := limb * 3
		var sh: Vector3 = roots[limb]
		var el: Vector3 = pos[k]
		var wr: Vector3 = pos[k + 1]
		# The hand as it is in the pose, against its forearm and upper arm, carried with them as they are now.
		var was := _frame((target[k + 1] as Vector3) - (target[k] as Vector3), sh - (target[k] as Vector3))
		var hand: Basis = _frame(wr - el, sh - el) * was.inverse() * (tgt_hands[limb] as Basis)
		# ...lifted at the wrist, only as far as it must be, if its fingertips would be in the deck.
		var fingers := hand * ((_hand_mid[side] as Vector3) * RAG_FINGERS)
		var deck := RAG_RADIUS[k + 2] - wr.y
		if fingers.y < deck and Vector2(fingers.x, fingers.z).length() > 0.001:
			var flat := Vector2(fingers.x, fingers.z).normalized() * sqrt(maxf(0.0, fingers.length_squared() - deck * deck))
			hand = Basis(_rag_arc(fingers, Vector3(flat.x, deck, flat.y))) * hand
		var pole := (_rag_bend(sh, el, wr, bends[limb]) + (bends[limb] as Vector3) * 0.05).normalized()
		_reach(side, Transform3D(hand, wr), _rag_smooth(limb, pole, _in_rig(chest).basis.orthonormalized()))
	for side in [-1, 1]:
		var limb := 2 if side < 0 else 3
		var k := limb * 3
		var hp: Vector3 = roots[limb]
		var kn: Vector3 = pos[k]
		var an: Vector3 = pos[k + 1]
		var knee_dir := (_rag_bend(hp, kn, an, bends[limb]) + (bends[limb] as Vector3) * 0.05).normalized()
		_plant(side, an, _rag_smooth(limb, knee_dir, _in_rig(hips).basis.orthonormalized()), 0.0)
		# The foot as it is in the pose, against its shin and toe, set on the shin and toe as they are now.
		var shin := an - _in_rig(knees[side]).origin
		var was := _frame((target[k + 1] as Vector3) - (target[k] as Vector3), (target[k + 2] as Vector3) - (target[k + 1] as Vector3))
		var foot: Basis = _frame(shin, (pos[k + 2] as Vector3) - an) * was.inverse() * (tgt_hands[limb] as Basis)
		ankles[side].basis = _in_rig(knees[side]).basis.inverse() * foot
	var nk: Vector3 = roots[4]
	var want: Vector3 = (pos[12] as Vector3) - nk
	var up := _in_rig(chest).basis.y.normalized()
	if want.length() > 0.01:
		var wd := want.normalized()
		var bent := up.angle_to(wd)
		if bent > RAG_NECK_MAX:
			wd = up.slerp(wd, RAG_NECK_MAX / bent)
		var now := _in_rig(head) * RAG_SKULL - nk
		var q := _rag_arc(now, wd)
		neck.basis = _in_rig(neck.get_parent() as Node3D).basis.inverse() * (Basis(q) * _in_rig(neck).basis)


## A direction the ragdoll steers a limb by (an elbow's or knee's bend), eased over a few steps in
## the frame of what it hangs from (`frame`: his chest or hips), so a limb never
## rolls round in one step but still turns with him as he spins.
func _rag_smooth(i: int, dir: Vector3, frame: Basis) -> Vector3:
	if dir.length() < 0.0001:
		return dir
	var local := (frame.inverse() * dir).normalized()
	var smooth: Array = _rag["smooth"]
	var was: Vector3 = smooth[i]
	if was != Vector3.ZERO and was.dot(local) > -0.999:
		local = was.slerp(local, RAG_EASE).normalized()
	smooth[i] = local
	return frame * local


## The turn taking direction `from` onto `to` (none if either is too short, or they're opposite).
static func _rag_arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.length() < 0.0001 or to.length() < 0.0001:
		return Quaternion.IDENTITY
	var a := from.normalized()
	var b := to.normalized()
	if a.dot(b) < -0.9999:
		return Quaternion.IDENTITY
	return Quaternion(a, b)


## Which way a joint between `a` and `c` is bent out (toward `b`, square to a-c), or `fallback`
## if it's near straight.
static func _rag_bend(a: Vector3, b: Vector3, c: Vector3, fallback: Vector3) -> Vector3:
	var line := (c - a).normalized()
	var off := (b - a) - line * (b - a).dot(line)
	return off.normalized() if off.length() > 0.01 else fallback


## CROSS's body through his death (the path his ragdoll follows; see the DIE_ constants): jolted
## back by the hit, his run carrying him on ("travel"), falling forward onto his front (slowly, then
## fast) as his legs go, rolling a little onto his side; down, a bump and a short slide, then still.
## Blocked ("back"), knocked back the other way onto his back, arms flung out; mid-slide ("slide"),
## slumped back flat onto his back, skidding on. His limbs as his muscles would put them (the
## ragdoll only leans on this a little).
func _death_body(t: float, hips_from: Vector3) -> void:
	var opts: Dictionary = _rag["opts"] if not _rag.is_empty() else {}
	var travel := float(opts.get("travel", 0.4))
	# Blocked (he ran into what got him: no room to go over forwards): knocked back off it instead,
	# onto his back. Mid-slide, on his back too, but carried on.
	var slide := bool(opts.get("slide", false))
	var way := -1.0 if bool(opts.get("back", false)) else 1.0
	var face_up := way < 0.0 or slide
	var u := clampf((t - DIE_LIFT) / (DIE_LAND - DIE_LIFT), 0.0, 1.0)  # going over
	var down := t >= DIE_LAND
	var after := maxf(0.0, t - DIE_LAND)
	var jolt := sin(clampf(t / 0.18, 0.0, 1.0) * PI) * 0.35
	var go := clampf(t / (DIE_LAND + 0.35), 0.0, 1.0)
	var y := lerpf(hips_from.y, DIE_LIE, u * u)
	if down:
		y = DIE_LIE + 0.035 * sin(clampf(after / 0.14, 0.0, 1.0) * PI)
	hips.position = Vector3(hips_from.x, y, hips_from.z - way * travel * (1.0 - (1.0 - go) * (1.0 - go)))
	var e := u * u * (3.0 - 2.0 * u)
	hips.basis = Basis(Vector3.RIGHT, (PI / 2.0 if face_up else -PI / 2.0) * e) * Basis(Vector3.UP, DIE_ROLL * e)
	var air := sin(PI * u) if not down else 0.0
	var slap := smoothstep(0.0, 0.12, after) if down else 0.0
	if face_up:
		_death_back_limbs(jolt, air, slap, e if slide else -1.0)
		return
	for side in [-1, 1]:
		# Arms: thrown back by the hit, trailing as he goes over, then flopped down by his sides.
		var arm_air := Vector3(-0.6 - 0.3 * jolt, 0.0, side * (0.35 + 0.3 * air))
		var arm_down := Vector3(-0.15 if side < 0 else 0.25, 0.0, side * (0.45 if side < 0 else 0.25))
		shoulders[side].rotation = arm_air.lerp(arm_down, slap)
		elbows[side].rotation.x = lerpf(0.5 + 0.3 * air, 0.3 if side < 0 else 0.6, slap)
		# Legs: buckling as they go, then lying out behind him, one a little bent.
		var leg_air := Vector3(0.3 * air, 0.0, side * 0.08)
		var leg_down := Vector3(0.0 if side < 0 else 0.25, 0.0, side * (0.1 if side < 0 else 0.16))
		leg_hips[side].rotation = leg_air.lerp(leg_down, slap)
		knees[side].rotation.x = lerpf(-0.2 - 0.9 * air, -0.1 if side < 0 else -0.55, slap)
		ankles[side].rotation.x = lerpf(0.2 * air, 0.4, slap)
	spine.rotation.x = jolt - 0.15 * air
	chest.rotation.x = 0.5 * jolt
	neck.rotation.x = 0.2 * jolt
	head.rotation.x = 0.6 * jolt + 0.2 * air
	head.rotation.y = slap  # (lying, his face turned to one side)


## Knocked back onto his back: his arms flung forward and out by the hit (not trailing behind him,
## under him as he lands), his legs kicking up a little as he goes over; lying, arms out to his sides,
## one knee up. Mid-slide (`slid`: how far he's gone over, or < 0), he stays leaning back as he was
## and his legs stay out in front, low (never up into the pipe he's sliding under).
func _death_back_limbs(jolt: float, air: float, slap: float, slid: float) -> void:
	var slide := slid >= 0.0
	for side in [-1, 1]:
		var arm_air := Vector3(0.7 + 0.4 * jolt, 0.0, side * (0.5 + 0.4 * air))
		var arm_down := Vector3(0.15 if side < 0 else 0.35, 0.0, side * (0.95 if side < 0 else 0.7))
		shoulders[side].rotation = arm_air.lerp(arm_down, slap)
		elbows[side].rotation.x = lerpf(0.4 + 0.3 * air, 0.35 if side < 0 else 0.7, slap)
		var leg_air := Vector3(0.45 * air, 0.0, side * 0.1)
		var knee_air := -0.2 - 0.6 * air
		var ankle_air := 0.1 * air
		if slide:  # (from the slide's legs: SLIDE_LEAD, SLIDE_FOLD)
			var leg := SLIDE_LEAD if side < 0 else SLIDE_FOLD
			leg_air = Vector3(lerpf(leg.x, 0.05, slid), 0.0, side * 0.1)
			knee_air = lerpf(leg.y, -0.3, slid)
			ankle_air = lerpf(leg.z, ankle_air, slid)
		var leg_down := Vector3(0.05 if side < 0 else 0.45, 0.0, side * (0.12 if side < 0 else 0.08))
		leg_hips[side].rotation = leg_air.lerp(leg_down, slap)
		knees[side].rotation.x = lerpf(knee_air, -0.1 if side < 0 else -0.8, slap)
		ankles[side].rotation.x = lerpf(ankle_air, -0.2, slap)
	spine.rotation.x = jolt - 0.1 * air
	head.rotation.x = 0.6 * jolt - 0.3 * air  # (his chin tucked as he goes over)
	if slide:
		spine.rotation.x = 0.8 * (1.0 - slid) + 0.2 * jolt  # (leaning back as in his slide, then flat)
		head.rotation.x = -0.55 * (1.0 - slid)
	chest.rotation.x = 0.5 * jolt
	neck.rotation.x = 0.2 * jolt
	head.rotation.y = 0.6 * slap  # (lying, his face turned to one side)


## What's in his hand as he's killed (this rig's space): his pistol.
func _death_prop_from() -> Transform3D:
	var pistol := wrists[1].get_node_or_null("Pistol") as Node3D
	return _in_rig(pistol) if pistol != null else Transform3D.IDENTITY


## His pistol as he dies: flying from his hand at the hit, tumbling, it lands on its side ahead of
## him, bounces and lies still. The flash and its light out.
func _death_prop(t: float, from: Dictionary) -> void:
	if _muzzle_flash != null:
		_muzzle_flash.visible = false
	if _flash_light != null:
		_flash_light.visible = false
	var pistol := wrists[1].get_node_or_null("Pistol") as Node3D
	if pistol == null:
		return
	var held: Transform3D = from["prop"]
	var size := held.basis.get_scale()
	var b0 := held.basis.orthonormalized()
	var xf := Transform3D(b0, held.origin)
	if t > DIE_LET_GO:
		var travel := float((from["opts"] as Dictionary).get("travel", 0.4))
		var room := float((from["opts"] as Dictionary).get("room", 99.0))
		var k := clampf((t - DIE_LET_GO) / (PISTOL_LAND - DIE_LET_GO), 0.0, 1.0)
		var back := bool((from["opts"] as Dictionary).get("back", false))
		# Knocked back, it drops from his hand near where he was hit; else it flies on ahead. Never
		# past what's in front of him.
		var rest_z := maxf(held.origin.z + 0.35 if back else held.origin.z - travel - 0.5, -room + 0.15)
		var rest_at := Vector3(held.origin.x + 0.15, 0.03, rest_z)
		var at := Vector3(lerpf(held.origin.x, rest_at.x, k), lerpf(held.origin.y, rest_at.y, k * k) + 0.25 * sin(PI * k),
				lerpf(held.origin.z, rest_at.z, 1.0 - (1.0 - k) * (1.0 - k)))
		var rest := Basis(Vector3.UP, 0.8) * Basis(Vector3.FORWARD, PI / 2.0)
		var turn := (b0 * Basis(Vector3.RIGHT, 9.0 * k)).orthonormalized().slerp(rest, k * k)
		var after := maxf(0.0, t - PISTOL_LAND)
		if after > 0.0:
			at.y += 0.04 * sin(clampf(after / 0.15, 0.0, 1.0) * PI)
			turn = rest
		xf = Transform3D(turn, at)
	pistol.transform = _in_rig(wrists[1]).affine_inverse() * Transform3D(xf.basis * Basis.from_scale(size), xf.origin)


## His death's ragdoll is all worked out (the rest of it can be shown at once).
func death_baked() -> bool:
	return not _rag.is_empty() and int(_rag["n"]) > int(ceil(_plan("end") * RAG_HZ))


## One leg planted: `side`'s ankle joint to `at` (this rig's space; as near as the leg reaches),
## the knee toward `knee` (a direction), the foot flat on the floor and turned out by `toe` (+ to
## his left). As _reach_from_shoulder does an arm.
func _plant(side: int, at: Vector3, knee: Vector3, toe: float) -> void:
	var lh: Node3D = leg_hips[side]
	var kn: Node3D = knees[side]
	var an: Node3D = ankles[side]
	var leg_in: Node3D = kn.get_parent()
	var pk := kn.position  # hip to knee, in the leg-in pivot's frame
	var pa := an.position  # knee to ankle, in the knee's frame
	var parent := _in_rig(lh.get_parent() as Node3D)
	var to := parent.basis.inverse() * (at - parent * lh.position)
	# Never quite straight (so the knee always has a way to point).
	to = to.limit_length((pk.length() + pa.length()) * 0.995)
	# The knee (a hinge about its x; -x folds the shin back): bent so hip to ankle is as long as hip
	# to `at` (as the elbow is, folding the other way).
	var ca := pk.y * pa.y + pk.z * pa.z
	var sa := pk.z * pa.y - pk.y * pa.z
	var r := sqrt(ca * ca + sa * sa)
	var phi := atan2(sa, ca)
	var k := (to.length_squared() - pk.length_squared() - pa.length_squared()) * 0.5 - pk.x * pa.x
	kn.basis = Basis(Vector3.RIGHT, phi - acos(clampf(k / maxf(r, 0.0001), -1.0, 1.0)))
	# The hip: the leg (hip to ankle) onto `at`, the knee toward `knee`.
	var reach := leg_in.basis * (pk + kn.basis * pa)
	lh.basis = _frame(to, parent.basis.inverse() * knee) * _frame(reach, leg_in.basis * pk).inverse()
	# The foot: flat, turned out (its sole's level at rest, under the flat-foot pivot).
	var flat := an.get_node(String(an.name) + "Flat") as Node3D
	an.basis = _in_rig(kn).basis.inverse() * Basis(Vector3.UP, toe) * flat.basis.inverse()


## One arm's two-joint reach: `side`'s wrist joint to `target.origin` (this rig's space; as near as
## the arm reaches), the elbow toward `pole`, the hand turned to `target.basis`. With the arm raised
## high, the collarbone lifts too (the shrug, as SoldierRig does it), and the arm reaches again from
## there.
func _reach(side: int, target: Transform3D, pole: Vector3) -> void:
	clavicles[side].basis = Basis.IDENTITY
	_reach_from_shoulder(side, target, pole)
	var arm_in: Node3D = elbows[side].get_parent()
	var arm: Vector3 = shoulders[side].basis * (arm_in.basis * (elbows[side] as Node3D).position)
	var lift := clampf((acos(clampf(-arm.normalized().y, -1.0, 1.0)) - SHRUG_FROM) * SHRUG, 0.0, SHRUG_MAX)
	if lift > 0.0:
		clavicles[side].basis = Basis(Vector3.BACK, side * lift)
		_reach_from_shoulder(side, target, pole)


func _reach_from_shoulder(side: int, target: Transform3D, pole: Vector3) -> void:
	var sh: Node3D = shoulders[side]
	var el: Node3D = elbows[side]
	var arm_in: Node3D = el.get_parent()
	var pe := el.position  # shoulder to elbow, in the arm-in pivot's frame
	var pw := (wrists[side] as Node3D).position  # elbow to wrist, in the elbow's frame
	var parent := _in_rig(sh.get_parent() as Node3D)
	var to := parent.basis.inverse() * (target.origin - parent * sh.position)
	to = to.limit_length((pe.length() + pw.length()) * 0.995)  # (never quite straight: the elbow keeps a way to point)
	# The elbow (a hinge about its x): bent so shoulder to wrist is as long as shoulder to target.
	# |pe + turn(pw)|^2 = |pe|^2 + |pw|^2 + 2 pe.turn(pw), and pe.turn(pw) = pe.x pw.x + r cos(bend - phi).
	var ca := pe.y * pw.y + pe.z * pw.z
	var sa := pe.z * pw.y - pe.y * pw.z
	var r := sqrt(ca * ca + sa * sa)
	var phi := atan2(sa, ca)  # the straightest it goes
	var k := (to.length_squared() - pe.length_squared() - pw.length_squared()) * 0.5 - pe.x * pw.x
	var bend := phi + acos(clampf(k / maxf(r, 0.0001), -1.0, 1.0))  # the forward-bending way
	el.basis = Basis(Vector3.RIGHT, bend)
	# The shoulder: the arm (shoulder to wrist) onto the target, the elbow toward the pole.
	var reach := arm_in.basis * (pe + el.basis * pw)
	var elbow := arm_in.basis * pe
	sh.basis = _frame(to, parent.basis.inverse() * pole) * _frame(reach, elbow).inverse()
	# The hand, its turn about the forearm shared with the forearm (a turn about the forearm's own
	# line doesn't move the wrist).
	var w := wrists[side] as Node3D
	w.basis = _in_rig(el).basis.inverse() * target.basis
	var fore := pw.normalized()
	var q := w.basis.get_rotation_quaternion()
	var twist := wrapf(2.0 * atan2(Vector3(q.x, q.y, q.z).dot(fore), q.w), -PI, PI)
	if _twist_on:
		# (his ragdoll: carried on from its last step, so it never flips round as it passes half a turn)
		if _twist_was.has(side):
			twist = float(_twist_was[side]) + wrapf(twist - float(_twist_was[side]), -PI, PI)
		_twist_was[side] = twist
	el.basis = el.basis * Basis(fore, twist * FOREARM_SHARE)
	w.basis = _in_rig(el).basis.inverse() * target.basis
