class_name SoulAge
extends RefCounted

## ADR 0258 §5: how old a body is, and whether it has outlived the lifespan it was born
## with. A companion to [method SoulDeath.resolve], not a second end-of-life path — it answers
## one question ("has this body's lifespan elapsed?") and the resolver decides what an answer
## means.
##
## ## Why a companion file and not more of `soul_death.gd`
##
## `soul_death.gd` is already past `LINE_BUDGET = 400`, and ADR 0190 records the same move for
## `SoulArrivalMarks` for the same reason: the rule is `app/`'s, `app/` is a LAYER rather than a
## module (`LAYER_DEPS["app"] == {"*"}`, `tools/arch/rules.py`), so this costs ZERO new arch
## edges and is not a new module.
##
## ## The three reads, and what an ANSWERABLE seam would be
##
##   1. `actor.get(&"age_years")` — the body field ADR 0258 §2 names. Read through `Object.get`
##      rather than as `actor.age_years`, because a member `Actor` does not declare is a COMPILE
##      error when the parameter is statically typed, and this file has to compile on a tree where
##      that field has not landed. Dynamic resolution is what makes the guard below possible at
##      all: without it there would be no way to distinguish "the field is absent" from "the field
##      is zero", and those two answers have opposite consequences.
##   2. `RealmDefaults.LIFESPAN.effective_lifespan_for(actor)` — the published read, in DAYS
##      (`realm_lifespan_table.gd:134`), scaling `RaceDef.lifespan` by the realm TIER's
##      multiplier.
##   3. `SaveApi.store_for(WorldClock.WORLD_KEY).periods()` — ADR 0259's count of whole world
##      periods. `WorldClock` is a `core` class and the clock is the ONLY thing allowed to
##      advance, so this ASKS and never advances.
##
## ## EVERY MISSING SEAM IS A NAMED REFUSAL, AND NONE OF THEM IS ZERO
##
## The failure this file exists to prevent: an absent read that falls back to `0` or to a large
## default. Zero periods means "nobody is old, nobody dies" — a whole feature silently inert.
## A large default means "every hero in the game is instantly over their lifespan" — a
## guard that kills every actor on the first frame. Both are worse than a refusal, so every
## missing piece answers [constant REASON_NO_AGE_FIELD] / [constant REASON_NO_CLOCK] /
## [constant REASON_NO_LIFESPAN] / [constant REASON_NO_CALENDAR] and reports `expired: false`.
## The guard is loud AND safe, in that order.
##
## ## An unwired age field is SAFE HERE, and the reason is the resolver's order
##
## ADR 0258 §2's field defaults to a newborn's age and is never negative, so a tree whose field
## defaults high is the one hazard, and it is refused above rather than believed. `is_dead`
## short-circuits on this same answer (`SoulDeath.is_dead`), so an absent field costs a field
## probe and expires nobody — and a wired field is never confused with an absent one, because
## the probe is what asks.

## The body ended because something hurt it. The whole of the pre-ADR-0258 behaviour.
const CAUSE_DEATH := &"death"

## The body ended because it reached the lifespan it was born with (ADR 0258 §5).
const CAUSE_AGE := &"age"

## No actor to age. `SoulDeath._refuse` carries it too, so the cause vocabulary is total.
const REASON_NO_ACTOR := "no_actor"

## **`Actor` carries no `age_years` member.** The refusal a tree without ADR 0258 §2 lands on,
## and the one that must never be read as "infinitely old".
const REASON_NO_AGE_FIELD := "no_age_field"

## **No `WorldClock` is installed into `SaveApi` under `world_time`.** Also never read as zero
## age: a clock that has not been wired has not told us how old anybody is, and inventing that
## answer in either direction is the hazard above.
const REASON_NO_CLOCK := "no_world_clock"

## The lifespan read as zero: no body plan attached, or no realm the ladder knows. `RealmLifespan`
## answers `0.0` for both, and comparing an age against a zero lifespan would expire every body
## in the game.
const REASON_NO_LIFESPAN := "no_lifespan"

## The `TimeLadder` authors no `day` or no `year` ratio, so periods cannot be compared against a
## lifespan authored in days without inventing a calendar. Refused rather than assumed.
const REASON_NO_CALENDAR := "no_calendar_ratio"

## The authored field ADR 0258 §2 names, read DYNAMICALLY. Spelled once so a rename is one edit.
const AGE_FIELD := &"age_years"

## The `TimeLadder` magnitudes this file converts between. Named, never a literal, because a
## second copy of a ratio is what ADR 0173 refuses.
const DAY := &"day"
const YEAR := &"year"


## How old `actor`'s body is in years, or `-1.0` when it carries no age field.
##
## **`Object.get`, never `actor.age_years`.** `Actor` is a statically-typed parameter and a
## member it does not declare is a compile error, so a direct read cannot be written before the
## field lands — and writing one anyway would stop the whole project parsing. `-1.0` rather than
## `0.0` because zero is a REAL age and a reader cannot tell an unanswered question from an
## answered one if both are zero.
static func age_years(actor: Actor) -> float:
	if actor == null or not (AGE_FIELD in actor):
		return -1.0
	var raw = actor.get(AGE_FIELD)
	if (raw is int or raw is float) and not (raw is bool):
		return maxf(0.0, float(raw))
	return -1.0


## The lifespan `actor`'s body was born with, in DAYS, or `0.0` when it has none.
##
## Read through `RealmDefaults.LIFESPAN`, which is the one preloaded instance of the authored
## table — the same instance `race/provider.gd` contributes from, so an age and a lifespan are
## never resolved against two different tables.
static func lifespan_days(actor: Actor) -> float:
	if actor == null:
		return 0.0
	return maxf(0.0, RealmDefaults.LIFESPAN.effective_lifespan_for(actor))


## How many whole periods the world has advanced, or `-1` when no clock is answering.
##
## `SaveApi.store_for` is the only door into it: `item_workbench_app._ready` installs the live
## `WorldClock` AS the `world_time` store, so asking the store is asking the clock and no
## second reference to it exists here. `-1`, never `0` — a clock that has not been wired has not
## said the world is new.
static func world_periods() -> int:
	var store = SaveApi.store_for(WorldClock.WORLD_KEY)
	if store == null:
		return -1
	if not store.has_method(&"periods"):
		return -1
	var raw = store.call(&"periods")
	if (raw is int or raw is float) and not (raw is bool):
		return maxi(0, int(raw))
	return -1


## Whether `actor`'s body has reached its lifespan. The additive predicate a caller asks before
## it asks whether the body is dead, so the two answers cannot be confused: **age ends a body
## at full health, and `is_dead` would never see it.**
##
## Always the answer of [method answer_for] rather than a re-derivation, so a caller asking the
## question and a resolver acting on it cannot disagree about the same body.
static func has_expired(actor: Actor) -> bool:
	return bool(answer_for(actor).get("expired", false))


## The whole answer as primitives: `{ok, reason, expired, age_years, age_days, lifespan_days,
## periods, days_per_year}`.
##
## **`answer_for`, never `read`.** `Object.read` already exists on every `RefCounted` — the file
## reader — so a method of that name is SHADOWED rather than shadowing, and GDScript refuses the
## call outright. Spelled out rather than worked around, for the same reason ADR 0127 names
## `read_ledger` instead of `load`.
##
## `ok` is false on every refusal and `expired` is false on every refusal — the refusal is LOUD
## (a named `reason` a caller can log) and SAFE (it expires nobody). Those are different
## requirements and this shape is what lets both hold at once.
##
## ## The comparison is in DAYS, and the calendar is DERIVED from the ladder
##
## The lifespan is authored in days and `age_years` is named in years, so something has to
## bridge them. `TimeLadder` is the only converter (ADR 0173) and every ratio is measured from
## the BASE, so days-per-year is `ratio_for(&"year") / ratio_for(&"day")` = 4380/12 = 365 — the
## same reading convention `realm_lifespan_table.gd:46` documents for that table, derived rather
## than typed in a second time. Integer division throughout: a period count must be exact
## (`time_ladder.gd:96`).
##
## ## REACHING the lifespan ends the body, so the comparison is `>=`
##
## ADR 0258 §5 says "reaching the lifespan", not "passing it". A body that is exactly as old as
## it was born to live has reached it.
static func answer_for(actor: Actor) -> Dictionary:
	var answer := {
		"ok": false,
		"reason": "",
		"expired": false,
		"age_years": -1.0,
		"age_days": 0.0,
		"lifespan_days": 0.0,
		"periods": -1,
		"days_per_year": 0,
	}
	if actor == null:
		answer["reason"] = REASON_NO_ACTOR
		return answer
	var years := age_years(actor)
	if years < 0.0:
		answer["reason"] = REASON_NO_AGE_FIELD
		return answer
	answer["age_years"] = years
	var days_per_year := days_per_year()
	if days_per_year <= 0:
		answer["reason"] = REASON_NO_CALENDAR
		return answer
	answer["days_per_year"] = days_per_year
	var periods := world_periods()
	if periods < 0:
		answer["reason"] = REASON_NO_CLOCK
		return answer
	answer["periods"] = periods
	var lifespan := lifespan_days(actor)
	if lifespan <= 0.0:
		answer["reason"] = REASON_NO_LIFESPAN
		return answer
	answer["lifespan_days"] = lifespan
	answer["age_days"] = float(years * days_per_year)
	answer["ok"] = true
	answer["expired"] = answer["age_days"] >= lifespan
	return answer


## Whole DAYS in one authored YEAR, derived from the ladder's own ratios, or `0` when either
## magnitude is unauthored.
##
## ## Two divisions and no constant, because `TimeLadder` measures every ratio from the BASE
##
## The ladder is deliberately NOT self-consistent — a 30-day month inside a 365-day year is what
## a calendar is (ADR 0173) — so chaining `year` to `day` is wrong and reading the ratio off one
## row is the whole answer. Dividing the two authored rows is what makes a retune of either one
## move this with it rather than leaving a 365 lying beside it.
static func days_per_year() -> int:
	var year_ratio := TimeLadder.ratio_for(YEAR)
	var day_ratio := TimeLadder.ratio_for(DAY)
	if year_ratio < 1 or day_ratio < 1:
		return 0
	return year_ratio / day_ratio
