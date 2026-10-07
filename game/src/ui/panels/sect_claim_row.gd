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

const UNSWORN := "LOC_UI_PANELS_3221B2A48E"
const NO_POSITION := "LOC_UI_PANELS_9066CF9FA5"
const NO_DUTIES := "LOC_UI_PANELS_7041A839DB"
const OWE_PREFIX := "LOC_UI_PANELS_194E59F2BC"
const NOTHING_OWED := "LOC_UI_PANELS_40F3AB82C2"
const PERCENT_SUFFIX := "%"
const UNKNOWN_TEXT := "LOC_UI_PANELS_35562BCB7A"
const UNKNOWN_POSITION := "LOC_UI_PANELS_EEFD106570"
## The facade's own refusal constant for a hero sworn to nothing
## (`SectApi.NOT_A_MEMBER`). Named here rather than inlined so the row renders the
## MODULE's string, and a test greps the constant rather than a hand-typed copy.
const NOT_A_MEMBER := "not_a_member"

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
		_reason = NOT_A_MEMBER
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


## Empty the row completely — no view and no reason, so `summary()` reports `{}`.
##
## This is deliberately NOT `show_claim({})`: an unaffiliated hero and a cleared row
## are different claims about the world. `show_claim({})` renders the `not_a_member`
## sentence, because "you are sworn to nothing" is a fact worth showing, while
## `clear()` means "this row carries nothing at all" and is what a spare pool row in
## the pool reports. Collapsing the two would make an unaffiliated hero read as a
## missing widget.
func clear() -> void:
	_bind_nodes()
	_view = {}
	_reason = ""
	_render()


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
		# Read straight off the view, and a REFUSAL is never a membership. Inverting
		# the view's own flag here reported an unaffiliated hero as a member, which
		# is the one claim this row exists to get right in both directions.
		"is_member": _reason == "" and bool(_view.get("is_member", false)),
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
	L.localize_tree(self)
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
	_institution_label.text = L.t(_institution)
	_institution_label.theme_type_variation = _head_tone()
	_position_label.text = L.t(_position)
	_standing_label.text = L.t(_standing)
	_duty_label.text = L.t(_duty)
	_duty_label.visible = _duty != ""
	_meta_label.text = L.t(_meta)


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
	_standing = _standing_text(position)
	var duties := _string_list(_view.get("duties", []))
	_duty = _duty_text() if not duties.is_empty() else ""
	_meta = _meta_text()


## The standing line, and it NAMES THE OFFICE the standing belongs to.
##
## This is not decoration: ADR 0064's split is that a position and a standing are
## two independent facts, and a standing printed with no office attached would read
## as one derived rank — exactly the spreadsheet the split exists to prevent. The
## office leads the line and the numbers follow it, so a reader sees "Bulwark, and
## here is how much standing Bulwark's holder has" as two claims rather than one.
##
## With no office held there is no office to name, so the line carries the standing
## alone and still renders: a member with thick standing and no position is an
## ordinary state (ADR 0083), not a blank row.
func _standing_text(position: String) -> String:
	var numbers := (
		"%d / %d standing · %d%s recognised"
		% [
			int(_view.get("standing", 0)),
			int(_view.get("standing_cap", 0)),
			int(roundf(float(_view.get("standing_percent", 0.0)) * 100.0)),
			PERCENT_SUFFIX,
		]
	)
	return numbers if position == "" else "%s · %s" % [position, numbers]


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
	return L.t("LOC_UI_PANELS_D9CD377026") % [position, ", ".join(duties)]


func _meta_text() -> String:
	var obligations: Dictionary = _view.get("obligations", {}) as Dictionary
	if obligations.is_empty():
		return L.t("LOC_UI_PANELS_C59A938FCC") % [L.t(NOTHING_OWED), L.t(NO_DUTIES)]
	var terms: Array = []
	for term_id in obligations.keys():
		terms.append("%s %d" % [String(term_id), int(obligations[term_id])])
	return L.t("LOC_UI_PANELS_D9CD377026") % [L.t(OWE_PREFIX), ", ".join(terms)]


func _head_tone() -> StringName:
	return &"WarnLabel" if _reason != "" else &"ClaimLabel"


func _string_list(values: Variant) -> Array:
	var out: Array = []
	if not (values is Array):
		return out
	for value in values as Array:
		out.append(String(value))
	return out
