class_name MindProvider
extends StatProvider

## Contributes the module's actor-scoped derived stats from base attributes,
## resources, and the mind cultivation path rank (ADR 0013/0016).
##
## Every realm-shaped read here is ONE bounded per-realm number,
## `RealmRate.factor`, applied to every contribution. It is a RATE: how
## much a unit of this realm's cultivation counts, never how strong a thing from
## this realm is. The path's real magnitudes live where they belong —
## `MindRealmSeed.sea_capacity` for the reservoir (100 -> 825), applied once by
## `MindTraining.synchronize`, and `RealmScaling` (core) for the shared combat
## stats — so this provider must not also scale by the realm's strength, or it
## would count the same realm twice and collide with `SeaProvider`, which owns
## `MindStats.SEA_CAPACITY`. The body and qi providers read the same number for
## the same realm.
##
## `tests/modules/mind_cultivation/test_mind_power_curve.gd` pins the factor, its
## bound, and the no-double-count rule. `test_mind_stat_surface.gd` pins the
## emitted id set and fails if either discarded local (`spirit`, `mind_power_ratio`)
## or the deleted `comprehension_bonus` comes back.


func contribute(context: StatContext) -> Dictionary:
	# ## The FALLBACK, and why mind was as dead as qi on a real actor
	#
	# `perception` and `mental_clarity` are this module's OWN base attributes, and
	# `MindStats` is the only place their ids are declared — but **nothing in
	# `game/data` ever allocates them.** No `RaceDef.base_attributes` names either
	# (all five races grant only core's seven), so on any actor the game can build
	# both read `0.0`. They are reachable only through an authored `StatModifier`
	# (`cult_perception` / `cult_mental_clarity`), and the only `.tres` that carry
	# one are passives a player must equip.
	#
	# So `MENTAL_ATTACK` read exactly `(0 + 0) * factor == 0.0`, `base` was `0.0`,
	# `erosion` was `0.0`, and ADR 0171's whole mind mechanism proposed nothing on a
	# stock actor — the identical bug class qi had, one module over. `MENTAL_DEFENSE`
	# was half-alive: it has a `will` term, and every race grants `will`.
	#
	# `Stat.WILL` is core's own resolve, and it is ALREADY the defensive term on the
	# line below, so this makes the mind path's two base attributes resolve to the
	# one attribute every body in this game actually has, instead of leaving the
	# authored attributes as unreachable ids that only an equipped passive can move.
	# An authored `cult_perception` still works exactly as before — it is a FLAT
	# added on top of this baseline, which is the ADR 0022 shape, not a replacement.
	#
	# The coefficients are the module's OWN and unchanged: `MENTAL_ATTACK` is still
	# `perception * 2.0 + mental_clarity * 1.5`, and a stock body is read as
	# `perception == clarity == will`. `test_mind_provider.gd`'s pinned fixtures set
	# these attributes explicitly and are therefore bit-for-bit unchanged, which is
	# what keeps this a fallback rather than a rebalance. ADR 0183.
	var perception := _or_core_fall(context, MindStats.PERCEPTION, Stat.WILL)
	var mental_clarity := _or_core_fall(context, MindStats.MENTAL_CLARITY, Stat.WILL)
	var will := context.value(Stat.WILL)

	## `mind_power_ratio` was computed here and thrown away, as was a `spirit`
	## local that fed nothing (BL-0154/BL-0155). Both are gone rather than wired,
	## and that is a decision rather than an oversight: ADR 0071 deliberately makes
	## the sea's LEVEL the DENOMINATOR of an incoming mind strike
	## (`g /= defender_sea.structural_capacity`) instead of a stat multiplier, and
	## names its defensive identity as "four levers, none of which is raise a
	## resistance stat". A derived stat scaling with how full the sea is would be the
	## fifth lever that ADR ruled out. What the fill actually gates is
	## `seed.sea_fill_required`, authored 1.0 at every realm, which is why
	## `test_mind_stat_surface.gd` asserts the fill REFUSES a breakthrough and that
	## cultivating it is what stops it refusing. The stat expression the sea level is
	## owed belongs to ADR 0071's `MindDamage`, which does not exist yet.
	var awareness_ratio := _pool_ratio(context, MindStats.AWARENESS)
	var technique_factor := _realm_factor(context)
	var meridian_power := _meridian_power_bonus(context)

	return {
		MindStats.MENTAL_ATTACK: (perception * 2.0 + mental_clarity * 1.5) * technique_factor,
		MindStats.MENTAL_DEFENSE:
		(mental_clarity * 2.0 + will * 0.5) * technique_factor * (1.0 + meridian_power),
		MindStats.SPIRITUAL_SENSE_RANGE: 50.0 + perception * 5.0 + technique_factor * 10.0,
		# ADR 0071 / BL-0114: `MIND_FOCUS_CHANCE` and `MIND_AVOIDANCE` are the RENAMED
		# `critical_chance` / `dodge_chance`. Neither is core's `Stat.CRIT_CHANCE` or
		# `Stat.EVASION` and neither may ever gate a non-mind hit -- folding them into core
		# would have made every mind stat boost every qi and body hit, which is why ADR
		# 0071 ruled RENAME rather than fold. Their ONLY consumer is ADR 0071's
		# `MindDamage`, which reads the first to spend `FOCUS_MULT` on the TURBULENCE term
		# alone and the second to remove `COHERENCE_DAMP` of the coherence term. That
		# mechanism is not written: the formulas below are unchanged by the rename, and
		# `combat_tuning.gd` already carries its nine tuning numbers defaulted to 0.0.
		# The formulas are UNCHANGED by the rename -- same perception and awareness terms,
		# same caps -- so this is a save-affecting rename and nothing else.
		MindStats.MIND_FOCUS_CHANCE: minf(0.75, 0.05 + perception * 0.003 + awareness_ratio * 0.1),
		MindStats.MIND_AVOIDANCE: minf(0.6, perception * 0.002 + awareness_ratio * 0.05),
		MindStats.ILLUSION_RESISTANCE: minf(0.8, mental_clarity * 0.004 + will * 0.002),
		MindStats.MIND_TECHNIQUE_POWER:
		(perception * 1.5 + mental_clarity * 1.0) * technique_factor * (1.0 + meridian_power),
	}


## `own` when the body carries it, else `core` — the fallback that keeps mind's
## offence alive on a stock actor. See the docblock at the top of [method contribute].
##
## A NEGATIVE `own` reads as the fallback too, not as a negative attribute: the
## baseline is a body-plan term, so a body with no mind faculty reads the resolve
## rather than subtracting from it. This is the same "degrade, never throw" shape
## every other read in this repository uses.
func _or_core_fall(context: StatContext, own: StringName, core: StringName) -> float:
	var authored := context.value(own)
	return authored if authored > 0.0 else maxf(0.0, context.value(core))


## The network's power bonus, through the one accessor ADR 0057 added for it.
##
## The network is core state on the Actor and reaches a provider as
## `StatContext.meridian_network()`, never as `component(&"meridians")` — that
## lookup is a different key in the module component bag and answers null for
## every actor the game builds. Read that way, a trained network was worth
## exactly 0.0 on this path, with no error and nothing to point at.
##
## The two absent cases are separated on purpose. `MeridianNetwork.get_power_bonus`
## answering 0.0 means channels exist and nobody strengthened one; falling off
## the end means this context was built for something that carries no network at
## all, and only this caller can tell those apart.
func _meridian_power_bonus(context: StatContext) -> float:
	var network := context.meridian_network()
	if network is MeridianNetwork:
		return network.get_power_bonus()
	return 0.0


## The realm factor, or neutral when the path is unstarted. R1 is the neutral
## realm because it is the first ordinal, so its factor is `RATE_STEP^0`.
func _realm_factor(context: StatContext) -> float:
	var state := context.path(MindPath.PATH_ID)
	if state == null:
		return RealmRate.NEUTRAL
	return RealmRate.factor(state.rank_id)


func _pool_ratio(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)
