class_name Skins
## The operative's skins (the decision log's "UNLOCKS: picking the operative's skin"): CROSS, his
## skins and the other two operatives, in the order UNLOCKS shows them, each with what unlocks it.
## Every one has CROSS's 19 joints, so his rig (SoldierRig) and every pose fit them all.

## The one everyone starts with.
const DEFAULT := "cross"

## In UNLOCKS' order: each one's id (its model's file name), its name, and what unlocks it: getting
## out of mission [n] on [setting] (none: always open). A first pass, to be set by the user.
const LIST := [
	{"id": "cross", "name": "CROSS"},
	{"id": "shadow", "name": "SHADOW", "unlock": [1, "easy"]},
	{"id": "casual", "name": "CASUAL", "unlock": [1, "medium"]},
	{"id": "tropical", "name": "TROPICAL", "unlock": [1, "hard"]},
	{"id": "midnight", "name": "MIDNIGHT", "unlock": [2, "easy"]},
	{"id": "silent", "name": "SILENT", "unlock": [2, "medium"]},
	{"id": "rebel", "name": "REBEL", "unlock": [2, "hard"]},
	{"id": "future", "name": "FUTURE", "unlock": [3, "easy"]},
	{"id": "jungle", "name": "JUNGLE", "unlock": [3, "medium"]},
	{"id": "street", "name": "STREET", "unlock": [3, "hard"]},
	{"id": "bishop", "name": "BISHOP", "unlock": [6, "hard"]},
	{"id": "vesper", "name": "VESPER", "unlock": [9, "hard"]},
]

## The other operatives (their own models, in game/player); the rest are CROSS's skins (game/player/skins).
const OPERATIVES := ["bishop", "vesper"]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in LIST:
		out.append(String(s["id"]))
	return out


static func has(id: String) -> bool:
	return ids().has(id)


static func index_of(id: String) -> int:
	return maxi(0, ids().find(id))


static func info(id: String) -> Dictionary:
	return LIST[index_of(id)]


## What unlocks it: [mission, setting], or [] when it's always open.
static func unlock_of(id: String) -> Array:
	return info(id).get("unlock", [])


## Its model's file and its settings file (the goggles' lenses, Street's ribbons).
static func model_path(id: String) -> String:
	if id == DEFAULT:
		return SoldierRig.MODEL.resource_path
	return "res://game/player/%s%s.glb" % ["" if OPERATIVES.has(id) else "skins/", id]


static func lens_path(id: String) -> String:
	if id == DEFAULT:
		return SoldierRig.LENS_FILE
	return model_path(id).get_basename() + ".json"


## The rig for it, as the player wears it (named CROSS whoever it is: he's the one running).
static func make_rig(id: String) -> SoldierRig:
	if not has(id) or id == DEFAULT:
		return SoldierRig.new()
	return SoldierRig.new(load(model_path(id)) as PackedScene, lens_path(id), "CROSS")
