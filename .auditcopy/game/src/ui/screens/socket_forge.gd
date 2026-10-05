class_name SocketForgeScreen
extends UiScreen

## The socket forge screen: the host item, its slots with their own modifiers and
## the socket item seated in each, plus the actions a player can take right now.
##
## A pure view over one read model. The composition root pushes the socket
## program's panel state in with `bind_view()`; the screen answers an action by
## emitting `socket_action_requested`, and whoever owns the gameplay program runs
## it and pushes the next view back. No game rule lives here and no number is
## formatted here: every `%d` and `%.2f` belongs to a panel. Every action is
## offered with the gameplay reason it is unavailable.
##
## Contract: `summary()` is the testable surface, with child panel summaries
## nested under their own key.

signal socket_action_requested(action: StringName, args: Dictionary)

const MAX_SLOTS := 2
const ACTIONS: Array[StringName] = [
	&"create_slot",
	&"impute_slot",
	&"insert_socket",
	&"extract_socket",
	&"enchant",
]
const ACTION_LABELS := {
	&"create_slot": "Open socket",
	&"impute_slot": "Imprint socket",
	&"insert_socket": "Insert socket item",
	&"extract_socket": "Extract socket item",
	&"enchant": "Apply enchantment",
}
const PRIMARY_ACTION := &"enchant"

var _view: Dictionary = {}
var _host_index: int = 0
var _slot_index: int = 0
var _gem_index: int = 0
var _parent_label: Label = null
var _meta_label: Label = null
var _host_option: OptionButton = null
var _slot_option: OptionButton = null
var _gem_option: OptionButton = null
var _enchant_label: Label = null
var _actions: ActionSet = null
var _rows: Array = []


## Push the socket program's read model in. Safe to call repeatedly; the screen
## repaints from the new view and drops a selection that no longer exists.
func bind_view(view: Dictionary) -> void:
	_view = view.duplicate(true)
	_reconcile_selection()
	refresh()


## The host the player is looking at, or "" when the view names none.
func selected_host() -> String:
	return String(_view.get("parent", {}).get("instance_id", ""))


## The slot the player is acting on.
func selected_slot() -> int:
	return _slot_index


## The socket item the player has chosen to insert, or "" when none is offered.
func selected_gem() -> String:
	var owned: Array = _view.get("owned_socket_items", [])
	if _gem_index >= 0 and _gem_index < owned.size():
		return String((owned[_gem_index] as Dictionary).get("instance_id", ""))
	return ""


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null or _view.is_empty():
		return {}
	var parent: Dictionary = _view.get("parent", {})
	if parent.is_empty():
		return {}
	var eligibility: Dictionary = _view.get("eligibility", {})
	var costs: Dictionary = _view.get("costs", {})
	var preview: Dictionary = _view.get("enchant_preview", {})
	return {
		"actor_id": String(_view.get("actor_id", "")),
		"host_count": (_view.get("hosts", []) as Array).size(),
		"host_instance_id": String(parent.get("instance_id", "")),
		"host_def_id": String(parent.get("def_id", "")),
		"host_rarity": String(parent.get("rarity", "")),
		"host_equipped": String(parent.get("equipped_slot", "")) != "",
		"slot_cap": int(_view.get("slot_cap", 0)),
		"slot_count": int(_view.get("slot_count", 0)),
		"imprint_used": int(_view.get("imprint_used", 0)),
		"imprint_cap": int(_view.get("imprint_cap", 0)),
		"slot_index": _slot_index,
		"slot_kind": String(costs.get("slot_kind", "")),
		"slot_occupied": bool(costs.get("slot_occupied", false)),
		"slot_imputed": int(costs.get("slot_imputed", 0)),
		"gem_count": (_view.get("owned_socket_items", []) as Array).size(),
		"can_create": _open(eligibility, &"create_slot"),
		"can_impute": _open(eligibility, &"impute_slot"),
		"can_insert": _open(eligibility, &"insert_socket"),
		"can_extract": _open(eligibility, &"extract_socket"),
		"can_enchant": _open(eligibility, &"enchantment"),
		"reasons": _reasons(eligibility),
		"costs":
		{
			"create_slot": String(costs.get("create_slot", "")),
			"impute_slot": String(costs.get("impute_slot", "")),
			"enchantment": String(costs.get("enchantment", "")),
		},
		"enchant_allowed": int(preview.get("cap", 0)),
		"enchant_generation": int(preview.get("generation", 0)),
		"enchant_permitted": (preview.get("permitted", []) as Array).size(),
		"enchant_locked": (preview.get("locked", []) as Array).size(),
		"slots": _slot_summaries(),
		"actions": _actions.summary() if _actions != null else {},
	}


## One initial focus for the screen. Only the stack calls this, and only when
## the screen is actually live.
func focus_initial() -> void:
	_bind_nodes()
	if _actions == null:
		return
	_actions.focus_initial()
	# The panel records the landing spot; the screen mirrors it so `summary()`
	# answers for the whole screen, not just its action row.
	_focus_target = String(_actions.summary().get("focus_target", ""))


func on_screen_shown() -> void:
	refresh()


func act_create_slot() -> bool:
	return _request(&"create_slot", {"reagent_id": _cost(&"create_slot")})


func act_impute_slot() -> bool:
	return _request(&"impute_slot", {"index": _slot_index, "reagent_id": _cost(&"impute_slot")})


func act_insert_socket() -> bool:
	return _request(&"insert_socket", {"index": _slot_index, "gem_instance_id": selected_gem()})


func act_extract_socket() -> bool:
	return _request(&"extract_socket", {"index": _slot_index})


func act_enchant() -> bool:
	return _request(&"enchant", {"reagent_id": _cost(&"enchantment")})


## Look at another host the actor owns. The read model has to follow, so the
## caller re-pushes the view.
func select_host(index: int) -> void:
	_host_index = maxi(0, index)


## Act on another slot of the current host.
func select_slot(index: int) -> void:
	_slot_index = maxi(0, index)


## Choose which owned socket item to insert.
func select_gem(index: int) -> void:
	_gem_index = maxi(0, index)


func _refresh_view() -> void:
	_bind_nodes()
	var parent: Dictionary = _view.get("parent", {})
	_parent_label.text = String(parent.get("display_name", "No socket host"))
	_meta_label.text = _meta_text(parent)
	_fill_selectors()
	_fill_rows(parent)
	_enchant_label.text = _enchant_text()
	if _actions != null:
		(
			_actions
			. set_state(
				{
					"actions": ACTIONS,
					"labels": ACTION_LABELS,
					"enabled": _enabled(),
					"primary": PRIMARY_ACTION,
					"message": _message,
					"tone": _tone,
				}
			)
		)


func _bind_nodes() -> void:
	if _parent_label != null:
		return
	_parent_label = get_node_or_null("%ParentLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_enchant_label = get_node_or_null("%EnchantLabel") as Label
	_actions = get_node_or_null("%Actions") as ActionSet
	if _actions != null and not _actions.action_requested.is_connected(_on_action):
		_actions.action_requested.connect(_on_action)
	_host_option = get_node_or_null("%HostOption") as OptionButton
	_slot_option = get_node_or_null("%SlotOption") as OptionButton
	_gem_option = get_node_or_null("%GemOption") as OptionButton
	# One handler for all three selectors: the bound kind says which selection
	# moved, so a new selector costs one line here and nowhere else.
	for entry in [[_host_option, 0], [_slot_option, 1], [_gem_option, 2]]:
		var option := entry[0] as OptionButton
		if option != null and not option.item_selected.is_connected(_on_option_selected):
			option.item_selected.connect(_on_option_selected.bind(entry[1]))
	for index in MAX_SLOTS:
		_rows.append(get_node_or_null("Layout/SlotRows/SlotRow%d" % index))


## Hand an action to whoever owns the gameplay program, or report the gameplay
## reason it is unavailable and change nothing.
func _request(action: StringName, args: Dictionary) -> bool:
	var eligibility: Dictionary = _view.get("eligibility", {})
	var reason := String(eligibility.get(String(_eligibility_key(action)), "no_view"))
	if reason != "":
		set_message("Rejected: %s" % reason, TONE_ERROR)
		refresh()
		return false
	set_message("Requested %s" % action, TONE_OK)
	# The host travels with the intent: the gameplay program acts on the item this
	# screen is looking at, never on a default the player did not choose.
	var intent := args.duplicate()
	intent["host_id"] = selected_host()
	socket_action_requested.emit(action, intent)
	refresh()
	return true


func _eligibility_key(action: StringName) -> StringName:
	return &"enchantment" if action == &"enchant" else action


func _cost(action: StringName) -> String:
	return String(_view.get("costs", {}).get(String(action), ""))


func _open(eligibility: Dictionary, key: StringName) -> bool:
	return String(eligibility.get(String(key), "no_view")) == ""


## One reason string per action, in the screen's own action order, so a caller
## can read why every button is in the state it is in.
func _reasons(eligibility: Dictionary) -> Array:
	var out: Array = []
	for action in ACTIONS:
		out.append(String(eligibility.get(String(_eligibility_key(action)), "no_view")))
	return out


func _enabled() -> Dictionary:
	var eligibility: Dictionary = _view.get("eligibility", {})
	var out := {}
	for action in ACTIONS:
		out[String(action)] = _open(eligibility, _eligibility_key(action))
	return out


# --- Plumbing -----------------------------------------------------------------


## Drop a selection the new view no longer offers, so a repaint after a mutation
## can never address a slot or an item that has gone.
func _reconcile_selection() -> void:
	var hosts: Array = _view.get("hosts", [])
	var parent: Dictionary = _view.get("parent", {})
	var owned: Array = _view.get("owned_socket_items", [])
	_host_index = clampi(_host_index, 0, maxi(0, hosts.size() - 1))
	_slot_index = clampi(_slot_index, 0, maxi(0, int(parent.get("slot_count", 0)) - 1))
	_gem_index = clampi(_gem_index, 0, maxi(0, owned.size() - 1))


func _meta_text(parent: Dictionary) -> String:
	if parent.is_empty():
		return "No item that can carry a socket is owned."
	var parts: Array = [
		"%s / %s" % [parent.get("grade", ""), parent.get("subcategory", "")],
		"%s rarity" % parent.get("rarity_label", ""),
		"realm %s" % parent.get("realm", ""),
	]
	if String(parent.get("equipped_slot", "")) != "":
		parts.append("worn in %s" % parent["equipped_slot"])
	else:
		parts.append("carried")
	return " | ".join(parts)


## The slot rows are composed in the scene; a slot the item does not have is
## handed an empty dictionary and renders itself absent.
func _fill_rows(parent: Dictionary) -> void:
	var slots: Array = parent.get("slots", [])
	for index in _rows.size():
		var row = _rows[index]
		if row == null:
			continue
		var slot: Dictionary = {}
		for entry in slots:
			if int(entry.get("index", -1)) == index:
				slot = entry
		row.call("show_slot", slot)


func _slot_summaries() -> Dictionary:
	var out := {}
	for index in _rows.size():
		var row = _rows[index]
		if row == null:
			continue
		out[str(index)] = row.call("summary")
	return out


## What an enchantment of this target could produce and what it costs. Raw
## counts and names only: the numbers belong to the panels, the reasons are the
## gameplay program's.
func _enchant_text() -> String:
	var preview: Dictionary = _view.get("enchant_preview", {})
	if preview.is_empty():
		return "No item selected."
	if not bool(preview.get("ok", false)):
		return "Enchantment unavailable: %s" % preview.get("reason", "")
	return (
		"Enchantment: %d permitted outcome(s), %d locked option(s), %d of %d treatments used"
		% [
			(preview.get("permitted", []) as Array).size(),
			(preview.get("locked", []) as Array).size(),
			int(preview.get("generation", 0)),
			int(preview.get("cap", 0)),
		]
	)


## Items are data; the selector widgets themselves are composed in the scene.
func _fill_selectors() -> void:
	_fill_option(_host_option, _names(_view.get("hosts", [])), _host_index, "no socket host")
	_fill_option(
		_slot_option,
		_names(_view.get("parent", {}).get("slots", []), "kind"),
		_slot_index,
		"no slot"
	)
	_fill_option(
		_gem_option, _names(_view.get("owned_socket_items", [])), _gem_index, "no socket item"
	)


## The readable label of each entry of a selector's source list.
func _names(entries: Array, key: String = "display_name") -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String(entry.get(key, "")))
	return out


func _fill_option(option: OptionButton, labels: Array, selected: int, empty: String) -> void:
	if option == null:
		return
	option.clear()
	if labels.is_empty():
		option.add_item(empty)
		option.select(0)
		option.disabled = true
		return
	option.disabled = false
	for label in labels:
		option.add_item(String(label))
	option.select(clampi(selected, 0, labels.size() - 1))


func _on_action(action: StringName) -> void:
	match action:
		&"create_slot":
			act_create_slot()
		&"impute_slot":
			act_impute_slot()
		&"insert_socket":
			act_insert_socket()
		&"extract_socket":
			act_extract_socket()
		_:
			act_enchant()


func _on_option_selected(index: int, kind: int) -> void:
	match kind:
		0:
			select_host(index)
		1:
			select_slot(index)
		_:
			select_gem(index)
