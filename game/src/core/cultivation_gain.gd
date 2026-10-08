class_name CultivationGain
extends RefCounted

## How much one unit of cultivation work is WORTH right now, beyond the realm's own rate
## (ADR 0214; ADR 0926 extends it with the actor's own rate).
##
## ## This is a RATE, and that is the whole point
##
## The gain expression in all three paths is one multiplication, then one call:
##
## ```
## gain = amount * RealmRate.factor(realm_id) * (1.0 + meridians.get_flow_bonus())
## gain = CultivationGain.scale_gain(actor, gain)
## ```
##
## `scale_gain` is what this file supplies, and it is TWO bounded factors MULTIPLIED:
## the PLACE's density and the ACTOR's own rate stat. Both multiply the GAIN TERM ONLY:
## never `amount` (a price), never a reservoir's capacity, never a `magnitude_unit` stat.
## Anything that multiplies `gain` is a rate; anything that adds to `amount` is not, and
## adding to `amount` would make a dense place cheap rather than rich.
##
## ## Why it lives in `core` and not in `domain`
##
## `domain` is a module, and a module may reach another only through its facade
## (`tools/arch/rules.py`). `qi_cultivation` declares `contracts` + `core` + `destiny` +
## `items` + `race`; `body_cultivation` and `mind_cultivation` likewise do NOT declare
## `domain`, and adding it to three registry entries to carry one float would be the
## cross-module edge this repo exists to prevent. `core` is a LAYER, not a module
## (`LAYER_DEPS["core"] == {"core", "contracts"}`), so holding the curve here creates
## ZERO new edges — the same argument `core/realm_rate.gd` already makes for itself.
##
## The PLACE side is written by the composition root (`DomainBoot._apply_zones`, from the
## zones `domain` owns) and the GAIN side is read by the three cultivation paths, and the
## two halves meet only as one number on an `Actor`. That is the same plain-data seam
## `EnvironmentField.GEAR_TAGS_KEY` already is. The ACTOR's own rate is not published at
## all: it is a derived stat, read where it lives.
##
## ## It is NOT `inside_world_qi_density`, and neither may read the other
##
## `core/inside_world_provider.gd:15` publishes `inside_world_qi_density`: that is the
## actor's PERSONAL inner-world reservoir (ADR 0018). This is a PLACE's ambient richness.
## They are separate numbers with separate homes — reading one from the other would make a
## cultivator's cultivation speed scale off their own private world, which is the
## "magnitude riding a rate" failure in a new place.
##
## ## Both bounds are `RATE_STEP`-safe by construction
##
## `RealmRate.RATE_STEP` is `1.02` and `tests/core/test_realm_rate.gd` computes the
## authored ceiling from the three `progress_required` ladders — qi's deepest transition
## at `2900/2800` ≈ **1.0357**. Neither factor is realm-DEPENDENT: the density is bounded
## by [constant MAX_DEVIATION] (the widest single-place swing is `1.25x`) and the actor's
## rate by [method rate_ceiling] — the ladder's ENTIRE span, DERIVED from the shared
## curve rather than typed, so one actor's speed can never be worth the whole climb.
## Neither is applied to `RealmRate.factor` itself, so `RATE_STEP` remains the only
## per-realm number and no place and no wardrobe can re-price a realm. A 2x multiplier
## would let a place deliver a breakthrough's work for free; a bounded constant is a
## decision a player makes by standing somewhere or equipping something, not a ladder
## they skip.
##
## ## Never SUMMED, always composed
##
## `1.25` in a dense room, `1.12` from the actor's own rate and `1.25` from a meridian
## bonus are three factors multiplied, not `1.25 + 1.12 + 1.25`. Summing rate factors is
## what once made a single breakthrough worth more than everything else combined
## (AGENTS.md §Realm scale), and it is the specific shape ADR 0214 refuses.

## Neutral: a room with no zone, a run with no weather, an actor with nothing published.
## The multiplier is `1.0` here, so every existing path is unchanged until a place
## authors a density.
const NEUTRAL := 1.0

## How far either side of `1.0` an authored place may push, and the reason the field is a
## bounded MULTIPLIER rather than an open float: `|QI_DENSITY - 1.0| <= 0.25`, so a dense
## place is at most a quarter faster and a thin one at most a quarter slower.
##
## Read by the tests below `QI_DENSITY_MAX` / `QI_DENSITY_MIN`; authored per zone as
## `qi_density`, clamped on the way in rather than refused so a content typo degrades to
## the authored ceiling instead of deleting a reward.
const MAX_DEVIATION := 0.25

## The closed authoring band: a room with no zone authors `1.0` and is invisible to this
## rule. A `qi_density` of 1.0 means "this place is neither rich nor thin", NOT "this
## place has no density".
const QI_DENSITY_MIN := 1.0 - MAX_DEVIATION
const QI_DENSITY_MAX := 1.0 + MAX_DEVIATION

## The marker slot a place publishes its ambient density under. One key, one float —
## published rather than passed as a parameter so all three cultivation paths read ONE
## shared number and a body cultivator cannot get a private cultivation-speed multiplier
## the gate arithmetic never sees (ADR 0214).
const DENSITY_KEY := &"place_qi_density"

## The floor of the actor's own rate read. A rate of zero would make every sitting worth
## nothing and stall the path silently, which is the failure a floor exists to refuse; a
## debuff may slow cultivation to a quarter, never to a dead stop.
const RATE_FLOOR := 0.25


## The authored density, clamped into [constant QI_DENSITY_MIN], [constant
## QI_DENSITY_MAX]].
##
## Clamping rather than refusing is the honest degradation: a `.tres` authoring `3.0` gets
## the ceiling the ADR names, and the content audit reports the out-of-band value. A
## refusal would leave the place with a NEUTRAL `1.0` and silently delete a reward.
static func clamp_density(density: float) -> float:
	if not is_finite(density):
		return NEUTRAL
	return clampf(density, QI_DENSITY_MIN, QI_DENSITY_MAX)


## Publish `actor`'s ambient place density and answer the value actually applied.
##
## `NEUTRAL` is written rather than skipped, because an actor walking out of a dense room
## and into a plain one must not keep the dense room's number through a key nobody cleared.
##
## The value is stored in a DICTIONARY, not as a bare float in `module_data`.
## `set_module_data` is typed `(id, data: Dictionary)`, so publishing the float directly was a
## hard type error — GDScript attributes it upward, so the parse failure surfaced in some
## unrelated suite as "Could not resolve class LootContentTables" and a reader had no path back
## to this line. It is the same shape as the world-polity stamp, which is why that one is now
## Dictionary-wrapped too: `module_data` is a dictionary OF dictionaries, and every entry in it
## must be one.
static func publish_density(actor: Actor, density: float) -> float:
	if actor == null:
		return NEUTRAL
	var applied := clamp_density(density)
	actor.set_module_data(DENSITY_KEY, {"density": applied})
	return applied


## The ambient place density published on `actor`, or [constant NEUTRAL].
##
## Reads the `density` field of the stored dictionary. A body carrying the OLD bare-float shape
## — written before `publish_density` was corrected, and readable from an in-memory actor
## mid-session — answers [constant NEUTRAL] rather than raising, because a save or a carry that
## trips over one stale key costs a player their run.
static func density_of(actor: Actor) -> float:
	if actor == null:
		return NEUTRAL
	var slot := actor.get_module_data(DENSITY_KEY)
	var value = slot.get("density") if (slot is Dictionary) else slot
	if not (value is float or value is int):
		return NEUTRAL
	return clamp_density(float(value))


## The ceiling of the actor's own rate read: the ladder's ENTIRE rate span
## (`RealmRate.rate_span()`), so one actor's speed can never be worth the whole climb.
##
## DERIVED from the shared curve rather than typed, so a retune of the ladder moves it —
## the discipline `tests/core/test_realm_rate.gd` already enforces on every other rate
## bound. It is a ceiling on the READ, not on the derivation: the stat's own value is
## still what it is, and no shipped actor reaches the ceiling (the authored `aptitude`
## scale tops out near `13`, so the derived rate tops out near `1.26`).
static func rate_ceiling() -> float:
	return RealmRate.rate_span()


## `actor`'s own cultivation rate, clamped into [constant RATE_FLOOR], [method
## rate_ceiling].
##
## `Stat.CULTIVATION_RATE` is derived in `core` (`actor_stats.gd`: `1.0 + aptitude *
## 0.02`) and granted by item options, bloodlines, sets, fates and consumables as PERCENT
## modifiers — dozens of authored grants that were DECORATIVE until this read existed
## (BL-0931). An actor with no derivation at all (a bare `ActorStats` whose core provider
## was never mounted) answers [constant NEUTRAL]: `derived()` returns `0.0` for an id
## nobody published, and reads-absent-instead-of-0 is a different fact from a rate of
## zero, which is why the check is `has()` rather than a comparison.
static func rate_of(actor: Actor) -> float:
	if actor == null:
		return NEUTRAL
	if not actor.stats.derived_all().has(Stat.CULTIVATION_RATE):
		return NEUTRAL
	return clampf(actor.stats.derived(Stat.CULTIVATION_RATE), RATE_FLOOR, rate_ceiling())


## `gain` multiplied by `actor`'s gain-side factors — the WHOLE of the rule, and the one
## call each of the three paths makes.
##
## Two factors, MULTIPLIED: the ambient place density ([method density_of]) and the
## actor's own rate ([method rate_of]). Applied to the gain TERM only, and never summed
## with `RealmRate.factor` or the meridian flow bonus. `amount` is untouched: a dense
## place makes one unit of work worth more, it does not make the work cheaper to buy.
static func scale_gain(actor: Actor, gain: float) -> float:
	return gain * density_of(actor) * rate_of(actor)
