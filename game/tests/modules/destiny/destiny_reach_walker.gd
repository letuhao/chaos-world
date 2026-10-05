extends RefCounted

## Not a suite: the runner only collects `test_*.gd`, so this helper is named to
## sit outside discovery. It is reached by the sibling `test_destiny_reach_*`
## suites through `preload`, the same shared-fixture idiom `qi_gate_probe.gd`
## established for the qi reachability audits.
##
## ## What lives here, and what does not
##
## This file holds the reachability ENGINE — the authored grant/gate graph, the
## `_fixpoint` walk, and every helper both assertions suites need. It holds NO
## assertions and no `test_*` function: those live in the sibling suites, one per
## concern. The split is by seam, so each suite can state its own rule, and this
## file is the single answer to "how does the walker decide?" that neither suite
## can drift from. Two copies of a reachability walk would be two answers to the
## same question and one of them would drift; the same is true one layer up, of
## the engine and its callers.
##
## ## The discipline this file exists to preserve
##
## Every earn goes through the REAL `DestinyApi` / `CharacterCreationFlow` facade,
## never a simulation: a walk records only what the engine actually granted, and
## an unknown or malformed gate refuses closed. `DestinyApi.gate` is asked for
## anything it owns rather than re-implemented here. See the module docstring on
## `test_destiny_reachability_content.gd`'s former header (now on
## `test_destiny_reach_from_arrivals.gd`) for why that matters.
##
## Every function here is `static` because the suites hold no state between tests
## — a fresh `Actor` probe per walk — and a static helper cannot leak one walk's
## ledger into the next. The single piece of state a walk carries is its `held`
## set, which is a local in `_fixpoint` and is returned to the caller, never
## stored on the helper.

## The exclusivity group whose members close each other. Read from the catalog so
## the arrival suites cover a fourth arrival without editing themselves.
const ORIGIN_GROUP := &"origin"

## The composition root that earns an arrival. It is the ONLY `earn_destiny` call
## site outside quest and event, so a walk ignoring it would report the three
## arrivals unreachable when the player is handed one at creation.
const ARRIVAL_SOURCE := "arrival"

## How many passes the fixpoint is allowed before it stops and says so.
##
## The loop only ever GROWS `held` — every pass that adds nothing ends it — so it
## cannot spin. The cap is not what makes it terminate; it is the assertion that
## it did not need to. `nodes.size() + 1` passes is the deepest growth the shipped
## graph can ask for: a chain of one node behind the last is `_fixpoint`'s own
## deep case (`the_severed` → `the_severed_calling` → `bound_name_called_once`),
## and one more pass has to come back empty or `changed` is still true and the
## walk is not at a fixpoint at all — which is the answer, and the only one that
## must never be swallowed by another pass. Naming it means a walk that grew
## without end reports "did not reach a fixpoint" rather than quietly hanging.
##
## **This constant is 64 and it is KNOWN TO BE TOO TIGHT — do not raise it again
## without reading the note below, and do not "fix" it by deriving it from
## `nodes.size()` either.** Measured 2026-10-04, when ADR 0190's four arrival-mark
## fates took the shipped walk to 65 passes: one over, on a graph that was never
## wrong.
##
## Three fixes were tried and all three were wrong, which is why the number is left
## alone rather than guessed at again:
##
##   1. Deriving it as `nodes.size() + margin`. Raising the margin moved the
##      reported count UP in lockstep — 28, 29, 30, 35 — so the cap was never
##      binding at all and the walk was not terminating on its own condition.
##   2. The loop increments `passes` and only THEN tests, so the guard rejects at
##      `cap + 1`; accounting for that did not help either, for the same reason.
##   3. A second bound on `_tagged_held(held).size() > nodes.size()` — a fact about
##      the data rather than a number — NEVER FIRED on any margin, which says the
##      walk never holds more tagged nodes than the graph has. So it is not looping
##      by re-recording nodes.
##
## That leaves the actual cause unmeasured: something makes `changed` stay true
## without `held` growing. `_earn` returns true and the caller sets `changed = true`
## on any successful grant, and a destination whose `grants_fates` are already held
## can return true every pass without adding a node — which would be the real
## defect, and it is a fix to `_earn`'s bookkeeping rather than to this number.
## Until that is measured, raising the constant only hides it.
const FIXPOINT_PASS_CAP := 64

## The tag `_fixpoint` writes into `held` when it gave up before reaching a
## fixpoint. It is deliberately NOT a `fate:` or `destiny:` tag, so no assertion
## reading `held` can count it as one — its only job is to be visible.
const UNREACHED_TAG := "unreached:fixpoint"

## How many periods of world history this walk assumes have already passed.
##
## MEASURED, not chosen, and it cannot drift:
## `test_the_walk_reads_every_fact_the_authored_content_reads`
## asserts this equals [constant WorldAmbient.ROSTER]'s length, so a roster edit that
## outgrows this number turns the suite red rather than quietly narrowing the walk.
## Four is what that length is today — one ambient fact per period, first due at
## period 1 — and four is the whole point: reachability asks "is there a hero who can
## hold it", not "can it be held in the first turn". A `const` cannot hold
## `WorldAmbient.ROSTER.size()` (not a constant expression in GDScript), which is why
## the number is written down and asserted rather than derived.
const WORLD_PERIODS := 4


## One node of the authored graph: a fate or a destiny the catalog ships.
##
## `grants` are the nodes this one hands over the moment it is earned, and
## `needs_*` are what its own gate demands first. Both are read off the SHIPPED
## `.tres` through the real catalogs, never parsed out of text: a text scan would
## re-implement the catalog's loader and could disagree with what actually ships.
class ReachNode:
	var id: StringName
	## Fate ids handed over when this node is earned. Never a destiny: a destiny
	## grants fates, never the reverse.
	var grants: Array = []
	var needs_fates: Array = []
	var needs_destinies: Array = []
	var is_destiny: bool = false
	var group: StringName = &""
	## `source -> authored requirement`. An EMPTY requirement means ungated, which
	## is the difference between a node a player can reach for free and one that
	## waits on something.
	var sources: Dictionary = {}

	func _init(node_id: StringName, destiny: bool = false) -> void:
		id = node_id
		is_destiny = destiny

	## Whether this node could be added to a hero already holding `have_fates` and
	## `have_destinies`.
	##
	## Exclusivity is asked of the catalog through the module's own group rule
	## rather than re-derived, and the prerequisites are the two exported arrays
	## `DestinyGate.earnable` iterates — so this mirrors the engine's condition
	## exactly, and a second opinion here could not disagree with the real earn.
	func satisfiable(have_fates: Dictionary, have_destinies: Dictionary) -> bool:
		for fate_id in needs_fates:
			if not have_fates.has(fate_id):
				return false
		for destiny_id in needs_destinies:
			if not have_destinies.has(destiny_id):
				return false
		if not is_destiny or group == &"":
			return true
		# **String, not StringName — this is the bug that made 13 assertions fail.**
		# `FateCatalog.destinies_in_group` hands back `Array[StringName]`, so the
		# loop compared a StringName against a dictionary keyed by String and the
		# membership test was ALWAYS false: exclusivity never fired anywhere in
		# this walk. That is not a near-miss, it is the opposite answer — it let a
		# hero hold a whole group at once and report members reachable that no real
		# playthrough can produce, and it hid members that ARE reachable. It is
		# also why a from-a-fresh-hero walk appeared to need no arrival: every
		# branch looked open.
		for other in FateCatalog.instance().destinies_in_group(group):
			if String(other) != String(id) and have_destinies.has(String(other)):
				return false
		return true


# --- The authored graph ------------------------------------------------------


## The shipped graph: every fate and destiny, and every rule that hands one over
## or demands one first. Keyed with a `d` prefix on destinies so a fate and a
## destiny sharing an id could not collide in one dictionary.
static func graph() -> Dictionary:
	var nodes: Dictionary = {}
	var catalog := FateCatalog.instance()
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		var node := ReachNode.new(fate_id, false)
		nodes[String(fate_id)] = node
	for destiny_id in catalog.destiny_ids():
		var def := catalog.destiny_definition(destiny_id)
		if def == null:
			continue
		var node := ReachNode.new(destiny_id, true)
		node.group = def.group
		node.needs_fates = strings(def.requires_fates)
		node.needs_destinies = strings(def.requires_destinies)
		# `earn_destiny` appends `grants_fates` in the SAME call, so they are a
		# grant edge on the destiny rather than a separate authored rule.
		for fate_id in def.grants_fates:
			if nodes.has(String(fate_id)):
				node.grants.append(String(fate_id))
		nodes[key(destiny_id, true)] = node
	# A quest pays on completion, which needs only its own gate.
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		_add_grants(nodes, def.grants, "quest:" + String(quest_id), def.requirement)
	# An event pays once at resolution, which needs only its trigger.
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		_add_grants(nodes, def.pay, "event:" + String(event_id), def.trigger)
	# The arrivals. `candidates()` is the flow's own published table, so nothing
	# here duplicates the arrival list — adding a fourth arrival needs no edit
	# here, and deleting one cannot leave a stale entry behind.
	#
	# ## The marks are added BEFORE the loop, once, for two reasons
	#
	# **They are not per-origin.** `SoulArrivalMarks.grant` pays an arrival's marks on the
	# death that mints THAT ARRIVAL, and every origin can reach every arrival over a
	# three-life ladder — so the edge is a property of the world, not of a starting
	# destiny. Adding it inside the loop both misstated the rule and re-walked the whole
	# soul catalog once per origin.
	#
	# **It is above the `continue` below, which is the sharper half.** An origin whose
	# destiny node is missing skips the rest of its body — and a block placed after that
	# `continue` is silently dead for exactly the origins that need it most. The four
	# authored marks were reported stranded by that placement, which is the same false
	# negative as an unproduced fact.
	#
	# The ids are also in a DIFFERENT namespace from `view["id"]`: that one is an ORIGIN
	# DESTINY (`the_chosen_instrument`) while an arrival is `the_walker_back_through_ash`,
	# so `arrival_definition(arrival_id)` answers null for every origin. The two spaces are
	# joined by nothing but `race_id`, so there is no lookup to make — walk the catalog.
	var arrival_source := ARRIVAL_SOURCE
	var soul_catalog := SoulCatalog.instance()
	for known_arrival in soul_catalog.known_arrivals():
		var arrival_def := soul_catalog.arrival_definition(StringName(known_arrival))
		if arrival_def == null:
			continue
		for mark_id in arrival_def.marks:
			var mark_node = nodes.get(String(mark_id), null)
			if mark_node != null and not (mark_node as ReachNode).sources.has(arrival_source):
				(mark_node as ReachNode).sources[arrival_source] = {}
	for entry in CharacterCreationFlow.new().candidates():
		var view: Dictionary = entry
		var arrival_id := StringName(view.get("id", ""))
		var node_key := key(arrival_id, true)
		var node = nodes.get(node_key, null)
		if node == null:
			continue
		var source := arrival_source
		if not (node as ReachNode).sources.has(source):
			(node as ReachNode).sources[source] = {}
		# The fates an arrival brings with it: a destiny naming one of them in its
		# own `requires_fates` can never be earned otherwise (DEF-0109), so
		# creation earns it first, under the same `source`.
		for fate_id in view.get("arrival_fates", []) as Array:
			var fate_node = nodes.get(String(fate_id), null)
			if fate_node != null and not (fate_node as ReachNode).sources.has(source):
				(fate_node as ReachNode).sources[source] = {}
	return nodes


## Record `rows` as grant edges on whichever nodes they name.
static func _add_grants(
	nodes: Dictionary, rows: Array, source: String, requirement: Dictionary
) -> void:
	for row in rows:
		var kind := String(row.get("kind", ""))
		var id := String(row.get("id", ""))
		if kind != "fate" and kind != "destiny":
			continue
		var node = nodes.get(key(StringName(id), kind == "destiny"), null)
		if node == null:
			continue
		if not (node as ReachNode).sources.has(source):
			(node as ReachNode).sources[source] = requirement


## The catalog key for one id.
static func key(id: StringName, is_destiny: bool) -> String:
	return ("d" + String(id)) if is_destiny else String(id)


## Whether `id` names a DESTINY in the shipped catalog.
##
## Needed because `graph` keys destinies behind a `d` prefix to keep a fate and a
## destiny sharing one id from colliding, and a bare id has to be put back on the
## right side of that key.
static func is_destiny_id(id: String) -> bool:
	return FateCatalog.instance().destiny_definition(StringName(id)) != null


static func strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


# --- The three-valued gate verdict -------------------------------------------


## `_open` as the engine would answer it: `true` OPEN, `false` CLOSED,
## `null` UNREADABLE — a verb this module does not own, or a fact it cannot account
## for. The three are kept apart because `none_of` treats them differently, and
## collapsing them is what opened `the_stone_that_answering`.
##
## ## Every verb is asked of the module that OWNS it, and none of them is refused
##
## The previous version refused three of the six authored verbs as "not this walk's
## to answer" — `fact`, `declare` and `tagged` — and that refusal is what produced
## DEF-0279. It reported two REACHABLE fates as permanently unearnable
## (`heaven_s_warning_unread`, `night_off_the_rotation`) and could not see four of
## the eight authored events open at all. The requirement language is EVALUATED by
## two modules and every verb in it already has an owner that answers it:
## `DestinyGate` reads `has_fate`, `has_destiny`, `counter`, `tagged` and the three
## composites, and `EventGate` contributes `fact` and `declare` while DELEGATING
## those four verbatim to `DestinyApi.gate`. So `_answer` asks `EventGate.evaluate`,
## which is production's own flat answer to the whole language — there is no second
## evaluator here and no hand-kept verb set that can drift from that one.
##
## ## Why `fact` is READABLE, and what it reads
##
## A fact is a thing that happened (ADR 0113), and the world answers the question
## through `EventGate._has_fact` → `EventFacts.count_of` → `WorldFact.count`: a real
## read of the real ledger on the real probe. A fact with no recorded value is 0, and
## a fact the world has not yet published is 0 too — so `the_stone_that_answering.tres:20`,
## whose trigger is `none_of([fact treasure_stone_read])`, is OPEN on a fresh hero,
## which is what its own `on_enter` writing that fact one stage later means it was
## authored to be. Answering `true` and answering `unreadable` were both wrong for
## the same reason: neither asked anything. The value that reaches the ledger is the
## walk's only modelling decision, and production's own publisher makes it — see
## [method seed_world_facts].
##
## `declare` is the same argument: `EventGate._declaration` passes a declaration that
## names its `other_id` and refuses one that does not, because ADR 0085 makes a war
## with no readable prize the defect. The walk takes that answer rather than its own.
##
## ## `_answer` rather than a bool, and why
##
## A leaf's verdict is `{ok, reason, unmet}`, and the reason is what distinguishes a
## player being told no from a requirement nobody could READ.
## [constant DestinyGate.POISON_REASONS] already draws that line, so `_answer` reads
## it rather than inventing one: a poisoned leaf is UNREADABLE (`read: false`) and
## closes its composite, because `none_of` over an unreadable child would otherwise
## open the gate. The composite recursion is the one thing kept here rather than
## delegated, and only because it needs `null` to stay DISTINCT from `false`.
##
## ## Why the answer is read off a Dictionary rather than returned per branch
##
## The verdict is a three-valued answer (`true` / `false` / `null`), and the shape
## that keeps it honest is to build it ONCE in `verdict()` as
## `{ok: bool?, read: bool}` and let the `return`s be the two leaves a real
## dispatcher has. `gate_answers()` is that dispatcher: it routes a requirement to
## exactly the answer that verb deserves and RETURNS once. `verdict()` reads that
## one answer off the dictionary and no longer decides anything itself, so the
## number of return statements is no longer a function of how many verbs a future
## gate adds.
static func verdict(requirement: Dictionary, probe: Actor) -> Variant:
	var answer: Dictionary = gate_answers(requirement, probe)
	# `read: false` is the UNREADABLE verdict and must be handed back as `null`,
	# not coerced: `none_of` distinguishes "closed" from "cannot be read", and so
	# must the walk.
	if not bool(answer.get("read", true)):
		return null
	return bool(answer.get("ok", false))


## The three-valued answer to ONE authored requirement, as a dictionary so the
## recursion below has a single return path.
##
## The shape is `{read: bool, ok: bool}`: `read` is whether the engine could answer
## at all, and `ok` is what it answered when it could. An `ok` of `false` on a
## READABLE requirement is a genuine "no": the hero does not hold it, or the world
## has not said it yet.
##
## **A leaf's answer is production's, never this file's.** `_answer` hands the whole
## requirement to `EventGate.evaluate` — the flat evaluator over the whole authored
## language, which owns `fact` and `declare` and DELEGATES `has_fate`,
## `has_destiny`, `counter` and `tagged` to `DestinyApi.gate`. Reading one
## evaluator means a `tagged` gate no fate carries refuses `unknown_tag` (ADR 0196)
## rather than reading as an ordinary "no", so the walk can never mistake a content
## bug for a hero who has not earned the thing yet.
static func gate_answers(requirement: Dictionary, probe: Actor) -> Dictionary:
	# An UNGATED rule. Empty on purpose, so a quest that pays nothing anyone must
	# earn is openable exactly as `DestinyGate.evaluate` treats an empty map.
	if requirement == null or requirement.is_empty():
		return {"read": true, "ok": true}
	if not (requirement is Dictionary):
		return {"read": false, "ok": false}
	# `none_of` is the ONE composite this walk cannot delegate: `EventGate._composite`
	# is not reachable without its leaves, and collapsing an unreadable child to a
	# plain false INVERTS a `none_of` into an open gate. So composites are walked
	# here, over leaves production answers.
	var entry := requirement as Dictionary
	var verb := StringName(entry.get("verb", ""))
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		return _composite_answer(entry, verb, probe)
	# ## The exception, and it is DERIVED rather than kept by hand
	#
	# A fact this walk carries no row for is a fact it declines to answer for, and
	# [method abstain_on] names that set: every `fact` id the authored content reads,
	# minus the ambient roster [method seed_world_facts] puts on the ledger. The list
	# is computed from the shipped tree on every call rather than written down,
	# because a written-down list of fates is what certified two reachable ones as
	# dead (DEF-0279) — and because a fact, unlike a fate, can be reachable through
	# a rule whose own `on_enter` is the producer, which no id list can express.
	#
	# `abstain_on()` is reached once per leaf verdict, so it is read on the way IN
	# through the composite (a `none_of` needs to know a child is unreadable before
	# it can refuse) and once per leaf OUT of it.
	if verb == EventFacts.VERB_FACT and not _answers_facts(probe, entry):
		return {"read": false, "ok": false}
	var read := EventGate.evaluate(probe, entry)
	if DestinyGate.POISON_REASONS.has(String(read.get("reason", ""))):
		return {"read": false, "ok": false}
	return {"read": true, "ok": bool(read.get("ok", false))}


## Whether this walk can answer for the fact `entry` names.
##
## The ledger is the answer whenever the world has published one — the ambient
## roster [method seed_world_facts] wrote, or a row any earlier `record` left — so a
## recorded fact is read off the real ledger and nothing else is consulted. A fact
## with no row is 0, and 0 is an answer ONLY for a rule that requires it to be
## ABSENT: `none_of(fact treasure_stone_read)` is open on a hero who has never read
## the stone, which is the gate `the_stone_that_answering` was authored around.
static func _answers_facts(probe: Actor, entry: Dictionary) -> bool:
	var fact_id := StringName((entry as Dictionary).get("id", ""))
	if fact_id == &"":
		return true
	if WorldFact.count(probe, fact_id) > 0:
		return true
	return not abstain_on().has(fact_id)


static func _composite_answer(
	requirement: Dictionary, verb: StringName, probe: Actor
) -> Dictionary:
	var children = requirement.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return {"read": true, "ok": false}
	var any_passed := false
	var all_passed := true
	var readable := true
	for child in children as Array:
		# Typed, never inferred: `verdict` answers `true` / `false` / `null` and `:=`
		# on that would be a Variant, which this project treats as an error.
		var child_verdict: Variant = verdict(child, probe)
		# A malformed child poisons the whole composite: refuse-with-cause means a
		# nested gate that cannot be read is never treated as satisfied.
		if child_verdict == null:
			# ## A fact with no ledger row is a genuine NO, not an unreadable rule
			#
			# `EventGate._has_fact` compares a COUNT against a `need`, and
			# `WorldFact.count` answers 0 for a row nobody wrote — so the engine counts
			# such a child as plain `unmet` and carries on, and so does this. That is
			# the whole difference between `none_of` opening and refusing: treating the
			# 0 as unreadable made `the_stone_that_answering`'s trigger poison itself,
			# which is how a fate with a working route was reported as dead (DEF-0279).
			# Only `malformed`, `unknown_verb` and `unknown_tag` poison a composite, and
			# [method _fact_no_ledger_row] is the discriminator that keeps a plain 0 out
			# of that set.
			if _fact_no_ledger_row(child, probe):
				all_passed = false
				continue
			readable = false
			break
		if child_verdict:
			any_passed = true
		else:
			all_passed = false
	if not readable:
		return {"read": false, "ok": false}
	var ok := any_passed
	if verb == &"all_of":
		ok = all_passed
	elif verb == &"none_of":
		ok = not any_passed
	return {"read": true, "ok": ok}


## Whether `requirement` is a `fact` leaf the hero's ledger carries NO row for. The
## one unreadable child that still means something specific: its count is 0, so a
## `none_of` over it is satisfied and an `any_of` over it is not — which is exactly
## what `EventGate._composite` decides for itself when it sees a plain `unmet`.
static func _fact_no_ledger_row(requirement, probe: Actor) -> bool:
	if not (requirement is Dictionary):
		return false
	var entry := requirement as Dictionary
	if StringName(entry.get("verb", "")) != EventFacts.VERB_FACT:
		return false
	var fact_id := StringName(entry.get("id", ""))
	return fact_id != &"" and WorldFact.count(probe, fact_id) == 0


# --- The fixpoint walk -------------------------------------------------------


## Everything a hero arriving as `origin_id` can ever come to hold.
##
## `hero` is a real `Actor` kept in step with the walk, so the gate can ask the
## module's own answer rather than a copy of it. The arrival is granted through the
## REAL flow, so an arrival the engine would refuse is not silently seeded here.
static func reachable_from(origin_id: StringName) -> Dictionary:
	var hero := probe()
	seed_world_facts(hero, WORLD_PERIODS)
	var held: Dictionary = {}
	var outcome := CharacterCreationFlow.new().grant_origin(hero, origin_id)
	if bool(outcome.get("ok", false)):
		held["destiny:" + String(origin_id)] = true
		# Whatever creation brought with the arrival, read back off the hero
		# rather than restated: `ARRIVAL_FATES` is code the walk must not mirror.
		for fate_id in DestinyApi.fates(hero):
			held["fate:" + String(fate_id)] = true
	return _fixpoint(hero, held)


## The same fixpoint from a hero holding NOTHING but what this call grants it —
## used to show a destiny is reachable WITHOUT a sibling of its group, which an
## arrival walk cannot show, because an arrival is handed rather than gated.
##
## ## `seed_destinies` is now the whole hero
##
## It used to be *supplementary*: the caller passed `[destiny_id]` and relied on
## `tournament_of_the_spirit_peaks.tres` paying `the_chosen_instrument` to bring
## it in through the fixpoint. That was this assertion asking about a dependency —
## the one it exists to catch. It answers on its own terms now, so the hero is
## handed the member and then left alone: whatever the fixpoint adds from there on
## is content doing it, not the seed.
##
## ## The seed is recorded only where the engine actually granted it
##
## `DestinyApi.earn_destiny` REFUSES a destiny whose `requires_*` are unmet
## (`DestinyGate.earnable`), so a seed naming an unearned prerequisite would be a
## silent no-op: the previous version appended the ids it WISHED for, which is
## the one thing this walk must never do — it is how a walk reports content
## reachable on a hero the real earn path refused.
##
## That is exactly what the caller seeded. `the_chosen_instrument` requires
## `reborn_in_a_lesser_vessel`, which creation supplies through `ARRIVAL_FATES`,
## so seeding `[the_chosen_instrument]` alone earned nothing, recorded it anyway,
## and the fixpoint below found no way back to it — the arrival being handed to a
## player at creation was reported as something content has to unlock. The seed is
## taken here and recorded here instead: this hero's own ledger after each earn,
## read back off the facade.
##
## `seed_fates` survives only for a `requires_fates` this hero has not been given
## another way. Nothing in the shipped tree is gated on a fate at all — every
## gate reads `has_destiny`, `fact` or `declare` — so on the shipped content it
## is empty, and the exclusivity rule is about destinations closing each
## other. It is kept because the rule is about prerequisites in general and a
## future `requires_fates` should not silently have no seed: an UNMET one still
## refuses, so it can only ever under-report, never invent a path.
static func reachable_bare(
	seed_fates: Array, seed_destinies: Array, arrival_fates: Array = []
) -> Dictionary:
	var hero := probe()
	seed_world_facts(hero, WORLD_PERIODS)
	var held: Dictionary = {}
	for fate_id in seed_fates:
		DestinyApi.earn_fate(hero, StringName(fate_id), "reachability")
		if DestinyApi.has_fate(hero, StringName(fate_id)):
			held["fate:" + String(fate_id)] = true
	# The arrival's own prerequisites, granted before it and only when it is the
	# arrival that brings them — a seed for any other destiny is handed nothing.
	for fate_id in arrival_fates:
		DestinyApi.earn_fate(hero, StringName(fate_id), "reachability")
		if DestinyApi.has_fate(hero, StringName(fate_id)):
			held["fate:" + String(fate_id)] = true
	for destiny_id in seed_destinies:
		DestinyApi.earn_destiny(hero, StringName(destiny_id), "reachability")
		if DestinyApi.has_destiny(hero, StringName(destiny_id)):
			held["destiny:" + String(destiny_id)] = true
	return _fixpoint(hero, held)


## THE FIXPOINT. Repeatedly take whichever authored rule is satisfiable right now
## and add what it yields, until a whole pass adds nothing.
##
## One implementation for both walks, because two copies of a reachability walk
## are two answers to the same question and one of them will drift. Each pass
## only ever grows `held`, so this terminates; the set it stops at is exactly what
## a player could accumulate by playing the authored content, which is the only
## honest definition of reachable for content nobody chooses.
static func _fixpoint(probe: Actor, held: Dictionary) -> Dictionary:
	var nodes := graph()
	var changed := true
	var passes := 0
	while changed:
		changed = false
		passes += 1
		# Bounded, and the bound names the failure rather than hanging on it: past
		# this many passes `held` is still growing, so the walk is chasing a cycle
		# the earn path will keep feeding it.
		if passes > FIXPOINT_PASS_CAP:
			held[UNREACHED_TAG] = passes
			return held
		for node_key in nodes.keys():
			if held.has(tag(node_key)):
				continue
			var node = nodes[node_key]
			# A node nothing grants is an ORPHAN — DEF-0181's own defect. Treating
			# it as available would let the walk agree with itself. `verdict`, not
			# `open`: a rule whose verdict is UNREADABLE is closed here, and `none_of`
			# has to know that from the inside to refuse rather than open.
			var offered := false
			for source in (node as ReachNode).sources.keys():
				if verdict((node as ReachNode).sources[source], probe) == true:
					offered = true
					break
			if not offered:
				continue
			if not node.satisfiable(_half(held, false), _half(held, true)):
				continue
			if not _earn(probe, node as ReachNode, held):
				continue
			changed = true
	return held


## Earn `node` on `probe` through the module's own facade, and record it in
## `held` only if the engine actually granted it.
##
## Refusing to record on a refusal is the whole point: a walk that recorded what
## it WANTED would pass on a hero the real earn path refused. That divergence is
## the unsatisfiable-cycle shape, so it has to be visible rather than absorbed.
static func _earn(probe: Actor, node: ReachNode, held: Dictionary) -> bool:
	if node.is_destiny:
		DestinyApi.earn_destiny(probe, node.id, "reachability")
		if not DestinyApi.has_destiny(probe, node.id):
			return false
		held["destiny:" + String(node.id)] = true
	else:
		DestinyApi.earn_fate(probe, node.id, "reachability")
		if not DestinyApi.has_fate(probe, node.id):
			return false
		held["fate:" + String(node.id)] = true
	# A destiny carries its `grants_fates` with it in the same call, so they
	# arrive here rather than needing another pass.
	#
	# **Only the ones this call ACTUALLY ADDED, and the return says so.** The grants
	# loop used to assign every id unconditionally and return true, which is what kept
	# `_fixpoint` spinning: re-assigning a key that is already present is not an error
	# and does not grow `held`, yet the caller set `changed = true` on the strength of the
	# return, so no pass ever came back empty and the walk ran to `FIXPOINT_PASS_CAP` and
	# reported "did not reach a fixpoint" — a CONTENT verdict produced by a bookkeeping
	# bug. ADR 0190's four arrival-mark fates added enough duplicate-assignment nodes to
	# push the shipped graph from 64 passes to 65 and turn that lie red.
	#
	# The fix is to measure growth rather than assume it: the node's own tag was just
	# written, so anything the grants loop adds is growth the loop caused. A destination
	# whose grants are all held earns nothing new and now correctly returns false.
	var grew := false
	for fate_id in node.grants:
		var granted_tag := "fate:" + String(fate_id)
		if held.has(granted_tag):
			continue
		held[granted_tag] = true
		grew = true
	return grew


## The `kind:id` tag a node key carries, so `held` can say what kind it holds.
static func tag(key: String) -> String:
	if key.begins_with("d"):
		return "destiny:" + key.substr(1)
	return "fate:" + key


## The fates, or the destinies, `held` currently carries — the two ledgers
## `Node.satisfiable` reads.
static func _half(held: Dictionary, want_destiny: bool) -> Dictionary:
	var prefix := "destiny:" if want_destiny else "fate:"
	var out: Dictionary = {}
	for held_tag in held.keys():
		if String(held_tag).begins_with(prefix):
			out[String(held_tag).substr(prefix.length())] = true
	return out


## A throwaway hero with the destiny ledger attached and nothing earned.
##
## Public because a suite may need the cheapest possible hero to ask a single
## engine question directly (the exclusivity-closure case seeds through the REAL
## flow onto exactly this), while the walks themselves never expose it.
static func probe() -> Actor:
	var actor := Actor.new(&"reachability_probe", {Stat.PHYSIQUE: 1.0, Stat.SPIRIT: 1.0})
	DestinyApi.attach(actor)
	return actor


# --- Reporting and census helpers --------------------------------------------


## Why a walk stopped early, or `""` when it reached a fixpoint. `_fixpoint`
## records the pass count under `UNREACHED_TAG`, so a truncated walk is
## reported as its own failure instead of as a list of ids it never got round to.
static func unreached_reason(held: Dictionary) -> String:
	if not held.has(UNREACHED_TAG):
		return ""
	return (
		"stopped after %d passes (cap %d)"
		% [
			int(held[UNREACHED_TAG]),
			FIXPOINT_PASS_CAP,
		]
	)


## `held`'s tags, sorted, for a failure message that has to be readable.
static func sorted_tags(held: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for held_tag in held.keys():
		out.append(String(held_tag))
	out.sort()
	return out


## Every arrival the composition root ships, canonically ordered. Asked of the
## flow's own group so a fourth arrival is covered without editing a suite.
static func arrivals() -> Array:
	var out: Array = []
	for destiny_id in FateCatalog.instance().destinies_in_group(ORIGIN_GROUP):
		out.append(destiny_id)
	return out


## Every arrival's walk, once. The census and the union test each need them, and
## two walks of the same graph are two answers to the same question.
static func all_arrival_walks() -> Dictionary:
	var out: Dictionary = {}
	for origin_id in arrivals():
		out[origin_id] = reachable_from(origin_id)
	return out


## The fates and destinies the shipped catalog defines, as id strings.
static func shipped() -> Dictionary:
	var fates: Array[String] = []
	for fate_id in FateCatalog.instance().fate_ids():
		fates.append(String(fate_id))
	var destinies: Array[String] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		destinies.append(String(destiny_id))
	return {"fates": fates, "destinies": destinies}


## How many fates plus destinies the shipped catalog defines.
static func shipped_size() -> int:
	var catalog := shipped()
	return (catalog["fates"] as Array).size() + (catalog["destinies"] as Array).size()


## Every shipped fate and destiny id no walk in `walks` reached — either because
## NOTHING reached it, or, when `per_arrival`, because THIS walk did not.
##
## A sibling arrival is excluded by `arrivals`: exclusivity closes it for good
## (ADR 0065), so its absence from a walk seeded with another arrival is the
## design and not a defect.
static func unreachable(walks: Dictionary, arrivals: Array, per_arrival: bool) -> Array[String]:
	var held: Dictionary = {}
	for walk_key in walks.keys():
		if per_arrival:
			held = walks[walk_key]
		else:
			for held_tag in (walks[walk_key] as Dictionary).keys():
				held[String(held_tag)] = true
	var out: Array[String] = []
	var catalog := shipped()
	for fate_id in catalog["fates"]:
		if not held.has("fate:" + String(fate_id)):
			out.append(String(fate_id))
	for destiny_id in catalog["destinies"]:
		if arrivals.has(destiny_id) and per_arrival:
			# Not a defect: a sibling arrival is closed for good by this one.
			continue
		if not held.has("destiny:" + String(destiny_id)):
			out.append(String(destiny_id))
	return out


## Every shipped fate and destiny id the union of the arrival walks does not reach.
##
## The claim this asserts is "some arrival can earn everything", so the walker's own
## answer is the answer: an id it reaches is reachable and an id it does not is
## stranded, with no exemption list standing between the two. See ADR 0198.
static func stranded_ids() -> Array[String]:
	return unreachable(all_arrival_walks(), arrivals(), false)


# --- World facts -------------------------------------------------------------


## Every ambient fact this walk pretends the world has published, in roster order.
##
## Read from [constant WorldAmbient.ROSTER] and truncated to [constant
## WORLD_PERIODS] entries — never restated, so a roster edit shows up here without a
## second list to keep in step. Four ids on the shipped tree:
## `storm_front_sighted`, `void_seam_sounded`, `tournament_called`,
## `sect_war_called`.
static func ambient_facts() -> Array[StringName]:
	var out: Array[StringName] = []
	for index in range(mini(WORLD_PERIODS, WorldAmbient.ROSTER.size())):
		out.append(StringName((WorldAmbient.ROSTER[index] as Dictionary).get("fact", &"")))
	return out


## Every fact a reachable grant rule NAMES, as `fact_id -> the sources naming it`,
## over every quest requirement, every event trigger and every quest STEP the graph
## reads.
##
## This is the MEASUREMENT that replaced the hand-maintained exemption list. A list
## of fate ids cannot say which facts the content tree reads, because that answer is
## a property of the tree at the moment of the walk. See [method abstain_on] for what
## the walk does with the difference.
static func fact_demand() -> Dictionary:
	var out: Dictionary = {}
	var catalog := QuestCatalog.instance()
	for quest_id in catalog.quest_ids():
		var def := catalog.definition(quest_id)
		if def == null:
			continue
		for fact_id in _fact_gates(def.requirement):
			_name_fact(out, fact_id, "quest:%s" % String(quest_id))
		# A quest step names a fact in the same ledger and nothing in `game/src` writes
		# one — the player does, which is why DEF-0183's nine steps are named here and
		# the walker is told they are beyond a pure fate walk. `the_station_you_held`
		# needs `sect_post_held` 1, `oaths_discharged` 3 and `household_heir_registered`
		# 1 before its ungated `pay` fires.
		for step in def.steps as Array:
			var step_id := String((step as QuestStepDef).step_id)
			var fact_id := String((step as QuestStepDef).fact)
			if fact_id != "":
				_name_fact(out, fact_id, "quest:%s/step:%s" % [quest_id, step_id])
	var events := EventCatalog.instance()
	for event_id in events.event_ids():
		var def := events.event_definition(event_id)
		if def != null:
			for fact_id in _fact_gates(def.trigger):
				_name_fact(out, fact_id, "event:%s" % String(event_id))
	return out


## Record `fact_id` as demanded, under `source`. One writer, because a second is how
## the demand map and its report could disagree about who waits on what.
static func _name_fact(out: Dictionary, fact_id: String, source: String) -> void:
	var named: Array = out.get(fact_id, [])
	if not named.has(source):
		named.append(source)
	out[fact_id] = named


## Put this walk's world facts on `probe`, through the ONLY verb that writes the
## ledger ([method WorldFact.record]) and the only publisher that produces them
## ([method WorldAmbient.due]).
##
## Called once per walk, before the fixpoint, so a `fact` gate reads the same ledger
## an event's `on_enter` would read in a real run. No producer is invented: the ids
## come from `WorldAmbient`'s own roster and the amounts from `record`'s own default
## of one occurrence. A hero whose quest steps have written a fact first — the walk
## does not run quest stages — keeps its row, because `due` skips anything
## `WorldFact.count` already answers above zero.
static func seed_world_facts(probe: Actor, periods: int) -> void:
	for fact_id in WorldAmbient.due(probe, periods):
		WorldFact.record(probe, fact_id)


## ## The exception set, and why it is measured rather than guessed
##
## A fact is a COUNT and `WorldFact.count` answers 0 for a row nobody wrote, so a
## `none_of` over a fact the walk cannot reach is still OPEN — the honest answer,
## and what makes `the_stone_that_answering` openable: that event writes
## `treasure_stone_read` from its own `on_enter` one stage after opening. What the
## walk genuinely cannot answer is a rule that ASSERTS a fact is PRESENT, because
## there is no reading of "this happened" that becomes a yes without inventing a
## producer. So the exception set is the facts such a rule names, minus the ambient
## roster [method seed_world_facts] puts on the ledger — computed from the shipped
## tree on every call, never written down.
##
## **It cannot be a list of fate ids.** The question such a list cannot answer is
## "what does this fact belong to", and it has no single answer: `treasure_stone_read`
## is written by `the_stone_that_answering` — the same event whose trigger names it —
## so a `none_of` over it is open on a fresh ledger and shut for ever after, while
## `{fact: storm_front_sighted}` is unmet until a period passes. Both read as 0 to a
## hero who has just arrived, and they are different claims about the game.
static func assertions() -> Dictionary:
	var ambient := ambient_facts()
	var unpublished: Array[StringName] = []
	var demand := fact_demand()
	for fact_id in sorted_tags(demand):
		if _only_absent_names(demand[fact_id] as Array, StringName(fact_id)):
			continue
		if not ambient.has(StringName(fact_id)):
			unpublished.append(StringName(fact_id))
	return {"unpublished": unpublished}


## Whether every source naming `fact_id` reads it only to ask that it is ABSENT, or
## whether nothing in the content names it at all.
##
## The asymmetry is the engine's, not a walker's convenience. `EventGate._composite`
## counts failed children and `none_of` inverts that count, so a failed `fact` child
## makes a `none_of` over it TRUE; a positive `{fact: X}` child inside `all_of` or
## `any_of` is a different question, and one whose answer is an assertion the walk
## would have to invent. A fact nothing reads is not an assertion at all, and lands
## on the same side as the absent ones.
static func _only_absent_names(sources: Array, fact_id: StringName) -> bool:
	for source in sources:
		var entry := String(source)
		if entry.contains("/step:"):
			# A quest STEP is a player action, so the walk does not act. A REQUIRED
			# step is an assertion it cannot make; an `optional` one is not a gate at
			# all (`QuestStepDef.is_satisfied` ignores it), so neither is this file's
			# problem. Read per step rather than per quest for exactly that reason.
			if _step_is_required(entry) and fact_id != &"":
				return false
			continue
		if _reads_fact_presence(_authored_trigger(entry), fact_id):
			return false
	return true


## Whether the authored quest step named in `"quest:<id>/step:<step_id>"` is a
## REQUIRED one. False when the step cannot be read, which keeps a missing definition
## out of the exception set rather than inventing a gate over it.
static func _step_is_required(source: String) -> bool:
	var quest_id := StringName(source.get_slice(":", 0).get_slice(":", 1).get_file())
	var step_id := source.get_file()
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null:
		return false
	for step in def.steps as Array:
		if String((step as QuestStepDef).step_id) == step_id:
			return not (step as QuestStepDef).optional
	return false


## The authored requirement behind `"quest:<id>"` or `"event:<id>"`, or an empty
## dictionary when the source names a definition the catalogs do not hold. Never
## throws: an unresolvable source is content this walk does not model, and an empty
## answer keeps it on the absent side rather than opening a gate.
static func _authored_trigger(source: String) -> Dictionary:
	var kind := source.get_slice(":", 0)
	var id := StringName(source.get_slice(":", 0).get_slice(":", 1).get_file())
	if kind == "quest":
		var def := QuestCatalog.instance().definition(id)
		return {} if def == null else (def.requirement as Dictionary)
	if kind == "event":
		var event_def := EventCatalog.instance().event_definition(id)
		return {} if event_def == null else (event_def.trigger as Dictionary)
	return {}


## Whether `requirement` reads `fact_id` as something that must be SATISFIED, as
## opposed to inside the `of` list of a `none_of` asking for its absence. Bounded by
## the authored nesting of one requirement, which is a few levels deep and is
## snapshotted from the tree rather than grown by the walk.
static func _reads_fact_presence(requirement: Dictionary, fact_id: StringName) -> bool:
	if requirement.is_empty():
		return false
	var verb := StringName(requirement.get("verb", ""))
	if verb == EventFacts.VERB_FACT:
		return StringName(requirement.get("id", "")) == fact_id
	var children = requirement.get("of", [])
	if verb == &"none_of" or not (children is Array):
		return false
	for child in children as Array:
		if child is Dictionary and _reads_fact_presence(child as Dictionary, fact_id):
			return true
	return false


## The facts this walk declines to answer for, from [method assertions].
static func abstain_on() -> Array[StringName]:
	return assertions()["unpublished"] as Array[StringName]


## How many quest steps the authored quests carry. Bounded by the shipped content:
## one per `QuestStepDef` in `game/data/quest/quests`, and it is counted rather than
## written down so a new step cannot desynchronise the number from the tree.
static func quest_step_count() -> int:
	var total := 0
	var catalog := QuestCatalog.instance()
	for quest_id in catalog.quest_ids():
		var def := catalog.definition(quest_id)
		if def != null:
			total += (def.steps as Array).size()
	return total


## Every fact id the authored content names, sorted by its STRING value so a report
## reads the same on every run. Bounded by the shipped content: one entry per `fact`
## leaf in a quest requirement or event trigger, and one per quest step.
static func _fact_demand_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for fact_id in sorted_tags(fact_demand()):
		out.append(StringName(fact_id))
	return out


## `fact_id -> the sources naming it`, as one readable line for a census message.
static func fact_demand_report() -> String:
	var demand := fact_demand()
	var parts: Array[String] = []
	for fact_id in sorted_tags(demand):
		parts.append("%s <- %s" % [fact_id, ", ".join(demand[fact_id] as Array)])
	return "; ".join(parts)


## Every `fact` id named anywhere in a requirement, at any nesting.
static func _fact_gates(node) -> Array[String]:
	var out: Array[String] = []
	_collect_fact_gates(node, out)
	return out


static func _collect_fact_gates(node, out: Array[String]) -> void:
	# Bounded by the authored nesting: this descends the `of` lists of a requirement,
	# never a graph of its own.
	if not (node is Dictionary):
		return
	var entry := node as Dictionary
	if StringName(entry.get("verb", "")) == &"fact":
		var fact_id := String(entry.get("id", ""))
		if fact_id != "" and not out.has(fact_id):
			out.append(fact_id)
		return
	var children = entry.get("of", [])
	if children is Array:
		for child in children as Array:
			_collect_fact_gates(child, out)


# --- Gate-shape helpers ------------------------------------------------------


## The ids a requirement names, split by the kind of node they name.
##
## `QuestDef.required_gate_ids` flattens all six verbs into one id list, which
## loses WHICH verb named what. A quest gated on `has_fate oath_breaker` and
## paying the DESTINY `oath_breaker` would read as a cycle under that list, so
## the verb is honoured here. Small and explicit rather than another flattened
## helper, because the cycle assertions both need the distinction.
static func gates_on(requirement: Dictionary, want_destiny: bool) -> Array:
	var out: Array = []
	_walk_gates(requirement, want_destiny, out)
	return out


static func _walk_gates(node, want_destiny: bool, out: Array) -> void:
	if not (node is Dictionary):
		return
	var entry := node as Dictionary
	var verb := StringName(entry.get("verb", ""))
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		var children = entry.get("of", [])
		if not (children is Array):
			return
		# Bounded by the authored nesting, never an unbounded search.
		for child in children as Array:
			_walk_gates(child, want_destiny, out)
		return
	var wanted := (
		want_destiny if verb == &"has_destiny" else (verb == &"has_fate" and not want_destiny)
	)
	if not wanted:
		return
	var id := String(entry.get("id", ""))
	if id != "" and not out.has(id):
		out.append(id)


## Every source that hands `node` over: its authored `sources` (quest `grants`,
## event `pay`, an arrival) PLUS the `grants_fates` of every shipped destiny, each
## labelled with that destiny so the reason names a file rather than just "yes".
##
## The label is `destiny:<id>` rather than a plain `{}` because an orphan report
## is only actionable if it can say which `.tres` to open; `graph` already models
## the edge separately as `ReachNode.grants` for the fixpoint to consume.
static func grant_route(node: ReachNode) -> Dictionary:
	var out: Dictionary = node.sources.duplicate()
	for destiny_id in FateCatalog.instance().destiny_ids():
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null or not def.grants_fates.has(node.id):
			continue
		var source := "destiny:%s" % destiny_id
		if not out.has(source):
			out[source] = {}
	return out


## Every exclusivity group in the shipped tree, as `group -> [member ids]`.
static func groups() -> Dictionary:
	var out: Dictionary = {}
	for destiny_id in FateCatalog.instance().destiny_ids():
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null or def.group == &"":
			continue
		var members: Array = out.get(def.group, [])
		members.append(destiny_id)
		out[def.group] = members
	return out


## The fates an arrival brings with it, so that `destiny_id` is handable exactly
## the way creation hands it over.
##
## ## Why the member's own seed does not live here
##
## It used to. This function returned `[destiny_id]` alongside these fates, which
## meant the seed was "the member plus whatever the fixpoint could be made to add"
## — and the fixpoint could be made to add it, because `the_station_you_held.tres`
## pays an ungated row and `tournament_of_the_spirit_peaks.tres` pays this very
## destiny. Every seeded member therefore closed the other two arrivals on its
## way in, which is what made the sibling half of the exclusivity assertion report
## a reach that was an artifact of the seed.
##
## ## What is left here, and why it is not `[destiny_id]`
##
## `the_chosen_instrument` names `reborn_in_a_lesser_vessel` in its own
## `requires_fates`, and that fate's only grant routes in the shipped tree are
## the quest `the_short_road` and `ARRIVAL_FATES` in `character_creation_flow.gd`
## — creation hands it over on the player's behalf (DEF-0109). So this is the
## arrival's OWN prerequisite set, taken from the flow's published
## `candidates()[].arrival_fates`, never from the constant: the walk must not
## mirror `ARRIVAL_FATES`, and a constant restated here would drift from it.
## `reachable_bare` earns them through the real facade, so a fate whose
## definition is gone is refused rather than recorded.
##
## ## Why it is not "every other member of the group"
##
## That is what the previous version did, by walking `group[1]` and `group[2]`
## around whichever member it was asked about. It failed BOTH halves of the
## exclusivity assertion, and neither half could ever have passed: every seed it
## chose was a SIBLING of the member, so the member was permanently closed and "is
## reachable from a hero holding nothing" was false for every `origin` destiny,
## including the one a fresh hero is handed.
##
## It is also a stronger claim than the design makes. An arrival is offered to
## the player as one of three choices, so the honest statement is per member, not
## for the group as a whole: **every member of the group is reachable on its
## own.** That is what the exclusivity suite asks, and it is what this seed feeds
## it.
static func granted_by_arrival(destiny_id: StringName) -> Array[String]:
	for entry in CharacterCreationFlow.new().candidates():
		var view: Dictionary = entry
		if StringName(view.get("id", "")) != destiny_id:
			continue
		var out: Array[String] = []
		for fate_id in view.get("arrival_fates", []) as Array:
			out.append(String(fate_id))
		return out
	# Not an arrival: no creation hand-over exists, so nothing is seeded and the
	# walk must reach it from its own authored prerequisites alone. That is the
	# ordinary case and it is what makes the helper safe for a group whose
	# members are earned rather than handed over.
	return []
