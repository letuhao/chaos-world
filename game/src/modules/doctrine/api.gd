class_name DoctrineApi
extends RefCounted

## Public facade for the `doctrine` module (ADR 0267). Other modules may reference ONLY
## this file (`api.gd`).
##
## A System (道統) is a transmitted body of rules a practitioner opts into, farms on its own
## counter and spends on a board. The rule itself is `DoctrineRule` in `contracts/`; this
## module owns the REGISTRY, the LEDGER and the ARBITRATION, and the three responsibilities
## are one thing because a System nobody registered has no board to read and a balance nobody
## arbitrated is a money printer.
##
## ## The verbs, and what each one is for
##
##   - [method attach] — admit one System, or refuse it by name. The registration gate.
##   - [method rules] — what is registered, read from the declaration alone.
##   - [method available] — the rows a join screen draws: every registered System and whether
##     this actor has joined it.
##   - [method join] / [method leave] — opt in and opt out. `leave` is the price-bearing half.
##   - [method earn] — apply an occurrence to the joined Systems. The ARBITER.
##   - [method boards] / [method price] — the catalogue and the live quote.
##   - [method redeem] — one press, one row, one transaction.
##   - [method state] / [method summary] — the persisted ledger and the read model.
##
## ## Why `earn` arbitrates here and `redeem` does not
##
## An earn is event-driven and two Systems may answer the same occurrence, so the arbitration
## belongs to whoever owns the event — ADR 0067's proposal, ADR 0114's `resolve`. This facade
## is that caller, so it arbitrates, and the rule is **the largest claim on the occurrence
## takes it**: `amount` is the only scalar a proposal carries, so the biggest one is the biggest
## claim, and the answer does not depend on the order the registry happens to hold. A spend is
## the opposite — one player press, one row, one self-contained transaction — so it is applied
## straight through and needs no arbiter.
##
## ## Why there is no per-actor `attach`
##
## Every other module's first verb binds the module to an actor. This one cannot, because
## there is nothing to bind: a System's ledger is created by [method join] and normalized on
## every read, so an actor who never joined reads a default and an actor who loaded a save
## reads their own. A verb that restored a snapshot nobody had would be a verb with no case.
##
## ## What this module deliberately does NOT do
##
## It never ticks, never reads a clock and never reaches the scene tree (DEF-0111). A System is
## exactly the thing that wants a tick, and an institution that owns one accrues on wall time.
## Every accrual is one caller-initiated [method earn], so "how much has this System earned" is
## a question with a caller and never a question with a timer.
##
## ## The refusal vocabulary, mapped
##
## `DoctrineRule.REASONS` is closed and extending it is an ADR, so a facade refusal picks the
## nearest honest member rather than inventing a sixth string:
##
##   - `NOT_CLAIMED` — nothing is claimed here: no such System, an unnamed one, a System whose
##     payload does not carry the keys the contract declares, or an actor who has not joined.
##   - `ALREADY_MAXED` — this state is already at its maximum: joined twice, or a row that is
##     not repeatable and has already been bought.
##   - `TIER_LOCKED` — the row's tier band is above this counter's tier.
##   - `UNDECLARED_POOL` — the pool is not one this System declared, or it is core's, or it has
##     no row that spends it.
##   - `INSUFFICIENT` — the balance is short.
##
## `{}` never means any of those: it means the System or the row does not exist (ADR 0083).


## Admit `rule`, or refuse it by name. See [DoctrineRegistry.attach] for what it checks and
## why registration rather than lookup is the gate. The one verb a module, a template or a mod
## calls to add a System, and the only way a System enters the game.
static func attach(rule: Variant) -> Dictionary:
	return DoctrineRegistry.attach(rule)


## Every registered System's declaration, in registration order, as primitives. Reads no actor
## and calls none of the rule's actor-taking methods, so it is safe on a boot with no world.
static func rules() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# `ids()` is a copy taken before the walk, so nothing a rule answers can grow it (INC-0002).
	for id in DoctrineRegistry.ids():
		var rule := DoctrineRegistry.find(id)
		if rule == null:
			continue
		var pools: Array[String] = []
		for pool in rule.resource_ids():
			pools.append(String(pool))
		(
			out
			. append(
				{
					"system_id": String(id),
					"display_name": rule.display_name(),
					"data_key": String(rule.data_key()),
					"pools": pools,
					"pool_count": pools.size(),
				}
			)
		)
	return out


## The rows a join screen draws: every registered System, whether this actor has joined it,
## and the live facts a row labels itself with. Empty for a null actor and empty for an empty
## registry — both are ordinary states, not errors.
static func available(actor: Actor) -> Array[Dictionary]:
	if actor == null:
		return []
	var out: Array[Dictionary] = []
	for id in DoctrineRegistry.ids():
		var rule := DoctrineRegistry.find(id)
		if rule == null:
			continue
		out.append(_system_view(actor, id, rule))
	return out


## Opt `actor` into `system_id`. `{}` when no such System is registered — the three-state
## vocabulary's "does not exist", which is not a refusal (ADR 0083).
##
## A second join is `ALREADY_MAXED`: this actor's state for this System is already as joined
## as it gets. Nothing is charged, because the price of [method join] is the counter starting
## at zero and every tier band above it being locked.
static func join(actor: Actor, system_id: StringName) -> Dictionary:
	var rule := _rule(system_id)
	if actor == null or rule == null:
		return {}
	if _is_joined(actor, rule):
		return _refused(DoctrineRule.ALREADY_MAXED, system_id)
	_store(actor, rule, DoctrineLedger.joined(_ledger(actor, rule)))
	return {
		"ok": true,
		"reason": "",
		"system_id": String(system_id),
		"data_key": String(rule.data_key())
	}


## Opt `actor` out of `system_id`, forfeiting the counter, the tier bands it reached and every
## unspent coin — the counterpart that makes [method join] a decision rather than a free
## re-accumulation. `{}` for a System that does not exist; `NOT_CLAIMED` for one this actor is
## not in. Granted rows are NOT reversed: see [method DoctrineLedger.left].
static func leave(actor: Actor, system_id: StringName) -> Dictionary:
	var rule := _rule(system_id)
	if actor == null or rule == null:
		return {}
	if not _is_joined(actor, rule):
		return _refused(DoctrineRule.NOT_CLAIMED, system_id)
	_store(actor, rule, DoctrineLedger.left(_ledger(actor, rule)))
	return {
		"ok": true,
		"reason": "",
		"system_id": String(system_id),
		"data_key": String(rule.data_key())
	}


## Apply one `event` occurrence. With `system_id` empty every JOINED System is asked, and the
## largest claim takes the occurrence while the rest are declined — with `system_id` named only
## that System is asked, so a caller that wants one System's answer gets exactly it.
##
## Returns `{ok, reason, applied, declined, candidate_count}` and applies nothing when `ok` is
## false, so a caller can report the refusal and know nothing moved. Every System's `earn` is a
## PURE proposal by contract, so asking all of them costs nothing but the walk.
##
## ## The walk is over a snapshot
##
## The candidate list is built first and then walked. A rule asked for a proposal could
## otherwise register a System — or leave — and grow or shrink the list under the loop, which
## is INC-0002's shape with an extra step. Asking is free and applying is the only write.
static func earn(actor: Actor, event: Dictionary, system_id: StringName = &"") -> Dictionary:
	var candidates := _candidates(actor, event, system_id)
	if candidates.is_empty():
		return _earn_answer(false, DoctrineRule.NOT_CLAIMED, [], [], 0)
	var applied: Array[Dictionary] = []
	var declined: Array[Dictionary] = []
	# Snapshotted by the `for` itself and nothing is appended to it: the two lists grow while
	# `candidates` does not, so the walk cannot outrun its input (INC-0002).
	for entry in candidates:
		var claim: Dictionary = entry["proposal"]
		if bool(claim["ok"]) and float(claim["amount"]) > 0.0:
			(
				applied
				. append(
					{
						"system_id": String(entry["system_id"]),
						"pool": String(claim.get("pool", "")),
						"amount": float(claim["amount"]),
					}
				)
			)
		else:
			declined.append(_declined(entry, String(claim.get("reason", DoctrineRule.NOT_CLAIMED))))
	# The index rather than the row: `Dictionary` equality is reference identity, so
	# comparing rows to find the winner would be comparing the only object the framework
	# made by whether it is the same object, which is true of exactly one of them by
	# construction and says nothing about the amounts.
	var winner_index := _largest(applied)
	if winner_index < 0:
		return _earn_answer(false, _first_reason(declined), [], declined, candidates.size())
	for index in applied.size():
		if index != winner_index:
			(
				declined
				. append(
					{
						"system_id": String(applied[index]["system_id"]),
						"reason": DoctrineRule.NOT_CLAIMED,
					}
				)
			)
	var winner := applied[winner_index]
	var rule := DoctrineRegistry.find(StringName(winner["system_id"]))
	var booked := DoctrineLedger.credit(
		_ledger(actor, rule),
		rule.resource_ids(),
		StringName(winner["pool"]),
		float(winner["amount"])
	)
	if not bool(booked["ok"]):
		return _earn_answer(false, String(booked["reason"]), [], declined, candidates.size())
	_store(actor, rule, booked["ledger"])
	return _earn_answer(true, "", [winner], declined, candidates.size())


## The rows `system_id` sells `actor`, verbatim from the rule. A catalogue read: it answers
## for an actor who has NOT joined, because a join screen has to draw what joining would offer.
## Use [method price] for what a row costs this actor RIGHT NOW — `owned` and `affordable` are
## live and cannot be derived from a row. Empty for a System that does not exist.
static func boards(actor: Actor, system_id: StringName) -> Array[Dictionary]:
	var rule := _rule(system_id)
	if rule == null or actor == null:
		return []
	return rule.boards(actor)


## What `row_id` costs `actor` right now. `{}` when the System or the row does not exist;
## otherwise every key in `DoctrineRule.PRICE_KEYS`, refusal included.
##
## The row is looked up BEFORE the opt-in is checked, because ADR 0083's first state is
## "does not exist" and a row this System does not sell does not exist whether or not the
## actor has joined it. Getting that order wrong is how a panel draws a refusal on a row that
## was never there.
##
## An unjoined actor is `NOT_CLAIMED` rather than a price: `owned` and `affordable` would both
## be answering about a state the actor is not in, and a quote for a System you are not in is
## the number a panel would draw on a row that cannot be pressed.
static func price(actor: Actor, system_id: StringName, row_id: StringName) -> Dictionary:
	var rule := _rule(system_id)
	if rule == null or actor == null:
		return {}
	var quoted := rule.price(actor, row_id)
	if quoted.is_empty():
		return {}
	if not _is_joined(actor, rule):
		return _price_answer(false, DoctrineRule.NOT_CLAIMED, row_id)
	return quoted


## Spend `row_id` for `actor` and grant what it says. `{}` when the System or the row does not
## exist; otherwise the rule's own answer, carrying every key in `DoctrineRule.REDEEM_KEYS`.
##
## ## The affordability check runs BEFORE the rule's writer, on purpose
##
## `redeem` is the rule's one mutator and it grants through `Actor.add_status` the moment it
## is called. If the framework booked the spend afterwards and found the balance short, the
## grant would already have landed and the coin would never have left — a free row. So the
## quote is read first and a refusal is returned without the rule ever writing. The booking
## after the call is therefore the redundant path, kept because a redundant write that cannot
## happen is cheaper than one that can.
static func redeem(actor: Actor, system_id: StringName, row_id: StringName) -> Dictionary:
	var rule := _rule(system_id)
	if actor == null or rule == null:
		return {}
	if not _is_joined(actor, rule):
		return _redeem_answer(false, DoctrineRule.NOT_CLAIMED, row_id)
	var quoted := rule.price(actor, row_id)
	if quoted.is_empty():
		return {}
	if not bool(quoted.get("ok", false)):
		return _redeem_answer(false, String(quoted.get("reason", DoctrineRule.NOT_CLAIMED)), row_id)
	var answer := rule.redeem(actor, row_id)
	if answer.is_empty():
		return {}
	if not bool(answer.get("ok", false)):
		return answer
	# The ROW is the price, not the rule's report of it: `spent` is passed through for the
	# caller and the ledger is debited the amount the board published, so a rule that
	# under-reports its own cost cannot mint a row for nothing.
	var booked := DoctrineLedger.debit(
		_ledger(actor, rule),
		rule.resource_ids(),
		StringName(answer.get("pool", "")),
		_row_amount(rule, actor, row_id)
	)
	if bool(booked["ok"]):
		_store(actor, rule, booked["ledger"])
		return answer
	return _redeem_answer(false, String(booked["reason"]), row_id)


## Every System's ledger exactly as core persists it, keyed by system id. The payload a save
## carries, so a caller never reaches into `actor.module_data`. A null actor reads as the
## skeleton for no Systems rather than as a failure.
static func state(actor: Actor) -> Dictionary:
	var out := {}
	for id in DoctrineRegistry.ids():
		var rule := DoctrineRegistry.find(id)
		if rule == null:
			continue
		out[String(id)] = DoctrineLedger.normalize({}) if actor == null else _ledger(actor, rule)
	return out


## The whole read model in one call, primitives only: the Systems, each one's ledger summary,
## the union of every declared pool, and the closed reason set a panel compares against. `{}`
## when there is no actor — the contract a panel tests instead of pixels.
##
## No board row is nested under a System here, and that is a depth budget rather than a taste:
## `DoctrineRule.is_primitive_payload` refuses past `MAX_PAYLOAD_DEPTH = 4`, and a row already
## sits three levels down. `boards()` and `price()` are the verbs that carry rows.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var systems: Dictionary = {}
	var pools: Array[String] = []
	var joined_count := 0
	for id in DoctrineRegistry.ids():
		var rule := DoctrineRegistry.find(id)
		if rule == null:
			continue
		var view := _system_view(actor, id, rule)
		if bool(view["joined"]):
			joined_count += 1
		systems[String(id)] = view
		for pool in rule.resource_ids():
			var name := String(pool)
			if not pools.has(name):
				pools.append(name)
	return {
		"actor_id": String(actor.id),
		"system_count": DoctrineRegistry.count(),
		"joined_count": joined_count,
		"pools": pools,
		"reasons": DoctrineRule.REASONS.duplicate(),
		"systems": systems,
	}


# --- Internals -------------------------------------------------------------


## One System's row for `available()` and `summary()`. Keys are chosen so the whole nested
## payload stays inside `MAX_PAYLOAD_DEPTH`: primitives only, no `balances` map and — under
## `summary` — no `pools` array either, because `summary().systems.<id>` already sits three
## levels down and an array of strings under it is the fourth value the contract refuses.
## `with_pools` therefore drops it for `summary` and keeps it for `available`, whose rows are
## a flat array with two levels to spare.
static func _system_view(
	actor: Actor, id: StringName, rule: DoctrineRule, with_pools: bool
) -> Dictionary:
	var ledger := _ledger(actor, rule)
	var progress := rule.progress(actor)
	var tier := rule.tier_for(actor)
	var view := {
		"system_id": String(id),
		"display_name": rule.display_name(),
		"data_key": String(rule.data_key()),
		"joined": bool(ledger[DoctrineLedger.KEY_JOINED]),
		"points": int(progress.get("points", 0)),
		"points_max": int(progress.get("points_max", 0)),
		"tier": int(tier.get("tier", 0)),
		"tier_name": str(tier.get("tier_name", "")),
		"tiers": int(tier.get("tiers", 0)),
		"next_tier_points": int(tier.get("next_tier_points", 0)),
		"row_count": rule.boards(actor).size(),
		"balance": float(ledger[DoctrineLedger.KEY_BALANCE]),
		"earnings": int(ledger[DoctrineLedger.KEY_EARNINGS]),
		"redemptions": int(ledger[DoctrineLedger.KEY_REDEMPTIONS]),
	}
	if with_pools:
		var pools: Array[String] = []
		for pool in rule.resource_ids():
			pools.append(String(pool))
		view["pools"] = pools
	return view


## `{rule, system_id, proposal}` per candidate, built BEFORE anything is applied. Naming
## `system_id` restricts the question to one System; leaving it empty asks every joined one,
## because a System nobody joined has no balance to credit.
static func _candidates(actor: Actor, event: Dictionary, system_id: StringName) -> Array:
	var out: Array = []
	if actor == null:
		return out
	for id in DoctrineRegistry.ids():
		if system_id != &"" and id != system_id:
			continue
		var rule := DoctrineRegistry.find(id)
		if rule == null:
			continue
		if system_id == &"" and not _is_joined(actor, rule):
			continue
		out.append({"rule": rule, "system_id": id, "proposal": rule.earn(actor, event)})
	return out


## The INDEX of the biggest claim, or `-1` when nothing claimed. On a tie the earliest wins:
## the walk is in registration order and the comparison is strict, so the answer is the same
## on every run without consulting a clock (DEF-0111) or a random source.
static func _largest(claims: Array[Dictionary]) -> int:
	var best := -1
	for index in claims.size():
		if best < 0 or float(claims[index]["amount"]) > float(claims[best]["amount"]):
			best = index
	return best


static func _row_amount(rule: DoctrineRule, actor: Actor, row_id: StringName) -> float:
	# `boards()` hands back the rule's own arrays and this walk appends to nothing, so the
	# lookup terminates on whatever the rule authored (INC-0002).
	for row in rule.boards(actor):
		if StringName(row.get("row_id", "")) == row_id:
			return float(row.get("amount", 0.0))
	return 0.0


static func _rule(system_id: StringName) -> DoctrineRule:
	return DoctrineRegistry.find(system_id)


static func _ledger(actor: Actor, rule: DoctrineRule) -> Dictionary:
	return DoctrineLedger.normalize(actor.get_module_data(rule.data_key()))


static func _store(actor: Actor, rule: DoctrineRule, ledger: Dictionary) -> void:
	actor.set_module_data(rule.data_key(), ledger)


static func _is_joined(actor: Actor, rule: DoctrineRule) -> bool:
	return bool(_ledger(actor, rule)[DoctrineLedger.KEY_JOINED])


static func _refused(reason: String, system_id: StringName) -> Dictionary:
	return {"ok": false, "reason": reason, "system_id": String(system_id)}


static func _earn_answer(
	ok: bool, reason: String, applied: Array[Dictionary], declined: Array[Dictionary], count: int
) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"applied": applied,
		"declined": declined,
		"candidate_count": count,
	}


static func _declined(entry: Dictionary, reason: String) -> Dictionary:
	return {"system_id": String(entry["system_id"]), "reason": reason}


## The first named reason among the declines, or `NOT_CLAIMED` when none named one. A facade
## level `reason` exists so a caller can compare ONE value; the per-System detail is in
## `declined`.
static func _first_reason(declined: Array[Dictionary]) -> String:
	for row in declined:
		var reason := String(row["reason"])
		if reason != "":
			return reason
	return DoctrineRule.NOT_CLAIMED


static func _price_answer(ok: bool, reason: String, row_id: StringName) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"row_id": String(row_id),
		"pool": "",
		"amount": 0.0,
		"owned": 0,
		"affordable": false,
	}


static func _redeem_answer(ok: bool, reason: String, row_id: StringName) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"row_id": String(row_id),
		"pool": "",
		"spent": 0.0,
		"granted": [],
	}
