class_name SocketReadModel
extends RefCounted

## The socket program's read model: one primitives-only dictionary a screen can
## render unchanged, and the eligibility reasons behind every action in it.
##
## Separated from the facade so the projection has one job — turning owned items
## and the stored ledger into a view — and so the facade stays a set of verbs
## rather than a data builder. Nothing here mutates anything.


## One projection for `actor`: its hosts, their slots, the socket items and
## reagents it owns, what each action would cost, why it would be refused, and
## what an enchantment of the parent could produce.
static func project(
	actor: Actor, ledger: SocketLedger, parent_instance_id: StringName
) -> Dictionary:
	var parent := parent_view(actor, ledger, parent_instance_id)
	if parent.is_empty():
		return {}
	var reagents := reagent_views(actor)
	var index := focused_slot(parent)
	# Built before the projection so `affixes` is populated when `costs` and
	# `reforge_preview` read it — `project` assembles one dictionary literal, so
	# there is no statement to order these in.
	var projected := {
		"actor_id": String(actor.id),
		"realm": String(actor.realm()),
		"parent": parent,
		"hosts": host_views(actor),
		"reagents": reagents,
		"owned_socket_items": socket_item_views(actor, ledger),
		"costs": cost_views(reagents, index, parent),
		"eligibility": eligibility(actor, ledger, parent, reagents, index),
		"enchant_preview": enchant_preview(actor, ledger, parent, reagents),
		# The first affix a reforge could legally replace, and what it would cost.
		# A screen offers one control rather than a selector it must validate
		# itself; `parent.affixes` is the full list behind that choice.
		"reforge_preview": reforge_preview(actor, ledger, parent, reagents),
		"slot_count": int(parent["slot_count"]),
		"slot_cap": int(parent["cap"]),
		"imprint_used": int(parent["imprint_used"]),
		"imprint_cap": SocketPolicy.IMPRINT_CAP,
	}
	# The assembled projection (boot repair): the build above never returned it,
	# which fails this file's parse and everything through `SocketApi` up to boot.
	return projected


## The socket host a screen is looking at, and every slot it carries.
static func parent_view(
	actor: Actor, ledger: SocketLedger, parent_instance_id: StringName
) -> Dictionary:
	var owner := SocketOwnership.locate(actor, parent_instance_id)
	if owner.is_empty():
		for host in SocketOwnership.socket_hosts(actor):
			owner = {
				"instance": host["instance"],
				"def": host["def"],
				"where": host["where"],
				"slot": host["equip_slot"],
			}
			break
	if owner.is_empty():
		return {}
	var instance: ItemInstance = owner["instance"]
	var def: ItemDef = owner["def"]
	if def == null:
		return {}
	var slots: Array = []
	var imprint_used := 0
	for slot_entry in ledger.parent(instance.instance_id).get("slots", []):
		slots.append(slot_view(ledger, slot_entry))
		imprint_used += (slot_entry.get("imputed", []) as Array).size()
	var channel := ledger.channel(instance.instance_id)
	var attempts := ledger.reforge_count(instance.instance_id)
	return {
		"instance_id": String(instance.instance_id),
		"def_id": String(def.id),
		"display_name": String(def.display_name),
		"subcategory": String(def.subcategory),
		"grade": String(def.grade),
		"rarity": String(ItemRarity.sanitize(instance.rarity)),
		"rarity_label": String(ItemRarity.display_name(instance.rarity)),
		"realm": String(instance.realm),
		"required_tier": def.required_tier(),
		"equipped_slot": String(owner.get("slot", &"")),
		"where": String(owner.get("where", &"")),
		"cap": SocketPolicy.slot_cap(instance.rarity),
		"is_socket_item": SocketPolicy.is_socket_item(def),
		"carries_sockets": SocketPolicy.carries_sockets(def),
		"slots": slots,
		"slot_count": slots.size(),
		"imprint_used": imprint_used,
		"enchantment": Dictionary(channel.get("effect", {})).duplicate(true),
		"enchantment_generation": int(channel.get("generation", 0)),
		"enchantment_cap": SocketPolicy.enchant_cap(instance.rarity),
		# Every affix the item carries, each marked with whether a reforge may
		# replace it, so a screen selects among the legal ones and greys out the
		# authored ones instead of offering a press that is refused.
		"affixes": affix_views(instance),
		"reforge_attempts": attempts,
		"reforge_cap": SocketPolicy.reforge_cap(instance.rarity),
		"reforge_next_cost": SocketPolicy.reforge_cost_units(attempts),
		"reforge_exhausted": attempts >= SocketPolicy.reforge_cap(instance.rarity),
	}


## Every affix `instance` carries, with what a reforge would cost to replace it.
## `reforgable` is false for an authored fixed option, a set threshold and a
## unique's locked signature, and `blocked_reason` names why — the same strings
## the transaction refuses with, so a screen shows the reason rather than inventing
## one.
static func affix_views(instance: ItemInstance) -> Array:
	var out: Array = []
	if instance == null:
		return out
	for effect in SocketPolicy.effects_of(instance):
		var option_id := StringName(effect.get("option_id", &""))
		if option_id == &"":
			continue
		var reforgeable := SocketPolicy.is_reforgable(instance, option_id)
		out.append(
			{
				"option_id": String(option_id),
				"label": String(effect.get("label", option_id)),
				"channel": String(effect.get("channel", "")),
				"op": String(effect.get("op", "FLAT")),
				"unit": String(effect.get("unit", "magnitude")),
				"target_type": String(effect.get("target_type", "")),
				"target_id": String(effect.get("target_id", "")),
				"value": float(effect.get("value", 0.0)),
				"value_min": float(effect.get("value_min", 0.0)),
				"value_max": float(effect.get("value_max", 0.0)),
				"reforgable": reforgeable,
				"blocked_reason": "" if reforgeable else _blocked_reason(effect),
			}
		)
	return out


static func _blocked_reason(effect: Dictionary) -> String:
	if bool(effect.get("locked", false)):
		return "option_locked"
	return "authored_option"


## One slot as the screen reads it: the effects the slot itself carries and the
## gem inserted into it, kept apart so a player can see which is which.
static func slot_view(ledger: SocketLedger, slot_entry: Dictionary) -> Dictionary:
	var gem: Dictionary = slot_entry.get("gem", {})
	var gem_instance := (
		ItemInstance.from_dict(ItemInstance.migrate(gem)) if not gem.is_empty() else null
	)
	var gem_def := SocketContent.resolve(gem_instance.def_id) if gem_instance != null else null
	var gem_channel := ledger.channel(gem_instance.instance_id) if gem_instance != null else {}
	return {
		"index": int(slot_entry.get("index", 0)),
		"kind": String(slot_entry.get("kind", SocketPolicy.KIND_ANY)),
		"imputed": (slot_entry.get("imputed", []) as Array).duplicate(true),
		"imputed_count": (slot_entry.get("imputed", []) as Array).size(),
		"occupied": not gem.is_empty(),
		"gem_instance_id": "" if gem_instance == null else String(gem_instance.instance_id),
		"gem_def_id": "" if gem_instance == null else String(gem_instance.def_id),
		"gem_display_name": _gem_name(gem_instance, gem_def),
		"gem_rarity":
		"" if gem_instance == null else String(ItemRarity.sanitize(gem_instance.rarity)),
		"gem_effects": (slot_entry.get("gem_effects", []) as Array).duplicate(true),
		"gem_enchantment": Dictionary(gem_channel.get("effect", {})).duplicate(true),
	}


## Every item the actor owns that could carry a socket, worn first so a screen
## has a stable ordering to offer in its selector.
static func host_views(actor: Actor) -> Array:
	var out: Array = []
	for entry in SocketOwnership.socket_hosts(actor):
		var instance: ItemInstance = entry["instance"]
		var def: ItemDef = entry["def"]
		(
			out
			. append(
				{
					"instance_id": String(instance.instance_id),
					"def_id": "" if def == null else String(def.id),
					"display_name": "" if def == null else String(def.display_name),
					"rarity": String(ItemRarity.sanitize(instance.rarity)),
					"rarity_label": String(ItemRarity.display_name(instance.rarity)),
					"where": String(entry.get("where", &"")),
					"equipped_slot": String(entry.get("equip_slot", &"")),
				}
			)
		)
	return out


## The reagents a player could spend right now, grouped by what they are for.
static func reagent_views(actor: Actor) -> Dictionary:
	var inventory := ItemsApi.inventory(actor)
	var out := {"slot_creation": [], "imputation": [], "enchantment": []}
	for def in SocketContent.tagged(SocketApi.TAGS_SLOT_REAGENT):
		if def.tags.has(SocketApi.TAGS_SLOT_CREATION):
			out["slot_creation"].append(_reagent_view(def, inventory))
		if def.tags.has(SocketApi.TAGS_IMPUTATION):
			out["imputation"].append(_reagent_view(def, inventory))
	for def in SocketContent.tagged(SocketApi.TAGS_ENCHANTMENT):
		out["enchantment"].append(_reagent_view(def, inventory))
	return out


static func socket_item_views(actor: Actor, ledger: SocketLedger) -> Array:
	var out: Array = []
	for entry in SocketOwnership.owned_socket_items(actor, ledger):
		var instance: ItemInstance = entry["instance"]
		var def: ItemDef = entry["def"]
		(
			out
			. append(
				{
					"instance_id": String(instance.instance_id),
					"def_id": String(instance.def_id),
					"display_name": "" if def == null else String(def.display_name),
					"kind": String(SocketPolicy.kind_of(def)),
					"rarity": String(ItemRarity.sanitize(instance.rarity)),
					"realm": String(instance.realm),
					"socketed": bool(entry.get("socketed", false)),
				}
			)
		)
	return out


## What an enchantment of this parent could produce. A pure read: no unit is
## consumed, no state written and no roll stream advanced.
static func enchant_preview(
	actor: Actor, ledger: SocketLedger, parent: Dictionary, reagents: Dictionary
) -> Dictionary:
	return EnchantmentService.preview(
		actor,
		ledger,
		StringName(String(parent.get("instance_id", ""))),
		SocketContent.resolve(StringName(first_held(reagents["enchantment"])))
	)


## A reforge preview for the first affix on `parent` that may legally be
## replaced, so a screen has one control to offer and one reason to show. It is
## the same `ReforgeService.preview` the facade calls — a pure read — so a button
## built from it cannot disagree with the commit behind it. `option` is "" when no
## affix on the item is reforgeable, which is the case for a common item and for
## an item whose affixes are all authored.
static func reforge_preview(
	actor: Actor, ledger: SocketLedger, parent: Dictionary, reagents: Dictionary
) -> Dictionary:
	var option_id := first_reforgeable(parent)
	if option_id == "":
		return ReforgeService.preview(
			actor, ledger, StringName(String(parent.get("instance_id", ""))), &"", null
		)
	return ReforgeService.preview(
		actor,
		ledger,
		StringName(String(parent.get("instance_id", ""))),
		StringName(option_id),
		SocketContent.resolve(StringName(first_held(reagents["enchantment"])))
	)


## The first affix on `parent` a reforge may replace, as an id. "" when the item
## has none: every affix authored, or the cap already spent. Bounded by the
## affixes the item carries.
static func first_reforgeable(parent: Dictionary) -> String:
	for entry in parent.get("affixes", []):
		if bool((entry as Dictionary).get("reforgable", false)):
			return String((entry as Dictionary)["option_id"])
	return ""


## The reagent a player holds for each action, and what the focused slot looks
## like right now. Empty ids mean the actor holds nothing usable for that action.
static func cost_views(reagents: Dictionary, index: int, parent: Dictionary) -> Dictionary:
	var slots: Array = parent.get("slots", [])
	var focused: Dictionary = {}
	for slot_entry in slots:
		if int(slot_entry["index"]) == index:
			focused = slot_entry
	return {
		"create_slot": first_held(reagents["slot_creation"]),
		"impute_slot": first_held(reagents["imputation"]),
		"enchantment": first_held(reagents["enchantment"]),
		# Reforge spends the enchantment reagent, so the held unit is the same
		# string and the cost shown is the ESCALATED one, not the flat reagent
		# count above: a screen that showed "1" here would quote a price the
		# transaction would refuse to honour.
		"reforge": first_held(reagents["enchantment"]),
		"reforge_units": SocketPolicy.reforge_cost_units(
			int(parent.get("reforge_attempts", 0))
		),
		"slot_index": index,
		"slot_kind": String(focused.get("kind", SocketPolicy.KIND_ANY)),
		"slot_occupied": bool(focused.get("occupied", false)),
		"slot_imputed": int(focused.get("imputed_count", 0)),
	}


## Why each action is unavailable right now. An empty string means it would
## commit; anything else is the gameplay reason a player is shown.
static func eligibility(
	actor: Actor, ledger: SocketLedger, parent: Dictionary, reagents: Dictionary, index: int
) -> Dictionary:
	var parent_id := StringName(String(parent.get("instance_id", "")))
	var create_id := first_held(reagents["slot_creation"])
	var impute_id := first_held(reagents["imputation"])
	var enchant_id := first_held(reagents["enchantment"])
	var gem_id := _first_free_socket_item(actor, ledger)
	var out := {
		"create_slot":
		SlotService.creation_refusal(
			actor, ledger, parent_id, SocketContent.resolve(StringName(create_id))
		),
		"impute_slot":
		SlotService.imputation_refusal(
			actor, ledger, parent_id, index, SocketContent.resolve(StringName(impute_id))
		),
		"insert_socket": SlotService.insertion_refusal(actor, ledger, parent_id, index, gem_id),
		"extract_socket": SlotService.extraction_refusal(actor, ledger, parent_id, index),
		"enchantment":
		EnchantmentService.refusal(
			actor, ledger, parent_id, SocketContent.resolve(StringName(enchant_id))
		),
		# One reason per candidate affix, keyed by option id, because a reforge
		# names an AFFIX rather than an item: "why can I not replace this one" is
		# the question a screen actually has to answer.
		"reforge": reforge_refusals(actor, ledger, parent_id, enchant_id),
	}
	# No reagent in hand is its own reason: an unknown id must not be reported as
	# a missing definition.
	if create_id == "":
		out["create_slot"] = "missing_cost"
	if impute_id == "":
		out["impute_slot"] = "missing_cost"
	if enchant_id == "":
		out["enchantment"] = "missing_cost"
	# A reforge with no reagent in hand is refused the same way, so the map is not
	# published as a set of empty reasons that read as "available".
	if enchant_id == "":
		out["reforge"] = {}
	return out


## Why replacing each affix on `parent_id` would refuse, keyed by option id. An
## absent key means the affix is not on the item; an empty string means it would
## commit. The set is bounded by the affixes the item carries, so this never walks
## the catalog.
static func reforge_refusals(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, reagent_id: String
) -> Dictionary:
	var out := {}
	var owner := SocketOwnership.locate(actor, parent_id)
	var instance := owner.get("instance") as ItemInstance
	if instance == null:
		return out
	var reagent := SocketContent.resolve(StringName(reagent_id))
	for effect in SocketPolicy.effects_of(instance):
		var option_id := StringName(effect.get("option_id", &""))
		if option_id == &"" or out.has(String(option_id)):
			continue
		out[String(option_id)] = ReforgeService.refusal(
			actor, ledger, parent_id, option_id, reagent
		)
	return out


## The slot a screen acts on: the first one the item carries, or slot 0 when it
## carries none and a socket is about to be opened.
static func focused_slot(parent: Dictionary) -> int:
	var slots: Array = parent.get("slots", [])
	return 0 if slots.is_empty() else int((slots[0] as Dictionary)["index"])


## The first reagent of a group the actor actually holds, or "".
static func first_held(entries: Array) -> String:
	for entry in entries:
		if int(entry["held"]) > 0:
			return String(entry["def_id"])
	return ""


static func _reagent_view(def: ItemDef, inventory: Inventory) -> Dictionary:
	return {
		"def_id": String(def.id),
		"display_name": String(def.display_name),
		"kind": String(SocketPolicy.kind_of(def)),
		"grade": String(def.grade),
		"rarity": String(def.rarity),
		"realm": String(def.realm),
		"held": 0 if inventory == null else inventory.count(def.id),
		"cost": 1,
	}


## The gem's readable name, falling back to its definition id so a socketed slot
## is never rendered blank.
static func _gem_name(instance: ItemInstance, def: ItemDef) -> String:
	if def != null and String(def.display_name) != "":
		return String(def.display_name)
	return "" if instance == null else String(instance.def_id)


static func _first_free_socket_item(actor: Actor, ledger: SocketLedger) -> StringName:
	for entry in SocketOwnership.owned_socket_items(actor, ledger):
		if not bool(entry.get("socketed", false)):
			return (entry["instance"] as ItemInstance).instance_id
	return &""
