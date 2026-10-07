extends TestCase

## ADR 0090 (the catalogue is authored `.tres` data) and ADR 0110 (the ten tier-2
## statuses are authored content, and the loader now PUBLISHES them).
##
## These assertions are about CONTENT, not behaviour: all twenty authored defs exist on
## disk, are well-formed, ride one of the ten elements, publish their counterplay, and
## are two DISTINCT mechanics per element. A catalogue that loads is not a catalogue that
## is legal — `StatusDef.problems()` is the gate, and these tests are the gate's
## regression list.
##
## ## What changed and why, stated once so the rest need not repeat it
##
## ADR 0110 SUPERSEDES ADR 0090's tier-1-only clause. That clause was a BALANCE reason,
## not an authoring one: ADR 0069 measured every tier-2 matchup row strictly dominant, so
## a status on an advanced element balanced content on a broken table. The balance
## objection is now answered in code — `ElementProvider`'s `TIER_MASTERY_STEP` taxes the
## mastery term of a tier-2 element until its row mean sits on tier-1's — so the gate
## moved with it. `StatusDef.AUTHORED_ELEMENTS` is all ten elements;
## `TIER_ONE_ELEMENTS`/`TIER_TWO_ELEMENTS` survive as the two halves it is assembled from;
## and an element outside all ten is refused, NAMED, and REPORTED through `rejected()`
## rather than silently dropped.
##
## So the ten tier-2 ids are PUBLISHED rather than loaded-and-refused, and every test
## below that used to read the CONTENT TREE to reach one now reads the catalogue. Because
## the catalogue is a closed twenty, the strong claims here are the EXACT id set and the
## per-element PAIRING — a population count would still be true of a different twenty.

## The ten tier-1 ids. Authored content may not drift into a different set without a
## decision, so this list is pinned.
const TIER_ONE_IDS: Array[StringName] = [
	&"metal_sever",
	&"metal_sunder",
	&"wood_bloom",
	&"wood_parasite",
	&"water_chill",
	&"water_deluge",
	&"fire_immolation",
	&"fire_pyre",
	&"earth_bulwark",
	&"earth_quake",
]

## The ten tier-2 ids (ADR 0110), two per advanced element. Pinned for the same reason.
const TIER_TWO_IDS: Array[StringName] = [
	&"lightning_arc",
	&"lightning_surge",
	&"ice_rime",
	&"ice_shatter",
	&"wind_gust",
	&"wind_spread",
	&"light_brand",
	&"light_halo",
	&"dark_corrosion",
	&"dark_wane",
]

## Every id the catalogue publishes. Asserted as an exact SET rather than as a size, so a
## twenty-first def fails loudly and a substituted one fails just as loudly.
const EXPECTED_IDS: Array[StringName] = TIER_ONE_IDS + TIER_TWO_IDS

## The seven CULTIVATION blessings authored by ADR 0919, one per element that shipped
## none, so every element now pays exactly ONE permanent blessing. Kept separate from
## [constant EXPECTED_IDS] because the ADR 0090/0110 pairing claims below are about the
## element's ORIGINAL pair, and a blessing is a THIRD def wherever the pair's second
## member is not already the blessing (`wood`, `earth` and `light` ship theirs inside
## the pair, which is why seven ids are new rather than ten).
const BLESSING_IDS: Array[StringName] = [
	&"metal_temper",
	&"water_wellspring",
	&"fire_forge",
	&"lightning_quicken",
	&"ice_stillness",
	&"wind_stride",
	&"dark_veil",
]

## Everything the catalogue publishes: the closed pair content plus the blessings.
const ALL_IDS: Array[StringName] = EXPECTED_IDS + BLESSING_IDS

## The four blessings whose elements are ADVANCED, for the tier-2 id-set pin.
const ADVANCED_BLESSING_IDS: Array[StringName] = [
	&"lightning_quicken",
	&"ice_stillness",
	&"wind_stride",
	&"dark_veil",
]

## The `mechanic` each tier-1 element's pair is built from. ADR 0090's claim was "ten
## distinct mechanics" — ten shapes because ten were authored, against a closed ten-name
## vocabulary (`StatusDef.MECHANICS`). ADR 0110's ten REUSE those shapes rather than
## widening the vocabulary, so this doubles as the set the vocabulary may be read from.
const TIER_ONE_MECHANICS: Dictionary = {
	&"metal": [&"bleed", &"sunder"],
	&"wood": [&"drain", &"regrowth"],
	&"water": [&"slow", &"wave"],
	&"fire": [&"escalating_burn", &"feed_siblings"],
	&"earth": [&"brace", &"root"],
}

## One claimed landed-blow status per element, `element -> id`. Pinned because
## `StatusApi.status_for_element` is a LOOK-UP: a catalogue that quietly re-pointed a slot
## would keep every count in this file true while changing what a blow actually inflicts.
const CLAIMED_BY_ELEMENT: Dictionary = {
	&"metal": &"metal_sever",
	&"wood": &"wood_parasite",
	&"water": &"water_chill",
	&"fire": &"fire_immolation",
	&"earth": &"earth_quake",
	&"lightning": &"lightning_arc",
	&"ice": &"ice_rime",
	&"wind": &"wind_gust",
	&"light": &"light_brand",
	&"dark": &"dark_corrosion",
}

## The magnitude channels that spend a pool. A PAIR is only the shape ADR 0090 asks for
## when one of its two members is a channel and the other is not: two statuses that both
## spend a pool are two damage numbers wearing different names.
const PULSE_UNITS: Array[StringName] = [&"health_share", &"element_power"]

## The text `StatusDef.problems()` reports for an element outside
## `StatusDef.AUTHORED_ELEMENTS`: the GATE this file tests, named rather than rebuilt.
## ADR 0110 moved this gate from "tier-2 is out" to "the tenth element is in".
const UNKNOWN_ELEMENT_GATE := "not one of the ten authored elements"

## Ids no `.tres` claims and `rejected()` has never heard of. The public spelling of ADR
## 0090's "refused, not deferred-and-forgotten" — and the only refusal that SURVIVED the
## gate's widening, because ADR 0090 refused these two on their OWN reasoning (no
## victim-side stat to amplify; a rewrite of ten resistance ids) rather than on their
## element. ADR 0110 changed neither of those things, so they are still unpublished.
const UNPUBLISHED_IDS: Array[StringName] = [&"light_expose", &"dark_erasure"]

## All ten elements, assembled rather than restated so a tenth would be caught here.
## `gdlintrc` scopes class variables to lowercase snake, so this is not CONSTANT_CASE
## despite being a `static var` — the same shape as any other module-scoped cache, and
## deliberately not `_`-prefixed so it cannot collide with the reader below.
static var all_elements_cache: Array[StringName] = []


func _all_elements() -> Array[StringName]:
	if all_elements_cache.is_empty():
		all_elements_cache.assign(ElementStats.BASE_ELEMENTS)
		all_elements_cache.append_array(ElementStats.ADVANCED_ELEMENTS)
	return all_elements_cache


func _catalog() -> StatusCatalog:
	return StatusCatalog.instance()


## Every authored def ON DISK keyed by its declared `id`, including any the loader refuses.
## A directory walk rather than a list of pinned paths, because a file nothing here names
## must still be counted. Keyed by `id`, so a rename changes nothing.
func _authored() -> Dictionary:
	var out: Dictionary = {}
	for entry in DirAccess.get_files_at(StatusCatalog.STATUSES_ROOT):
		if not entry.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [StatusCatalog.STATUSES_ROOT, entry]) as StatusDef
		if def != null and def.id != &"":
			out[String(def.id)] = def
	return out


## `{element: [StatusDef, ...]}` over the authored tree, so a count is a count of FILES.
func _per_element(authored: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in authored.keys():
		var def := authored[key] as StatusDef
		var pair: Array = out.get(def.element, [])
		pair.append(def)
		out[def.element] = pair
	return out


## `{id: reason}` for everything the loader turned away. Empty is the claim a well-formed
## tree has to make, and this is how a refusal is read back rather than inferred from an
## absent id.
func _refused_reasons() -> Dictionary:
	var out: Dictionary = {}
	for entry in _catalog().rejected():
		out[String((entry as Dictionary).get("id", ""))] = String(
			(entry as Dictionary).get("reason", "")
		)
	return out


## Ids AS Strings. The catalogue hands back an `Array[StringName]` and [method Array.sort]
## orders that by the StringName POINTER rather than by the name it carries — which is
## exactly why `StatusCatalog` sorts its ids the way it does. So both sides of every
## ordering assertion below are compared as Strings.
func _as_strings(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(id))
	return out


func _sorted(values: Array) -> Array[String]:
	var out := _as_strings(values)
	out.sort()
	return out


## Every published id whose element is `element`, in catalogue order. `.filter()` rather
## than a hand-rolled loop so the order is the catalogue's own rather than a re-derivation.
func _ids_on(element: StringName) -> Array[String]:
	var wanted := String(element)
	var picked: Array[StringName] = []
	for status_id in _catalog().status_ids():
		if String((StatusApi.definition(status_id) as StatusDef).element) == wanted:
			picked.append(status_id)
	return _as_strings(picked)


## The mechanics a pair of defs names, sorted, as Strings. Sorted because the pair arrives
## in `DirAccess` order while the claim is about the SET an element ships; compared as
## text because that is what a reader of a failure line wants to see.
func _mechanics_of(pair: Array) -> Array[String]:
	var out: Array[String] = []
	for def in pair:
		out.append(String((def as StatusDef).mechanic()))
	out.sort()
	return out


## The element's ADR 0090/0110 PAIR: its authored defs minus the seven blessings ADR 0919
## added. The three ORIGINAL blessings (`wood_bloom`, `earth_bulwark`, `light_halo`) are
## pair members and stay, so this filter is exactly the new set — the pairing claims are
## about the pair the two ADRs authored, and a blessing is a third def wherever one was
## added.
func _pair_without_blessings(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		if BLESSING_IDS.has((def as StatusDef).id):
			continue
		out.append(def)
	return out


func test_the_catalogue_publishes_exactly_the_authored_statuses() -> void:
	# ADR 0110 publishes the ten new pair defs rather than refusing them, and ADR 0919
	# adds the seven blessings whose elements shipped none, so the catalogue's whole
	# content is its twenty-seven. The id SET is pinned and every element's slot is read
	# through the LOOK-UP, because a size would be true of any set at all.
	var ids := _catalog().status_ids()
	assert_eq(_sorted(ids), _sorted(ALL_IDS), "exactly the authored ids")
	for element in _all_elements():
		assert_eq(
			StatusApi.status_for_element(element, 1.0),
			CLAIMED_BY_ELEMENT.get(element, &""),
			"%s answers with the status its .tres claimed" % String(element)
		)
	# The ORDER is part of the contract too, and determinism is ADR 0090's claim rather
	# than alphabetisation: `StatusCatalog` sorts its `Array[StringName]` in StringName
	# order, which is neither pointer order a reader can predict nor string order — measured
	# here, the catalogue answers `dark_wane, dark_corrosion, light_halo, …`. So the pin is
	# that the order is FIXED, read back twice, and demonstrably NOT alphabetical. An
	# assertion about a hand-sorted order would be a test of a fiction the loader never had.
	assert_eq(_as_strings(ids), _as_strings(_catalog().status_ids()), "the order is stable")
	assert_ne(
		_as_strings(ids),
		_sorted(ids),
		"and the catalogue's own order is not alphabetical, so the pin above is the real one"
	)


func test_every_published_def_is_well_formed() -> void:
	# The positive half of ADR 0110's old load-bearing claim, and now the only half: the
	# ten new defs are ACCEPTED, so `problems()` is empty across the whole twenty. An empty
	# `problems()` must not be satisfiable by a tree that published nothing, so the two
	# facts it leans on are asserted beside it — twenty defs on disk, and an empty
	# `rejected()`. Without those this would also pass on a loader that loaded nothing at
	# all, which is the refusal path's mirror image.
	assert_eq(_catalog().problems(), [], "no published def reports an authoring problem")
	assert_eq(_refused_reasons(), {}, "and no authored def was refused at load")
	assert_eq(_authored().size(), ALL_IDS.size(), "every authored def is on disk to publish")


func test_every_tier_two_def_validates_clean_and_publishes() -> void:
	# What ADR 0110 buys, and the assertion the tier-1-only world could not express. A
	# tier-2 def used to be refused, so the only way to inspect one was to read the CONTENT
	# TREE; it now validates against every rule the tier-1 ten do, resolves by id through
	# the facade, and appears in `rejected()` nowhere.
	var authored := _authored()
	var refused := _refused_reasons()
	for status_id in TIER_TWO_IDS:
		var key := String(status_id)
		var def := authored.get(key) as StatusDef
		assert_ne(def, null, "%s is authored on disk" % key)
		assert_eq(def.problems(), [], "%s validates clean like a tier-1 def" % key)
		assert_eq(refused.has(key), false, "%s is not rejected" % key)
		var resolved := StatusApi.definition(status_id)
		assert_ne(resolved, null, "%s resolves through the facade" % key)
		assert_eq(resolved.id, status_id, "and resolves to itself, not to a neighbour")
		# The resolved element is the load-bearing half, because it is the one
		# `status_for_element` walks; the on-disk one only says what the `.tres` declares.
		assert_eq(resolved.element, def.element, "%s still rides its authored element" % key)


func test_the_gate_boundary_is_exactly_the_authored_element_list() -> void:
	# What the gate actually is, read off `StatusDef.AUTHORED_ELEMENTS` rather than
	# restated: all TEN elements pass, and an eleventh is refused with the element gate's
	# reason and NOTHING else. A second problem on the eleventh would mean the probe itself
	# is malformed, which is why the single-problem assertion is here rather than implied.
	#
	# Built fresh rather than mutated in place: `load()` caches, so the `StatusDef` the
	# CATALOGUE holds is the same instance — reassigning its element would corrupt the tree
	# every later test in this run reads.
	for element in _all_elements():
		var def := _probe()
		def.element = element
		assert_eq(_gated(def), 0, "a %s def is accepted by the gate" % String(element))
	var eleventh := _probe()
	eleventh.element = &"aether"
	assert_eq(_gated(eleventh), 1, "an element outside all ten is gated")
	assert_eq(eleventh.problems().size(), 1, "and the element gate is the ONLY reason")
	assert_eq(
		String(eleventh.problems()[0]).contains(UNKNOWN_ELEMENT_GATE),
		true,
		"named as the ten authored elements"
	)
	# The lists the gate reads are the elements module's own, so an eleventh element added
	# to one side alone fails here instead of silently re-shaping the boundary.
	assert_eq(StatusDef.TIER_ONE_ELEMENTS, ElementStats.BASE_ELEMENTS, "tier-1 half matches")
	assert_eq(
		StatusDef.TIER_TWO_ELEMENTS,
		ElementStats.ADVANCED_ELEMENTS,
		"tier-2 half matches (ADR 0110)"
	)
	assert_eq(StatusDef.AUTHORED_ELEMENTS, _all_elements(), "and the gate's list is exactly ten")


## A detached copy of an authored def: same field values, its own instance, so a probe can
## mutate it without touching the cached resource the catalogue holds. `duplicate()` rather
## than a field-by-field copy because a copied field list is a second vocabulary that rots
## the first time `StatusDef` grows a field.
##
## No `template_id`: `problems()` is PURE, so a probe only has to be a well-formed authored
## def with a DIFFERENT element, and every caller overwrites the one field it is testing.
## One template is what makes that safe — a `metal_sever` probe for a `lightning` assertion
## and the same one for an `aether` one differ by the element and nothing else.
func _probe() -> StatusDef:
	var template := load("%s/%s.tres" % [StatusCatalog.STATUSES_ROOT, "metal_sever"]) as StatusDef
	var copy: StatusDef = template.duplicate()
	copy.payload = template.payload.duplicate(true)
	return copy


## How many of `def`'s problems are the authored-element gate. Zero is the claim being
## tested; one means the gate is the only thing holding this def back, and anything more
## means the def has a REAL defect the gate is merely also masking.
func _gated(def: StatusDef) -> int:
	var count := 0
	for problem in def.problems():
		if String(problem).contains(UNKNOWN_ELEMENT_GATE):
			count += 1
	return count


func test_ids_are_unique_and_the_file_name_is_not_the_key() -> void:
	# One pass over the CONTENT TREE, which is all twenty ids at once. Walking the
	# catalogue and then the tree separately looked equivalent and was not: the catalogue
	# only holds what it published, so the second loop re-tested those ids against a `seen`
	# map they had already populated and reported them as duplicates.
	var seen: Dictionary = {}
	for key in _authored().keys():
		assert_eq(seen.has(StringName(key)), false, "id %s is authored once" % String(key))
		seen[StringName(key)] = true
	assert_eq(_sorted(seen.keys()), _sorted(ALL_IDS), "distinct authored ids")
	# Resolution is by id, so a def is found by the id a save would store, not by the
	# filename it happens to live under.
	assert_eq(StatusApi.definition(&"fire_pyre").id, &"fire_pyre", "resolved by id")


func test_every_status_rides_an_element_that_exists() -> void:
	# The restated element lists cannot silently drift from the elements module's own; this
	# is the assertion that keeps that true. ADR 0110 gives it a third list to pin, because
	# `AUTHORED_ELEMENTS` is the one `problems()` actually gates on: a def that drifted off
	# THAT would be refused at load, and the tree-wide `problems()` assertion would catch it
	# without saying which element or which def.
	assert_eq(StatusDef.TIER_ONE_ELEMENTS, ElementStats.BASE_ELEMENTS, "tier-1 list matches")
	assert_eq(StatusDef.TIER_TWO_ELEMENTS, ElementStats.ADVANCED_ELEMENTS, "tier-2 list matches")
	for status_id in _catalog().status_ids():
		var def := StatusApi.definition(status_id)
		assert_eq(
			StatusDef.AUTHORED_ELEMENTS.has(def.element),
			true,
			(
				"%s rides one of the ten authored elements (%s)"
				% [String(status_id), String(def.element)]
			)
		)
	# And every element is COVERED — exactly two, not zero. An element with no authored
	# status is one a landed blow could never inflict, which was `lightning`'s state for
	# the whole of ADR 0090 and is no longer any element's.
	for element in _all_elements():
		var on_element := _ids_on(element)
		assert_eq(
			on_element.size() >= 2 and on_element.size() <= 3,
			true,
			"%s ships its pair plus at most one blessing" % String(element)
		)
		var blessings := 0
		for id in on_element:
			var def := StatusApi.definition(StringName(id)) as StatusDef
			if def != null and not def.is_combat_scope():
				blessings += 1
		assert_eq(blessings, 1, "%s ships exactly one cultivation blessing" % String(element))


func test_every_status_publishes_non_empty_mitigation_tags() -> void:
	# ADR 0090 restates ADR 0075's rule for a status: empty is an authoring error the
	# audit rejects, not a free tax. Twenty statuses, twenty non-empty lever sets — and
	# the check runs over the CONTENT TREE, because a tier-2 def used to be unable to
	# ship a status nothing answered to without the loader's gate hiding the fact. ADR 0110
	# lifted the gate, so those ten are on the same footing as the tier-1 ten.
	var authored := _authored()
	assert_eq(authored.size(), ALL_IDS.size(), "every authored def (ADR 0110/0919)")
	for key in authored.keys():
		var def := authored[key] as StatusDef
		assert_ne(def.mitigation_tags.size(), 0, "%s publishes mitigation_tags" % key)
		for lever in def.mitigation_tags:
			assert_eq(
				StatusDef.LEVERS.has(lever),
				true,
				"%s names a known lever (%s)" % [key, String(lever)]
			)
		# Affinity alone denies a player with the wrong spirit root any answer, the rule
		# `domain_map_contract.gd` already enforces for a hazard zone.
		assert_eq(def.mitigation_tags == [&"affinity"], false, "%s is not affinity only" % key)


func test_each_element_ships_two_statuses_with_different_mechanics() -> void:
	# ADR 0090 refuses a catalogue that is "twenty damage numbers". Asserted per ELEMENT
	# and in three parts, because a shared mechanic name alone would still let two
	# identical shapes through: the pair must name two different mechanics, must not be the
	# same (channel, kind) pair, and — for tier-2 — must be exactly one damage channel
	# beside one control/modifier/amplifier.
	var per_element := _per_element(_authored())
	for element in _all_elements():
		var pair: Array = _pair_without_blessings(per_element.get(element, []))
		assert_eq(pair.size(), 2, "%s ships its two pair defs" % String(element))
		var first := pair[0] as StatusDef
		var second := pair[1] as StatusDef
		assert_ne(first.mechanic(), second.mechanic(), "%s names two mechanics" % String(element))
		assert_ne(
			[first.magnitude_unit, first.kind],
			[second.magnitude_unit, second.kind],
			"%s is not the same channel wearing another kind" % String(element)
		)
	# The stronger rule — one damage channel beside one control/modifier/amplifier — holds
	# for tier-2 ONLY, because tier-1 does not satisfy it: `earth` ships `brace` beside
	# `root`, neither of which spends a pool. ADR 0090's own claim was "ten distinct
	# mechanics" and that is the whole of what tier-1 promised; one-channel-beside-one-
	# control is what ADR 0110 adds for the ten new statuses.
	for element in ElementStats.ADVANCED_ELEMENTS:
		var pair: Array = _pair_without_blessings(per_element.get(element, []))
		var channels := 0
		var units: Array[StringName] = []
		for def in pair as Array:
			if PULSE_UNITS.has((def as StatusDef).magnitude_unit):
				channels += 1
			units.append((def as StatusDef).magnitude_unit)
		assert_eq(channels, 1, "%s is one damage channel beside one control" % String(element))
		units.sort()
		assert_eq(units.size(), 2, "%s resolves through two channels" % String(element))
		assert_ne(units[0], units[1], "%s does not share one channel" % String(element))


func test_the_closed_mechanic_vocabulary_is_used_whole() -> void:
	# `StatusDef.MECHANICS` is a closed ten-name vocabulary and `status_def.gd` is not this
	# file's to widen. ADR 0090 named all ten through tier-1; ADR 0110 requires every
	# advanced element to REUSE a tier-1 mechanic rather than invent a shape the runtime
	# does not resolve. So the claim is a fixed point rather than a count: the vocabulary
	# is used whole, tier-1 keeps ADR 0090's own per-element pairing exactly, and no
	# advanced element names a mechanic tier-1 has never resolved.
	var authored := _authored()
	var per_element := _per_element(authored)
	var used: Dictionary = {}
	for key in authored.keys():
		used[(authored[key] as StatusDef).mechanic()] = true
	assert_eq(used.size(), StatusDef.MECHANICS.size(), "the whole closed vocabulary is used")
	for mechanic in StatusDef.MECHANICS:
		assert_eq(used.has(mechanic), true, "%s is authored somewhere" % String(mechanic))

	var tier_one_mechanics: Dictionary = {}
	for element in ElementStats.BASE_ELEMENTS:
		assert_eq(
			_mechanics_of(_pair_without_blessings(per_element.get(element, []) as Array)),
			_sorted(TIER_ONE_MECHANICS[element] as Array),
			"%s keeps ADR 0090's two mechanics" % String(element)
		)
		for name in TIER_ONE_MECHANICS[element] as Array:
			tier_one_mechanics[StringName(name)] = true

	for element in ElementStats.ADVANCED_ELEMENTS:
		var names: Array[String] = _mechanics_of(
			_pair_without_blessings(per_element.get(element, []) as Array)
		)
		for name in names:
			assert_eq(
				tier_one_mechanics.has(StringName(name)),
				true,
				"%s reuses a mechanic the runtime already resolves" % String(element)
			)
		names.sort()
		assert_eq(names.size(), 2, "%s names two mechanics of its own" % String(element))
		assert_ne(names[0], names[1], "%s does not reuse one mechanic twice" % String(element))


func test_computed_magnitudes_are_not_per_status_fields() -> void:
	# ADR 0090: computed magnitudes are `CombatTuning` fields, not per-status, so a
	# rebalance is one `.tres` edit and no test re-pins a literal. The def carries a CAP (a
	# designer's to own) and a UNIT (which channel reads the magnitude), and never a
	# magnitude of its own. ADR 0110's ten are held to the same rule: the tier divisor
	# rescales them at the provider, so a pinned number would be a second tax.
	var authored := _authored()
	for key in authored.keys():
		var def := authored[key] as StatusDef
		for field in def.get_property_list():
			var property_name := String(field.get("name", ""))
			assert_eq(
				property_name in ["magnitude", "power", "potency", "damage", "damage_per_tick"],
				false,
				"%s authors no computed magnitude field (%s)" % [key, property_name]
			)
		assert_ne(def.magnitude_unit, &"", "%s names its magnitude unit" % key)


func test_a_status_screen_row_is_primitives_only() -> void:
	# AGENTS.md's testable contract: `summary()` hands a UI plain values, never a Resource,
	# so a panel and a test read the same dict.
	var report := StatusApi.summary()
	# `id` is read as a StringName directly: assigning it to a `String`-typed local first
	# and re-wrapping it is what produced `String(fire_pyre)`, because the constructor only
	# accepts a String or an int, never a StringName.
	var id := StringName(report["ids"][0])
	# `count` is already a plain int in the report; wrapping it is both a redundant cast
	# and an error, because that constructor takes a String or an int, never the int's
	# boxed Variant as handed out of a Dictionary read.
	assert_eq(typeof(report["count"]), TYPE_INT, "count is a plain int")
	assert_eq(report["count"], ALL_IDS.size(), "and it agrees with the catalogue")
	# The row has the same shape for a tier-1 and a tier-2 def — the contract ADR 0110
	# needs, since lifting the gate changed WHICH rows a screen can reach, and a row whose
	# shape depended on the tier would have shipped a screen that broke on `dark_wane`.
	#
	# Three rows, each named by id rather than reached by index: `report["ids"][0]` is
	# whatever StringName order put first (`dark_wane`), so an index would have been an
	# assertion about the loader's sort rather than about the row contract. `id` above is
	# still exercised, as the one row read straight off the report.
	var rows: Array = [
		(StatusApi.definition(&"light_halo") as StatusDef).to_dict(),
		(StatusApi.definition(&"dark_wane") as StatusDef).to_dict(),
		(StatusApi.definition(id) as StatusDef).to_dict(),
	]
	for row in rows:
		var as_dict := row as Dictionary
		for key in as_dict.keys():
			assert_eq(
				typeof(as_dict[key]) == TYPE_OBJECT or typeof(as_dict[key]) == TYPE_NIL,
				false,
				"row key '%s' is not an object" % String(key)
			)
		assert_eq(String(as_dict["mitigation_tags"][0]), "affinity", "levers are Strings")
		assert_eq(typeof(as_dict["duration"]), TYPE_FLOAT, "duration is a float")
	# And the rows describe the defs they came from — a screen that rendered `dark_wane`
	# with `light_halo`'s element would pass every assertion above.
	assert_eq(
		[
			(rows[0] as Dictionary)["id"],
			(rows[1] as Dictionary)["id"],
			(rows[2] as Dictionary)["id"]
		],
		["light_halo", "dark_wane", String(report["ids"][0])],
		"each row names the def it was built from"
	)
	assert_eq(
		[String((rows[0] as Dictionary)["element"]), String((rows[1] as Dictionary)["element"])],
		[String(ElementStats.LIGHT), String(ElementStats.DARK)],
		"and each on its own authored element"
	)


func test_the_catalogue_reaches_through_the_facade_only() -> void:
	# The facade is the module's whole public surface (rules.py:24). A UI or a sibling
	# module that reached `StatusCatalog` or `StatusDef` directly would be a boundary
	# violation `tools arch` cannot see, so the shape is pinned here instead.
	assert_eq(
		_sorted(StatusApi.status_ids()),
		_sorted(ALL_IDS),
		"every authored id is reachable from the facade"
	)
	assert_eq(StatusApi.has_status(&"fire_pyre"), true, "existence check on the facade")
	assert_eq(StatusApi.has_status(&"dark_wane"), true, "for a tier-2 id too (ADR 0110)")
	# And the facade still says NO to the ids nothing authors — these two are NOT the old
	# tier-2 gate. ADR 0090 refused them on their own reasoning, ADR 0110 lifted nothing
	# about them, and the gate's widening is about which ELEMENTS a status may ride rather
	# than about which NAMES may exist. `rejected()` is asserted empty of them as well:
	# nothing was refused, because no file claims them, so a loader that had quietly begun
	# REJECTING unknown ids would be caught rather than credited with a refusal.
	for unpublished in UNPUBLISHED_IDS:
		assert_eq(StatusApi.has_status(unpublished), false, "%s is refused" % String(unpublished))
		assert_eq(
			StatusApi.definition(unpublished), null, "%s resolves to null" % String(unpublished)
		)
		assert_eq(
			_refused_reasons().has(String(unpublished)),
			false,
			"%s was never authored, so nothing had to refuse it" % String(unpublished)
		)


func test_every_authored_status_publishes_and_every_published_status_is_authored() -> void:
	# The two halves of one claim, in OPPOSITE directions. When ADR 0110 lifted the gate
	# this was the assertion that had to invert: the ten tier-2 ids used to be authored and
	# absent from the facade, and a test that only asserted ABSENCE would have passed on a
	# designer who never wrote the file. So each id is checked for presence — and every
	# published id is checked to be one the tree actually holds, so "reachable" cannot be
	# satisfied by an id no `.tres` declares.
	var authored := _authored()
	for status_id in TIER_TWO_IDS:
		assert_eq(authored.has(String(status_id)), true, "%s is authored" % String(status_id))
		assert_eq(StatusApi.has_status(status_id), true, "%s is published" % String(status_id))
		assert_ne(StatusApi.definition(status_id), null, "%s resolves" % String(status_id))
	for status_id in _catalog().status_ids():
		assert_eq(
			authored.has(String(status_id)),
			true,
			"%s is authored AND published" % String(status_id)
		)
	# WHICH ids ride an advanced element, asserted as the pinned set rather than as "the
	# five advanced elements are covered": a tier-1 id quietly re-pointed at `lightning`
	# would steal that element's slot and make this the assertion that names it.
	var on_tier_two: Array[String] = []
	for status_id in _catalog().status_ids():
		var def := StatusApi.definition(status_id)
		if ElementStats.ADVANCED_ELEMENTS.has(def.element):
			on_tier_two.append(String(status_id))
	assert_eq(
		_sorted(on_tier_two),
		_sorted(TIER_TWO_IDS + ADVANCED_BLESSING_IDS),
		"exactly the tier-2 ids are tier-2"
	)
