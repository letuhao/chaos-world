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
## ## Rates are a FLAT DELTA (ADR 0877)
##
## `rate = clampf(maxf(0.0, rate - resist) / rate_scale, 0.0, 1.0)` — Keepverse's
## `RateFromZero`, via [method CombatStats.rate_from_zero]. Equal halves cancel to
## exactly `0.0`: a defender who matches an attack answers it completely, which is the
## owner's yin-yang rule and the reason ADR 0877 reverses ADR 0215's ratio. NEITHER half
## is capped — `1e10` against `1e10` reads `0.0` at any magnitude — and the `[0, 1]` is
## on the OUTPUT only, because a probability is arithmetic rather than a progression
## ceiling. A defender who falls behind by `rate_scale` is certain to be hit, dodged,
## parried or critted; a defender who leads is a wall. That is the intended reading.

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
## `tuning` is read for `avoidance_band_cap` only. `p_hit`, `p_parry` and `p_block`
## arrive already resolved by the caller: they are the same flat-delta trigger shape
## [method CombatStats.rate_from_zero] writes in ONE place, and `rate()` below is the
## actor-level read of that same formula. No sigmoid is used anywhere here, so an
## empty band is genuinely a no-op rather than an unchosen `0.5`.
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


## A rate contest, as the flat delta [method CombatStats.rate_from_zero] defines
## (ADR 0877): `clampf(maxf(0.0, rate_value - resist) / tuning.rate_scale, 0, 1)`.
##
## ## The call order: the RAISE half first, the SUPPRESS half second
##
## The caller passes the half that RAISES the outcome first and the half that SUPPRESSES
## it second, which is `CombatBand.rate_of`'s and `CombatRecoil.bounce`'s existing order
## and it is preserved so no call site has to be read twice to find a transposed
## argument. For hit, crit and penetration the raise half is the ATTACKER's; for parry,
## block and reflect it is the DEFENDER's — the pairs AGENTS.md inverts — so the order
## is about raise/suppress and never about attacker/defender.
##
## A null `tuning` answers `0.0`: without a scale there is no exchange rate, and this
## module's degenerate default is meant to be VISIBLY broken rather than a certainty
## nobody chose — the same read [method CombatStats.rate_from_zero] gives a
## non-positive scale.
static func rate(rate_value: float, resist: float, tuning: CombatTuning = null) -> float:
	if tuning == null:
		return 0.0
	return CombatStats.rate_from_zero(rate_value, resist, tuning.rate_scale)


## [method rate] with `CombatStats`'s neutral default folded in, so a caller that never
## seeds a default still reads the DEFAULTS table rather than a bare `0.0` it happened
## to pass. One reading of the neutral shape, which is what makes "an unstatted actor
## contests nothing" a property of the table instead of of every call site.
static func rate_of(id: StringName, actor: Actor, tuning: CombatTuning) -> float:
	return rate(CombatStats.default_of(id) + derived_of(actor, id), 0.0, tuning)


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
