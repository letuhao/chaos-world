class_name RealmDefaults
extends RefCounted

## The shared realm ladder: 9 Mortal, 9 Spirit, 9 Immortal, 3 Transcendent
## (ADR 0005). Append-only, and appending is `register_realms` below rather than an
## edit to the authored rows — see the note there for why the rows live in this
## file's text.

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

## Realms appended to the AUTHORED base by `register_realms`: a mod's, or content's.
## An array rather than a single realm so one call can extend the ladder by as many
## realms as the caller needs. Empty in the shipped game.
static var _extensions: Array[RealmDef] = []


static func ladder() -> RealmLadder:
	if _ladder == null:
		_ladder = RealmLadder.new(_all())
	return _ladder


## Append realms to the shared ladder without editing the authored rows. This is what
## makes the ladder DATA rather than a code literal: a realm is added by handing over
## a `RealmDef`, not by inserting a `_make(...)` call into `_all()`.
##
## The authored rows deliberately stay in THIS file's source text, because four Python
## tools parse them as text — `tools/realm_power.py` (`REALM_LINE`),
## `tools/cultivation/seed.py`, `tools/cultivation/seed_systems.py` and
## `tools/item_migrate.py`. Relocating them to a `.tres` is the textbook "make it data"
## move and it would leave all four looking at an empty ladder, so the extensibility
## had to come from a seam instead. That is the honest trade: the ladder is extensible
## and single-authored, and the row location is a tooling contract rather than an
## accident.
##
## The built ladder is DROPPED so the next `ladder()` rebuilds, and the rebuild reads
## `RealmDef.power` by ID for the appended realms exactly as it does for the authored
## ones. A cached ladder that ignored a later append is the stale-cache shape the note
## in `_all()` below already cost one field.
##
## A realm already on the ladder is not appended twice: the ladder is keyed by ID, so
## a duplicate would shadow the first and `index_of` would answer for the wrong one.
## A realm with no ID is refused for the same reason — a keyed table cannot hold a
## keyless row. Returns the IDs actually accepted, so a caller that has to undo the
## call (a mod unloading) knows what to undo.
static func register_realms(realms: Array[RealmDef]) -> Array[StringName]:
	var accepted: Array[StringName] = []
	for realm in realms:
		var id := realm.id
		if String(id) == "":
			continue
		_extensions.append(realm)
		accepted.append(id)
	_ladder = null
	return accepted


## Drop realms a caller previously registered, for a mod unloading. Authored realms are
## never in `_extensions`, so this cannot remove one. Returns the IDs actually removed.
static func unregister_realms(realm_ids: Array[StringName]) -> Array[StringName]:
	var removed: Array[StringName] = []
	# The bound is the `_extensions.size()` SNAPSHOT the `range` is built from, taken
	# before the loop; the body erases from `_extensions` as it walks, so a condition
	# that re-read the live size would shrink in lockstep with the index and skip
	# entries (INC-0002). Walking backwards keeps every unremoved entry's index valid
	# after an erase.
	for index in range(_extensions.size() - 1, -1, -1):
		var entry := _extensions[index]
		if realm_ids.has(entry.id):
			removed.append(entry.id)
			_extensions.remove_at(index)
	_ladder = null
	return removed


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
	# Registered realms are appended AFTER the authored rows and BEFORE the power pass,
	# so an extension is powered by the same keyed lookup as an authored one. Assembling
	# after the power pass would leave it on the neutral 1.0 default.
	for realm in _extensions:
		if not _carries(realms, realm.id):
			realms.append(realm)
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


## Whether the ladder as assembled so far already carries `id`. Bounded by the
## container it walks, appends nothing, and returns on the first hit — so no pass
## grows the collection it is being tested against (INC-0002).
static func _carries(realms: Array[RealmDef], id: StringName) -> bool:
	for realm in realms:
		if realm.id == id:
			return true
	return false


static func _make(id: StringName, display_name: String, tier: int) -> RealmDef:
	var entry := RealmDef.new()
	entry.id = id
	entry.display_name = display_name
	entry.tier = tier
	return entry
