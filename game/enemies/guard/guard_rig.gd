class_name GuardRig
extends SoldierRig
## The guard (the user's design: a black balaclava, tan pixel camo, an olive plate carrier, black
## gloves and boots; made from their Meshy model like CROSS, see art_source/guard). The rifle
## troopers, the pursuit squad and the sniper wear him (user), each with a rifle in both hands
## (GuardRifle).
##
## The rifle sits in his right fist on its pistol grip. Each frame the pose says where the rifle
## should be (its butt in his shoulder aiming at something, held low at the ready, across his chest
## at a run), and both arms reach for it: the right hand to the grip, then the left to the
## handguard. Each reach is a two-joint solve: the elbow bends so shoulder to wrist is the right
## length, the shoulder turns the arm onto the target with the elbow out to a natural side, and the
## wrist turns the hand to hold on. The legs, hips and back pose as CROSS's do (SoldierRig).

const GUARD_MODEL := preload("res://game/enemies/guard/guard.glb")
## How the rifle sits in the right fist: its barrel this far (rad) above the line of the hand (the
## pistol grip's rake), and nudged this far from the middle of the fist (fist axes: along the hand,
## toward the palm, toward the thumb).
const GRIP_RAKE := 0.15
const GRIP_NUDGE := Vector3(0.0, 0.0, 0.0)
## Where the butt goes, from the right shoulder joint in the chest's axes (in toward his middle,
## up, forward): the pocket of the shoulder.
const POCKET := Vector3(-0.09, 0.03, -0.06)
## At the ready (standing guard): held low across him, its grip here (chest axes, from the chest
## joint), the muzzle down and to his left.
const READY_GRIP := Vector3(0.11, -0.34, -0.17)
const READY_AHEAD := Vector3(-0.5, -0.38, -0.78)
## At a run (port arms): the rifle across his chest, its grip here (chest axes, from the chest joint)
## and its barrel pointing up to his left.
const PORT_GRIP := Vector3(0.12, -0.32, -0.2)
const PORT_AHEAD := Vector3(-0.55, 0.8, -0.25)
## The left hand under the handguard: which way its fingers run, and its palm faces (rifle axes).
const SUPPORT_RUN := Vector3(0.9, 0.25, -0.4)
const SUPPORT_PALM := Vector3(0.35, 1.0, 0.0)
## Which way the elbows go (chest axes; right, left): at the ready, down by his sides; at a run, down
## and a little out; aiming, the right out to the side and the left down under the rifle; lying in a
## nest, down onto the floor (his chest's front, -Z, faces the floor then).
const POLES_READY: Array[Vector3] = [Vector3(0.35, -1.0, 0.35), Vector3(-0.35, -1.0, 0.1)]
const POLES_PORT: Array[Vector3] = [Vector3(0.5, -1.0, 0.4), Vector3(-0.5, -1.0, 0.1)]
const POLES_AIM: Array[Vector3] = [Vector3(0.8, -0.6, 0.2), Vector3(-0.25, -1.0, -0.1)]
const POLES_PRONE: Array[Vector3] = [Vector3(0.5, -0.2, -1.0), Vector3(-0.5, -0.2, -1.0)]
## A shot: how long the kick takes to settle (s), how far the muzzle flips up and the rifle comes
## back into his shoulder at its peak.
const KICK_TIME := 0.15
const KICK_LIFT := 0.14
const KICK_BACK := 0.035
## Shot (not down): a jolt back, this long.
const FLINCH_TIME := 0.22
## How much of a hand's turn about the forearm the forearm takes (turned at the elbow), the rest at
## the wrist, so no one joint twists the skin too far (holding the handguard palm up, the left hand
## turns over ~115 degrees): as CROSS's hands-up shares it.
const FOREARM_SHARE := 0.5
## Down: how long he takes to fall, face first, and how far into the fall he's left how he was.
const FALL_TIME := 0.55
const FALL_BLEND := 0.3
## The flash at a rifle's muzzle, bigger than the pistol's.
const RIFLE_FLASH := 1.5

var kind: GuardRifle.Kind = GuardRifle.Kind.CARBINE
var rifle: Node3D
## The rifle in the right wrist joint's frame.
var _attach := Transform3D.IDENTITY
var _scope: Node3D
var _lens: Node3D
var _duck := 0.0
## < 0 on his feet; 0 .. 1 falling; 1 down. And how he was when he started to fall (to blend from).
var _fall := -1.0
var _fall_from: Array = []
var _flinch := 0.0
## What he's aiming at (this rig's space).
var _target := Vector3(0, 1.2, -10)
var _airborne := false
var _rising := true
var _prone := false
## Settled, and given the same state as last time: nothing to re-pose.
var _still := false
## Moving on his own (see pose_to()): the state, and how much longer.
var _held := {}
var _held_left := 0.0
## Where the elbows go this frame (chest axes; see POLES_*).
var _poles: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _body_joints: Array[Node3D] = []


func _init(rifle_kind: GuardRifle.Kind = GuardRifle.Kind.CARBINE) -> void:
	super(GUARD_MODEL, "", "GUARD")
	kind = rifle_kind
	_body_joints = [hips, spine, chest, neck, head, leg_hips[-1], leg_hips[1], knees[-1], knees[1], ankles[-1], ankles[1]]
	_build_rifle()
	animate(0.0, {})


## A pose given before he's in the scene doesn't reach his skeleton: give it again now.
func _ready() -> void:
	_apply()
	_still = false
	set_process(_held_left > 0.0 or (_fall >= 0.0 and _fall < 1.0))


## Moving on his own, when the enemy that owns him has stopped posing him (a fall, a catch): posed
## from `s` every frame for `seconds` (and until a fall has finished).
func pose_to(s: Dictionary, seconds: float = 0.6) -> void:
	_held = s
	_held_left = seconds
	_still = false
	set_process(true)


func _process(delta: float) -> void:
	_held_left -= delta
	_still = false  # (he may be being moved: aim again from where he is now)
	animate(delta, _held)
	if _held_left <= 0.0 and (_fall < 0.0 or _fall >= 1.0):
		set_process(false)


## The guard carries a rifle, not CROSS's pistol: it's built once his hands are measured.
func _build_pistol() -> void:
	pass


func _build_rifle() -> void:
	rifle = Node3D.new()
	rifle.name = "Rifle"
	wrists[1].add_child(rifle)
	# In the fist: the barrel along the hand (raked up a little), the rifle's top toward the thumb,
	# its right side against the palm.
	var f := _frame(_hand_run[1], _hand_palm[1])
	var run := f.x
	var palm := f.y
	var top := f.z
	var ahead := run * cos(GRIP_RAKE) + top * sin(GRIP_RAKE)
	var up := top * cos(GRIP_RAKE) - run * sin(GRIP_RAKE)
	var mid: Vector3 = _hand_mid[1] + f * GRIP_NUDGE
	_attach = Transform3D(Basis(-palm, up, -ahead), mid)
	rifle.transform = _attach
	var gun := MeshInstance3D.new()
	gun.name = "Gun"
	gun.mesh = GuardRifle.mesh(kind)
	gun.material_override = GuardRifle.material()
	rifle.add_child(gun)
	_meshes.append(gun)
	_materials.append(gun.material_override)
	_slide = Node3D.new()  # (the pistol's; nothing slides on a rifle)
	rifle.add_child(_slide)
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	rifle.add_child(_muzzle)
	_muzzle.position = GuardRifle.muzzle(kind)
	_build_flash()
	if kind == GuardRifle.Kind.SNIPER:
		_scope = Node3D.new()
		_scope.name = "Scope"
		rifle.add_child(_scope)
		_scope.position = GuardRifle.scope_front()
	if kind == GuardRifle.Kind.CARBINE_LIGHT:
		# The light's lens, and its glare (a bright point in the dark, and on the rear-view CCTV).
		_lens = Node3D.new()
		_lens.name = "Light"
		rifle.add_child(_lens)
		_lens.position = GuardRifle.light_lens()
		var lens := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.03, 0.008)
		lens.mesh = box
		lens.material_override = PsxMaterials.glow(Color("fff2c0"))
		_lens.add_child(lens)
		var glare := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.3, 0.3)
		glare.mesh = quad
		glare.material_override = PsxMaterials.halo(Color(1.0, 0.93, 0.7, 0.85))
		_lens.add_child(glare)
		glare.position = Vector3(0, 0, -0.03)


## The front of the sniper's scope (null for the others): his laser and glint come from it.
func scope() -> Node3D:
	return _scope


## The squad's light (null for the others).
func light() -> Node3D:
	return _lens


## Where shots leave the rifle (world space).
func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle.is_inside_tree() else global_position + Vector3.UP * 1.3


## A shot: the rifle kicks up into his shoulder and the muzzle flashes (a new shape, size and reach
## each time, as CROSS's does). There's no lamp: the flash lamp is the player's.
func fire() -> void:
	_kick = 1.0
	_still = false
	var shape := _flash_rng.randf()
	(_flash_star.material_override as ShaderMaterial).set_shader_parameter("seed", shape)
	(_flash_tongues.material_override as ShaderMaterial).set_shader_parameter("seed", shape)
	_flash_size = _flash_rng.randf_range(0.85, 1.2) * RIFLE_FLASH
	_flash_reach = _flash_rng.randf_range(0.8, 1.3) * RIFLE_FLASH
	_flash_tongues.rotation.z = _flash_rng.randf() * TAU


## Shot, not down: a jolt.
func flinch() -> void:
	_flinch = 1.0
	_still = false


## Down: he falls on his face (and stays there), on his own.
func fall() -> void:
	if _fall < 0.0:
		_fall_from = _snap()
		_fall = 0.0
		pose_to({})


func is_down() -> bool:
	return _fall >= 1.0


## Every frame he's to move (the enemy calls it), from his state: `run` 0..1 (how fast, of a full
## run), `airborne` (and `rising`), `duck` (sliding under something), `aim` (the rifle up at
## `target`, world space), `prone` (lying in a sniper's nest). fire(), flinch() and fall() start
## their own moves. Settled and given the same state again, he's left as he is (cheap to call).
func animate(delta: float, s: Dictionary) -> void:
	if _still and s == _last_state:
		return
	_last_state = s.duplicate()
	var target_run: float = s.get("run", 0.0)
	_run = move_toward(_run, target_run, delta * 4.0)
	_phase = fmod(_phase + delta * TAU * 1.55 * maxf(target_run, 0.2), TAU)
	var aiming: bool = s.get("aim", false)
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * 6.0)
	var ducking: bool = s.get("duck", false)
	_duck = move_toward(_duck, 1.0 if ducking else 0.0, delta * 8.0)
	_kick = maxf(0.0, _kick - delta / KICK_TIME)
	_flinch = maxf(0.0, _flinch - delta / FLINCH_TIME)
	if _fall >= 0.0:
		_fall = minf(1.0, _fall + delta / FALL_TIME)
	_airborne = s.get("airborne", false)
	_rising = s.get("rising", true)
	_prone = s.get("prone", false)
	if s.has("target") and is_inside_tree():
		_target = global_transform.affine_inverse() * (s["target"] as Vector3)
	_flash(delta)
	_pose_body()
	_hold(_rifle_target())
	_show_flash()
	_apply()
	_still = (_run == target_run and target_run == 0.0 and (_aim == 0.0 or _aim == 1.0) and (_duck == 0.0 or _duck == 1.0)
			and _kick == 0.0 and _flinch == 0.0 and (_fall < 0.0 or _fall >= 1.0) and _flash_left <= 0.0)


# --- The body ------------------------------------------------------------------------------------

func _pose_body() -> void:
	_reset()
	if _prone:
		_pose_prone()
	elif _fall >= 0.0:
		_pose_fall()
		if not _fall_from.is_empty():
			# From however he was standing, running or sliding when he was hit, not in one jump.
			var t := clampf(_fall / FALL_BLEND, 0.0, 1.0)
			_blend_from(_fall_from, t * t * (3.0 - 2.0 * t))
	else:
		if _airborne:
			_pose_jump(_rising)
		elif _run < 0.05:
			_pose_guard()
		else:
			_pose_run()
		if _duck > 0.0:
			# Into the slide (as CROSS slides), blended so he drops into it.
			var from := _snap()
			_reset()
			_pose_slide()
			_blend_from(from, _duck * _duck * (3.0 - 2.0 * _duck))
	var a := _aim * _aim * (3.0 - 2.0 * _aim)
	if a > 0.0 and not _prone and _fall < 0.0:
		# Aiming: turned toward what he's aiming at (hips, back and chest each taking a share, so
		# his left hand still reaches the handguard aiming off to his side), side-on behind the
		# rifle (his left shoulder forward), his head turned back to look down it, tilted onto the
		# stock.
		var yaw := atan2(-_target.x, -_target.z)  # + to his left
		hips.rotation.y += 0.3 * yaw * a
		spine.rotation.y += 0.35 * yaw * a
		chest.rotation.y += (0.35 * yaw - 0.45) * a
		head.rotation.y += 0.25 * a
		head.rotation.x -= 0.12 * a
		head.rotation.z -= 0.12 * a
	if _flinch > 0.0:
		var j := sin(_flinch * PI) * _flinch
		spine.rotation.x += 0.3 * j
		head.rotation.x += 0.25 * j


## Standing guard: feet a little apart, the left a half step ahead, knees soft.
func _pose_guard() -> void:
	hips.position.y = _hip_y - 0.03
	spine.rotation.x = -0.05
	leg_hips[-1].rotation.x = 0.18
	knees[-1].rotation.x = -0.2
	ankles[-1].rotation.x = 0.02
	leg_hips[1].rotation.x = -0.1
	knees[1].rotation.x = -0.1
	ankles[1].rotation.x = 0.1


## Lying on his front in a sniper's nest (head toward -Z), propped on both elbows, looking ahead
## along the rifle; legs a little apart.
func _pose_prone() -> void:
	hips.position = Vector3(0, 0.16, 0)
	hips.rotation.x = -PI / 2.0
	spine.rotation.x = 0.2
	chest.rotation.x = 0.15
	neck.rotation.x = 0.35
	head.rotation.x = 0.3
	for side in [-1, 1]:
		leg_hips[side].rotation.z = side * 0.12
		ankles[side].rotation.x = 0.6


## Falling on his face: pitching over his feet (gravity: slow, then fast), his knees giving on the
## way down; down, he lies flat, his head turned to one side.
func _pose_fall() -> void:
	var p := _fall * _fall
	var tip := p * PI / 2.0
	var h := _hip_y
	var lie := 0.16 * p  # down, the body's thickness off the floor
	hips.position = Vector3(0, h * cos(tip) + lie, -h * sin(tip))
	hips.rotation.x = -tip
	var buckle := sin(_fall * PI)
	for side in [-1, 1]:
		knees[side].rotation.x = -0.7 * buckle
		leg_hips[side].rotation.x = 0.35 * buckle
		leg_hips[side].rotation.z = side * 0.1 * p
	spine.rotation.x = -0.2 * buckle
	head.rotation.y = 0.9 * p
	head.rotation.x = 0.3 * p


## The body joints' turns and the hips' place, to blend from.
func _snap() -> Array:
	var out: Array = [hips.position]
	for j in _body_joints:
		out.append(j.quaternion)
	return out


func _blend_from(from: Array, t: float) -> void:
	hips.position = (from[0] as Vector3).lerp(hips.position, t)
	for i in _body_joints.size():
		_body_joints[i].quaternion = (from[i + 1] as Quaternion).slerp(_body_joints[i].quaternion, t)


# --- The rifle and the arms ----------------------------------------------------------------------

## Where the rifle should be this frame (this rig's space).
func _rifle_target() -> Transform3D:
	var ch := _in_rig(chest)
	var pocket := _pocket(ch)
	# At the ready: held low across him, the muzzle down to his left (in the chest's axes, so it moves
	# with him).
	var xf := Transform3D(ch.basis * Basis.looking_at(READY_AHEAD, Vector3(0, 0.3, -1)), ch * READY_GRIP)
	_poles = POLES_READY.duplicate()
	# At a run (or hopping, or sliding): across his chest.
	var carry := maxf(_run, maxf(_duck, 1.0 if _airborne else 0.0))
	if carry > 0.0 and not _prone:
		var port := Transform3D(ch.basis * Basis.looking_at(PORT_AHEAD, Vector3(0, 0.2, -1)), ch * PORT_GRIP)
		xf = xf.interpolate_with(port, clampf(carry, 0.0, 1.0))
		for i in 2:
			_poles[i] = _poles[i].lerp(POLES_PORT[i], clampf(carry, 0.0, 1.0))
	# Aiming: butt in the shoulder, the barrel at the target.
	var a := 1.0 if _prone else _aim * _aim * (3.0 - 2.0 * _aim)
	if a > 0.0:  # (falling, it eases out as his aim drops)
		var look := _target - pocket
		if look.length() > 0.5:
			var aim_basis := Basis.looking_at(look.normalized(), Vector3.UP)
			xf = xf.interpolate_with(Transform3D(aim_basis, pocket - aim_basis * GuardRifle.butt(kind)), a)
			for i in 2:
				_poles[i] = _poles[i].lerp(POLES_PRONE[i] if _prone else POLES_AIM[i], a)
	if _fall >= 0.0:
		# Falling, he lets it go down with him: on the floor by his right side as he lands.
		var dropped_basis := Basis(Vector3.FORWARD, PI / 2.0)
		var dropped := Transform3D(dropped_basis, Vector3(0.38, 0.05, -1.05))
		xf = xf.interpolate_with(dropped, clampf((_fall - 0.4) / 0.6, 0.0, 1.0))
	if _kick > 0.0:
		# The kick: the muzzle flips up about the butt, and the rifle comes back into his shoulder.
		var k := _kick * _kick
		var butt := xf * GuardRifle.butt(kind)
		var flip := Basis(xf.basis.x, KICK_LIFT * k)
		xf = Transform3D(flip * xf.basis, butt + flip * (xf.origin - butt) + xf.basis.z * KICK_BACK * k)
	return xf


## The pocket of his right shoulder, this rig's space.
func _pocket(ch: Transform3D) -> Vector3:
	return _in_rig(shoulders[1]).origin + ch.basis * POCKET


## Both hands onto the rifle at `xf`: the right to its grip, then the left to its handguard (where
## the rifle ended up, in case the right arm couldn't quite reach).
func _hold(xf: Transform3D) -> void:
	var ch := _in_rig(chest).basis
	_reach(1, xf * _attach.affine_inverse(), ch * _poles[0])
	var r := _in_rig(rifle)
	if _fall > 0.6:
		# Down: the left arm flung out ahead on the floor, palm down.
		var t := clampf((_fall - 0.6) / 0.4, 0.0, 1.0)
		var flung := _frame(Vector3(-0.3, 0, -1), Vector3.DOWN) * _frame(_hand_run[-1], _hand_palm[-1]).inverse()
		var at := Vector3(-0.5, 0.08, -2.05) - flung * (_hand_mid[-1] as Vector3)
		var held := _left_on(r)
		_reach(-1, Transform3D(held.basis.slerp(flung, t), held.origin.lerp(at, t)), ch * _poles[1])
		return
	_reach(-1, _left_on(r), ch * _poles[1])


## Where the left wrist goes to hold the rifle at `r` under its handguard.
func _left_on(r: Transform3D) -> Transform3D:
	var hand := _frame(r.basis * SUPPORT_RUN, r.basis * SUPPORT_PALM) * _frame(_hand_run[-1], _hand_palm[-1]).inverse()
	return Transform3D(hand, r * GuardRifle.support(kind) - hand * (_hand_mid[-1] as Vector3))


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
	el.basis = el.basis * Basis(fore, twist * FOREARM_SHARE)
	w.basis = _in_rig(el).basis.inverse() * target.basis


## The muzzle flash, while the kick's still fresh (as CROSS's, without its lamp).
func _show_flash() -> void:
	var u := (1.0 - _kick) / FLASH_TIME
	var on := _kick > 0.0 and u < 1.0
	_muzzle_flash.visible = on
	if on:
		for m: MeshInstance3D in [_flash_star, _flash_tongues]:
			(m.material_override as ShaderMaterial).set_shader_parameter("heat", 1.0 - u)
		_flash_star.scale = Vector3.ONE * _flash_size * (0.8 + 0.7 * u)
		_flash_tongues.scale = Vector3(_flash_size, _flash_size, _flash_reach * (0.7 + 0.9 * u))
