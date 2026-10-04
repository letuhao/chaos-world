extends TestCase

## BL-0053's central claim, asserted against the SHIPPED content tree.
##
## `test_quest.gd` proves the module's behaviour with in-code fixtures. This suite
## does the opposite: it reads `res://data/quest/quests/` through the real catalog
## and asserts the authored content is well formed. Between them, a fixture cannot
## quietly become the only thing that works — if shipped content drifts, this file
## goes red.
##
## The load-bearing assertion is `test_the_three_kinds_share_one_shape`: BL-0053
## names authored, systemic and emergent, and the whole design is that they are
## ONE `QuestDef` with a `kind` field rather than three types. If a future author
## adds a fourth kind or a kind-specific field, the loop over the catalog catches
## it here instead of a panel discovering it in play.

## The fields every shipped quest must carry, whatever its kind. Naming them
## explicitly is what makes "one shape" a testable claim rather than a hope: a
## reader that has to handle a kind-specific field would have to branch on `kind`,
## and this list is the thing it would branch over.
const REQUIRED_FIELDS := [
	"id",
	"display_name",
	"description",
	"kind",
	"tier",
	"requirement",
	"steps",
	"grants",
]

const REQUIRED_STEP_FIELDS := ["step_id", "fact", "need", "optional"]
const REQUIRED_GRANT_FIELDS := ["kind", "id", "amount"]

## The ids BL-0053 names, and the gate on one destiny so the ADR 0113 / DEF-0110
## seam is genuinely exercised by shipped content rather than only by a fixture.
const REQUIRED_DESTINY_IDS := [
	"the_one_who_stayed",
	"the_severed",
	"the_chosen_instrument",
	"the_one_who_returned",
	"the_oath_bound",
]
const REQUIRED_RACE_IDS := ["commonborn", "emberblood", "stoneborn", "tidecaller"]


func teardown() -> void:
	DestinyFixtureCatalog.teardown()
	QuestFixtureCatalog.teardown()


func _shipped() -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	var catalog := QuestCatalog.instance()
	for quest_id in catalog.quest_ids():
		var def := catalog.definition(quest_id)
		if def != null:
			out.append(def)
	return out


# --- The three kinds are one shape -----------------------------------------


## BL-0053, made testable. Every shipped quest — whatever its kind — answers the
## same questions with the same fields, so one reader serves all three.
func test_the_three_kinds_share_one_shape() -> void:
	var shipped := _shipped()
	# `assert_eq(.., false)`, NOT `assert_ne(.., false)`: `assert_ne(x, false)`
	# demands x be TRUE, so the original spelling asserted the authored tree was
	# EMPTY and went red on the day the first five quests landed. A test whose
	# failure count is a measure of how good the content is has to say so in the
	# operator, not in the label.
	assert_eq(shipped.is_empty(), false, "the authored quest tree is not empty")

	var seen_kinds: Array[String] = []
	for def in shipped:
		for field in REQUIRED_FIELDS:
			assert_eq(
				def.get(field) != null,
				true,
				"%s (kind %s) carries the '%s' field" % [def.id, def.kind, field]
			)
		assert_eq(
			def.kind_valid(), true, "%s names a kind BL-0053 defines ('%s')" % [def.id, def.kind]
		)
		if not seen_kinds.has(String(def.kind)):
			seen_kinds.append(String(def.kind))
		# One shape means every kind is READ by the same code path. A kind that
		# had no authored quest would leave that path untested by shipped content.
		assert_ne(def.has_steps(), false, "%s (kind %s) has at least one step" % [def.id, def.kind])
		for step in def.steps:
			for field in REQUIRED_STEP_FIELDS:
				assert_eq(
					step.get(field) != null,
					true,
					"%s step %s carries '%s'" % [def.id, step.step_id, field]
				)
			assert_ne(step.fact, &"", "%s step %s names a fact" % [def.id, step.step_id])
		for grant in def.grants:
			for field in REQUIRED_GRANT_FIELDS:
				assert_eq(
					grant.get(field) != null,
					true,
					"%s grant %s carries '%s'" % [def.id, grant.get("id", ""), field]
				)

	# BL-0053 names three kinds and all three must be AUTHORED, or one is a
	# promise the content does not keep.
	for kind in QuestDef.KINDS:
		assert_eq(
			seen_kinds.has(String(kind)),
			true,
			"at least one shipped quest is of kind '%s' (saw %s)" % [kind, seen_kinds]
		)


## Every quest id is unique and non-empty — the catalog keys on the id, so a
## duplicate would silently shadow one quest with another.
func test_every_shipped_quest_has_a_unique_non_empty_id() -> void:
	var ids: Array[String] = []
	for def in _shipped():
		assert_ne(def.id, &"", "a shipped quest has an id")
		assert_eq(ids.has(String(def.id)), false, "quest id '%s' is unique" % def.id)
		ids.append(String(def.id))


# --- Gates are data, and reference real content ---------------------------


## The gate is authored DATA, never code, and it names real content. A gate on a
## destiny that does not exist refuses closed forever, which is the DEF-0110
## "silently unlocks content" failure in reverse: content that can never open.
##
## **The vocabulary is wider than fate and destiny, and this test used to say it
## was not.** `required_gate_ids()` deliberately flattens EVERY `{verb, id}` pair,
## through `all_of`/`any_of`/`none_of`, so a panel can render "what is holding this
## back" without re-deriving the grammar — which means a `counter` gate's id comes
## back here too. A counter is read by `DestinyApi` out of the actor's ledger, not
## out of the catalog, so `FateCatalog` legitimately never carries it, and the
## original assertion failed on `the_tally_of_a_man_who_kept_count` — which gates
## `all_of[has_fate: first_blood_duel, counter: duels_won]`, and `first_blood_duel`
## DECLARES `duels_won` in its own `counters` list.
##
## So the valid set is fates, destinies, and every counter a `FateDef` declares.
## That last group is read from the catalog rather than typed here, because
## `FateDef.counters` exists precisely so the answerable-gate list lives in content
## instead of in a hardcoded id list in code.
func test_every_shipped_gate_names_a_real_fate_destiny_or_declared_counter_id() -> void:
	var real_fates: Dictionary = {}
	for fate_id in FateCatalog.instance().fate_ids():
		real_fates[String(fate_id)] = true
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for counter_id in def.counters:
			real_fates[String(counter_id)] = true
	var real_destinies: Dictionary = {}
	for destiny_id in FateCatalog.instance().destiny_ids():
		real_destinies[String(destiny_id)] = true

	# `required_gate_ids` answers every id a quest's gates NAME, and a `tagged`
	# gate names a TAG, not a fate — so without the vocabulary here the first
	# shipped `tagged` gate read as "no FateDef declares 'duel'" and failed a
	# perfectly correct quest. The vocabulary is `FateDef.TAGS`, the closed list
	# ADR 0189 defines, and this is the runtime half of the check tools/data.py
	# makes at author time.
	var real_tags: Dictionary = {}
	for tag in FateDef.TAGS:
		real_tags[String(tag)] = true

	var gated := 0
	for def in _shipped():
		for gate_id in def.required_gate_ids():
			gated += 1
			assert_eq(
				real_fates.has(gate_id) or real_destinies.has(gate_id) or real_tags.has(gate_id),
				true,
				"%s gates on '%s', which no FateDef or DestinyDef declares" % [def.id, gate_id]
			)
	assert_ne(gated, 0, "at least one shipped quest is gated, so the seam is exercised")


## A `tagged` gate is only meaningful if some fate ACTUALLY carries that tag. A
## vocabulary member no fate wears is a gate nothing can ever open — the ADR 0189
## failure mode — and it is invisible to the id check above, because the tag IS a
## declared id in `FateDef.TAGS`. This is the runtime twin of the Python audit's
## `_tag_findings`.
func test_every_shipped_tag_gate_names_a_tag_some_fate_carries() -> void:
	var carried: Dictionary = {}
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for tag in def.tags:
			carried[String(tag)] = true

	var tagged_gates := 0
	for def in _shipped():
		for gate in _tagged_rows(def.requirement):
			tagged_gates += 1
			var tag_id := String(gate.get("id", ""))
			assert_eq(
				carried.has(tag_id),
				true,
				(
					(
						"%s gates on tag '%s', which no shipped fate carries - a gate that "
						+ "nothing can ever open"
					)
					% [def.id, tag_id]
				)
			)
	assert_ne(
		tagged_gates,
		0,
		"at least one shipped quest uses the `tagged` verb, so ADR 0189 is reachable"
	)


## Every `tagged` row inside a requirement, composites descended.
##
## Bounded by the AUTHORED nesting exactly as `QuestDef._collect_gate_ids` is: a
## composite names its own children, so the depth is what the author wrote and a
## malformed cycle is refused upstream rather than walked here. `out` is passed in
## and appended to, so a caller cannot be surprised by a fresh array each call.
func _tagged_rows(node, out: Array = []) -> Array:
	if not (node is Dictionary):
		return out
	var entry := node as Dictionary
	var verb := StringName(entry.get("verb", ""))
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		var children = entry.get("of", [])
		if not (children is Array):
			return out
		for index in range((children as Array).size()):
			_tagged_rows((children as Array)[index], out)
		return out
	if verb == &"tagged":
		out.append(entry)
	return out


## ADR 0113 / DEF-0110, exercised by shipped content: at least one quest is
## gated on `has_destiny`, which is the seam the deferred entry asked a quest
## system to own.
func test_at_least_one_shipped_quest_is_gated_on_a_destiny() -> void:
	var found := false
	for def in _shipped():
		if String(def.requirement.get("verb", "")) == "has_destiny":
			found = true
			assert_ne(def.requirement.get("id", &""), &"", "the destiny gate names a destiny")
	assert_eq(found, true, "a shipped quest gates on {verb: has_destiny, id: ...}")


# --- Grants ----------------------------------------------------------------


## Every fate/destiny a quest pays is a REAL id in fate's own catalog, and never
## carries a `quest:` prefix (DEF-0107: "never author a fate id as quest:*").
func test_every_shipped_fate_grant_names_a_real_fate_without_the_quest_namespace() -> void:
	var real_fates: Dictionary = {}
	for fate_id in FateCatalog.instance().fate_ids():
		real_fates[String(fate_id)] = true
	var paid := 0
	for def in _shipped():
		for grant in def.grants:
			var kind := StringName(grant.get("kind", ""))
			var id := String(grant.get("id", ""))
			# `assert_eq(.., false)` for the same reason as above: the label says the
			# id must NOT be namespaced, and `assert_ne(id.begins_with("quest:"),
			# false)` demanded the opposite — every correctly-authored fate id failed
			# its own check. DEF-0107's rule is "no `quest:` prefix on a fate id", so
			# `false` is the passing value.
			assert_eq(
				id.begins_with("quest:"),
				false,
				"%s grant '%s' is NOT namespaced as quest:* (DEF-0107)" % [def.id, id]
			)
			if kind == QuestDef.GRANT_FATE:
				paid += 1
				assert_eq(
					real_fates.has(id),
					true,
					"%s pays fate '%s', which the fate catalog defines" % [def.id, id]
				)
			elif kind == QuestDef.GRANT_DESTINY:
				paid += 1
	assert_ne(
		paid, 0, "at least one shipped quest pays a fate or destiny, so DEF-0107 is exercised"
	)


## The grant kind set is closed. `nothing` is NOT a kind, and an unknown kind
## would be refused at pay time (a silent content loss).
func test_every_shipped_grant_kind_is_in_the_closed_set() -> void:
	for def in _shipped():
		for kind in def.grant_kinds():
			assert_eq(
				QuestDef.GRANT_KINDS.has(kind),
				true,
				"%s grant kind '%s' is one of fate/destiny/item" % [def.id, kind]
			)


# --- Content uses the real race/destiny vocabulary -------------------------


## The authored quests reference the real fate/destiny ids the module's gate and
## grants read, so they are not gated on content that does not exist. The race
## vocabulary is asserted separately: a quest step can name a race-shaped fact
## (the short road's Emberbody furnace), and those race ids are the shipped ones.
func test_shipped_quests_reference_the_real_destiny_vocabulary() -> void:
	for destiny_id in REQUIRED_DESTINY_IDS:
		assert_eq(
			FateCatalog.instance().destiny_definition(StringName(destiny_id)) != null,
			true,
			"destiny '%s' exists and can gate or be paid" % destiny_id
		)
	for race_id in REQUIRED_RACE_IDS:
		assert_eq(
			ResourceLoader.exists("res://data/races/%s.tres" % race_id),
			true,
			"race '%s' exists" % race_id
		)
