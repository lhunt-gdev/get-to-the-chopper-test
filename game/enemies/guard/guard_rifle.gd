class_name GuardRifle
extends RefCounted
## The guards' rifles (user: the guard model for the rifle troopers, the pursuit squad and the sniper,
## with "a rifle ... held with two hands"). PS1-style low-poly guns, modelled here from side profiles
## pushed out to their width (stock, receiver, raked pistol grip, curved magazine, sights) and short
## many-sided tubes (handguard, barrel, muzzle, scope), flat-shaded, their colours from a small
## palette texture through the game's PS1 shader. One mesh per kind, shared by every guard.
##
## Rifle space: the barrel runs along -Z, its top is +Y, its right +X, and the origin is the middle
## of the pistol grip, where the right fist closes on it.

enum Kind {
	CARBINE,        ## the rifle troopers'
	CARBINE_LIGHT,  ## the pursuit squad's: a light under the handguard, a bright point in the dark
	SNIPER,         ## the sniper's: a long barrel, a scope and a bipod
	MINIGUN,        ## the boss's (user): six spinning barrels, carried at the hip
}

## The palette, one texel each: gunmetal, the receiver, the polymer furniture, small details (sights,
## rails), the scope's glass, the light's body.
const PALETTE: Array[Color] = [Color("1b1c1f"), Color("2e3034"), Color("26272b"), Color("4b4e54"), Color("32465a"), Color("3d3f43")]
enum Swatch { METAL, RECEIVER, FURNITURE, DETAIL, GLASS, LIGHT }

## The parts were drawn with the grip's middle here; everything is moved so it's at the origin.
const GRIP := Vector3(0.0, -0.01, 0.028)
## The minigun's barrels turn about this line (along -Z): their own mesh (barrels_mesh()), spun.
const SPIN_AXIS := Vector3(0.0, 0.11, -0.28)
## ...and how far out round it each of the six sits, and how long they are.
const BARREL_RING := 0.03
const BARREL_LENGTH := 0.6

static var _barrels: ArrayMesh

static var _meshes := {}
static var _palette: ImageTexture


## The mesh for a kind (built the first time).
static func mesh(kind: Kind) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(kind)
	return _meshes[kind]


## The material every rifle uses: the palette through the PS1 shader (lit by the area's lamps).
static func material() -> ShaderMaterial:
	if _palette == null:
		var img := Image.create(PALETTE.size(), 1, false, Image.FORMAT_RGBA8)
		for i in PALETTE.size():
			img.set_pixel(i, 0, PALETTE[i])
		_palette = ImageTexture.create_from_image(img)
	return PsxMaterials.textured(_palette)


## Where the barrel ends (rifle space): shots and the flash come from here.
static func muzzle(kind: Kind) -> Vector3:
	match kind:
		Kind.SNIPER:
			return Vector3(0, 0.075, -0.865) - GRIP
		Kind.MINIGUN:
			return SPIN_AXIS + Vector3(0, 0, -BARREL_LENGTH - 0.01) - GRIP
	return Vector3(0, 0.078, -0.53) - GRIP


## The middle of the butt pad: it goes into his shoulder when he aims.
static func butt(kind: Kind) -> Vector3:
	return (Vector3(0, 0.03, 0.37) if kind == Kind.SNIPER else Vector3(0, 0.028, 0.35)) - GRIP


## Where the middle of his left fist goes: under the handguard; on the sniper's rifle (resting on its
## bipod), under the back of the stock, as a sniper lying behind it holds it.
static func support(kind: Kind) -> Vector3:
	match kind:
		Kind.SNIPER:
			return Vector3(0, -0.03, 0.24) - GRIP
		Kind.MINIGUN:
			return Vector3(0, 0.25, -0.135) - GRIP  # the minigun's: round the bar of its top handle
	return Vector3(0, 0.021, -0.21) - GRIP


## How the left hand holds on (rifle axes): which way its fingers run, and its palm faces. Under a
## handguard, palm up, fingers round its right side; on the minigun's top handle, from above, palm
## down, fingers curled over the bar.
static func support_hand(kind: Kind) -> Array[Vector3]:
	if kind == Kind.MINIGUN:
		return [Vector3(1.0, -0.2, -0.3), Vector3(0.0, -1.0, 0.15)]
	return [Vector3(0.9, 0.25, -0.4), Vector3(0.35, 1.0, 0.0)]


## The minigun's six barrels and their two clamps, round their own axis (the origin), along -Z: the
## part that spins (put it at SPIN_AXIS - GRIP and turn it about z).
static func barrels_mesh() -> ArrayMesh:
	if _barrels == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 6:
			var ang := TAU * i / 6.0
			var c := Vector3(cos(ang), sin(ang), 0.0) * BARREL_RING + GRIP  # (_tube moves by -GRIP)
			_tube(st, c, c + Vector3(0, 0, -BARREL_LENGTH), 0.009, 5, Swatch.METAL, Swatch.METAL)
		for z: float in [-0.12, -BARREL_LENGTH + 0.04]:
			_tube(st, GRIP + Vector3(0, 0, z), GRIP + Vector3(0, 0, z - 0.03), 0.047, 8, Swatch.RECEIVER, Swatch.RECEIVER)
		_tube(st, GRIP, GRIP + Vector3(0, 0, -BARREL_LENGTH), 0.012, 6, Swatch.DETAIL, Swatch.METAL)  # the middle rod
		_barrels = st.commit()
	return _barrels


## The top of the sights (the line he looks down when he aims).
static func sight(kind: Kind) -> Vector3:
	return (Vector3(0, 0.19, 0.08) if kind == Kind.SNIPER else Vector3(0, 0.15, 0.06)) - GRIP


## The front of the scope (the sniper's: his laser and its glint come from here).
static func scope_front() -> Vector3:
	return Vector3(0, 0.17, -0.265) - GRIP


## The minigun's ejection port (rifle space): on its right side under the housing, the cases
## thrown out along its x (out to the right, a little down and back).
static func eject_port() -> Transform3D:
	var out := Vector3(1.0, -0.35, 0.25).normalized()
	return Transform3D(_frame_of(out, Vector3.UP), SPIN_AXIS + Vector3(0.07, -0.03, 0.15) - GRIP)


static func _frame_of(x: Vector3, up: Vector3) -> Basis:
	var z := x.cross(up).normalized()
	return Basis(x, z.cross(x), z)


## The front of the squad's light (its lens glows there, facing -Z).
static func light_lens() -> Vector3:
	return Vector3(0.036, 0.058, -0.333) - GRIP


# --- Modelling ------------------------------------------------------------------------------------

static func _build(kind: Kind) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sniper := kind == Kind.SNIPER
	# The pistol grip, raked back, and the trigger and its guard.
	_prism(st, [Vector2(-0.005, 0.046), Vector2(0.035, 0.046), Vector2(0.062, -0.062), Vector2(0.022, -0.068)], 0.0, 0.016, Swatch.FURNITURE)
	_prism(st, [Vector2(-0.052, -0.002), Vector2(0.0, -0.002), Vector2(0.0, 0.006), Vector2(-0.052, 0.006)], 0.0, 0.005, Swatch.METAL)
	_prism(st, [Vector2(-0.052, 0.006), Vector2(-0.044, 0.006), Vector2(-0.044, 0.046), Vector2(-0.052, 0.046)], 0.0, 0.005, Swatch.METAL)
	_prism(st, [Vector2(-0.024, 0.014), Vector2(-0.017, 0.012), Vector2(-0.016, 0.046), Vector2(-0.024, 0.046)], 0.0, 0.004, Swatch.METAL)
	if kind == Kind.MINIGUN:
		# The minigun (the barrels are their own mesh, to spin): the drive housing over the grip, its
		# back plate, the motor on its right, the top carry handle (the left hand's), and the box of
		# ammunition on its left with the belt feeding up into it.
		var ax := SPIN_AXIS
		_tube(st, ax + Vector3(0, 0, 0.36), ax + Vector3(0, 0, 0.02), 0.066, 8, Swatch.RECEIVER, Swatch.METAL)
		_prism(st, [Vector2(ax.z + 0.36, ax.y - 0.06), Vector2(ax.z + 0.42, ax.y - 0.06), Vector2(ax.z + 0.42, ax.y + 0.06),
				Vector2(ax.z + 0.36, ax.y + 0.06)], 0.0, 0.055, Swatch.METAL)
		_tube(st, Vector3(0.07, 0.15, 0.0), Vector3(0.07, 0.15, -0.16), 0.026, 6, Swatch.METAL, Swatch.METAL)
		for z: float in [-0.06, -0.21]:
			_beam(st, Vector3(0, 0.17, z), Vector3(0, 0.255, z), 0.018, Swatch.METAL)
		_beam(st, Vector3(0, 0.25, -0.05), Vector3(0, 0.25, -0.22), 0.022, Swatch.FURNITURE)
		_prism(st, [Vector2(0.02, -0.09), Vector2(-0.18, -0.09), Vector2(-0.18, 0.08), Vector2(0.02, 0.08)], -0.115, 0.055, Swatch.FURNITURE)
		_beam(st, Vector3(-0.095, 0.08, -0.08), Vector3(-0.045, 0.12, -0.08), 0.05, Swatch.DETAIL)
	elif sniper:
		# A bolt-action: a plain receiver, the bolt handle out to the right, a solid stock with a
		# cheek rest, a short box magazine.
		_prism(st, [Vector2(0.1, 0.045), Vector2(0.1, 0.105), Vector2(-0.16, 0.105), Vector2(-0.16, 0.045)], 0.0, 0.022, Swatch.RECEIVER)
		_prism(st, [Vector2(0.06, 0.078), Vector2(0.076, 0.078), Vector2(0.076, 0.094), Vector2(0.06, 0.094)], 0.04, 0.018, Swatch.METAL)
		_prism(st, [Vector2(0.1, 0.1), Vector2(0.23, 0.118), Vector2(0.355, 0.112), Vector2(0.37, 0.1), Vector2(0.37, -0.045),
				Vector2(0.335, -0.05), Vector2(0.19, 0.0), Vector2(0.1, 0.04)], 0.0, 0.02, Swatch.FURNITURE)
		_prism(st, [Vector2(-0.06, 0.046), Vector2(-0.1, 0.046), Vector2(-0.1, -0.035), Vector2(-0.06, -0.035)], 0.0, 0.013, Swatch.METAL)
		# The forend, the long heavy barrel and its muzzle brake.
		_tube(st, Vector3(0, 0.075, -0.16), Vector3(0, 0.075, -0.36), 0.026, 8, Swatch.FURNITURE, Swatch.FURNITURE)
		_tube(st, Vector3(0, 0.075, -0.36), Vector3(0, 0.075, -0.8), 0.012, 6, Swatch.METAL, Swatch.METAL)
		_tube(st, Vector3(0, 0.075, -0.8), Vector3(0, 0.075, -0.865), 0.018, 6, Swatch.METAL, Swatch.METAL)
		# The scope on two mounts, its bells, and its glass at the front.
		for z in [0.03, -0.11]:
			_prism(st, [Vector2(z + 0.012, 0.105), Vector2(z - 0.012, 0.105), Vector2(z - 0.012, 0.155), Vector2(z + 0.012, 0.155)], 0.0, 0.01, Swatch.DETAIL)
		_tube(st, Vector3(0, 0.17, 0.07), Vector3(0, 0.17, -0.19), 0.017, 8, Swatch.METAL, Swatch.METAL)
		_tube(st, Vector3(0, 0.17, 0.07), Vector3(0, 0.17, 0.11), 0.022, 8, Swatch.METAL, Swatch.GLASS)
		_tube(st, Vector3(0, 0.17, -0.19), Vector3(0, 0.17, -0.265), 0.027, 8, Swatch.METAL, Swatch.GLASS)
		# The bipod's legs, splayed down from the front of the forend.
		for side in [-1, 1]:
			_beam(st, Vector3(side * 0.012, 0.055, -0.33), Vector3(side * 0.06, -0.17, -0.29), 0.009, Swatch.METAL)
	else:
		# A carbine: the receiver with a rail and rear sight on top, a skeleton stock, a curved
		# magazine.
		_prism(st, [Vector2(0.1, 0.045), Vector2(0.1, 0.115), Vector2(-0.15, 0.115), Vector2(-0.17, 0.1), Vector2(-0.17, 0.045)], 0.0, 0.024, Swatch.RECEIVER)
		_prism(st, [Vector2(0.07, 0.115), Vector2(0.07, 0.128), Vector2(-0.14, 0.128), Vector2(-0.14, 0.115)], 0.0, 0.012, Swatch.DETAIL)
		_prism(st, [Vector2(0.07, 0.128), Vector2(0.07, 0.15), Vector2(0.045, 0.15), Vector2(0.035, 0.128)], 0.0, 0.01, Swatch.DETAIL)
		_prism(st, [Vector2(0.1, 0.105), Vector2(0.32, 0.098), Vector2(0.335, 0.09), Vector2(0.335, -0.035), Vector2(0.305, -0.04), Vector2(0.1, 0.05)], 0.0, 0.019, Swatch.FURNITURE)
		_prism(st, [Vector2(0.335, 0.09), Vector2(0.35, 0.09), Vector2(0.35, -0.035), Vector2(0.335, -0.035)], 0.0, 0.021, Swatch.METAL)
		_prism(st, [Vector2(-0.058, 0.046), Vector2(-0.104, 0.046), Vector2(-0.116, -0.03), Vector2(-0.138, -0.115),
				Vector2(-0.098, -0.128), Vector2(-0.078, -0.04)], 0.0, 0.0135, Swatch.METAL)
		# The handguard, the gas block and front sight, the barrel and its muzzle.
		_tube(st, Vector3(0, 0.078, -0.17), Vector3(0, 0.078, -0.34), 0.032, 8, Swatch.FURNITURE, Swatch.FURNITURE)
		_tube(st, Vector3(0, 0.078, -0.34), Vector3(0, 0.078, -0.37), 0.018, 6, Swatch.METAL, Swatch.METAL)
		_prism(st, [Vector2(-0.34, 0.09), Vector2(-0.37, 0.09), Vector2(-0.363, 0.15), Vector2(-0.347, 0.15)], 0.0, 0.006, Swatch.METAL)
		_tube(st, Vector3(0, 0.078, -0.37), Vector3(0, 0.078, -0.49), 0.0105, 6, Swatch.METAL, Swatch.METAL)
		_tube(st, Vector3(0, 0.078, -0.49), Vector3(0, 0.078, -0.53), 0.015, 6, Swatch.METAL, Swatch.METAL)
		if kind == Kind.CARBINE_LIGHT:
			_tube(st, Vector3(0.036, 0.058, -0.25), Vector3(0.036, 0.058, -0.33), 0.014, 6, Swatch.LIGHT, Swatch.LIGHT)
	return st.commit()


## The middle of a palette texel.
static func _uv(swatch: int) -> Vector2:
	return Vector2((swatch + 0.5) / PALETTE.size(), 0.5)


## One flat-shaded triangle facing `normal` (its corners put in the winding Godot draws as the front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, swatch: int) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(normal)
	st.set_uv(_uv(swatch))
	for p in [a, b, c]:
		st.add_vertex(p - GRIP)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, swatch: int) -> void:
	_tri(st, a, b, c, normal, swatch)
	_tri(st, a, c, d, normal, swatch)


## A side profile (points (z, y), in order round it) pushed out across X: `half` either side of x = cx.
static func _prism(st: SurfaceTool, profile: Array[Vector2], cx: float, half: float, swatch: int) -> void:
	var pts := PackedVector2Array(profile)
	var area := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		area += p.x * q.y - q.x * p.y
	var tris := Geometry2D.triangulate_polygon(pts)
	for side in [-1.0, 1.0]:
		var x: float = cx + side * half
		for t in range(0, tris.size(), 3):
			var a := pts[tris[t]]
			var b := pts[tris[t + 1]]
			var c := pts[tris[t + 2]]
			_tri(st, Vector3(x, a.y, a.x), Vector3(x, b.y, b.x), Vector3(x, c.y, c.x), Vector3(side, 0, 0), swatch)
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var e := q - p
		# Outward: to the right of each edge for a profile drawn clockwise in (z, y), to the left for
		# one drawn the other way.
		var out := Vector2(e.y, -e.x) if area > 0.0 else Vector2(-e.y, e.x)
		var n := Vector3(0, out.y, out.x).normalized()
		_quad(st, Vector3(cx - half, p.y, p.x), Vector3(cx + half, p.y, p.x), Vector3(cx + half, q.y, q.x), Vector3(cx - half, q.y, q.x), n, swatch)


## A many-sided tube from `a` to `b` (one flat face up), its ends capped: `cap` at `b`'s end.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, sides: int, swatch: int, cap: int) -> void:
	var axis := (b - a).normalized()
	var u := (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
	if u.length() < 0.5:
		u = Vector3.RIGHT
	var v := axis.cross(u)
	var ring: Array[Vector3] = []
	for i in sides:
		var ang := TAU * (i + 0.5) / sides
		ring.append(u * cos(ang) * radius + v * sin(ang) * radius)
	for i in sides:
		var p := ring[i]
		var q := ring[(i + 1) % sides]
		_quad(st, a + p, a + q, b + q, b + p, (p + q).normalized(), swatch)
	for i in range(1, sides - 1):
		_tri(st, a + ring[0], a + ring[i], a + ring[i + 1], -axis, swatch)
		_tri(st, b + ring[0], b + ring[i], b + ring[i + 1], axis, cap)


## A thin square bar from `a` to `b`.
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, thick: float, swatch: int) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD).normalized() * thick * 0.5
	var v := axis.cross(u).normalized() * thick * 0.5
	var corners: Array[Vector3] = [u + v, -u + v, -u - v, u - v]
	for i in 4:
		var p := corners[i]
		var q := corners[(i + 1) % 4]
		_quad(st, a + p, a + q, b + q, b + p, (p + q).normalized(), swatch)
	_quad(st, a + corners[0], a + corners[1], a + corners[2], a + corners[3], -axis, swatch)
	_quad(st, b + corners[0], b + corners[1], b + corners[2], b + corners[3], axis, swatch)
