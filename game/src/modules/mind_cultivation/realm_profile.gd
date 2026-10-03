class_name MindRealmProfile
extends RefCounted

## A RENAME SEAM onto the one realm rate. Not a second curve.
##
## This file authors no balance number. `RATE_STEP` and `NEUTRAL` are ALIASES of the
## constants in `core/realm_rate.gd`, and `factor` DELEGATES to it (ADR 0066, ADR 0081).
## Retuning the rate is a one-line edit in `core`, and it moves all three paths at once by
## construction rather than by discipline — which is the whole point: the three copies were
## four declarations of one number waiting for someone to retune one of them.
##
## The class survives only because six call sites (`MindTraining.cultivate`,
## `MindProvider._realm_factor` and their body/qi twins) are mid-flight in other changes and
## must not be edited underneath their owners. Retiring it is the mechanical rename
## `MindRealmProfile.factor` -> `RealmRate.factor` at those six sites.
##
## It is deliberately not a re-implementation. `tests/core/test_realm_rate.gd` fails if the
## step stops being an alias, if `factor` stops delegating, or if any other `const RATE_STEP`
## appears anywhere in this module — so it cannot drift back into a private curve.

## Alias of `RealmRate.RATE_STEP`. Not an authored second value.
const RATE_STEP := RealmRate.RATE_STEP

## Alias of `RealmRate.NEUTRAL`. Not an authored second value.
const NEUTRAL := RealmRate.NEUTRAL


## The realm factor for `realm_id`. One implementation: `RealmRate.factor`.
static func factor(realm_id: StringName) -> float:
	return RealmRate.factor(realm_id)
