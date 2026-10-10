extends TestCase

## ADR 0167 / BL-0815: a DOMAIN DELVE costs world time, end to end.
##
## The third consumer of ADR 0167's classes, after the season-scale retreat and the
## period-scale craft. A delve is season-scale (a journey into a place that exists once), so
## it pays `ItemWorkbenchPlay.DOMAIN_DELVE_PERIODS` through `advance_world` — the one
## dispatcher the wait, the retreat and the craft all end in — and only once the run is OPEN,
## so a refused delve costs nothing (ADR 0044).
##
## Never drive the thing under test: the app is the REAL `ItemWorkbenchApp` scene mounted by
## `SeamHarness`, and the figures asserted are the world fold's own total.

var _harness: SeamHarness = null
var _app: ItemWorkbenchPlay = null


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchPlay


func teardown() -> void:
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


func _booted() -> bool:
	if _app == null:
		return false
	assert_eq(
		_harness.boot_error, "", "the real ItemWorkbenchApp scene boots, or nothing below is proven"
	)
	return _harness.boot_error == ""


func _periods() -> int:
	return int(_app.call(&"world_summary").get("periods", 0))


## The first authored domain template, so the test does not name one that may be retired.
func _template_id() -> String:
	var templates: Array = DomainApi.templates()
	if templates.is_empty():
		return ""
	return String((templates[0] as Dictionary).get("template_id", ""))


func test_a_domain_delve_costs_world_time() -> void:
	if not _booted():
		return
	var template := _template_id()
	assert_ne(template, "", "the authored domain catalogue is not empty")
	if template == "":
		return
	var before := _periods()

	var entered := _app.call("_venture_domain_enter", template, 20261010) as Dictionary

	assert_eq(
		bool(entered.get("ok", false)), true, "the delve opens: %s" % entered.get("reason", "")
	)
	assert_eq(
		_periods() - before,
		ItemWorkbenchPlay.DOMAIN_DELVE_PERIODS,
		"the world moved by the authored delve cost"
	)
	assert_eq(
		int(entered.get("paid", 0)),
		ItemWorkbenchPlay.DOMAIN_DELVE_PERIODS,
		"and the report names the same figure the world moved"
	)


## A REFUSED delve costs nothing (ADR 0044): the time is paid only once the run is open.
func test_a_refused_delve_pays_nothing() -> void:
	if not _booted():
		return
	var before := _periods()

	var entered := _app.call("_venture_domain_enter", "no_such_template", 1) as Dictionary

	assert_eq(bool(entered.get("ok", true)), false, "an unknown template is refused")
	assert_eq(_periods(), before, "and the world did not move")
