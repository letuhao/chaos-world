class_name DifficultyPresetRow
extends PanelContainer

## One authored difficulty preset: what it costs a soul and what it pays back, and
## the one button that selects it.
##
## ## The five numbers are printed HERE, never in the screen
##
## Every `%d%%`, every share and every cap on this surface belongs to this row
## (AGENTS.md, UI standard). The screen hands `DifficultyApi.views()` rows down raw
## and renders none of it.
##
## ## Why the row knows no rule about which preset is which
##
## ADR 0129 forbids naming a preset after an ordinal, a tier or a realm, so there
## is no "this one is the hard one" fact to author here. The row therefore prints
## the SCALARS and lets a player read the consequence: a harder row has a larger
## soul-damage share and a larger death-loss cap, a weaker guardian and less credit
## for tribulation preparation, and nothing else in the row is tuned by difficulty.
##
## ## The button is a REQUEST
##
## It emits the preset id and the screen asks the composition root, so the one
## place a run's difficulty changes is the root's own seam — the same shape
## `QuestRow`'s accept button uses.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when the
## row carries no preset.

## The press. Carries the preset id ONLY.
signal select_requested(difficulty_id: StringName)

const SELECT_TEXT := "LOC_UI_PANELS_A0D3387DE3"
const SELECTED_TEXT := "LOC_UI_PANELS_251EFC8086"
## The scalar column this row leads with, and the label it reads under. The whole
## scalar set is printed; this one is the sentence a player reads first.
const LEAD_SCALAR := "soul_damage_share"
const LEAD_LABEL := "LOC_UI_PANELS_438C01D936"
## A share of one, printed as a whole percent. The fraction is `ADR 0129`'s rule —
## every scalar is a fraction of what the player already holds — so the row says so
## rather than printing a raw multiplier and letting a player read 1.0 as "double".
const PERCENT_SCALE := 100.0
const SHARE_SUFFIX := "LOC_UI_PANELS_F82303A8D4"
const NEUTRAL_MARK := "LOC_UI_PANELS_FD8C0CB415"
const NO_PRESETS := "LOC_UI_PANELS_8B2CDAD798"

var _view: Dictionary = {}
var _head: String = ""
var _scalars_line: String = ""
var _lead_line: String = ""
var _state_line: String = ""
var _head_label: Label = null
var _scalars_label: Label = null
var _lead_label: Label = null
var _state_label: Label = null
var _select_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one preset exactly as `DifficultyApi.views()` publishes it: a
## `difficulty_id` and the five scalars. The screen adds `selected`, because "which
## one this run is under" is the screen's question and not the module's. An empty
## dictionary clears the row.
func show_preset(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_head = String(_view.get("difficulty_id", ""))
	_scalars_line = _scalars_text()
	_lead_line = _lead_text()
	_state_line = _state_text()
	_render()


## Everything this row shows, primitives only. `{}` when it carries no preset, so a
## spare row in the pool is not reported as an authored one.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"difficulty_id": difficulty_id(),
		"selected": is_selected(),
		"soul_damage_share": float(_view.get(LEAD_SCALAR, 1.0)),
		"guardian_effectiveness": float(_view.get("guardian_effectiveness", 1.0)),
		"tribulation_preparation_credit": float(_view.get("tribulation_preparation_credit", 1.0)),
		"scalar_count": _view.size() - 1,
		"can_select": can_select(),
		"head": _head,
		"scalars_line": _scalars_line,
		"lead_line": _lead_line,
		"state_line": _state_line,
		"select_label": _button_text(),
	}


## The preset this row offers, or `""` when the row is empty.
func difficulty_id() -> String:
	return String(_view.get("difficulty_id", ""))


## Whether this is the preset the run is played under. Carried down from the
## screen's own read of `DifficultyApi.current_id`, never re-derived.
func is_selected() -> bool:
	return bool(_view.get("selected", false))


## Whether the select button is a live control. The run's CURRENT preset is not
## selectable again: it is already what the player is playing, and a live button
## that re-selects it would be a control with nothing behind it.
func can_select() -> bool:
	return is_filled() and not is_selected()


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


## Give the keyboard and pad a landing spot. The button when this preset may be
## selected, so focus lands where a player would act. Recorded first, because a node
## outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _select_button != null and _select_button.is_inside_tree():
		_select_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in `@onready`: the headless runner drives this row before
## a scene tree exists. Idempotent, and the connect guarded.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_scalars_label = get_node_or_null("%ScalarsLabel") as Label
	_lead_label = get_node_or_null("%LeadLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label
	_select_button = get_node_or_null("%SelectButton") as Button
	if _select_button != null and not _select_button.pressed.is_connected(_on_select):
		_select_button.pressed.connect(_on_select)


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = L.t(_head.capitalize())
	_scalars_label.text = L.t(_scalars_line)
	_lead_label.text = L.t(_lead_line)
	_state_label.text = L.t(_state_line)
	_state_label.theme_type_variation = &"OkLabel" if is_selected() else &"MetaLabel"
	_select_button.disabled = not can_select()
	_select_button.text = L.t(_button_text())
	_select_button.theme_type_variation = &"PrimaryButton"


## Every scalar, in the module's own vocabulary and in the order `views()` produced
## them. Printed rather than summarised, because ADR 0129's whole claim is that a
## preset moves a CLOSED set of fractions, and a player cannot verify a closed set
## they cannot see.
##
## Iterated with a bounded `for` over a data dictionary, never a `while` whose
## bound the body could grow: the row count is authored content, and an
## unbounded-accumulating loop here is the shape `tests/arch_rules/
## test_no_unbounded_wait.gd` exists to fail.
func _scalars_text() -> String:
	if _view.is_empty():
		return L.t(NO_PRESETS)
	var parts: Array[String] = []
	for key in _view.keys():
		var name := String(key)
		if name == "difficulty_id" or name == "selected":
			continue
		parts.append("%s %s" % [name, _share_text(name, float(_view[key]))])
	return "  ".join(parts)


## The leading scalar as a sentence, because a raw column of numbers is not a
## statement about what a preset does to a run. The neutral row says so in words:
## ADR 0129's guard holds it at exactly one, and a player choosing "the middle one"
## deserves to know choosing it changes nothing.
func _lead_text() -> String:
	if _view.is_empty():
		return ""
	var share := float(_view.get(LEAD_SCALAR, 1.0))
	# NOT "capped at X" any more. `death_loss_cap` was cut (BL-0887) because it bound on no
	# shipped preset, so the row used to promise a ceiling the arithmetic never applied — a
	# player reading "capped at 150%" while paying 150% either way was told a fact about the
	# game that was not true. The share alone is now the whole of what a death costs.
	return L.t("LOC_UI_PANELS_265FC52551") % [L.t(LEAD_LABEL), _share_text(L.t(LEAD_SCALAR), share)]


## Whether this row is the live preset, and whether selecting it would be a no-op.
func _state_text() -> String:
	if not is_selected():
		return L.t("LOC_UI_PANELS_129B5EA91D")
	return "This is the preset this run is under." + _neutral_note()


## The word a share is read in. A share of one is a whole number of percent, and
## anything else is a fraction of it — so a player never reads `1.0` and guesses.
func _share_text(name: String, value: float) -> String:
	if not is_finite(value):
		return "unmeasured"
	var percent := int(roundf(value * PERCENT_SCALE))
	return (
		L.t("LOC_UI_PANELS_3701471B5E") % percent
		if absf(percent - 100.0) > 0.001
		else "100%" + _suffix(name)
	)


## The suffix that says what a share is a share OF. Only the lead scalar a player feels on a
## death carries one; the rest are named by their own column.
func _suffix(name: String) -> String:
	if name == LEAD_SCALAR:
		return L.t(SHARE_SUFFIX)
	return ""


func _neutral_note() -> String:
	return NEUTRAL_MARK if is_neutral() else ""


## Whether this row's scalars are all exactly one, which is ADR 0129's "R1 at 1.0"
## rule applied to a preset axis: the shipped default must be arithmetically a no-op.
func is_neutral() -> bool:
	if _view.is_empty():
		return false
	for key in _view.keys():
		var name := String(key)
		if name == "difficulty_id" or name == "selected":
			continue
		if not is_equal_approx(float(_view[key]), 1.0):
			return false
	return true


func _button_text() -> String:
	if not is_filled():
		return ""
	return SELECTED_TEXT if is_selected() else SELECT_TEXT


## The press is a REQUEST. The row emits the id it was built with; the screen asks
## the composition root's seam, and nothing here writes a preset.
func _on_select() -> void:
	var id := difficulty_id()
	if id == "" or not can_select():
		return
	select_requested.emit(StringName(id))
