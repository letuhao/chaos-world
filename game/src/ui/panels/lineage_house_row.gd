class_name LineageHouseRow
extends PanelContainer

## The HOUSE half of the lineage screen: the clan this hero belongs to, the
## position they hold, the standing behind it, and the terms published on both
## sides of the ledger — as `ClanApi.summary(actor)` publishes them.
##
## ## Position and standing are TWO lines, never one derived rank
##
## ADR 0064's split: a member can hold a high position on thin standing, and can
## hold thick standing in no position at all. That gap IS the politics layer, so
## this row prints the position and the standing separately. A row that divided
## one by the other into a single number would have built a spreadsheet and thrown
## the design away at the last step.
##
## ## The terms are the feature, so they are printed, not summarised
##
## ADR 0064: a clan owes and asks. `patronage` and `duty` are the whole of what a
## clan publishes — the module settles none of them yet, so a screen that showed
## only the house's name and its standing would have published a membership with
## no content in it. The facade flattens both to sorted term ids, so this row
## prints each side under its own heading.
##
## ## Belonging to none is a SENTENCE, not an empty card
##
## "An actor may belong to no clan, and that is the normal starting state." A hero
## with no house renders `NO_HOUSE` and the row stays VISIBLE — an absent house is
## a fact, and hiding it would read as a missing widget.

## The facade's own empty-clan answer, spelled out here rather than as `""`.
const NO_HOUSE := "LOC_UI_PANELS_9817BF5C60"
const NO_HOUSE_NOTE := "LOC_UI_PANELS_694FAF9838" + "LOC_UI_PANELS_2FEC71C85D"
const NO_POSITION := "LOC_UI_PANELS_39A8D71F21"
const FOUNDED_ON := "LOC_UI_PANELS_59AF7CBB9A"
const RANK_LINE := "LOC_UI_PANELS_CF1C85ADBA"
const STANDING_LINE := "LOC_UI_PANELS_742F03C37A"
const RECOGNITION_LINE := "LOC_UI_PANELS_2D2111FA1D"
const PATRONAGE_HEAD := "LOC_UI_PANELS_3BA227C31E"
const DUTY_HEAD := "LOC_UI_PANELS_7EF42D3F64"
const NOTHING_PUBLISHED := "LOC_UI_PANELS_7F1F670A84"
const UNKNOWN_HOUSE := "LOC_UI_PANELS_3A1492F09A"
const BAND_HINT := "LOC_UI_PANELS_94FD10FEAB"

var _view: Dictionary = {}
## The facade's `clans` catalog, set by `show_house` alongside the actor block. A
## private field rather than a third argument so the two travel together and a row
## can never be handed one without the other.
var _catalog: Dictionary = {}
var _name_line: String = ""
var _position_line: String = ""
var _standing_line: String = ""
var _terms_line: String = ""
var _meta: String = ""
var _name_label: Label = null
var _position_label: Label = null
var _standing_label: Label = null
var _terms_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one house as the actor-level block of `ClanApi.summary(actor)` plus that
## call's `clans` catalog, which is where the authored terms and ranks live.
func show_house(view: Dictionary, catalog: Dictionary = {}) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_catalog = catalog.duplicate(true)
	_render()


## Everything the row shows, primitives only. `{}` for a spare pool row carrying
## nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	_compute_lines()
	# The clan id is read ONCE and the boolean is built from the String, rather than
	# comparing a `bool` against `""` — which does not parse, because the facade
	# publishes ids as strings and `bool(x) != ""` has no meaning to compare.
	var clan_id := String(_view.get("clan", ""))
	var held := clan_id != ""
	return {
		"clan_id": clan_id,
		"display_name": _name_line,
		"known": bool(_view.get("known", false)),
		"is_member": held,
		"rank": String(_view.get("rank", "")),
		"rank_index": int(_view.get("rank_index", -1)),
		"rank_count": int(_view.get("rank_count", 0)),
		"standing": int(_view.get("standing", 0)),
		"band_rank": String(_view.get("band_rank", "")),
		"band_count": int(_view.get("band_count", 0)),
		"standing_outranks_position": bool(_view.get("outranks_standing", false)),
		# The hinge, published beside the raw standing it re-reads, so a screen can
		# show "recognised at 30 of 40" AND why the two differ (ADR 0064).
		"recognition": float(_view.get("recognition", 0.0)),
		"recognition_scale": float(_view.get("recognition_scale", 1.0)),
		"founding_bloodline": String(_view.get("founding_bloodline", "")),
		"founding_purity": float(_view.get("founding_purity", 0.0)),
		"min_purity": float(_view.get("min_purity", 0.0)),
		"patronage": _string_list(_view.get("patronage", [])),
		"duty": _string_list(_view.get("duty", [])),
		"rivals": _string_list(_view.get("rivals", [])),
		"name_line": _name_line,
		"position_line": _position_line,
		"standing_line": _standing_line,
		"terms_line": _terms_line,
		"meta": _meta,
		"card_tone": String(_card_tone()),
		"focus_target": "LineageHouseRow",
	}


## Whether the row carries a house worth taking space for. A hero who belongs to
## none answers TRUE: "no house" is the ordinary state and gets a sentence.
func is_filled() -> bool:
	return not _view.is_empty()


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
	_position_label = get_node_or_null("%PositionLabel") as Label
	_standing_label = get_node_or_null("%StandingLabel") as Label
	_terms_label = get_node_or_null("%TermsLabel") as Label
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
	_position_label.text = L.t(_position_line)
	_standing_label.text = L.t(_standing_line)
	_terms_label.text = L.t(_terms_line)
	_meta_label.text = L.t(_meta)
	_meta_label.visible = _meta != ""


## Every line this row prints, computed once so `summary()` and `_render()` cannot
## disagree about what the row says.
func _compute_lines() -> void:
	_name_line = _name_line_of()
	_position_line = _position_text()
	_standing_line = _standing_text()
	_terms_line = _terms_text()
	_meta = _meta_text()


func _name_line_of() -> String:
	var clan_id := String(_view.get("clan", ""))
	if clan_id == "":
		return L.t(NO_HOUSE)
	var authored := String(_view.get("display_name", ""))
	if authored != "":
		return authored
	return clan_id if clan_id != "" else UNKNOWN_HOUSE


## The position, alone. Never merged with the standing — see the class note.
func _position_text() -> String:
	var rank := String(_view.get("rank", ""))
	var index := int(_view.get("rank_index", -1))
	var count := int(_view.get("rank_count", 0))
	if rank == "":
		return L.t("LOC_UI_PANELS_D9CD377026") % [L.t(RANK_LINE), L.t(NO_POSITION)]
	if count > 0 and index >= 0:
		return L.t("LOC_UI_PANELS_3DE33305A6") % [L.t(RANK_LINE), rank, index + 1, count]
	return L.t("LOC_UI_PANELS_D9CD377026") % [L.t(RANK_LINE), rank]


## The standing, the recognition it publishes, and the band it falls in. Three
## numbers kept apart because ADR 0064 keeps them apart.
func _standing_text() -> String:
	var band := String(_view.get("band_rank", ""))
	var band_text := "" if band == "" else L.t("LOC_UI_PANELS_CF8832D9E0") % band
	return (
		"%s %d · %s %.1f%s"
		% [
			STANDING_LINE,
			int(_view.get("standing", 0)),
			RECOGNITION_LINE,
			float(_view.get("recognition", 0.0)),
			band_text,
		]
	)


## The terms, both sides, under their own headings. The house's obligations come
## first: a player reading this is owed something before they owe something.
func _terms_text() -> String:
	var patronage := _string_list(_view.get("patronage", []))
	var duty := _string_list(_view.get("duty", []))
	return (
		"%s: %s\n%s: %s"
		% [
			PATRONAGE_HEAD,
			", ".join(patronage) if not patronage.is_empty() else NOTHING_PUBLISHED,
			DUTY_HEAD,
			", ".join(duty) if not duty.is_empty() else NOTHING_PUBLISHED,
		]
	)


## The founding line and the concentration in it — ADR 0064's hinge, and the reason
## a member of a high-standing house can be recognised without being weightier.
func _meta_text() -> String:
	if String(_view.get("clan", "")) == "":
		return L.t(NO_HOUSE_NOTE)
	var parts: Array[String] = []
	var founding := String(_view.get("founding_bloodline", ""))
	if founding != "":
		var yours := float(_view.get("founding_purity", 0.0))
		parts.append("%s %s (yours %.2f)" % [FOUNDED_ON, founding, yours])
	var rivals := _string_list(_view.get("rivals", []))
	if not rivals.is_empty():
		parts.append("rival: %s" % ", ".join(rivals))
	return " · ".join(parts)


## A hero with no house wears the quiet card: absence is not a refusal and must not
## be painted as one (ADR 0083's three-state vocabulary).
func _card_tone() -> StringName:
	if String(_view.get("clan", "")) == "":
		return &"LockedCard"
	return &"ClaimCard"


func _string_list(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(String(entry))
	return out
