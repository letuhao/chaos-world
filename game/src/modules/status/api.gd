class_name StatusApi
extends RefCounted

## Public facade for the `status` module (ADR 0090).
## Other modules may reference ONLY this file (`api.gd`).
##
## The module is three things and nothing else: the authored catalogue
## (`StatusDef` `.tres` content under `res://data/statuses/`), the resolution of a
## live `StatusEffect` against its def, and the ONE tick loop ADR 0089 mandates. It
## owns no damage formula and no stat composition: a status is data, and this module
## is where data becomes `StatModifier`s through the existing modifier pipeline.
##
## ## `tick_statuses` is the production caller ADR 0089 exists for
##
## Measured 2026-10-02, `Actor.tick_statuses` had ZERO callers outside
## `tests/core/test_actor_statuses.gd:18,26`, so no DoT could tick, no status could
## expire, and ADR 0075's environment hazard had nothing to ride. `app/status_loop.gd`
## calls [method tick_statuses] once per frame from the `InputHandler.tick` that
## already drives the frame — one caller, one clock, no second loop.
##
## ## Statuses stay SESSION-ONLY
##
## ADR 0089: no `statuses` key in `Actor.to_dict()`, statuses never moved the schema
## version themselves, and `module_data` is refused as a home just as firmly as a schema
## slot. A status written into a payload would let a designer retune silently rewrite an
## old save, and a status has no def id to rehydrate from. So the live-resolution records
## live in a `WeakRef` table inside [code]StatusRuntime[/code], never on the actor, and
## nothing this module writes is reachable from `to_dict()`. Later bumps (ADR 0140, for
## wounds) are not this module's, and do not reach it.
##
## ## The tenth public method is [method cleanse], and its trigger FIRED
##
## ADR 0107 deferred the verb until "the first authored CONSUMABLE that answers a
## mitigation lever" existed, then restated that as a greppable predicate: a `.tres`
## under `game/data/items` carrying `subcategory = "pill"` AND a non-empty
## `cleanse_lever` field whose id is a member of [member StatusDef.LEVERS]. The census
## behind that deferral found 237 pills and **0** of them carrying a lever.
##
## `data/items/consumable/cleansing_jade_pill.tres` is the first that does, so the verb
## is built in the same change and `items` gains `status` in `registry.json` — which is
## exactly what ADR 0107 said would happen and when. Ten public methods, under
## `MAX_FACADE_PUBLIC_METHODS = 12`.
##
## ## The vocabulary is spent, not extended
##
## `mitigation_tags` is still the ONE purge vocabulary. `cleanse` takes one lever in and
## reads `mitigation_tags` out; it introduces no percentage, no strength roll and no
## second dialect. `EnvironmentField._lever_for` already read the same field to CHOOSE a
## mitigation at apply time, so this is the vocabulary's second reader and not a new one.
##
## ## The ELEVENTH public method is [method resolve], and it is the one that makes a
## ## caller-BUILT status pay
##
## Measured 2026-10-04: a hazard status landed with `actor.add_status` — ADR 0075's
## environment zones (`modules/domain/environment_field.gd:405`) and ADR 0073's traps
## (`modules/domain/domain_fixtures.gd:403`) — never reached a `StatusRuntime` record,
## because only [method apply] and [method apply_cultivation] build one
## (`api.gd:100-104`, `:218-222`). `tick_statuses` skips any status whose record is absent
## (`api.gd:136-141`), so a furnace and a trap aged out and paid nothing: the status was on
## the actor, `has_status` answered true, and no health moved. Every caller had done the
## work `apply` exists to do — resolved a magnitude, a cadence, a stacking mode and the
## zone's own levers — and none of it was reachable, because building the `StatusEffect`
## by hand and REGISTERING it are two different acts.
##
## ## Why `apply` and `apply_cultivation` cannot express this
##
## Both build the effect themselves through [method _effect_for], which resolves a def's
## `magnitude`, `tick_interval`, `mitigation_tags`, `scope` and `stacking`. A zone and a
## trap do not have those numbers: `domain` declares `core` + `contracts` only and authors
## its own hazard def under `res://src/data/statuses/` (`environment_field.gd:286`), and
## a trap carries a fixture's own `damage_share`. Routing either through `apply` would
## hand it a pulse that spends `magnitude * share_per_pulse` off the def and discard the
## strength this game resolved for this actor — and `apply` additionally REFUSES a
## COMBAT-scope def through `apply_cultivation`, which `fire_immolation` (a trap's own
## authored status) is. Neither verb can express "keep the instance the caller built, and
## give it the runtime it needs to pulse".
##
## ## What it does and does NOT do
##
## It registers exactly one runtime record for the LIVE instance carrying
## `effect.id` — the one [method _runtime] already keyed by id — and re-derives that
## instance's strength from its own `magnitude`, because REFRESH keeps the STRONGER of
## the two (`core/status_registry.gd:151`): a re-application resolved weaker must lower
## the pulse, which is the rule `EnvironmentField.apply` already honours by hand
## (`environment_field.gd:402-403`). It never adds a status to the actor, never ages one,
## never spends a pool and runs no loop of its own: the caller still calls
## [method apply] or `Actor.add_status`, and the ONE tick loop ADR 0089 mandates is still
## this module's. Returns the same `{ok, id, magnitude, duration}` shape the two apply
## verbs answer with, so a caller reads one shape either way.
##
## ## TWO TREES, and `status_ids` is still the closed twenty
##
## `StatusCatalog` reads two content roots through one loader and one gate. The first
## (`res://data/statuses`) is the twenty element-riding statuses a landed blow can
## inflict, and [method status_ids] answers exactly those and nothing else. The second
## ([constant StatusCatalog.AMBIENT_SOURCES_ROOT], `res://src/data/statuses`) holds
## statuses inflicted by a PLACE — ADR 0075's `env_scourge`, which `domain` authors
## because it owns the hazard — and is reached through [method StatusApi.resolve] and
## [method apply_cultivation] only.
##
## They are separate because the two questions are separate: "what does this blow
## inflict" has a pinned answer of twenty, and "what does standing in this do" has no
## such bound. Folding the hazard into the first would have made a landed `fire` blow
## able to inflict `env_scourge`, which is a lie the game would then act on. Folding the
## catalogue into the second would have emptied [method status_ids] of its claim.

# --- Catalogue ---------------------------------------------------------------

## The most channel pulses ONE status may spend in a single [method tick_statuses]
## call. Far above what a real frame delta owes: the authored cadences are whole
## seconds and a frame is a fraction of one, so the ceiling is there to be
## UNREACHABLE rather than to be a budget — and a caller that reaches it is told so
## through the answer's `truncated` key instead of silently under-paying.
##
## ## Why a fixed number and not the caller's delta
##
## The bound is read here, never derived from the accumulator the loop below drains: a
## loop whose count is the value its own body reduces is the shape that reached 67 GB
## resident (INC-0002), and `tests/arch_rules/test_no_unbounded_wait.gd` exists because
## that judgement shipped. 64 pulses is 128 seconds at the slowest authored cadence
## (`water_deluge`, 2.0s), which no frame delta reaches.
const PULSES_PER_FRAME := 64


## Every authored status id, canonically ordered.
static func status_ids() -> Array[StringName]:
	return StatusCatalog.instance().status_ids()


## One authored definition, or null. Refused content (a tier-2 element, an empty
## `mitigation_tags`, a FLAT on a rate stat) is null, never a broken def.
static func definition(status_id: StringName) -> StatusDef:
	return StatusCatalog.instance().definition(status_id)


static func has_status(status_id: StringName) -> bool:
	return StatusCatalog.instance().has(status_id)


## `{ok, id, ...}`: apply a status by id, resolving its def and magnitude and
## holding the result as `StatModifier`s under `status:<id>`.
##
## `magnitude` is the POTENCY, not the damage: the caller derives it from the
## elemental term the hit landed (`element_power_<e>`, ADR 0088), so this module
## never invents a damage number. A missing `magnitude` means 1.0 rather than a
## refusal, because a status whose source has no elemental affinity is still a
## status and 0.0 would silently make it inert.
##
## Re-application follows ADR 0086's declared `Stacking`: `refresh` takes the longer
## duration and the stronger magnitude, `stack` adds into `magnitude_cap`, `replace`
## overwrites both. Returns the refusals by reason so a caller can report them.
##
## `grant_id` is the caller's own handle for this application (ADR 0902, P5): it rides
## the effect so [method clear_grant] can reach every instance ONE grant wrote. Empty
## is the shipped callers' shape, so a grant-less call reproduces the old numbers.
static func apply(
	actor: Actor,
	status_id: StringName,
	magnitude: float = 1.0,
	duration: float = -1.0,
	grant_id: StringName = &""
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var def := StatusCatalog.instance().definition(status_id)
	if def == null:
		# ADR 0902 (P5): a REFUSED application is a fact worth naming, and there is a
		# host here — somebody the unknown id failed to land on.
		StatusEvents.note_resisted(actor.id, status_id, &"unknown_status")
		return {"ok": false, "reason": "unknown_status", "id": String(status_id)}
	var resolved := minf(maxf(magnitude, 0.0), def.magnitude_cap)
	var life := def.duration if duration < 0.0 else duration
	# ADR 0902 (P4): the lockout is checked BEFORE the effect lands, so a refused
	# re-application leaves the live instance untouched.
	if _icd_refusal(actor, def):
		StatusEvents.note_resisted(actor.id, def.id, &"status_icd")
		return {"ok": false, "reason": "status_icd", "id": String(def.id)}
	# `Actor.add_status` is ADR 0086's apply path. Its return type is in flight (it
	# answers `void` today and a result dict under the ADR), so the OUTCOME is
	# observed rather than a return value captured: discarding a return value is
	# legal in GDScript whether or not there is one, and `has_status` is the
	# contract both shapes agree on. That also makes a refusal observable without
	# a second code path per shape.
	var answer := actor.add_status(_effect_for(def, resolved, life, grant_id))
	var held := _effect_by_instance(actor, int(answer.get(StatusRegistry.INSTANCE, 0)))
	if not bool(answer.get(&"ok", false)) or held == null:
		StatusEvents.note_resisted(
			actor.id, def.id, &"refused_by_actor", StringName(answer.get(&"reason", &""))
		)
		return {"ok": false, "reason": "refused_by_actor", "id": String(def.id)}
	# The merge decided WHICH instance survives (ADR 0902, P3); the runtime binds
	# to that instance, not to the id, so a `coexist` pair keeps two records.
	var runtime := _bind_runtime(actor, def, held)
	StatusRuntime.apply_modifiers(actor, runtime)
	_reconcile(actor)
	# A BURST spends itself at the moment of arrival (water_deluge): it damages
	# exactly once and leaves no modifier behind to be rebuilt later.
	if bool(def.payload.get("spends_on_apply", false)):
		_pulse(actor, runtime)
	# ADR 0902 (P5): the completed fact, announced after the modifiers are on the
	# actor — a subscriber reacting to it can never observe a half-written status.
	StatusEvents.note_applied(actor.id, def.id, held.instance_id, grant_id)
	return {
		"ok": true,
		"id": String(def.id),
		"instance_id": held.instance_id,
		"grant": String(grant_id),
		"magnitude": resolved,
		"duration": life,
		"mechanic": String(def.mechanic()),
	}


## The production tick (ADR 0089). Advances every live status by `delta`: the
## DoT/amplifier channel fires on its own interval, and `Actor.tick_statuses` ages
## and expires the rest. Returns `{ticked, damage, expired}` so a caller can read
## what the frame did without inspecting the actor.
##
## Ordering is load-bearing: the channels fire BEFORE the age pass, so a status that
## expires on this frame still spends its last pulse. A status that expired on the
## previous frame is already gone from the actor's array.
##
## ONE channel pulse per call, and why the loop below is bounded the way it is
##
## `StatusRegistry._pulses_due` owes one entry per interval a hitched frame crossed, so
## `core` already pays per pulse; what the old shape here did NOT was drain the whole
## accumulator, and it read `ticks_elapsed` for the escalating burn's curve BEFORE the
## increment. A long delta therefore paid ONE pulse of a stale curve and then threw the
## rest of the accumulator away — measured on ADR 0075's furnace, one `delta = 8.0` for
## an 8s status at a 2s cadence: `0.02163` spent where `0.0903` was owed, one pulse of
## four. The escalation was compounding one step per FRAME rather than one step per
## PULSE, which is the opposite of what `escalation_per_tick` names.
##
## So the accumulator is DRAINED here, and the bound is not a guess: `PULSES_PER_FRAME`
## is far above the most a real frame delta can owe, and a caller that genuinely needed
## more is answered by `truncated` rather than by a longer loop. The alternative —
## repeating this whole function until the accumulator clears — would be a `while` whose
## exit condition a status can refuse to meet, which is the shape ADR 0002's loop rules
## and `test_no_unbounded_wait.gd` exist to catch.
static func tick_statuses(actor: Actor, delta: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "ticked": 0, "damage": 0.0, "expired": 0}
	var before := _live_instances(actor)
	var runtimes := _runtime(actor)
	var damage := 0.0
	var ticks := 0
	var truncated := 0
	for status in actor.statuses:
		var runtime := runtimes.get(status.instance_id) as StatusRuntime
		if runtime == null:
			# A status this module did not author (tribulation's blessing, a
			# pregnancy stage machine) still ages through `Actor.tick_statuses`
			# below. It contributes no channel here rather than being mis-resolved
			# against a def that is not its own.
			continue
		# A BURST spends itself AT ARRIVAL (`apply` called `_pulse` once) and never again.
		# The guard lives HERE rather than inside `_pulse` because `_pulse` is also the
		# arrival path: suppressing by kind there stopped the wave landing at all, while
		# suppressing here leaves the one legitimate spend intact and removes only the
		# re-spend that made one wave land twice. `spends_on_apply` is the authored
		# statement of that intent. It is checked BEFORE the accumulator is drained, so a
		# burst's leftover elapsed time is not spent either.
		if runtime.def.kind == &"burst" and bool(runtime.def.payload.get("spends_on_apply", false)):
			continue
		var interval := maxf(0.001, runtime.def.tick_interval)
		runtime.tick_elapsed += delta
		# The ICD clock is real time, not the pulse cadence (ADR 0902, P4).
		runtime.icd_elapsed += delta
		# Bounded `for` over a count read from a FIXED cap, never a `while` on the
		# accumulator: a loop whose bound is the value its own body drains is the shape
		# that reached 67 GB (INC-0002). `owed` is snapshotted from the accumulator
		# before the first pulse, and the `>=` comparison is what drains a remainder
		# smaller than one interval to nothing rather than leaving it owed.
		var owed := int(floor(runtime.tick_elapsed / interval))
		if owed > PULSES_PER_FRAME:
			truncated += owed - PULSES_PER_FRAME
			owed = PULSES_PER_FRAME
		for _pulse in owed:
			runtime.tick_elapsed -= interval
			runtime.ticks_elapsed += 1
			ticks += 1
			damage += _pulse(actor, runtime)
	actor.tick_statuses(delta)
	var expired := _count_lost(before, _live_instances(actor))
	_reconcile(actor)
	var answer := {"ok": true, "ticked": ticks, "damage": damage, "expired": expired}
	if truncated > 0:
		answer["truncated"] = truncated
	return answer


## Apply a CULTIVATION-scope status: a permanent blessing the game PAYS OUT rather than
## one a landed blow inflicts.
##
## ## Why this is a separate verb and not `apply` with a different argument
##
## `apply` is COMBAT's verb. Its potency is deliberately the elemental term the hit landed
## (`element_power_<e>`, ADR 0088), and its only production caller
## (`modules/combat/exchange.gd`) can only ever ask `status_for_element`, which by ADR 0105
## answers an `on_landed_blow` id — and every such id is COMBAT scope. So `apply` cannot
## reach a CULTIVATION def even in principle: three authored defs (`earth_bulwark`,
## `light_halo`, `wood_bloom`, all `duration = -1.0`) had no producer and were unreachable by
## ANY path. A second `apply` with a flag would either let a caller pass a cultivation id
## through the combat verb — erasing the scope boundary this module exists to keep — or
## branch internally on the same question twice.
##
## ## What a caller must supply instead of an elemental term
##
## There is no hit, so there is no elemental term to read, and potency cannot be invented
## here: ADR 0088's rule is that a module never invents a damage number. So `magnitude`
## stays the CALLER'S potency — the same contract `apply` has, one layer up — and defaults
## to `1.0`, which is exactly a full-strength blessing because these defs author
## `magnitude_cap = 1.0` and their modifiers are per unit of magnitude
## (`StatusRuntime.build_modifiers`).
##
## ## Why CULTIVATION scope is REFUSED here
##
## The refusal is the load-bearing half and it is what keeps the boundary from eroding one
## call at a time: this verb applies the SCOPE it is named for and nothing else. A COMBAT
## def routed here would install a debuff through the blessing path, where
## [method clear_combat_scope] does not reach it and `StatusApply`'s `status_defense`
## gate was never drawn. A COMBAT status belongs to [method apply], which is reached from
## the blow that inflicts it.
##
## ## Why permanence is NOT forced
##
## `duration` is honoured exactly as `apply` honours it, and the def's own `duration` is
## what a caller gets by default. A CULTIVATION def authoring `DURATION_FOREVER` (`-1.0`)
## is a permanent blessing that survives combat exit — ADR 0089's purge rule clears COMBAT
## scope and never touches this — and that is authored content, not a rule restated here.
##
## ## `apply` is NOT widened, and `apply_cultivation` is
##
## The two verbs reach different trees on purpose. `apply` is the landed-blow verb and
## stays on the catalogue, because an AMBIENT def can never be what a blow inflicts —
## `StatusCatalog` refuses `on_landed_blow` on an ambient def at load
## (`_admit_ambient`), so nothing this verb resolved could name one. `apply_cultivation`
## resolves from EITHER tree, because its remit is by SCOPE rather than by source: it
## applies a CULTIVATION-scope status the game does not inflict with a blow, and an ADR
## 0075 hazard is exactly that — `env_scourge` authors `scope = cultivation` for the
## reason [method EnvironmentField._hazard]'s comment gives. Before this change the
## hazard was refused here by name too, so the verb this scope claims to hold could not
## reach the only content that uses the scope, which is what made the hazard cost nothing.
static func apply_cultivation(
	actor: Actor,
	status_id: StringName,
	magnitude: float = 1.0,
	duration: float = -1.0,
	grant_id: StringName = &""
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var def := StatusCatalog.instance().any_definition(status_id)
	if def == null:
		StatusEvents.note_resisted(actor.id, status_id, &"unknown_status")
		return {"ok": false, "reason": "unknown_status", "id": String(status_id)}
	# NOT logged: naming a COMBAT def here is a caller bug, not the defender's answer.
	if def.is_combat_scope():
		return {"ok": false, "reason": "not_cultivation_scope", "id": String(def.id)}
	var resolved := minf(maxf(magnitude, 0.0), def.magnitude_cap)
	var life := def.duration if duration < 0.0 else duration
	# ADR 0902 (P4): the lockout is checked BEFORE the effect lands, so a refused
	# re-application leaves the live instance untouched.
	if _icd_refusal(actor, def):
		StatusEvents.note_resisted(actor.id, def.id, &"status_icd")
		return {"ok": false, "reason": "status_icd", "id": String(def.id)}
	var answer := actor.add_status(_effect_for(def, resolved, life, grant_id))
	var held := _effect_by_instance(actor, int(answer.get(StatusRegistry.INSTANCE, 0)))
	if not bool(answer.get(&"ok", false)) or held == null:
		StatusEvents.note_resisted(
			actor.id, def.id, &"refused_by_actor", StringName(answer.get(&"reason", &""))
		)
		return {"ok": false, "reason": "refused_by_actor", "id": String(def.id)}
	# The merge decided WHICH instance survives (ADR 0902, P3); the runtime binds
	# to that instance, not to the id, so a `coexist` pair keeps two records.
	var runtime := _bind_runtime(actor, def, held)
	StatusRuntime.apply_modifiers(actor, runtime)
	_reconcile(actor)
	# ADR 0902 (P5): the completed fact, in the same spelling as [method apply]'s.
	StatusEvents.note_applied(actor.id, def.id, held.instance_id, grant_id)
	return {
		"ok": true,
		"id": String(def.id),
		"instance_id": held.instance_id,
		"grant": String(grant_id),
		"magnitude": resolved,
		"duration": life,
		"permanent": def.is_permanent(),
		"mechanic": String(def.mechanic()),
	}


## Register the `StatusEffect` a CALLER built — an ADR 0075 environment zone, an
## ADR 0073 trap — so it actually pays under [method tick_statuses]. Returns the same
## `{ok, id, magnitude, duration}` shape [method apply] answers with.
##
## ## What the caller has already done, and what it has not
##
## The caller resolved a magnitude against THIS actor's mitigation, an authored cadence,
## a stacking mode and the zone's or fixture's own levers, and handed the result to
## `Actor.add_status`. That is every field [method tick_statuses] reads — and none of it
## is reachable, because the tick path reads a [code]StatusRuntime[/code] record keyed by
## id, not the effect on the actor. This method is the half that was missing: it resolves
## the authored def and writes that one record, and the existing tick loop does the rest.
##
## ## Why the magnitude is re-derived rather than taken from `effect`
##
## A REFRESH merge keeps the STRONGER of the held and incoming magnitudes
## (`core/status_registry.gd:151`), so the LIVE instance is the honest number to read
## back, not the one this call arrived with: a weaker re-application of a hazard must
## lower the pulse it will pay, which is the rule `EnvironmentField.apply` honours by
## hand at its own refresh branch. `magnitude_cap` still bounds it, so a caller cannot
## raise what a def says is the ceiling.
##
## ## Refusals, in this module's existing vocabulary
##
## `{reason = "no_effect"}` is a caller that built nothing, `{reason = "empty_id"}` one
## that built a nameless status, and `{reason = "def_not_on_actor"}` one whose instance
## the actor REFUSED — three different faults, all named, and none of them a silent
## return. The last is the load-bearing half: it is answered by reading the actor rather
## than by trusting the caller, so a rejected status is never left with a live record
## that pulses nothing.
##
## ## The def is resolved from EITHER tree, and that is what makes a hazard pay
##
## `any_definition` rather than `definition`, so an AMBIENT def resolves here as
## readily as a catalogue one. Measured before this change: `env_scourge` — authored by
## `domain` under `res://src/data/statuses`, because `res://data/statuses` is a closed
## twenty whose id set another suite pins and whose every member rides an element — was
## refused here by name (`unknown_status`), and so was `apply_cultivation`, because both
## verbs looked it up in the element-riding tree. The hazard sat on the actor,
## `has_status` answered true, and `tick_statuses` skipped it: a furnace that cost
## nothing. `StatusCatalog.AMBIENT_SOURCES_ROOT` is the second tree, read by the same
## loader and the same `StatusDef.problems()` gate, and the twenty is untouched.
static func resolve(actor: Actor, effect: StatusEffect) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if effect == null:
		return {"ok": false, "reason": "no_effect"}
	if effect.id == &"":
		return {"ok": false, "reason": "empty_id"}
	var def := StatusCatalog.instance().any_definition(effect.id)
	if def == null:
		return {"ok": false, "reason": "unknown_status", "id": String(effect.id)}
	var live := _live(actor, effect.id)
	if live == null:
		return {"ok": false, "reason": "def_not_on_actor", "id": String(effect.id)}
	var runtime := _bind_runtime(actor, def, live)
	runtime.magnitude = minf(maxf(live.magnitude, 0.0), def.magnitude_cap)
	StatusRuntime.apply_modifiers(actor, runtime)
	return {
		"ok": true,
		"id": String(effect.id),
		"magnitude": runtime.magnitude,
		"duration": live.remaining,
		"mechanic": String(def.mechanic()),
	}


## The COMBAT-scope statuses are cleared on combat exit by the same caller that ticks
## them (ADR 0089); CULTIVATION-scope statuses are never purged by combat state.
## Returns the ids that were cleared.
##
## ## `clear_combat_scope` is not the cleanse and is not renamed (ADR 0107)
##
## `clear_combat_scope` is a combat-lifecycle fact — combat exit happened, so every
## COMBAT-scope status goes. `cleanse` is a player action against ONE authored lever.
## Two verbs, two meanings. Conflating them would let a combat exit silently answer a
## poison pill, which is precisely the bug this module exists to avoid.
static func clear_combat_scope(actor: Actor) -> Array[String]:
	if actor == null:
		return []
	var cleared: Array[String] = []
	var runtimes := _runtime(actor)
	for status in actor.statuses:
		var runtime := runtimes.get(status.instance_id) as StatusRuntime
		if runtime == null or not runtime.def.is_combat_scope():
			continue
		StatusRuntime.clear_source(actor, runtime.source)
		cleared.append(String(runtime.def.id))
	_purge(actor, cleared)
	return cleared


## ## The ONE removal verb ADR 0107 deferred, built because its trigger FIRED
##
## Removes every live status whose authored `mitigation_tags` contains `lever`,
## releasing its modifiers through the same `_purge` path `clear_combat_scope` uses.
## One lever in, `mitigation_tags` out: there is no percentage, no strength and no
## second purge dialect, so the vocabulary that ADR 0086 made "the ONE purge vocabulary"
## is finally the one a verb spends.
##
## ## Why this is nine-and-thirty methods and not a spare tenth
##
## The trigger was a predicate, not a phrase, and the predicate is now TRUE: an
## authored pill under `game/data/items` carries `subcategory = pill` AND a non-empty
## `cleanse_lever` whose id is a member of `StatusDef.LEVERS`
## (`data/items/consumable/cleansing_jade_pill.tres`). Before that pill existed, this
## method would have been the ADR 0089 defect class — a public verb whose only caller is
## its own test — and ADR 0107 was right to defer it. The consumer arriving is what
## makes the verb real, and that ordering is the whole point of the deferral.
##
## ## SCOPE is NOT filtered, and that is deliberate
##
## `clear_combat_scope` is a combat-exit fact. A cleanse is not: a pill that answers
## `pill` removes what the pill names, and a CULTIVATION-scope status that names `pill`
## has published that it can be answered. Filtering by scope here would give the player
## a pill that silently does nothing to the blessing they are looking at, which is the
## "read model advertising counterplay the game cannot deliver" defect ADR 0086's
## `mitigation_tags` exists to prevent. What the authored tag set says is what happens.
##
## ## Refusals are NAMED, in this module's existing vocabulary
##
## `apply` returns `{ok, id, reason}` and this matches it, because a caller that spends a
## real pill needs to tell "you were not afflicted" from "that is not a lever this game
## has" — and both from a bug. `{reason = "unknown_lever"}` names the second and the
## list is the closed `StatusDef.LEVERS` set, so a typo is a refusal rather than a
## cleanse that changes nothing and says nothing.
static func cleanse(actor: Actor, lever: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "lever": String(lever), "reason": "no_actor"}
	var named := String(lever)
	if not StatusDef.LEVERS.has(lever):
		return {"ok": false, "lever": named, "reason": "unknown_lever"}
	# Bounded `for` over the actor's live status list, which `tick_statuses` prunes. A
	# status this module did not author carries no `StatusDef`, so it has no authored
	# `mitigation_tags` to match and is simply never removed: guessing at a foreign
	# status's lever set is how a cleanse would start eating somebody else's state.
	var runtimes := _runtime(actor)
	var cleared: Array[String] = []
	for status in actor.statuses:
		var runtime := runtimes.get(status.instance_id) as StatusRuntime
		if runtime == null or not runtime.def.mitigation_tags.has(lever):
			continue
		StatusRuntime.clear_source(actor, runtime.source)
		cleared.append(String(runtime.def.id))
	_purge(actor, cleared)
	return {
		"ok": true,
		"lever": named,
		"cleared": cleared,
		"count": cleared.size(),
	}


## ## `clear_grant` — every instance ONE grant wrote (ADR 0902, P5)
##
## The Keepverse `ClearGrant` shape: a grant is an opaque caller-owned handle, and a
## ladder that re-projects a stage withdraws its PREVIOUS grant before writing the
## replacement so a stage change never stacks (their `StatusProjectionHost`). This is
## that verb, scoped to the actor that holds the instances.
##
## ## Why the sweep is INSTANCE-keyed and not id-keyed
##
## `coexist` (P3) makes two live instances of one id legal, and the Keepverse model
## withdraws them independently (`StatusDerivedModReader`: "two coexisting stacks of
## the same status withdraw independently"). `_purge` removes by ID and would take a
## sibling under another grant; this collects the matching INSTANCES and erases
## exactly those.
##
## Only module-tracked instances are cleared: a status this module did not author
## carries no runtime record, and reaching into it would be a purge of somebody
## else's state (the same rule [method cleanse] documents).
static func clear_grant(actor: Actor, grant_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "grant": String(grant_id), "reason": "no_actor"}
	if grant_id == &"":
		return {"ok": false, "grant": "", "reason": "empty_grant"}
	var store := _runtime(actor)
	var cleared: Array[String] = []
	var instances: Array[int] = []
	for status in actor.statuses:
		if status.grant_id != grant_id:
			continue
		if store.get(status.instance_id) == null:
			continue
		cleared.append(String(status.id))
		instances.append(status.instance_id)
	_purge_instances(actor, instances)
	# ADR 0902 (P6=C): the grant's counters go with its instances — the Keepverse
	# `ClearGrant` prefix sweep, so a re-projected grant starts from zero.
	StatusCounters.clear_grant(actor, grant_id)
	return {"ok": true, "grant": String(grant_id), "cleared": cleared, "count": cleared.size()}


## ## `withdraw` — the host left (ADR 0902, P5)
##
## The Keepverse `WithdrawEntity(hostPtr)` shape: a host that dies or leaves mid-life
## takes ITS instances with it, in every scope, because none of them has a host left
## to act through. Distinct from [method clear_combat_scope] (a combat-exit fact) and
## from [method cleanse] (one authored lever): this verb answers "this actor is gone",
## which is why it neither filters by scope nor reads a tag.
##
## `StatusRuntime.forget` follows the sweep: the resolution table is per-actor state,
## and a reused actor must not read a dead instance's magnitude or ICD clock.
static func withdraw(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var store := _runtime(actor)
	var cleared: Array[String] = []
	var instances: Array[int] = []
	for status in actor.statuses:
		if store.get(status.instance_id) == null:
			continue
		cleared.append(String(status.id))
		instances.append(status.instance_id)
	_purge_instances(actor, instances)
	StatusRuntime.forget(actor)
	# ADR 0902 (P6=C): the host's counters leave with its instances.
	StatusCounters.forget(actor)
	return {"ok": true, "cleared": cleared, "count": cleared.size()}


## Remove the statuses carrying `instances`, in place, and let the same reconcile
## every other purge runs release their records and modifiers. INSTANCE-keyed where
## [method _purge] is id-keyed (ADR 0902, P3), because `coexist` siblings share an id.
static func _purge_instances(actor: Actor, instances: Array[int]) -> void:
	for index in range(actor.statuses.size() - 1, -1, -1):
		if instances.has(actor.statuses[index].instance_id):
			actor.statuses.remove_at(index)
	_reconcile(actor)
	actor.mark_stats_dirty()


## ## `record_counter_hit` / `record_instance_hit` — the two key spaces (ADR 0902, P6=C)
##
## The Keepverse `RecordCounterHit` shape: the CALLER brings the key and the threshold
## config, and the call answers whether a burst threshold was reached. `every_hits <= 0`
## and an empty grant are refused (`false`) rather than counted against nothing.
##
## The per-instance spelling keys by the handle `StatusRegistry` minted, so two
## `coexist` instances of one id count independently — the same identity rule the
## instance-keyed store already follows.
static func record_counter_hit(
	actor: Actor,
	grant_id: StringName,
	scope_key: StringName,
	every_hits: int,
	reset_on_burst: bool,
	hits: int = 1
) -> bool:
	if actor == null or grant_id == &"":
		return false
	return StatusCounters.record(
		actor, StatusCounters.grant_key(grant_id, scope_key), every_hits, reset_on_burst, hits
	)


static func record_instance_hit(
	actor: Actor, instance_id: int, every_hits: int, reset_on_burst: bool, hits: int = 1
) -> bool:
	if instance_id <= 0:
		return false
	return StatusCounters.record(actor, instance_id, every_hits, reset_on_burst, hits)


## Both counter key spaces, as copies (ADR 0902, P6/P13 readback).
static func counter_snapshot(actor: Actor) -> Dictionary:
	return StatusCounters.snapshot(actor)


## ## `record_landed_blow` — the landed-blow firing (ADR 0902, P6=C)
##
## Called with the `status_application` row the spine's S12 filed on a landed outcome
## (`StatusApply.record`'s flattened entry) — `CombatBoot.resolve_hit` is the caller.
## A def that authors a counter under its payload advances here:
##
##     payload.counter = {every_hits: int, reset_on_burst: bool, space: "instance"|"grant", scope: name}
##
## and a def that authors none is a no-op — every shipped def today, so the funnel
## call is byte-identical for the shipped content and the wiring is what makes a
## future authored counter live.
##
## `space` names the key space: `"instance"` (the default) keys by the row's minted
## handle — or, for an `already_held` row that carries none, by the LIVE instance the
## id names, so "every N hits while this status is up" is real. `"grant"` keys by the
## row's grant plus the config's `scope`. ONE hit per landed blow; a caller merging N
## blows advances N through [method record_counter_hit].
static func record_landed_blow(host: Actor, entry: Dictionary) -> bool:
	if host == null or entry.is_empty():
		return false
	# ADR 0902 (P6=C): a row that NAMES a status counts — an `already_held` refusal is
	# still a landed blow carrying the status; one naming nothing is not this verb's.
	var status_id := StringName(entry.get("status_id", &""))
	if status_id == &"":
		return false
	var def := StatusCatalog.instance().any_definition(status_id)
	if def == null:
		return false
	var config: Variant = def.payload.get("counter", {})
	if not (config is Dictionary) or (config as Dictionary).is_empty():
		return false
	var counter := config as Dictionary
	var every_hits := int(counter.get("every_hits", 0))
	var reset_on_burst := bool(counter.get("reset_on_burst", true))
	if String(counter.get("space", "instance")) == "grant":
		return record_counter_hit(
			host,
			StringName(entry.get("grant_id", &"")),
			StringName(counter.get("scope", &"")),
			every_hits,
			reset_on_burst
		)
	var instance_id := int(entry.get("instance_id", 0))
	if instance_id <= 0:
		# No fresh handle: advance the LIVE instance the id names. The first match is
		# unique for every stacking except `coexist`, which this docblock names.
		instance_id = _live_instance_for(host, status_id)
	return record_instance_hit(host, instance_id, every_hits, reset_on_burst)


## The element→status mapping of ADR 0105: the id whose def claims
## [member StatusDef.on_landed_blow] on `element`, or `&""` when nothing does.
##
## ## Why this lives in `status`, and not in the caller
##
## The catalogue IS `status`'s content (ADR 0090), so the element→status relation is a
## question about content and belongs beside it. A copy authored in `techniques` or
## `combat` would be a second file describing the same ten `.tres`, free to drift from
## them and invisible to `StatusDef.problems()` — which is exactly the "one family read
## and nine siblings unread" defect class ADR 0088 declines to pay for. `TechniqueDef`
## gains no field for the same reason ADR 0105 gives: the element is already the carrier.
##
## ## Why the SELECTOR is authored rather than derived from `StatusDef.element`
##
## Every tier-1 element ships TWO statuses, so "the element's status" is a choice, and
## deriving it means breaking a tie in code — by filename, by catalogue order, by `kind`.
## That is a balance decision disguised as a tie-break, and it moves silently when a third
## status is authored. See `StatusDef.on_landed_blow`.
##
## ## `chance` is the CALLER'S gate, not a second authored number
##
## It is an argument so ADR 0087's `status_chance` keeps exactly one home (the attack,
## as `StatApply` reads it) and ADR 0088's potency keeps exactly one ( `element_power_<e>`).
## A `chance` at or below `0.0` is ADR 0087's CLOSED gate, which spends no draw at all, so
## it is answered here rather than at a roll that will not happen.
##
## ## `&""` is a NORMAL answer, never an error
##
## Four ordinary cases produce it and none of them is a fault: an empty or unknown element
## (a blow carrying no element at all), a tier-2 element (ADR 0090 withholds those statuses
## deliberately), a closed gate, and an element whose defs exist but none claims the slot.
## A caller reads the empty id and applies nothing.
static func status_for_element(element: StringName, chance: float = 1.0) -> StringName:
	return StatusCatalog.instance().status_for_element(element, chance)


## Primitives only, so a screen and a test read the same shape (AGENTS.md's
## testable contract). `{}` when there is no actor or no catalogue row to report.
##
## Rows carry the instance handle, the grant and the def's shape fields (ADR 0902,
## P5/P13), and the top-level `resisted` list is the bus's bounded refusal log — all
## primitives, all readable with no actor.
##
## `ids` is still the closed twenty and `count` its size, because that is the claim
## every consumer of this report is making. The ambient tree is reported beside it under
## `ambient_ids` / `ambient_count`, never folded in: a screen listing "every status this
## game has" must be able to say which of the two a row came from.
static func summary(actor: Actor = null) -> Dictionary:
	var ids := StatusCatalog.instance().status_ids()
	var ambient := StatusCatalog.instance().ambient_ids()
	var report := {
		"count": ids.size(),
		"ids": [],
		"ambient_count": ambient.size(),
		"ambient_ids": [],
		"active": [],
		"rejected": [],
		"resisted": StatusEvents.shared().resisted_log(),
		"counters": {},
	}
	for status_id in ids:
		(report["ids"] as Array).append(String(status_id))
	for status_id in ambient:
		(report["ambient_ids"] as Array).append(String(status_id))
	for entry in StatusCatalog.instance().rejected():
		(report["rejected"] as Array).append(entry)
	if actor == null:
		return report
	var runtimes := _runtime(actor)
	var active: Array = []
	for status in actor.statuses:
		var runtime := runtimes.get(status.instance_id) as StatusRuntime
		(
			active
			. append(
				{
					"id": String(status.id),
					"known": runtime != null,
					"instance_id": status.instance_id,
					"grant": String(status.grant_id),
					"remaining": status.remaining,
					"permanent": status.is_permanent(),
					"magnitude": 0.0 if runtime == null else runtime.magnitude,
					"ticks_elapsed": 0 if runtime == null else runtime.ticks_elapsed,
					"scope": "" if runtime == null else String(runtime.def.scope),
					"family": "" if runtime == null else String(runtime.def.family),
					"categories": [] if runtime == null else _strings_of(runtime.def.categories),
					"crowd_control": false if runtime == null else runtime.def.crowd_control,
				}
			)
		)
	report["active"] = active
	# ADR 0902 (P6/P13): both counter key spaces, an actor-scoped read.
	report["counters"] = StatusCounters.snapshot(actor)
	return report


# --- the mind-control vocabulary (its own tree, its own contests) ----------------
#
# The closed twenty above are ELEMENT-RIDING: inflicted by a landed blow that names
# an element, resolved through `StatusApply`'s apply chance and resisted by the
# combat gate's `status_defense`. None of that is true of a mind status, which is inflicted
# by a CONFRONTATION, names no element, is resisted by its own contest, and whose
# whole point is that it can never be unavoidable. So the mind vocabulary is a second
# content tree (`res://src/data/mind_statuses`), a second content type
# (`MindStatusDef`) and ONE verb here rather than four.
#
# One verb, not one per role, because the two roles differ in their CURRENCY and not
# in their call shape — a caller says "confront them with this" and gets back either a
# status to apply or a composure meter to spend. A role argument would have been a
# second way to spell the same call, and `MindStatusApi.project` already refuses a
# control id while `impose` refuses an expression one, so the role is validated
# rather than declared.


## ## `mind_confront` — THE mind verb
##
## `{ok, id, class, magnitude, spent, contest | breakdown, ...}`. Runs the contest for
## `status_id` against `target` on behalf of `attacker`, banks one use of mastery
## against `attacker`, and writes whatever the contest left standing.
##
## ## The invariant this verb exists to guarantee
##
## ```
## p_answer = clampf(floor_resist + headroom * p_land, floor_resist, 1)
## ```
##
## `p_answer` is the share of applications the TARGET REFUSES, and it can never fall
## below the def's authored `floor_resist` — at any attacker investment and at any
## realm. That is the owner's rule ("no CC is a contest the target can win, never a
## stun-lock") turned into arithmetic, and it is refused twice over: `MindContest`
## clamps to the floor and `MindStatusDef.problems()` refuses a `floor_resist` of
## `0.0` at load.
##
## ## A RESISTED status still lands, at `potency * spend`
##
## Never as `false` and nothing. A target watching a bar fall to a smaller value has
## been given legible resistance; a target watching nothing happen has been given an
## invisible one, and an invisible resistance cannot be planned against.
##
## ## `rng` is OPTIONAL and its null reading is the DEFENDER's
##
## A deterministic caller is asking for the one answer that consults no randomness
## (ADR 0067). For a contest the conservative reading is the target's: the status
## lands at `floor_resist`-strength spend and is never silently freed. So a null
## generator can never mint a free CC, and can never mint an unanswerable one either.
static func mind_confront(
	attacker: Actor, target: Actor, status_id: StringName, rng: Variant = null
) -> Dictionary:
	if attacker == null or target == null:
		return {
			"ok": false, "reason": String(MindStatusApi.REFUSED_NO_ACTOR), "id": String(status_id)
		}
	var def := MindStatusCatalog.instance().definition(status_id)
	if def == null:
		return {
			"ok": false, "reason": String(MindStatusApi.REFUSED_UNKNOWN), "id": String(status_id)
		}
	if def.role == MindVocabulary.ROLE_CONTROL:
		return MindStatusApi.impose(attacker, target, status_id, rng)
	if def.role == MindVocabulary.ROLE_EXPRESSION:
		return MindStatusApi.project(attacker, target, status_id, rng)
	return {
		"ok": false,
		"reason": String(MindStatusApi.REFUSED_UNKNOWN),
		"id": String(status_id),
		"detail": "a composure is the defender's answer and is never projected",
	}


## ## Why there is no `mind_summary` beside it
##
## This used to publish a second mind verb, `mind_summary`, which delegated to
## `MindStatusApi.summary`. It had ZERO callers in `src/`, `tests/` and `tools/`
## alike, so the thirteen this facade exposed were twelve real methods and one
## delegation nothing asked for. The mind READ model stays where its only reader
## would reach it — `MindStatusApi.summary` — rather than being held on the
## element-riding facade by a verb no screen and no test ever called.
##
## `mind_confront` above STAYS, and the distinction is the whole point: that one is
## the mind path's single production-shaped verb, and both mind suites call it as
## the loop under test.

# --- Internals ---------------------------------------------------------------


## The live `StatusEffect` an authored def resolves to.
##
## ## Why this is more than `StatusEffect.new(id, life)`
##
## ADR 0086 is explicit that the contract is "a tagged, stackable INSTANCE" and ADR 0090
## is explicit that a `StatusDef` "carries exactly the instance fields of ADR 0086 that
## are AUTHORED". So the two halves are one object and this is the seam: a def that
## resolves into a bare `StatusEffect.new(id, life)` throws its authored half away and
## leaves every default, and those defaults are the silent kind — `tick_interval = 0.0`
## is the contract's "plain timer, never pays one" (`contracts/status_effect.gd`), so a
## DoT written that way still ages out, still shows as applied, and spends nothing. A
## `.tres` would have to be a `.tres` that does nothing at all.
##
## Each field is read through the def's own closed vocabulary rather than cast, because a
## def that names something outside it is refused at load (`StatusDef.problems`) and a
## bad cast here would be a second, quieter opinion about the same value.
static func _effect_for(
	def: StatusDef, magnitude: float, life: float, grant_id: StringName = &""
) -> StatusEffect:
	var effect := StatusEffect.new(def.id, life)
	effect.magnitude = magnitude
	effect.magnitude_cap = def.magnitude_cap
	effect.tick_interval = maxf(0.0, def.tick_interval)
	effect.mitigation_tags = def.mitigation_tags.duplicate()
	effect.element = def.element
	effect.scope = (
		StatusEffect.Scope.CULTIVATION
		if def.scope == &"cultivation"
		else (StatusEffect.Scope.COMBAT)
	)
	effect.stacking = _stacking_of(def.stacking)
	effect.kind = _kind_of(def.kind)
	# ADR 0902 (P5): the application's own handle, carried on the effect so a
	# lifecycle sweep can find every instance ONE grant wrote.
	effect.grant_id = grant_id
	return effect


## A def's authored `stacking` as the contract's enum. REFRESH rather than a hard
## failure, because it is the contract's own default and a refactor that left this
## unreadable must not turn every re-application into a refusal.
static func _stacking_of(stacking: StringName) -> StatusEffect.Stacking:
	match stacking:
		&"stack":
			return StatusEffect.Stacking.STACK
		&"replace":
			return StatusEffect.Stacking.REPLACE
		&"coexist":
			return StatusEffect.Stacking.COEXIST
		_:
			return StatusEffect.Stacking.REFRESH


## A def's authored `kind` as the contract's enum, for the same reason as `_stacking_of`.
static func _kind_of(kind: StringName) -> StatusEffect.Kind:
	match kind:
		&"dot":
			return StatusEffect.Kind.DOT
		&"control":
			return StatusEffect.Kind.CONTROL
		&"amplifier":
			return StatusEffect.Kind.AMPLIFIER
		&"burst":
			return StatusEffect.Kind.BURST
		_:
			return StatusEffect.Kind.STAT_MODIFIER


## The per-actor runtime store, delegated to `StatusRuntime` so there is exactly one
## owner of the id-keyed map. ADR 0089 keeps statuses out of the save payload entirely,
## and that works because the store is a `WeakRef` table rather than module data — a
## record parked in `actor.module_data` would put potency, escalation state and authored
## def ids into every save.
static func _runtime(actor: Actor) -> Dictionary:
	return StatusRuntime._runtimes(actor)


## The re-application lockout a def without its own `icd` uses (ADR 0902, P4).
## Pushed from `CombatTuning.status_icd_default` at boot; `0.0` = no ICD. The
## status module owns this because it owns the per-instance clock the check reads.
static var _icd_default: float = 0.0


## Set the fallback ICD. A value, not a dispatch: deterministic and non-interactive.
static func set_icd_default(seconds: float) -> void:
	_icd_default = maxf(0.0, seconds)


## Whether a live same-id instance is still inside its ICD window (ADR 0902, P4).
## A same-id effect with NO runtime record cannot prove it is outside the window,
## so it refuses — the conservative reading, the same way a null rng never mints
## a free CC. Bounded `for` over the actor's list.
static func _icd_refusal(actor: Actor, def: StatusDef) -> bool:
	var icd := def.icd if def.icd > 0.0 else _icd_default
	if icd <= 0.0:
		return false
	var store := _runtime(actor)
	for status in actor.statuses:
		if status.id != def.id:
			continue
		var runtime := store.get(status.instance_id) as StatusRuntime
		if runtime == null or runtime.icd_elapsed < icd:
			return true
	return false


## The live instance handle carrying `status_id` on `actor`, or 0 when none does
## (ADR 0902, P6=C). Bounded `for` over the actor's own list; the FIRST match is
## unique for every stacking except `coexist`, which [method record_landed_blow] names.
static func _live_instance_for(actor: Actor, status_id: StringName) -> int:
	for status in actor.statuses:
		if status.id == status_id:
			return status.instance_id
	return 0


## The live effect carrying `instance_id`, or null (ADR 0902, P3). Bounded
## `for` over the actor's list; the caller only asks with an id it just read
## off an answer, so `0` (not minted) matches nothing in practice.
static func _effect_by_instance(actor: Actor, instance_id: int) -> StatusEffect:
	for status in actor.statuses:
		if status.instance_id == instance_id:
			return status
	return null


## The ONE resolution record of a live instance (ADR 0902, P3): reused across
## merges — refresh and stack mutate the held instance and must NOT mint a
## second record — and created on first appearance. Magnitude and stacks mirror
## the CORE effect, so one number keeps one home.
static func _bind_runtime(actor: Actor, def: StatusDef, held: StatusEffect) -> StatusRuntime:
	var store := _runtime(actor)
	var runtime := store.get(held.instance_id) as StatusRuntime
	if runtime == null:
		runtime = StatusRuntime.new()
		runtime.def = def
		runtime.source = (
			StatusRuntime.source_for_instance(def.id, held.instance_id)
			if def.stacking == &"coexist"
			else StatusRuntime.source_for(def.id)
		)
		store[held.instance_id] = runtime
	runtime.magnitude = held.magnitude
	runtime.stacks = held.stacks
	# The application cleared the window (ADR 0902, P4): elapsed restarts here.
	runtime.icd_elapsed = 0.0
	return runtime


## Sweep every runtime whose instance left the actor's list. Expiry, replace
## and purge all land here, so the sweep lives in ONE place.
static func _reconcile(actor: Actor) -> void:
	_prune(actor, _live_instances(actor))


## One tick channel of one status. Returns the damage it wrote.
##
## `magnitude_unit` names WHICH CHANNEL the status resolves through, and `pool` names
## how much of it is spent — a share of the potency, not an authored damage number.
## So `health_share` spends, `stat_modifier` holds modifiers already computed at apply
## time (ADR 0089: ticking never adds or removes one), and `sibling_amp` contributes
## nothing itself and exists only to feed the burns beside it.
static func _pulse(actor: Actor, runtime: StatusRuntime) -> float:
	if runtime == null or runtime.def == null:
		return 0.0
	var def := runtime.def
	# A BURST spends itself AT ARRIVAL, which is `apply`'s call into this function.
	# It is deliberately NOT suppressed here: suppressing by kind inside `_pulse`
	# blocked the arrival spend too, so `water_deluge` landed nothing at all. The
	# no-respend rule lives in `tick_statuses`, which is the only other caller and
	# the only place "a second spend" is even possible.
	# TWO damage channels, not one. `health_share` is the flat bleed shape; the
	# `element_power` channel is the escalating burn, which resolves its magnitude
	# through the attacker's element power the same way any other qi term does. Both
	# spend; returning early for the second made `fire_immolation` a no-op that
	# still read as "applied", which is the failure this program exists to prevent.
	var spends_health := (
		def.magnitude_unit == &"health_share" or def.magnitude_unit == &"element_power"
	)
	if not spends_health:
		return 0.0
	var magnitude := StatusRuntime.pulse_magnitude(
		runtime, _sibling_burns(actor, runtime), _amplifier_gain(actor), _amplifier_cap(actor)
	)
	if magnitude <= 0.0:
		return 0.0
	var pool_id := StringName(def.payload.get("pool", &"health"))
	var pool := actor.resource(pool_id)
	if pool == null:
		return 0.0
	var amount := magnitude * float(def.payload.get("share_per_pulse", 0.0))
	if amount <= 0.0:
		return 0.0
	actor.change_resource(pool_id, -amount)
	return amount


## How many statuses ALREADY on the actor the amplifiers feed: the burns that spend
## through the `health_share` or `element_power` channel, excluding the one being
## pulsed, so a burn never counts as its own sibling and the channel can never double.
##
## ## Why the gate left THIS function
##
## It used to refuse unless `runtime.def.mechanic() == feed_siblings` — the pulsing
## status had to BE an amplifier. That is backwards: `fire_pyre` is a `sibling_amp`
## status with no pool of its own, so it spends nothing and `_pulse` returns before
## ever reaching this count. The two conditions were mutually exclusive, so
## `_sibling_burns` answered `0` for every burn in the game and both amplifiers were
## structurally inert at any magnitude (measured: `AMPLIFIER DELTA = 0.000000`).
##
## The count is now a property of the ACTOR — what is feeding the amplifiers — rather
## than of the status happening to be on its tick. Which siblings an amplifier feeds is
## authored per amplifier ([method _amplifier_gain] reads that def), not decided here.
static func _sibling_burns(actor: Actor, runtime: StatusRuntime) -> int:
	# The `runtime.def == null` half is the non-vacuity guard: a caller that has no
	# resolved status cannot name the id to exclude, and counting against an unknown def
	# is how a pulse ends up multiplied by a sibling set it was never part of.
	if actor == null or runtime == null or runtime.def == null:
		return 0
	var count := 0
	for other in actor.statuses:
		if other.id == runtime.def.id:
			continue
		var other_runtime := _runtime(actor).get(other.instance_id) as StatusRuntime
		if other_runtime != null and _feeds(other_runtime.def):
			count += 1
	return count


## Every live amplifier's authored `sibling_gain`, summed.
##
## ## Why the total rather than one def's number
##
## An amplifier's `sibling_gain` lives on ITS OWN def (`fire_pyre` authors 0.5,
## `wind_spread` 0.45), and the pulsing status authors none — which is the defect this
## reads past. The gain therefore has to be collected from the amplifiers present on the
## actor, and SUMMED so a body carrying both gets both: `fire_pyre` and `wind_spread`
## are two authored amplifiers with two authored gains, and a second one that quietly
## did nothing is the same defect wearing a different hat.
##
## Each def's gain is clamped to its own authored `sibling_cap` before it is added, so
## the channel saturates per amplifier instead of running away as amplifiers accumulate:
## a body with N amplifiers reaches at most `N * cap`, and no single amplifier can
## contribute an unbounded share. A status this module did not author carries no
## `StatusDef`, so it contributes nothing rather than being guessed at.
static func _amplifier_gain(actor: Actor) -> float:
	var total := 0.0
	for _entry in _amplifiers(actor):
		total += minf(_entry[&"gain"], _entry[&"cap"])
	return total


## The most the amplifier channel may add on top, as the MAXIMUM over the live
## amplifiers rather than their sum: the cap is the ceiling of the channel, not a
## per-amplifier budget, so stacking two amplifiers widens what they are allowed to add
## (see [method _amplifier_gain]) without also stacking the ceiling that bounds it.
static func _amplifier_cap(actor: Actor) -> float:
	var cap := 0.0
	for _entry in _amplifiers(actor):
		cap = maxf(cap, _entry[&"cap"])
	return cap


## Every live `feed_siblings` amplifier on the actor, as `{gain, cap}` read off its own
## def. One walk so the gain and the cap cannot be counted over different sets.
static func _amplifiers(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var runtimes := _runtime(actor)
	for status in actor.statuses:
		var runtime := runtimes.get(status.instance_id) as StatusRuntime
		if runtime == null or not _is_amplifier(runtime.def):
			continue
		(
			out
			. append(
				{
					&"gain": maxf(0.0, float(runtime.def.payload.get("sibling_gain", 0.0))),
					&"cap": maxf(0.0, float(runtime.def.payload.get("sibling_cap", 0.0))),
				}
			)
		)
	return out


static func _is_amplifier(def: StatusDef) -> bool:
	if def == null:
		return false
	return def.magnitude_unit == &"sibling_amp" and def.mechanic() == &"feed_siblings"


## Whether this def is one the amplifiers feed. `magnitude_unit` decides rather than
## `kind`: `element_power` is what makes a status spend its magnitude, so it is the
## channel that can be fed, and a def whose own mechanic is `feed_siblings` is the
## amplifier being fed rather than a sibling — which is why `_sibling_burns` excludes
## the pulsing status by id as well.
static func _feeds(def: StatusDef) -> bool:
	if def == null:
		return false
	return def.magnitude_unit == &"health_share" or def.magnitude_unit == &"element_power"


## The ONE live instance carrying `status_id`, or null — the same question
## `Actor.has_status` answers, except it hands back the instance the merge rule chose so
## a caller can read the strength that will actually pulse. Bounded `for` over the
## actor's live status list, which `tick_statuses` prunes.
static func _live(actor: Actor, status_id: StringName) -> StatusEffect:
	for status in actor.statuses:
		if status.id == status_id:
			return status
	return null


static func _live_instances(actor: Actor) -> Array[int]:
	var out: Array[int] = []
	for status in actor.statuses:
		out.append(status.instance_id)
	return out


static func _count_lost(before: Array[int], after: Array[int]) -> int:
	var lost := 0
	for instance in before:
		if not after.has(instance):
			lost += 1
	return lost


## `categories` as plain strings for the read model: the summary contract is
## primitives only (ADR 0902, P13).
static func _strings_of(values: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return out


## Drop the runtime records and modifiers of instances the actor no longer
## carries, so an expired burn cannot leave a modifier or a stale magnitude
## behind. Keyed by INSTANCE (ADR 0902, P3): one `for` over a snapshot, with
## the sibling carrying another instance of the same id untouched.
static func _prune(actor: Actor, live: Array[int]) -> void:
	var runtimes := _runtime(actor)
	var gone: Array[int] = []
	for instance in runtimes.keys():
		var runtime := runtimes.get(instance) as StatusRuntime
		if runtime == null or live.has(int(instance)):
			continue
		runtimes.erase(instance)
		StatusRuntime.clear_source(actor, runtime.source)
		gone.append(int(instance))
	if not gone.is_empty():
		# ADR 0902 (P6=C): a left instance's counters leave with it, so a successor
		# instance can never inherit a dead sibling's count.
		StatusCounters.drop_instances(actor, gone)


## Drop the purged ids from the actor's array, in place, and let `_prune` sweep the
## runtimes and modifiers they leave behind.
##
## ## Why the array is erased IN PLACE and never reassigned
##
## `StatusRegistry` holds that array BY REFERENCE (`core/actor.gd:143`,
## `StatusRegistry._init(statuses)`), which is deliberate: `FertilityApi.advance` erases
## from `actor.statuses` directly (`modules/fertility/api.gd:69`) and `EnvironmentField`
## reads it directly, so a shadow copy here would go stale the moment either ran.
## `actor.statuses = kept` therefore REBINDS the property to a brand new array while the
## registry keeps the old one — after which `actor.statuses` reads empty and
## `actor.has_status()` still answers for the purged ids, because every read of a status
## goes through the registry. That is the worst shape a purge can take: the module
## believes the combat debuff is gone while the rest of the game still has it.
##
## So this erases through the same reference the registry holds, exactly as fertility
## does. `_live_instances` is read AFTER the erasure, not before, so `_prune` sees the
## survivors -- reading it first meant the just-cleared ids counted as live and their
## modifiers were never released.
static func _purge(actor: Actor, cleared: Array[String]) -> void:
	for index in range(actor.statuses.size() - 1, -1, -1):
		if cleared.has(String(actor.statuses[index].id)):
			actor.statuses.remove_at(index)
	# The runtime sweep is instance-keyed (ADR 0902, P3), so this is the same
	# reconcile every apply and expiry runs: what left the actor loses its record
	# and its OWN source tag's modifiers; coexist siblings stay untouched.
	_reconcile(actor)
	actor.mark_stats_dirty()
