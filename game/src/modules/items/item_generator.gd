class_name ItemGenerator
extends RefCounted

## Seeded item generation (ADR 0025). Realizes an item's rolled channel from its
## declared derived pool under the item's rarity/realm policy. Deterministic:
## the same seed and configuration version reproduce the same realization, and
## canonical pool ordering makes registration order irrelevant.

const CONFIG_VERSION := 2


## Build a realized instance for `def`, rolling `roll_count` options.
static func generate(
	def: ItemDef, instance_id: StringName, rng: RandomNumberGenerator
) -> ItemInstance:
	var instance := ItemInstance.new(def.id, instance_id)
	instance.rarity = ItemRarity.sanitize(def.rarity)
	instance.realm = def.realm
	instance.catalog_version = CONFIG_VERSION
	instance.seed = rng.seed
	instance.rolled = roll(def, rng)
	return instance


## Realized rolled options for `def` under its rarity and realm policy.
static func roll(def: ItemDef, rng: RandomNumberGenerator) -> Array[Dictionary]:
	if def.roll_spec.is_empty():
		return []
	var contexts := ItemRarity.contexts(def.rarity)
	var spec_contexts: Array = def.roll_spec.get("contexts", [])
	var chosen: Array[StringName] = []
	for context in contexts:
		if spec_contexts.is_empty() or spec_contexts.has(String(context)):
			chosen.append(context)
	if chosen.is_empty():
		return []
	var count := roll_count(def)
	if count <= 0:
		return []
	var realm_index := realm_index_for(def)
	var rarity_index := ItemRarity.tier(def.rarity)
	var realized: Array[Dictionary] = []
	var used: Array[StringName] = []
	for position in count:
		var context: StringName = chosen[position % chosen.size()]
		var effect := OptionCatalog.instance().roll_next(
			def.activation(), context, used, realm_index, rarity_index, rng
		)
		if effect.is_empty():
			break
		used.append(StringName(effect.get("option_id", "")))
		realized.append(effect)
	return realized


## How many rolled options this item receives. A roll spec may widen or narrow
## the rarity band but never silently produces a zero-count item for a rollable
## category: `count` defaults to the rarity policy and is clamped to the pool.
static func roll_count(def: ItemDef) -> int:
	var from_rarity := ItemRarity.affix_count(def.rarity)
	if def.roll_spec.is_empty():
		return from_rarity
	return maxi(1, int(def.roll_spec.get("count", from_rarity)))


## Index of the definition's realm on the canonical 30-realm ladder. Items with
## no authored realm roll at the ladder's start; gates are a separate concern.
static func realm_index_for(def: ItemDef) -> int:
	if def.realm == &"":
		return 0
	var index := RealmDefaults.ladder().index_of(def.realm)
	return maxi(0, index)
