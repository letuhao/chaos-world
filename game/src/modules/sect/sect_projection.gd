class_name SectProjection
extends RefCounted

## Rebuilds a member's whole sect contribution onto an actor from the ledger, and
## keeps the `Actor.traits` mirror in step with it.
##
## **Derived, never stored.** The ledger is the only truth; this class is the one
## place that turns it into stat modifiers and trait ids. A save can be restored,
## replayed or normalized and the projection is simply recomputed, so it can never
## drift from the ledger or double-count.
##
## ## Strip-then-rebuild, copied verbatim from `RaceProjection` and `BloodlineProjection`
##
## Every entry point into this module — an attach, a join, a promotion, a standing
## change, a restored save — can arrive with a contribution already on the stack.
## Removing this module's own sources first and rebuilding from the ledger is the
## only formulation with that property, and it is why re-attaching is free of
## consequence rather than a source of compounding.
##
## A second, parallel stat fold is forbidden (ADR 0026). The projection reuses
## `actor.stats.add_modifier` exactly as an authored trait does.

## The module's signal bus. It lives on the projection rather than the facade
## because a GDScript signal belongs to an instance and a facade is a namespace of
## statics. Anything that needs to observe a claim connects here, and nothing
## outside the module emits through it.
static var bus: SectEvents = null


static func events() -> SectEvents:
	if bus == null:
		bus = SectEvents.new()
	return bus


## Project `ledger` onto `actor`. Idempotent by construction: everything this
## module owns is stripped first, then rebuilt. Returns the ledger as persisted,
## so the caller reads the grant record this run wrote rather than the one it
## handed in — the two differ whenever the ledger it was given was stale.
##
## **Every exit writes.** The cleared pair is written before the build begins and
## the rebuilt pair over it after, so the ledger on the actor always names what is
## actually on the stat stack. A caller that persists the ledger it passed in
## rather than this return value would restore a record the projection never made.
static func apply(actor: Actor, ledger: Dictionary) -> Dictionary:
	if actor == null:
		return SectState.normalize(ledger)
	strip(actor)
	var next := SectState.normalize(ledger)
	# An unaffiliated member, or a save naming a sect this build does not ship,
	# contributes nothing at all — and the empty grant record written here is what
	# lets a later attach strip a contribution an older build made.
	next["applied_standing"] = 0
	next["granted_percent"] = {}
	var sect_id := SectState.institution(next)
	if sect_id == &"":
		_write(actor, next)
		return next
	# The trait mirror carries membership, not strength: a member who has earned
	# no standing is still sworn to something, and a gate asking "is this actor in
	# a sect" reads the mirror rather than a stat for exactly that reason.
	actor.traits.add(SectState.trait_for(sect_id))
	if SectCatalog.instance().sect_definition(sect_id) == null:
		_write(actor, next)
		return next
	next = _grant(actor, sect_id, next)
	_write(actor, next)
	return next


## Remove every contribution this module owns: the stat stack and the trait
## mirror. Used only by `apply`, so a partial projection can never be left behind.
##
## The grant record is **not** cleared here. `apply` clears and rewrites it as one
## pair, in one place, from what this pass actually rebuilt — which is the whole of
## `RaceProjection`'s strip-then-rebuild shape. A strip that published its own
## cleared ledger would write a second, competing copy of the same record, and the
## caller would persist whichever it happened to hold.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	# The stack and the mirror, not the catalog, name what to take back: losing a
	# `.tres` is exactly when a contribution would otherwise be stranded on the
	# actor with nothing left to remove it with.
	for source in _own_sources(actor):
		actor.stats.remove_modifiers_from(source)
		actor.traits.remove(source)


## The total this module contributes to `stat_id`, read from the modifier stack
## rather than recomputed. A test helper and an inspect aid: reading the stack
## proves the projection actually landed instead of trusting the ledger.
static func contribution(actor: Actor, stat_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if modifier.stat == stat_id and SectState.is_own_source(modifier.source):
			total += modifier.value
	return total


## ## Why the ledger has to remember what it applied
##
## `ActorStats.remove_modifiers_from` only knows a source tag and a `StatModifier`
## is a value, so the only number a rebuild needs is the one that was granted.
## ADR 0084 makes the record load-bearing for a second reason: the ledger stores
## the granted figures rather than re-reading the definition, which is also why
## stripping still works after the `.tres` has been deleted.
##
## ## A member with no office recognises nothing
##
## A position is what carries the allowlist, and ADR 0064's two-part split means a
## member may hold thick standing in no position at all. So the ordinary member —
## sworn to a sect, holding no office — is granted no percent, and neither fact is
## ever inferred from the other. That gap is the whole politics layer; collapsing
## it into one number would build a spreadsheet.
##
## ## The modifier loop is `InstitutionProjection.grant`, never a second copy
##
## The grant is a pure function of (allowlist, standing, source): the same bounded
## PERCENT on the same authored ids under the same tag. A per-tier loop would be a
## second place that formula could drift (ADR 0066), so this builds the call and
## keeps only the envelope — the `applied_standing` / `granted_percent` record
## `apply` rewrites every pass, which is this tier's own because the ledger keys
## are.
##
## A refused grant (an allowlist id no sheet can name) grants nothing and keeps the
## empty record, exactly as the office-missing path does: an authored fault is not
## a member's recognition, and a modifier that provably moves nothing must not be
## recorded as if it did.
##
## Returns the ledger **as this pass recorded it**, and `apply` is the one thing
## that writes it. A half-rebuilt projection whose record only reached the caller
## would be indistinguishable from a member who had been granted nothing — which is
## exactly the failure ADR 0084's "a rebuild has to know what it previously added"
## rule exists to prevent.
static func _grant(actor: Actor, sect_id: StringName, ledger: Dictionary) -> Dictionary:
	var next := SectState.normalize(ledger)
	var def := SectCatalog.instance().sect_definition(sect_id)
	var office := def.position(SectState.position(next)) if def != null else null
	if office == null:
		return next
	var source := SectState.source_for(sect_id)
	var report := InstitutionProjection.grant(
		actor, office.standing_percent_stats, SectState.standing(next), source
	)
	if not bool(report.get("ok", false)):
		return next
	next["applied_standing"] = SectState.standing(next)
	next["granted_percent"] = report["granted"]
	return next


## Every source id this module currently owns a modifier or a trait under. Walked
## from the actor rather than from the catalog, so a sect whose `.tres` has been
## deleted is still stripped rather than left behind. Both carriers share one
## namespace — `sect:<sect_id>` — because a `StatModifier` source and an
## `Actor.traits` id are the same kind of string here.
static func _own_sources(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for modifier in actor.stats._modifiers:
		if SectState.is_own_source(modifier.source) and not out.has(modifier.source):
			out.append(modifier.source)
	for trait_id in actor.traits.to_array():
		if SectState.is_own_trait(trait_id) and not out.has(trait_id):
			out.append(trait_id)
	return out


static func _write(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(SectState.MODULE_KEY, SectState.normalize(ledger))
