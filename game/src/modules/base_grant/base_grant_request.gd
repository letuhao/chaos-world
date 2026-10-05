class_name BaseGrantRequest
extends RefCounted

## A grant REQUEST: the whole vocabulary a caller may speak, and the one gate that reads
## it. Lives beside `api.gd` rather than in it because "what shape may a grant be" and
## "what may a grant do to an actor" are two reasons to change — a new request key moves
## this file and touches no verb.
##
## ## The gate, stated once
##
## `raised` is the sum of `gains`, `removed` the sum of `costs`, `net = raised - removed`:
##
##   - **`net <= 0` is a TRANSFER.** Legal with no payment. Base magnitude moves between
##     attributes and nobody is stronger afterwards, so there is no advantage left to
##     answer. This is the half with no precedent in the tree: nothing else subtracts
##     from a base stat.
##   - **`net > 0` is a PURCHASE.** Legal only when the request names a `cost_pool` and
##     pays at least `net` out of it.
##
## One inequality, checked before anything is written. A one-sided "+1 physique" with no
## cost is `UNPAID`, which is AGENTS.md's yin-yang rule as an executable refusal rather
## than a review note a future agent has to remember. `costs` can never launder a gain,
## because its total is subtracted FIRST: "+100 physique, -1 agility" is still `net == 99`
## and still has to pay for 99.
##
## ## What is bounded here, and what deliberately is not (ADR 0200)
##
## **Nothing in this file bounds a base attribute.** A base attribute is a magnitude that
## has to climb with a 551x ladder, so a ceiling on one is the defect ADR 0200 exists to
## remove — and a ceiling on the per-grant AMOUNT would be a ceiling on an INPUT, the
## same defect in a different hat. The authored amount is free and stays free.
##
## The only bound is the press COUNT in `BaseGrantLedger`, which is a rate and not a
## magnitude: it caps how fast one source injects permanent power into a save, and it
## cannot die as the ladder grows because it never multiplies anything.

## `actor.module_data` key the press counter is persisted under.
const MODULE_KEY := &"base_grants"

## The RATE bound: how many times one `source` may be granted against one actor.
##
## Not a balance number. A board is authored content, so this sits deliberately far above
## any board a System will ship; it exists so a save cannot be pumped by pressing one row
## forever, not so a designer is stopped.
const MAX_GRANTS_PER_SOURCE := 64

## Float slack on every comparison. Authored decimals do not sum exactly — a hand-written
## `0.3 + 0.7` is not `1.0` — so a gate compared with `==` would refuse a request that
## has been paid for in full. It is a comparison tolerance, not a rounding rule: nothing
## here rounds a value a caller reads back.
const EPSILON := 0.0001

## `actor` is null, so there is nothing to move.
const REASON_NO_ACTOR := "no_actor"
## The request names no `source`. A permanent base write with no provenance cannot be
## audited, cannot be budgeted, and cannot be explained to a player afterwards.
const REASON_UNSOURCED := "unsourced"
## `gains` is absent, empty, or every delta nets to zero: there is nothing to grant.
## `ok` there would be BL-0110 — the verb consumed a press and the actor is identical
## afterwards.
const REASON_NO_GAIN := "no_gain"
## A `gains`/`costs` key that is not in `Stat.BASE_ATTRIBUTES`. The answer carries
## `unknown_attribute` so the caller is told WHICH id, because a silent `0.0` for a typo'd
## attribute is the failure mode this exists to remove.
const REASON_UNKNOWN_ATTRIBUTE := "unknown_attribute"
## A gain at or below zero, a negative cost, or a `cost_amount` that is missing or
## non-positive. Refused rather than clamped: a zero "gain" is a no-op wearing a gain's
## name and a zero cost is a cost of nothing.
const REASON_BAD_AMOUNT := "bad_amount"
## The yin-yang gate: `net > 0` and the request either named no pool or paid less than
## the gain. Paying less is `UNPAID` rather than a discount deliberately — two presses of
## "+1 physique for 0.5" are "+2 physique for 1", which is the loophole a partial payment
## opens.
const REASON_UNPAID := "unpaid"
## `cost_pool` named, but the actor has no such pool. Distinct from `INSUFFICIENT` so a
## typo is never reported as a broke actor.
const REASON_UNKNOWN_POOL := "unknown_pool"
## The named pool holds less than `cost_amount`.
const REASON_INSUFFICIENT := "insufficient"
## A `costs` entry would drive a base attribute below `0.0`. The transfer floor, checked
## against the POST value rather than the delta, because a gain and a cost may name the
## same attribute and the net is what lands.
const REASON_BELOW_FLOOR := "below_floor"
## This source has already made `MAX_GRANTS_PER_SOURCE` presses.
const REASON_BUDGET_SPENT := "budget_spent"

## Every reason above, as one list, so a caller validates against one set rather than
## keeping a second copy — the decay BL-0619 is about. `reason` is `""` on success.
const REASONS: Array[String] = [
	REASON_NO_ACTOR,
	REASON_UNSOURCED,
	REASON_NO_GAIN,
	REASON_UNKNOWN_ATTRIBUTE,
	REASON_BAD_AMOUNT,
	REASON_UNPAID,
	REASON_UNKNOWN_POOL,
	REASON_INSUFFICIENT,
	REASON_BELOW_FLOOR,
	REASON_BUDGET_SPENT,
]

## The keys every `grant`/`preview` answer carries — always, including on a refusal, so a
## caller has ONE payload shape to parse for the case it cares about.
const ANSWER_KEYS: Array[StringName] = [
	&"ok",
	&"reason",
	&"source",
	&"granted",
	&"cost",
	&"before",
	&"after",
	&"grants_used",
	&"grants_left",
	&"applied",
]

## The whole vocabulary a caller may speak. A key outside this list is ignored, and there
## is deliberately NO realm key: a magnitude has nowhere to live (ADR 0273).
const REQUEST_KEYS: Array[StringName] = [
	&"source",
	&"gains",
	&"costs",
	&"cost_pool",
	&"cost_amount",
]


## Read `request` against `actor` and answer without writing anything.
##
## Returns the full answer shape carrying every key in [constant ANSWER_KEYS], plus
## `"plan"` — the write [method BaseGrantApi._apply] will perform — ONLY when `ok`. A
## refusal has no plan at all, which is the structural form of "a refused grant leaves the
## actor untouched": there is nothing for a caller to apply even if it ignored `ok`.
##
## Every walk below is a `for` over a caller-supplied dictionary that the body never
## writes to, so each terminates on whatever the caller passed (INC-0002). There is no
## `while` in this file.
static func evaluate(actor: Actor, request: Dictionary, used: int) -> Dictionary:
	if actor == null:
		return _refused(REASON_NO_ACTOR, &"", 0)
	var source := str(request.get("source", ""))
	if source == "":
		return _refused(REASON_UNSOURCED, &"", 0)
	# The rate bound is a property of the SOURCE rather than of this request, so it is
	# answered before the request is read: a board that has spent its budget should say so
	# rather than report whatever the caller's request happened to be short of.
	if used >= MAX_GRANTS_PER_SOURCE:
		return _refused(REASON_BUDGET_SPENT, StringName(source), used)

	var raw_gains: Variant = request.get("gains", {})
	if not raw_gains is Dictionary or (raw_gains as Dictionary).is_empty():
		return _refused(REASON_NO_GAIN, StringName(source), used)
	var raw_costs: Variant = request.get("costs", {})
	var costs: Dictionary = raw_costs if raw_costs is Dictionary else {}

	var deltas: Dictionary = {}
	var raised := 0.0
	for key in (raw_gains as Dictionary).keys():
		var id := StringName(str(key))
		if not Stat.BASE_ATTRIBUTES.has(id):
			return _unknown(REASON_UNKNOWN_ATTRIBUTE, id, StringName(source), used)
		var amount := float((raw_gains as Dictionary)[key])
		if amount <= 0.0:
			return _refused(REASON_BAD_AMOUNT, StringName(source), used)
		deltas[String(id)] = amount
		raised += amount
	var removed := 0.0
	for key in costs.keys():
		var id := StringName(str(key))
		if not Stat.BASE_ATTRIBUTES.has(id):
			return _unknown(REASON_UNKNOWN_ATTRIBUTE, id, StringName(source), used)
		var amount := float(costs[key])
		if amount < 0.0:
			return _refused(REASON_BAD_AMOUNT, StringName(source), used)
		if amount == 0.0:
			continue
		deltas[String(id)] = float(deltas.get(String(id), 0.0)) - amount
		removed += amount

	if not _moves(deltas):
		# "+1 will, -1 will" asks for nothing, and `ok` on a grant that moves nothing is
		# BL-0110: the verb consumed a press and the actor is identical afterwards.
		return _refused(REASON_NO_GAIN, StringName(source), used)

	var net := raised - removed
	var charge := _charge(actor, request, source, used, net)
	if not bool(charge["ok"]):
		return charge

	var before: Dictionary = {}
	var after: Dictionary = {}
	for key in deltas.keys():
		var id := StringName(str(key))
		var start := actor.stats.get_base(id)
		var end := start + float(deltas[key])
		if end < 0.0:
			return _unknown(REASON_BELOW_FLOOR, id, StringName(source), used)
		before[String(id)] = start
		after[String(id)] = end

	return {
		"ok": true,
		"reason": "",
		"source": source,
		"granted": deltas.duplicate(),
		"cost": charge["cost"],
		"before": before,
		"after": after,
		"grants_used": used,
		"grants_left": maxi(0, MAX_GRANTS_PER_SOURCE - used - 1),
		"applied": false,
		"plan": {"deltas": deltas, "cost": charge["cost"], "source": source},
	}


## What this request pays, and whether it can. The purchase half of the gate.
##
## `net <= 0` pays nothing — a transfer is its own answer — so a bare `costs` map is a
## COMPLETE request. `net > 0` must name a pool and pay at least `net`, and the pool is
## resolved HERE rather than at apply time so a refusal names the real reason instead of a
## downstream one.
static func _charge(
	actor: Actor, request: Dictionary, source: String, used: int, net: float
) -> Dictionary:
	var pool_id := StringName(str(request.get("cost_pool", "")))
	var amount := float(request.get("cost_amount", 0.0))
	if net <= 0.0 and pool_id == &"":
		return {"cost": {}, "ok": true}
	if pool_id == &"":
		return _refused(REASON_UNPAID, StringName(source), used)
	if amount <= 0.0:
		return _refused(REASON_BAD_AMOUNT, StringName(source), used)
	if net > 0.0 and amount + EPSILON < net:
		return _refused(REASON_UNPAID, StringName(source), used)
	var pool := actor.resource(pool_id)
	if pool == null:
		return _refused(REASON_UNKNOWN_POOL, StringName(source), used)
	if pool.current + EPSILON < amount:
		return _refused(REASON_INSUFFICIENT, StringName(source), used)
	return {"cost": {String(pool_id): amount}, "ok": true}


## Whether any entry in `deltas` is a non-zero move. A snapshot-free walk: the body reads
## and returns, and writes to nothing, so it terminates on the caller's own map (INC-0002).
static func _moves(deltas: Dictionary) -> bool:
	for key in deltas.keys():
		if absf(float(deltas[key])) > EPSILON:
			return true
	return false


## A refusal naming WHICH id tripped the gate. Two reasons are only diagnosable by the id —
## `unknown_attribute` and `below_floor` — and a refusal nobody can diagnose is a bug
## report, so both carry it rather than a re-derivable count.
static func _unknown(reason: String, id: StringName, source: StringName, used: int) -> Dictionary:
	var out := _refused(reason, source, used)
	out[reason] = String(id)
	return out


## A refusal carrying every key in [constant ANSWER_KEYS]. `granted`, `before` and `after`
## are empty because nothing moved — that emptiness IS the guarantee, and a caller can read
## it instead of re-deriving it from `ok`.
static func _refused(reason: String, source: StringName, used: int) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"source": String(source),
		"granted": {},
		"cost": {},
		"before": {},
		"after": {},
		"grants_used": used,
		"grants_left": maxi(0, MAX_GRANTS_PER_SOURCE - used),
		"applied": false,
	}
