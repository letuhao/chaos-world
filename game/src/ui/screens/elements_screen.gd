class_name ElementsScreen
extends UiScreen

## The elements/mastery screen (ADR 0004, BL-0095). A pure consumer of the `elements`
## facade: it renders `ElementsApi.preview` and `ElementsApi.roster` and calls facade
## actions, never module internals.
##
## ## Where the NUMBERS live
##
## The screen's own labels carry names and state words only. Every number is a
## `StatRow`'s: the screen hands down raw `current`/`maximum` values and the panel owns
## the formatting (`%d/%d`, decimals, widths), which is the one-number-format rule. The
## per-element rows are grown through `StatRow.create()` — the panel instancing its own
## composition — and clamped through `RowBudget.cap`, so a runaway list truncates
## rather than allocates.
##
## ## The element-scoped verbs and their selection
##
## `practise` and `elixir` act on ONE element: the least-trained element the body
## carries a SPARK for. The pick is made on every refresh and RECORDED on the summary
## (`selected`), so a player (or a test) reads back which element a press trained
## rather than inferring it from the outcome.
##
## ## Contract
##
## `summary()` is the testable surface: the path read, the roster, the action set's
## summary, the step the facade charges for a sitting, and the element rows' summaries
## nested under `element_rows`.

const SELECTION_NONE := &""

var _actions: ActionSet = null
var _rank_label: Label = null
var _conditions_label: Label = null
var _element_list: VBoxContainer = null
var _mastery_row: StatRow = null
var _rows: Dictionary = {}
## The element the element-scoped verbs act on. See the docblock above.
var _selected_element: StringName = SELECTION_NONE


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var live := ElementsApi.preview(_actor)
	var view := {
		"enrolled": not live.is_empty(),
		"rank": live.get("rank", ""),
		"stage": live.get("stage", ""),
		"target": live.get("target", ""),
		"mastery": live.get("mastery", 0.0),
		"threshold": live.get("threshold", -1.0),
		"can_act": live.get("can_advance", false),
		"elements": ElementsApi.roster(_actor),
		"selected": String(_selected_element),
		"steps": _steps(),
	}
	_feed_children(live)
	view["mastery_row"] = _mastery_row.summary() if _mastery_row != null else {}
	view["actions"] = _actions.summary() if _actions != null else {}
	view["element_rows"] = _rows_summary()
	return view


# --- rendering ---------------------------------------------------------------------


func _refresh_view() -> void:
	_bind_nodes()
	var live := ElementsApi.preview(_actor) if _actor != null else {}
	_feed_children(live)
	_render_elements()
	_render_actions(live)
	_render_rank(live)


## Hand the facade's raw values to the child panels. Shared by `refresh()` and
## `summary()` so a child's reported state is never one refresh stale.
func _feed_children(live: Dictionary) -> void:
	if _mastery_row == null:
		return
	var mastery := float(live.get("mastery", 0.0))
	var threshold := float(live.get("threshold", -1.0))
	(
		_mastery_row
		. set_state(
			{
				"name": "Total mastery",
				"current": mastery,
				# A bar needs a positive maximum: at an unreadable threshold the row
				# shows the mastery against itself rather than dividing by zero.
				"maximum": threshold if threshold > 0.0 else maxf(1.0, mastery),
				"decimals": 0,
				"mode": StatRow.MODE_BAR,
			}
		)
	)


## One row per element, grown to fit and clamped. Existing rows are reused by id, so a
## refresh repaints rather than rebuilds.
func _render_elements() -> void:
	if _element_list == null or _actor == null:
		return
	var roster := ElementsApi.roster(_actor)
	var pick := _pick_element()
	var threshold := float(ElementsApi.preview(_actor).get("threshold", -1.0))
	var shown := mini(RowBudget.cap(roster.size()), roster.size())
	for index in shown:
		var entry := roster[index] as Dictionary
		var id := StringName(entry.get("id", ""))
		var row: StatRow = _rows.get(id)
		if row == null:
			row = StatRow.create()
			if row == null:
				continue
			_element_list.add_child(row)
			_rows[id] = row
		var mastery := float(entry.get("mastery", 0.0))
		(
			row
			. set_state(
				{
					"name": String(entry.get("name", "")),
					"current": mastery,
					"maximum": threshold if threshold > 0.0 else maxf(1.0, mastery),
					"decimals": 0,
					"mode": StatRow.MODE_BAR,
					"selected": id == pick,
				}
			)
		)


func _render_actions(live: Dictionary) -> void:
	if _actions == null:
		return
	var enrolled := not live.is_empty()
	var pick := _selected_element
	(
		_actions
		. set_state(
			{
				"actions": [&"awaken", &"practise", &"elixir", &"advance"],
				"labels":
				{
					"awaken": "Awaken",
					"practise": "Practise",
					"elixir": "Use Elixir",
					"advance": "Advance",
				},
				"enabled":
				{
					"awaken": not enrolled,
					"practise": enrolled and pick != SELECTION_NONE,
					"elixir": enrolled and pick != SELECTION_NONE,
					"advance": enrolled and bool(live.get("can_advance", false)),
				},
				"primary": &"advance",
				"message": _message,
				"tone": _tone,
			}
		)
	)


## The rank line. Names only: the stage vocabulary and the next realm's stage, both
## authored strings the facade publishes.
func _render_rank(live: Dictionary) -> void:
	if _rank_label == null:
		return
	if live.is_empty():
		_rank_label.text = L.t("LOC_UI_SCREENS_DED9163A97")
		return
	var target := String(live.get("target", ""))
	var stage := String(live.get("stage", ""))
	if target.is_empty():
		_rank_label.text = L.t("LOC_UI_SCREENS_D17F0990E5") % stage
		return
	_rank_label.text = L.t("LOC_UI_SCREENS_8472AD32C5") % [stage, target]


func _conditions_text(live: Dictionary) -> String:
	if live.is_empty():
		return ""
	if bool(live.get("can_advance", false)):
		return L.t("LOC_UI_SCREENS_2AB419BDE8")
	return L.t("LOC_UI_SCREENS_29F89CDD00")


# --- the verbs ---------------------------------------------------------------------


## Enroll the path. The S2 ruling calls this the Awaken action: explicit, and the only
## door (nothing enrolls implicitly).
func act_awaken() -> void:
	if _actor == null:
		return
	var result := ElementsApi.begin(_actor)
	if bool(result.get("ok", false)):
		set_message("The elements answer.", TONE_OK)
	else:
		set_message("Already awakened.", TONE_ERROR)
	refresh()


## One sitting on the selected element. The facade owns the step it is charged at.
func act_practise() -> void:
	if _actor == null:
		return
	var pick := _pick_element()
	if pick == SELECTION_NONE:
		set_message("No element to train.", TONE_ERROR)
		refresh()
		return
	if ElementsApi.practise(_actor, pick, ElementsApi.PRACTICE_STEP):
		set_message("Trained %s." % _name_of(pick), TONE_OK)
	else:
		set_message("%s cannot be trained." % _name_of(pick), TONE_ERROR)
	refresh()


## Drink the selected element's authored elixir.
func act_use_elixir() -> void:
	if _actor == null:
		return
	var pick := _pick_element()
	if pick == SELECTION_NONE:
		set_message("No element to infuse.", TONE_ERROR)
		refresh()
		return
	var result := ElementsApi.use_elixir(_actor, pick)
	if bool(result.get("ok", false)):
		set_message("Infused %s." % _name_of(pick), TONE_OK)
	else:
		var reason := String(result.get("reason", ""))
		if reason == "no_elixir":
			set_message("%s elixir absent." % _name_of(pick), TONE_ERROR)
		elif reason == "no_spark":
			set_message("%s has no spark." % _name_of(pick), TONE_ERROR)
		else:
			set_message("The elixir was refused.", TONE_ERROR)
	refresh()


## The climb: paid in total mastery against the next realm's authored threshold.
func act_advance() -> void:
	if _actor == null:
		return
	var result := ElementsApi.advance(_actor)
	if bool(result.get("ok", false)):
		var live := ElementsApi.preview(_actor)
		set_message("Risen to %s." % String(live.get("stage", "")), TONE_OK)
	else:
		set_message(_refusal_text(String(result.get("reason", ""))), TONE_ERROR)
	refresh()


## Every refusal the facade names, as a state word rather than a number.
func _refusal_text(reason: String) -> String:
	match reason:
		"not_enrolled":
			return L.t("LOC_UI_SCREENS_B92081109E")
		"insufficient_mastery":
			return L.t("LOC_UI_SCREENS_BB1E36324F")
		"max_rank":
			return L.t("LOC_UI_SCREENS_609AB4CAF6")
		"no_progress_source":
			return L.t("LOC_UI_SCREENS_7D857BF25D")
		_:
			return L.t("LOC_UI_SCREENS_B3D069D3E7")


# --- plumbing ----------------------------------------------------------------------


## The facade owns its step sizes, so the screen reports the facade's numbers rather
## than inventing its own (ADR 0038: steps live in the facade).
func _steps() -> Dictionary:
	return {"practise": ElementsApi.PRACTICE_STEP}


## The least-trained element the body carries a SPARK for, or `SELECTION_NONE`. Stable
## order (the roster's) so a tie picks the same element every refresh.
func _pick_element() -> StringName:
	_selected_element = SELECTION_NONE
	if _actor == null:
		return _selected_element
	var best_mastery := 0.0
	for entry in ElementsApi.roster(_actor):
		var row := entry as Dictionary
		if not bool(row.get("spark", false)):
			continue
		var mastery := float(row.get("mastery", 0.0))
		if _selected_element == SELECTION_NONE or mastery < best_mastery:
			_selected_element = StringName(row.get("id", ""))
			best_mastery = mastery
	return _selected_element


## The authored display name of an element id, from the roster the facade publishes.
func _name_of(element_id: StringName) -> String:
	if _actor == null:
		return String(element_id)
	for entry in ElementsApi.roster(_actor):
		var row := entry as Dictionary
		if StringName(row.get("id", "")) == element_id:
			return String(row.get("name", element_id))
	return String(element_id)


func _rows_summary() -> Dictionary:
	var out := {}
	for key in _rows:
		var row: StatRow = _rows[key]
		if row != null:
			out[String(key)] = row.summary()
	return out


func _bind_nodes() -> void:
	super()
	if _actions != null:
		return
	_actions = get_node_or_null("%Actions") as ActionSet
	_rank_label = get_node_or_null("%RankLabel") as Label
	_conditions_label = get_node_or_null("%ConditionLabel") as Label
	_element_list = get_node_or_null("%ElementList") as VBoxContainer
	_mastery_row = get_node_or_null("%MasteryRow") as StatRow
	if _actions != null and not _actions.action_requested.is_connected(_on_action):
		_actions.action_requested.connect(_on_action)


func _render() -> void:
	if _conditions_label == null or _actor == null:
		return
	_conditions_label.text = L.t(_conditions_text(ElementsApi.preview(_actor)))


func focus_initial() -> void:
	_bind_nodes()
	var live := ElementsApi.preview(_actor) if _actor != null else {}
	var target := _button_name(&"awaken")
	if not live.is_empty():
		target = (
			_button_name(&"advance")
			if bool(live.get("can_advance", false))
			else _button_name(&"practise")
		)
	_focus_target = target
	var button := _find_button(target)
	if button != null and button.is_inside_tree():
		button.grab_focus()


func _on_action(action: StringName) -> void:
	match action:
		&"awaken":
			act_awaken()
		&"practise":
			act_practise()
		&"elixir":
			act_use_elixir()
		_:
			act_advance()


func _button_name(action: StringName) -> String:
	return "%sButton" % String(action).to_pascal_case()


func _find_button(button_name: String) -> Button:
	if _actions == null or button_name.is_empty():
		return null
	for child in _actions.get_children():
		var found := _search_button(child, button_name)
		if found != null:
			return found
	return null


func _search_button(node: Node, button_name: String) -> Button:
	if node is Button and String(node.name) == button_name:
		return node as Button
	for child in node.get_children():
		var found := _search_button(child, button_name)
		if found != null:
			return found
	return null
