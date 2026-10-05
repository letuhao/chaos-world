class_name CombatBand
extends RefCounted

## One draw, three mutually exclusive bands: `missed | parried | blocked` (ADR 0068).
##
## ## The shape, verbatim from the ADR
##
## ```
## miss    = r >= p_hit
## parried = !miss && r >= p_hit - p_parry
## blocked = !parry && r >= p_hit - p_parry - p_block
## ```
##
## Parry and block are carved out of the TOP of the would-have-been-a-hit region, so
## at zero parry and zero block this collapses to exactly `r < p_hit` by arithmetic —
## there is no special case to get wrong. And because all three thresholds are
## comparisons against ONE `r`, the bands are exclusive and partition the draw by
## construction: a caller cannot observe two of them at once.
##
## ## Pure
##
## No `Actor`, no scene tree, no `randf()`. The generator is injected and MAY be null,
## in which case the caller has declared the roll saturated and no draw is consumed —
## which is the shape `CombatProbability.RollSuccess` uses for a `p <= 0` or
## `p >= 1` chance, and is why a fully-saturated roll is free.
##
## ## Rates are a RATIO of two magnitudes (ADR 0215)
##
## `rate = offense / (offense + resist)`. ADR 0068 wrote
## `clampf(maxf(0.0, rate - resist) / rate_scale, 0.0, 1.0)` here and refused a sigmoid
## for one reason: "a sigmoid returns 0.5 at parity, so an actor with ZERO parry stat
## would parry half the time — a default nobody chose". **The ratio answers that objection
## by construction**: at parity `o == d` and `o / (o + d) == 0.5`, and that `0.5` is not
## a curve's midpoint imposed on an unchosen default — it is the definition of two equal
## shares. A parity that means `0.5` is the property ADR 0215 exists to buy; the shape
## that forbade it forbade the right thing for the wrong reason.
##
## The absolute difference is what ADR 0215 deletes. Against a constant divisor it
## saturates: once the gap exceeds a few multiples of `rate_scale` every roll is a
## certainty, and a R30 cultivator against a R3 one lands every hit, crits every hit and
## applies every status, because nothing in the formula can say "faster than the eye".
##
## `0 / (0 + 0)` is `0.0` rather than `NaN`, for [method CombatStats.contest]'s reason:
## two actors who have invested in neither half contest nothing, and neither lands.

## ## No division in the roll itself
##
## The thresholds are compared, never divided, and the roll partitions `[0, 1)` by
## comparison alone. The only division in this file is the contest's own denominator,
## `offense + resist`, which is zero only when both halves are zero — and that case is
## answered before the division, not after it. So there is no division by an authored
## constant here at all any more, and `CombatTuning.rate_scale` is no longer read by the
## band roll in any path.

## The draw. `r` is the single `rng` value every threshold is compared against, kept
## on the record so a test can assert the bands partition one number and not two.
## Named `draw`, not `roll`: the class also owns `static func roll(...)`, and GDScript
## refuses a parse where a member variable and a member function share a name.
var draw: float = 1.0
## Whether this attack was avoided entirely. The S2 early return: a miss never
## invokes a mechanism (ADR 0067).
var missed: bool = true
## Carved out of the top of the hit region: the attack landed and was parried. A
## parry is NOT a miss — it landed — so the mechanism still ran, and the caller
## decides what a landed-but-parried blow costs.
var parried: bool = false
## Carved below the parry band, for the same reason.
var blocked: bool = false


## A miss: nothing landed, nothing was computed, and the caller stops.
static func miss() -> CombatBand:
	return CombatBand.new()


## A clean hit: landed, and neither parried nor blocked. `r` is carried because it is
## the draw the caller must not re-roll for the crit stage — S3 is a SECOND draw, but
## the SECOND one, and reading this one again would make crit a function of the band.
static func clean(roll: float) -> CombatBand:
	var band := CombatBand.new()
	band.draw = roll
	band.missed = false
	return band


## Whether anything landed: not missed. A parry or a block is a landed hit.
func is_landed() -> bool:
	return not missed


## Whether the hit was clean — landed, not parried, not blocked. Exactly the predicate
## ADR 0068 gives S3: "a parried or blocked hit NEVER reaches crit".
func is_clean() -> bool:
	return not missed and not parried and not blocked


## The three bands from one draw.
##
## `tuning` is read for `avoidance_band_cap` and `rate_scale` only. `p_hit` arrives
## already resolved by the caller, because the landed-probability contest is between
## two actors who both intend to act (`accuracy` vs `EVASION`) and that contest has a
## legitimate sigmoid form this file deliberately does not own. `p_parry` and
## `p_block` are LINEAR-from-zero rates and arrive already resolved for the same
## reason: they are read-with-zero-not-means-nothing rates, and `rate()` below is the
## one place that shape is written.
##
## A null `rng` saturates high: a caller that passes none has declared the roll is not
## random, and every attack lands. That keeps the null case a total function instead of
## a `randf()` call — the spine takes an injected generator precisely so a resolve is
## reproducible from its seed (ADR 0067).
##
## `rng` is `Variant` and NOT `RandomNumberGenerator`, and that is the seam's whole
## point. A `RandomNumberGenerator` is the only thing a caller used to be able to hand
## in, which makes "how many draws did this cost?" unanswerable: `randf()` is native,
## so it cannot be overridden, so a counting subclass is impossible, so `band()` above
## could promise "exactly one draw" while nothing could check it. Anything answering
## `randf() -> float` satisfies this, which is dependency inversion in the only form
## GDScript allows (there is no `interface` keyword). `CombatRng` in `contracts/` is the
## named form of the contract; this is its runtime half.
static func roll(
	tuning: CombatTuning, p_hit: float, p_parry: float, p_block: float, rng: Variant
) -> CombatBand:
	if rng == null:
		return clean(1.0)
	var p_land := clampf(p_hit, 0.0, 1.0)
	# Cap the TOTAL, not the parts: capping each band independently would let three
	# saturated bands stack to 1.0 and reintroduce the immunity the cap exists to
	# forbid, so a scaled-down allocation is the only reading consistent with the cap.
	var parry := clampf(p_parry, 0.0, 1.0)
	var block := clampf(p_block, 0.0, 1.0)
	var cap := clampf(tuning.avoidance_band_cap, 0.0, 1.0)
	var total := parry + block
	if total > cap and total > 0.0:
		parry *= cap / total
		block *= cap / total
	# Explicitly typed, not `:=`. `rng` is a `Variant` so a duck-typed generator can be
	# passed, and inference from a Variant is both a warning-as-error here and a silent
	# way to lose the float type if it stops being an error.
	# Taken ONLY when a band could consume it, which is what the note below promises.
	# `randf()` is called exactly once here, so a draw spent on a certain hit is a draw
	# the caller cannot get back -- and the count is now observable, because a
	# duck-typed generator can report it. A certain LAND is not on its own enough:
	# `parry` and `block` compare the draw against `p_land - band`, so a draw still
	# decides a parry at `p_land == 1.0`. The condition is therefore "some band could
	# consume it", not "`p_land < 1.0`" -- the narrower guard silently zeroed every
	# parry and block, which is what the three-band draw count caught.
	var r: float = 0.0
	if p_land < 1.0 or parry > 0.0 or block > 0.0:
		r = rng.randf()
	var band := CombatBand.new()
	band.draw = r
	# Saturated cases consume ZERO draws, the shape `CombatProbability.RollSuccess`
	# already uses. `p_land >= 1.0` means there is nothing left for the bands to carve,
	# so this attack cannot miss and the draw is pure waste -- which is why the draw
	# above is guarded rather than taken and discarded.
	band.missed = p_land < 1.0 and r >= p_land
	var parry_edge := p_land - parry
	band.parried = not band.missed and parry > 0.0 and r >= parry_edge
	var block_edge := parry_edge - block
	band.blocked = (not band.missed and not band.parried and block > 0.0 and r >= block_edge)
	return band


## A rate contest, as a RATIO of two magnitudes: `offense / (offense + resist)`
## (ADR 0215).
##
## ## Why the argument order stayed and the FORM did not
##
## The caller passes the DEFENDER's rate first and the ATTACKER's resist second, which is
## `CombatBand.rate_of`'s and `CombatRecoil.bounce`'s existing order and it is preserved so
## no call site has to be read twice to find a transposed argument. What changed is that
## `resist` is now the OTHER HALF OF THE SAME QUANTITY — a magnitude the rival invests in —
## rather than a subtraction term. That is a rename of meaning, not a rename of position,
## so every existing call site's ARGUMENTS are still in the right order.
##
## ## The demoted sigmoid, and the rule that keeps it demoted
##
## Where a designer wants a contest more decisive than the ratio's plain reading,
## `sigmoid(k * (offense - resist) / (offense + resist))` is available and
## [method decisive] implements it. **`k` is the only dial and it is a NUMBER IN DATA**;
## what may never come back is the bare `sigmoid(scale * (offense - resist))`, whose
## `scale` divides nothing and therefore saturates. The difference is the denominator:
## `(o - d) / (o + d)` is scale-free, `(o - d)` is not.
##
## A null `tuning` saturates high for the same reason a null `rng` does: the caller has
## supplied nothing, and a silent `0.5` would be the one value nobody chose.
static func rate(rate_value: float, resist: float, tuning: CombatTuning = null) -> float:
	if tuning == null:
		return 1.0
	return CombatStats.contest(rate_value, resist)


## The demoted sigmoid, available and NOT the default: `sigmoid(k * (o - d) / (o + d))`.
##
## `k` is read from [member CombatTuning.contest_steepness] — DATA, never a literal here —
## and `0.0` is the degenerate default meaning "no steepness chosen", which reads as the
## plain ratio rather than as a curve. That is what makes the default shipping shape the
## ratio and the decisive shape an explicit, authored opt-in.
##
## ## Why this is NOT what [method rate] does, stated as the ADR's own rule
##
## ADR 0215: "The sigmoid is not deleted, it is **demoted**: where a designer wants a
## decisive contest that approaches the ratio's reading, `sigmoid(k · (offense - defense) /
## (offense + defense))` is available, and the `· (o + d)` denominator is what keeps it
## scale-free. A bare sigmoid over `(o - d)` is the defect this exists to remove and must
## not be reintroduced."
##
## Nothing in production reads this yet — `test_a_bare_sigmoid_over_a_difference_is_not
## _reachable` is the guard that keeps it that way until a `.tres` asks for it.
static func decisive(rate_value: float, resist: float, tuning: CombatTuning) -> float:
	var o := maxf(0.0, rate_value if is_finite(rate_value) else 0.0)
	var d := maxf(0.0, resist if is_finite(resist) else 0.0)
	var total := o + d
	if total <= 0.0 or tuning == null:
		return 0.0
	var k := _finite(tuning.contest_steepness)
	if k <= 0.0:
		return o / total
	# `e = (o - d) / (o + d)` is strictly inside `(-1, 1)`, so `sigmoid(k * e)` is strictly
	# inside `(0, 1)` too: the decisive form inherits the plain ratio's non-saturation
	# rather than giving it up for decisiveness.
	var edge := (o - d) / total
	var exponent := clampf(-k * edge, -60.0, 60.0)
	return 1.0 / (1.0 + exp(exponent))


## [method rate] with `CombatStats`'s neutral default folded in, so a caller that never
## seeds a default still reads the DEFAULTS table rather than a bare `0.0` it happened
## to pass. One reading of the neutral shape, which is what makes "an unstatted actor
## contests nothing" a property of the table instead of of every call site.
static func rate_of(id: StringName, actor: Actor, tuning: CombatTuning) -> float:
	return rate(CombatStats.default_of(id) + derived_of(actor, id), 0.0, tuning)


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0


## The derived value of `id` on `actor`, or 0.0 for a null actor or a null stat table.
## Total on purpose: the band roll runs before anything has been validated, and a
## half-built actor must not be able to crash a hit.
static func derived_of(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)


## Primitives only, so a UI panel can render the roll without naming this class. `{}`
## for a miss: a caller reading a parried or blocked attack reads the same keys.
##
## The draw is read off `draw`, never off `roll`: `roll` is this class's STATIC FUNCTION,
## so `"roll": roll` in a `Variant`-typed expression put a `Callable` in a payload whose
## whole contract is "primitives only, so `ui/` can render it" (ADR 0038) -- and
## `CombatEngineApi.band()` hands that dictionary straight to a caller. The field and the
## function cannot share a name in GDScript, which is why the field is `draw`; the read
## has to say so.
func to_dict() -> Dictionary:
	if missed:
		return {}
	return {
		"draw": draw,
		"missed": false,
		"parried": parried,
		"blocked": blocked,
		"clean": is_clean(),
	}
