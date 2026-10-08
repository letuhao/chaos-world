class_name Expellable
extends InstitutionCapability

## Casting a member out — and what it COSTS the one doing the casting (ADR 0084,
## ADR 0922). The rule is not decoration: **an expulsion costs the expeller
## STRICTLY MORE than it costs the expelled**, which is what makes an inquisition
## a political act rather than an administrative one. A free expulsion is a
## strictly-positive action, so every disagreement would end in a purge and
## membership would mean nothing.
##
## ## The asymmetry is a GATE here, never a sentence in a docstring
##
## [method costs] publishes both sides as numbers; [method expel] REFUSES to
## produce a plan when `expeller <= expelled`, naming `cost_not_asymmetric` and
## carrying both numbers so a content author sees the fix. A kind cannot author
## a cheap purge and get one anyway — that is the whole reason this is a gate
## rather than a reading.
##
## ## Authority is a sibling contract, not a dependency this one requires
##
## A guild may implement expulsion without offices that author anything, and an
## office-holding kind may implement authority without expulsion. So this
## capability reads the SAME authored vocabulary — an `authorities` list on the
## context — and refuses `not_authorised` when the acting member's office does
## not author [constant Authorised.AUTHORITY_EXPEL]. Measured: the shipped
## trading guild's top seat authors exactly that word, and until this family
## shipped, nothing executed it.
##
## ## Context keys this capability reads
##
##   - `authorities` — the acting member's authored authority ids (`Array`).
##   - `member` — the acting member's id (`String`).
##   - `target` — the member being cast out (`String`).
##   - `target_member` — whether the target holds a claim (`bool`).
##   - `target_authorities` — the target's office authority ids (`Array`). Used
##     for the peer rule: you cannot purge your equals (below).
##   - `cost_expelled`, `cost_expeller` — the authored standing costs of the
##     act (`int`), one per side. This capability deliberately does NOT derive
##     them: where a kind authors its numbers is its own content question, and a
##     derived cost would be a second tuning surface inside a contract.
##   - `force` — `bool`, default false. Bypasses the peer rule ONLY, and is
##     recorded in the plan so a forced purge is legible afterwards. It NEVER
##     bypasses the authority check.
##
## ## The peer rule, without a rank
##
## "You cannot purge your equals" (ADR 0084) is expressed from AUTHORED DATA:
## if the target's office also carries the expel authority, the target is a
## peer and may only be cast out by an explicitly forced act. There is no
## comparison of offices and no index — the numeric hierarchy ADR 0064 kept out
## of the claim would be back the moment authority became `rank >= 3`.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111).

## The id this capability is dispatched under. `Authorised.AUTHORITY_EXPEL`
## is the authored word, owned THERE so a capability, an office's content and a
## plan cannot spell it three ways.
const ID := &"expellable"

## The acting member's office does not author the expel authority. The authored
## question answered "no", and it is a refusal rather than a plan.
const R_NOT_AUTHORISED := "not_authorised"
## No target was named: there is nobody to cast out, so the request is
## incomplete rather than declined.
const R_NO_TARGET := "no_target"
## The member named themselves. Self-removal is leaving, which is always
## permitted and is a different act with different costs — so it is refused here
## by name rather than quietly treated as a purge of one.
const R_CANNOT_EXPEL_SELF := "cannot_expel_self"
## The target holds no claim in this institution. Distinct from `no_target`:
## this one names somebody who is simply not a member.
const R_TARGET_NOT_A_MEMBER := "target_not_a_member"
## The target holds an office that itself carries the expel authority, so the
## target is the acting member's peer. Refused unless the act is FORCED, and the
## force is recorded.
const R_CANNOT_EXPEL_EQUAL_OR_ABOVE := "cannot_expel_equal_or_above"
## The authored costs are not asymmetric: the expeller does not pay strictly
## more than the expelled. ADR 0084's rule as content, refused with both
## numbers.
const R_COST_NOT_ASYMMETRIC := "cost_not_asymmetric"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [
		R_NOT_AUTHORISED,
		R_NO_TARGET,
		R_CANNOT_EXPEL_SELF,
		R_TARGET_NOT_A_MEMBER,
		R_CANNOT_EXPEL_EQUAL_OR_ABOVE,
		R_COST_NOT_ASYMMETRIC,
	]
	return out


## ## The authored costs, as a READ.
##
## `{ok: true, reason: "", expelled: n, expeller: m, asymmetric: m > n}` — or
## `malformed` when either side is not a number. `asymmetric` is published as a
## bool so a caller renders WHY an expulsion is refused without re-deriving the
## comparison, and [method expel] reads the same pair rather than comparing
## twice.
##
## **A read, not a gate**: it answers with what is authored even when the
## authored pair breaks the rule, because a caller showing a price before a
## press must be able to render the number. [method expel] is where the rule
## refuses.
func costs(ctx: Dictionary) -> Dictionary:
	var expired = ctx.get("cost_expelled", null)
	var expeller = ctx.get("cost_expeller", null)
	if not (expired is int or expired is float) or not (expeller is int or expeller is float):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "cost_expelled/cost_expeller"}
		)
	var expelled_cost := int(expired)
	var expeller_cost := int(expeller)
	return (
		InstitutionCapability
		. ok(
			{
				"expelled": expelled_cost,
				"expeller": expeller_cost,
				"asymmetric": expeller_cost > expelled_cost,
			}
		)
	)


## ## Plan the expulsion, or refuse it.
##
## `{ok: true, reason: "", plan: {member, target, office, forced, cost_expelled,
## cost_expeller, cause}}` — where `plan` is primitives-only and `office` is the
## target's office id (`""` for a member holding none). The applier reads the
## plan and writes it; this contract commits nothing (see the base class note).
##
## Refusal order, and every refusal returns above the plan, so a refused verb
## proposes nothing (ADR 0044): costs readable, asymmetric, authority held,
## target named, not self, a member, not a peer (unless forced).
##
## `cause` is the word a caller records for the act. Owned here so a history
## line, a regard cause and a plan cannot spell "expelled" three ways.
func expel(ctx: Dictionary) -> Dictionary:
	var priced := costs(ctx)
	if not bool(priced.get("ok", false)):
		return priced
	if not bool(priced["asymmetric"]):
		return (
			InstitutionCapability
			. refuse(
				R_COST_NOT_ASYMMETRIC,
				{"expelled": int(priced["expelled"]), "expeller": int(priced["expeller"])},
			)
		)
	if not _authors_expel(ctx.get("authorities", [])):
		return InstitutionCapability.refuse(R_NOT_AUTHORISED)
	var member := InstitutionCapability.text(ctx.get("member", ""), "")
	var target := InstitutionCapability.text(ctx.get("target", ""), "")
	if target == "":
		return InstitutionCapability.refuse(R_NO_TARGET)
	if target == member:
		return InstitutionCapability.refuse(R_CANNOT_EXPEL_SELF)
	if not InstitutionCapability.flag(ctx.get("target_member", false)):
		return InstitutionCapability.refuse(R_TARGET_NOT_A_MEMBER)
	var forced := InstitutionCapability.flag(ctx.get("force", false))
	if not forced and _authors_expel(ctx.get("target_authorities", [])):
		return InstitutionCapability.refuse(R_CANNOT_EXPEL_EQUAL_OR_ABOVE)
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"member": member,
					"target": target,
					"office": InstitutionCapability.text(ctx.get("target_office", ""), ""),
					"forced": forced,
					"cost_expelled": int(priced["expelled"]),
					"cost_expeller": int(priced["expeller"]),
					"cause": "expelled",
				},
			}
		)
	)


## ## The authored data this capability reads cannot be READ.
##
## A cost that arrived as a string, or an authority list that is not a list,
## would make every gate answer `no` — indistinguishable from a kind that
## grants nothing. `check` vets what is PRESENT and treats an absent key as the
## per-verb refusals' business, so a bare probe context passes and a corrupt one
## does not.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["authorities", "target_authorities"]:
		if ctx.has(field) and not (ctx[field] is Array):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	if (
		ctx.has("cost_expelled")
		and not (ctx["cost_expelled"] is int or ctx["cost_expelled"] is float)
	):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "cost_expelled"}
		)
	if (
		ctx.has("cost_expeller")
		and not (ctx["cost_expeller"] is int or ctx["cost_expeller"] is float)
	):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "cost_expeller"}
		)
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: the cost pair is
## ASYMMETRIC on a priced context (asserted as a comparison, never two
## literals), an equal-cost context is refused `cost_not_asymmetric`, an office
## without the authority is refused `not_authorised`, and a member is refused
## casting out themselves.
##
## **This method is the KIND's `check` too**: a kind whose content cannot price
## an expulsion fails here at registration rather than at the first purge.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"authorities": ["expel"],
		"member": "probe_member",
		"target": "probe_target",
		"target_member": true,
		"target_office": "probe_seat",
		"target_authorities": [],
		"cost_expelled": 3,
		"cost_expeller": 9,
	}
	var priced := costs(probe.duplicate(true))
	_judge(found, "costs", priced)
	if bool(priced.get("ok", false)):
		if not (int(priced["expeller"]) > int(priced["expelled"])):
			found.append("costs: the expeller does not pay strictly more than the expelled")
	var planned := expel(probe.duplicate(true))
	_judge(found, "expel", planned)
	if bool(planned.get("ok", false)):
		var plan = planned.get("plan", {})
		if not (plan is Dictionary) or not (plan as Dictionary).has("target"):
			found.append("expel: a successful plan does not name the target")
	var equal := probe.duplicate(true)
	equal["cost_expeller"] = equal["cost_expelled"]
	expect_refusal(found, "expel", expel(equal), R_COST_NOT_ASYMMETRIC)
	var unpowered := probe.duplicate(true)
	unpowered["authorities"] = []
	expect_refusal(found, "expel", expel(unpowered), R_NOT_AUTHORISED)
	var self_target := probe.duplicate(true)
	self_target["target"] = self_target["member"]
	expect_refusal(found, "expel", expel(self_target), R_CANNOT_EXPEL_SELF)
	return found


# --- Internals ---------------------------------------------------------------


## Whether `authored` names the expel authority, compared as TEXT for the reason
## `InstitutionProjection.recognises` documents: an authored list may hold
## `StringName`s while a context built from a save holds plain `String`s, and
## `Array.has()` is key-type strict — so `has("expel")` against `[&"expel"]`
## silently matches nothing.
func _authors_expel(authored: Variant) -> bool:
	if not (authored is Array):
		return false
	for entry in authored as Array:
		if String(entry) == String(Authorised.AUTHORITY_EXPEL):
			return true
	return false
