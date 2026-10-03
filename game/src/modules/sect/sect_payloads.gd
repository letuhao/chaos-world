class_name SectPayloads
extends RefCounted

## The **`{ok, reason, ...}` shapes** `SectApi`'s verbs answer with. Extracted
## because they are the module's vocabulary rather than its behaviour: every verb
## ends in one of these, and a caller learns the whole response contract from one
## file instead of from a dozen private methods in the facade.
##
## ## A refusal is a NAMED game rule, never input validation
##
## Each carries a `reason` constant a caller can render without inventing prose
## (ADR 0084), and each carries the ledger it found so a refusal is provably a
## refusal: the caller can compare `payload["ledger"]` against what it held before
## and see the actor byte-for-byte unchanged (ADR 0044).
##
## ## `applied` is present on EVERY shape
##
## A consumer can read one key without knowing which verb it called. It is the one
## number that is ever non-zero, and it is non-zero exactly when standing moved —
## so a reader checking `applied == 0` is checking "nothing about my standing
## changed", which is ADR 0064's two-part split stated as a field.


## A refused verb, handing back the ledger it found so the caller can see that
## nothing was written.
static func refuse(reason: String, ledger: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "ledger": ledger}


## The ordinary success shape.
static func ok(ledger: Dictionary) -> Dictionary:
	return {"ok": true, "reason": "", "applied": 0, "ledger": ledger}


## `standing_below_floor`, with both numbers so a panel can show the shortfall
## rather than only the refusal. `force: true` is published because this refusal is
## the one a council may overrule: ADR 0064's two-part split exists so promotion on
## thin standing stays expressible, and a caller that cannot SEE that the gate was
## a floor has no way to route the exception.
static func below_floor(ledger: Dictionary, office: SectPositionDef) -> Dictionary:
	return {
		"ok": false,
		"reason": SectApi.STANDING_BELOW_FLOOR,
		"ledger": ledger,
		"required": office.standing_floor,
		"actual": SectState.standing(ledger),
		"force": true,
	}


## `founding_cost_unmet`, with both numbers so a panel can show the shortfall rather
## than only the refusal. `force` is ABSENT on purpose: there is no override for
## founding. BL-0174 prices an institution's existence, and an override would make
## the price decorative.
static func found_unmet(ledger: Dictionary, def: SectDef, price: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"reason": SectApi.FOUNDING_COST_UNMET,
		"ledger": ledger,
		"required": int(price["outstanding"]),
		"actual": int(SectFounding.cost(def)["found"]),
		"currency": String(def.founding_cost.get("currency", "")),
	}


## A refused `declare_schism`, naming the half it was refused for — so a panel can
## say WHICH split could not happen rather than only that one of them did not.
static func schism_refused(reason: String, ledger: Dictionary, half_id: String) -> Dictionary:
	var out := refuse(reason, ledger)
	out["seceding_id"] = half_id
	return out


## The schism success shape.
##
## **Every number that decides the split is published**, because the point of a
## priced split is that a caller can show a player what it will cost: what there
## was, what each half inherits, what each half pays, what each half is left with,
## and — when the price exceeded the inheritance — exactly how much of the bill the
## split could not cover. `applied` is the declaring member's OWN standing delta,
## which is the second half of "costs both halves": the other half's cost is in
## `settled`, and a caller reading only `applied` reads one of two equal charges.
static func schism(
	ledger: Dictionary,
	parent_id: String,
	half_id: String,
	bill: Dictionary,
	unassigned: int,
	applied: int
) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"applied": applied,
		"parent_id": parent_id,
		"seceding_id": half_id,
		"verb": SectSchism.VERB,
		"undivided": int(bill["undivided"]),
		"half": int(bill["half"]),
		"price": int(bill["price"]),
		"unassigned": unassigned,
		"settled": int(bill["settled"]),
		"shortfall": int(bill["shortfall"]),
		"ledger": ledger,
	}


## `period_not_elapsed`, with both counts. This is ADR 0084's "refuses a further step
## until a period elapses" made legible: a panel renders "the seat has been empty 0 of
## 2 periods" without knowing what a stage is.
static func period_not_elapsed(
	ledger: Dictionary, office: SectPositionDef, held: int
) -> Dictionary:
	return {
		"ok": false,
		"reason": SectApi.PERIOD_NOT_ELAPSED,
		"ledger": ledger,
		"required": maxi(0, office.succession_periods),
		"actual": held,
	}


## The teaching success shape.
##
## `standing_delta` is **always 0** and is published rather than omitted, because
## ADR 0064's two-part split is the reason a lesson may not touch standing and a
## consumer has to be able to check that for itself. `fit` and `fit_delta` are the
## only numbers that move; `tax` is what the teacher paid for them.
static func taught(ledger: Dictionary, gained: int, tax: float) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"applied": 0,
		"standing_delta": 0,
		"fit": (ledger["fit"] as Dictionary).duplicate(),
		"fit_delta": gained,
		"tax": tax,
		"ledger": ledger,
	}
