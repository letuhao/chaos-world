class_name EventPrize
extends RefCounted

## The `pay` rows of an `EventDef`, applied EXACTLY ONCE (ADR 0061).
##
## ## A prize is a LIST of destinations, never one
##
## `pay` is authored as `{kind, id, amount}` per row with `kind` one of `fate`,
## `destiny`, `nation_standing` or `nothing`. One row can never be both a fate and
## a standing delta, so a list is not a convenience — it is what keeps each grant
## attributable to its own owning module. A row naming a kind outside the closed set
## is DROPPED and reported, never guessed at: an unpayable prize nobody can read is
## the defect ADR 0084's "refuse, and name yourself" rule exists to prevent.
##
## ## The fate source string is EXACTLY `"event:" + event_id` (DEF-0108)
##
## DEF-0108 is explicit: "Call `DestinyApi.earn_fate(actor, fate_id,
## "event:<event_id>")` from the event's own resolution." The string is built by
## `EventDef.fate_source()` and passed through unchanged, so an audit can name the
## system that earned a fate by reading the ledger — and so a quest grant can never
## be mistaken for an event grant or vice versa.
##
## ## Once, and the guard lives in the LEDGER not in this file
##
## `EventState.has_paid` is the once-guard. This class never marks a row paid
## itself: the caller does, after `apply` returns, under the same write that removes
## the event from `active`. A guard kept here would be a second ledger, and a second
## ledger is what ADR 0114 calls a second notion of "already fired".

## How much one period of an open stage costs the world. Mirrors
## `WorldApi.trigger_conflict`'s `severity * 0.1` rather than a second magic
## multiplier of this module's own, and is read from the def so a rebalance is a
## `.tres` edit.
const STABILITY_COST_PER_PERIOD := 0.1


## Apply an event's prize once. Returns what was granted, what was refused and why,
## and the standing after the `nation_standing` rows were written.
static func apply(actor: Actor, def: EventDef, period: int) -> Dictionary:
	var granted: Array[Dictionary] = []
	var refused: Array[Dictionary] = []
	for row in def.pay:
		var outcome := _apply_row(actor, def, row)
		if bool(outcome.get("ok", false)):
			granted.append(outcome)
		else:
			refused.append(outcome)
	var ledger := NationApi.state(actor)
	return {
		"ok": true,
		"period": period,
		"rows": def.pay.size(),
		"granted": granted,
		"refused": refused,
		"fate_source": def.fate_source(),
		# `NationApi` clamps the written value to its own `standing_cap`, so the
		# balance AFTER the grant is what `nation` holds, not what this row asked
		# for. Reported rather than returned as "amount paid".
		"nation_standing": int(ledger.get("standing", 0)),
		"has_nation": NationState.founded(ledger),
	}


## Settle one period of an open stage against world stability, and return the
## settlement. **A read is not a write**: `WorldApi.trigger_conflict` refuses without
## a world, and that refusal is returned rather than forced through, so an event
## running on an actor that has no `actor.world` still advances.
static func settle_period(actor: Actor, def: EventDef, severity: float) -> Dictionary:
	if actor == null or def == &"":
		return {"ok": false, "reason": "no_actor"}
	return WorldApi.trigger_conflict(actor, def.id, severity)


# --- Internals -------------------------------------------------------------


static func _apply_row(actor: Actor, def: EventDef, row: Dictionary) -> Dictionary:
	var kind := StringName(row.get("kind", ""))
	var id := StringName(row.get("id", ""))
	var amount := int(row.get("amount", 1))
	if kind == EventDef.PAY_NOTHING:
		# Authored absence. Legal, and NOT the same as a missing key: an author who
		# writes `{kind: "nothing"}` has said the prize is nothing.
		return {"ok": true, "kind": String(kind), "id": "", "amount": 0}
	if kind == EventDef.PAY_FATE:
		if id == &"":
			return {"ok": false, "reason": "pay_names_no_id", "kind": String(kind)}
		# DEF-0108's exact string. `earn_fate` is exactly-once itself, so calling it
		# twice with the same id is harmless — but `EventState.paid` is what stops the
		# second CALL from happening at all.
		DestinyApi.earn_fate(actor, id, def.fate_source())
		return {"ok": true, "kind": String(kind), "id": String(id), "amount": amount}
	if kind == EventDef.PAY_DESTINY:
		if id == &"":
			return {"ok": false, "reason": "pay_names_no_id", "kind": String(kind)}
		DestinyApi.earn_destiny(actor, id, def.fate_source())
		return {"ok": true, "kind": String(kind), "id": String(id), "amount": amount}
	if kind == EventDef.PAY_NATION_STANDING:
		if id == &"":
			return {"ok": false, "reason": "pay_names_no_id", "kind": String(kind)}
		var ledger := NationApi.state(actor)
		if not NationState.founded(ledger):
			return {
				"ok": false,
				"reason": EventState.R_UNKNOWN_NATION,
				"kind": String(kind),
				"id": String(id),
			}
		# **REFUSED, with the reason, and that is the honest answer.**
		#
		# `NationApi` has no verb that writes a standing delta directly: standing
		# moves by founding a claim and by settling periods against it
		# (`accrue_territory`), never by a number this module hands it. ADR 0085
		# settles where an authored standing delta DOES belong — inside the prize
		# `declare_war` fixes up front, which `resolve_conflict` then pays verbatim.
		# So an event that wants standing must declare it in its `declare` row, and
		# this row names that instead of writing through a verb that does not exist.
		return {
			"ok": false,
			"reason": EventState.R_STANDING_IS_DECLARED,
			"kind": String(kind),
			"id": String(id),
			"declared_standing": _declared_delta(ledger, String(id)),
		}
	return {
		"ok": false,
		"reason": EventState.R_UNKNOWN_PAY_KIND,
		"kind": String(kind),
		"id": String(id),
	}


## The standing delta an open standoff over this polity already DECLARED for the
## other side, or 0 when none has. Read, never written: ADR 0085 fixes a conflict's
## prize at declaration and pays it verbatim, so an event's `nation_standing` row can
## report what is in play but must not move it.
static func _declared_delta(ledger: Dictionary, polity_id: String) -> int:
	var self_id := String(ledger.get("nation_id", ""))
	if polity_id == "" or self_id == "":
		return 0
	for standoff_id in (ledger.get("standoffs", {}) as Dictionary).keys():
		var entry = (ledger["standoffs"] as Dictionary)[standoff_id]
		if not (entry is Dictionary):
			continue
		var sides = (entry as Dictionary).get("sides", {})
		if not (sides is Dictionary) or not (sides as Dictionary).has(polity_id):
			continue
		var deltas = ((entry as Dictionary).get("prize", {}) as Dictionary).get("standing", {})
		if not (deltas is Dictionary):
			continue
		if (deltas as Dictionary).has(polity_id):
			return int((deltas as Dictionary)[polity_id])
	return 0
