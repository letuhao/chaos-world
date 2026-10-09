extends TestCase

## BL-0951 / ADR 0939, S15: the foundation readout panel.
##
## The UI program is a pure consumer; these tests assert `summary()` and the rendering
## inputs, never pixels, and drive the panel with no scene tree so `@onready` could not have
## been used.

const PANEL := "res://src/ui/panels/foundation_panel.tscn"


func _panel() -> FoundationPanel:
	var panel := (load(PANEL) as PackedScene).instantiate() as FoundationPanel
	# Guard: a scene whose root script is unattached instantiates as a bare Control, every
	# cast below silently yields null, and each test then passes against `{}`.
	assert_ne(panel, null, "foundation_panel.tscn roots a FoundationPanel")
	return panel


func _summary(foundation: float, karmic: float, rows: Array) -> Dictionary:
	return {
		"foundation": foundation,
		"karmic": karmic,
		"count": rows.size(),
		"weakest": "",
		"snapshots": rows,
	}


func test_an_empty_state_reads_as_empty() -> void:
	var panel := _panel()
	assert_eq(panel.summary(), {}, "nothing handed over, nothing to render")


func test_the_panel_reports_the_carried_foundation_and_rows() -> void:
	var panel := _panel()
	panel.set_state(_summary(0.4, 0.05, [{"realm_id": "qi_refining", "perfection": 0.4}]))
	var view := panel.summary()
	assert_eq(bool(view.get("bound", false)), true, "the panel bound its widgets")
	assert_almost_eq(float(view.get("foundation", -1.0)), 0.4, "the carried foundation")
	assert_almost_eq(float(view.get("karmic", -1.0)), 0.05, "the karmic floor")
	assert_eq(int(view.get("count", -1)), 1, "one realm left")
	var rows: Array = view.get("rows", [])
	assert_eq(rows.size(), 1, "one row")
	assert_eq(
		String((rows[0] as Dictionary).get("realm_id", "")), "qi_refining", "naming the realm"
	)


## The wall row reads met/unmet from the two numbers a path's preview publishes.
func test_the_wall_reads_met_or_unmet() -> void:
	var panel := _panel()
	panel.set_state(_summary(0.2, 0.0, []), {"foundation": 0.2, "min_foundation": 0.3})
	var unmet: Dictionary = panel.summary().get("wall", {})
	assert_eq(bool(unmet.get("met", true)), false, "below the wall is unmet")
	assert_almost_eq(float(unmet.get("min_foundation", -1.0)), 0.3, "and the wall is named")
	panel.set_state(_summary(0.4, 0.0, []), {"foundation": 0.4, "min_foundation": 0.3})
	var met: Dictionary = panel.summary().get("wall", {})
	assert_eq(bool(met.get("met", false)), true, "above the wall is met")


func test_the_summary_is_json_clean() -> void:
	var panel := _panel()
	panel.set_state(_summary(0.4, 0.0, [{"realm_id": "qi_refining", "perfection": 0.4}]))
	var parsed: Variant = JSON.parse_string(JSON.stringify(panel.summary()))
	assert_eq(parsed is Dictionary, true, "the readout is primitives only")
