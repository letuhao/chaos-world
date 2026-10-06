class_name BloodlineProjection
extends RefCounted

## Rebuilds an actor's whole bloodline contribution from the ledger, and keeps the
## `Actor.traits` mirror in step with it.
##
## **Derived, never stored.** The ledger is the only truth; this class is the one place
## that turns it into stat modifiers, trait ids and the summary component a pure
## provider reads. A save can be restored, replayed or normalized and the projection is
## simply recomputed, so it can never drift from the ledger or double-count.
##
## **Strip-then-rebuild is what makes a purity change safe.** Purity is monotonically
## decaying within an actor's life (ADR 0063), so a lineage crosses its threshold at
## most once — downward. But the projection still has to be idempotent for the other
## paths into it: a restored save re-attaches, a conception rewrites the ledger, and
## every one of those must land exactly once. Removing this module's sources first and
## rebuilding from the ledger is the only formulation with that property.
##
## A second, parallel stat fold is forbidden (ADR 0026). The projection reuses
## `actor.stats.add_modifier` exactly as an authored trait does.

## `actor.components` slot holding the derived `BloodlineSummary`.
const SUMMARY_COMPONENT := BloodlineSummary.COMPONENT
## Alias kept so `BloodlineApi` reads the way `RaceApi` does. Both name one slot.
const DEF_COMPONENT := SUMMARY_COMPONENT


## Project `ledger` onto `actor`. Idempotent by construction: everything this module
## owns is stripped first, then rebuilt from the ledger.
##
## For every lineage in the ledger: if `def.is_awake(purity)` its PERCENT modifiers
## are added, and the `bloodline:<id>` trait mirror is added **whether or not it is
## awake**. A dormant lineage is exactly what a lineage screen exists to show, and
## `has_trait` is how it is read — dropping the mirror while asleep would make a
## sleeping bloodline indistinguishable from no bloodline at all, which is the one
## thing a player must never be unable to tell.
static func apply(actor: Actor, ledger: Dictionary) -> void:
	if actor == null:
		return
	var next := BloodlineState.normalize(ledger)
	strip(actor)
	var catalog := BloodlineCatalog.instance()
	var applied := {}
	for lineage_id in BloodlineState.lineage_ids(next):
		var def := catalog.bloodline_definition(lineage_id)
		var purity := BloodlineState.purity(next, lineage_id)
		# The mirror goes on first and unconditionally; only the modifiers wait for
		# the gate.
		actor.traits.add(BloodlineState.trait_for(lineage_id))
		var traits: Array[StringName] = [BloodlineState.trait_for(lineage_id)]
		if def != null and def.is_awake(purity):
			# ADR 0125's instability counterpart: the spike elevates purity past
			# the awaken gate, but the body struggles to stabilise foreign blood,
			# so the lineage's own authored modifiers arrive discounted by the
			# read-time factor -- never the gate itself, which stays binary. The
			# builders mint fresh objects per call, so scaling here touches no
			# shared state.
			var discount := BloodlineState.instability_discount(purity)
			for modifier in def.build_modifiers():
				modifier.value = float(modifier.value) * discount
				actor.stats.add_modifier(modifier)
			for trait_id in def.traits:
				var id := StringName(trait_id)
				if not traits.has(id):
					actor.traits.add(id)
					traits.append(id)
		applied[String(lineage_id)] = _strings(traits)
	next["applied"] = applied
	actor.set_module_data(BloodlineState.MODULE_KEY, next)
	actor.set_component(SUMMARY_COMPONENT, BloodlineSummary.from_ledger(next))


## Remove every contribution this module owns: the stat stack, every trait mirror
## (both the namespaced `bloodline:<id>` one and any authored trait a lineage granted),
## and the summary component.
##
## The ledger records what was actually added, including for content the catalog no
## longer ships — a dropped `.tres` is exactly when those traits would otherwise be
## stranded on the actor with nothing left to take them back with.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := BloodlineState.normalize(actor.get_module_data(BloodlineState.MODULE_KEY))
	for lineage_id in BloodlineState.applied_ids(ledger):
		actor.stats.remove_modifiers_from(BloodlineState.source_for(lineage_id))
		for trait_id in BloodlineState.applied_traits(ledger, lineage_id):
			actor.traits.remove(trait_id)
	if actor.component(SUMMARY_COMPONENT) != null:
		actor.components.erase(SUMMARY_COMPONENT)
	var next := BloodlineState.normalize(ledger)
	next["applied"] = {}
	actor.set_module_data(BloodlineState.MODULE_KEY, next)


## The total a lineage contributes to `stat_id`, read from the modifier stack rather
## than recomputed. A test helper and an inspect aid: reading the stack proves the
## projection actually landed instead of trusting the ledger.
static func contribution(actor: Actor, stat_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if modifier.stat == stat_id and BloodlineState.is_own_source(modifier.source):
			total += modifier.value
	return total


static func _strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
