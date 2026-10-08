class_name Schismatic
extends InstitutionCapability

## **A schism costs BOTH halves** (ADR 0085, ADR 0922). A free schism is a
## strictly-positive action, so every crisis would end in a split and no
## institution would ever have to answer for one. That is why this is its own
## capability rather than a branch inside a promotion or a leave verb: the
## price is the only thing standing between a disagreement and an amputation,
## and a declaration is a POLITICAL ACT with a price, never an administrative
## correction.
##
## ## The three numbers, and the property that makes them right
##
## 1. **The undivided standing is divided.** `half = undivided / 2`, floor. The
##    one point an odd undivided value leaves over is **charged away, never
##    minted**: `half * 2 + odd_charged == undivided` is a property of the
##    shape, so two halves can never sum back to more than they started with —
##    a grant wearing a split's clothes.
## 2. **Each half pays the SAME price.** One `price` is computed here and
##    published ONCE; [method declare]'s plan carries a single `settled` number,
##    so there is no second number a caller could write to one half and not the
##    other. Symmetric by construction, not by convention.
## 3. **Neither half is cheaper.** The suite asserts the two halves in the plan
##    are distinct and that `settled` is one value — a design that gave each
##    half its own subtraction would be two places to drift, and the whole rule
##    is that no half pays less.
##
## ## The clamp is the cost being real, and it is NEVER a refusal
##
## A half whose price exceeds its inheritance settles at zero and the plan
## publishes the `shortfall` — the split still happens. A schism nobody can
## afford to make is not a game rule, it is a missing verb, and the shortfall is
## what lets a panel say "this split will cost you everything you have" before
## it happens. The ONE price gate this verb keeps is `no_price`: a declaration
## that charges nothing AT ALL is the free-schism defect itself, because every
## crisis would then end in a split.
##
## ## What was REJECTED
##
## - **Refusing an unaffordable split.** `SectSchism` settled this: a cost that
##   can only refuse is a missing verb, and refusal would make a doomed house
##   inescapable — the opposite of "a player with no exit is in a bad state
##   with no out".
## - **A per-half price argument.** One price, one place it is computed, so an
##   asymmetry cannot be authored by accident. Per-place charges ride on top of
##   that ONE number rather than replacing it.
## - **Counting unassigned places from the argument.** The bill is counted
##   against the AUTHORED place list (`places`), never against `assigned`: a
##   caller cannot shrink the charge by handing in a short assignment list, and
##   a place the institution never claimed is not a place a split can leave
##   unassigned. This is `SectSchism.unassigned`'s rule, carried forward.
## - **Moving ground.** This capability assigns NO territory and moves none (ADR
##   0085: a claim never moves ground): it decides WHO EXISTS and WHAT EACH
##   HALF OWES IN RECOGNITION, and the per-place charge is the only thing
##   places touch.
##
## ## Context keys this capability reads
##
##   - `institution` — the undivided organization id (`String`).
##   - `seceding` — the id of the half walking away (`String`). A named half:
##     an unnamed one cannot be refused by name, and a split is a declaration
##     of sides.
##   - `member` — the declaring member's id (`String`), recorded on the plan.
##   - `undivided` — int: the standing before the split.
##   - `price` — int: the declared base cost, charged to EACH half.
##   - `places` — the authored place ids this organization claims (`Array`).
##   - `assigned` — the place ids the declaration assigns (`Array`). Read only
##     to compute what was LEFT unassigned, never to shrink the authored list.
##   - `cost_per_unassigned` — int: the charge per unassigned place, to each
##     half.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111), and no
## `rng`: a split whose price rolled would be a gate that can satisfy itself.

## The id this capability is dispatched under.
const ID := &"schismatic"

## The word a declared split is recorded under. Carried verbatim into whatever
## reads the declaration; a reader decides for itself whether `schism` is
## hostile, and this capability never asks anybody to agree.
const VERB := "schism"

## No seceding half was named. A split is a declaration of sides, so a side
## that cannot be named cannot be refused by name either.
const R_NO_SECEDING_HALF := "no_seceding_half"
## The undivided organization named itself as the half walking away. A failure
## mode rather than a split: the arithmetic would create two rows for one id.
const R_CANNOT_SECEDE_FROM_ITSELF := "cannot_secede_from_itself"
## There is no undivided standing to divide: one point, or none. Splitting it
## would produce two halves of zero and charge both of them for the privilege,
## which is the worst possible trade and a refusal rather than a formality.
const R_NOTHING_TO_SPLIT := "nothing_to_split"
## The declaration charges nothing at all — no base price and no unassigned
## places. **This is the free-schism defect itself**: a strictly-positive action
## every crisis would end in. ADR 0085's rule as a gate, not a sentence.
const R_NO_PRICE := "no_price"
## The authored place lists cannot be read. A corrupt list would silently
## change the bill — reading as "nothing unassigned" — so it is refused by name
## rather than absorbed.
const R_MALFORMED_PLACES := "malformed_places"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [
		R_NO_SECEDING_HALF,
		R_CANNOT_SECEDE_FROM_ITSELF,
		R_NOTHING_TO_SPLIT,
		R_NO_PRICE,
		R_MALFORMED_PLACES,
	]
	return out


## ## The whole arithmetic, as one dictionary, so a caller and a test read the
## ## same numbers rather than each re-deriving the sum.
##
## `{ok, reason, undivided, half, odd_charged, price, settled, shortfall,
## unassigned, kept, seceded}` — where `kept` and `seceded` are the SAME
## `settled` number published twice under the two halves' names, because they
## are one number by construction. `shortfall` is how much of the price a half
## could not cover, clamped at zero rather than driven below.
##
## **A read, not a gate**: it answers with what is authored even when the
## authored numbers break a rule (an undivided of 1, a price of 0), because a
## caller showing the price before a press must be able to render the numbers.
## [method declare] is where the gates refuse.
##
## A corrupt place list refuses `malformed_places` rather than reading as
## "nothing unassigned": the bill is a number a player pays, and guessing it
## downward is the one direction that would make a split cheaper by accident.
func settle(ctx: Dictionary) -> Dictionary:
	var undivided = ctx.get("undivided", null)
	var price = ctx.get("price", null)
	if not (undivided is int or undivided is float) or not (price is int or price is float):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "undivided/price"}
		)
	var places = ctx.get("places", [])
	var assigned = ctx.get("assigned", [])
	if not (places is Array) or not (assigned is Array):
		return InstitutionCapability.refuse(R_MALFORMED_PLACES)
	var unassigned := _unassigned(places as Array, assigned as Array)
	var per_place := InstitutionCapability.count(ctx.get("cost_per_unassigned", 0), 0)
	var before := maxi(0, int(undivided))
	var charged := maxi(0, int(price)) + maxi(0, per_place) * unassigned
	var half := int(floor(float(before) / 2.0))
	var settled := maxi(0, half - charged)
	return (
		InstitutionCapability
		. ok(
			{
				"undivided": before,
				"half": half,
				"odd_charged": before - half * 2,
				"price": charged,
				"unassigned": unassigned,
				"settled": settled,
				"shortfall": maxi(0, charged - half),
				"kept": settled,
				"seceded": settled,
			}
		)
	)


## ## Plan a declaration of schism, or refuse it.
##
## `{ok: true, reason: "", plan: {institution, seceding, member, halves, price,
## settled, odd_charged, unassigned, cause, verb}}` — where `halves` names the
## two ids and `settled` is the ONE number both of them start from. The applier
## writes `settled` to each half and charges each the same `price`; this
## contract commits nothing, and a refusal returns above the plan (ADR 0044).
##
## Refusal order: a seceding half named, not the undivided itself, standing to
## divide, a price that is really a price. `no_price` is the ONE gate on the
## number: a declaration that charges nothing at all is the free-schism defect,
## while a declaration whose price EXCEEDS a half's inheritance still plans —
## settling at zero with the shortfall published, never refused.
func declare(ctx: Dictionary) -> Dictionary:
	var undivided_id := InstitutionCapability.text(ctx.get("institution", ""), "")
	if undivided_id == "":
		return InstitutionCapability.refuse(InstitutionCapability.R_UNKNOWN_INSTITUTION)
	var seceding := InstitutionCapability.text(ctx.get("seceding", ""), "")
	if seceding == "":
		return InstitutionCapability.refuse(R_NO_SECEDING_HALF)
	if seceding == undivided_id:
		return InstitutionCapability.refuse(R_CANNOT_SECEDE_FROM_ITSELF)
	var priced := settle(ctx)
	if not bool(priced.get("ok", false)):
		return priced
	var fault := _declaration_fault(priced)
	if not fault.is_empty():
		return fault
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"institution": undivided_id,
					"seceding": seceding,
					"member": InstitutionCapability.text(ctx.get("member", ""), ""),
					"halves": [undivided_id, seceding],
					"price": int(priced["price"]),
					"settled": int(priced["settled"]),
					"odd_charged": int(priced["odd_charged"]),
					"unassigned": int(priced["unassigned"]),
					"shortfall": int(priced["shortfall"]),
					"verb": VERB,
					"cause": VERB,
				},
			}
		)
	)


## The two gates on the NUMBER a declaration charges: there is standing to
## divide, and the declaration is really a price. Split out of [method declare]
## so the verb keeps its named refusals while staying inside gdlint's
## `max-returns`.
##
## `priced` is [method settle]'s own read, passed in rather than re-derived.
## `no_price` is deliberately the ONLY gate on the number: a declaration whose
## price EXCEEDS a half's inheritance still declares — settling at zero with the
## shortfall published — because a schism nobody can afford is a missing verb,
## not a rule.
func _declaration_fault(priced: Dictionary) -> Dictionary:
	if int(priced["undivided"]) < 2:
		return InstitutionCapability.refuse(
			R_NOTHING_TO_SPLIT, {"undivided": int(priced["undivided"])}
		)
	if int(priced["price"]) <= 0:
		return InstitutionCapability.refuse(R_NO_PRICE)
	return {}


## ## The authored data this capability reads cannot be READ.
##
## A place list that arrived as a string would make the bill read as "nothing
## unassigned", which is the one direction that makes a split cheaper. `check`
## vets what is PRESENT; an absent key is the per-verb refusals' business.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["places", "assigned"]:
		if ctx.has(field) and not _is_id_list(ctx[field]):
			return InstitutionCapability.refuse(R_MALFORMED_PLACES, {"field": field})
	for field in ["undivided", "price", "cost_per_unassigned"]:
		if ctx.has(field) and not (ctx[field] is int or ctx[field] is float):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: the odd point is
## CHARGED and never minted (`half * 2 + odd_charged == undivided`), both halves
## start from ONE `settled` number (`kept == seceded`, asserted as a comparison
## between the published pair), the bill cannot be shrunk by handing in a short
## assignment list, a ruinous price still PLANS and publishes its shortfall,
## and a declaration charging nothing at all is refused by name.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "probe_house",
		"seceding": "probe_split",
		"member": "probe_member",
		"undivided": 41,
		"price": 5,
		"places": ["probe_meadow", "probe_harbour"],
		"assigned": ["probe_meadow"],
		"cost_per_unassigned": 2,
	}
	var settled := settle(probe.duplicate(true))
	_judge(found, "settle", settled)
	if bool(settled.get("ok", false)):
		var half := int(settled["half"])
		if half * 2 + int(settled["odd_charged"]) != int(settled["undivided"]):
			found.append("settle: the odd point was minted or lost rather than charged away")
		if int(settled["kept"]) != int(settled["seceded"]):
			found.append("settle: the two halves settled on different numbers")
		if int(settled["unassigned"]) != 1:
			found.append("settle: the unassigned count does not match the authored places")
		if int(settled["price"]) != int(probe["price"]) + int(probe["cost_per_unassigned"]):
			found.append("settle: the price did not include the per-unassigned charge")
	var planned := declare(probe.duplicate(true))
	_judge(found, "declare", planned)
	if bool(planned.get("ok", false)):
		var plan = planned.get("plan", {})
		if not (plan is Dictionary):
			found.append("declare: a successful plan is not a dictionary")
		else:
			var row := plan as Dictionary
			var halves = row.get("halves", [])
			if not (halves is Array) or (halves as Array).size() != 2:
				found.append("declare: the plan does not name exactly two halves")
			elif String((halves as Array)[0]) == String((halves as Array)[1]):
				found.append("declare: the plan names one half twice")
			if int(row.get("settled", -1)) != int(settled["settled"]):
				found.append("declare: the plan's settled differs from the read's")
	# A short assignment list cannot shrink the bill: the charge is counted
	# against the AUTHORED places.
	var short_list := probe.duplicate(true)
	short_list["assigned"] = []
	var full_bill := settle(short_list)
	_judge(found, "settle", full_bill)
	if bool(full_bill.get("ok", false)):
		if int(full_bill["unassigned"]) != (short_list["places"] as Array).size():
			found.append("settle: an empty assignment list did not bill every authored place")
		if int(full_bill["price"]) <= int(settled["price"]):
			found.append("settle: handing in a short list did not change the bill")
	# A ruinous price still PLANS: the clamp and the shortfall are the cost being
	# real, and a refusal here would make a doomed house inescapable.
	var ruinous := probe.duplicate(true)
	ruinous["price"] = 1000
	var doomed := declare(ruinous)
	_judge(found, "declare", doomed)
	if bool(doomed.get("ok", false)):
		var plan = doomed.get("plan", {})
		if plan is Dictionary:
			if int((plan as Dictionary).get("settled", -1)) != 0:
				found.append("declare: an over-priced half did not settle at zero")
			if int((plan as Dictionary).get("shortfall", 0)) <= 0:
				found.append("declare: an over-priced half published no shortfall")
	var free := probe.duplicate(true)
	free["price"] = 0
	free["cost_per_unassigned"] = 0
	expect_refusal(found, "declare", declare(free), R_NO_PRICE)
	var lonely := probe.duplicate(true)
	lonely["undivided"] = 1
	expect_refusal(found, "declare", declare(lonely), R_NOTHING_TO_SPLIT)
	var itself := probe.duplicate(true)
	itself["seceding"] = itself["institution"]
	expect_refusal(found, "declare", declare(itself), R_CANNOT_SECEDE_FROM_ITSELF)
	return found


# --- Internals ---------------------------------------------------------------


## How many of the authored `places` the declaration left UNASSIGNED.
##
## Counted against the AUTHORED list rather than against the argument, so the
## caller cannot shrink the bill by handing in a short list, and a place the
## institution never claimed is not a place a split can abandon. An entry in
## `assigned` that is not in `places` is ignored on both sides. The walk is a
## `for` over the authored snapshot, writing nothing into it: the bound is the
## content's own length.
func _unassigned(places: Array, assigned: Array) -> int:
	var count := 0
	for place in places:
		if place is not String and place is not StringName:
			continue
		if not _assigned_to(assigned, String(place)):
			count += 1
	return count


## Whether `assigned` names `place`, matched by TEXT for the reason
## `InstitutionProjection.recognises` documents: an authored array may hold
## `StringName`s while a context built from a save holds plain `String`s, and
## `Array.has()` is type-strict.
func _assigned_to(assigned: Array, place: String) -> bool:
	for entry in assigned:
		if (entry is String or entry is StringName) and String(entry) == place:
			return true
	return false


## Whether `value` really is a list of ids. An empty array IS one: an
## organization that claims no place authors a bill of zero.
func _is_id_list(value: Variant) -> bool:
	if not (value is Array):
		return false
	for entry in value as Array:
		if not (entry is String or entry is StringName):
			return false
	return true
