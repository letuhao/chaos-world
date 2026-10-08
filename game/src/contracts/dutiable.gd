class_name Dutiable
extends InstitutionCapability

## Obligation terms as ids and counts, and what serving them DISCHARGES
## (ADR 0083, ADR 0922). The generalization of `SectDuty` and of
## `InstitutionClaim`'s obligation map: a duty is a named term and a period
## count, and serving pays it down without the institution ever keeping a
## second number beside the ledger.
##
## ## An over-settle CLAMPS and returns the settled count
##
## [method serve] publishes `settled` — how many periods actually came off the
## lines — and it is `min(owed, requested)`, **never the requested number**.
## That is the same property `InstitutionClaim.settle` already holds ("Returns
## how many were actually settled, so a caller can refuse to settle a line it
## has no ledger for instead of silently paying a debt it does not have"), and
## the reason it is a property: a caller that requested 10 against a line of 3
## and was told `10` would publish a settlement that never happened, and a save
## restored from that report would owe negative periods. The clamp is asserted
## as a COMPARISON (`settled <= owed` and `settled == min(owed, requested)`),
## never as a hand-written literal.
##
## ## What was REJECTED
##
## - **Two numbers: a rate and a total.** A term is `{id: periods_owed}` — ids
##   and counts, never authored amounts, so retuning a rate never rewrites a
##   save. A second "original" figure would be a number the ledger has to keep
##   in step with itself, the ADR 0066 failure mode inside one obligation line.
## - **Serving only on the crossing.** `SectDuty.serve` documents why a payment
##   that clears no term is still a payment: refusing the first periods of a
##   long term because no term happened to end would make a long term
##   impossible to pay down at all. So `paid` and `discharged` are separate
##   numbers here, exactly as they are there.
## - **A schedule.** Every line is paid the same `periods`, because a member's
##   service is ONE act; splitting it across lines by hand would be a caller
##   inventing an ordering the ledger has no opinion about.
## - **Absorbing an empty serve.** A serve with nothing owed is refused
##   `nothing_owed` rather than answering success-with-zero: a settlement that
##   moved nothing is indistinguishable from one that never ran, so it is a
##   named refusal and the context is untouched (ADR 0044).
##
## ## A vacancy is never 0, and neither is an absent term
##
## `owed` for a term nobody opened is `0` and that is correct — "nobody opened
## this debt" and "this debt is settled" are the same state
## (`InstitutionClaim.owed` states the rule). What is NOT absorbed is a serve
## whose plan would move nothing: that refuses by name instead of writing a
## zero.
##
## ## Context keys this capability reads
##
##   - `member` — the serving member's id (`String`), recorded on the plan.
##   - `owed` — the open lines, `{term_id: periods}`, a `Dictionary`. The
##     caller reads it from the member's claim (`obligation` map); this layer
##     may not name the claim store it lives in.
##   - `periods` — how many periods this call serves, an explicit argument from
##     a caller that owns time (DEF-0111). Below 1 refuses `no_periods`.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111). Every
## accrual takes an explicit `periods` from a caller that owns time.

## The id this capability is dispatched under.
const ID := &"dutiable"

## What was owed is already settled: the serve moved nothing, so it is refused
## rather than answered with a zero. A settlement that moved nothing is
## indistinguishable from one that never ran.
const R_NOTHING_OWED := "nothing_owed"
## No term was named where a verb needs one: there is no line to ask about, so
## the question itself is broken rather than answered `0`.
const R_NO_TERM := "no_term"
## The open lines arrived in a shape nothing can read. A `String` where the map
## should be would make every line read as absent, which is indistinguishable
## from a member who owes nothing.
const R_MALFORMED_LEDGER := "malformed_ledger"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [R_NOTHING_OWED, R_NO_TERM, R_MALFORMED_LEDGER]
	return out


## ## What one line still owes, as a READ.
##
## `{ok: true, reason: "", term, owed}` for a named term — `owed` is `0` for a
## line nobody opened, which is the settled state and never an error. A refusal
## only for a question that cannot be asked (`no_term`) or a ledger that cannot
## be read (`malformed_ledger`).
func owed_of(ctx: Dictionary, term_id: StringName) -> Dictionary:
	if term_id == &"":
		return InstitutionCapability.refuse(R_NO_TERM)
	var lines = ctx.get("owed", {})
	if not (lines is Dictionary):
		return InstitutionCapability.refuse(R_MALFORMED_LEDGER)
	var held = InstitutionCapability.entry(lines as Dictionary, term_id)
	if not (held is int or held is float):
		return InstitutionCapability.ok({"term": String(term_id), "owed": 0})
	return InstitutionCapability.ok({"term": String(term_id), "owed": maxi(0, int(held))})


## ## Every period still owed across every open line, as one number.
##
## A read, so a gate and a panel cannot drift into answering different
## questions about the same member — the shared read `SectDuty.still_owed`
## already provides on the sect side. Lines at zero or below contribute
## nothing, and a corrupt value reads as absent rather than aborting the walk.
func outstanding(ctx: Dictionary) -> Dictionary:
	var lines = ctx.get("owed", {})
	if not (lines is Dictionary):
		return InstitutionCapability.refuse(R_MALFORMED_LEDGER)
	var total := 0
	for key in (lines as Dictionary).keys():
		var held = (lines as Dictionary)[key]
		if held is int or held is float:
			total += maxi(0, int(held))
	return InstitutionCapability.ok({"owed": total, "terms": (lines as Dictionary).size()})


## ## Plan one call of service, or refuse it.
##
## `{ok: true, reason: "", plan: {member, periods, settled, remaining, cause},
## served: [{term, settled, discharged}, ...]}` — where `served` is the
## per-term list the applier writes, `settled` the TOTAL periods that actually
## came off the lines (clamped), and `remaining` what the member still owes
## after this call. Every number is primitives-only, and the plan is a read the
## applier applies; this contract commits nothing.
##
## `served` rides at the TOP level beside `plan` rather than inside it: a row
## inside an array inside a plan is one nesting past the family's
## `MAX_PAYLOAD_DEPTH`, and the payload rule refuses a shape it cannot verify
## rather than letting an unverifiable one through.
##
## Refusal order: periods positive, ledger readable, something actually owed.
## A refusal returns ABOVE the plan, so a refused serve writes nothing
## (ADR 0044) — and there is no branch where a refusal follows a moved count.
##
## ## The clamp, in three numbers
##
## `settled = min(owed, periods)` PER LINE, summed; `discharged` counts TERMS a
## call brought to zero (the crossing), because a term of three paid one at a
## time is three services and ONE oath. Reading the crossing after the payment
## is what makes it a crossing; reading it before would record a payment that
## did not clear the term.
func serve(ctx: Dictionary) -> Dictionary:
	var periods := InstitutionCapability.count(ctx.get("periods", 0), 0)
	if periods < 1:
		return InstitutionCapability.refuse(InstitutionCapability.R_NO_PERIODS)
	var lines = ctx.get("owed", {})
	if not (lines is Dictionary):
		return InstitutionCapability.refuse(R_MALFORMED_LEDGER)
	var rows: Array = []
	var settled_total := 0
	var remaining := 0
	# A `for` over a materialised, canonically ordered key list, writing into
	# `rows` and into two counters: the body never writes to the object being
	# walked, so the bound is the member's own open-line count and nothing here
	# grows the container its own bound is read from.
	for key in _sorted(lines as Dictionary):
		var owed := maxi(0, _count((lines as Dictionary)[key]))
		if owed <= 0:
			continue
		var settled := mini(owed, periods)
		var left := owed - settled
		settled_total += settled
		remaining += left
		(
			rows
			. append(
				{
					"term": key,
					"settled": settled,
					"discharged": left <= 0,
				}
			)
		)
	if settled_total <= 0:
		return InstitutionCapability.refuse(R_NOTHING_OWED, {"owed": remaining})
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"member": InstitutionCapability.text(ctx.get("member", ""), ""),
					"periods": periods,
					"settled": settled_total,
					"remaining": remaining,
					"cause": "served",
				},
				# The per-line breakdown rides at the TOP level, not inside the
				# plan: a row dictionary inside an array inside a plan is one
				# level past the family's `MAX_PAYLOAD_DEPTH`, and the payload
				# rule refuses it rather than letting an unverifiable shape
				# through.
				"served": rows,
			}
		)
	)


## ## The authored data this capability reads cannot be READ.
##
## `owed` that is not a map would make every line read as absent, which is
## indistinguishable from a member who owes nothing. `check` vets what is
## PRESENT; an absent key is the per-verb refusals' business.
func check(ctx: Dictionary) -> Dictionary:
	if ctx.has("owed") and not (ctx["owed"] is Dictionary):
		return InstitutionCapability.refuse(R_MALFORMED_LEDGER, {"field": "owed"})
	if ctx.has("periods") and not (ctx["periods"] is int or ctx["periods"] is float):
		return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": "periods"})
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: an over-settle CLAMPS —
## asserted as `settled == min(owed, periods)` and `settled <= owed`, never as
## two literals — the settled total equals the sum of the per-line clamps, a
## serve that clears a term RECORDS the crossing and one that does not clears
## nothing, and a member with nothing owed is refused `nothing_owed` rather
## than answered with a zero.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	# owed 5, requested 9: the clamp is the whole point, and this context makes
	# it visible in one call.
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"member": "probe_member",
		"owed": {"probe_duty": 5, "probe_patronage": 1},
		"periods": 9,
	}
	var planned := serve(probe.duplicate(true))
	_judge(found, "serve", planned)
	# Every expectation below is computed FROM the probe, so the clamp is
	# asserted as the comparison `min(owed, requested)` rather than as a
	# hand-written total two literals could drift from.
	var charged := int(probe["periods"])
	var lines: Dictionary = probe["owed"]
	var expected := 0
	var expected_crossings := 0
	for key in _sorted(lines):
		var owed := int(lines[key])
		expected += mini(owed, charged)
		if owed <= charged:
			expected_crossings += 1
	if bool(planned.get("ok", false)):
		var plan = planned.get("plan", {})
		if not (plan is Dictionary):
			found.append("serve: a successful plan is not a dictionary")
		else:
			var row := plan as Dictionary
			var settled := int(row.get("settled", -1))
			if settled != expected:
				found.append("serve: settled %d, expected the clamped %d" % [settled, expected])
			if settled > expected:
				found.append("serve: settled more than the lines owed")
			var served = planned.get("served", [])
			var summed := 0
			var crossings := 0
			if served is Array:
				for entry in served as Array:
					if entry is Dictionary:
						summed += int((entry as Dictionary).get("settled", 0))
						if bool((entry as Dictionary).get("discharged", false)):
							crossings += 1
			if summed != settled:
				found.append("serve: the per-line settled rows do not sum to `settled`")
			if crossings != expected_crossings:
				found.append(
					"serve: discharged %d terms, expected %d" % [crossings, expected_crossings]
				)
	var partial := probe.duplicate(true)
	partial["periods"] = 2
	var part := serve(partial)
	_judge(found, "serve", part)
	if bool(part.get("ok", false)):
		var served_rows = part.get("served", [])
		var crossings := 0
		if served_rows is Array:
			for entry in served_rows as Array:
				if entry is Dictionary and bool((entry as Dictionary).get("discharged", false)):
					crossings += 1
		var partial_crossings := 0
		for key in _sorted(lines):
			if int(lines[key]) <= 2:
				partial_crossings += 1
		if crossings != partial_crossings:
			found.append(
				(
					"serve: a partial payment discharged %d terms, expected %d"
					% [crossings, partial_crossings]
				)
			)
	var empty := probe.duplicate(true)
	empty["owed"] = {}
	expect_refusal(found, "serve", serve(empty), R_NOTHING_OWED)
	var zero := probe.duplicate(true)
	zero["periods"] = 0
	expect_refusal(found, "serve", serve(zero), InstitutionCapability.R_NO_PERIODS)
	return found


# --- Internals ---------------------------------------------------------------


## ## The keys of `lines`, canonically ordered by STRING value.
##
## A `for` over a snapshot of the keys, building a NEW array: the body never
## writes to the container being walked, so the sort cannot grow its own input
## — the `InstitutionLedger.sorted_keys` shape, local because `contracts/` may
## not depend on `core/`.
func _sorted(lines: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in lines.keys():
		out.append(String(key))
	out.sort()
	return out


## `value` as a non-negative integer count, `0` otherwise. A corrupt line reads
## as absent rather than aborting the walk: the alternative — a raw `int()` on
## a dictionary — raises in GDScript, so one hand-edited save would take out
## the whole serve instead of reading as a member with a damaged line.
func _count(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	return maxi(0, int(value))
