class_name NpcRosterPanel
extends PanelContainer

## Who is standing in the room the player is actually standing in.
##
## ## Why this is a panel and not a screen
##
## The roster is one question asked of the place the player is already standing in, and
## the page that shows the place is [code]domain_explore[/code]. A route of its own
## would need a `ScreenRoutes` entry, a nav action and a binding arm for a list with no
## verb at all — and an unrouted screen measures as shipped-but-dead, which is the exact
## failure DEF-0261 is being closed out of.
##
## ## The one rule this panel exists to enforce: IT KEYS ON THE LOCATION, NEVER ON THE BOOT CAST
##
## [method show_room] is handed ONE payload — the tracked current room — and the roster
## it paints came out of that same payload. There is no `show_boot_settlement` and no
## `npcs` argument a caller could hand over directly, so there is no seam on which the
## stale-cast panel can be written. [method ItemWorkbenchPlay.npc_presence]'s boot-time
## settlement is deliberately NOT wired here: it is minted once at boot into
## [code]mortal_plains[/code] and never restocked, so keying a roster on it would show
## four people who may have left, in a room the player is not in, with no way for the
## player to tell.
##
## ## An empty room is an EMPTY roster, and it never borrows a neighbour's cast
##
## The count, the rows and the empty line all come from the same filtered read, so a
## place with nobody in it renders `0` and says so. This is asserted rather than
## described: `tests/ui/test_npc_roster_panel.gd` stocks a room, walks the player to an
## empty one, and fails if a single neighbour's name survives.
##
## ## What it owns
##
## Every `%d`, every `%s` and every sentence. The screen hands raw primitives and
## formats nothing (AGENTS.md, UI standard). `summary()` reports the raw counts AND the
## text set on the labels, so a headless test asserts the wording instead of pixels.
##
## Contract: `summary()` is the testable surface, primitives only.

## What the roster says when the composition root wired nothing. A missing seam is
## named on the row rather than painted as an empty room, because "nobody is here" and
## "this panel is not connected" are different facts and a player must be able to tell.
const UNWIRED_TEXT := "The roster of this place is not wired to anything."
## A place the player has not been placed in. Not "empty" — there is no place at all.
const NOWHERE_TEXT := "You are standing nowhere in particular."
## An empty room. The honest reading, and the one that must never be a neighbour's cast.
const EMPTY_ROOM_TEXT := "Nobody else stands here."

## How many people one row is worth naming. The read model already caps the list and
## says so with `truncated`; this bounds the RENDERED rows so a busy settlement does not
## grow an unbounded label, and the note below says how many were left out.
const MAX_ROWS := 8

## What each roster row reads. The columns are the module's own read-model keys — a row
## invents no field, so the panel cannot show a thing the module does not track.
const ROW_TEMPLATE := "%s - %s%s"

var _wired: bool = false
var _located: bool = false
var _location_id: String = ""
var _display_name: String = ""
var _count: int = 0
var _truncated: bool = false
var _rows: Array = []
var _room_label: Label = null
var _roster_label: Label = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Render the tracked current room and the cast standing in it. `room` is the
## composition root's [code]NpcBoot.where_is[/code] answer verbatim: the place AND the
## presence for that exact place.
##
## ## Why there is exactly ONE way in
##
## The tempting second door — "let the caller pass a `npcs` array in so the panel is
## testable without the seam" — is the defect itself. A caller holding an array has no
## way to check it belongs to the room on screen, so a stale array renders as though it
## were the current room, and the panel can no longer tell an honest screen from a lying
## one. [code]{}[/code] is therefore the un-bound state rather than an empty roster, and
## a headless test drives it through the seam like any other caller would.
func show_room(room: Dictionary) -> void:
	_bind_nodes()
	_wired = not room.is_empty()
	var here: Dictionary = room.get("here", {}) as Dictionary
	_located = bool(room.get("located", false))
	_location_id = String(room.get("location_id", ""))
	_display_name = String(room.get("display_name", ""))
	# **Read the count from the rows the panel will actually paint.** The module's `count`
	# is the honest figure for the whole room; this panel renders a bounded number of
	# them, and a header that claimed a different number than the list beneath it would
	# be the second, contradicting copy of the same fact.
	_rows = _capped_rows(here)
	_count = _rows.size()
	_truncated = _truncated_by_panel(here) or bool(here.get("truncated", false))
	_render()


## Everything this panel shows, primitives only. A roster row is a flat dictionary of
## primitives, never a `Node` or a resource, so the contract a screen test asserts is
## the contract a player reads.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"wired": _wired,
		"located": _located,
		"location_id": _location_id,
		"display_name": _display_name,
		"count": _count,
		"truncated": _truncated,
		"rows": _rows.duplicate(true),
		"room_line": _room_text(),
		"roster_line": _roster_text(),
	}


## Whether a roster can be shown at all. A screen reads this to decide whether the
## panel is a live surface or a row that says nothing is wired to it.
func has_roster() -> bool:
	_bind_nodes()
	return _wired and _located


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in `@onready`: the headless runner drives this panel before a
## scene tree exists, so a binding that waits for `_ready` never happens. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_room_label = get_node_or_null("%RoomLabel") as Label
	_roster_label = get_node_or_null("%RosterLabel") as Label
	_bound = _room_label != null and _roster_label != null


func _render() -> void:
	if _room_label == null:
		return
	_room_label.text = _room_text()
	_roster_label.text = _roster_text()


## The room's identity, in the module's own words. An authored `location_id` is printed
## as one and the `display_name` leads when the content supplies one, because the id is
## the handle a driver and a test match on while the name is what a player reads.
func _room_text() -> String:
	if not _wired:
		return UNWIRED_TEXT
	if not _located or _location_id.is_empty():
		return NOWHERE_TEXT
	if _display_name.is_empty():
		return "This place: %s" % _location_id
	return "This place: %s (%s)" % [_display_name, _location_id]


## The cast, one row each, or the honest sentence for an empty room. Never borrowed:
## an empty list renders [constant EMPTY_ROOM_TEXT] and nothing else.
func _roster_text() -> String:
	if not _wired:
		return ""
	if not _located:
		return ""
	if _rows.is_empty():
		return EMPTY_ROOM_TEXT
	var lines: Array[String] = []
	# Each `for` walks `_rows`, which was built BEFORE this loop and which this loop
	# never appends to — the shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts.
	for row in _rows:
		lines.append(_row_text(row as Dictionary))
	if _truncated:
		lines.append("and others this panel does not name.")
	return "\n".join(lines)


## One row. The name leads; the stage is named when the module tracked one, and the
## tier only when it differs from the stage — a cultivator's own stage is the more
## interesting fact and printing both unconditionally buries it.
func _row_text(row: Dictionary) -> String:
	var name := String(row.get("display_name", ""))
	if name.is_empty():
		name = String(row.get("npc_id", "an unnamed figure"))
	var stage := String(row.get("stage_label", ""))
	var tier := String(row.get("tier", ""))
	var tail := stage if not stage.is_empty() else tier
	return String(ROW_TEMPLATE) % [name, String(row.get("presence", "")), _tail(tail)]


## The parenthetical, or nothing. An npc with no stage and no tier contributes no
## punctuation at all rather than a dangling separator.
func _tail(text: String) -> String:
	return "" if text.is_empty() else " (%s)" % text


## The rows to paint: the module's own rows, in its own order, cut to [constant
## MAX_ROWS]. A COPY, because `summary()` hands these out and a caller mutating them
## must not reach back into the panel's state.
func _capped_rows(here: Dictionary) -> Array:
	var source: Array = here.get("npcs", []) as Array
	if source.size() <= MAX_ROWS:
		return source.duplicate(true)
	var kept: Array = []
	for index in range(MAX_ROWS):
		kept.append(source[index])
	return kept


## Whether THIS panel dropped a row the module returned. Reported apart from the
## module's own `truncated`, which is about a read that hit its cap rather than about a
## row this panel chose not to name — two different causes, one visible sentence.
func _truncated_by_panel(here: Dictionary) -> bool:
	var source: Array = here.get("npcs", []) as Array
	return source.size() > MAX_ROWS
