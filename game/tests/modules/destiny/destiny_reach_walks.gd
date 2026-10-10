extends RefCounted

## Not a suite: the runner only collects `test_*.gd`, so this helper is named to sit
## outside discovery. It is reached by the sibling `test_destiny_reach_*` suites through
## `preload`, the same idiom `destiny_reach_walker.gd` established beside it.
##
## ## What lives here, and what does not
##
## This file holds the WALK: the two entries a suite calls (`reachable_from`,
## `reachable_bare`), the fixpoint they both run, the earn step it takes through the
## module's own facade, the node-key tag the fixpoint reads, and the walk-level reads a
## suite needs of them (`all_arrival_walks`, `stranded_ids`). The GRAPH and the gate
## answering stay in `destiny_reach_walker.gd`, and this file reaches THAT one without
## being reached by it, so the pair cannot load in a cycle. Split out of the walker for
## size (gdlint's `max-file-lines` is 1000); the moved bodies are verbatim.
##
## ## The discipline this file exists to preserve
##
## Every earn goes through the REAL `DestinyApi` / `CharacterCreationFlow` facade, never
## a simulation: a walk records only what the engine actually granted, and an unknown or
## malformed gate refuses closed. `DestinyApi.gate` is asked for anything it owns rather
## than re-implemented here.
##
## Every function here is `static` because the suites hold no state between tests — a
## fresh `Actor` probe per walk — and a static helper cannot leak one walk's ledger into
## the next. The single piece of state a walk carries is its `held` set, which is a local
## in `_fixpoint` and is returned to the caller, never stored on the helper.

## The walker: the grant/gate graph, the gate answering, the shared constants and the
## catalog reads. One-way on purpose — the walker never names this file, so the two
## cannot form a preload cycle.
const Walker := preload("res://tests/modules/destiny/destiny_reach_walker.gd")


## Everything a hero arriving as `origin_id` can ever come to hold.
##
## `hero` is a real `Actor` kept in step with the walk, so the gate can ask the
## module's own answer rather than a copy of it. The arrival is granted through the
## REAL flow, so an arrival the engine would refuse is not silently seeded here.
static func reachable_from(origin_id: StringName) -> Dictionary:
	var hero := Walker.probe()
	Walker.seed_world_facts(hero, Walker.WORLD_PERIODS)
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
	var hero := Walker.probe()
	Walker.seed_world_facts(hero, Walker.WORLD_PERIODS)
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
	var nodes := Walker.graph()
	var changed := true
	var passes := 0
	while changed:
		changed = false
		passes += 1
		# Bounded, and the bound names the failure rather than hanging on it: past
		# this many passes `held` is still growing, so the walk is chasing a cycle
		# the earn path will keep feeding it.
		if passes > Walker.FIXPOINT_PASS_CAP:
			held[Walker.UNREACHED_TAG] = passes
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
			for source in (node as Walker.ReachNode).sources.keys():
				if Walker.verdict((node as Walker.ReachNode).sources[source], probe) == true:
					offered = true
					break
			if not offered:
				continue
			if not node.satisfiable(_half(held, false), _half(held, true)):
				continue
			if not _earn(probe, node as Walker.ReachNode, held):
				continue
			changed = true
	return held


## Earn `node` on `probe` through the module's own facade, and record it in
## `held` only if the engine actually granted it.
##
## Refusing to record on a refusal is the whole point: a walk that recorded what
## it WANTED would pass on a hero the real earn path refused. That divergence is
## the unsatisfiable-cycle shape, so it has to be visible rather than absorbed.
static func _earn(probe: Actor, node: Walker.ReachNode, held: Dictionary) -> bool:
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


## Every arrival's walk, once. The census and the union test each need them, and
## two walks of the same graph are two answers to the same question.
static func all_arrival_walks() -> Dictionary:
	var out: Dictionary = {}
	for origin_id in Walker.arrivals():
		out[origin_id] = reachable_from(origin_id)
	return out


## Every shipped fate and destiny id the union of the arrival walks does not reach.
##
## The claim this asserts is "some arrival can earn everything", so the walker's own
## answer is the answer: an id it reaches is reachable and an id it does not is
## stranded, with no exemption list standing between the two. See ADR 0198.
static func stranded_ids() -> Array[String]:
	return Walker.unreachable(all_arrival_walks(), Walker.arrivals(), false)
