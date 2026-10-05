class_name TechniqueUpkeep
extends RefCounted

## Which equipped techniques are currently paying their upkeep (ADR 0054).
##
## This is the same generic shape as `EquipmentUpkeep`, welded to a different slot
## list rather than a fork of it. `EquipmentUpkeep` is bound to `Equipment.SLOTS`,
## so a technique slot needs its own settle loop that shares the same `_pay`.
##
## Upkeep is an ongoing obligation, not an equip gate, so this never unequips
## anything and never blocks an equip. A technique that cannot pay is SUSPENDED: it
## stays equipped and contributes nothing. That ordering is deliberate — if spending
## in combat could unequip, a fight you were winning would strip you mid-fight, and
## a player could never opt out of an upkeep they could not afford.

## The shortest interval a technique may author. Anything below this would settle
## every frame regardless of what it asked for, so a zero or negative `upkeep_interval`
## degrades to "not every frame" instead of "every frame".
##
## **A floor on AUTHORED DATA, not a cadence** (ADR 0173's `MIN_INTERVAL` row). It is
## read as `maxf(def.upkeep_interval, MIN_INTERVAL)` against a `TechniqueDef` whose own
## default is `60.0` seconds, so it guards a `.tres` edit rather than measuring the
## world. No `TimeLadder` magnitude is one second, and deriving one would move upkeep
## balance instead of retiming the clock — so this number stays authored and is reported
## to the single-source guard as a deliberate remaining hit rather than hidden from it.
const MIN_INTERVAL := 1.0

## ## How a PASSIVE is mastered, and the evidence that chose it (ADR 0247)
##
## **One rung per settled interval, while the technique is equipped and not
## suspended.** Mastery of a passive is TIME WORN: the ladder `ladder_view`
## publishes to the codex screen was, for every authored passive, a ladder no
## player could climb — `activate` refuses a passive with `not_active`, and
## `_grant_mastery` is reached only from `activate` (DEF-0304).
##
## Three inputs were considered and two are refused by the SHIPPED CORPUS rather
## than by taste:
##
## - **Re-studying the manual.** The verb is live (`ItemUse` →
##   `TechniqueDelivery.study` → `TechniquesApi.learn`) and already monotonic. Its
##   INPUT is not: all eighteen authored passive manuals declare exactly one route
##   and `test_no_two_defs_claim_the_same_manual` pins the mapping one-to-one, so
##   fifteen of eighteen declare a single `domain:`/`boss:` and are obtainable once.
##   It would close DEF-0304 for three techniques and leave fifteen open.
## - **Paying upkeep as the SOURCE.** `settle` skipped a def with no bill, and only
##   three of eighteen authored passives declare one. Gating the rung on a bill
##   fifteen techniques do not carry leaves fifteen unreachable.
## - **"Using its stat."** Not an input: a passive's stat is live from the equip,
##   so the rule would describe a state rather than an act.
##
## So upkeep becomes the GATE that withholds a rung, never the source that earns
## it, and the visit predicate below is what makes an unpaid-free passive visitable
## at all.
##
## ## THE TUNING KNOB, and it is this constant
##
## How many settled intervals one rung costs. At the shipped 60.0s
## `upkeep_interval` and `RUNG_PERIODS = 1` that is rung 4 in four minutes of
## continuous wear, which is FAST and may well be the wrong balance: a worn frame
## is meant to be the slow investment. Raising this is a one-constant change, it
## needs no save migration, and it is deliberately the only number in this file a
## designer is expected to retune.
##
## It is read by [method _grant_rung] and by nothing else, so a constant that a
## retune could orphan is not left behind.
const RUNG_PERIODS := 1

## The `mastery_by` a ladder is published under, so a screen can say how a passive
## is climbed. Named here rather than in the read model so the projection and the
## settle loop cannot disagree about the verb — the same reason `is_capacity_effect`
## is written once and read twice (ADR 0160).
const MASTERY_BY := &"worn"

## technique_id -> true when suspended. Absent means active.
var _suspended: Dictionary = {}

## technique_id -> settled intervals worn since the last rung, for [constant
## RUNG_PERIODS]. SESSION-SCOPED and never persisted: the rung is the durable fact
## and this is the step toward the next one, so a save carries the player's progress
## and not the arithmetic. See [method _grant_rung].
var _earned: Dictionary = {}

## Seconds accumulated toward the next settlement. `settle` charges a technique's
## upkeep IMMEDIATELY, so a caller that invokes it per frame would drain the pool
## sixty times a second and make every upkeep unaffordable within a second. The
## accumulator is what lets the composition root's frame tick (`StatusLoop.tick`,
## ADR 0089) drive upkeep on the same clock as statuses and bonds without either
## system owning a clock of its own.
var _elapsed: float = 0.0


func is_suspended(technique_id: StringName) -> bool:
	return _suspended.get(technique_id, false)


func suspended() -> Array[StringName]:
	var out: Array[StringName] = []
	for technique_id in _suspended.keys():
		out.append(technique_id)
	return out


func clear() -> void:
	_suspended.clear()
	_earned.clear()
	_elapsed = 0.0


## Accumulate `delta` and settle only when an interval has genuinely elapsed. Returns
## the ids that changed state on THIS call, so a caller pays for a rebuild only when
## something moved. A `settle` that finds nothing due is free.
func advance(actor: Actor, delta: float, equipped: Array[StringName]) -> Array[StringName]:
	if actor == null:
		return []
	_elapsed += maxf(0.0, delta)
	var interval := _shortest_interval(equipped)
	# The epsilon is not cosmetic. A frame tick adds 1/60 sixty times, and float
	# accumulation lands that sum a hair UNDER 60.0 — so a strict `<` never fires at
	# exactly one interval and a 60-second upkeep silently never charges. The
	# tolerance is far below MIN_INTERVAL, so it can never settle early by a
	# meaningful amount.
	if interval <= 0.0 or _elapsed < interval - 0.001:
		return []
	_elapsed -= interval
	return settle(actor, equipped)


## The shortest authored interval among the equipped techniques [method _visits],
## or 0 when none do. The shortest wins so no technique is ever charged late, and
## `MIN_INTERVAL` bounds a zero that would otherwise settle on every frame.
##
## Reads the SAME predicate `settle` does, so the cadence can never disagree with
## what a settle would actually visit: an interval that decides to wake, and then
## declines to act because it has nothing to do, is a technique whose rung moves at
## a different rate from the clock that is supposed to be driving it.
func _shortest_interval(equipped: Array[StringName]) -> float:
	var shortest := 0.0
	for technique_id in equipped:
		var def := TechniqueCatalog.instance().definition(technique_id)
		if def == null or not _visits(def):
			continue
		var interval := maxf(def.upkeep_interval, MIN_INTERVAL)
		if shortest <= 0.0 or interval < shortest:
			shortest = interval
	return shortest


## Whether a settled interval has anything to DO for `def` — a bill to charge, or a
## passive ladder to climb (ADR 0247).
##
## This replaces a bare `def.upkeep.is_empty()`, and it is what makes a passive with
## no upkeep at all visitable. Fifteen of the eighteen authored passives declare no
## upkeep, so the old test reached none of them and the rung had no clock to move it.
##
## An ACTIVE with no bill is still skipped, unchanged: its ladder is climbed by
## `activate`, which calls at its own rate and pays its own costs.
static func _visits(def: TechniqueDef) -> bool:
	if def == null:
		return false
	return not def.upkeep.is_empty() or def.is_passive()


## Drop the suspension record for a technique that is no longer equipped, so a
## technique that is unequipped and later re-equipped starts paying again rather
## than inheriting a stale refusal — and the wear ledger goes with it, for the same
## reason: a loadout swap is a fresh investment, not a continuation of the last one.
func forget(technique_id: StringName) -> void:
	_suspended.erase(technique_id)
	_earned.erase(technique_id)


## Settle one interval for every equipped technique [method _visits]. Returns
## the technique ids whose state changed — a suspension flipping, or a passive's
## rung climbing (ADR 0247) — so a caller rebuilds only those. Suspension is per
## technique and keyed by id, so paying one technique's upkeep does not reactivate
## another's.
func settle(actor: Actor, equipped: Array[StringName]) -> Array[StringName]:
	var changed: Array[StringName] = []
	if actor == null:
		return changed
	for technique_id in equipped:
		var def := TechniqueCatalog.instance().definition(technique_id)
		if def == null or not _visits(def):
			continue
		# One id, at most ONE entry, however many things moved for it. `StatusLoop.tick`
		# stringifies this list straight into its frame report, so a duplicate would
		# print the same technique twice in the readout.
		var was := is_suspended(technique_id)
		# The bill is charged BEFORE the rung is granted, and that order is the whole
		# rule (ADR 0247). A rung is earned for an interval that was actually PAID,
		# so a technique that cannot afford its upkeep on the very first interval
		# suspends having taught nothing — mastery paid for a contribution the actor
		# never received is the one answer this feature must not give.
		#
		# An empty `upkeep` settles to a no-op: `_pay` over no resources returns true,
		# which is the answer this file has always given an un-billed technique, and is
		# the whole reason such a passive is now visited at all.
		var paid := _pay(actor, def)
		var moved := false
		if paid and was:
			# Paying again revives it. No rung: the interval it had suspended for was
			# not worn, and a technique that walks back to life has to wear its way up
			# again rather than cash in the gap.
			_suspended.erase(technique_id)
			moved = true
		elif not paid and not was:
			_suspended[technique_id] = true
			moved = true
		elif paid and def.is_passive():
			# Paid, and not suspended before this interval: the one case that earns.
			moved = _grant_rung(actor, def)
		if moved:
			changed.append(technique_id)
	return changed


## Move a passive's rung up by ONE, and report whether it moved (ADR 0247).
##
## ## Why exactly ONE, and why it is the same expression casting uses
##
## `_grant_mastery` reaches rung `r + 1` through
## `TechniqueScales.rung_for(rung + 1, def.mastery_rungs)` and refuses when the
## ladder has no room. A period that granted as many rungs as it liked would not be
## a deeper investment, it would be a multiplier on `advance`'s delta — and
## `advance` subtracts ONE interval per settle, so a single frame spanning ten
## intervals would hand ten rungs and make the rate a function of frame rate rather
## than of the ladder.
##
## ## Why monotonicity is not this method's job
##
## `TechniqueCodex.set_rung` refuses any rung that is not strictly greater, so a
## lower rung cannot replace a higher one whatever this caller computes. That is the
## guarantee; what this method owes is only that it never ASKS for a rung below the
## one held, and that it never counts an interval it did not convert.
##
## ## Why `raise_mastery` and not a direct codex write
##
## `TechniquesApi` is at the 12-method cap, and `raise_mastery` is already the
## facade's one rung verb: it sets, commits the shared payload (a codex-only write
## would drop every equipped binding — DEF-0154) and rebuilds. Reaching it is the
## same route `TechniqueCasting._grant_mastery` takes, so both kinds of technique
## land their rung through one function.
##
## ## The cap is checked BEFORE the counter moves
##
## A technique parked at the top of its ladder is asked to climb on every settled
## interval for the rest of the session. Counting those intervals would grow an
## integer forever against a ladder that can never spend it, so the ceiling is the
## first thing asked and the count is only touched when there is somewhere to go.
func _grant_rung(actor: Actor, def: TechniqueDef) -> bool:
	var codex := TechniquesApi.codex(actor)
	var held := int(codex.row(def.id).get("rung", 0))
	var reached := TechniqueScales.rung_for(held + 1, def.mastery_rungs)
	if reached <= held:
		# At the ladder's end: keep no partial progress, so a technique that is later
		# re-equipped and re-climbed starts its next rung from zero intervals rather
		# than from an arbitrary bank.
		_earned.erase(def.id)
		return false
	_earned[def.id] = int(_earned.get(def.id, 0)) + 1
	if int(_earned[def.id]) < maxi(1, RUNG_PERIODS):
		return false
	_earned[def.id] = 0
	return bool(TechniquesApi.raise_mastery(actor, def.id, reached).get("ok", false))


## Pay one interval, or refuse. Base pools only, so a technique cannot fund its own
## upkeep out of the stats it grants — the same rule equipment follows, and the one
## that keeps `ItemRequirement`'s reserve load-bearing: without a reserve, upkeep
## would chip an actor to zero and suspend on the last tick.
func _pay(actor: Actor, def: TechniqueDef) -> bool:
	for resource_id in def.upkeep.keys():
		var pool := actor.resource(StringName(resource_id))
		if pool == null:
			return false
		var reserve := 0.0
		if def.requirement != null:
			reserve = float(def.requirement.upkeep_reserve.get(resource_id, 0.0))
		if pool.current - float(def.upkeep[resource_id]) < reserve:
			return false
	for resource_id in def.upkeep.keys():
		var pool: ResourcePool = actor.resource(StringName(resource_id))
		pool.current -= float(def.upkeep[resource_id])
	return true
