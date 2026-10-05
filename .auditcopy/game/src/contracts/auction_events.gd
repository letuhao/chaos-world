class_name AuctionEvents
extends RefCounted

## Signal contract for the `market` module's auction (ADR 0102, ADR 0093). Emitted by
## the module; consumed by any observer.
##
## Everything here announces a fact **already written to the ledger**. A consumer must
## never treat one of these as a request it can veto — that is the distinction ADR 0093
## draws between an event and a hook — and every number carried is one the caller could
## already read from `MarketApi.summary(actor)["lots"]`.
##
## ## No standing delta, anywhere
##
## `standing` is institutional recognition owned by `sect` (ADR 0083/0084). A module
## that wrote it here would be a **second writer** and would buy an `economy -> sect`
## edge. So nothing below mutates a relationship: `app/` subscribes and calls
## `SocialApi.apply_cause` with an authored cause id, which is where the ladder is
## allowed to move.
##
## ## `shared()` rather than a facade accessor
##
## `HoldingsApi.events()` is the usual door, and it is the right one — but `MarketApi`
## already publishes twelve public methods, exactly `MAX_FACADE_PUBLIC_METHODS`, so an
## accessor here would be a thirteenth and `tools arch` would fail the gate. The bus
## therefore lives on the contract, which `contracts/` may own (it is the leaf layer),
## and the module reaches it through its own private holder. The subscriber's call is
## unchanged in spirit: one stable instance, connected once.

## A bid was recorded against `lot_id` and is now the high bid. `amount` is the bid
## written and `required` is what the module would have accepted as the least — a
## consumer rendering a ladder reads both without re-deriving the step.
signal bid_placed(bidder_id: String, lot_id: StringName, amount: int, required: int)

## A previous high bidder was displaced. `by_id` is the actor who displaced them and
## `amount` is the new high — the amount that beat them, not the amount they held.
## **The displaced bidder's own bid is untouched in the ledger**: they stay in the walk
## and fall to their own bid at settlement (ADR 0102), so a consumer must not read this
## as a removal from the lot.
signal outbid_in_auction(bidder_id: String, lot_id: StringName, by_id: String, amount: int)

## A bidder's purse no longer covered their own bid when the lot closed. The lot stays
## open and the challenge passes to the next bidder at THEIR bid; the defaulting bidder
## is not charged and the seller is never charged a shortfall. `amount` is the promise
## they could not keep.
signal defaulted_on_a_bid(bidder_id: String, lot_id: StringName, amount: int)

## A lot closed `sold`. The coins have moved to `seller_id` and the escrolled good has
## been delivered to `bidder_id` **before** this fires, so a consumer that answers by
## reading the two purses sees them already settled rather than mid-transfer.
signal won_auction(bidder_id: String, lot_id: StringName, amount: int, seller_id: String)

## ## The one bus, and why it lives HERE rather than behind a facade accessor
##
## `contracts/` is the leaf layer (`LAYER_DEPS` in `tools/arch/rules.py`), so a static
## here is a legal home for a shared instance and no dependency is invented to carry it.
static var _shared: AuctionEvents = null


## The single bus every auction-event publisher and subscriber shares. Stable across
## calls, so a subscriber that connected once is still connected the next time this is
## asked for.
static func shared() -> AuctionEvents:
	if _shared == null:
		_shared = AuctionEvents.new()
	return _shared
