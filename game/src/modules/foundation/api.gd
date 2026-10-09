class_name FoundationApi
extends RefCounted

## Public facade for the `foundation` module. Other modules may reference ONLY this file
## (`api.gd`).
##
## ## What this module is
##
## The SHARED half of the foundation program (BL-0951 / ADR 0939): the record of how
## perfectly each realm was left, and the vocabulary around it. Each cultivation path
## implements its own rules over the record — its own `min_foundation` demand, its own
## tribulation scaling, its own principle-based measurement — so no path keeps a second
## copy (ADR 0066) and this module never learns a path's formula.
##
## ## The one verb this slice publishes
##
## `snapshot` is the WRITE: called by a path's breakthrough transaction at the moment the
## actor leaves a realm. The reads (`foundation`, `state`, `summary`) land with the gate
## that consumes them — a published verb with no caller is the dead surface
## `tools/arch`'s caller-less guard refuses, and its allowlist is not a backlog.
##
## ## Three-state vocabulary (ADR 0083)
##
## A null actor or an empty realm answers a NAMED refusal, never a hidden zero.

const R_NO_ACTOR := "no_actor"
const R_EMPTY_REALM := "empty_realm"
const R_ALREADY_SNAPSHOTTED := "already_snapshotted"

## A training press costs TIME, and time is periods (BL-0951 / ADR 0939, S6). One press is
## one day of the body's life at the authored ladder ratios (12 periods to the day) — the
## same price on every path, because the clock does not bargain by path. Authored here so
## a retune is one edit: the verbs in the three paths call [method spend_periods], they
## never name a count.
const TRAINING_PRESS_PERIODS := 12

## What one last attempt in the final band burns (BL-0951 / ADR 0939, S6): one year of the
## body's remaining life, at the authored ladder ratios (12 periods to the day, 365 days
## to the year — derived below, never typed). The attempt that spends it is harsher than
## any other for exactly this reason: win or lose, the years are gone.
const LASTLIGHT_ATTEMPT_PERIODS := 4380

## The cliff's named refusal (BL-0951 / ADR 0939, S6): in the final band there is no more
## training to do, so every training verb refuses with THIS rather than with silence.
const R_LASTLIGHT := "lastlight"


## The carried aggregate the paths gate on: the mean of every snapshot, `0.0` when the
## actor has left no realm yet. This is the number a path's authored `min_foundation`
## compares against; the paths own the comparison, this module owns the arithmetic.
static func foundation(actor: Actor) -> float:
	if actor == null:
		return 0.0
	return FoundationRecord.aggregate(
		FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	)


## The foundation a tribulation is fought at: the carried aggregate, or `1.0` when the
## actor has left no realm yet. An empty record is not a sloppy record — a fight the
## tribulation tests start at a realm directly has no departures to judge, so it rates
## the baseline rather than the harshest fight. A real climb always leaves realms behind
## it, so in play this default never fires; in a fixture it keeps the shipped endurance
## band exactly where the census measured it.
static func tribulation_foundation(actor: Actor) -> float:
	if actor == null:
		return 1.0
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if FoundationRecord.count(record) == 0:
		return 1.0
	return FoundationRecord.aggregate(record)


## Spend `periods` of the BODY's life: accrue them into `age_years` through the
## `TimeLadder` ratios and answer the years spent. Every training press in every path
## pays through this one verb (BL-0951 / ADR 0939, S6), so one sitting costs the same
## life wherever it is sat.
##
## ## The body's life, never the world's count
##
## This writes `actor.age_years` — a BODY FACT (ADR 0258 §2) — and never touches the
## `WorldClock`: modules may not own time (ADR 0089 / DEF-0111), and the world does not
## get older because one body sat down. Closed-door cultivation ages the cultivator
## while the world stands still, which is also what makes a lone sitting unable to
## trigger world events, saves or accruals that belong to the passing world.
##
## A null actor, a non-positive span or a non-finite one spends nothing and answers
## `0.0`: a refusal elsewhere in the verb must cost nothing (ADR 0044), and time that
## was never sat cannot be owed.
static func spend_periods(actor: Actor, periods: int) -> float:
	if actor == null or periods <= 0:
		return 0.0
	var day_ratio := TimeLadder.ratio_for(&"day")
	var year_ratio := TimeLadder.ratio_for(&"year")
	if day_ratio < 1 or year_ratio < 1:
		return 0.0
	var years := float(periods) / float(day_ratio) / float(year_ratio / day_ratio)
	if not is_finite(years) or years <= 0.0:
		return 0.0
	actor.age_years = maxf(0.0, actor.age_years + years)
	return years


## Whether training is refused for this actor, by name: `R_LASTLIGHT` in the final band,
## `""` everywhere else (BL-0951 / ADR 0939, S6). Every training verb in every path asks
## THIS first, so the cliff is one rule rather than three coinciding refusals — and a
## screen can ask it too, which is how a player learns the sitting is gone before
## pressing it. A null actor is refused: a verb with nobody to train trains nothing.
static func training_refusal(actor: Actor) -> String:
	if actor == null:
		return R_NO_ACTOR
	if AgeBandTable.band_for_actor(actor) == AgeBandTable.LASTLIGHT:
		return R_LASTLIGHT
	return ""


## Price one breakthrough attempt taken NOW: in the final band it burns
## `LASTLIGHT_ATTEMPT_PERIODS` of the body's remaining life through [method spend_periods]
## and answers the years burned; in any earlier band it answers `0.0` and spends nothing
## (BL-0951 / ADR 0939, S6). Each path's attempt flow calls this where the attempt is
## decided — after the roll, win or lose — so the last years go whether the heavens
## open or not. Succeed and the lengthened life may pull the body out of the final band;
## fail and the burn may finish what the lifespan started, through the existing
## `SoulAge`/`SoulDeath` machinery rather than any new death of its own.
static func burn_final_attempt(actor: Actor) -> float:
	if actor == null:
		return 0.0
	if AgeBandTable.band_for_actor(actor) != AgeBandTable.LASTLIGHT:
		return 0.0
	return spend_periods(actor, LASTLIGHT_ATTEMPT_PERIODS)


## Write the PERFECTION snapshot for a realm the actor is leaving. ONCE per realm: a
## second write for the same realm is refused by name, because a past the actor already
## spent must not be rewritable (ADR 0939).
##
## `perfection` is clamped into [0, 1]; an actor that never trained past its gate records
## `0.0`, which is a real answer rather than a missing one.
static func snapshot(actor: Actor, realm_id: StringName, perfection: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if realm_id == &"":
		return {"ok": false, "reason": R_EMPTY_REALM}
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if FoundationRecord.has_snapshot(record, realm_id):
		return {
			"ok": false,
			"reason": R_ALREADY_SNAPSHOTTED,
			"realm": String(realm_id),
			"existing": FoundationRecord.snapshot_for(record, realm_id),
		}
	record = FoundationRecord.with_snapshot(record, realm_id, perfection)
	actor.set_module_data(FoundationRecord.SLOT, record)
	return {
		"ok": true,
		"realm": String(realm_id),
		"perfection": FoundationRecord.snapshot_for(record, realm_id),
		"count": FoundationRecord.count(record),
		"aggregate": FoundationRecord.aggregate(record),
	}
