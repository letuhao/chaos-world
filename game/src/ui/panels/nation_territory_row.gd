class_name NationTerritoryRow
extends PanelContainer

## One claim over places, as `NationApi.summary(actor)` publishes it under
## `claims`: `{territory_id, display_name, holder_id, tier_index, held_since,
## challenger_id, yield_accrued, location_count, has_seat, upkeep}`.
##
## The line that matters is the challenger: **a claim on held ground never moves
## ground.** The row says who contests and who still holds, side by side, so a
## player reading it cannot mistake a contest for a conquest. The holder is printed
## from `holder_id` alone and this row never writes one — there is no verb on this
## screen that could, because a screen calls one facade read and nothing else.
##
## An empty dictionary is ADR 0083's FIRST state (this claim does not exist): the row
## clears and hides. A claim with a `""` challenger is not that — it is an existing
## claim with nobody contesting it, and it renders with a line saying so.
##
## `summary()` is the testable surface. Every format is the row's own.

const NO_CHALLENGER := "LOC_UI_PANELS_381F54ABB8"
const NO_HOLDER := "LOC_UI_PANELS_E1F5215ABF"
const HOLDER_PREFIX := "LOC_UI_PANELS_0D4A738829"
const CHALLENGER_PREFIX := "LOC_UI_PANELS_B0B2F4EB2A"
const UNKNOWN_TEXT := "LOC_UI_PANELS_CFBBE0095D"
const TIER_PREFIX := "tier"

var _view: Dictionary = {}
var _head: String = ""
var _holder: String = ""
var _challenge: String = ""
var _meta: String = ""
var _head_label: Label = null
var _holder_label: Label = null
var _challenge_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one claim. An empty dictionary clears and hides the row.
func show_territory(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_holder = ""
		_challenge = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var authored_name := String(_view.get("display_name", ""))
	_head = authored_name if authored_name != "" else String(_view.get("territory_id", ""))
	if _head == "":
		_head = UNKNOWN_TEXT
	var holder := String(_view.get("holder_id", ""))
	_holder = NO_HOLDER if holder == "" else "%s %s" % [HOLDER_PREFIX, holder]
	var challenger := String(_view.get("challenger_id", ""))
	_challenge = NO_CHALLENGER if challenger == "" else "%s %s" % [CHALLENGER_PREFIX, challenger]
	_meta = _meta_text()
	_render()


func clear() -> void:
	show_territory({})


## Everything the row shows, primitives only. `{}` when the claim does not exist.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	var challenger := String(_view.get("challenger_id", ""))
	return {
		"territory_id": territory_id(),
		"display_name": String(_view.get("display_name", "")),
		"holder_id": String(_view.get("holder_id", "")),
		"held_since": int(_view.get("held_since", 0)),
		"tier_index": int(_view.get("tier_index", 0)),
		"challenger_id": challenger,
		"contested": challenger != "",
		"yield_accrued": int(_view.get("yield_accrued", 0)),
		"location_count": int(_view.get("location_count", 0)),
		"has_seat": bool(_view.get("has_seat", false)),
		"upkeep": float(_view.get("upkeep", 0.0)),
		"head": _head,
		"holder_line": _holder,
		"challenge_line": _challenge,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"challenge_tone": String(_challenge_tone()),
		"card_tone": String(_card_tone()),
		"focus_target": "NationTerritoryRow",
	}


## Whether this claim EXISTS. A claim nobody holds still exists and renders; a spare
## row in the pool does not.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether somebody is contesting ground this actor already holds. A contest is a
## standoff, not a transfer — the holder line still names the holder.
func is_contested() -> bool:
	return is_filled() and String(_view.get("challenger_id", "")) != ""


func territory_id() -> String:
	return String(_view.get("territory_id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_holder_label = get_node_or_null("%HolderLabel") as Label
	_challenge_label = get_node_or_null("%ChallengeLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_head_label.text = L.t(_head)
	_head_label.theme_type_variation = _head_tone()
	_holder_label.text = L.t(_holder)
	_challenge_label.text = L.t(_challenge)
	_challenge_label.theme_type_variation = _challenge_tone()
	_challenge_label.visible = is_contested()
	_meta_label.text = L.t(_meta)


func _card_tone() -> StringName:
	return &"ContestedClaimCard" if is_contested() else &"ClaimCard"


func _head_tone() -> StringName:
	return &"ContestedClaimLabel" if is_contested() else &"SeatLabel"


## An open contest is a standoff the player is in, so it is printed in the warning
## tone; an uncontested claim is the quiet expected state.
func _challenge_tone() -> StringName:
	return &"WarnLabel" if is_contested() else &"MetaLabel"


## "tier 2 · 4 places · accrued 6 · upkeep 2.00". Every number is the row's to
## render; the screen passes raw values.
func _meta_text() -> String:
	return (
		"%s %d · %d place(s) · accrued %d · upkeep %.2f"
		% [
			TIER_PREFIX,
			int(_view.get("tier_index", 0)),
			int(_view.get("location_count", 0)),
			int(_view.get("yield_accrued", 0)),
			float(_view.get("upkeep", 0.0)),
		]
	)
