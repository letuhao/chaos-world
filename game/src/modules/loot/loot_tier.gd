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
##
## ## The band's vitality also prices the fight (ADR 0076)
##
## `attack_for` / `defense_for` express a boss's own combat numbers as multiples of the
## vitality this band already authors, so one authored number prices both halves of an
## encounter: a band that is hard to kill is a band that hits back, and a weak binding is
## weak in both directions. It is deliberately **not** a second authored field per
## binding — sixty-odd tiers of new content would be a content wave to express a
## relationship `vitality` already implies — and it is deliberately **not** derived from a
## realm index: a band names its realm, and `RealmPowerTable` is the actor table, not a
## boss's.

## What share of a band's authored vitality one point of a boss's attack is worth, and of
## its defense. Two named constants rather than two authored tables: the numbers a boss
## fights with are a consequence of how hard the band is to kill, not a second balance
## dial nobody owns. A band at 520 vitality fields an attack of 130.
const ATTACK_PER_VITALITY := 0.25
const DEFENSE_PER_VITALITY := 0.25

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


## The attack `boss_id` exchanges with, priced off the same authored vitality its pool is
## drawn from (ADR 0076). Frozen into the spawned boss, so a resumed fight is the fight
## that was priced.
func attack_for(boss_id: StringName) -> float:
	return vitality_for(boss_id) * ATTACK_PER_VITALITY


## The defense `boss_id` meets a blow with, on the same terms as [method attack_for].
func defense_for(boss_id: StringName) -> float:
	return vitality_for(boss_id) * DEFENSE_PER_VITALITY


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
