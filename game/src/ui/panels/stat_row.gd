class_name StatRow
extends HBoxContainer

## One labelled value, and the only place a "%d/%d" is ever formatted.
##
## Screens hand raw numbers down; this row owns the wording, the decimals and the
## width, so two screens showing the same value can never disagree about it.
##
## ## Two ways to name a row, and why the second one is not optional
##
## A row that is NOT a stat — a pool, a channel, a gate — passes `name` and
## `decimals` itself. That stays exactly as it was: a count wants no decimals.
##
## A row that IS a stat passes `stat: <id>` and nothing else. The label and the
## precision then come from `StatPresenter`, which declares them per stat id. That
## is the fix for the defect where this row defaulted to zero decimals: the default
## was silent, so `acupoint_quality = 0.5` printed `1` and
## `breakthrough_chance = 0.2` printed `0`, and a screen that simply forgot to pass
## `decimals` produced a confidently wrong figure. A caller that passes neither
## `stat` nor `decimals` still gets the old integer behaviour, because a whole
## number is the right reading of a count and inferring decimals from the value
## would be worse (see `StatPresenter`).
##
## Contract: `summary()` is the testable surface, and it reports whether this row
## actually rendered -- see `rendered`.

const MODE_BAR := &"bar"
const MODE_PLAIN := &"plain"
## The label carries the whole line and the value column is hidden. Used by rows
## whose content is one sentence (a channel is "Lung open d0 (required)"), where
## splitting name from value would only hurt readability.
const MODE_TEXT := &"text"

## This panel's own scene, so `create()` is the one place a row is built.
const SCENE := "res://src/ui/panels/stat_row.tscn"

var _label: Label = null
var _value: Label = null
var _bar: ProgressBar = null
var _name: String = ""
var _current: float = 0.0
var _maximum: float = 0.0
## `StatPresenter.EXACT` (-1) means "print the float as held". It is also the value
## a row starts on, so a row that was never configured never rounds anything.
var _decimals: int = StatPresenter.EXACT
var _mode: StringName = MODE_PLAIN
var _visible_bar: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Configure the row. `stat` is a stat id whose label and precision
## `StatPresenter` declares; `name` is the visible label when the row is not a
## stat; `current`/`maximum` the raw values; `decimals` overrides the declared
## precision; `mode` whether to show a progress bar under the label.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	if state.has("stat"):
		var id := StringName(state["stat"])
		_name = StatPresenter.label_for(id)
		_decimals = StatPresenter.decimals_for(id)
	if state.has("name"):
		_name = String(state["name"])
		# Only a non-stat row takes its precision from the call site. Without this a
		# pooled stat that also passed `name` would keep the id's decimals, and a
		# pooled count would print whatever the id happened to declare.
		if not state.has("stat"):
			_decimals = 0
	if state.has("current"):
		_current = float(state["current"])
	if state.has("maximum"):
		_maximum = float(state["maximum"])
	if state.has("decimals"):
		_decimals = int(state["decimals"])
	if state.has("mode"):
		_mode = StringName(state["mode"])
	_render()


## The value as the row renders it. Empty until `set_state` supplies a name, so a
## row with nothing to say takes no space.
##
## `rendered` is the honest part. A row built with `StatRow.new()` rather than from
## `stat_row.tscn` has no `%ValueLabel`, so it draws nothing at all -- and before
## this key existed, `summary()` still reported a plausible `name`, `current` and
## `text` for it. That is how the character sheet passed its own "every derived
## stat is reachable" test while rendering nothing: the test walked children, found
## childless `StatRow`s, and read figures off fields no label was ever given. A row
## that cannot draw has to be able to say so.
func summary() -> Dictionary:
	_bind_nodes()
	if _name.is_empty():
		return {}
	return {
		"name": _name,
		"current": _current,
		"maximum": _maximum,
		"decimals": _decimals,
		"mode": String(_mode),
		"bar_visible": _bar != null and _visible_bar,
		"bar_ratio": ratio(),
		"text": value_text(),
		"label_text": "" if _label == null else _label.text,
		"rendered": _value != null,
	}


## Fill fraction, clamped to 0..1. Zero when no maximum is known, so a bar never
## renders as full or empty by accident.
func ratio() -> float:
	if _maximum <= 0.0:
		return 0.0
	return clampf(_current / _maximum, 0.0, 1.0)


## Value with its unit and precision. The single formatting rule every row uses.
func value_text() -> String:
	if _maximum > 0.0:
		return L.t("LOC_UI_PANELS_B9884E384D") % [_number(_current), _number(_maximum)]
	return _number(_current)


## The one place a figure becomes text.
##
## `StatPresenter.EXACT` prints the float as held. That branch exists so an
## undeclared stat is never *rounded*: `"%d" % int(round(0.5))` is `1`, which is not
## a presentation of 0.5, it is a different number. An exact float is occasionally
## ugly; a wrong figure is invisible, and that asymmetry is the whole reason the
## fallback is not "round it and move on".
func _number(value: float) -> String:
	if _decimals == StatPresenter.EXACT:
		return "%s" % value
	if _decimals > 0:
		return "%.*f" % [_decimals, value]
	return "%d" % int(round(value))


func _bind_nodes() -> void:
	L.localize_tree(self)
	if _label != null:
		return
	_label = get_node_or_null("%StatLabel") as Label
	_value = get_node_or_null("%ValueLabel") as Label
	_bar = get_node_or_null("%StatBar") as ProgressBar


## A row built from this panel's own scene, so it actually has the three widgets.
##
## A screen whose list outgrows the rows its `.tscn` declares needs more rows. The
## correct way to get one is to instance `stat_row.tscn` -- NOT `StatRow.new()`,
## which produces a bare `HBoxContainer` with no `%StatLabel`, no `%ValueLabel` and
## no `%StatBar`. Such a row still answers `summary()` with a name, a current and a
## `text`, so it passes a test that only asks "is this stat rendered?" while drawing
## an empty box. `CharacterScreen` grew its list this way and rendered nothing at
## all.
##
## The row still belongs to the panel's scene: the widgets are declared in
## `panels/stat_row.tscn`, never built in script, so the UI standard holds. This is
## the panel instancing its own composition, not a screen assembling widgets.
static func create() -> StatRow:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as StatRow


func _render() -> void:
	if _value == null:
		return
	visible = not _name.is_empty()
	_label.text = L.t(_name)
	var text_only := _mode == MODE_TEXT
	_value.visible = not text_only
	_value.text = L.t(value_text())
	if _bar != null:
		_visible_bar = _mode == MODE_BAR
		_bar.visible = _visible_bar
		if _visible_bar:
			_bar.max_value = 1.0
			_bar.value = ratio()
