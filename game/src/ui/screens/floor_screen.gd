class_name FloorScreen
extends UiScreen

## The floor: see what has been dropped at a location, take one into your bag, put
## one down, and age the entries that decay.
##
## ## Why this screen exists at all
##
## `MarketApi.drop`, `take` and `settle` shipped with the whole floor discipline —
## a realized `ItemInstance` per entry, a per-location cap of
## `MarketApi.MAX_FLOOR_PER_LOCATION`, and a `decay_periods` counter that `settle`
## ages — and `MarketApi.summary` publishes the whole ledger as `floor`. **No screen
## in the shipped program ever read any of it**, so a dropped item was a ledger row
## only a test could reach: one player dropped goods, and the only thing that could
## pick them up again was `tests/`.
##
## `market_screen.gd` said the omission out loud — *"The floor is deliberately NOT on
## this surface"* — and the reason it gave was the `settle` period, not the drop and
## the take. This screen is the surface that closes it, and it takes the same period
## argument the shop screen declined to invent.
##
## ## The three verbs are CALLED BY NAME, and every argument is a primitive
##
## `market` IS declared in `rules.UI_MODULES` (as `"market": ["economy"]`), so this
## screen may name `MarketApi` by bare name exactly as `MarketScreen` reads its purse
## and `AuctionScreen` escrows its lot. `drop(actor, location_id, rows, decay_periods)`,
## `take(actor, location_id, drop_id)` and `settle(actor, location_id, periods)` all
## take the bound actor plus plain ids and a row array — none of them needs a shop
## `Actor` or any other `app/` type, so **no seam is injected on this route at all**
## and `_bind_route_screen`'s arm is the plain `setup(actor)`, the same proof custody
## makes.
##
## The `economy` in that grant is the MODULE graph edge (`market -> economy` in
## `registry.json`); it is **not** a grant of `economy` to `ui/`, because
## `tools/arch/enforce.py` checks `dep in rules.UI_MODULES` and `economy` has no key
## there. So this screen may not name `EconomyApi`.
##
## ## Time is the PLAYER'S, never a default
##
## DEF-0111: no module in this program owns a clock. The floor is the only container
## in this program that **destroys** goods on expiry, so its aging verb is the one a
## screen cannot paper over with a tick. [method act_settle] therefore takes its
## `periods` explicitly, and [constant SETTLE_PERIODS] is an authored step a press
## applies — declared here rather than defaulted at the verb, because a defaulted
## period is an invented tick wearing a button's clothes.
##
## ## The location is a FACT, not a filter this screen invents
##
## `MarketState` keys the floor by `location_id`, and `MarketApi.drop` refuses an
## empty one by name (`no_location`). The location therefore arrives through
## [method at_location] and defaults to nothing rather than to a guess — the same
## rule `MarketScreen.at_location` follows, and for the same reason: a defaulted
## location is a floor that is everywhere and therefore nowhere.
##
## ## What is NOT on this surface
##
## The screen publishes an entry's `drop_id` rather than offering to drop "one of
## everything": `MarketApi.drop` plans every row before it removes anything
## (ADR 0044), and the entry's `quantity` is the batch it escrowed. So the drop verb
## names the `def_id` to leave, and the panel prints the quantity the take will
## deliver.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no actor,
## with each row's own summary nested under that row's key.

## Rows the scene mounts and this screen tops up to. `MarketApi.MAX_FLOOR_PER_LOCATION`
## is 8 per location — a refused admit rather than a silent trim — so the pool is grown
## through `RowBudget.cap`, the same shape `MarketScreen` uses for stalls.
const DROP_ROWS := 8
const ROW_SCENE := "res://src/ui/panels/floor_drop_row.tscn"
const ACTIONS_SCENE := "res://src/ui/panels/action_set.tscn"
const HEADER_TEXT := "What lies on the floor here, and who left it."
const NO_ACTOR_TEXT := "No hero bound."
const FOOTER_TEXT := "Up / Down picks a drop, Accept takes it. Cancel returns."

## The action ids this screen publishes, in the order the bar shows them. Declared as
## constants rather than built per call so the order a test reads is the order the
## player sees.
const ACTION_TAKE := &"take"
const ACTION_DROP := &"drop"
const ACTION_SETTLE := &"settle"

## The periods one press of the settle action ages the floor by. A single tidy-up
## step, declared here rather than defaulted at the verb: a press says how much time
## the player is choosing to let pass.
const SETTLE_PERIODS := 1
## The periods a drop placed by the action bar is given before it expires. Zero —
## "never decays" — because the plain drop is the floor's default state and the aging
## is what a caller opts into.
const NO_DECAY_PERIODS := 0

## The refusals this screen raises ITSELF, before a verb is called. Authored constants
## rather than prose, for the same reason the modules author their own: a panel
## renders a reason it did not have to invent.
const NO_ACTOR := "no_actor"
const NO_DROP_PICKED := "no_drop_picked"
## No location has been named, so "what lies here" has no answer. Distinct from
## `MarketApi.NO_LOCATION` only in that the module raises that one for a drop; this is
## the same sentence said by the read side.
const NO_LOCATION := "no_location"
## The hero is carrying nothing this screen can put down. Distinct from every module
## refusal: there is a bag, and nothing in it this verb will take.
const NO_CARRIED := "no_carried"
## `periods <= 0` was asked for, so there is no elapsed time to age by. The module
## owns the rule (`MarketApi.NO_PERIODS`); this screen refuses by the same name so
## one id covers the whole path whichever layer raised it.
const NO_PERIODS := MarketApi.NO_PERIODS

var _header: Label = null
var _footer: Label = null
var _drop_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _drop_rows: Array = []
## The drop the verbs would act on. `""` picks nothing, and each verb then refuses
## `no_drop_picked` by name rather than silently acting on the first row.
var _selected_drop: String = ""
## The location whose floor this screen is showing. Set through [method at_location]
## rather than defaulted at a verb, because the ledger key is content and a defaulted
## location would be a floor that exists everywhere.
var _location_id: StringName = &""
## The floor rows as the facade published them, cached from the last refresh so a
## refresh costs exactly one facade call however many times `summary()` is asked.
var _views: Array = []
## The last verb's verdict, carried through verbatim. `{}` before any action, so a
## test reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}


## Show the floor at `location_id`. The location is the ONE fact the caller has that
## this screen cannot read for itself — `world_spawn` is not in `rules.UI_MODULES`, so
## a screen may not ask where the hero is standing.
##
## A `null` or empty location clears the board and leaves the verbs refusing
## `no_location`, which is a different sentence from "the floor is empty": the first
## says nobody said where to look, the second says the room is bare.
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
		"floor_wired": true,
		# The floor and the purse, read from `MarketApi.summary` by bare name: `market`
		# is declared in `rules.UI_MODULES`, so this is the one facade call this screen
		# makes for its own state.
		"purse": int(MarketApi.summary(_actor).get("purse", 0)),
		"drop_count": rows.size(),
		"drop_ids": _drop_ids(rows),
		"decaying_count": _count_where(rows, "decaying"),
		"capacity": int(MarketApi.summary(_actor).get("floor_capacity_per_location", 0)),
		"selected_drop": _selected_drop,
		"selected_decaying": bool(picked.get("decaying", false)),
		"selected_mine": bool(picked.get("mine", false)),
		# The last verb's verdict as primitives. `last_reason` is the module's own named
		# constant, so one run tells a taken drop from a refused one from an aged-out
		# one — the refusals that would otherwise all read as "nothing happened".
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"last_reason": String(_last_result.get("reason", "")),
		"last_drop": String(_last_result.get("drop_id", "")),
		"last_def_id": String(_last_result.get("def_id", "")),
		"last_quantity": int(_last_result.get("quantity", 0)),
		"last_expired": int(_last_result.get("expired", 0)),
		"last_remaining": int(_last_result.get("remaining", 0)),
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# Each row's own summary, nested under that row's key so a test reads the drop
		# without walking the widget tree.
		"rows": rows,
	}


# --- Actions. Each calls the facade by name, and reports what came back --------


## Take the picked drop into the hero's bag, or the entry named by `drop_id`.
## Returns `MarketApi.take`'s verdict unchanged, so a caller never has to read the
## message line to learn what happened.
##
## The verb is first-come — `decay_periods == 0` never ages, and a claim window
## would be a second time mechanism on top of the counter `settle` already needs — so
## the pick decides who gets there first, which is why an unselected board refuses
## rather than acting on whichever row happens to be first.
func act_take(drop_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := drop_id if drop_id != "" else _selected_drop
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _location_id == &"":
		return _verdict(NO_LOCATION)
	if wanted == "":
		return _verdict(NO_DROP_PICKED)
	return _settle(_decorate(MarketApi.take(_actor, _location_id, wanted), wanted))


## Put `quantity` of `def_id` from the hero's bag onto the floor of this location,
## where it ages out after `decay_periods` periods (`0` = never).
##
## `decay_periods` is AUTHORED at drop time rather than patched afterwards on
## purpose: `MarketState.normalize` returns a copy, so a write-through "set the decay
## then age it" reads as having worked and has not — the entry silently never
## expires, and the only evidence is a test that waited.
func act_drop(def_id: String, quantity: int = 1, decay_periods: int = 0) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _location_id == &"":
		return _verdict(NO_LOCATION)
	if def_id == "" or quantity <= 0:
		return _verdict(NO_CARRIED)
	if decay_periods < 0:
		return _verdict(NO_PERIODS)
	var rows := [{"def_id": def_id, "quantity": quantity}]
	return _settle(MarketApi.drop(_actor, _location_id, rows, decay_periods))


## Age the floor here by `periods`, destroying every entry whose `decay_periods`
## has elapsed. Returns `MarketApi.settle`'s verdict, which carries `expired` and
## `remaining` so a caller learns how much was destroyed and not merely that
## something was.
func act_settle(periods: int = SETTLE_PERIODS) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _location_id == &"":
		return _verdict(NO_LOCATION)
	if periods <= 0:
		return _verdict(NO_PERIODS)
	return _settle(MarketApi.settle(_actor, _location_id, periods))


## Pick the drop the take verb would act on. Returns false for an id this screen is
## not showing, so a caller never "selects" a drop that does not exist here, and
## clears the selection rather than leaving a stale one behind.
func select_drop(drop_id: String) -> bool:
	_bind_nodes()
	if drop_id == "":
		_selected_drop = ""
	elif _drop_ids(_row_summaries()).has(drop_id):
		_selected_drop = drop_id
	else:
		return false
	_render()
	return true


## The drop ids this screen is showing, in display order — the list `ui_up` / `ui_down`
## walk. Read off the rows rather than off the facade, so what the player can pick is
## exactly what they can see.
func drop_ids() -> Array:
	_bind_nodes()
	return _drop_ids(_row_summaries())


## The def ids the hero is carrying, in bag order, as a read of the bag through
## `ItemsApi` — `items` carries an EMPTY grant in `rules.UI_MODULES`, so naming its
## facade is exactly as legal here as `HoldingsApi` is on the forage screen. A player
## drops a row by naming one of these.
func carried_def_ids() -> Array:
	_bind_nodes()
	var out: Array = []
	if _actor == null:
		return out
	var carried := ItemsApi.inventory(_actor)
	if carried == null:
		return out
	for stack in carried.stacks():
		var def_id := StringName(stack.def_id)
		if carried.count(def_id) > 0 and not out.has(String(def_id)):
			out.append(String(def_id))
	for instance in carried.instances():
		var def_id := StringName(instance.def_id)
		if not out.has(String(def_id)):
			out.append(String(def_id))
	return out


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first LIVE control in the action row, because this screen
## does something and the control a player can press is the one the keyboard must land
## on. Recorded first, because a drop outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before


## `ui_accept` takes the picked drop, and `ui_up` / `ui_down` walk the picked list.
## Each is CONSUMED only when it did something, so `ui_cancel` stays free for
## `ScreenStack` to pop exactly as it pops every other screen: a screen that could
## take and also swallowed the cancel would trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked, for the
## reason `MarketScreen.on_stack_input` gives: a screen that declines an unbound event
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


## Re-read the facade — the ONE call this screen makes per refresh — and hand raw
## values down. Every later read is of the cached `_views`, never of the facade, so a
## refresh costs exactly one call however many times `summary()` is asked. The rows
## own every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var model := MarketApi.summary(_actor) if _actor != null else {}
	var floor := model.get("floor", {}) as Dictionary
	# `MarketState.drops_at` on the MODULE's side because the location key does not
	# exist on a fresh ledger and `floor[""]` on a missing key is a runtime error
	# rather than an empty list. Here the same shape is spelled with `get`, so the
	# first page ever opened at an empty location renders rather than aborts.
	_views = (floor.get(String(_location_id), []) as Array) if _location_id != &"" else []
	_fill_from_views()


func _fill_from_views() -> void:
	if _drop_rows.is_empty():
		return
	# Snapshot the bound BEFORE the pool grows: `needed` is a content-derived count and
	# a grow loop that re-reads it is the shape `RowBudget` exists to close.
	var needed: int = _views.size()
	var target := RowBudget.cap(needed)
	while _drop_rows.size() < target:
		var row := load(ROW_SCENE).instantiate() as Control
		row.name = "Drop%d" % _drop_rows.size()
		_drop_box.add_child(row)
		_drop_rows.append(row)
	var index := 0
	while index < _drop_rows.size():
		var view: Dictionary = _views[index] as Dictionary if index < _views.size() else {}
		(_drop_rows[index] as FloorDropRow).show_drop(_publishable(view))
		index += 1
	# A selection that fell off the end of the list is CLEARED rather than left stale:
	# a pick naming a drop this screen is no longer showing would act on nothing.
	if not _drop_ids(_row_summaries()).has(_selected_drop):
		_selected_drop = ""


## The entry as this screen publishes it: the ledger row flattened onto the keys
## `FloorDropRow` renders, with the ONE fact only this screen can know folded in —
## whether the bound hero is the one who left it, decided by comparing the ledger's
## bare `dropped_by` string against the actor's id and never by naming an `Actor`.
func _publishable(view: Dictionary) -> Dictionary:
	if view.is_empty():
		return {}
	var out := {
		"drop_id": String(view.get("drop_id", "")),
		"location_id": String(view.get("location_id", "")),
		"def_id": String(view.get("def_id", "")),
		"quantity": int(view.get("quantity", 0)),
		"dropped_by": String(view.get("dropped_by", "")),
		"periods_held": int(view.get("periods_held", 0)),
		"decay_periods": int(view.get("decay_periods", 0)),
	}
	out["mine"] = _actor != null and String(view.get("dropped_by", "")) == String(_actor.id)
	return out


func _bind_nodes() -> void:
	super()
	if _header != null:
		return
	_header = get_node_or_null("%HeaderLabel") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_drop_box = get_node_or_null("Layout/Scroll/Drops") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _drop_box != null
	if not _bound:
		return
	_drop_rows = _rows_in(_drop_box, DROP_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares
## it, because a headless test may instantiate this screen's script against a scene
## that predates the action row; the ACTIONS are then unreachable and every take
## reports `no_drop_picked` rather than pretending to have fired.
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
		if row != null and row.has_method(&"show_drop"):
			out.append(row)
	for index in range(extra):
		var row := load(ROW_SCENE).instantiate() as Control
		row.name = "Drop%d" % out.size()
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
## `take` needs a located board and a picked drop: `MarketApi.take` refuses
## `no_such_drop` for an id this screen is not showing, and a control that is live
## where the verb refuses is the "looks alive and is dead" shape the UI standard
## exists to prevent. `drop` needs the hero carrying something, and whether the def
## named is bound is the MODULE's rule (`MarketApi.drop` refuses `not_carried`) so
## this screen does not re-judge it. `settle` needs a location, because there is no
## floor to age anywhere else — a press with nowhere named is a refusal, not a no-op.
func _publish_actions() -> void:
	if _actions == null:
		return
	(
		_actions
		. set_state(
			{
				"actions": _action_ids(),
				"labels":
				{
					ACTION_TAKE: "Take the picked drop",
					ACTION_DROP: "Drop the first thing you carry",
					ACTION_SETTLE: "Let one period pass here",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_TAKE if _selected_drop != "" else ACTION_SETTLE,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so
## the order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [String(ACTION_TAKE), String(ACTION_DROP), String(ACTION_SETTLE)]


## Which of the three is live right now.
func _enabled_actions() -> Dictionary:
	return {
		String(ACTION_TAKE): _actor != null and _location_id != &"" and _selected_drop != "",
		String(ACTION_DROP):
		_actor != null and _location_id != &"" and not carried_def_ids().is_empty(),
		String(ACTION_SETTLE): _actor != null and _location_id != &"",
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled
## action, so this cannot fire a verb the control does not offer.
##
## `drop` takes the hero's FIRST carried stack and [constant NO_DECAY_PERIODS] —
## the authored "this does not rot" step — rather than a figure a button author
## typed, so a retune is one constant and not a search.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_TAKE:
			act_take()
		ACTION_DROP:
			var carried := carried_def_ids()
			if not carried.is_empty():
				act_drop(String(carried[0]), 1, NO_DECAY_PERIODS)
		ACTION_SETTLE:
			act_settle(SETTLE_PERIODS)


## `ui_accept` on the screen: take the picked drop, and decline otherwise. Declared in
## one place because two consumers (`on_stack_input` and the action bar) must agree on
## which verb a press means.
func _accept() -> bool:
	if _selected_drop == "":
		return false
	act_take()
	return true


## Move the pick `step` entries along the shown list, wrapping. Returns false when
## there is nothing to pick, so `ui_down` on an empty floor is declined rather than
## consumed — a screen that swallows a key it cannot honour is a screen that has
## swallowed the player's cancel by association.
func _step(step: int) -> bool:
	var ids := _drop_ids(_row_summaries())
	if ids.is_empty():
		return false
	var index := ids.find(_selected_drop)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	_selected_drop = String(ids[posmod(index + step, ids.size())])
	_render()
	return true


## A refusal this screen raises ITSELF, in the module's own `{ok, reason}` shape. Never
## a silent no-op: an action a player asked for that did not happen is reported in the
## same vocabulary the modules use, so one renderer covers both.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## The verb's own verdict with the drop this screen acted at carried beside it, so a
## caller reading the returned dictionary learns WHICH entry moved without having to
## remember which one it picked. `take` names no `drop_id` in its own answer, so the
## pick is what carries it.
func _decorate(result: Dictionary, drop_id: String) -> Dictionary:
	var out := result.duplicate(true)
	if not out.has("drop_id"):
		out["drop_id"] = drop_id
	return out


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary. The screen
## never rewrites it, so `last_result` is the module's answer and a test can compare it
## against `MarketApi` directly.
##
## The repaint happens AFTER the verdict is recorded, so the rows the player sees are
## the ones the verdict describes: a refused take writes nothing (`MarketApi.take`
## refuses before it removes the entry), so the floor behind it is byte-for-byte as
## found, and painting the refusal over it is what makes "the world did not change,
## and here is why" legible on one line.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = result.duplicate(true)
	if bool(_last_result.get("ok", false)):
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		# The reason VERBATIM. Not "Rejected: no_such_drop", not a sentence this screen
		# composed: the module authored the constant and a panel that reworded it would
		# be describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## Every mounted row's own summary, in display order. A spare pool row reports `{}`,
## which is what makes the reported count the ledger's AUTHORED size rather than the
## size of the pool the scene happened to mount.
func _row_summaries() -> Array:
	var out: Array = []
	for row in _drop_rows:
		var filled: Dictionary = (row as FloorDropRow).summary()
		if filled.is_empty():
			continue
		out.append(filled)
	return out


func _picked_view() -> Dictionary:
	if _selected_drop == "":
		return {}
	for filled in _row_summaries():
		if String((filled as Dictionary).get("drop_id", "")) == _selected_drop:
			return filled as Dictionary
	return {}


func _drop_ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String((row as Dictionary).get("drop_id", "")))
	return out


func _count_where(rows: Array, key: String) -> int:
	var total := 0
	for row in rows:
		if bool((row as Dictionary).get(key, false)):
			total += 1
	return total
