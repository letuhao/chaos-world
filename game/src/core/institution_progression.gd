class_name InstitutionProgression
extends RefCounted

## The APPLIER of organization progression (D11): the one store the counter
## lives in, and the verbs that read and move it, driving `Progressive`
## unchanged. A capability DECIDES; this file writes what its plan says
## (ADR 0922).
##
## ## Where the counter lives, and why it is not on an actor
##
## `InstitutionMembership` states the split this file obeys: a fact whose subject
## includes an actor id stays on that actor; a fact whose subject is the
## ORGANIZATION goes to the world. The counter's subject is the organization —
## duty served by its members, people it admitted — so it is NOT on any member's
## body, and a member who leaves does not take the organization's growth with
## them. No world save slot can accept it today (`WorldPolityLedger`'s row
## normalizer keeps four fields and drops everything else), so the store is a
## process table with [method clear] in the surface, exactly the
## `InstitutionMembership` roster shape — and the persistence gap is that file's
## own DEF-0119, recorded there rather than re-authored here.
##
## ## A REFUSED VERB WRITES NOTHING (ADR 0044)
##
## [method declare] validates the authored table THROUGH the capability before
## any row exists; [method record] drives `Progressive.accrue` and writes the
## returned plan's `points` only on success. Every refusal returns above the
## write line, so a broken table or an idle accrual leaves the store
## byte-for-byte as found.
##
## ## The milestones are CALLER-FED, and that is the honest state today
##
## `InstitutionDef` authors no milestone table yet, so [method declare] takes the
## table the way `AdmitTable`'s `join` takes its admission rows: the content's
## future home is the def (the exact edit is reported with this slice — a
## `milestones` field, a `progression_capacity` field and one boot call), and
## until then the caller hands it in. Nothing here invents a table.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111). [method
## record] takes the activity counts a caller that owns time and the ledger has
## already measured.

## This file's own store version, and deliberately NOT shared with any other
## ledger: the ledgers here have independent migration histories and one
## constant would make a bump in one re-stamp the others silently.
const STORE_VERSION := 1

## The refusal an empty institution id reaches. Aliased from the ledger, so a
## caller may look the reason up under either name and get one value.
const R_UNKNOWN_INSTITUTION := InstitutionLedger.R_UNKNOWN_INSTITUTION
## An accrual or a read on an organization nobody declared. Distinct from the
## empty id above: that one names nothing, this one names something the store
## has no row for.
const R_UNKNOWN_RECORD := "unknown_record"
## A second [method declare] for one organization. Loud, never idempotent: two
## rows for one identity are two owners of one counter, and
## `InstitutionContract.register` records the same rule.
const R_ALREADY_DECLARED := "already_declared"
## The store is at [constant RECORD_LIMIT]. A table nobody bounds is a table a
## corrupt caller grows until every read walks it.
const R_RECORD_LIMIT := "record_limit"

## Every reason this surface can return, keyed by the name it is written with,
## so a caller can look one up without holding the constant. The capability's
## own refusals pass through verbatim and are deliberately absent: they are its
## vocabulary, and a second table here would be a list somebody has to keep in
## step (ADR 0066).
const REASONS := {
	R_UNKNOWN_INSTITUTION: R_UNKNOWN_INSTITUTION,
	R_UNKNOWN_RECORD: R_UNKNOWN_RECORD,
	R_ALREADY_DECLARED: R_ALREADY_DECLARED,
	R_RECORD_LIMIT: R_RECORD_LIMIT,
}

## How many organizations the store may carry. Mirrors `InstitutionMembership`'s
## `ROSTER_LIMIT` for the same reason, and is NOT the same constant: independent
## stores, independent bounds.
const RECORD_LIMIT := 64

## The process-wide store: `{institution_id: {version, points, milestones,
## base_capacity}}`. STATIC because it is process state and the composition root
## owns the one instance, and public only through [method summary], [method
## records] and [method clear].
static var _records: Dictionary = {}


## ## Declare one organization's authored milestone table, or refuse it.
##
## `{ok: true, reason: "", institution, milestones, points, base_capacity}` or
## `{ok: false, reason: <named constant>}` — the three-state vocabulary, where a
## refusal is a third thing and never a silently absent row. The table is graded
## THROUGH `Progressive.progress` before any row exists, so a table this contract
## cannot read is refused where it was written and nothing is half-declared.
##
## `milestones` is untyped on purpose: a typed element would make GDScript RAISE
## at the call boundary on a wrongly-shaped row, so a corrupt table would abort
## the caller instead of being refused here — `InstitutionContract.register`
## records the identical reasoning for its `capabilities` parameter.
##
## A duplicate is refused [constant R_ALREADY_DECLARED]; a boot that re-walks
## asks [method knows] first, the `InstitutionBoot.register_def` pattern.
static func declare(
	institution_id: StringName, milestones: Array = [], base_capacity: int = 0
) -> Dictionary:
	var wanted := InstitutionLedger.text(institution_id, "")
	if wanted == "":
		return InstitutionLedger.refuse(R_UNKNOWN_INSTITUTION)
	if _records.has(wanted):
		return InstitutionLedger.refuse(R_ALREADY_DECLARED)
	if _records.size() >= RECORD_LIMIT:
		return InstitutionLedger.refuse(R_RECORD_LIMIT)
	var candidate := {
		"points": 0,
		"milestones": milestones,
		"base_capacity": maxi(0, base_capacity),
	}
	var graded := _drive("progress", wanted, candidate, 0, 0)
	if not bool(graded.get("ok", false)):
		return graded
	_records[wanted] = {
		"version": STORE_VERSION,
		"points": 0,
		"milestones": milestones.duplicate(true),
		"base_capacity": maxi(0, base_capacity),
	}
	return (
		InstitutionLedger
		. ok(
			{
				"institution": wanted,
				"milestones": (milestones as Array).size(),
				"points": 0,
				"base_capacity": maxi(0, base_capacity),
			}
		)
	)


## ## Record the activity an organization earned since the last accrual.
##
## `served` is the duty periods actually settled (the sum of `Dutiable.serve`'s
## per-line `settled`) and `admitted` is the members admitted. The capability
## turns them into a plan; on success the plan's `points` is written and the
## whole answer is returned with `institution` added, so a caller publishes what
## landed rather than assuming it. On any refusal NOTHING is written.
static func record(institution_id: StringName, served: int = 0, admitted: int = 0) -> Dictionary:
	var wanted := InstitutionLedger.text(institution_id, "")
	var stored = _records.get(wanted, null)
	if not (stored is Dictionary):
		return InstitutionLedger.refuse(R_UNKNOWN_RECORD)
	var row := stored as Dictionary
	var planned := _drive("accrue", wanted, row, served, admitted)
	if not bool(planned.get("ok", false)):
		return planned
	# Everything that can refuse has refused. Past this line the verb COMMITS
	# (ADR 0044), so there is no ordering in which a refusal follows a write.
	row["points"] = int((planned.get("plan", {}) as Dictionary).get("points", 0))
	var answer := planned.duplicate(true)
	answer["institution"] = wanted
	return answer


## ## Where one organization's growth stands, as a READ.
##
## `{}` when the organization was never declared — ADR 0083's FIRST state, a
## different answer from a refusal and never a fabricated zero. Otherwise the
## capability's own read, so a panel and a gate cannot drift into answering
## differently about the same counter.
static func summary(institution_id: StringName) -> Dictionary:
	var wanted := InstitutionLedger.text(institution_id, "")
	var stored = _records.get(wanted, null)
	if not (stored is Dictionary):
		return {}
	return _drive("progress", wanted, stored as Dictionary, 0, 0)


## Whether an organization's table has been declared. The cheap branch a caller
## takes before deciding whether to declare — the `InstitutionBoot.register_def`
## fold, without this file folding anything itself.
static func knows(institution_id: StringName) -> bool:
	return _records.has(InstitutionLedger.text(institution_id, ""))


## The whole store, one level deeper than [method summary]. Published so a
## headless driver and a test answer from ONE read and none of them walks the
## static.
static func records() -> Dictionary:
	return _records.duplicate(true)


## ## Drop every row, and answer how many were dropped.
##
## Part of the surface rather than a test convenience: `tests/run_tests.gd`
## drives every suite in ONE process, so a row a suite forgets to clear is
## handed to every suite after it. Idempotent — a second call answers `0` rather
## than refusing.
static func clear() -> int:
	var dropped := _records.size()
	_records.clear()
	return dropped


# --- Internals ---------------------------------------------------------------


## ## One capability verb, driven with the store's own row as its context
##
## The capability is constructed per call and never cached: it holds no state,
## and a cached instance would be one more thing a suite has to remember to
## reset. `verb` names which of the two verbs to drive, so the context build
## exists once — `record` and `summary` differ only in which verb reads it.
static func _drive(
	verb: String, institution_id: String, row: Dictionary, served: int, admitted: int
) -> Dictionary:
	var ctx := {
		"kind": "progressive_probe",
		"institution": institution_id,
		"points": int(row.get("points", 0)),
		"milestones": row.get("milestones", []),
		"base_capacity": int(row.get("base_capacity", 0)),
		"served": served,
		"admitted": admitted,
	}
	var impl := Progressive.new()
	return impl.accrue(ctx) if verb == "accrue" else impl.progress(ctx)
