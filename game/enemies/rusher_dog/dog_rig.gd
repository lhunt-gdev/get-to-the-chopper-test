class_name DogRig
extends Node3D
## The guard dog (the user's Meshy German Shepherd in a tactical vest), a PS1-style low-poly model
## (3,000 triangles, a 512 texture) rigged with a dog's 19 bones (hips, spine, chest, neck, head, two
## in the tail, and three in each leg) by art_source/operative/tools/build_dog.sh, about 0.72 m at
## the shoulder.
##
## Posed procedurally, as SoldierRig poses CROSS: joint nodes at the bones' rest positions, turned
## by the poses, their transforms copied onto the skeleton's bones each time he's posed. Faces -Z.
## Joint signs: +x turns a leg forward (from the shoulder or hip down), the body nose-up (hips,
## chest), the head and neck up, the tail down.

const MODEL := preload("res://game/enemies/rusher_dog/dog.glb")
## The skeleton's bones, parents before children, and each one's parent.
const TREE := {
	"Hips": "", "Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck",
	"Tail1": "Hips", "Tail2": "Tail1",
	"FrontUpperR": "Chest", "FrontLowerR": "FrontUpperR", "FrontPawR": "FrontLowerR",
	"FrontUpperL": "Chest", "FrontLowerL": "FrontUpperL", "FrontPawL": "FrontLowerL",
	"HindUpperR": "Hips", "HindLowerR": "HindUpperR", "HindFootR": "HindLowerR",
	"HindUpperL": "Hips", "HindLowerL": "HindUpperL", "HindFootL": "HindLowerL",
}
## A gallop's strides per second at a full run.
const STRIDES := 3.0
## The rotary gallop (user: each leg on its own timing, as a dog's): when in the stride each foot
## lands (fraction of a stride): the left hind, the right hind a moment later, then the right fore,
## then the left fore, round his body.
const FOOTFALL := {"HindL": 0.0, "HindR": 0.1, "FrontR": 0.45, "FrontL": 0.55}
## How much of a stride each foot is on the ground (the rest it's in the air, swinging forward).
const STANCE := 0.34
## The bite: how long his leap at you takes (s).
const LUNGE_TIME := 0.45
## Down: how long he takes to drop onto his side (s).
const DROP_TIME := 0.3
## Barking: barks a second.
const BARKS := 2.6

## Bone name -> its joint node.
var joints := {}
var _skeleton: Skeleton3D
var _sk_xf := Transform3D.IDENTITY
var _drivers := {}
var _rest := {}
var _order: Array[int] = []
var _hips_at := Vector3.ZERO
var _phase := 0.0
var _run := 0.0
var _time := 0.0
var _crouch := 0.0
var _wag := 0.0
## The bite's leap: < 0 none, else how far through it (0..1).
var _lunge := -1.0
## Down: < 0 on his feet, else how far into the drop (0..1); and how he stood when shot.
var _down := -1.0
var _down_from: Array = []
var _last := {}
var _held_left := 0.0


func _init() -> void:
	name = "DOG"
	_build()


func _ready() -> void:
	_apply()  # (a pose given before he's in the scene doesn't reach his skeleton)
	set_process((_down >= 0.0 and _down < 1.0) or _held_left > 0.0)


## He's shot: he drops onto his side, on his own (nothing else need pose him), and stays there.
func fall() -> void:
	if _down >= 0.0:
		return
	_down_from = _snap()
	_down = 0.0
	set_process(true)


## The bite: a leap at you, front legs up, as he gets to you (carrying on with what he was doing).
func lunge() -> void:
	_lunge = 0.0


## Moving on his own, when nothing else poses him any more (the run's over): posed from `s` every
## frame for `seconds` (a leap finishes, a gallop slows to a stand).
func pose_to(s: Dictionary, seconds: float) -> void:
	_last = s
	_held_left = seconds
	set_process(true)


func is_down() -> bool:
	return _down >= 1.0


func _process(delta: float) -> void:
	_held_left -= delta
	animate(delta, _last)
	if (_down >= 1.0 or _down < 0.0) and _held_left <= 0.0:
		set_process(false)


func _build() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_sk_xf = _in_rig(_skeleton)
	# His texture through the game's PS1 shader, like everything else.
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var src := mi.get_active_material(0) as BaseMaterial3D
		mi.material_override = PsxMaterials.textured(src.albedo_texture if src else null)
	for bone: String in TREE:
		var b := _skeleton.find_bone(bone)
		_order.append(b)
		_rest[b] = _skeleton.get_bone_global_rest(b).orthonormalized()
		var at: Vector3 = _sk_xf * (_rest[b] as Transform3D).origin
		var parent: Node3D = self if TREE[bone] == "" else joints[TREE[bone]]
		var parent_at := Vector3.ZERO if TREE[bone] == "" else _sk_xf * (_rest[_skeleton.find_bone(TREE[bone])] as Transform3D).origin
		var j := Node3D.new()
		j.name = bone
		j.position = at - parent_at
		parent.add_child(j)
		joints[bone] = j
		_drivers[b] = j
	_hips_at = (joints["Hips"] as Node3D).position
	_apply()


## `node`'s transform in this rig's space.
func _in_rig(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Copy the joint nodes' pose onto the skeleton (as SoldierRig does).
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


func _reset() -> void:
	for j: Node3D in joints.values():
		j.basis = Basis.IDENTITY
	(joints["Hips"] as Node3D).position = _hips_at


func _j(n: String) -> Node3D:
	return joints[n]


## From his state: `run` 0..1 (a gallop, how fast), `wag` (his tail wagging, standing guard),
## `bark` (crouched, front down, barking), `leap` 0..1 (stretched out over something he's bounding
## over). lunge() and fall() start their own moves.
func animate(delta: float, s: Dictionary) -> void:
	_last = s
	_time += delta
	var target_run: float = s.get("run", 0.0)
	_run = move_toward(_run, target_run, delta * 4.0)
	_phase = fmod(_phase + delta * TAU * STRIDES * maxf(target_run, 0.25), TAU)
	_crouch = move_toward(_crouch, 1.0 if s.get("bark", false) else 0.0, delta * 7.0)
	_wag = move_toward(_wag, 1.0 if s.get("wag", false) else 0.0, delta * 3.0)
	if _lunge >= 0.0:
		_lunge += delta / LUNGE_TIME
		if _lunge >= 1.0:
			_lunge = -1.0
	if _down >= 0.0:
		_down = minf(1.0, _down + delta / DROP_TIME)
	_reset()
	if _down >= 0.0:
		_pose_down()
		var t := _down * _down * (3.0 - 2.0 * _down)
		_blend_from(_down_from, t)
	else:
		_pose_stand()
		if _run > 0.0:
			_pose_gallop(_run)
		if _crouch > 0.0:
			_pose_bark(_crouch)
		var leap: float = s.get("leap", 0.0)
		if _lunge >= 0.0:
			leap = maxf(leap, sin(_lunge * PI))
		if leap > 0.0:
			_pose_leap(leap)
		if _wag > 0.0:
			_j("Tail1").rotation.y = 0.35 * _wag * sin(_time * 11.0)
			_j("Tail2").rotation.y = 0.3 * _wag * sin(_time * 11.0 - 0.9)
	_apply()


## Every joint's turn and the hips' place, to blend from.
func _snap() -> Array:
	var out: Array = [(joints["Hips"] as Node3D).position]
	for n in TREE:
		out.append((joints[n] as Node3D).quaternion)
	return out


func _blend_from(from: Array, t: float) -> void:
	if from.is_empty():
		return
	var h := _j("Hips")
	h.position = (from[0] as Vector3).lerp(h.position, t)
	var i := 1
	for n in TREE:
		var j := _j(n)
		j.quaternion = (from[i] as Quaternion).slerp(j.quaternion, t)
		i += 1


## The bark (the telegraph): crouched in a bow, front down on folded front legs (paws out ahead,
## flat on the floor) and back legs bunched to spring, head low and out, jerking up with each bark,
## tail up.
func _pose_bark(k: float) -> void:
	_j("Hips").position.y -= 0.05 * k
	_j("Hips").rotation.x -= 0.12 * k  # front down
	_j("Chest").rotation.x -= 0.08 * k
	for s in ["R", "L"]:
		_j("FrontUpper" + s).rotation.x += 0.5 * k
		_j("FrontLower" + s).rotation.x += 1.2 * k
		_j("FrontPaw" + s).rotation.x -= 1.5 * k
		_j("HindUpper" + s).rotation.x += 0.3 * k
		_j("HindLower" + s).rotation.x -= 0.45 * k
		_j("HindFoot" + s).rotation.x += 0.25 * k
	var bark := maxf(0.0, sin(_time * TAU * BARKS))
	_j("Neck").rotation.x += (-0.2 + 0.3 * bark) * k
	_j("Head").rotation.x += (-0.1 + 0.2 * bark) * k
	_j("Tail1").rotation.x -= 0.5 * k  # up


func _pose_stand() -> void:
	_j("Neck").rotation.x = 0.05  # (his tail hangs as modelled)


## A dog's rotary gallop: each foot lands on its own beat round his body (FOOTFALL); each leg on
## the ground sweeps back under him as it pushes (its paw flat on the floor), then lifts, folds up and
## swings forward to reach for the next landing. His back arches as his hind legs reach forward under
## him and stretches out as his front legs reach ahead; he's off the ground twice a stride (stretched
## out, then gathered up), his head kept level; the tail streams out behind.
func _pose_gallop(r: float) -> void:
	var u := _phase / TAU
	var bend := cos(TAU * (u - 0.95))  # 1 gathered (hind legs forward under him), -1 stretched out
	_j("Hips").position.y = _hips_at.y + r * (0.03 * cos(2.0 * TAU * (u - 0.45)) - 0.02)  # up in each flight
	_j("Hips").rotation.x = 0.1 * r * bend  # the rump tucks under...
	_j("Chest").rotation.x = -0.18 * r * bend  # ...and the shoulders drop: the back arches
	_j("Neck").rotation.x = 0.05 + 0.12 * r * bend  # (the head stays level)
	_j("Tail1").rotation.x = -0.4 * r  # streaming out behind, a little low
	_j("Tail2").rotation.x = 0.1 * r + 0.15 * r * bend  # (the end hanging, swinging with his back)
	for leg: String in FOOTFALL:
		var front := leg.begins_with("Front")
		var s := leg.right(1)
		var a := _stride(fposmod(u - float(FOOTFALL[leg]), 1.0), front)
		var names: Array = ["FrontUpper", "FrontLower", "FrontPaw"] if front else ["HindUpper", "HindLower", "HindFoot"]
		for i in 3:
			_j(String(names[i]) + s).rotation.x = r * float(a[i])


## One leg through its stride (`u` 0..1 from its foot's landing): [upper, lower, paw] turns. On the
## ground (STANCE): from reaching forward to pushed back behind him, a front paw kept flat on the
## floor as the leg rolls over it, a back leg's knee and hock giving a little under his weight. In the
## air: swung forward again, folding up (the paw tucked) and opening out to land.
static func _stride(u: float, front: bool) -> Array:
	var reach := 0.55 if front else 0.5
	var back := -0.6 if front else -0.7
	if u < STANCE:
		var s := u / STANCE
		var up := lerpf(reach, back, s)
		if front:
			return [up, 0.0, -up * 0.9]
		var give := sin(PI * s)
		return [up, -0.25 * give, 0.3 * give]
	var t := (u - STANCE) / (1.0 - STANCE)
	var swing := lerpf(back, reach, t * t * (3.0 - 2.0 * t))
	var fold := sin(PI * minf(1.0, t * 1.15))
	if front:
		return [swing, 0.45 * fold, -1.4 * fold]
	return [swing, -0.9 * fold, 1.0 * fold]


## The lunge: rearing up off his back legs (the whole body nose-up about the hips), front legs
## reaching out ahead, back legs pushing off behind, head stretched forward.
func _pose_leap(k: float) -> void:
	_j("Hips").rotation.x += 0.45 * k
	_j("Hips").position.y += 0.12 * k
	_j("Neck").rotation.x -= 0.35 * k
	_j("Head").rotation.x -= 0.2 * k
	_j("Tail1").rotation.x -= 0.3 * k
	# (Each leg goes from wherever the gallop had it toward the leap, so it doesn't jump.)
	for s in ["R", "L"]:
		for jt: Array in [["FrontUpper", 1.1], ["FrontLower", 0.2], ["FrontPaw", -0.6], ["HindUpper", -0.7], ["HindLower", 0.2], ["HindFoot", -0.3]]:
			var j := _j(String(jt[0]) + s)
			j.rotation.x = lerpf(j.rotation.x, float(jt[1]), k)


## Down: lying on his side, legs out limp, head on the floor.
func _pose_down() -> void:
	var h := _j("Hips")
	h.rotation.z = PI / 2.0 - 0.1  # onto his right side
	h.position = Vector3(_hips_at.x - _hips_at.y + 0.17, 0.17, _hips_at.z)
	_j("Neck").rotation.x = -0.3
	_j("Head").rotation.x = -0.15
	_j("Tail1").rotation.x = -0.6
	for s in ["R", "L"]:
		_j("FrontUpper" + s).rotation.x = 0.35
		_j("FrontPaw" + s).rotation.x = -0.4
		_j("HindUpper" + s).rotation.x = -0.25
		_j("HindLower" + s).rotation.x = -0.3
