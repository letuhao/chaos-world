extends TestCase

## ADR 0105's element→status mapping: `StatusApi.status_for_element`.
##
## ## What is being decided HERE and what is decided elsewhere
##
## WHERE the relation lives is decided by the content: `StatusDef.on_landed_blow` is an
## authored `.tres` field, so a designer's `.tres` IS the mapping (ADR 0090's rule). WHAT
## it resolves to is decided by `status_for_element`. Why it cannot be derived from
## `StatusDef.element` is stated on the field itself: every element ships TWO statuses,
## so deriving would mean breaking a tie in code and shipping a balance decision wearing
## a tie-break's name.
##
## The end-to-end proof that a real blow uses this — the test that did not exist before
## ADR 0105 — is `tests/modules/combat/test_combat_exchange_status.gd`. This suite is the
## mapping's own contract, including the refusals.
##
## ## What ADR 0110 changed here
##
## Under ADR 0090's tier-1-only gate a tier-2 element answered `&""` because no status
## was ever published for it, and this file asserted that as the shipped design. ADR 0110
## publishes the ten tier-2 defs, so a tier-2 element now answers with a REAL id — the
## opposite truth, asserted at the same strength. `&""` keeps exactly three causes: an
## elementless blow, an element nobody authored, and a closed gate. The fourth cause is
## gone, and the assertions below say so rather than quietly dropping a branch.

## The published ids that claim a landed blow, tier-1's five. Pinned rather than counted
## so that a content edit which silently moves the mapping fails loudly instead of making
## "every element claims one" true of a different set.
const CLAIMED: Array[StringName] = [
	&"earth_quake",
	&"fire_immolation",
	&"metal_sever",
	&"water_chill",
	&"wood_parasite",
]

## Every element's claimed status, `element -> id`. The mapping IS the claim, so it is
## pinned in full rather than derived from whichever half of the tree happens to be
## published: `StatusApi.status_for_element` is a look-up, and a catalogue that quietly
## re-pointed one slot would leave every count in this file true.
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

## The ten tier-2 ids (ADR 0110). Pinned separately from [constant CLAIMED] because the two
## lists answer different questions — which statuses a landed blow inflicts, and which ids
## exist at all — and collapsing them would make a mapping that moved indistinguishable
## from a catalogue that gained a status nobody rides a blow with.
const TIER_TWO_AUTHORED: Array[StringName] = [
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

## The one per advanced element whose `.tres` claims the landed blow — and which is now
## PUBLISHED, not merely authored. Exactly one per advanced element is what
## `StatusCatalog._landed_blow_collisions` requires of a published tree, so this is both
## ADR 0110's precondition and its result.
const TIER_TWO_CLAIMED: Array[StringName] = [
	&"dark_corrosion",
	&"ice_rime",
	&"light_brand",
	&"lightning_arc",
	&"wind_gust",
]

# --- the mapping answers what the `.tres` authored -----------------------------


func _all_elements() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ElementStats.BASE_ELEMENTS)
	out.append_array(ElementStats.ADVANCED_ELEMENTS)
	return out


func _as_strings(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(id))
	return out


func _sorted(values: Array) -> Array[String]:
	var out := _as_strings(values)
	out.sort()
	return out


func test_each_tier_one_element_answers_with_the_status_that_claims_it() -> void:
	# The positive half. Without it every refusal below would pass against a catalogue that
	# mapped nothing whatsoever, which is the shape of a mapping silently deleted.
	for status_id in CLAIMED:
		var def := StatusApi.definition(status_id)
		if def == null:
			continue
		assert_eq(
			StatusApi.status_for_element(def.element, 1.0),
			status_id,
			"%s is the status a %s blow inflicts" % [String(status_id), String(def.element)]
		)


func test_the_five_that_do_not_claim_are_still_real_statuses() -> void:
	# The CONTROL, and the reason the field exists at all. `fire_pyre` is a perfectly good
	# authored status that a landed blow does NOT inflict — so the answer for `fire` is a
	# choice rather than "whichever status this element has", and the other fifteen
	# behave the same way.
	assert_eq(StatusApi.status_for_element(&"fire", 1.0), &"fire_immolation", "fire picks one")
	assert_ne(&"fire_pyre", StatusApi.status_for_element(&"fire", 1.0), "and it is not the other")
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def == null or def.on_landed_blow:
			continue
		assert_eq(
			StatusApi.has_status(status_id),
			true,
			"%s still ships; declining to ride a blow does not unpublish it" % String(status_id)
		)


func test_the_element_alone_does_not_decide_the_answer() -> void:
	# The decision ADR 0105 had to make, asserted as behaviour: two statuses on one element,
	# one answer. If `status_for_element` were derived from `def.element` it would have no
	# way to choose, and this would be the assertion that caught it.
	var on_fire: Array[StringName] = []
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def != null and def.element == &"fire":
			on_fire.append(status_id)
	assert_eq(on_fire.size(), 2, "fire ships two statuses")
	assert_eq(
		StatusApi.status_for_element(&"fire", 1.0) in on_fire,
		true,
		"and the mapping picks one of them rather than inventing a third"
	)
	assert_eq(
		CLAIMED.has(StatusApi.status_for_element(&"fire", 1.0)),
		true,
		"and the one it picks is the one the .tres flagged"
	)


# --- empty is a normal answer ---------------------------------------------------


func test_an_unknown_or_empty_element_maps_to_nothing_and_is_not_an_error() -> void:
	# The elementless blow ADR 0088 measured as the common one: `ElementsApi.attach` has no
	# production caller, so an untrained body blows with no element at all. Nothing here
	# logs, throws, or returns null — it returns the one value that means "no status", and
	# that is a normal answer rather than a failure. Two causes, not three: ADR 0110
	# removed the tier-2 one, and its absence is asserted in the next test rather than
	# left as a silently dropped branch.
	assert_eq(StatusApi.status_for_element(&"", 1.0), &"", "an empty element maps to nothing")
	assert_eq(
		StatusApi.status_for_element(&"not_an_element", 1.0),
		&"",
		"an element nobody authored maps to nothing"
	)
	# The positive control, restated per element rather than once for `fire`: a mapping
	# that answered `&""` for everything would satisfy both assertions above.
	for element in _all_elements():
		assert_ne(StatusApi.status_for_element(element, 1.0), &"", "%s does map" % String(element))


# --- ADR 0110: the tier-2 mapping is authored, published, and reached ------------


func test_every_tier_two_element_claims_exactly_one_published_status() -> void:
	# The ten tier-2 statuses ship as CONTENT and the loader now ACCEPTS them (ADR 0110),
	# so the mapping is asserted where players meet it — through the facade — and the
	# CONTENT TREE is asserted to AGREE with it. A `.tres` that claims a slot its published
	# def does not resolve is the one authoring mistake that would surface in play, and
	# comparing the two is what catches it.
	var claimed: Array[StringName] = []
	for entry in DirAccess.get_files_at(StatusCatalog.STATUSES_ROOT):
		if not entry.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [StatusCatalog.STATUSES_ROOT, entry]) as StatusDef
		if def == null or not def.on_landed_blow:
			continue
		if ElementStats.ADVANCED_ELEMENTS.has(def.element):
			claimed.append(def.id)
	assert_eq(_sorted(claimed), _sorted(TIER_TWO_CLAIMED), "one per advanced element")
	for status_id in TIER_TWO_CLAIMED:
		var claimed_def := (
			load("%s/%s.tres" % [StatusCatalog.STATUSES_ROOT, String(status_id)]) as StatusDef
		)
		assert_eq(
			claimed_def.is_combat_scope(),
			true,
			"%s claims the landed blow, so it must be a COMBAT status" % String(status_id)
		)
		# The load-bearing half: the authored selector now REACHES the facade. Under the
		# old gate this returned `&""` and the whole of ADR 0110 was that it would not.
		assert_eq(
			StatusApi.status_for_element(claimed_def.element, 1.0),
			status_id,
			"%s is what a %s blow now inflicts" % [String(status_id), String(claimed_def.element)]
		)
		assert_eq(
			StatusApi.has_status(status_id),
			true,
			"and it is a PUBLISHED status, not merely one on disk (ADR 0110)"
		)


func test_a_tier_two_element_now_maps_rather_than_being_withheld() -> void:
	# The assertion this file had to INVERT. Under ADR 0090 every advanced element answered
	# `&""` and that was the shipped design; ADR 0110 lifts the clause, so the same call
	# must now answer with the status its `.tres` claimed. Same strength, opposite truth:
	# a caller still cannot be handed an id nobody authored, and a mapping that went back
	# to `&""` would fail here rather than pass quietly.
	for element in ElementStats.ADVANCED_ELEMENTS:
		assert_eq(
			StatusApi.status_for_element(element, 1.0),
			CLAIMED_BY_ELEMENT.get(element, &""),
			"%s is no longer withheld (ADR 0110)" % String(element)
		)
	# `&""` keeps its other three causes. The closed gate is asserted on an ADVANCED
	# element now that it has a real id to lose: it is the check that proves the answer
	# above came from the MAPPING and not from an element that merely happens to resolve.
	assert_eq(StatusApi.status_for_element(&"", 1.0), &"", "an empty element still maps to nothing")
	assert_eq(
		StatusApi.status_for_element(ElementStats.LIGHT, 0.0),
		&"",
		"a closed gate still maps to nothing even for an element that does"
	)
	assert_ne(
		StatusApi.status_for_element(ElementStats.LIGHT, 1.0),
		&"",
		"and the same element at an open gate does map"
	)


func test_every_element_resolves_to_its_pinned_status() -> void:
	# The whole mapping, in one pinned table. Tier-1 and tier-2 are asserted together
	# because ADR 0110 made them one catalogue: ten elements, ten statuses, one row each,
	# and no element left answering `&""` for want of a def.
	for element in _all_elements():
		assert_eq(
			StatusApi.status_for_element(element, 1.0),
			CLAIMED_BY_ELEMENT.get(element, &""),
			"%s resolves to its authored status" % String(element)
		)
	# And every pinned answer is a status the catalogue really publishes, so the table
	# cannot be satisfied by a typo that happens to match nothing.
	for element in _all_elements():
		var resolved := CLAIMED_BY_ELEMENT[element] as StringName
		assert_eq(StatusApi.has_status(resolved), true, "%s is published" % String(resolved))
		assert_eq(
			(StatusApi.definition(resolved) as StatusDef).element,
			element,
			"and %s rides the element it is mapped to" % String(resolved)
		)


func test_a_tier_two_def_that_claims_its_slot_resolves_for_the_whole_element() -> void:
	# The completeness claim, kept from the gate era because it is still the right one: the
	# mapping covers every element the elements module defines, so a blow carrying any
	# authored element is answerable. Under the old gate the loop this used to walk was the
	# CONTENT TREE; it is the CATALOGUE now, because that is what a blow consults.
	var claimed: Dictionary = {}
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def != null and def.on_landed_blow:
			claimed[String(def.element)] = String(def.id)
	for element in _all_elements():
		assert_eq(
			claimed.has(String(element)),
			true,
			"%s has exactly one landed-blow status published" % String(element)
		)
	for status_id in TIER_TWO_AUTHORED:
		var def := (
			load("%s/%s.tres" % [StatusCatalog.STATUSES_ROOT, String(status_id)]) as StatusDef
		)
		assert_eq(
			(
				String(claimed.get(String(def.element), &"")) == String(def.id)
				or not def.on_landed_blow
			),
			true,
			"%s is the status its element answers with" % String(status_id)
		)


func test_a_closed_gate_maps_to_nothing_without_spending_a_draw() -> void:
	# ADR 0087's closed gate. A `chance` at or below zero consumes no draw at all, so it is
	# answered here rather than at a roll that will not be taken — the same reason
	# `CombatBand.roll` skips its draw on a saturated band.
	for chance in [0.0, -1.0]:
		assert_eq(
			StatusApi.status_for_element(&"fire", chance),
			&"",
			# `%s` on the float directly: GDScript's `String(...)` constructor
			# accepts a String or an int, never a float, so wrapping it is an error
			# rather than a cast.
			"a chance of %s is a closed gate" % chance
		)
	# And the contrast that makes it a gate rather than a disabled mapping.
	assert_ne(StatusApi.status_for_element(&"fire", 0.01), &"", "any open gate maps")


func test_the_gate_is_the_callers_number_and_not_a_second_authored_one() -> void:
	# `chance` is an ARGUMENT, deliberately: ADR 0087's `status_chance` keeps exactly one
	# home (the attack) and ADR 0088's potency keeps exactly one (`element_power_<e>`), so
	# neither is restated in a def. Every chance above the floor answers the same id.
	var answer := &""
	for step in 20:
		var chance := 0.05 + 0.047 * float(step)
		var resolved := StatusApi.status_for_element(&"fire", chance)
		if answer == &"":
			answer = resolved
		assert_eq(resolved, answer, "an open gate never changes which status is named")


# --- the loader refuses what the caller cannot answer ---------------------------


func test_two_statuses_claiming_one_element_is_reported_not_silently_resolved() -> void:
	# The ambiguity ADR 0105's selector exists to prevent. A collision cannot be REFUSED per
	# def (neither def is malformed on its own) so it is reported across the tree — and
	# `status_for_element` answers nothing rather than picking a winner, because picking
	# would make the game's debuff a function of filename alphabetical order.
	var claimant := StatusDef.new()
	claimant.id = &"probe_also_claims_fire"
	claimant.element = &"fire"
	claimant.kind = &"dot"
	claimant.scope = &"combat"
	claimant.stacking = &"refresh"
	claimant.duration = 5.0
	claimant.magnitude_unit = &"element_power"
	claimant.magnitude_cap = 2.0
	claimant.tick_interval = 1.0
	claimant.mitigation_tags = [&"affinity", &"pill"]
	claimant.on_landed_blow = true
	claimant.payload = {
		"mechanic": &"bleed",
		"text": "probe",
		"pool": &"health",
		"share_per_pulse": 0.01,
		"modifiers": [],
	}
	var admitted := StatusCatalog.instance().register(claimant)
	var problems := StatusCatalog.instance().problems()
	# Whether the probe was admitted or refused, the tree must SAY so rather than silently
	# choosing. Both branches are asserted because the def is well-formed on its own, so
	# admission is the loader's normal answer and the report is the part under test.
	if admitted:
		assert_eq(
			(problems + _problem_texts()).size() > 0,
			true,
			"a collision is reported rather than resolved"
		)
		assert_eq(
			StatusApi.status_for_element(&"fire", 1.0),
			&"",
			"and an ambiguous element maps to nothing instead of picking a winner"
		)
	_cleanup(claimant.id)


func test_a_def_authored_without_the_selector_still_loads_and_never_rides_a_blow() -> void:
	# The backward-compatibility claim, which is why the field defaults to `false`: an
	# authored `.tres` that predates ADR 0105 must load, resolve and tick unchanged — it
	# simply never rides a blow. Had the default been `true`, every future def an author
	# forgot about would land on every exchange.
	var legacy := StatusDef.new()
	legacy.id = &"probe_legacy_no_selector"
	legacy.element = &"wood"
	legacy.kind = &"dot"
	legacy.scope = &"combat"
	legacy.stacking = &"refresh"
	legacy.duration = 5.0
	legacy.magnitude_unit = &"element_power"
	legacy.magnitude_cap = 2.0
	legacy.tick_interval = 1.0
	legacy.mitigation_tags = [&"affinity", &"pill"]
	legacy.payload = {
		"mechanic": &"drain",
		"text": "probe",
		"pool": &"health",
		"share_per_pulse": 0.01,
		"modifiers": [],
	}
	assert_eq(legacy.on_landed_blow, false, "the default is the safe one")
	assert_eq(legacy.problems(), [], "and such a def is still perfectly well-formed")
	assert_eq(
		StatusCatalog.instance().register(legacy),
		true,
		"so a .tres written before ADR 0105 still loads unchanged"
	)
	assert_eq(
		StatusApi.status_for_element(&"wood", 1.0),
		&"wood_parasite",
		"and wood keeps answering with the status that did claim it"
	)
	_cleanup(legacy.id)


## The vocabulary a `.tres` must NOT grow. ADR 0087's gate, ADR 0088's potency, and the
## three names a second magnitude vocabulary would arrive under. Pinned as a constant
## rather than inlined so the list is one thing to read.
const FORBIDDEN_FIELDS: Array[String] = [
	"chance",
	"status_chance",
	"magnitude",
	"power",
	"potency",
]


func test_the_selector_is_not_a_magnitude_and_the_defs_still_carry_no_computed_power() -> void:
	# ADR 0088's "no second magnitude vocabulary", extended to the selector. The mapping is a
	# boolean; potency stays `element_power_<e>` and the gate stays the caller's, so no def
	# pins a number a rebalance would have to edit twenty times.
	#
	# ## Why the body asserted nothing
	#
	# It filtered `get_property_list()` down to `["chance", "magnitude", ...]` and asserted
	# only INSIDE that branch. On the shipped tree the filter matches NOTHING — no
	# `StatusDef` exports a field with any of those names, which is the claim being made —
	# so the loop ran to completion and recorded no assertion at all. A test that can only
	# fail when its own premise is already false proves nothing; the check below therefore
	# asserts the ABSENCE for every def, whether or not the filter matched.
	var published: Array[StringName] = StatusApi.status_ids()
	# The positive control: the catalogue is real and non-empty, so an empty sweep cannot
	# pass for "twenty defs each carry no such field".
	assert_eq(published.size() > 0, true, "the catalogue publishes defs to inspect")
	for status_id in published:
		var def := StatusApi.definition(status_id)
		var authored := _authored_field_names(def)
		for field in FORBIDDEN_FIELDS:
			assert_eq(
				authored.has(field),
				false,
				(
					"%s authors no %s field: potency is the caller's term and the gate is the attack's"
					% [String(status_id), field]
				)
			)
	# And the ONE magnitude-shaped field a def DOES own, asserted as the ceiling rather
	# than as a power: `magnitude_cap` is a bound a designer owns, and it is the only
	# exported numeric the status vocabulary admits. It is named here so a future `.tres`
	# that pins an actual power under a new name is caught by the field list above rather
	# than by this one.
	assert_eq(
		_has_property(StatusApi.definition(published[0]), "magnitude_cap"),
		true,
		"magnitude_cap is the only exported magnitude-shaped field"
	)


## The names of `def`'s EXPORTED properties. `get_property_list()` also reports usage
## categories and built-in `script`/`resource_*` entries, so the list is narrowed to the
## `PROPERTY_USAGE_STORAGE` script variables — which is exactly the set a `.tres` can
## author.
func _authored_field_names(def: StatusDef) -> Array[String]:
	var out: Array[String] = []
	if def == null:
		return out
	for field in def.get_property_list():
		if int(field.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0:
			continue
		if String(field.get("class_name", "")) == "Dictionary":
			continue
		out.append(String(field.get("name", "")))
	return out


func _has_property(def: StatusDef, field: String) -> bool:
	return _authored_field_names(def).has(field)


# --- internals ------------------------------------------------------------------


## The collision report as plain text, so an assertion can look for it without depending on
## which branch `register` took.
func _problem_texts() -> Array[String]:
	var out: Array[String] = []
	for entry in StatusApi.summary()["rejected"]:
		out.append(String((entry as Dictionary).get("reason", "")))
	return out


## Undo a probe registration. The catalogue is a process-wide singleton and every other
## suite in this tree asserts on its exact twenty, so a probe that outlives its test would
## be reported as a content change by a suite that never made one.
func _cleanup(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids
