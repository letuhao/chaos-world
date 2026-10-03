class_name SoulApi
extends RefCounted

## Public facade for the `soul` module (ADR 0127, ADR 0130). Other modules may reference
## ONLY this file (`api.gd`).
##
## ## What a soul is here
##
## A soul is the one piece of state that outlives the body carrying it. When a body dies
## without a guardian item spent, the soul takes damage and the player re-embodies into a
## different arrival; the world does not rewind. That is the whole feature.
##
## ## Where the ledger lives, and why it is not `module_data`
##
## **In an injected store, reached through `set_store`.** `actor.module_data` has the actor's
## lifetime, and a soul exists precisely to outlive it — a ledger stored there dies with the
## exact body it exists to survive, and the failure is silent because every single-actor test
## passes. ADR 0101 named this shape for a world object and owed the persistent store; ADR
## 0128 pays it. The actor mirror is kept ONLY because a save carries it, and it is never
## read as truth.
##
## `set_store` takes any object with `read_ledger()` / `write_ledger(ledger)`, exactly as
## `HoldingsApi.set_store` does. Named that way and never `load` / `save`: those are global
## GDScript builtins, and a `RefCounted` method of that name resolves to the builtin — a
## compile error rather than a loud failure, invisible until the suite runs.
##
## ## No sibling module dependency, on purpose
##
## This facade declares none. It may depend on `core` and `contracts`, which the gate exempts.
## It may NOT depend on `destiny`, because `destiny` earns onto a BODY's `module_data` and the
## next body is a different `Actor` — a declared-but-dead edge is the seam ADR 0065 warns
## about. The edge becomes legal only when the soul carries the whole destiny ledger, which is
## a separate decision.
##
## ## The twelve methods are the cap, deliberately
##
## Fifteen modules already sit at `MAX_FACADE_PUBLIC_METHODS`. `summary()` answers the whole
## screen in one call rather than publishing per-scalar getters, and `state()` hands a caller
## the ledger the save carries rather than making it reach into `module_data`.

## The store's ledger key, and the actor mirror's `module_data` key.
const MODULE_KEY := SoulState.MODULE_KEY

## The tag a consumable carries to be a guardian. Read off `ItemDef.tags`, which already
## exists and which no current rule reads — so this is authored content, not a new item
## category and not a fourth activation channel.
const GUARDIAN_TAG := &"guardian"

## Where the soul is. Null until `set_store` installs one, and the in-memory ledger is the
## documented-wrong default: it is a seam, not an endorsement (ADR 0101).
static var _store: RefCounted = null


## Install the holder for the shared soul ledger — any object with `read_ledger()` and
## `write_ledger(ledger)`. `app/` installs the file-backed store; a test installs
## `SoulWorldLedger`.
##
## `attach` mirrors onto the actor so a single-player save carries the soul, which is the
## ADR 0101 split exactly.
static func set_store(store: RefCounted) -> void:
	_store = store


## Attach the module to `actor`: mirror the ledger onto its `module_data` so the save carries
## it. Idempotent, and safe before any soul exists.
##
## Reads from the STORE and writes the actor copy, never the reverse. A restore that wrote the
## store from the actor would make a save authoritative for the soul, which is the reverse of
## the design.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, SoulState.normalize(_state()))


## The soul as it stands: `{integrity, integrity_max, lives, lives_max, incarnation,
## arrival, body_id, difficulty_id, origins, damage_count, repair_count}`, and `{}` only for a
## null actor.
##
## A soul that has never died still reads, at its authored defaults — a brand-new run HAS a
## soul, and answering "no soul" here would make the first death the first thing that creates
## one. `{}` is reserved for the one question that has no answer.
static func soul(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return _public(_state())


## Damage the soul by `amount`, and record why. The ONLY verb that lowers integrity.
##
## `amount` is authored by the caller — difficulty's share and cap decide it (ADR 0129), never
## this module. Refuses `no_soul` for a null actor and returns the amount APPLIED, so a caller
## that over-reports learns it over-reported rather than announcing a hit nothing took.
static func damage(actor: Actor, amount: int, reason: String) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_soul", "applied": 0, "soul": {}}
	var ledger := _state()
	var applied := SoulState.apply_damage(ledger, amount, reason)
	_persist(actor, ledger)
	return {
		"ok": applied > 0,
		"reason": "" if applied > 0 else "nothing_to_damage",
		"applied": applied,
		"soul": _public(ledger),
	}


## Raise the soul's integrity by `amount`, and record why. Repair only ever raises and never
## past the authored maximum: a soul holding more than its own ceiling would make the ceiling
## decorative.
static func repair(actor: Actor, amount: int, reason: String) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_soul", "applied": 0, "soul": {}}
	var ledger := _state()
	var applied := SoulState.apply_repair(ledger, amount, reason)
	_persist(actor, ledger)
	return {
		"ok": applied > 0,
		"reason": "" if applied > 0 else "already_whole",
		"applied": applied,
		"soul": _public(ledger),
	}


## Spend a guardian item if the actor holds one, and answer whether it did.
##
## Delegates the whole effect to `items`, whose spend is all-or-nothing — so a refused spend
## costs nothing and the guardian path cannot half-fire. NEVER calls back into the death
## handler: this returns whether a guardian was spent, and the caller decides what that means.
static func spend_guardian(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_soul", "def_id": ""}
	for def_id in _guardian_ids(actor):
		var spent := ItemsApi.use_item(actor, def_id, 1)
		if bool(spent.get("ok", false)):
			return {"ok": true, "reason": "", "def_id": String(def_id)}
	return {"ok": false, "reason": "no_guardian", "def_id": ""}


## The verdict for "can this soul re-body, and into what": `{ok, reason, unmet, arrival}`.
## Read-only, and both halves asked at once so a caller cannot read them across a write.
static func verdict(_actor: Actor) -> Dictionary:
	return SoulGate.evaluate(_state(), SoulCatalog.instance())


## The arrival this soul is owed next, or `""`. The GATE's answer, never a list to choose
## from: ADR 0065 forbids the picker this shape would invite.
static func next_arrival(_actor: Actor) -> StringName:
	return SoulGate.next_arrival(_state(), SoulCatalog.instance())


## Record a re-embodiment: one more incarnation, one fewer life, a new body, and the arrival
## the gate chose. The ONE verb that changes bodies.
##
## `body_id` is the new body's id and `arrival_id` is the gate's answer; passing an arrival the
## gate did not choose is refused rather than honoured, because a caller that can name its own
## arrival is the picker ADR 0065 forbids. Idempotent per incarnation: a repeated call for the
## same body writes nothing.
static func reincarnate(actor: Actor, body_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_soul", "incarnation": 0}
	var ledger := _state()
	if not SoulState.has_lives(ledger):
		return {"ok": false, "reason": "no_lives", "incarnation": int(ledger.get("incarnation", 0))}
	if (
		String(ledger.get("body_id", "")) == String(body_id)
		and int(ledger.get("incarnation", 0)) > 0
	):
		return {
			"ok": false,
			"reason": "already_this_body",
			"incarnation": int(ledger.get("incarnation", 0)),
		}
	var arrival_id := SoulGate.next_arrival(ledger, SoulCatalog.instance())
	if arrival_id == SoulGate.NO_ARRIVALS:
		return {
			"ok": false, "reason": "no_arrival", "incarnation": int(ledger.get("incarnation", 0))
		}
	var incarnation := SoulState.incarnate(
		ledger, body_id, arrival_id, SoulCatalog.instance().known_arrivals()
	)
	_persist(actor, ledger)
	return {
		"ok": true,
		"reason": "",
		"incarnation": incarnation,
		"arrival": String(arrival_id),
		"soul": _public(ledger),
	}


## The soul exactly as the save carries it, so a caller never reaches into `module_data`.
static func state(_actor: Actor) -> Dictionary:
	return _state()


## Everything a soul screen needs in one call. Primitives only, and `{}` with no actor.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var ledger := _state()
	var public := _public(ledger)
	public["can_rebody"] = bool(SoulGate.can_rebody(ledger)["ok"])
	public["next_arrival"] = String(SoulGate.next_arrival(ledger, SoulCatalog.instance()))
	public["arrivals_left"] = _arrivals_left(ledger)
	return public


## Content audit: every authored arrival is reachable and well-formed. Same shape as
## `HoldingsApi.validate`, so a tool reads them the same way.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var catalog := SoulCatalog.instance()
	if not catalog.is_loaded():
		problems.append("soul: no authored arrivals loaded")
		return problems
	for arrival_id in catalog.arrival_ids():
		var def := catalog.arrival_definition(arrival_id)
		if def == null:
			problems.append("soul: %s has no definition" % arrival_id)
			continue
		if def.race_id == &"":
			problems.append("soul: arrival %s names no body" % arrival_id)
		if def.display_name.is_empty():
			problems.append("soul: arrival %s has no display name" % arrival_id)
	return problems


# --- Internals -------------------------------------------------------------


## The ledger, from the store when one is installed and from the actor mirror otherwise. The
## actor mirror is the documented-wrong default (ADR 0101) and the reason it is still here is
## that it is what a save carries.
static func _state(_actor: Actor = null) -> Dictionary:
	if _store != null and _store.has_method(&"read_ledger"):
		return SoulState.normalize(_store.call(&"read_ledger"), _known())
	return SoulState.empty()


## Write the store and then the actor mirror. Both, always: the store is truth and the mirror
## is what a save carries, so writing only the store would make a save lose the soul and
## writing only the actor would make the soul die with the body.
static func _persist(actor: Actor, ledger: Dictionary) -> void:
	var normalized := SoulState.normalize(ledger, _known())
	if _store != null and _store.has_method(&"write_ledger"):
		_store.call(&"write_ledger", normalized)
	actor.set_module_data(MODULE_KEY, normalized)


## The known-arrival filter. An empty catalog reports an empty filter, which `normalize` reads
## as "keep everything" — so a tree that failed to load is told apart from a build that ships
## no arrivals, the `DestinyApi._catalog_loaded` problem.
static func _known() -> Dictionary:
	if not SoulCatalog.instance().is_loaded():
		return {}
	return SoulCatalog.instance().known_arrivals()


## The ledger as the rest of the game reads it: every key a String, every number an int, so a
## JSON hop does not turn an amount into a float and stop the ledger comparing equal to
## itself across a save.
static func _public(ledger: Dictionary) -> Dictionary:
	return {
		"integrity": int(ledger.get("integrity", 0)),
		"integrity_max": int(ledger.get("integrity_max", 0)),
		"lives": int(ledger.get("lives", 0)),
		"lives_max": int(ledger.get("lives_max", 0)),
		"incarnation": int(ledger.get("incarnation", 0)),
		"arrival": String(ledger.get("origin_id", "")),
		"body_id": String(ledger.get("body_id", "")),
		"difficulty_id": String(ledger.get("difficulty_id", "")),
		"origins": _strings(ledger.get("origins", [])),
		"damage_count": (ledger.get("damage", []) as Array).size(),
		"repair_count": (ledger.get("repair", []) as Array).size(),
	}


## Every guardian item id the actor holds. Read from the bag's own stack list rather than a
## live scan, so this is the same set the item module would spend from — and the def is asked
## of the bag, which already resolves it, instead of being reconstructed here.
static func _guardian_ids(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	# Asked of the facade rather than reaching into the actor: the bag is the ITEMS module's
	# component and this is the declared `soul -> items` edge, so the guardian check reads the
	# same bag the spend will.
	var bag := ItemsApi.inventory(actor)
	if bag == null:
		return out
	for stack in bag.stacks():
		var def := bag.definition_of(stack.def_id) as ItemDef
		if def != null and (def.tags as Array).has(GUARDIAN_TAG):
			out.append(def.id)
	return out


## How many authored arrivals this soul has not lived through.
static func _arrivals_left(ledger: Dictionary) -> int:
	var held := ledger.get("origins", []) as Array
	var left := 0
	for arrival_id in SoulCatalog.instance().arrival_ids():
		if not held.has(String(arrival_id)):
			left += 1
	return left


static func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
