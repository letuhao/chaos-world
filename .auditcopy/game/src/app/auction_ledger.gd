class_name AuctionLedger
extends RefCounted

## The composition root's AUDIT TRAIL for the auction event contract (ADR 0093, ADR 0102).
##
## ## Why this file exists
##
## `NpcLedger` is the precedent, and this is its twin for the auction bus. ADR 0093 accepts
## the cost of a signal contract: "an event that fires before a subscriber connects is lost
## … because a durable event log is a queue, and a queue in `app/` would be a stateful
## system in the composition root". So the bus carries the FACT and this file answers a
## different question: *what did the composition root observe, and what did it do about it*.
##
## ## It is a bounded trail and a refusal list, never save state
##
## `MarketApi`'s lots ARE the truth about an auction (ADR 0102). This answers a different
## question — which signals arrived, and which ones could not be credited — and a log in
## `app/` that grew with every bid for a session's length is the stateful-system shape
## `tools/arch/rules.py` rejects. Hence [constant MAX_ROWS]: the oldest row is DROPPED at
## the bound, so the memory is a named constant rather than a growth curve.
##
## ## Why a refusal is recorded rather than swallowed
##
## `AuctionStanding` skips a credit it cannot make — an unknown cause, a participant with no
## live body. Silently, that is indistinguishable from a signal nobody published, which is
## the exact bug class this program exists to close (DEF-0217 was four signals with no
## subscriber at all). So the skip is written here **by name**, and a caller can read
## "three auctions settled and one could not be credited" instead of guessing.
##
## ## It holds no `Actor`, reads no `module_data` and writes none, so it adds no
## `persistence` signal to `app/` and never trips the app-state check — the `NpcLedger`
## invariant, restated because it is the one that makes a log safe to keep.

## The most rows the trail keeps. A save is the auction ledger; this is a log, and a log
## that grew with every bid for the length of a session would be the unbounded table the
## composition root is not allowed to hold. The oldest row is dropped first.
const MAX_ROWS := 64

## The partner a `defaulted_on_a_bid` is written against.
##
## **The auction house, and no named counterparty.** ADR 0102's signal carries no seller on
## a default: the lot stays open and the challenge passes to the next bidder, so there is
## nobody the broken promise was made *to* on that signal. A grudge invented against
## whoever happened to bid next would be a lie the ledger would then repeat forever.
const HOUSE_PARTNER := "auction_house"

# --- refusals -----------------------------------------------------------------
# Named constants rather than prose, so a panel renders the rule it was given and a caller
# can branch on the fact instead of re-deriving it (ADR 0084).

## The bridge named a cause the `social` catalog does not ship. `SocialApi.apply_cause`
## would have refused it `unknown_cause`, so this names that refusal from its own side.
const UNKNOWN_CAUSE := "unknown_cause"
## The auction named a participant this process holds no live `Actor` for — an npc the
## build never authored, or a bidder this process never minted. Their lot is unaffected:
## the auction ledger already holds the settlement.
const NO_SUBJECT := "no_subject"
## The partner id was empty, so there was nobody to record the bond against.
const NO_PARTNER := "no_partner"

## Every auction signal this process has observed, oldest first.
##
## A `static var` because the bus is process-wide (`AuctionEvents.shared()`) and a
## per-instance sink would need every owner to keep it alive to be worth connecting.
## `rules.py` excludes `static var` from the app-state heuristics by construction — this is
## process-wide memoisation, the same shape `NpcLedger._rows` documents.
static var _rows: Array[Dictionary] = []

## Every credit the bridge refused to make, with the reason it gave. Bounded exactly as the
## trail is: a refusal list that grew without a cap would be the same defect the cap on the
## trail prevents.
static var _refusals: Array[Dictionary] = []


## Record one observed signal. `facts` are primitives only, one fact per key — ADR 0093's
## rule, and the reason a panel can render a row without asking what any of it means.
static func record(signal_name: String, facts: Dictionary) -> void:
	var row := facts.duplicate()
	row["signal"] = signal_name
	if _rows.size() >= MAX_ROWS:
		_rows.remove_at(0)
	_rows.append(row)


## Record a credit the bridge could not make. `reason` is a named constant above or the
## verbatim refusal `SocialApi.apply_cause` returned, so a caller reads the rule rather than
## inferring one.
static func refuse(
	reason: String, cause_id: StringName, actor_id: String, partner_id: String
) -> void:
	var row := {
		"reason": reason,
		"cause_id": String(cause_id),
		"actor_id": actor_id,
		"partner_id": partner_id,
	}
	if _refusals.size() >= MAX_ROWS:
		_refusals.remove_at(0)
	_refusals.append(row)


## The trail, newest first — the order a panel or a probe reads it in. Copied, so a caller
## cannot reach in and rewrite history.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_rows.size() - 1, -1, -1):
		out.append((_rows[index] as Dictionary).duplicate())
	return out


## The refusals, newest first.
static func refusals() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_refusals.size() - 1, -1, -1):
		out.append((_refusals[index] as Dictionary).duplicate())
	return out


## Every observed signal named `signal_name`, newest first — the row filter a panel asks
## when it renders one event rather than the whole trail.
static func rows_for(signal_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows():
		if String(row.get("signal", "")) == signal_name:
			out.append(row)
	return out


## How many signals have been observed, capped at [constant MAX_ROWS].
static func count() -> int:
	return _rows.size()


## How many credits have been refused, capped at [constant MAX_ROWS].
static func refusal_count() -> int:
	return _refusals.size()


## The most recent row, or `{}` when nothing has been observed — the same empty-shape answer
## `MarketApi.summary` gives for a lot this build does not ship.
static func last() -> Dictionary:
	if _rows.is_empty():
		return {}
	return (_rows[_rows.size() - 1] as Dictionary).duplicate()


## The whole read model in one call, primitives only. `{}`-shaped answers rather than a
## bare row list, so a panel never has to know a row could be absent.
static func summary() -> Dictionary:
	return {
		"count": _rows.size(),
		"refusal_count": _refusals.size(),
		"max_rows": MAX_ROWS,
		"rows": rows(),
		"refusals": refusals(),
		"last": last(),
		"house_partner": HOUSE_PARTNER,
	}


## Forget the trail. Only a test harness calls this: `AuctionEvents.shared()` is
## process-wide and a suite that ran an auction would otherwise leave rows behind for
## whichever auction suite runs next and read a count that is not its own.
static func reset() -> void:
	_rows.clear()
	_refusals.clear()
