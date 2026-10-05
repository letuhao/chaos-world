class_name AuctionScreen
extends UiScreen

## The auction floor: see every lot, list one of your own, bid on somebody's, and
## close one.
##
## ## Why this screen exists at all
##
## `MarketApi.list`, `MarketApi.bid` and `MarketApi.settle_lot` shipped with ADR 0102's
## whole escrow discipline — a lot freezes one realized price, escrows the instance out
## of the seller's bag, and walks the bids in descending order at close — and
## `AuctionReadModel` published a primitives-only `lot_id / price / required_bid /
## high_bid / high_bid_amount / bid_count / status` row for every lot in the world.
## **No screen ever read any of it.** So who was winning an auction, what a bid had to
## be, and what a lot was frozen at were all computed and invisible, and the only
## caller of the whole escrow verb was a test.
##
## ## The bid arrives as an INJECTED Callable, and that is not optional
##
## `AuctionBids.bid(npc, lot_id, bid_period)` lives in `app/` — and `app` is the only
## entry in `rules.PRIVATE_UNITS` — so `ui/` may neither name the type nor call the
## verb. It is also the only place the bid decision exists at all: it derives
## `AuctionState.bid_ceiling(purse, tags)` from the bidder's appetite tag and refuses
## `auction_ceiling_below_required` when a shallow purse cannot reach a rare lot's
## opening. Re-deriving any of that in `ui/` would be a second price path (ADR 0094).
##
## So [method bind_auction] takes `Callable(bidder, lot_id, period) -> Dictionary`,
## which is `AuctionBids.bid`'s signature verbatim. **Unwired, a bid refuses
## `no_auction_seam` by name** rather than reporting a bid nobody placed.
##
## The SETTLEMENT is the same shape for the same reason, and there are two of its
## arguments rather than one: `MarketApi.settle_lot` needs the `Actor` holding the
## escrow AND a resolver turning a bidder's id back into a live wallet. See
## [method bind_settlement], which is where both are handed over.
##
## The LIST is different and is called BY NAME. `MarketApi` is `market/api.gd` and
## `market` is declared in `rules.UI_MODULES`, so `MarketApi.list` is reachable from
## `ui/` exactly as `HoldingsApi.claim` is on the forage screen — it takes
## `(seller: Actor, instance_id, closes_after_periods)` and every argument is either
## the bound actor or a plain id. **This is the split the whole file turns on**: a verb
## whose arguments `ui/` can produce is called by name; a verb whose arguments require
## an `app/` type is injected.
##
## ## An npc bidder, not a player hand
##
## A lot row's press asks the seam to bid **for this hero** through `AuctionBids.bid`,
## and that verb computes the amount from the bidder's purse and appetite tag rather
## than from a number a button author typed. So the player sees and controls WHETHER
## to bid, and the amount is the auction's own arithmetic — the same rule that makes
## `tests/app/test_auction_bids.gd`'s determinism claims true of a live screen.
##
## ## Time is the PLAYER'S, never a default
##
## DEF-0111: no module in this program owns a clock. `closes_after_periods` is
## required at list time and this screen declares its own step as an authored constant
## rather than as a parameter default on the verb, because a defaulted period is an
## invented tick wearing a button's clothes — and [method act_list] takes it
## explicitly so a caller asking for more periods has to say so.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no actor,
## with each row's own summary nested under that row's key.

## Rows the scene mounts and this screen tops up to. `MarketApi.MAX_OPEN_LOTS` is 16,
## a refused admit rather than a silent trim, so the pool is grown through
## `RowBudget.cap` — the same shape `ForageScreen` uses for nodes.
const LOT_ROWS := 16
const ROW_SCENE := "res://src/ui/panels/auction_lot_row.tscn"
const ACTIONS_SCENE := "res://src/ui/panels/action_set.tscn"
const HEADER_TEXT := "Every lot in the world, and who is winning it."
const NO_ACTOR_TEXT := "No hero bound."
const FOOTER_TEXT := (
	"Up / Down picks a lot, Accept bids on it through the auction's own arithmetic. "
	+ "Cancel returns."
)

## The action ids this screen publishes, in the order the bar shows them. Declared as
## constants rather than built per call so the order a test reads is the order the
## player sees.
const ACTION_BID := &"bid"
const ACTION_LIST := &"list"
const ACTION_SETTLE := &"settle"

## The lot status words, published rather than spelled as literals, because the row
## panel branches on them and a screen that spelled `open` in three places would be
## three places to drift from `AuctionReadModel`.
const STATUS_OPEN := "open"
const STATUS_SOLD := "sold"
const STATUS_UNSOLD := "unsold"

## The refusals this screen raises ITSELF, before a verb is called. Authored constants
## rather than prose, for the same reason the modules author their own: a panel renders
## a reason it did not have to invent.
const NO_ACTOR := "no_actor"
const NO_LOT_PICKED := "no_lot_picked"
## The bid seam is not bound, so the bid the player pressed cannot run. Distinct from
## every module refusal: the amount was named and there is nowhere to send it.
const NO_AUCTION_SEAM := "no_auction_seam"
## The bidder resolver is not bound, so the settlement the player pressed cannot run.
## Distinct from `NO_AUCTION_SEAM` for the same reason `bid` is: the lot is priced, the
## period was named, and the ONE thing missing is a way to reach the bidder — the
## ledger names them by id alone and only `app/` holds live bodies.
const NO_BIDDER_RESOLVER := "no_bidder_resolver"
## The hero escrowed nothing, so there is no instance to list. Distinct from
## `MarketApi.NO_PERIODS`: there is a hero here and a bag, and nothing in it that has
## an authored worth.
const NO_INSTANCE := "no_instance"
## `closes_after_periods <= 0` was asked for. The module owns the rule (`no_periods`);
## this screen refuses by the same name so one id covers the whole path whichever
## layer raised it.
const NO_PERIODS := MarketApi.NO_PERIODS

## The periods one press of the list action keeps a lot open. A single auction window,
## declared here rather than defaulted at the verb: a press says how long this hero
## meant to hold the goods.
const LIST_PERIODS := 3

## The periods one press of the settle action closes a lot by. An authored step a
## player chooses to advance, not a clock: nothing in this program owns time
## (DEF-0111), so a defaulted period here would be an invented tick wearing a button's
## clothes.
const SETTLE_PERIODS := 3

var _header: Label = null
var _footer: Label = null
var _lot_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _lot_rows: Array = []
## The lot the verbs would act on. `""` picks nothing, and each verb then refuses
## `no_lot_picked` by name rather than silently acting on the first row.
var _selected_lot: String = ""
## The bid verb, injected by the composition root. See the class note.
var _bid: Callable = Callable()
## The bidder resolver `MarketApi.settle_lot` walks its settlement with, injected by
## the composition root. `Callable(bidder_id: String) -> Actor`.
var _bidder_of: Callable = Callable()
## The house actor settlement pays into. `MarketApi.settle_lot(winner_actor, ...)`
## takes the shop or seller holding the escrow, and only `app/` knows which `Actor`
## that is — a screen cannot mint one. Null until [method bind_settlement] supplies
## it, and every settle refuses by name rather than reporting a sale nobody ran.
var _house_actor: Actor = null
## The last verb's verdict, carried through verbatim. `{}` before any action, so a test
## reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The read model's lot rows, cached from the last refresh, so a refresh costs exactly
## one facade call however many times `summary()` is asked.
var _views: Array = []


## Inject the bid verb. Called at the route mount by the composition root.
##
## `Callable(bidder, lot_id, bid_period) -> Dictionary`, which is `AuctionBids.bid`'s
## signature verbatim. Safe to call again; the screen repaints from the facade either
## way.
##
## Assigned exactly as given rather than merged into a default, so binding a
## deliberate null clears a previously bound seam — the rule `item_workbench.setup`'s
## save and load callables follow.
func bind_auction(bid: Callable) -> void:
	_bind_nodes()
	_bid = bid
	_refresh_view()
	_render()


## ## The SETTLEMENT seam, and why both halves arrive as Callables
##
## `MarketApi.settle_lot(winner_actor, bidder_of, lot_id, periods)` is the verb that
## closes a lot, and it is the one that shipped with **no caller outside a test** — so a
## won lot stayed `open` forever and a page of bids could never end. It takes two
## arguments a screen cannot produce:
##
##  - `winner_actor`, the shop or seller holding the ESCROW. `MarketApi.list` removed
##    the instance from that actor's bag at list time, and only `app/` knows which
##    `Actor` it was — `ShopCounter` mints the counters, `ActorFactory` mints actors,
##    and `app` is the only entry in `rules.PRIVATE_UNITS`.
##  - `bidder_of`, the RESOLVER. A lot records bids as a plain `actor_id` string —
##    "a bid is a PROMISE and promises outlive the room" (ADR 0102) — so settlement has
##    to turn an id back into a live wallet at the moment it pays. Only the composition
##    root holds that registry (`AuctionStanding._body` is the shipped instance of
##    exactly this resolution), so the resolver is handed over rather than rebuilt.
##
## So [method bind_settlement] takes `Callable(bidder_id: String) -> Actor` and the
## `Actor` to pay, and **unwired the verb refuses `no_bidder_resolver` by name** rather
## than reporting a settlement nobody ran.
##
## Safe to call again; the screen repaints from the facade either way.
func bind_settlement(bidder_of: Callable, house_actor: Actor) -> void:
	_bind_nodes()
	_bidder_of = bidder_of
	_house_actor = house_actor
	_refresh_view()
	_render()


## Whether the bid seam is bound. Published by `summary()` so a probe can tell
## "this screen cannot bid" from "this screen has nothing to bid on", which are
## different sentences and both reachable.
func auction_wired() -> bool:
	return _bid.is_valid()


## Whether settlement can run. Both halves of the seam, because a resolver with no
## house has nobody to pay and a house with no resolver cannot reach the winner.
func settlement_wired() -> bool:
	return _bidder_of.is_valid() and _house_actor != null


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var rows := _row_summaries()
	var picked := _picked_view()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		"auction_wired": auction_wired(),
		"settlement_wired": settlement_wired(),
		# The one facade call this screen makes by bare name, for the purse and the
		# world's lot tally. `market` is declared in `rules.UI_MODULES`, so this is
		# exactly the reach `ForageScreen` has on `HoldingsApi`.
		"purse": int(MarketApi.summary(_actor).get("purse", 0)),
		"lot_count": rows.size(),
		"lot_ids": _lot_ids(rows),
		"open_count": _count_where(rows, "open"),
		"settled_count": _count_where(rows, "sold") + _count_where(rows, "unsold"),
		"bidding_count": _count_where(rows, "can_bid"),
		"mine_count": _count_where(rows, "mine"),
		"selected_lot": _selected_lot,
		"selected_open": bool(picked.get("open", false)),
		"selected_mine": bool(picked.get("mine", false)),
		"selected_can_bid": bool(picked.get("can_bid", false)),
		# The last verb's verdict as primitives. `last_reason` is the module's own named
		# constant, so one run tells a placed bid from a refused one from a missing
		# seam — the refusals that would otherwise all read as "nothing happened".
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"last_reason": String(_last_result.get("reason", "")),
		"last_lot": String(_last_result.get("lot_id", "")),
		"last_amount": int(_last_result.get("amount", 0)),
		"last_required": int(_last_result.get("required", 0)),
		# The settlement's OWN two sentences, because `sell` and `sell failed` differ by
		# nothing a caller could otherwise read: both return `ok: true`.
		"last_status": String(_last_result.get("status", "")),
		"last_winner": String(_last_result.get("winner", "")),
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# Each row's own summary, nested under that row's key so a test reads the lot
		# without walking the widget tree.
		"rows": rows,
	}


# --- Actions. One calls the facade, one calls the seam -----------------------


## Bid on the picked lot, or `lot_id` when one is named, through the injected seam.
## Returns the seam's verdict unchanged, so a caller never has to read the message line
## to learn what happened.
##
## ## The amount is the AUCTION'S, not a parameter here
##
## `AuctionBids.bid` computes it from `AuctionState.bid_ceiling(purse, tags)` clamped to
## the required bid, and refuses `auction_ceiling_below_required` when a shallow purse
## cannot reach a rare lot's opening — which is the whole "rare items attract powerful
## cultivators" claim, and it is arithmetic rather than a simulation. This screen takes
## no amount at all: a player chooses WHETHER to bid, and the ledger records what the
## auction decided.
##
## `bid_period` is [constant LIST_PERIODS]'s sibling, not the clock: it is stamped on the
## bid row so a ledger read later can say which window the bid was made in. Time itself
## is the caller's (DEF-0111).
func act_bid(lot_id: String = "", bid_period: int = 0) -> Dictionary:
	_bind_nodes()
	var wanted := lot_id if lot_id != "" else _selected_lot
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_LOT_PICKED)
	if not auction_wired():
		return _verdict(NO_AUCTION_SEAM)
	return _settle(_bid.call(_actor, StringName(wanted), bid_period) as Dictionary)


## Escrow `instance_id` of the bound hero into a lot that closes after `periods`.
## Returns `MarketApi.list`'s verdict.
##
## Called BY NAME, and this is the asymmetry the class note is about: `market` is a
## declared `UI_MODULES` grant, so `MarketApi.list(seller, instance_id, periods)` is
## reachable from `ui/` exactly as `HoldingsApi.claim` is on the forage screen — every
## argument is either the bound actor or a plain id, and none of them is an `app/` type.
func act_list(instance_id: String, periods: int = LIST_PERIODS) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if periods <= 0:
		return _verdict(NO_PERIODS)
	if instance_id == "":
		return _verdict(NO_INSTANCE)
	return _settle(MarketApi.list(_actor, StringName(instance_id), periods))


## Close the picked lot, or the lot named by `lot_id`, by `periods`, and pay the
## outcome. Returns `MarketApi.settle_lot`'s verdict, which carries `status`,
## `winner` and `amount` — so a caller learns whether the lot SOLD or went UNSOLD
## rather than reading a bare `ok: true` that both share.
##
## ## The one verb that makes an auction an AUCTION
##
## `bid` makes a promise; this keeps it. A lot could be listed and bid on forever,
## because `settle_lot` shipped with ADR 0102 and had no caller outside a test — so a
## won lot stayed `open` and its escrow stayed in limbo. Both of this verb's extra
## arguments arrive through [method bind_settlement] and for the same reason: the
## module records bidders as ids, and only `app/` holds the live bodies and knows
## which `Actor` holds the escrow.
##
## `periods` is this caller's, exactly as it is for `bid`'s `bid_period` (DEF-0111).
## `MarketApi.settle_lot` refuses `lot_not_due` while `periods < closes_after`, so a
## press too early is a NAMED refusal rather than a settlement nobody earned.
func act_settle(lot_id: String = "", periods: int = SETTLE_PERIODS) -> Dictionary:
	_bind_nodes()
	var wanted := lot_id if lot_id != "" else _selected_lot
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_LOT_PICKED)
	if periods <= 0:
		return _verdict(NO_PERIODS)
	if not settlement_wired():
		return _verdict(NO_BIDDER_RESOLVER)
	return _settle(MarketApi.settle_lot(_house_actor, _bidder_of, StringName(wanted), periods))


## Pick the lot the verbs would act on. Returns false for an id this screen is not
## showing, so a caller never "selects" a lot that does not exist here, and clears the
## selection rather than leaving a stale one behind.
func select_lot(lot_id: String) -> bool:
	_bind_nodes()
	if lot_id == "":
		_selected_lot = ""
	elif _lot_ids(_row_summaries()).has(lot_id):
		_selected_lot = lot_id
	else:
		return false
	_render()
	return true


## The lot ids this screen is showing, in display order — the list `ui_up` / `ui_down`
## walk. Read off the rows rather than off the facade, so what the player can pick is
## exactly what they can see.
func lot_ids() -> Array:
	_bind_nodes()
	return _lot_ids(_row_summaries())


## The hero's own escrowed instance ids, in bag order, as a read of the bag through
## `ItemsApi` — `items` carries an EMPTY grant in `rules.UI_MODULES`, so naming its
## facade is exactly as legal here as `HoldingsApi` is on the forage screen. A player
## lists a lot by pressing the action with this many instances to choose from.
##
## ## Why an INSTANCE and never a def id
##
## `MarketApi.list` escrows by `remove_instance`, and `Inventory._roll_instance` calls
## `rng.randomize()` while `EconomyExchange._plan` prices off `inventory.sample(def_id)`
## — the FIRST matching stack. A def-id listing would let a seller list a common roll
## and deliver a legendary one at the frozen low price, which is the inflation ADR 0094
## closed for base worth. So the published surface is instances, and this is the read
## that lets a caller name one.
func listable_instance_ids() -> Array:
	_bind_nodes()
	var out: Array = []
	if _actor == null:
		return out
	var inventory := ItemsApi.inventory(_actor)
	if inventory == null:
		return out
	for instance in inventory.instances():
		out.append(String(instance.instance_id))
	return out


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first LIVE control in the action row, because this screen
## does something and the control a player can press is the one the keyboard must land
## on. Recorded first, because a lot outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before


## `ui_accept` fires the bid the picked lot's own state makes the primary one, and
## `ui_up` / `ui_down` walk the picked list. Each is CONSUMED only when it did
## something, so `ui_cancel` stays free for `ScreenStack` to pop exactly as it pops
## every other screen: a screen that could bid and also swallowed the cancel would
## trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked, for the reason
## `ForageScreen.on_stack_input` gives: a screen that declines an unbound event by
## DECLARING it declined is exactly the contract `ScreenStack` relies on.
func on_stack_input(event: InputEvent) -> bool:
	if _actor == null or event == null or not _bound:
		return false
	if not event.is_pressed() or event.is_echo() or event.is_action_pressed(&"ui_cancel"):
		return false
	if event.is_action_pressed(&"ui_accept"):
		return _accept()
	if event.is_action_pressed(&"ui_down"):
		return _step(1)
	if event.is_action_pressed(&"ui_up"):
		return _step(-1)
	return false


# --- Plumbing ---------------------------------------------------------------


## Re-read the facade — the ONE call this screen makes per refresh — and hand raw values
## down. Every later read is of the cached `_views`, never of the facade, so a refresh
## costs exactly one call however many times `summary()` is asked. The rows own every
## format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	_views = (MarketApi.summary(_actor).get("lots", []) as Array if _actor != null else [])
	_fill_from_views()


func _fill_from_views() -> void:
	if _lot_rows.is_empty():
		return
	# Snapshot the bound BEFORE the pool grows: `needed` is a content-derived count and
	# a grow loop that re-reads it is the shape `RowBudget` exists to close.
	var needed: int = _views.size()
	var target := RowBudget.cap(needed)
	while _lot_rows.size() < target:
		var row := load(ROW_SCENE).instantiate() as Control
		row.name = "Lot%d" % _lot_rows.size()
		_lot_box.add_child(row)
		_lot_rows.append(row)
	var index := 0
	while index < _lot_rows.size():
		var view: Dictionary = _views[index] as Dictionary if index < _views.size() else {}
		(_lot_rows[index] as AuctionLotRow).show_lot(_publishable(view))
		index += 1
	# A selection that fell off the end of the list is CLEARED rather than left stale:
	# a pick naming a lot this screen is no longer showing would act on nothing.
	if not _lot_ids(_row_summaries()).has(_selected_lot):
		_selected_lot = ""


## The lot as this screen publishes it: `AuctionReadModel`'s primitives with the two
## facts only this screen can know folded in — whether the lot is MINE (a bare
## `seller_id` string compared against the bound actor's id, never a `ShopDef` or an
## `Actor` the screen may not hold), and whether the bid would reach the required
## amount.
##
## ## `can_bid` is `required_bid <= purse`, and that is the WHOLE of the player's side
##
## `AuctionState.bid_ceiling(purse, tags)` scales the purse by the bidder's authored
## appetite — 30 for an `opportunist`, 45 for a `thrifty`, 90 for a `collector` — and
## that number is `app/`'s to compute, because the tag table is read off `Actor.tags`
## and the verb lives there. So the row answers the half a panel can answer on its own
## ("could this hero reach the opening at all?") and the seam answers the rest. A row
## that is live where the verb refuses `auction_ceiling_below_required` is the "looks
## alive and is dead" shape, so the two halves are reported separately in
## `summary()` rather than collapsed into one boolean.
func _publishable(view: Dictionary) -> Dictionary:
	if view.is_empty():
		return {}
	var out := view.duplicate(true)
	out["mine"] = (_actor != null and String(view.get("seller_id", "")) == String(_actor.id))
	out["can_bid"] = _affords(out)
	return out


## Whether the bound hero's purse reaches a lot's required bid. A read of two
## primitives the ledger and the facade already hold, never a re-derivation: the price
## is `required_bid` and the money is `EconomyApi.purse` inside `MarketApi.summary`.
func _affords(view: Dictionary) -> bool:
	if _actor == null:
		return false
	var purse := int(MarketApi.summary(_actor).get("purse", 0))
	return purse >= int(view.get("required_bid", 0))


func _bind_nodes() -> void:
	super()
	if _header != null:
		return
	_header = get_node_or_null("%HeaderLabel") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_lot_box = get_node_or_null("Layout/Scroll/Lots") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _lot_box != null
	if not _bound:
		return
	_lot_rows = _rows_in(_lot_box, LOT_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares
## it, because a headless test may instantiate this screen's script against a scene
## that predates the action row; the ACTIONS are then unreachable and every bid
## reports `no_auction_seam` rather than pretending to have fired.
##
## The guard is what makes "one handler per connection" a fact rather than an accident
## of the `_bind_nodes` early return: the moment anything calls this a second time, an
## unguarded `connect` would duplicate silently.
func _connect_actions() -> void:
	if _actions == null:
		return
	if not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)


## The rows the scene declares, in order, then enough grown rows to reach `extra`. A
## pool smaller than `extra` would have to truncate the data the next refresh brings,
## so the mounted rows are topped up here rather than left to `_fill_from_views`.
func _rows_in(box: VBoxContainer, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and row.has_method(&"show_lot"):
			out.append(row)
	for index in range(extra):
		var row := load(ROW_SCENE).instantiate() as Control
		row.name = "Lot%d" % out.size()
		box.add_child(row)
		out.append(row)
	return out


func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = ""
		_publish_actions()
		return
	_header.text = HEADER_TEXT
	_footer.text = FOOTER_TEXT
	_publish_actions()


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line, so the screen formats no
## number and no sentence.
##
## `bid` needs the seam AND a picked lot that is open, not the hero's own, and whose
## required bid the hero's purse reaches — because `MarketApi.bid` refuses
## `lot_not_open`, `seller_is_bidder` and `bid_too_low`, and a control that is live
## where the verb refuses is the "looks alive and is dead" shape. `list` needs a hero
## holding an instance at all: `MarketApi.list` refuses `not_carried` for a bag with
## nothing escrowable in it, and the refusal is better rendered than pre-judged.
## `settle` needs the settlement seam AND a picked lot that is still open, because
## `MarketApi.settle_lot` refuses `lot_not_open` for a lot already closed and
## `lot_not_due` for one whose window has not elapsed — so a control live there would
## refuse on every press.
func _publish_actions() -> void:
	if _actions == null:
		return
	var picked := _picked_view()
	(
		_actions
		. set_state(
			{
				"actions": _action_ids(),
				"labels":
				{
					ACTION_BID: "Bid on the picked lot",
					ACTION_LIST: "List one of your goods for auction",
					ACTION_SETTLE: "Close the picked lot and pay the winner",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_BID if bool(picked.get("can_bid", false)) else ACTION_LIST,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so
## the order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [String(ACTION_BID), String(ACTION_LIST), String(ACTION_SETTLE)]


## Which of the three is live right now.
func _enabled_actions() -> Dictionary:
	var picked := _picked_view()
	return {
		String(ACTION_BID):
		(
			_actor != null
			and _selected_lot != ""
			and bool(picked.get("open", false))
			and not bool(picked.get("mine", false))
			and bool(picked.get("can_bid", false))
		),
		String(ACTION_LIST): _actor != null and not listable_instance_ids().is_empty(),
		String(ACTION_SETTLE):
		(
			_actor != null
			and settlement_wired()
			and _selected_lot != ""
			and bool(picked.get("open", false))
		),
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled
## action, so this cannot fire a verb the control does not offer.
##
## `list` takes the hero's FIRST escrowable instance and
## [constant LIST_PERIODS] — the authored window — rather than a quantity a button
## author typed, so a retune of the window is one constant and not a search.
## `settle` takes [constant SETTLE_PERIODS] for the same reason.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_BID:
			act_bid()
		ACTION_LIST:
			var instances := listable_instance_ids()
			if not instances.is_empty():
				act_list(String(instances[0]), LIST_PERIODS)
		ACTION_SETTLE:
			act_settle("", SETTLE_PERIODS)


## `ui_accept` on the screen: bid on the picked lot when it can be bid on, and decline
## otherwise. Declared in one place because two consumers (`on_stack_input` and the
## action bar) must agree on which verb a press means.
##
## **`ui_accept` does NOT settle**, and that is a deliberate half rather than a gap: a
## single accept that bid when it could and settled when it could not would pay out an
## auction on the same key that opens one. Settlement is a deliberate, separately
## labelled action, and the bar is where a player commits to it.
func _accept() -> bool:
	if not auction_wired() or _selected_lot == "":
		return false
	if not bool(_picked_view().get("can_bid", false)):
		return false
	act_bid()
	return true


## Move the pick `step` entries along the shown list, wrapping. Returns false when
## there is nothing to pick, so `ui_down` on an empty board is declined rather than
## consumed — a screen that swallows a key it cannot honour is a screen that has
## swallowed the player's cancel by association.
func _step(step: int) -> bool:
	var ids := _lot_ids(_row_summaries())
	if ids.is_empty():
		return false
	var index := ids.find(_selected_lot)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	_selected_lot = String(ids[posmod(index + step, ids.size())])
	_render()
	return true


## A refusal this screen raises ITSELF, in the module's own `{ok, reason}` shape. Never
## a silent no-op: an action a player asked for that did not happen is reported in the
## same vocabulary the modules use, so one renderer covers both.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary. The screen
## never rewrites it, so `last_result` is the module's answer and a test can compare it
## against `AuctionBids` directly.
##
## The repaint happens AFTER the verdict is recorded, so the rows the player sees are
## the ones the verdict describes: a refused bid writes nothing (`AuctionBids.bid`'s
## `ceiling_below_required` has no ledger row, no write and no event), so the high
## bidder behind it is byte-for-byte as found, and painting the refusal over it is what
## makes "the world did not change, and here is why" legible on one line.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = result.duplicate(true)
	if bool(_last_result.get("ok", false)):
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		# The reason VERBATIM. Not "Rejected: seller_is_bidder", not a sentence this
		# screen composed: the module authored the constant and a panel that reworded it
		# would be describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## Every mounted row's own summary, in display order. A spare pool row reports `{}`,
## which is what makes the reported count the world's lot count rather than the size of
## the pool the scene happened to mount.
func _row_summaries() -> Array:
	var out: Array = []
	for row in _lot_rows:
		var filled: Dictionary = (row as AuctionLotRow).summary()
		if filled.is_empty():
			continue
		out.append(filled)
	return out


## The lot row for the current pick, or `{}` when nothing is picked. The picked row's
## OWN summary rather than a facade re-read, so the action bar's enabled state and the
## lot row on screen can never describe two different worlds.
func _picked_view() -> Dictionary:
	if _selected_lot == "":
		return {}
	for filled in _row_summaries():
		if String((filled as Dictionary).get("lot_id", "")) == _selected_lot:
			return filled as Dictionary
	return {}


func _lot_ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String((row as Dictionary).get("lot_id", "")))
	return out


func _count_where(rows: Array, key: String) -> int:
	var total := 0
	for row in rows:
		if bool((row as Dictionary).get(key, false)):
			total += 1
	return total
