class_name QuestGrants
extends RefCounted

## Pays one quest's authored rewards, exactly once, through the facade of the
## module that owns each reward.
##
## ## Why fate is earned from here and nowhere else
##
## DEF-0107 is the whole reason this file exists: "the quest module owns this,
## when it is built. It should call `DestinyApi.earn_fate(actor, fate_id,
## "quest:<quest_id>")` from the one place a quest is marked complete, and read
## gates through `DestinyApi.gate(actor, requirement)`. Fate keeps its own
## fate/destiny catalog; **never author a fate id as `quest:*`.**"
##
## So the source string is built here, in exactly that shape, and a grant whose
## id arrives already namespaced is REFUSED rather than paid — it would create a
## fate nothing in fate's catalog can ever resolve, which is the ADR 0065 failure
## ("read as a working reference and silently grant nothing").
##
## ## Why `item` pays nothing
##
## An item grant is an **id for a future inventory delivery**. `ItemsApi` is not
## a quest dependency and this module does not declare one, so calling it would
## be an undeclared edge. The grant is therefore recorded as unspent: the
## completion returns what is owed, and whoever later owns inventory delivery
## reads it. Silently dropping it would be worse than recording it; calling across
## a module we do not depend on would be worse than both.

## Fate is earned, never removed (ADR 0065) and never chosen, so `earn_fate` is
## itself exactly-once. This module's own once-guard is in front of it anyway —
## belt and braces, because a double-paid fate is permanent and unrecoverable.
const FATE_SOURCE_PREFIX := "quest:"
## The namespaces a grant id may NOT carry. ADR 0065 on fate, ADR 0113 on facts.
const RESERVED_PREFIXES: Array[String] = ["quest:", "fact:", "beat:"]


## Pay every grant `def` declares for `quest_id`.
##
## Returns `{paid: Array[Dictionary], unspent: Array[Dictionary]}`. Both lists are
## `{kind, id, amount}` primitives, so a caller reports them without reaching
## into a Resource.
static func pay(actor: Actor, def: QuestDef, quest_id: StringName) -> Dictionary:
	var paid: Array[Dictionary] = []
	var unspent: Array[Dictionary] = []
	if actor == null or def == null:
		return {"paid": paid, "unspent": unspent}
	for grant in def.grants:
		var entry := _normalize(grant)
		if entry.is_empty():
			continue
		var kind := StringName(entry["kind"])
		# An unknown kind is refused and reported, never guessed at: silently
		# treating an unreadable grant as `nothing` would lose content silently.
		if not QuestDef.GRANT_KINDS.has(kind):
			unspent.append(_with_reason(entry, "unknown_grant_kind"))
			continue
		if _namespaced(String(entry["id"])):
			unspent.append(_with_reason(entry, "reserved_namespace"))
			continue
		match kind:
			QuestDef.GRANT_FATE:
				DestinyApi.earn_fate(
					actor, StringName(entry["id"]), FATE_SOURCE_PREFIX + String(quest_id)
				)
				paid.append(entry)
			QuestDef.GRANT_DESTINY:
				DestinyApi.earn_destiny(
					actor, StringName(entry["id"]), FATE_SOURCE_PREFIX + String(quest_id)
				)
				paid.append(entry)
			QuestDef.GRANT_ITEM:
				# Recorded, not delivered. See the class note.
				unspent.append(_with_reason(entry, "no_inventory_dependency"))
	return {"paid": paid, "unspent": unspent}


## Every grant `def` declares, normalized, whether or not it can be paid. What a
## completion OWES, so a panel can show a reward before it is granted.
##
## No actor: this is a read of the authored def, not of anyone's ledger.
static func owed(def: QuestDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	for grant in def.grants:
		var entry := _normalize(grant)
		if not entry.is_empty():
			out.append(entry)
	return out


# --- Internals -------------------------------------------------------------


## One grant as `{kind: StringName, id: StringName, amount: int}`. A grant whose
## `amount` is below 1 is normalized to 1: a reward of zero is a typo, and paying
## nothing for a completed quest loses content without saying so.
static func _normalize(grant: Dictionary) -> Dictionary:
	var kind := StringName(grant.get("kind", ""))
	var id := StringName(grant.get("id", ""))
	if kind == &"" or id == &"":
		return {}
	return {"kind": kind, "id": id, "amount": maxi(1, int(grant.get("amount", 1)))}


static func _namespaced(id: String) -> bool:
	for prefix in RESERVED_PREFIXES:
		if id.begins_with(prefix):
			return true
	return false


static func _with_reason(entry: Dictionary, reason: String) -> Dictionary:
	var out := entry.duplicate()
	out["reason"] = reason
	return out
