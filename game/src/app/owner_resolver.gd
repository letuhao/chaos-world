class_name OwnerResolver
extends RefCounted

## The composition root's `(kind, id)` owner resolver (ADR 0097, ADR 0104, ADR 0933). One
## public answer that tells `holdings` and `custody` whether an `OwnerRef` names something
## real.
##
## ## Why this file exists
##
## `HoldingsApi.set_resolver` and `CustodyApi.set_resolver` are two seams with ONE
## contract — `{"ok": true, "reason": ""}` or `{"ok": false, "reason": "<named>"}` — and
## with nothing installed both refuse `no_resolver`, so an institution can hold nothing at
## all. Neither module may answer for itself: an `actor`, a `clan`, a `sect` and a
## `nation` live in four modules that do not contain each other, and `tools/arch`'s
## bare-reference detector EXCLUDES `modules/*`, so a holder check that called into all
## three would build a cycle the gate cannot see. `app/` is the one layer allowed to know
## every tier, so `app/` answers.
##
## ## A def id, not a person
##
## The resolver answers **"does this build ship an institution of that id"**, never "is
## somebody standing here holding it". An institution is CONTENT: each tier is a catalog
## of authored `.tres` defs — and the institutions family is one more catalog — so the
## honest answer is membership of that catalog. `actor` is the one kind with no catalog —
## any non-empty id names somebody, and a live `Actor` is resolved elsewhere, through the
## injected minter (ADR 0104).
##
## ## The kind vocabulary is OPEN, and this is where it is validated (ADR 0933)
##
## `actor` and the three shipped tiers resolve through their static paths below. **Every
## other kind is an institution kind and must be registered in `InstitutionRegistry`** —
## that is ADR 0922's pack licence reaching the holder vocabulary: a modder ships a kind
## and it holds, with no base-game edit. An unregistered kind refuses as
## `OwnerRef.UNKNOWN_KIND` rather than defaulting to `actor`, which would let a sect's
## holding pass a player's check — the exact failure the type exists to prevent. A
## registered kind still needs an id naming an authored organization OF THAT KIND, or it
## refuses as `unknown_institution`.

# --- refusals -----------------------------------------------------------------
## The kind no boot registered. Spelled as the alias it is, and the same name an empty
## kind reaches in `OwnerRef.create` — one rule, one string.
const UNKNOWN_KIND := OwnerRef.UNKNOWN_KIND
## A holder carrying no id at all. Every module's own `unknown_owner`, written once.
const UNKNOWN_OWNER := "unknown_owner"
## The id names no institution of that tier in this build. These three are the names
## `ClanGate`, `SectApi` and `NationState` already use for exactly this refusal, so a
## panel that already renders them renders this too.
const UNKNOWN_CLAN := "unknown_clan"
const UNKNOWN_SECT := "unknown_sect"
const UNKNOWN_NATION := "unknown_nation"
## The id names no authored organization of the kind it was scoped to. Aliased from the
## generic vocabulary `core` already publishes (`InstitutionLedger.R_UNKNOWN_INSTITUTION`,
## `InstitutionCapability.R_UNKNOWN_INSTITUTION`) rather than restated a fourth time.
const UNKNOWN_INSTITUTION := InstitutionLedger.R_UNKNOWN_INSTITUTION

## `{"ok": true, "reason": ""}` is the same literal in both outcomes, built once so the
## two arms of every branch below cannot drift apart in shape.
const _OK := {"ok": true, "reason": ""}


## Whether `id`, scoped by `kind`, names a real holder in this build.
##
## `{ok: true, reason: ""}` or `{ok: false, reason: <a named constant>}` — ADR 0083's
## refusal answer: a named reason a panel renders, never a bare boolean whose meaning the
## caller has to guess.
static func resolve(kind: String, id: String) -> Dictionary:
	if id == "":
		return {"ok": false, "reason": UNKNOWN_OWNER}
	var kind_name := StringName(kind)
	match kind_name:
		&"actor":
			# The one kind with no catalog. An actor is named by its id and resolved to a
			# live `Actor` elsewhere (ADR 0104's minter), so a non-empty id is enough.
			return _OK
		&"clan":
			return _known(ClanCatalog.instance().clan_ids(), id, UNKNOWN_CLAN)
		&"sect":
			return _known(SectCatalog.instance().sect_ids(), id, UNKNOWN_SECT)
		&"nation":
			return _nation(id)
	# The OPEN half (class note): anything else is an institution kind, and the registry
	# is the vocabulary. `knows` is what lets a pack's kind resolve and what refuses a typo
	# BY NAME before any content is consulted.
	if not InstitutionRegistry.instance().knows(kind_name):
		return {"ok": false, "reason": UNKNOWN_KIND}
	return _institution(kind_name, id)


## ## Why every tier is read through its CATALOG rather than its facade
##
## `ClanApi` happens to publish `clan_ids` and `SectApi` publishes no id list at all, so
## "call the facade" is not one shape across the three tiers — asking each a different
## question is how they would drift apart again. The catalog IS the repo's own precedent
## for the root asking a content question: `institution_resolver.gd:129` already reads
## `SectCatalog` from this layer, `app/` may name any concrete type by construction
## (`LAYER_DEPS["app"] == {"*"}`), and a catalog is the literal answer to "does this build
## ship an institution of that id". Each one loads lazily, read-only, through
## `ContentScan.files_under` — so nothing here reads a directory by hand.
##
## ## The nation asymmetry, recorded rather than hidden
##
## `NationApi` publishes no world list of polities: its `summary` is the actor's OWN board,
## and `state` is that actor's ledger. Asking either "which nations exist" would be
## answering about one actor and reading it as an answer about the world — the
## single-actor-passes / multi-actor-fails shape ADR 0101 found. So the nation tier reads
## `NationCatalog`, which is the authored `.tres` tree the facade itself resolves through
## `_catalog()`.
static func _nation(id: String) -> Dictionary:
	return _known(NationCatalog.instance().nation_ids(), id, UNKNOWN_NATION)


## Whether `id` is one of `ids`. The refusal is NAMED by the caller, so one helper answers
## all three tiers without a `match` and without a default that could swallow a tier.
static func _known(ids: Array[StringName], id: String, unknown: String) -> Dictionary:
	if ids.has(StringName(id)):
		return _OK
	return {"ok": false, "reason": unknown}


## ## The generic institution branch, and why it reads the content catalog
##
## `InstitutionRegistry` holds one row per kind — a def TYPE, capabilities, a script — and
## no ids, so membership of the KIND is the registry's half of the answer; the ID's half is
## the authored catalog: `InstitutionDefCatalog`, the same family `InstitutionBoot`
## registers kinds from. Both halves are needed: a def whose kind never registered is not a
## holder kind, and a kind that DID register has nowhere else its ids could be checked.
static func _institution(kind: StringName, id: String) -> Dictionary:
	var def := InstitutionDefCatalog.instance().definition(StringName(id))
	if def == null or def.kind != kind:
		return {"ok": false, "reason": UNKNOWN_INSTITUTION}
	return _OK
