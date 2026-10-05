class_name RaceProjection
extends RefCounted

## Rebuilds a race's whole contribution onto an actor from the ledger, and keeps the
## `Actor.traits` mirror in step with it.
##
## **Derived, never stored.** The ledger is the only truth; this class is the one place
## that translates it into base attributes, stat modifiers, affinities and trait ids.
## A save can be restored, replayed or normalized and the projection is simply
## recomputed, so it can never drift from the ledger or double-count.
##
## A second, parallel stat fold is forbidden (ADR 0026). The race reuses
## `actor.stats.add_modifier` exactly as an authored trait does.

## `actor.components` slot holding the resolved `RaceDef`, so `RaceProvider` can read it
## out of a `StatContext` and stay pure instead of reaching into the catalog's mutable
## content on every stat query.
const DEF_COMPONENT := &"race_def"


## Project `race_id` onto `actor`. Idempotent by construction: whatever the ledger says
## was applied is stripped first, then the new race is rebuilt. Passing the race the
## ledger already names is therefore free of consequence, which is what lets a save
## restore and re-attach safely.
##
## `&""` is a legal argument and means "no race": the actor keeps whatever it was born
## with in its ledger, and the previous contribution is removed. An id the catalog does
## not define is refused the same way — stripped, recorded as nothing, never guessed.
static func apply(actor: Actor, race_id: StringName) -> void:
	if actor == null:
		return
	var ledger := _ledger(actor)
	strip(actor)
	var def := RaceCatalog.instance().race_definition(race_id)
	if def == null:
		_write(actor, ledger)
		return
	for modifier in def.build_modifiers():
		actor.stats.add_modifier(modifier)
	# Base attributes and affinities are grants, not modifiers, so the ledger records
	# exactly what was handed out — see the note in `strip`.
	_grant(actor, def)
	actor.traits.add(RaceState.trait_for(def.id))
	actor.set_component(DEF_COMPONENT, def)
	var next := RaceState.normalize(ledger)
	next["race"] = String(def.id)
	next["applied_race"] = String(def.id)
	next["granted"] = {
		String(def.id):
		{
			"attributes": _number_record(def.base_attributes),
			"affinities": _number_record(def.affinities),
		}
	}
	_write(actor, next)


## Remove every contribution this module owns: the stat stack, the trait mirror, the
## `race_def` component, the base attributes already handed out, and the affinities.
##
## **Why the ledger has to remember a grant.** A `StatModifier` cannot LOWER a base
## attribute, and `AffinityMap` has no additive or scoped set — both are absolute values.
## So "strip" is impossible without knowing what was granted, and the ledger stores the
## granted numbers rather than re-reading the definition. That is also why stripping
## works for a race whose `.tres` has since been deleted: there is nothing to look up,
## only a number to take back.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := _ledger(actor)
	var applied := RaceState.applied_race(ledger)
	if applied != &"":
		actor.stats.remove_modifiers_from(RaceState.source_for(applied))
		actor.traits.remove(RaceState.trait_for(applied))
		var record := RaceState.grants(ledger, applied)
		_ungrant_base_attributes(actor, record)
		_ungrant_affinities(actor, record)
	if actor.component(DEF_COMPONENT) != null:
		actor.components.erase(DEF_COMPONENT)
	var next := RaceState.normalize(ledger)
	next["applied_race"] = ""
	next["granted"] = {}
	_write(actor, next)


## The total a race contributes to `stat_id`, read from the modifier stack rather than
## recomputed. A test helper and an inspect aid: reading the stack proves the projection
## actually landed instead of trusting the ledger.
static func contribution(actor: Actor, stat_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if modifier.stat == stat_id and RaceState.is_own_source(modifier.source):
			total += modifier.value
	return total


## Add the race's authored base attributes and affinities.
##
## Both are applied ADDITIVELY on top of whatever is already on the actor rather than
## replacing it: a character sheet is the player's own build and the race is a body it
## was born into. Strip subtracts the same amounts, which is what makes the pair
## exactly reversible — see `strip`.
static func _grant(actor: Actor, def: RaceDef) -> void:
	for key in def.base_attributes.keys():
		var stat_id := StringName(key)
		var granted := float(def.base_attributes[key])
		actor.stats.set_base(stat_id, actor.stats.get_base(stat_id) + granted)
	for key in def.affinities.keys():
		var element_id := StringName(key)
		var held := actor.affinities.get_value(element_id)
		actor.affinities.set_value(element_id, held + float(def.affinities[key]))


## Take back exactly what `_grant` handed out, and only that.
##
## The affinity map is NOT cleared: other modules grant affinities into the same map,
## and wiping it would destroy their contributions along with ours. Subtracting our own
## recorded amount leaves a stranger's grant exactly where it was. The value is floored
## at zero because a negative affinity is meaningless and a stranger who lowered the
## value below ours must not be pushed further down by our removal.
static func _ungrant_base_attributes(actor: Actor, record: Dictionary) -> void:
	var attributes: Dictionary = record.get("attributes", {})
	for key in attributes.keys():
		var stat_id := StringName(key)
		actor.stats.set_base(
			stat_id, maxf(0.0, actor.stats.get_base(stat_id) - float(attributes[key]))
		)


static func _ungrant_affinities(actor: Actor, record: Dictionary) -> void:
	var affinities: Dictionary = record.get("affinities", {})
	for key in affinities.keys():
		var element_id := StringName(key)
		actor.affinities.set_value(
			element_id, maxf(0.0, actor.affinities.get_value(element_id) - float(affinities[key]))
		)


## The ledger as stored, unfiltered. Filtering against the catalog is the facade's job at
## attach time; the projection only needs to know what is currently applied, and must be
## able to read that even for content the catalog no longer ships.
static func _ledger(actor: Actor) -> Dictionary:
	return RaceState.normalize(actor.get_module_data(RaceState.MODULE_KEY))


static func _write(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(RaceState.MODULE_KEY, ledger)


static func _number_record(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source.keys():
		var value = source[key]
		if value is float or value is int:
			out[String(key)] = float(value)
	return out
