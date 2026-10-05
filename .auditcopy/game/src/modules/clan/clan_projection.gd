class_name ClanProjection
extends RefCounted

## Rebuilds an actor's whole clan contribution from the ledger, and keeps the
## `Actor.traits` mirrors in step with it.
##
## **Derived, never stored.** The ledger is the only truth; this class is the one place
## that turns it into trait ids and the summary component a pure provider reads. A save
## can be restored, replayed or normalized and the projection is simply recomputed, so
## it can never drift from the ledger or double-count.
##
## ## It grants NO stat. At all. This is the design, not an omission.
##
## ADR 0064: a clan hands out **recognition, never power**. So `apply` adds no
## `StatModifier`, calls no `set_base`, and touches no affinity. The only things it
## writes are two `Actor.traits` mirrors — `clan:<id>` and `clan_rank:<rank>` — and a
## `clan_summary` component. `standing` is a number a reputation system composes
## against; it is not a combat value, and a module that granted one would hand a
## player power for being recognised.
##
## A second, parallel stat fold would be forbidden regardless (ADR 0026); here there
## simply is no first fold to be second to.
##
## Strip-then-rebuild is what makes this idempotent, which matters because a restored
## save re-attaches, a `join` re-projects, and every one of those must land exactly
## once. Mirrors that were added for a clan the catalog has since dropped would
## otherwise be stranded, which is why the ledger records what was actually applied
## rather than trusting the current definition.

## `actor.components` slot holding the derived `ClanSummary`, so `ClanProvider` can
## read it out of a `StatContext` and stay pure instead of reaching into the catalog's
## mutable content on every stat query.
const SUMMARY_COMPONENT := ClanSummary.COMPONENT
## Alias kept so `ClanApi` reads the way `RaceApi` does. Both name one slot.
const DEF_COMPONENT := SUMMARY_COMPONENT


## Project `ledger` onto `actor`. Idempotent by construction: everything this module
## owns is stripped first, then rebuilt.
##
## Both mirrors go on UNCONDITIONALLY once a clan is named, and the rank mirror goes on
## only while a position is actually held. That asymmetry is deliberate: a member with
## no position is a real and interesting state, and dropping the clan mirror for them
## would make a clan's inner member indistinguishable from an outsider — which is the
## one thing a social screen must never be unable to tell.
static func apply(actor: Actor, ledger: Dictionary) -> void:
	if actor == null:
		return
	var next := ClanState.normalize(ledger)
	strip(actor)
	var clan_id := ClanState.clan_id(next)
	var rank := ClanState.rank(next)
	var applied := {}
	if clan_id != &"":
		actor.traits.add(ClanState.trait_for(clan_id))
		applied["clan"] = String(clan_id)
		if rank != &"":
			actor.traits.add(ClanState.rank_trait_for(rank))
			applied["rank"] = String(rank)
	next["applied"] = applied
	actor.set_module_data(ClanState.MODULE_KEY, next)
	actor.set_component(SUMMARY_COMPONENT, ClanSummary.from_ledger(next))


## Remove every contribution this module owns: the trait mirrors and the summary
## component. **No stat modifiers are removed, because none were ever added** — see the
## class note. The call below is a belt-and-braces sweep for content authored before
## this rule, and it is a no-op on any current build.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := ClanState.normalize(actor.get_module_data(ClanState.MODULE_KEY))
	for source in _own_sources(actor):
		actor.stats.remove_modifiers_from(source)
	for trait_id in _applied_traits(ledger):
		actor.traits.remove(trait_id)
	if actor.component(SUMMARY_COMPONENT) != null:
		actor.components.erase(SUMMARY_COMPONENT)
	var next := ClanState.normalize(ledger)
	next["applied"] = {}
	actor.set_module_data(ClanState.MODULE_KEY, next)


## The total a clan contributes to `stat_id`. **Always 0.0**, and that is the assertion
## ADR 0064 makes executable: a clan cannot move a stat, so this has nothing to sum.
## It exists so a test can read the rule through the same lens a stat read would use.
static func contribution(actor: Actor, stat_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if modifier.stat == stat_id and ClanState.is_own_source(modifier.source):
			total += modifier.value
	return total


## Every `Actor.traits` id the ledger records as projected, including for a clan the
## catalog no longer ships — a dropped `.tres` is exactly when a mirror would otherwise
## be stranded with nothing left to take it back with.
static func _applied_traits(ledger: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var record := ClanState.applied(ledger)
	var clan_id := String(record.get("clan", ""))
	if clan_id != "":
		out.append(ClanState.trait_for(StringName(clan_id)))
	var rank := String(record.get("rank", ""))
	if rank != "":
		out.append(ClanState.rank_trait_for(StringName(rank)))
	return out


## Modifier sources on the actor tagged as this module's. Empty on every current build;
## a test asserts it stays that way.
static func _own_sources(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for modifier in actor.stats._modifiers:
		if ClanState.is_own_source(modifier.source):
			out.append(modifier.source)
	return out
