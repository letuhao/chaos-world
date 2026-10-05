class_name SectTeaching
extends RefCounted

## Transmission: how a doctrine gets from one member to another, and what that
## costs the one doing the transmitting (BL-0187, BL-0188).
##
## ## Fit is the ONLY thing this moves
##
## Fit is transmission — one of the three things an institution grants, alongside
## recognition and access (ADR 0084) — and it projects **zero** stat modifiers. It
## is a gate and nothing else, which is why `SectProjection` never reads it: a cap
## on a number that is a gate is what stops it becoming a currency, and
## comprehension is the one thing this repo says cannot be bought.
##
## Standing is **never** touched here. Not by a lesson, not by a refusal, not by the
## teacher being spent. The two halves of ADR 0064's split are separate facts and a
## module that spent the teacher's standing while teaching would have collapsed them
## into one number, which is precisely the spreadsheet that split exists to prevent.
## The facade publishes `standing_delta` on every teaching result so this is
## observable rather than merely documented.
##
## ## The cost is real and it is on the teacher
##
## A lesson spends `teach_tax` — the office's plus the doctrine's — out of the
## teacher's own `stamina` pool. Free and unlimited teaching would make disciples a
## resource faucet (BL-0188), so the price is authored on both halves and summed in
## `SectDoctrineDef.tax_for`. The **stamina** pool is named because it is the one
## core pool every actor in this repo has; the alternative — inventing a `teaching`
## pool in this module — would be a second resource system.
##
## ## `comprehension_floor` is read from BASE ALLOCATION ONLY
##
## `actor.stats.get_base(Stat.COMPREHENSION)`, never `derived`. ADR 0052/0054 pinned
## that deliberately: *"a technique can never satisfy its own requirement with the
## stats it grants."* Reading `derived` would let the bounded percent this module
## projects — the institution's own grant — fund the gate that measures whether the
## institution may teach, which is the exact smuggling `set_base` was rejected for.

## The refusal a teacher hands back. **Not** an authored constant: a doctrine names
## its own `refusals` (BL-0186) and the facade publishes whichever word the caller
## gave it, so the vocabulary lives in content and a panel never invents a wording.
const R_NOT_A_MEMBER := SectApi.NOT_A_MEMBER
const R_UNKNOWN_DOCTRINE := SectApi.UNKNOWN_DOCTRINE
const R_SAME_ACTOR := "same_actor"
const R_STUDENT_NOT_SWORN := "student_not_sworn"
const R_TEACHER_UNFIT := "teacher_unfit"
const R_COMPREHENSION_BELOW_FLOOR := "comprehension_below_floor"
const R_COMPREHENSION_ABOVE_SPAN := "comprehension_above_span"
const R_NOTHING_TO_TEACH := "nothing_to_teach"


## The fit `periods` sessions of this doctrine are worth: a pure rate multiplied by a
## count. **No roll** — a lesson that might not land is a gate that can satisfy
## itself, the same reason a succession is walked.
static func gain(doctrine: SectDoctrineDef, periods: int) -> int:
	return maxi(0, doctrine.fit_per_period * maxi(0, periods))


## Whether `teacher` is far enough along this doctrine to teach it at all. Fit and
## only fit: a member with perfect standing and no affinity for the doctrine cannot
## teach it, because teaching is transmission and transmission is a gate.
static func teacher_fits(teacher_ledger: Dictionary, doctrine: SectDoctrineDef) -> bool:
	return SectState.fit(teacher_ledger, doctrine.id) >= doctrine.floor_fit()


## Whether `student_ledger` may be taught this doctrine — the sect's own authored
## `min_purity`, which is the door and is separate from the doctrine's own affinity
## floor. Both halves are authored and neither derives from the other.
static func student_admitted(def: SectDef, student_ledger: Dictionary) -> bool:
	return def.teaches_at(SectState.fit(student_ledger, def.doctrine_id))


## Add fit to a ledger's `fit` map for `doctrine_id`, clamped at `FIT_CAP`. Written
## on the ledger rather than through `SectState`'s normalized copy, because the caller
## is holding a duplicate it is about to persist.
##
## A cap is what makes this a gate rather than a currency: a currency that
## accumulates is a thing to buy comprehension with (ADR 0084).
static func apply_fit(
	ledger: Dictionary, doctrine_id: StringName, points: int, periods: int
) -> int:
	var before := SectState.fit(ledger, doctrine_id)
	var after := clampi(before + points * maxi(0, periods), 0, SectState.FIT_CAP)
	var fit_map: Dictionary = ledger["fit"]
	if after > 0:
		fit_map[String(doctrine_id)] = after
	else:
		fit_map.erase(String(doctrine_id))
	return after - before


## What one session costs the teacher: the office's authored `teach_tax` plus the
## doctrine's own, summed in one place so a screen renders one number rather than
## re-deriving a sum.
static func tax_for(doctrine: SectDoctrineDef, position: SectPositionDef) -> float:
	return doctrine.tax_for(position)


## Whether the teacher can pay `tax`. A teacher with no pool at all has nothing to
## spend, which reads the same as a teacher who has spent everything — "no teaching
## fund" and "an empty one" are the same answer, exactly as `SectFounding.funds`
## treats the founding pool.
static func can_pay(teacher: Actor, tax: float) -> bool:
	if tax <= 0.0:
		return true
	if teacher == null:
		return false
	var pool := teacher.resource(&"stamina")
	return pool != null and pool.current >= tax


## Take `tax` from the teacher. No-op rather than an error when there is nothing to
## take: the caller has already refused, and a settlement that could empty a pool it
## never entered is a bug in the caller rather than a player outcome.
static func charge(teacher: Actor, tax: float) -> void:
	if teacher == null or tax <= 0.0:
		return
	var pool := teacher.resource(&"stamina")
	if pool == null:
		return
	pool.change(-tax)
