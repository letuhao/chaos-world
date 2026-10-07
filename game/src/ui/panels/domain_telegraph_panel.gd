class_name DomainTelegraphPanel
extends PanelContainer

## What a fixture WOULD cost you, shown BEFORE anything lands (ADR 0211).
##
## ## Why this exists, and why it is a panel rather than another line in the screen
##
## ADR 0211 made the `Arm` button into a free `inspect` — the screen no longer fires
## anything — and then the telegraph has nowhere left to live: the screen it used to
## paint is the screen that must not paint it. `domain_explore.gd` is already over its
## thousand-line budget, so the wording, the decimals and the widths live HERE, which is
## also where AGENTS.md puts them ("screens pass raw values to a panel; the panel owns
## `%d/%d`, decimals and widths").
##
## ## The four facts, and the one it refuses to show
##
## A trap's boundary, the kind of harm, the AUTHORED magnitude and the authored window
## are all published by `DomainFixtures.telegraph` as primitives, and all four are shown
## here. What is deliberately NOT shown is this actor's mitigated residual: the panel is
## handed the telegraph payload whole and never asks for `residual_share`, because a
## resolved number on a hazard readout leaks the player's own gear to the UI
## (`domain_fixtures.gd:519`). A trap that reads "3.0" here reads the same to a hero with
## four mitigation levers and a hero with none, which is the point — the boundary is
## public, the arithmetic is theirs.
##
## ## Presence is the trigger, so this panel is a WARNING and never a control
##
## There is no button on this panel. `armed` and `spent` are the LEDGER's two states and
## they are what make a telegraph legible: `armed` but not `spent` is the window the
## player can still walk out of, which is the entire reason the warning exists
## (`domain_fixtures.gd:550` publishes `boundary_visible` for the same reason).
##
## Contract: `summary()` is the testable surface, primitives only.

## What the panel says when it has been handed nothing. "Nothing is wired" and "this
## fixture is not a trap" are different facts, so they get different sentences.
const NOTHING_TEXT := "LOC_UI_PANELS_8C32D606BB"

## The heading, so a player knows what the block they are reading IS.
const TITLE_TEXT := "LOC_UI_PANELS_BAF062AB02"

## The three-state vocabulary, from the module's own ledger. A trap is never re-armed
## within a run (`domain_fixtures.gd:394`), so `spent` is terminal and says so in words
## rather than leaving a player to guess whether the floor is safe to walk back across.
const STATE_IDLE := "quiet"
const STATE_ARMED := "telegraphing"
const STATE_SPENT := "spent"

## How a magnitude is rendered. `%s` rather than `%d`: the authored share is a
## FRACTION of a health pool, and rounding it to an integer on a 100-point hero reads
## as a different number than the one the module published.
const MAGNITUDE_TEMPLATE := "LOC_UI_PANELS_16B5D7DF20"
const WINDOW_TEMPLATE := "LOC_UI_PANELS_B9C4E4A2BE"

## The whole payload, held so `summary()` answers before any frame runs. Never mutated:
## the caller may hand the same dictionary to two panels.
var _payload: Dictionary = {}
var _fixture_id: String = ""
var _kind: String = ""
var _status_id: String = ""
var _armed: bool = false
var _spent: bool = false
var _claimed: bool = false
var _bounds: Array = []
var _boundary_visible: bool = false
var _telegraph_s: float = 0.0
var _damage_share: float = 0.0
var _duration_s: float = 0.0
var _levers: Array = []
var _state: String = STATE_IDLE
var _boundary_label: Label = null
var _harm_label: Label = null
var _window_label: Label = null
var _levers_label: Label = null
var _state_label: Label = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## The one door. `telegraph` is `DomainFixtures.telegraph`'s dictionary WHOLE — the same
## payload `inspect` returns, because ADR 0211 made inspecting a trap the RIGHT play and
## this panel is what makes it worth pressing.
##
## `{}` clears the panel rather than leaving the last fixture's numbers standing: a
## hazard readout that still shows the previous trap's window after the selection moved
## is worse than one that shows nothing.
func show_telegraph(telegraph: Dictionary) -> void:
	_bind_nodes()
	_payload = telegraph.duplicate(true)
	_fixture_id = String(_payload.get("fixture_id", ""))
	_kind = String(_payload.get("kind", ""))
	_status_id = String(_payload.get("status_id", ""))
	_armed = bool(_payload.get("armed", false))
	_spent = bool(_payload.get("spent", false))
	_claimed = bool(_payload.get("claimed", false))
	_boundary_visible = bool(_payload.get("boundary_visible", false))
	_bounds = _array_of(_payload.get("bounds", []))
	_telegraph_s = float(_payload.get("telegraph_s", 0.0))
	_damage_share = float(_payload.get("damage_share", 0.0))
	_duration_s = float(_payload.get("duration_s", 0.0))
	_levers = _array_of(_payload.get("mitigation_levers", []))
	_state = _state_of()
	_render()


## Everything this panel shows, primitives only. `armed` and `spent` are published
## SEPARATELY from `state` because the tests assert the ledger itself rather than this
## panel's reading of it: a `state` this panel derived could agree with a wrong ledger.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"shown": not _payload.is_empty(),
		"fixture_id": _fixture_id,
		"kind": _kind,
		"status_id": _status_id,
		"armed": _armed,
		"spent": _spent,
		"claimed": _claimed,
		"boundary_visible": _boundary_visible,
		"bounds": _bounds.duplicate(true),
		"telegraph_s": _telegraph_s,
		"damage_share": _damage_share,
		"duration_s": _duration_s,
		"levers": _levers.duplicate(true),
		"state": _state,
		"boundary_line": _boundary_text(),
		"harm_line": _harm_text(),
		"window_line": _window_text(),
		"levers_line": _levers_text(),
		"state_line": _state_text(),
	}


## Whether this panel has something to show, so a screen can decide whether the block is
## a live readout or a row that says nothing is wired to it.
func has_telegraph() -> bool:
	_bind_nodes()
	return not _payload.is_empty()


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in an annotation: the headless runner drives this panel before
## a scene tree exists (AGENTS.md, UI standard). Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_boundary_label = get_node_or_null("%BoundaryLabel") as Label
	_harm_label = get_node_or_null("%HarmLabel") as Label
	_window_label = get_node_or_null("%WindowLabel") as Label
	_levers_label = get_node_or_null("%LeversLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label
	_bound = _state_label != null


func _render() -> void:
	if _state_label == null:
		return
	_boundary_label.text = L.t(_boundary_text())
	_harm_label.text = L.t(_harm_text())
	_window_label.text = L.t(_window_text())
	_levers_label.text = L.t(_levers_text())
	_state_label.text = L.t(_state_text())
	# THEME VARIATIONS, never `theme_override_*` (AGENTS.md, UI standard): a spent trap
	# is the one state where the panel is reporting a past consequence, and the ink is the
	# theme's to choose.
	_state_label.theme_type_variation = &"OkLabel" if _spent else &"WarnLabel"


## Which of the module's THREE ledger states this panel is describing. Read from the two
## booleans rather than from a third published word, because `armed` and `spent` are what
## the ledger actually holds and the panel must not hold a third opinion about them.
func _state_of() -> String:
	if _payload.is_empty():
		return STATE_IDLE
	if _spent:
		return STATE_SPENT
	if _armed:
		return STATE_ARMED
	return STATE_IDLE


## The boundary the trap claims, as four numbers a player could check against the floor
## plan. `%d` on all four: a tile count is a whole number, and a decimal on one would
## imply a precision the authored `Rect2i` does not have.
##
## `boundary_visible` leads the line rather than gating it. The module publishes it
## unconditionally (`domain_fixtures.gd:555`) precisely because the boundary must be
## legible whether or not the player is already standing in it — that is what makes
## leaving in time possible at all.
func _boundary_text() -> String:
	if _payload.is_empty():
		return ""
	if _bounds.size() < 4:
		return L.t("LOC_UI_PANELS_1E53323563")
	return (
		"reach: %d,%d %dx%d tiles"
		% [int(_bounds[0]), int(_bounds[1]), int(_bounds[2]), int(_bounds[3])]
	)


## The kind of harm and the AUTHORED magnitude. `status_id` is the harm's own name and
## `kind` says what kind of fixture is doing it, and both are shown because a player
## deciding whether to step onto a tile needs to know what it costs and not just how much.
##
## ## Why `damage_share` and never `residual_share`
##
## The module refuses to leak a resolved number into a telegraph
## (`domain_fixtures.gd:519`), and this panel is handed the telegraph alone. A hero with
## four levers and a hero with none read the SAME figure here, which is honest: the floor
## is dangerous to everyone and the player's own gear is their own business.
func _harm_text() -> String:
	if _payload.is_empty():
		return ""
	var share := MAGNITUDE_TEMPLATE % _damage_share
	if _status_id.is_empty():
		return L.t("LOC_UI_PANELS_2A19B25A84") % [_kind_name(), share]
	return L.t("LOC_UI_PANELS_50ABC461B3") % [_kind_name(), _status_id, share]


## The authored window and how long the harm then lasts. The window is the number that
## matters — it is how long a player has to leave — so it leads, and the burn that
## follows is the thing they are stepping into.
func _window_text() -> String:
	if _payload.is_empty():
		return ""
	return (
		"window %s, then burns for %s"
		% [WINDOW_TEMPLATE % _telegraph_s, WINDOW_TEMPLATE % _duration_s]
	)


## The authored counterplay. Named rather than numbered because a lever the player cannot
## name is not counterplay, and an empty list says the floor has none rather than
## implying the panel failed to find them.
func _levers_text() -> String:
	if _payload.is_empty():
		return ""
	if _levers.is_empty():
		return L.t("LOC_UI_PANELS_00879DEA99")
	return L.t("LOC_UI_PANELS_7D079853CB") % ", ".join(_levers)


## The ledger state, in words. `spent` is terminal within a run (ADR 0211's one-way
## machine), so the sentence says the floor is already clear rather than leaving a player
## to wonder whether walking back across it is free.
func _state_text() -> String:
	if _payload.is_empty():
		return L.t(NOTHING_TEXT)
	match _state:
		STATE_SPENT:
			return L.t("LOC_UI_PANELS_D895E653CB")
		STATE_ARMED:
			return L.t("LOC_UI_PANELS_5846F5E8A0")
		_:
			return L.t("LOC_UI_PANELS_52E6906A36")


func _kind_name() -> String:
	return "trap" if _kind.is_empty() else _kind


func _array_of(value: Variant) -> Array:
	return value as Array if value is Array else []
