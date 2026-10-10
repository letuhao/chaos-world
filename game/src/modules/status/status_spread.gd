class_name StatusSpread
extends RefCounted

## ADR 0902 (P9, BL-0925): contagion — one instance re-applies its def to CANDIDATE
## hosts, each hop a full resolve through the module's own apply door.
##
## ## The hop cap is a CONSTANT, not a tuning key
##
## `MAX_HOP_DEPTH` is the loop-safety bound the backlog entry demanded "from day one": a
## contagion that could hop A -> B -> A is an unbounded cascade wearing content's name,
## and a tunable cap is a cap a balance pass can raise until it is one. A def may author a
## SMALLER `max_hops`; the constant is the ceiling nothing exceeds.
##
## ## The candidates are the CALLER's
##
## The module owns no board (BL-0925's own gate: "multi-host encounters"), so `hop`
## receives the candidate list from the caller that owns a multi-host view. The source
## host is skipped by construction — a contagion never re-infects the body it came from.

const MAX_HOP_DEPTH := 4
const KEY_SPREAD := &"spread"
const KEY_HOP := &"spread_hop"


## The hop depth this instance was born at (`0` for one applied directly).
static func hop_of(effect: StatusEffect) -> int:
	if effect == null:
		return 0
	return maxi(0, int(effect.payload.get(KEY_HOP, 0)))


## The def's authored spread config — `{chance, max_hops, icd}` — or `{}`.
static func config_of(def: StatusDef) -> Dictionary:
	if def == null:
		return {}
	var raw: Variant = def.payload.get(KEY_SPREAD, {})
	return raw as Dictionary if raw is Dictionary else {}


## The authored hop ceiling for `def`, never above [constant MAX_HOP_DEPTH].
static func max_hops_of(def: StatusDef) -> int:
	var config := config_of(def)
	return clampi(int(config.get("max_hops", MAX_HOP_DEPTH)), 0, MAX_HOP_DEPTH)


## One hop: roll once per candidate, apply the SOURCE's def to each that passes, carrying
## `hop_depth + 1` onto the new instance. Returns one primitives-only row per candidate
## that was rolled and passed; candidates the roll skips are not rows. Bounded `for` over
## the CALLER's array, and the depth gate refuses before any roll.
static func hop(
	actor: Actor, def: StatusDef, candidates: Array, chance: float, rng: Variant, hop_depth: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null or def == null or rng == null:
		return out
	if hop_depth > MAX_HOP_DEPTH or hop_depth >= max_hops_of(def):
		return out
	var capped := clampf(chance, 0.0, 1.0)
	if capped <= 0.0:
		return out
	for candidate in candidates:
		if candidate == null or candidate == actor:
			continue
		if rng.randf() >= capped:
			continue
		out.append(_infect(actor, candidate, def, hop_depth + 1))
	return out


## Apply `def` to `candidate` and stamp the new instance's hop depth. The door follows
## the def's scope, exactly as every other caller picks.
static func _infect(source: Actor, candidate: Actor, def: StatusDef, hop_depth: int) -> Dictionary:
	var answer: Dictionary = {}
	if def.is_combat_scope():
		answer = StatusApi.apply(candidate, def.id, 1.0)
	else:
		answer = StatusApi.apply_cultivation(candidate, def.id, 1.0)
	if not bool(answer.get("ok", false)):
		return {
			"host": String(candidate.id),
			"id": String(def.id),
			"applied": false,
			"hop": hop_depth,
		}
	var live := StatusEngine.effect_by_instance(candidate, int(answer.get("instance_id", 0)))
	if live != null:
		# Module scratch on the contract's own payload: the hop depth travels WITH the
		# instance, so the next hop's cap reads it wherever the instance lands.
		live.payload[KEY_HOP] = hop_depth
	return {
		"host": String(candidate.id),
		"id": String(def.id),
		"applied": true,
		"hop": hop_depth,
		"source": String(source.id),
	}
