class_name RelationshipType
extends RefCounted

## The type of a relationship between two actors (ADR 0123).
##
## **Ordered by commitment.** A relationship can move forward (NONE → FRIEND → ROMANTIC
## → SPOUSE) or backward, but it cannot skip steps. DC_PARTNER is orthogonal — it flags
## a partner for dual cultivation tracking regardless of the romantic type.

const NONE := &"none"
const FRIEND := &"friend"
const ROMANTIC := &"romantic"
const SPOUSE := &"spouse"
const DC_PARTNER := &"dc_partner"


static func all() -> Array[StringName]:
	return [NONE, FRIEND, ROMANTIC, SPOUSE, DC_PARTNER]


static func is_valid(type: StringName) -> bool:
	return type == NONE or type == FRIEND or type == ROMANTIC or type == SPOUSE or type == DC_PARTNER
