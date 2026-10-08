class_name ForageScreen
extends UiScreen

## The gather surface: take a node, work it, and end up holding what it yields.
##
## ## Why this screen exists at all
##
## An independent audit found the economy program "wired to itself, not to a player".
## Sixteen authored `ResourceNodeDef` `.tres`, a `NODE_YIELDS` table with an entry for
## every one of them, `HoldingsApi.claim` and `ForageApi.harvest` both green in every
## suite — and `HoldingsApi.claim` with **no production caller anywhere in the tree**.
## A node was therefore never held, `ForageAction.workable` could never answer true, and
## the harvest verb was reachable from nothing while `tools data audit` reported
## `gather` live because `app/forage_action.gd` exists. That is the UNWIRED class that
## passes every test and no player can reach.
##
## So the slice is TWO beats in one page, and the order is the mechanic:
##
##   1. **claim** a node — `HoldingsApi.claim`. This is what makes it yours.
##   2. **gather** it — the harvest, which requires step 1 and refuses `no_holder`
##      without it.
##
## A screen offering only the harvest would be a button that refuses forever, and one
## offering only the claim would be a claim nothing can spend. They are one page
## because they are one player's relationship with a piece of ground.
##
## ## `release` is here too, and it is NOT free
##
## `HoldingsApi.release` is always permitted and never free: the obligation lines the
## claim charged stay written, because a holder who walks away from a claim has not
## un-paid it (ADR 0085). Its only refusal is `cannot_release_foreign`. So the button
## is live for every holder and the refusal is RENDERED rather than the control greyed
## out — a player who is told nothing may still be told why nothing happened.
##
## ## The harvest arrives as a Callable, and the claim does not
##
## `app/` is a `PRIVATE_UNIT` (`rules.py`), so this program may name neither
## `ForageAction` (an `app/` type) nor any module interior. `HoldingsApi.claim` and
## `HoldingsApi.release` are therefore reached BY NAME — `holdings` is declared in
## `rules.UI_MODULES` and this screen calls its facade, exactly as `SectScreen` calls
## `SectApi`. The harvest goes through `ForageAction.gather`, which a screen cannot
## name, so the composition root hands the verb over at the route mount by
## [method bind_harvest] — ADR 0143's seam, the same one `QuestScreen.bind_quests` and
## `SoulHearthScreen.bind_soul` use. **Unwired, `act_gather` refuses `no_harvest_seam`
## by name** rather than reporting a harvest nobody ran.
##
## ## Periods are the PLAYER'S, never a default
##
## DEF-0111: no module in this program owns a clock, so `periods` is required and never
## defaulted. This screen declares its own step (a single period) as an authored
## constant rather than as a parameter default on the verb, because a defaulted period
## is an invented tick wearing a button's clothes — and [method act_gather] takes it
## explicitly so a caller asking for more periods has to say so.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no actor,
## with each row's own summary nested under that row's key.

## Rows the scene mounts and this screen tops up to. Sixteen nodes are authored today
## and a pool that dropped one would read as dead content, so the pool is grown through
## `RowBudget.cap` rather than truncated — the same shape `SectScreen` uses for offices.
const NODE_ROWS := 16
const NODE_SCENE := "res://src/ui/panels/resource_node_row.tscn"
const ACTIONS_SCENE := "res://src/ui/panels/action_set.tscn"
const HEADER_TEXT := "LOC_UI_SCREENS_E1FACAED67"
const NO_ACTOR_TEXT := "LOC_UI_SCREENS_6E9BC19A74"
const NO_ACTOR_FOOTER := ""
const FOOTER_TEXT := "LOC_UI_SCREENS_9EAB3F9E93" + "LOC_UI_SCREENS_6A41F1E6E5"

## The action ids this screen publishes, in the order the bar shows them. Declared as
## constants rather than built per call so the order a test reads is the order the
## player sees.
const ACTION_CLAIM := &"claim"
const ACTION_GATHER := &"gather"
const ACTION_RELEASE := &"release"

## The refusals this screen raises ITSELF, before a verb is called. Authored constants
## rather than prose, for the same reason the modules author their own: a panel renders
## a reason it did not have to invent.
const NO_ACTOR := "no_actor"
const NO_NODE_PICKED := "no_node_picked"
## The harvest seam is not bound, so the gather the player pressed cannot run. Distinct
## from every module refusal: the amount was named and there is nowhere to send it.
const NO_HARVEST_SEAM := "no_harvest_seam"
## `periods <= 0` was asked for. The module owns the rule; this screen refuses by the
## same name so one id covers the whole path whichever layer raised it.
const NO_PERIODS := ForageApi.NO_PERIODS

## The periods one press of the gather action works. A single period, declared here
## rather than defaulted at the verb: a press says how long the hero laboured.
const GATHER_PERIODS := 1

var _header: Label = null
var _footer: Label = null
var _node_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _node_rows: Array = []
## The node `act_claim` / `act_gather` / `act_release` would act on. `""` picks nothing,
## and each verb then refuses `no_node_picked` by name rather than silently acting on
## the first row.
var _selected_node: String = ""
## The harvest verb, injected by the composition root. See the class note for why the
## claim is reached by name and the harvest is not.
var _harvest: Callable = Callable()
## The last verb's verdict, carried through verbatim. `{}` before any action, so a test
## reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The facade's rows for the bound actor, cached from the last refresh, so a refresh
## costs exactly one facade call however many times `summary()` is asked.
var _views: Array = []


## Inject the harvest verb. Called at the route mount by the composition root.
##
## `Callable(actor, node_id, periods) -> Dictionary`, which is `ForageAction.gather`'s
## signature verbatim. Safe to call again; the screen repaints from the facade either
## way.
##
## Assigned exactly as given rather than merged into a default, so binding a
## deliberate null clears a previously bound seam — the rule `item_workbench.setup`'s
## save and load callables follow.
func bind_harvest(harvest: Callable) -> void:
	_bind_nodes()
	_harvest = harvest
	_refresh_view()
	_render()


## Whether the harvest seam is bound. Published by `summary()` so a probe can tell "this
## screen cannot gather" from "this screen has nothing to gather", which are different
## sentences and both reachable.
func harvest_wired() -> bool:
	return _harvest.is_valid()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var rows := _node_summaries()
	var picked := _picked_view()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		# The three custody facts, as three DISTINCT booleans rather than one
		# "available": a node this hero holds, a node nobody holds, and a node held
		# under an open standoff are three different situations (ADR 0085).
		"held_count": _held_count(rows),
		"vacant_count": _vacant_count(rows),
		"contested_count": _contested_count(rows),
		"workable_count": _workable_count(rows),
		"node_count": rows.size(),
		"node_ids": _node_ids(rows),
		"selected_node": _selected_node,
		"selected_held": bool(picked.get("held", false)),
		"selected_vacant": bool(picked.get("vacant", false)),
		"selected_contested": bool(picked.get("contested", false)),
		"selected_workable": bool(picked.get("workable", false)),
		"harvest_wired": harvest_wired(),
		# The last verb's verdict as primitives. `last_reason` is the module's own named
		# constant, so one run tells a full bag from a spent vein from ground somebody
		# else holds — the refusals that would otherwise all read as "nothing happened".
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"last_reason": String(_last_result.get("reason", "")),
		"last_node": String(_last_result.get("node_id", "")),
		"last_granted": int(_last_result.get("granted", 0)),
		"last_yielded": int(_last_result.get("yielded", 0)),
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# Each row's own summary, nested under that row's key so a test reads the row
		# without walking the widget tree.
		"rows": rows,
	}


# --- Actions. Each calls the facade through its seam, and reports what came back ---


## Take the picked node, or `node_id` when one is named. Returns `HoldingsApi.claim`'s
## verdict unchanged, so a caller never has to read the message line to learn what
## happened.
##
## **A claim on HELD ground opens a standoff rather than taking the ground** (ADR
## 0085), which is why `contested` is passed through beside `ok`: a claim and a
## challenge are different situations and a panel renders them differently. `ok: true`
## here is never "the node is yours now".
func act_claim(node_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := node_id if node_id != "" else _selected_node
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_NODE_PICKED)
	var result := HoldingsApi.claim(_actor, StringName(wanted), _owner())
	_settle(result)
	return _last_result.duplicate(true)


## Give up the picked node. Always permitted and never free — see the class note.
## Returns `HoldingsApi.release`'s verdict.
func act_release(node_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := node_id if node_id != "" else _selected_node
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_NODE_PICKED)
	var result := HoldingsApi.release(_actor, StringName(wanted), _owner())
	_settle(result)
	return _last_result.duplicate(true)


## Work the picked node for `periods` and put the yield in the bag. Returns the
## harvest's own verdict.
##
## ## The owner ref is the CALLER'S here, and that is the point
##
## `ForageAction.gather` derives `{"kind": "actor", "id": actor.id}` from the actor
## rather than taking it, precisely so a caller cannot name somebody else's id and work
## their ground. This screen therefore passes only `actor, node_id, periods` and the
## composition root's verb derives the ref itself — the screen's `_owner()` is used by
## the two HOLDINGS verbs above, which do take one, and never by this one.
func act_gather(node_id: String = "", periods: int = GATHER_PERIODS) -> Dictionary:
	_bind_nodes()
	var wanted := node_id if node_id != "" else _selected_node
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_NODE_PICKED)
	if periods <= 0:
		return _verdict(NO_PERIODS)
	if not _harvest.is_valid():
		return _verdict(NO_HARVEST_SEAM)
	return _settle(_harvest.call(_actor, StringName(wanted), periods) as Dictionary)


## Pick the node the verbs would act on. Returns false for an id this screen is not
## showing, so a caller never "selects" a node that does not exist here, and clears the
## selection rather than leaving a stale one behind.
func select_node(node_id: String) -> bool:
	_bind_nodes()
	if node_id == "":
		_selected_node = ""
	elif _node_ids(_node_summaries()).has(node_id):
		_selected_node = node_id
	else:
		return false
	_render()
	return true


## The node ids this screen is showing, in display order — the list `ui_up` / `ui_down`
## walk. Read off the rows rather than off the facade, so what the player can pick is
## exactly what they can see.
func node_ids() -> Array:
	_bind_nodes()
	return _node_ids(_node_summaries())


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first LIVE control in the action row, because this screen
## does something and the control a player can press is the one the keyboard must land
## on. Recorded first, because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before


## `ui_accept` fires whichever verb the picked node's own state makes the primary one —
## claim a node nobody holds, work a node this hero holds, and decline both otherwise —
## and `ui_up` / `ui_down` walk the picked list. Each is CONSUMED only when it did
## something, so `ui_cancel` stays free for `ScreenStack` to pop exactly as it pops
## every other screen: a screen that could work a node and also swallowed the cancel
## would trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked, for the reason
## `SectScreen.on_stack_input` gives: a screen that declines an unbound event by
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
	_views = ForageApi.views(_actor) if _actor != null else []
	_fill_from_views()


func _fill_from_views() -> void:
	if _node_rows.is_empty():
		return
	# Snapshot the bound BEFORE the pool grows: `needed` is a content-derived count and
	# a grow loop that re-reads it is the shape `RowBudget` exists to close.
	var needed: int = _views.size()
	var target := RowBudget.cap(needed)
	while _node_rows.size() < target:
		var row := load(NODE_SCENE).instantiate() as Control
		row.name = "Node%d" % _node_rows.size()
		_node_box.add_child(row)
		_node_rows.append(row)
	var index := 0
	while index < _node_rows.size():
		var view: Dictionary = _views[index] as Dictionary if index < _views.size() else {}
		(_node_rows[index] as ResourceNodeRow).show_node(view)
		index += 1
	# A selection that fell off the end of the list is CLEARED rather than left stale:
	# a pick naming a node this screen is no longer showing would act on nothing.
	if not _node_ids(_node_summaries()).has(_selected_node):
		_selected_node = ""


func _bind_nodes() -> void:
	super()
	if _header != null:
		return
	_header = get_node_or_null("%HeaderLabel") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_node_box = get_node_or_null("Layout/Scroll/Nodes") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _node_box != null
	if not _bound:
		return
	_node_rows = _rows_in(_node_box, NODE_SCENE, "Node", NODE_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares it,
## because a headless test may instantiate this screen's script against a scene that
## predates the action row; the ACTIONS are then unreachable and every verb reports
## `no_harvest_seam` rather than pretending to have fired.
##
## The guard is what makes "one handler per connection" a fact rather than an accident
## of the `_bind_nodes` early return: the moment anything calls this a second time, an
## unguarded `connect` would duplicate silently.
func _connect_actions() -> void:
	if _actions == null:
		return
	if not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)


## The `OwnerRef` the two HOLDINGS verbs take, as the plain dictionary the facade
## compares against. `ui/` may not mint an `Actor`, but it may read one off the screen
## it is bound to — and this is exactly what `ForageAction.owner_ref` builds for the
## harvest, spelled out here rather than imported because `ForageAction` is an `app/`
## type this program may not name.
func _owner() -> Dictionary:
	return {"kind": "actor", "id": String(_actor.id)}


## The rows the scene declares, in order, then enough grown rows to reach `extra`. A pool
## smaller than `extra` would have to truncate the data the next refresh brings, so the
## mounted rows are topped up here rather than left to `_fill_from_views`.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and row.has_method(&"show_node"):
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = L.t(NO_ACTOR_TEXT)
		_footer.text = L.t(NO_ACTOR_FOOTER)
		_publish_actions()
		return
	_header.text = L.t(HEADER_TEXT)
	_footer.text = L.t(FOOTER_TEXT)
	_publish_actions()


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line, so the screen formats no number
## and no sentence.
##
## `gather` needs the harvest seam AND a workable node; `claim` needs a node picked that
## the hero does not already hold, because `HoldingsApi.claim` on ground the hero ALREADY
## holds is the standoff path and the player has a `release` button for leaving;
## `release` needs a node the hero holds, because `cannot_release_foreign` is the only
## refusal the verb has and a player who is told nothing may still be told why nothing
## happened.
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
					ACTION_CLAIM: "Take the picked node",
					ACTION_GATHER: "Work the picked node",
					ACTION_RELEASE: "Give up the picked node",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_GATHER if bool(picked.get("workable", false)) else ACTION_CLAIM,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so the
## order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [String(ACTION_CLAIM), String(ACTION_GATHER), String(ACTION_RELEASE)]


## Which of the three is live right now.
func _enabled_actions() -> Dictionary:
	var picked := _picked_view()
	var held := bool(picked.get("held", false))
	return {
		String(ACTION_CLAIM): _actor != null and _selected_node != "" and not held,
		String(ACTION_GATHER): _actor != null and bool(picked.get("workable", false)),
		String(ACTION_RELEASE): _actor != null and held,
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled action,
## so this cannot fire a verb the control does not offer.
##
## `gather` takes [constant GATHER_PERIODS] — the authored step — rather than a number
## a button author typed, so a retune of the step is one constant and not a search.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_CLAIM:
			act_claim()
		ACTION_GATHER:
			act_gather()
		ACTION_RELEASE:
			act_release()


## `ui_accept` on the screen: work the picked node when it is workable, claim it when it
## is nobody's, and decline otherwise. Declared in one place because two consumers
## (`on_stack_input` and the action bar) must agree on which verb a press means.
func _accept() -> bool:
	var picked := _picked_view()
	if bool(picked.get("workable", false)):
		act_gather()
		return true
	if _selected_node != "" and not bool(picked.get("held", false)):
		act_claim()
		return true
	return false


## Move the pick `step` entries along the shown list, wrapping. Returns false when there
## is nothing to pick, so `ui_down` on an empty board is declined rather than consumed —
## a screen that swallows a key it cannot honour is a screen that has swallowed the
## player's cancel by association.
func _step(step: int) -> bool:
	var ids := _node_ids(_node_summaries())
	if ids.is_empty():
		return false
	var index := ids.find(_selected_node)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	_selected_node = String(ids[posmod(index + step, ids.size())])
	_render()
	return true


## A refusal this screen raises ITSELF, in the module's own `{ok, reason}` shape. Never a
## silent no-op: an action a player asked for that did not happen is reported in the
## same vocabulary the modules use, so one renderer covers both.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary. The screen
## never rewrites it, so `last_result` is the module's answer and a test can compare it
## against `HoldingsApi` directly.
##
## The repaint happens AFTER the verdict is recorded, so the rows the player sees are the
## ones the verdict describes: a refused verb writes nothing (ADR 0085), so the custody
## behind it is byte-for-byte as found, and painting the refusal over it is what makes
## "the world did not change, and here is why" legible on one line.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = result.duplicate(true)
	if bool(_last_result.get("ok", false)):
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		# The reason VERBATIM. Not "Rejected: no_holder", not a sentence this screen
		# composed: the module authored the constant and a panel that reworded it would be
		# describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## Every mounted row's own summary, in display order. A spare pool row reports `{}`,
## which is what makes the reported count the catalog's AUTHORED size rather than the
## size of the pool the scene happened to mount.
func _node_summaries() -> Array:
	var out: Array = []
	for row in _node_rows:
		var filled: Dictionary = (row as ResourceNodeRow).summary()
		if filled.is_empty():
			continue
		out.append(filled)
	return out


## The facade row for the current pick, or `{}` when nothing is picked. The picked row's
## OWN summary rather than a facade re-read, so the action bar's enabled state and the
## node row on screen can never describe two different worlds.
func _picked_view() -> Dictionary:
	if _selected_node == "":
		return {}
	for filled in _node_summaries():
		if String((filled as Dictionary).get("node_id", "")) == _selected_node:
			return filled as Dictionary
	return {}


func _node_ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String((row as Dictionary).get("node_id", "")))
	return out


func _count_where(rows: Array, key: String) -> int:
	var total := 0
	for row in rows:
		if bool((row as Dictionary).get(key, false)):
			total += 1
	return total


func _held_count(rows: Array) -> int:
	return _count_where(rows, "held")


func _vacant_count(rows: Array) -> int:
	return _count_where(rows, "vacant")


func _contested_count(rows: Array) -> int:
	return _count_where(rows, "contested")


func _workable_count(rows: Array) -> int:
	return _count_where(rows, "workable")
