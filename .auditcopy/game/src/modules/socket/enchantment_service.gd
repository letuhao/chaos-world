class_name EnchantmentService
extends RefCounted

## Applying and replacing the enchantment channel on eligible equipment and
## socket items.
##
## One replaceable channel per target: a new enchantment replaces the old one,
## it never stacks. Options this module does not author — item-authored fixed,
## rolled, and later set/unique — are locked, so a treatment can neither
## overwrite nor duplicate them.
##
## Preview and commit are separate on purpose. A preview reads the catalog's
## windows, costs and refusals and touches nothing: no unit is consumed, no state
## is written, and no roll stream is advanced. A commit validates everything
## again, spends through `Crafting`, realizes once, and records the request id so
## replaying it replays the same answer.

const ACTION_PREVIEW := &"preview_enchantment"
const ACTION_COMMIT := &"commit_enchantment"


## What a treatment of `target_id` could produce, and what would stop it. Pure
## read: no inventory unit is consumed, no state is written, and `rng` is never
## advanced.
static func preview(
	actor: Actor,
	ledger: SocketLedger,
	target_id: StringName,
	reagent: ItemDef,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	# Captured so the preview can report that it left the caller's stream alone: a
	# preview resolves windows and refusals, never a realized value.
	var stream_before := 0 if rng == null else int(rng.state)
	var owner := SocketOwnership.locate(actor, target_id)
	var target := owner.get("instance") as ItemInstance
	var out := {
		"ok": false,
		"reason": "",
		"action": String(ACTION_PREVIEW),
		"target": String(target_id),
		"cost": [],
		"permitted": [],
		"locked": [],
		"current": {},
		"generation": 0,
		"cap": 0,
		"rolled": false,
		"stream_advanced": false,
	}
	if target == null:
		out["reason"] = "unknown_target"
		return out
	var channel := ledger.channel(target_id)
	out["generation"] = int(channel.get("generation", 0))
	out["cap"] = SocketPolicy.enchant_cap(target.rarity)
	out["current"] = Dictionary(channel.get("effect", {})).duplicate(true)
	out["locked"] = _locked_ids(target)
	var refusal := _refusal(actor, owner, reagent, int(out["generation"]), int(out["cap"]))
	if not refusal.is_empty():
		out["reason"] = refusal
		out["stream_advanced"] = _advanced(rng, stream_before)
		return out
	out["ok"] = true
	out["cost"] = [reagent.id]
	out["permitted"] = SocketPools.permitted(
		SocketPools.CHANNEL_ENCHANT, _realm_id(target), _rarity_index(target), _used_ids(target)
	)
	out["stream_advanced"] = _advanced(rng, stream_before)
	return out


## Treat `target_id` with `reagent`, replacing whatever the channel carried.
## Idempotent: the same `request_id` returns the recorded result without
## consuming a second unit, in this session or after a save/load round trip.
static func commit(
	actor: Actor,
	ledger: SocketLedger,
	target_id: StringName,
	reagent: ItemDef,
	request_id: StringName,
	seed: int
) -> Dictionary:
	var replay := ledger.request(request_id)
	if not replay.is_empty():
		return replay.duplicate(true)
	var owner := SocketOwnership.locate(actor, target_id)
	var target := owner.get("instance") as ItemInstance
	if target == null:
		return SocketResult.refused(ACTION_COMMIT, target_id, "unknown_target")
	# Read-only until every check has passed: a refused treatment must leave the
	# ledger byte-identical, so the channel is only created once it is written.
	var channel := ledger.channel(target_id)
	var cap := SocketPolicy.enchant_cap(target.rarity)
	var refusal := _refusal(actor, owner, reagent, int(channel.get("generation", 0)), cap)
	if not refusal.is_empty():
		return SocketResult.refused(ACTION_COMMIT, target_id, refusal)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var effect := SocketPools.roll(
		SocketPools.CHANNEL_ENCHANT,
		_used_ids(target),
		_realm_id(target),
		_rarity_index(target),
		rng
	)
	if effect.is_empty():
		return SocketResult.refused(ACTION_COMMIT, target_id, "no_legal_option")
	# Spend only after every read-only check has passed, so a refusal is free.
	var cost := SocketCosts.spend(ItemsApi.inventory(actor), _single(reagent.id))
	if cost != OK:
		return SocketResult.refused(ACTION_COMMIT, target_id, "cost_failed")
	var replaced := Dictionary(channel.get("effect", {})).duplicate(true)
	channel = ledger.ensure_channel(target_id)
	channel["generation"] = int(channel.get("generation", 0)) + 1
	channel["effect"] = effect.duplicate(true)
	channel["reagent_id"] = String(reagent.id)
	var result := (
		SocketResult
		. committed(
			ACTION_COMMIT,
			target_id,
			[reagent.id],
			{
				"effect": effect,
				"generation": int(channel["generation"]),
				"cap": cap,
				"replaced": replaced,
			}
		)
	)
	ledger.record_request(request_id, result)
	ledger.commit(actor)
	_rebind(target)
	SocketEffects.sync(actor, ledger)
	return result


## Every reason a treatment would refuse right now. Empty means it would commit.
static func refusal(
	actor: Actor, ledger: SocketLedger, target_id: StringName, reagent: ItemDef
) -> String:
	var owner := SocketOwnership.locate(actor, target_id)
	var target := owner.get("instance") as ItemInstance
	if target == null:
		return "unknown_target"
	var channel := ledger.channel(target_id)
	return _refusal(
		actor,
		owner,
		reagent,
		int(channel.get("generation", 0)),
		SocketPolicy.enchant_cap(target.rarity)
	)


## Whether a caller's roll stream moved during a preview. It never should: a
## preview resolves the catalog's windows and the transaction's refusals, and
## nothing else.
static func _advanced(rng: RandomNumberGenerator, stream_before: int) -> bool:
	return rng != null and int(rng.state) != stream_before


static func _refusal(
	actor: Actor, owner: Dictionary, reagent: ItemDef, generation: int, cap: int
) -> String:
	if reagent == null:
		return "unknown_reagent"
	var target := owner.get("instance") as ItemInstance
	if target == null:
		return "unknown_target"
	if target.bound_to != &"" and target.bound_to != actor.id:
		return "bound_to_other"
	if not SocketPolicy.meets_tier(
		SocketPolicy.tier_of(actor.realm()), SocketPolicy.tier_of(reagent.realm)
	):
		return "realm_tier_too_low"
	if generation >= cap:
		return "cap_exhausted"
	if not ItemsApi.inventory(actor).has(reagent.id):
		return "missing_cost"
	if (
		SocketPools
		. permitted(
			SocketPools.CHANNEL_ENCHANT, _realm_id(target), _rarity_index(target), _used_ids(target)
		)
		. is_empty()
	):
		return "no_legal_option"
	return ""


## Options the target already carries that a treatment must leave alone.
static func _locked_ids(target: ItemInstance) -> Array:
	var out: Array = []
	for option_id in SocketPolicy.foreign_option_ids(target):
		out.append(String(option_id))
	return out


## Every option id a treatment may not use: the options the target carries
## through a foreign channel. A replacement is therefore never a duplicate of
## what the target already has.
static func _used_ids(target: ItemInstance) -> Array[StringName]:
	return SocketPolicy.foreign_option_ids(target)


## The realm the roll is scaled for, as an ID and never as a ladder position:
## `OptionCatalog._realm_factor` keys a MAGNITUDE by realm id (ADR 0050) and reads
## a RATE as `realm_ordinal`, which clamps an unknown id to 0 itself. Threading an
## index through instead made every magnitude lookup miss.
static func _realm_id(target: ItemInstance) -> StringName:
	if target == null:
		return &""
	if target.realm != &"":
		return target.realm
	if target.def_ref != null:
		return target.def_ref.realm
	return &""


static func _rarity_index(target: ItemInstance) -> int:
	var rarity := target.rarity if target != null else &"common"
	return OptionCatalog.rarity_tier(rarity)


## Re-point a treated instance's definition reference so a later read resolves
## the same definition the treatment validated against.
static func _rebind(target: ItemInstance) -> void:
	if target == null or target.def_ref != null:
		return
	target.def_ref = SocketContent.resolve(target.def_id)


static func _single(reagent_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.append(reagent_id)
	return out
