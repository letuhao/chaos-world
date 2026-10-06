class_name RealmLifespan
extends Resource

## The authored per-REALM-TIER lifespan multiplier table (ADR 0169).
##
## One multiplier per `RealmDef.tier`, a decade ladder: Mortal 1.0, Spirit 10.0,
## Immortal 100.0, Transcendent 1000.0. `RaceDef.lifespan` stays exactly as
## authored — the MORTAL-TIER BASELINE of a body — and an actor's lifespan is
## `def.lifespan x multiplier_for(realm.tier)`.
##
## ## Why a second table and not a row on `realm_power_table.tres`
##
## Different questions, different units, different guards. `RealmPowerTable` is
## keyed by realm ID because a realm's strength is that realm's own number
## (ADR 0050). A lifespan is a function of the BAND, not of the realm: R1 and R9
## are both mortal bodies, so keying by id would author 30 cells to say 1.0 nine
## times. Keyed by `tier` the same way `TechniquePolicy.UNIVERSAL_SLOTS_BY_TIER`
## is, so a realm inserted inside a band inherits that band's number — which is
## the correct answer, and is the anti-shift rule that cost this repo a full table
## once already.
##
## ## Why it must never share a constant, a recipe or a fixture with the RATE
##
## `RealmRate.RATE_STEP` is `1.02` and the whole 30-realm ladder is worth
## `RATE_STEP^29 = 1.776` — a GAIN, under 2x. This table spans 1000x. Reading a
## shared exponential as a magnitude is the exact failure `AGENTS.md:141`
## records: it is what once made a single breakthrough worth more than every
## other investment in the game put together (ADR 0050/0066). The two are
## different kinds of number — days is a magnitude, days-per-day is a rate — and
## combining them is dimensionally void. `tests/core/test_realm_lifespan_table.gd`
## pins both invariances so neither can reach the other.
##
## ## Why it never reads a WORLD TIER
##
## `WorldTierDef.time_flow_min/max` (`world_tier_def.gd:14-15`) is an authored
## ~100x ladder whose only loader in the tree is a test, and the tier bands
## 1-9/10-18/19-27/28-30 coincide with this one's BY COINCIDENCE. Two
## vocabularies that agree accidentally are what gets merged by accident, so this
## file reads `RealmDef.tier` and nothing else: no `world` field, no
## `WorldState`, no `InsideWorld`. That negative is ADR 0169's, and it is
## enforced by a source guard rather than left to review.
##
## ## Format note
##
## Godot's text resource parser accepts no comment line inside `[resource]` —
## one silently swallows the property after it — so the reading convention lives
## here, in the script: **365 days per year is a reading convention for THIS
## table only**. The calendar and the persistence schema for an age field are
## ADR 0169's deferred half and are not decided by these four numbers.

## Neutral is 1.0, NOT 0.0. A missing row must leave a body exactly as authored
## rather than scale its life to nothing — the same fallback, for the same
## reason, as `realm_power_table.gd:32`. It is also the row Mortal carries, so
## the fallback and the baseline are the same number and an unauthored fifth
## tier degrades to "a mortal body" rather than to a corpse.
const NEUTRAL := 1.0

## `actor.components` slot holding the body plan, as published by the `race`
## module under `RaceProjection.DEF_COMPONENT`. Spelled as the literal id rather
## than as `RaceProjection.DEF_COMPONENT` because `core` may not name a module
## class at all — see `_baseline_of` below for the direction this edge runs in.
const RACE_DEF_COMPONENT := &"race_def"

## The tiers this table authors, as written. Enumerated rather than derived so a
## fifth tier is a new AUTHORED ROW, not a formula the table grew: `tier` is not
## a ladder position, and a curve from it is what ADR 0042/0050 deleted.
const AUTHORED_TIERS: Array[int] = [1, 2, 3, 4]

## The mortal tier, as `RealmDefaults` writes it (`MORTAL := 1`). Named here
## rather than read there: ANY `RealmDefaults` member access compiles that file,
## whose `LIFESPAN` preload points back at this file's `.tres`, which is the
## compile cycle that fails the parse with "Cyclic reference". An actor on no
## known realm is a mortal body, and the mortal row is the neutral one by the
## test's own pin, so the fallback and the baseline stay one number.
const FALLBACK_TIER := 1

## The authored tier multiplier, keyed by `RealmDef.tier`. Loaded once by
## `RealmDefaults.LIFESPAN` beside `POWER` — a plain preload on the other side.
## The edge runs ONE way only: this file must never name `RealmDefaults` back,
## or the `.gd -> RealmDefaults (preload .tres) -> script .gd` cycle fails the
## parse. Singleton reads go through `_authored_table()` below, which resolves
## the same `.tres` at runtime instead of at compile time
## (`time_ladder.gd:109-113` records why the two directions differ).
@export var multipliers: Dictionary = {}


## The multiplier for a realm TIER, or `NEUTRAL` for a tier nobody authored.
##
## Keyed by tier rather than by `RealmDef.index` for the anti-shift reason
## `RealmDefaults._all():73-74` already records for power: a realm inserted
## inside a band must inherit that band's number, and an index key would slide
## every realm below the insertion onto the wrong one. A fifth tier resolves to
## `NEUTRAL`, which is a reviewable answer (the test pins it) rather than a
## formula's guess.
func multiplier_for(tier: int) -> float:
	return float(multipliers.get(tier, NEUTRAL))


## The EFFECTIVE lifespan of a body whose baseline is `baseline_days` while it
## stands at `tier`, in days.
##
## **This is the one multiplication in the whole repository**, and it lives here
## in `core/` for three reasons that are really one reason:
##
##   1. ADR 0169 says so, and `core` is a LAYER rather than a module
##      (`LAYER_DEPS["core"] == {"core", "contracts"}`, `tools/arch/rules.py:29`),
##      so a provider reading it declares ZERO new arch edges.
##   2. A second site is how `def.lifespan x 10.0` would end up typed into a
##      provider — numerically identical to this one on day one and free to
##      drift on day two. That is the ADR 0116 mutation in miniature (403
##      passed / 3 failed, only the structural pins firing), and it is why
##      `tests/core/test_realm_lifespan_table.gd` reads SOURCE.
##   3. `RealmScaling.highest_realm` is already core's one answer to "which
##      realm does this actor stand at", so the read has a home and the tier
##      cannot be resolved two different ways in two different modules.
##
## The result is one number, in days, comparable against an elapsed age and an
## authored retreat cost. No consumer has to know a tier exists.
##
## A null body reads `NEUTRAL`: a caller with no baseline has no lifespan to
## scale, and zero would be a claim about a body that does not exist.
func effective_days(baseline_days: float, tier: int) -> float:
	return maxf(0.0, baseline_days) * multiplier_for(tier)


## The SAME read against an actor, so no caller has to resolve a realm to ask how
## long a body lives.
##
## `null` is an actor standing on no realm the ladder knows, or an actor with no
## path at all — both are a MORTAL body, because the mortal row is the neutral one,
## and every authored race `.tres` is written as a mortal-tier baseline
## (emberblood 18,250 d, commonborn 36,500, stoneborn 54,000, tidecaller 58,400).
##
## **The realm comes from `RealmScaling.highest_realm` and from nothing else.**
## That is core's one answer to "which realm does this actor stand at", read
## through the shared ladder rather than a second tier lookup, so the tier cannot
## be resolved two different ways in two different modules (the ADR 0026 trap).
##
## It reads no world tier, no `WorldState` and no `InsideWorld`, and this is the
## one function ADR 0169's negative is really about. Those band numbers coincide
## with the realm tiers by accident, and an accidental coincidence is what gets
## merged by accident — the dimensionally-void conversion `days x (days per day)`
## belongs to the clock that owns both units (ADR 0173), never to either table.
## `tests/core/test_realm_lifespan_table.gd` refuses those reads in SOURCE.
static func effective_lifespan_for(actor: Actor) -> float:
	var realm := RealmScaling.highest_realm(actor)
	var tier := FALLBACK_TIER if realm == null else realm.tier
	var baseline := 0.0
	var def := actor.component(RACE_DEF_COMPONENT) as RaceDef
	if def != null:
		baseline = maxf(0.0, def.lifespan)
	var bonus = actor.get(&"lifespan_bonus_days")
	var bonus_days := 0.0
	if (bonus is int or bonus is float) and not (bonus is bool):
		bonus_days = maxf(0.0, float(bonus))
	return (
		maxf(0.0, baseline) * float(_authored_table().multipliers.get(tier, NEUTRAL)) + bonus_days
	)


## The authored table behind the static reads: the same `.tres`
## `RealmDefaults.LIFESPAN` preloads, resolved here with `load()` at runtime
## rather than at compile time. `load()` returns the engine's cached resource,
## so this is the same instance the preload publishes — one table, two doors,
## and no cycle. (Cycle repair: naming `RealmDefaults` from this file closed a
## `.gd -> RealmDefaults -> .tres -> .gd` loop the parser refuses.)
static func _authored_table() -> RealmLifespan:
	return load("res://src/core/realm_lifespan_table.tres") as RealmLifespan


## The authored MORTAL-TIER BASELINE in days, or 0.0 when no body plan is attached.
##
## **A private read of the body plan, not a call into the `race` module's facade.**
## The facade is a `core -> modules/race` edge and `LAYER_DEPS["core"]` is
## `{"core", "contracts"}` (`tools/arch/rules.py:29-33`), so core may not reach
## upward for a feature module at all. The dependency is written the other way —
## `core` names the COMPONENT SLOT id that `race` publishes under
## (`RaceProjection.DEF_COMPONENT`), the module fills it at conception, and core
## reads the slot by name without importing anything. `core/actor.gd` already
## restores a body plan from a save the same way, for the same reason.
func _baseline_of(actor: Actor) -> float:
	if actor == null:
		return 0.0
	var def := actor.component(RACE_DEF_COMPONENT) as RaceDef
	if def == null:
		return 0.0
	return maxf(0.0, def.lifespan)


## The elixir's lifespan bonus in days, or `0.0` when the body carries none.
##
## **A private read of the body fact, not a call into a module's facade.** The bonus
## is a core field on `Actor` (`lifespan_bonus_days`), written by the items module
## through the actor's own API. Core reads it directly for the same one-way-edge
## reason `_baseline_of` reads the body plan: `core` may not name a module class,
## and the field is core's own.
func _bonus_of(actor: Actor) -> float:
	if actor == null:
		return 0.0
	var bonus: Variant = actor.get(&"lifespan_bonus_days")
	if (bonus is int or bonus is float) and not (bonus is bool):
		return maxf(0.0, float(bonus))
	return 0.0


## Whether `actor`'s body has already reached the lifespan it was born with.
##
## The guard ADR 0270 §2 names: a lifespan-extending elixir has NO EFFECT on a body
## already past its span. This is the one predicate that answers that question from
## `core/`, so the items module does not have to re-derive the calendar or the age
## read. `SoulAge.has_expired` is the richer answer (it names a reason for every
## missing seam); this is the simpler one the item use path needs, and it refuses
## `false` on every missing seam rather than inventing an answer.
static func is_past_span(actor: Actor) -> bool:
	if actor == null:
		return false
	var age_years: Variant = actor.get(&"age_years")
	if not (age_years is float) or age_years < 0.0:
		return false
	var realm := RealmScaling.highest_realm(actor)
	var tier := FALLBACK_TIER if realm == null else realm.tier
	var baseline := 0.0
	var def := actor.component(RACE_DEF_COMPONENT) as RaceDef
	if def != null:
		baseline = maxf(0.0, def.lifespan)
	var bonus: Variant = actor.get(&"lifespan_bonus_days")
	var bonus_days := 0.0
	if (bonus is int or bonus is float) and not (bonus is bool):
		bonus_days = maxf(0.0, float(bonus))
	var lifespan := (
		maxf(0.0, baseline) * float(_authored_table().multipliers.get(tier, NEUTRAL)) + bonus_days
	)
	if lifespan <= 0.0:
		return false
	var year_ratio: int = TimeLadder.ratio_for(&"year")
	var day_ratio: int = TimeLadder.ratio_for(&"day")
	if year_ratio < 1 or day_ratio < 1:
		return false
	return (float(age_years) * float(year_ratio / day_ratio)) >= lifespan
