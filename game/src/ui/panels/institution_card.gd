class_name InstitutionCard
extends PanelContainer

## One organization of ANY kind, as the institution screen's read model publishes it:
## its name and its kind, the offices it authors (each with its capacity and whether it
## is VACANT), the member's standing as a RATIO, and what they still owe.
##
## ## The THREE states are three DIFFERENT things, and a row is where they are got wrong
##
## ADR 0083 in one row, and every case below is reachable and asserted:
##
##   - `show_organization({})` -- this row carries no organization at all (a spare row in
##     the screen's pool). **HIDDEN**, `summary()` is `{}`, `is_filled()` answers false.
##   - `show_organization({"ok": false, "reason": R})` -- a verb was REFUSED and `R` is the
##     facade's own authored constant. **VISIBLE**, `RefusedCard`, reason **VERBATIM**.
##   - `show_organization({"vacant": true, ...})` -- the organization EXISTS and the
##     viewer's place in it is ABSENT. **VISIBLE**, `VacantSeatCard`, `is_filled()` true.
##   - a present view whose `claim.exists` is true -- a member holding a claim.
##
## The third is NOT the first: a house you belong to and hold no seat in is a fact about
## the world, while a spare pool row is an artefact of the widget pool. Collapsing the
## third into the first hides the member, and rendering it as `0` or `"-"` destroys the
## succession design that exists to make a vacancy legible (ADR 0084).
##
## ## Position and standing are TWO facts, and this row never divides one by the other
##
## ADR 0064's split, unchanged by ADR 0083: a member may hold a high office on thin
## standing, and may hold thick standing in no office at all. **The standing line renders
## the ratio the CLAIM computed** (`InstitutionClaim.normalized()`) and this row never
## recomputes it from `standing / standing_cap`, so a card cannot disagree with the claim
## it is rendering. The test proves it by handing this row a view whose `normalized` and
## whose raw numbers deliberately disagree.
##
## ## Every number is formatted HERE
##
## `summary()` is the testable surface. A screen passes raw values and formats nothing.

## A seat exists and nobody holds it. The WORD, never `0` and never a dash: an unfilled
## authored office is a fact about the world, and `0` reads as a count somebody kept.
const VACANT_TEXT := "VACANT"
## The same fact in the payload, so a test asserts a value rather than a sentence.
const STATE_VACANT := "vacant"
const STATE_HELD := "held"
## The office exists and NOBODY PUBLISHED ITS ROSTER. **Not `held`**: an empty roster and
## an unpublished one are different facts, and reporting the second as the first invents
## a succession nobody published. It is also not `vacant` -- the vacancy is a claim about
## the world, and nobody has made it.
const STATE_UNKNOWN := "unknown"
const HELD_PREFIX := "held by"
const HOLDER_UNKNOWN := "holders not published"
const NO_OFFICE := "no office held"
const NOT_A_MEMBER := "belonging to nothing"
const NOTHING_OWED := "nothing owed"
const OWE_PREFIX := "Owes"
const UNNAMED := "Organization unnamed"
const OFFICE_UNNAMED := "Office unnamed"
const NO_OFFICES_AUTHORED := "this organization authors no office at all"
const PERCENT_SUFFIX := "%"
## The claim's own two-state refusal, aliased rather than restated: a panel renders a
## reason it did not have to invent (ADR 0083's third state).
const NOT_AN_INSTITUTION := InstitutionLedger.R_NOT_AN_INSTITUTION

## Office lines ONE card renders. Clamped again by `RowBudget.cap` at the point of use: the
## count is a data-derived office count, and a pool that grew to fit an unbounded one would
## parent live `Control`s without limit.
const POSITION_ROWS := 4

var _view: Dictionary = {}
var _reason: String = ""
var _head: String = ""
var _kind: String = ""
var _positions: Array = []
var _standing_line: String = ""
var _obligation_line: String = ""
var _meta_line: String = ""
var _head_label: Label = null
var _position_label: Label = null
var _standing_label: Label = null
var _obligation_label: Label = null
var _meta_label: Label = null
var _position_box: VBoxContainer = null
var _position_lines: Array = []


func _ready() -> void:
	# Binding and a FIRST paint only. Widgets are composed in the scene; nothing is
	# built here, so this is safe to skip entirely and the headless runner, which drives
	# every suite from `SceneTree._initialize()` and never fires `_ready()`, still works.
	_bind_nodes()
	_render()


## Render one organization as the screen publishes it. See the class note for the three
## states and why each is a different thing.
##
## An **empty** dictionary is the first state -- this row carries nothing -- so the row
## clears itself and hides. A **refusal** is the third state and renders on its own tone
## with the facade's `reason` untouched.
func show_organization(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		clear()
		return
	_view = view.duplicate(true)
	_reason = ""
	if bool(view.get("ok", true)) == false:
		# ADR 0083's third state. The reason VERBATIM: not "Rejected: seat_occupied",
		# not a sentence this row composed -- a refusal a panel had to word is a refusal
		# the player cannot act on.
		_reason = String(view.get("reason", ""))
		if _reason == "":
			# A refusal with no reason is not a legible refusal, so it is given the
			# family's OWN "there is no institution here" constant rather than an empty
			# line that reads like the row simply had nothing to show.
			_reason = NOT_AN_INSTITUTION
	_compute_lines()
	_render()


## Empty the row completely: no view AND no reason, so `summary()` reports `{}`.
##
## Deliberately not `show_organization({})`'s twin state -- a row carrying nothing and a
## member belonging to nothing are different claims about the world, and the second is
## rendered by [method show_organization] with a view.
func clear() -> void:
	_bind_nodes()
	_view = {}
	_reason = ""
	_positions = []
	_compute_lines()
	_render()


## Everything this row shows, primitives only, with every office's own summary nested
## under `positions`. `{}` when the row carries nothing at all -- not a shaped row with
## empty fields, which is what would make a spare pool row and a vacant office read alike.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	_compute_lines()
	var offices: Array = []
	for position in _positions:
		offices.append(_position_summary(position))
	return {
		"id": organization_id(),
		"kind": _kind,
		"display_name": String(_view.get("display_name", "")),
		"refused": _reason != "",
		"reason": _reason,
		# The organization exists -- that is what `is_filled()` already said -- and the
		# VIEWER'S place in it is the separate fact the middle state reports.
		"exists": true,
		"vacant": is_vacant(),
		"is_member": is_member(),
		"claim": _claim_summary(),
		"position": String(_claim().get("position", "")),
		"standing": int(_claim().get("standing", 0)),
		"standing_cap": int(_claim().get("standing_cap", 0)),
		# The RATIO the claim computed, in [0, 1]. Read off the view and never
		# recomputed here -- see the class note.
		"standing_ratio": float(_claim().get("normalized", 0.0)),
		"position_count": _positions.size(),
		"positions": offices,
		"head": _head,
		"standing_line": _standing_line,
		"obligation_line": _obligation_line,
		"meta": _meta_line,
		"head_tone": String(_head_tone()),
		"card_tone": String(_card_tone()),
		"focus_target": "InstitutionCard",
	}


## Whether this row carries an organization at all. **A vacant one answers true and
## renders**; a spare pool row answers false and does not. The distinction is the whole
## point of the row, so it is a named predicate rather than something a caller infers.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether the organization exists and the viewer holds no office in it: ADR 0083's
## middle state. Never `0`, never a hidden row.
func is_vacant() -> bool:
	return is_filled() and _reason == "" and bool(_view.get("vacant", false))


## Whether the viewer holds a claim here. **Never inferred from the absence of a
## refusal** -- an unaffiliated viewer and a refused `join` are different facts.
func is_member() -> bool:
	return is_filled() and _reason == "" and bool(_claim().get("exists", false))


## The organization's id, or `""` when this row carries nothing.
func organization_id() -> String:
	return String(_view.get("id", ""))


## Every office id this row renders, in the order it renders them. An office the
## organization does not author is `{}` and is not in this list at all.
func position_ids() -> Array:
	var out: Array = []
	for position in _positions:
		out.append(String((position as Dictionary).get("id", "")))
	return out


## One office's rendered payload, `{}` when this organization authors no such office.
## Its three states are the class note's: `{}` absent, `vacant` filled-by-nobody,
## anything else filled.
func position_summary(position_id: String) -> Dictionary:
	for position in _positions:
		if String((position as Dictionary).get("id", "")) == position_id:
			return _position_summary(position)
	return {}


## Give the keyboard and pad a landing spot. The target is recorded first, because a node
## outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless suite
## runner drives this row before a scene tree exists, so `_ready()` is not a dependable
## place to bind them. Idempotent, and re-entrant-safe (the `_reason` is read before any
## nested call).
func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_position_label = get_node_or_null("%PositionLabel") as Label
	_standing_label = get_node_or_null("%StandingLabel") as Label
	_obligation_label = get_node_or_null("%ObligationLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_position_box = get_node_or_null("%PositionList") as VBoxContainer


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_tone()
	_position_label.text = _position_line()
	_position_label.visible = not _positions.is_empty()
	_standing_label.text = _standing_line
	_obligation_label.text = _obligation_line
	_meta_label.text = _meta_line
	_render_positions()


# --- The lines. Computed once, so summary() and _render() cannot disagree ---------


func _compute_lines() -> void:
	if not is_filled():
		_head = ""
		_kind = ""
		_positions = []
		_standing_line = ""
		_obligation_line = ""
		_meta_line = ""
		return
	_positions = _position_views()
	var authored := String(_view.get("display_name", ""))
	_head = authored if authored != "" else String(_view.get("id", UNNAMED))
	_kind = String(_view.get("kind", ""))
	# A refusal replaces the CLAIM, not the organization: the organization is still
	# named so the player can see WHICH house refused them.
	_standing_line = _reason if _reason != "" else _standing_text()
	_obligation_line = "" if _reason != "" else _obligation_text()
	_meta_line = _meta_text()


## The offices this organization publishes, in canonical order, with `{}` DROPPED.
##
## A `for` over a SNAPSHOT of the view's own array writing into a NEW array: the body
## never touches the array being walked, so the bound is the authored office count and
## there is no shape here for a loop to grow in lockstep with its own bound
## (`tests/arch_rules/test_no_unbounded_wait.gd`).
func _position_views() -> Array:
	var out: Array = []
	var authored: Variant = _view.get("positions", [])
	if not (authored is Array):
		return out
	for entry in authored as Array:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		# ADR 0083's FIRST state: the organization authors no such office, so there is
		# no office to show. Dropping it rather than rendering a blank is what keeps a
		# spare pool row and an absent office from reading alike.
		if row.is_empty() or String(row.get("id", "")) == "":
			continue
		out.append(row.duplicate(true))
	return out


func _claim() -> Dictionary:
	var held: Variant = _view.get("claim", {})
	return held as Dictionary if held is Dictionary else {}


## The claim's payload as this row reports it: `{}` when the viewer holds none, which is
## the FIRST state and not a zeroed row.
func _claim_summary() -> Dictionary:
	var claim := _claim()
	if not bool(claim.get("exists", false)):
		return {}
	return {
		"exists": true,
		"position": String(claim.get("position", "")),
		"standing": int(claim.get("standing", 0)),
		"standing_cap": int(claim.get("standing_cap", 0)),
		"normalized": float(claim.get("normalized", 0.0)),
		"obligations": _obligations(claim.get("obligations", {})),
	}


## One office's rendered payload: the three states kept apart, plus the line.
##
## `state` is a WORD -- `vacant`, `held` or `none` -- and `vacant` is a BOOLEAN, so a
## test can assert a vacancy without reading a sentence. A seat nobody holds is never
## reported as `held: 0` alone, which is the shape a `0` reading comes from.
func _position_summary(position: Dictionary) -> Dictionary:
	var view := position as Dictionary
	var vacant := bool(view.get("vacant", false))
	var capacity := int(view.get("capacity", 0))
	var holders := String(view.get("holders", ""))
	var published := view.has("vacant")
	return {
		"id": String(view.get("id", "")),
		"display_name": String(view.get("display_name", "")),
		"vacant": vacant,
		# What `capacity` MEANS is the office's own word, read off the authored cap: `0`
		# is an unbounded room, `1` is a seat, more is a room that can fill.
		"capacity": capacity,
		"is_seat": capacity == 1,
		"unbounded": capacity <= 0,
		# The RAW count, published so `has_room` below is auditable rather than asserted.
		# **It is never the authority on whether the seat is vacant** -- `vacant` is, and a
		# reader who took `held == 0` as the vacancy would have rebuilt the `0` reading this
		# row exists to refuse.
		"held": int(view.get("held", 0)),
		"has_room": capacity <= 0 or int(view.get("held", 0)) < capacity,
		"state": _position_state(vacant, published),
		# Whether anybody told us WHO holds it. `false` with `state == "unknown"` is the
		# honest third answer, and reporting `state == "held"` on an unpublished roster
		# was the defect this flag exists to make impossible to repeat.
		"roster_published": published,
		"duty_per_period": int(view.get("duty_per_period", 0)),
		"patronage_per_period": int(view.get("patronage_per_period", 0)),
		"duties": _strings(view.get("duties", [])),
		"authorities": _strings(view.get("authorities", [])),
		"line": _position_line_of(view),
		"line_tone": String(_position_line_tone(vacant)),
	}


## Which of the three office states this is. **`published` is the authority**: an office
## whose roster nobody supplied is `unknown`, never `held` and never `vacant`. The first
## version inferred `held` from "not vacant", and the headless driver rendered every
## office of all three guilds as `held · holders not published` -- a succession invented
## by a missing `if`.
func _position_state(vacant: bool, published: bool) -> String:
	if vacant:
		return STATE_VACANT
	return STATE_HELD if published else STATE_UNKNOWN


## "First Ledger · VACANT · 1 seat · duty 3 · patronage 3". Every word and every number
## belongs to this row; the screen hands raw values down.
##
## The `VACANT` token is the point: an office nobody holds says so in words, and it is
## printed before the numbers so the eye finds the gap without reading them.
func _position_line_of(view: Dictionary) -> String:
	var name := String(view.get("display_name", ""))
	if name == "":
		name = String(view.get("id", OFFICE_UNNAMED))
	var parts: Array = [name]
	if bool(view.get("vacant", false)):
		parts.append(VACANT_TEXT)
	parts.append(_capacity_text(int(view.get("capacity", 0))))
	parts.append(_holder_text(view))
	var duty := int(view.get("duty_per_period", 0))
	var patronage := int(view.get("patronage_per_period", 0))
	if duty > 0:
		parts.append("duty %d" % duty)
	if patronage > 0:
		parts.append("patronage %d" % patronage)
	return " · ".join(PackedStringArray(parts))


## `0` is an unbounded ROOM, `1` is a SEAT, and more is a room that can fill. ADR 0084
## makes the first two different things, so the cap is never printed as a bare number
## whose meaning the reader has to guess.
func _capacity_text(capacity: int) -> String:
	if capacity <= 0:
		return "unbounded room"
	if capacity == 1:
		return "1 seat"
	return "%d seats" % capacity


## Who holds it. A vacancy is `VACANT`, a published holder is named, and a roster nobody
## published says SO -- never `0`, which would read as a count kept.
func _holder_text(view: Dictionary) -> String:
	if bool(view.get("vacant", false)):
		return VACANT_TEXT
	var holders := String(view.get("holders", ""))
	if holders == "":
		return HOLDER_UNKNOWN
	return "%s %s" % [HELD_PREFIX, holders]


## Every office on one line, so the card shows its offices even where the office box has
## no scene. `NO_OFFICES_AUTHORED` when it authors none -- a farmers' circle really does,
## and that is ADR 0064's "thick standing in no position at all" made legible rather
## than an empty gap.
func _position_line() -> String:
	if _positions.is_empty():
		return NO_OFFICES_AUTHORED
	var parts: Array = []
	for position in _positions:
		parts.append(_position_line_of(position as Dictionary))
	return "\n".join(PackedStringArray(parts))


## The standing line: the office NAMED, then the standing, then the RATIO the claim
## computed. The office leads so a reader sees two claims rather than one derived rank --
## which is exactly the spreadsheet ADR 0064's split exists to prevent.
func _standing_text() -> String:
	if not is_member():
		return NOT_A_MEMBER
	var claim := _claim()
	var office := String(claim.get("position", ""))
	var numbers := (
		"%d / %d standing · %d%s of cap"
		% [
			int(claim.get("standing", 0)),
			int(claim.get("standing_cap", 0)),
			int(roundf(float(claim.get("normalized", 0.0)) * 100.0)),
			PERCENT_SUFFIX,
		]
	)
	return numbers if office == "" else "%s · %s" % [office, numbers]


## What they still owe, by term id. An absent ledger is `nothing owed`, never an empty
## line, because "nobody opened this debt" and "this debt is settled" are the same state.
func _obligation_text() -> String:
	var claim := _claim()
	var owed := _obligations(claim.get("obligations", {}))
	if owed.is_empty():
		return NOTHING_OWED
	var terms: Array = []
	for term_id in InstitutionLedger.sorted_keys(owed):
		terms.append("%s %d" % [term_id, int(owed[term_id])])
	return "%s: %s" % [OWE_PREFIX, ", ".join(PackedStringArray(terms))]


## The card's meta line: the KIND, the authored founding price and what this kind may do.
## Raw integers reach this row; the words are the row's own.
func _meta_text() -> String:
	if _reason != "":
		return "refused · %s" % _reason
	var parts: Array = []
	if _kind != "":
		parts.append(_kind)
	parts.append("founding cost %d" % int(_view.get("founding_cost", 0)))
	var capabilities := _strings(_view.get("capabilities", []))
	if not capabilities.is_empty():
		parts.append(", ".join(PackedStringArray(capabilities)))
	var territories := _strings(_view.get("territories", []))
	if not territories.is_empty():
		parts.append("claims %s" % ", ".join(PackedStringArray(territories)))
	return " · ".join(PackedStringArray(parts))


## One office line per widget. The pool is bounded by `RowBudget.cap` on a bound
## snapshotted BEFORE the loop -- the bound is a data-derived office count, and a
## `while` that filled toward a size another body grew is INC-0002.
func _render_positions() -> void:
	if _position_box == null:
		return
	var wanted := mini(RowBudget.cap(_positions.size()), POSITION_ROWS)
	var have := _position_lines.size()
	# `for` over a RANGE: fills toward a FIXED count computed above, with an
	# unconditional append. Bounded by construction and never re-read from `have`.
	for index in range(wanted - have):
		var line := Label.new()
		line.name = "Position%d" % (have + index)
		line.theme_type_variation = &"SeatLabel"
		_position_box.add_child(line)
		_position_lines.append(line)
	for index in range(_position_lines.size()):
		var label: Label = _position_lines[index]
		var shown := index < wanted
		label.visible = shown
		if not shown:
			continue
		var view := _positions[index] as Dictionary
		label.text = _position_line_of(view)
		label.theme_type_variation = _position_line_tone(bool(view.get("vacant", false)))


func _card_tone() -> StringName:
	if _reason != "":
		return &"RefusedCard"
	if is_vacant():
		return &"VacantSeatCard"
	return &"ClaimCard"


func _head_tone() -> StringName:
	if _reason != "":
		return &"WarnLabel"
	if is_vacant():
		return &"VacantSeatLabel"
	return &"ClaimLabel"


## A vacant office is printed in the VACANCY tone so the eye finds the gap. Everything
## else is quiet, because a filled office is the expected state.
func _position_line_tone(vacant: bool) -> StringName:
	return &"VacantSeatLabel" if vacant else &"SeatLabel"


func _obligations(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	var rows := value as Dictionary
	for term_id in InstitutionLedger.sorted_keys(rows):
		out[String(term_id)] = int(rows[term_id])
	return out


func _strings(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(String(entry))
	return out
