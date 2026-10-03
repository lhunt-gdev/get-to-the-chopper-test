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

## The model, rigged (exported from art_source/operative/tools/stage4_rig.py).
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
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[Material] = []
var _skeleton: Skeleton3D
## Skeleton space to this rig's space.
var _sk_xf := Transform3D.IDENTITY
## Bone index -> the node whose transform (in this rig's space) poses that bone.
var _drivers := {}
## Bone index -> its rest transform in skeleton space.
var _rest := {}
## Bones, parents first.
var _order: Array[int] = []


func _init() -> void:
	name = "CROSS"
	_build()
	scale = Vector3.ONE * SIZE


## --- Building ---------------------------------------------------------------------------------

func _joint(parent: Node3D, pos: Vector3, joint_name: String) -> Node3D:
	var j := Node3D.new()
	j.name = joint_name
	j.position = pos
	parent.add_child(j)
	return j


## A box part on `joint` (the pistol), `size`, centred at `pos` in the joint's space.
func _part(joint: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = PsxMaterials.flat(color)
	joint.add_child(m)
	_meshes.append(m)
	_materials.append(m.material_override)
	return m


func _build() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_sk_xf = _in_rig(_skeleton)
	# His texture, through the game's PS1 shader (stepped lighting from the lamps you can see, the
	# vertex wobble, affine texturing) like everything else.
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var src := mi.get_active_material(0) as BaseMaterial3D
		var mat := PsxMaterials.textured(src.albedo_texture if src else null)
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


## The lens positions from LENS_FILE (none if it's missing).
func _lenses() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var f := FileAccess.open(LENS_FILE, FileAccess.READ)
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
## `surrender`, `aim` (FIRE held: the gun up).
## Joint signs (the model faces -Z): spine, neck, head: -x leans forward. Shoulders, leg hips:
## +x swings the limb forward. Elbows: +x bends the forearm up and forward. Knees: -x folds the
## shin back. Shoulder z: side * angle raises the arm out to its side.
func animate(delta: float, s: Dictionary) -> void:
	_last_state = s
	_flash(delta)
	if s.get("surrender", false):
		_pose_surrender()
		# A shot just before the catch doesn't stay frozen on: the gun settles, the flash goes.
		_aim = 0.0
		_kick = 0.0
		_slide.position.z = 0.0
		_muzzle_flash.visible = false
		_flash_light.visible = false
		_shrug()
		_apply()
		return
	var target_run: float = s.get("run", 0.0)
	_run = move_toward(_run, target_run, delta * 4.0)
	_phase = fmod(_phase + delta * TAU * 1.55 * maxf(target_run, 0.2), TAU)
	_reset()
	var cover := String(s.get("cover", ""))
	if cover == "crouch":
		_pose_crouch()
	elif cover == "stand":
		_pose_stand()
	elif s.get("sliding", false):
		_pose_slide()
	elif s.get("airborne", false):
		_pose_jump(s.get("rising", true))
	elif _run < 0.05:
		_pose_stand()
	else:
		_pose_run()
	var stun: float = s.get("stun", 0.0)
	if stun > 0.0:  # pitched forward, arms flung out, wobbling
		spine.rotation.x -= 0.5 * stun + 0.12 * sin(stun * 40.0)
		for side in [-1, 1]:
			shoulders[side].rotation.z = side * 0.9 * stun
	rotation.z = -float(s.get("lean", 0.0)) * 0.18  # into a lane change
	_aim_and_recoil(delta, s.get("aim", false))
	_shrug()
	_apply()


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


func _pose_slide() -> void:
	# Down low, feet first: leaning back, the lead leg out straight, the other folded under.
	hips.position.y = _kneel_y - 0.12  # down low
	spine.rotation.x = 0.8
	head.rotation.x = -0.55
	leg_hips[-1].rotation.x = 1.45
	knees[-1].rotation.x = -0.1
	leg_hips[1].rotation.x = 0.7
	knees[1].rotation.x = -1.9
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


## Hit: the whole model flashes red for a moment.
func flash() -> void:
	_flash_left = 0.15
	var red := PsxMaterials.flat(Color("d83a2a"))
	for m in _meshes:
		m.material_override = red


func _flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		for i in _meshes.size():
			_meshes[i].material_override = _materials[i]
