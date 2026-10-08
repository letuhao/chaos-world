class_name ItemWorkbench
extends PanelContainer

## The item workbench screen: the actor's inventory on the left, the selected
## item's full detail on the right, and the action row underneath it.
##
## A pure consumer of the `items` facade (ADR 0007). It reads inventory and
## equipment, calls the facade's public actions, and renders what they return —
## it owns no item rule and never reaches into module internals. Every rejected
## action leaves the actor untouched and reports the gameplay reason.
##
## Widgets live in `item_workbench.tscn`. Refreshes are driven by the inventory
## and equipment signals, never by polling.
##
## Contract: `summary()` is the testable surface. Headless tests assert it
## instead of pixels.

## Which activation channels an item can actually be used on. Mirrors the items
## module's activation vocabulary; gameplay still decides.
## Definition subtype to the equipment slot a player most likely means. The
const TONE_ERROR := &"error"
const TONE_OK := &"ok"

var _actor: Actor
var _message: String = ""
var _tone: StringName = &""
var _seed_counter: int = 0
var _focus_initialized: bool = false
## Injected by the composition root so the UI program never touches the
## filesystem. `_save_callable(payload) -> String` returns "" on success or a
## reason on failure; `_load_callable() -> Dictionary` returns the saved state
## (ADR 0027).
var _save_callable: Callable = Callable()
var _load_callable: Callable = Callable()
var _header_label: Label = null
var _inventory_panel: InventoryPanel = null
var _detail_panel: ItemDetailPanel = null
var _action_bar: ActionBar = null


func _ready() -> void:
	_bind_nodes()
	refresh()


## Point the workbench at the actor and, optionally, at the persistence callable
## the composition root owns. Safe to call again: the panels rebind and the
## previous selection is dropped.
## Point the workbench at the actor and its persistence. Both callables are
## assigned exactly as given, so passing an invalid Callable clears a previously
## injected one instead of silently keeping it.
func setup(
	actor: Actor, save_callable: Callable = Callable(), load_callable: Callable = Callable()
) -> void:
	_bind_nodes()
	_actor = actor
	_save_callable = save_callable
	_load_callable = load_callable
	_message = ""
	_tone = &""
	_inventory_panel.bind(actor)
	refresh()


## Re-read the facade and repaint. Signal-driven; nothing here polls.
func refresh() -> void:
	_bind_nodes()
	_header_label.text = L.t(_header_text())
	_inventory_panel.refresh()
	_apply_selection()


## Select the inventory row whose key is `key`, then repaint.
func select_key(key: String) -> bool:
	_bind_nodes()
	var selected := _inventory_panel.select_key(key)
	_apply_selection()
	return selected


## Everything this screen shows, in one primitive-only dictionary: the three
## panel summaries plus the flat numbers a test most often wants. Returns `{}`
## with no actor bound, so a test never reads a half-initialised screen.
func summary() -> Dictionary:
	_bind_nodes()
	if _actor == null or _inventory_panel == null or _detail_panel == null:
		return {}
	var inventory := _inventory_panel.summary()
	var detail := _detail_panel.summary()
	var actions := _action_bar.summary()
	if inventory.is_empty() or detail.is_empty() or actions.is_empty():
		return {}
	return {
		"has_actor": _actor != null,
		"actor_id": "" if _actor == null else String(_actor.id),
		"row_count": int(inventory["rows"]),
		"selection_key": _inventory_panel.selection_key(),
		"fixed_count": int(detail["fixed_count"]),
		"rolled_count": int(detail["rolled_count"]),
		"effect_line_count": int(detail["effect_line_count"]),
		"action_enabled": actions["enabled"],
		"message": String(actions["message"]),
		"tone": String(actions["tone"]),
		"focus_owner": _focus_owner_name(),
		"focus_target": String(inventory["focus_target"]),
		"inventory": inventory,
		"detail": detail,
		"actions": actions,
	}


## One initial focus for the screen, so it is keyboard/gamepad reachable. Only
## the stack calls this, and only when the screen is actually live.
func focus_initial() -> void:
	_bind_nodes()
	if _inventory_panel == null:
		return
	_focus_initialized = true
	_inventory_panel.focus_initial()


## Called by the screen stack when this screen becomes the live one.
func on_screen_shown() -> void:
	refresh()


## Called by the screen stack when a screen is pushed over this one. The
## workbench keeps no live state to pause, so it only stops taking focus.
func on_screen_hidden() -> void:
	_focus_initialized = false


## Called by the screen stack for input addressed at the live screen. Unhandled
## input is not a route: the stack forwards events so the top screen decides.
## Returns false so the stack still unwinds on `ui_cancel`.
func on_stack_input(_event: InputEvent) -> bool:
	return false


## Resolve the panels on first use rather than in `@onready`: the headless suite
## runner drives this screen before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _inventory_panel != null:
		return
	_header_label = get_node_or_null("%HeaderLabel") as Label
	_inventory_panel = get_node_or_null("%InventoryPanel") as InventoryPanel
	_detail_panel = get_node_or_null("%ItemDetailPanel") as ItemDetailPanel
	_action_bar = get_node_or_null("%ActionBar") as ActionBar
	_inventory_panel.selection_changed.connect(_on_selection_changed)
	_action_bar.action_requested.connect(_on_action_requested)
	_action_bar.slot_changed.connect(_on_slot_changed)


# --- Actions. Each returns true when the facade accepted the action --------


## Use one unit of the selected item. A rejection reports the facade's own
## reason and consumes nothing.
func act_use() -> bool:
	_bind_nodes()
	var row := _inventory_panel.selected_row()
	var reason := ItemActionRules.use_block_reason(_actor, row)
	if reason != "":
		return _reject(reason)
	var result := ItemsApi.use_item(_actor, StringName(row["def_id"]))
	if not bool(result.get("ok", false)):
		return _reject(String(result.get("reason", "use_rejected")))
	_action_bar.report(&"used", 0, String(row["display_name"]))
	_settle()
	return true


## Equip the selected item into the chosen slot. A rejected equip leaves the
## item in the inventory; the reason comes from the same conditions the facade
## checks, so the player is told why.
func act_equip() -> bool:
	_bind_nodes()
	var row := _inventory_panel.selected_row()
	var reason := ItemActionRules.equip_block_reason(_actor, row)
	if reason != "":
		return _reject(reason)
	var slot := ItemActionRules.slot_for(_actor, row, _action_bar.selected_slot())
	if not ItemsApi.equip_item(_actor, slot, row["def"]):
		return _reject("equip_rejected")
	_action_bar.report(&"equipped", 0, String(row["display_name"]), String(slot))
	_settle()
	return true


## Move whatever occupies the chosen slot back into the inventory.
func act_unequip() -> bool:
	_bind_nodes()
	var reason := ItemActionRules.unequip_block_reason(_actor, _action_bar.selected_slot())
	if reason != "":
		return _reject(reason)
	var slot := _action_bar.selected_slot()
	if not ItemsApi.unequip_to_inventory(_actor, slot):
		return _reject("unequip_rejected")
	_action_bar.report(&"unequipped", 0, "", String(slot))
	_settle()
	return true


## Break the selected bag row down into the materials it is worth. **The sink** (BL-0921).
##
## A guaranteed wearable the hero cannot use — or a piece whose subtype loses to the one
## already worn, with five slots against eight competing subtypes — is worth more as
## materials than as a bag slot, and until this existed the bar offered no verb that took
## an item OUT of the bag at all.
##
## The RULE is [Teardown]'s: nine named refusals, and a worn, unique, set-member, socketed
## or enchanted piece is protected. This action reports whichever refusal the press met,
## the way `act_unequip` reports `unequip_block_reason`, rather than pre-filtering the list
## into a button that can never light: a refusal the player can read is a rule they can
## learn, and a grey button teaches nothing.
##
## The row is looked up as an INSTANCE, because a stack has no instance to break down and
## `Teardown` answers `unknown_instance` for one — which is more honest than a silent
## no-op that leaves the player wondering whether the press registered.
func act_teardown() -> bool:
	_bind_nodes()
	var row := _inventory_panel.selected_row()
	if row.is_empty() or row.get("def") == null:
		return _reject("no_selection")
	var inventory := ItemsApi.inventory(_actor)
	if inventory == null:
		return _reject("no_inventory")
	var instance := inventory.find_instance(StringName(String(row.get("def_id", ""))))
	if instance == null:
		return _reject("unknown_instance")
	var answer := ItemsApi.teardown(_actor, instance.instance_id)
	if not bool(answer.get("ok", false)):
		return _reject(String(answer.get("reason", "teardown_rejected")))
	_action_bar.report(
		&"torn_down", int(answer.get("units", 0)), String(answer.get("def_id", ""))
	)
	_settle()
	return true


## Roll a fresh realization of the selected definition and acquire it into the
## inventory. The facade owns realization and ownership, so this action never
## has to know how an item is minted or where it lands.
func act_generate() -> bool:
	_bind_nodes()
	var row := _inventory_panel.selected_row()
	if row.is_empty() or row.get("def") == null:
		return _reject("no_selection")
	# Untyped on purpose: a panel may only reach the items module through its
	# facade, never an items type directly.
	var def = row["def"]
	if ItemsApi.inventory(_actor) == null:
		return _reject("no_inventory")
	_seed_counter += 1
	var instance := ItemsApi.generate(_actor, def, _next_seed(String(def.id)))
	if instance == null:
		return _reject("inventory_full")
	# Raw values only: the action bar owns the wording and the `%d`.
	_action_bar.report(&"generated", _slot_count(), String(def.display_name))
	_settle()
	return true


## Hand the item state to the injected save callable. Realized values are
## serialized, never rerolled, so a save/load cycle cannot change an item.
func act_save() -> bool:
	_bind_nodes()
	if _actor == null:
		return _reject("no_actor")
	if not _save_callable.is_valid():
		return _reject("no_persistence")
	var failure := String(_save_callable.call(ItemsApi.serialize(_actor)))
	if failure != "":
		return _reject("save_failed: %s" % failure)
	_action_bar.report(&"saved", _slot_count())
	_settle()
	return true


## Restore item state through the injected load callable. A payload that is not
## a dictionary is reported and changes nothing.
func act_load() -> bool:
	_bind_nodes()
	if _actor == null:
		return _reject("no_actor")
	if not _load_callable.is_valid():
		return _reject("no_persistence")
	var payload = _load_callable.call()
	if not payload is Dictionary or (payload as Dictionary).is_empty():
		return _reject("load_failed: no saved state")
	ItemsApi.deserialize(_actor, payload)
	_action_bar.report(&"loaded", _slot_count())
	_settle()
	return true


func _slot_count() -> int:
	var inventory := ItemsApi.inventory(_actor)
	if inventory == null:
		return 0
	return inventory.used_slots()


func _next_seed(def_id: String) -> int:
	return absi(hash(def_id)) % 1000003 + _seed_counter * 2654435761


# --- Plumbing --------------------------------------------------------------


func _apply_selection() -> void:
	_bind_nodes()
	var row := _inventory_panel.selected_row()
	if row.is_empty() or row.get("def") == null:
		_detail_panel.clear()
		_action_bar.set_state(
			{"enabled": _all_disabled(), "message": _message, "tone": String(_tone)}
		)
		return
	_detail_panel.show_entry(row)
	(
		_action_bar
		. set_state(
			{
				"enabled": _enabled_for(row),
				"slot": String(ItemActionRules.slot_for(_actor, row, _action_bar.selected_slot())),
				"message": _message,
				"tone": String(_tone),
			}
		)
	)


func _enabled_for(row: Dictionary) -> Dictionary:
	return {
		"use": ItemActionRules.use_block_reason(_actor, row) == "",
		"equip": ItemActionRules.equip_block_reason(_actor, row) == "",
		"unequip": ItemActionRules.unequip_block_reason(_actor, _action_bar.selected_slot()) == "",
		"generate": true,
		"save": _actor != null and _save_callable.is_valid(),
		"load": _actor != null and _load_callable.is_valid(),
	}


func _all_disabled() -> Dictionary:
	return {
		"use": false,
		"equip": false,
		"unequip": false,
		"generate": false,
		"save": false,
		"load": false,
	}


## A rejection repaints from the untouched actor, so nothing the player sees can
## drift away from the item state.
func _reject(reason: String) -> bool:
	_action_bar.clear_outcome()
	_message = "Rejected: %s" % reason
	_tone = TONE_ERROR
	refresh()
	return false


## Repaint after a success whose wording the action bar already owns.
func _settle() -> bool:
	_message = ""
	_tone = TONE_OK
	refresh()
	return true


func _focus_owner_name() -> String:
	var viewport := get_viewport()
	if viewport == null:
		return ""
	var focused := viewport.gui_get_focus_owner()
	if focused == null or not is_ancestor_of(focused):
		return ""
	return String(focused.name)


## Who is looking at what, plus the two numbers that gate every equip on screen:
## the actor's realm and the realm an item of this grade would need.
func _header_text() -> String:
	if _actor == null:
		return L.t("LOC_UI_SCREENS_3994EC31FC")
	return L.t("LOC_UI_SCREENS_35EEB6C52E") % [_actor.id, _actor.realm()]


func _on_selection_changed(_row: Dictionary) -> void:
	_apply_selection()


func _on_slot_changed(_slot: StringName) -> void:
	_apply_selection()


func _on_action_requested(action: StringName, _payload: Dictionary) -> void:
	match action:
		&"use":
			act_use()
		&"equip":
			act_equip()
		&"unequip":
			act_unequip()
		&"generate":
			act_generate()
		&"save":
			act_save()
		&"load":
			act_load()
		&"teardown":
			act_teardown()
