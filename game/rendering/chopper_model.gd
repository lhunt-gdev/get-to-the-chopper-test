class_name ChopperModel
extends RefCounted
## The extraction chopper's meshes (user reference, built to the player's scale): a military
## transport helicopter about 13 m long with a 15 m rotor, in its own space: +z toward you, the nose
## at -x, the tail at +x, the skids on y = 0. Low-poly, PS1-style, in a handful of meshes all mapped
## onto one atlas (PsxTextures.chopper_atlas: the paint drawn as side, top and end views of it, and
## swatches for the glass, the cabin, the blades, the stripes, metal and the lamps):
##   hull       - the body (a lofted nose with the stepped canopy's frame, the cabin with its door
##                opening and the lit cabin inside, the tapering tail boom), the engine housing with
##                its intakes and exhausts, the mast, the sponsons, the skids on their cross tubes,
##                the fin and stabiliser, the door slid back on its rail, the door gun: lit
##   glow       - the cockpit glass (dark, the instrument panel glowing in it), the cabin's lamp, the
##                beacon, the nav lights and the landing light's lens: unlit, the same atlas
##   rotor      - the hub and four blades, drooping a little toward their tips (spun about its y)
##   tail_rotor - its hub and two striped blades (spun about its z)
## The meshes don't depend on the paint, so they're made once; a repaint is a different atlas
## (PsxTextures.CHOPPER_LIVERIES).

## Where the moving parts and lights go (as before the rebuild: the KO replay's cameras stay under
## the rotor, the lamps sit where the level puts them).
const ROTOR_AT := Vector3(0.6, 3.98, 0)
const TAIL_ROTOR_AT := Vector3(10.3, 3.6, 0.22)
const TAIL_LIGHT_AT := Vector3(10.35, 4.25, 0)
const CABIN_LAMP_AT := Vector3(0.0, 2.45, 0.6)
const LANDING_LIGHT_AT := Vector3(0, 1.2, 3.0)
const BLADE_TIP := 7.7
const TAIL_BLADE := 1.2
## The door opening (x, y), in the near side of the cabin at z = CABIN_HALF.
const DOOR_X := Vector2(-1.0, 1.0)
const CABIN_HALF := 1.25
## The parts drawn unlit (onto the glow mesh).
const GLOW_ZONES := ["glass", "lamp_white", "lamp_warm", "lamp_red", "lamp_green", "panel"]

static var _meshes: Dictionary = {}

var _tools := {}  # mesh name -> SurfaceTool
var _target := "hull"


## The four meshes ({hull, glow, rotor, tail_rotor}), made the first time.
static func meshes() -> Dictionary:
	if _meshes.is_empty():
		var b := ChopperModel.new()
		b._build()
		for k: String in b._tools:
			_meshes[k] = (b._tools[k] as SurfaceTool).commit()
	return _meshes


func _build() -> void:
	for k in ["hull", "glow", "rotor", "tail_rotor"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[k] = st
	_target = "hull"
	_body()
	_engine()
	_cabin_inside()
	_door_and_gun()
	_tail()
	_skids()
	_lights()
	_target = "rotor"
	_rotor()
	_target = "tail_rotor"
	_tail_rotor()


# --- The parts ------------------------------------------------------------------------------

## The body, lofted nose to tail through cross sections (_section), cut into pieces no longer than
## a metre or so (so the PS1's warped textures don't swim far). The canopy's glass is the upper band
## and roof over the cockpit; the door opening is left out of the cabin's near side.
func _body() -> void:
	# x, bottom, top, half width, bottom chamfer, top chamfer, window line
	var keys := [
		[-3.8, 1.0, 1.5, 0.35, 0.12, 0.12, 1.3],
		[-3.6, 0.8, 1.85, 0.75, 0.25, 0.25, 1.45],
		[-3.2, 0.7, 2.15, 0.98, 0.28, 0.3, 1.5],
		[-2.6, 0.62, 2.58, 1.15, 0.26, 0.3, 1.55],
		[-2.0, 0.6, 2.76, 1.22, 0.22, 0.26, 1.65],
		[-1.8, 0.58, 2.78, CABIN_HALF, 0.2, 0.2, 1.75],
		[DOOR_X.x, 0.58, 2.78, CABIN_HALF, 0.2, 0.2, 1.75],
		[DOOR_X.y, 0.58, 2.78, CABIN_HALF, 0.2, 0.2, 1.75],
		[2.8, 0.58, 2.78, CABIN_HALF, 0.2, 0.2, 1.75],
		[3.5, 1.1, 2.76, 0.95, 0.28, 0.25, 1.95],
		[4.4, 1.72, 2.66, 0.55, 0.15, 0.18, 2.2],
		[7.0, 1.9, 2.55, 0.4, 0.1, 0.12, 2.22],
		[10.2, 2.05, 2.45, 0.28, 0.08, 0.08, 2.25],
		[10.7, 2.12, 2.42, 0.22, 0.06, 0.06, 2.27],
	]
	var rings: Array = []
	for i in keys.size():
		if i > 0:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var n := ceili((float(b[0]) - float(a[0])) / 1.2)
			for k in range(1, n):
				var t := float(k) / n
				var mid: Array = []
				for c in a.size():
					mid.append(lerpf(float(a[c]), float(b[c]), t))
				rings.append(_section.callv(mid))
		rings.append(_section.callv(keys[i]))
	var zone := func(xm: float, j: int) -> String:
		var near_side := j == 0 or j == 1
		if xm > DOOR_X.x and xm < DOOR_X.y and near_side:
			return ""  # the door opening
		if xm > -3.6 and xm < -1.8 and (j == 1 or j == 5):
			return "glass"  # the windscreen's sides and the cockpit's side windows
		if xm > -3.6 and xm < -2.0 and j >= 2 and j <= 4:
			return "glass"  # the windscreen and the roof window over it
		return "paint"
	_loft(rings, zone, true)
	# The sponsons low on either side, behind the door.
	for s in [-1.0, 1.0]:
		var pods: Array = []
		for p in [[1.05, 0.66, 0.96, 0.15], [1.3, 0.6, 1.02, 0.36], [2.5, 0.6, 1.02, 0.36], [2.8, 0.66, 0.96, 0.15]]:
			pods.append(_pod_section(p[0], p[1], p[2], s * 1.05, s * (float(p[3]) + 0.2)))
		_loft(pods, _all("paint"), true)


## A cross section of the body at `x` (ten points round it, +z bottom first): its bottom and top,
## half width, the chamfers along its bottom and top edges, and the window line splitting its sides
## (the faces: 0 the near side below the window line, 1 above it, 2 the near top chamfer, 3 the top,
## 4 the far top chamfer, 5 and 6 the far side, 7 the far bottom chamfer, 8 the bottom, 9 the near
## bottom chamfer).
func _section(x: float, yb: float, yt: float, hw: float, cb: float, ct: float, yw: float) -> Array:
	return [Vector3(x, yb + cb, hw), Vector3(x, yw, hw), Vector3(x, yt - ct, hw), Vector3(x, yt, hw - ct),
			Vector3(x, yt, -(hw - ct)), Vector3(x, yt - ct, -hw), Vector3(x, yw, -hw), Vector3(x, yb + cb, -hw),
			Vector3(x, yb, -(hw - cb)), Vector3(x, yb, hw - cb)]


## A sponson's cross section at `x`: from the hull's side (z0) out by `out`, yb to yt, chamfered.
func _pod_section(x: float, yb: float, yt: float, z0: float, out: float) -> Array:
	var z1 := z0 + out
	var c := 0.08 * signf(out)
	return [Vector3(x, yb, z0), Vector3(x, yb, z1 - c), Vector3(x, yb + 0.08, z1), Vector3(x, yt - 0.08, z1),
			Vector3(x, yt, z1 - c), Vector3(x, yt, z0)]


## The engine housing on the cabin roof (the intakes at its front, the two exhausts out of its
## back, soot painted behind them), the mast up to the rotor, the beacon.
func _engine() -> void:
	var rings: Array = []
	for p in [[-1.1, 2.7, 2.98, 0.5, 0.15], [-0.7, 2.7, 3.36, 0.78, 0.22], [0.6, 2.7, 3.4, 0.8, 0.22],
			[1.9, 2.7, 3.4, 0.8, 0.22], [2.6, 2.7, 3.12, 0.62, 0.2]]:
		rings.append(_section(p[0], p[1], p[2], p[3], 0.0, p[4], (p[1] + p[2]) / 2.0))
	var no_bottom := func(_xm: float, j: int) -> String:
		return "" if j == 8 else "paint"
	_loft(rings, no_bottom, true)
	for s in [-1.0, 1.0]:
		_box(Vector3(-0.72, 3.04, s * 0.5), Vector3(0.1, 0.34, 0.42), "grille")  # the intakes
		_box(Vector3(-0.55, 3.24, s * 0.5), Vector3(0.36, 0.06, 0.46), "metal")  # their lips
		var a := Vector3(2.35, 3.05, s * 0.42)
		var b := Vector3(3.0, 2.98, s * 0.66)
		_tube(a, b, 0.17, 8, "metal", "soot")  # the exhausts, black inside
	_tube(Vector3(0.6, 3.36, 0), Vector3(0.6, 3.92, 0), 0.13, 8, "metal", "metal")  # the mast
	_box(Vector3(0.6, 3.5, 0), Vector3(0.5, 0.12, 0.5), "metal")  # the swashplate's collar


## The cabin inside, seen through the door: padded walls, the tread floor, the ceiling, troop seats
## along the far wall (red webbing). It faces in; the lamp lights it.
func _cabin_inside() -> void:
	var lo := Vector3(-1.75, 0.82, -1.18)
	var hi := Vector3(2.75, 2.62, CABIN_HALF - 0.02)
	_box_inside(lo, hi)
	_box(Vector3(0.6, 1.05, -0.95), Vector3(3.2, 0.08, 0.42), "seat")  # the seat
	_box(Vector3(0.6, 1.55, -1.12), Vector3(3.2, 0.9, 0.06), "seat")  # its backrest
	for x in [-0.9, 0.6, 2.1]:
		_box(Vector3(x, 0.93, -0.8), Vector3(0.05, 0.22, 0.05), "metal")  # its legs
	_box(Vector3(1.0, 2.56, 0.1), Vector3(3.0, 0.06, 0.06), "metal")  # a grab rail along the roof


## The door slid back on its rail, and the door gun on its post by the opening.
func _door_and_gun() -> void:
	_box(Vector3(1.95, 1.825, 1.31), Vector3(1.9, 1.55, 0.06), "door")
	_box(Vector3(0.95, 2.66, 1.3), Vector3(2.0, 0.05, 0.1), "metal")  # the rail over the opening
	_box(Vector3(1.95, 1.04, 1.3), Vector3(1.9, 0.04, 0.08), "metal")  # and under the door
	_box(Vector3(-0.85, 1.75, 1.45), Vector3(0.08, 0.08, 0.9), "black")  # the barrel
	_box(Vector3(-0.85, 1.75, 0.95), Vector3(0.2, 0.2, 0.35), "black")  # its body
	_box(Vector3(-0.85, 1.92, 0.95), Vector3(0.1, 0.14, 0.2), "metal")  # its sight
	_box(Vector3(-0.85, 1.35, 0.95), Vector3(0.05, 0.75, 0.05), "metal")  # its post


## The fin (swept, on the end of the boom), the stabiliser, a tail bumper.
func _tail() -> void:
	var fin := [Vector2(9.3, 2.3), Vector2(10.7, 2.3), Vector2(10.72, 4.35), Vector2(10.05, 4.35)]
	_extrude_z(fin, -0.09, 0.09, "paint")
	_box(Vector3(10.3, 3.6, 0.13), Vector3(0.18, 0.18, 0.1), "metal")  # the tail rotor's gearbox
	var stab := [Vector2(8.75, -1.3), Vector2(9.25, -1.3), Vector2(9.6, -0.3), Vector2(9.6, 0.3),
			Vector2(9.25, 1.3), Vector2(8.75, 1.3), Vector2(8.65, 0.3), Vector2(8.65, -0.3)]
	_extrude_y(stab, 2.32, 2.38, "paint")
	_beam(Vector3(9.9, 2.12, 0), Vector3(10.2, 1.7, 0), 0.06, "metal")  # the bumper


## The skids: a tube each side curling up at the front, on two cross tubes under the belly.
func _skids() -> void:
	for s in [-1.0, 1.0]:
		var z: float = s * 1.25
		_beam(Vector3(-2.3, 0.07, z), Vector3(3.1, 0.07, z), 0.06, "metal")
		_beam(Vector3(-2.3, 0.07, z), Vector3(-2.75, 0.2, z), 0.06, "metal")
		_beam(Vector3(-2.75, 0.2, z), Vector3(-2.9, 0.36, z), 0.06, "metal")
		for x in [-1.4, 2.0]:
			_beam(Vector3(x, 0.08, z), Vector3(x, 0.4, s * 1.1), 0.05, "metal")
			_beam(Vector3(x, 0.4, s * 1.1), Vector3(x, 0.6, s * 0.8), 0.05, "metal")
	for x in [-1.4, 2.0]:
		_beam(Vector3(x, 0.6, -0.8), Vector3(x, 0.6, 0.8), 0.05, "metal")


## The lights that never change: the cabin's lamp, the beacon on the engine, a nav light on each
## end of the stabiliser (red to port, green to starboard), the landing light's lens under the nose.
## (The blinking tail light is its own: the level swaps its material.)
func _lights() -> void:
	_box(CABIN_LAMP_AT + Vector3(0, 0.12, 0), Vector3(0.3, 0.05, 0.3), "lamp_warm")
	_box(Vector3(1.6, 3.46, 0), Vector3(0.2, 0.12, 0.2), "lamp_red")
	_box(Vector3(9.0, 2.35, -1.33), Vector3(0.12, 0.1, 0.08), "lamp_red")
	_box(Vector3(9.0, 2.35, 1.33), Vector3(0.12, 0.1, 0.08), "lamp_green")
	_box(Vector3(-2.7, 0.58, 0), Vector3(0.36, 0.05, 0.36), "lamp_white")


## The rotor at the top of the mast: the hub and grips, four blades drooping a little toward their
## tips (straight out to 2.6 m, then down 0.18 m by the tip). In the rotor's own space.
func _rotor() -> void:
	_tube(Vector3(0, -0.09, 0), Vector3(0, 0.09, 0), 0.32, 8, "metal", "metal")
	_tube(Vector3(0, 0.09, 0), Vector3(0, 0.22, 0), 0.12, 6, "black", "black")
	for k in 4:
		var b := Basis(Vector3.UP, k * PI / 2.0)
		_box_at(b, Vector3(0.38, 0, 0), Vector3(0.36, 0.1, 0.18), "metal")  # the grip
		var w := 0.21
		var t := 0.03
		var droop := 0.18
		var r := [0.25, 2.6, BLADE_TIP]
		var ys := [0.0, 0.0, -droop]
		var rings: Array = []
		for i in 3:
			var x: float = r[i]
			var y: float = ys[i]
			rings.append([b * Vector3(x, y + t, -w), b * Vector3(x, y + t, w), b * Vector3(x, y - t, w), b * Vector3(x, y - t, -w)])
		_loft(rings, _all("blade"), true)


## The tail rotor: its hub and two blades, striped toward the tips. In its own space (spun about z).
func _tail_rotor() -> void:
	_tube(Vector3(0, 0, -0.05), Vector3(0, 0, 0.08), 0.12, 6, "metal", "metal")
	for k in 2:
		var b := Basis(Vector3.BACK, k * PI / 2.0)
		var rings: Array = []
		for y in [-TAIL_BLADE, 0.0, TAIL_BLADE]:
			rings.append([b * Vector3(-0.09, y, -0.02), b * Vector3(0.09, y, -0.02), b * Vector3(0.09, y, 0.02), b * Vector3(-0.09, y, 0.02)])
		_loft(rings, _all("stripes"), true)


# --- Building blocks ------------------------------------------------------------------------

## Joins each ring of points to the next with quads (and closes the two ends if `caps`). zone(xm,
## j) says what face j between two rings (xm: their mean x) is: an atlas zone, or "" to leave it out.
func _loft(rings: Array, zone: Callable, caps: bool) -> void:
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var inside := (_centre(a) + _centre(b)) / 2.0
		var xm := inside.x
		for j in a.size():
			var j2 := (j + 1) % a.size()
			var z: String = zone.call(xm, j)
			if z != "":
				_poly([a[j], a[j2], b[j2], b[j]], inside, z)
	if caps:
		var first: Array = rings[0]
		var last: Array = rings[-1]
		_poly(first, _centre(rings[1]), zone.call(_centre(first).x, 3))
		_poly(last, _centre(rings[-2]), zone.call(_centre(last).x, 3))


## A zone for every face (for _loft).
func _all(zone: String) -> Callable:
	return func(_xm: float, _j: int) -> String: return zone


func _centre(pts: Array) -> Vector3:
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	return c / pts.size()


## A box (centre, size).
func _box(c: Vector3, size: Vector3, zone: String) -> void:
	_box_at(Basis.IDENTITY, c, size, zone)


## A box turned by `b` (about the origin of the space it's in), centred at b * c.
func _box_at(b: Basis, c: Vector3, size: Vector3, zone: String) -> void:
	var h := size / 2.0
	var lo: Array = []
	var hi: Array = []
	for p in [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]:
		lo.append(b * (c + p))
		hi.append(b * (c + Vector3(-p.x, p.y, p.z)))
	_loft([lo, hi], _all(zone), true)


## The inside of a box, lo to hi, its faces facing in, all but its +z side (the door's side).
func _box_inside(lo: Vector3, hi: Vector3) -> void:
	var c := (lo + hi) / 2.0
	var p := func(x: float, y: float, z: float) -> Vector3:
		return Vector3(lerpf(lo.x, hi.x, x), lerpf(lo.y, hi.y, y), lerpf(lo.z, hi.z, z))
	var faces := [
		[[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], "inside_wall"],  # the far wall
		[[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1], "inside_floor"],
		[[0, 1, 0], [1, 1, 0], [1, 1, 1], [0, 1, 1], "inside_wall"],  # the ceiling
		[[0, 0, 0], [0, 1, 0], [0, 1, 1], [0, 0, 1], "inside_wall"],  # the cockpit's bulkhead
		[[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1], "inside_wall"],  # the aft wall
	]
	for f: Array in faces:
		var pts: Array = []
		for k in 4:
			pts.append(p.call(f[k][0], f[k][1], f[k][2]))
		# Facing in: the "inside" point given is far outside past the face, so it faces the centre.
		var mid := _centre(pts)
		_poly(pts, mid + (mid - c) * 4.0, f[4])


## A tube of `sides` sides, radius r, from a to b (its ends capped: `cap` the zone at b).
func _tube(a: Vector3, b: Vector3, r: float, sides: int, zone: String, cap: String) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var ra: Array = []
	var rb: Array = []
	for k in sides:
		var ang := TAU * (k + 0.5) / sides
		var o := (side * cos(ang) + up * sin(ang)) * r
		ra.append(a + o)
		rb.append(b + o)
	_loft([ra, rb], _all(zone), false)
	_poly(ra, b, zone)
	_poly(rb, a, cap)


## A square bar, w thick, from a to b.
func _beam(a: Vector3, b: Vector3, w: float, zone: String) -> void:
	_tube(a, b, w * 0.7071, 4, zone, zone)


## A flat shape (x, y points, convex) given thickness from z0 to z1.
func _extrude_z(profile: Array, z0: float, z1: float, zone: String) -> void:
	var a: Array = []
	var b: Array = []
	for p: Vector2 in profile:
		a.append(Vector3(p.x, p.y, z0))
		b.append(Vector3(p.x, p.y, z1))
	_loft([a, b], _all(zone), true)


## A flat shape (x, z points, convex) given thickness from y0 to y1.
func _extrude_y(profile: Array, y0: float, y1: float, zone: String) -> void:
	var a: Array = []
	var b: Array = []
	for p: Vector2 in profile:
		a.append(Vector3(p.x, y0, p.y))
		b.append(Vector3(p.x, y1, p.y))
	_loft([a, b], _all(zone), true)


## A flat, convex polygon facing away from `inside`, flat-shaded, in `zone` (onto the glow mesh if
## it's a glowing zone).
func _poly(pts: Array, inside: Vector3, zone: String) -> void:
	var n := Vector3.ZERO  # Newell's normal (copes with repeated points)
	for k in pts.size():
		var p: Vector3 = pts[k]
		var q: Vector3 = pts[(k + 1) % pts.size()]
		n += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
	if n.length() < 1e-6:
		return
	n = n.normalized()
	if n.dot(_centre(pts) - inside) < 0.0:
		n = -n
	var st: SurfaceTool = _tools["glow" if zone in GLOW_ZONES else _target]
	for k in range(1, pts.size() - 1):
		var tri: Array = [pts[0], pts[k], pts[k + 1]]
		var c := ((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0])
		if c.length() < 1e-7:
			continue
		if c.dot(n) > 0.0:  # a front face winds clockwise
			tri = [tri[0], tri[2], tri[1]]
		for v: Vector3 in tri:
			st.set_normal(n)
			st.set_uv(uv(zone, v, n))
			st.add_vertex(v)


## Where on the atlas (0-1) the point p of a face facing n in `zone` is (PsxTextures' layout).
static func uv(zone: String, p: Vector3, n: Vector3) -> Vector2:
	var px := Vector2.ZERO
	var rect := Rect2(Vector2.ZERO, Vector2(PsxTextures.CHOPPER_SIZE))
	var a := n.abs()
	match zone:
		"paint":
			if a.z >= a.y and a.z >= a.x:  # the side views
				var far := n.z < 0.0
				var u := (PsxTextures.CHOPPER_X.y - p.x) if far else (p.x - PsxTextures.CHOPPER_X.x)
				rect = Rect2(0, PsxTextures.CHOPPER_SIDE_ROWS if far else 0, 180, PsxTextures.CHOPPER_SIDE_ROWS)
				px = Vector2(u * PsxTextures.CHOPPER_PX, (PsxTextures.CHOPPER_TOP_Y - p.y) * PsxTextures.CHOPPER_PX + rect.position.y)
			elif a.y >= a.x:  # the top view (the bottom too)
				rect = Rect2(PsxTextures.CHOPPER_TOP)
				px = rect.position + Vector2((p.x - PsxTextures.CHOPPER_X.x) * PsxTextures.CHOPPER_TOP_PX, (p.z + PsxTextures.CHOPPER_TOP_Z) * PsxTextures.CHOPPER_TOP_PX)
			else:  # the ends
				rect = Rect2(PsxTextures.CHOPPER_END)
				px = rect.position + Vector2((p.z + PsxTextures.CHOPPER_END_Z) * PsxTextures.CHOPPER_END_PX, (PsxTextures.CHOPPER_END_Y - p.y) * PsxTextures.CHOPPER_END_PX)
		"glass":
			var gx := (p.x - PsxTextures.CHOPPER_GLASS_X.x) / (PsxTextures.CHOPPER_GLASS_X.y - PsxTextures.CHOPPER_GLASS_X.x)
			if a.z >= a.y:
				rect = Rect2(PsxTextures.CHOPPER_RECTS["glass_side"])
				px = rect.position + rect.size * Vector2(gx, (PsxTextures.CHOPPER_GLASS_Y.x - p.y) / (PsxTextures.CHOPPER_GLASS_Y.x - PsxTextures.CHOPPER_GLASS_Y.y))
			else:
				rect = Rect2(PsxTextures.CHOPPER_RECTS["glass_top"])
				px = rect.position + rect.size * Vector2(gx, (p.z + CABIN_HALF) / (2.0 * CABIN_HALF))
		"inside_wall", "inside_floor":
			rect = Rect2(PsxTextures.CHOPPER_RECTS[zone])
			var ix := (p.x - PsxTextures.CHOPPER_INSIDE_X.x) / (PsxTextures.CHOPPER_INSIDE_X.y - PsxTextures.CHOPPER_INSIDE_X.x)
			if a.x > 0.5:
				ix = (p.z + CABIN_HALF) / (2.0 * CABIN_HALF)
			var iy := (PsxTextures.CHOPPER_INSIDE_Y.x - p.y) / (PsxTextures.CHOPPER_INSIDE_Y.x - PsxTextures.CHOPPER_INSIDE_Y.y)
			if a.y > 0.5:
				iy = (p.z + CABIN_HALF) / (2.0 * CABIN_HALF)
			px = rect.position + rect.size * Vector2(ix, iy)
		"door":
			rect = Rect2(PsxTextures.CHOPPER_RECTS["door"])
			px = rect.position + rect.size * Vector2((p.x - PsxTextures.CHOPPER_DOOR_X.x) / (PsxTextures.CHOPPER_DOOR_X.y - PsxTextures.CHOPPER_DOOR_X.x),
					(PsxTextures.CHOPPER_DOOR_Y.x - p.y) / (PsxTextures.CHOPPER_DOOR_Y.x - PsxTextures.CHOPPER_DOOR_Y.y))
		"blade":
			rect = Rect2(PsxTextures.CHOPPER_RECTS["blade"])
			px = rect.position + rect.size * Vector2(Vector2(p.x, p.z).length() / BLADE_TIP, 0.5)
		"stripes":
			rect = Rect2(PsxTextures.CHOPPER_RECTS["stripes"])
			px = rect.position + rect.size * Vector2(Vector2(p.x, p.y).length() / TAIL_BLADE, 0.5)
		_:  # one colour: the middle of its swatch
			rect = Rect2(PsxTextures.CHOPPER_RECTS[zone])
			px = rect.get_center()
	# Kept half a pixel inside its own patch, so nothing picks up its neighbour's.
	px = px.clamp(rect.position + Vector2(0.5, 0.5), rect.end - Vector2(0.5, 0.5))
	return px / Vector2(PsxTextures.CHOPPER_SIZE)
