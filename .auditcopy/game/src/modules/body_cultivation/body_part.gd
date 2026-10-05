class_name BodyPart
extends RefCounted

## A limb a body actually HAS. The unit a material art grows.
##
## ## Absent is a real state, not an empty one
##
## A body has no entry for a limb it was never given. That absence is the whole
## premise of the material arts: the part does not exist and the art is what
## creates it, so "buff the arm" is a different verb that lives in
## `BodyPractice`'s demand stats and never touches this file.
##
## ## A grown part is built out of matter, and matter has a price
##
## `integrity` is the reservoir this part holds, drained by the material arts'
## own cost and refilled by the body's ordinary recovery. A rebuilt limb is not a
## free limb: it is a reservoir a wielder has to keep paid, which is the yin-yang
## half of "grow a part".

var id: StringName = &""
var display_name: String = ""
## The material art that grew this part, so a panel can say WHAT it is made of.
var art_id: StringName = &""
## The body demand the matter placed on it. The liability, carried on the part
## itself rather than only on the art, so a save restores the burden with the limb.
var demand: StringName = &""
## Reservoir this part holds, in integrity units.
var integrity: float = 0.0
## How many times this part has been rebuilt. Not a magnitude of the part: a
## counter of the art's own history.
var rebuilds: int = 0


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"art_id": String(art_id),
		"demand": String(demand),
		"integrity": integrity,
		"rebuilds": rebuilds,
	}


static func from_dict(data: Dictionary) -> BodyPart:
	var part := BodyPart.new()
	part.id = StringName(data.get("id", ""))
	part.display_name = String(data.get("display_name", ""))
	part.art_id = StringName(data.get("art_id", ""))
	part.demand = StringName(data.get("demand", ""))
	part.integrity = float(data.get("integrity", 0.0))
	part.rebuilds = int(data.get("rebuilds", 0))
	return part
