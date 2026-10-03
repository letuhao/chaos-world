class_name CombatApi
extends RefCounted

## Public facade for the `combat` module (ADR 0076).
##
## ## What this module is
##
## Exactly one thing: **an encounter is a stat-resolved exchange, and either side can win
## it.** `CombatDamage` resolves a blow from two stat bundles; `CombatExchange` runs one
## fight turn against the live boss the `loot` module owns and settles the loss when the
## player runs out of health.
##
## ## What was deleted, and why it is not coming back
##
## `Shield`, `attach_shield` and `shield` were two files with zero callers whose docstring
## promised "damage depletes the shield before health" — a promise no code honoured. ADR
## 0076 deletes them rather than leaving behaviour the code lacks. A shield is a wave the
## spine does not have yet; when it does, it is a component in the spine's own slot, not a
## second resource pool bolted onto the module's front door.
##
## ## The division of labour
##
## `loot` owns the encounter: whose vitality is spent, the once-only reward, the run
## lifecycle. `combat` owns the resolution: how much a blow is worth and what the boss
## answers with. So `combat` depends on `loot` through its facade and `loot` knows nothing
## of `combat` — the edge runs one way, and `tools arch` enforces it.
##
## ## Every exchange is a share, never a magnitude
##
## Damage is a fraction of the target's own pool, which is what makes the model safe
## against a 551x realm table meeting 12x authored vitality: both pools are spent by the
## same fraction, so a realm lifts both sides together. See `CombatDamage` for the shape
## and `core/realm_power_table.tres` for the table this deliberately does not extend.
##
## ## Why these are thin delegates
##
## The behaviour lives in `CombatExchange` and `CombatDamage`, not here. This file exists
## because the cross-module rule is facade-only, and a caller that reaches for
## `res://src/modules/combat/api.gd` should not have to know which of the module's scripts
## happens to hold the arithmetic.

## The player spent the boss's remaining vitality. Aliased from CombatExchange so a screen
## matches one vocabulary and the module keeps exactly one source for it.
const OUTCOME_BOSS_DEFEATED := CombatExchange.OUTCOME_BOSS_DEFEATED
## The boss outlasted the player and the run is over.
const OUTCOME_PLAYER_LOST := CombatExchange.OUTCOME_PLAYER_LOST


## Run one exchange with the live boss. See [method CombatExchange.exchange].
static func exchange(actor: Actor, seed_value: int = 0) -> Dictionary:
	return CombatExchange.exchange(actor, seed_value)


## The player's fight state: their health pool. See [method CombatExchange.player].
static func player(actor: Actor) -> Dictionary:
	return CombatExchange.player(actor)


## A fight the player has not started: their numbers, their health, their losses. See
## [method CombatExchange.preview].
static func preview(actor: Actor) -> Dictionary:
	return CombatExchange.preview(actor)


## The fights this actor has lost. See [method CombatExchange.duel].
static func duel(actor: Actor) -> Dictionary:
	return CombatExchange.duel(actor)


## How much of the target's own pool one blow is worth against a defense bundle. See
## [method CombatExchange.resolve_share]'s implementation in `CombatDamage`: a read that
## moves nothing, so a preview can quote the exact number an exchange would spend.
static func resolve_share(
	offense: Dictionary, defense: Dictionary, rng: RandomNumberGenerator = null
) -> Dictionary:
	return CombatDamage.resolve_hit(offense, defense, rng)


## The player's own offensive numbers, as the bundle `resolve_share` reads. See
## [method CombatExchange.offense].
static func offense(actor: Actor) -> Dictionary:
	return CombatExchange.offense(actor)


## The player's own defensive numbers, as the bundle `resolve_share` reads. See
## [method CombatExchange.guard].
static func guard(actor: Actor) -> Dictionary:
	return CombatExchange.guard(actor)
