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
##
## Unarmed (the scout, the alarm runner: another model built the same way), his arms swing free as
## CROSS's do, and the same reach puts his hand on what he's reaching for (the alarm panel).

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
## The boss's minigun, carried at the hip: its grip here (chest axes, from the chest joint), and how
## fast its barrels spin flat out (rad/s).
## The minigun's grip (from his hips joint, in his chest's facing; [waiting, spun up]): in at his hip,
## then pushed out at his right side as he commits.
const HIP_GRIP: Array[Vector3] = [Vector3(0.29, 0.12, -0.16), Vector3(0.31, 0.1, -0.2)]
const SPIN_RATE := 45.0
## The boss's stance (user: "a cool action ready stance"; from a panel of four designs, judged):
## waiting, tall and square with his chest out (the skull on it showing), chin down; as the barrels
## spin up he commits, sinking, his hips rocking forward onto his front foot and tipping, his back
## leaning in and his chest rounding over the gun. Each a pair: [waiting, spun up]. How far down
## he sinks (m, his own size); his hips forward (- ahead), turned to his right (+ to his left) and
## tipped (- forward); his back's lean and his chest (- forward, + back); the turn his back and
## chest give back toward you.
const BRACE_DROP := 0.1
const BRACE_SPIN_DROP := 0.035
const BRACE_HIPS_AHEAD := [0.01, -0.03]
const BRACE_HIPS_TURN := [-0.18, -0.3]
const BRACE_HIPS_TIP := [0.0, -0.2]
const BRACE_SPINE := [0.0, -0.18]
const BRACE_CHEST := [0.07, -0.12]
const BRACE_SPINE_TURN := [0.06, 0.16]
const BRACE_CHEST_TURN := [0.02, 0.1]
## His neck stacked on his shoulders, and how far his face is tipped down (chin down, glaring from
## under his brow at you, the same waiting or spun up: the head makes up whatever his back does).
const BRACE_NECK := 0.03
const BRACE_GAZE := -0.12
## His feet (ankles, this rig's space; the left a step forward, the right back and wide, so the deck
## shows between his legs from the game camera) and how far each is turned out (+ to his left).
const BRACE_FEET := {-1: Vector2(-0.27, -0.21), 1: Vector2(0.35, 0.28)}
const BRACE_TOES := {-1: 0.1, 1: -0.8}
## His elbows (chest axes; right, left): the right down and back behind the grip, the left out wide
## and low, so his forearm reaches the top handle under the skull, not across it.
const BRACE_POLES: Array[Vector3] = [Vector3(0.7, -0.85, 0.55), Vector3(-1.0, -0.3, 0.05)]
const BREATH_RATE := 2.2
## The boss's death (his KO replay; user: hit, he drops the minigun, he's pushed off his feet,
## twists round "one or twice" and lands face up in a pool of blood). Times are on his death's own
## clock (s since he was killed: slowed for the replay, and wound back for each one); distances in
## this rig's units (his own size). The last hits land; his hands open; he's off his feet; he's down.
const DEATH_HITS: Array[float] = [0.0, 0.08, 0.16]
const DEATH_LET_GO := 0.08
const DEATH_LIFT := 0.18
const DEATH_LAND := 0.95
## How far back his hips land, how high they rise on the way, his turns about himself (whole turns,
## so he lands face up), how far his heading drifts round (he lands a little across), and how high
## his hips lie off the deck.
const DEATH_BACK := 1.45
const DEATH_RISE := 0.62
const DEATH_TWISTS := 2.0
const DEATH_DRIFT := 0.3
const DEATH_LIE := 0.22
## The minigun: when it hits the deck, and where it ends up (on its side, its motor down, barrels
## toward you and a little to his right: in front of where he stood, clear of the lane you run past in).
const GUN_LAND := 0.6
## How long his death runs on its own clock (s; the blood has spread by then).
const DEATH_END := 2.6
## Like a ragdoll (user: "he's very stiff can't you make it a little more human/rag doll looking?"):
## his body's path is set (above), but from the hits his muscles go slack and the rest of him moves
## under its own weight, worked out at this many steps a second of his death's clock. Gravity (this
## rig's units: 9.8 m/s² at 1.35 m to the unit); the share of a limb's speed it keeps each step in
## the air (and once he's down, settling), and of its slide along the deck.
const RAG_HZ := 120.0
const RAG_GRAVITY := 7.26
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
const GUN_YAW := -0.12
const GUN_REST := Transform3D(Basis(Vector3.UP, GUN_YAW) * Basis(Vector3.FORWARD, PI / 2.0), Vector3(0.26, 0.1, -0.4))
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
## Carrying a rifle (false: the scout).
var armed := true
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
## Unarmed, reaching: for what (this rig's space), and how far into the reach he is (0..1, eased).
var _reach_at := Vector3.ZERO
var _reach_w := 0.0
## The minigun: its spinning barrels, how fast they're going (0..1, eased) and whether it's firing.
var _barrels: Node3D
var _spin := 0.0
var _firing := false
## The minigun's ejection port (its cases come out here).
var _eject: Node3D
## Braced (the boss's stance), and his breath.
var _brace := false
var _breath := 0.0
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
## The barrels' turn and spin when he was killed (they spin down from there as the gun falls).
var _barrels_from := 0.0
var _spin_from := 0.0


## rifle_kind: which rifle; model and rig_name: which character (the guard, or the scout);
## carries_rifle: false for no rifle at all (the scout).
func _init(rifle_kind: GuardRifle.Kind = GuardRifle.Kind.CARBINE, model: PackedScene = GUARD_MODEL,
		rig_name: String = "GUARD", carries_rifle: bool = true) -> void:
	super(model, "", rig_name)
	kind = rifle_kind
	armed = carries_rifle
	_body_joints = [hips, spine, chest, neck, head, leg_hips[-1], leg_hips[1], knees[-1], knees[1], ankles[-1], ankles[1]]
	for side in [-1, 1]:
		_ankle_rest[side] = _in_rig(ankles[side]).origin
	if not armed:  # his free arms blend too (into a slide, a fall), the reach's collarbone and hand too
		_body_joints.append_array([shoulders[-1], shoulders[1], elbows[-1], elbows[1], clavicles[-1], clavicles[1], wrists[-1], wrists[1]])
	if armed:
		_build_rifle()
	animate(0.0, {})


## Every joint in him (the hips first), for the boss's death, which poses them all.
func _all_joints() -> Array[Node3D]:
	var out: Array[Node3D] = [hips, spine, chest, neck, head]
	for side in [-1, 1]:
		out.append_array([clavicles[side], shoulders[side], elbows[side], wrists[side], leg_hips[side], knees[side], ankles[side]])
	return out


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
	if kind == GuardRifle.Kind.MINIGUN:
		_barrels = Node3D.new()
		_barrels.name = "Barrels"
		rifle.add_child(_barrels)
		_barrels.position = GuardRifle.SPIN_AXIS - GuardRifle.GRIP
		var b := MeshInstance3D.new()
		b.mesh = GuardRifle.barrels_mesh()
		b.material_override = GuardRifle.material()
		_barrels.add_child(b)
		_meshes.append(b)
		_materials.append(b.material_override)
		_eject = Node3D.new()
		_eject.name = "Eject"
		rifle.add_child(_eject)
		_eject.transform = GuardRifle.eject_port()
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


## The minigun's ejection port, world space: the cases fly out along its x (null for the others).
func eject_port() -> Node3D:
	return _eject


## The minigun going (its barrels up to speed and firing: a round every frame or so).
func is_firing() -> bool:
	return _firing


## Where shots leave the rifle (world space).
func muzzle_position() -> Vector3:
	return _muzzle.global_position if armed and _muzzle.is_inside_tree() else global_position + Vector3.UP * 1.3


## A shot: the rifle kicks up into his shoulder and the muzzle flashes (a new shape, size and reach
## each time, as CROSS's does). There's no lamp: the flash lamp is the player's.
func fire() -> void:
	if not armed:
		return
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


## The boss is killed: how he stands now (his hips' place and every joint's turn), and his minigun
## (this rig's space), for pose_death() to start from, every time it's shown.
func death_start() -> Dictionary:
	var joints: Array[Quaternion] = []
	for j in _all_joints():
		joints.append(j.quaternion)
	_barrels_from = _barrels.rotation.z if _barrels != null else 0.0
	_spin_from = _spin
	set_process(false)  # (posed from now on by pose_death, not by a hold or a fall)
	if _flash_left > 0.0:
		_flash(_flash_left)  # (no red hit flash left on him)
	_flinch = 0.0
	_kick = 0.0
	var from := {"hips": hips.position, "joints": joints, "gun": _in_rig(rifle) if rifle != null else Transform3D.IDENTITY}
	var pts := _rag_points()
	var roots := _rag_roots()
	_rag = {"from": from, "pos": pts.duplicate(), "prev": pts.duplicate(), "n": 0, "samples": [], "bones": _rag_bones(pts, roots),
			"smooth": [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO], "twist": {},
			"waist_q": Quaternion(_in_rig(chest).basis.orthonormalized()), "waist_w": Vector3.ZERO}
	return from


## The boss's death at `t` (s on its own clock), from `from` (death_start()): the same t, the
## same pose, so it can be shown again from any angle. The last hits jolt him back; his hands open
## and the minigun falls (barrels spinning down), hits the deck and bounces onto its side; he's
## blasted up and back off his feet, going over backwards and twisting round twice, his limbs
## slack and swinging; he slams down on his back, his limbs flop onto the deck, and he lies still,
## face up. (Worked out as a ragdoll a step at a time as it's first needed, and a little ahead each
## time it's shown, so the replays are ready.)
func pose_death(t: float, from: Dictionary) -> void:
	_still = false
	if _rag.is_empty():
		return
	var last := int(ceil(DEATH_END * RAG_HZ))
	var need := mini(int(ceil(clampf(t, 0.0, DEATH_END) * RAG_HZ)) + 1, last)
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
	hips.position = (a[0] as Vector3).lerp(b[0], f)
	var joints: Array[Node3D] = _all_joints()
	for k in joints.size():
		joints[k].quaternion = (a[k + 1] as Quaternion).slerp(b[k + 1], f)
	_death_gun(t, from["gun"])
	_apply()


## The pose his body's path and his muscles would give him at `t`: the set path, and out of his
## stance, not in one jump (his upper body at once, his hips and legs as he leaves the deck: until
## then his feet stay where they were).
func _death_target(t: float, from: Dictionary) -> void:
	_reset()
	_death_body(t, from["hips"])
	var up := smoothstep(0.0, 0.12, t)
	var low := smoothstep(DEATH_LIFT - 0.02, DEATH_LIFT + 0.12, t)
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
	var down := smoothstep(DEATH_LAND, DEATH_LAND + 0.25, t)
	var still := smoothstep(DEATH_LAND + 0.4, DEATH_LAND + 0.9, t)
	var drag := lerpf(lerpf(RAG_DRAG, RAG_DRAG_DOWN, down), RAG_DRAG_STILL, still)
	var fall := RAG_GRAVITY * dt * dt * (1.0 - still)  # (lying, he stays where he fell: no slow sag)
	for i in pos.size():
		var p: Vector3 = pos[i]
		var v: Vector3 = (p - (prev[i] as Vector3)) * drag
		prev[i] = p
		pos[i] = (p + v + Vector3(0.0, -fall, 0.0)).lerp(target[i], _rag_pull(t, i))
	# Each hit knocks his arms and head back (away from you) and out.
	for h in DEATH_HITS:
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
	var alive_until := DEATH_LIFT if leg else 0.04
	var slack_by := DEATH_LIFT + 0.08 if leg else 0.16
	var air := RAG_PULL_HEAD if i == 12 else RAG_PULL_AIR
	var limp := RAG_PULL_HEAD_DOWN if i == 12 else RAG_PULL_DOWN
	var p := lerpf(1.0, air, smoothstep(alive_until, slack_by, t))
	p = lerpf(p, limp, smoothstep(DEATH_LAND, DEATH_LAND + 0.3, t))
	return p * (1.0 - smoothstep(DEATH_LAND + 0.4, DEATH_LAND + 0.9, t))  # (then none: he lies where he fell)


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
	if t < DEATH_LET_GO:
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
	var c := RAG_WAIST_C if t < DEATH_LAND else 2.0 * sqrt(RAG_WAIST_K)
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


func _death_body(t: float, hips_from: Vector3) -> void:
	var u := clampf((t - DEATH_LIFT) / (DEATH_LAND - DEATH_LIFT), 0.0, 1.0)  # through the air
	var e := u * u * (3.0 - 2.0 * u)
	var down := t >= DEATH_LAND
	var after := maxf(0.0, t - DEATH_LAND)
	# The hits: a jolt back at each.
	var jolt := 0.0
	for h in DEATH_HITS:
		var k := t - h
		if k >= 0.0 and k < 0.14:
			jolt += sin(k / 0.14 * PI) * 0.22
	# Off his feet: up and back (fast at first, blasted), going over backwards, twisting round.
	var y := lerpf(hips_from.y, DEATH_LIE, e) + DEATH_RISE * sin(PI * u) * (1.0 - 0.5 * u)
	var z := lerpf(hips_from.z, DEATH_BACK, 1.0 - (1.0 - u) * (1.0 - u))
	if down:
		# Down hard: a bounce, sliding a little further, then still.
		y = DEATH_LIE + 0.07 * sin(clampf(after / 0.16, 0.0, 1.0) * PI)
		z = DEATH_BACK + 0.08 * smoothstep(0.0, 0.3, after)
	hips.position = Vector3(hips_from.x * (1.0 - e), y, z)
	var pitch := PI / 2.0 * e
	var twist := TAU * DEATH_TWISTS * smoothstep(DEATH_LIFT, DEATH_LAND - 0.04, t)
	hips.basis = Basis(Vector3.UP, DEATH_DRIFT * e) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, twist)
	# Flailing in the air (each limb a little out of step); down, the limbs slap out on the deck.
	var air := sin(PI * u) if not down else 0.0
	var slap := smoothstep(0.0, 0.1, after) if down else 0.0
	for side in [-1, 1]:
		var wob := sin(t * 13.0 + side * 1.7) * air
		var out_air := Vector3(-0.35 + 0.25 * wob, 0.0, side * (1.2 + 0.3 * wob))
		var out_down := Vector3(-0.25 if side < 0 else -0.35, 0.0, side * (1.35 if side < 0 else 1.05))
		shoulders[side].rotation = out_air.lerp(out_down, slap) if down else out_air * maxf(air, smoothstep(DEATH_LET_GO, DEATH_LIFT + 0.1, t))
		elbows[side].rotation.x = lerpf(0.45 + 0.35 * wob, 0.35 if side < 0 else 0.45, slap)  # (never straight: limp arms bend a little)
		wrists[side].rotation.x = 0.2 * slap
		var leg_air := Vector3(0.55 * air + 0.15 * wob, 0.0, side * (0.12 + 0.15 * air))
		var leg_down := Vector3(0.05 if side < 0 else 0.4, 0.0, side * (0.14 if side < 0 else 0.2))
		leg_hips[side].rotation = leg_air.lerp(leg_down, slap) if down else leg_air
		knees[side].rotation.x = lerpf(-0.15 - 0.75 * air, -0.12 if side < 0 else -0.75, slap)
		ankles[side].rotation.x = lerpf(0.25 * air, 0.35, slap)
		# Coming down, twisting low over the deck: limbs pulled in along him (so none sweeps through
		# it), then thrown out as he slams down.
		var tuck := smoothstep(0.3, 0.6, u) * (1.0 - slap)
		if tuck > 0.0:
			shoulders[side].rotation = shoulders[side].rotation.lerp(Vector3(0.0, 0.0, side * 0.12), tuck)
			elbows[side].rotation.x = lerpf(elbows[side].rotation.x, 0.55, tuck)
			leg_hips[side].rotation = leg_hips[side].rotation.lerp(Vector3(0.0, 0.0, side * 0.06), tuck)
			knees[side].rotation.x = lerpf(knees[side].rotation.x, -0.05, tuck)
	# His back: jolted back by the hits, arched in the air, flat on the deck; his head thrown back,
	# then rolled to one side.
	spine.rotation.x = jolt + 0.2 * air + 0.04 * slap
	chest.rotation.x = 0.6 * jolt + 0.1 * air
	neck.rotation.x = 0.3 * jolt
	head.rotation.x = 0.8 * jolt + 0.3 * air + 0.15 * slap
	head.rotation.y = 0.75 * slap


## The minigun as he dies: in his hands as he was killed; let go, it drops (slowly, then fast),
## pitching nose down and rolling onto its side, hits the deck, bounces once and lies still; the
## barrels spin down.
func _death_gun(t: float, held: Transform3D) -> void:
	if rifle == null:
		return
	var xf := held
	if t > DEATH_LET_GO:
		var k := clampf((t - DEATH_LET_GO) / (GUN_LAND - DEATH_LET_GO), 0.0, 1.0)
		var at := Vector3(lerpf(held.origin.x, GUN_REST.origin.x, k), lerpf(held.origin.y, GUN_REST.origin.y, k * k),
				lerpf(held.origin.z, GUN_REST.origin.z, k))
		# (pitched about its own level right-hand side: - nose down)
		var right := Basis(Vector3.UP, GUN_YAW) * Vector3.RIGHT
		var nose_down := Basis(right, -0.5) * GUN_REST.basis
		var turn := held.basis.slerp(nose_down, smoothstep(0.0, 1.0, k))
		var after := maxf(0.0, t - GUN_LAND)
		# Nose first: the grip lands high enough that the tip of the barrels just meets the deck, then
		# eases down to rest as the bounce lays it flat.
		var land_y := maxf(GUN_REST.origin.y, 0.06 - (nose_down * GuardRifle.muzzle(kind)).y)
		at.y += (land_y - GUN_REST.origin.y) * k * k * (1.0 - smoothstep(0.0, 0.3, after))
		if after > 0.0:
			# The bounce: up a little, its nose kicking up, then down flat.
			var b := sin(clampf(after / 0.24, 0.0, 1.0) * PI)
			at.y += 0.07 * b
			turn = Basis(right, 0.25 * b) * nose_down.slerp(GUN_REST.basis, smoothstep(0.0, 0.3, after))
		xf = Transform3D(turn, at)
		xf.origin.y += maxf(0.0, 0.03 - (xf * GuardRifle.muzzle(kind)).y)  # (never through the deck)
	rifle.transform = _in_rig(wrists[1]).affine_inverse() * xf
	if _barrels != null:
		_barrels.rotation.z = _barrels_from + _spin_from * SPIN_RATE * (1.0 - exp(-1.4 * t)) / 1.4
	_muzzle_flash.visible = false


## His death's ragdoll is all worked out (the rest of it can be shown at once).
func death_baked() -> bool:
	return not _rag.is_empty() and int(_rag["n"]) > int(ceil(DEATH_END * RAG_HZ))


func is_down() -> bool:
	return _fall >= 1.0


## Every frame he's to move (the enemy calls it), from his state: `run` 0..1 (how fast, of a full
## run), `airborne` (and `rising`), `duck` (sliding under something), `aim` (the rifle up at
## `target`, world space), `prone` (lying in a sniper's nest), `reach` (unarmed: his right hand
## flat on that point, world space), `brace` (the boss's stance), `spin` 0..1 and `firing` (the
## minigun's barrels, and the gun going). fire(), flinch() and fall() start
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
	_brace = s.get("brace", false)
	if _brace:
		_breath = fmod(_breath + delta * BREATH_RATE, TAU)
	if s.has("target") and is_inside_tree():
		_target = global_transform.affine_inverse() * (s["target"] as Vector3)
	if s.has("reach") and is_inside_tree():
		_reach_at = global_transform.affine_inverse() * (s["reach"] as Vector3)
	# The minigun: its barrels spin up and down; firing, the flash flickers every frame.
	_spin = move_toward(_spin, float(s.get("spin", 0.0)), delta * 1.5)
	_firing = s.get("firing", false) and _spin > 0.9
	if _barrels != null:
		_barrels.rotation.z = fmod(_barrels.rotation.z + _spin * SPIN_RATE * delta, TAU)
	if _firing:
		fire()
	_reach_w = move_toward(_reach_w, 1.0 if s.has("reach") else 0.0, delta * 7.0)
	_flash(delta)
	_pose_body()
	if armed:
		_hold(_rifle_target())
		_show_flash()
	else:
		_free_arms()
	_apply()
	_still = (_run == target_run and target_run == 0.0 and (_aim == 0.0 or _aim == 1.0) and (_duck == 0.0 or _duck == 1.0)
			and _spin == 0.0 and not _firing and not _brace
			and (_reach_w == 0.0 or _reach_w == 1.0)
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
		elif _brace:
			_pose_brace()
		elif _run < 0.05:
			_pose_guard()
		else:
			_pose_run()
			if not armed:
				# No pistol forward: the right arm pumps opposite the left, as the left does.
				shoulders[1].rotation.x = -0.7 * _run * sin(_phase + PI)
				elbows[1].rotation.x = 1.1 + 0.3 * _run
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
		if kind == GuardRifle.Kind.MINIGUN:
			# The minigun at his hip: he swings it by turning from the hips (his feet stay planted),
			# square on behind it, his head turning a little with it, watching you.
			hips.rotation.y += 0.4 * yaw * a
			spine.rotation.y += 0.3 * yaw * a
			chest.rotation.y += 0.2 * yaw * a
			head.rotation.y += 0.1 * yaw * a
		else:
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
	if _brace and _fall < 0.0 and not _prone and not _airborne:
		for side in [-1, 1]:
			var toe := _brace_toe(side)
			_plant(side, _brace_foot(side), Basis(Vector3.UP, toe) * Vector3.FORWARD, toe)


## Standing guard: feet a little apart, the left a half step ahead, knees soft.
func _pose_guard() -> void:
	if not armed:
		for side in [-1, 1]:  # his hands by his sides
			shoulders[side].rotation = Vector3(0.0, 0.0, side * 0.05)
			elbows[side].rotation.x = 0.2
	hips.position.y = _hip_y - 0.03
	spine.rotation.x = -0.05
	leg_hips[-1].rotation.x = 0.18
	knees[-1].rotation.x = -0.2
	ankles[-1].rotation.x = 0.02
	leg_hips[1].rotation.x = -0.1
	knees[1].rotation.x = -0.1
	ankles[1].rotation.x = 0.1


## The boss's stance behind his minigun (user: "a cool action ready stance"): braced like a heavy
## gunner, down low and leaning into the gun, his hips back and turned to his right (his left foot
## forward: the feet are planted after, see _plant), his chest turned back square to the front, his
## head up, watching; breathing. With the barrels spinning he sinks lower and leans in; firing,
## the gun's shudder runs through him.
func _pose_brace() -> void:
	var b := sin(_breath)
	var s := _spin * _spin * (3.0 - 2.0 * _spin)
	hips.position = Vector3(0, _hip_y - BRACE_DROP - BRACE_SPIN_DROP * s + 0.008 * b, lerpf(BRACE_HIPS_AHEAD[0], BRACE_HIPS_AHEAD[1], s))
	hips.rotation.y = lerpf(BRACE_HIPS_TURN[0], BRACE_HIPS_TURN[1], s)
	hips.rotation.x = lerpf(BRACE_HIPS_TIP[0], BRACE_HIPS_TIP[1], s)
	spine.rotation.x = lerpf(BRACE_SPINE[0], BRACE_SPINE[1], s)
	spine.rotation.y = lerpf(BRACE_SPINE_TURN[0], BRACE_SPINE_TURN[1], s)
	chest.rotation.x = lerpf(BRACE_CHEST[0], BRACE_CHEST[1], s) + 0.015 * b
	chest.rotation.y = lerpf(BRACE_CHEST_TURN[0], BRACE_CHEST_TURN[1], s)
	neck.rotation.x = BRACE_NECK
	# His face square on to you and tipped down the same however he's leaning (the aim then turns
	# him, head and all, to what he's aiming at).
	head.rotation.x = BRACE_GAZE - (hips.rotation.x + spine.rotation.x + chest.rotation.x + neck.rotation.x)
	head.rotation.y = -(hips.rotation.y + spine.rotation.y + chest.rotation.y)
	if _firing:
		# The gun's shudder runs through him, head and all.
		var j := 0.012
		spine.rotation.x += _flash_rng.randf_range(-j, j)
		chest.rotation.z += _flash_rng.randf_range(-j, j)
		head.rotation.x += _flash_rng.randf_range(-j, j) * 0.7
		hips.position.y += _flash_rng.randf_range(-0.004, 0.004)


## Braced, where `side`'s ankle joint stands (this rig's space, at its height at rest), and how far
## that foot's turned out (+ to his left).
func _brace_foot(side: int) -> Vector3:
	var foot: Vector2 = BRACE_FEET[side]
	return Vector3(foot.x, (_ankle_rest[side] as Vector3).y, foot.y)


func _brace_toe(side: int) -> float:
	return BRACE_TOES[side]


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
	if kind == GuardRifle.Kind.MINIGUN:
		var mg := _minigun_target(ch)
		if _fall >= 0.0:
			# Falling, he drops it: on its side (the motor down) by his right hand as he lands.
			var dropped := Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0.45, 0.1, -1.0))
			mg = mg.interpolate_with(dropped, clampf((_fall - 0.4) / 0.6, 0.0, 1.0))
		return mg
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


## The boss's minigun, at his hip in both hands: its grip out at his right side at his belt, a little
## ahead of his hip (placed from his hips joint, turned the way his chest faces but not tipped with
## his lean, so it swings round with him as he sweeps, sinks with him, and never drives into his
## thigh), the barrels pointed where he's aiming (or ahead and a little down), the kick a shudder
## while it fires.
func _minigun_target(ch: Transform3D) -> Transform3D:
	var back := ch.basis.z
	var facing := Basis(Vector3.UP, atan2(back.x, back.z))
	var s := _spin * _spin * (3.0 - 2.0 * _spin)
	var grip: Vector3 = _in_rig(hips).origin + facing * HIP_GRIP[0].lerp(HIP_GRIP[1], s)
	var ahead := (facing * Vector3(0.0, -0.06, -1.0)).normalized()
	var a := _aim * _aim * (3.0 - 2.0 * _aim)
	if a > 0.0:
		var look := _target - grip
		if look.length() > 0.5:
			ahead = ahead.slerp(look.normalized(), a)
	var xf := Transform3D(Basis.looking_at(ahead, Vector3.UP), grip)
	_poles = BRACE_POLES.duplicate()
	if _kick > 0.0:
		var k := _kick * 0.012
		xf.origin += Vector3(_flash_rng.randf_range(-k, k), _flash_rng.randf_range(-k, k), _flash_rng.randf_range(0.0, k * 2.0))
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


## No rifle (the scout): his arms as the pose left them (swinging as he runs), the right hand
## reaching flat onto `_reach_at` (the alarm panel), and down, both arms flung out ahead on the
## floor.
func _free_arms() -> void:
	var ch := _in_rig(chest).basis
	if _reach_w > 0.0 and _fall < 0.0:
		var w := _reach_w * _reach_w * (3.0 - 2.0 * _reach_w)
		var toward := (_reach_at - _in_rig(shoulders[1]).origin).normalized()
		# Fingers up, palm onto it.
		var hand := _frame(Vector3.UP, toward) * _frame(_hand_run[1], _hand_palm[1]).inverse()
		var on := Transform3D(hand, _reach_at - toward * 0.03 - hand * (_hand_mid[1] as Vector3))
		_reach(1, _in_rig(wrists[1]).interpolate_with(on, w), ch * Vector3(0.6, -1.0, 0.2))
	if _fall > 0.6:
		var t := clampf((_fall - 0.6) / 0.4, 0.0, 1.0)
		for side in [-1, 1]:
			var flung := _frame(Vector3(0.3 * side, 0, -1), Vector3.DOWN) * _frame(_hand_run[side], _hand_palm[side]).inverse()
			var at := Vector3(0.45 * side, 0.08, -2.0) - flung * (_hand_mid[side] as Vector3)
			_reach(side, _in_rig(wrists[side]).interpolate_with(Transform3D(flung, at), t), ch * Vector3(0.5 * side, -1.0, 0.0))


## Where the left wrist goes to hold the rifle at `r` under its handguard.
func _left_on(r: Transform3D) -> Transform3D:
	var hold := GuardRifle.support_hand(kind)
	var hand := _frame(r.basis * hold[0], r.basis * hold[1]) * _frame(_hand_run[-1], _hand_palm[-1]).inverse()
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
