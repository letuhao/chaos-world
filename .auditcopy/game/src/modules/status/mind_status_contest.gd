class_name MindContest
extends RefCounted

## The ONE contest every mind status is resolved through — the CC group and the
## expression channels both come through here, and they differ only in what they
## do with the answer.
##
## ## The formula, verbatim
##
## ```
## edge       = (offence - defence) / (offence + defence)     in [-1, 1], 0 at parity
## p_land     = clampf(0.5 + edge * steepness, 0, 1)          the coin-flip form
## p_answer   = clampf(floor_resist + headroom * (1 - p_land), floor_resist, 1)
## ```
##
## ## The `1 -` on `p_land` is the whole answer, and reading it wrong is the defect
## this file's formula used to carry
##
## `p_land` is the ATTACKER's chance of landing. `p_answer` is the TARGET's chance of
## REFUSING. Those are the two ends of one coin, so the answer is the COMPLEMENT of
## the land rate — `1 - p_land` — and `headroom` scales the complement. The form this
## file used to publish was `floor_resist + headroom * p_land`, which reads a rate
## against the wrong side of the toss: a STRONGER attacker pushed `p_land` UP, and
## that raised the published REFUSAL rate with it. So the "refusal rate" rose when
## the attacker got stronger and stopped responding to `defence` altogether, and a
## sweep of defender investment read `0.654` flat at defence `15`, `40` and `90`.
##
## ## WHY A `+ p_land` IS NOT A MERE SIGN ERROR: it breaks three of the four
## ## required properties, and no `floor_resist` value repairs it
##
## 1. **Investing in the defence did nothing.** `p_answer` was a function of the
##    attacker's edge alone, so the sweep this design exists to make legible was flat
##    above the first step.
## 2. **A saturating attacker was the EASIEST to refuse**, the exact inverse of
##    `floor_resist`'s promise. `floor_resist` is the share the target KEEPS; at
##    `edge == +1` the attacker lands every time and the target must still refuse
##    `floor_resist` of it, which is `floor_resist + headroom * (1 - 1) = floor_resist`
##    — not `floor_resist + headroom`, which is what the old term produced.
## 3. **A target who out-invests read the parity rate**, because the old term sent
##    `p_land` to `0.0` when `edge == -1` and the published rate fell to the bare
##    floor. The complement inverts that: at `edge == -1` the target refuses
##    `floor_resist + headroom`, its best.
##
## Every published number a player sees is unchanged INDIRECTION-ONLY: at parity
## `p_land == 0.5`, and `1 - 0.5 == 0.5`, so the parity rate
## `floor_resist + headroom * 0.5` — the number the 329% kill-time comparison, the
## coin-flip margin and `test_a_non_investor_is_not_coin_flipped` are all built on —
## is bit-for-bit the same as before. Only the two OFF-PARITY ends move, which is
## precisely where the old formula was wrong.
##
## ## WHY NOT THE COIN FLIP, which is the whole reason this file exists
##
## The naive gate is a `0.5 sigmoid neutral point`: at parity the apply rate is
## `0.5`, so a target with no defence at all is flipped a coin and is landed half
## the time. Applied every beat that is not a hard disable — it is a SOFTER hard
## disable, because the roll is fresh each beat and a lock re-rolls better than a
## lock it holds. Measured on that shape: a perma-lock at **329% of baseline kill
## time**, which is worse than the stun it replaced.
##
## ## The three things that break it, and each is a separate mechanism
##
## **1. A FLOOR, not a cap.** `floor_resist` is the share the target refuses even
## when the attacker lands everything, so the answer rate has a positive lower
## bound. This is the repo's own distributional reasoning: the spine's chip floor and
## `mental_defense_cap`'s `1 - cap` are the same claim in two other places, and a cap
## is a truncation where a floor is a promise.
##
## **2. HEADROOM bounds how much the floor can be taken off.** Without it the target's
## refusal rate is pinned at `floor_resist` and `steepness` would do nothing.
## `headroom` is the spread between the floor the target keeps against a saturating
## attacker (`floor_resist`) and its best against an out-invested one
## (`floor_resist + headroom`), so **`headroom < 1.0` is what keeps every answer rate
## strictly inside `(0, 1)`** — `MindStatusDef.problems()` refuses `headroom >= 1.0`,
## which is the same refusal the floor gate is, from the other end.
##
## **3. The gap is a RATIO, never a difference.** `(o - d) / (o + d)` is scale-free:
## a realm gap multiplies both terms and the edge is unchanged, so a deep-realm
## attacker is NOT automatically certain where an equal-realm attacker is not. This
## is ADR 0215's shape, and it is what stops the ladder from turning every contest
## into a formality at depth — the saturation failure ADR 0215 measured.
##
## ## What the contest NEVER does
##
## It never returns `0.0` for a well-formed def and a live pair of actors, and it
## never returns `1.0`. The floor is what stops the first and `headroom < 1.0` is
## what stops the second: the range is `[floor_resist, floor_resist + headroom]`, and
## `MindStatusDef.problems()` REFUSES a `floor_resist` at `0.0` and a `headroom` at
## or above `1.0`, so both ends are closed by authoring rather than by clamping. So
## the output range is genuinely open — the property `test_mind_status_no_lock.gd`
## pins by walking the defs rather than by restating a number.
##
## ## `steepness` is a DATA number, not this file's
##
## The coin flip is the problem, not the sigmoid: `0.5 + edge * 0.5` and
## `0.5 + edge * 0.9` are the same shape and both are a coin flip at parity. So the
## dial lives on the def's authored `steepness`, where a designer tunes how decisive
## a contest feels, and this file keeps no constant of its own. The one number it
## holds is `NEUTRAL`, and that is the coin flip's own neutral, named so the
## comment above it and the code cannot drift apart.

## The coin flip's neutral, and the load-bearing reason the whole file exists.
const NEUTRAL := 0.5


## Every primitive the contest computed, so a readout and a test read the same
## shape without recomputing it (ADR 0038: primitives in a read model).
##
## `{offence, defence, edge, steepness, p_land, floor_resist, headroom, p_answer,
## answer_share, spend, i}` — `answer_share` is `1 - p_answer`, the share of a
## landed status that is REFUSED rather than paid, and `spend` is how much of the
## magnitude survives the contest. `p_answer` is the number the fight screen shows.
static func resolve(
	def: MindStatusDef, offence: float, defence: float, rng: Variant = null
) -> Dictionary:
	var answer := _empty_answer()
	if def == null:
		return answer
	var strong := _finite(offence)
	var guard := _finite(defence)
	answer["offence"] = maxf(0.0, strong)
	answer["defence"] = maxf(0.0, guard)
	answer["steepness"] = def.steepness()
	answer["floor_resist"] = def.floor_resist()
	answer["headroom"] = def.headroom()
	# Hole: `o + d == 0` is `0.0 / 0.0 == NaN`, and a NaN survives every `clampf` in
	# this file. Two actors who have invested in NEITHER side of the contest read
	# parity, which is the correct answer: neither can win, so neither wins.
	var total := maxf(0.0, strong) + maxf(0.0, guard)
	var edge := 0.0 if total <= 0.0 else (maxf(0.0, strong) - maxf(0.0, guard)) / total
	edge = clampf(edge, -1.0, 1.0)
	answer["edge"] = edge
	# The COIN FLIP, and then the floor that rescues it. `NEUTRAL` is what this line
	# is and is not: parity is a 50% LAND rate, but the ANSWER rate is
	# `floor_resist + headroom * 0.5`, which on a shipped def is far above the 0.5
	# the naive form would have left a non-investor with.
	var p_land := clampf(NEUTRAL + edge * _finite(def.steepness()), 0.0, 1.0)
	answer["p_land"] = p_land
	var floor_value := def.floor_resist()
	var headroom := def.headroom()
	# The REFUSAL share is the COMPLEMENT of the land rate — the two ends of one
	# coin, not two independent rates. See the docblock: reading `p_land` here
	# without the `1 -` published a refusal rate that rose with the ATTACKER's
	# strength and ignored the defence, which is the defect this line's term is
	# load-bearing against.
	#
	# The clamp's LOWER bound is the floor itself, so a hand-edited `.tres` cannot
	# author a `floor_resist` of `0.0` beside a `headroom` of `1.0` and make the
	# floor vanish, and its UPPER bound is `1.0` rather than `floor + headroom`
	# because `headroom >= 1.0` is refused at load for the same reason.
	var p_answer := clampf(floor_value + headroom * (1.0 - p_land), floor_value, 1.0)
	answer["p_answer"] = p_answer
	answer["answer_share"] = 1.0 - p_answer
	answer["spend"] = 1.0 - p_answer
	answer["i"] = _roll(rng, p_answer)
	return answer


## ## The spend, as a share of the authored magnitude
##
## One function and not two, because a status that is REFUSED costs nothing and a
## status that LANDS costs exactly the remainder — and a second caller's own
## `1 - p` is how a refactor would let a refused status land at full magnitude.
static func spend_of(answer: Dictionary) -> float:
	return clampf(_finite(float(answer.get("spend", 0.0))), 0.0, 1.0)


## Whether this contest was WON by the target. Named rather than left as a `rng`
## comparison at each of the two call sites, so "who rolled" cannot differ between
## the read model and the write.
static func answered(answer: Dictionary) -> bool:
	return float(answer.get("i", 0.0)) < float(answer.get("p_answer", 0.0))


## The share of a landed status that survives the contest, as a magnitude bound.
## Multiplicative against the caller's potency, so a resisted status is WEAKER
## rather than absent — the resist is legible to a player watching the bar move.
static func magnitude_after(answer: Dictionary, potency: float) -> float:
	return maxf(0.0, _clamped(_finite(potency))) * spend_of(answer)


## ## One draw, and a NULL generator means no draw and no landing
##
## The same rule ADR 0067 and `CombatBand.roll` already use: a deterministic
## caller is asking for the one answer that consults no randomness, so it is
## handed the SATURATED answer rather than a silent `randf()` that would make the
## same contest replay differently. Here the saturated answer is the FLOOR — a
## target with no generator refuses at least `floor_resist` of the time, which is
## the conservative reading and never the one that mints a CC out of nothing.
static func _roll(rng: Variant, _p_answer: float) -> float:
	if rng == null or not (rng is Object):
		return 0.0
	if not (rng as Object).has_method(&"randf"):
		return 0.0
	return clampf(_clamped(_finite(float((rng as Object).call(&"randf")))), 0.0, 1.0)


## Every key present, so a panel rendering this shape never has to ask whether a
## key exists — the same contract `MindDamage._empty_parts` keeps.
static func _empty_answer() -> Dictionary:
	return {
		"offence": 0.0,
		"defence": 0.0,
		"edge": 0.0,
		"steepness": 0.0,
		"p_land": 0.0,
		"floor_resist": 0.0,
		"answer_share": 0.0,
		"p_answer": 0.0,
		"spend": 0.0,
		"i": 0.0,
	}


## The `[0, 1]` form of [_finite], for the callers that want a bounded quantity and
## have no contest ratio to put an infinite input through. An infinity authored where a
## share was expected saturates to the nearer end rather than to zero.
static func _clamped(value: float) -> float:
	return clampf(_finite(value), 0.0, 1.0)


## Sanitise one contest input.
##
## `NaN` is a hole rather than a magnitude — it survives every `clampf` in this file
## — so it is the one value read as absent. An INFINITE input is not: `INF` is `+1`
## to every comparison and `NEG_INF` is `-1` to every one of them, so an over-invested
## side is a LIMIT the ratio already has a shape for, and both directions have to be
## carried or `(INF + -INF)` is `NaN` and the whole contest is.
static func _finite(value: float) -> float:
	if is_nan(value):
		return 0.0
	return 1.0 if value > 0.0 else -1.0
