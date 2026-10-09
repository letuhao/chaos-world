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
const R_NO_SNAPSHOT := "no_snapshot"
const R_MEND_CAPPED := "mend_capped"
const R_SCAR_FLOORED := "already_ruined"
const R_BAD_AMOUNT := "bad_amount"

## No snapshot may be mended above this (BL-0951 / ADR 0939, S7): a poor foundation is a
## scar, never erased. 0.5 clears the authored floors through R13 and never R14+, so
## mending carries a run through the middle game while the deep ladder stays closed to
## whoever never trained. The avenue owns the STEP (its authored amount); the module owns
## this ceiling, and no avenue raises it.
const MEND_CAP := 0.5

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

## What one use of the FORBIDDEN LIFESPAN ART burns (BL-0951 / ADR 0939, S11): one year of
## the actor's own remaining life, at the authored ladder ratios — the same span the final
## attempt burns. The art is forbidden because its price is the cultivator's own years, the
## one currency no other avenue spends and none of them returns.
const FORBIDDEN_ART_PERIODS := 4380

## The mend one use of the forbidden art lands (BL-0951 / ADR 0939, S11). It is the largest
## single-avenue step — bigger than the elixir's 0.1, the secret realm's 0.15 and the rite's
## 0.2 — because it is paid in the one thing that does not come back. The module still owns
## the ceiling: no use lifts a snapshot above `MEND_CAP`.
const FORBIDDEN_ART_MEND := 0.25

## The forbidden art's named refusal (BL-0951 / ADR 0939, S11): a body already in the final
## band has nothing left to trade, so the art refuses BY NAME rather than burning the last
## of an already-spent life.
const R_FORBIDDEN_NO_YEARS := "no_years_left_to_burn"


## The carried aggregate the paths gate on: the mean of every snapshot, `0.0` when the
## actor has left no realm yet. This is the number a path's authored `min_foundation`
## compares against; the paths own the comparison, this module owns the arithmetic.
static func foundation(actor: Actor) -> float:
	if actor == null:
		return 0.0
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	# The karmic-memory floor (BL-0951 / ADR 0939, S14): a soul that has died before starts
	# with a little more than nothing, so the carried mean never reads BELOW what its deaths
	# earned it. A FLOOR and not an addition — a body whose own past already exceeds it is
	# unchanged, so a careful cultivator's deaths never inflate a good record.
	return maxf(FoundationRecord.aggregate(record), FoundationRecord.karmic(record))


## Seed the KARMIC-MEMORY floor (BL-0951 / ADR 0939, S14): a re-embodied soul carries a
## little foundation from the deaths it has already died, so its next body starts above
## nothing.
##
## ## Why the value is injected, never read here
##
## The floor's SOURCE is the soul's karmic memory, which lives in `destiny`'s fates — and
## `destiny` already depends on `foundation` (S12), so this module reading destiny would be
## a cycle the boundary gate forbids. So the app-layer rebirth path (the one layer that may
## read both) computes the value and calls THIS to set it: the module never learns where it
## came from, only that a floor was set.
##
## The value is clamped into `[0, 1]` by the record, and the answer names the floor and the
## resulting foundation so a caller can assert the raise landed. A non-positive value is
## refused by name: there is nothing to seed, and a silent no-op would read as a raise.
static func seed_karmic(actor: Actor, value: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if not is_finite(value) or value <= 0.0:
		return {"ok": false, "reason": R_BAD_AMOUNT}
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	record = FoundationRecord.with_karmic(record, value)
	actor.set_module_data(FoundationRecord.SLOT, record)
	return {
		"ok": true,
		"reason": "",
		"karmic": FoundationRecord.karmic(record),
		"foundation": foundation(actor),
	}


## The actor's karmic-memory floor, `0.0` when it has none (BL-0951 / ADR 0939, S14).
static func karmic(actor: Actor) -> float:
	if actor == null:
		return 0.0
	return FoundationRecord.karmic(
		FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	)


## The whole record as primitives, for a foundation READOUT (BL-0951 / ADR 0939, S15): the
## carried foundation, the karmic floor, the mended ceiling, the weakest scar, the final-band
## flag, and one row per realm the actor has LEFT, in LADDER order. `{}` for a null actor, so
## a screen can tell "no actor" from "an actor who has left nothing".
##
## Rows are ordered by the SHARED ladder, not by the snapshot map's key order, so two runs of
## the same record render identically — a readout that reshuffles is one a player cannot
## compare against itself.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	var ladder := RealmDefaults.ladder()
	var rows: Array = []
	for realm_id in (record["snapshots"] as Dictionary).keys():
		(
			rows
			. append(
				{
					"realm_id": String(realm_id),
					"perfection": FoundationRecord.snapshot_for(record, StringName(realm_id)),
					"index": ladder.index_of(StringName(realm_id)),
				}
			)
		)
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ai := int(a["index"])
			var bi := int(b["index"])
			if ai != bi:
				# An id the ladder does not hold sorts LAST, so a stale save cannot push a
				# real realm down the list; equal indices fall back to the id, for determinism.
				return (ai if ai >= 0 else 1 << 30) < (bi if bi >= 0 else 1 << 30)
			return String(a["realm_id"]) < String(b["realm_id"])
	)
	return {
		"foundation": foundation(actor),
		"karmic": FoundationRecord.karmic(record),
		"count": FoundationRecord.count(record),
		"mend_cap": MEND_CAP,
		"weakest": String(mend_target(actor)),
		"lastlight": AgeBandTable.band_for_actor(actor) == AgeBandTable.LASTLIGHT,
		"snapshots": rows,
	}


## The realm whose snapshot a mend should land on: the WEAKEST scar — the lowest snapshot
## strictly below `MEND_CAP` — or `&""` when there is none (BL-0951 / ADR 0939, S7). The
## item route mends through this because it names no realm: lifting the worst scar raises
## the carried mean the fastest, so the default is also the optimal play, and a targeted
## mend (a later avenue or screen) still calls [method mend] with its own realm.
static func mend_target(actor: Actor) -> StringName:
	if actor == null:
		return &""
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	var worst := &""
	var worst_value := MEND_CAP
	for id in (record.get("snapshots", {}) as Dictionary).keys():
		var value := float((record["snapshots"] as Dictionary)[id])
		if value < worst_value:
			worst_value = value
			worst = StringName(id)
	return worst


## One realm's snapshot as a number, or `-1.0` when the actor never left it. Avenues that
## name their own realm (the rite, a screen) read through this rather than the record;
## `-1.0` rather than `0.0` because zero is a REAL perfection and a reader cannot tell an
## unanswered question from a sloppy past if both are zero (the `SoulAge.age_years`
## convention, for the same reason).
static func snapshot_for(actor: Actor, realm_id: StringName) -> float:
	if actor == null or realm_id == &"":
		return -1.0
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if not FoundationRecord.has_snapshot(record, realm_id):
		return -1.0
	return FoundationRecord.snapshot_for(record, realm_id)


## Lower one realm's snapshot by up to `amount`, floored at `0.0` (BL-0951 / ADR 0939,
## S8): the heaven-defying rite's price for a lost gamble. A scarred past drags the
## carried mean down, which is what makes the gamble a gamble rather than a priced
## purchase — the avenue risks more than wealth, so it may also pay more (see the rite's
## own bounds). Scarring a `0.0` snapshot changes nothing and is refused as already
## ruined; every other refusal mirrors [method mend].
static func scar(
	actor: Actor, realm_id: StringName, amount: float, source: String = ""
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if realm_id == &"":
		return {"ok": false, "reason": R_EMPTY_REALM}
	if not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "reason": R_BAD_AMOUNT}
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if not FoundationRecord.has_snapshot(record, realm_id):
		return {"ok": false, "reason": R_NO_SNAPSHOT, "realm": String(realm_id)}
	var existing := FoundationRecord.snapshot_for(record, realm_id)
	if existing <= 0.0:
		return {
			"ok": false,
			"reason": R_SCAR_FLOORED,
			"realm": String(realm_id),
			"existing": existing,
		}
	var scarred := maxf(existing - amount, 0.0)
	record = FoundationRecord.with_snapshot(record, realm_id, scarred)
	actor.set_module_data(FoundationRecord.SLOT, record)
	return {
		"ok": true,
		"realm": String(realm_id),
		"before": existing,
		"after": scarred,
		"scarred": existing - scarred,
		"source": source,
		"aggregate": FoundationRecord.aggregate(record),
	}


## Mend one realm's snapshot by up to `amount`, never above `MEND_CAP` (BL-0951 /
## ADR 0939, S7). The avenue owns the STEP — its authored amount, priced by whatever the
## avenue costs — and this owns the ceiling: a sloppy past can be lifted toward 0.5 and
## never to perfection. `source` names the avenue that paid (the item id, the rite, the
## realm) and travels in the answer, so a later per-avenue accounting has something to
## key on.
##
## Named refusals, never a silent no-op: no actor, an empty realm, an unusable amount, a
## realm with no snapshot to mend, and a snapshot already at the cap are all different
## states and read differently.
static func mend(
	actor: Actor, realm_id: StringName, amount: float, source: String = ""
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if realm_id == &"":
		return {"ok": false, "reason": R_EMPTY_REALM}
	if not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "reason": R_BAD_AMOUNT}
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if not FoundationRecord.has_snapshot(record, realm_id):
		return {"ok": false, "reason": R_NO_SNAPSHOT, "realm": String(realm_id)}
	var existing := FoundationRecord.snapshot_for(record, realm_id)
	if existing >= MEND_CAP:
		return {
			"ok": false,
			"reason": R_MEND_CAPPED,
			"realm": String(realm_id),
			"existing": existing,
		}
	var lifted := minf(existing + amount, MEND_CAP)
	record = FoundationRecord.with_snapshot(record, realm_id, lifted)
	actor.set_module_data(FoundationRecord.SLOT, record)
	return {
		"ok": true,
		"realm": String(realm_id),
		"before": existing,
		"after": lifted,
		"mended": lifted - existing,
		"source": source,
		"aggregate": FoundationRecord.aggregate(record),
	}


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


## The forbidden lifespan art (BL-0951 / ADR 0939, S11): burn one year of the actor's OWN
## life to mend a scarred past realm. This is the avenue whose only subject is the record
## and the time currency, both of which this module owns, so it is the module's own verb —
## there is no other module whose subject it is.
##
## Answers `{"ok": true, "reason": "", "realm", "mended", "years"}` on success and
## `{"ok": false, "reason": <named>}` on every refusal, never a bare `{}`.
##
## ## The realm is named or defaulted
##
## The caller's `realm_id` if it named one, else the WEAKEST scar (`mend_target`) — the same
## default the elixir, the site and the sacrifice use, for the same reason.
##
## ## Bounded, priced, refusing by name
##
## The gift is [method mend], which caps at `MEND_CAP`; the price is
## `FORBIDDEN_ART_PERIODS` of life through [method spend_periods]. The band is read FIRST:
## an actor in the final band has no years to spare and is refused by name, so the art never
## burns the last of an already-spent life. A refusal costs nothing (ADR 0044) — nothing is
## written until every gate has passed.
static func forbidden_art(actor: Actor, realm_id: StringName = &"") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if AgeBandTable.band_for_actor(actor) == AgeBandTable.LASTLIGHT:
		return {"ok": false, "reason": R_FORBIDDEN_NO_YEARS}
	var target := realm_id
	if target == &"":
		target = mend_target(actor)
	if target == &"":
		return {"ok": false, "reason": R_NO_SNAPSHOT}
	var existing := snapshot_for(actor, target)
	if existing < 0.0:
		return {"ok": false, "reason": R_NO_SNAPSHOT, "realm": String(target)}
	if existing >= MEND_CAP:
		return {"ok": false, "reason": R_MEND_CAPPED, "realm": String(target)}
	var mended := mend(actor, target, FORBIDDEN_ART_MEND, "forbidden_lifespan_art")
	if not bool(mended.get("ok", false)):
		return mended
	var years := spend_periods(actor, FORBIDDEN_ART_PERIODS)
	return {
		"ok": true,
		"reason": "",
		"realm": String(target),
		"mended": mended,
		"years": years,
	}


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
