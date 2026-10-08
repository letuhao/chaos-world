class_name MarketScreen
extends UiScreen

## The shop surface: see the stalls at a location, read their priced shelves, and buy
## or sell.
##
## ## Why this screen exists at all
##
## `ShopCounter` shipped the whole priced read model — `summary(shop_id)`,
## `at_location(location_id, player)`, a shelf priced by the ONE reader
## `MarketTransfer.quote` also settles through, and a `can_buy` per shop — and **no
## screen ever asked for it**. `ShopCounter.at_location`'s own docstring calls itself
## "the door a caller actually walks through", and before this screen nothing did: a
## shop was authored content a catalog could read and a player could never meet.
## `MarketApi.buy` and `sell` both take a `shop_actor: Actor`, and the only thing
## that can mint one is `ShopCounter`, an `app/` type — so the verbs had no argument a
## screen could produce, which is DEF-0218's whole shape.
##
## ## Everything reaches this screen as an INJECTED Callable
##
## `market` IS declared in `rules.UI_MODULES` (as `"market": ["economy"]`), so this
## screen may name `MarketApi` by bare name and reach `MarketApi.summary` for the
## purse, the spread and the lot tally — exactly as `ForageScreen` calls
## `HoldingsApi.claim`. The `economy` in that grant is the MODULE graph edge
## (`market -> economy` in `registry.json`); it is **not** a grant of `economy` to
## `ui/`, because `tools/arch/enforce.py` checks `dep in rules.UI_MODULES` — and
## `economy` has no key there. So this screen may not name `EconomyApi`.
##
## That leaves the two things `ui/` genuinely cannot reach, and both arrive on the
## same ADR 0143 seam `ForageScreen.bind_harvest` uses:
##
##  - **the priced read model.** `ShopCounter` is `app/`, and `PRIVATE_UNITS` is
##    `frozenset({"app"})`, so the screen may neither name the type nor call
##    `ShopCounter.at_location` through it.
##  - **the verbs.** `MarketApi.buy(shop_actor, player, rows)` needs a shop `Actor`.
##    A screen cannot mint an `Actor` at all (`app/` owns `ActorFactory`), and the
##    counter is cached per shop id precisely so the goods LEAVE it — a screen that
##    minted its own would hand every caller a full shelf and make the spread
##    testable but the game nonsense.
##
## So [method bind_market] takes one callable answering
## `read(location_id, player) -> Dictionary` (`ShopCounter.at_location`'s signature
## verbatim) and one answering `buy(shop_id, player, rows) -> Dictionary` /
## `sell(shop_id, player, rows) -> Dictionary`. **Unwired, the verbs refuse
## `no_market_seam` by name** rather than reporting a purchase nobody ran.
##
## ## The location is a FACT, not a filter this screen invents
##
## `ShopDef.location_id` is authored content that differentiates a travelling
## merchant without a second price formula, and `ShopCatalog.at_location` is the ONE
## answer to "which shops are in this room". A screen that listed every authored shop
## would make a caravan trade everywhere and would be exactly the ADR 0100 failure the
## catalog's own docstring names. The location therefore arrives through
## [method at_location], and it defaults to nothing rather than to a guess.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no actor,
## with each row's own summary nested under that row's key.

## Rows the scene mounts and this screen tops up to. Five shops are authored today and
## a pool that dropped one would read as dead content, so the pool is grown through
## `RowBudget.cap` rather than truncated — the same shape `ForageScreen` uses for
## nodes.
const SHOP_ROWS := 5
const ROW_SCENE := "res://src/ui/panels/market_row.tscn"
const ACTIONS_SCENE := "res://src/ui/panels/action_set.tscn"
const HEADER_TEXT := "LOC_UI_SCREENS_114BA7455A"
const NO_ACTOR_TEXT := "LOC_UI_SCREENS_6E9BC19A74"
const FOOTER_TEXT := "LOC_UI_SCREENS_CE52F50F36" + "LOC_UI_SCREENS_6A41F1E6E5"

## The action ids this screen publishes, in the order the bar shows them. Declared as
## constants rather than built per call so the order a test reads is the order the
## player sees.
const ACTION_BUY := &"buy"
const ACTION_SELL := &"sell"

## The refusals this screen raises ITSELF, before a verb is called. Authored constants
## rather than prose, for the same reason the modules author their own: a panel renders
## a reason it did not have to invent.
const NO_ACTOR := "no_actor"
const NO_SHOP_PICKED := "no_shop_picked"
## No location has been named, so "which shops are here" has no answer. Distinct from
## `no_market_seam`: there is a room to look in and nobody to read it.
const NO_LOCATION := "no_location"
## The market seam is not bound, so the buy or sell the player pressed cannot run.
## Distinct from every module refusal: the shelf was priced and there is nowhere to
## send the trade.
const NO_MARKET_SEAM := "no_market_seam"

## The floor is deliberately NOT on this surface. `MarketApi.settle(location, periods)`
## ages a dropped lot and no module in this program owns a clock (DEF-0111), so a
## "tidy the floor" button would need a period this screen cannot invent. It is named
## here so the omission is a decision rather than an oversight.

var _header: Label = null
var _footer: Label = null
var _shop_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _shop_rows: Array = []
## The stall the verbs would act on. `""` picks nothing, and each verb then refuses
## `no_shop_picked` by name rather than silently acting on the first row.
var _selected_shop: String = ""
## The location whose stalls this screen is showing. Set through [method at_location]
## rather than defaulted at a verb, because `ShopDef.location_id` is authored content
## and a defaulted location would be a caravan that trades everywhere.
var _location_id: StringName = &""
## The priced read model, injected by the composition root. See the class note.
var _read: Callable = Callable()
## The buy verb, injected. `Callable(shop_id, player, rows) -> Dictionary`.
var _buy: Callable = Callable()
## The sell verb, injected. `Callable(shop_id, player, rows) -> Dictionary`.
var _sell: Callable = Callable()
## The last verb's verdict, carried through verbatim. `{}` before any action, so a test
## reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The seam's answer for the picked location, cached from the last refresh so a
## refresh costs exactly one seam call however many times `summary()` is asked. A
## DICTIONARY, because `ShopCounter.at_location` answers `{location_id, shops,
## shop_count}` and narrowing it to an array here would drop the count the row list is
## checked against.
var _views: Dictionary = {}


## Inject the market seams. Called at the route mount by the composition root.
##
## `read` is `Callable(location_id, player) -> Dictionary`, which is
## `ShopCounter.at_location`'s signature verbatim. `buy` and `sell` are
## `Callable(shop_id, player, rows) -> Dictionary` — the shop id, never a `ShopDef` or
## an `Actor`, because this program may name neither. Safe to call again; the screen
## repaints from the seam either way.
##
## Assigned exactly as given rather than merged into a default, so binding a
## deliberate null clears a previously bound seam — the rule
## `item_workbench.setup`'s save and load callables follow.
func bind_market(read: Callable, buy: Callable, sell: Callable) -> void:
	_bind_nodes()
	_read = read
	_buy = buy
	_sell = sell
	_refresh_view()
	_render()


## Whether the market seam is bound. Published by `summary()` so a probe can tell
## "this screen cannot trade" from "this screen has nothing to trade", which are
## different sentences and both reachable.
func market_wired() -> bool:
	return _read.is_valid() and _buy.is_valid() and _sell.is_valid()


## Show the stalls at `location_id`. The location is the ONE fact the caller has that
## this screen cannot read for itself, and it is content rather than a rule.
##
## A `null` or empty location clears the board and leaves the verbs refusing
## `no_location`, which is a different sentence from "no stalls here": the first says
## nobody said where to look, the second says the room is empty.
func at_location(location_id: StringName) -> void:
	_bind_nodes()
	_location_id = location_id
	refresh()


## The location this screen is showing.
func location_id() -> StringName:
	return _location_id


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var rows := _row_summaries()
	var picked := _picked_view()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		"location_id": String(_location_id),
		"located": _location_id != &"",
		"market_wired": market_wired(),
		# The purse, read from `MarketApi.summary` by bare name: `market` is declared in
		# `rules.UI_MODULES`, so this is the one call the screen may make itself.
		"purse": int(MarketApi.summary(_actor).get("purse", 0)),
		"shop_count": rows.size(),
		"shop_ids": _shop_ids(rows),
		"buyable_count": _count_where(rows, "can_buy"),
		"selected_shop": _selected_shop,
		"selected_can_buy": bool(picked.get("can_buy", false)),
		"selected_realized": bool(picked.get("realized", false)),
		# The last verb's verdict as primitives. `last_reason` is the module's own named
		# constant, so one run tells a paid purchase from a refused one from a missing
		# seam — the refusals that would otherwise all read as "nothing happened".
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"last_reason": String(_last_result.get("reason", "")),
		"last_shop": String(_last_result.get("shop_id", "")),
		"last_coins": int(_last_result.get("coins", 0)),
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# Each row's own summary, nested under that row's key so a test reads the stall
		# without walking the widget tree.
		"rows": rows,
	}


# --- Actions. Each calls the seam, and reports what came back ----------------


## Buy the cheapest thing on the picked stall, or `def_id` when one is named.
## Returns the trade's own verdict unchanged, so a caller never has to read the
## message line to learn what happened.
##
## `def_id` empty means "the cheapest line on the shelf", which is the row's own
## cheapest figure rather than a price this screen re-derives — so what is bought is
## always something the panel showed the player as affordable.
func act_buy(def_id: String = "") -> Dictionary:
	_bind_nodes()
	# The pick decides the stall; `def_id` is consulted only for WHICH shelf line the
	# buy takes, and an empty one means the cheapest — so there is one rule and no
	# second way to name a stall this screen is not showing.
	# Each branch writes the SAME variable and the function returns it once, so the
	# gate order below is the refusal order a caller reads, with no early exit able
	# to skip a later check.
	var verdict: Dictionary = {}
	if _actor == null:
		verdict = _verdict(NO_ACTOR)
	elif not market_wired():
		verdict = _verdict(NO_MARKET_SEAM)
	elif _location_id == &"":
		verdict = _verdict(NO_LOCATION)
	elif _selected_shop == "":
		verdict = _verdict(NO_SHOP_PICKED)
	else:
		var wanted := _selected_shop
		var shelf := _shelf_for(wanted)
		if shelf.is_empty():
			verdict = _verdict(NO_SHOP_PICKED)
		else:
			var row: Dictionary = _line(shelf, def_id) as Dictionary
			if row.is_empty():
				verdict = _verdict(NO_SHOP_PICKED)
			else:
				var bought := _buy.call(StringName(wanted), _actor, [row]) as Dictionary
				verdict = _settle(_decorate(bought, wanted))
	return verdict


## Sell `quantity` of `def_id` back to the picked stall, or the cheapest thing on it
## when no def is named. Returns the trade's own verdict.
##
## `MarketApi.sell` refuses `shop_will_not_buy` for a def outside the shop's authored
## `buys` list — which is how a black market is authored rather than priced — so the
## refusal is passed through by name and the row says `buys nothing` before the press.
func act_sell(def_id: String = "", quantity: int = 1) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if not market_wired():
		return _verdict(NO_MARKET_SEAM)
	if _location_id == &"":
		return _verdict(NO_LOCATION)
	var wanted := _selected_shop
	if wanted == "":
		return _verdict(NO_SHOP_PICKED)
	var rows := _rows_to_sell(wanted, def_id, quantity)
	if rows.is_empty():
		return _verdict(NO_SHOP_PICKED)
	var sold := _sell.call(StringName(wanted), _actor, rows) as Dictionary
	return _settle(_decorate(sold, wanted))


## Pick the stall the verbs would act on. Returns false for an id this screen is not
## showing, so a caller never "selects" a stall that does not exist here, and clears
## the selection rather than leaving a stale one behind.
func select_shop(shop_id: String) -> bool:
	_bind_nodes()
	if shop_id == "":
		_selected_shop = ""
	elif _shop_ids(_row_summaries()).has(shop_id):
		_selected_shop = shop_id
	else:
		return false
	_render()
	return true


## The shop ids this screen is showing, in display order — the list `ui_up` / `ui_down`
## walk. Read off the rows rather than off the seam, so what the player can pick is
## exactly what they can see.
func shop_ids() -> Array:
	_bind_nodes()
	return _shop_ids(_row_summaries())


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first LIVE control in the action row, because this screen
## does something and the control a player can press is the one the keyboard must land
## on. Recorded first, because a stall outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before


## `ui_accept` fires the buy the picked stall's own state makes the primary one, and
## `ui_up` / `ui_down` walk the picked list. Each is CONSUMED only when it did
## something, so `ui_cancel` stays free for `ScreenStack` to pop exactly as it pops
## every other screen: a screen that could buy and also swallowed the cancel would
## trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked, for the
## reason `ForageScreen.on_stack_input` gives: a screen that declines an unbound event
## by DECLARING it declined is exactly the contract `ScreenStack` relies on.
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


## Re-read the seam — the ONE call this screen makes per refresh — and hand raw values
## down. Every later read is of the cached `_views`, never of the seam, so a refresh
## costs exactly one call however many times `summary()` is asked. The rows own every
## format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	_views = _read.call(_location_id, _actor) as Dictionary if market_wired() else {}
	_fill_from_views()


func _fill_from_views() -> void:
	if _shop_rows.is_empty():
		return
	# Snapshot the bound BEFORE the pool grows: `needed` is a content-derived count and
	# a grow loop that re-reads it is the shape `RowBudget` exists to close.
	var shops := _views.get("shops", []) as Array
	var target := RowBudget.cap(shops.size())
	while _shop_rows.size() < target:
		var row := load(ROW_SCENE).instantiate() as Control
		row.name = "Shop%d" % _shop_rows.size()
		_shop_box.add_child(row)
		_shop_rows.append(row)
	var index := 0
	while index < _shop_rows.size():
		var view: Dictionary = shops[index] as Dictionary if index < shops.size() else {}
		(_shop_rows[index] as MarketRow).show_shop(_publishable(view))
		index += 1
	# A selection that fell off the end of the list is CLEARED rather than left stale:
	# a pick naming a stall this screen is no longer showing would act on nothing.
	if not _shop_ids(_row_summaries()).has(_selected_shop):
		_selected_shop = ""


## The stall as this screen publishes it: the counter's read model, flattened onto the
## keys `MarketRow` renders, with `display_name` / `kind` / `buys` lifted out of the
## def view rather than read from a `ShopDef` — `ui/` may not name that type.
##
## The whole dictionary is primitives by the time it reaches here: `ShopCounter.summary`
## publishes `definition` as `ShopDef.to_dict`, and `to_dict` is primitives, so the
## nested lift is a copy rather than a walk into a resource.
func _publishable(view: Dictionary) -> Dictionary:
	if view.is_empty():
		return {}
	var definition := view.get("definition", {}) as Dictionary
	var out := {
		"shop_id": String(view.get("shop_id", "")),
		"display_name": String(definition.get("display_name", "")),
		"kind": String(definition.get("kind", "")),
		"location_id": String(definition.get("location_id", "")),
		"buys": definition.get("buys", []),
		"ok": bool(view.get("ok", false)),
		"can_buy": bool(view.get("can_buy", false)),
		"shelf": view.get("shelf", []),
		"purse": int(view.get("purse", 0)),
		"funding": int(view.get("funding", 0)),
	}
	return out


func _bind_nodes() -> void:
	super()
	if _header != null:
		return
	_header = get_node_or_null("%HeaderLabel") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_shop_box = get_node_or_null("Layout/Scroll/Shops") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _shop_box != null
	if not _bound:
		return
	_shop_rows = _rows_in(_shop_box, SHOP_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares
## it, because a headless test may instantiate this screen's script against a scene
## that predates the action row; the ACTIONS are then unreachable and every verb
## reports `no_market_seam` rather than pretending to have fired.
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
		if row != null and row.has_method(&"show_shop"):
			out.append(row)
	for index in range(extra):
		var row := load(ROW_SCENE).instantiate() as Control
		row.name = "Shop%d" % out.size()
		box.add_child(row)
		out.append(row)
	return out


func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = L.t(NO_ACTOR_TEXT)
		_footer.text = ""
		_publish_actions()
		return
	_header.text = L.t(HEADER_TEXT)
	_footer.text = L.t(FOOTER_TEXT)
	_publish_actions()


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line, so the screen formats no
## number and no sentence.
##
## `buy` needs the seam AND a picked stall the hero can afford, because
## `ShopCounter._can_afford` compares the purse to the cheapest `sell_total` — the
## whole count, not one unit — and a cheaper unit price on a dearer row is not
## affordability. `sell` needs the seam and a picked stall: whether the hero's def is
## on that stall's `buys` list is the MODULE's rule (`shop_will_not_buy`) and this
## screen does not re-derive authored content.
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
					ACTION_BUY: "Buy the cheapest thing here",
					ACTION_SELL: "Sell back to this stall",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_BUY if bool(picked.get("can_buy", false)) else ACTION_SELL,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so
## the order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [String(ACTION_BUY), String(ACTION_SELL)]


## Which of the two is live right now.
func _enabled_actions() -> Dictionary:
	var picked := _picked_view()
	return {
		String(ACTION_BUY):
		(
			_actor != null
			and _selected_shop != ""
			and bool(picked.get("ok", false))
			and bool(picked.get("can_buy", false))
		),
		String(ACTION_SELL): _actor != null and _selected_shop != "",
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled
## action, so this cannot fire a verb the control does not offer.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_BUY:
			act_buy()
		ACTION_SELL:
			act_sell()


## `ui_accept` on the screen: buy the cheapest thing on the picked stall when it is
## affordable, and decline otherwise. Declared in one place because two consumers
## (`on_stack_input` and the action bar) must agree on which verb a press means.
func _accept() -> bool:
	if not market_wired() or _selected_shop == "":
		return false
	if not bool(_picked_view().get("can_buy", false)):
		return false
	act_buy()
	return true


## Move the pick `step` entries along the shown list, wrapping. Returns false when
## there is nothing to pick, so `ui_down` on an empty board is declined rather than
## consumed — a screen that swallows a key it cannot honour is a screen that has
## swallowed the player's cancel by association.
func _step(step: int) -> bool:
	var ids := _shop_ids(_row_summaries())
	if ids.is_empty():
		return false
	var index := ids.find(_selected_shop)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	_selected_shop = String(ids[posmod(index + step, ids.size())])
	_render()
	return true


## The priced shelf of `shop_id` off the CACHED read model, never off the seam — so
## the rows the player sees and the rows a verb sells from cannot describe two
## different worlds.
func _shelf_for(shop_id: String) -> Array:
	for view in _views.get("shops", []) as Array:
		if String((view as Dictionary).get("shop_id", "")) == shop_id:
			return (view as Dictionary).get("shelf", []) as Array
	return []


## The shelf line a buy takes: the named `def_id` when one is given, else the cheapest
## priced row. Returns `{}` when the shelf prices nothing, which is a stall with no
## stock rather than a stall the hero cannot afford — two different sentences, and the
## second one lives on the row's `can_buy` instead.
##
## The comparison reads the `coins` the facade already computed rather than re-deriving
## a price, which is the ADR 0094 one-price-path rule: what the screen offers is what
## the settlement charges, because both read `MarketTransfer.quote`.
func _line(shelf: Array, def_id: String) -> Dictionary:
	if def_id != "":
		for entry in shelf:
			var named := entry as Dictionary
			if String(named.get("def_id", "")) == def_id:
				return named
		return {}
	var cheapest: Dictionary = {}
	for entry in shelf:
		var row := entry as Dictionary
		var coins := int(row.get("coins", 0))
		if coins <= 0:
			continue
		if cheapest.is_empty() or coins < int(cheapest["coins"]):
			cheapest = row
	return cheapest


## What a sell would hand over. The hero's own bag is read through `ItemsApi` — `items`
## carries an EMPTY grant in `rules.UI_MODULES`, so naming its facade is exactly as
## legal here as `HoldingsApi` is on the forage screen — and the def is the cheapest
## thing this hero carries that the picked stall actually buys, because whether a
## stall buys a def is authored content the screen must not re-derive.
func _rows_to_sell(shop_id: String, def_id: String, quantity: int) -> Array:
	var buys := _buys_for(shop_id)
	if buys.is_empty():
		return []
	var wanted := StringName(def_id)
	if wanted == &"":
		var carried := ItemsApi.inventory(_actor)
		if carried == null:
			return []
		for stack in carried.stacks():
			var candidate := StringName(stack.def_id)
			if buys.has(String(candidate)) and carried.count(candidate) > 0:
				wanted = candidate
				break
	if wanted == &"" or not buys.has(String(wanted)):
		return []
	return [{"def_id": String(wanted), "quantity": maxi(1, quantity)}]


## The defs a stall authors a `buys` list for, off the cached read model. `[]` is a
## black market and is the authored refusal, not an absence — which is why a sell from
## one is declined here rather than sent to a verb that would refuse it.
func _buys_for(shop_id: String) -> Array:
	for view in _views.get("shops", []) as Array:
		var row := view as Dictionary
		if String(row.get("shop_id", "")) != shop_id:
			continue
		return ((row.get("definition", {}) as Dictionary).get("buys", [])) as Array
	return []


## The named shop's own row for `shop_id`, off the cached read model, decorated with
## `mine` / `can_buy` the way `AuctionScreen` decorates a lot. Used by `act_sell`'s
## affordability question and by nothing else, because `act_sell`'s own refusal is the
## module's.
func _picked_view() -> Dictionary:
	if _selected_shop == "":
		return {}
	for view in _views.get("shops", []) as Array:
		if String((view as Dictionary).get("shop_id", "")) == _selected_shop:
			return _publishable(view as Dictionary)
	return {}


## A refusal this screen raises ITSELF, in the module's own `{ok, reason}` shape. Never
## a silent no-op: an action a player asked for that did not happen is reported in the
## same vocabulary the modules use, so one renderer covers both.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## The trade's own verdict with the stall this screen acted at carried beside it, so a
## caller reading the returned dictionary learns WHICH stall moved money without having
## to remember which one it picked.
func _decorate(result: Dictionary, shop_id: String) -> Dictionary:
	var out := result.duplicate(true)
	out["shop_id"] = shop_id
	return out


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary. The screen
## never rewrites it, so `last_result` is the module's answer and a test can compare it
## against `MarketApi` directly.
##
## The repaint happens AFTER the verdict is recorded, so the rows the player sees are
## the ones the verdict describes: a refused trade writes nothing on either side
## (`EconomyExchange` plans before it mutates), so the shelf behind it is
## byte-for-byte as found, and painting the refusal over it is what makes "the world
## did not change, and here is why" legible on one line.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = result.duplicate(true)
	if bool(_last_result.get("ok", false)):
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		# The reason VERBATIM. Not "Rejected: no_room", not a sentence this screen
		# composed: the module authored the constant and a panel that reworded it would be
		# describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## Every mounted row's own summary, in display order. A spare pool row reports `{}`,
## which is what makes the reported count the catalog's AUTHORED size rather than the
## size of the pool the scene happened to mount.
func _row_summaries() -> Array:
	var out: Array = []
	for row in _shop_rows:
		var filled: Dictionary = (row as MarketRow).summary()
		if filled.is_empty():
			continue
		out.append(filled)
	return out


func _shop_ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String((row as Dictionary).get("shop_id", "")))
	return out


func _count_where(rows: Array, key: String) -> int:
	var total := 0
	for row in rows:
		if bool((row as Dictionary).get(key, false)):
			total += 1
	return total
