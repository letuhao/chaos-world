class_name Authorised
extends InstitutionCapability

## The authored `duties` / `authorities` of an office, asked as a REAL question
## (ADR 0084, ADR 0922). ADR 0084 made authority authored data — "may this member
## expel another" is a `.tres` question, never `if rank >= 3` — and measured
## today that data is **inert**: `InstitutionPositionDef.authorities` is an
## exported array nothing in the generic institution family reads, and the one
## reader in the tree (`SectGate._holds_authority`) lives inside `sect`, so a
## trading guild's authored `expel` (measured: `lantern_exchange.tres` and
## `grey_horizon_hunt.tres` both author it on their top seat) is executable by
## nothing at all.
##
## ## Authority is a LOOKUP, never a comparison
##
## `holds` is a membership test in one office's own authored list. It never
## compares two offices, never compares a number, and never derives an ordering
## — the numeric hierarchy ADR 0064 kept out of the claim would come straight
## back through a back door the moment authority became `rank >= 3`.
##
## ## Three answers, and the two that are easy to collapse
##
##   - `{ok: true, has: true}` — the office authors it, so its holder may.
##   - `{ok: true, has: false}` — the office exists and authors no such power.
##     **A legitimate state, not an error**: an ordinary member's office grants
##     little, and "this member cannot" is what the design wants said plainly.
##   - `{ok: false, reason: <named>}` — the QUESTION was refused: an empty
##     authority id, or an acting member with no office at all. `authorise` is
##     where these are told apart, because a caller about to gate a press needs
##     the fix named ("hold an office" vs "this office never had that power").
##
## The office arrives as PRIMITIVES — `ctx["office"]` is an id `String` and
## `ctx["authorities"]`/`ctx["duties"]` are `Array`s of id strings — because
## this layer may not name the authored office resource that owns them
## (`contracts/` depends on nothing, and an authored `Resource` filed here is
## what `RESOURCE_HOME_UNITS` refuses). The caller that holds the def assembles
## the context; that is the seam `InstitutionContract` dispatches through.
##
## Rejected: reading `duties` as a mirrored second `authorities` list. A duty is
## what the holder MUST do and an authority is what the holder MAY do; merging
## them would make "carry the seal" read as a permission, which is the exact
## "a duty is a duty" rule `InstitutionPositionDef` states.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111).

## The id this capability is dispatched under.
const ID := &"authorised"

## The authored authority id the shipped content uses for expulsion. Owned HERE
## so a capability, an office's `.tres` and an expulsion plan cannot spell it
## three ways; measured on the shipped guilds, both top seats author exactly this
## word. Family content is free to author others.
const AUTHORITY_EXPEL := &"expel"

## An authority id was asked as `""`: there is no power to look up, so the
## question itself is broken rather than answered `has: false`.
const R_NO_AUTHORITY_ID := "no_authority_id"
## The acting member holds NO office, so there is nothing to exercise authority
## from. Distinct from `unknown_authority`: this one is a member's state, the
## other is content's.
const R_NO_OFFICE := "no_office"
## The office EXISTS and does not author this authority. An authored-data
## question, and the refusal names it so a content author sees the fix rather
## than a player being told a mystery.
const R_UNKNOWN_AUTHORITY := "unknown_authority"


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [R_NO_AUTHORITY_ID, R_NO_OFFICE, R_UNKNOWN_AUTHORITY]
	return out


func capability_id() -> StringName:
	return ID


## Whether the acting member MAY exercise `authority_id`, as a read. The
## `has_capability` shape: a refusal only for a question that cannot be asked,
## never for one whose answer is "no".
func holds(ctx: Dictionary, authority_id: StringName) -> Dictionary:
	if authority_id == &"":
		return InstitutionCapability.refuse(R_NO_AUTHORITY_ID)
	return InstitutionCapability.ok({"has": _authors(ctx, authority_id)})


## Gate the act itself: `{ok: true, authority: id}` or a named refusal. This is
## the verb a caller about to perform an authorised act asks FIRST, which is
## what turns authored data into a real gate rather than a comment.
func authorise(ctx: Dictionary, authority_id: StringName) -> Dictionary:
	if authority_id == &"":
		return InstitutionCapability.refuse(R_NO_AUTHORITY_ID)
	if InstitutionCapability.text(ctx.get("office", ""), "") == "":
		return InstitutionCapability.refuse(R_NO_OFFICE)
	if not _authors(ctx, authority_id):
		return InstitutionCapability.refuse(
			R_UNKNOWN_AUTHORITY, {"authority": String(authority_id)}
		)
	return InstitutionCapability.ok({"authority": String(authority_id)})


## The authored duty verb ids of the held office, canonically ordered by string
## value — NEVER `Array[StringName].sort()`, because interned ids are not
## specified to order by their string value and a list whose order is
## load-bearing must not depend on which id loaded first. An empty list for a
## member with no office: they have no duties to read, which is a state and not
## an error.
func duty_terms(ctx: Dictionary) -> Array[String]:
	return _sorted(ctx.get("duties", []))


## The kind-level gate. Authority data that cannot be READ is a content fault
## and is refused HERE, before any act is gated on it: an `authorities` value
## that arrived as a string (a hand-edited save, a JSON row) would otherwise
## make every lookup answer `has: false`, which is indistinguishable from an
## office that grants nothing.
func check(ctx: Dictionary) -> Dictionary:
	if not _is_id_list(ctx.get("authorities", [])):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "authorities"}
		)
	if not _is_id_list(ctx.get("duties", [])):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "duties"}
		)
	return {"ok": true, "reason": "", "unmet": []}


# --- Internals ---------------------------------------------------------------


## Whether the office the context names authors `authority_id`, matched by
## TEXT: an authored array may hold `StringName`s while a context built from a
## save holds plain `String`s, and `Array.has()` is type-strict — the silent
## no-match failure `InstitutionProjection.recognises` documents at length.
func _authors(ctx: Dictionary, authority_id: StringName) -> bool:
	var authored = ctx.get("authorities", [])
	if not (authored is Array):
		return false
	for entry in authored as Array:
		if String(entry) == String(authority_id):
			return true
	return false


## `value`'s entries as sorted strings when it is a list of id-shaped values,
## `[]` otherwise. Shared by [method duty_terms] and [method check], so "what
## is a readable id list" has one answer in this file.
func _sorted(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (value is Array):
		return out
	for entry in value as Array:
		if entry is String or entry is StringName:
			out.append(String(entry))
	out.sort()
	return out


## Whether `value` really is a list of ids. An empty array IS one: an office
## that authors nothing is a legitimate authored state.
func _is_id_list(value: Variant) -> bool:
	if not (value is Array):
		return false
	for entry in value as Array:
		if not (entry is String or entry is StringName):
			return false
	return true
