class_name RealmDefaults
extends RefCounted

## The shared 30-realm ladder: 9 Mortal, 9 Spirit, 9 Immortal, 3 Transcendent
## (ADR 0005). Append-only; adding a realm is data.

const MORTAL := 1
const SPIRIT := 2
const IMMORTAL := 3
const TRANSCENDENT := 4

static var _ladder: RealmLadder


static func ladder() -> RealmLadder:
	if _ladder == null:
		_ladder = RealmLadder.new(_all())
	return _ladder


static func _all() -> Array[RealmDef]:
	var realms: Array[RealmDef] = [
		_make(&"qi_refining", "Qi Refining", MORTAL),
		_make(&"foundation", "Foundation Establishment", MORTAL),
		_make(&"core_formation", "Core Formation", MORTAL),
		_make(&"nascent_soul", "Nascent Soul", MORTAL),
		_make(&"spirit_transformation", "Spirit Transformation", MORTAL),
		_make(&"void_refinement", "Void Refinement", MORTAL),
		_make(&"body_integration", "Body Integration", MORTAL),
		_make(&"great_ascension", "Great Ascension", MORTAL),
		_make(&"tribulation", "Tribulation Crossing", MORTAL),
		_make(&"spirit_condensation", "Spirit Condensation", SPIRIT),
		_make(&"spirit_sea", "Spirit Sea", SPIRIT),
		_make(&"spirit_palace", "Spirit Palace", SPIRIT),
		_make(&"spirit_manifestation", "Spirit Manifestation", SPIRIT),
		_make(&"spirit_severing", "Spirit Severing", SPIRIT),
		_make(&"spirit_unity", "Spirit Unity", SPIRIT),
		_make(&"spirit_domain", "Spirit Domain", SPIRIT),
		_make(&"spirit_sovereign", "Spirit Sovereign", SPIRIT),
		_make(&"spirit_ascension", "Spirit Ascension", SPIRIT),
		_make(&"earth_immortal", "Earth Immortal", IMMORTAL),
		_make(&"heaven_immortal", "Heaven Immortal", IMMORTAL),
		_make(&"golden_immortal", "Golden Immortal", IMMORTAL),
		_make(&"mystic_immortal", "Mystic Immortal", IMMORTAL),
		_make(&"true_immortal", "True Immortal", IMMORTAL),
		_make(&"primordial_immortal", "Primordial Immortal", IMMORTAL),
		_make(&"great_luo", "Great Luo Immortal", IMMORTAL),
		_make(&"dao_fruit", "Dao Fruit", IMMORTAL),
		_make(&"immortal_sovereign", "Immortal Sovereign", IMMORTAL),
		_make(&"transcendent", "Transcendent", TRANSCENDENT),
		_make(&"dao_ancestor", "Dao Ancestor", TRANSCENDENT),
		_make(&"primordial_origin", "Primordial Origin", TRANSCENDENT),
	]
	for i in realms.size():
		realms[i].power = 1.0 + i * 0.1
	return realms


static func _make(id: StringName, display_name: String, tier: int) -> RealmDef:
	var entry := RealmDef.new()
	entry.id = id
	entry.display_name = display_name
	entry.tier = tier
	return entry
