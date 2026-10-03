class_name BossDef
extends Resource

## Data-driven boss (ADR 0008). Spawns in a domain and drops loot items.
##
## ## A boss is a combatant, not a health bag
##
## `attack` and `defense` are NOT here. They are priced off the band vitality the
## encounter already authors (`LootTier.attack_for` / `defense_for`, ADR 0076), so one
## authored number prices both halves of an encounter and a weak binding is weak in both
## directions.
##
## What IS here is the boss's own **striking profile**: how this creature fights, as
## opposed to how hard its band is. Every field below is read by
## `CombatDamage.resolve_hit`, which is the same function a player's blow resolves
## through — so a boss and a player meet on one damage model, and a boss's identity is
## authored data rather than a literal in the combat module. Before these fields existed
## every boss in the game exchanged blows through a hardcoded `{0 crit, 1.0 crit damage,
## 0 penetration, 0 evasion, 0 damage reduction}` profile: no boss could crit, pierce,
## slip a blow, or soften one, and no content could change that.
##
## ## The defaults are the inert profile, deliberately
##
## `crit_chance 0` / `crit_damage 1.0` / the rest zero is exactly the behaviour that
## existed before these fields, so authoring nothing is the same as always. They are not
## a suggestion of balance: `CombatDamage` clamps every one of them (`crit_chance` and
## `evasion` into 0..1, `damage_reduction` under `MITIGATION_CEILING`, `crit_damage`
## under a share of 1.0), so a bad number here cannot make a fight unwinnable or
## unlosable — it can only make the boss different.

@export var id: StringName = &""
@export var display_name: String = ""
@export var domain_id: StringName = &""
## Legacy flat item list, the pre-loot-table migration path. Empty across the shipped
## corpus: what a boss drops is bound on `LootTier.boss_tables` (ADR 0033), and
## `LootContent.table_for_boss` is the single authority between them.
@export var loot: Array[StringName] = []
## Chance the boss's answer lands as a crit. 0 means it never does.
@export var crit_chance: float = 0.0
## Crit multiplier, with a 1.5 baseline like the player's own. 1.0 means a crit is no
## heavier than an ordinary blow, which is what "no crits authored" wants.
@export var crit_damage: float = 1.0
## How much of the target's mitigation this boss cuts through. Normalised against the
## player's own reference penetration, so a large number approaches the model's ceiling
## rather than erasing mitigation outright.
@export var penetration: float = 0.0
## Chance the boss slips a blow entirely. A slipped blow spends nothing of the player's
## pool, and applies no status.
@export var evasion: float = 0.0
## Flat share of a blow this boss removes before the mitigation ratio, on top of its
## armor. Adds to the ratio rather than multiplying it, like the player's own.
@export var damage_reduction: float = 0.0


## The profile as the bundle `CombatDamage.resolve_hit` reads, clamped into the ranges
## the model works in. Empty-safe: a boss nobody authored reads as the inert profile.
func combat_profile() -> Dictionary:
	return {
		"crit_chance": clampf(crit_chance, 0.0, 1.0),
		"crit_damage": maxf(0.0, crit_damage),
		"penetration": maxf(0.0, penetration),
		"evasion": clampf(evasion, 0.0, 1.0),
		"damage_reduction": clampf(damage_reduction, 0.0, 1.0),
	}
