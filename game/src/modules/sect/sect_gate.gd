class_name SectGate
extends RefCounted

## Evaluates authored sect requirements against a member's ledger, and decides
## whether one institution may teach or open something to this actor at all.
##
## ## A gate reads the ledger, never a derived stat
##
## A stat can be satisfied by an item, by a pill, by another module's grant. A
## gate that read one would be a gate the player could *buy*, and "may I learn
## this here" becoming a discount a grinder unlocks is exactly the failure ADR
## 0076 measured on reputation and ADR 0062 already ruled out for paths. Fit,
## standing, office and duty are all ledger facts here, and the allowlist of an
## office is authored content rather than a number the gate invents.
##
## A requirement is **data, never code**: either an empty dictionary — ungated,
## always open — or a map naming exactly one verb. No GDScript is authored per
## gate, so adding content is a content edit, not a code change.
##
## ## Verbs (a closed set — an unknown verb is refused, never silently true)
##
##   `{verb: &"is_member"}`                              — sworn to anything at all
##   `{verb: &"in_sect",      sect: &"jade_court"}`      — sworn to this sect
##   `{verb: &"standing_at_least",  need: 40}`            — the recognition bar
##   `{verb: &"holds_position", position: &"elder"}`     — the office itself
##   `{verb: &"holds_authority", authority: &"teach"}`   — what the office may do
##   `{verb: &"fit_at_least",  doctrine: &"iron_vine", need: 30}` — transmission
##   `{verb: &"duty_owed",    term: &"patronage_elder"}` — the obligation bar
##   `{verb: &"all_of",       of: [ ...requirements ]}`
##   `{verb: &"any_of",       of: [ ...requirements ]}`
##   `{verb: &"none_of",      of: [ ...requirements ]}`
##
## A requirement with no verb, or a verb that is not one of these, refuses closed
## and **names itself**. Refuse-with-cause is the house rule: content that is
## malformed must fail loudly and locally, never open a door it cannot read.
##
## ## Why `standing_at_least` is a route and not a wall
##
## It is the ordinary promotion gate, and it reports `standing_below_floor` with
## the numbers in `unmet` rather than refusing to say how far short the member
## fell. ADR 0064's two-part split exists because promotion on thin standing has
## to stay expressible — that gap is where the politics lives — so the gate hands
## the caller everything needed to authorise the exception and never makes the
## decision for them.

const VERB_IS_MEMBER := &"is_member"
const VERB_IN_SECT := &"in_sect"
const VERB_STANDING_AT_LEAST := &"standing_at_least"
const VERB_HOLDS_POSITION := &"holds_position"
const VERB_HOLDS_AUTHORITY := &"holds_authority"
const VERB_FIT_AT_LEAST := &"fit_at_least"
const VERB_DUTY_OWED := &"duty_owed"
const VERB_ALL_OF := &"all_of"
const VERB_ANY_OF := &"any_of"
const VERB_NONE_OF := &"none_of"

const VERBS: Array[StringName] = [
	VERB_IS_MEMBER,
	VERB_IN_SECT,
	VERB_STANDING_AT_LEAST,
	VERB_HOLDS_POSITION,
	VERB_HOLDS_AUTHORITY,
	VERB_FIT_AT_LEAST,
	VERB_DUTY_OWED,
	VERB_ALL_OF,
	VERB_ANY_OF,
	VERB_NONE_OF,
]

## The shared authority lookup, held once because a capability is stateless: the
## office arrives as primitives in the context each call builds, so one instance
## answers every evaluation. `holds_authority` is the tree's one reader of
## authored `authorities` data, which is why this gate — and not clan's, whose
## def authors no such field — is the tier the `Authorised` contract fits.
static var _authorised: Authorised = null


static func _capability() -> Authorised:
	if _authorised == null:
		_authorised = Authorised.new()
	return _authorised


## The full verdict, always this shape:
## `{ok: bool, reason: String, unmet: Array[Dictionary]}` where every unmet entry
## is `{kind, id, required, actual, label}` — the shape `ItemRequirement.unmet()`
## already produces, so a panel renders a reason it did not have to invent. `ok`
## is the whole answer; the rest is for display.
##
## The actor arrives as the first argument, never as a second thing every verb has
## to remember to thread through — a `.tres` or a quest entry names a requirement
## with no actor on it at all, and a panel's dictionary must survive being
## evaluated untouched. `evaluate` copies the requirement into a probe the verbs
## are handed, so the caller's own dictionary is never written to.
##
## ## The probe carries authored data and drops only what the CALLER supplied
##
## What the probe deliberately does not carry is anything the caller owns.
## `actor` and `ledger` are the two keys a caller supplies, and `evaluate`
## overwrites both from its own arguments, so a requirement authored as content
## can neither answer for an actor nobody attached one to nor name a claim the
## caller did not pass. Everything else in the copy is authored data a verb has to
## be able to read — `need`, `position`, `doctrine`, and a composite's `of` — and a
## composite that could not see its own children would refuse every one of them as
## malformed.
static func evaluate(_actor: Actor, requirement: Dictionary) -> Dictionary:
	# Ungated is ungated. `{}` is not a requirement with a missing verb, it is the
	# absence of one, so it opens before anything is read at all — which is what
	# lets a panel ask the ungated question of a null actor.
	if requirement.is_empty():
		return _pass()
	var probe := requirement.duplicate()
	# The caller's own actor, never whatever the requirement arrived carrying.
	probe["actor"] = _actor
	probe["ledger"] = requirement.get("ledger", {})
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		return _refuse("malformed", "A sect gate names no verb.", "")
	match verb:
		VERB_IS_MEMBER:
			return _is_member(probe)
		VERB_IN_SECT:
			return _in_sect(probe)
		VERB_STANDING_AT_LEAST:
			return _standing_at_least(probe)
		VERB_HOLDS_POSITION:
			return _holds_position(probe)
		VERB_HOLDS_AUTHORITY:
			return _holds_authority(probe)
		VERB_FIT_AT_LEAST:
			return _fit_at_least(probe)
		VERB_DUTY_OWED:
			return _duty_owed(probe)
		VERB_ALL_OF:
			return _composite(probe, true, false)
		VERB_ANY_OF:
			return _composite(probe, false, false)
		VERB_NONE_OF:
			return _composite(probe, true, true)
		_:
			return _refuse(
				"unknown_verb",
				"Sect gate verb '%s' is not one this module reads." % verb,
				String(verb)
			)


# --- Internals -------------------------------------------------------------


static func _is_member(requirement: Dictionary) -> Dictionary:
	var ledger := _ledger(requirement)
	if SectState.is_affiliated(ledger):
		return _pass()
	return _fail(
		&"membership", SectState.institution(ledger), &"sworn", &"unaffiliated", "Sworn to no sect"
	)


static func _in_sect(requirement: Dictionary) -> Dictionary:
	var sect_id := StringName(requirement.get("sect", ""))
	if sect_id == &"":
		return _refuse("malformed", "An in_sect gate names no sect id.", "in_sect")
	var ledger := _ledger(requirement)
	if SectState.institution(ledger) == sect_id:
		return _pass()
	return _fail(
		&"sect",
		sect_id,
		String(sect_id),
		String(SectState.institution(ledger)),
		"Sworn to '%s'" % sect_id
	)


## The standing bar. Reported as `standing_below_floor` with both numbers, so the
## caller can see how far short the member fell and decide whether to wait.
static func _standing_at_least(requirement: Dictionary) -> Dictionary:
	var need := int(requirement.get("need", 0))
	if need < 0:
		return _refuse(
			"malformed", "A standing gate needs a `need` of zero or more.", "standing_at_least"
		)
	var ledger := _ledger(requirement)
	var held := SectState.standing(ledger)
	if held >= need:
		return _pass()
	return {
		"ok": false,
		"reason": SectDef.STANDING_BELOW_FLOOR,
		"unmet":
		[
			{
				"kind": "standing",
				"id": String(SectState.institution(ledger)),
				"required": need,
				"actual": held,
				"label": "Standing %d of %d" % [held, need],
			}
		],
	}


static func _holds_position(requirement: Dictionary) -> Dictionary:
	var position_id := StringName(requirement.get("position", ""))
	if position_id == &"":
		return _refuse("malformed", "A holds_position gate names no position id.", "holds_position")
	var ledger := _ledger(requirement)
	var held := SectState.position(ledger)
	if held == position_id:
		return _pass()
	return _fail(
		&"position",
		position_id,
		String(position_id),
		String(held),
		"Holds the office '%s'" % position_id
	)


## Authority is authored data (ADR 0084), so this is a lookup in the office's own
## `authorities` list and never a comparison between offices. "May this member
## expel another" is a `.tres` question, and this is the gate that asks it.
##
## The lookup itself is `Authorised.authorise`, never a second implementation:
## the office is handed over as primitives (`office`, `authorities`, `duties`)
## because `contracts/` may not name the authored office resource, and the
## verdict is folded back into this gate's own `{ok, reason, unmet}` shape so the
## two refusal states (`no_office`, `unknown_authority`) stay one player-facing
## sentence — "may X" is unmet either way, and the `actual` names which.
static func _holds_authority(requirement: Dictionary) -> Dictionary:
	var authority_id := StringName(requirement.get("authority", ""))
	if authority_id == &"":
		return _refuse("malformed", "A holds_authority gate names no authority.", "holds_authority")
	var ledger := _ledger(requirement)
	var sect_id := SectState.institution(ledger)
	var def := SectCatalog.instance().sect_definition(sect_id)
	var office := def.position(SectState.position(ledger)) if def != null else null
	var verdict := _capability().authorise(_authority_ctx(office), authority_id)
	if bool(verdict.get("ok", false)):
		return _pass()
	return _fail(
		&"authority",
		authority_id,
		String(authority_id),
		"" if office == null else _string_list(office.authorities),
		"May '%s'" % authority_id
	)


## The office as the `Authorised` contract reads it: primitives only, because
## `contracts/` depends on nothing and may not name `SectPositionDef`. Keys are
## compared as text inside the capability, so a `String`-keyed save and a
## `StringName`-authored def answer the same way.
static func _authority_ctx(office: SectPositionDef) -> Dictionary:
	if office == null:
		return {"office": "", "authorities": [], "duties": []}
	return {
		"office": String(office.id),
		"authorities": office.authorities,
		"duties": office.duties,
	}


## Transmission, never recognition. Fit is a bounded integer per doctrine and it
## gates who may be taught (ADR 0084); it is not standing and is never conflated
## with it, so a member with a perfect claim and no affinity still fails here.
static func _fit_at_least(requirement: Dictionary) -> Dictionary:
	var doctrine_id := StringName(requirement.get("doctrine", ""))
	if doctrine_id == &"":
		return _refuse("malformed", "A fit_at_least gate names no doctrine id.", "fit_at_least")
	var need := int(requirement.get("need", 0))
	if need < 0:
		return _refuse("malformed", "A fit gate needs a `need` of zero or more.", "fit_at_least")
	var ledger := _ledger(requirement)
	var held := int((ledger.get("fit", {}) as Dictionary).get(String(doctrine_id), 0))
	if held >= need:
		return _pass()
	return _fail(
		&"fit", doctrine_id, need, held, "Fit %d of %d for '%s'" % [held, need, doctrine_id]
	)


## What the member still owes, read from the claim's own obligation ledger. A
## duty bar is a way of saying "not yet", and it is satisfied by settling — never
## by being underwritten by a stat.
##
## The bar is inclusive of the debt itself (`owed <= need`): a debt of exactly
## `need` is settled enough, and only a debt ABOVE it is still owed. Reading the
## figure through the claim rather than off the ledger's raw key means the answer
## comes from the one accessor `core/` already owns, so `duty_owed` and
## `summary()["obligations"]` can never disagree about what a member owes.
static func _duty_owed(requirement: Dictionary) -> Dictionary:
	var term_id := StringName(requirement.get("term", ""))
	if term_id == &"":
		return _refuse("malformed", "A duty_owed gate names no term id.", "duty_owed")
	var need := int(requirement.get("need", 0))
	if need < 1:
		return _refuse("malformed", "A duty_owed gate needs a positive `need`.", "duty_owed")
	var owed := SectState.claim(_ledger(requirement)).owed(term_id)
	if owed <= need:
		return _pass()
	return _fail(
		&"duty",
		term_id,
		need,
		owed,
		"Owes %d periods of '%s', %d settles it" % [owed, term_id, need]
	)


## `all_of` requires every child, `any_of` one, and `none_of` opens only when every
## child is unmet — the last being the form that expresses a closed door.
##
## A malformed or unknown-verb child poisons the whole composite: refuse-with-cause
## means a nested gate that cannot be read is never treated as satisfied, and never
## treated as absent either.
##
## ## The children come from the AUTHORED requirement, the actor from the CALLER
##
## `of` is content, so it is read off the probe — and the probe is a copy of the
## requirement, which is what lets a composite see its own children at all. What is
## not read is the actor: the recursion is handed `probe`'s `actor` key, which
## `evaluate` has already overwritten with the actor the caller actually passed, so
## a child can neither answer for somebody else nor lose the claim this evaluation
## is about.
##
## Each child is built as its OWN requirement — the parent's `actor` and
## `ledger` travel across, everything else comes from the child. Building the
## child from the parent instead (and overwriting only `of`) leaves the parent's
## `verb` in place, so every child is re-entered as the same composite and the
## gate recurses on its own children. That also means a child which is itself a
## composite reads its own `of`, and a nested list cannot be shadowed by its
## parent's.
static func _composite(probe: Dictionary, require_all: bool, refuse_when_any: bool) -> Dictionary:
	var children = probe.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return _refuse("malformed", "A composite gate names no children.", "all_of")
	var unmet: Array[Dictionary] = []
	var passed := 0
	for child in children as Array:
		# The child IS the next requirement, so the probe's `actor` and `ledger`
		# are carried across and everything else comes from the child. Building
		# `nested` from the parent and overwriting `of` instead would leave the
		# parent's `verb` in place, so a child would be re-entered as the same
		# composite and recurse on the parent's own children forever.
		var nested := {
			"actor": probe.get("actor", null),
			"ledger": probe.get("ledger", {}),
		}
		if child is Dictionary:
			for key in (child as Dictionary).keys():
				nested[String(key)] = (child as Dictionary)[key]
		else:
			return _refuse(
				"malformed", "A composite gate names a child that is not a map.", "all_of"
			)
		var verdict := evaluate(probe.get("actor", null) as Actor, nested)
		if bool(verdict.get("ok", false)):
			passed += 1
			continue
		var nested_reason := String(verdict.get("reason", ""))
		if nested_reason == "malformed" or nested_reason == "unknown_verb":
			return verdict
		for entry in verdict.get("unmet", []) as Array:
			unmet.append(entry)
	var total := (children as Array).size()
	var ok := passed >= total if require_all else passed > 0
	if refuse_when_any:
		ok = passed == 0
	if ok:
		return _pass()
	return {"ok": false, "reason": "unmet", "unmet": unmet}


## ## The ledger a requirement is read against
##
## A gate that needs the actor reads `actor.module_data` through the facade's own
## key — `app/` is forbidden from doing it, and a module reaches a sibling only
## through its facade, so this is the same path every other gate in the repo takes.
## A gate that is pure authored data (`all_of`, and any content author writing a
## nested requirement) carries its own `ledger`, which is what lets a requirement
## be evaluated with no actor at all.
##
## An `actor` key that is not an `Actor` — a null actor is the ordinary case for an
## ungated panel question — is not a ledger and does not become one, so a null
## actor reads the authored `ledger` or the empty claim and nothing else.
static func _ledger(requirement: Dictionary) -> Dictionary:
	var actor = requirement.get("actor", null)
	if actor is Actor:
		return SectState.normalize(actor.get_module_data(SectState.MODULE_KEY))
	return SectState.normalize(requirement.get("ledger", {}))


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": "unmet",
		"unmet":
		[
			{
				"kind": String(kind),
				"id": String(id),
				"required": required,
				"actual": actual,
				"label": label,
			}
		],
	}


## A refusal is distinct from a normal failure: the requirement itself is
## unreadable, which is a content bug rather than a player being told no. It
## refuses closed and names the verb it could not read, so the fix is visible in
## the log rather than in a player's confusion.
##
## `verb` is named by the caller rather than read off the probe. The probe carries
## the authored arguments, but an unreadable requirement has no readable verb to
## report, so the caller names the one it could not match.
static func _refuse(reason: String, label: String, verb: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet":
		[
			{
				"kind": "gate",
				"id": verb,
				"required": "a_readable_requirement",
				"actual": "unreadable",
				"label": label,
			}
		],
	}


static func _string_list(values: Array[StringName]) -> String:
	return ", ".join(PackedStringArray(values))
