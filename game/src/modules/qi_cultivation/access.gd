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


static func provider(actor: Actor) -> QiProvider:
	for p in actor.stats._providers:
		if p is QiProvider:
			return p
	return QiProvider.new()


static func path_def() -> CultivationPathDef:
	return QiPath.path_def()


static func meridians(actor: Actor) -> MeridianNetwork:
	return actor.meridians


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
