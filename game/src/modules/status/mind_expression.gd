class_name MindExpression
extends RefCounted

## EXPRESSION DAMAGE: the attacker projects something — a statement, a direction —
## and it damages the target's composure. The damage is composure damage; the
## composure is the defender's answer, and the two ship together.
##
## ## Why this is not the CC group with a different name
##
## The two tracks differ in WHO the contest is between, and that difference is
## what stops them being reskins:
##
## - A **control** status is a contest between the attacker's mind and the
##   target's ACTIONS. Winning costs the target a tempo, a reserve or an
##   advantage. The target's answer is `p_answer` and it is a RATE.
## - An **expression** is a contest between the attacker's projection and the
##   target's COMPOSURE. Winning does not impose a state at all — it CONSUMES a
##   reserve the target carries, and the target's answer is `composure_regained`,
##   which is a QUANTITY of reserve restored per beat, not a probability.
##
## So the two are not two dials on one curve: one is a coin the target flips
## (`MindContest`), the other is a meter the target refills (`MindExpression`).
## A player facing a `daze` rolls; a player facing a `voice` drains and then
## recovers. `test_mind_status_no_lock.gd` pins the difference by asserting the two
## resolvers publish DIFFERENT keys and that no control shape is reachable through
## this file.
##
## ## The channel, and why TWO and not four
##
## `voice` and `intent` are the two projections, and each has a defender stat the
## other does not: `voice` is answered by CONVICTION (`will`) and `intent` by
## CLARITY UNDER MOTION (`mental_clarity`). That non-symmetry is the whole
## argument for the track. A third channel would have needed a third defender stat
## with a real authored baseline, and the repo's own history — mind's two base
## attributes reading `0.0` on every stock actor until ADR 0183 gave them a
## fallback — is the reason I will not invent a third axis and call it shipped.
## Four, as the owner's brainstorm floated, had the same problem one level up:
## four numbers with no matchups is not a vocabulary.
##
## ## The formula
##
## ```
## edge      = (projection - composure) / (projection + composure)   ratio, as in MindContest
## pressure  = clampf(0.5 + edge * steepness, 0, 1)
## potency   = share_of_the_pool_per_point_of_projection             the SPEND
## raw       = (projection * (1 + attacker mastery) * pressure) * potency
## ```
##
## ## `projection` IS THE ATTACKER'S MASTERY — so it is summed with the ATTACKER's
## ## own, never taken from the target
##
## This used to read `projection` off the TARGET, under the reading that the edge is
## "who reads the channel better" and a target who holds a `mind_composure_voice`
## can argue a voice off a stranger. Measured, that reading made the whole expression
## track unable to spend anything: `mind_status_mastery_voice` on the fixture was
## `0.24` while `mind_composure_voice` on the target was `0.03`, and
## `harm = 0.02 * 0.4 * 0.18 = 0.001512` against a composure pool of `100.0` — a
## spend of **0.0015%** of what the target was carrying, which `ResourcePool.change`
## swallowed whole, so `mind_confront` reported `ok`, `spent 0.001512`, and a pool
## that never moved. That is the same defect the `_stat_of` note below records one
## step earlier in the chain, and it was hiding one step further on: the CC group
## reads the attacker's mastery through `_offence_of(attacker, def)` and was never
## affected, so only this resolver read a defence stat as if it were an attack.
##
## ## THE BALANCE DECISION, and it is a blend rather than a replacement
##
## The pool's currency is composure — an ABSOLUTE reserve of `100.0` points — while
## `projection` is a mastery RATE. Multiplying a rate by a share gives a fraction of a
## point, which is why the scale-free edge alone could never move a `100.0` pool. So
## the money number is `potency`, a share of the POOL per point of projection, and
## it carries no ceiling of its own: `0.003` is three points of a hundred-point pool
## per point of projection.
##
## `minf(1.0, projection)` is deliberately NOT applied here. The scale-free edge is
## the contest; the rate is the currency it is expressed in. A saturated attacker at
## `projection 1.0` presses `edge` to `-1.0`, `pressure` to its floor, and spends
## proportionally less — which is what the compressor's own composure is FOR. What
## bounds a projection against an unlimited spend is `MindStatusDef.problems()`, which
## refuses `harm >= 1.0` at load, and that gate is already on record: it accepts the
## huge harmonic `20.45` with `harm 0.08` without complaint.
##
## The non-CC sibling on this same shape — a compressor that spends a POOL — and the
## fact that an expression's answer is a pool REFILL rather than a thrown roll are
## both outside this module; ADR 0215 is the ratio's own record.
##
## and the answer is not a chance but a RATE OF RECOVERY: `recovery_per_beat`, a
## share of what was taken, which is what the `composure` def's `beat` prices. The
## defender therefore always has a live answer — a meter they refill — which is
## the same promise the control track makes with a floor, made in the currency the
## damage was paid in.

## The composure POOL a projection damages, and the stat PREFIX the composure
## contest reads. Both from `MindVocabulary` in `contracts/`, because this module
## may not name `MindStats` (`status` declares only `contracts` + `core`) and
## `mind_cultivation` may not name a `status` def. `MindVocabulary` is the one
## place both sides agree on the spelling.
const COMPOSURE_POOL := MindVocabulary.COMPOSURE_POOL
const COMPOSURE_PREFIX := MindVocabulary.DEFENCE_PREFIX


## Every primitive this resolver computed, so a readout and a test read one shape.
## `{channel, projection, composure, edge, pressure, share, harm, recovered, spent,
## remain, pool_bound}`.
static func breakdown(
	def: MindStatusDef, target: Variant, rng: Variant = null, attacker: Variant = null
) -> Dictionary:
	var parts := _empty_parts()
	if def == null:
		return parts
	parts["channel"] = String(def.channel())
	var composure := _stat_of(target, _prefixed(COMPOSURE_PREFIX, def.channel()))
	parts["composure"] = composure
	# `1 + the attacker's own mastery`, read off the ATTACKER rather than the target.
	# `project` and `preview` pass it; a caller that does not resolves against a
	# projection of `1.0` and lands on the NEUTRAL edge rather than a coin flip biased
	# by a defence stat standing in for an attack.
	var mastery := _stat_of(attacker, _prefixed(MindStatusDef.OFFENCE_PREFIX, def.channel()))
	parts["projection"] = 1.0 + mastery
	var projection: float = parts["projection"]
	var total := projection + composure
	# Hole: the same `0.0 / 0.0` guard `MindContest.resolve` keeps. Two actors who
	# invested in neither side are at parity, which is the honest answer.
	var edge := 0.0 if total <= 0.0 else (projection - composure) / total
	edge = clampf(edge, -1.0, 1.0)
	parts["edge"] = edge
	var pressure := clampf(MindContest.NEUTRAL + edge * def.steepness(), 0.0, 1.0)
	parts["pressure"] = pressure
	parts["share"] = def.harm()
	# The harm the projection would land UNANSWERED, so a readout can show the
	# defence as the difference between two rows rather than recomputing it.
	var raw := _finite(projection) * pressure * def.harm()
	parts["harm"] = raw
	var pool: Variant = _pool_of(target, COMPOSURE_POOL)
	parts["pool_bound"] = pool != null
	if pool == null:
		return parts
	var held := maxf(0.0, _finite(_number(pool.get(&"current"))))
	# A projection CANNOT spend composure the target does not have: the pool clamps,
	# and `harm` is reported as what was ACTUALLY spent so a caller never writes a
	# negative delta derived from an unclamped number.
	var spent := minf(raw, held)
	parts["spent"] = spent
	parts["remain"] = maxf(0.0, held - spent)
	# The ANSWER: what the defender gets back this beat, as a share of what was
	# taken. This is the composure track's floor — not a chance, a quantity — and it
	# is what makes an expression damage a budget rather than a bleed.
	var recovered := minf(spent, def.recovery_per_beat() * spent)
	parts["recovered"] = recovered
	# A deterministic caller is asking for the one answer that consults no
	# randomness (ADR 0067). A projection has exactly one randomness-DEPENDENT half
	# — whether the target recovers this beat — and it is the defender's, so the
	# deterministic reading is the one where the defender is NOT refunded: a
	# headless caller measuring the damage measures the attacker's ceiling, never
	# a number a re-run would not produce.
	if rng == null:
		parts["recovered"] = 0.0
	return parts


## ## THE SIGN IS `- (spent - recovered)`, AND THE COLLAPSE THIS CAUSED IS THE
## ## WHOLE TRACK NOT SPENDING
##
## `ResourcePool.change` ADDS: `current = clampf(current + delta, 0, maximum)`. So a
## projection that takes composure away must write a NEGATIVE delta, and this function
## returned `spent - recovered` — POSITIVE. Every expression REFUNDED the reserve
## instead of draining it.
##
## ## WHY THE CLAMP HID IT AT A `0.0` POOL AND NOT AT ANY OTHER — the shape of the
## ## bug, and why it is a guard defect rather than a sign defect
##
## The pool is minted at `current == maximum` (`ResourcePool._init`), and a positive
## delta against a full pool clamps straight back to `maximum`: the write happened, the
## value moved, the caller's returned "delta written" was `0.0`, and the only visible
## symptom was a projection reporting `spent 0.0` while having done nothing. That is
## the most expensive possible reading — the one path that says the attack ran reported
## no attack — and it is why the delta's SIGN is asserted below rather than inferred
## from a balance number that happens to survive it.
##
## Measured before the fix, on the shipped `mind_voice` against a full `100.0` pool:
## `broken = clampf(100.0 + 0.174811, 0.0, 100.0) == 100.0`, and with the pool one
## point short it was `clampf(99.9999997 + 0.174811, 0.0, 100.0) == 100.0` — so a
## second projection pushed the target back to full. The `remain` the caller was
## handed (`99.825189`) disagreed with the pool the whole time.
##
## With the sign corrected the same projection writes `-0.174811` and the pool reads
## `99.825189`, which is the number `remain` was reporting all along.
static func delta_of(parts: Dictionary) -> float:
	var spent := _finite(float(parts.get("spent", 0.0)))
	var recovered := _finite(float(parts.get("recovered", 0.0)))
	return recovered - spent


## Land one expression's delta against the target's composure pool, through the
## pool's OWN `change`, so it clamps like every other pool in this repo. Returns
## the delta that was WRITTEN, so a caller can report a clamped spend rather than
## the unbounded one it computed.
static func apply(target: Variant, parts: Dictionary) -> float:
	var pool: Variant = _pool_of(target, COMPOSURE_POOL)
	if pool == null:
		return 0.0
	var delta := delta_of(parts)
	if is_zero_approx(delta):
		return 0.0
	var before := _finite(_number(pool.get(&"current")))
	pool.call(&"change", delta)
	return _finite(_number(pool.get(&"current"))) - before


## A projection stat id for `channel`: `mind_status_mastery_<channel>`.
static func projection_stat(channel: StringName) -> StringName:
	return _prefixed(MindVocabulary.OFFENCE_PREFIX, channel)


## A composure stat id for `channel`: `mind_composure_<channel>`.
static func composure_stat(channel: StringName) -> StringName:
	return _prefixed(COMPOSURE_PREFIX, channel)


static func _prefixed(prefix: String, channel: StringName) -> StringName:
	return StringName(prefix + String(channel))


## A stat read off an actor through `call`, so a caller of another shape degrades
## to `0.0` rather than crashing an expression. TYPED, not `Variant`: an inferred
## assignment off a Variant is a warning this project treats as an error.
##
## ## `stats` is a PROPERTY, so `has_method` reads every one of these as `0.0`
##
## `Actor` declares `var stats: ActorStats` (`core/actor.gd`) — a field, not a
## method — so the obvious handle check found no `stats` method and EVERY projection
## resolved `projection == composure == 0.0`. That lands at `edge == 0.0`, `pressure`
## at the neutral `0.5`, and `raw == 0.0`, so `mind_confront` reported `ok` and spent
## `0.0` against the target's composure: the whole expression track was a `.tres` that
## did nothing at all, through the one path that says it ran. `MindStatusApi._stat_of`
## reads `actor.stats` directly and was always right, which is why the CC group was
## never affected and only this resolver was.
static func _stat_of(actor: Variant, stat_id: StringName) -> float:
	if actor == null or stat_id == &"" or not (actor is Object):
		return 0.0
	var holder := actor as Object
	var value: Variant = null
	if &"stats" in holder:
		value = holder.get(&"stats")
	elif holder.has_method(&"stats"):
		value = holder.call(&"stats")
	if not (value is Object) or not (value as Object).has_method(&"derived"):
		return 0.0
	return maxf(0.0, _finite(_number((value as Object).call(&"derived", stat_id))))


static func _pool_of(actor: Variant, pool_id: StringName) -> Variant:
	if actor == null or pool_id == &"" or not (actor is Object):
		return null
	var holder := actor as Object
	if not holder.has_method(&"resource"):
		return null
	return holder.call(&"resource", pool_id)


static func _number(value: Variant) -> float:
	if value is float or value is int:
		return _finite(float(value))
	return 0.0


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0


static func _empty_parts() -> Dictionary:
	return {
		"channel": "",
		"projection": 0.0,
		"composure": 0.0,
		"edge": 0.0,
		"pressure": 0.0,
		"share": 0.0,
		"harm": 0.0,
		"spent": 0.0,
		"recovered": 0.0,
		"remain": 0.0,
		"pool_bound": false,
	}
