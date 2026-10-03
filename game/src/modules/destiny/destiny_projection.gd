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
## [method on_fact_recorded] existed nothing in `src/` ever wrote one. All nine
## authored counter ids were permanently 0, so a `.tres` gate
## `{verb: &"counter", id: &"duels_won", need: 3}` was theatre: it could never open
## and no player could ever earn what it advertised (DEF-0121, DEF-0181).
##
## The writer is the beat substrate, not a new one. `WorldFact`'s ledger is already
## driven in production by [code]BeatDirector.offer[/code] (which records BEFORE it
## consults a sink), by [code]event/EventBeatWriter[/code] and by
## [code]app/CharacterCreationFlow[/code]. This table rides that same path, so the
## bridge adds ZERO frame drivers and ZERO parallel event systems: it is a pure
## function from a fact that was recorded to a counter that moves.
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
## WHY THE DISPATCH LIVES IN `app/` AND NOT IN A `BeatSink`.
##
## ADR 0117's contract: a sink is PURE — it mutates no ledger — and the director
## applies. A sink that moved `DestinyApi`'s ledger from inside `resolve` would
## break that contract for every sink, and `contracts/beat_sink.gd` states the
## rule.
##
## ## Three writers reach the fact ledger, and only ONE of them is the director
##
## 1. [code]BeatDirector.offer[/code] — the composition root's whole beat path, and
##    the one [method BeatDirector] dispatches on. Dispatched there below.
## 2. [code]event/EventBeatWriter.offer[/code] — what an authored `on_enter` beat
##    and a trigger opening go through. [code]app/world_pulse.gd[/code] names this
##    as the ONE point that BYPASSES the director: re-offering those beats from
##    `app/` would write one occurrence twice, because the ledger is monotone.
## 3. [code]app/CharacterCreationFlow.build[/code] — one fact, `character_created`,
##    written directly and deliberately after the grant it describes has landed.
##
## The bridge calls [code]event/EventBeatWriter.offer[/code] explicitly, so the
## counter follows the SAME moment the fact is recorded, on whichever of the three
## paths recorded it. That is what makes `hundredth_beast_slain` — the 100th of
## the beast tide, which no director ever sees — move `kills`.
##
## MONOTONICITY IS `DestinyApi.record`'S RULE, NOT THIS FILE'S.
##
## [method on_fact_recorded] moves a counter ONLY through the facade's monotone
## verb, and hands it the beat's OWN `amount`. Nothing here lowers a count, and a
## beat the director already refused (`amount < 1`) never arrives.

## The authored fact -> counter pairs. `{"fact": &"<world fact id>", "counter":
## &"<destiny counter id>"}`, one row per relationship, **never a list on the
## right**: one fact must never move two counters, because a gate author reading
## `count: duels_won = 3` would have no way to know the number was also a sum of
## two unrelated deeds.
##
## Every `counter` value here is an id some shipped `FateDef.counters` declares,
## and every `fact` value is an id the shipped production paths actually record.
## [code]test_destiny_counter_production_wiring.gd[/code] asserts both directions
## over the real catalogs, so deleting a row here cannot quietly retire a fate.
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


static func events() -> DestinyEvents:
	if bus == null:
		bus = DestinyEvents.new()
	return bus


## The counter id `fact` moves, or `&""` when the table says it moves none.
##
## A pure lookup over [constant COUNTER_FACTS]. Empty means "no relationship was
## authored", which is the answer for the overwhelming majority of beats — a
## period elapsing and a treasure stone being read are not fates.
static func counter_for_fact(fact: StringName) -> StringName:
	for row in COUNTER_FACTS:
		var entry := row as Dictionary
		if StringName(entry.get("fact", &"")) == fact:
			return StringName(entry.get("counter", &""))
	return &""


## Move the counter `fact` names by `amount`, and return the counter's value after
## it. `&""` returns 0 and writes nothing.
##
## The ONLY writer behind the `counter` gate verb, and it does exactly one thing:
## hand the beat's own `amount` to [method DestinyApi.record]. Monotonicity,
## clamping and the projection rebuild are the facade's, so there is no second
## rule here to drift from it.
##
## Returns the value AFTER the delta (0 when nothing moved, and 0 when no
## relationship is authored), so a report can name what the beat did.
static func on_fact_recorded(actor: Actor, fact: StringName, amount: int = 1) -> int:
	var counter_id := counter_for_fact(fact)
	if actor == null or counter_id == &"" or amount < 1:
		return 0
	return DestinyApi.record(actor, counter_id, amount)


## The same rule on the one production writer that bypasses the director.
##
## [code]event/EventBeatWriter.offer[/code] is what an authored `on_enter` beat
## goes through, and [code]app/world_pulse.gd[/code] states in as many words that
## re-offering those from the composition root "would write one occurrence twice",
## because the ledger is monotone. So the counter has to follow the fact HERE, or
## an authored event beat moves a fact and no fate counter — which is precisely how
## `hundredth_beast_slain` reached the world's memory while `one_hundredth_slain`'s
## `kills` counter stayed at 0 forever.
##
## [method on_fact_recorded] is reused verbatim rather than reimplemented: one
## lookup, one delta, one monotone facade verb, and no second rule to drift.
## Written beats default to [constant EventBeatWriter.KIND_FACT], the
## documentation's own word for "no extra destination", so the fourth argument is
## never spelled here.
static func on_beat_written(actor: Actor, fact: StringName, amount: int = 1) -> int:
	return on_fact_recorded(actor, fact, amount)


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
