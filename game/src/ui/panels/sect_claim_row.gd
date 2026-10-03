class_name SectClaimRow
extends PanelContainer

## One row of a sect member's claim, as `SectApi.summary(actor)` publishes it: the
## institution, the position and its authored duties and authorities, standing and
## its share of the cap, and what is still owed.
##
## ## Position and standing are two facts, and this row never collapses them
##
## ADR 0064's split, carried forward unchanged by ADR 0083: a member can hold a high
## position on thin standing, and can hold thick standing in no position at all.
## That gap is the whole politics layer, so this row prints the position and the
## standing as **two separate lines** rather than as one derived rank — a screen
## that rendered `rank = standing / 20` would have built a spreadsheet and thrown
## away the design.
##
## ## A refusal is a third state, not an empty row
##
## `show_claim({})` is ADR 0083's FIRST state — no claim exists, row hidden.
## `show_refusal({"reason": R})` is the third: the action exists and is refused, and
## `R` is an authored constant the facade chose rather than a string this row
## invented. An unaffiliated member is rendered as an explicit refusal row, not as
## a blank page.
##
## `summary()` is the testable surface. Every format is the row's own.

const UNSWORN := "Sworn to nothing"
const NO_POSITION := "No office held"
const NO_DUTIES := "no duty authored"
const OWE_PREFIX := "Owes"
const NOTHING_OWED := "Nothing owed"
const PERCENT_SUFFIX := "%"
const UNKNOWN_TEXT := "Institution unnamed"
const UNKNOWN_POSITION := "Office unnamed"

var _view: Dictionary = {}
var _reason: String = ""
var _institution: String = ""
var _position: String = ""
var _standing: String = ""
var _duty: String = ""
var _meta: String = ""
var _institution_label: Label = null
var _position_label: Label = null
var _standing_label: Label = null
var _duty_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one claim as the facade publishes it. An empty dictionary is a member with
## no claim at all, which is the NORMAL starting state (ADR 0083): it renders the
## `not_a_member` refusal rather than hiding, so "you belong to nothing" is a
## sentence on the page and not an absence of one.
func show_claim(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_reason = "not_a_member"
		_render()
		return
	_view = view.duplicate(true)
	_reason = ""
	_render()


## Render a refusal: `{ok: false, reason: "<named constant>"}`. The reason is shown
## as the facade authored it, never as prose this row composed, because a refusal a
## panel had to word is a refusal the player cannot act on.
func show_refusal(result: Dictionary) -> void:
	_bind_nodes()
	_view = (result as Dictionary).duplicate(true)
	_reason = String(_view.get("reason", ""))
	_render()


func clear() -> void:
	show_claim({})


## Everything the row shows, primitives only. `{}` when the row carries nothing at
## all — a row with no view AND no reason is not a claim and not a refusal, so it
## says nothing rather than inventing either.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty() and _reason == "":
		return {}
	_compute_lines()
	return {
		"refused": _reason != "",
		"reason": _reason,
		"is_member": not bool(_view.get("is_member", false)) and _reason == "",
		"sect_id": String(_view.get("sect_id", "")),
		"sect_name": String(_view.get("sect_name", "")),
		"doctrine_id": String(_view.get("doctrine_id", "")),
		"position_id": String(_view.get("position_id", "")),
		"position_name": String(_view.get("position_name", "")),
		"standing": int(_view.get("standing", 0)),
		"standing_cap": int(_view.get("standing_cap", 0)),
		"standing_ratio": float(_view.get("standing_ratio", 0.0)),
		"standing_percent": float(_view.get("standing_percent", 0.0)),
		"duties": _string_list(_view.get("duties", [])),
		"authorities": _string_list(_view.get("authorities", [])),
		"teaches": bool(_view.get("teaches", false)),
		"institution_line": _institution,
		"position_line": _position,
		"standing_line": _standing,
		"duty_line": _duty,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"focus_target": "SectClaimRow",
	}


## Whether the row carries something worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty() or _reason != ""


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _institution_label != null:
		return
	_institution_label = get_node_or_null("%InstitutionLabel") as Label
	_position_label = get_node_or_null("%PositionLabel") as Label
	_standing_label = get_node_or_null("%StandingLabel") as Label
	_duty_label = get_node_or_null("%DutyLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _institution_label == null:
		return
	visible = is_filled()
	theme_type_variation = &"RefusedCard" if _reason != "" else &"ClaimCard"
	if not visible:
		return
	_compute_lines()
	_institution_label.text = _institution
	_institution_label.theme_type_variation = _head_tone()
	_position_label.text = _position
	_standing_label.text = _standing
	_duty_label.text = _duty
	_duty_label.visible = _duty != ""
	_meta_label.text = _meta


## Every line this row prints, computed once from the view. Split out so `summary()`
## and `_render()` can never disagree about what the row says.
func _compute_lines() -> void:
	if _reason != "":
		_institution = _reason
		_position = ""
		_standing = ""
		_duty = ""
		_meta = "refused · no claim is written"
		return
	if not bool(_view.get("is_member", false)):
		_institution = UNSWORN
		_position = ""
		_standing = ""
		_duty = ""
		_meta = "the three tiers are peers, not a nest · join one to hold a claim"
		return
	var name := String(_view.get("sect_name", ""))
	_institution = name if name != "" else String(_view.get("sect_id", UNKNOWN_TEXT))
	var position := String(_view.get("position_name", ""))
	if position == "":
		position = String(_view.get("position_id", ""))
	_position = NO_POSITION if position == "" else position
	_standing = (
		"%d / %d standing · %d%s recognised"
		% [
			int(_view.get("standing", 0)),
			int(_view.get("standing_cap", 0)),
			int(roundf(float(_view.get("standing_percent", 0.0)) * 100.0)),
			PERCENT_SUFFIX,
		]
	)
	var duties := _string_list(_view.get("duties", []))
	_duty = _duty_text() if not duties.is_empty() else ""
	_meta = _meta_text()


## A position is a duty, not a level (ADR 0083), so a claim that names an office
## names what the office obliges. With no office held there is no duty line at all,
## rather than a placeholder duty.
func _duty_text() -> String:
	var duties := _string_list(_view.get("duties", []))
	if duties.is_empty():
		return ""
	var position := String(_view.get("position_name", ""))
	if position == "":
		position = String(_view.get("position_id", UNKNOWN_POSITION))
	return "%s: %s" % [position, ", ".join(duties)]


func _meta_text() -> String:
	var obligations: Dictionary = _view.get("obligations", {}) as Dictionary
	if obligations.is_empty():
		return "%s · %s" % [NOTHING_OWED, NO_DUTIES]
	var terms: Array = []
	for term_id in obligations.keys():
		terms.append("%s %d" % [String(term_id), int(obligations[term_id])])
	return "%s: %s" % [OWE_PREFIX, ", ".join(terms)]


func _head_tone() -> StringName:
	return &"WarnLabel" if _reason != "" else &"ClaimLabel"


func _string_list(values: Variant) -> Array:
	var out: Array = []
	if not (values is Array):
		return out
	for value in values as Array:
		out.append(String(value))
	return out
