class_name UniqueItem
extends RefCounted

## Unique-item identity (ADR 0025/0033).
##
## A unique is a *stable authored identity*, not "the only copy in the world":
## it has an id, a locked fixed signature, a declared boss route, and the same
## bounded rolled channel every other item gets. Two properties are enforced
## here rather than left to content conventions:
##
##   - The locked fixed signature is authored, never rolled. Rolling may only
##     *add* options, and may never reuse an option the signature already locks.
##   - A treatment that would alter a locked option is refused. `is_locked` is
##     the predicate a treatment runtime asks before it rewrites an option.

## Tag every unique definition carries. Identity is data, not a subclass.
const TAG := &"unique"
## `tags` entry naming the boss a unique drops from: `unique_route:<boss_id>`.
const ROUTE_TAG_PREFIX := "unique_route:"
## Hard ceiling on how many extra rolled options a unique may gain while topping
## up around its locked signature. A bounded search never runs away.
const MAX_TOP_UP_ROUNDS := 8


static func is_unique(def: ItemDef) -> bool:
	return def != null and def.tags.has(TAG)


## The option ids a unique's signature locks. These are the authored fixed
## values, read straight from the definition — never from a realization.
static func locked_option_ids(def: ItemDef) -> Array[StringName]:
	var out: Array[StringName] = []
	if def == null:
		return out
	for entry in def.fixed_modifiers:
		var option_id := StringName(entry.get("option_id", ""))
		if option_id != &"" and not out.has(option_id):
			out.append(option_id)
	return out


## Whether `option_id` is part of this unique's locked signature. A treatment
## that resolves this to true must refuse to touch the option.
##
## Only a unique locks anything. An ordinary item — including a set piece — has no
## locked signature, so a treatment is free to work on every option it carries.
static func is_locked(def: ItemDef, option_id: StringName) -> bool:
	if not is_unique(def):
		return false
	return locked_option_ids(def).has(option_id)


## The boss a unique declares as its drop route, read from the definition's own
## tags so the declaration travels with the item. `&""` when it names none.
static func route_boss_id(def: ItemDef) -> StringName:
	if def == null:
		return &""
	for tag in def.tags:
		var text := String(tag)
		if text.begins_with(ROUTE_TAG_PREFIX):
			return StringName(text.substr(ROUTE_TAG_PREFIX.length()))
	return &""


## Realize a unique. The locked fixed signature is untouched; the rolled channel
## is filled up to the item's roll count with options that are neither locked
## nor already rolled, so a unique always gets both channels and never a
## doubled one. Deterministic: the same seed reproduces the same realization.
static func forge(
	def: ItemDef, instance_id: StringName, rng: RandomNumberGenerator
) -> ItemInstance:
	var instance := ItemGenerator.generate(def, instance_id, rng)
	if not is_unique(def):
		return instance
	var locked := locked_option_ids(def)
	var rolled := _without_locked(instance.rolled, locked)
	var target := ItemGenerator.roll_count(def)
	var rounds := 0
	while rolled.size() < target and rounds < MAX_TOP_UP_ROUNDS:
		rounds += 1
		var extra := _without_locked(ItemGenerator.roll(def, rng), locked)
		if extra.is_empty():
			break
		rolled = _merge(rolled, extra, target)
	instance.rolled = rolled
	return instance


## Dropped effects whose option the unique's signature already locks. Rolling
## never re-authors a fixed value; it only ever adds a different option.
static func _without_locked(
	effects: Array[Dictionary], locked: Array[StringName]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect in effects:
		if not locked.has(StringName(effect.get("option_id", ""))):
			out.append(effect)
	return out


## Merge two rolled batches, keeping the first realization of each option, then
## cap at `limit`. The cap is what makes the top-up bounded: a unique receives
## exactly its roll count, never more, no matter how many rounds it takes to fill.
static func _merge(a: Array[Dictionary], b: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array[StringName] = []
	for effect in a + b:
		if out.size() >= limit:
			break
		var option_id := StringName(effect.get("option_id", ""))
		if seen.has(option_id):
			continue
		seen.append(option_id)
		out.append(effect)
	return out
