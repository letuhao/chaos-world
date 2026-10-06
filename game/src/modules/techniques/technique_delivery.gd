class_name TechniqueDelivery
extends RefCounted

## The delivery seam: an item that is a technique MANUAL, studied by `items`, and
## the `CodexEntry` that results (ADR 0053, ADR 0056, DEF-0151).
##
## ## Why this is a class and not a facade method
##
## `TechniquesApi` publishes this as a CONSTANT rather than as a method on it. It is
## reached the same way `TechniqueCasting` is reached — a named type in this module.
## ADR 0056 forced that shape with a twelve-verb cap that ADR 0265 removed; cohesion
## is what keeps it now:
##
## ```
## var seam := TechniqueDelivery.installed()
## var learned := TechniqueDelivery.study(seam, actor, item_def, instance)
## ```
##
## `TechniqueDelivery.installed()` is the composition-root-installed seam, and
## `TechniqueDelivery.study` is the one call `items` makes. Neither is on
## `TechniquesApi`, because both belong to this module's interior rather than to its
## interface. See `technique_casting.gd` for the same argument about
## `CASTING_COMPONENT`.
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
	# Published as `study` — a Callable to the static entry point — NOT as
	# `TechniqueDelivery` itself. `ProjectSettings` stores a Variant, and a plain
	# `RefCounted` is not one that survives the round trip: it reads back as `null`,
	# so `items` refused `no_seam` against a seam that was demonstrably installed.
	# A Callable IS a first-class Variant, which is why the casting resolver already
	# travels this way.
	ProjectSettings.set_setting(SETTING, Callable(TechniqueDelivery, "study"))


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
## A `TechniqueDef` names the manual that delivers it — [member
## TechniqueDef.delivered_by] — and the seam resolves that claim. The reverse is not
## used: a manual carries no technique vocabulary, because `items` must not grow one
## and an item is a carrier rather than a teacher.
##
## The previous rule was `item.id == technique.id`, and it was exact and
## unfalsifiable: it shipped 1363 manuals against 51 definitions with an
## intersection of ZERO (DEF-0203), so every study refused `unknown_technique` and
## every definition was unobtainable — while the whole suite stayed green, because
## every test registered its own def under its own synthetic manual's id. An identity
## between two independently authored vocabularies is not a contract anyone reviewed;
## it is a collision 51 rows would have to stumble into. The authored field is the
## same claim, stated where it can be read, diffed and reviewed.
##
## **This is not a widened match.** There is no name rule, no tag rule and no family
## rule: an id no def claims still resolves to nothing and is still refused
## `unknown_technique` by name, because a study that silently taught the wrong
## technique would be worse than one that refused. Id equality is KEPT as the second,
## exact path, so a hand-authored pair that already agrees needs no authoring.
##
## `instance` is accepted and UNREAD, and that is a decision rather than an
## omission.
##
## It travels through so the seam's signature is the one `items` already has in
## hand (`ItemUse._apply_learned` receives both). The manual's annotations are NOT
## drawn from it, and this is the whole design: a codex row already stores realized
## annotations (`CodexEntry.realized`, ADR 0196), so a second copy of a carrier
## would need to hand those over — and `ItemUse` strips the instance on use, so
## reading it would make the margin a property of the CARRIER rather than of the
## copy the actor now holds. A manual that drops two different rolled copies in
## two readers' hands would be a bug, not a feature.
##
## What the instance IS good for is provenance: it is the record of what the
## carrier itself rolled, which the module never reads and this seam declines to
## translate into a technique. Study is one codex row, and the annotations on it are
## drawn by `TechniquesApi.learn` from the def.
##
## It is deliberately not consulted today: a codex entry stores
## realized data only when learning realized any (`CodexEntry.realized`), and this
## seam passes nothing into it.
##
## ## Refusals, all of which change NOTHING
##
##   - `not_a_technique`     — null, or a category that is not `technique`. The
##     load-bearing guard: the seam refuses to guess, so an equipment row or a
##     consumable routed here can never become a codex entry.
##   - `no_seam`             — nothing is bound, so there is no learner to call.
##   - `unknown_technique`   — no `TechniqueDef` claims this manual: neither by
##     `delivered_by` nor by an id that matches its own.
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
	var technique := TechniqueCatalog.instance().delivers(def_id)
	if technique == null:
		return {"ok": false, "reason": "unknown_technique", "id": String(def_id)}
	# TWO arguments, not three. `bind_learner` takes `(actor, id, rung = 0)` and
	# `rung` is an `int`: passing `null` in its place made the call throw, and a
	# thrown call left `study` with no value to return — so `items` received `{}`
	# from `_apply_learned`, `use_item` reported an empty outcome, and seven tests
	# reported "asserted nothing". A seam that throws must not look like a seam that
	# declines: that is what an empty dictionary read as.
	var produced: Variant = _bound.call(actor, technique.id)
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
