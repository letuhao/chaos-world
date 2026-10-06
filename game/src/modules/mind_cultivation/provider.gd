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
	# `perception` is this module's OWN base attribute, and `MindStats` is the only
	# place its id is declared — but **nothing in `game/data` ever allocates it.** No
	# `RaceDef.base_attributes` names it (all five races grant only core's seven), so
	# on any actor the game can build it reads `0.0`. It is reachable only through an
	# authored `StatModifier` (`cult_perception`), and the only `.tres` that carry one
	# are passives a player must equip.
	#
	# So `MENTAL_ATTACK` read exactly `0.0 * factor == 0.0`, `base` was `0.0`,
	# `erosion` was `0.0`, and ADR 0171's whole mind mechanism proposed nothing on a
	# stock actor — the identical bug class qi had, one module over. `MENTAL_DEFENSE`
	# was half-alive: it has a `will` term, and every race grants `will`.
	#
	# `Stat.WILL` is core's own resolve, and ADR 0183 made this fallback the baseline
	# for the mind path's attribute reads; ADR 0900 then retired the second attribute
	# (`mental_clarity`) and split the roles: perception carries the OFFENCE reads,
	# will the DEFENCE ones, and a stock body reads `perception == will`. An authored
	# `cult_perception` still works exactly as before — it is a FLAT added on top of
	# this baseline, which is the ADR 0022 shape, not a replacement.
	#
	# The coefficient SUMS are unchanged: a stock body still reads
	# `MENTAL_ATTACK == will * 3.5` and `MENTAL_DEFENSE == will * 2.5`.
	# `test_mind_provider.gd`'s pinned fixtures set the attributes explicitly and were
	# re-keyed with ADR 0900; the stock read is bit-for-bit unchanged.
	var perception := _or_core_fall(context, MindStats.PERCEPTION, Stat.WILL)
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
		# ADR 0900: mental_clarity retired; the OFFENCE reads are perception's and the
		# DEFENCE reads are will's. A stock body reads perception == will (ADR 0183's
		# fallback), so every number here is unchanged from the pre-retirement read.
		MindStats.MENTAL_ATTACK: perception * 3.5 * technique_factor,
		MindStats.MENTAL_DEFENSE: will * 2.5 * technique_factor * (1.0 + meridian_power),
		MindStats.SPIRITUAL_SENSE_RANGE: 50.0 + perception * 5.0 + technique_factor * 10.0,
		# ADR 0071 / BL-0114, then ADR 0215. `MIND_FOCUS_CHANCE` and `MIND_AVOIDANCE`
		# were ADR 0071's RENAMED `critical_chance` / `dodge_chance`, and ADR 0215 renamed
		# them AGAIN to `MIND_CLARITY` / `MIND_VEIL` so the contest has a name for both
		# halves: `mind_clarity` attacks and `mind_veil` hides. Neither is core's
		# `Stat.CRIT_CHANCE` or `Stat.EVASION` and neither may ever gate a non-mind hit --
		# folding them into core would have made every mind stat boost every qi and body
		# hit, which is why ADR 0071 ruled RENAME rather than fold, and why ADR 0215 kept
		# that ruling instead of folding them into core's crit pair.
		#
		# ## ADR 0215 deleted the `minf` on all THREE of these, and that is the
		# ## load-bearing half of the rename
		# `minf(0.75, …)`, `minf(0.6, …)` and `minf(0.8, …)` were every one of them
		# rate-shaped by the shape rule, every one of them a half of a CONTEST, and every
		# one of them a cap whose only effect was to stop the defender's half growing. ADR
		# 0200 deliberately KEPT caps on rate axes; ADR 0215 is the decision that that
		# rule was applied to the wrong question for a contest, because a rate contest is
		# `offense / (offense + defense)` and a cap there bounds a HALF of a ratio rather
		# than a rate axis nothing contests. So the caps are deleted rather than retuned:
		# the attribute terms are unchanged, they simply have no ceiling, which is why all
		# three left `Stat.RATE_STATS` and why a FLAT on any of them is legal content
		# rather than +1000%.
		#
		# ## The MIND_CLARITY / MIND_VEIL rows are bit-for-bit unchanged
		# Those two rows read `perception` and `awareness_ratio` and never touched the
		# retired `mental_clarity` (ADR 0900), so a save written against the old ids keeps
		# the same numbers -- which is the testable claim `test_mind_clarity_veil_pair.gd`
		# makes, and it makes it by measuring both halves rather than restating them.
		MindStats.MIND_CLARITY: 0.05 + perception * 0.003 + awareness_ratio * 0.1,
		MindStats.MIND_VEIL: perception * 0.002 + awareness_ratio * 0.05,
		MindStats.ILLUSION_RESISTANCE: will * 0.006,
		MindStats.MIND_TECHNIQUE_POWER:
		perception * 2.5 * technique_factor * (1.0 + meridian_power),
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
