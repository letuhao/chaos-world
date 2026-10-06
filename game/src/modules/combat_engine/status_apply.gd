class_name StatusApply
extends RefCounted

## S12: status application on a CLEAN landed hit, from a seeded substream (ADR 0087).
##
## ## Called by the spine: ADR 0105 amended 2026-10-04 (DEF-0145 closed)
##
## ADR 0087 made this the spine's twelfth stage. ADR 0105 first decided "S12 is
## retired as the application site, not re-routed; the spine is not built to reach it",
## and the spine's call was REMOVED — a measured call: no shipped `ctx_builder` wrote
## [constant REQUEST_KEY], so every landed blow through the stage returned
## `REFUSE_NO_REQUEST`.
##
## **That is no longer true, and this block was the last place still saying it was.**
## The spine now ships and is reachable from a player's blow
## (`app/combat_boot.gd:881,947` wraps the shipped `ctx_builder` with a
## `status_request`), and `CombatSpine.resolve_hit` calls this stage again
## (`spine.gd:198-200`). The stage is live on BOTH paths: the spine for a blow
## resolved through it, and `CombatExchange._status_on_landing` /
## `_boss_affliction_numbers` for the encounter, which keeps its own call.
##
## What SURVIVES either way, and is what every production path reads: the arithmetic
## below. `elemental_resist`, `apply_chance`, `potency_of` and `status_seed` are called
## in place by `modules/combat/exchange.gd` (`_status_on_landing` for the player's own
## landed blow, `_boss_affliction_numbers` for the boss's authored affliction) and
## `modules/loot/loot_affliction.gd`. ADR 0105's own words survive the amendment:
## "ADR 0087's placement is superseded, not its arithmetic" — the arithmetic was never
## in question. `modules/status/api.gd`'s `apply`/`clear_combat_scope` are the verbs
## that write to an actor; [method apply] is the arithmetic-only reader.
##
## ## The formula, verbatim
##
## ```
## gate    = the attack's authored status_chance           (0.0 means "applies nothing")
## p_apply = the flat power-vs-resist contest              (ADR 0884, via `apply_chance`)
## chance  = clampf(gate * p_apply, status_min_apply, 1.0) (only when gate > 0)
## potency = maxf(status_potency_floor,
##                attacker element_power_<e> * status_potency_scale)
## ```
##
## and then ONE draw from a per-hit SUBSTREAM decides it. The roll is `r < p_apply`.
##
## ## The load-bearing property: a MISSED / PARRIED / BLOCKED hit applies NOTHING
##
## S12 gates on [method CombatOutcome.is_clean] — landed, not parried, not blocked — and
## that is not a detail. S2 (ADR 0067) carved `missed | parried | blocked` out of ONE
## draw precisely so the bands are mutually exclusive, and a defender who parried a blow
## has ANSWERED it: handing them a debuff for the privilege would make parrying worse
## than eating the hit, which inverts the entire defensive vocabulary. The same gate
## already stops S3 (crit), so S12 and crit agree about what a clean hit is instead of
## each inventing its own notion. This is the assertion `tests/…/test_status_application.gd`
## exists for.
##
## ## The resist formula is ADR 0069's, read once and not restated
##
## `QiDamage._resistance_of` already computes `clampf(element_defense_<e> /
## resist_divisor - penetration, 0, resist_cap)` for the damage formula, and S12 reads
## the SAME `CombatTuning` fields rather than a second pair that could drift. One
## resistance vocabulary in the game: a defender's fire resistance answers a fire hit
## and a fire-tainted status with one number.
##
## ## Mastery is PENETRATION and nothing else (ADR 0088)
##
## Two facts, and they are the whole ADR:
##
## 1. **No new stat channel.** Potency reads `element_power_<e>` — the id
##    `ElementProvider.contribute` already emits (`modules/elements/provider.gd:23`) —
##    rather than a new `element_status_power_<e>` family. ADR 0088's measured argument
##    is that a second per-element family costs 10 more authored option ids and one more
##    read site for a scalar that already exists, which is exactly the "one family read
##    and nine siblings unread" defect class. Reusing it inherits ADR 0069's
##    `RealmScaling.SOURCE` fix for free.
## 2. **Penetration is subtracted from RESISTANCE, never multiplied into POTENCY.**
##    `CombatStats.PENETRATION` appears exactly once in this file, in the resist term.
##    Applying it to potency as well would double-dip one investment — mastery would buy
##    both "your debuffs land" and "your debuffs hit harder", and a balance pass could
##    not move either without moving both.
##
## ## No `elements` edge, and therefore no registry edit
##
## ADR 0087's consequence says `combat_engine` gains `elements` in
## `tools/arch/registry.json`. It does NOT need to, and the reason is the precedent
## `QiDamage` set (see its module docblock, "this module has NO `elements` edge"): the
## per-element stat ids are named as STRING PREFIXES on `CombatTuning`
## (`element_power_prefix`, `resist_resistance_prefix`) and read as bare ids. This file
## names no class of the `elements` module — not `ElementStats`, not `ElementRules` —
## so the registry stays `["contracts", "core"]` and does not have to declare an edge
## that exists only as a string concatenation. A registry entry whose only justification
## is a naming convention is a lie waiting to be removed.
##
## ## A null `rng` means NO DRAW and NO STATUS, never a `randf()` fallback
##
## The spine takes an injected generator precisely so a resolve is reproducible from a
## seed (ADR 0067), and `CombatBand.roll` already treats a null `rng` as "the caller
## has declared this roll saturated". S12 follows it exactly: a null generator means no
## status roll happened at all. The alternative — the `randf()` fallback
## `CombatDamage.resolve_hit` uses — is the thing ADR 0087 explicitly rejects as "a
## silent fallback", and a shared spine cannot be the one place that guesses.
##
## ## The seed is a SUBSTREAM, and this is the precedent it copies
##
## ADR 0087 gives the shape verbatim and it is the shape `LootState._encounter_seed`
## already uses (`modules/loot/loot_state.gd:607-609`):
##
## ```
## (parent_seed * 2654435761 + absi(hash(salt))) & 0x7FFFFFFF
## ```
##
## Why a substream rather than a third draw off the caller's generator: the caller's
## stream is SHARED, so a draw here would shift every subsequent band's and crit's
## numbers — adding a status roll would re-roll every crit in the fight. Deriving a
## child stream from `(seed, attacker, defender, technique, hit_index)` means S12's
## outcome is a pure function of inputs, and a technique that grows a `status_chance`
## cannot retroactively change the damage it dealt. Three draws per landed hit maximum
## (band, crit, status) and each is independent of how many were taken before it.
##
## ## Degrade, never throw
##
## A null actor, a null technique, an empty status id, a defender who already holds the
## id, and an unknown `StatusEffect` shape all return a refusal. Nothing here writes
## health, so the status layer cannot become a second damage formula (ADR 0087), and
## nothing here negates: potency and chance are non-negative and S9's single sign flip
## stays the only one in the engine.

## The key every authored effect rides in on `ctx.data`: a status def carrying
## `{id, chance, element, scope, duration, potency}`. A STRING dict so this file reads
## a content shape it does not own without naming a type another agent is mid-write on
## — the same `Variant` discipline `QiDamage` uses for its injected rules.
##
## ## Nothing in `game/src` writes this key, and that is measured rather than assumed
##
## `app/combat_boot.gd`'s `ctx_builder_for` — the only shipped `ctx_builder` — routes to
## `QiDamage.builder`, `BodyDamage.builder` or `MindDamage.builder`, and all three set only
## their own mechanism inputs (`element_share`, `aim_meridian`, `mind_kind` / the sea).
## `TechniqueDef` authors no status field, and ADR 0105 explicitly declined to add one
## ("`TechniqueDef` gains NO status field … The element is already the authored carrier").
## Every `set_data(REQUEST_KEY, …)` in the tree is under `game/tests/` (three sites), so
## the spine's S12 was UNWIRED rather than rarely-taken: every landed blow through it
## returned `REFUSE_NO_REQUEST`. That measurement is why the spine's call was deleted
## (ADR 0105, DEF-0145) instead of being given a second producer.
const REQUEST_KEY := &"status_request"

## The result keys of [method apply]. Every value is a primitive, so a readout can
## render it and a save can carry it without naming this class (ADR 0038).
const APPLIED := &"applied"
const REFUSED := &"refused"

## The `effects[]` entry S12 appends its result to, and the kind it carries. ADR 0087:
## "`CombatOutcome` gains no status field. S12's result rides `effects[]`, so
## `to_dict()` stays primitives-only (ADR 0038) and a screen renders it unchanged."
## So the outcome does not grow a field, this is the read model, and the spine stays
## the one place a caller looks.
const EFFECT_KIND := &"status_application"
const OUTCOME_KEY := &"status"

## Refusal reasons, as the caller sees them. Each is a claim a test can pin, which a
## bare `false` could not be.
const REFUSE_NOT_CLEAN := &"not_clean"
const REFUSE_NO_REQUEST := &"no_request"
const REFUSE_NO_GATE := &"no_gate"
const REFUSE_ALREADY_HELD := &"already_held"
const REFUSE_NO_RNG := &"no_rng"
const REFUSE_RESISTED := &"resisted"
const REFUSE_NO_POTENCY := &"no_potency"
const REFUSE_UNWRITABLE := &"unwritable"
## ADR 0885: the defender carries `status.immune.<tag>` at `>= 1.0` for a tag this status
## declares. A hard refusal is its own reason, like every other refusal here.
const REFUSE_IMMUNE := &"immune"

## The authored keys read off a `REQUEST_KEY` dictionary. Named here so the shape is
## stated once: a def that spells a key differently is unreadable, not silently absent,
## and an unreadable key reads the degenerate value every one of these has.
const KEY_ID := &"id"
const KEY_CHANCE := &"chance"
const KEY_ELEMENT := &"element"
## ADR 0884: the status's own `kind` (`StatusDef.kind`), read for the per-category
## channel. An absent key reads `&""`, which simply skips that channel.
const KEY_KIND := &"kind"
## ADR 0885: the immunity tags the applying status declares (`StatusDef.immunity_tags`).
## An absent or non-array key is no tags.
const KEY_IMMUNITY_TAGS := &"immunity_tags"
const KEY_SCOPE := &"scope"
const KEY_DURATION := &"duration"
const KEY_POTENCY := &"potency"

## Scope ids as ADR 0086 names them, read as `StringName`s because `StatusEffect`'s
## `enum Scope` is a contracts-layer type this file must not name. `COMBAT` is the only
## scope `Stat.STATUS_RESISTANCE` touches (ADR 0086: "a blessing the game pays out must
## not tax the player for receiving it"); any other scope is not resisted at all.
const SCOPE_COMBAT := &"combat"


## S12. Resolve the request on `ctx.data`, roll it against the defender, and apply it.
##
## Returns a primitives-only result dictionary (see the `REFUSED_*` constants), never a
## bare `bool`, because "why not" is the part a balance pass needs: a status that never
## lands on a specific defender is a balance question, and a bare `false` would make it
## a debug question instead.
##
## `rng` is the caller's stream, read for its SEED and never drawn from — the draw
## happens on a substream derived in [method status_seed]. `technique` and `hit_index`
## enter only that seed, so S12 never inspects what it is defending against beyond the
## stats it reads. `hit_index` is the number of this hit in the exchange; two identical
## attacks in one fight must not roll the same status.
static func apply(
	attacker: Actor,
	target: Actor,
	tuning: CombatTuning,
	ctx: AttackContext,
	outcome: CombatOutcome,
	rng: Variant = null,
	technique: Variant = null,
	hit_index: int = 0
) -> Dictionary:
	# The gate that makes this stage safe to run last and unconditionally. Checked
	# FIRST, before the request is even read, so a parried blow cannot pay for a
	# dictionary lookup it will never use — and, more importantly, so the refusal is
	# the FIRST thing a reader of the outcome sees.
	if outcome == null or not outcome.is_clean():
		return _refused(REFUSE_NOT_CLEAN)
	var request := _request_of(ctx)
	if request.is_empty():
		return _refused(REFUSE_NO_REQUEST)
	var status_id := StringName(request.get(KEY_ID, &""))
	if status_id == &"":
		return _refused(REFUSE_NO_REQUEST)
	# A closed gate consumes NO draw — the same reason `CombatBand.roll` skips its draw
	# on a saturated band. Waste here would be doubly costly: the stream is shared, so a
	# pointlessly consumed number would shift the NEXT hit's band and crit.
	var gate := _finite(_number(request.get(KEY_CHANCE, 0.0)))
	if gate <= 0.0:
		return _refused(REFUSE_NO_GATE)
	if target == null or target.has_status(status_id):
		return _refused(REFUSE_ALREADY_HELD)
	if rng == null:
		# No generator, no status. The spine takes an injected `rng` precisely so a
		# resolve is reproducible (ADR 0067); a null one is a caller asking for the
		# answer that consults no randomness, and a `randf()` fallback would be exactly
		# the silent guess ADR 0087 rejects.
		return _refused(REFUSE_NO_RNG)
	var tags := _tags_of(request)
	# ADR 0885, the hard half of immunity: a defender whose `status.immune.<tag>` reaches
	# `1.0` refuses the status outright, BEFORE the roll — the closed-gate discipline: a
	# refusal that consumes no draw.
	if tuning.status_immune_prefix != "":
		for tag in tags:
			var immune := _stat(target, StringName(tuning.status_immune_prefix + String(tag)))
			if immune >= 1.0:
				return _refused(REFUSE_IMMUNE, {REFUSE_IMMUNE: tag})
	var element := _id_of(request.get(KEY_ELEMENT, &""))
	var kind := _id_of(request.get(KEY_KIND, &""))
	var resist := elemental_resist(attacker, target, tuning, element)
	# ADR 0885: the potency split's two net factors, and the intensity floor BEFORE the
	# roll (Keepverse §2.2: a status that would land at zero intensity does nothing, which
	# is what "refused" means).
	var intensity_net := _net_factor(
		attacker,
		target,
		tuning,
		status_id,
		kind,
		tuning.status_intensity_prefix,
		tuning.status_intensity_reduction_prefix,
		tags
	)
	var duration_net := _net_factor(
		attacker,
		target,
		tuning,
		status_id,
		kind,
		tuning.status_duration_prefix,
		tuning.status_duration_reduction_prefix,
		tags
	)
	if intensity_net <= _finite(tuning.status_min_net_factor):
		return _refused(REFUSE_NO_POTENCY)
	# `elem_resist` is the ELEMENTAL half and applies to every scope: it is a
	# defender's build answering an element, not a combat-games dial, so a cultivation
	# blessing that happens to name an element is still answered by fire resistance.
	# The `status_defense` half is the COMBAT dial and is read inside `apply_chance`
	# only when the scope is COMBAT (ADR 0086).
	var chance := apply_chance(
		attacker,
		target,
		tuning,
		gate,
		status_id,
		kind,
		element,
		resist,
		_id_of(request.get(KEY_SCOPE, SCOPE_COMBAT))
	)
	var stream := _substream(rng, attacker, target, technique, hit_index)
	# Saturated high consumes NO draw, matching `CombatBand.roll`: `p_apply >= 1.0`
	# means the roll cannot change the answer.
	if chance < 1.0 and not stream.randf() < chance:
		return _refused(REFUSE_RESISTED)
	return _written(
		attacker, target, tuning, request, status_id, resist, chance, intensity_net, duration_net
	)


## Publish `result` on `outcome` by APPENDING it to the proposal's `effects[]`, which
## is how ADR 0087 requires S12 to report without `CombatOutcome` gaining a field.
##
## ## Why this is not `outcome.to_dict()[...]` and not a new field
##
## `CombatOutcome.effects()` reads the MECHANISM's proposal, and the spine has already
## read that proposal for S6 and S7 by the time S12 runs — so the read model has to be
## written onto the same array a caller's mechanism produced it on, or there would be two
## `effects[]` and a UI would have to guess which one it is reading.
##
## Appended only when it CHANGED something: a refusal for `not_clean` on every missed
## swing would otherwise fill `effects[]` with one entry per attack in the fight, which
## is an unbounded payload growing in a save blob for the privilege of recording that
## nothing happened. A refusal IS recorded when it is informative — a resisted roll, a
## held status, a missing request — because those are the balance questions. The one
## refusal that is silence is "this hit was not clean", and the outcome already says so.
static func record(outcome: CombatOutcome, result: Dictionary) -> void:
	if outcome == null or result.is_empty():
		return
	if not bool(result.get(APPLIED, false)) and result.get(REFUSED, &"") == REFUSE_NOT_CLEAN:
		return
	# FLATTENED, not nested. `DamageProposal.effects` is primitives-only by contract
	# (`damage_proposal.gd:_primitive_only`), so handing `add_effect` a Dictionary
	# under one key was dropped with a loud error and the effect arrived empty. Every
	# field of `result` is a primitive by construction, so spreading them beside the
	# kind is both legal and what a reader of the effect expects.
	var entry := {}
	for key in result.keys():
		entry[StringName(key)] = result[key]
	var proposal := outcome.proposal
	if proposal == null:
		return
	if proposal.has_method(&"add_effect"):
		proposal.call(&"add_effect", EFFECT_KIND, entry)
		return
	# A proposal of a shape that cannot carry an effect is not a crash: the mechanism
	# owns this array and `CombatProposalReader` exists precisely so a proposal written
	# against a different shape reads as empty instead of breaking the spine.
	var effects: Variant = proposal.get(&"effects")
	if effects is Array:
		(effects as Array).append(entry.duplicate(true))


# --- the arithmetic, exposed so each term is a two-line test --------------------


## ADR 0069's elemental resist, for a STATUS: `clampf(element_defense_<e> /
## resist_divisor - CombatStats.PENETRATION, 0, resist_cap)`.
##
## The divisor and cap are the SAME `CombatTuning` fields `QiDamage._resistance_of`
## reads, so the two resist terms cannot drift apart, and the penetration is the SAME
## `CombatStats.PENETRATION` — ADR 0088's "mastery does exactly two things, both
## penetration", and this is one of them.
##
## A non-positive or non-finite divisor reads as `0.0` rather than dividing, for
## `QiDamage._resistance_of`'s reason: a `0.0` divisor would produce `0.0 / 0.0` and a
## NaN that survives every clamp. An empty element has no resistance to read, which is a
## real answer and not a failure — ADR 0069's "a wrong element is a weaker hit, never a
## null one" applied to the status layer.
static func elemental_resist(
	attacker: Actor, target: Actor, tuning: CombatTuning, element: StringName
) -> float:
	if element == &"" or tuning == null or target == null or target.stats == null:
		return 0.0
	var raw := _finite(target.stats.derived(_suffixed(tuning.resist_resistance_prefix, element)))
	# Answered, not raw: the defender's `ABSORPTION` turns aside this much of the
	# attacker's penetration before it ever reaches the armour value, as a flat
	# difference through `CombatStats.pierce` (Keepverse `penDelta`). Either half
	# floors at zero on its own side: negative penetration would be a defence
	# bonus wearing an attacker's name, and the mirror holds for absorption.
	var raw_pen := maxf(
		0.0,
		(
			CombatStats.default_of(CombatStats.PENETRATION)
			+ _finite(_stat(attacker, CombatStats.PENETRATION))
		)
	)
	var raw_abs := maxf(
		0.0,
		(
			CombatStats.default_of(CombatStats.ABSORPTION)
			+ _finite(_stat(target, CombatStats.ABSORPTION))
		)
	)
	var penetration := CombatStats.pierce(raw_pen, raw_abs)
	# ADR 0200. `resist_cap` is gone: mitigation is a RATIO of two magnitudes, never an
	# authored percent, so there is no ceiling to clamp a resistance to. Penetration now
	# scales the DEFENSE VALUE (`pierce_scale`) rather than subtracting points off it,
	# which is the dimensionally-wrong shape the ADR names by name.
	var divisor := _finite(tuning.resist_divisor)
	if divisor <= 0.0:
		return 0.0
	var defense := maxf(0.0, raw / divisor)
	var pierce_scale := _finite(tuning.pierce_scale)
	if pierce_scale > 0.0:
		defense *= 1.0 / (1.0 + maxf(0.0, penetration) / pierce_scale)
	return defense


## The chance an OPEN gate actually applies (ADR 0884):
##
## ```
## power   = status.power.omni + status.power.<kind> + status.power.<status_id>
## resist  = status_defense share [combat only] + elemental_resist
##           + status.resist.<element> + status.resist.omni
##           + status.resist.<kind> + status.resist.<status_id>
## p_apply = clampf(0.5 + (power - resist) / (2 * status_rate_scale), 0.0, 1.0)
## chance  = clampf(gate * p_apply, status_min_apply, 1.0)
## ```
##
## ## Parity reads HALF, which is Keepverse's own semantics on our clamp
##
## Keepverse's evaluator builds its apply chance from the same `power - resist` delta
## through a sigmoid, whose value at parity is exactly `0.5`; this copy keeps that
## semantics on this tree's linear clamp (ADR 0877): parity reads half, `+/-`
## `status_rate_scale` of net advantage reads certainty / zero, and NEITHER input is
## capped. A strict-zero parity (the hit/crit rule) would make a shipped status
## impossible the moment its defender held one point of defence, which replaces the
## feature rather than porting it.
##
## ## Why the scope gates ONE term and not the others
##
## ADR 0086: "`Scope.COMBAT` is resisted by `Stat.STATUS_RESISTANCE`; `Scope.CULTIVATION`
## is not — a blessing the game pays out must not tax the player for receiving it." Only
## the `status_defense` share is gated, because it is the combat-games dial. Every
## channel term and `elemental_resist` are a defender's BUILD answering a status, so a
## cultivation effect naming an element is still answered by that element's resistance
## and by a defender's authored stance.
##
## ## The stat id is read from `tuning.status_defense_stat`, and that is the whole fix
##
## This read `Stat.STATUS_RESISTANCE` directly, and ADR 0200 renamed the id:
## `actor_stats.gd` now puts `will * 0.003` into `Stat.STATUS_DEFENSE` — a MAGNITUDE the
## realm ladder scales — and leaves `status_resistance` carrying a provider's value that
## nothing puts a `StatModifier` on. So the gate was reading a stat no defensive
## investment could move. Measured on `test_status_application.gd`'s own fixtures, a target
## at `_tuning_cap_resist()` (a flat `0.8`, which is what core's old formula saturated at)
## read `derived(status_resistance) == 0.8` and `derived(status_defense) == 0.0`, so the
## COMBAT gate answered `1.0 * (1 - 0.8) = 0.2` while a REAL `will`-scaled status defense
## was contributing nothing at all: an actor with the strongest status defence the game can
## author was strictly easier to hit with statuses than one with none.
##
## Read through DATA for the reason `mind_stat_prefix` is a string: `combat_engine` may not
## name the core const the ladder maintains, and the shape the gate wants is "whatever the
## defense magnitude is called today". `contracts/stat.gd` still declares both spellings, so
## the stale reference compiled silently and read a wrong number rather than failing — which
## is the failure this indirection exists to catch.
##
## The `0..1` clamp stays, and it is NOT a cap on the input: `status_defense` is unbounded,
## and the read maps it through ADR 0200's own ratio, which is the same shape `QiDamage`,
## `BodyDamage` and `MindDamage` use. ADR 0884 REPLACED the multiplicative composition with
## one flat delta, so what keeps a fully defended target reachable is `status_min_apply`
## alone: it is the floor a saturated defender still takes the status at, and it is what
## forbids the `0.0` an unbounded resist total would otherwise reach.
static func apply_chance(
	attacker: Actor,
	target: Actor,
	tuning: CombatTuning,
	gate: float,
	status_id: StringName,
	kind: StringName,
	element: StringName,
	elem_resist: float,
	scope: StringName = SCOPE_COMBAT
) -> float:
	if tuning == null or gate <= 0.0:
		return 0.0
	var power := _channel_total(attacker, tuning.status_power_prefix, status_id, kind, &"")
	var resist := _channel_total(target, tuning.status_resist_prefix, status_id, kind, element)
	resist += maxf(0.0, _finite(elem_resist))
	if scope == SCOPE_COMBAT:
		resist += clampf(_status_defense_share(target, tuning), 0.0, 1.0)
	var scale := _finite(tuning.status_rate_scale)
	# A non-positive scale cannot say how much advantage is decisive, and the honest
	# answer for a contest with no exchange rate is parity rather than a division.
	var p_apply := 0.5
	if scale > 0.0:
		p_apply = clampf(0.5 + (power - resist) / (2.0 * scale), 0.0, 1.0)
	var chance := _finite(gate) * p_apply
	return clampf(chance, clampf(_finite(tuning.status_min_apply), 0.0, 1.0), 1.0)


## One side's authored channel total (ADR 0884): `prefix + "omni"` always, plus
## `prefix + kind`, `prefix + status_id` and — the defender's call — `prefix + element`
## when each is known. An unauthored or absent prefix reads `0.0` for the whole side, and
## an unknown id reads `0.0` like every other absent stat on this path.
static func _channel_total(
	actor: Actor, prefix: String, status_id: StringName, kind: StringName, element: StringName
) -> float:
	if prefix == "" or actor == null or actor.stats == null:
		return 0.0
	var total := _stat(actor, StringName(prefix + "omni"))
	if kind != &"":
		total += _stat(actor, StringName(prefix + String(kind)))
	if status_id != &"":
		total += _stat(actor, StringName(prefix + String(status_id)))
	if element != &"":
		total += _stat(actor, StringName(prefix + String(element)))
	return maxf(0.0, _finite(total))


## ADR 0200's ratio for the COMBAT half of the status gate:
## `share = mitigation_ceiling * D / (K + D)` with `D` the defender's `status_defense`
## MAGNITUDE and `K = defense_divisor_k` the attacker's own scale.
##
## ## Why S12 needs a ratio at all, and what it costs
##
## `apply_chance` takes no `attacker`, so it cannot build the same `K` the three damage
## mechanisms build from the attacker's own offense. `defense_divisor_k` alone is what is
## available without growing a new parameter on a function six call sites use, and it is
## a defensible substitute: it is the same authored constant, and the gate's contest is
## between two defensive investments rather than between an offense and a defence.
##
## The honest cost is that the attacker's realm NO LONGER SCALES THIS GATE. `status_defense`
## climbs `1.00 -> 551.46` with the ladder and `K` does not, so a deep-realm defender's
## status immunity converges on `mitigation_ceiling` while at R1 the same build resists
## almost nothing. **That is the same class of defect ADR 0200 was written to remove, in the
## one place the fix did not reach**, and closing it properly needs a second decision I am
## not making silently: either `apply_chance` grows an `attacker` parameter and every call
## site passes one, or S12 reads the caller's already-resolved elemental resist as its `K`.
## Either is a change to `CombatExchange` and `exchange.gd`, outside this file's seam.
##
## What is asserted today is the part that IS sound: the share is an unbounded magnitude
## through a ratio, so it is strictly below the ceiling for every finite defense, the two
## resists compose rather than annihilate, and `status_min_apply` forbids a hard `0.0`.
## `tests/modules/combat_engine/test_status_application.gd` pins exactly those three.
static func _status_defense_share(target: Actor, tuning: CombatTuning) -> float:
	var divisor := _finite(tuning.resist_divisor)
	if divisor <= 0.0:
		return 0.0
	var raw := maxf(0.0, _finite(_stat(target, StringName(tuning.status_defense_stat))))
	var defense := raw / divisor
	var ceiling := clampf(_finite(tuning.mitigation_ceiling), 0.0, 1.0)
	if ceiling <= 0.0:
		return 0.0
	var divisor_k := maxf(0.0, _finite(tuning.defense_divisor_k))
	var denominator := divisor_k + defense
	if denominator <= 0.0:
		return 0.0
	return _finite(ceiling * defense / denominator)


## The potency of an applied status: `maxf(status_potency_floor, attacker
## element_power_<e> * status_potency_scale)`.
##
## ## The REUSE, which is ADR 0088's whole answer
##
## `element_power_<e>` is the id `ElementProvider.contribute` already emits, and it is
## already realm-invariant because ADR 0069 gave it a source-tagged `Op.MULT` realm
## modifier. A new `element_status_power_<e>` would be a SECOND magnitude vocabulary for
## the same element, with none of that invariance and ten more authored option ids. So
## potency reads the same scalar the damage formula's elemental term reads, and the cost
## ADR 0088 states is accepted: an actor cannot be a great elementalist AND a weak
## debuffer.
##
## ## Penetration is deliberately NOT here
##
## This is the assertion ADR 0088's second bullet exists to make. `CombatStats
## .PENETRATION` appears exactly once in this file — in [method elemental_resist] — and
## never in this function, so one investment buys "your status lands more often" and
## never also "your status hits harder".
##
## The floor exists because `element_power_<e>` is `0.0` on every actor until the
## mastery path and `app/` wiring land (ADR 0088's own consequence): without it S12 would
## apply statuses that are all but invisible. NON-NEGATIVE by construction — the only
## arithmetic is a multiply and a `maxf` of non-negatives — so nothing here can produce a
## negative magnitude a later reader would take for a sign. That matters because the
## spine's sign discipline admits exactly ONE negation, at S9.
static func potency_of(attacker: Actor, tuning: CombatTuning, element: StringName) -> float:
	var floor_value := 0.0 if tuning == null else maxf(0.0, _finite(tuning.status_potency_floor))
	if element == &"" or tuning == null or attacker == null or attacker.stats == null:
		return floor_value
	var power := maxf(
		0.0, _finite(attacker.stats.derived(_suffixed(tuning.element_power_prefix, element)))
	)
	return maxf(floor_value, power * maxf(0.0, _finite(tuning.status_potency_scale)))


## The seed of S12's per-hit substream: `LootState._encounter_seed`'s exact shape, which
## ADR 0087 names as the precedent (`modules/loot/loot_state.gd:607-609`).
##
## ```
## (parent_seed * 2654435761 + absi(hash(attacker.id ^ defender.id ^ hit_index))) & 0x7FFFFFFF
## ```
##
## ## `hit_index` is INSIDE the hash, and that is the whole point
##
## The salt mixes the three participants and then hashes ONCE, so `hit_index` reaches
## the multiplier term and two identical attacks in one exchange cannot land on the same
## child seed. Hashing the labels and XOR-ing `hit_index` AFTERWARDS would look
## equivalent and is not: the original computed the salt and then dropped it, which made
## the seed a pure function of `(seed, label)` and turned every hit in a fight into a
## replay of the first one's answer -- exactly the failure `hit_index` was added to
## prevent. A salt that is built and not multiplied in is a silent no-op, which is the
## defect class this whole file is written against.
##
## The same seed still reproduces the same sequence: the term is a pure function of its
## inputs, so `(seed, attacker, defender, technique, hit_index)` names one stream and
## nothing is drawn off the caller's generator to get there.
static func status_seed(
	hit_seed: int, attacker: Actor, target: Actor, technique: Variant, hit_index: int = 0
) -> int:
	var label := str(hit_index)
	if attacker != null:
		label = "%s^%s" % [String(attacker.id), label]
	if target != null:
		label = "%s^%s" % [String(target.id), label]
	if technique is Object:
		label = "%s^%s" % [String((technique as Object).get(&"id")), label]
	return (hit_seed * 2654435761 + absi(hash(label))) & 0x7FFFFFFF


## Everything after the roll succeeds: build the status and hand it to the actor.
##
## ## The return shape assumed of `Actor.add_status`
##
## This call is written defensively because `core/actor.gd` is owned elsewhere and the
## exact shape is not yet fixed: the return value is treated as "an absent / void /
## non-Dictionary answer means ACCEPTED", and a Dictionary is read for `ok` and
## `reason` only when it actually carries those keys. That way a plain
## `func add_status(status) -> void` and a `-> bool` and a
## `-> {ok: bool, reason: StringName}` all mean the same thing here, and none of the
## three can crash the spine on a shape mismatch.
##
## The awkwardness is worth naming: a refusal here would be a DUPLICATE of the two
## refusals above it. By the time this runs, the defender does not hold the id and the
## roll came up — so a refusal can only mean "the actor refused a status this stage had
## already cleared", which is a state bug in the actor rather than a balance decision.
## A shape that returned `ok` would be genuinely load-bearing for that case; today it is
## reported and passed through, and nothing is silently swallowed.
static func _written(
	attacker: Actor,
	target: Actor,
	tuning: CombatTuning,
	request: Dictionary,
	status_id: StringName,
	resist: float,
	chance: float,
	intensity_net: float = 1.0,
	duration_net: float = 1.0
) -> Dictionary:
	# ADR 0885: the intensity factor scales the MAGNITUDE, the duration factor the TIME.
	# Parity is `1.0` on both, so a request with no split channels authored writes the
	# same status the pre-split code wrote — the copy is additive at its baseline.
	var potency := (
		maxf(
			_finite(_number(request.get(KEY_POTENCY, 0.0))),
			potency_of(attacker, tuning, _id_of(request.get(KEY_ELEMENT, &"")))
		)
		* maxf(0.0, _finite(intensity_net))
	)
	var effect := _status(status_id, request, potency, tuning, duration_net)
	if effect == null:
		return _refused(REFUSE_UNWRITABLE)
	var answer: Variant = target.call(&"add_status", effect)
	if not _accepted(answer):
		return _refused(
			REFUSE_UNWRITABLE,
			{
				REFUSE_UNWRITABLE: StringName(_reason_of(answer)),
			}
		)
	return {
		APPLIED: true,
		REFUSED: &"",
		&"status_id": String(status_id),
		&"chance": chance,
		&"resist": resist,
		&"potency": potency,
		&"intensity_net": maxf(0.0, _finite(intensity_net)),
		&"duration_net": maxf(0.0, _finite(duration_net)),
	}


# --- internals -----------------------------------------------------------------


## The immunity tags off a request, or an empty list. A non-array key and non-name entries
## are dropped rather than crashing a hit that has already spent its damage.
static func _tags_of(request: Dictionary) -> Array:
	var raw: Variant = request.get(KEY_IMMUNITY_TAGS, [])
	if not (raw is Array):
		return []
	var out: Array = []
	for entry in raw:
		if entry is StringName or entry is String:
			out.append(StringName(entry))
	return out


## ADR 0885's net factor for one potency axis: `clampf(1 + delta / scale, min, max)`, where
## `delta` is the attacker's channel total minus the defender's `*Reduction` total, and
## each declared tag's `status.immuneReduction.<tag>` multiplies `(1 - reduction)` in —
## Keepverse's §6: a partial immunity blunts the status overall, never one axis
## selectively. A non-positive scale reads parity, exactly like the gate's own.
static func _net_factor(
	attacker: Actor,
	target: Actor,
	tuning: CombatTuning,
	status_id: StringName,
	kind: StringName,
	prefix: String,
	reduction_prefix: String,
	tags: Array
) -> float:
	if tuning == null:
		return 1.0
	var delta := _channel_total(attacker, prefix, status_id, kind, &"")
	delta -= _channel_total(target, reduction_prefix, status_id, kind, &"")
	var scale := _finite(tuning.status_net_factor_scale)
	var net := 1.0
	if scale > 0.0:
		net = 1.0 + delta / scale
	var low := _finite(tuning.status_min_net_factor)
	var high := _finite(tuning.status_max_net_factor)
	if high < low:
		high = low
	net = clampf(net, low, high)
	if tuning.status_immune_reduction_prefix != "":
		for tag in tags:
			var reduction := clampf(
				_stat(target, StringName(tuning.status_immune_reduction_prefix + String(tag))),
				0.0,
				1.0
			)
			net *= 1.0 - reduction
	return maxf(0.0, net)


## The `REQUEST_KEY` dictionary off `ctx.data`, or `{}`. Read through `get()` and
## `is Dictionary` because the shape belongs to whoever authored the effect, and a
## malformed request must degrade to "applies nothing" rather than crash a hit that has
## already spent its damage.
static func _request_of(ctx: AttackContext) -> Dictionary:
	if ctx == null:
		return {}
	var raw: Variant = ctx.data_value(REQUEST_KEY, null)
	return raw if raw is Dictionary else {}


## The substream for this hit. Built from [method status_seed], which is
## `LootState._encounter_seed`'s shape verbatim — the precedent ADR 0087 names.
##
## `state` is set alongside `seed` because that is what `DomainRng._generator` does
## (`modules/domain/domain_rng.gd:88-92`): seeding a Godot generator without resetting
## its state leaves the first draw a function of whatever ran before, which would make
## the "same seed, same outcome" claim false the moment two substreams were made from
## one parent in the same frame.
static func _substream(
	rng: Variant, attacker: Actor, target: Actor, technique: Variant, hit_index: int
) -> RandomNumberGenerator:
	var stream := RandomNumberGenerator.new()
	var seed_value := status_seed(rng.seed, attacker, target, technique, hit_index)
	# `stream.seed = seed_value` ONLY. `RandomNumberGenerator.state` is the RAW PCG
	# state, not a seed: assigning it discards the mixing `seed` performs, and the
	# result is a stream whose first draw is the same for every seed. Measured over 40
	# seeds: with the overwrite, 40/40 drew exactly 0.0; without it, the draws spread
	# across 0.0098..0.9811. A stage whose entire purpose is a seeded roll was
	# answering every hit the same way.
	stream.seed = seed_value
	return stream


## Build the `StatusEffect` to apply, or null when no constructor can make one.
##
## ## Why the constructor is resolved BY NAME rather than called directly
##
## `contracts/status_effect.gd` is owned by another agent and is mid-flight: ADR 0086
## widens it with `element` / `scope` / `magnitude` / `stacks` / … fields, and this
## file must compile against the OLD two-field shape, the NEW one, and anything between
## them. So the id and the duration go through the positional two-argument constructor
## every version has, and the widened fields are written afterwards through `set()` —
## which is the same `Variant` discipline `QiDamage` uses for an injected rules table,
## and the same reason `CombatProposalReader` reads a proposal through `get()` rather
## than `.amount`. A status therefore always carries its id and duration even if the
## widening never lands.
##
## Returns null only if `StatusEffect` cannot be constructed at all, which is a real
## breakage and is reported as one rather than swallowed.
static func _status(
	status_id: StringName,
	request: Dictionary,
	potency: float,
	tuning: CombatTuning,
	duration_net: float = 1.0
) -> RefCounted:
	var duration := _finite(_number(request.get(KEY_DURATION, 0.0)))
	if duration <= 0.0 and tuning != null:
		duration = _finite(tuning.status_default_duration)
	# ADR 0885: the duration factor scales the TIME; zero is still a constructible
	# effect, because `StatusEffect` owns what a zero duration means.
	duration *= maxf(0.0, _finite(duration_net))
	var effect := StatusEffect.new(status_id, duration)
	if effect == null:
		return null
	# The ADR 0086 fields, written only when the contract carries them, because a
	# `set()` on an absent property pushes an engine warning and this file must not warn
	# for a field whose contract has not landed yet. See `_assign`.
	_assign(effect, &"magnitude", maxf(0.0, potency))
	_assign(effect, &"element", _id_of(request.get(KEY_ELEMENT, &"")))
	_assign(effect, &"scope", _id_of(request.get(KEY_SCOPE, SCOPE_COMBAT)))
	return effect


## Write `value` on `effect` only when the property exists. `set()` on a missing
## property pushes an engine warning, and this file must not emit warnings for a field
## whose contract has not landed yet.
static func _assign(effect: RefCounted, key: StringName, value: Variant) -> void:
	if _has_property(effect, key):
		effect.set(key, value)


## Whether `object` exposes `key`. `get_property_list` rather than `in`-style probing,
## because that is the one question that answers about a scripted object.
static func _has_property(object: Object, key: StringName) -> bool:
	for entry in object.get_property_list():
		if StringName(entry.get("name", &"")) == key:
			return true
	return false


## Whether `Actor.add_status`'s answer means ACCEPTED.
##
## The deliberately permissive reading, stated in full at the call site: a void answer,
## a `null`, a `true`, and a `Dictionary` with no `ok` key are all ACCEPTED, and only an
## explicit `ok == false` is a refusal. The reason is that the current
## `core/actor.gd` declares `func add_status(status: StatusEffect) -> void` — a void
## answer must not be mistaken for a refusal, or every status in the game would be
## refused by a shape nobody chose.
static func _accepted(answer: Variant) -> bool:
	if answer is Dictionary:
		return not (answer as Dictionary).has(&"ok") or bool((answer as Dictionary)[&"ok"])
	return true


## A refusal reason as a `String`, for the primitives-only result. Anything that is not
## a name becomes the generic one.
static func _reason_of(answer: Variant) -> String:
	if answer is Dictionary:
		var reason: Variant = (answer as Dictionary).get(&"reason", &"")
		if reason is String or reason is StringName:
			return String(reason)
	return String(REFUSE_UNWRITABLE)


## One stat id built from an authored prefix, matching `QiDamage._suffixed` exactly so
## the two stages cannot spell the same stat two ways.
static func _suffixed(prefix: String, element: StringName) -> StringName:
	return StringName((prefix if prefix is String else "") + String(element))


static func _refused(reason: StringName, extra: Dictionary = {}) -> Dictionary:
	var out := {APPLIED: false, REFUSED: reason}
	for key in extra.keys():
		out[key] = extra[key]
	return out


## The derived value of `id` on `actor`, or 0.0. Total, for `CombatSpine._stat`'s
## reason: S12 runs on a hit that has already mutated both actors, so it must not be
## the stage that crashes on a half-built one.
static func _stat(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)


## A `Variant` as a finite float, or 0.0. A `bool` is deliberately not a number: `true`
## as a chance would silently read 1.0 and apply every status.
static func _number(value: Variant) -> float:
	if value is float or value is int:
		return _finite(float(value))
	return 0.0


static func _id_of(value: Variant) -> StringName:
	return StringName(value) if value is StringName or value is String else &""


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
