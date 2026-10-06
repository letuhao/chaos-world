class_name TechniquesApi
extends RefCounted

## Public facade for the `techniques` module (ADR 0053/0054/0055/0056/0059).
## Other modules and `ui/` may reference ONLY this file (`api.gd`).
##
## Three states, three owners of truth, and this facade is the only way out to
## them:
##
##   - **Learning** is acquisition. Gated by realm, paid for in progress, spent from
##     a codex. It happens off-combat and is never reversible by accident.
##   - **Equipping** is a build choice. Limited, reversible for free, re-decided per
##     fight.
##   - **Mastery** is a long investment, persisted alongside the codex entry.
##
## Learning, equipping and mastery are separately testable and separately
## persisted, and that separation is the whole point: collapsing them would make a
## single mis-click unequip a permanent investment, and a slot limit would silently
## delete something the player paid real currency for.
##
## No attach order. This module reaches `PathState`, `RealmDefaults` and
## `Actor.meridians` directly — all `contracts/` or `core/` — so it needs no
## cultivation facade and, per ADR 0059, grows none either.

const CODEX_COMPONENT := &"technique_codex"
const SLOTS_COMPONENT := &"technique_slots"
const UPKEEP_COMPONENT := &"technique_upkeep"

## Active execution and the per-technique cooldown table (DEF-0125). Not a facade
## method: `activate` is a component on the actor, reached the way `TechniqueUpkeep`
## is and named here as a constant. ADR 0056 originally forced that by a twelve-verb
## cap that ADR 0265 removed; what keeps it a component now is cohesion — the facade
## publishes the component id rather than re-exporting its collaborators. See
## `technique_casting.gd`.
const CASTING_COMPONENT := &"technique_casting"

## ## The DELIVERY seam, and why there is no `DELIVERY` constant here
##
## How a `category = &"technique"` item becomes a `CodexEntry` is NOT a facade
## method either, for the reason the two constants above give: the cap is 12 and
## this module publishes 12. It is reached as a named type — `TechniqueDelivery` —
## installed as a process-wide binding by the composition root and called by
## `items`. Neither `items` nor `app/` can reach it through this file, and that is
## deliberate: the seam is one-way.
##
## ```
## # app/, at boot:
## TechniqueDelivery.install(Callable(TechniqueDelivery, "bind_learner"))
## ```
##
## This file used to publish `const DELIVERY := &"technique_delivery"` for that
## reach, and it was inert: the string was not a component key, not a save key, and
## not the `ProjectSettings` key the seam actually travels under
## (`TechniqueDelivery.SETTING == "technique/delivery_seam"`). Nothing in `res://src`
## read it and nothing ever could, because no code path consumes that literal —
## which is the defect `tools/arch`'s facade-constant guard exists to name. The
## binding itself was never affected: it is `TechniqueDelivery.install` that makes
## the seam live, and `app/item_workbench_body.gd` calls it on every actor it
## builds. `tools arch`'s own `GATED_EXACT` still names `DELIVERY`, because the
## rule is about the SHAPE a cap-bound module publishes, not about this module.

## The ACTIVATION READBACK: what one landed cast actually moved, as primitives.
##
## Not a facade method either, for the same reason as the two above. It is reached as
## a named type, which is what keeps the readback a CONSTANT rather than a verb that
## forwards into this module's own interior:
##
## ```
## var before := TechniqueCastView.snapshot(caster, foe)
## var turn := TechniqueCastView.of(casting.activate(caster, def, foe), before, caster, foe)
## ```
##
## It exists because `activate`'s `damage` is the spine's descriptor and the spine's
## descriptor is fourteen fields about the SPINE. A turn that paid qi, spent a
## cooldown, eroded a sea and wounded a meridian is four facts in four systems, and a
## mind technique's damage is deliberately not in `amount` at all (ADR 0071 with ADR
## 0162), so a caller reading the damage fields alone concludes it did nothing.
## DEF-0097.
const CAST_VIEW := "technique_cast_view"

const STATE_KEY := &"technique_state"

## Affordability is compared with a tolerance, so a path holding exactly the price
## pays rather than being short by one float ULP. The same epsilon
## `TechniqueCasting.EPSILON` uses for the same reason, kept here rather than
## reached across the module so the study charge and the cast cost cannot drift
## apart on a rounding difference.
const EPSILON := 0.000001

## Published so a panel reports the module's numbers instead of hardcoding its own
## (AGENTS.md: no number formatting in a screen, step amounts live in the facade).
const LEARN_BASE := TechniqueScales.LEARN_BASE
const LEARN_STEP := TechniqueScales.LEARN_STEP
const TECHNIQUE_STEP := TechniqueScales.TECHNIQUE_STEP
const MAX_MASTERY_RUNGS := TechniqueScales.MAX_RUNGS


## Attach the module to `actor`: give it a codex, a slot table, an upkeep
## tracker and a casting table, then adopt whatever state a prior
## `Actor.from_dict` carried. Idempotent and safe after a load — the restored
## snapshot is the starting state, not a second copy of it.
##
## The codex and the slot table share ONE payload under `STATE_KEY`, because a save
## that kept the techniques but dropped the bindings would restore an empty loadout
## over a full codex (DEF-0154). `TechniqueCodex` owns the key and `TechniqueSlots`
## contributes its `bindings` section, so neither half can be written without the
## other being carried.
static func attach(actor: Actor) -> void:
	if actor == null or actor.component(CODEX_COMPONENT) is TechniqueCodex:
		return
	var stored: Dictionary = actor.get_module_data(STATE_KEY)
	var codex := TechniqueCodex.new(stored)
	actor.set_component(CODEX_COMPONENT, codex)
	actor.set_component(SLOTS_COMPONENT, TechniqueSlots.new(stored))
	actor.set_component(UPKEEP_COMPONENT, TechniqueUpkeep.new())
	actor.set_component(
		CASTING_COMPONENT, TechniqueCasting.new(actor.get_module_data(TechniqueCasting.STATE_KEY))
	)
	_commit(actor)
	# ADR 0883: the module's half of the aptitude resolution. The subscription is guarded
	# (a re-attach must not stack handlers) and the resolve runs once here, so a LOADED
	# actor's technique points land back on top of whatever the save carried.
	if not actor.path_advanced.is_connected(_on_path_advanced.bind(actor)):
		actor.path_advanced.connect(_on_path_advanced.bind(actor))
	resolve_aptitudes(actor)


## The actor's codex, attached on demand.
static func codex(actor: Actor) -> TechniqueCodex:
	attach(actor)
	return actor.component(CODEX_COMPONENT) as TechniqueCodex


## The actor's technique slots, attached on demand. The slot table is the limited,
## path-typed binding; the codex behind it is not bounded by it.
static func slots(actor: Actor) -> TechniqueSlots:
	attach(actor)
	return actor.component(SLOTS_COMPONENT) as TechniqueSlots


## ADR 0883, the technique half of the aptitude resolution. Idempotent by construction:
## core's `AptitudeGrant.apply` REPLACES the store with the majors alone, then this adds
## `technique_points` for EVERY learned row, split across the DOMINANT posture's four.
## Every stage that changes the build calls this same verb — `learn` on success, `attach`
## after a load/save round trip, and `path_advanced` because a breakthrough replaced the
## store with majors only.
##
## Reads the codex COMPONENT, never `codex(actor)`: the on-demand accessor calls `attach`,
## and `attach` calls this, so going through it would be the recursion this line avoids.
static func resolve_aptitudes(actor: Actor) -> void:
	if actor == null or actor.stats == null:
		return
	var grant := AptitudeGrant.shipped()
	if grant == null:
		return
	grant.apply(actor)
	var per_technique := grant.technique_points
	if not is_finite(per_technique) or per_technique <= 0.0:
		return
	var codex_ref := actor.component(CODEX_COMPONENT) as TechniqueCodex
	var learned := 0 if codex_ref == null else codex_ref.count()
	if learned <= 0:
		return
	var points := actor.stats.aptitude_points()
	var posture := AptitudeGrant.dominant_posture(points)
	if posture == &"":
		return
	var each := float(learned) * per_technique / float(Aptitude.PER_POSTURE)
	for id in Aptitude.in_posture(posture):
		points[id] = float(points.get(id, 0.0)) + each
	actor.stats.set_aptitudes(points)


static func _on_path_advanced(_path_id: StringName, _rank_id: StringName, actor: Actor) -> void:
	resolve_aptitudes(actor)


## Learn `def`, or refuse with the gameplay cause. Learning is permanent and is
## paid for out of cultivation progress the actor owns. Re-learning a technique
## already at a higher rung never lowers it — a duplicate manual is not a
## mastery loss.
##
## It is NOT free. ADR 0055 prices study at `LEARN_BASE * LEARN_STEP^ordinal *
## MAG_GRADE` and this method charges exactly that out of the PREFERRED PATH'S
## PROGRESS (see ADR 0140). The price is computed before the codex is touched,
## affordability is checked before any progress is deducted, and a shortfall is
## a refusal that names what was owed and what was held — so a learn that fails
## writes NOTHING (DEF-0206).
##
## ## This is where a manual's MARGIN is drawn, and why here
##
## A manual's text is authored and fixed; what varies between copies is the
## annotation in the margin (`TechniqueMarginalia`, ADR 0196). It is drawn here, at
## the learn, and nowhere else — for the same reason learning is charged here and
## not in the caller: it is the one moment the copy enters an actor's hands, and it
## is the one moment the codex row is written. Drawing it at CRAFT time would put
## it on a carrier that may never be studied; drawing it at REBUILD time would make
## the contribution of an equipped technique depend on how many times it had been
## rebuilt.
##
## `rng` is a SEED SOURCE, not a stream, in the shape ADR 0191 fixed for a
## breakthrough attempt: an optional generator whose `seed` is read, so a test
## chooses the copy it gets by seeding and the choice survives the save. One draw
## per rollable option, in authored order. Production passes none and takes the
## engine's entropy once.
static func learn(
	actor: Actor, def: TechniqueDef, rung: int = 0, rng: RandomNumberGenerator = null
) -> Dictionary:
	var refused := _refuse(actor, def)
	if not refused.is_empty():
		return refused
	var price := TechniqueGate.learn_price_for(actor, def)
	# All-or-nothing: every gate the charge crosses is checked BEFORE a single
	# unit of progress moves, which is the shape `EquipmentUpkeep._pay` and
	# `TechniqueCasting.activate` already use. Learning is permanent, so a charge
	# that failed halfway would take progress for a technique nobody gained.
	var owed := _study_charge(actor, def)
	if not _short(actor, owed).is_empty():
		var broke := _refused("insufficient_progress", def.id)
		broke["short"] = _short(actor, owed)
		broke["learn_price"] = price
		return broke
	for path_id in owed.keys():
		var state := actor.path(path_id)
		state.progress = maxf(0.0, state.progress - float(owed[path_id]))
	var codex := codex(actor)
	# Drawn BEFORE `learn` writes, and only ever for a row that carries NO margin:
	# the margin is a property of the copy the actor is holding, so a second copy of
	# the same manual re-teaches the technique without re-drawing its numbers.
	#
	# ## Why the gate tests the ARRAY and not the KEY
	#
	# `TechniqueCodex.record` writes `"realized"` on every row, so `has("realized")`
	# is true for every row that has ever been written — including one recorded
	# directly (`codex.learn(id)`) and including a v1 row that `migrate` gave an
	# empty `[]` because it has no seed to replay. Gating on the KEY therefore made
	# a margin unreachable for any technique not learned through this method, and
	# `test_the_codex_list_marks_which_rows_are_annotated` caught exactly that: a row
	# learned by hand reported `annotated: false` forever.
	#
	# The gate is "carries no annotations", which is the same question
	# `CodexEntry.realized` and `TechniqueReadModel`'s `annotated` flag already ask,
	# and it is the question that keeps a second copy from re-rolling an investment.
	var margin: Array[Dictionary] = []
	if codex.row(def.id).get("realized", []).is_empty():
		margin = TechniqueMarginalia.draw(def, rng)
	codex.learn(def.id, rung, margin)
	_commit(actor)
	# ADR 0883: LEARNING A TECHNIQUE is the second stage that re-resolves the build.
	resolve_aptitudes(actor)
	return {
		"ok": true,
		"id": String(def.id),
		"rung": int(codex.row(def.id).get("rung", 0)),
		"learn_price": price,
		"paid": _numbers(owed),
		"margin": _margin_view(codex.row(def.id)),
	}


## Equip a known technique into the first free slot its own path allows: a SHARED
## technique takes a universal slot, a DUAL technique takes one on each of its two
## paths, and a refused equip changes nothing — which is why the claim is asked for
## before anything moves rather than allocated optimistically and rolled back.
static func equip(actor: Actor, def_or_id) -> Dictionary:
	var def := _as_def(def_or_id)
	var refused := _refuse_equip(actor, def)
	if not refused.is_empty():
		return refused
	var claim := slots(actor).claimable(_tier(actor), def)
	if claim.is_empty():
		return _refused("no_free_slot", def.id)
	# Re-equipping moves rather than stacks: `bind` releases the previous binding
	# first, and the rebuild below is remove-all-then-re-add, so one technique can
	# never hold its own modifiers twice.
	slots(actor).bind(def.id, claim)
	_commit(actor)
	rebuild(actor)
	return {"ok": true, "id": String(def.id), "slots": _strings(claim)}


## Release a technique's slots. Free and non-destructive: the entry stays in the
## codex with its rung, so re-equipping is one call and no re-learning. This is the
## whole of ADR 0053's "losing a slot never loses the technique".
static func unequip(actor: Actor, def_or_id) -> Dictionary:
	var def := _as_def(def_or_id)
	if def == null:
		return _refused("unknown_definition", &"")
	if slots(actor).unequip(def.id).is_empty():
		return _refused("not_equipped", def.id)
	# A suspension record is per technique and outlives nothing: an unequipped
	# technique later re-equipped starts paying upkeep again rather than inheriting
	# a stale refusal.
	_upkeep(actor).forget(def.id)
	TechniqueEffects.clear(actor, def.id)
	# The contribution is gone, so nothing can be left behind: drop the applied
	# record too, or a later rebuild would sweep for a technique that no longer
	# contributes and grow its sweep list without bound.
	slots(actor).forget_applied(def.id)
	_commit(actor)
	return {"ok": true, "id": String(def.id)}


## Replace every equipped technique's contribution from scratch. Remove-all-then-
## re-add per technique, copying `SocketEffects.apply`, so rebuilding any number of
## times cannot accumulate drift — and a suspended technique rebuilds as an empty
## contribution, so rebuilding never hands a technique its modifiers back while it
## cannot pay for itself.
static func rebuild(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var table := slots(actor)
	var equipped_ids := table.equipped(_tier(actor))
	var applied := 0
	for technique_id in equipped_ids:
		var effects := _contribution(actor, technique_id)
		TechniqueEffects.apply(actor, technique_id, effects)
		applied += (
			TechniqueEffects.modifiers_of(effects, TechniqueEffects.source_for(technique_id)).size()
		)
	# Clear anything this module applied that is NO LONGER bound. Without this, a
	# contribution outlives its binding whenever the binding leaves the table
	# without passing through `unequip` — an unequip during a domain change, or a
	# save restored with fewer bindings than the actor was running with. Nothing
	# else in the module can find those sources, because the source tag is namespaced
	# per technique and `ActorStats` only removes a source it is told the name of
	# (DEF-0152).
	for technique_id in table.applied_ids():
		if not equipped_ids.has(technique_id):
			TechniqueEffects.clear(actor, technique_id)
	actor.mark_stats_dirty()
	return {"applied": applied, "equipped": equipped_ids.size()}


## Settle one upkeep interval for every equipped technique and rebuild whatever
## changed state. A technique that cannot pay is SUSPENDED: still equipped,
## contributing nothing, and never unequipped — so spending in combat can never
## strip a loadout, and an unaffordable upkeep never blocks an equip.
##
## `settle` charges IMMEDIATELY. A caller that drives it per frame would drain a
## pool sixty times a second, so the frame caller uses `tick` instead, which
## accumulates the delta and settles only when an authored interval has elapsed.
## `delta` is OPTIONAL and that is the whole point: a frame caller passes it and gets
## interval-accurate settlement, while a caller that wants to settle right now — a
## test, or a domain change — omits it and pays immediately. Both are real uses, so
## neither is the default and the facade does not grow a second method for the other
## (it is at the 12 cap).
static func settle_upkeep(actor: Actor, delta: float = -1.0) -> Array[StringName]:
	if actor == null:
		return []
	var equipped := slots(actor).equipped(_tier(actor))
	var upkeep := _upkeep(actor)
	var changed := (
		upkeep.settle(actor, equipped) if delta < 0.0 else upkeep.advance(actor, delta, equipped)
	)
	if not changed.is_empty():
		rebuild(actor)
	return changed


## Raise a known technique's mastery rung and re-derive every contribution, so a
## rung increase is observable immediately rather than at the next rebuild. The
## caller pays whatever the study cost is; this records the outcome.
static func raise_mastery(actor: Actor, def_or_id, rung: int) -> Dictionary:
	var def := _as_def(def_or_id)
	if def == null:
		return _refused("unknown_definition", &"")
	var codex := codex(actor)
	if not codex.set_rung(def.id, rung):
		return _refused("no_rung_gained", def.id)
	_commit(actor)
	rebuild(actor)
	return {"ok": true, "id": String(def.id), "rung": int(codex.row(def.id).get("rung", 0))}


## Everything a screen needs to render the codex and the loadout: primitives only,
## so it can be a `summary()` payload unchanged. `{}` when there is no actor.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return TechniqueReadModel.summary(
		actor, codex(actor), slots(actor), _upkeep(actor), _tier(actor)
	)


## One technique's full read model: identity, grade, path, costs, the mastery
## ladder, its effects and both gates. `{}` for an unknown id, so a panel never
## renders a row it cannot fill. This is also the study preview: `known` false with
## an empty `learn_unmet` is exactly "this actor may learn it now, at this price".
static func inspect(actor: Actor, def_or_id) -> Dictionary:
	var def := _as_def(def_or_id)
	if def == null:
		return {}
	return TechniqueReadModel.inspect(
		actor,
		codex(actor),
		slots(actor),
		_upkeep(actor),
		def,
		_refuse(actor, def).get("unmet", []),
		_refuse_equip(actor, def).get("unmet", [])
	)


# --- Internals -------------------------------------------------------------


## The pool the study is charged to: the technique's own path's accumulated
## `PathState.progress`, and nothing else (ADR 0140).
##
## ## Why PROGRESS and not qi
##
## `qi` is a `ResourcePool` and would have been the obvious pool, but a technique's
## qi cost IS its cast cost, and qi refills from the reservoir on its own schedule.
## Charging study out of it would price ACQUISITION in the same currency as
## EXECUTION, which makes "may I afford to learn this" a question about combat
## timing rather than about cultivation. It would also be the one cost in the game
## an actor can avoid entirely by never casting, which is precisely the actor a
## study cost is aimed at.
##
## ## Why PROGRESS and not comprehension or insight
##
## `Stat.COMPREHENSION` is a BASE ATTRIBUTE, not a pool. It is gated by
## `QiBreakthroughCondition`, `BodyBreakthroughCondition` and `MindAdvancement`,
## it feeds `Stat.INSIGHT_GAIN` (the RATE comprehension itself grows at),
## `TribulationEndurance` and the ascension ladder. Draining it is not a
## transaction; it is a set of gates silently moving backwards, in three modules
## this one may not reach. So it is never charged.
##
## `Stat.INSIGHT_GAIN` is a derived RATE, not a stock: writing to it would
## overwrite a composition rather than spend a quantity.
##
## `PathState.progress` is the one quantity in the game that is BOTH spendable and
## about cultivation. It accumulates from training and is compared against
## `RealmSeed.progress_required` by every path's breakthrough condition. That is
## exactly the promise ADR 0055 made when it sized `LEARN_STEP = 1.03` against
## qi's `progress_required` floor of `29/28`: study is cheaper than a
## breakthrough and never runs ahead of one. Naming `progress` as the payer is
## what makes that published ladder MEAN something instead of being a number on a
## screen nobody pays.
##
## ## Which path pays
##
## The technique's OWN path, read the same way the slot allocator reads it: a
## DUAL technique's first path, and a SHARED technique's `shared` marker — which
## is never a `PathState` id and is therefore never charged at all, the same way
## it never takes a path slot (ADR 0053).
static func _study_charge(actor: Actor, def: TechniqueDef) -> Dictionary:
	if actor == null or def == null:
		return {}
	var price := TechniqueGate.learn_price_for(actor, def)
	if price <= 0.0:
		return {}
	# Typed explicitly rather than `:=`. `def.path_ids()` is declared
	# `Array[StringName]`, and inferring the local from it re-boxes the value as an
	# untyped `Array`, which throws "Trying to assign an array of type Array to a
	# variable of type Array[StringName]" at RUNTIME — after the price is already
	# computed, so a learn silently paid nothing. Announcing the type keeps the
	# element type through the assignment.
	var paths: Array[StringName] = def.path_ids()
	if paths.is_empty() or not PathState.ALL.has(paths[0]):
		return {}
	return {paths[0]: price}


## Every pool this study cannot pay, with what it owed and what it held. Checked
## whole BEFORE anything moves, which is what makes a refused learn write nothing.
static func _short(actor: Actor, owed: Dictionary) -> Array:
	var out: Array = []
	for path_id in owed.keys():
		var state := actor.path(path_id)
		var held := 0.0 if state == null else state.progress
		var required := float(owed[path_id])
		if held + EPSILON >= required:
			continue
		out.append({"resource": String(path_id), "required": required, "current": held})
	return out


## Every gate a learn must pass, as one refusal. Empty means learnable.
static func _refuse(actor: Actor, def: TechniqueDef) -> Dictionary:
	if actor == null or def == null:
		var unknown := _refused("unknown_definition", &"")
		unknown["unmet"] = []
		return unknown
	var unmet := TechniqueGate.unmet(actor, def)
	if not unmet.is_empty():
		return {"ok": false, "reason": "realm_unmet", "id": String(def.id), "unmet": unmet}
	return {}


## Every gate an equip must pass, as one refusal. The realm gate still applies,
## because equipping is a build choice and not an escape from the ladder — but the
## codex check is the extra one: a technique must be LEARNED before it can be bound,
## which is the separation of the three states made structural.
static func _refuse_equip(actor: Actor, def: TechniqueDef) -> Dictionary:
	var refused := _refuse(actor, def)
	if not refused.is_empty():
		return refused
	if not codex(actor).knows(def.id):
		var unlearned := _refused("not_learned", def.id)
		unlearned["unmet"] = []
		return unlearned
	return {}


## What one technique contributes right now: its entry's realized data plus the
## def's authored passive options, or nothing at all while it is suspended. This is
## ADR 0054's suspension rule in one place — a suspended technique is equipped and
## contributes exactly zero, and neither `rebuild` nor any equip can revive it.
static func _contribution(actor: Actor, technique_id: StringName) -> Array[Dictionary]:
	if _upkeep(actor).is_suspended(technique_id):
		return []
	var def := TechniqueCatalog.instance().definition(technique_id)
	if def == null:
		return []
	var entry := codex(actor).entry(technique_id)
	return def.effects() if entry == null else entry.effects_for(def)


## Write the whole module's snapshot: the codex rows AND the slot bindings, under
## one key. Persisting only the codex is what made a reload drop the whole loadout
## (DEF-0154), so both halves are written together and neither can be forgotten.
static func _commit(actor: Actor) -> void:
	if actor == null:
		return
	var payload := codex(actor).to_dict()
	var slot_snapshot := slots(actor).to_dict()
	payload["bindings"] = slot_snapshot.get("bindings", [])
	payload["applied"] = slot_snapshot.get("applied", [])
	actor.set_module_data(STATE_KEY, payload)


static func _upkeep(actor: Actor) -> TechniqueUpkeep:
	return actor.component(UPKEEP_COMPONENT) as TechniqueUpkeep


static func _tier(actor: Actor) -> int:
	return TechniquePolicy.tier_of(actor.realm())


static func _as_def(def_or_id) -> TechniqueDef:
	if def_or_id is TechniqueDef:
		return def_or_id
	return TechniqueCatalog.instance().definition(StringName(def_or_id))


static func _refused(reason: StringName, technique_id: StringName) -> Dictionary:
	return {"ok": false, "reason": String(reason), "id": String(technique_id)}


static func _strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## A `{StringName: float}` charge flattened to `{String: float}`, so a read model
## or a panel receives primitives. `StringName` keys survive a save envelope as
## their printed form rather than as themselves, so a caller that serialized the
## outcome would report a charge against nothing.
static func _numbers(owed: Dictionary) -> Dictionary:
	var out := {}
	for path_id in owed.keys():
		out[String(path_id)] = float(owed[path_id])
	return out


## A codex row's margin as `{option_id: value}` primitives, for the learn outcome
## and for a caller that wants to compare two copies without reaching into the
## codex. Primitives only, like every other dictionary this facade returns.
static func _margin_view(row: Dictionary) -> Dictionary:
	var out := {}
	for effect in row.get("realized", []):
		var option_id := String((effect as Dictionary).get("option_id", ""))
		if option_id.is_empty():
			continue
		out[option_id] = float((effect as Dictionary).get("value", 0.0))
	return out
