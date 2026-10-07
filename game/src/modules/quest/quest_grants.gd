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
## ## Why an item grant is DELIVERED
##
## This used to record an `item` grant as unspent on the grounds that `items` was
## not a declared dependency. It is now declared (`tools/arch/registry.json`), and
## an id a quest owes that only gets written down is the ADR 0065 lie: it reads as
## a working reference and hands the player nothing. So `QuestGrants.pay` resolves
## the id and calls `ItemsApi.generate`, which realizes the def from a seeded roll
## and acquires it. `paid` means "in the bag"; `unspent` means "named, with the
## reason it could not be".
##
## **Resolution names `Crafting.resolve`, and that is the one deliberate reach past
## the facade.** `ItemsApi` is at its twelve-method cap, so no thirteenth verb was
## added to it, and `Inventory.definition_of` cannot stand in: it answers only for
## defs already IN the bag, so on the actor a quest first pays it answers nothing at
## all. `Crafting.resolve` is the game's stable content resolver
## (`modules/socket/socket_content.gd`), and `economy`, `loot`, `market`, `soul` and
## `set_bonus` each name it from a module that declares `items`. `tools arch` does
## not see the difference: `BARE_REF_UNITS` excludes `modules/*`, so this edge is
## enforced by review, exactly like `nation` → `sect`.

## Fate is earned, never removed (ADR 0065) and never chosen, so `earn_fate` is
## itself exactly-once. This module's own once-guard is in front of it anyway —
## belt and braces, because a double-paid fate is permanent and unrecoverable.
const FATE_SOURCE_PREFIX := "quest:"
## The namespaces a grant id may NOT carry. ADR 0065 on fate, ADR 0113 on facts.
const RESERVED_PREFIXES: Array[String] = ["quest:", "fact:", "beat:"]

# --- Item delivery refusals ---------------------------------------------------
# Owned here so a panel can switch on them and so the completion report names the
# cause rather than reporting a generic "not paid".

## The granted id names no authored `ItemDef`. A stale or invented id is a content
## bug, so it is reported rather than skipped: the quest completed and owed
## something that does not exist.
const ITEM_UNKNOWN := "unknown_item"
## The actor has no `items` module attached, so there is no bag to put anything in.
## Distinct from a full bag — an actor with no inventory cannot have one that is
## full. `ItemsApi.generate` answers null for both, and conflating them would tell a
## player their bag is full when they have no bag.
const ITEM_NO_INVENTORY := "no_inventory"
## There is a bag and it has no room. `ItemsApi.generate` spends one slot per call
## and returns null rather than overflow, so nothing is half-delivered.
const ITEM_INVENTORY_FULL := "inventory_full"
## The grant asks for more than one unit. `ItemsApi.generate` realizes exactly ONE
## unit, and the only defs it can be handed are authored `.tres` files, every one of
## which is `stackable = false` — so a second unit has no delivery at all. Refused by
## name rather than looped over a request that cannot be honoured (a loop is only
## bounded by the item count, which is content, not code).
const ITEM_AMOUNT_UNSUPPORTED := "amount_unsupported"


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
				# ADR 0134 §1a: earn, then VERIFY. `earn_fate` answers the ledger, never
				# a verdict — a null actor, an id the catalog does not ship, and an
				# already-held id are byte-identical returns — so appending to `paid`
				# unconditionally claimed a grant this quest never made. An author who
				# typed `oath_breakr` would have completed the quest, seen the reward
				# listed, and received nothing. The item branch below already had this
				# shape; these two did not, which is why an item typo was visible and a
				# fate typo was not.
				var fate_id := StringName(entry["id"])
				DestinyApi.earn_fate(actor, fate_id, FATE_SOURCE_PREFIX + String(quest_id))
				if DestinyApi.has_fate(actor, fate_id):
					paid.append(entry)
				else:
					unspent.append(_with_reason(entry, "fate_not_granted"))
			QuestDef.GRANT_DESTINY:
				var destiny_id := StringName(entry["id"])
				DestinyApi.earn_destiny(actor, destiny_id, FATE_SOURCE_PREFIX + String(quest_id))
				# A destiny can be refused by a gate, a prerequisite or a closed group, so
				# the same verification applies — and here it matters more, because a
				# refused destiny is the one case where a player would otherwise be told
				# a quest paid out and be owed nothing for it.
				if DestinyApi.has_destiny(actor, destiny_id):
					paid.append(entry)
				else:
					unspent.append(_with_reason(entry, "destiny_not_granted"))
			QuestDef.GRANT_ITEM:
				var delivered := _deliver(actor, entry, quest_id)
				if bool(delivered["ok"]):
					paid.append(entry)
				else:
					unspent.append(_with_reason(entry, String(delivered["reason"])))
			QuestDef.GRANT_CHEST:
				var opened := _open_chest(actor, entry, quest_id)
				if bool(opened["ok"]):
					paid.append(entry)
				else:
					unspent.append(_with_reason(entry, String(opened["reason"])))
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


## Put one authored `item` grant into `actor`'s bag, or name why it could not go.
##
## Returns `{ok: true}` on delivery and `{ok: false, reason: R}` otherwise. The
## caller owns `paid`/`unspent`, so this answers one question and adds nothing to a
## list — and the entry itself is left untouched, because what the quest OWED is
## `{kind, id, amount}` whether or not it landed.
##
## **Every refusal is inert.** Each one returns before `ItemsApi.generate` is
## called, and `generate` is the only verb that acquires anything, so a refused
## grant cannot half-deliver: there is no path from a refusal to a real item.
static func _deliver(actor: Actor, entry: Dictionary, quest_id: StringName) -> Dictionary:
	var def_id := StringName(entry["id"])
	if int(entry["amount"]) > 1:
		return {"ok": false, "reason": ITEM_AMOUNT_UNSUPPORTED}
	# An id naming nothing is a refusal, not a silent skip: the quest completed and
	# owed an item the content tree does not have, and saying so is the whole point.
	var def := Crafting.resolve(def_id)
	if def == null:
		return {"ok": false, "reason": ITEM_UNKNOWN}
	if ItemsApi.inventory(actor) == null:
		return {"ok": false, "reason": ITEM_NO_INVENTORY}
	# `generate` returns null on a full bag, having rolled nothing away. The seed is
	# derived from the quest and the item, so one quest always pays the same
	# realization — the same determinism `ShopDef.stock_seed` gives a shop's shelf,
	# and the same reason no delivery path in the game reads an unseeded RNG.
	if ItemsApi.generate(actor, def, _seed(quest_id, def_id)) == null:
		return {"ok": false, "reason": ITEM_INVENTORY_FULL}
	return {"ok": true, "reason": ""}


## The realization seed for one `quest_id`/`def_id` pair. Deterministic in both ids,
## so a repeated completion of the same quest yields the same item rather than a
## reroll.
static func _seed(quest_id: StringName, def_id: StringName) -> int:
	return hash("%s%s:%s" % [FATE_SOURCE_PREFIX, String(quest_id), String(def_id)])


## Open one authored `chest` grant into `actor`'s bag, or name why it could not open.
##
## Same determinism rule as [method _deliver]: the seed is derived from the quest and the
## chest id, so one quest always pays the same bundle rather than a reroll. Returns
## `{ok, reason}`; the caller owns `paid`/`unspent`, and the entry is left untouched
## because what the quest OWED is `{kind, id, amount}` whether or not it opened.
##
## The bundle itself is the `items` module's to draw — this verb asks the facade and reads
## its answer, so a second bundle shape (a loot table, a mod's own chest) needs no change
## here.
static func _open_chest(actor: Actor, entry: Dictionary, quest_id: StringName) -> Dictionary:
	if int(entry["amount"]) > 1:
		# `open_chest` opens one bundle; a grant asking for two is a shape this path does
		# not have, refused by name rather than looped over a request it cannot honour.
		return {"ok": false, "reason": ITEM_AMOUNT_UNSUPPORTED}
	var chest_id := StringName(entry["id"])
	var opened := ItemsApi.open_chest(actor, chest_id, _seed(quest_id, chest_id))
	if not bool(opened.get("ok", false)):
		return {"ok": false, "reason": String(opened.get("reason", ItemsApi.CHEST_UNKNOWN))}
	# A refused ROW (an unknown item id, a full bag) means the chest did not deliver
	# everything it promised, so the grant is unspent and carries the first row's reason
	# rather than reporting a clean payout.
	var refused := opened.get("refused", []) as Array
	if not refused.is_empty():
		return {"ok": false, "reason": String((refused[0] as Dictionary).get("reason", ""))}
	return {"ok": true, "reason": ""}


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
