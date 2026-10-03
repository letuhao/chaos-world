class_name NationProjection
extends RefCounted

## Rebuilds a nation's whole recognition onto an actor from the ledger.
##
## **Derived, never stored.** The ledger is the only truth; this class is the one
## place that translates it into stat modifiers. A save can be restored, replayed
## or normalized and the projection is simply recomputed, so it can never drift
## from the ledger or double-count.
##
## ## PERCENT only, and only on an authored allowlist (ADR 0084)
##
## Every modifier written here is `Stat.Op.PERCENT` on a stat id the held seat's
## `NationOfficeDef.standing_percent_stats` names. Three properties follow and each
## is a test rather than a hope:
##   - A percent rides the member's own growth, so a nation is a real edge at its
##     realm and exactly as strong at R5 as at R30.
##   - No ladder of authored seats can sum into an uncapped multiplier, because the
##     value is `InstitutionClaim.standing_percent` — already capped in `core/`.
##   - Nothing here is a FLAT and nothing here is `set_base`, so a claim cannot
##     smuggle a member through a gate that reads base allocation (ADR 0052/0054).
##
## A second, parallel stat fold is forbidden (ADR 0065). The nation reuses
## `actor.stats.add_modifier` exactly as an authored trait does.
##
## The module's signal bus lives here rather than on the facade, exactly as
## `DestinyProjection` does it: a GDScript signal belongs to an instance and
## `NationApi` is a namespace of statics holding the facade's twelve verbs.

static var bus: NationEvents = null


static func events() -> NationEvents:
	if bus == null:
		bus = NationEvents.new()
	return bus


## Apply the whole ledger to `actor`. Idempotent by construction: everything this
## module owns is stripped first, then rebuilt. Calling this after no change is
## free of consequence, which is what lets a save restore and re-attach safely.
##
## `office_defs` maps office id → `NationOfficeDef` and `nation_id` names the
## polity for the source tag. An empty allowlist applies nothing, so a nation that
## recognises no stat writes nothing at all.
static func apply(
	actor: Actor, ledger: Dictionary, office_defs: Dictionary, nation_id: StringName
) -> Dictionary:
	if actor == null:
		return {}
	strip(actor)
	var granted := build(ledger, office_defs, nation_id)
	for stat_id in granted.keys():
		actor.stats.add_modifier(
			StatModifier.new(
				StringName(String(stat_id)),
				Stat.Op.PERCENT,
				float(granted[stat_id]),
				NationState.source_for(nation_id)
			)
		)
	return granted


## Remove every contribution this module owns. Used only by `apply`, so a partial
## projection can never be left behind — and a projection that cannot be inverted
## is a projection that compounds on re-attach (ADR 0084).
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	# The source tag is per NATION, so removing the applied one clears every seat's
	# contribution at once. A stray tag from a nation this actor no longer lives
	# under is removed too, so a schism cannot leave the old half's recognition
	# welded to whoever joined it.
	for source in own_sources(actor):
		actor.stats.remove_modifiers_from(source)


## What the ledger projects, as `{stat_id: percent}`, WITHOUT touching an actor.
## Split out from `apply` so the shape is testable without a stat stack, and so
## `attach` can record exactly what it granted (ADR 0084).
static func build(ledger: Dictionary, office_defs: Dictionary, nation_id: StringName) -> Dictionary:
	var out := {}
	if nation_id == &"":
		return out
	var percent := InstitutionClaim.standing_percent(int(ledger.get("standing", 0)))
	if percent <= 0.0:
		return out
	var offices: Dictionary = ledger.get("offices", {}) as Dictionary
	for office_id in offices.keys():
		if String(offices[office_id]) == "":
			continue
		var def = office_defs.get(String(office_id), null)
		if not (def is NationOfficeDef):
			continue
		for stat_id in (def as NationOfficeDef).percent_stats():
			out[String(stat_id)] = float(out.get(String(stat_id), 0.0)) + percent
	return out


## The total this module contributes to `stat_id`, read from the modifier stack
## rather than recomputed. A test helper: reading the stack proves the projection
## actually landed instead of trusting the ledger.
static func contribution(actor: Actor, stat_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if modifier.stat == stat_id and NationState.is_own_source(modifier.source):
			total += modifier.value
	return total


## Every stat-modifier source this module currently owns.
static func own_sources(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null:
		return out
	for modifier in actor.stats._modifiers:
		if NationState.is_own_source(modifier.source):
			out.append(modifier.source)
	return out
