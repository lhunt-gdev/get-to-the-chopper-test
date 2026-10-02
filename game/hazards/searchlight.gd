class_name Searchlight
extends Node3D
## A searchlight on the roofs (user decision): on top of the next building over, it sweeps its
## beam back and forth across all five lanes, with a pool of light on the road. Run into the pool
## and you're spotted: the light turns red and locks onto you for a moment, and the alert goes up
## one level. Each light catches you only once. You can see the pool coming, so you time a lane
## change to slip past it; jumping or taking cover in it doesn't hide you.
##
## The level places it at its spot on the road (its origin is the road's centre line there, -Z on
## down the route) and calls update() every physics frame. `at` is its route distance.

signal spotted

## Seconds for one sweep across and back.
const PERIOD := 3.4
## How far the pool swings either side of the centre line (m): from the outer lane to the outer lane.
const SWING := 2.8
## The pool of light: how wide (radius across the road) and how long (each way along it).
const POOL_RADIUS := 1.0
const POOL_HALF_LENGTH := 1.6
## Where the lamp sits: out to the side on the next building, high up.
const OUT := 13.0
const UP := 9.0
## How long it holds on you once it's caught you.
const HOLD := 1.6
const WHITE := Color(0.8, 0.88, 1.0)
const RED := Color(1.0, 0.18, 0.12)

var at: float = 0.0
## Which side its building is on: -1 left, 1 right.
var side: int = 1
## Where in its sweep it starts (0..1), so neighbouring lights don't move in step.
var phase: float = 0.0
## The pool's position across the road right now.
var x: float = 0.0
var caught := false

var _t := 0.0
var _hold := 0.0
var _beam: MeshInstance3D
var _disc: MeshInstance3D
var _beam_mat: Material
var _disc_mat: Material
## The pool's light (an Ambience lamp follows it).
var pool: Node3D


func _init() -> void:
	var lamp := MeshInstance3D.new()
	var housing := BoxMesh.new()
	housing.size = Vector3(0.9, 0.7, 0.9)
	lamp.mesh = housing
	lamp.material_override = PsxMaterials.flat(Color("2a2d30"))
	lamp.name = "Lamp"
	add_child(lamp)
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 1.3
	cone.height = 1.0  # scaled to the beam's length every frame
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	add_child(_beam)
	_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = POOL_RADIUS
	disc.bottom_radius = POOL_RADIUS
	disc.height = 0.02
	disc.radial_segments = 16
	disc.rings = 1
	_disc.mesh = disc
	_disc.scale = Vector3(1.0, 1.0, POOL_HALF_LENGTH / POOL_RADIUS)  # longer along the road
	add_child(_disc)
	pool = Node3D.new()
	add_child(pool)
	_set_colour(WHITE)


func _ready() -> void:
	get_node("Lamp").position = Vector3(side * OUT, UP, 0)
	x = pool_x(0.0, phase)
	_aim()


## Where the pool is across the road at time t (s). Pure rule, so it's unit-tested.
static func pool_x(t: float, start_phase: float) -> float:
	return SWING * sin(TAU * (t / PERIOD + start_phase))


## Whether you're in the pool. Pure rule, so it's unit-tested.
static func in_pool(player_d: float, player_x: float, light_at: float, light_x: float) -> bool:
	return absf(player_d - light_at) <= POOL_HALF_LENGTH and absf(player_x - light_x) <= POOL_RADIUS


## Where the pool will be `ahead_s` seconds from now (the bots use it to dodge).
func x_in(ahead_s: float) -> float:
	return pool_x(_t + ahead_s, phase)


## One frame. Returns true the moment it spots you.
func update(delta: float, player_d: float, player_x: float) -> bool:
	_t += delta
	var got_you := false
	if _hold > 0.0:
		_hold -= delta
		x = move_toward(x, player_x, 9.0 * delta)  # locked on, following you
	else:
		x = pool_x(_t, phase)
		if not caught and in_pool(player_d, player_x, at, x):
			caught = true
			got_you = true
			_hold = HOLD
			_set_colour(RED)
			spotted.emit()
	_aim()
	return got_you


## Beam from the lamp down to the pool; the pool's disc and light on the road.
func _aim() -> void:
	var src := Vector3(side * OUT, UP - 0.2, 0)
	var dst := Vector3(x, 0.0, 0)
	var dir := (src - dst).normalized()
	_beam.basis = Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1, src.distance_to(dst), 1))
	_beam.position = (src + dst) / 2.0
	_disc.position = Vector3(x, 0.02, 0)
	pool.position = Vector3(x, 1.5, 0)


func _set_colour(c: Color) -> void:
	_beam_mat = PsxMaterials.beam(Color(c.r, c.g, c.b, 0.14))
	_disc_mat = PsxMaterials.beam(Color(c.r, c.g, c.b, 0.22))
	_beam.material_override = _beam_mat
	_disc.material_override = _disc_mat
