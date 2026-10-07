class_name LineageBloodRow
extends PanelContainer

## One bloodline this hero carries, as `BloodlineApi.summary(actor)` publishes it:
## the concentration, the tier it falls in, whether it has crossed its authored
## awaken threshold, and what it grants.
##
## ## DORMANT IS A VISIBLE STATE, and this row is where it is kept visible
##
## This is the case most likely to be silently dropped. Purity decays within one
## actor's life and is never raised (ADR 0063), so a lineage that crossed its
## threshold can fall back under it and stay carried — and
## `BloodlineProjection.apply` deliberately keeps the `bloodline:<id>` trait mirror
## on **while dormant**, exactly so a sleeping lineage is never indistinguishable
## from no lineage at all. A screen that filtered dormant rows out, or that hid a
## row whose `awake` flag is false, would be undoing that decision one layer up: the
## mirror would still be on the actor and the player would have no way to see why.
##
## So: **every carried lineage gets a row, awake or not.** `show_bloodline({})` is
## the different thing — a spare pool row with nothing in it — and that one hides.
##
## ## Purity GATES, it does not scale, and this row says so
##
## A dormant lineage's grants are listed in full and labelled dormant. Printing
## them as live would be the ability-score reading ADR 0063 exists to refuse; hiding
## them would make the bar unreachable-looking. One line says what is locked and by
## what.
##
## ## Every number is formatted HERE
##
## The UI standard puts `%d`, decimals and widths in the panel. The screen hands
## raw facade values down and formats nothing.

## The tier name a row reads as. Authored constants rather than prose, so a test can
## compare the string a player sees against the one the facade published.
const TIER_DORMANT := "dormant"
const NONE_CARRIED := "LOC_UI_PANELS_E100DFB0F5"
const DORMANT_NOTE := "LOC_UI_PANELS_BFA543BE74"
const AWAKE_NOTE := "LOC_UI_PANELS_302BFD6803"
const UNKNOWN_LINEAGE := "LOC_UI_PANELS_10B1395A1D"
const NO_THRESHOLD := "LOC_UI_PANELS_679AF9ABCB"
const CROSSES_RACES := "LOC_UI_PANELS_DB63BEF781"
const GRANTS := "grants"
const NOTHING_GRANTED := "LOC_UI_PANELS_B0386472CE"

var _view: Dictionary = {}
var _catalog: Dictionary = {}
var _name_line: String = ""
var _purity_line: String = ""
var _state_line: String = ""
var _grant_line: String = ""
var _meta: String = ""
var _name_label: Label = null
var _purity_label: Label = null
var _state_label: Label = null
var _grant_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one carried lineage. `view` is one entry of `BloodlineApi.summary`'s
## `lineages` block and `catalog` is that call's `bloodlines` dictionary, passed
## alongside so the authored name, description and traits come out of the one
## snapshot the screen already holds rather than a second facade call.
func show_bloodline(view: Dictionary, catalog: Dictionary = {}) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_catalog = catalog.duplicate(true)
	_render()


## Everything the row shows, primitives only. `{}` for a spare pool row carrying
## nothing.
##
## **`dormant` is reported as a distinct fact** rather than being folded into
## `awake`, because "you carry it and it has not awakened" is the one sentence a
## player must be able to read off this screen, and `awake: false` reads as
## absence unless the row names it.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	_compute_lines()
	var awake := bool(_view.get("awake", false))
	var tier := String(_view.get("tier", ""))
	return {
		"lineage_id": String(_view.get("id", "")),
		"display_name": _name_line,
		"purity": float(_view.get("purity", 0.0)),
		"tier": tier,
		"awake": awake,
		# `dormant` is its OWN claim, never `not awake`: the tier is the facade's
		# word for "below the bar", and a row that only reported the negation would
		# let a sleeping lineage and an unshipped one read alike.
		"dormant": tier == TIER_DORMANT,
		"known": bool(_view.get("known", false)),
		"crosses_races": bool(_catalog_entry().get("crosses_races", false)),
		"traits": _string_list(_catalog_entry().get("traits", [])),
		"awaken_threshold": float(_catalog_entry().get("awaken_threshold", 0.0)),
		"description": String(_catalog_entry().get("description", "")),
		"name_line": _name_line,
		"purity_line": _purity_line,
		"state_line": _state_line,
		"grant_line": _grant_line,
		"meta": _meta,
		"card_tone": String(_card_tone()),
		"focus_target": "LineageBloodRow",
	}


## Whether the row carries a lineage worth taking space for. **A dormant lineage
## answers TRUE** — it is carried, it is visible, and hiding it here would delete
## the whole reason the trait mirror survives sleep.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether this lineage is awake. A named predicate rather than something a caller
## infers from the tier, so the two facts stay independently assertable.
func is_awake() -> bool:
	return is_filled() and bool(_view.get("awake", false))


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily in `_bind_nodes()`, never `@onready`: the headless runner drives
## this row before a scene tree exists (ADR 0080, UI standard).
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _name_label != null:
		return
	_name_label = get_node_or_null("%NameLabel") as Label
	_purity_label = get_node_or_null("%PurityLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label
	_grant_label = get_node_or_null("%GrantLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _name_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_compute_lines()
	_name_label.text = L.t(_name_line)
	_name_label.theme_type_variation = _head_tone()
	_purity_label.text = L.t(_purity_line)
	_state_label.text = L.t(_state_line)
	_grant_label.text = L.t(_grant_line)
	_meta_label.text = L.t(_meta)
	_meta_label.visible = _meta != ""


## Every line this row prints, computed once so `summary()` and `_render()` cannot
## disagree about what the row says.
func _compute_lines() -> void:
	_name_line = _name_line_of()
	_purity_line = _purity_text()
	_state_line = _state_text()
	_grant_line = _grant_text()
	_meta = _meta_text()


## The authored display name, falling back to the bare id, and finally to a word
## that says the content is missing rather than to nothing.
func _name_line_of() -> String:
	var lineage_id := String(_view.get("id", ""))
	var authored := String(_view.get("display_name", ""))
	if authored != "":
		return authored
	if lineage_id == "":
		return L.t(UNKNOWN_LINEAGE)
	if lineage_id != "" and bool(_view.get("known", false)):
		return lineage_id
	return L.t(UNKNOWN_LINEAGE)


## Purity as a percentage, plus the tier the facade named and the bar it has to
## clear. The bar is shown whether or not the lineage has cleared it, because a
## dormant lineage's whole meaning is the gap to its threshold.
func _purity_text() -> String:
	var entry := _catalog_entry()
	var threshold := float(entry.get("awaken_threshold", 0.0))
	var bar := NO_THRESHOLD if threshold <= 0.0 else "%.2f" % threshold
	return (
		"Purity %.2f · %s · bar %s"
		% [
			float(_view.get("purity", 0.0)),
			String(_view.get("tier", TIER_DORMANT)),
			bar,
		]
	)


## The one sentence a player must be able to read: awake, or carried and asleep.
func _state_text() -> String:
	if bool(_view.get("awake", false)):
		return L.t(AWAKE_NOTE)
	return L.t(DORMANT_NOTE)


## What the lineage grants, named whether or not they apply. Printing them live
## while dormant would be the ability-score reading; hiding them would make the bar
## look unreachable. So they are listed and marked.
func _grant_text() -> String:
	var traits := _string_list(_catalog_entry().get("traits", []))
	if traits.is_empty():
		return L.t("LOC_UI_PANELS_265FC52551") % [L.t(GRANTS), L.t(NOTHING_GRANTED)]
	return L.t("LOC_UI_PANELS_D9CD377026") % [L.t(GRANTS), ", ".join(traits)]


func _meta_text() -> String:
	var parts: Array[String] = []
	var entry := _catalog_entry()
	if bool(entry.get("crosses_races", false)):
		parts.append(CROSSES_RACES)
	var race_id := String(entry.get("race_id", ""))
	if race_id != "":
		parts.append("bound to %s" % race_id)
	return " · ".join(parts)


## A sleeping lineage wears the quiet codex card, not a warning card: it is a fact
## about the ancestry, not a mistake the player made. Only its STATE line is loud.
func _card_tone() -> StringName:
	if not is_filled():
		return &"LockedCard"
	return &"EarnedCard" if is_awake() else &"LockedCard"


func _head_tone() -> StringName:
	return &"EarnedLabel" if is_awake() else &"DestinyLockedLabel"


## The facade's own catalog row for this lineage, or `{}` for a lineage this build
## does not ship. Read out of the snapshot, never re-queried.
func _catalog_entry() -> Dictionary:
	var lineage_id := String(_view.get("id", ""))
	return (_catalog.get(lineage_id, {}) as Dictionary) as Dictionary


func _string_list(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(String(entry))
	return out
