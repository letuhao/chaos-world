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

## ## ADR 0200: every RESISTANCE-LIKE magnitude moved onto this list
##
## This list used to be seven ids: the four attack/defense halves plus hp, qi and stamina.
## That is exactly the asymmetry that made mitigation collapse: the attacker's elemental
## power rode a 551x ladder while the defender's elemental mitigation stayed where it was
## authored, so by R3 the defense term was noise and the only thing a designer could read
## as "the mitigation number" was a CAP.
##
## ## `STATUS_DEFENSE`, and why the old `STATUS_RESISTANCE` cap had to die with it
##
## `status_resistance` was `minf(0.8, will * 0.003)` — a percent whose ceiling needed
## `will >= 250` against an authored `base_will` topping out at 54.9 (DEF-0262), so it was
## a dead stat at every realm a player could reach. It is now `status_defense`, an
## unbounded MAGNITUDE feeding ADR 0200's ratio, and it is here on the ladder because a
## magnitude is exactly what the ladder SHOULD scale. `mind_cultivation` and
## `status/mind_*` are other live sessions' files, so `StatusApply` keeps reading the id it
## has always read through `CombatTuning`'s prefix rather than a renamed const landing here
## under them; the id STRING is what changed, and the const name records the new shape.
##
## ## `element_power_<e>` and `element_defense_<e>` are NOT here, and cannot be
##
## The per-element ids are built from the element id at read time, so a static list cannot
## hold them. `elements/api.gd:apply_realm_modifiers` writes BOTH halves' realm `MULT`
## themselves, in the same shape and under this same `SOURCE`, which is why they also have
## to re-write the halves after every `RealmScaling.apply` (that call clears `SOURCE`
## wholesale). Both are written from ONE `realm.power` for the reason the whole module
## exists: ADR 0200's mitigation ratio is `D / (K + D)` with `K` on the attacker's
## `element_power_<e>` and `D` on the defender's `element_defense_<e>`, and with only the
## offense half on the ladder the fraction of a qi hit that is elemental DRIFTED with the
## realm — measured `0.665043 -> 0.705803` over the shipped ladder by
## `tests/modules/combat_engine/test_cross_mechanism_balance.gd`, whose own printed verdict
## was `NOT CONSTANT -- FINDING`. `tests/modules/elements/test_element_stat_publication.gd::
## test_both_element_halves_take_the_realm_multiplier` pins the pair.
##
## ## What is deliberately NOT here
##
## Every RATE: `ATTACK_SPEED`, `COOLDOWN_REDUCTION`, `QI_COST_REDUCTION`, `EVASION`,
## `CRIT_CHANCE`. ADR 0200's own test is the distinction — "a cap on a mitigation or defense
## axis dies because that axis must scale with the ladder; a cap on a rate axis stays,
## because rate is not what power creep rides" — and AGENTS.md's realm-scale section is
## sharper still: a rate must NEVER track a magnitude (ADR 0050). `MOVE_SPEED` is a
## magnitude but is left out because nothing on the combat path reads it and scaling it is
## a movement decision, not a combat one.
const SCALED_STATS := [
	Stat.MAX_HEALTH,
	Stat.MAX_QI,
	Stat.MAX_STAMINA,
	Stat.ATTACK_PHYSICAL,
	Stat.ATTACK_SPIRITUAL,
	Stat.DEFENSE_PHYSICAL,
	Stat.DEFENSE_SPIRITUAL,
	Stat.STATUS_DEFENSE,
]


static func apply(actor: Actor) -> void:
	actor.stats.remove_modifiers_from(SOURCE)
	var realm := highest_realm(actor)
	if realm == null:
		# ADR 0882: the aptitude ladder follows the same answer as the modifiers —
		# no path, no realm, the neutral.
		actor.stats.set_aptitude_ladder(1.0)
		return
	var power := realm.power
	# ADR 0882: the ONE push of the aptitude ladder, and this function already runs at
	# breakthrough (`core/breakthrough.gd`), which is one of the two stages the aptitude
	# layer re-resolves at. A MAGNITUDE edge reads this; a CONTEST edge never does.
	actor.stats.set_aptitude_ladder(power)
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
