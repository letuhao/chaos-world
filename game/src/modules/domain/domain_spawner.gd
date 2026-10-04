class_name DomainSpawner
extends RefCounted

## Mints the `Actor`s a domain's spawn refs name (ADR 0074).
##
## **One return type. There is no `MobActor`, no `NpcActor`, no mini-boss class.** A mob, a
## mini-boss, a boss, an npc and a rival cultivator all come out of `spawn` as the same `Actor`
## the player is, because that is what the game is: `Actor` is the base for every pc, npc and
## mob, and a role is a `StringName` on `Actor.tags`. A caller that wants to know what it is
## holding asks `role_of` / `has_role`, and damage resolution never asks — it reads stats.
##
## **A role changes nothing here.** There is deliberately no `if role == "boss"` anywhere in
## this file, because three mechanisms that each branch on a role are three mechanisms that
## disagree (the same rule ADR 0067 states for `path_id`). A mini-boss is an `InhabitantDef`
## with a bigger `base` and a higher `realm_id`: a bigger number and a tag, which is exactly
## what "different magnitudes, same class" means. When a mechanism seems to want a role
## branch, the number belongs on the def.
##
## **Unknown input fails loudly.** An unknown role is refused, never defaulted to `npc`; a ref
## naming an inhabitant the catalog does not ship is reported by name and mints no Actor, never
## a placeholder that something downstream would mistake for content.
##
## ## The constructor seam (ADR 0002)
##
## `set_minter` injects TWO contacts, because a path and the machinery that mounts it are two
## different questions and only `app/` can answer the second one.
##
## `minter` is the actor constructor. This module declares `core` + `contracts` only
## (`tools/arch/registry.json`), so it cannot itself reach `qi_cultivation`'s facade to enrol a
## cultivation path with the player's full provider set — and it must not widen its own
## dependency list to do it. So `app/` installs a minter that assembles the actor through
## `ActorFactory`, which is the same spine the player is built from, and the default below is
## the core-only half of it. `NpcApi.set_minter` is the same seam for the same reason.
##
## `enroller` is the CULTIVATION half: `Callable(actor: Actor, realm_id: StringName) -> void`.
## `_enrol_cultivator` is the one place that asks whether a species cultivates — the def's
## authored `cultivates` — and it can only answer `actor.set_path(...)`, which is a label.
## `QiTraining.synchronize` is what sizes the dantian, unlocks the meridians and caps the
## reservoir to the realm, and it lives in a module this one may not name. BL-0753: for its
## whole life `_enrol_cultivator` wrote a `PathState` and nothing else, so six of the nine
## shipped species were realm-scaled rivals who could not cultivate, break through, or even
## preview. `app/` answers this contact with the same `_attach_qi` verb every other qi entry
## point uses, so there is exactly one place that mounts a qi rig. `DomainFixtures.set_minter`
## takes its two contacts the same way.

## The `actor.module_data` key placement and role provenance persist under. It is ordinary
## module data, so it round-trips through `Actor.to_dict()` / `from_dict()` — there is no
## bespoke spawner save path and no second file format.
const MODULE_KEY := &"domain_spawn"

## The tag a hostile species carries. Content reads this; nothing branches on it in a
## mechanism (ADR 0074).
const HOSTILE_TAG := &"hostile"

## Ceiling on one spawn ref's `count`. A ref is authored data, and a hand-edited `count` of
## ten million is a defect that must fail out loud rather than mint ten million Actors and fill
## the disk. One step over is refused by name.
const MAX_COUNT_PER_REF := 64

## The contacts `app/` installs, and what each is for. `minter` is
## `Callable(id: StringName, base: Dictionary) -> Actor`; `app/` passes a static over
## `ActorFactory` so an inhabitant gets the identical provider set the player gets.
## `enroller` is `Callable(actor: Actor, realm_id: StringName) -> void` and is what turns a
## `PathState` into a cultivator; a null one leaves the core-only `set_path` default, which
## is a labelled rival and nothing more (BL-0753). `app/` answers it with
## `ActorFactory.enrol_inhabitant_qi`, which routes to the same `_attach_qi` as every other
## qi entry point, so there is no second way to mount a qi rig.
static var _minter: Callable = Callable()
static var _enroller: Callable = Callable()


## Install the actor constructor and the cultivation enroller. Both optional: a null
## `minter` restores the default core spine and a null `enroller` restores the core-only
## enrolment. Idempotent.
static func set_minter(minter: Callable, enroller: Callable = Callable()) -> void:
	_minter = minter
	_enroller = enroller


## Mint one inhabitant.
##
## Returns null — loudly, never a default — for a null def, a role outside the closed set, or a
## def that declares it cultivates while authoring no realm to cultivate at.
static func spawn(def: InhabitantDef, role: StringName) -> Actor:
	if def == null:
		push_error("DomainSpawner.spawn: no InhabitantDef; nothing was spawned")
		return null
	if not DomainRoles.is_valid(role):
		push_error(
			(
				(
					"DomainSpawner.spawn: role '%s' is not in the closed set; allowed: %s. A role is "
					+ "a tag, not a class, and an unknown one is refused rather than defaulted."
				)
				% [String(role), ", ".join(_role_names())]
			)
		)
		return null
	if def.cultivates and def.realm_id == &"":
		push_error(
			(
				(
					"DomainSpawner.spawn: inhabitant '%s' declares it cultivates but authors no realm_id; "
					+ "a rival cultivator with no realm is a mob with a name."
				)
				% String(def.inhabitant_id)
			)
		)
		return null
	var actor := _mint(def)
	if actor == null:
		return null
	actor.display_name = def.display_name
	_stamp(actor, def, role)
	# Provenance is recorded HERE, by the one place that knows the role, rather than by the
	# map walk: an actor minted by a direct `spawn` call carries its role exactly as one minted
	# through `spawn_map` does. `spawn_map` then merges the placement into the same slot.
	_remember(actor, role)
	if def.cultivates:
		_enrol_cultivator(actor, def)
	# The realm magnitude the player earns at a breakthrough applies to an inhabitant born at
	# that realm. Read from `core`, keyed by realm id (ADR 0050), and a no-op for a species
	# with no path — so a mob is not scaled by a realm it does not have.
	RealmScaling.apply(actor)
	actor.mark_stats_dirty()
	return actor


## Walk `map.spawn_refs()` in canonical order and mint one Actor per instance, honouring each
## ref's `count`.
##
## `catalog` maps `inhabitant_id -> InhabitantDef`. A ref naming an id the catalog does not ship
## is reported by room, ref and id, and mints NOTHING — a placeholder would be an actor that
## looks like content and answers for none.
##
## `position_of` is `Callable(room_id: StringName, ref_id: String, index: int) -> Vector2`. It
## is required: a spawn whose place cannot be resolved is not a spawn, and a placement that
## cannot be asked for is a defect worth naming. The resolved point is recorded in
## `module_data` under [constant MODULE_KEY], so it persists through the ordinary actor payload.
static func spawn_map(map: DomainMap, catalog: Dictionary, position_of: Callable) -> Array[Actor]:
	var out: Array[Actor] = []
	if map == null:
		push_error("DomainSpawner.spawn_map: no DomainMap; nothing was spawned")
		return out
	if position_of.is_null():
		push_error(
			"DomainSpawner.spawn_map: position_of is required; a spawn with no place is not a spawn"
		)
		return out
	for ref in map.spawn_refs():
		var inhabitant_id := StringName(ref.get("inhabitant_id", ""))
		var def := _resolve(catalog, inhabitant_id)
		if def == null:
			push_error(
				(
					(
						"DomainSpawner.spawn_map: room '%s' ref '%s' names inhabitant '%s' and the "
						+ "catalog does not ship it; no Actor minted."
					)
					% [
						String(ref.get("room_id", "")),
						String(ref.get("ref_id", "")),
						String(inhabitant_id)
					]
				)
			)
			continue
		var role := StringName(ref.get("role", ""))
		var count := int(ref.get("count", 1))
		if count < 1:
			push_error(
				(
					(
						"DomainSpawner.spawn_map: room '%s' ref '%s' asks for %d instances; a spawn "
						+ "ref mints at least one."
					)
					% [String(ref.get("room_id", "")), String(ref.get("ref_id", "")), count]
				)
			)
			continue
		if count > MAX_COUNT_PER_REF:
			push_error(
				(
					(
						"DomainSpawner.spawn_map: room '%s' ref '%s' asks for %d instances, over the "
						+ "%d ceiling; refused rather than minting a population nobody authored."
					)
					% [
						String(ref.get("room_id", "")),
						String(ref.get("ref_id", "")),
						count,
						MAX_COUNT_PER_REF,
					]
				)
			)
			continue
		for index in range(count):
			var actor := spawn(def, role)
			if actor == null:
				break
			out.append(_place(actor, ref, position_of, index))
	return out


## The role stamped on `actor`, or `""` when it was not minted by this spawner. Read from
## `module_data`, so a save/load cycle answers the same as the live actor does.
static func role_of(actor: Actor) -> StringName:
	if actor == null:
		return &""
	return StringName(_bookkeeping(actor).get("role", ""))


## Whether `actor` carries `role` as a tag. The role is data on the actor, so this is the whole
## question "is this a boss?" — and it never asks what class `actor` is.
static func has_role(actor: Actor, role: StringName) -> bool:
	return actor != null and actor.tags.has(role)


## Whether `actor` was authored hostile. The def decides; the role only permits.
static func is_hostile(actor: Actor) -> bool:
	return actor != null and actor.tags.has(HOSTILE_TAG)


## Where `actor` was placed, or `Vector2.ZERO` when it carries no recorded placement.
static func placement(actor: Actor) -> Vector2:
	var box: Array = _bookkeeping(actor).get("position", [])
	return Vector2(float(box[0]), float(box[1])) if box.size() == 2 else Vector2.ZERO


## The room `actor` was spawned into, or `""`.
static func room_of(actor: Actor) -> StringName:
	return StringName(_bookkeeping(actor).get("room_id", ""))


# --- internals ---------------------------------------------------------------


## Build the actor. The injected minter is the full spine `app/` owns; the default is the core
## half of it: core resource pools and the three core high-tier providers, the same ones
## `ActorFactory.attach_high_tier` registers for the player.
static func _mint(def: InhabitantDef) -> Actor:
	var base := _resolve_base(def)
	if not _minter.is_null():
		var injected := _minter.call(def.inhabitant_id, base) as Actor
		if injected == null:
			push_error(
				(
					"DomainSpawner: the installed minter returned null for '%s'; nothing was spawned"
					% String(def.inhabitant_id)
				)
			)
			return null
		return injected
	var actor := Actor.new(def.inhabitant_id, base)
	actor.attach_core_resources()
	attach_high_tier(actor)
	return actor


## The core high-tier providers. Mirrors `ActorFactory.attach_high_tier` deliberately: these are
## `core/` classes, so a default-minted inhabitant answers `inside_world_stability`,
## `world_stability` and `ascension_stage` from exactly the providers the player answers them
## from.
static func attach_high_tier(actor: Actor) -> Actor:
	actor.stats.add_provider(InsideWorldProvider.new())
	actor.stats.add_provider(WorldCreationProvider.new())
	actor.stats.add_provider(AscensionProvider.new())
	return actor


## Stamp the role and the authored tags onto the actor. Tags are `Array[StringName]` and
## `Actor.to_dict()` serialises them, so the role survives a save with no help from here.
static func _stamp(actor: Actor, def: InhabitantDef, role: StringName) -> void:
	if not actor.tags.has(role):
		actor.tags.append(role)
	for tag in def.tags:
		if not actor.tags.has(tag):
			actor.tags.append(tag)
	# Hostility is the def's authored opt-in, gated by the role's permission, and it lands as a
	# TAG like every other property of a role.
	if def.hostile and DomainRoles.is_hostile(role) and not actor.tags.has(HOSTILE_TAG):
		actor.tags.append(HOSTILE_TAG)


## A real `PathState` at the def's realm, WITH the machinery behind it. This is the whole
## difference between a rival cultivator and a mob with a name: it can cultivate, break
## through and be saved mid-cultivation, because it is enrolled rather than dressed up.
##
## ## Why the enroller is asked for the realm and not the def
##
## It runs AFTER `_mint` (see `spawn`), so `app/` never sees the def — only this call's
## two arguments — and a def is not a thing this module may hand across the seam. `realm_id`
## is the whole of what mounting a path means, and it is the one thing `_enrol_cultivator`
## reads off the def. `spawn` calls this exactly once per instance, so `attach` runs once
## per actor — which it must, because `QiCultivationApi.attach` appends its provider
## unguarded.
##
## ## The default below is the label, and that is the point
## Without an enroller this is a `PathState` and nothing else: no dantian, no qi provider, no
## `QiTraining.synchronize`, no meridian unlock — so `QiTraining.cultivate` and
## `QiBreakthroughCondition.can_breakthrough` both refuse and `preview` answers `no_dantian`.
## That is the core-only spine this module is allowed to build by itself, and it is why
## `RealmScaling.apply` below reading a realm no actor can use is a defect to report rather
## than a shape to keep. `app/` installs the enroller and the difference closes.
static func _enrol_cultivator(actor: Actor, def: InhabitantDef) -> void:
	if not _enroller.is_null():
		_enroller.call(actor, def.realm_id)
		return
	actor.set_path(PathState.new(PathState.QI, def.realm_id))


## Record where this instance went, merging the placement into the role provenance `spawn`
## already wrote. Module data, so the ordinary actor payload carries it.
static func _place(actor: Actor, ref: Dictionary, position_of: Callable, index: int) -> Actor:
	var room_id := StringName(ref.get("room_id", ""))
	var ref_id := String(ref.get("ref_id", ""))
	var point: Variant = position_of.call(room_id, ref_id, index)
	if not (point is Vector2):
		push_error(
			(
				(
					"DomainSpawner.spawn_map: position_of returned %s for room '%s' ref '%s' index %d, "
					+ "not a Vector2; the Actor is minted but unplaced."
				)
				% [str(point), String(room_id), ref_id, index]
			)
		)
		return actor
	var record := _bookkeeping(actor)
	record["room_id"] = String(room_id)
	record["ref_id"] = ref_id
	record["position"] = [(point as Vector2).x, (point as Vector2).y]
	actor.set_module_data(MODULE_KEY, record)
	return actor


## Stamp the role provenance onto the actor, merging into whatever is already recorded so a
## second call never discards a placement.
static func _remember(actor: Actor, role: StringName) -> void:
	var record := _bookkeeping(actor)
	record["role"] = String(role)
	record["inhabitant_id"] = String(actor.id)
	actor.set_module_data(MODULE_KEY, record)


static func _bookkeeping(actor: Actor) -> Dictionary:
	return actor.get_module_data(MODULE_KEY) if actor != null else {}


## The authored base attributes. An authored realm with an empty `base` is a real content
## shape — a rival whose strength IS its realm — so an empty map is passed through, never
## invented.
static func _resolve_base(def: InhabitantDef) -> Dictionary:
	return def.base.duplicate()


## Look `inhabitant_id` up in a catalog keyed by either `String` or `StringName`, because a
## `.tres` loader and a hand-built test dictionary do not agree on which. Null rather than a
## guess: a spawn ref that names nothing must be refused by the caller, not resolved to the
## first entry.
static func _resolve(catalog: Dictionary, inhabitant_id: StringName) -> InhabitantDef:
	var found: Variant = catalog.get(inhabitant_id, null)
	if found == null:
		found = catalog.get(String(inhabitant_id), null)
	return found as InhabitantDef


static func _role_names() -> Array[String]:
	var out: Array[String] = []
	for role in DomainRoles.ROLES:
		out.append(String(role))
	return out
