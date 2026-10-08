class_name AdmitTable
extends InstitutionCapability

## The admission table: invitation policy plus requirement rows, and the three
## states each of them keeps apart (ADR 0083, ADR 0084, ADR 0922).
##
## ## The standard has NO admission gate today, and this is where one would live
##
## Measured: no shipped institution authors an admission requirement, and
## `InstitutionMembership.join` admits any actor into any def it can load. That
## is a DELIBERATE authored state — an open house — and not a gap this capability
## fills in: an empty table admits, exactly as an empty `SectGate` requirement
## admits. What the capability adds is the SHAPE an author needs the day a house
## wants a door, and the three-state vocabulary that keeps the door legible.
##
## ## A vacancy is never `0`; absent is not unmet
##
## The heart of this file, and the reason it is a contract rather than a check:
##
##   - `{}` — **does not exist**: no requirement under this id. Rendered as a
##     hidden row, never as `0` and never as unmet.
##   - `{"vacant": true}` — **exists and its value is absent**: the requirement
##     row is authored and the candidate's value is missing. A VISIBLE row with
##     its own tone, never a zero and never a hidden one.
##   - `{"ok": false, "reason": R, "unmet": [...]}` — **exists and is refused**:
##     the candidate was evaluated and failed, with the entries that say where.
##
## [method requirement] is the verb that answers the three states, one row at a
## time; [method admits] is the gate that folds a whole table to one verdict.
## A collapsed implementation — one where an absent value and a failed value
## both read as `0` — is the defect ADR 0083 exists to forbid, and the probes
## in [method contract_findings] assert the three shapes are distinguishable.
##
## ## What was REJECTED
##
## - **A derived invitation.** `invite_only` is AUTHORED data, and a table that
##   computed an invitation from other rows would make the door depend on read
##   order between requirements. The flag is one boolean and one meaning.
## - **Repairing a missing value.** [method requirement] reads what is there; it
##   never defaults a missing bar to zero, because a zero bar is an OPEN door and
##   a missing bar is a question the author has not answered. Those are opposite
##   outcomes and only one of them is safe to guess.
## - **Storing `required`/`actual` as formatted text.** The `unmet` entries are
##     primitives — `{kind, id, required, actual}` — mirroring `SectGate`'s own
##     entry shape, so a panel renders a reason rather than parsing a sentence.
## - **An admission that writes membership.** Joining is `join`'s act; this
##   capability only DECIDES whether it may happen, and a refused admit writes
##   nothing (ADR 0044).
##
## ## Context keys this capability reads
##
##   - `member` — the candidate's id (`String`), recorded for the plan.
##   - `invite_only` — `bool`, authored: the house admits by invitation. Absent
##     reads as `false` — an open house — because the ungated state is what a
##     table that authors nothing MEANS (`SectGate`'s `{}` reasoning).
##   - `requirements` — `{requirement_id: {kind, need, ...}}`, the authored
##     table. A requirement is data, never code: a map naming its own kind.
##   - `values` — `{requirement_id: value}`, what the candidate actually
##     carries. A requirement whose id is ABSENT here is `vacant`, never `0`.
##   - `invited` — `bool`: whether an invitation has actually been extended.
##     Only read when `invite_only` holds; irrelevant otherwise.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111).

## The id this capability is dispatched under.
const ID := &"admit_table"

## The house admits by invitation and none was extended. Distinct from `unmet`:
## this is not a bar the candidate failed but a door nobody opened for them.
const R_NOT_INVITED := "not_invited"
## No requirement id was named where one is required: there is no row to read,
## so the question is broken rather than answered `{}`.
const R_NO_REQUIREMENT := "no_requirement"
## The candidate's value for this requirement is not present. **Carried with
## `vacant: true` on the row**, never collapsed into a failed check and never
## into a zero.
const R_VACANT := "vacant"
## The candidate was evaluated against a row and fell short; the entries that
## say where travel in `unmet`.
const R_BELOW_REQUIREMENT := "below_requirement"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [R_NOT_INVITED, R_NO_REQUIREMENT, R_VACANT, R_BELOW_REQUIREMENT]
	return out


## ## One authored requirement row, answered in one of the three states.
##
## `{}` when the table authors no row under this id — DOES NOT EXIST, and a
## caller must render it as nothing rather than as a zero;
## `{"ok": true, "reason": "", "vacant": true, "kind": ...}` when the row exists
## and the candidate carries no value for it — EXISTS AND ITS VALUE IS ABSENT, a
## visible row in its own tone, carrying `required` only when the row authored
## one;
## `{"ok": true, "reason": "", "has": true, ...}` and
## `{"ok": false, "reason": "below_requirement", "unmet": [...]}` when the
## candidate was actually evaluated — EXISTS, EVALUATED.
##
## The comparison is `value >= need` for a numeric bar; every authored row here
## carries `kind` so a later expansion (a named flag, a held id) adds a branch
## rather than a second verb. The row's `label` composes from the requirement's
## own id, so a panel never has to invent one.
func requirement(ctx: Dictionary, requirement_id: StringName) -> Dictionary:
	if requirement_id == &"":
		return InstitutionCapability.refuse(R_NO_REQUIREMENT)
	var table = ctx.get("requirements", {})
	if not (table is Dictionary):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "requirements"}
		)
	var authored = InstitutionCapability.entry(table as Dictionary, requirement_id)
	if not (authored is Dictionary):
		# DOES NOT EXIST — ADR 0083's FIRST state, and the whole reason a
		# caller cannot collapse this with the refusal below.
		return {}
	var values = ctx.get("values", {})
	if not (values is Dictionary):
		return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": "values"})
	return _evaluate(
		authored as Dictionary,
		requirement_id,
		InstitutionCapability.entry(values as Dictionary, requirement_id)
	)


## ## One authored row judged against the candidate's value — the second half of
## ## [method requirement], split out for gdlint's `max-returns`.
##
## `{vacant: true}` when `held` is absent — a VISIBLE row in its own tone, never
## a zero; a success when the row asks nothing (`need` is absent) or the value
## clears the bar; a named refusal carrying its `unmet` entry otherwise. The
## three shapes are the whole point of this file, so the branch that produces
## each one is deliberately one `return` apiece.
func _evaluate(row: Dictionary, requirement_id: StringName, held: Variant) -> Dictionary:
	if held == null:
		var vacant := {
			"vacant": true,
			"id": String(requirement_id),
			"kind": InstitutionCapability.text(row.get("kind", ""), ""),
			"label": "%s has no value" % String(requirement_id),
		}
		# `need` is carried only when the row AUTHORED one: a `null` inside a
		# payload is not a primitive a save can round-trip, and the family's
		# `ok()` refuses the whole answer rather than letting one through.
		if row.has("need"):
			vacant["required"] = row["need"]
		return InstitutionCapability.ok(vacant)
	var need = row.get("need", null)
	if need == null:
		return _satisfied(row, requirement_id, held)
	if not (need is int or need is float) or not (held is int or held is float):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "requirements.%s" % String(requirement_id)}
		)
	if float(held) >= float(need):
		return _satisfied(row, requirement_id, held, need)
	return (
		InstitutionCapability
		. refuse(
			R_BELOW_REQUIREMENT,
			{
				"unmet":
				[
					{
						"kind": InstitutionCapability.text(row.get("kind", ""), ""),
						"id": String(requirement_id),
						"required": float(need),
						"actual": float(held),
					},
				],
			}
		)
	)


## The success shape of a row the candidate satisfied, with or without an
## authored bar. ONE builder for the two successes so the keys a caller reads
## cannot differ between a row that asks nothing and one that asks a number —
## `required` is present only where there was one to report.
func _satisfied(
	row: Dictionary, requirement_id: StringName, held: Variant, need: Variant = null
) -> Dictionary:
	var out := {
		"has": true,
		"id": String(requirement_id),
		"kind": InstitutionCapability.text(row.get("kind", ""), ""),
		"actual": held,
	}
	if need != null:
		out["required"] = float(need)
		out["actual"] = float(held)
	return InstitutionCapability.ok(out)


## ## Would this candidate be admitted? The whole table as one verdict.
##
## `{ok: true, reason: "", admitted: true}` or a refusal naming the door that
## closed: `invite_only` with no invitation refuses FIRST (a door nobody opened
## is a different fact from a bar a candidate missed); then every requirement is
## evaluated in canonical id order, the first failure wins, and every unmet
## entry travels so a panel can render all of them rather than the first.
##
## ## A vacant row is surfaced, never silently passed
##
## A requirement whose value is absent makes the whole admit VACANT-failing:
## the candidate cannot satisfy a question the content does not answer about
## them, and `unmet` carries the row with `actual: "vacant"` so the tone is the
## vacancy's own. Treating it as satisfied would admit on a missing answer;
## treating it as `0` would be the same collapse ADR 0083 forbids.
##
## An empty table admits: the ungated state is what a table that authors
## nothing MEANS, and `invite_only: false` with no requirements is an open
## house — a legitimate content state, not a hole.
func admits(ctx: Dictionary) -> Dictionary:
	if InstitutionCapability.flag(ctx.get("invite_only", false)):
		if not InstitutionCapability.flag(ctx.get("invited", false)):
			return InstitutionCapability.refuse(R_NOT_INVITED)
	var table = ctx.get("requirements", {})
	if not (table is Dictionary):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "requirements"}
		)
	var unmet: Array = []
	# A `for` over a materialised, canonically ordered key list, appending to a
	# NEW array: the body never writes to the table being walked, so the bound
	# is the authored table's own size and nothing here grows the container its
	# own bound is read from.
	for key in _sorted(table as Dictionary):
		var answer := requirement(ctx, StringName(key))
		if answer.is_empty():
			# A key the table itself holds cannot read as DOES NOT EXIST; the
			# walk is over the table's own keys, and an empty answer here means
			# the value map could not be read at all.
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED)
		if bool(answer.get("ok", false)) and bool(answer.get("vacant", false)):
			# ONE row shape, and `required` is carried only when the requirement
			# AUTHORED one: a `null` inside a payload is not a primitive a save
			# can round-trip, and the family's refusal builder refuses the whole
			# answer rather than letting one through.
			var row: Dictionary = {
				"kind": String(answer.get("kind", "")),
				"id": key,
				"actual": "vacant",
			}
			if answer.has("required"):
				row["required"] = answer["required"]
			unmet.append(row)
			continue
		if not bool(answer.get("ok", false)):
			if String(answer.get("reason", "")) == R_BELOW_REQUIREMENT:
				var entries = answer.get("unmet", [])
				if entries is Array:
					unmet.append_array(entries as Array)
				continue
			return answer
	if unmet.is_empty():
		return InstitutionCapability.ok({"admitted": true})
	return InstitutionCapability.refuse(
		R_VACANT if _all_vacant(unmet) else R_BELOW_REQUIREMENT, {"unmet": unmet}
	)


## ## The authored data this capability reads cannot be READ.
##
## A `requirements` that is not a map would make every row read as DOES NOT
## EXIST, which is indistinguishable from a table that authors nothing. `check`
## vets what is PRESENT; an absent key is the per-verb refusals' business.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["requirements", "values"]:
		if ctx.has(field) and not (ctx[field] is Dictionary):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes, and the three-state
## assertions are the point: a row the table does not author is `{}` (does not
## exist), a row with no value for the candidate is `vacant: true` (exists, its
## value is absent) and is NEVER `0`, an unmet row is a refusal carrying its
## entries, an open house admits, and an invitation-only house with no
## invitation refuses by name.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"member": "probe_candidate",
		"invite_only": false,
		"requirements":
		{"probe_purity": {"kind": "purity", "need": 10}, "probe_oath": {"kind": "flag"}},
		"values": {"probe_purity": 25},
	}
	var missing := requirement(probe.duplicate(true), &"probe_nowhere")
	if not missing.is_empty():
		found.append("requirement: a row the table does not author must answer {} (does not exist)")
	var vacant := requirement(probe.duplicate(true), &"probe_oath")
	_judge(found, "requirement", vacant)
	if bool(vacant.get("ok", false)):
		if not bool(vacant.get("vacant", false)):
			found.append(
				"requirement: a row with no candidate value must be `vacant`, not evaluated"
			)
		if vacant.has("actual"):
			found.append("requirement: a vacancy carries an `actual`, so it can render as a value")
	var met := requirement(probe.duplicate(true), &"probe_purity")
	_judge(found, "requirement", met)
	if bool(met.get("ok", false)) and not bool(met.get("has", false)):
		found.append("requirement: a satisfied numeric bar did not read as satisfied")
	var low := probe.duplicate(true)
	low["values"] = {"probe_purity": 1}
	expect_refusal(found, "requirement", requirement(low, &"probe_purity"), R_BELOW_REQUIREMENT)
	# A COMPLETE answer set, so `admits` exercises the whole-table pass rather
	# than the vacancy path measured separately below.
	var complete := probe.duplicate(true)
	complete["values"] = {"probe_purity": 25, "probe_oath": 1}
	var open_house := admits(complete)
	_judge(found, "admits", open_house)
	if bool(open_house.get("ok", false)) and not bool(open_house.get("admitted", false)):
		found.append(
			"admits: a table with every requirement met and no invitation policy must admit"
		)
	var closed := complete.duplicate(true)
	closed["invite_only"] = true
	expect_refusal(found, "admits", admits(closed), R_NOT_INVITED)
	closed["invited"] = true
	var opened := admits(closed)
	_judge(found, "admits", opened)
	if bool(opened.get("ok", false)) and not bool(opened.get("admitted", false)):
		found.append("admits: an invited candidate must be admitted")
	# The vacant row fails the whole admit and NAMES itself, rather than passing
	# silently on a missing answer.
	var half := probe.duplicate(true)
	half["values"] = {}
	expect_refusal(found, "admits", admits(half), R_VACANT)
	return found


# --- Internals ---------------------------------------------------------------


## ## The keys of `source`, canonically ordered by STRING value.
##
## A `for` over a snapshot of the keys, building a NEW array: the body never
## writes to the container being walked, so the sort cannot grow its own input
## — the `InstitutionLedger.sorted_keys` shape, local because `contracts/` may
## not depend on `core/`.
func _sorted(source: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in source.keys():
		out.append(String(key))
	out.sort()
	return out


## Whether EVERY unmet entry is a vacancy. Used only to pick which named reason
## the whole-table refusal reports, so a mixed table reports the substantive
## failure while a table of unanswered questions reports the vacancy — the two
## situations a panel renders in different tones.
func _all_vacant(unmet: Array) -> bool:
	if unmet.is_empty():
		return false
	for entry in unmet:
		if not (entry is Dictionary) or str((entry as Dictionary).get("actual", "")) != "vacant":
			return false
	return true
