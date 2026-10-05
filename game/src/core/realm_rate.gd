class_name RealmRate
extends RefCounted

## What one unit of a realm's training is worth, as ONE bounded per-realm number
## shared by every cultivation path (ADR 0066).
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
## `RealmDef.power` changes. The curve returns 1.776 from R1 to the top realm; a
## rate is a gain, not a magnitude (ADR 0050).
##
## ## The shape
##
## `factor(i) = rate_step()^i`, where `i` is the realm's ORDINAL on the shared
## ladder (0 at Qi Refining, 29 at Primordial Origin) — the same ordinal as
## `RealmDef.index`, read through `RealmDefaults.ladder().index_of` so the
## ordinal and the ladder can never drift apart. It is an ordinal: never a tier,
## never a stage, never a ladder index that means something else.
##
## `rate_step()` is `rate_span()^(1 / (size - 1))`: the authored SPAN spread over
## the transitions there actually are. That is the whole point. With a bare step
## the total was `RATE_STEP^(size - 1)`, so the span was a function of ladder
## LENGTH — 1.776 at 30 realms, 1.99988 at 36 (a 5e-5 margin), 2.040 at 37, and
## extending the ladder was a balance decision made by arithmetic nobody chose.
## Here the top realm is worth `rate_span()` whether the ladder holds 30 realms or
## 100 (ADR 0268).
##
## Compounding per realm rather than stepping per tier is deliberate. A tier step
## makes the first realm of a new tier CHEAPER, because the price of a
## breakthrough is the authored work budget divided by the rate and the budget
## does not step at the same moment. Per realm, the rate rises strictly and the
## price of a breakthrough rises strictly — see
## `tests/core/test_realm_rate.gd`, which pins both.
##
## `RATE_STEP` is the only authored number here, and it is the step AT
## `AUTHORED_LADDER_SIZE` — not a promise about any other ladder. What the curve
## compounds is `rate_step()`, and it must stay at or below the smallest per-realm
## step in the AUTHORED work budget, or the rate outruns the price and the deep
## realms get cheap. That bound is read from the data, not typed in —
## `tests/core/test_realm_rate.gd` walks all three authored `progress_required`
## ladders and takes the tightest step any of them prices a transition at. Today
## that is qi's `dao_ancestor -> primordial_origin` at `2900/2800`, so the ceiling
## is ~1.0357 and this sits under it. The first transition is excluded because qi
## and mind author R1 and R2 equal, which leaves that price with no predecessor to
## be cheaper than.
##
## The two bounds now AGREE rather than being independent, which is what makes the
## ceiling safe to extend past. `ln(rate_step()) = ln(rate_span()) / (size - 1)`
## with a positive numerator, so the step is STRICTLY DECREASING in ladder length:
## a longer ladder takes a smaller per-realm step and the margin against the
## authored ceiling GROWS. 30 realms -> 1.020000, 36 -> 1.016546, 37 -> 1.016082,
## 100 -> 1.005819, against a ceiling of 1.035714. A SHORTER ladder is the only
## way to walk up onto it, and a 2-realm ladder is a content bug the bound test
## should catch rather than absorb. A rate needs no justification for being modest
## — but it does need to stay a gain.
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
## `BodyRealmProfile`, `QiRealmProfile` and `MindRealmProfile` are GONE. They
## were three byte-identical private curves; they were then reduced to rename
## seams that aliased the constants here and delegated `factor`, so that six call
## sites sitting in other agents' in-flight changes did not have to move; the
## seams have now been retired and all three paths call `RealmRate.factor`
## directly. They were never a second opinion — `RATE_STEP` was authored in
## exactly one place from the moment the first copy was deleted, and the guards in
## `tests/core/test_realm_rate.gd` are what kept it that way through both stages.

## Per-realm compounding step AT `AUTHORED_LADDER_SIZE`. Still a `const` and still
## exactly `1.02`, which is load-bearing twice over: `modules/economy/api.gd`
## publishes it in a facade summary, and `tests/core/test_realm_lifespan_table.gd`
## pins its value at zero tolerance. It describes the ladder as AUTHORED and stops
## describing the curve the moment the ladder is a different length —
## `rate_step()` is what `factor` compounds.
const RATE_STEP := 1.02

## The ladder length `RATE_STEP` is authored FOR. Named rather than read from
## `ladder().size()` because the two are allowed to differ: this is the length the
## authored step describes, not a claim about today's ladder.
const AUTHORED_LADDER_SIZE := 30

## Neutral is 1.0: an unstarted path, or a realm that is not on the ladder,
## contributes exactly what an actor with no path would.
const NEUTRAL := 1.0

static var _step: float = 0.0
static var _step_size: int = -1


## What the whole ladder is worth, as a SPAN: the authored step compounded over
## `AUTHORED_LADDER_SIZE`. A function rather than an authored literal so it cannot
## drift from `RATE_STEP` — the number a retune edits and the number the curve
## reaches are the same number by construction.
static func rate_span() -> float:
	return pow(RATE_STEP, float(AUTHORED_LADDER_SIZE - 1))


## The per-realm step for the ladder AS IT STANDS: the authored span spread over
## the number of transitions there are.
##
## Cached per ladder SIZE, so a `RealmDefaults.register_realms` call that lengthens
## the ladder is picked up without a reload. A bare `const` cannot be invalidated at
## all, which is the trap `RealmDefaults._all()` already fell into once by caching a
## derived value on the object that produces its own input.
static func rate_step() -> float:
	var size := RealmDefaults.ladder().size()
	if size != _step_size:
		# At the AUTHORED ladder length the answer IS the authored constant, returned
		# verbatim rather than recomputed. `pow(pow(RATE_STEP, n), 1.0 / n)` is
		# algebraically `RATE_STEP` but not bit-exact, and a 1e-16 drift is enough to
		# tip a threshold a caller reads as a count — which is how an unchanged ladder
		# length stopped a body trial's hunt from resolving inside its strike budget.
		if size == AUTHORED_LADDER_SIZE:
			_step = RATE_STEP
		else:
			_step = pow(rate_span(), 1.0 / float(maxi(1, size - 1)))
		_step_size = size
	return _step


## The realm factor for `realm_id`, or `NEUTRAL` for an unknown or empty id.
static func factor(realm_id: StringName) -> float:
	var ladder := RealmDefaults.ladder()
	var ordinal := ladder.index_of(realm_id)
	# A one-realm ladder has no transitions and therefore no span, so the only realm
	# on it is neutral. Dividing by `size - 1` unguarded is the INF this avoids.
	if ordinal < 0 or ladder.size() <= 1:
		return NEUTRAL
	return pow(rate_step(), float(ordinal))
