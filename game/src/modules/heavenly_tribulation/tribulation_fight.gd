class_name TribulationFight
extends RefCounted

## The heavenly tribulation's fight lifecycle (ADR 0020, ADR 0032).
##
## `core` owns the record, the phase machine and the rewards. This module owns
## the three questions core deliberately does not answer:
##
##   - WHICH realm a tribulation is owed. `actor.tribulation` is a single slot,
##     and `Breakthrough.tribulation_ok` accepts only a record bound to the exact
##     realm being entered, so somebody has to pick one. The rule is the FIRST
##     tier any enrolled path still owes: a hero standing at R18 owes R19 before
##     a second path on the same actor owes R28.
##   - WHEN the fight is decided. Reaching the last phase is not surviving
##     (`Tribulation.survived`), so the wave that completes the record is where
##     the verdict is taken — once, and never inferred.
##   - HOW MUCH of a fight this actor survives. That is NOT this module's: the roll
##     and the curve behind it are `TribulationEndurance`, in core, so there is one
##     answer to "did this actor survive" rather than one per module (ADR 0066). This
##     module decides WHEN the verdict is taken and reports it.
##
## SEAM. `TribulationEndurance._owed_realm` restates this module's
## `target_realm` — the same "first tier any enrolled path still owes" rule, in two
## places, because core's copy is private. `TribulationEndurance.owed_realm` should
## become public and this module's `target_realm` should delete; until then the rule
## has two homes and a test on either would not catch a change to the other.

## Upper bound on waves one fight may drag on, and the loop guard for a driver
## that keeps calling `fight_wave`. `Tribulation.max_waves` is authored 3..9 and
## `advance_wave` refuses to pass it, so `max_waves + 2` calls complete a fight;
## 16 is two full fights of headroom. It exists to name the failure it catches:
## a phase machine that does not converge.
const WAVE_GUARD := 16

# --- Which realm is owed -----------------------------------------------------


## Ladder index of the realm this actor's next tribulation is owed for, or -1
## when no enrolled path is owed one.
static func target_index(actor: Actor) -> int:
	var ladder := RealmDefaults.ladder()
	var best := -1
	for state in actor.paths.values():
		if state == null or not state.is_started():
			continue
		var upcoming := ladder.next(state.rank_id)
		if upcoming == null:
			continue
		var index := ladder.index_of(upcoming.id)
		# Lowest tier owed wins, not highest: the slot holds one fight, so the
		# closest unearned gate is the one worth filling.
		if index >= Breakthrough.IMMORTAL_REALM_THRESHOLD and (best < 0 or index < best):
			best = index
	return best


## The realm id a tribulation is owed for, or empty when none is owed.
static func target_realm(actor: Actor) -> StringName:
	var index := target_index(actor)
	if index < 0:
		return &""
	return RealmDefaults.ladder().realms()[index].id


# --- The fight ----------------------------------------------------------------


## Begin the tribulation owed, bound to that realm. Refused when no realm is owed
## or a fight is already in progress: re-beginning an unfinished fight would
## discard the waves already fought, so a caller must fight it out, withdraw, or
## let the save carry it.
static func begin(actor: Actor) -> Dictionary:
	var index := target_index(actor)
	if index < 0:
		return _refused("no realm above the Immortal gate is owed yet")
	if actor.tribulation != null and not actor.tribulation.is_complete():
		return _refused("a tribulation is already in progress")
	var started := Breakthrough.begin_tribulation(actor, index)
	if started == null:
		return _refused("the tribulation would not begin")
	return {
		"ok": true,
		"reason": "",
		"decided": false,
		"wave": started.wave,
		"max_waves": started.max_waves,
	}


## Fight one wave. The wave that brings the record to its last phase also takes
## the verdict, because a record that merely ran to its last phase has survived
## nothing. `rng` makes the roll a test's choice instead of a hope; null uses the
## engine's.
static func fight_wave(actor: Actor, rng: RandomNumberGenerator = null) -> Dictionary:
	if actor.tribulation == null:
		return _refused("no tribulation has begun")
	if actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED:
		return _refused("the tribulation is already decided")
	if not actor.tribulation.is_complete():
		Breakthrough.advance_tribulation(actor)
	if not actor.tribulation.is_complete():
		return {"ok": true, "reason": "", "decided": false, "wave": actor.tribulation.wave}
	var won := TribulationEndurance.survives(actor, actor.tribulation, rng)
	Breakthrough.resolve_tribulation(actor, won)
	return {"ok": true, "reason": "", "decided": true, "survived": won}


## Fight from whatever phase the record is in to a decided verdict, bounded by
## `WAVE_GUARD`. Provided for a caller that wants "finish this" rather than "one
## more wave"; the bound names what failed to converge rather than hiding it.
static func fight_to_verdict(actor: Actor, rng: RandomNumberGenerator = null) -> Dictionary:
	var guard := 0
	while guard < WAVE_GUARD:
		guard += 1
		var step := fight_wave(actor, rng)
		if not bool(step.get("ok", false)):
			return step
		if bool(step.get("decided", false)):
			return step
	return _refused("the tribulation did not reach a verdict in %d waves" % WAVE_GUARD)


## Walk away from a fight without deciding it. The waves fought are forfeited, so
## the gate stays shut and nothing is gained or lost. Refused once the fight is
## decided: a survivor that withdrew would be discarding the gate it earned, and
## a defeat that withdrew would be discarding the record that proves it happened.
static func withdraw(actor: Actor) -> bool:
	if actor.tribulation == null:
		return false
	if actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED:
		return false
	Breakthrough.cancel_tribulation(actor)
	return true


# --- Read model ---------------------------------------------------------------


## Everything a tribulation screen renders, as primitives. Empty when no actor is
## bound or no path is enrolled.
static func state(actor: Actor) -> Dictionary:
	if actor == null or actor.paths.is_empty():
		return {}
	var ladder := RealmDefaults.ladder()
	var index := target_index(actor)
	var record := actor.tribulation
	var decided := record != null and record.outcome != Tribulation.OUTCOME_UNRESOLVED
	var target := ladder.realms()[index] if index >= 0 else null
	var view := {
		"owed": index >= 0,
		"target": "" if target == null else String(target.id),
		"target_name": "" if target == null else target.display_name,
		"bound": "" if record == null else String(record.realm_id),
		"has_record": record != null,
		# Undecided: the record is the player's to fight out or withdraw, and the
		# waves already survived are still worth something.
		"active": record != null and not decided,
		"decided": decided,
		"type": "" if record == null else String(record.type),
		"phase": "" if record == null else String(record.phase),
		"wave": 0 if record == null else record.wave,
		"max_waves": 0 if record == null else record.max_waves,
		"difficulty": 0.0 if record == null else record.difficulty,
		"outcome": "" if record == null else String(record.outcome),
		# The share of fights this actor survives, from core's one curve. Null
		# record is deliberate: core prices the fight this actor is owed when none
		# is running, so the screen can show the odds before the player commits.
		"chance": 0.0 if index < 0 else TribulationEndurance.endurance(actor),
	}
	# The gate, read through core's own predicate so a screen never restates it,
	# and open when nothing is owed: a mortal hero's gate is not shut.
	view["gate_open"] = true if index < 0 else Breakthrough.tribulation_ok(actor, index)
	return view


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "decided": false}
