class_name ItemRarity
extends RefCounted

## Rarity policy (ADR 0025). Separate from grade and from the item's realm.
## Controls how many rolled options an item receives, which affix positions are
## eligible, and the magnitude/socket budgets. Grade is never read here.

const COMMON := &"common"
const MAGIC := &"magic"
const RARE := &"rare"
const LEGENDARY := &"legendary"

const ALL := [COMMON, MAGIC, RARE, LEGENDARY]

## Per rarity: rolled option count, affix positions, socket cap, and the extra
## magnitude budget multiplier applied on top of the catalog realm policy.
const POLICY := {
	COMMON: {"count": 1, "contexts": ["prefix"], "sockets": 0, "budget": 0.0},
	MAGIC: {"count": 2, "contexts": ["prefix", "postfix"], "sockets": 0, "budget": 0.25},
	RARE: {"count": 3, "contexts": ["prefix", "postfix"], "sockets": 1, "budget": 0.5},
	LEGENDARY: {"count": 4, "contexts": ["prefix", "postfix"], "sockets": 2, "budget": 1.0},
}


static func is_valid(rarity: StringName) -> bool:
	return POLICY.has(rarity)


static func tier(rarity: StringName) -> int:
	return ALL.find(rarity)


static func affix_count(rarity: StringName) -> int:
	return int(POLICY.get(rarity, POLICY[COMMON])["count"])


static func contexts(rarity: StringName) -> Array:
	var entry: Dictionary = POLICY.get(rarity, POLICY[COMMON])
	var out: Array = []
	for context in entry["contexts"]:
		out.append(StringName(context))
	return out


static func socket_cap(rarity: StringName) -> int:
	return int(POLICY.get(rarity, POLICY[COMMON])["sockets"])


static func magnitude_budget(rarity: StringName) -> float:
	return float(POLICY.get(rarity, POLICY[COMMON])["budget"])


## Clamp an authored rarity to a known value so malformed content degrades to
## the conservative common tier rather than producing an unbudgeted item.
static func sanitize(rarity: StringName) -> StringName:
	return rarity if POLICY.has(rarity) else COMMON


static func display_name(rarity: StringName) -> String:
	match sanitize(rarity):
		MAGIC:
			return L.t("LOC_ITEMS_E6791BE7EE")
		RARE:
			return L.t("LOC_ITEMS_CCE370D2F9")
		LEGENDARY:
			return L.t("LOC_ITEMS_B7E8916505")
		_:
			return L.t("LOC_ITEMS_7DE90A6524")
