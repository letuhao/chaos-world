class_name CombatRecoil
extends RefCounted

## S10 and S11: what a landed blow gives BACK (ADR 0067, ADR 0068).
##
## Split out of `CombatSpine` only because it is a coherent unit — the two stages that
## read the HP write rather than compute into it — and because eleven stages of prose in
## one file had reached the line budget. The ORDER is still S9 -> S10 -> S11 and it is
## still asserted in one place: `CombatSpine._spend` calls [method reflect] and then
## [method leech], so the ordering is readable at the call site rather than spread over
## two files.
##
## ## Both are SEPARATE PACKETS, never modifications of the incoming hit
##
## That is the property the split exists to protect. A reflect folded into the amount
## would make S10 an input to S9, and a leech folded into the amount would make S11 an
## input to S9 — and in both cases "the health write happens once, then the give-back is
## paid" would stop being true. Everything here reads `health_delta` and writes
## afterwards.
##
## ## Termination is a DROP, never a clamp
##
## A bounce is re-reflected by the other side if it reflects, so a chain can be longer
## than one — which is the precondition ADR 0068's `CHAIN_DEPTH_LIMIT = 6` assumes. It
## terminates by refusing the bounce AT the limit and recording that it did, so a reader
## can tell a truncated chain from a resisted one. Clamping to zero would make the two
## indistinguishable, and would be exactly the silent rounding ADR 0067 forbids.


## S10. Post-shield reflect, read from what the shield FAILED to absorb: a fully absorbed
## hit reflects nothing (ADR 0068). Rate x share, and nothing else — the bounce carries
## no element payload, so it is not re-mitigated by a mechanism and cannot crit.
##
## `chain_depth` is the caller's, not the actor's: the bounce is the one thing in the
## spine that can recur, so the depth is a parameter and not a field some actor carries
## between fights.
static func reflect(
	attacker: Actor, target: Actor, tuning: CombatTuning, outcome: CombatOutcome, chain_depth: int
) -> void:
	if outcome.overflow <= 0.0:
		return
	var bounced := bounce(target, attacker, outcome.overflow, tuning)
	if bounced <= 0.0:
		return
	if chain_depth >= tuning.chain_depth_limit:
		# DROPPED, not clamped: the outcome says the chain ended, so the truncation is
		# visible to a reader instead of being rounded away.
		outcome.chain_dropped = true
		return
	outcome.reflected = bounced
	# The bounce is PAID, not merely recorded. `CombatOutcome.reflected` documents "what
	# the defender's reflect bounced back", and a number a readout shows a player while no
	# pool is charged is a tax with no effect — the attacker took the full `overflow` and
	# the defender paid nothing for the thorns. Written here rather than in `_respect`,
	# which is the RETURN leg: S10's own packet lands on the attacker, and the return leg
	# lands back on the target, so the two never fold into one another.
	var pool := attacker.resource(&"health") as ResourcePool
	if pool != null:
		pool.change(-bounced)
	_respect(attacker, target, tuning, bounced, chain_depth + 1)


## One side of a bounce: `rate x share x amount`. Every term is non-negative and the
## share is clamped into `[0, 1]`, so no state a caller can corrupt turns a thorn into a
## divide-by-zero, an infinite bounce or a negative heal.
##
## ## The share carries its own answer, like S6's crit multiplier
##
## `REFLECT_DAMAGE` is the bounce's size and `REFLECT_RESIST_DAMAGE` is the share
## of it the resister turns aside: `damage * (1 - resist)` floored at `0.0`, the
## same subtraction shape `CombatSpine._crit_damage` reads. An unauthored
## resister answers `0.0`, so every existing bounce is byte-identical until
## content authors the half.
static func bounce(reflector: Actor, resister: Actor, amount: float, tuning: CombatTuning) -> float:
	var rate := CombatBand.rate(
		_stat(reflector, CombatStats.REFLECT_RATE),
		_stat(resister, CombatStats.REFLECT_RESIST_RATE),
		tuning
	)
	if rate <= 0.0 or amount <= 0.0:
		return 0.0
	var magnitude := clampf(_stat(reflector, CombatStats.REFLECT_DAMAGE), 0.0, 1.0)
	var resist := maxf(0.0, _stat(resister, CombatStats.REFLECT_RESIST_DAMAGE))
	return rate * magnitude * maxf(0.0, 1.0 - resist) * amount


## The other side of a bounce: a landed bounce IS a landed hit, so a defender who
## reflects can themselves be reflected from.
##
## This is a hole I closed and it is worth stating. Refusing any bounce that lands would
## make thorns permanently one-sided — a defender who reflects 30% would take nothing from
## an attacker who reflects 30%, which is not a trade, it is a tax — and then
## `CHAIN_DEPTH_LIMIT` would govern a chain that could never be longer than one hop. So
## the bounce is spent and may be returned, and the DEPTH is the only thing that
## terminates it: `_respect` refuses at the limit and takes `chain_depth + 1` from its
## caller, so no cycle is reachable at any depth.
static func _respect(
	attacker: Actor, target: Actor, tuning: CombatTuning, bounced: float, chain_depth: int
) -> void:
	if chain_depth >= tuning.chain_depth_limit:
		return
	var bounced_back := bounce(attacker, target, bounced, tuning)
	if bounced_back <= 0.0:
		return
	var health := target.resource(&"health") as ResourcePool
	if health != null:
		health.change(-bounced_back)


## S11. Leech, paid after the HP write, as a share of what was ACTUALLY spent on the
## target's health — read from the pool's own movement rather than from `overflow`.
##
## The distinction is the whole point: a hit a shield fully absorbed heals nothing, and a
## hit against a 1-HP target heals 1.0 rather than the 40.0 the blow was worth. That is
## what makes "leech pays for damage dealt" true rather than "leech pays for damage
## rolled".
static func leech(attacker: Actor, tuning: CombatTuning, outcome: CombatOutcome) -> void:
	var share := CombatBand.rate(_stat(attacker, CombatStats.LIFESTEAL), 0.0, tuning)
	if share <= 0.0:
		return
	var pool := attacker.resource(tuning.lifesteal_pool) as ResourcePool
	if pool == null:
		return
	var healed := maxf(0.0, -outcome.health_delta) * share
	if healed <= 0.0:
		return
	pool.change(healed)
	outcome.lifesteal = healed


# Total, for the same reason `CombatSpine._stat` is: a null actor or a null stat table
# reads 0.0 rather than crashing a packet that is already halfway through a hit.


static func _stat(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)
