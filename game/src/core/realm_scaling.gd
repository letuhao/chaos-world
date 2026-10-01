class_name RealmScaling
extends RefCounted

## Applies the highest realm's power multiplier to an actor's scalable stats as a
## source-tagged MULT modifier (ADR 0001/0005). Re-applying replaces the old ones.

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
	for id in SCALED_STATS:
		actor.stats.add_modifier(StatModifier.new(id, Stat.Op.MULT, realm.power, SOURCE))


static func highest_realm(actor: Actor) -> RealmDef:
	var ladder := RealmDefaults.ladder()
	var best := -1
	for state in actor.paths.values():
		best = maxi(best, ladder.index_of(state.rank_id))
	if best < 0:
		return null
	return ladder.realms()[best]
