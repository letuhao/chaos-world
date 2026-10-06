class_name CombatDuelHit
extends RefCounted

## One blow, actor to actor, over the SHARE model (ADR 0126).
##
## ## Why this file exists
##
## `CombatExchange` answers only for the boss `loot` already spawned: a player and a live
## encounter. This answers for TWO `Actor`s, which is the shape every caller outside that
## one screen actually has — an npc against a player, a technique against a duellist. It
## resolves the blow through the EXISTING `CombatDamage.resolve_hit` and spends it on the
## defender's own `health` pool, so the arithmetic, the floors and the ceilings are one
## implementation, not two that agree today.
##
## ## It is not on `CombatApi`
##
## `api.gd` is the module's cross-module facade and re-exports verbs that other modules
## and `ui/` need. This is the module's own internal verb, reached by name the way
## `CombatExchange` is; `CombatApi.hit` is the one-line delegate that makes it reachable
## from outside.
##
## ## It needs no node, no body and no frame
##
## Everything below is `RefCounted` state. Nothing here ticks, and nothing here needs a
## `SceneTree`, which is what makes the whole thing assertable from the headless runner —
## `run_tests.gd` quits before the first frame, so a scene-tree-dependent seam could only
## ever be asserted by hand.
##
## ## Every refusal is NAMED, never thrown
##
## `no_attacker`, `no_defender`, `same_actor`, `defender_slain`, `defender_spared`,
## `no_health_pool`. A caller that passes a null is a caller in the middle of wiring, and
## a crash there surfaces far from the call that caused it. A dead defender is an ordinary
## outcome of a fight, not an error at all, so it is refused rather than charged to a
## corpse — and a SPARED defender is refused for the same reason, one step earlier: the
## duel is already over with them and this blow would undo a decision somebody else made.

## The health pool this module spends. Core already owns and already serializes it.
const HEALTH_POOL := &"health"


## One blow from `attacker` against `defender`, SPENT on the defender's health.
##
## Returns primitives only, so a screen renders it unchanged:
## `{ok, reason, share, taken, crit, evaded, power, mitigation, defender_slain}`.
##
## `taken` is `share * health_maximum`, spent through `ResourcePool.change` — never by
## assigning `pool.current`, which would skip the `changed` signal every stat cache
## listens to. `share` comes from [method CombatDamage.resolve_hit] unchanged: a share of
## the defender's OWN pool, never a magnitude, which is the whole reason the model is
## safe against a 551x realm table.
##
## `rng` may be null, in which case the roll is `randf()` and the blow is NOT
## reproducible. Callers that need a repeatable outcome pass a seeded one — `CombatApi
## .hit` does.
static func resolve(
	attacker: Actor, defender: Actor, rng: RandomNumberGenerator = null
) -> Dictionary:
	if attacker == null:
		return _refusal("no_attacker")
	if defender == null:
		return _refusal("no_defender")
	if attacker == defender:
		# An actor spending its OWN pool would make a self-inflicted blow read as a
		# wound inflicted by somebody, and `same_actor` is the only honest answer.
		return _refusal("same_actor")
	var pool := defender.resource(HEALTH_POOL) as ResourcePool
	if pool == null:
		return _refusal("no_health_pool")
	if pool.current <= 0.0:
		# Refused BEFORE the roll: a corpse spends nothing, so an evaded blow and a
		# blow on a body already down are not distinguishable by their arithmetic.
		return _refusal("defender_slain")
	if CombatDuel.spared(CombatDuel.normalize(defender.get_module_data(CombatDuel.MODULE_KEY))):
		# Also refused BEFORE the roll, and for the same reason. A spared opponent is
		# somebody the duel is already OVER with: `CombatApi.spare` ended it without a
		# killing blow, and spending a share of their health afterwards would make the
		# mercy a note somebody else could undo with the next swing.
		return _refusal("defender_spared")
	var blow := CombatDamage.resolve_hit(_offense(attacker), _guard(defender), rng)
	var share := float(blow.get("share", 0.0))
	var taken := share * pool.maximum
	pool.change(-taken)
	var health := alive(defender)
	var slain := not bool(health["ok"])
	if slain:
		_record_win(attacker, defender)
	return {
		"ok": true,
		"reason": "",
		"share": share,
		"taken": taken,
		"crit": bool(blow.get("crit", false)),
		"evaded": bool(blow.get("evaded", false)),
		"power": float(blow.get("power", 0.0)),
		"mitigation": float(blow.get("mitigation", 0.0)),
		"defender_slain": slain,
	}


## Whether `actor` is still standing, as `{ok, reason, health, health_max, health_ratio}`.
##
## `ok` is the one bit a caller branches on: `false` means a dead actor, which is a state
## and not an error. `reason` names which of the two refusals it was — `no_actor` for no
## actor at all, `no_health_pool` for one nobody attached resources to, and `defender_slain`
## for a pool that is genuinely empty. `attach_core_resources` is NOT called here: a read
## must not create the thing it is reporting on, and `_health` above reads a pool that
## exists rather than inventing one, so a fight against an un-attached actor is refused by
## name instead of silently zeroed.
static func alive(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false,
			"reason": "no_actor",
			"health": 0.0,
			"health_max": 0.0,
			"health_ratio": 0.0,
		}
	var pool := actor.resource(HEALTH_POOL) as ResourcePool
	if pool == null:
		return {
			"ok": false,
			"reason": "no_health_pool",
			"health": 0.0,
			"health_max": 0.0,
			"health_ratio": 0.0,
		}
	return {
		"ok": pool.current > 0.0,
		"reason": "" if pool.current > 0.0 else "defender_slain",
		"health": pool.current,
		"health_max": pool.maximum,
		"health_ratio": pool.ratio(),
	}


## What the same blow WOULD be worth, spending nothing.
##
## The read-only twin of [method resolve], for a panel that has to quote a number a swing
## would produce before the swing happens. It refuses exactly what `resolve` refuses and
## returns the same key set, so a caller can render either without branching on which one
## it holds. `rng` may be null, in which case the quote is a roll — an exact, repeatable
## quote needs a seeded one.
static func report(
	attacker: Actor, defender: Actor, rng: RandomNumberGenerator = null
) -> Dictionary:
	if attacker == null:
		return _refusal("no_attacker")
	if defender == null:
		return _refusal("no_defender")
	if attacker == defender:
		return _refusal("same_actor")
	var pool := defender.resource(HEALTH_POOL) as ResourcePool
	if pool == null:
		return _refusal("no_health_pool")
	if pool.current <= 0.0:
		return _refusal("defender_slain")
	var blow := CombatDamage.resolve_hit(_offense(attacker), _guard(defender), rng)
	return {
		"ok": true,
		"reason": "",
		"share": float(blow.get("share", 0.0)),
		# What the blow WOULD spend. Reported, never spent: this method touches no pool.
		"taken": float(blow.get("share", 0.0)) * pool.maximum,
		"crit": bool(blow.get("crit", false)),
		"evaded": bool(blow.get("evaded", false)),
		"power": float(blow.get("power", 0.0)),
		"mitigation": float(blow.get("mitigation", 0.0)),
		"defender_slain": false,
	}


## The attacker's numbers, as the bundle `CombatDamage.resolve_hit` reads. Physical
## **plus** spiritual attack: a body cultivator and a qi cultivator both fight, and
## `RealmScaling` scales both ids by the same authored realm power. Same builder
## `CombatExchange.offense` uses, so a blow against a boss and a blow against an actor are
## priced by one function.
static func _offense(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return {
		"attack":
		actor.stats.derived(Stat.ATTACK_PHYSICAL) + actor.stats.derived(Stat.ATTACK_SPIRITUAL),
		"crit_chance": actor.stats.derived(Stat.CRIT_CHANCE),
		# ADR 0877: the STAT is now the crit BONUS magnitude. This model's profiles were
		# tuned on a `1.5 +` crit multiplier, so this boundary PRESERVES that reference
		# (`1.5 + bonus`, byte-identical to the old `1.5 + comprehension * 0.004`) until
		# the exchange converts to the flat pair, which is its own lane's change.
		"crit_damage": 1.5 + actor.stats.derived(Stat.CRIT_DAMAGE),
		"penetration": actor.stats.derived(Stat.PENETRATION),
	}


## The defender's numbers, as the bundle `CombatDamage.resolve_hit` reads. `evasion` is
## the defender's, and `damage_reduction` is already a flat 0..1 fraction (ADR 0022), so
## it is read as one.
static func _guard(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return {
		"defense":
		actor.stats.derived(Stat.DEFENSE_PHYSICAL) + actor.stats.derived(Stat.DEFENSE_SPIRITUAL),
		"damage_reduction": actor.stats.derived(Stat.DAMAGE_REDUCTION),
		"evasion": actor.stats.derived(Stat.EVASION),
	}


## One refusal, in the shape both public verbs return: `ok: false`, every number zero,
## and no claim that the defender died. `defender_slain` is `false` rather than absent
## because a refusal that spent nothing did not kill anybody.
static func _refusal(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"share": 0.0,
		"taken": 0.0,
		"crit": false,
		"evaded": false,
		"power": 0.0,
		"mitigation": 0.0,
		"defender_slain": false,
	}


## Count the duel this blow ended, on the attacker's own record, and tell the world.
##
## ## Recorded on the WINNER, and only on a killing blow
##
## `defender_slain` is the one bit that means the duel is over and somebody lost it, so
## this is the only place `duels_won` is written. A spared opponent (`CombatApi.spare`)
## deliberately does NOT come through here: the fight ended without a killing blow, the
## loser is on their feet, and calling that a duel won would make the counter mean "a
## fight ended" instead of "a fight was won".
##
## ## Once per slaying blow, never per blow
##
## `resolve` is the module's only blow verb and it is called once per swing, so a
## survivor's tenth exchange records nothing. The ledger is monotone, so a per-swing
## write would be a number that grows with how hard somebody fought rather than with
## what they achieved.
static func _record_win(attacker: Actor, defender: Actor) -> void:
	var duel := CombatDuel.normalize(attacker.get_module_data(CombatDuel.MODULE_KEY))
	(
		CombatDuel
		. record_win(
			duel,
			{
				"outcome": "duel_won",
				"opponent_id": String(defender.id),
				"wins": int(duel.get("wins", 0)) + 1,
			},
			# THE ACTOR. Without it `record_win`'s `actor: Actor = null` default takes
			# the branch that SKIPS the earn entirely, so a duel closed with a killing
			# blow recorded the win and paid nothing: the `wins` counter moved, the duel
			# history read `duel_won`, and `first_blood_duel` was never granted. That is
			# the whole UNWIRED class — the site exists, verifies nothing, and no player
			# can reach it — and it survived because the signature made the actor
			# OPTIONAL, so the call site compiled and read as correct.
			#
			# `record_defeat`'s caller passes it (and DEF-0105's earn was verified there),
			# so this was the only one of the two that did not. The lesson is the
			# signature's: an earn site whose participant is a defaulted parameter is a
			# site that can be wired to nothing and still typecheck.
			attacker
		)
	)
	attacker.set_module_data(CombatDuel.MODULE_KEY, duel)
	# LAST, once the record it describes is on the ledger (ADR 0137).
	CombatFacts.record_duel_won(attacker)
