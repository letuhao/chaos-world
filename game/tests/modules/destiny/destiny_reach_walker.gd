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
const FIXPOINT_PASS_CAP := 64

## The tag `_fixpoint` writes into `held` when it gave up before reaching a
## fixpoint. It is deliberately NOT a `fate:` or `destiny:` tag, so no assertion
## reading `held` can count it as one — its only job is to be visible.
const UNREACHED_TAG := "unreached:fixpoint"


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
	for entry in CharacterCreationFlow.new().candidates():
		var view: Dictionary = entry
		var arrival_id := StringName(view.get("id", ""))
		var node_key := key(arrival_id, true)
		var node = nodes.get(node_key, null)
		if node == null:
			continue
		var source := ARRIVAL_SOURCE
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
## ## What `fact` answers, and why it is not `true`
##
## `fact` and `declare` are NOT gate verbs — `DestinyGate` reads six verbs and
## `fact` is not among them, so `evaluate()` refuses it outright. The previous
## version answered `true`, and a COMPOSITE walked by hand over that answer is what
## produced the ten failures this function is being rewritten for:
## `tournament_of_the_spirit_peaks.tres` triggers on
## `{verb: fact, id: tournament_called}`, and open meant "this event may open", so
## the first arrival walk earned `the_chosen_instrument` through the tournament
## while already holding it. `the_dawn_descent` and `beast_tide_of_the_mortal_plains`
## did the same to `heaven_s_chosen_instrument` and `one_hundredth_slain`. Those are
## **the fates of a sibling arrival** — a hero holding `the_chosen_instrument`
## cannot ever hold them, because its `grants_fates` already paid them — so the
## walk reported content reachable that the engine has handed the player already,
## and then reported the whole branch unreachable from an arrival that earned it.
##
## So a fact is asked of the world's own answer, not assumed. `WorldAmbient.ROSTER`
## is production's published table of the facts the WORLD reaches and reports on
## its own (`storm_front_sighted`, `void_seam_sounded`, `tournament_called`,
## `sect_war_called`), it is read rather than restated so the walk cannot drift from
## it, and one of them being in the roster is what makes the rule openable: the
## world will say it, so a player can be holding it. A fact with no producer here
## and no route out of the fate tree (the nine quest step facts of DEF-0183, and
## `treasure_stone_read` behind `the_stone_that_answering`) is refused, and what it
## pays is reported unreachable — which is a finding about content, not a walker
## that guessed.
##
## ## The three siblings
##
## `counter` is asked of the module, which owns it, with the same `need` semantics
## the engine uses; no shipped destiny gate names one, so the question is empty
## today. `declare` is an event payload (`EventGate._declaration`) and a war that
## has to be declared against another polity is not something this walk can
## honestly assume open.
##
## ## `_verdict` rather than a bool, and why
##
## The old hand-rolled composite collapsed a fact into a plain yes/no, and for
## `none_of` that inverts into a false OPEN. `the_stone_that_answering.tres:33`
## triggers on `{verb: none_of, of: [{verb: fact, id: treasure_stone_read}]}`, and
## "no one has read the stone" read as satisfied-by-default — so the walk paid
## `heaven_s_warning_unread` to every hero, and the suite could not tell the
## difference between a paid-out fate and a wrongly-open gate. `DestinyGate`
## already distinguishes the two: a child that is `malformed` or `unknown_verb`
## POISONS its parent, and only a plain `unmet` child counts as a plain no. So
## this mirrors that three-valued shape rather than a boolean — which is also what
## `the_stone_that_answering` is now correctly reported as: refused, not open.
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
## gate adds. Callers still see the identical three-valued answer — nothing about
## what the walker decides has changed.
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
## at all, and `ok` is what it answered when it could. A requirement this walk
## cannot read — a `fact`, an unknown verb, a malformed composite — is `read: false`,
## which `verdict()` turns back into `null`. An `ok` of `false` on a READABLE
## requirement is a genuine "no": the hero does not hold it.
static func gate_answers(requirement: Dictionary, probe: Actor) -> Dictionary:
	# An UNGATED rule. Empty on purpose, so a quest that pays nothing anyone must
	# earn is openable exactly as `DestinyGate.evaluate` treats an empty map.
	if requirement == null or requirement.is_empty():
		return {"read": true, "ok": true}
	if not (requirement is Dictionary):
		return {"read": false, "ok": false}
	var verb := StringName((requirement as Dictionary).get("verb", ""))
	if verb == &"has_fate" or verb == &"has_destiny" or verb == &"counter":
		# The module's own answer, aliases and all. An unreadable gate arrives here
		# as `{ok: false, reason: "malformed"}`, and is a plain no to a walk that can
		# only act on what the hero holds.
		return {"read": true, "ok": bool(DestinyApi.gate(probe, requirement as Dictionary)["ok"])}
	if verb == &"fact":
		# UNREADABLE, not open and not closed: this is a question about the WORLD,
		# not about the hero, and the world's ledger is not this walk's to read.
		# Every fact route — a quest step, an event stage, a `pay` — is the moment
		# that owns it (ADR 0113), and none of them is a fate.
		return {"read": false, "ok": false}
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		return _composite_answer(requirement as Dictionary, verb, probe)
	# No verb at all, or one the module does not own: refused, as `DestinyGate`
	# refuses it. An unreadable gate is a content bug, and treating it as open would
	# let it silently hand over a destiny.
	return {"read": false, "ok": false}


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
		# Typed, never inferred: `_verdict` answers `true` / `false` / `null` and
		# `:=` on that would be a Variant, which this project treats as an error.
		var child_verdict: Variant = verdict(child, probe)
		# A malformed child poisons the whole composite: refuse-with-cause means a
		# nested gate that cannot be read is never treated as satisfied.
		if child_verdict == null:
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


# --- The fixpoint walk -------------------------------------------------------


## Everything a hero arriving as `origin_id` can ever come to hold.
##
## `hero` is a real `Actor` kept in step with the walk, so the gate can ask the
## module's own answer rather than a copy of it. The arrival is granted through the
## REAL flow, so an arrival the engine would refuse is not silently seeded here.
static func reachable_from(origin_id: StringName) -> Dictionary:
	var hero := probe()
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
	for fate_id in node.grants:
		held["fate:" + String(fate_id)] = true
	return true


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
	return "stopped after %d passes (cap %d)" % [int(held[UNREACHED_TAG]), FIXPOINT_PASS_CAP]


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


## Every shipped fate and destiny id no walk reached AND no fact gate could open —
## the ids that are stranded in CONTENT rather than behind a world fact.
##
## The trigger is each suite's own `KNOWN_UNREACHABLE_FATES` constant, because a
## walk that reaches one means the `.tres` was fixed and this should say so rather
## than keep asserting the gap forever.
static func known_unreachable() -> Array[String]:
	var missing := unreachable(all_arrival_walks(), arrivals(), false)
	var fact_gated := world_gated(missing)
	var out: Array[String] = []
	for id in missing:
		if not fact_gated.has(String(id)):
			out.append(String(id))
	return out


# --- World-fact census -------------------------------------------------------


## Whether the WORLD produces `fact_id` on its own, whatever this hero has earned.
##
## Read from `WorldAmbient.ROSTER` — the one published list of facts that need no
## hero to have earned them, because a period passes and the world reports what it
## saw — and restated nowhere, so this walk cannot drift from it.
##
## The census uses this to SPLIT the ids it could not reach into two kinds: one
## whose only route waits on a fact the world does report, and one waiting on a
## fact nobody writes. It never uses it to OPEN a grant rule — a walk cannot hold a
## fact it never recorded — but it can say which of the two it is looking at, and
## the first kind is content a `.tres` edit settles.
static func _world_says(fact_id: StringName) -> bool:
	if fact_id == &"":
		return false
	return WorldAmbient.ids().has(String(fact_id))


## Which of `missing` has its only route behind a fact the WORLD produces, as
## `fate -> the fact it waits on`.
##
## `heaven_s_warning_unread` is the counter-example the census exists to separate:
## its only rule is `the_stone_that_answering`, whose trigger is
## `none_of(fact treasure_stone_read)`, and no producer anywhere writes that fact.
## A walker that granted it would be inventing a ledger it does not have; one that
## reported it flat would be reporting a fact-supply defect as a fate defect.
static func world_gated(missing: Array) -> Dictionary:
	var out: Dictionary = {}
	var nodes := graph()
	for id in missing as Array:
		var node = nodes.get(key(StringName(String(id)), is_destiny_id(String(id))), null)
		if node == null:
			continue
		for source in (node as ReachNode).sources.keys():
			var facts := _fact_gates((node as ReachNode).sources[source])
			for fact_id in facts:
				if _world_says(StringName(fact_id)):
					out[String(id)] = String(fact_id)
	return out


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


## `fate -> fact` pairs as one line, so a census message can say which route it
## is talking about instead of naming ids twice.
static func world_gated_report(pairs: Dictionary) -> String:
	var parts: Array[String] = []
	for id in sorted_tags(pairs):
		parts.append("%s behind '%s'" % [id, String(pairs[id])])
	return "; ".join(parts)


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
