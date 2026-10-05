class_name RealmScaling
extends RefCounted

## Applies the highest realm's stat multiplier to an actor's scalable stats as a
## source-tagged MULT modifier (ADR 0001/0005). Re-applying replaces the old ones.
##
## The multiplier is `RealmDef.power`: one authored number per realm, read from
## `core/realm_power_table.tres`. Nothing here computes it from the realm index
## (ADR 0050). There is no formula to fall back on, so a subsystem that needs a
## different shape has to say so in its own data instead of growing a private curve
## next door to this one.

const SOURCE := &"realm"
const SCALED_STATS := [
	Stat.MAX_HEALTH,
	Stat.MAX_QI,
	Stat.MAX_STAMINA,
	Stat.ATTACK_PHYSICAL,
	Stat.ATTACK_SPIRITUAL,
	Stat.DEFENSE_PHYSICAL,
	Stat.DEFENSE_SPIRITUAL,
]


static func apply(actor: Actor) -> void:
	actor.stats.remove_modifiers_from(SOURCE)
	var realm := highest_realm(actor)
	if realm == null:
		return
	var power := realm.power
	for id in SCALED_STATS:
		actor.stats.add_modifier(StatModifier.new(id, Stat.Op.MULT, power, SOURCE))


static func highest_realm(actor: Actor) -> RealmDef:
	var ladder := RealmDefaults.ladder()
	var best := -1
	for state in actor.paths.values():
		best = maxi(best, ladder.index_of(state.rank_id))
	if best < 0:
		return null
	return ladder.realms()[best]
