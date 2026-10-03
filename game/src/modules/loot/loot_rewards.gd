class_name LootRewards
extends RefCounted

## Reward payloads: build one per encounter, realize its drops, hand them over,
## and project them for a reader.
##
## A payload is a plain, versioned dictionary so it can live in
## `actor.module_data` and round-trip through JSON. Every unit of a drop is
## realized **at defeat time**, from the source's realm and rarity context, and
## stored as a full instance dictionary: a drop therefore exists in the world
## before the player picks it up, and a save/load between defeat and pickup
## restores the exact rolls rather than re-rolling them (ADR 0027).
##
## Pickup is all-or-nothing per drop record, which is what makes "a failed pickup
## never consumes a claim" true without partial-claim bookkeeping.

const PAYLOAD_VERSION := 1
## Shared realization of a stackable drop: every unit of one drop record carries
## the same realization, so they merge into one batch and never disagree.
const SHARED_INSTANCE_SUFFIX := "#i0"
const UNIT_INSTANCE_FORMAT := "#u%d"


## Build the single reward payload for a defeated boss. `plans` come from
## [method LootResolver.resolve].
static func build(
	encounter_id: String,
	boss_id: StringName,
	domain_id: StringName,
	tier: LootTier,
	table: LootTableDef,
	plans: Array,
	seed_value: int,
	warnings: Array = []
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var drops: Array = []
	var blocked := warnings.duplicate()
	for index in plans.size():
		var plan: Dictionary = plans[index]
		if LootContent.instance().definition(StringName(plan.get("def_id", ""))) == null:
			# The resolver already refuses an unresolvable id; belt and braces so a
			# payload can never claim to hold an item the game cannot define.
			blocked.append(
				"%s: %s" % [LootResolver.WARN_UNKNOWN_ITEM, String(plan.get("def_id", ""))]
			)
			continue
		drops.append(_drop("%s#d%d" % [encounter_id, index], plan, rng))
	return {
		"version": PAYLOAD_VERSION,
		"encounter_id": encounter_id,
		## The claim token for this encounter. Stable across reloads, so a
		## repeated defeat, a re-entry and a load all address the same payload.
		"claim_token": encounter_id,
		"source_kind": "boss",
		"source_id": String(boss_id),
		"domain_id": String(domain_id),
		"boss_id": String(boss_id),
		"table_id": String(table.id) if table != null else "",
		"tier": int(tier.tier) if tier != null else 0,
		"tier_label": String(tier.label) if tier != null else "",
		"realm": String(tier.realm) if tier != null else "",
		"rarity": String(tier.rarity) if tier != null else "",
		"seed": seed_value,
		"drops": drops,
		"warnings": blocked,
	}


static func _drop(drop_id: String, plan: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var def := LootContent.instance().definition(StringName(plan.get("def_id", "")))
	var quantity := maxi(1, int(plan.get("quantity", 1)))
	var realm := StringName(plan.get("realm", ""))
	var rarity := ItemRarity.sanitize(StringName(plan.get("rarity", &"")))
	var instance_id := StringName("%s%s" % [drop_id, SHARED_INSTANCE_SUFFIX])
	var realized := ItemInstance.new(def.id, instance_id)
	realized.def_ref = def
	realized.rarity = rarity
	realized.realm = realm
	realized.catalog_version = ItemGenerator.CONFIG_VERSION
	if bool(def.is_rollable()):
		# The drop rolls for the realm and rarity it fell from, not the ones its
		# definition was authored at: a late boss's drop rolls at that realm.
		var contextual := contextualize(def, realm, rarity)
		realized = ItemGenerator.generate(contextual, instance_id, rng)
		realized.def_ref = contextual
	return {
		"drop_id": drop_id,
		"entry_id": String(plan.get("entry_id", "")),
		"table_id": String(plan.get("table_id", "")),
		"def_id": String(def.id),
		"quantity": quantity,
		"stackable": bool(def.stackable),
		"rarity": String(realized.rarity),
		"realm": String(realized.realm),
		"instance": realized.to_dict(),
		"claimed": false,
		"stashed": false,
	}


## A copy of `def` carrying a drop's realm/rarity context. Shared authored content
## is never mutated; when the context already matches, the definition is reused.
static func contextualize(def: ItemDef, realm: StringName, rarity: StringName) -> ItemDef:
	if def == null:
		return null
	if String(def.realm) == String(realm) and String(def.rarity) == String(rarity):
		return def
	var copy := def.duplicate() as ItemDef
	copy.realm = realm
	copy.rarity = rarity
	return copy


## The realized instance a drop record describes. `suffix` mints a distinct
## instance id for one unit of a non-stackable drop; the realization itself is
## identical either way.
static func instance_from(drop: Dictionary, suffix: String) -> ItemInstance:
	var data: Dictionary = drop.get("instance", {}) as Dictionary
	var instance := ItemInstance.from_dict(ItemInstance.migrate(data.duplicate(true)))
	if suffix != "":
		instance.instance_id = StringName("%s%s" % [String(drop.get("drop_id", "drop")), suffix])
	instance.def_ref = LootContent.instance().definition(instance.def_id)
	return instance


## Whether this drop can be handed over right now. A stackable drop needs either
## an existing batch it can merge into or a free slot; a non-stackable one needs
## one free slot per unit.
static func fits(drop: Dictionary, inventory: Inventory, realized: ItemInstance) -> bool:
	if inventory == null:
		return false
	var quantity := maxi(1, int(drop.get("quantity", 1)))
	if not bool(drop.get("stackable", false)):
		return quantity <= maxi(0, inventory.capacity - inventory.used_slots())
	var probe := ItemStack.from_instance(realized, 0)
	for batch in inventory.stacks():
		if batch.def_id == probe.def_id and batch.signature() == probe.signature():
			return true
	return inventory.used_slots() < inventory.capacity


## Hand a drop to the inventory. Returns the leftover unit count; callers must
## treat anything above zero as a failed pickup and leave the claim untouched.
static func deliver(drop: Dictionary, inventory: Inventory) -> int:
	if inventory == null:
		return maxi(1, int(drop.get("quantity", 1)))
	var def := LootContent.instance().definition(StringName(drop.get("def_id", "")))
	if def == null:
		return maxi(1, int(drop.get("quantity", 1)))
	var quantity := maxi(1, int(drop.get("quantity", 1)))
	var realized := instance_from(drop, "")
	if bool(drop.get("stackable", def.stackable)):
		var batch := ItemStack.from_instance(realized, quantity)
		batch.def_ref = def
		return inventory.add_batch(batch)
	var leftover := 0
	for unit in quantity:
		var one := instance_from(drop, UNIT_INSTANCE_FORMAT % unit)
		one.def_ref = def
		if inventory.add_instance(one) != 0:
			leftover += 1
	return leftover


# --- Reader projections -----------------------------------------------------


## Primitives-only view of a payload. Counts stay raw; the reader owns every
## `%d` and every wording.
static func view(payload: Dictionary) -> Dictionary:
	var drops: Array = payload.get("drops", [])
	var claimed := 0
	var stashed := 0
	var pending := 0
	var rows: Array = []
	for drop in drops:
		var entry := drop_view(drop)
		if bool(entry["claimed"]):
			claimed += 1
		elif bool(entry["stashed"]):
			stashed += 1
		else:
			pending += 1
		rows.append(entry)
	return {
		"encounter_id": String(payload.get("encounter_id", "")),
		"claim_token": String(payload.get("claim_token", "")),
		"source_kind": String(payload.get("source_kind", "")),
		"source_id": String(payload.get("source_id", "")),
		"domain_id": String(payload.get("domain_id", "")),
		"boss_id": String(payload.get("boss_id", "")),
		"table_id": String(payload.get("table_id", "")),
		"tier": int(payload.get("tier", 0)),
		"tier_label": String(payload.get("tier_label", "")),
		"realm": String(payload.get("realm", "")),
		"rarity": String(payload.get("rarity", "")),
		"drop_count": drops.size(),
		"claimed_count": claimed,
		"stashed_count": stashed,
		"pending_count": pending,
		"settled": pending == 0 and stashed == 0,
		"warnings": payload.get("warnings", []).duplicate(),
		"drops": rows,
	}


## Primitives-only view of one drop, carrying its resolved effects so a panel can
## format them without the UI program naming any item type.
static func drop_view(drop: Dictionary) -> Dictionary:
	var def := LootContent.instance().definition(StringName(drop.get("def_id", "")))
	var instance := instance_from(drop, "")
	var effects: Array = def.effects(instance) if def != null else []
	return {
		"drop_id": String(drop.get("drop_id", "")),
		"entry_id": String(drop.get("entry_id", "")),
		"table_id": String(drop.get("table_id", "")),
		"def_id": String(drop.get("def_id", "")),
		"display_name": String(def.display_name) if def != null else "",
		"category": String(def.category) if def != null else "",
		"subcategory": String(def.subcategory) if def != null else "",
		"grade": String(def.grade) if def != null else "",
		"quantity": int(drop.get("quantity", 1)),
		"stackable": bool(drop.get("stackable", false)),
		"rarity": String(instance.rarity),
		"realm": String(instance.realm),
		"instance_id": String(instance.instance_id),
		"rolled_count": instance.rolled.size(),
		"effect_count": effects.size(),
		"effects": effects,
		"claimed": bool(drop.get("claimed", false)),
		"stashed": bool(drop.get("stashed", false)),
		"claimable": not bool(drop.get("claimed", false)) and not bool(drop.get("stashed", false)),
	}


## Primitives-only view of the in-progress encounter.
static func active_view(active: Dictionary) -> Dictionary:
	if active.is_empty():
		return {
			"in_domain": false,
			"domain_id": "",
			"encounter_id": "",
			"boss_id": "",
			"defeated": false,
			"attack": 0.0,
			"defense": 0.0,
		}
	var vitality := float(active.get("vitality", 0.0))
	var vitality_max := maxf(1.0, float(active.get("vitality_max", 1.0)))
	return {
		"in_domain": true,
		"domain_id": String(active.get("domain_id", "")),
		"encounter_def": String(active.get("encounter_def", "")),
		"tier": int(active.get("tier", 0)),
		"tier_label": String(active.get("tier_label", "")),
		"run": int(active.get("run", 0)),
		"boss_index": int(active.get("boss_index", 0)),
		"boss_id": String(active.get("boss_id", "")),
		"encounter_id": String(active.get("encounter_id", "")),
		"vitality": vitality,
		"vitality_max": vitality_max,
		"health_ratio": clampf(vitality / vitality_max, 0.0, 1.0),
		"realm": String(active.get("tier_realm", "")),
		"rarity": String(active.get("tier_rarity", "")),
		# The boss's own numbers, priced off the band's authored vitality (ADR 0076). Read
		# here so the combat module can meet a blow with them through this module's
		# facade, and so a panel can show what it is fighting.
		"attack": float(active.get("attack", 0.0)),
		"defense": float(active.get("defense", 0.0)),
		"defeated": bool(active.get("defeated", false)),
	}
