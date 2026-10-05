class_name AuctionStanding
extends RefCounted

## **The composition root's SUBSCRIBER to the auction event contract** (ADR 0102, ADR 0093,
## ADR 0091). `app/` is where the market's four auction signals reach
## `SocialApi.apply_cause`.
##
## ## Why this file exists (DEF-0217)
##
## `contracts/auction_events.gd` declares `bid_placed`, `outbid_in_auction`,
## `defaulted_on_a_bid` and `won_auction`, and ADR 0102's Consequences section promises they
## reach `SocialApi.apply_cause` — while the **only `.connect` anywhere in the repo was in a
## test**. Every signal was emitted into the void: the bus existed, the contract promised a
## consumer, and there was none. ADR 0102 accepted "the events are unwired until `app/`
## installs the causes … for one change", and this is that change.
##
## ## Why the wiring lives in `app/` and the CAUSES live in `social/`
##
## ADR 0093's whole inversion: **the observer registers with the subject, and the module
## names no consumer.** `market` declares `["contracts", "core", "economy", "items"]` — it
## may not name `social`, and adding that edge would be an undeclared dependency the gate
## fails on. So the subscriber is here, and `NpcBoot._install_event_seams` is the exact
## precedent: same shape, same guarded connect, same reason.
##
## ## And `AuctionEvents.shared()` is the door, because a facade accessor was not available
##
## `MarketApi` publishes exactly twelve public methods, `rules.MAX_FACADE_PUBLIC_METHODS`,
## so a thirteenth `events()` accessor fails `tools arch`. The bus therefore lives on the
## contract, which is the leaf layer and may own a shared instance — and ADR 0093 accepts
## the cost it names: "an event that fires before a subscriber connects is lost … accepted
## because a durable event log is a queue, and a queue in `app/` would be a stateful
## system". Nothing may bid before `EconomyBoot.install` has run.
##
## ## A participant is a PERSON, and a refusal writes nothing
##
## `SocialApi.apply_cause(actor, partner_id, …)` needs a live `Actor` to write a bond on,
## and an auction participant may be any actor whose purse covers their bid. So a bidder
## or a seller who this process has **no live `Actor` for** is skipped by name: they stay
## on the auction ledger, where the money already moved, and only the social ladder is
## untouched. **Nothing about the settlement changes** — ADR 0093's rule that an event
## announces a fact already written, and a consumer must never treat one as a veto it can
## use to unwind.
##
## The mirror is deliberately NOT written, because the contract says so: "`SocialApi` leaves
## the mirror to the caller's transaction". The seller's regard for the winning bidder is
## the seller's own transaction to record.

## The tag stamped on a shop counter's `Actor.tags` (ADR 0092: a role is a tag). An auction
## against a merchant attributes the sale to `shop_<shop_id>`, which is exactly what
## `ShopCounter` names the Actor — so a player who outbids for a stall's goods improves
## their standing with that stall, and the same id resolves from either direction.
const SHOP_ROLE := ShopCounter.ROLE

## Every `cause_id` this bridge applies, mapped from the signal it answers.
##
## ## All FOUR are authored, because `apply_cause` refuses an unknown cause
##
## `SocialApi.apply_cause` answers `{"ok": false, "reason": "unknown_cause"}` for a cause
## the catalog does not ship — so a bridge built on ids nobody authored would be a bridge
## that refuses on every event. **A cause that nothing references is the mirror defect
## (dead content), so these are not new inert vocabulary: each one is applied by exactly the
## handler named beside it, below.**
##
## ## `bid_placed` deliberately has NO cause, and that is the anti-farm rule
##
## Placing a bid is an act a player performs freely, as often as they like. A cause for it
## would be a per-click standing faucet: `SocialBondClass.FRIEND_DISTINCT_CAUSES` counts
## distinct KINDS, so a bid cause and an outbid cause sharing a `market` kind would still
## be one kind, but a bid cause in its own `bid` kind would make the whole ladder buyable
## from a merchant. So `bid_placed` is **recorded and announced, never credited** — which is
## precisely what ADR 0102 meant by "the events announce facts, `app/` decides what they
## are worth".
const BID_CAUSE := &""
const OUTBID_CAUSE := &"outbid_in_auction"
const DEFAULTED_CAUSE := &"defaulted_on_a_bid"
const WON_CAUSE := &"won_auction"

## The player actor `install` was handed, or null before any install. Held so an auction
## event fired between boots still has a subject to write the bond on.
static var _player: Actor = null

## That player's id, so a lot naming `&"hero"` resolves to the live body. An id, not the
## actor, is what the auction ledger carries — "a bid is a PROMISE and promises outlive the
## room" (ADR 0102).
static var _player_id: String = ""


## Every cause id this bridge can apply, sorted — the vocabulary a content audit reads to
## answer "is anything unwired here", and what `tests/app/test_auction_standing.gd` pins
## against the authored catalog.
static func cause_ids() -> Array[StringName]:
	var out: Array[StringName] = [OUTBID_CAUSE, DEFAULTED_CAUSE, WON_CAUSE]
	out.sort()
	return out


## Connect every auction signal to its handler, and remember the player whose id a lot may
## name. **Guarded by `is_connected`** (AGENTS.md): `AuctionEvents.shared()` is a
## process-wide singleton, `EconomyBoot.install` is idempotent and is called again after a
## save load, and an unguarded connect would accumulate one handler per boot until every
## outbid moved standing N times.
##
## `player` is recorded rather than resolved on demand because **`app/` is the only layer
## that knows who the player is** — no module may hold that, and `MarketApi`'s lot rows name
## actors by id alone. Returns true when every connect was already in place, which is what
## makes a second `install` provably a no-op.
static func install(player: Actor = null) -> bool:
	if player != null:
		_player = player
		_player_id = String(player.id)
	var bus := AuctionEvents.shared()
	var already := true
	if not bus.bid_placed.is_connected(AuctionStanding.on_bid_placed):
		bus.bid_placed.connect(AuctionStanding.on_bid_placed)
		already = false
	if not bus.outbid_in_auction.is_connected(AuctionStanding.on_outbid):
		bus.outbid_in_auction.connect(AuctionStanding.on_outbid)
		already = false
	if not bus.defaulted_on_a_bid.is_connected(AuctionStanding.on_defaulted):
		bus.defaulted_on_a_bid.connect(AuctionStanding.on_defaulted)
		already = false
	if not bus.won_auction.is_connected(AuctionStanding.on_won):
		bus.won_auction.connect(AuctionStanding.on_won)
		already = false
	return already


## The four handlers, as exact static Callables. Public rather than `_`-prefixed because
## `is_connected` compares by Callable and a private name would be equally comparable — but
## these are the named subscriber seam ADR 0093 describes, and a test connects them by name.


## A bid was recorded. **Announced into the trail and credited nothing** — see
## `BID_CAUSE`'s note on why a repeatable click is not an act of standing.
static func on_bid_placed(
	bidder_id: String, lot_id: StringName, amount: int, _required: int
) -> void:
	AuctionLedger.record(
		"bid_placed", {"bidder": bidder_id, "lot_id": String(lot_id), "amount": amount}
	)


## A bidder was displaced. They stay in the settlement walk at their OWN bid (ADR 0102), so
## this is a demotion and not an eviction — and the standing it moves is exactly that:
## a small negative against the person who took the lead, applied ONCE, to the displaced
## bidder only.
static func on_outbid(bidder_id: String, lot_id: StringName, by_id: String, amount: int) -> void:
	AuctionLedger.record(
		"outbid_in_auction",
		{"bidder": bidder_id, "lot_id": String(lot_id), "by": by_id, "amount": amount}
	)
	_credit(bidder_id, by_id, OUTBID_CAUSE)


## A bidder's purse no longer covered their own bid. **A broken promise is the harshest
## thing a bidder can do to a seller**, so this is the one auction cause that is strongly
## negative, and it is negative against the HOUSE rather than against the person they
## outbid: `defaulted_on_a_bid` carries no counterparty, and inventing one would attribute
## a grudge to whoever happened to bid next.
static func on_defaulted(bidder_id: String, lot_id: StringName, amount: int) -> void:
	AuctionLedger.record(
		"defaulted_on_a_bid", {"bidder": bidder_id, "lot_id": String(lot_id), "amount": amount}
	)
	_credit(bidder_id, AuctionLedger.HOUSE_PARTNER, DEFAULTED_CAUSE)


## A lot closed `sold`. **The standing moves to the SELLER**, not to the bidder: the coins
## have already gone to `seller_id` and the goods to `bidder_id` before this fires, so the
## act the world records is a sale the seller made, and `apply_cause(actor, partner_id)` is
## written on the actor who RECEIVED the money.
static func on_won(bidder_id: String, lot_id: StringName, amount: int, seller_id: String) -> void:
	(
		AuctionLedger
		. record(
			"won_auction",
			{
				"bidder": bidder_id,
				"lot_id": String(lot_id),
				"amount": amount,
				"seller": seller_id,
			}
		)
	)
	_credit(seller_id, bidder_id, WON_CAUSE)


# --- internals ---------------------------------------------------------------


## Apply `cause_id` to the bond between `actor_id` and `partner_id`.
##
## ## How an id becomes the `Actor` `apply_cause` demands
##
## The auction ledger names actors by **id** — "a bid is a PROMISE and promises outlive the
## room" (ADR 0102) — so the party may be a counter this process minted, an npc, or the
## player. Resolution is tried in that order and nowhere else:
##
##   1. **A minted shop counter.** `ShopCounter.counter(shop_id)` is the live Actor the
##      counter was realized under, and its id is `shop_<shop_id>` — which is what
##      `MarketApi.list` records as a `seller_id` when an auction house lists through the
##      market. Without this the sale of a shop's goods would credit nobody, because a shop
##      is authored content and has no `NpcDef` to mint from.
##   2. **The tracked roster**, via `NpcApi.resident(npc_id)` — the off-stage mechanism ADR
##      0074 already provides, so an npc the player walked away from is still a subject.
##   3. **The player**, whose id `install` recorded. `app/` is the only layer that knows who
##      the player is, and it is handed the actor by `EconomyBoot.install`.
##
## A participant in none of those is left on the auction ledger, where the money already
## moved. The social ladder is a second ledger, and failing to move it must never move the
## first.
static func _credit(actor_id: String, partner_id: String, cause_id: StringName) -> void:
	if actor_id == "" or partner_id == "" or cause_id == &"":
		return
	if SocialCauseCatalog.instance().cause_definition(cause_id) == null:
		AuctionLedger.refuse(AuctionLedger.UNKNOWN_CAUSE, cause_id, actor_id, partner_id)
		return
	var actor := _body(actor_id)
	if actor == null:
		AuctionLedger.refuse(AuctionLedger.NO_SUBJECT, cause_id, actor_id, partner_id)
		return
	var answered := SocialApi.apply_cause(actor, StringName(partner_id), cause_id)
	if not bool(answered.get("ok", false)):
		AuctionLedger.refuse(
			String(answered.get("reason", "unknown_cause")), cause_id, actor_id, partner_id
		)


## The live `Actor` for `actor_id`, or null when this process holds none.
static func _body(actor_id: String) -> Actor:
	if actor_id.begins_with(ShopCounter.ID_PREFIX):
		return ShopCounter.counter(StringName(actor_id.trim_prefix(ShopCounter.ID_PREFIX)))
	if actor_id == _player_id and _player != null:
		return _player
	var resident := NpcApi.resident(StringName(actor_id))
	if resident != null:
		return resident
	return null


## Whether `actor_id` names a body this process can reach. **A read with no side effect**, so
## a panel can grey an affordance out rather than letting the verb refuse later.
static func can_credit(actor_id: String) -> bool:
	return actor_id != "" and _body(actor_id) != null


## The live `Actor` `actor_id` names, or null — [method _body] as a PUBLIC answer,
## because "whose body is this bidder" is no longer only the social ladder's question.
##
## `MarketApi.settle_lot(winner_actor, bidder_of, lot_id, periods)` walks its settlement
## by asking a resolver to turn each recorded `actor_id` back into a wallet, and `ui/`
## may neither hold that registry nor mint an `Actor` (`app` is the only entry in
## `rules.PRIVATE_UNITS`). The composition root hands the screen a Callable over this,
## so **the body that gets PAID is found by the same lookup that credits the sale** —
## two answers to "who is this bidder" could disagree, and the disagreeing one would be
## the one deciding whose coins leave.
static func body_of(actor_id: String) -> Actor:
	return _body(actor_id)


## Test seam: drop the recorded player and the trail. **Only a harness calls this** — the
## bus is process-wide, and a suite that outbid somebody would otherwise leave a bond
## standing for whichever suite runs next and read a standing that is not its own.
static func reset() -> void:
	_player = null
	_player_id = ""
	AuctionLedger.reset()
