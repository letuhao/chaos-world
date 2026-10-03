class_name RealmRate
extends RefCounted

## What one unit of a realm's training is worth, as ONE bounded per-realm number
## shared by all three cultivation paths (ADR 0066).
##
## ## It is a RATE, and that is the whole point
##
## The question it answers is "how much does a unit of this realm's training
## count", never "how strong is a thing from this realm". Those are different
## kinds of number. A MAGNITUDE — health, damage, capacity — wants a visible
## per-realm authored relationship, and each path already owns its own where it
## belongs, none of them here:
##
##   - `RealmScaling` (core) scales the SHARED combat stats by the realm's
##     strength. The path providers contribute those ids ADDITIVELY on top of
##     that baseline (ADR 0026), so multiplying by the realm's strength here as
##     well would count the same realm twice.
##   - `QiRealmSeed.dantian_capacity`, `BodyRealmSeed.integrity_maximum` and
##     `MindRealmSeed.sea_capacity` are the paths' own reservoir magnitudes,
##     authored per realm and applied once by each `*Training.synchronize`.
##
## So `RealmRate` never reads, derives or tracks a magnitude. It does not open
## `core/realm_power_table.tres`; `RealmScaling` reads the authored
## `RealmDef.power` and nothing else. That split is machine-checked, not a
## comment: `tests/core/test_realm_rate.gd` asserts `factor` is unchanged when a
## `RealmDef.power` changes. The curve returns `1.02^29 = 1.776`; a rate is a
## gain, not a magnitude (ADR 0050).
##
## ## The shape
##
## `factor(i) = RATE_STEP^i`, where `i` is the realm's ORDINAL on the shared
## ladder (0 at Qi Refining, 29 at Primordial Origin) — the same ordinal as
## `RealmDef.index`, read through `RealmDefaults.ladder().index_of` so the
## ordinal and the ladder can never drift apart. It is an ordinal: never a tier,
## never a stage, never a ladder index that means something else.
##
## Compounding per realm rather than stepping per tier is deliberate. A tier step
## makes the first realm of a new tier CHEAPER, because the price of a
## breakthrough is the authored work budget divided by the rate and the budget
## does not step at the same moment. Per realm, the rate rises strictly and the
## price of a breakthrough rises strictly — see
## `tests/core/test_realm_rate.gd`, which pins both.
##
## `RATE_STEP` is the only balance number here and it is authored, not derived:
## it must stay at or below the smallest per-realm step in the AUTHORED work budget,
## or the rate outruns the price and the deep realms get cheap. That bound is read
## from the data, not typed in — `tests/core/test_realm_rate.gd` walks all three
## authored `progress_required` ladders and takes the tightest step any of them
## prices a transition at. Today that is qi's `dao_ancestor -> primordial_origin`
## at `2900/2800`, so the ceiling is ~1.0357 and this sits under it. The first
## transition is excluded because qi and mind author R1 and R2 equal, which leaves
## that price with no predecessor to be cheaper than. A rate needs no justification
## for being modest — but it does need to stay a gain.
##
## This is a foundation primitive, not a shared module facade. `core` is a
## LAYER, not a module: `LAYER_DEPS["core"] == {"core", "contracts"}`
## (`tools/arch/rules.py`). All three cultivation modules already declare `core`
## in `tools/arch/registry.json`, so holding the curve here creates ZERO new
## edges. The old per-path copies justified themselves with the cross-module
## facade rule; that rule never applied to `core`, and the other half of the
## claim — that a shared curve "is the magnitude ladder this replaced" — has been
## false since ADR 0050.
##
## `BodyRealmProfile`, `QiRealmProfile` and `MindRealmProfile` still exist, as RENAME
## SEAMS: they alias `RATE_STEP` and delegate `factor` here, because six call sites are
## mid-flight in other changes and must not be edited underneath their owners. They
## author no number, and the test named above fails if one of them ever does. Retiring
## them is the mechanical `*RealmProfile.factor` -> `RealmRate.factor` rename.

## Per-realm compounding step. Bounded by construction: the whole ladder is worth
## `RATE_STEP^29`, under 2x — a gain, not a magnitude.
const RATE_STEP := 1.04

## Neutral is 1.0: an unstarted path, or a realm that is not on the ladder,
## contributes exactly what an actor with no path would.
const NEUTRAL := 1.0


## The realm factor for `realm_id`, or `NEUTRAL` for an unknown or empty id.
static func factor(realm_id: StringName) -> float:
	var ordinal := RealmDefaults.ladder().index_of(realm_id)
	if ordinal < 0:
		return NEUTRAL
	return pow(RATE_STEP, float(ordinal))
