class_name DestinyProjection
extends RefCounted

## Rebuilds every fate consequence onto an actor from the ledger, and keeps the
## `Actor.traits` mirror in step with it.
##
## **Derived, never stored.** The ledger is the only truth; this class is the
## one place that translates it into stat modifiers and trait ids. That is what
## makes the earn-only invariant safe to ship: a save can be restored, replayed
## or normalized and the projection is simply recomputed, so it can never drift
## from the ledger or double-count.
##
## A second, parallel stat fold is forbidden (ADR 0065). Fate reuses
## `actor.stats.add_modifier` exactly as an authored trait does, because the
## moment a fate gets its own composer, every stat aggregation rule has to be
## taught about it twice.

## The authored fact -> counter pairs. `{"fact": &"<world fact id>", "counter":
## &"<destiny counter id>"}`, one row per relationship, **never a list on the
## right**: one fact must never move two counters, because a gate author reading
## `count: duels_won = 3` would have no way to know the number was also a sum of
## two unrelated deeds.
##
## Every `counter` value in COUNTER_FACTS is an id some shipped
## `FateDef.counters` declares, and every `fact` value is an id the shipped
## production paths actually record.
## [code]test_destiny_counter_production_wiring.gd[/code] asserts both directions
## over the real catalogs, so deleting a row cannot quietly retire a fate.
const COUNTER_FACTS: Array[Dictionary] = [
	# `what_the_rotation_cost.tres` step 2 — the beat a duel writes. The one fact
	# that is authored under BOTH `quest` and `destiny`, which is what makes it
	# the seam: a quest step watching it and a fate reading it are the same
	# occurrence in the world's memory.
	{"fact": &"duels_won", "counter": &"duels_won"},
	# step 3 — the third man was spared.
	{"fact": &"third_man_spared", "counter": &"enemies_spared"},
	# step 1 — came off the wall mid-watch.
	{"fact": &"vigil_broken", "counter": &"watch_turned"},
	# step 2 — the calling was cut and the name called.
	{"fact": &"bound_name_called", "counter": &"severances"},
	# step 1 — a counted mark from the mountain.
	{"fact": &"mountain_circled_once", "counter": &"heaven_marks"},
	# step 3 — the sect countersigned the register with no living elder of the line.
	# `oaths_sworn`, not `severances`: a registered heir is a sworn house, and
	# `household_registered_as_heir` declares `oaths_sworn` as its counter.
	{"fact": &"household_heir_registered", "counter": &"oaths_sworn"},
	# step 2 — the post was actually held, so the oaths of it were discharged.
	# Deliberately NOT `oaths_sworn`: `ancestral_debt_unpaid` reads that counter,
	# and the sect's register here records debts DISCHARGED, which is the
	# opposite claim. A counter that rose for both would answer a gate the player
	# has not earned.
	{"fact": &"oaths_discharged", "counter": &"oaths_broken"},
	# The 100th of the tide, counted by the sect and not by the hand. The only
	# event beat wired to a fate counter, and the only counter any event reaches.
	{"fact": &"hundredth_beast_slain", "counter": &"kills"},
]

## Facts the shipped tree PRODUCES and no authored fate reads — deliberately unmapped.
##
## ## BL-0600's decision, written down rather than left to look like an oversight
##
## `sect_post_held` is a real world fact with a real producer (`SectFacts.record_post_held`)
## and four shipped quest steps watch it. It is NOT in [constant COUNTER_FACTS], and that is
## a DECISION: no authored `FateDef.counters` names a counter a held office should move.
## Adding a row would move a counter no fate reads, which
## `test_every_wired_counter_is_one_the_shipped_tree_declares` refuses, and picking one of
## the existing counters (say `oaths_sworn`) would change a shipped fate's progress as a
## side effect of a wiring fix — a balance change dressed as a bug fix.
##
## ## Why a named list and not a comment
##
## The census in `tests/modules/destiny/test_destiny_unmapped_facts.gd` asserts this list
## EQUALS what it finds, so a fact that gains or loses a mapping must be moved here in the
## same change. Without the list, the next reader cannot tell "deliberately unmapped" from
## "somebody forgot", which is exactly the ambiguity BL-0600 recorded.
const FACTS_NO_FATE_READS: Array[StringName] = [&"sect_post_held"]

## The module's signal bus. It lives HERE because a GDScript signal belongs to an
## instance and a facade is a namespace of statics — but it is REACHED through the
## facade, as [method DestinyApi.events], because `ui/` is a pure consumer and may
## name `destiny` only through `api.gd`: a codex screen that had to come here to
## subscribe was a boundary breach, which is what `tools arch` failed the repo on.
##
## So this is where the bus is OWNED and [method DestinyApi.events] is how it is
## handed out — one instance, delegated rather than copied, or subscribers would
## split across two buses and every listener would hear nothing. Anything that
## needs to observe fate connects through that verb, and nothing outside the
## module emits through it.
static var bus: DestinyEvents = null

##
## The gate verb `counter` reads `ledger["counters"]` through
## [method DestinyApi.state] (it was once a verb of its own, `DestinyApi.counter`,
## retired at the twelve-method cap — see [method DestinyApi.events]), and until
## [method on_fact_recorded] was reached from [method subscribe_to_fact_ledger]
## nothing in `src/` ever wrote one. All nine authored counter ids were permanently
## 0, so a `.tres` gate `{verb: &"counter", id: &"duels_won", need: 3}` was theatre:
## it could never open and no player could ever earn what it advertised (DEF-0121,
## DEF-0181).
##
## The writer is the beat substrate, not a new one. `WorldFact.record` is the ONE
## verb that writes the fact ledger — its own docstring says so — and every shipped
## producer reaches it: [code]BeatDirector.offer[/code], [code]CombatFacts[/code],
## [code]ClanFacts[/code], [code]SectFacts[/code], [code]event/EventBeatWriter[/code],
## [code]app/CharacterCreationFlow[/code], [code]app/SoulDeath[/code] and
## [code]app/ItemWorkbenchApp[/code]. **Eight writers**, and the number is asserted
## rather than counted by hand: `tests/arch_rules/test_fact_ledger_writers.gd` walks
## `res://src` and compares that set to its `KNOWN_WRITERS` by exact equality, so this
## paragraph and the test cannot disagree for more than one cycle without something
## going red. They DID disagree — this list said six for several cycles while the test
## said eight, because ADR 0130's `soul_died` and the birth's `child_born` each shipped
## after the enumeration was written. Two of the eight write facts NO fate in
## [constant COUNTER_FACTS] reads, and that is the correct answer for a blank fact: a
## fact is a thing that happened, not a thing that pays out, and it still costs one
## dispatch to arrive here and be refused.
## This module SUBSCRIBES to that verb,
## so the bridge adds ZERO frame drivers and ZERO parallel event systems: it is a
## pure function from a fact that was recorded to a counter that moves.
##
## WHY THE MAPPING LIVES HERE, AND WHY IT IS AN EXPLICIT CONSTANT.
##
## 1. It is authored content, and it sits with the module that owns the question.
##    A fact id is an authored world assertion; a counter id is an authored fate
##    assertion ([code]FateDef.counters[/code]). The two vocabularies are kept in
##    one flat `WorldFact` namespace by ADR 0113 and ADR 0065 on purpose — a
##    prefixed id "reads as a working reference and silently grants nothing". The
##    ONLY honest thing to do is write down which id means which, and this file is
##    the one place that already answers "what is a fate's consequence".
## 2. A data file would be second vocabulary with no reader.
##    [code]OptionCatalog.scale_path[/code] and [code]item_slots.gd[/code] are the
##    repo's JSON precedent, and they are audit-scanned by [code]tools/options.py[/code]
##    and the `data` gate. A new file under `game/data/destiny/` that nothing in
##    [code]tools/[/code] knows would ship un-audited content, and a typo in it would
##    be a silently dead fate — the exact failure `_destiny_findings` exists to
##    prevent. Rejected: an auditable location with no auditor, on a gap that is
##    closed by making ONE truthful edit.
## 3. Never a fuzzy name match. `duels_won` and `hundredth_beast_slain` are both
##    about killing and are NOT the same claim; `sect_post_held` is about an office
##    and `oaths_sworn` is about a spoken oath. Deriving the pairing from spelling
##    would grant a fate for the wrong deed, and the grant is permanent (ADR 0065).
##    Every row below is spelled out because it is a decision, not a derivation.
##
## WHY THE DISPATCH IS A SUBSCRIPTION TO `WorldFact.record`, AND NOT A `BeatSink`
##
## ADR 0117's contract: a sink is PURE — it mutates no ledger — and the director
## applies. A sink that moved `DestinyApi`'s ledger from inside `resolve` would
## break that contract for every sink, and `contracts/beat_sink.gd` states the
## rule. So the dispatch is not a sink, and it is not in the director either.
##
## ## Why `BeatDirector.offer` was the wrong chokepoint, measured (ADR 0149)
##
## It was tried there first and **0 of the 8 rows could fire in production.** The
## director has exactly ONE production caller, [code]app/WorldPulse.offer[/code],
## which offers the period fact and the four [code]app/WorldAmbient[/code] roster
## facts — and not one of them appears in [constant COUNTER_FACTS]. Meanwhile all
## eight real producers call `WorldFact.record` directly and bypassed the dispatch
## entirely, so the suite driving the director's own path was green while every
## authored counter sat at 0. Green machinery, no wiring: the defect class ADR 0149
## is about.
##
## `WorldFact.record` is the chokepoint that actually holds, because it is the ONE
## verb that writes and its own docstring claims it. [method subscribe_to_fact_ledger]
## is the install, and [code]app/item_workbench_app.gd[/code] is what runs it —
## the composition root, which is the only layer allowed to know `destiny` exists.
## `core/` names no subscriber and could not: `tools arch` holds it to
## `LAYER_DEPS["core"] == {"core", "contracts"}`.
##
## ## One fact occurrence moves one counter, EXACTLY once
##
## The subscription is one entry in a list [code]core/world_fact.gd[/code] walks,
## and [code]record[/code] is called once per occurrence by every writer — so
## there is exactly one dispatch per fact, whichever of the eight writers made it. The
## director's own former call is the one thing that could double this, and it is
## gone: `app/beat_director.gd` must delete it (see the note on
## [method subscribe_to_fact_ledger]).
##
## ## MONOTONICITY IS `DestinyApi.record`'S RULE, NOT THIS FILE'S
##
## [method on_fact_recorded] moves a counter ONLY through the facade's monotone
## verb, and hands it the beat's OWN `amount`. Nothing here lowers a count, and a
## write `core` refused (`amount < 1`, an empty id, a null actor) never reaches a
## subscriber at all — the hook fires only on `ok: true`.


## The module's post-write hook entry point, in the form `core/world_fact.gd` calls
## it: `(actor, fact_id, amount)`. Every parameter is a primitive or a value object
## this layer already speaks, and nothing is read back from the report — the fact is
## already in the ledger by the time this runs. [method on_fact_recorded] does the
## whole job.
##
## ## Why a MODULE verb and not a lambda installed by `app/`
##
## The composition root could pass `Callable(DestinyProjection, "on_fact_recorded")`
## and reach the same place. It does not, for the same reason
## [code]NpcBoot.install[/code] hands over `Callable(NpcApi, "tally")` rather than a
## closure: the callable this layer publishes states the signature a reader is
## already looking at, and the module can describe what it promises to do with the
## call. A lambda assembled in `app/` would leave `app/` holding the rule and
## `destiny/` holding only a lookup table — two places to drift, and the second one
## is the one a module boundary is supposed to make impossible.
static func subscribe_to_fact_ledger() -> bool:
	return WorldFact.subscribe(Callable(DestinyProjection, "on_fact_recorded"))


## Whether [method subscribe_to_fact_ledger] is installed. A read rather than a
## compare against the install's return value, so a probe or a test holding no
## reference to the callable can still ask whether the bridge is live.
static func is_subscribed_to_fact_ledger() -> bool:
	return WorldFact.has_subscriber(Callable(DestinyProjection, "on_fact_recorded"))


## Remove the bridge. The exact inverse of [method subscribe_to_fact_ledger], and
## idempotent. Exists because the test runner shares one process across every suite:
## a suite that leaves a subscriber installed would move counters for every later
## suite that records a fact, which is a failure belonging to neither.
static func unsubscribe_from_fact_ledger() -> bool:
	return WorldFact.unsubscribe(Callable(DestinyProjection, "on_fact_recorded"))


## The authored fact -> counter pairs. `{"fact": &"<world fact id>", "counter":
## &"<destiny counter id>"}`, one row per relationship, **never a list on the
## right**: one fact must never move two counters, because a gate author reading
## `count: duels_won = 3` would have no way to know the number was also a sum of
## two unrelated deeds.
##
## Every `counter` value in COUNTER_FACTS is an id some shipped
## `FateDef.counters` declares, and every `fact` value is an id the shipped
## production paths actually record.
## [code]test_destiny_counter_production_wiring.gd[/code] asserts both directions
## over the real catalogs, so deleting a row cannot quietly retire a fate.


## The bus a consumer subscribes to, created on first use. `ui/` reaches this
## through [method DestinyApi.events] rather than naming this file, because
## `ui/` may only cross a module boundary at its facade.
static func events() -> DestinyEvents:
	if bus == null:
		bus = DestinyEvents.new()
	return bus


static func counter_for_fact(fact: StringName) -> StringName:
	for row in COUNTER_FACTS:
		var entry := row as Dictionary
		if StringName(entry.get("fact", &"")) == fact:
			return StringName(entry.get("counter", &""))
	return &""


## Move the counter `fact` names by `amount`, and return the counter's value after
## it. `&""` returns 0 and writes nothing.
##
## **This is the bridge `core/world_fact.gd` calls** once per successful write —
## see [method subscribe_to_fact_ledger] — and it is deliberately the whole body of
## the dispatch, because a chokepoint that also branches is a chokepoint that can
## be reached in a second order. It does exactly one thing: hand the fact's OWN
## `amount` to [method DestinyApi.record]. Monotonicity, clamping and the projection
## rebuild are the facade's, so there is no second rule here to drift from it.
##
## Returns the value AFTER the delta (0 when nothing moved, and 0 when no
## relationship is authored), so a caller can name what the occurrence did.
static func on_fact_recorded(actor: Actor, fact: StringName, amount: int = 1) -> int:
	var counter_id := counter_for_fact(fact)
	if actor == null or counter_id == &"" or amount < 1:
		return 0
	return DestinyApi.record(actor, counter_id, amount)


## The event module's word for the same moment. Retained, because the fact is the
## same fact and a second implementation would be a second rule to drift —
## [method on_fact_recorded] is called verbatim, with no fourth argument: a written
## beat defaults to [constant EventBeatWriter.KIND_FACT], the documentation's own
## phrase for "no extra destination".
##
## **It is no longer the only thing that reaches an authored `on_enter` beat, and it
## did not need to be.** `EventBeatWriter.offer` calls `WorldFact.record` like every
## other producer, so the subscription reaches it; this verb is kept as the readable
## name for that writer's case rather than as a wire. Rejected: having the event
## module call this directly, which would have made `event` name `destiny` — an edge
## `tools/arch/registry.json` does not declare — and would have left a second
## dispatch that a future writer could hit twice.
static func on_beat_written(actor: Actor, fact: StringName, amount: int = 1) -> int:
	return on_fact_recorded(actor, fact, amount)


## READ the counter `fact` names, WITHOUT moving it. For a caller that wants to
## report what a beat did: the write already went through `WorldFact.record` and
## fired the subscriber, so the value here is the running total AFTER that move.
##
## The pairing with [method on_fact_recorded] is the whole point: one MOVES, one
## READS. A caller holding a report shape must never reach for the mover, because a
## counter is monotonic and never refundable (ADR 0065) — a second call for one
## occurrence is invisible AND irreversible. `&""` reads 0.
static func counter_after(actor: Actor, fact: StringName) -> int:
	var counter_id := counter_for_fact(fact)
	if actor == null or counter_id == &"":
		return 0
	var ledger := DestinyState.normalize(actor.get_module_data(DestinyState.MODULE_KEY))
	return DestinyState.counter_value(ledger, counter_id)


## Apply the whole ledger to `actor`. Idempotent by construction: every fate
## contribution is stripped first, then rebuilt. Calling this after no change is
## free of consequence — it produces the same modifier stack.
static func apply(actor: Actor, ledger: Dictionary) -> void:
	if actor == null:
		return
	strip(actor)
	for fate_id in DestinyState.fate_ids(ledger):
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null or not def.has_modifiers():
			continue
		for modifier in def.build_modifiers():
			actor.stats.add_modifier(modifier)
	# The trait mirror covers EVERY held fate, including the pure-narrative ones
	# that contribute no numbers: a fate whose whole purpose is to gate story is
	# exactly the one most likely to be tested through `has_trait`, so keying the
	# mirror off `has_modifiers()` would drop the fates that matter most here.
	for fate_id in DestinyState.fate_ids(ledger):
		actor.traits.add(DestinyState.trait_for(fate_id))
	for destiny_id in DestinyState.destiny_ids(ledger):
		actor.traits.add(DestinyState.trait_for(destiny_id))


## Remove every contribution this module owns, from both the stat stack and the
## trait mirror. Used only by `apply`, so a partial projection can never be left
## behind.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	for fate_id in FateCatalog.instance().fate_ids():
		actor.stats.remove_modifiers_from(DestinyState.source_for(fate_id))
		actor.traits.remove(DestinyState.trait_for(fate_id))
	for destiny_id in FateCatalog.instance().destiny_ids():
		actor.stats.remove_modifiers_from(DestinyState.source_for(destiny_id))
		actor.traits.remove(DestinyState.trait_for(destiny_id))


## What this module contributes to `stat_id`, read from the modifier stack
## rather than recomputed. Reading the stack proves the projection actually
## landed instead of trusting the ledger.
##
## Returned as `{"flat": float, "percent": float}` because a magnitude and a
## rate are different kinds of number: `3.0` flat and `0.3` percent both mean
## something real about a stat, and adding them into one total produces a number
## that means neither (ADR 0065 keeps fate on the single modifier pipeline,
## where `derived = (base + flat) * (1 + percent)` keeps them apart).
static func contribution(actor: Actor, stat_id: StringName) -> Dictionary:
	var out := {"flat": 0.0, "percent": 0.0}
	if actor == null:
		return out
	for modifier in actor.stats._modifiers:
		if modifier.stat != stat_id or not DestinyState.is_own_source(modifier.source):
			continue
		if modifier.op == Stat.Op.PERCENT:
			out["percent"] = float(out["percent"]) + modifier.value
		else:
			out["flat"] = float(out["flat"]) + modifier.value
	return out


## The number of modifiers this module currently holds on `actor`. The
## idempotence check: projecting twice must leave this unchanged.
static func modifier_count(actor: Actor) -> int:
	if actor == null:
		return 0
	var total := 0
	for modifier in actor.stats._modifiers:
		if DestinyState.is_own_source(modifier.source):
			total += 1
	return total
