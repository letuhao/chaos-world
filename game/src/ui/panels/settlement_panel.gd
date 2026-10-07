class_name SettlementPanel
extends PanelContainer

## What a settlement room HOLDS and who stands in it (ADR 0209).
##
## ## Install, not retire
##
## ADR 0163 decided the data model (a `RoomDef` of `kind = settlement` carrying a
## `settlement_ref` fixture naming a sect) and the seam (`DomainSettlement.summary` /
## `.resident`, read-only). What was unwired was narrower than "the class is wrong":
## the class was never CALLED. So this panel is the thing that calls it, through
## [SettlementBridge] — the same `Callable` seam `DomainBridge` already is. Retiring
## the class would silently invalidate an accepted ADR's consequences; installing it is
## four lines in a bridge and this panel.
##
## ## A settlement is the room you SELECTED, not a route of its own
##
## A settlement arrives in `rooms[]` with `kind = "settlement"` and needs no new route,
## no nav action and no second binding arm. It is keyed on the SELECTED room, exactly as
## `NpcRosterPanel` is keyed on the current location, and it takes the fixture row's
## place when the selected room is one. A screen of its own would ship-but-dead
## (DEF-0261).
##
## ## The three-state vocabulary is load-bearing (ADR 0083)
##
## `{}` = no settlement · `authors_no_settlement_ref` = a building that names no sect ·
## `unknown_settlement_ref` = it names one that does not resolve. Three DIFFERENT facts,
## and `DomainSettlement` already returns them as named refusals. A panel that collapsed
## them to "empty" would make "there is a castle here" indistinguishable from "this room
## is empty", so a refusal is shown VERBATIM by id — the `NpcRosterPanel.UNWIRED_TEXT`
## move.
##
## ## Where the institution comes from, and never from
##
## Only from `DomainSettlement`, which resolves the ref properly and refuses it by name.
## NEVER from the minimap payload: the payload publishes `kind` and `tags`, but
## `settlement_ref` is a FIXTURE, and reading a sect id out of tags is exactly the
## post-hoc heuristic ADR 0073 forbids.
##
## ## What it writes
##
## Nothing. No admit, expel, found or schedule: a ref names, it does not act.
##
## Contract: `summary()` is the testable surface, primitives only.

## What the readout says when no settlement bridge is wired. Named rather than blank,
## because "this room is not a settlement" and "this panel cannot ask" are different
## facts and a player must be able to tell them apart.
const UNWIRED_TEXT := "No settlement is wired to this screen."
## What the readout says for a room that is not a settlement. Not "empty" — the room
## simply is not one, and saying so is the honest reading.
const NOT_A_SETTLEMENT_TEXT := "This room is not a settlement."

## How many residents one row is worth naming. The module already caps its own read and
## says so with `truncated`; this bounds the RENDERED rows, and the note below names how
## many were left out rather than dropping them silently.
const MAX_RESIDENTS := 8

## One resident row. `%s - %s x%d`, with a leading count only when the group is bigger
## than one, so a group of three reads as three people and a group of one reads as a
## person rather than as "1 mob".
const ROW_TEMPLATE := "%s%s"

## The suffix naming the rest. A separate sentence rather than a bare number, because a
## number with no unit on a resident list reads as a page count.
const TRUNCATED_SUFFIX := "and others this panel does not name."

## Every `%d`/`%s` and every sentence on this surface. The screen hands raw primitives
## from the bridge and formats nothing (AGENTS.md, UI standard).
var _shown: bool = false
var _room_id: String = ""
var _ok: bool = false
var _reason: String = ""
var _ref_kind: String = ""
var _ref_id: String = ""
var _institution: String = ""
var _display_name: String = ""
var _resident_count: int = 0
var _residents: Array = []
var _truncated: bool = false
var _kind: String = ""
var _building_label: Label = null
var _institution_label: Label = null
var _resident_label: Label = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one selected room. `summary` is `DomainSettlement.summary`'s own dictionary
## verbatim; `residents` is `DomainSettlement.residents`'s. Either may be `{}` — outside
## a run, for a room that is not a settlement, and for a bridge nobody wired are three
## different states and each keeps its own wording.
##
## ## Why there is exactly ONE way in
##
## The tempting second door — a `residents` array a caller could hand over directly — is
## the defect `NpcRosterPanel` documents: a caller holding an array has no way to check
## it belongs to the room on screen, so a stale list renders as though it were the room
## the player is in.
func show_settlement(summary: Dictionary, residents: Dictionary = {}) -> void:
	_bind_nodes()
	_shown = not summary.is_empty()
	_room_id = String(summary.get("room_id", ""))
	_ok = bool(summary.get("ok", false))
	_reason = String(summary.get("reason", ""))
	_ref_kind = String(summary.get("ref_kind", ""))
	_ref_id = String(summary.get("ref_id", ""))
	_kind = String(summary.get("room_kind", ""))
	_display_name = String(summary.get("display_name", ""))
	var institution: Dictionary = summary.get("institution", {}) as Dictionary
	_institution = String(institution.get("display_name", ""))
	_residents = _capped_rows(residents.get("residents", []))
	_resident_count = _residents.size()
	_truncated = _truncated_by_panel(residents) or bool(residents.get("truncated", false))
	_render()


## Everything this panel shows, primitives only, so a headless test asserts the WORDS
## rather than pixels (ADR 0209).
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"shown": _shown,
		"room_id": _room_id,
		"ok": _ok,
		"reason": _reason,
		"ref_kind": _ref_kind,
		"ref_id": _ref_id,
		"institution": _institution,
		"resident_count": _resident_count,
		"residents": _residents.duplicate(true),
		"truncated": _truncated,
		"line": _institution_text(),
		"kind": _kind,
		"building_line": _building_text(),
		"resident_line": _resident_text(),
	}


## Whether a settlement readout can be shown at all. A screen reads this to decide
## whether this panel is a live surface or a row that says nothing is wired to it.
func has_settlement() -> bool:
	_bind_nodes()
	return _shown


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in an annotation: the headless runner drives this panel before
## a scene tree exists (AGENTS.md, UI standard). Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_building_label = get_node_or_null("%BuildingLabel") as Label
	_institution_label = get_node_or_null("%InstitutionLabel") as Label
	_resident_label = get_node_or_null("%ResidentsLabel") as Label
	_bound = _building_label != null and _institution_label != null


func _render() -> void:
	if _building_label == null:
		return
	_building_label.text = _building_text()
	_institution_label.text = _institution_text()
	# A refusal is painted in the ERROR ink and nothing else on this panel is a
	# failure, so the tone is this panel's own and the theme owns the colour.
	if not _ok and _shown:
		_institution_label.theme_type_variation = &"WarnLabel"
	else:
		_institution_label.theme_type_variation = &"MetaLabel"
	_resident_label.text = _resident_text()


## The building's own name and kind. A castle is a settlement with nothing named, and it
## reads as a BUILDING rather than as a broken sect — which is why the id leads: it is
## the handle a driver and a test match on, and the display name is what a player reads.
func _building_text() -> String:
	if not _shown:
		return UNWIRED_TEXT
	if _room_id.is_empty():
		return NOT_A_SETTLEMENT_TEXT
	if _display_name.is_empty():
		return "%s (%s)" % [_room_id, _kind]
	return "%s (%s, %s)" % [_display_name, _room_id, _kind]


## The institution the room names, or the REFUSAL ID VERBATIM.
##
## Never a blank and never a sentence this file invented: `authors_no_settlement_ref`,
## `unknown_settlement_ref` and `no_institution_lookup` are three facts the module
## distinguished on purpose, and rewriting them into one polite "nothing here" would
## collapse exactly the distinction ADR 0209 exists to preserve.
func _institution_text() -> String:
	if not _shown:
		return ""
	if not _ok:
		return _reason
	if _institution.is_empty():
		return _ref_id
	return "%s %s" % [_institution, _ref_id]


## Who stands here. The room's OWN `actor_spawn_refs` — never a sect roster, because a
## second copy of one is the ADR 0066 failure mode and the sect ledger is `sect`'s.
func _resident_text() -> String:
	if not _shown:
		return ""
	var lines: Array[String] = []
	for row in _residents:
		lines.append(_row_text(row as Dictionary))
	if _truncated:
		lines.append(TRUNCATED_SUFFIX)
	return "\n".join(lines)


## One resident row. The role leads when there is one, because a role is a TAG on an
## actor and never a class (ADR 0074), and the count is a GROUP rather than that many
## rows — so `3` names three people and `1` adds no figure at all.
func _row_text(row: Dictionary) -> String:
	var role := String(row.get("role", ""))
	if role.is_empty():
		role = String(row.get("inhabitant_id", ""))
	if role.is_empty():
		role = String(row.get("ref_id", "someone"))
	var count := int(row.get("count", 1))
	return String(ROW_TEMPLATE) % [role, "" if count <= 1 else " x%d" % count]


## The rows to paint: the module's own rows, in its own order, cut to
## [constant MAX_RESIDENTS]. A COPY, because `summary()` hands these out and a caller
## mutating them must not reach back into the panel's state.
func _capped_rows(rows: Variant) -> Array:
	var source: Array = rows as Array if rows is Array else []
	if source.size() <= MAX_RESIDENTS:
		return source.duplicate(true)
	var kept: Array = []
	for index in range(MAX_RESIDENTS):
		kept.append(source[index])
	return kept


## Whether THIS panel dropped a row the module returned, reported apart from the module's
## own `truncated` — two different causes, one visible sentence.
func _truncated_by_panel(residents: Dictionary) -> bool:
	var source: Array = residents.get("residents", []) as Array
	return source.size() > MAX_RESIDENTS
