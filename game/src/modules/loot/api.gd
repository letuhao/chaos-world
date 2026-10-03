class_name LootApi
extends RefCounted

## Public facade for the `loot` module (BL-0083). Owns the loot tables, the boss
## and domain reward lifecycle, and the bounded `loot_bonus` consumer.
##
## Design notes a caller needs:
##
##  - The items facade is frozen at its 12 methods, so every action here returns a
##    plain result dictionary (`ok`, `status`, `reason`) instead of a typed
##    object, and the loot state lives in `actor.module_data["loot_state"]`
##    (ADR 0027). Core never names a loot type.
##  - Exactly one reward payload exists per encounter. Its id is deterministic, so
##    a repeated defeat, a re-entry and a save/load all resolve the same claim.
##  - A pickup is all-or-nothing per drop. A full inventory overflows to a bounded
##    world drop container and never spends the claim; when that container is full
##    the pickup is refused and the drop stays retrievable in the reward.
##  - Boss difficulty and drop context are authored data
##    ([LootTier]), never derived from the player's gear.


## Attach the loot state to an actor: restores and normalizes what a prior
## `to_dict()` carried, and stamps the schema version. Idempotent.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(
		LootState.MODULE_KEY, LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	)


## Every authored domain encounter as primitives: its domain, its entry gate and
## its authored tiers. The reader picks a domain and a tier from this list.
static func domains() -> Array:
	var content := LootContent.instance()
	var out: Array = []
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		(
			out
			. append(
				{
					"encounter_id": String(encounter.id),
					"domain_id": String(encounter.domain_id),
					"display_name": encounter.display_name,
					"key_reach": encounter.key_reach,
					"tier_count": encounter.tier_count(),
					"tiers": encounter.tier_views(),
				}
			)
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["domain_id"]) < String(b["domain_id"])
	)
	return out


## Rule E2/E4: enter `domain_id` at `tier_index`, granting or resuming a run. The
## entry gate is a key item's `key_reach` property (ADR 0033); a domain that
## declares no gate is open.
static func enter_domain(
	actor: Actor, domain_id: StringName, tier_index: int = 0, seed_value: int = 0
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var encounter := LootContent.instance().encounter_for_domain(domain_id)
	if encounter == null:
		return {"ok": false, "reason": LootState.ERR_UNKNOWN_DOMAIN, "domain_id": String(domain_id)}
	if encounter.key_reach > 0:
		var reach := _key_reach(actor)
		if reach < float(encounter.key_reach):
			return {
				"ok": false,
				"reason": LootState.ERR_KEY_REACH,
				"domain_id": String(domain_id),
				"required": encounter.key_reach,
				"reach": reach,
			}
	var state := _state(actor)
	var result := LootState.enter(state, encounter, tier_index, seed_value)
	_save(actor, state)
	return result


## Spend `damage` on the active boss and defeat it when its authored vitality is spent.
## A boss that is already dead resolves its existing payload instead of minting a second
## one.
##
## This is the primitive, and it stays one: it takes an amount because an amount is what a
## pool is spent with. It is **not** where the game's damage comes from —
## `CombatExchange.exchange` is what a player presses, because a blow is a resolution
## against the actor's own combat numbers rather than a caller's constant (ADR 0076). The
## composition root points the loot bridge's `strike` at the exchange, not here.
static func strike(actor: Actor, damage: float, seed_value: int = 0) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var state := _state(actor)
	var result := LootState.strike(state, actor, damage, seed_value)
	_save(actor, state)
	return result


## Leave the domain. The in-progress boss is discarded; every unclaimed reward is
## kept and stays retrievable.
static func abandon(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var state := _state(actor)
	var result := LootState.abandon(state)
	_save(actor, state)
	return result


## The reward payload for `encounter_id` as primitives. An encounter with nothing
## left reports `claim_already_spent`, and a decided no-drop reports `no_drop`, so
## a reader can tell "nothing fell" from "you already took it".
static func reward(actor: Actor, encounter_id: String) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var state := _state(actor)
	if LootState.is_spent(state, encounter_id):
		var spent: Dictionary = state["claimed"][encounter_id]
		var spent_reason := String(spent.get("reason", LootState.ERR_CLAIM_SPENT))
		return {
			"ok": false,
			"encounter_id": encounter_id,
			"reason":
			(
				LootState.OK_NO_DROP
				if spent_reason == LootState.OK_NO_DROP
				else LootState.ERR_CLAIM_SPENT
			),
			"drop_count": int(spent.get("drops", 0)),
			"reward": {},
		}
	var rewards: Dictionary = state["rewards"]
	if not rewards.has(encounter_id):
		return {
			"ok": false,
			"encounter_id": encounter_id,
			"reason": LootState.ERR_UNKNOWN_REWARD,
			"reward": {}
		}
	return {
		"ok": true,
		"encounter_id": encounter_id,
		"reason": "",
		"reward": LootRewards.view(rewards[encounter_id])
	}


## Pick up one drop. `status` is `claimed`, `overflow` or `refused`.
static func pickup(actor: Actor, encounter_id: String, drop_id: String) -> Dictionary:
	if actor == null:
		return {"ok": false, "status": "refused", "reason": "no_actor"}
	var state := _state(actor)
	var result := LootState.pickup(state, encounter_id, drop_id, ItemsApi.inventory(actor))
	_save(actor, state)
	return result


## Pick up every claimable drop of one encounter. Each drop keeps its own outcome,
## so one full-inventory drop cannot hold back the rest.
static func pickup_all(actor: Actor, encounter_id: String) -> Dictionary:
	if actor == null:
		return {"ok": false, "status": "refused", "reason": "no_actor"}
	var state := _state(actor)
	var result := LootState.pickup_all(state, encounter_id, ItemsApi.inventory(actor))
	_save(actor, state)
	return result


## Take one drop back out of the bounded world drop container into the inventory.
static func reclaim(actor: Actor, stash_id: String) -> Dictionary:
	if actor == null:
		return {"ok": false, "status": "refused", "reason": "no_actor"}
	var state := _state(actor)
	var result := LootState.reclaim(state, stash_id, ItemsApi.inventory(actor))
	_save(actor, state)
	return result


## Everything a reader needs in one primitive-only dictionary: the in-progress
## encounter, every unclaimed reward, the world drop container, the player's key
## reach and their bounded `loot_bonus` axes.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := _state(actor)
	var rewards: Array = []
	var pending := 0
	for encounter_id in (state["rewards"] as Dictionary).keys():
		var view := LootRewards.view(state["rewards"][encounter_id])
		rewards.append(view)
		pending += int(view["pending_count"])
	rewards.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["encounter_id"]) < String(b["encounter_id"])
	)
	var stashes: Array = []
	for stash in state["world_drops"]:
		stashes.append(_stash_view(state, stash as Dictionary))
	var active := LootRewards.active_view(state["active"])
	var rate := LootBonus.rate_for(actor)
	return {
		"actor_id": String(actor.id),
		"in_domain": bool(active.get("in_domain", false)),
		"active": active,
		"rewards": rewards,
		"reward_count": rewards.size(),
		"pending_drops": pending,
		"claimed_encounters": (state["claimed"] as Dictionary).size(),
		"world_drops": stashes,
		"world_drop_count": stashes.size(),
		"world_drop_capacity": LootState.WORLD_DROP_CAPACITY,
		"world_drops_full": stashes.size() >= LootState.WORLD_DROP_CAPACITY,
		"key_reach": _key_reach(actor),
		"loot_bonus": rate,
		"loot_bonus_axes": LootBonus.axes(rate),
		"loot_bonus_limits": LootBonus.limits(),
		"runs": (state["runs"] as Dictionary).duplicate(),
	}


## Validate the authored loot content. `scope` is "" (everything), "tables" or
## "encounters"; returns one message per problem, empty when clean.
static func validate(scope: String = LootValidator.SCOPE_ALL) -> Array[String]:
	return LootValidator.validate(scope)


## A table as declared, nested tables included: its ids, counts, contexts and
## entries. Used by a reader that wants to show what a boss can drop.
static func table(table_id: StringName) -> Dictionary:
	var found := LootContent.instance().table(table_id)
	if found == null:
		return {}
	var entries: Array = []
	for entry in found.entries:
		if entry == null:
			continue
		(
			entries
			. append(
				{
					"id": String(entry.id),
					"kind": String(entry.kind),
					"item_id": String(entry.item_id),
					"table_id": String(entry.table_id),
					"weight": entry.weight,
					"chance": entry.chance,
					"guaranteed": entry.guaranteed,
					"quantity": entry.quantity,
					"quantity_max": entry.quantity_max,
					"rarity_floor": String(entry.rarity_floor),
				}
			)
		)
	return {
		"id": String(found.id),
		"display_name": found.display_name,
		"realm": String(found.realm),
		"rarity": String(found.rarity),
		"rolls": found.rolls,
		"rolls_max": found.rolls_max,
		"allow_empty": found.allow_empty,
		"entries": entries,
		"item_ids": _string_ids(found.reachable_item_ids()),
	}


## A stashed drop rendered as a drop row, so the world drop container and the
## reward list show the same thing in the same shape. The stash id addresses the
## reclaim action; the drop id is the row key.
static func _stash_view(state: Dictionary, stash: Dictionary) -> Dictionary:
	var encounter := String(stash.get("encounter_id", ""))
	var payload := (state["rewards"] as Dictionary).get(encounter, {}) as Dictionary
	var drop: Dictionary = {}
	for candidate in payload.get("drops", []):
		if String((candidate as Dictionary).get("drop_id", "")) == String(stash.get("drop_id", "")):
			drop = LootRewards.drop_view(candidate as Dictionary)
			break
	var view := drop.duplicate()
	view["stash_id"] = String(stash.get("stash_id", ""))
	view["encounter_id"] = encounter
	view["stashed"] = true
	view["claimable"] = false
	return view


## The highest domain a key item the actor carries opens (ADR 0033). Read through
## the items module's own property reader, so `key_reach` has exactly one
## meaning in the game.
static func _key_reach(actor: Actor) -> float:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return 0.0
	var best := 0.0
	for batch in inventory.stacks():
		var def := batch.def_ref
		if def == null:
			continue
		best = maxf(
			best, float(def.property_total(inventory.sample(batch.def_id), OptionTarget.KEY_REACH))
		)
	for instance in inventory.instances():
		var def := instance.def_ref
		if def == null:
			continue
		best = maxf(best, float(def.property_total(instance, OptionTarget.KEY_REACH)))
	return best


static func _string_ids(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


static func _state(actor: Actor) -> Dictionary:
	return LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))


static func _save(actor: Actor, state: Dictionary) -> void:
	actor.set_module_data(LootState.MODULE_KEY, state)
