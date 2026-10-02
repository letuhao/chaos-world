class_name QiRealmProfile
extends RefCounted

## What the realm the qi cultivator is standing in is worth, as ONE bounded
## per-realm number.
##
## ## It is a RATE, and that is the whole point
##
## The question it answers is "how much does a unit of this realm's circulation
## count", never "how strong is a thing from this realm". Those are different
## kinds of number. A magnitude — health, damage, capacity — wants a visible
## per-realm authored relationship, and the qi path has its own already, owned
## where it belongs: `QiRealmSeed.dantian_capacity` is the reservoir magnitude,
## authored per realm and applied once by `QiTraining.synchronize`. `RealmScaling`
## (core) scales the shared combat stats by the realm's strength. A provider that
## also multiplied by the realm's strength would count the same realm twice, and
## a rate has no business tracking a magnitude at all. Reading a shared
## exponential curve here is what once made a single breakthrough worth more than
## everything else combined.
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
## breakthrough is the authored progress budget divided by the rate and the
## budget does not step at the same moment. Per realm, the rate rises strictly
## and the price of a breakthrough rises strictly — see
## `tests/modules/qi_cultivation/test_qi_realm_profile.gd`, which pins both.
##
## `RATE_STEP` is the only balance number here and it is authored, not derived:
## it must stay at or below the smallest per-realm step in the authored
## `progress_required` ladder, or the rate outruns the price and the deep realms
## get cheap. A rate needs no justification for being modest — but it does need to
## stay a gain.
##
## The body and mind paths carry a verbatim copy of `RATE_STEP` and the formula.
## They are separate classes because a module may only reach another module
## through its `api.gd` facade, and the alternative — one shared curve — is the
## magnitude ladder this replaced. Do not retune one without the other two; all
## three suites pin the same named realms against the same expectations.

## Per-realm compounding step. Bounded by construction: the whole ladder is worth
## `RATE_STEP^29`, under 2x — a gain, not a magnitude.
const RATE_STEP := 1.02

## Neutral is 1.0: an unstarted path, or a realm that is not on the ladder,
## contributes exactly what an actor with no path would.
const NEUTRAL := 1.0


## The realm factor for `realm_id`, or `NEUTRAL` for an unknown or empty id.
static func factor(realm_id: StringName) -> float:
	var ordinal := RealmDefaults.ladder().index_of(realm_id)
	if ordinal < 0:
		return NEUTRAL
	return pow(RATE_STEP, float(ordinal))
