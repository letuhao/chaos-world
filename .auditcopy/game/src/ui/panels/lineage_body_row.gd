class_name LineageBodyRow
extends PanelContainer

## The BODY half of the lineage screen: the race this hero was born into, as
## `RaceApi.summary(actor)` publishes it. Consumes only that facade (ADR 0030).
##
## ## A race is a body plan that REFUSES, so the refusals are the content
##
## ADR 0062's claim is negative, not positive: "a race is a body plan that refuses
## to be a stat stick". The honest reading of a body is what it CANNOT do — which
## paths it closes, which realm it can never pass, how short its life is. So this
## row leads with the closed list and the ceiling, and reports affinities as an
## unranked `{element: value}` map. A row that sorted them into a score would have
## rebuilt the very stat stick the ADR forbids.
##
## ## Every number on this row is formatted HERE, never in the screen
##
## The UI standard puts `%d`, decimals and widths in the panel. `LineageScreen`
## hands this row raw facade values and formats nothing, so the same realm ceiling
## reads identically here and in the header summary line.
##
## ## `summary()` is the testable surface, primitives only
##
## `{}` when the row carries no view at all (a spare pool row).

## What a body with no authored race is called. A word, never `""` and never a
## dash: an absent race is a fact about the world, not a missing widget.
const NO_RACE := "Body unnamed"
## `realm_ceiling` is 0 on a body with NO ceiling, which is the opposite of a
## ceiling of zero. Spelled out so the two can never read alike.
const NO_CEILING := "No ceiling"
const OPEN_ALL_PATHS := "Closes no path"
const PATHS_CLOSED := "Paths closed"
const BASELINE_NOTE := "the fallback body, born before the world has an opinion about you"
const DAYS := "days"
const REALM_SUFFIX := "R"

var _view: Dictionary = {}
var _catalog: Dictionary = {}
var _name_line: String = ""
var _refusal_line: String = ""
var _ceiling_line: String = ""
var _affinity_line: String = ""
var _meta: String = ""
var _name_label: Label = null
var _refusal_label: Label = null
var _ceiling_label: Label = null
var _affinity_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one body. `view` is the actor-level block of `RaceApi.summary(actor)`
## and `catalog` is that call's `races` dictionary, passed alongside so the row can
## read a race's AUTHORED name out of the one snapshot the screen already holds
## rather than costing a second facade call.
##
## An EMPTY `view` is a hero this build has no race for: it renders the `NO_RACE`
## sentence and stays VISIBLE, because "your body is unnamed" is a real state and
## hiding it would read as a missing widget.
func show_body(view: Dictionary, catalog: Dictionary = {}) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_catalog = catalog.duplicate(true)
	_render()


## Everything the row shows, primitives only. `{}` for a spare pool row carrying
## nothing — the same `{}`-means-absent vocabulary every panel in `src/ui/` uses.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	_compute_lines()
	var closed := _string_list(_view.get("closed_paths", []))
	return {
		"race_id": String(_view.get("race", "")),
		"display_name": _name_line,
		"is_baseline": bool(_view.get("is_baseline", false)),
		"closed_paths": closed,
		"closed_path_count": closed.size(),
		"open_path_count": int(_view.get("open_path_count", 0)),
		# 0 means NO ceiling, which is not the claim "a ceiling of zero", so both
		# are reported: the raw ordinal a gate reads, and whether it binds at all.
		"realm_ceiling": int(_view.get("realm_ceiling", 0)),
		"realm_ceiling_binds": int(_view.get("realm_ceiling", 0)) > 0,
		"realm_reached": int(_view.get("realm_reached", 0)),
		"lifespan": float(_view.get("lifespan", 0.0)),
		"affinities": _affinity_map(_view.get("affinities", {})),
		"affinity_count": _affinity_map(_view.get("affinities", {})).size(),
		"name_line": _name_line,
		"refusal_line": _refusal_line,
		"ceiling_line": _ceiling_line,
		"affinity_line": _affinity_line,
		"meta": _meta,
		"card_tone": String(_card_tone()),
		"focus_target": "LineageBodyRow",
	}


## Whether the row carries a body worth taking space for.
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
	if _name_label != null:
		return
	_name_label = get_node_or_null("%NameLabel") as Label
	_refusal_label = get_node_or_null("%RefusalLabel") as Label
	_ceiling_label = get_node_or_null("%CeilingLabel") as Label
	_affinity_label = get_node_or_null("%AffinityLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _name_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_compute_lines()
	_name_label.text = _name_line
	_refusal_label.text = _refusal_line
	_ceiling_label.text = _ceiling_line
	_affinity_label.text = _affinity_line
	_affinity_label.visible = _affinity_line != ""
	_meta_label.text = _meta
	_meta_label.visible = _meta != ""


## Every line this row prints, computed once from the view so `summary()` and
## `_render()` can never disagree about what the row says.
func _compute_lines() -> void:
	_name_line = _name_line_of()
	_refusal_line = _refusal_text()
	_ceiling_line = _ceiling_text()
	_affinity_line = _affinity_text()
	_meta = _meta_text()


## The authored display name, with the bare id as its fallback rather than the
## fallback WORD — an id is a fact, and this row has a separate voice for absence.
func _name_line_of() -> String:
	var race_id := String(_view.get("race", ""))
	if race_id == "":
		return NO_RACE
	var authored := String((_catalog.get(race_id, {}) as Dictionary).get("display_name", ""))
	return authored if authored != "" else race_id


## The refusals on ONE line, the closed paths first: a closed path is the refusal
## a player meets first, at conception, long before a realm ceiling matters.
func _refusal_text() -> String:
	var closed := _string_list(_view.get("closed_paths", []))
	var open := int(_view.get("open_path_count", 0))
	if closed.is_empty():
		return "%s · %d open" % [OPEN_ALL_PATHS, open]
	return "%s: %s · %d open" % [PATHS_CLOSED, ", ".join(closed), open]


## The ceiling as a realm ordinal and the lifespan in days. A ceiling of 0 is "no
## ceiling" and is never printed as `R0`.
func _ceiling_text() -> String:
	var ceiling := int(_view.get("realm_ceiling", 0))
	var ceiling_text := NO_CEILING if ceiling <= 0 else "%s%d" % [REALM_SUFFIX, ceiling]
	return (
		"Ceiling %s · reached R%d · %d %s"
		% [
			ceiling_text,
			int(_view.get("realm_reached", 0)),
			int(roundf(float(_view.get("lifespan", 0.0)))),
			DAYS,
		]
	)


## Affinities as the authored `element: value` pairs, sorted by element so two runs
## agree. **Unranked on purpose**: a race is not a score (ADR 0062), so there is no
## total here to print and none a future edit could add without breaking the rule.
func _affinity_text() -> String:
	var affinities := _affinity_map(_view.get("affinities", {}))
	if affinities.is_empty():
		return ""
	var keys := affinities.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s %.1f" % [String(key), float(affinities[key])])
	return "Affinities: %s" % ", ".join(parts)


## One quiet line of provenance, and the only thing on this row that is not a fact
## about the body itself.
func _meta_text() -> String:
	return BASELINE_NOTE if bool(_view.get("is_baseline", false)) else ""


## The fallback body gets the quieter card: it is the body nobody chose, and styling
## it like a specialist would read as an endorsement.
func _card_tone() -> StringName:
	return &"LockedCard" if bool(_view.get("is_baseline", false)) else &"ClaimCard"


## `{element: value}` as primitives. Coerced rather than trusted, because this is
## the map the panel formats and the standard says the panel owns what it renders.
func _affinity_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key in (value as Dictionary).keys():
		out[String(key)] = float((value as Dictionary)[key])
	return out


func _string_list(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(String(entry))
	return out
