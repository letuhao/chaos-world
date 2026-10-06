class_name InstitutionMembership
extends RefCounted

## The ACTOR-SCOPED surface gameplay never published: what one actor holds of every
## organization of ANY kind, and the three verbs that change it (join, leave, found).
##
## ## Why this file exists
##
## The institution family shipped a registry of KINDS, a catalog of DEFINITIONS, a
## generic founding verb, a ledger with two writers and a projection — and **no surface
## answering "what does THIS actor hold"**. `ui/` may legally read `core/`
## (a downward dependency), so the institution screen could ask, and
## `InstitutionLedger` publishes exactly two writers (`promote`, `move_standing`),
## neither of which enrols anybody. A hero could found a guild, be charged for it, and
## see the written ledger discarded: the whole family was reachable and inert.
##
## ## WHERE A MEMBERSHIP LIVES, and why it is not sect's answer
##
## Two facts live in two places, and the split is by SUBJECT rather than by
## convenience — the rule `WorldPolityLedger` states and enforces for the `polity` slot:
## **a fact whose subject includes an actor id stays on that actor; a fact whose subject
## is the organization goes to the world.**
##
##   - **The CLAIM is on the actor**, under [constant MEMBERSHIP_KEY] in `module_data`.
##     Its subject is (actor, organization), its lifetime is the actor's, and promoting
##     it to a world root would give two people two copies of one person's standing —
##     the per-actor-copy bug `WorldLedger`'s docblock calls out. It round-trips a save
##     through `Actor.to_dict` because every key is a plain `String` and every value a
##     primitive.
##   - **The ROSTER is NOT on the actor.** `InstitutionFounding.write` puts
##     `{position: [actor_id]}` in the founder's ledger, so a member who JOINED rather
##     than founded sees no roster at all — measured, and the reason this file refuses to
##     reproduce it. The roster's subject is the organization, so it lives in
##     [method roster_of] and is published to every member rather than to the founder.
##     A roster persisted inside one person's body is a correctness problem and not an
##     oddity: ADR 0261 (PROPOSED, not Accepted) has many characters sharing one world,
##     where a founder's save is not the world's record of who belongs to anything.
##
## ## The roster is PROCESS state, and that is stated rather than hidden
##
## No world save slot can accept a roster: `polity`'s row normalizer keeps `kind`,
## `standing`, `standing_cap` and `sequence` and DROPS everything else, and its own
## boundary rule forbids an actor id on a row. So the roster is a process-wide table
## with [method clear] in the surface, which is the `InstitutionRegistry` shape: the
## headless runner drives every suite in ONE process, so a table a suite forgets to
## clear is handed to every suite after it. **It does not survive a save** — that gap is
## DEF-0119's and is recorded there, not solved here. In play the claims come back from
## disk and the roster does not, and an absent roster publishes `{}` — ADR 0083's FIRST
## state, which `InstitutionCard` renders as `holders not published` rather than as a
## vacancy nobody declared.
##
## ## A REFUSED VERB WRITES NOTHING
##
## Every check in every verb runs before the actor's store is touched and before a
## single modifier is stripped, and the roster table is only reached on the commit line
## (ADR 0044). A refusal is therefore a property of the control flow rather than a
## discipline each caller must remember.
##
## ## Leaving is always permitted, and it always costs
##
## [method leave] refuses `no_actor` and `not_a_member` and NOTHING else — no reason
## code is reachable from an exit. It strips the recognition, drops the standing the
## member earned and removes them from the roster, so walking out is a real loss and
## never a dead end.
##
## ## Admission is never free
##
## A joiner is seated in an authored office and immediately OWES what that office and
## the organization ask (`duty_<office>`, `duty_<id>`), which is the yin-yang pair:
## recognition on one side, an open debt on the other. An office whose authored
## `capacity` is filled refuses the admit as `capacity_full` — a REFUSAL, never a silent
## trim (ADR 0084) — while `capacity == 0` is an unbounded room that is never full.
##
## ## `position` and `standing` never derive from each other
##
## [method move_standing] is the only writer of standing here and it never reads the
## office; [method join] and [method found] write the office and never invent a
## standing. A member may hold a seat on thin standing and may hold thick standing in
## no office at all — ADR 0064's split, which is the whole politics layer (ADR 0083).
##
## ## Recognition is re-projected on EVERY change, strip first
##
## `join`, `leave`, `found`, [method move_standing] and [method reproject] all end in
## the same call, and `InstitutionProjection.grant` strips its own source tag before it
## writes. Delegating that loop unchanged measured the compounding directly: five
## rebuilds climbed the modifier stack 2, 4, 6, 8, 10, 12 while every assertion about
## the sheet still read plausibly. The tag is also the INVERSION: a contribution whose
## defining `.tres` has been deleted can still be taken back, which is exactly when a
## lost office would otherwise strand it.
##
## ## NOTHING HERE TICKS
##
## No `_process`, no `Time.get_ticks*`, no `get_tree()` (DEF-0111). Every accrual takes an
## explicit `periods` from a caller that owns time.

## The actor's `module_data` slot. Plain `String` keys and primitives throughout, because
## `Actor.to_dict` copies `module_data` VERBATIM and converts only the OUTER key, so an
## inner `StringName` key, a `Resource`, an `Actor` or a `Vector2` would reach the save
## untouched and no checker in this repo can see it.
const MEMBERSHIP_KEY := &"institutions"
## The namespace every institution's recognition is contributed under. Built at runtime
## through `InstitutionLedger.source_tagged`, because a `const` cannot hold a call and a
## hand-spelled third construction is what that helper exists to prevent.
const SOURCE_PREFIX := "institution:"
## This file's own store version, and deliberately NOT shared with any other ledger: four
## ledgers have four migration histories and one constant would make a bump in one
## re-stamp the others silently.
const STORE_VERSION := 1

## The refusals. Aliased from `InstitutionLedger` where one exists, and authored here only
## where that file has no opinion — a verb of this file's own.
const R_NO_ACTOR := InstitutionLedger.R_NO_ACTOR
const R_UNKNOWN_KIND := InstitutionLedger.R_UNKNOWN_KIND
const R_UNKNOWN_INSTITUTION := InstitutionLedger.R_UNKNOWN_INSTITUTION
## Admission into an organization this actor already belongs to. A guild a member may
## re-enter is not a membership.
const R_ALREADY_A_MEMBER := "already_a_member"
## The office the caller named exists, but the organization authors no such office. A
## CONTENT fault, refused rather than seated in a guessed one.
const R_UNKNOWN_POSITION := "unknown_position"
## An organization that AUTHORS offices but has no office a newcomer could enter, so
## there is nothing to seat anybody in. Distinct from `unknown_position`: that one names
## an office the content does not have, this one names a content that has none to offer.
const R_NO_ENTRY_OFFICE := "no_entry_office"
## The office is at its authored `capacity`. ADR 0084's overflow, and a REFUSED ADMIT —
## nobody is silently trimmed off a roster nobody voted to reduce.
const R_CAPACITY_FULL := "capacity_full"
## Leaving when the actor belongs to nothing. **The only thing `leave` refuses on** apart
## from `no_actor`: an exit that could be refused is a trap, not a door.
const R_NOT_A_MEMBER := "not_a_member"

## Every reason this surface can return, keyed by the name it is written with, so a
## caller can look one up without holding the constant. The ledger's own table PLUS this
## file's, never a filtered copy of it — a second list is a list somebody has to keep in
## step with the first.
const REASONS := {
	R_NO_ACTOR: R_NO_ACTOR,
	R_UNKNOWN_KIND: R_UNKNOWN_KIND,
	R_UNKNOWN_INSTITUTION: R_UNKNOWN_INSTITUTION,
	R_ALREADY_A_MEMBER: R_ALREADY_A_MEMBER,
	R_UNKNOWN_POSITION: R_UNKNOWN_POSITION,
	R_NO_ENTRY_OFFICE: R_NO_ENTRY_OFFICE,
	R_CAPACITY_FULL: R_CAPACITY_FULL,
	R_NOT_A_MEMBER: R_NOT_A_MEMBER,
}

## How many organizations the world roster table may carry. A hand-edited or runaway
## caller is refused room rather than allowed to grow a table every read walks. Mirrors
## `WorldPolityLedger.INSTITUTION_LIMIT` for the same reason, and is NOT the same
## constant: four ledgers, four migration histories.
const ROSTER_LIMIT := 64
## How many actors one office's holder list may name. The same corrupt-save guard on the
## inner container, so a roster cap that only bounds the outer one bounds nothing.
const HOLDER_LIMIT := 256

## The process-wide roster table: `{institution_id: {position_id: [actor_id, ...]}}`.
## STATIC because it is process state and the composition root owns the one instance, and
## public only through [method roster_of], [method rosters] and [method clear].
static var _rosters: Dictionary = {}


## ## What `actor` holds of every organization, as primitives.
##
## `{}` when the actor holds nothing — an empty answer is a STATE, not a failure, and it
## is the same value an unbound reader publishes. Otherwise
## `{institutions: {<organization_id>: {exists, kind, position, standing, standing_cap,
## normalized, obligations, roster}}}`.
##
## ## `normalized` is the CLAIM's own ratio, delegated not restated
##
## It is `InstitutionClaim.normalized()` on the read ledger, never `standing /
## standing_cap` written here. A caller publishing the two numbers and dividing them is
## a SECOND copy of that formula, which is the ADR 0066 failure mode inside the file
## that exists to remove it — and `ui/` reading a ratio rather than dividing one is what
## makes a card incapable of disagreeing with the claim it renders.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var claims := _claims(actor)
	var ids := _sorted_keys(claims)
	if ids.is_empty():
		return {}
	var institutions: Dictionary = {}
	# A `for` over a SNAPSHOT of the sorted ids, writing into a NEW dictionary: the body
	# never touches the container being walked, so the bound is the actor's own claim
	# count and there is no shape here for a loop to grow in lockstep with its own bound
	# (`tests/arch_rules/test_no_unbounded_wait.gd`).
	for institution_id in ids:
		institutions[institution_id] = _view(institution_id, claims[institution_id] as Dictionary)
	return {"institutions": institutions}


## The raw claim row `actor` holds for one organization, or `{}` — ADR 0083's FIRST
## state. A read rather than a second dictionary lookup by every caller, so a panel and
## a gate cannot drift into answering differently about the same membership.
static func claim_of(actor: Actor, institution_id: StringName) -> Dictionary:
	if actor == null:
		return {}
	var wanted := InstitutionLedger.text(institution_id, "")
	if wanted == "":
		return {}
	var found = _claims(actor).get(wanted, {})
	return (found as Dictionary).duplicate(true) if found is Dictionary else {}


## Whether `actor` holds a claim in `institution_id`. The cheap branch a caller takes when
## it only needs to know a membership exists.
static func holds(actor: Actor, institution_id: StringName) -> bool:
	if actor == null:
		return false
	return _claims(actor).has(InstitutionLedger.text(institution_id, ""))


## The source tag one organization's recognition is contributed under. Every strip and
## every rebuild goes through it, so a caller naming it by hand is a third construction
## of one namespace.
static func source_tag(institution_id: StringName) -> StringName:
	return InstitutionLedger.source_tagged(SOURCE_PREFIX, institution_id)


## ## Enrol `actor` in `institution_id`, seated in an authored office.
##
## `{ok, reason, ledger, institution, position, granted}` or
## `{ok: false, reason}` — the ledger's own shape plus the projected grant, so a caller
## publishes what landed rather than assuming it.
##
## ## The ENTRY office, and the rule that picks it
##
## A named `position_id` is taken as given and refused `unknown_position` when the
## content authors no such office. With no name, the entry office is the first authored
## office that is UNBOUNDED, in canonical id order, and `NO_POSITION` when the
## organization authors none. **Unbounded is the honest discriminator** because
## `InstitutionPositionDef`'s own note is the authority: `0` is a room with no walls, `1`
## is a seat, and above 1 is a room that can fill — so an unbounded office is exactly the
## one its author left open to any member, and it is the office a newcomer belongs in.
## Both shipped guilds author exactly one and both describe it as the ordinary member's
## office. The order is by ID, never array position, because ADR 0064 refuses an index
## standing in for an authored id.
##
## An organization whose every office is capped still admits an ordinary member holding
## no office — the member duty lines open either way, so admission is never free — and
## `NO_ENTRY_OFFICE` fires only when the kind AUTHORS offices and none of them can be
## named, which is a content fault rather than a policy.
static func join(
	registry: InstitutionRegistry,
	actor: Actor,
	institution_id: StringName,
	position_id: StringName = &""
) -> Dictionary:
	if actor == null:
		return InstitutionLedger.refuse(R_NO_ACTOR)
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	var wanted := InstitutionLedger.text(institution_id, "")
	if wanted == "":
		return InstitutionLedger.refuse(R_UNKNOWN_INSTITUTION)
	var def := _definition(wanted)
	if def == null:
		return InstitutionLedger.refuse(R_UNKNOWN_INSTITUTION)
	var claims := _claims(actor)
	if claims.has(wanted):
		return InstitutionLedger.refuse(R_ALREADY_A_MEMBER)
	var seated := _entry_office(def, position_id)
	if seated.get("refused", "") != "":
		return InstitutionLedger.refuse(String(seated["refused"]))
	var office: Variant = seated.get("office", null)
	var seat := InstitutionLedger.text(seated.get("position", ""), "")
	# ADR 0084's overflow, checked against the WORLD roster rather than a count of rows
	# somebody kept: an office is full when the organization says it is, and `has_room`
	# answers true for an unbounded one, so `capacity == 0` is never full.
	if (
		office != null
		and not (office as InstitutionPositionDef).has_room(_holders(wanted, seat).size())
	):
		return InstitutionLedger.refuse(R_CAPACITY_FULL)
	# ## The PROJECTION is asked BEFORE the claim is stored, and this is the ADR 0044 half
	# the checks above do not cover
	#
	# A grant can be REFUSED — a kind the registry does not know, or an allowlist naming a
	# stat this sheet cannot derive — and a refused grant writes nothing, so a join that
	# committed first and projected after would leave the member enrolled in a house that
	# recognises them not at all, with the refusal published nowhere. So the row is built, the
	# projection is run against a claim that is not yet stored, and only a success commits.
	# The projection is a pure function of `(allowlist, standing, tag, actor)`, so running it
	# against the uncommitted row is the same work, not a dry run that has to be undone.
	var row := _member_row(registry, def, office, seat)
	var granted := _project(actor, registry, row)
	if not bool(granted.get("ok", false)):
		return granted
	# Everything that can refuse has refused. Past this line the verb COMMITS, so there is
	# no ordering in which a refusal follows a write (ADR 0044).
	claims[wanted] = row
	_write_claims(actor, claims)
	_enrol(wanted, seat, String(actor.id))
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": row,
				"institution": wanted,
				"position": seat,
				"obligation": (row["obligation"] as Dictionary).duplicate(true),
				"granted": granted.get("granted", {}),
			}
		)
	)


## ## Walk out. Always permitted; the refusals are `no_actor` and `not_a_member` only.
##
## A NAMED `institution_id` leaves that one organization. An EMPTY one leaves EVERY
## organization the actor holds, and that is deliberate rather than a default: the UI
## seam is `leaver()` with no argument, so "leave" has to mean something total, and
## leaving all of them is the only reading that cannot be ambiguous about which house a
## player meant. Every organization named is walked out of, none is left behind, and the
## answer carries the list so a caller can show it.
##
## ## It COSTS, and the cost is the point
##
## The recognition is stripped, the standing the member earned goes with the claim, and
## the roster row is removed. A member with no exit is a bad state with no out.
##
## ## And it RE-PROJECTS the whole sheet
##
## Leaving is a moment of reconciliation, not only a removal: every remaining claim is
## rebuilt from its own row through the same strip-then-rebuild path, so a claim a save
## restored without its modifier comes back consistent and one that was never removed
## comes off.
static func leave(
	registry: InstitutionRegistry, actor: Actor, institution_id: StringName = &""
) -> Dictionary:
	if actor == null:
		return InstitutionLedger.refuse(R_NO_ACTOR)
	var claims := _claims(actor)
	var targets := _leave_targets(claims, institution_id)
	if targets.is_empty():
		return InstitutionLedger.refuse(R_NOT_A_MEMBER)
	# A `for` over the SNAPSHOT `targets`, writing into `claims`, into the world roster
	# and into the actor's modifier stack: none of those three is the array being walked,
	# so the bound is the claim count `targets` was built from and nothing can grow it.
	for leaving in targets:
		InstitutionProjection.strip(actor, source_tag(StringName(leaving)))
		claims.erase(leaving)
		_disenrol(leaving, String(actor.id))
	_write_claims(actor, claims)
	var reprojected := reproject(registry, actor)
	return (
		InstitutionLedger
		. ok(
			{
				"left": targets.duplicate(),
				"count": targets.size(),
				"reprojected": bool(reprojected.get("ok", false)),
			}
		)
	)


## ## Bring one organization into being and put the actor in it, PERSISTED.
##
## `InstitutionFounding.found` returns a NEW ledger and deliberately attaches nothing —
## persisting it is the composition root's job, which is exactly the gap this method
## closes. It delegates the founding itself, unchanged, so the price, the refusals and
## the seated office are the founding verb's own words; a refused founding writes nothing
## here either, because the store is only reached on the commit line.
##
## The founder's row is the founder's OWN ledger with the roster removed and the roster
## written to the world table instead — that one line is the whole difference between
## this file and sect's answer, where the roster lives on the founder's body and a member
## who joined rather than founded can never see it.
static func found(
	registry: InstitutionRegistry, actor: Actor, def: InstitutionDef, founder_id: String = ""
) -> Dictionary:
	if actor == null:
		return InstitutionLedger.refuse(R_NO_ACTOR)
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	if def == null:
		return InstitutionLedger.refuse(R_UNKNOWN_INSTITUTION)
	var wanted := String(def.id)
	var who := InstitutionLedger.text(founder_id, "")
	if who == "":
		who = String(actor.id)
	var claims := _claims(actor)
	# The actor's OWN claim for this organization is the prior ledger, so founding a house
	# twice refuses `already_found` on the second pass instead of charging the price again
	# for a claim that already exists.
	var answer := InstitutionFounding.found(
		registry, actor, def.founding_profile(), who, claims.get(wanted, {}) as Dictionary
	)
	if not bool(answer.get("ok", false)):
		return answer
	var row: Dictionary = (answer["ledger"] as Dictionary).duplicate(true)
	row.erase("roster")
	# ## The projection runs BEFORE the claim is stored, for `join`'s reason
	#
	# A refused grant writes nothing, so committing first would leave a founder who PAID for
	# a house and was then refused its recognition, with the refusal published nowhere and
	# the founding price already drawn. The founding verb has committed its own half by this
	# point — the price is drawn — which is why the projection is not merely checked here but
	# is reported: a caller reads `granted` and knows whether the house recognised its founder.
	var granted := _project(actor, registry, row)
	claims[wanted] = row
	_write_claims(actor, claims)
	_enrol(wanted, InstitutionLedger.text(row.get("position", ""), ""), who)
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": row,
				"institution": wanted,
				"position": InstitutionLedger.text(row.get("position", ""), ""),
				"charged": int(answer.get("charged", 0)),
				"granted": granted.get("granted", {}),
			}
		)
	)


## ## Move `actor`'s standing in one organization by `delta`, and re-project.
##
## The ONLY writer of standing on this surface, and it writes nothing else:
## `InstitutionLedger.move_standing` is handed the claim and never the office, so a promotion
## and a standing move cannot reach each other through a shared field name (ADR 0064).
##
## `registry` is INJECTED, for the reason every other verb here does it — and for one this
## verb made concrete. An earlier version reached for `InstitutionRegistry.instance()`, so a
## caller driving its OWN registry had its recognition silently STRIPPED on every standing
## move: the shared registry knew no kind, the rebuild read that as "this kind publishes no
## offices", and the grant came off the sheet with nothing said. A global makes a verb's
## answer depend on read order, which is exactly what `InstitutionRegistry` is an instance
## rather than a static table to prevent.
##
## Standing can go UP and DOWN, because it is earned and a module that could only raise it
## would be a favour rather than a standing. A zero delta is refused by the ledger's own
## `non_positive` and writes nothing, and the applied amount is returned so a caller
## publishes how much of a requested change actually landed.
static func move_standing(
	registry: InstitutionRegistry, actor: Actor, institution_id: StringName, delta: int
) -> Dictionary:
	if actor == null:
		return InstitutionLedger.refuse(R_NO_ACTOR)
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	var wanted := InstitutionLedger.text(institution_id, "")
	var claims := _claims(actor)
	if wanted == "" or not claims.has(wanted):
		return InstitutionLedger.refuse(R_NOT_A_MEMBER)
	var moved := InstitutionLedger.move_standing(claims[wanted] as Dictionary, delta)
	if not bool(moved.get("ok", false)):
		return moved
	var row: Dictionary = (moved["ledger"] as Dictionary).duplicate(true)
	claims[wanted] = row
	_write_claims(actor, claims)
	var granted := _project(actor, registry, row)
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": row,
				"standing": int(row.get("standing", 0)),
				"applied": int(moved.get("applied", 0)),
				"granted": granted.get("granted", {}),
			}
		)
	)


## ## Rebuild every recognition this actor's claims imply, and nothing else.
##
## Strip-then-rebuild for each organization in turn, which is what makes this idempotent:
## calling it any number of times leaves the sheet exactly where one call left it. This
## is the seam a composition root calls after a LOAD, because `Actor.from_dict` restores
## no `StatProvider` and a claim whose `.tres` is gone still owes a sheet.
##
## It rebuilds what the CLAIMS imply; it does not strip an organization the actor has
## already left, because [method leave] already strips by tag and a tag nobody writes is
## nobody's to remove here.
static func reproject(registry: InstitutionRegistry, actor: Actor) -> Dictionary:
	if actor == null:
		return InstitutionLedger.refuse(R_NO_ACTOR)
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	var claims := _claims(actor)
	var ids := _sorted_keys(claims)
	var granted: Dictionary = {}
	# A `for` over the SNAPSHOT of sorted ids, writing into `granted` and into the actor's
	# modifier stack: neither is the array being walked, so the bound is the actor's claim
	# count and no body here grows the container its own bound is read from.
	for institution_id in ids:
		var answer := _project(actor, registry, claims[institution_id] as Dictionary)
		if not bool(answer.get("ok", false)):
			return answer
		granted[institution_id] = answer.get("granted", {})
	return InstitutionLedger.ok({"granted": granted, "count": ids.size()})


## ## Who holds each office of one organization, as the WORLD publishes it.
##
## Every office the organization AUTHORS appears **once the world has published a roster for
## it at all** — with an empty holder list where nobody holds it, because an unfilled
## authored office is a fact about the world and a visible row (ADR 0084's vacancy design).
##
## ## An organization that has published NOTHING publishes nothing at all
##
## The authored offices do not by themselves make a roster. The roster is process state (see
## the class note), so a process that has just started knows only what the CONTENT authors,
## not who is standing in it — and before the world has a row for the organization this
## answers `{}`, which `InstitutionCard` renders as `holders not published` in its own
## `unknown` tone. Seeding the rows from the def alone answered "nobody holds anything
## anywhere" the instant the process restarted, and that is a claim about the world nobody
## made — measured by this suite's own restart case, where it turned five authored offices
## into declared vacancies.
##
## `{}` when the organization is unknown too — ADR 0083's FIRST state, never a fabricated
## empty roster.
static func roster_of(institution_id: StringName) -> Dictionary:
	var wanted := InstitutionLedger.text(institution_id, "")
	if wanted == "":
		return {}
	# The gate is the WORLD's row, not the def's offices: no row means nobody has published
	# this organization's roster, which is a different fact from a published roster nobody is
	# standing in.
	if not _rosters.has(wanted):
		return {}
	var out: Dictionary = {}
	var def := _definition(wanted)
	if def != null:
		for office in _sorted_keys(_office_ids(def)):
			out[office] = [] as Array
	var held: Dictionary = _rosters[wanted] as Dictionary
	# A `for` over the SNAPSHOT of the world's sorted position ids, writing into `out` and
	# never into the map being walked: the bound is the world's own office count.
	for position_id in _sorted_keys(held):
		out[position_id] = _holders(wanted, position_id)
	return out


## The whole world roster table, one level deeper than [method roster_of]. Published so a
## headless driver and a test answer from ONE read and none of them walks the static.
static func rosters() -> Dictionary:
	return _rosters.duplicate(true)


## ## Drop every roster row, and answer how many were dropped.
##
## Part of the surface rather than a test convenience: `tests/run_tests.gd` drives every
## suite in ONE process, so a roster a suite forgets to clear is handed to every suite
## after it. Idempotent — a second call answers `0` rather than refusing.
static func clear() -> int:
	var dropped := _rosters.size()
	_rosters.clear()
	return dropped


# --- Internals -----------------------------------------------------------------


## ## Where a claim is stored, and why `get_module_data` is not enough on its own
##
## The slot is a plain dictionary of primitives, so `get_module_data`'s own contract
## already turns a corrupt slot into `{}`. The `claims` CONTAINER inside it is checked
## here, because a hand-edited save may park a bare string there and a container nothing
## validated is where a corrupt payload becomes a plausible one.
static func _claims(actor: Actor) -> Dictionary:
	var slot = actor.get_module_data(MEMBERSHIP_KEY)
	if not (slot is Dictionary):
		return {}
	var claims = (slot as Dictionary).get("claims", {})
	return claims as Dictionary if claims is Dictionary else {}


static func _write_claims(actor: Actor, claims: Dictionary) -> void:
	actor.set_module_data(MEMBERSHIP_KEY, {"version": STORE_VERSION, "claims": claims})


## One claim as the screen's read model publishes it. `normalized` is the CLAIM's own
## ratio on the ledger's own repaired read, so the two never disagree and neither is a
## second copy of the other's formula.
static func _view(institution_id: String, row: Dictionary) -> Dictionary:
	var read_out := InstitutionLedger.read(row)
	if not bool(read_out["exists"]):
		return {}
	var claim := InstitutionClaim.from_dict(read_out)
	return {
		"exists": true,
		"kind": String(read_out["kind"]),
		"position": String(read_out["position"]),
		"standing": int(read_out["standing"]),
		"standing_cap": int(read_out["standing_cap"]),
		"normalized": claim.normalized(),
		"obligations":
		InstitutionLedger.positive_lines(read_out.get("obligation", {}) as Dictionary),
		"roster": roster_of(StringName(institution_id)),
	}


## The def for one organization, or null. Null rather than a guess: an unknown
## organization is a content bug and an invented def would hide it.
static func _definition(institution_id: String) -> InstitutionDef:
	if institution_id == "":
		return null
	return InstitutionDefCatalog.instance().definition(StringName(institution_id))


## `{position, office, refused}` — the office a joiner is seated in. `office` is null for
## a member holding no office, which is a legitimate state and never an error; `refused`
## names the content fault when the caller named an office the content does not author.
static func _entry_office(def: InstitutionDef, position_id: StringName) -> Dictionary:
	var named := InstitutionLedger.text(position_id, "")
	if named != "":
		var asked := def.position(StringName(named))
		if asked == null:
			return {"position": "", "office": null, "refused": R_UNKNOWN_POSITION}
		return {"position": named, "office": asked, "refused": ""}
	for office_id in _sorted_keys(_office_ids(def)):
		var office := def.position(StringName(office_id))
		# An UNBOUNDED room is the one its author left open to any member, so it is the
		# office a newcomer belongs in. The walk is over a materialised sorted id list and
		# `return` leaves on the first hit, so it drains the array it tests.
		if office != null and office.room() <= 0:
			return {"position": office_id, "office": office, "refused": ""}
	if def.positions.is_empty():
		return {"position": "", "office": null, "refused": ""}
	return {"position": "", "office": null, "refused": R_NO_ENTRY_OFFICE}


## ## The claim row a JOINER is given, and why it is the founder's own shape
##
## `InstitutionFounding.write` already merges the organization's membership lines with the
## office's by the LARGER count per term, and that merge is a RULE rather than a function
## two files share. So the joiner's row is built by that same writer rather than by a
## second merge here, and then three fields differ from a founder's:
##
##   - `standing` is 0, because `founder_standing` is the price of FOUNDING and charging
##     a newcomer for standing they have not earned is the same infinite regress the field
##     exists to avoid. Recognition is earned, so a brand-new member is recognised for
##     nothing until they earn it.
##   - `founder_id` is empty, because they founded nothing.
##   - `treasury` is REMOVED. Founding is the only verb that opens a treasury, and a
##     joiner must not open the institution's books on the way in.
##
## `registry` is INJECTED for the reason `move_standing` documents: `write` consults it for
## the `teaches` capability, so reaching for the shared one let a caller driving its own
## registry get a joiner row whose fit axis was written by a registry that knows nothing.
static func _member_row(
	registry: InstitutionRegistry, def: InstitutionDef, office: Variant, seat: String
) -> Dictionary:
	var profile := def.founding_profile()
	if office != null:
		profile["office_obligation"] = (office as InstitutionPositionDef).obligation_lines()
	var row := InstitutionFounding.write(registry, profile, "", InstitutionLedger.text(seat, ""))
	row["standing"] = 0
	row["founder_id"] = ""
	row.erase("roster")
	row.erase("treasury")
	return row


## ## Rebuild one claim's recognition: strip by TAG, then rebuild from the claim.
##
## The tag is the INVERSION, so a contribution is exactly invertible even after the `.tres`
## that authored it is deleted — which is precisely when losing an office would otherwise
## strand it. A kind that does not publish offices has no allowlist to project, so its tag is
## stripped and nothing is written: an empty grant is ADR 0083's FIRST state and a success,
## never a refusal.
##
## ## The THREE answers are kept apart, and this is where they were once collapsed
##
## An UNKNOWN KIND is not a kind without offices. `has_capability` answers
## `{ok: false, reason: "unknown_kind", has: false}` for a registry that has never heard of
## the kind, which is the same `has: false` a registered kind-without-offices returns — and
## reading that as the latter STRIPPED a live grant with nothing said, because a caller
## driving its own registry reached a rebuild that read the shared one. So the two answers
## are read separately: an unknown kind is a REFUSAL (`unknown_kind`, and a refusal writes
## nothing, so the standing grant survives), and only a KNOWN kind that declares no offices
## is the empty grant.
static func _project(actor: Actor, registry: InstitutionRegistry, row: Dictionary) -> Dictionary:
	var tag := source_tag(StringName(InstitutionLedger.text(row.get("institution", ""), "")))
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_INSTITUTION)
	var def := _definition(InstitutionLedger.text(row.get("institution", ""), ""))
	# The DEFINITION is gone — the `.tres` was deleted or the family was never loaded. There
	# is nothing to re-read an allowlist from, so the contribution is taken back rather than
	# welded to whoever held it: the tag is the inversion, and the claim outranks the content.
	if def == null:
		InstitutionProjection.strip(actor, tag)
		return InstitutionLedger.ok({"granted": {}})
	var verdict := registry.has_capability(def.kind, InstitutionRegistry.CAP_HAS_OFFICES)
	# ## An UNKNOWN KIND refuses, and refusing is NON-DESTRUCTIVE
	#
	# `InstitutionProjection.grant` validates before it strips for the same reason (ADR
	# 0083's third state writes nothing): a member does not lose the recognition they already
	# hold because a boot had not registered the kind this rebuild asked about.
	if not bool(verdict["ok"]):
		return InstitutionLedger.refuse(String(verdict["reason"]))
	if not bool(verdict["has"]):
		InstitutionProjection.strip(actor, tag)
		return InstitutionLedger.ok({"granted": {}})
	var read_out := InstitutionLedger.read(row)
	var office := def.position(StringName(String(read_out["position"])))
	var allowlist: Dictionary = office.standing_percent_stats if office != null else {}
	return InstitutionProjection.grant(actor, allowlist, int(read_out["standing"]), tag)


## The organizations `leave` will walk `actor` out of, canonically ordered. An empty
## answer means the actor belongs to nothing, which is the one refusal `leave` owns.
static func _leave_targets(claims: Dictionary, institution_id: StringName) -> Array:
	var wanted := InstitutionLedger.text(institution_id, "")
	if wanted != "":
		return [wanted] if claims.has(wanted) else ([] as Array)
	return _sorted_keys(claims)


## ## Put `actor_id` into `position_id`'s holder list, idempotently.
##
## Both guards are caps rather than loops, and both answer the same question: a table
## nobody bounds is a table a corrupt caller grows until every read walks it. The
## organization list is capped whole and the holder list per office, and neither bound is
## re-read from the container the body writes into.
static func _enrol(institution_id: String, position_id: String, actor_id: String) -> void:
	if institution_id == "" or position_id == "" or actor_id == "":
		return
	if not _rosters.has(institution_id) and _rosters.size() >= ROSTER_LIMIT:
		return
	var holders := _holders(institution_id, position_id)
	if holders.size() >= HOLDER_LIMIT or holders.has(actor_id):
		return
	holders.append(actor_id)
	_write_roster(institution_id, position_id, holders)


## ## Take `actor_id` out of every office of one organization, and drop the organization
## when nobody is left in it.
##
## A `for` over the SNAPSHOT of the roster's sorted position ids, writing into a DUPLICATE
## of that roster and never into the snapshot or into the live table: the body erases
## from the copy it is walking and the bound is the organization's own authored office
## count, so there is no shape here for a loop to grow in lockstep with its own bound.
static func _disenrol(institution_id: String, actor_id: String) -> void:
	if institution_id == "" or actor_id == "" or not _rosters.has(institution_id):
		return
	var live: Dictionary = _rosters[institution_id] as Dictionary
	var roster := live.duplicate(true)
	for position_id in _sorted_keys(live):
		var holders: Array = (roster[position_id] as Array).duplicate()
		holders.erase(actor_id)
		roster[position_id] = holders
	if roster.is_empty():
		_rosters.erase(institution_id)
		return
	_rosters[institution_id] = roster


## The holder list for one office, ALWAYS an array so a caller never branches on whether
## the office has ever been filled.
static func _holders(institution_id: String, position_id: String) -> Array:
	if institution_id == "" or position_id == "":
		return [] as Array
	var held: Variant = _rosters.get(institution_id, {})
	if not (held is Dictionary):
		return [] as Array
	var holders: Variant = (held as Dictionary).get(position_id, [])
	return (holders as Array).duplicate() if holders is Array else ([] as Array)


static func _write_roster(institution_id: String, position_id: String, holders: Array) -> void:
	var roster: Variant = _rosters.get(institution_id, {})
	var out: Dictionary = roster as Dictionary if roster is Dictionary else {}
	out[position_id] = holders
	_rosters[institution_id] = out


## Every office id this organization authors, keyed by id so the common `_sorted_keys`
## walk applies unchanged.
static func _office_ids(def: InstitutionDef) -> Dictionary:
	var out: Dictionary = {}
	for office_id in def.position_ids():
		out[String(office_id)] = true
	return out


## The keys of `source`, canonically ordered by their STRING value — never `sort()` on the
## raw keys, because the ids here are interned and interned order is not string order
## (`InstitutionRegistry._canonical` measured that divergence on this engine).
static func _sorted_keys(source: Dictionary) -> Array:
	var out: Array = []
	for key in source.keys():
		out.append(String(key))
	out.sort()
	return out
