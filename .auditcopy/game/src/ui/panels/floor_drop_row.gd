class_name FloorDropRow
extends PanelContainer

## One drop lying on the floor of a location, as [method FloorScreen] publishes it:
## what it is, how many of it there are, who left it and how much longer it lasts.
##
## ## It owns every number on the row
##
## `quantity`, `periods_held` and `decay_periods` arrive raw and are printed HERE, as
## AGENTS.md's UI standard requires: "no number formatting in a screen — the panel
## owns `%d/%d`, decimals and widths." The screen hands this row a primitives
## dictionary and formats nothing.
##
## ## The AGING is the row's headline, not a footnote
##
## An entry with `decay_periods > 0` is on a clock, and no other surface in this
## program renders that clock — `MarketApi.settle` is the only verb that ages it and
## nothing a player can press called it. So how long the entry has been held and how
## long it has left is on the row's own line, and an entry that never decays says so
## in words rather than printing a zero a player would read as "expires now".
##
## ## `{}` is the FIRST state, not a blank row
##
## `show_drop({})` is a spare row in the pool that no drop occupies: it clears,
## hides and reports `{}`. A drop that EXISTS but sits at another location still
## renders, because "it is not here" is a state a player reads and not an absence.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when unfilled.

## Stands in for a drop the floor does not hold. A word, never the id and never a
## dash: an absent entry is a value that is ABSENT, and "-" would read as an
## authored value.
const NO_DROP_TEXT := "No drop here"
## What an entry that never decays says. `decay_periods == 0` means "never", and
## printing "held 0 of 0 periods" would read as an expiry rather than as an
## exemption.
const NO_DECAY_TEXT := "does not decay"
## "held 2 of 5 periods" — the module's own word for time, so the row uses it rather
## than inventing a unit.
const DECAY_TEXT := "held %d of %d periods"
## "left: hero". Who put it down is the only fact about a drop the row carries that
## the goods themselves do not.
const BY_TEXT := "left by: %s"
const META_SEP := " · "

var _view: Dictionary = {}
var _head: String = ""
var _good_line: String = ""
var _decay_line: String = ""
var _by_line: String = ""
var _head_label: Label = null
var _good_label: Label = null
var _decay_label: Label = null
var _by_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one drop as [method FloorScreen] publishes it. An EMPTY dictionary is
## ADR 0083's FIRST state — no drop is on this row — so the row clears itself and
## hides. That is the whole difference between a spare row in a pool and an authored
## but unrealized entry, and it is why the two are not the same call.
func show_drop(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_good_line = ""
		_decay_line = ""
		_by_line = ""
		_render()
		return
	_view = view.duplicate(true)
	_head = String(_view.get("def_id", ""))
	if _head == "":
		_head = String(_view.get("drop_id", ""))
	if _head == "":
		_head = NO_DROP_TEXT
	_good_line = _good_text()
	_decay_line = _decay_text()
	_by_line = _by_text()
	_render()


func clear() -> void:
	show_drop({})


## Everything the row shows, primitives only. `{}` when no drop is on this row —
## never a shaped row with empty fields, which is what would make a spare pool row
## and an unrealized entry read alike.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"drop_id": drop_id(),
		"def_id": String(_view.get("def_id", "")),
		"location_id": String(_view.get("location_id", "")),
		"quantity": int(_view.get("quantity", 0)),
		"dropped_by": String(_view.get("dropped_by", "")),
		"mine": is_mine(),
		"periods_held": int(_view.get("periods_held", 0)),
		"decay_periods": int(_view.get("decay_periods", 0)),
		"decaying": decays(),
		"periods_left": periods_left(),
		# The row's OWN sentences, so a test reads the rendered figures and not only
		# the raw numbers behind them — the half of "the panel owns the format" that a
		# number-only assertion cannot see.
		"head": _head,
		"good_line": _good_line,
		"decay_line": _decay_line,
		"by_line": _by_line,
		"focus_target": "FloorDropRow",
	}


## Whether a drop is ON this row. An authored drop nobody here may take answers
## true and renders; a spare row in the pool answers false and does not.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether the bound player is the one who left this entry behind.
func is_mine() -> bool:
	return is_filled() and bool(_view.get("mine", false))


## Whether this entry ages at all. `decay_periods == 0` is the module's own
## "never decays", read rather than re-derived.
func decays() -> bool:
	return is_filled() and int(_view.get("decay_periods", 0)) > 0


## How many periods the entry has left before `settle` destroys it, or 0 for an
## entry that never decays. Arithmetic on two primitives the facade published, and
## clamped at zero because an entry whose held count has already reached its decay
## is one the next settle destroys rather than one with negative time left.
func periods_left() -> int:
	if not decays():
		return 0
	return maxi(0, int(_view.get("decay_periods", 0)) - int(_view.get("periods_held", 0)))


## The drop this row offers, or `""` when the row is empty.
func drop_id() -> String:
	return String(_view.get("drop_id", ""))


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
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_good_label = get_node_or_null("%GoodLabel") as Label
	_decay_label = get_node_or_null("%DecayLabel") as Label
	_by_label = get_node_or_null("%ByLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_good_label.text = _good_line
	_decay_label.text = _decay_line
	_decay_label.theme_type_variation = _decay_tone()
	_by_label.text = _by_line


## "on the floor x3" — how many of the good this entry holds, in the module's own
## noun. `MarketApi.take` delivers the whole `quantity`, so this is the figure the
## take will hand the player rather than one per unit.
func _good_text() -> String:
	return "on the floor x%d" % int(_view.get("quantity", 0))


## "held 2 of 5 periods" or "does not decay". The two are different sentences, not
## one sentence with a zero: the first is a clock a player can read and the second is
## an exemption from one.
func _decay_text() -> String:
	if not decays():
		return NO_DECAY_TEXT
	return DECAY_TEXT % [int(_view.get("periods_held", 0)), int(_view.get("decay_periods", 0))]


## "left by: hero". Whose it was matters on a floor several people share, and
## `dropped_by` is the only field that carries it.
func _by_text() -> String:
	var dropped_by := String(_view.get("dropped_by", ""))
	if dropped_by == "":
		return ""
	return BY_TEXT % dropped_by


## An entry on its last period is the loud card and one that never decays is the
## quiet one, because the clock is the fact this row exists to publish.
func _decay_tone() -> StringName:
	if not decays():
		return &"MetaLabel"
	return &"WarnLabel" if periods_left() <= 1 else &"OkLabel"