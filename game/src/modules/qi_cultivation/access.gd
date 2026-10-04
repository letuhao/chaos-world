class_name QiAccess
extends RefCounted


## Module-internal accessors, deliberately NOT on the facade (ADR 0095).
##
## `QiCultivationApi` sat at the 12-method ISP cap with five of its twelve being
## accessors that nothing outside this module ever called: `provider`, `path_def`,
## `meridians`, `dantian` and `attach_dantian`. Keeping them there is what stopped
## `attach` from also attaching the dantian — there was no room left for the one
## line that made the whole path work, so the composition root's single call left
## every qi actor without a dantian and every qi action inert. Moving them here
## costs nothing (`tools arch` counts only `api.gd`) and leaves the facade
## publishing verbs.
##
## Three of the five have since been DELETED rather than kept warm (BL-0787).
## `dantian` and `attach_dantian` stay because six call sites in this module read
## them; the other three had no caller in `src/`, `tests/` or `tools/` at all:
##
## - `path_def()` — a pass-through to `QiPath.path_def()`, one call, no logic.
## - `meridians(actor)` — a pass-through to `actor.meridians`, which every caller
##   already reads directly; this file's own neighbours do it unguarded.
## - `provider(actor)` — see below. It was the one genuinely TRAPPIED member.
##
## ## `provider()` is gone rather than made loud, and why that is the same thing
##
## It ended with `return QiProvider.new()` when no provider was registered: an
## UNATTACHED provider, contributed by nothing, handed back with full confidence.
## Any caller trusting it got a working-looking object that silently supplied no
## stat — the failure mode this program keeps paying for, where a second,
## divergent source of truth makes the wrong read look like a working one
## (ADR 0057). The one caller in the tree asserted `!= null`, which that fallback
## makes unconditionally true, so the trap was not merely unfished: its only test
## could not fail.
##
## Making the absence loud was the alternative, and it is the wrong one here:
## a loud version is a guard with no caller, so it would be a fourth dead member
## wearing an assertion's clothes. The trap is unfishable because the trapdoor
## is deleted — a caller that wants the provider now has to ask the actor's own
## provider list, where a missing provider is visible instead of manufactured.
static func dantian(actor: Actor) -> Dantian:
	return actor.component(&"dantian") as Dantian


## The dantian is not an optional component: `cultivate`, `recover`, the preview
## and the breakthrough condition all refuse an actor without one. It is created
## here, once, and is idempotent so a caller that already attached it is harmless.
static func attach_dantian(actor: Actor) -> Dantian:
	var existing := actor.component(&"dantian") as Dantian
	if existing != null:
		return existing
	var dantian := Dantian.new()
	dantian.structural_capacity = actor.stats.get_base(QiStats.DANTIAN_CAPACITY)
	actor.set_component(&"dantian", dantian)
	actor.stats.add_provider(DantianProvider.new())
	return dantian
