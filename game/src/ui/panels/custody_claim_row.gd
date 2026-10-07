class_name CustodyClaimRow
extends PanelContainer

## One custody claim as the custody page shows it, from one entry of
## [method CustodyApi.summary]'s `claims`.
##
## ## ## It prints the SUBJECT DEF ID, and that is the whole point
##
## ADR 0104: a custody record carries **no** `description`, no `flavor` and no
## `display_name`; the subject's name is authored on its def and read through the
## catalog. `ui/` may not read that catalog — `npc` is not in `rules.UI_MODULES`,
## and a bare `NpcDef` in a panel is a bare cross-module edge the arch gate refuses
## — so this row prints the def id the claim actually carries and invents no name
## beside it. A second copy of the name is prose in a save schema's clothing, and
## prose in a save schema is how prose becomes what gets read.
##
## ## It owns EVERY number on the row
##
## `periods` and `opened_period` arrive raw and are printed HERE, as AGENTS.md's UI
## standard requires: "no number formatting in a screen — the panel owns `%d/%d`,
## decimals and widths." The screen hands this row a primitives dictionary and
## formats nothing.
##
## ## `{}` is the FIRST state, not a blank row
##
## `show_claim({})` is a spare row in the pool that no authored claim occupies: it
## clears, hides and reports `{}`. A claim that EXISTS but is RELEASED arrives with
## `status: "released"` and renders as a visible card — the distinction a widget
## pool makes for free and one a collapsed row would throw away.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when unfilled.

## Stands in for a released claim's holder. A word, never the id and never a dash:
## an absent holder is a value that is ABSENT (ADR 0083), and "-" would read as an
## authored value.
const VACANT_TEXT := "Vacant"
## A claim whose subject id this build's record does not name. Said in words rather
## than rendered as an empty card.
const UNNAMED_SUBJECT := "Subject unnamed"
## The two statuses `CustodyState` publishes, read off the record and never
## composed: a panel that paraphrased them would be describing a rule the module
## did not write.
const STATUS_HELD := "held"
const STATUS_RELEASED := "released"
## "custody · 4 periods". `periods` is the module's word (DEF-0111), so the row
## uses it rather than inventing a unit.
const META_SEP := "·"
## "term custody" and "4 periods owed", joined. A term is an authored id and a
## count, never an amount — so the row never prints a currency beside one.
const TERM_SEP := " · "

var _view: Dictionary = {}
var _subject: String = ""
var _holder: String = ""
var _term: String = ""
var _status: String = ""
var _head_label: Label = null
var _holder_label: Label = null
var _term_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one claim as [method CustodyApi.summary] publishes it.
##
## An EMPTY dictionary is ADR 0083's FIRST state — no claim is on this row — so the
## row clears itself and hides. That is the whole difference between a spare row in
## a pool and a claim that was released, and it is why the two are not the same
## call.
func show_claim(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_subject = ""
		_holder = ""
		_term = ""
		_status = ""
		_render()
		return
	_view = view.duplicate(true)
	_subject = String(_view.get("subject_id", ""))
	if _subject == "":
		_subject = UNNAMED_SUBJECT
	_holder = _holder_text()
	_term = _term_text()
	_status = String(_view.get("status", ""))
	_render()


func clear() -> void:
	show_claim({})


## Everything the row shows, primitives only. `{}` when no claim is on this row —
## never a shaped row with empty fields, which is what would make a spare pool row
## and a released claim read alike.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"claim_id": claim_id(),
		# The DEF ID, not a name. See the class note: a custody record carries no prose,
		# and `ui/` may not read the catalog the subject's name is authored on.
		"subject_id": String(_view.get("subject_id", "")),
		"subject_kind": String(_view.get("subject_kind", "")),
		"holder_kind": String((_view.get("holder", {}) as Dictionary).get("kind", "")),
		"holder_id": String((_view.get("holder", {}) as Dictionary).get("id", "")),
		"holder_vacant": is_vacant(),
		"term_id": String(_view.get("term_id", "")),
		"periods": int(_view.get("periods", 0)),
		"opened_period": int(_view.get("opened_period", 0)),
		"held": is_held(),
		"released": is_released(),
		# The row's OWN sentences, so a test reads the rendered figure and not only the
		# raw number behind it — which is the half of "the panel owns the format" that a
		# number-only assertion cannot see.
		"subject_line": _subject,
		"holder_line": _holder,
		"term_line": _term,
		"status_line": _status,
		"card_tone": String(_card_tone()),
		"head_tone": String(_head_tone()),
		"focus_target": "CustodyClaimRow",
	}


## Whether a claim is ON this row. A released claim answers true and renders; a
## spare row in the pool answers false and does not.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether this claim is still held — the one state that makes transfer and release
## reachable at all.
func is_held() -> bool:
	return is_filled() and String(_view.get("status", "")) == STATUS_HELD


## Whether this claim has been released. The claim STAYS in the ledger so the
## history reads as history, and this is the row that says so rather than the row
## disappearing and taking the subject's past with it.
func is_released() -> bool:
	return is_filled() and String(_view.get("status", "")) == STATUS_RELEASED


## Whether the claim exists with no holder, which is ADR 0083's vacancy rather than
## the absence of a claim.
func is_vacant() -> bool:
	return is_filled() and OwnerRef.is_vacant(_view.get("holder", {}))


func claim_id() -> String:
	return String(_view.get("claim_id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%SubjectLabel") as Label
	_holder_label = get_node_or_null("%HolderLabel") as Label
	_term_label = get_node_or_null("%TermLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_head_label.text = _subject
	_head_label.theme_type_variation = _head_tone()
	_holder_label.text = _holder
	_holder_label.theme_type_variation = _holder_tone()
	_term_label.text = _term
	_status_label.text = _status
	_status_label.theme_type_variation = _status_tone()


## A released claim is its OWN card rather than a tint of the held one: the holder
## is vacant and the term is NOT forgiven, so a player who cannot see that
## distinction reads a release as the claim having ended rather than the holding
## having stopped.
func _card_tone() -> StringName:
	return &"VacantSeatCard" if is_released() else &"ClaimCard"


## A vacant holder is printed in the vacancy tone so the eye finds the gap without
## reading the line under it.
func _head_tone() -> StringName:
	return &"VacantSeatLabel" if is_vacant() else &"ClaimLabel"


func _holder_tone() -> StringName:
	return &"VacantSeatLabel" if is_vacant() else &"SeatHolderLabel"


## The status word is the module's own constant, and the tone says whether the claim
## is live. A released claim is printed in the warning ink because the term is still
## owed — `release` never forgives it.
func _status_tone() -> StringName:
	return &"WarnLabel" if is_released() else &"OkLabel"


## "actor warden" / "sect iron_vow" / "Vacant". The `OwnerRef`'s kind and id, both
## raw, joined — the module's vocabulary exactly, and no institution's name resolved
## through a catalog this panel may not reach.
func _holder_text() -> String:
	var holder: Dictionary = _view.get("holder", {}) as Dictionary
	if holder.is_empty() or OwnerRef.is_vacant(holder):
		return VACANT_TEXT
	var kind := String(holder.get("kind", ""))
	var id := String(holder.get("id", ""))
	if kind == "" and id == "":
		return VACANT_TEXT
	return kind if id == "" else "%s %s" % [kind, id]


## "term custody · 4 periods". The term is an authored id and the periods are a
## COUNT — a custody term is never an amount (ADR 0104), so nothing here reads as a
## price and nothing on this row can be mistaken for one.
func _term_text() -> String:
	var parts: Array[String] = []
	var term := String(_view.get("term_id", ""))
	if term != "":
		parts.append("term %s" % term)
	parts.append("%d periods" % int(_view.get("periods", 0)))
	return TERM_SEP.join(parts)
