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
## lifecycle, AND the status the boss's creature afflicts (authored on its `BossDef`,
## paid by `LootState.strike`, which is this verb's own call into it). This owns the
## resolution: how much a blow is worth and what the boss answers with. So `combat`
## depends on `loot` through its facade, and `loot` knows nothing of `combat` — the edge
## runs one way and `tools arch` enforces it.
##
## ## Why the status rides the ATTACKER, and why that is not a workaround
##
## The boss is NOT an `Actor` — it is a `Dictionary` in `actor.module_data`
## (`loot_state.gd:523-547`), with frozen attack/defense/vitality and no stats to resist
## with and no `add_status` to be written on. `StatusApi.apply(actor, …)` therefore cannot
## be pointed at it at all, and inventing a boss `Actor` to hold one debuff would be a
## second combatant the whole encounter model does not have. So a landed blow's status
## rides the player, which is what ADR 0105 calls for and what makes the player a SUBJECT
## of a status for the first time — a fight whose own blow can slow, burn or root the hand
## that threw it.
##
## ## Why the boss's OWN status also rides the player
##
## For the same reason and by the same route: the only `Actor` in an encounter is the
## player, so it is the only thing a status can be written on. What is different is WHO
## chooses the def. ADR 0105's rule is that the ATTACKER'S element chooses it, and that
## answer can only ever be an `on_landed_blow` id — one per element, so the second half of
## every element's pair (`fire_pyre`, `metal_sunder`, `water_deluge`, `ice_shatter`,
## `lightning_surge`, `wind_spread`, `dark_wane`) had no producer at all, and the two
## amplifiers among them left the whole amplifier channel inert in production. A boss is
## the one creature in the game with an authored identity and no element, so its authored
## `BossDef.affliction` is what names the def: `_boss_affliction_numbers` pays it with the
## same ADR 0087 gate and ADR 0088 potency the landed blow uses, and `loot` does the apply.
##
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


## ADR 0105's substitute for ADR 0087's per-technique `status_chance`: the base gate
## chance, before ADR 0087's resist terms are subtracted, for BOTH statuses an exchange
## can inflict -- the player's own landed blow and the boss's authored affliction.
##
## ## WHERE THE NUMBER LIVES NOW (DEF-0145), and why it is not a literal here
##
## It used to be `const STATUS_GATE_CHANCE := 1.0` below, with this docblock admitting it
## was standing in for a `CombatTuning` field that could not be authored because the wave
## that wrote this file was forbidden from editing `modules/combat_engine/**`. That
## restriction is gone, so the number is DATA: `CombatTuning.status_gate_chance`, authored
## at `1.0` in `combat_damage.tres`. [method _status_gate] is the one reader, and both
## call sites below go through it, so a balance pass edits the `.tres` and nothing else.
##
## ## Why `1.0` is still the shipped value, and what `1.0` does and does not mean
##
## THE VALUE IS NOT BEING RETUNED BY THIS MOVE. `1.0` does NOT mean "resistance is
## ignored". `StatusApply.resolve_roll` reads the gate through `apply_chance`, which is
## `clampf(gate * p_apply, status_min_apply, 1.0)` over ADR 0884's flat power-vs-resist
## delta — so a gate of `1.0` hands the whole decision to that delta and the roll below.
## An actor with NO status power lands on the parity half rather than on certainty until
## `status.power.*` content lands (DEF-0346); the gate multiplies whatever parity the
## delta resolves. Lowering the authored value makes a resisted actor's landed status
## *and* a boss's affliction both rarer in proportion, without touching
## `status_min_apply` (the floor that keeps an open gate from reaching zero) or any
## `magnitude_cap`. That dial now
## lives in data, and a balance pass is a one-line `.tres` edit rather than a `.gd` one.
##
## The shipped rate is deliberately unchanged from what was measured. The defect was never
## that `1.0` is a bad number; it was that the boss's path DISCARDED the resolved chance
## instead of rolling it (`LootAffliction.inflict` compared `chance` to zero and then never
## used it), so every boss affliction landed 100% of the time regardless of
## `status_resistance`. Both paths now roll, identically, so `1.0` finally means what it
## always said.
static func _status_gate(tuning: CombatTuning) -> float:
	if tuning == null:
		return 0.0
	return clampf(tuning.status_gate_chance, 0.0, 1.0)


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
	# The two ADR 0087/0088 numbers the BOSS's own affliction is paid with, resolved
	# through the same two spine calls and in the same order as `_status_on_landing` uses
	# for the player's own blow, so the two statuses an exchange can inflict are gated by
	# one formula and neither is a second opinion about what chance means. `gate_open` is
	# the ROLLED verdict, not the chance: `loot` cannot roll it (no `combat_engine` edge),
	# so the gate travels down as an answer.
	var afflictions := _boss_affliction_numbers(actor, active, rng, float(blow["share"]))
	var struck := LootApi.strike(
		actor,
		float(blow["share"]) * float(active["vitality_max"]),
		seed_value,
		bool(afflictions["gate_open"]),
		float(afflictions["potency"])
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
		# What the boss this blow met inflicts, under the same shape as the landed-blow
		# `status` above. Primitives only, so a screen renders both without naming either
		# module.
		"affliction": {"applied": false, "id": "", "reason": ""},
		"boss": after,
		"player": player(actor),
	}
	if not bool(result["ok"]):
		return result
	result["status"] = _status_on_landing(actor, active, result, rng)
	# Read off the STRIKE, not recomputed: `LootApi.strike` already ran the producer
	# against the boss that was struck, and on a defeat that boss is gone — so the
	# recomputation would either be the next creature's affliction or empty.
	result["affliction"] = struck.get("affliction", result["affliction"])
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
		# ADR 0877: the STAT is now the crit BONUS magnitude. This model's profiles were
		# tuned on a `1.5 +` crit multiplier, so this boundary PRESERVES that reference
		# (`1.5 + bonus`, byte-identical to the old `1.5 + comprehension * 0.004`) until
		# the exchange converts to the flat pair, which is its own lane's change.
		"crit_damage": 1.5 + actor.stats.derived(Stat.CRIT_DAMAGE),
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
## The three terms are READ, not invented: the chance, the potency and the rolled verdict
## all come from `StatusApply.resolve_roll` (ADR 0886), the same owner the spine's S12
## stage calls, so neither path can restate the other's arithmetic. `potency` is no longer
## floor-only either: `actor_factory.gd` attaches `ElementsApi` to every built actor, so
## `element_power_<e>` is live and the floor is what an UNTRAINED element reads.


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
	var gate := _status_gate(tuning)
	var status_id := StatusApi.status_for_element(element, gate)
	if status_id == &"":
		return none
	var def := StatusApi.definition(status_id)
	var request := {
		"id": status_id,
		"element": element,
		"kind": &"" if def == null else def.kind,
		"immunity_tags": [] if def == null else def.immunity_tags,
		"chance": gate,
		"scope": String(StatusApply.SCOPE_COMBAT),
	}
	var hit_index := _hit_index(actor)
	# ADR 0886: the arithmetic is `StatusApply.resolve_roll`'s, the SAME call the spine's
	# S12 stage makes — this site used to run only the gate and skip the potency split and
	# immunity entirely. `active` rides the technique slot the way `status_seed`
	# documents: the boss is not an `Actor`, and a Dictionary contributes only
	# `active.get("element")` to the salt, so the stream stays keyed to this encounter.
	var resolved := StatusApply.resolve_roll(actor, actor, tuning, request, rng, active, hit_index)
	if not bool(resolved.get(&"ready", false)) or not bool(resolved.get(&"open", false)):
		return none
	_count_hit(actor)
	var duration := -1.0
	if def != null:
		duration = float(def.duration) * maxf(0.0, float(resolved.get(&"duration_net", 1.0)))
	var applied := StatusApi.apply(actor, status_id, float(resolved.get(&"potency", 0.0)), duration)
	return {
		"applied": bool(applied.get("ok", false)),
		"id": String(status_id),
		"potency": float(resolved.get(&"potency", 0.0)),
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
## ADR 0088 measured that `ElementsApi.attach` had no production caller; that is no
## longer true — `actor_factory.gd` attaches it (and `apply_realm_modifiers` after
## enrolment), so `element_power_<e>` is live for every built actor and potency follows
## the element rather than the floor for a trained affinity. The floor is what an
## untrained element reads, which is why the report carries potency separately from
## "applied".
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


## ADR 0087's gate and ADR 0088's potency for the status the BOSS inflicts, resolved and
## ROLLED as `{chance, potency, gate_open}`.
##
## ## Why this ROLLS, and why the roll lives HERE rather than in `LootAffliction`
##
## Measured before this edit: this function returned a `chance` that
## `LootAffliction.inflict` compared against `0.0` and then DISCARDED — no rng, no roll,
## anywhere on the affliction path — so every authored boss affliction landed on the first
## blow that connected, and `Stat.STATUS_RESISTANCE` (computed right here, passed down two
## modules, and thrown away) had no visible effect on anything. The gate was theatre.
##
## The roll cannot live in `loot`. `loot`'s registry entry is
## `[contracts, core, items, status]` — it does NOT depend on `combat_engine` — and giving
## it the substream would mean a `loot -> combat_engine` edge, a second place that owns ADR
## 0087's `status_seed` shape, and the two paths would then be free to disagree about when a
## roll is free. So the roll happens here, in the module that already owns a seeded
## substream for exactly this purpose, and the RESULT travels down `LootApi.strike` as a
## VERDICT rather than as a probability. `loot` keeps no rng, keeps no chance arithmetic,
## and cannot be asked to re-roll.
##
## ## The SUBSTREAM, mirrored from `_status_on_landing` line for line
##
## The discipline is the player's own landed-blow path's, unchanged:
##
## ```
## var stream := RandomNumberGenerator.new()
## var seed_value := StatusApply.status_seed(rng.seed, actor, actor, active, salt)
## stream.seed = seed_value        # `state` is RAW PCG, never assigned
## if chance < 1.0 and not stream.randf() < chance:
##     return closed
## ```
##
## Three properties are load-bearing and all three are inherited, not reinvented:
##
## - `stream.seed = seed_value` ONLY. `RandomNumberGenerator.state` is the RAW PCG state,
##   not a seed; assigning it discards the mixing `seed` performs. That bug was already
##   found and fixed once here (see `_status_on_landing`), and re-introducing it in a second
##   function is exactly how it comes back.
## - `rng.seed` is the shared EXCHANGE stream, which `_answer` also draws from. Taking a
##   draw off it would re-roll the boss's return stroke — adding a status would change the
##   damage the boss deals. The status stream is DERIVED from it, never consumed from it, so
##   the affliction cannot perturb the blow that triggered it.
## - A saturated chance consumes NO draw, matching `_status_on_landing`, `StatusApply` and
##   `CombatBand.roll`: the stream is derived, so nothing here can shift a later blow either
##   way, but the rule is kept identically in both functions so the two paths cannot drift
##   on when a roll is free.
##
## ## Why the salt is the boss's SHARE, not the landed-blow counter
##
## `_status_on_landing` salts on `_hit_index(actor)`, which it increments itself, because a
## landed blow must not replay the previous blow's answer. The affliction has no counter of
## its own to bump — `loot` owns the boss's lifecycle and `combat` must not write into it —
## so the SALT is instead the share the blow actually dealt, scaled to an integer. Two
## properties fall out of that choice and both are wanted:
##
##   - `chain_depth` / recursion cannot bite. The salt is a pure function of a blow that is
##     already resolved, so a re-entrant call re-DERIVES rather than consumes: no shared
##     cursor advances and no depth counter can be read twice.
##   - Two blows that dealt the same share re-roll the same verdict (determinism), and two
##     blows that dealt different shares almost never do (the replay bug). The share spans
##     `CombatDamage`'s clamped `[MIN_SHARE, 1.0]` and is a function of the attack roll
##     alone, which is what makes it a per-blow value rather than a per-fight constant.
##
##   The scaling is used for the SALT ONLY and never for the comparison: the roll itself is
##   `stream.randf() < chance` against the full-precision `chance`, so two blows in the same
##   hundredth bucket are answered by one draw but not by one PROBABILITY.
static func _boss_affliction_numbers(
	actor: Actor, active: Dictionary, rng: RandomNumberGenerator, share: float
) -> Dictionary:
	var none := {"chance": 0.0, "potency": 0.0, "gate_open": false}
	var status_id := StringName(active.get("affliction", ""))
	if actor == null or status_id == &"":
		return none
	var def := StatusApi.definition(status_id)
	if def == null or not def.is_combat_scope():
		return none
	var tuning := CombatEngineApi.tuning()
	var element := def.element
	var request := {
		"id": status_id,
		"element": element,
		"kind": def.kind,
		"immunity_tags": def.immunity_tags,
		"chance": _status_gate(tuning),
		"scope": String(StatusApply.SCOPE_COMBAT),
	}
	var salt := int(clampf(share, 0.0, 1.0) * 100.0)
	# ADR 0886: the same owner the player's own blow uses. `gate_open` is the ROLLED
	# verdict, resolved here because `loot` has no `combat_engine` edge to roll it and
	# inventing a bare `randf()` there would be a second place that owns "when is a roll
	# free" (see `loot_affliction.gd`'s own note on the edge direction).
	var resolved := StatusApply.resolve_roll(actor, actor, tuning, request, rng, active, salt)
	if not bool(resolved.get(&"ready", false)):
		return none
	var chance := float(resolved.get(&"chance", 0.0))
	# The CLOSED gate, answered BEFORE any verdict: an already-closed chance spends no
	# draw, here or anywhere else, so it is refused rather than rolled against.
	if chance <= 0.0:
		return none
	if not bool(resolved.get(&"open", false)):
		return {"chance": chance, "potency": 0.0, "gate_open": false}
	return {
		"chance": chance,
		"potency": float(resolved.get(&"potency", 0.0)),
		"gate_open": true,
	}


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


## The boss's offense, read off the live boss.
##
## `attack` is priced off the band's authored vitality (ADR 0076). The rest is the
## boss's own authored striking profile, frozen with the boss by `LootState._spawn` and
## read through `LootApi`'s facade like everything else about it. These used to be
## literals in this function — `crit_chance 0`, `crit_damage 1`, `penetration 0` — which
## meant no boss in the game could crit, pierce, or vary its answer at all, and no
## authored content could make one (BL-0224). Reading them costs nothing here: they are
## already in the bundle `CombatDamage.resolve_hit` expects, and that function clamps
## every one, so a boss nobody profiled still fights exactly as it did before.
static func _boss_offense(active: Dictionary) -> Dictionary:
	return {
		"attack": float(active.get("attack", 0.0)),
		"crit_chance": float(active.get("crit_chance", 0.0)),
		"crit_damage": float(active.get("crit_damage", 1.0)),
		"penetration": float(active.get("penetration", 0.0)),
	}


## The boss's defense. Its armor is priced off the band; its evasion and flat damage
## reduction are the authored half, read for the same reason as [method _boss_offense].
static func _boss_guard(active: Dictionary) -> Dictionary:
	return {
		"defense": float(active.get("defense", 0.0)),
		"damage_reduction": float(active.get("damage_reduction", 0.0)),
		"evasion": float(active.get("evasion", 0.0)),
	}


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
			},
			actor
		)
	)
	actor.set_module_data(CombatDuel.MODULE_KEY, duel)
	# ## DEF-0105: the earn is VERIFIED here, and this is the only read of it
	#
	# `CombatDuel.record_defeat` calls `DestinyApi.earn_fate`, and `earn_fate`
	# returns the LEDGER — not a verdict. A refused earn (unknown id, already held,
	# a null actor) returns that identical ledger and QUEUES nothing (ADR 0134), so
	# the call on its own cannot say the fate arrived. `has_fate` is the only
	# honest answer, and asking it here rather than trusting the call is precisely
	# what `event_prize.gd:95-96` does not do.
	#
	# A miss is REPORTED and nothing else: an earn that silently failed would leave
	# a player who earned a consequence with no consequence, which is the UNWIRED
	# failure this whole seam is being closed to remove. A refused earn is an
	# ordinary outcome, so it is not an error — `push_warning` is the engine
	# telling a developer the wiring is wrong, and never a player-facing notice.
	if not DestinyApi.has_fate(actor, CombatDuel.FATE_FELL):
		push_warning(
			(
				(
					"combat: a duel was recorded as lost but %s was not earned (id unknown to the "
					+ "fate catalog?). The ledger and the fate are separate writes, so nothing here "
					+ "records the debt."
				)
				% String(CombatDuel.FATE_FELL)
			)
		)
	# Carried out, not killed: the run is over and the player walks out of the domain at
	# full vitality. Spent through `change` rather than by assigning `current`, so the
	# pool's `changed` signal still fires and every stat cache watching it invalidates.
	var pool := _health(actor)
	pool.change(pool.maximum - pool.current)
