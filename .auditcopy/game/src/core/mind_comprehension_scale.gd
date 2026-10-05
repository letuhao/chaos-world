class_name MindComprehensionScale
extends RefCounted

## What a mind realm's comprehension GATE costs, as ONE ladder-governed number per
## realm. Beside `core/realm_power_table.gd` because it is that table's single
## answer for a gate requirement, not a second curve.
##
## ## Why this file exists: a private quadratic is being retired
##
## `MindRealmSeed.comprehension_required` was, at all 30 realms and to the last
## decimal, `2r^2 + 6r + 10` in the realm's ladder ORDINAL — a private power curve
## sitting one file away from the actor SSOT. `core/realm_power_table.tres` is
## 1.00 -> 551.46 over the same ladder; the quadratic is roughly linear. The two
## disagreed by up to 22.2x, so the mind path's binding entry gate was priced off a
## shape nothing else in the game used, and nothing in the tree tied the 30
## literals together or checked that they agreed with each other. That is the ADR
## 0116 shape: a constant declared twice is two constants.
##
## The gate is a MAGNITUDE, and magnitudes are ladder-governed like every other.
## `RealmScaling` scales the shared combat stats by `realm.power`; this scales a
## gate requirement by the same number. One power curve, keyed by realm id.
##
## ## `SCALE` is DERIVED, and it is authored in exactly one place
##
## `SCALE` is the GEOMETRIC MEAN over the 30 rungs of the retired quadratic's
## per-rung ratio `comprehension_required / power` — i.e. the single multiplier that
## best preserves the TOTAL work the gate represented across the ladder, rather than
## a number chosen to flatter any one realm. Reproduce it from the data with:
##
##     k = exp( mean( ln( comprehension_required(rung) / power(rung) ) ) )
##
## over the 30 rungs, where `comprehension_required` is the retired quadratic
## `2r^2 + 6r + 10` and `power` is `core/realm_power_table.tres`. That evaluates to
## 27.944816621143715, written here as 27.9448. The arithmetic mean of the same
## ratios is 38.0011 — a different, equally defensible answer that would re-centre
## the ladder on its arithmetic middle instead of its geometric one. The geometric
## mean is the one that does not move the ladder's total difficulty, which is the
## property a re-authoring pass must preserve.
##
## `SCALE` is a MAGNITUDE-CALIBRATION, not a rate: unlike `RealmRate.RATE_STEP`
## (ADR 0066) it does not compound per realm and it is not bounded by the authored
## work budget. It is one flat factor. `tests/core/test_mind_comprehension_scale.gd`
## asserts it is declared in exactly one place in `res://src`, so a second copy is a
## build failure rather than a silent divergence.
##
## ## Rounding
##
## The authored `.tres` literals are the NEAREST INTEGER to `SCALE * power`, and
## `required()` returns that same nearest integer so the runtime and the data agree
## exactly — the gate never compares against a fractional number the data does not
## carry. `roundf` rounds halves away from zero; no rung's `SCALE * power` lands on
## a half today (the guard asserts tie-freedom by name), so the rule is unambiguous
## for every current realm.
##
## This is a foundation primitive, not a module facade. `core` is a LAYER, not a
## module, so holding this here creates ZERO new dependency edges — `mind_cultivation`
## already declares `core`.

## The ladder-to-gate factor. Derived as the geometric mean of the retired
## `2r^2 + 6r + 10` quadratic's per-rung `comprehension / power` ratios over all 30
## rungs; see the docblock for the reproduction. The ONLY declaration in `res://src`.
const SCALE := 27.9448


## The comprehension a realm's entry gate demands: `round(SCALE * power(realm_id))`.
## Keyed by realm id, never by ladder ordinal, so an inserted realm cannot silently
## shift every realm below it onto the wrong price. An id that is not on the ladder
## prices at R1 rather than at zero — `power_for` falls back to a neutral 1.0, and a
## missing entry must never make a gate free or unreachable.
static func required(realm_id: StringName) -> float:
	return roundf(SCALE * RealmDefaults.POWER.power_for(realm_id))


## `MindRealmSeed.insight_required`, which is a strict weaker copy of the gate at
## exactly half of it and can never bind. Kept here so the half is a derivation and
## not a second hand-typed ladder (BL-0146 carries deleting the field itself).
static func insight_floor(realm_id: StringName) -> float:
	return roundf(required(realm_id) * 0.5)
