class_name SetBonusApi
extends RefCounted

## Public facade for the `set_bonus` module. Other modules may reference ONLY
## this file (`api.gd`).
##
## Concrete implementations live beside this file and are wired in `app/`.
##
## The module owns two things and nothing else:
##
##   - **Sets.** A threshold bonus is keyed by the set's own source id, never by
##     a member's instance id, and every change re-derives the whole contribution
##     from the equipment that is actually worn. Equip, unequip and rebuild
##     therefore cannot drift, double, or delete each other (ADR 0026).
##   - **Uniques.** A stable authored identity with a locked fixed signature, a
##     bounded rolled channel that may only add to that signature, and a declared
##     boss drop route a loot runtime can consume (ADR 0025/0033).
##
## The items module's facade is frozen, so anything the game needs beyond it
## lives here. Attach order matters: `ItemsApi.attach(actor)` first, then this.

## The actor component holding the live set state.
const STATE_COMPONENT := &"set_bonus_state"
## `actor.module_data` key the versioned snapshot is persisted under (ADR 0027).
const MODULE_KEY := &"set_state"
## Route index the loot runtime reads. One JSON object per line.
const ROUTES_PATH := SetCatalog.ROUTES_PATH


## Attach the module to `actor`. Call after `ItemsApi.attach(actor)`: the state
## is derived from equipment, so it must exist first. Binds to the equipment
## `changed` signal, restores any snapshot a prior `Actor.from_dict` carried, and
## re-derives the live state from what is worn. Idempotent.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var state := actor.component(STATE_COMPONENT) as SetBonusState
	if state == null:
		state = SetBonusState.new(actor)
		actor.set_component(STATE_COMPONENT, state)
	# A restored snapshot is normalized, then immediately re-derived: equipment
	# is the single source of truth, so a stale snapshot is diagnosed by
	# comparison rather than trusted.
	var pending: Dictionary = actor.get_module_data(MODULE_KEY)
	actor.set_module_data(MODULE_KEY, SetBonusState.normalize(pending))
	state.recompute(actor)


## Re-derive every set from the actor's equipment right now and apply the result.
## Each call fully replaces the previous contribution, so repeated calls are
## idempotent. Normally unnecessary — the module reacts to equipment changes —
## but a caller that mutated stats outside the items layer can force a pass.
static func refresh(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := actor.component(STATE_COMPONENT) as SetBonusState
	if state == null:
		attach(actor)
		state = actor.component(STATE_COMPONENT) as SetBonusState
	if state == null:
		return {}
	return state.recompute(actor)


## The actor's versioned set snapshot as core persists it. This is the payload a
## save carries, so a caller never has to reach for the actor's module data.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return SetBonusState.normalize({})
	return SetBonusState.normalize(actor.get_module_data(MODULE_KEY))


## A read-only, primitive-only snapshot of every authored set and unique, built
## for an inspection UI: identity, membership, per-member fixed options and
## locked signature, and every threshold marked active or inactive.
static func inspect(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var catalog := SetCatalog.instance()
	var live := _live_sets(actor)
	var out := {
		"actor_id": "" if actor == null else String(actor.id),
		"has_actor": actor != null,
		"set_count": catalog.set_ids().size(),
		"unique_count": catalog.unique_ids().size(),
		"sets": {},
		"active_set_ids": [],
	}
	for set_id in catalog.set_ids():
		var set_def := catalog.set_definition(set_id)
		if set_def == null:
			continue
		var entry: Dictionary = live.get(String(set_id), {})
		out["sets"][String(set_id)] = _set_view(set_def, entry)
		if (entry.get("active_tiers", []) as Array).size() > 0:
			out["active_set_ids"].append(String(set_id))
	out["unique_total"] = catalog.unique_ids().size()
	return out


## Every authored set id, canonically ordered.
static func sets() -> Array[StringName]:
	return SetCatalog.instance().set_ids()


## One set definition, or null when the id is unknown.
static func set_definition(set_id: StringName) -> SetDef:
	return SetCatalog.instance().set_definition(set_id)


## The definition behind a set member, a unique, or any other item id. One
## lookup: this module's own content tree first, then the items module's
## game-wide resolver. Null rather than a guess.
static func definition(item_id: StringName) -> ItemDef:
	return SetCatalog.instance().definition(item_id)


## Where an item stands in the set/unique world:
## `{set_id, kind, is_piece, is_unique}`. `set_id` is `""` for an item that
## belongs to no authored set.
static func membership(item_id: StringName) -> Dictionary:
	var catalog := SetCatalog.instance()
	var def := catalog.definition(item_id)
	var unique := UniqueItem.is_unique(def)
	for set_id in catalog.set_ids():
		var set_def := catalog.set_definition(set_id)
		if set_def == null or not set_def.is_member(item_id):
			continue
		return {
			"set_id": String(set_id),
			"kind": String(set_def.member_kind(item_id)),
			"is_piece": set_def.pieces.has(item_id),
			"is_unique": unique,
		}
	return {"set_id": "", "kind": "", "is_piece": false, "is_unique": unique}


## Whether an item definition is an authored unique. Accepts an id or the
## definition itself, so a caller holding either can ask.
static func is_unique(def_or_id) -> bool:
	return UniqueItem.is_unique(_as_def(def_or_id))


## Whether `option_id` is part of a unique's locked fixed signature. A treatment
## that would resolve this to true must refuse to alter the option: rolling and
## refining may only add to the signature, never rewrite it.
static func is_locked(def_or_id, option_id: StringName) -> bool:
	return UniqueItem.is_locked(_as_def(def_or_id), option_id)


## The declared drop route for a unique: `{unique_id, set_id, boss_id,
## domain_id, route_realm, min_rarity, drop_weight, item_subtype, declared}`.
##
## Three of those facts are owned by the item definition and are read from it, not
## from the route index: `boss_id` comes from the `unique_route:<boss>` tag,
## because that tag is what the loot runtime enforces and is therefore the one
## declaration that cannot drift from behaviour; `item_subtype` is the
## definition's own `subcategory`; and `set_id` is derived from which set
## actually lists this unique, so membership can never be contradicted by a column.
## The index carries only the drop tuning a designer knows: `domain_id`,
## `route_realm`, `min_rarity` and `drop_weight`.
##
## `declared` is true only when the tag names a boss *and* a tuning row exists, so
## a caller can never mistake a half-declared route for a resolved one.
static func drop_route(item_id: StringName) -> Dictionary:
	var catalog := SetCatalog.instance()
	var def := catalog.definition(item_id)
	var boss_id := UniqueItem.route_boss_id(def)
	var subtype := "" if def == null else String(def.subcategory)
	var row := catalog.route(item_id)
	if row.is_empty() or boss_id == &"":
		return {
			"unique_id": String(item_id),
			"set_id": "",
			"boss_id": "",
			"domain_id": "",
			"route_realm": "",
			"min_rarity": "",
			"drop_weight": 0.0,
			"item_subtype": subtype,
			"declared": false,
		}
	return {
		"unique_id": String(item_id),
		"set_id": _set_listing(item_id),
		"boss_id": String(boss_id),
		"domain_id": OptionCatalog.text_field(row, "domain_id"),
		"route_realm": OptionCatalog.text_field(row, "route_realm"),
		"min_rarity": OptionCatalog.text_field(row, "min_rarity"),
		"drop_weight": float(row.get("drop_weight", 1.0)),
		"item_subtype": subtype,
		"declared": true,
	}


## The set that lists `item_id`, or `""` when it belongs to none. Derived from the
## set definitions rather than read from the route index, so the two cannot
## disagree — the index used to carry a `set_id` column that was a second
## declaration of the very fact this answers.
static func _set_listing(item_id: StringName) -> String:
	var catalog := SetCatalog.instance()
	for set_id in catalog.set_ids():
		var set_def := catalog.set_definition(set_id)
		if set_def != null and set_def.is_member(item_id):
			return String(set_id)
	return ""


## Realize a unique from a seed. The locked fixed signature is preserved and the
## rolled channel is topped up to the item's roll count with options that are
## neither locked nor already rolled, so a unique always carries both channels
## and never a doubled one. Deterministic: the same seed gives the same roll.
## Returns null for an unknown id, so a bad loot entry consumes nothing.
static func forge_unique(item_id: StringName, seed_value: int) -> ItemInstance:
	var def := SetCatalog.instance().definition(item_id)
	if def == null or not UniqueItem.is_unique(def):
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return UniqueItem.forge(def, StringName("%s_unique" % item_id), rng)


# --- Internals -------------------------------------------------------------


static func _as_def(def_or_id):
	if def_or_id is ItemDef:
		return def_or_id
	return SetCatalog.instance().definition(StringName(def_or_id))


static func _live_sets(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := actor.component(STATE_COMPONENT) as SetBonusState
	if state == null:
		return SetBonusState.normalize({}).get("sets", {})
	return state.to_dict().get("sets", {})


static func _set_view(set_def: SetDef, entry: Dictionary) -> Dictionary:
	var members: Array = entry.get("members", [])
	var slots: Dictionary = entry.get("slots", {})
	var active: Array = entry.get("active_tiers", [])
	# A set may be authored wider than a body (the void coil has six members and
	# five slots), so "complete" means every member a body could actually wear, not
	# every member the set names — otherwise a full set reads as permanently
	# incomplete. `equippable_count` is that placement ceiling; `member_count`
	# stays the authored total.
	var equippable := SetCatalog.instance().max_wearable(set_def.id)
	var out := {
		"set_id": String(set_def.id),
		"display_name": set_def.display_name,
		"description": set_def.description,
		"realm": String(set_def.realm),
		"rarity": ItemRarity.display_name(set_def.rarity),
		"counting": String(set_def.counting),
		"member_count": set_def.member_count(),
		"equippable_count": equippable,
		"equipped_count": members.size(),
		"complete": members.size() >= equippable,
		"members": [],
		"thresholds": [],
		"active_threshold_count": active.size(),
		"active_option_count": _active_option_count(set_def, active),
	}
	for member_id in set_def.member_ids():
		out["members"].append(_member_view(set_def, member_id, slots))
	for index in set_def.tiers.size():
		out["thresholds"].append(_threshold_view(set_def, index, active.has(index)))
	return out


static func _member_view(set_def: SetDef, member_id: StringName, slots: Dictionary) -> Dictionary:
	var def := SetCatalog.instance().definition(member_id)
	var id := String(member_id)
	var view := {
		"def_id": id,
		"display_name": "" if def == null else def.display_name,
		"kind": String(set_def.member_kind(member_id)),
		"is_unique": UniqueItem.is_unique(def),
		"rarity": "" if def == null else ItemRarity.display_name(def.rarity),
		"realm": "" if def == null else String(def.realm),
		"subtype": "" if def == null else String(def.subcategory),
		"equipped": slots.has(id),
		"slot": String(slots.get(id, "")),
		"fixed_options": _fixed_options(def),
		"locked_option_ids": _locked_ids(def),
		"route_boss_id": String(UniqueItem.route_boss_id(def)),
	}
	# The declared route tuning rides with the member, so a unique's index row is
	# not decoration read only by tests: the set screen is handed this snapshot by
	# the composition root and can therefore say where a unique drops and how rare
	# the drop is. The boss itself is not restated here — the definition's own tag
	# owns it — so this only carries the columns the index is allowed to keep.
	if UniqueItem.is_unique(def):
		view["route"] = drop_route(member_id)
	return view


static func _threshold_view(set_def: SetDef, index: int, active: bool) -> Dictionary:
	var tier: Dictionary = set_def.tiers[index]
	var options := _tier_options(tier)
	return {
		"index": index,
		"count": int(tier.get("count", 0)),
		"label": String(tier.get("label", "")),
		"active": active,
		"source": String(SetBonusState.tier_source(set_def.id, index)),
		"options": options,
		"option_count": options.size(),
	}


static func _tier_options(tier: Dictionary) -> Array:
	var out: Array = []
	for entry in tier.get("options", []):
		var option_id := StringName(entry.get("option_id", ""))
		if option_id == &"":
			continue
		var effect := OptionCatalog.instance().fixed_effect(
			option_id, float(entry.get("value", 0.0))
		)
		if not effect.is_empty():
			out.append(_option_view(effect))
	return out


## A definition's locked fixed options, read through the definition's own
## aggregation so the UI shows exactly what gameplay would apply.
static func _fixed_options(def: ItemDef) -> Array:
	var out: Array = []
	if def == null:
		return out
	for effect in def.effects(null):
		if String(effect.get("channel", "")) == "fixed":
			out.append(_option_view(effect))
	return out


static func _locked_ids(def: ItemDef) -> Array:
	var out: Array = []
	for option_id in UniqueItem.locked_option_ids(def):
		out.append(String(option_id))
	return out


static func _option_view(effect: Dictionary) -> Dictionary:
	return {
		"option_id": String(effect.get("option_id", "")),
		"label": String(effect.get("label", effect.get("option_id", ""))),
		"op": String(effect.get("op", "FLAT")),
		"unit": String(effect.get("unit", "magnitude")),
		"target_type": String(effect.get("target_type", "")),
		"target_id": String(effect.get("target_id", "")),
		"value": float(effect.get("value", 0.0)),
		"value_min": float(effect.get("value_min", 0.0)),
		"value_max": float(effect.get("value_max", 0.0)),
	}


static func _active_option_count(set_def: SetDef, active: Array) -> int:
	var total := 0
	for index in active:
		total += (_tier_options(set_def.tiers[int(index)]) as Array).size()
	return total
