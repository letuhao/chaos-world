class_name DoctrineRegistry
extends RefCounted

## The registrable Systems, and the ONLY place a System is admitted.
##
## ## Registration is a gate, not a lookup table
##
## `attach` refuses a System that would make a board wrong before any player sees it: a
## row missing a key a panel draws from, a row spending a pool the System never declared,
## a declared pool no row spends (ADR 0083/AGENTS.md yin-yang — a currency generated with
## nowhere to spend it is an accumulating debt), a payload that is not primitives-only, and
## a System with no `data_key` to persist under. Every refusal names one of
## `DoctrineRule.REASONS`, because extending that closed set is an ADR and a gate cannot
## invent a seventh string.
##
## ## Registration order is the order `ids()` reports, and it is a COPY
##
## `ids()` hands back a duplicate on every call. A rule asked for a proposal during an
## earn that then registered a System could otherwise grow the walk the earn is standing
## on (INC-0002), and the reader of the list must never be able to write through it.
##
## ## Why the whole state is `static var`
##
## A System is registered once at boot by the composition root and read for the rest of
## the process, so a registry instance would have to be threaded through a graph nobody
## threads. `ScreenRegistry.register` is static for the same reason, and `clear()` is here
## so a test can reset the one piece of process-wide state this module owns.

## Registration order. Also the deterministic tie-break for equal earn claims.
static var _order: Array[StringName] = []
static var _rules: Dictionary = {}


## Admit `rule`, or refuse it by name. Idempotent per System: a second `attach` of the
## same id is a refusal rather than a silent replacement, because a System swapped under a
## live board is a board that changed under its reader.
##
## ## The probe actor, and why one is minted per call
##
## Row and payload validation needs an actor, because a rule is free to dereference the
## `Variant` it is handed and a null would abort a boot. The probe is a plain
## `RefCounted` `Actor` with no history, minted per call so a rule that writes during
## `boards` cannot accumulate state on a shared one. It is not cached: registration is a
## boot-time call, and `rules()` needs no actor at all.
static func attach(rule: Variant) -> Dictionary:
	if not rule is DoctrineRule:
		return _refused(DoctrineRule.NOT_CLAIMED, "", "attach takes a DoctrineRule")
	var candidate := rule as DoctrineRule
	var id := candidate.system_id()
	if id == &"":
		return _refused(
			DoctrineRule.NOT_CLAIMED,
			"",
			"an unnamed System has no data_key, so two of them share one save dictionary"
		)
	if candidate.data_key() == &"":
		return _refused(
			DoctrineRule.NOT_CLAIMED, id, "data_key is empty, so the state has nowhere to persist"
		)
	if _rules.has(String(id)):
		return _refused(DoctrineRule.NOT_CLAIMED, id, "already registered")
	var verdict := _validate(candidate, Actor.new(&"doctrine_attach_probe"))
	if not bool(verdict["ok"]):
		return verdict
	_rules[String(id)] = candidate
	_order.append(id)
	return {
		"ok": true, "reason": "", "system_id": String(id), "data_key": String(candidate.data_key())
	}


## The System registered under `system_id`, or `null`. Null rather than a guess: a System
## nothing registered teaches nothing, and inventing one would let a caller pass a gate its
## content never authored.
static func find(system_id: StringName) -> DoctrineRule:
	if system_id == &"":
		return null
	return _rules.get(String(system_id))


## Every registered id, in REGISTRATION order — a copy, so no caller can write through it.
static func ids() -> Array[StringName]:
	return _order.duplicate()


## How many Systems are registered. Read by `summary()` and by the tests; a facade with an
## empty registry must answer this rather than fall over.
static func count() -> int:
	return _order.size()


## Empty the registry. The one piece of process-wide state this module owns, so a test can
## reset it. Production never calls it: a boot that re-registered would be a boot that
## dropped every System.
static func clear() -> void:
	_order.clear()
	_rules.clear()


## Everything a System declared at registration, checked in the order below. The order is
## the design: identity, then the pools (a currency is declared before anything spends
## it), then each row (a panel draws from these keys), then the pairing (a pool with no
## sink), then the read payloads the contract declares key lists for.
static func _validate(rule: DoctrineRule, probe: Actor) -> Dictionary:
	var id := rule.system_id()
	var pools := rule.resource_ids()
	var pool_verdict := _check_pools(id, pools)
	if not bool(pool_verdict["ok"]):
		return pool_verdict
	var rows := rule.boards(probe)
	for row in rows:
		var row_verdict := _check_row(id, pools, row)
		if not bool(row_verdict["ok"]):
			return row_verdict
	var unsunk := _unsunk(pools, rows)
	if not unsunk.is_empty():
		return _refused(
			DoctrineRule.UNDECLARED_POOL,
			id,
			"declared pool(s) %s have no row that spends them" % _names(unsunk)
		)
	# The contract's declared key lists are enforced here because a registry is the only
	# place that can: an interface cannot check its own implementers, and ADR 0267 makes
	# these lists the shape rather than the documentation.
	var progress_verdict := _check_payload(
		id, "progress", rule.progress(probe), DoctrineRule.PROGRESS_KEYS
	)
	if not bool(progress_verdict["ok"]):
		return progress_verdict
	var tier_verdict := _check_payload(id, "tier_for", rule.tier_for(probe), DoctrineRule.TIER_KEYS)
	if not bool(tier_verdict["ok"]):
		return tier_verdict
	var earn_verdict := _check_payload(id, "earn", rule.earn(probe, {}), DoctrineRule.EARN_KEYS)
	if not bool(earn_verdict["ok"]):
		return earn_verdict
	return _check_price(id, rule, probe, rows)


## `price` is checked against a row that EXISTS rather than against a missing one, because
## `{}` is the correct answer for a row this System does not sell (ADR 0083's three states)
## and refusing that would refuse every System with an empty board. Reached only after
## every row has passed `_check_row`, so `rows[0]` is a dictionary here.
static func _check_price(
	id: StringName, rule: DoctrineRule, probe: Actor, rows: Array
) -> Dictionary:
	if rows.is_empty():
		return {"ok": true, "reason": "", "system_id": String(id)}
	return _check_payload(
		id, "price", rule.price(probe, StringName(rows[0]["row_id"])), DoctrineRule.PRICE_KEYS
	)


static func _check_pools(id: StringName, pools: Array[StringName]) -> Dictionary:
	var seen: Dictionary = {}
	for pool in pools:
		if pool == &"":
			return _refused(
				DoctrineRule.UNDECLARED_POOL, id, "an empty pool id, which two Systems could share"
			)
		if seen.has(String(pool)):
			return _refused(
				DoctrineRule.UNDECLARED_POOL, id, "pool '%s' is declared twice" % String(pool)
			)
		if DoctrineLedger.is_reserved(pool):
			return _refused(
				DoctrineRule.UNDECLARED_POOL,
				id,
				"pool '%s' is core's, and a capped stat is not a currency" % String(pool)
			)
		seen[String(pool)] = true
	return {"ok": true, "reason": "", "system_id": String(id)}


static func _check_row(id: StringName, pools: Array[StringName], row: Variant) -> Dictionary:
	if not row is Dictionary:
		return _refused(DoctrineRule.NOT_CLAIMED, id, "a board row is not a dictionary")
	var entry := row as Dictionary
	var row_id := StringName(entry.get("row_id", ""))
	if row_id == &"":
		return _refused(DoctrineRule.NOT_CLAIMED, id, "a board row has no row_id")
	var missing := DoctrineRule.missing_keys(entry, DoctrineRule.ROW_KEYS)
	if not missing.is_empty():
		return _refused(
			DoctrineRule.NOT_CLAIMED, id, "row '%s' is missing %s" % [String(row_id), missing]
		)
	if not DoctrineRule.is_primitive_payload(entry):
		return _refused(
			DoctrineRule.NOT_CLAIMED,
			id,
			"row '%s' carries a value the contract will not vouch for" % String(row_id)
		)
	var pool := StringName(entry.get("pool", ""))
	var amount := float(entry.get("amount", 0.0))
	if amount < 0.0:
		return _refused(
			DoctrineRule.NOT_CLAIMED, id, "row '%s' costs a negative amount" % String(row_id)
		)
	if pool == &"" and amount > 0.0:
		return _refused(
			DoctrineRule.NOT_CLAIMED,
			id,
			"row '%s' costs %.2f and names no pool to cost it from" % [String(row_id), amount]
		)
	if pool != &"" and not DoctrineLedger.declares(pools, pool):
		return _refused(
			DoctrineRule.UNDECLARED_POOL,
			id,
			(
				"row '%s' spends pool '%s', which this System never declared"
				% [String(row_id), String(pool)]
			)
		)
	if int(entry.get("tier_min", 0)) < 0:
		return _refused(
			DoctrineRule.TIER_LOCKED,
			id,
			"row '%s' is gated at a negative tier, so no tier ever locks it" % String(row_id)
		)
	if not bool(entry.get("repeatable", false)) and int(entry.get("max_count", 0)) <= 0:
		return _refused(
			DoctrineRule.ALREADY_MAXED,
			id,
			(
				"row '%s' is not repeatable and has no max_count, so no actor can ever buy it"
				% String(row_id)
			)
		)
	return {"ok": true, "reason": "", "system_id": String(id)}


static func _check_payload(
	id: StringName, label: String, payload: Variant, required: Array[StringName]
) -> Dictionary:
	if not payload is Dictionary:
		return _refused(DoctrineRule.NOT_CLAIMED, id, "%s answered a non-dictionary" % label)
	var answer := payload as Dictionary
	var missing := DoctrineRule.missing_keys(answer, required)
	if not missing.is_empty():
		return _refused(DoctrineRule.NOT_CLAIMED, id, "%s is missing %s" % [label, missing])
	if not DoctrineRule.is_primitive_payload(answer):
		return _refused(DoctrineRule.NOT_CLAIMED, id, "%s carries a non-primitive" % label)
	return {"ok": true, "reason": "", "system_id": String(id)}


## Pools `pools` declares that no row on `boards` spends. Both walks are over the rule's
## own returned collections and neither appends to what it is walking.
static func _unsunk(pools: Array[StringName], rows: Array) -> Array[StringName]:
	var sunk: Dictionary = {}
	for row in rows:
		if not row is Dictionary:
			continue
		var pool := StringName((row as Dictionary).get("pool", ""))
		if pool != &"":
			sunk[String(pool)] = true
	var out: Array[StringName] = []
	for pool in pools:
		if not sunk.has(String(pool)):
			out.append(pool)
	return out


static func _refused(reason: String, id: StringName, detail: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"system_id": String(id),
		"data_key": "",
		"detail": detail,
	}


static func _names(pools: Array[StringName]) -> String:
	var parts: Array[String] = []
	for pool in pools:
		parts.append("'%s'" % String(pool))
	return ", ".join(parts)
