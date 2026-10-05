class_name RealmDefaults
extends RefCounted

## The shared 30-realm ladder: 9 Mortal, 9 Spirit, 9 Immortal, 3 Transcendent
## (ADR 0005). Append-only; adding a realm is data.

const MORTAL := 1
const SPIRIT := 2
const IMMORTAL := 3
const TRANSCENDENT := 4

## The authored per-realm stat multipliers, indexed by ladder position (ADR 0050).
## A plain preload: it resolves a file and calls nothing here, which is the whole point
## (see the note in `_all()`).
const POWER := preload("res://src/core/realm_power_table.tres")

## The authored per-REALM-TIER lifespan multipliers (ADR 0169), beside `POWER` and for
## the same reason: reading a file calls nothing here. NOT `RealmDef.power` and NOT a
## ladder position, so it is deliberately NOT assigned in `_all()` like power is — a
## realm's lifespan is a function of its BAND, so the lookup happens where an actor's
## tier is known (`RaceProvider.contribute`, through
## `RealmLifespan.effective_days`), not once per realm at ladder build time.
const LIFESPAN := preload("res://src/core/realm_lifespan_table.tres")

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
	# `RealmDef.power` is AUTHORED, loaded from `POWER` above, and that is load-bearing
	# in three directions.
	#
	# It must stay an input. The first version of this field was filled here from
	# `PowerLadder.value(i)`, and the ladder needs the realm COUNT to solve its own
	# coefficients - so building the ladder called `RealmDefaults.ladder()` from inside
	# `RealmDefaults._all()` and recursed until the stack blew. A derived value cached on
	# the object that produces its own input is the defect; the table has no such cycle,
	# because reading a file cannot need the realm count (ADR 0050).
	#
	# It must stay a field. A consumer that reaches through `RealmDefaults` to look the
	# number up itself holds a private copy of the same contract, and the two drift the
	# first time a realm is added.
	#
	# It must be looked up by id. The table is keyed by realm id, so a realm inserted in
	# the middle of the ladder cannot shift every realm below it onto the wrong number.
	for realm in realms:
		realm.power = POWER.power_for(realm.id)
	return realms


static func _make(id: StringName, display_name: String, tier: int) -> RealmDef:
	var entry := RealmDef.new()
	entry.id = id
	entry.display_name = display_name
	entry.tier = tier
	return entry
