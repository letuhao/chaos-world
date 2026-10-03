class_name TechniqueDelivery
extends RefCounted

## The delivery seam: an item that is a technique MANUAL, studied by `items`, and
## the `CodexEntry` that results (ADR 0053, ADR 0056, DEF-0151).
##
## ## Why this is a class and not a facade method
##
## `TechniquesApi` is at `MAX_FACADE_PUBLIC_METHODS` (12) and ADR 0056 records that
## the cap binds immediately, so this cannot become a 13th `static func`. It is
## reached the same way `TechniqueCasting` is reached — a named type in this module,
## published as a CONSTANT on the facade rather than as a method on it:
##
## ```
## var seam := TechniqueDelivery.installed()
## var learned := TechniqueDelivery.study(seam, actor, item_def, instance)
## ```
##
## `TechniqueDelivery.installed()` is the composition-root-installed seam, and
## `TechniqueDelivery.study` is the one call `items` makes. Neither is on
## `TechniquesApi`, so the facade stays at exactly twelve. See
## `technique_casting.gd` for the same argument about `CASTING_COMPONENT`.
##
## ## Why the SEAM is a Callable and not a direct call
##
## `ItemUse._apply_learned` lives in `modules/items/`. Naming `TechniquesApi` from
## there would be an edge `items -> techniques`, and a bare class reference out of
## `modules/*` is not even an edge the checker sees (`BARE_REF_UNITS` in
## `tools/arch/rules.py` excludes `modules/*`), so it would have been an UNDECLARED
## dependency rather than a real one. `items` declares no such dependency and must
## not grow one. So `items` calls this seam, and `app/` — the composition root,
## which may depend on anything by construction (`LAYER_DEPS["app"] == {"*"}`) —
## binds it. This is the exact pattern `technique_casting.gd` already documents for
## the damage pipeline: the edge is made where the edge is legal, and this module
## stays ignorant of who bound it.
##
## ## What this seam DOES NOT do
##
## It never equips, never applies a passive, and never touches a slot. Those are
## three separate states with three owners of truth (ADR 0053), and an acquisition
## that also did either of the others would mean a single mis-click both bought a
## permanent investment and spent a limited slot on it. ADR 0054 says the same
## about a learned passive in particular: learning a technique must never make it
## contribute, and this file is where that is enforced rather than merely intended.
##
## So [method study] performs exactly one write: a codex row. The item is consumed
## by its caller (`ItemsApi.use_item` owns removal), and the three states stay three.

## The id key a delivery outcome carries, so a caller reports "studied X" without
## re-deriving which manual it held. Read by nothing in this module.
const LEARNED_FROM := &"learned_from"

## The `ProjectSettings` key the seam is published under, and the one `items` reads.
## It is a String rather than a class reference so `ItemUse` can reach the seam
## without naming any technique type — no `res://` path, no registry entry, and
## therefore no `items -> techniques` edge for `tools/arch` to have to bless. `app/`
## is the only place that may write it, and it may depend on anything by
## construction (`LAYER_DEPS["app"] == {"*"}`).
const SETTING := "technique/delivery_seam"

## The composition-root seam `items` calls:
## `func(actor: Actor, technique_id: StringName) -> Dictionary`.
##
## A `static var` rather than a field, because the INSTALL is a fact about how this
## process was wired, not about any actor: a headless test that never installs one
## must be able to ask "is anything bound?" and be told no, rather than silently
## sharing whatever a previous suite left behind. `run_tests.gd` documents that
## hazard by name — it calls `teardown` after every test precisely because a
## process-wide binding leaks between suites.
static var _bound: Callable = Callable()


## Install the seam `items` will call. `app/` calls this once at boot; a test calls
## it and then `clear()` in `teardown`. Passing an empty Callable CLEARS it, so a
## caller can uninstall deterministically rather than only by overwriting.
##
## Publishing is separate from binding on purpose: `_bound` decides whether a
## learner is callable, and the setting decides whether `items` can SEE the seam at
## all. Both are set here so neither half can be installed without the other, and
## both are cleared together — otherwise `items` would call into an unbound seam or
## refuse `no_seam` while a learner sat installed and unreachable.
static func install(learner: Callable) -> void:
	if learner.is_null() or not learner.is_valid():
		clear()
		return
	_bound = learner
	ProjectSettings.set_setting(SETTING, TechniqueDelivery)


## Uninstall. Separate from `install(Callable())` because a suite that asserts the
## unbound behaviour needs to state "nothing bound" explicitly rather than by
## passing a bare default.
static func clear() -> void:
	_bound = Callable()
	if ProjectSettings.has_setting(SETTING):
		ProjectSettings.set_setting(SETTING, null)


## Whether anything is bound. A caller uses this to distinguish "this build cannot
## learn" from "the gate refused", which are different messages to a player.
static func is_bound() -> bool:
	return not _bound.is_null() and _bound.is_valid()


## Study the technique `item_def` delivers, and return the outcome of
## [method TechniquesApi.learn].
##
## ## How an item names the technique it delivers
##
## The item id IS the technique id. Not a mapping table, not a lookup by display
## name, not a guess from shared words: the id is the identity, and
## `TechniqueCatalog.definition` resolves it by id because ADR 0056 makes the
## authored `id` field the save key. A manual whose id no definition claims is
## refused `unknown_technique` rather than resolved to something adjacent, because
## a study that silently taught the wrong technique would be worse than one that
## refused.
##
## `instance` is accepted and UNREAD. It travels through so the seam's signature is
## the one `items` already has in hand (`ItemUse._apply_learned` receives both), and
## so a future rolled-technique design has a parameter to fill rather than a
## signature to change. It is deliberately not consulted today: a codex entry stores
## realized data only when learning realized any (`CodexEntry.realized`), and this
## seam realizes nothing — see the `_realized` note below.
##
## ## Refusals, all of which change NOTHING
##
##   - `not_a_technique`     — null, or a category that is not `technique`. The
##     load-bearing guard: the seam refuses to guess, so an equipment row or a
##     consumable routed here can never become a codex entry.
##   - `no_seam`             — nothing is bound, so there is no learner to call.
##   - `unknown_technique`   — no `TechniqueDef` claims this item's id.
##   - anything `TechniquesApi.learn` itself refuses (`unknown_definition`,
##     `realm_unmet`) is returned VERBATIM, so the gate's own `unmet` list reaches
##     the caller rather than being flattened into a bare reason.
##
## On success the return carries `ok`, `id`, `rung` and [constant LEARNED_FROM], so
## a caller can report which manual delivered the technique.
static func study(actor: Actor, item_def, instance = null) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "unknown_definition"}
	var def_id := StringName(_field(item_def, "id"))
	if def_id == &"" or StringName(_field(item_def, "category")) != ItemCategory.TECHNIQUE:
		return {"ok": false, "reason": "not_a_technique", "id": String(def_id)}
	if not is_bound():
		return {"ok": false, "reason": "no_seam", "id": String(def_id)}
	var technique := TechniqueCatalog.instance().definition(def_id)
	if technique == null:
		return {"ok": false, "reason": "unknown_technique", "id": String(def_id)}
	var produced: Variant = _bound.call(actor, technique.id, null)
	if not produced is Dictionary:
		# A seam that answered with something else taught nothing, and reporting
		# success would consume the manual for a technique nobody can now study.
		return {"ok": false, "reason": "seam_returned_nothing", "id": String(def_id)}
	var outcome: Dictionary = produced
	if not bool(outcome.get("ok", false)):
		return outcome
	outcome[LEARNED_FROM] = String(def_id)
	return outcome


## The seam a caller binds: it receives the resolved `TechniqueDef` id and returns
## `TechniquesApi.learn`'s own outcome. Published so `app/` binds this shape and a
## test can bind a recording double without re-deriving the contract.
##
## `rung` is always 0 from this path. Delivery is ACQUISITION: a manual is worth
## rung 0, and mastery is the long investment ADR 0053 separates from it. Passing a
## higher rung would make a delivery do mastery too, which is the second half of the
## same collapse this seam exists to prevent.
static func bind_learner(actor: Actor, technique_id: StringName, rung: int = 0) -> Dictionary:
	return TechniquesApi.learn(actor, TechniqueCatalog.instance().definition(technique_id), rung)


## Read a property off a duck-typed def without naming its class, so this file
## holds no `res://` reference to `ItemDef` and declares no `techniques -> items`
## edge the registry does not record.
static func _field(source, property: StringName):
	if source == null:
		return null
	var read: Variant = source.get(property)
	return read
