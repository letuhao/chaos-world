class_name RaceApi
extends RefCounted

## Public facade for the `race` module (ADR 0062). Other modules may reference ONLY
## this file (`api.gd`). Concrete implementations live beside this file and are wired in
## `app/`.
##
## **A race is a body plan that refuses to be a stat stick.** It answers *can this body
## cultivate this path at all*, *what realm can it never pass*, *what does it feed on*
## and *how long does it live* — not a delta a character sheet has to diff.
##
## **A race is assigned once, at conception, and is immutable for the actor's life.**
## There is no transformation and no assimilation. `set_race` exists for conception,
## character creation and tests — the three places a race is legitimately written — and
## it is the only verb here that changes a race.
##
## Race × path is a **partition, not a tier list**: every authored race closes at least
## one of qi/body/mind, so no body can reach the top on every axis. That is why
## `can_take_path` is a facade verb at all — it is the question the whole feature exists
## to make answerable in combat and at every breakthrough.
##
## The facade is at its twelve-method cap, so anything a panel or a sibling module needs
## that is not a verb below lives on `RaceGate` or `RaceCatalog` behind a verb, never as
## a thirteenth method.

## `actor.components` slot holding the resolved `RaceDef`, read by `RaceProvider`.
const DEF_COMPONENT := RaceProjection.DEF_COMPONENT
## The stat-provider component slot. Underscored because it is wiring, not a question.
const _PROVIDER_COMPONENT := &"race_provider"
## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := RaceState.MODULE_KEY


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict` carried,
## normalizes it against the current catalog, re-projects the race the ledger names, and
## registers the provider. Idempotent, and safe to call before any race is assigned.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	# Registering the provider twice is harmless: a provider's contribution replaces
	# its own stat rather than accumulating (ADR 0026), and both copies read the same
	# component. Swapping the slot keeps a re-attach from leaking instances.
	var provider := actor.component(_PROVIDER_COMPONENT) as RaceProvider
	if provider == null:
		provider = RaceProvider.new()
		actor.set_component(_PROVIDER_COMPONENT, provider)
		actor.stats.add_provider(provider)
	var ledger := RaceState.normalize(actor.get_module_data(MODULE_KEY), _known_races())
	actor.set_module_data(MODULE_KEY, ledger)
	RaceProjection.apply(actor, RaceState.race_id(ledger))


## The actor's race id, or `&""` when it has none.
static func race_of(actor: Actor) -> StringName:
	return RaceGate.race_of(actor)


## The actor's `RaceDef`, or null when it has none or the catalog does not ship it.
## Null rather than a guess.
static func race_definition(actor: Actor) -> RaceDef:
	if actor == null:
		return null
	var known := actor.component(DEF_COMPONENT) as RaceDef
	if known != null:
		return known
	return RaceCatalog.instance().race_definition(RaceGate.race_of(actor))


## Assign `race_id` to `actor` and project it. Returns false — changing nothing —
## for a race the catalog does not ship, because a race nothing defines would grant
## nothing and gate everything.
##
## Not a transformation verb. It writes the race a child is BORN, which is the only
## write this module has.
static func set_race(actor: Actor, race_id: StringName) -> bool:
	if actor == null:
		return false
	var def := RaceCatalog.instance().race_definition(race_id)
	if def == null:
		return false
	var ledger := RaceState.normalize(actor.get_module_data(MODULE_KEY), _known_races())
	ledger["race"] = String(def.id)
	actor.set_module_data(MODULE_KEY, ledger)
	RaceProjection.apply(actor, def.id)
	return true


## The single race a child of `parent_a` and `parent_b` is born, for `roll` in `[0, 1)`.
##
## Pure, deterministic and headless-testable; see `RaceResolver` for the exact
## algorithm. A child of two different races is born ONE race, never a blend.
static func resolve_race(parent_a: Actor, parent_b: Actor, roll: float = 0.5) -> StringName:
	return RaceResolver.resolve(parent_a, parent_b, roll)


## Whether this body can cultivate `path_id` at all. The question a race exists to make
## answerable. An actor with no race takes no restriction.
static func can_take_path(actor: Actor, path_id: StringName) -> bool:
	return RaceGate.allows_path(actor, path_id)


## Whether gated content may open for `actor`.
##
## `requirement` is authored data, never code. It is either an empty dictionary —
## ungated, always open — or a `{verb: ..., ...}` map naming exactly one of the seven
## gate verbs (`is_race`, `race_allows_path`, `has_trait`, `realm_ceiling`, `all_of`,
## `any_of`, `none_of`).
##
## Returns `{ok: bool, reason: String, unmet: Array[Dictionary]}` where each unmet entry
## is `{kind, id, required, actual, label}` — the same shape `ItemRequirement.unmet()`
## produces, so a panel can render a reason it did not have to invent. `ok` is the whole
## answer; the rest is for display. An unknown verb refuses closed and names itself.
static func unmet(actor: Actor, requirement: Dictionary) -> Dictionary:
	return RaceGate.evaluate(actor, requirement)


## A read-only, primitive-only snapshot built for a character or lineage screen: what
## body this actor has, what it cannot reach, and what every authored race offers.
##
## One call answers the whole screen, so the facade needs no separate catalog accessor
## for the UI. `has_actor` is false and the race block is empty when there is no actor,
## which is the contract a panel tests instead of pixels.
static func summary(actor: Actor) -> Dictionary:
	var catalog := RaceCatalog.instance()
	var out := {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"race": "",
		"closed_paths": [],
		"open_path_count": PathState.ALL.size(),
		"realm_ceiling": 0,
		"realm_reached": 0,
		"lifespan": 0.0,
		"affinities": {},
		"is_baseline": false,
		"races": {},
		"baseline": "",
	}
	out["baseline"] = String(catalog.baseline_race())
	# Every authored race is listed whatever the actor is, so a lineage screen can
	# compare bodies without a second call; `held` is the only thing that differs.
	var held := RaceGate.race_of(actor)
	for race_id in catalog.race_ids():
		var authored := catalog.race_definition(race_id)
		if authored == null:
			continue
		out["races"][String(race_id)] = _view(authored, race_id == held)
	if actor == null:
		return out
	out["realm_reached"] = RaceGate.actor_realm_index(actor)
	var def := race_definition(actor)
	if def == null:
		return out
	out["race"] = String(def.id)
	out["closed_paths"] = _string_list(RaceGate.closed_paths(actor))
	out["open_path_count"] = PathState.ALL.size() - def.closed_paths.size()
	out["realm_ceiling"] = def.realm_ceiling
	out["lifespan"] = def.lifespan
	out["is_baseline"] = def.tags.has(RaceDef.BASELINE_TAG)
	for key in def.affinities.keys():
		out["affinities"][String(key)] = float(def.affinities[key])
	return out


## The actor's versioned ledger exactly as core persists it. This is the payload a save
## carries, so a caller never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return RaceState.empty()
	return RaceState.normalize(actor.get_module_data(MODULE_KEY), _known_races())


## Every authored race id, canonically ordered.
static func race_ids() -> Array[StringName]:
	return RaceCatalog.instance().race_ids()


# --- Internals ---------------------------------------------------------------


static func _known_races() -> Dictionary:
	var out := {}
	for race_id in RaceCatalog.instance().race_ids():
		out[String(race_id)] = true
	return out


static func _view(def: RaceDef, held: bool) -> Dictionary:
	return {
		"id": String(def.id),
		"held": held,
		"display_name": def.display_name,
		"description": def.description,
		"closed_paths": _string_list(def.closed_paths),
		"open_path_count": PathState.ALL.size() - def.closed_paths.size(),
		"realm_ceiling": def.realm_ceiling,
		"lifespan": def.lifespan,
		"dominance": def.dominance,
		"manifestation_threshold": def.manifestation_threshold,
		"affinity_count": def.affinities.size(),
		"tags": _string_list(def.tags),
	}


static func _string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
