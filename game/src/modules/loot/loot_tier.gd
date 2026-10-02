class_name LootTier
extends Resource

## One authored difficulty band of an encounter.
##
## Everything about the band is authored data: the realm and rarity a drop rolls
## for, the vitality its bosses have, and the loot table each boss drops from.
## Nothing here is derived from the player's gear, so a band cannot become easier
## just because the player got stronger — reaching a higher band is a separate,
## authored decision.
##
## `boss_tables` is the single place a boss's loot table is bound for this band:
## `[{boss_id: StringName, table_id: StringName, vitality: float}]`. `vitality` is
## optional and falls back to the band's authored value.

@export var tier: int = 1
@export var label: String = ""
@export var realm: StringName = &""
@export var rarity: StringName = &""
## Authored vitality for this band's bosses.
@export var vitality: float = 100.0
@export var boss_tables: Array[Dictionary] = []


func table_for(boss_id: StringName) -> StringName:
	for binding in boss_tables:
		if StringName(binding.get("boss_id", "")) == boss_id:
			return StringName(binding.get("table_id", ""))
	return &""


func binding_for(boss_id: StringName) -> Dictionary:
	for binding in boss_tables:
		if StringName(binding.get("boss_id", "")) == boss_id:
			return binding
	return {}


## Authored vitality for `boss_id`: the per-binding value when it declares one,
## otherwise the band's value. Never zero, so a boss always needs real damage.
func vitality_for(boss_id: StringName) -> float:
	var authored := float(binding_for(boss_id).get("vitality", 0.0))
	return maxf(1.0, authored if authored > 0.0 else vitality)


## Boss ids bound in this band, in authored order.
func boss_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for binding in boss_tables:
		var boss_id := StringName(binding.get("boss_id", ""))
		if boss_id != &"" and not out.has(boss_id):
			out.append(boss_id)
	return out


func table_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for binding in boss_tables:
		var table_id := StringName(binding.get("table_id", ""))
		if table_id != &"" and not out.has(table_id):
			out.append(table_id)
	return out
