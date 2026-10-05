class_name LootResolver
extends RefCounted

## Pure loot-table resolution. Given a table, a context and a seeded stream it
## returns a list of *drop plans* — nothing is realized, owned or mutated here.
##
## The four mechanisms run in a fixed order so their semantics stay separable:
##
##   1. Guaranteed entries    always present, exact authored quantity, resolved
##                             before any bonus is applied.
##   2. Weighted choice       `rolls..rolls_max` draws (plus the bounded
##                             `loot_bonus` count bonus), one candidate per draw,
##                             with replacement.
##   3. Independent chance    one Bernoulli roll per such entry, each independent
##                             of the draws and of each other, shifted only by the
##                             bounded `loot_bonus` chance bonus.
##   4. Non-empty guarantee   when the table declares `allow_empty = false` and
##                             nothing resolved, one forced pick restricted to
##                             direct item entries.
##
## The `loot_bonus` axes are deliberately not multiplicative. `count` is spent
## **once**, by the top-level table: a nested table resolves with a zeroed count
## bonus, so three levels of nesting cannot turn +2 draws into +8. `chance` and
## `quality` stay per-entry/per-drop, because that is what they mean.
##
## A plan carries the realm and rarity the drop must roll for, so realization
## happens in the source's context rather than the definition's.

const WARN_UNKNOWN_TABLE := "unknown_table"
const WARN_UNKNOWN_ITEM := "unknown_item"
const WARN_UNKNOWN_NESTED := "unknown_nested_table"
const WARN_DEPTH := "nesting_depth_exceeded"
const WARN_ROUTE := "unique_route_of_another_boss"
const WARN_EMPTY_POOL := "empty_weighted_pool"
const WARN_NO_FORCED_PICK := "no_item_entry_to_force"
const WARN_TRUNCATED := "plan_budget_reached"
## Ceiling on one resolve's plan count across every nesting level. With the count
## bonus confined to the top level this is a safety net, not a tuning dial: a
## deeply nested table can never multiply its way past it.
const MAX_PLANS_PER_RESOLVE := 12


## Build the resolution context. `axes` is [method LootBonus.axes].
static func make_context(
	realm: StringName, rarity: StringName, boss_id: StringName, axes: Dictionary
) -> Dictionary:
	return {
		"realm": realm,
		"rarity": rarity,
		"boss_id": boss_id,
		"chance_bonus": float(axes.get("chance", 0.0)),
		"count_bonus": int(axes.get("count", 0)),
		"quality_steps": int(axes.get("quality_steps", 0)),
	}


## Resolve `table` into `{"plans": Array, "warnings": Array}`. `plans` is a list
## of dictionaries with `entry_id`, `table_id`, `def_id`, `quantity`, `rarity`,
## `realm`, `stackable` and `unique_route`.
static func resolve(
	table: LootTableDef, context: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	return _resolve(table, context, rng, 0, [], true)


static func _resolve(
	table: LootTableDef,
	context: Dictionary,
	rng: RandomNumberGenerator,
	depth: int,
	chain: Array,
	top_level: bool
) -> Dictionary:
	var plans: Array = []
	var warnings: Array = []
	if table == null:
		warnings.append(WARN_UNKNOWN_TABLE)
		return {"plans": plans, "warnings": warnings}
	if depth > LootContent.MAX_NESTING_DEPTH:
		warnings.append("%s: %s" % [WARN_DEPTH, String(table.id)])
		return {"plans": plans, "warnings": warnings}

	# 1. Guaranteed entries. Resolved first and unconditionally, so the
	#    `loot_bonus` count bonus can neither add nor remove them.
	for entry in table.guaranteed_entries():
		_expand(entry, table, context, rng, depth, chain, plans, warnings, false)

	# 2. Weighted choice over the draw range. The count bonus is spent here and
	#    only here, so nesting multiplies authored draws but never the bonus.
	var pool := weighted_pool(table, context)
	var bonus := int(context.get("count_bonus", 0)) if top_level else 0
	var draws := table.draw_count(bonus, rng)
	if draws > 0 and pool.is_empty():
		if not table.allow_empty:
			warnings.append("%s: %s" % [WARN_EMPTY_POOL, String(table.id)])
		draws = 0
	for index in draws:
		var entry := weighted_choice(pool, rng)
		if entry != null:
			_expand(entry, table, context, rng, depth, chain, plans, warnings, true)

	# 3. Independent chance rolls.
	for entry in table.independent_entries():
		var chance := entry.effective_chance(float(context.get("chance_bonus", 0.0)))
		if chance <= 0.0 or rng == null or rng.randf() >= chance:
			continue
		_expand(entry, table, context, rng, depth, chain, plans, warnings, true)

	# 4. `allow_empty = false` means the table has declared it never comes up
	#    empty. The forced pick is restricted to direct item entries so an
	#    emptied nested table can never leave the parent empty.
	if plans.is_empty() and not table.allow_empty:
		var forced := _item_entries(pool)
		if forced.is_empty():
			warnings.append("%s: %s" % [WARN_NO_FORCED_PICK, String(table.id)])
		else:
			var entry := weighted_choice(forced, rng)
			if entry != null:
				_expand(entry, table, context, rng, depth, chain, plans, warnings, true)
	if top_level and plans.size() > MAX_PLANS_PER_RESOLVE:
		warnings.append(
			"%s: %d plan(s) dropped" % [WARN_TRUNCATED, plans.size() - MAX_PLANS_PER_RESOLVE]
		)
		return {"plans": plans.slice(0, MAX_PLANS_PER_RESOLVE), "warnings": warnings}
	return {"plans": plans, "warnings": warnings}


## The weighted pool for `table` under `context`, dropping entries whose item is
## a unique route of a different boss and entries with no positive weight.
static func weighted_pool(table: LootTableDef, context: Dictionary) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	if table == null:
		return out
	var boss_id := StringName(context.get("boss_id", ""))
	for entry in table.weighted_entries():
		if entry == null or not (entry.weight > 0.0):
			continue
		if not entry.is_nested() and not _permitted(entry, boss_id):
			continue
		out.append(entry)
	return out


## One weighted pick from `pool`, with replacement. A pool whose weights do not
## sum to a positive finite number yields nothing rather than guessing.
static func weighted_choice(pool: Array[LootEntry], rng: RandomNumberGenerator) -> LootEntry:
	var total := 0.0
	for entry in pool:
		total += entry.weight
	if pool.is_empty() or not is_finite(total) or total <= 0.0 or rng == null:
		return null
	var pick := rng.randf() * total
	for entry in pool:
		pick -= entry.weight
		if pick <= 0.0:
			return entry
	return pool[pool.size() - 1]


static func _item_entries(pool: Array[LootEntry]) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for entry in pool:
		if entry != null and not entry.is_nested():
			out.append(entry)
	return out


static func _permitted(entry: LootEntry, boss_id: StringName) -> bool:
	var def := LootContent.instance().definition(entry.item_id)
	return def == null or LootRoutes.permits(def, boss_id)


static func _expand(
	entry: LootEntry,
	table: LootTableDef,
	context: Dictionary,
	rng: RandomNumberGenerator,
	depth: int,
	chain: Array,
	plans: Array,
	warnings: Array,
	randomized: bool
) -> void:
	if entry == null:
		return
	if entry.is_nested():
		var child := LootContent.instance().table(entry.table_id)
		if child == null:
			warnings.append(
				"%s: %s.%s" % [WARN_UNKNOWN_NESTED, String(table.id), String(entry.table_id)]
			)
			return
		var nested := _resolve(
			child,
			_child_context(table, child, context),
			rng,
			depth + 1,
			chain + [String(table.id)],
			false
		)
		plans.append_array(nested["plans"])
		warnings.append_array(nested["warnings"])
		return
	var def := LootContent.instance().definition(entry.item_id)
	if def == null:
		warnings.append("%s: %s.%s" % [WARN_UNKNOWN_ITEM, String(table.id), String(entry.item_id)])
		return
	if not LootRoutes.permits(def, StringName(context.get("boss_id", ""))):
		warnings.append("%s: %s" % [WARN_ROUTE, String(entry.item_id)])
		return
	plans.append(_plan(entry, table, context, def, rng, randomized))


## A nested table resolves in its own context: its authored realm/rarity wins
## where it declares one, and it inherits the source's where it does not.
static func _child_context(
	parent: LootTableDef, child: LootTableDef, context: Dictionary
) -> Dictionary:
	var out := context.duplicate()
	var realm := StringName(context.get("realm", &""))
	if parent.realm != &"":
		realm = parent.realm
	if child.realm != &"":
		realm = child.realm
	var rarity := StringName(context.get("rarity", &""))
	if parent.rarity != &"":
		rarity = parent.rarity
	if child.rarity != &"":
		rarity = child.rarity
	out["realm"] = realm
	out["rarity"] = rarity
	return out


static func _plan(
	entry: LootEntry,
	table: LootTableDef,
	context: Dictionary,
	def: ItemDef,
	rng: RandomNumberGenerator,
	randomized: bool
) -> Dictionary:
	var realm := StringName(context.get("realm", &""))
	if realm == &"":
		realm = table.realm
	var rarity := StringName(context.get("rarity", &""))
	if rarity == &"":
		rarity = table.rarity
	rarity = _promote(rarity, entry.rarity_floor)
	var steps := int(context.get("quality_steps", 0))
	if steps > 0:
		rarity = ItemRarity.ALL[clampi(
			ItemRarity.tier(rarity) + steps, 0, ItemRarity.ALL.size() - 1
		)]
	return {
		"entry_id": String(entry.id),
		"table_id": String(table.id),
		"def_id": String(def.id),
		"quantity": entry.roll_quantity(rng, randomized),
		"rarity": String(rarity),
		"realm": String(realm),
		"stackable": bool(def.stackable),
		"unique_route": LootRoutes.routes(def),
	}


static func _promote(rarity: StringName, floor: StringName) -> StringName:
	var current := ItemRarity.tier(ItemRarity.sanitize(rarity))
	if floor == &"":
		return ItemRarity.ALL[current]
	return ItemRarity.ALL[maxi(current, ItemRarity.tier(ItemRarity.sanitize(floor)))]
