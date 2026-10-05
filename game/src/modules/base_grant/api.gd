class_name BaseGrantApi
extends RefCounted

## Public facade for the `base_grant` module. Other modules may reference ONLY this file
## (`api.gd`).
##
## One sanctioned way to move a base attribute, and nothing else. `core/actor_stats.gd`
## already publishes `set_base`; what was missing is the GATE around it. A doctrine board
## row that says "+1 physique" had no verb to call, and the one branch in the tree that
## read like it already existed — `ItemUse._apply_learned`'s `set_base` loop — is
## unreachable, because `ItemActivation.BY_CATEGORY` maps exactly one category to
## `LEARNED` and `_apply_learned` sends it to `_study_technique` on its first line.
##
## ## What this module is, in three lines
##
##   - The verbs are [method grant] (the one mutator), [method preview], [method state]
##     and [method summary]. Nothing else writes.
##   - The gate is `BaseGrantRequest`, and it is ONE inequality: `net = gains - costs`,
##     and a `net > 0` must be PAID FOR out of a named pool. The whole reasoning, the
##     closed reason set and the ADR citations live there rather than being restated here.
##   - The write is one `set_base` per touched attribute through core, then
##     `Actor.mark_stats_dirty()` — once, after the pool debit. No modifier, no provider,
##     no second stat composer, and no realm id anywhere (ADR 0273).
##
## ## What this module deliberately is not
##
##   - **Not an item channel.** `items/` is not touched and does not gain a verb. A
##     doctrine board, a rite and a future quest line all reach this instead.
##   - **Not a magnitude.** No method takes a realm id and returns a multiplier; there is
##     nowhere in this module to put a fourth magnitude table.
##   - **Not a clock.** Nothing here reads `Time.get_ticks*`, declares `_process` or calls
##     `get_tree()` (DEF-0111). A grant is one caller-initiated press.
##
## ## `preview` and `grant` cannot disagree
##
## Both call the same `BaseGrantRequest.evaluate`. `preview` stops there; `grant` applies
## the plan that call produced. There is no second validation path to drift, so a panel
## that greyed out a row greys out the row that would actually be refused.
##
## ## Three-state vocabulary
##
## A null actor answers `{}` from [method state]/[method summary] and a named refusal
## from [method grant]/[method preview] — "does not exist" is never a reason string
## (ADR 0083).

## `actor.module_data` key the press counter is persisted under.
const MODULE_KEY := BaseGrantRequest.MODULE_KEY

## The RATE bound: presses one `source` may make against one actor. See
## `BaseGrantRequest.MAX_GRANTS_PER_SOURCE` — re-exported so a panel reads one constant.
const MAX_GRANTS_PER_SOURCE := BaseGrantRequest.MAX_GRANTS_PER_SOURCE

## The closed refusal set, the keys every answer carries, and the request vocabulary.
##
## Each reason is re-exported by NAME rather than reachable only through the closed list,
## because a caller COMPARES a value — a panel greying a row, a test asserting a refusal —
## and `answer["reason"] == REASONS[4]` is a coupling to an array index. There is one
## definition: these alias `BaseGrantRequest`, so the list and the constants cannot drift.
const REASONS: Array[String] = BaseGrantRequest.REASONS
const ANSWER_KEYS: Array[StringName] = BaseGrantRequest.ANSWER_KEYS
const REQUEST_KEYS: Array[StringName] = BaseGrantRequest.REQUEST_KEYS

const REASON_NO_ACTOR := BaseGrantRequest.REASON_NO_ACTOR
const REASON_UNSOURCED := BaseGrantRequest.REASON_UNSOURCED
const REASON_NO_GAIN := BaseGrantRequest.REASON_NO_GAIN
const REASON_UNKNOWN_ATTRIBUTE := BaseGrantRequest.REASON_UNKNOWN_ATTRIBUTE
const REASON_BAD_AMOUNT := BaseGrantRequest.REASON_BAD_AMOUNT
const REASON_UNPAID := BaseGrantRequest.REASON_UNPAID
const REASON_UNKNOWN_POOL := BaseGrantRequest.REASON_UNKNOWN_POOL
const REASON_INSUFFICIENT := BaseGrantRequest.REASON_INSUFFICIENT
const REASON_BELOW_FLOOR := BaseGrantRequest.REASON_BELOW_FLOOR
const REASON_BUDGET_SPENT := BaseGrantRequest.REASON_BUDGET_SPENT


## Move `request`'s base attributes on `actor`. The sanctioned verb, and the only one.
##
## `request` speaks [constant REQUEST_KEYS] and nothing else:
##
##   - `source` — `String`, required and non-empty. Who is granting. It is the press
##     counter's key and the audit trail, so an empty one is refused rather than defaulted
##     to "anonymous": every other module in this repo names a `source` for the same
##     reason a `StatModifier` carries one.
##   - `gains` — `{String stat_id: float}`, required and non-empty. Base attributes to
##     RAISE. A value at or below `0.0` is `bad_amount`.
##   - `costs` — `{String stat_id: float}`, optional. Base attributes to LOWER: the
##     transfer half and the yin-yang counterpart.
##   - `cost_pool` / `cost_amount` — the visible cost, debited from a real `ResourcePool`.
##     Required together whenever `net > 0`, and `cost_amount` must be at least `net`.
##
## Returns every key in [constant ANSWER_KEYS]. On a refusal the actor is untouched and
## `applied` is `false`; on success `granted` carries the SIGNED deltas that landed, so a
## transfer reads as `{"physique": 1.0, "agility": -1.0}` rather than as two lists a
## caller has to subtract.
static func grant(actor: Actor, request: Dictionary) -> Dictionary:
	if actor == null:
		return BaseGrantRequest.evaluate(null, request, 0)
	var source := str(request.get("source", ""))
	var ledger := BaseGrantLedger.normalize(actor.get_module_data(MODULE_KEY))
	var verdict := BaseGrantRequest.evaluate(actor, request, BaseGrantLedger.used(ledger, source))
	if not bool(verdict["ok"]):
		return verdict
	_apply(actor, verdict["plan"] as Dictionary)
	verdict["applied"] = true
	verdict.erase("plan")
	return verdict


## What [method grant] would do to `actor`, and whether it would do it at all. Never
## mutates and never charges — the panel asks, the press answers.
##
## Same shape and same gates as [method grant], because both are one `evaluate`; the only
## difference is `applied`, which is always `false` here and which no `plan` ever reaches.
static func preview(actor: Actor, request: Dictionary) -> Dictionary:
	var used := 0
	if actor != null:
		used = BaseGrantLedger.used(
			BaseGrantLedger.normalize(actor.get_module_data(MODULE_KEY)),
			str(request.get("source", ""))
		)
	var verdict := BaseGrantRequest.evaluate(actor, request, used)
	verdict.erase("plan")
	return verdict


## The persisted press ledger exactly as core stores it, normalised. What a save carries.
## `{}` for a null actor, which is ADR 0083's "does not exist" rather than a failure.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return BaseGrantLedger.normalize(actor.get_module_data(MODULE_KEY))


## The read model a panel tests instead of pixels: this actor's id, the rate bound, the
## presses already spent per source, and the closed reason set. Primitics only, one level
## of nesting. `{}` for a null actor.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var spent: Dictionary = {}
	var grants: Variant = state(actor).get(BaseGrantLedger.KEY_GRANTS, {})
	if grants is Dictionary:
		# Snapshotted by the `for`; the body writes to `spent`, never to the map it walks
		# (INC-0002).
		for key in (grants as Dictionary).keys():
			spent[str(key)] = int((grants as Dictionary)[key])
	return {
		"actor_id": String(actor.id),
		"grants_max": MAX_GRANTS_PER_SOURCE,
		"grants_spent": spent,
		"reasons": REASONS.duplicate(),
	}


## Write the plan `BaseGrantRequest.evaluate` already validated.
##
## The ONLY place in this module that touches the actor, and it cannot half-apply: every
## gate — the rate bound, the yin-yang gate, the pool's existence and balance, and the
## `0.0` floor on every touched attribute — is behind us before this is reachable. The
## `keys()` of both maps are snapshotted by their own `for` and neither body writes into
## the map it walks (INC-0002).
static func _apply(actor: Actor, plan: Dictionary) -> void:
	var deltas: Dictionary = plan["deltas"]
	for key in deltas.keys():
		var id := StringName(str(key))
		actor.stats.set_base(id, actor.stats.get_base(id) + float(deltas[key]))
	var cost: Dictionary = plan["cost"]
	for key in cost.keys():
		var pool := actor.resource(StringName(str(key)))
		if pool != null:
			pool.change(-float(cost[key]))
	actor.set_module_data(
		MODULE_KEY, BaseGrantLedger.record(actor.get_module_data(MODULE_KEY), str(plan["source"]))
	)
	# ONE dirty mark for the whole grant, after the pool debit, so a panel listening to
	# `stats_changed` reads a finished transaction rather than a half-written one.
	actor.mark_stats_dirty()
