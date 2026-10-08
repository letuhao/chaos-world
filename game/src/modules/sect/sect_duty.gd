class_name SectDuty
extends RefCounted

## The obligation ledger's two transitions: what a seat OPENS, and what serving
## DISCHARGES (ADR 0083, ADR 0084).
##
## ## Why this is a component and not a `SectApi` method
##
## A facade many units import is a god object however many verbs it publishes
## (`rules.MAX_FACADE_FAN_IN`), so the surface stays the published join-and-read
## verbs and `test_sect_no_power.gd` pins the exact list. ADR 0084's own answer
## to "this facade has no room" is `SectAct`: the decision lives beside
## `SectSuccession` and `SectTeaching`, reached by name rather than by a new
## method. So does this, and `SectDuty.serve(actor, periods)` is the whole of
## the surface.
##
## ## The live balance bug this closes
##
## `InstitutionClaim.owe` and `.settle` had ZERO production callers. Lines opened at
## `join` and at `found` and nothing ever paid one down, so `summary()["settled"]` was
## permanently false for every member in the game and every `SectGate` `duty_owed` gate
## was a door that could never be described as anything but shut. Debt that cannot be
## discharged is not a gate; it is a decoration.
##
## ## No clock, ever
##
## `periods` is handed in by the caller that owns time (DEF-0111). Nothing here reads
## `Time`, declares `_process` or calls `get_tree()`.
##
## ## A discharge is a line brought to ZERO
##
## `oaths_discharged` counts TERMS discharged in full, not periods spent. A term owed
## three periods and paid three at once is one oath discharged, and a term paid one
## period at a time over three calls is one oath discharged on the third. So the ledger
## is written on the crossing and never before, which is what makes the fact
## once-per-occurrence rather than per-frame or per-read.

## Nothing was owed, so nothing was discharged. A refusal like any other: it writes
## nothing at all, and the claim is byte-for-byte as found (ADR 0084).
const R_NOTHING_OWED := "nothing_owed"
## The caller asked for no periods. `periods` of zero or less is a caller mistake
## rather than a settlement, and a settlement that moved nothing would be indistinguishable
## from one that never ran.
const R_NO_PERIODS := "no_periods"
## Aliased from the facade so the vocabulary this module refuses with has exactly one
## home. A refusal reason spelled twice is a reason a panel eventually renders wrong.
const R_NO_ACTOR := SectApi.NO_ACTOR
const R_NOT_A_MEMBER := SectApi.NOT_A_MEMBER


## `lines` with `office`'s own obligation lines opened, and every other line left
## exactly as the caller had it.
##
## **Max, never sum.** A line the member already owes more of is left alone: an office
## raises what a seat obliges a member to, it does not charge the arrears of the same
## seat a second time. This is the merge `InstitutionFounding._obligation` already uses
## for a founder's own duty, and it lives here so the founding path and the promotion
## path cannot disagree about what a seat costs.
##
## ## The lines of an office the member no longer holds are NOT closed
##
## Vacating a seat does not discharge what the seat owed. The line stays owed and is
## paid down by [method serve] like any other, because "you are no longer standing
## there" and "you did the work" are two different facts — and a member who could buy
## their way out of a duty by being demoted has been given a cheaper exit than honour.
static func open_office(lines: Dictionary, office: SectPositionDef) -> Dictionary:
	var out := lines.duplicate()
	if office == null:
		return out
	var office_lines := office.obligation_lines()
	for term_id in office_lines.keys():
		var key := String(term_id)
		out[key] = maxi(int(out.get(key, 0)), int(office_lines[term_id]))
	return out


## Serve the institution for `periods` periods: pay `periods` down on EVERY open line,
## and record one oath per line that reached zero.
##
## Every line is paid the same `periods`, because a member's service is one act and
## splitting it across lines by hand would be a caller inventing a schedule the ledger has
## no opinion about.
##
## ## A payment that clears no term is still a payment
##
## `serve` succeeds whenever it settled a period at all; `oaths_discharged` records only
## on a CROSSING. A term of three periods paid one at a time is three services and ONE
## oath, and refusing the first two because no term happened to end would make a long
## term impossible to pay down at all — the one state where a member is owed patience and
## the module answers with a refusal. So `paid` and `discharged` are separate numbers on
## the report and only the second one reaches the world.
##
## Returns `{ok, reason, paid, discharged, owed, settled}`: `paid` is how many periods
## this call actually settled, `discharged` is how many TERMS it brought to zero, and
## `settled` is the claim's own answer, read through `InstitutionClaim` rather than
## restated here.
static func serve(actor: Actor, periods: int = 1) -> Dictionary:
	if actor == null:
		return _report(false, R_NO_ACTOR, 0, 0, 0, true)
	if periods < 1:
		return _report(false, R_NO_PERIODS, 0, 0, 0, false)
	var ledger := SectState.normalize(actor.get_module_data(SectState.MODULE_KEY))
	if not SectState.is_affiliated(ledger):
		return _report(false, R_NOT_A_MEMBER, 0, 0, 0, true)
	var claim := SectState.claim(ledger)
	if claim.settled():
		return _report(false, R_NOTHING_OWED, 0, 0, 0, true)
	# The keys are SNAPSHOT before the walk. `settle` lowers a line in place and never
	# erases one, so the count is stable either way — but a bound read off the very
	# container the body mutates is the shape `test_no_unbounded_wait.gd` exists to
	# refuse, and the snapshot costs one line.
	var terms := claim.obligation.keys()
	var paid := 0
	var discharged := 0
	for term_id in terms:
		var term := StringName(term_id)
		if claim.owed(term) <= 0:
			continue
		paid += claim.settle(term, periods)
		# The crossing, read AFTER the settle: a line of three paid with one is still
		# owed and records nothing, and the same line paid with three records exactly
		# once. Reading it before would record a payment that did not clear the term.
		if claim.owed(term) <= 0:
			discharged += 1
	if paid <= 0:
		return _report(false, R_NOTHING_OWED, 0, 0, _still_owed(claim), false)
	SectApi._write_claim(ledger, claim)
	SectApi._record(ledger, "served", &"", "%d periods, %d terms" % [paid, discharged])
	SectApi._persist(actor, ledger, "served")
	# LAST, once the settlement it describes has actually landed — the same order
	# `app/CharacterCreationFlow` records `character_created` in. A fact that claims a
	# discharge the ledger does not carry is the ADR 0066 shape. Guarded by the crossing
	# count rather than left to the writer to refuse: a payment that cleared no term owes
	# the world no oath.
	if discharged > 0:
		SectFacts.record_oaths_discharged(actor, discharged)
	return _report(true, "", paid, discharged, _still_owed(claim), claim.settled())


## Every period still owed across every open line, as one number. A read rather than a
## second dictionary walk by every caller, so `serve`'s report and `SectGate`'s
## `duty_owed` cannot drift into answering different questions.
static func still_owed(claim: InstitutionClaim) -> int:
	if claim == null:
		return 0
	var total := 0
	for term_id in claim.obligation.keys():
		total += maxi(0, int(claim.obligation[term_id]))
	return total


## One shape on both paths, so a caller reads `paid` and `discharged` without asking
## which one it holds. `settled` is `true` on the two refusals where nothing could
## possibly be owed — a null actor and a member sworn to nothing — because an
## unaffiliated member has no lines at all, and reporting that as "still in debt" would
## be a lie about a person who owes nothing to anybody.
static func _report(
	ok: bool, reason: String, paid: int, discharged: int, owed: int, settled: bool
) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"paid": paid,
		"discharged": discharged,
		"owed": owed,
		"settled": settled,
	}


static func _still_owed(claim: InstitutionClaim) -> int:
	return still_owed(claim)
