class_name Successive
extends InstitutionCapability

## A succession is WALKED, never rolled (ADR 0084, taking ADR 0058's ascension
## shape). The generalization of `SectSuccession`: one authored stage per call,
## a period between stages, and no `rng` at all — so the outcome is a pure
## function of the ledger, and a test needs no seeded generator to prove it.
##
## ## No randomness anywhere, and the probes assert determinism
##
## There is no `RandomNumberGenerator`, no `randi`, no seeding hook, and no
## context key a roll could be read from. Rolling `standing / threshold` would
## make a promotion a gambling event and a gate that can satisfy itself, which
## is exactly what ADR 0084 rejects. The contract suite asserts the property
## rather than the absence: [method contract_findings] calls [method advance]
## twice on identical contexts and compares the answers by TEXT, so two runs
## that disagree — by a roll, by a read order, by anything — are a finding.
##
## ## One stage per call, and the clock is SPENT, not merely read
##
## Each `advance` costs the office's authored `stage_periods` out of the
## vacancy clock, so the next stage has to wait its own turn: a walk that left
## the count standing would be paced by the FIRST period alone, and the seat
## would then take every remaining stage back-to-back with nothing between
## them. This is what makes "refuses a further step until a period elapses" a
## property of the walk rather than a thing the first wait has to be remembered
## for — and the suite measures it by applying the plan and stepping again.
##
## ## What was REJECTED
##
## - **An index.** `stage` is a COUNT that is clamped against the authored
##   `walk_length` before anything reads it, so a corrupt save holding a
##   negative number or a million talks this module into nothing at all rather
##   than into a very long walk. There is no loop here; a walk is advanced one
##   explicitly requested step at a time, and [constant MAX_WAIT_PERIODS]
##   bounds how far one call may wait.
## - **A `step(office)` that trusts its ledger.** The clamped read is the whole
##   defence: `stage`, `held_periods` and `walk_length` all pass through
##   [method _count] or a clamp before use.
## - **Rolling `standing / threshold`** — ADR 0084's own rejection, recorded
##   here because the whole reason a succession is a contract is that a sect is
##   not the only institution that holds seats.
##
## ## Context keys this capability reads
##
##   - `member` — the acting member's id (`String`), recorded on the plan.
##   - `office` — the office id the walk is about (`String`). A seat, not a
##     person: several offices can walk at once and each has its own row.
##   - `open` — `bool`: whether a walk is open on this office.
##   - `stage` — int: how many authored stages have landed, clamped into
##     `[0, walk_length]`.
##   - `walk_length` — int: how many stages a full walk takes, authored. A
##     length of zero or less means the office has no walk at all.
##   - `stage_periods` — int: periods each stage costs, authored.
##   - `held_periods` — int: how many periods the vacancy has accrued.
##   - `periods` — int: how many periods one call waits. Bounded by
##     [constant MAX_WAIT_PERIODS]; a value below 1 refuses `no_periods`.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111). Every
## accrual takes an explicit `periods` from a caller that owns time.

## The id this capability is dispatched under.
const ID := &"successive"

## The two sides of a walk, as authored words rather than booleans, so a save
## and a screen read the same two strings.
const VACANT := &"vacant"
const SEATED := &"seated"

## The cap on periods a caller may wait in one call. A bounded parameter rather
## than an unbounded one: "wait until it comes due" must not be a way to skip
## the walk, and a caller that needs more waits more than once.
const MAX_WAIT_PERIODS := 8
## The longest walk any office may author. A corrupt save cannot describe a
## walk longer than this, and no shipped office needs more — the clamp is what
## stops `walk_length` from being an unbounded loop written as data.
const MAX_WALK_LENGTH := 32

## No office was named: a walk is a fact about a SEAT, so there is nothing to
## ask about.
const R_NO_OFFICE := "no_office"
## No walk is open on this office. Distinct from `walk_complete`: a walk that
## finished is done, and a walk that was never begun is a different state.
const R_NO_SUCH_WALK := "no_such_walk"
## A walk is already open on this office. Re-opening it would discard the
## stages it has taken, which is a reset wearing an open's clothes.
const R_ALREADY_OPEN := "already_open"
## This office authors no walk at all (`walk_length < 1`), so there is no
## succession method to advance. A refusal rather than an instant success: a
## seat that is simply APPOINTED is a different authored method.
const R_NO_WALK_AUTHORED := "no_walk_authored"
## The next stage is not due: the vacancy clock has not accrued the authored
## `stage_periods`. This is the one refusal ADR 0084's "refuses a further step
## until a period elapses" actually lives in.
const R_PERIOD_NOT_ELAPSED := "period_not_elapsed"
## The walk has taken every authored stage. Distinct from `no_such_walk`: a
## finished walk is complete, and a walk nobody opened is absent.
const R_WALK_COMPLETE := "walk_complete"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [
		R_NO_OFFICE,
		R_NO_SUCH_WALK,
		R_ALREADY_OPEN,
		R_NO_WALK_AUTHORED,
		R_PERIOD_NOT_ELAPSED,
		R_WALK_COMPLETE,
	]
	return out


## ## Where the walk stands, as a READ.
##
## `{ok: true, reason: "", office, stage, length, complete, side, ready,
## held_periods}` — every number clamped, and `ready` publishes whether the next
## stage is due so a caller about to show a button renders WHY without
## re-deriving the comparison. [method advance] is where the gate refuses; a
## read that refused on a young walk would make a screen unable to show the
## bar, the same split `Expellable.costs` keeps.
func walk(ctx: Dictionary) -> Dictionary:
	var office := InstitutionCapability.text(ctx.get("office", ""), "")
	if office == "":
		return InstitutionCapability.refuse(R_NO_OFFICE)
	var length := _clamped(ctx.get("walk_length", 0))
	var stage := _clamped(ctx.get("stage", 0))
	if stage > length:
		stage = length
	var cost := maxi(0, _count(ctx.get("stage_periods", 0)))
	var held := maxi(0, _count(ctx.get("held_periods", 0)))
	var complete := length > 0 and stage >= length
	return (
		InstitutionCapability
		. ok(
			{
				"office": office,
				"stage": stage,
				"length": length,
				"complete": complete,
				"side": String(SEATED if complete else VACANT),
				"ready": not complete and length > 0 and held >= cost,
				"held_periods": held,
			}
		)
	)


## ## Plan the opening of a vacancy on `office`, or refuse it.
##
## `{ok: true, reason: "", plan: {member, office, side, stage, held_periods,
## cause}}` — a walk that starts at stage 0, vacant, with a fresh clock. The
## plan is the applier's write instruction; this contract commits nothing.
func open(ctx: Dictionary) -> Dictionary:
	var office := InstitutionCapability.text(ctx.get("office", ""), "")
	if office == "":
		return InstitutionCapability.refuse(R_NO_OFFICE)
	if InstitutionCapability.flag(ctx.get("open", false)):
		return InstitutionCapability.refuse(R_ALREADY_OPEN, {"office": office})
	if _clamped(ctx.get("walk_length", 0)) < 1:
		return InstitutionCapability.refuse(R_NO_WALK_AUTHORED, {"office": office})
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"member": InstitutionCapability.text(ctx.get("member", ""), ""),
					"office": office,
					"side": String(VACANT),
					"stage": 0,
					"held_periods": 0,
					"cause": "seat_vacated",
				},
			}
		)
	)


## ## Plan `periods` of waiting on an open walk, or refuse it.
##
## `{ok: true, reason: "", plan: {office, held_periods, waited}}` — the accrual
## `SectSuccession.accrue` performs, as a plan. A walk that is complete refuses
## `walk_complete` (there is nothing left to wait FOR), and a walk nobody
## opened refuses `no_such_walk`: a seat nobody vacated has no vacancy to age.
func wait(ctx: Dictionary) -> Dictionary:
	var office := InstitutionCapability.text(ctx.get("office", ""), "")
	if office == "":
		return InstitutionCapability.refuse(R_NO_OFFICE)
	var stood := walk(ctx)
	if not bool(stood.get("ok", false)):
		return stood
	if not InstitutionCapability.flag(ctx.get("open", false)):
		return InstitutionCapability.refuse(R_NO_SUCH_WALK, {"office": office})
	if bool(stood["complete"]):
		# There is nothing left to wait FOR: the walk is done, so an accrual
		# would be a number with no reader. The `walk_complete` row is the
		# refusal, not a silent success, for the same reason `advance` refuses
		# one — a settlement that moved nothing is indistinguishable from one
		# that never ran.
		return InstitutionCapability.refuse(R_WALK_COMPLETE, {"office": office})
	var periods := InstitutionCapability.count(ctx.get("periods", 0), 0)
	if periods < 1:
		return InstitutionCapability.refuse(InstitutionCapability.R_NO_PERIODS)
	var waited := mini(periods, MAX_WAIT_PERIODS)
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"office": office,
					"held_periods": int(stood["held_periods"]) + waited,
					"waited": waited,
				},
			}
		)
	)


## ## Take ONE authored stage of the walk on `office`, or refuse it.
##
## `{ok: true, reason: "", plan: {member, office, stage, side, complete,
## held_periods, spent, cause}}`. This is the whole verb, and it is deliberately
## a plan built from three reads rather than a loop: count where the walk is,
## refuse if it is done or not due, otherwise add one and SPEND the clock.
##
## Refusal order: office named, a walk open, a walk authored, not complete,
## the period elapsed. Every refusal returns above the plan, so a refused step
## writes nothing (ADR 0044) — and because the plan carries the spent clock,
## applying it and immediately stepping again refuses `period_not_elapsed`,
## which is the property the suite measures.
func advance(ctx: Dictionary) -> Dictionary:
	var office := InstitutionCapability.text(ctx.get("office", ""), "")
	if office == "":
		return InstitutionCapability.refuse(R_NO_OFFICE)
	if not InstitutionCapability.flag(ctx.get("open", false)):
		return InstitutionCapability.refuse(R_NO_SUCH_WALK, {"office": office})
	var stood := walk(ctx)
	if not bool(stood.get("ok", false)):
		return stood
	var length := int(stood["length"])
	if length < 1:
		return InstitutionCapability.refuse(R_NO_WALK_AUTHORED, {"office": office})
	if bool(stood["complete"]):
		return InstitutionCapability.refuse(R_WALK_COMPLETE, {"office": office})
	var cost := maxi(0, _count(ctx.get("stage_periods", 0)))
	var held := int(stood["held_periods"])
	if held < cost:
		return InstitutionCapability.refuse(
			R_PERIOD_NOT_ELAPSED, {"held_periods": held, "stage_periods": cost}
		)
	var stage := int(stood["stage"]) + 1
	var complete := stage >= length
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"member": InstitutionCapability.text(ctx.get("member", ""), ""),
					"office": office,
					"stage": stage,
					"side": String(SEATED if complete else VACANT),
					"complete": complete,
					"held_periods": held - cost,
					"spent": cost,
					"cause": "succession_advanced",
				},
			}
		)
	)


## ## The authored data this capability reads cannot be READ.
##
## A `walk_length` that arrived as text would read as `0`, which is
## indistinguishable from an office that authors no walk at all. `check` vets
## what is PRESENT; an absent key is the per-verb refusals' business.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["stage", "walk_length", "stage_periods", "held_periods"]:
		if ctx.has(field) and not (ctx[field] is int or ctx[field] is float):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: two identical calls
## answer by TEXT (determinism — no roll can be hiding in the verb), a step
## SPENDS the clock so an immediate second step refuses `period_not_elapsed`,
## a walk whose every stage has landed refuses `walk_complete`, an unwalked
## office refuses `no_walk_authored`, and the walk's side flips to seated only
## on the last stage.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"member": "probe_member",
		"office": "probe_seat",
		"open": true,
		"stage": 0,
		"walk_length": 3,
		"stage_periods": 5,
		"held_periods": 5,
		"periods": 4,
	}
	var first := advance(probe.duplicate(true))
	var second := advance(probe.duplicate(true))
	if JSON.stringify(first) != JSON.stringify(second):
		found.append("advance: two identical calls disagreed — the walk is not deterministic")
	_judge(found, "advance", first)
	if bool(first.get("ok", false)):
		var plan = first.get("plan", {})
		if not (plan is Dictionary):
			found.append("advance: a successful plan is not a dictionary")
		else:
			var row := plan as Dictionary
			if int(row.get("stage", 0)) != int(probe["stage"]) + 1:
				found.append("advance: one call did not take exactly one stage")
			if (
				int(row.get("held_periods", -1))
				!= int(probe["held_periods"]) - int(probe["stage_periods"])
			):
				found.append("advance: the step did not spend the authored stage_periods")
			if bool(row.get("complete", true)):
				found.append("advance: a walk of three stages is complete after the first")
	# Apply the plan and step again: the clock was SPENT, so the next stage is
	# not due. This is ADR 0084's "refuses a further step until a period
	# elapses", measured rather than documented.
	var after := probe.duplicate(true)
	var applied = first.get("plan", {})
	if applied is Dictionary:
		after["stage"] = int((applied as Dictionary).get("stage", 0))
		after["held_periods"] = int((applied as Dictionary).get("held_periods", 0))
	expect_refusal(found, "advance", advance(after), R_PERIOD_NOT_ELAPSED)
	var due := probe.duplicate(true)
	due["stage"] = due["walk_length"]
	expect_refusal(found, "advance", advance(due), R_WALK_COMPLETE)
	# `wait` on a finished walk refuses too: there is nothing left to wait FOR,
	# and an accrual that fed a number no reader consults is the settlement
	# that moved nothing.
	expect_refusal(found, "wait", wait(due), R_WALK_COMPLETE)
	var waited := wait(probe.duplicate(true))
	_judge(found, "wait", waited)
	if bool(waited.get("ok", false)):
		var plan = waited.get("plan", {})
		if plan is Dictionary:
			if (
				int((plan as Dictionary).get("waited", -1))
				!= mini(int(probe["periods"]), MAX_WAIT_PERIODS)
			):
				found.append("wait: the accrual was not clamped to MAX_WAIT_PERIODS")
	var opened := open(probe.duplicate(true))
	if not opened.is_empty() and String(opened.get("reason", "")) != R_ALREADY_OPEN:
		found.append("open: an open walk should refuse `already_open`")
	var fresh := probe.duplicate(true)
	fresh["open"] = false
	_judge(found, "open", open(fresh))
	var unwalked := probe.duplicate(true)
	unwalked["walk_length"] = 0
	expect_refusal(found, "advance", advance(unwalked), R_NO_WALK_AUTHORED)
	var closed := probe.duplicate(true)
	closed["open"] = false
	expect_refusal(found, "advance", advance(closed), R_NO_SUCH_WALK)
	var last := probe.duplicate(true)
	last["stage"] = 2
	var landed := advance(last)
	_judge(found, "advance", landed)
	if bool(landed.get("ok", false)):
		var plan = landed.get("plan", {})
		if plan is Dictionary:
			if not bool((plan as Dictionary).get("complete", false)):
				found.append("advance: the last stage did not complete the walk")
			if String((plan as Dictionary).get("side", "")) != String(SEATED):
				found.append("advance: the completing stage did not seat the walk")
	return found


# --- Internals ---------------------------------------------------------------


## `value` as a non-negative clamped stage count, `0` otherwise. Clamped against
## [constant MAX_WALK_LENGTH] before anything reads it: a corrupt save holding a
## million talks the walk into nothing rather than into a very long one, and
## there is no loop here for it to grow.
func _clamped(value: Variant) -> int:
	return clampi(_count(value), 0, MAX_WALK_LENGTH)


## `value` as a non-negative integer count, `0` otherwise. A raw `int()` on a
## string RAISES in GDScript, so a hand-edited context would abort a verb
## instead of reading as absent — an explicit type test that falls back is
## refusal, not coincidence.
func _count(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	return maxi(0, int(value))
