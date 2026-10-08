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
	if not armed:  # his free arms blend too (into a slide, a fall), the reach's collarbone and hand too
		_body_joints.append_array([shoulders[-1], shoulders[1], elbows[-1], elbows[1], clavicles[-1], clavicles[1], wrists[-1], wrists[1]])
	if armed:
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
	gun.material_override = PsxMaterials.figure(GuardRifle.material())  # (dissolves to the floor with him)
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
		b.material_override = PsxMaterials.figure(GuardRifle.material())
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


## Down: he falls on his face (and stays there), on his own; from now on his body is never dissolved
## (keep_solid), so it doesn't melt away as you run past it.
func fall() -> void:
	if _fall < 0.0:
		keep_solid()
		_fall_from = _snap()
		_fall = 0.0
		pose_to({})


## The boss's death: his own timings (the DEATH_ constants) and gravity (9.8 m/s² at 1.35 m to the unit).
func _death_plan() -> Dictionary:
	return {"hits": DEATH_HITS, "let_go": DEATH_LET_GO, "lift": DEATH_LIFT, "land": DEATH_LAND, "end": DEATH_END, "gravity": 7.26}


## The boss is killed: his barrels' turn and spin (they spin down as the gun falls), and no more
## holds or falls of his own (pose_death poses him from now on). His body is never dissolved from
## now on (keep_solid).
func death_start(opts: Dictionary = {}) -> Dictionary:
	keep_solid()
	_barrels_from = _barrels.rotation.z if _barrels != null else 0.0
	_spin_from = _spin
	set_process(false)
	_flinch = 0.0
	if _flash_left > 0.0:
		_flash(_flash_left)  # (no red hit flash left on him)
	return super(opts)


func pose_death(t: float, from: Dictionary) -> void:
	_still = false
	super(t, from)


func _death_prop_from() -> Transform3D:
	return _in_rig(rifle) if rifle != null else Transform3D.IDENTITY


func _death_prop(t: float, from: Dictionary) -> void:
	_death_gun(t, from["prop"])


## The boss's body through his death (the path his ragdoll follows): jolted by the hits, blasted
## up and back, over backwards and twisting round twice, landing face up.
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
