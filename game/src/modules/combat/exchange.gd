class_name CombatExchange
extends RefCounted

## One encounter exchange: the player's blow, and the boss's answer (ADR 0076).
##
## ## Why this is not on `CombatApi`
##
## `api.gd` is the module's facade for a *blow*. This is the verb for a whole *fight
## turn*, and it needs the live boss — which `loot` owns. Keeping it in its own script
## means it depends on `LootApi` and `CombatDamage` and nothing else in this module, so it
## is not coupled to whatever the facade happens to re-export. A caller reaches it by
## name; `combat` is declared in `rules.UI_MODULES`, so `ui/` may.
##
## ## The division of labour
##
## `loot` owns the encounter: whose vitality is spent, the once-only reward, the run
## lifecycle. This owns the resolution: how much a blow is worth and what the boss answers
## with. So `combat` depends on `loot` through its facade, and `loot` knows nothing of
## `combat` — the edge runs one way and `tools arch` enforces it.
##
## ## Every exchange is a share, never a magnitude
##
## Damage is a fraction of the target's own pool, which is what makes the model safe
## against a 551x realm table meeting 12x authored vitality: both pools are spent by the
## same fraction, so a realm lifts both sides together. See `CombatDamage` and
## `core/realm_power_table.tres` for the table this deliberately does not extend.

## The player spent the boss's remaining vitality.
const OUTCOME_BOSS_DEFEATED := "boss_defeated"
## The boss outlasted the player and the run is over.
const OUTCOME_PLAYER_LOST := "player_lost"

## ADR 0105's substitute for ADR 0087's per-technique `status_chance`.
##
## ## Why this is a CONSTANT here and not an authored number
##
## ADR 0087's gate is authored ON A TECHNIQUE, and ADR 0105 refuses a `TechniqueDef`
## field for it (the element is the carrier, and `techniques` is at its 12-method cap).
## That refusal removes the only place the number could be authored without adding a
## balance surface ADR 0105 did not decide — so the base chance lives here, as one
## named, documented value in the module that spends it. It is NOT a second magnitude
## vocabulary: ADR 0087's resist formula and ADR 0088's `element_power_<e>` potency are
## both still the only arithmetic, read from `StatusApply` unchanged.
##
## At `1.0` the gate is saturated, so the resist terms decide the roll on their own and
## this constant moves nothing yet — which is deliberate. It is the ONE dial a balance pass
## turns, and turning it cannot require editing ten `.tres` or a technique catalogue.
## Should a future ADR give the gate a home in content, this constant is the single line
## to delete, because every read of it is here.
const STATUS_CHANCE := 1.0


## Run one exchange against the live boss.
##
## The player's damage is resolved from their own numbers, never from a caller's constant,
## and spent through `LootApi.strike` — so rule E1 (one reward per encounter) still
## decides what a defeat mints. The boss's answer is spent on the player's `health` pool,
## which core already owns and already serializes.
##
## A player at zero health has **lost the run**: `LootApi.abandon` discards the
## in-progress boss at full vitality and never mints the reward that was still owed, the
## player is carried out at full vitality — a boss fight is a stake on the run, not a wound
## that persists — and [method duel] records the loss so a screen can say so.
##
## Returns primitives only, so `ui/` can render it: `{ok, reason, outcome, boss, player,
## share, crit, evaded, status}`. `outcome` is `boss_defeated`, `player_lost`, or `""`.
##
## `status` is ADR 0105's report of what a landed blow inflicted: `{applied, id, potency}`,
## primitives only, so a screen renders it unchanged. It is `applied: false` for an
## evaded blow, for a refused exchange, and for an element with no authored status — all
## ordinary outcomes, not errors.
static func exchange(actor: Actor, seed_value: int = 0) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "outcome": ""}
	var active := live_boss(actor)
	if active.is_empty():
		# Loot owns the reason a strike is refused, so ask it rather than restating its
		# vocabulary. A zero strike changes nothing: `LootState.strike` refuses an empty
		# run before it looks at the damage.
		var refused := LootApi.strike(actor, 0.0, seed_value)
		refused["outcome"] = ""
		return refused
	# One stream per exchange, so the player's roll and the boss's answer are reproducible
	# from (seed, encounter) — the same two inputs a loot resolve already is.
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value * 2654435761 + absi(hash(String(active["encounter_id"])))) & 0x7FFFFFFF
	var blow := CombatDamage.resolve_hit(offense(actor), _boss_guard(active), rng)
	var struck := LootApi.strike(
		actor, float(blow["share"]) * float(active["vitality_max"]), seed_value
	)
	var after := LootApi.summary(actor).get("active", {}) as Dictionary
	var result := {
		"ok": bool(struck.get("ok", false)),
		"reason": String(struck.get("reason", "")),
		"encounter_id": String(struck.get("encounter_id", "")),
		"outcome": "",
		"share": float(blow["share"]),
		"crit": bool(blow["crit"]),
		"evaded": bool(blow["evaded"]),
		"power": float(blow["power"]),
		"mitigation": float(blow["mitigation"]),
		"status": {"applied": false, "id": "", "potency": 0.0},
		"boss": after,
		"player": player(actor),
	}
	if not bool(result["ok"]):
		return result
	result["status"] = _status_on_landing(actor, active, result, rng)
	if not _still_standing(active, after):
		result["outcome"] = OUTCOME_BOSS_DEFEATED
		return result
	return _answer(actor, active, result, rng)


## The player's own offensive numbers, as the bundle `CombatDamage.resolve_hit` reads.
## Offense is physical **plus** spiritual attack: a body cultivator and a qi cultivator
## both fight, and `RealmScaling` scales both ids by the same authored realm power.
static func offense(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return {
		"attack":
		actor.stats.derived(Stat.ATTACK_PHYSICAL) + actor.stats.derived(Stat.ATTACK_SPIRITUAL),
		"crit_chance": actor.stats.derived(Stat.CRIT_CHANCE),
		"crit_damage": actor.stats.derived(Stat.CRIT_DAMAGE),
		"penetration": actor.stats.derived(Stat.PENETRATION),
	}


## The player's own defensive numbers, as the bundle `CombatDamage.resolve_hit` reads.
## `evasion` is here because it is the defender's: it is what keeps a boss's answer from
## landing. `damage_reduction` is already a flat 0..1 fraction (ADR 0022), so it is read as
## one.
static func guard(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return {
		"defense":
		actor.stats.derived(Stat.DEFENSE_PHYSICAL) + actor.stats.derived(Stat.DEFENSE_SPIRITUAL),
		"damage_reduction": actor.stats.derived(Stat.DAMAGE_REDUCTION),
		"evasion": actor.stats.derived(Stat.EVASION),
	}


## The player's fight state as primitives: their health pool. What a panel needs to say
## "you are hurt" without naming a pool type.
static func player(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var pool := _health(actor)
	return {
		"health": pool.current,
		"health_max": pool.maximum,
		"health_ratio": pool.ratio(),
		"alive": pool.current > 0.0,
	}


## Everything a screen needs to show a fight it has not started: the player's own numbers,
## their health, and the fights they have already lost.
static func preview(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var view := player(actor)
	view["offense"] = offense(actor)
	view["guard"] = guard(actor)
	view["base_share"] = CombatDamage.BASE_SHARE
	view["min_share"] = CombatDamage.MIN_SHARE
	view["power_ceiling"] = CombatDamage.POWER_CEILING
	view["mitigation_ceiling"] = CombatDamage.MITIGATION_CEILING
	view["duel"] = duel(actor)
	return view


## The fights this actor has lost: a count, the last one, and a bounded recent history.
static func duel(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return CombatDuel.view(_duel_state(actor))


## The live boss as `LootApi` reports it, or `{}`. Read through the facade rather than off
## `actor.module_data`, so this module never reaches into another module's state.
static func live_boss(actor: Actor) -> Dictionary:
	var active := LootApi.summary(actor).get("active", {}) as Dictionary
	return active if bool(active.get("in_domain", false)) else {}


# --- Internals ---------------------------------------------------------------

## ADR 0105: what a landed blow inflicts, reported as `{applied, id, potency}`.
##
## ## The GATE, and it is exactly one term
##
## `not evaded`. `CombatDamage.resolve_hit` already returned `evaded` from the SAME
## single draw that decided crit (`damage.gd:66,84`), so this reuses a verdict the
## exchange has in hand rather than spending a second die on a question already answered.
## That is ADR 0087's rule transferred verbatim to ADR 0076's model: a blow the boss
## AVOIDED applies nothing, and `evaded` is the only word that means "avoided" here.
## `CombatOutcome.is_clean()` has no counterpart — `combat` builds no outcome — so the
## `evaded` term IS the clean gate. Everything else downstream (closed chance, no mapped
## status, already-held) is a refusal that costs nothing either.
##
## ## Why the status rides the ATTACKER, and why that is not a workaround
##
## The boss is NOT an `Actor` — it is a `Dictionary` in `actor.module_data`
## (`loot_state.gd:523-547`), with frozen attack/defense/vitality and no stats to resist
## with and no `add_status` to be written on. `StatusApi.apply(actor, …)` therefore cannot
## be pointed at it at all, and inventing a boss `Actor` to hold one debuff would be a
## second combatant the whole encounter model does not have. So the status rides the
## player, which is what ADR 0105 calls for and what makes the player a SUBJECT of a
## status for the first time — a fight whose own blow can slow, burn or root the hand that
## threw it.
##
## ## The roll is a SUBSTREAM, never a draw off the shared generator
##
## `rng` above is already shared with the boss's return stroke (`_answer`), so consuming
## from it here would re-roll the answer for the rest of the exchange — adding a status
## would change the damage the boss deals. Instead the seed is derived whole, through
## `StatusApply.status_seed(rng.seed, actor, active, null, _hit_index(actor))`: ADR 0087's
## exact shape, which is `LootState._encounter_seed`'s shape. `hit_index` is not the
## exchange number (this verb is press-driven and has no turn counter, ADR 0076) but the
## number of exchanges this actor has already survived, counted on the duel ledger's own
## neighbour — `module_data`, not `CombatDuel`, because a winning fight never reaches
## `record_defeat` and an uncounted index would replay hit 0's answer forever. Counting
## from `LOOT`'s schema namespace keeps the two runtimes' keys apart on one actor.
##
## The three terms are read, not invented: `potency_of` is ADR 0088's reuse of
## `element_power_<e>` (the floor applies while `ElementsApi.attach` has no production
## caller), and `apply_chance` is ADR 0087's multiplicative resist formula. Neither is
## restated here — a second copy of either could drift from the spine's.


## The number of landed blows this actor has already thrown, as a substream salt.
##
## Read through the schema-version key rather than through `CombatDuel`, which counts
## only LOSSES: a player winning a fight would hand every exchange the same salt and the
## same answer, which is precisely the "hit N is a replay of hit 1" failure `hit_index`
## was added to the seed to prevent.
static func _hit_index(actor: Actor) -> int:
	var ledger := actor.get_module_data(&"schema")
	if not ledger is Dictionary:
		return 0
	return int(ledger.get("status_hits", 0))


## Count this blow toward the salt. Done AFTER the roll so the value a roll read is never
## a value it also changed, and only for a blow that actually reached the arithmetic — an
## evaded one consumes no draw and must not shift the next blow's stream either.
static func _count_hit(actor: Actor) -> void:
	var ledger := actor.get_module_data(&"schema")
	var next := _hit_index(actor) + 1
	if ledger is Dictionary:
		var carried := (ledger as Dictionary).duplicate()
		carried["status_hits"] = next
		actor.set_module_data(&"schema", carried)
		return
	actor.set_module_data(&"schema", {"status_hits": next})


## The gate, in the order that costs the least first: nothing about an avoided blow
## reaches the roll, the seed, or the catalogue.
static func _status_on_landing(
	actor: Actor, active: Dictionary, result: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	var none := {"applied": false, "id": "", "potency": 0.0}
	if actor == null or bool(result.get("evaded", true)):
		return none
	var element := _element_of(actor)
	if element == &"":
		return none
	var tuning := CombatEngineApi.tuning()
	var chance := StatusApply.apply_chance(
		STATUS_CHANCE, actor, tuning, StatusApply.elemental_resist(actor, actor, tuning, element)
	)
	var status_id := StatusApi.status_for_element(element, chance)
	if status_id == &"":
		return none
	var hit_index := _hit_index(actor)
	# `status_seed`'s THIRD parameter is the technique and is typed `Actor`, which the boss
	# is not — so it goes in that slot as the `Variant` the signature accepts, and as the
	# boss dict because that is the encounter `rng.seed` was already derived from. The
	# status stream is then keyed to the same encounter the exchange is, and per
	# `status_seed`'s own salt a Dictionary contributes only `active.get("element")`.
	var stream := RandomNumberGenerator.new()
	var seed_value := StatusApply.status_seed(rng.seed, actor, actor, active, hit_index)
	# `stream.seed = seed_value` ONLY. `RandomNumberGenerator.state` is the RAW PCG
	# state, not a seed: assigning it discards the mixing `seed` performs, so every
	# derived stream collapsed to the same first draw. Measured over this suite's own 40
	# seeds: with the overwrite 40/40 landed identically with `randf() == 0.0`; without
	# it, 22 landed and 18 were refused across 0.0098..0.9811. The status roll ADR 0087
	# exists to be seeded had no seed at all.
	stream.seed = seed_value
	# A saturated chance consumes no draw, matching `StatusApply` and `CombatBand.roll`:
	# the stream is derived, so nothing here can shift a later blow either way, but the
	# rule is kept so the two paths cannot disagree about when a roll is free.
	if chance < 1.0 and not stream.randf() < chance:
		return none
	_count_hit(actor)
	var potency := StatusApply.potency_of(actor, tuning, element)
	var applied := StatusApi.apply(actor, status_id, potency)
	return {
		"applied": bool(applied.get("ok", false)),
		"id": String(status_id),
		"potency": potency,
	}


## The element the player's blow carries: the strongest tier-1 affinity on the attacker.
##
## ## Why the AFFINITY, and what it does and does not claim
##
## ADR 0105 says the element is "the ATTACKER'S ELEMENT, read through the status module",
## and `Actor.affinities` is core's own map of which elements this body answers to — the
## actor's element is already stated, already serialized (`core/actor.gd:288`), and already
## the thing `ElementProvider` derives `element_power_<e>` from. So this reads the real
## carrier rather than inventing a second one.
##
## What it does NOT do is make `element_power_<e>` non-zero. ADR 0088 measured that
## `ElementsApi.attach` has no production caller, so potency rests on
## `status_potency_floor` until the mastery path lands — a known dependency of that ADR,
## not a new one, and the reason the report carries potency separately from "applied".
##
## ## The strongest, not the first
##
## A player may hold several affinities, so "the element" needs a rule and `ids()` order
## is not one — a `Dictionary` walk returns keys in INSERTION order, which makes the
## answer depend on the order another module granted them. So the highest affinity wins,
## with the catalogue's canonical element order breaking a TIE, which makes the answer a
## function of authored values alone. A tie is a real state (two elements trained equally),
## not an error.
##
## ## Why the ELEMENT LIST is restated here
##
## `ElementStats.BASE_ELEMENTS` would need a `combat` → `elements` edge ADR 0105 does not
## take and `tools arch` would refuse, so the five tier-1 ids are restated for exactly the
## reason `StatusDef` restates the same list: `tools new_module` grants a module `core` +
## `contracts` alone. `tests/modules/status/test_status_catalogue.gd` already pins THAT
## restatement against `ElementStats`, and `tests/modules/combat/test_combat_exchange_status.gd`
## pins this one, so neither copy can drift silently.
static func _element_of(actor: Actor) -> StringName:
	if actor == null or actor.affinities == null:
		return &""
	var best: StringName = &""
	var best_value := 0.0
	# `AUTHORED_ELEMENTS` order, not `ids()` order: the tie-break has to be canonical or
	# "the same player" answers differently run to run. It is the FULL ten, not tier 1 —
	# walking only `TIER_ONE_ELEMENTS` meant a lightning/ice/wind/light/dark player carried
	# NO element at all, so the ten statuses ADR 0110 published could never be inflicted
	# through the only production caller. That was the UNWIRED failure mode exactly.
	for candidate in StatusDef.AUTHORED_ELEMENTS:
		var value := actor.affinities.get_value(candidate)
		if value > best_value:
			best = candidate
			best_value = value
	return best


## The boss's answer, spent on the player's health, and the loss that ends a run.
static func _answer(
	actor: Actor, active: Dictionary, result: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	var pool := _health(actor)
	var answer := CombatDamage.resolve_hit(_boss_offense(active), guard(actor), rng)
	var taken := float(answer["share"]) * pool.maximum
	pool.change(-taken)
	result["taken"] = taken
	result["share_taken"] = float(answer["share"])
	result["evaded_by_player"] = bool(answer["evaded"])
	result["player"] = player(actor)
	if pool.current > 0.0:
		return result
	# The run is lost: the in-progress boss is discarded at full vitality and the reward
	# that was still owed is never minted, which is exactly what abandoning a run means.
	var lost := LootApi.abandon(actor)
	_record_defeat(actor, active, float(answer["share"]))
	result["outcome"] = OUTCOME_PLAYER_LOST
	result["ok"] = bool(lost.get("ok", false))
	result["reason"] = String(lost.get("reason", ""))
	result["boss"] = LootApi.summary(actor).get("active", {})
	result["player"] = player(actor)
	result["duel"] = duel(actor)
	return result


## Whether the boss a blow was aimed at is the one still standing afterwards.
##
## Answered by identity rather than by reading `loot`'s outcome vocabulary: rule E3 spawns
## the next boss on a defeat, so `active` legitimately changes under a killing blow, and a
## cleared run empties it. The same encounter id with vitality left is the only shape that
## means "this one is still up".
static func _still_standing(before: Dictionary, after: Dictionary) -> bool:
	if not bool(after.get("in_domain", false)):
		return false
	return (
		String(after.get("encounter_id", "")) == String(before.get("encounter_id", ""))
		and float(after.get("vitality", 0.0)) > 0.0
	)


## A boss crits and pierces at nothing: its profile is authored as two multiples of its
## band vitality, and inventing a crit chance here would be a third balance dial.
static func _boss_offense(active: Dictionary) -> Dictionary:
	return {
		"attack": float(active.get("attack", 0.0)),
		"crit_chance": 0.0,
		"crit_damage": 1.0,
		"penetration": 0.0,
	}


static func _boss_guard(active: Dictionary) -> Dictionary:
	return {"defense": float(active.get("defense", 0.0)), "damage_reduction": 0.0, "evasion": 0.0}


## The actor's health pool, created on first use. `attach_core_resources` sizes it from the
## derived `MAX_HEALTH`, so an actor nobody attached pools to can still be hit.
static func _health(actor: Actor) -> ResourcePool:
	if actor.resource(&"health") == null:
		actor.attach_core_resources()
	return actor.resource(&"health") as ResourcePool


static func _duel_state(actor: Actor) -> Dictionary:
	return CombatDuel.normalize(actor.get_module_data(CombatDuel.MODULE_KEY))


static func _record_defeat(actor: Actor, active: Dictionary, share: float) -> void:
	var duel := _duel_state(actor)
	(
		CombatDuel
		. record_defeat(
			duel,
			{
				"domain_id": String(active.get("domain_id", "")),
				"boss_id": String(active.get("boss_id", "")),
				"encounter_id": String(active.get("encounter_id", "")),
				"tier": int(active.get("tier", 0)),
				"share": share,
			}
		)
	)
	actor.set_module_data(CombatDuel.MODULE_KEY, duel)
	# Carried out, not killed: the run is over and the player walks out of the domain at
	# full vitality. Spent through `change` rather than by assigning `current`, so the
	# pool's `changed` signal still fires and every stat cache watching it invalidates.
	var pool := _health(actor)
	pool.change(pool.maximum - pool.current)
