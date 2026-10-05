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
## harm      = projection * pressure * share * composure_scale
## ```
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
static func breakdown(def: MindStatusDef, target: Variant, rng: Variant = null) -> Dictionary:
	var parts := _empty_parts()
	if def == null:
		return parts
	parts["channel"] = String(def.channel())
	var projection := _stat_of(target, _prefixed(MindStatusDef.OFFENCE_PREFIX, def.channel()))
	var composure := _stat_of(target, _prefixed(COMPOSURE_PREFIX, def.channel()))
	parts["projection"] = projection
	parts["composure"] = composure
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


## The composure DELTA a landed expression writes. Negative when the projection
## wins more than the target recovers, positive when the target's composure
## out-recovers the projection — which is the answer being real rather than
## decorative. Zero for an unbound target, so the degradation is inert rather than
## a crash.
static func delta_of(parts: Dictionary) -> float:
	return _finite(float(parts.get("spent", 0.0))) - _finite(float(parts.get("recovered", 0.0)))


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
static func _stat_of(actor: Variant, stat_id: StringName) -> float:
	if actor == null or stat_id == &"" or not (actor is Object):
		return 0.0
	var holder := actor as Object
	if not holder.has_method(&"stats"):
		return 0.0
	var stats: Variant = holder.call(&"stats")
	if not (stats is Object) or not (stats as Object).has_method(&"derived"):
		return 0.0
	return maxf(0.0, _finite(_number((stats as Object).call(&"derived", stat_id))))


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
