class_name CustodyState
extends RefCounted

## The custody ledger (ADR 0104).
##
## ## A claim, not a thing
##
## A record names a **subject DEF ID** and a `holder` `OwnerRef`, and carries a term as a
## COUNT of periods. It is never an `Actor`, never an `ItemInstance`, never a `Resource`, and
## never a price — so nothing here can answer "what is this person worth".
##
## ## No description field, ever
##
## There is no `description`, `flavor`, `note` or `display_name` here, and the subject's name
## is authored on its def and read through the catalog. Prose in a save schema is how prose
## becomes what gets read. Vocabulary is exactly: holder, claim, term, periods, transferred,
## released.
##
## ## String keys throughout
##
## `Actor.to_dict` converts only the OUTER `module_data` key, so an inner `StringName` reaches
## the save untouched and breaks every round trip (ADR 0027).

const MODULE_KEY := &"custody_state"
const SCHEMA_VERSION := 1

## Bounded open claims. A refused admit, never a silent trim (the `NpcState.ensure_entry`
## shape) — a custody ledger that grows without a cap is a save that does the same.
const MAX_CLAIMS := 64

## The closed subject kinds. `npc` is what ships; `player` is a closed value reserved for a
## `PlayerDef` that does not exist yet, so authoring it can never be a typo that resolves to
## nobody.
const SUBJECT_KINDS: Array[StringName] = [&"npc", &"player"]

## The only two statuses a claim has.
const HELD := "held"
const RELEASED := "released"


static func empty() -> Dictionary:
	return {"version": SCHEMA_VERSION, "claims": {}}


static func normalize(data: Variant) -> Dictionary:
	# Starts from `empty()` ALWAYS, so a fresh ledger carries `claims` as a real key and a
	# caller that indexes it gets a refusal rather than a runtime error.
	var out := empty()
	if not data is Dictionary:
		return out
	var claims = (data as Dictionary).get("claims", {})
	if not claims is Dictionary:
		return out
	for claim_id in (claims as Dictionary).keys():
		var claim = (claims as Dictionary)[claim_id]
		if not claim is Dictionary:
			continue
		var subject := String((claim as Dictionary).get("subject_id", ""))
		if subject == "":
			# A claim with no subject names nothing anyone can hold. Dropped rather than kept.
			continue
		var ref := OwnerRef.from_dict((claim as Dictionary).get("holder", {}))
		if ref.is_empty():
			# An unheld claim is the RELEASED state, not a broken row.
			out["claims"][String(claim_id)] = {
				"claim_id": String(claim_id),
				"subject_id": subject,
				"subject_kind": String((claim as Dictionary).get("subject_kind", "npc")),
				"holder": OwnerRef.vacant(),
				"term_id": String((claim as Dictionary).get("term_id", "")),
				"periods": maxi(0, int((claim as Dictionary).get("periods", 0))),
				"opened_period": int((claim as Dictionary).get("opened_period", 0)),
				"status": RELEASED,
			}
			continue
		out["claims"][String(claim_id)] = {
			"claim_id": String(claim_id),
			"subject_id": subject,
			"subject_kind": String((claim as Dictionary).get("subject_kind", "npc")),
			"holder": ref.to_dict(),
			"term_id": String((claim as Dictionary).get("term_id", "")),
			"periods": maxi(0, int((claim as Dictionary).get("periods", 0))),
			"opened_period": int((claim as Dictionary).get("opened_period", 0)),
			"status": String((claim as Dictionary).get("status", HELD)),
		}
	return out


## The claim at `claim_id`, or `{}` when there is none.
static func claim(state: Dictionary, claim_id: StringName) -> Dictionary:
	var found = (state["claims"] as Dictionary).get(String(claim_id))
	return (found as Dictionary) if found is Dictionary else {}


## The first open claim on `subject_id`, or `{}`. One subject may be held once: a second
## claim on the same subject would leave two holders and no way to say which one counts.
static func claim_on_subject(state: Dictionary, subject_id: String) -> Dictionary:
	for claim_id in (state["claims"] as Dictionary).keys():
		var row := state["claims"][claim_id] as Dictionary
		if (
			String(row.get("subject_id", "")) == subject_id
			and String(row.get("status", "")) == HELD
		):
			return row
	return {}


## The holder of `claim`, or `{}`. A released claim carries the VACANT marker rather than an
## empty dict (ADR 0083): the claim exists and its value does not.
static func holder(claim: Dictionary) -> Dictionary:
	return claim.get("holder", {}) as Dictionary


## Move the holder of `claim_id` to `holder`, or refuse. A released claim is not reopened —
## capture is the only way a subject is taken, and a released claim stays released so the
## subject's history reads as history.
static func set_holder(state: Dictionary, claim_id: StringName, holder: Dictionary) -> Dictionary:
	var row := claim(state, claim_id)
	if row.is_empty():
		return {"ok": false, "reason": "no_such_claim"}
	if String(row.get("status", "")) != HELD:
		return {"ok": false, "reason": "not_held"}
	var ref := OwnerRef.from_dict(holder)
	if ref.is_empty():
		return {"ok": false, "reason": "unknown_owner"}
	row["holder"] = ref.to_dict()
	state["claims"][String(claim_id)] = row
	return {"ok": true, "reason": ""}


## Write one claim row. Refuses an unknown subject kind rather than storing it, because a
## kind nobody can resolve is a claim nobody can enforce.
static func put(state: Dictionary, claim: Dictionary) -> Dictionary:
	var subject := String(claim.get("subject_id", ""))
	if subject == "":
		return {"ok": false, "reason": "unknown_subject"}
	if not SUBJECT_KINDS.has(StringName(claim.get("subject_kind", ""))):
		return {"ok": false, "reason": "unknown_subject_kind"}
	if (state["claims"] as Dictionary).size() >= MAX_CLAIMS:
		return {"ok": false, "reason": "custody_full"}
	state["claims"][String(claim.get("claim_id", ""))] = claim.duplicate(true)
	return {"ok": true, "reason": ""}


## Settle `periods` against `claim_id`'s term. **All-or-nothing**: a request larger than the
## term settles NOTHING and is refused, so a holder is never left owing less than it claimed
## to owe and never silently forgiven.
##
## The cap-then-accept version of this (`mini(owed, periods)`) looked friendlier and was
## wrong twice over: it let a caller believe nine periods were settled when two were, and it
## made a partially-paid term indistinguishable from a fully-paid one on the next call. A
## caller that wants to settle what remains asks for exactly `periods_left`, which the
## refusal reports.
static func settle_term(state: Dictionary, claim_id: StringName, periods: int) -> Dictionary:
	var row := claim(state, claim_id)
	if row.is_empty():
		return {"ok": false, "reason": "no_such_claim"}
	if periods <= 0:
		return {"ok": false, "reason": "no_periods"}
	var owed := int(row.get("periods", 0))
	if owed <= 0:
		return {"ok": false, "reason": "claim_settled"}
	if periods > owed:
		return {"ok": false, "reason": "term_exceeds", "periods_left": owed}
	row["periods"] = owed - periods
	state["claims"][String(claim_id)] = row
	return {"ok": true, "reason": "", "settled": periods, "periods_left": row["periods"]}
