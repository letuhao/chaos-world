class_name ConsentLedger
extends RefCounted

## **Every oath that was OFFERED and every answer it was given** (ADR 0196).
##
## ## What it is for, and the one thing it may never be
##
## `SocialBond` is the truth about how two people regard each other — that is ADR 0091
## and this ledger does not restate it. What the bond cannot say is **that an offer was
## made and what was answered**, because a refusal writes *nothing* to the bond except
## the cost it costs: from the player's side after a refusal, the elder is exactly where
## they were before the offer. A world that cannot tell "he never asked" from "he asked
## and was refused" cannot price an oath.
##
## **So this records the CONSENT, and only the consent.** A row here is an offer and an
## answer, plus what the refusal cost at the time it was given. It is never a second
## copy of a standing value that `SocialBond` owns, and a refusal here writes no standing
## at all — the cost rides the bond's own cause ledger, which is where a reader looking
## for "why does he think less of me" will look, and not here.
##
## ## The audience constraint is also the honesty constraint
##
## A consent ledger has one audience: **the player**. "He refused you, and it cost you"
## is a line a panel prints. `give_to_witnesses` is the one social fact about the act
## that is *not* about the player's regard of the elder, and it is here for the same
## reason — a refusal the witnesses never heard about did not happen in a world with
## witnesses.
##
## ## Rows are ONE-SHOT, which is what stops the offer from being spam
##
## `offer` refuses a partner an offer that has already been ANSWERED, so the top rung of
## the ladder cannot be re-minted by pressing the button again. A row may be *renewed* —
## a brotherhood renewed is a different act and costs another refusal to end — but the
## renewal never grants `shared_brotherhood` twice (see `BrotherhoodOath`).
##
## **Persisted on the player actor** under its own `module_data` key, so `Actor.to_dict`
## is still the only save (ADR 0027) and a reloaded player has not, in the world's eyes,
## never made the offer.

const MODULE_KEY := &"consent_ledger"
const STATE_COMPONENT := &"consent_ledger"
const SCHEMA_VERSION := 1

## The `actor.components` slot the live ledger lives in between saves, exactly as
## `SocialState` and `NpcState` do. A cache and not an optimisation: every verb has to
## mutate the SAME object, or a cost recorded by one call is invisible to the next.
const _PROVIDER_COMPONENT := &"social_consent"

## Why an offer ended. A closed vocabulary, so a panel renders a reason it did not
## have to invent — and so `refused` cannot be spelled two ways by two call sites.
const OUTCOME_ACCEPTED := &"accepted"
const OUTCOME_REFUSED := &"refused"
const OUTCOME_DECLINED := &"declined"  ## the player withdrew the offer themselves
const OUTCOMES: Array[StringName] = [OUTCOME_ACCEPTED, OUTCOME_REFUSED, OUTCOME_DECLINED]

var _rows: Dictionary = {}


func _init() -> void:
	pass


## The row for `partner_id`, or `{}` when this oath has never been put to them.
func row(partner_id: StringName) -> Dictionary:
	return _rows.get(String(partner_id), {})


## Every row, keyed by partner id and sorted, for a panel and for a save audit.
func rows() -> Dictionary:
	var out := {}
	for key in _rows.keys():
		out[String(key)] = (_rows[key] as Dictionary).duplicate(true)
	return out


func offer_count() -> int:
	return _rows.size()


## Whether this oath has been put to `partner_id` before and ANSWERED. The anti-repeat
## rule: an offer already answered is refused, because an unanswered offer is not a
## thing a player may reopen every frame.
func answered(partner_id: StringName) -> bool:
	return not String(row(partner_id).get("outcome", "")) == ""


## Record that `partner_id` was put to the oath. Returns `{ok, reason}`; a refusal to
## record NAMES ITSELF rather than silently doing nothing, because a lost consent record
## is the exact defect this ledger exists to prevent.
##
## `witnessed` is recorded at offer time and never moves: the witness saw the *offer*,
## and whether the answer was yes is the two of them's business until it is not.
func offer(
	partner_id: StringName, witness_id: StringName = &"", witnessed: bool = false
) -> Dictionary:
	if partner_id == &"":
		return {"ok": false, "reason": "no_partner"}
	if answered(partner_id):
		return {"ok": false, "reason": "already_answered"}
	_rows[String(partner_id)] = {
		"partner_id": String(partner_id),
		"witness_id": String(witness_id),
		"witnessed": witnessed,
		"outcome": "",
		"cost": "",
		"gives_to_witnesses": false,
	}
	return {"ok": true, "reason": ""}


## Record the answer `partner_id` gave. `cost` is the CAUSE ID the refusal charged to the
## bond — a reference to the ledger's own record, never a copy of the number it moved.
## Refuses an offer that was never made, so a caller cannot answer a question nobody
## asked.
##
## `gives_to_witnesses` is set here and only here, and only on an acceptance: a sworn
## oath is public, a refusal is the two of them's business unless it was made standing
## in front of someone. The row is the record; the bond's class is still derived.
func answer(
	partner_id: StringName,
	outcome: StringName,
	cost: StringName = &"",
	gives_to_witnesses: bool = false
) -> Dictionary:
	if partner_id == &"":
		return {"ok": false, "reason": "no_partner"}
	if not OUTCOMES.has(outcome):
		return {"ok": false, "reason": "unknown_outcome"}
	if answered(partner_id):
		return {"ok": false, "reason": "already_answered"}
	var existing := row(partner_id)
	if existing.is_empty():
		return {"ok": false, "reason": "no_offer"}
	existing["outcome"] = String(outcome)
	existing["cost"] = String(cost)
	existing["gives_to_witnesses"] = outcome == OUTCOME_ACCEPTED or gives_to_witnesses
	_rows[String(partner_id)] = existing
	return {"ok": true, "reason": ""}


func to_dict() -> Dictionary:
	return {"version": SCHEMA_VERSION, "rows": rows()}


static func from_dict(data: Dictionary) -> ConsentLedger:
	var ledger := ConsentLedger.new()
	for key in data.get("rows", {}).keys():
		ledger._rows[String(key)] = (data["rows"][key] as Dictionary).duplicate(true)
	return ledger


static func empty() -> Dictionary:
	return {"version": SCHEMA_VERSION, "rows": {}}
