class_name Teachable
extends InstitutionCapability

## Transmission: how a doctrine gets from one member to another, as a CONTRACT
## rather than as sect code (ADR 0084, ADR 0922). The generalization of
## `SectTeaching`, and the reason it can be one: every number this capability
## reads was already primitives — a fit against a floor, a sworn student, a
## comprehension span — and none of it was ever sect-shaped.
##
## ## Fit is a GATE projecting ZERO stat modifiers
##
## Fit is transmission, one of the three things an institution grants alongside
## recognition and access (ADR 0084), and it is the one that moves NO stat:
## [method lesson] returns a PLAN of fit points and nothing else. The probes in
## [method contract_findings] assert that the plan carries no modifier-shaped
## key, which is the strongest check a layer that cannot name a stat sheet can
## make — the behavioral half (a live actor's modifier stack does not move) is
## asserted in `tests/contracts/test_institution_capabilities.gd`, on a real
## `Actor`, because `contracts/` may not name one.
##
## ## A kind without this capability has NO fit axis, not `fit: 0`
##
## `InstitutionRegistry.CAP_TEACHES` is the declaration, and
## `InstitutionFounding.write` already refuses to write the key at all for a
## kind that lacks it. This capability is what a kind that HAS it consults; a
## kind that does not has nothing here to override, and the absent key is a
## shape rather than a default (ADR 0084's `fit: 0` case). `InstitutionContract.of`
## answers `{ok: true, has: false}` for it — a legitimate state, never an error.
##
## ## What was REJECTED
##
## - **Rolling a lesson.** A lesson that might not land is a gate that can
##   satisfy itself, the same reason ADR 0084 walks a succession instead of
##   rolling one. [method lesson] is pure arithmetic: `fit_per_period * periods`.
## - **Reading `derived` comprehension.** The span is read from BASE allocation
##   only, exactly as `SectDoctrineDef` pins it: a technique can never satisfy
##   its own requirement with the stats it grants (ADR 0052/0054), and the
##   recognition this family projects is precisely such a grant — reading
##   `derived` would let the institution's own percent fund the gate that
##   measures whether the institution may teach.
## - **Granting a modifier from fit.** Fit is a currency of GATES: spending it
##   on a stat would make "so far above the bar" a purchase, and comprehension is
##   the one thing this repo says cannot be bought.
## - **Teaching the unsworn.** Transmission begins at membership; a student who
##   is not sworn is refused by name rather than silently admitted, because the
##   membership is the door `InstitutionMembership.join` already owns.
##
## ## Context keys this capability reads
##
##   - `member` — the teacher's id (`String`), and the subject of the plan.
##   - `target` — the student's id (`String`). Distinct from `member`: a lesson
##     is the one member-scoped verb here that acts ON somebody else.
##   - `doctrine` — the doctrine id being transmitted (`String`).
##   - `teacher_fit`, `doctrine_floor` — ints: the teacher's fit in this
##     doctrine and the floor below which it cannot be taught at all.
##   - `fit_per_period` — int: what one session is worth, a pure rate.
##   - `student_sworn` — `bool`: whether the student holds a claim in this
##     organization.
##   - `comprehension`, `comprehension_floor`, `comprehension_span` — numbers:
##     the student's BASE allocation and the authored band. The band's upper edge
##     is inclusive, so an author writes down the number they meant.
##   - `periods` — int: how many sessions one call teaches. Bounded by the
##     CALLER, never by a loop here; a value below 1 refuses `no_periods`.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111). Every accrual
## takes an explicit `periods` from a caller that owns time.

## The id this capability is dispatched under.
const ID := &"teachable"

## No doctrine was named: transmission names what it transmits, and a lesson
## with no subject is an incomplete request rather than a policy answer.
const R_NO_DOCTRINE := "no_doctrine"
## No student was named. Distinct from the family's `no_actor`, which names the
## TEACHER: this one names the absent other half of the pair.
const R_NO_STUDENT := "no_student"
## The member named themselves as the student. A lesson is transmission to
## ANOTHER member; teaching yourself is a different act (practice) with
## different costs, so it is refused by name rather than quietly admitted.
const R_SAME_ACTOR := "same_actor"
## The teacher's fit sits below the doctrine's authored floor, so this member
## cannot transmit this doctrine at all. A gate read off the ledger, never off
## a derived stat.
const R_TEACHER_UNFIT := "teacher_unfit"
## The student holds no claim in this organization. Transmission is a per-member
## act, and the unsworn have not been admitted by the layer that owns admission.
const R_STUDENT_NOT_SWORN := "student_not_sworn"
## The student's BASE comprehension sits below the authored floor: this doctrine
## is practised at a level they have not reached.
const R_COMPREHENSION_BELOW_FLOOR := "comprehension_below_floor"
## The student's BASE comprehension sits above the band's upper edge. Refused
## by a named reason rather than absorbed: a band an author wrote down has two
## edges, and a student past the top is a content question for that author.
const R_COMPREHENSION_ABOVE_SPAN := "comprehension_above_span"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [
		R_NO_DOCTRINE,
		R_NO_STUDENT,
		R_SAME_ACTOR,
		R_TEACHER_UNFIT,
		R_STUDENT_NOT_SWORN,
		R_COMPREHENSION_BELOW_FLOOR,
		R_COMPREHENSION_ABOVE_SPAN,
	]
	return out


## ## Whether this teacher fits this doctrine, as a READ.
##
## `{ok: true, reason: "", fit, floor, teaches}` — or `no_doctrine` when no
## doctrine was named, and `malformed` when the fit pair cannot be read. The
## read publishes the comparison as `teaches` so a caller about to show a lesson
## button renders WHY without re-deriving it, the same shape `Expellable.costs`
## publishes `asymmetric` in. [method lesson] is where the gate refuses; a read
## that refused on a low fit would make a screen unable to show the bar.
func fitness(ctx: Dictionary) -> Dictionary:
	var doctrine := InstitutionCapability.text(ctx.get("doctrine", ""), "")
	if doctrine == "":
		return InstitutionCapability.refuse(R_NO_DOCTRINE)
	var fit = ctx.get("teacher_fit", null)
	var floor = ctx.get("doctrine_floor", null)
	if not (fit is int or fit is float) or not (floor is int or floor is float):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "teacher_fit/doctrine_floor"}
		)
	var points := int(fit)
	var bar := int(floor)
	return (
		InstitutionCapability
		. ok(
			{
				"doctrine": doctrine,
				"fit": points,
				"floor": bar,
				"teaches": points >= bar,
			}
		)
	)


## ## Plan one call's transmission, or refuse it.
##
## `{ok: true, reason: "", plan: {teacher, student, doctrine, periods, fit_gain,
## cause}}` — where `plan` is primitives-only and `fit_gain` is
## `fit_per_period * periods`, a pure product and never a roll. The applier
## reads the plan and writes it into the student's ledger; this contract commits
## nothing (ADR 0044: a refusal writes nothing, and neither does a success —
## the plan IS the write instruction).
##
## Refusal order, every refusal above the plan: doctrine named, teacher named,
## student named, not self, teacher fits, student sworn, comprehension in band,
## periods positive.
##
## The checks are grouped into two helpers so each refusal keeps its own path
## while the verb stays inside gdlint's `max-returns`: [method _pair_fault]
## answers the naming rules and [method _qualification_fault] the bar the pair
## must clear. `{}` from either means that group passed.
func lesson(ctx: Dictionary) -> Dictionary:
	var pair := _pair_fault(ctx)
	if not pair.is_empty():
		return pair
	var priced := fitness(ctx)
	if not bool(priced.get("ok", false)):
		return priced
	var periods := InstitutionCapability.count(ctx.get("periods", 0), 0)
	var qualified := _qualification_fault(ctx, priced, periods)
	if not qualified.is_empty():
		return qualified
	var rate := InstitutionCapability.count(ctx.get("fit_per_period", 0), 0)
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"teacher": InstitutionCapability.text(ctx.get("member", ""), ""),
					"student": InstitutionCapability.text(ctx.get("target", ""), ""),
					"doctrine": InstitutionCapability.text(ctx.get("doctrine", ""), ""),
					"periods": periods,
					"fit_gain": maxi(0, rate) * periods,
					"cause": "taught",
				},
			}
		)
	)


## ## The authored data this capability reads cannot be READ.
##
## Numeric fields that arrived as text would make every gate answer `no` —
## indistinguishable from a kind that transmits nothing. `check` vets what is
## PRESENT and treats an absent key as the per-verb refusals' business, so the
## family's bare probe context passes and a corrupt one does not.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["teacher_fit", "doctrine_floor", "fit_per_period", "periods"]:
		if ctx.has(field) and not (ctx[field] is int or ctx[field] is float):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	for field in ["comprehension", "comprehension_floor", "comprehension_span"]:
		if ctx.has(field) and not (ctx[field] is int or ctx[field] is float):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	if ctx.has("student_sworn") and not (ctx["student_sworn"] is bool):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "student_sworn"}
		)
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: the fit comparison holds
## on a passing context (asserted as a COMPARISON, never two literals), a lesson
## yields exactly `fit_per_period * periods`, the plan carries no key that names
## a stat surface (fit projects zero modifiers), an unfit teacher is refused by
## name, and an unsworn student is refused by name — because a lesson that
## enrolled somebody would make admission a side effect of teaching.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"member": "probe_teacher",
		"target": "probe_student",
		"doctrine": "probe_doctrine",
		"teacher_fit": 9,
		"doctrine_floor": 3,
		"fit_per_period": 3,
		"student_sworn": true,
		"comprehension": 50.0,
		"comprehension_floor": 10.0,
		"comprehension_span": 80.0,
		"periods": 2,
	}
	var read := fitness(probe.duplicate(true))
	_judge(found, "fitness", read)
	if bool(read.get("ok", false)):
		if bool(read["teaches"]) != (int(read["fit"]) >= int(read["floor"])):
			found.append("fitness: `teaches` does not report the fit comparison it was handed")
	var planned := lesson(probe.duplicate(true))
	_judge(found, "lesson", planned)
	if bool(planned.get("ok", false)):
		var plan = planned.get("plan", {})
		if not (plan is Dictionary):
			found.append("lesson: a successful plan is not a dictionary")
		else:
			var row := plan as Dictionary
			if int(row.get("fit_gain", -1)) != int(probe["fit_per_period"]) * int(probe["periods"]):
				found.append("lesson: fit_gain is not fit_per_period * periods")
			for key in row.keys():
				if _names_a_stat_surface(String(key)):
					found.append(
						"lesson: the plan names a stat surface ('%s'); fit grants zero" % key
					)
	var unfit := probe.duplicate(true)
	unfit["teacher_fit"] = 0
	expect_refusal(found, "lesson", lesson(unfit), R_TEACHER_UNFIT)
	var stranger := probe.duplicate(true)
	stranger["student_sworn"] = false
	expect_refusal(found, "lesson", lesson(stranger), R_STUDENT_NOT_SWORN)
	var low := probe.duplicate(true)
	low["comprehension"] = 1.0
	expect_refusal(found, "lesson", lesson(low), R_COMPREHENSION_BELOW_FLOOR)
	var high := probe.duplicate(true)
	high["comprehension"] = 200.0
	expect_refusal(found, "lesson", lesson(high), R_COMPREHENSION_ABOVE_SPAN)
	return found


# --- Internals ---------------------------------------------------------------


## The naming fault in one lesson's context, or `{}` when the pair is named.
##
## Split out of [method lesson] so the verb keeps its refusal paths while
## staying inside gdlint's `max-returns`: doctrine named, teacher named, student
## named, not self — four checks, and every one of them is about WHO the lesson
## is between rather than about whether the pair qualifies.
func _pair_fault(ctx: Dictionary) -> Dictionary:
	if InstitutionCapability.text(ctx.get("doctrine", ""), "") == "":
		return InstitutionCapability.refuse(R_NO_DOCTRINE)
	var teacher := InstitutionCapability.text(ctx.get("member", ""), "")
	if teacher == "":
		return InstitutionCapability.refuse(InstitutionCapability.R_NO_ACTOR)
	var student := InstitutionCapability.text(ctx.get("target", ""), "")
	if student == "":
		return InstitutionCapability.refuse(R_NO_STUDENT)
	if student == teacher:
		return InstitutionCapability.refuse(R_SAME_ACTOR)
	return {}


## The bar a NAMED pair must clear, or `{}` when the lesson may proceed: teacher
## fits, student sworn, comprehension in band, periods positive.
##
## `priced` is [method fitness]'s own answer, passed in rather than re-derived,
## because the verb has already paid for it; `periods` is the count the verb
## read. Order is the documented one — a teacher under the floor is refused
## before anybody is asked whether the student is sworn.
func _qualification_fault(ctx: Dictionary, priced: Dictionary, periods: int) -> Dictionary:
	if not bool(priced["teaches"]):
		return (
			InstitutionCapability
			. refuse(
				R_TEACHER_UNFIT,
				{"fit": int(priced["fit"]), "floor": int(priced["floor"])},
			)
		)
	if not InstitutionCapability.flag(ctx.get("student_sworn", false)):
		return InstitutionCapability.refuse(R_STUDENT_NOT_SWORN)
	var band := _band(ctx)
	if band.get("refused", "") != "":
		return InstitutionCapability.refuse(String(band["refused"]))
	if periods < 1:
		return InstitutionCapability.refuse(InstitutionCapability.R_NO_PERIODS)
	return {}


## `{refused: <named reason>}` or `{floor, ceiling}` — the comprehension band a
## student must sit inside. ONE helper because the two faults and the two edges
## are one arithmetic rule, and a band read in two places is a band that can
## disagree about its own top; the upper edge is INCLUSIVE, so an author writes
## down the number they meant (the `SectDoctrineDef` rule).
func _band(ctx: Dictionary) -> Dictionary:
	var low = ctx.get("comprehension_floor", 0.0)
	var span = ctx.get("comprehension_span", 0.0)
	var points = ctx.get("comprehension", 0.0)
	if (
		not (low is int or low is float)
		or not (span is int or span is float)
		or not (points is int or points is float)
	):
		return {"refused": InstitutionCapability.R_MALFORMED}
	var floor := float(low)
	var ceiling := floor + maxf(0.0, float(span))
	if float(points) < floor:
		return {"refused": R_COMPREHENSION_BELOW_FLOOR}
	if float(points) > ceiling:
		return {"refused": R_COMPREHENSION_ABOVE_SPAN}
	return {"floor": floor, "ceiling": ceiling}


## Whether `key` names a stat surface a plan must never carry. A substring test
## rather than a list of exact names, so `insight_bonus` and `damage_modifier`
## are both caught — a plan this family builds is fit points and ids, and any
## word from a stat sheet is a grant wearing a plan's clothes.
func _names_a_stat_surface(key: String) -> bool:
	for marker in ["stat", "modifier", "percent", "bonus", "grant"]:
		if key.contains(marker):
			return true
	return false
