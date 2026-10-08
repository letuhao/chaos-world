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
##     value is `InstitutionLedger.standing_percent` — already capped in `core/`.
##   - Nothing here is a FLAT and nothing here is `set_base`, so a claim cannot
##     smuggle a member through a gate that reads base allocation (ADR 0052/0054).
##
## A second, parallel stat fold is forbidden (ADR 0065). The nation reuses
## `actor.stats.add_modifier` exactly as an authored trait does.
##
## The module's signal bus lives here rather than on the facade, exactly as
## `DestinyProjection` does it: a GDScript signal belongs to an instance and
## `NationApi` is a namespace of statics. Anything that needs to observe a claim
## connects here, and nothing outside the module emits through it.

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
##
## The grant is one `InstitutionProjection.grant` per held office under a
## PER-OFFICE tag, never one call over the union of allowlists:
## `InstitutionProjection.grant` writes ONE percent per id per tag, so handing it
## the union would grant the one percent and silently DROP the sum every office
## after the first contributed. Per-office tags keep every seat's recognition,
## and `strip` still clears all of them at once because every tag sits under
## `SOURCE_PREFIX`.
static func apply(
	actor: Actor, ledger: Dictionary, office_defs: Dictionary, nation_id: StringName
) -> Dictionary:
	if actor == null:
		return {}
	strip(actor)
	var granted := build(ledger, office_defs, nation_id)
	_grant_each(actor, ledger, office_defs, nation_id)
	return granted


## Remove every contribution this module owns. Used only by `apply`, so a partial
## projection can never be left behind — and a projection that cannot be inverted
## is a projection that compounds on re-attach (ADR 0084).
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	# Every tag this module writes sits under `SOURCE_PREFIX` — the one per-nation
	# tag older saves granted under, and the per-office tags `_grant_each` writes
	# now — so removing the applied ones clears every seat's contribution at once.
	# A stray tag from a nation this actor no longer lives under is removed too,
	# so a schism cannot leave the old half's recognition welded to whoever
	# joined it.
	for source in own_sources(actor):
		actor.stats.remove_modifiers_from(source)


## The stat source tag one OFFICE contributes under: the nation's tag with the
## office appended. Still under `SOURCE_PREFIX`, so `is_own_source` answers for
## it and `strip` clears it with the rest; still namespaced per office, so one
## seat's grant can never satisfy another seat's strip.
static func office_source_for(nation_id: StringName, office_id: StringName) -> StringName:
	if nation_id == &"" or office_id == &"":
		return &""
	return InstitutionLedger.source_tagged(
		NationState.SOURCE_PREFIX + String(nation_id) + ":", office_id
	)


## What the ledger projects, as `{stat_id: percent}`, WITHOUT touching an actor.
## Split out from `apply` so the shape is testable without a stat stack, and so
## `attach` can record exactly what it granted (ADR 0084).
##
## The sum across held offices, deliberately: every held seat recognises its own
## allowlist at the same bounded percent, so two seats recognising one stat grant
## it twice. The stack holds the same sum via the per-office grants `_grant_each`
## writes — the record and the modifiers agree because both walk `_held`.
static func build(ledger: Dictionary, office_defs: Dictionary, nation_id: StringName) -> Dictionary:
	var out := {}
	if nation_id == &"":
		return out
	var percent := InstitutionLedger.standing_percent(int(ledger.get("standing", 0)))
	if percent <= 0.0:
		return out
	for row in _held(ledger, office_defs):
		var def: NationOfficeDef = row["office"]
		for stat_id in def.percent_stats():
			out[String(stat_id)] = float(out.get(String(stat_id), 0.0)) + percent
	return out


## Every held office that names shipped content, as `{office_id, office}` rows in
## ledger order. Vacant seats grant nothing, and a seat naming an office the
## build does not ship is skipped the way `normalize` drops it. The ONE walk
## `build` and `_grant_each` share, so "held" has one meaning in this file: a
## `for` over the ledger's own keys filling a NEW array, which can never grow
## what it walks.
static func _held(ledger: Dictionary, office_defs: Dictionary) -> Array:
	var out: Array = []
	var offices: Dictionary = ledger.get("offices", {}) as Dictionary
	for office_id in offices.keys():
		if String(offices[office_id]) == "":
			continue
		var def = office_defs.get(String(office_id), null)
		if not (def is NationOfficeDef):
			continue
		out.append({"office_id": String(office_id), "office": def})
	return out


## Grant every held office its own recognition under its own tag. The loop
## `apply` owns: one `InstitutionProjection.grant` per seat, each a pure function
## of (allowlist, standing, tag) with nothing tier-shaped inside it.
static func _grant_each(
	actor: Actor, ledger: Dictionary, office_defs: Dictionary, nation_id: StringName
) -> void:
	if nation_id == &"":
		return
	var standing := int(ledger.get("standing", 0))
	# No percent, no modifiers: without this guard a member nobody recognises
	# would collect a row of `0.0` modifiers, which `build` — and the old `apply`
	# before it — correctly reads as nothing granted.
	if InstitutionLedger.standing_percent(standing) <= 0.0:
		return
	for row in _held(ledger, office_defs):
		var def: NationOfficeDef = row["office"]
		var tag := office_source_for(nation_id, StringName(String(row["office_id"])))
		if tag == &"":
			continue
		# A refused grant (an allowlist id no sheet can name) writes nothing for
		# that office while the summed record still counts it: the record is what
		# the ledger owes and the refusal names the content fault. Shipped content
		# validates, so the two agree everywhere a test can reach.
		InstitutionProjection.grant(actor, def.standing_percent_stats, standing, tag)


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
