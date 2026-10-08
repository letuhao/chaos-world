class_name Territorial
extends InstitutionCapability

## Sovereignty over authored places, and NOTHING else (ADR 0085, ADR 0922).
## A trading guild never needs this; a polity's whole reason to exist includes
## it, and the line between the two is the point of a per-capability contract.
##
## ## A claim grants NO yield, NO upkeep and NO combat bonus
##
## ADR 0085's territory rule, as shape rather than prose: every verb here
## answers with place IDS and counts, and there is nowhere in the vocabulary to
## put a number a place would earn, cost or add to a fight. The contract probes
## in [method contract_findings] assert that a successful plan carries no key
## naming a yield surface, which is the strongest check available where a stat
## sheet cannot be named (a claim DECIDES who may fight and where; the combat
## spine decides who wins).
##
## ## What was REJECTED, precisely
##
## - **A claim that moves ground.** "A claim on held ground never moves ground"
##   (ADR 0085): a challenge is a CONFLICT, and a conflict is a declaration of
##   sides and a prize with its own module. There is deliberately no `challenge`
##   verb here — the moment this capability could take a place away, it would be
##   a second combat system wearing a ledger.
## - **A node HOLD.** A `holdings` `OwnerRef` is exclusive and is that module's
##   own question; a resource node is not a region. Filing a hold here would
##   invent a second address for one fact (the ADR 0066 failure mode).
## - **A GRANT of ground.** A grant is a `WorldPolityLedger` record (a fact
##   whose subject is the organization, on the world). A capability in
##   `contracts/` may not name that store, so a grant has no representation
##   here — it is a later slice, and it is not invented early.
## - **Overlapping ownership.** Two organizations cannot BOTH hold one place:
##   [method claim] refuses a place the context reports as already held by
##   another holder, naming it. There is no shared sovereignty, no condominium
##   and no partial claim, because a rule that admitted one would need a
##   resolution order this layer has no data for.
##
## ## Context keys this capability reads
##
##   - `member` — the acting member's id (`String`), recorded on the plan.
##   - `institution` — the claiming organization (`String`, family-wide).
##   - `places` — the place ids this organization claims (`Array`).
##   - `authored` — the universe of place ids content defines (`Array`). A place
##     no content defines grants nothing and can be claimed by nobody.
##   - `holder` — the organization the world reports as holding a place
##     (`String`, `""` for unheld). Used by [method claim]'s overlap refusal.
##   - `place` — the one place id a verb is asked about (`String`).
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111).

## The id this capability is dispatched under.
const ID := &"territorial"

## No place was named. There is nothing to look up or claim, so the request is
## incomplete rather than declined.
const R_NO_PLACE_ID := "no_place_id"
## No such place: content defines no region under this id. Distinct from the
## family's `unknown_institution`, which names the organization.
const R_UNKNOWN_PLACE := "unknown_place"
## The organization already claims this place. A re-claim is a no-op with no
## second meaning, refused so a caller learns the ledger already says so.
const R_ALREADY_CLAIMED := "already_claimed"
## Another organization holds this place. **Overlapping ownership is refused by
## name** — a place has one sovereign, and two claimants would need a resolution
## order this layer cannot supply.
const R_HELD_BY_ANOTHER := "held_by_another"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [R_NO_PLACE_ID, R_UNKNOWN_PLACE, R_ALREADY_CLAIMED, R_HELD_BY_ANOTHER]
	return out


## ## Whether this organization claims `place_id` — the `has_capability` shape.
##
## `{ok: true, has: <bool>}` for a question that can be asked, and a refusal
## only for one that cannot (`no_place_id`). "This organization does not claim
## that place" is an ANSWER, not an error: a polity claims little, and the
## negative is what a map screen renders as an ordinary border.
func holds(ctx: Dictionary, place_id: StringName) -> Dictionary:
	if place_id == &"":
		return InstitutionCapability.refuse(R_NO_PLACE_ID)
	return InstitutionCapability.ok({"has": _claims(ctx.get("places", []), place_id)})


## The place ids this organization claims, canonically ordered by STRING value
## — never `Array[StringName].sort()`, because interned ids are not specified to
## order by their string value and a list whose order is load-bearing must not
## depend on which id loaded first. An empty list is a legitimate authored
## state: an organization that claims nothing yet, which is a different fact
## from an organization that does not exist.
func claim_terms(ctx: Dictionary) -> Array[String]:
	return _sorted(ctx.get("places", []))


## ## Plan a claim over one authored place, or refuse it.
##
## `{ok: true, reason: "", plan: {institution, member, place, cause}}` — ids
## only, and the applier writes the claim. Refusal order: place named, known,
## not already this organization's, not another organization's.
##
## The overlap check reads `holder` from the CONTEXT — who the WORLD says holds
## the place — because `contracts/` may not name the store that answer lives
## in. A world that publishes no holder publishes `""`, which reads as unheld;
## that is the same "nobody opened this debt" convention the family uses for
## absence (there is no holder and there was never a claim to release).
func claim(ctx: Dictionary) -> Dictionary:
	var place := InstitutionCapability.text(ctx.get("place", ""), "")
	if place == "":
		return InstitutionCapability.refuse(R_NO_PLACE_ID)
	if not _is_id_list(ctx.get("authored", [])):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "authored"}
		)
	if not _known(ctx.get("authored", []), place):
		return InstitutionCapability.refuse(R_UNKNOWN_PLACE)
	if _claims(ctx.get("places", []), StringName(place)):
		return InstitutionCapability.refuse(R_ALREADY_CLAIMED, {"place": place})
	var holder := InstitutionCapability.text(ctx.get("holder", ""), "")
	if holder != "":
		return InstitutionCapability.refuse(R_HELD_BY_ANOTHER, {"place": place, "holder": holder})
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"institution": InstitutionCapability.text(ctx.get("institution", ""), ""),
					"member": InstitutionCapability.text(ctx.get("member", ""), ""),
					"place": place,
					"cause": "claimed",
				},
			}
		)
	)


## ## The authored data this capability reads cannot be READ.
##
## A place list that arrived as a string (a hand-edited save, a JSON row) would
## make every lookup answer `has: false`, which is indistinguishable from a
## polity that claims nothing. `check` vets what is PRESENT; an absent key is
## the per-verb refusals' business, so the family's bare probe passes.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["places", "authored"]:
		if ctx.has(field) and not _is_id_list(ctx[field]):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: a claim on an authored
## place plans, the plan carries NO key that names a yield, an upkeep or a
## combat surface (ADR 0085 — a claim decides who may fight and where), an
## already-claimed place is refused by name, a place this organization does not
## claim is `has: false` rather than a refusal, and a place another holder
## claims is refused `held_by_another` — the no-overlapping-ownership rule.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"member": "probe_member",
		"places": ["probe_meadow"],
		"authored": ["probe_meadow", "probe_harbour"],
		"holder": "",
		"place": "probe_harbour",
	}
	var planned := claim(probe.duplicate(true))
	_judge(found, "claim", planned)
	if bool(planned.get("ok", false)):
		var plan = planned.get("plan", {})
		if not (plan is Dictionary):
			found.append("claim: a successful plan is not a dictionary")
		else:
			for key in (plan as Dictionary).keys():
				if _names_a_yield_surface(String(key)):
					found.append(
						"claim: the plan names a yield surface ('%s'); a claim grants none" % key
					)
	var held := holds(probe.duplicate(true), &"probe_meadow")
	_judge(found, "holds", held)
	if bool(held.get("ok", false)) and not bool(held["has"]):
		found.append("holds: a claimed place did not read as held")
	var free := holds(probe.duplicate(true), &"probe_harbour")
	if bool(free.get("ok", false)) and bool(free["has"]):
		found.append("holds: an unclaimed place read as held")
	var again := probe.duplicate(true)
	again["place"] = "probe_meadow"
	expect_refusal(found, "claim", claim(again), R_ALREADY_CLAIMED)
	var taken := probe.duplicate(true)
	taken["holder"] = "probe_rival"
	expect_refusal(found, "claim", claim(taken), R_HELD_BY_ANOTHER)
	var ghost := probe.duplicate(true)
	ghost["place"] = "probe_nowhere"
	expect_refusal(found, "claim", claim(ghost), R_UNKNOWN_PLACE)
	return found


# --- Internals ---------------------------------------------------------------


## Whether the authored list `places` names `place_id`, matched by TEXT: an
## authored array may hold `StringName`s while a context built from a save
## holds plain `String`s, and `Array.has()` is type-strict — the silent no-match
## failure `InstitutionProjection.recognises` documents at length.
func _claims(places: Variant, place_id: StringName) -> bool:
	if not (places is Array):
		return false
	for entry in places as Array:
		if String(entry) == String(place_id):
			return true
	return false


## Whether `authored` names `place`, by text, for the reason [method _claims]
## states. A place content does not define exists for nobody, so a claim over
## one is a content bug rather than a policy refusal.
func _known(authored: Variant, place: String) -> bool:
	if not (authored is Array):
		return false
	for entry in authored as Array:
		if String(entry) == place:
			return true
	return false


## `value`'s entries as sorted strings when it is a list of id-shaped values,
## `[]` otherwise. Shared by [method claim_terms] and [method check], so "what
## is a readable id list" has one answer in this file.
func _sorted(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (value is Array):
		return out
	for entry in value as Array:
		if entry is String or entry is StringName:
			out.append(String(entry))
	out.sort()
	return out


## Whether `value` really is a list of ids. An empty array IS one: an
## organization that claims nothing is a legitimate authored state.
func _is_id_list(value: Variant) -> bool:
	if not (value is Array):
		return false
	for entry in value as Array:
		if not (entry is String or entry is StringName):
			return false
	return true


## Whether `key` names a yield surface a claim must never carry. ADR 0085's
## rule is that territory grants no combat bonus, and it also grants no income
## and asks no upkeep — the three shapes a place-based economy would smuggle in
## through a plan a later applier reads. A substring test, so `grain_yield` and
## `upkeep_per_period` are both caught.
func _names_a_yield_surface(key: String) -> bool:
	for marker in ["yield", "upkeep", "income", "tax", "bonus", "defen", "combat", "power"]:
		if key.contains(marker):
			return true
	return false
