class_name OwnerResolver
extends RefCounted

## The composition root's `(kind, id)` owner resolver (ADR 0097, ADR 0104). One public
## answer that tells `holdings` and `custody` whether an `OwnerRef` names something real.
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
## of authored `.tres` defs, so the honest answer is membership of that catalog. `actor` is
## the one kind with no catalog — any non-empty id names somebody, and a live `Actor` is
## resolved elsewhere, through the injected minter (ADR 0104).
##
## ## An unknown kind refuses closed
##
## `OwnerRef.KINDS` is closed, so a kind outside it is a content bug. It refuses as
## `OwnerRef.UNKNOWN_KIND` rather than defaulting to `actor`, which would let a sect's
## holding pass a player's check — the exact failure the type exists to prevent.

# --- refusals -----------------------------------------------------------------
## The kind is outside the closed `OwnerRef.KINDS` set. Spelled as the alias it is.
const UNKNOWN_KIND := OwnerRef.UNKNOWN_KIND
## A holder carrying no id at all. Every module's own `unknown_owner`, written once.
const UNKNOWN_OWNER := "unknown_owner"
## The id names no institution of that tier in this build. These three are the names
## `ClanGate`, `SectApi` and `NationState` already use for exactly this refusal, so a
## panel that already renders them renders this too.
const UNKNOWN_CLAN := "unknown_clan"
const UNKNOWN_SECT := "unknown_sect"
const UNKNOWN_NATION := "unknown_nation"

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
	match StringName(kind):
		&"actor":
			# The one kind with no catalog. An actor is named by its id and resolved to a
			# live `Actor` elsewhere (ADR 0104's minter), so a non-empty id is enough.
			return _OK
		&"clan":
			# `ClanApi.clan_ids` is the facade's own published list of authored houses.
			return _known(ClanApi.clan_ids(), id, UNKNOWN_CLAN)
		&"sect":
			# `SectApi` publishes no id list — it is at the twelve-method cap — but its
			# `summary` carries every authored sect under `sects` whatever the actor is,
			# exactly so a screen can compare institutions in one call. That payload is
			# the read, and `null` is a legitimate argument for it: the world listing is
			# built before the actor is ever consulted.
			return _known(_sect_ids(), id, UNKNOWN_SECT)
		&"nation":
			return _nation(id)
		_:
			return {"ok": false, "reason": UNKNOWN_KIND}


## The authored sect ids, read out of `SectApi.summary`'s `sects` map.
static func _sect_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var asked := Callable(SectApi, "summary")
	if not asked.is_valid():
		return out
	var answered: Variant = asked.call(null)
	if not answered is Dictionary:
		return out
	var sects: Variant = (answered as Dictionary).get("sects", {})
	if not sects is Dictionary:
		return out
	for sect_id in (sects as Dictionary).keys():
		out.append(StringName(sect_id))
	return out


## ## The nation branch, and the asymmetry it records rather than hides
##
## `ClanApi` publishes `clan_ids`; `SectApi` publishes `sects` inside its `summary`; and
## **`NationApi` publishes neither.** Its `summary` is the actor's OWN board — offices,
## claims, stances, standoffs — and it holds no world list of polities at all. So there is
## no facade call that answers "does this build ship a nation of that id", and this branch
## is therefore built in two steps rather than pretending the symmetry is there:
##
##   1. ask the facade anyway, through a `Callable` rather than a direct call, and read a
##      `nations` map out of it if one is ever added (`sect` proves the shape is idiomatic
##      here). This is the half that keeps working when the facade grows the list;
##   2. fall back to `NationCatalog`, which is the authored `.tres` tree the facade itself
##      reads through `_catalog()`. `app/` may name any concrete type by construction
##      (`LAYER_DEPS["app"] == {"*"}`), and `institution_resolver.gd:129` already reads
##      `SectCatalog` from this layer, so this is the repo's own precedent rather than a
##      new reach.
##
## Without the fallback the branch would have to answer "no" for every nation id, which
## would make a real polity unable to hold a node — a wrong answer that looks like a
## working gate, which is worse than the seam it would be.
##
## ## What the `Callable` guards, precisely
##
## It guards a method that is ABSENT and an answer that is not a `Dictionary` — both of
## which turn into a named refusal instead of a runtime fault or a null dereference
## (ADR 0002's rule). It does NOT guard a parse error inside `nation/api.gd` itself: a
## class that fails to compile is a load failure for every dependent at once, which no
## probe on this side can intercept. What keeps this file off that blast radius is that it
## names `NationApi` and nothing else of the module, and never imports
## `institution_resolver.gd`.
static func _nation(id: String) -> Dictionary:
	var asked := Callable(NationApi, "summary")
	if asked.is_valid():
		var answered: Variant = asked.call(null)
		if answered is Dictionary:
			var known: Variant = (answered as Dictionary).get("nations", {})
			if known is Dictionary and (known as Dictionary).has(String(id)):
				return _OK
	return _known(NationCatalog.instance().nation_ids(), id, UNKNOWN_NATION)


## Whether `id` is one of `ids`. The refusal is NAMED by the caller, so one helper answers
## all three tiers without a `match` and without a default that could swallow a tier.
static func _known(ids: Array[StringName], id: String, unknown: String) -> Dictionary:
	if ids.has(StringName(id)):
		return _OK
	return {"ok": false, "reason": unknown}