extends TestCase

## **THE READOUT'S WOUND ROW.** ADR 0174 minted a drill body so the wound ledger is
## readable, and the ledger never bound — so the panel's wound row could not render.
##
## ## What was broken, and why the behavioural suites stayed green
##
## `ItemWorkbenchApp._build_readout_target` enrolled the body and returned it. It never
## called `CombatBoot.install`, and `install` is the only production caller of
## `CombatEngineApi.attach_wounds` — the ONLY production writer of the `body_wounds`
## component. So on the drill:
##
##   - `CombatEngineApi.wounds_of(target)` answered `null`;
##   - `CombatReadoutScreen._wounds_payload` returned `{}`;
##   - `CombatReadoutPanel.wounds_text` returned `No meridian carries a wound.`
##     FOREVER, on a body that had taken every blow the reader ever threw.
##
## `effects[]` was never the missing thing: the blow DID carry `body.wound`, and
## `EffectApply._wound` refused it because it reads `CombatEngineApi.wounds_of`, which
## answered null. So the defect is invisible to any assertion about effects and visible
## only to one about the LEDGER.
##
## ## Why this file walks the REAL app
##
## `ui_driver.gd:238-239` DOES call `CombatBoot.install(_drills)`, so the headless drive
## renders a wound row whether or not production does — a measure of the harness, not of
## the game. Every case below mounts the shipped `ItemWorkbenchApp.tscn` and navigates
## the shipped route, because the claim is that the COMPOSITION ROOT binds the ledger.
##
## The mutation this pins: delete `CombatBoot.install(drill)` from
## `_build_readout_target` and the two accumulation cases go red while every behavioural
## readout suite stays green.

const READOUT_SCENE := "res://src/ui/screens/combat_readout.tscn"
const ROUTE_READOUT := &"combat_readout"
## The panel's own wording for an empty ledger. Quoted so the assertion says what a
## PLAYER read, not what a field happened to hold.
const NO_WOUNDS := "No meridian carries a wound."
## The effect id a wound travels under, from the panel's own constant rather than a
## literal — a rename in the module would fail here rather than silently pass.
const KIND_WOUND := &"body.wound"
## The route id used only as a place to walk away TO. It is the root's own constant
## rather than a literal, so a rename of the loot route cannot turn this into a no-op
## that silently "passes" by never navigating.
const ROUTE_LOOT := &"loot_encounter"

var _harness: SeamHarness = null


func setup() -> void:
	_harness = SeamHarness.mount_new()


func teardown() -> void:
	if _harness != null:
		_harness.teardown()
	_harness = null


## The mounted readout screen the root itself parented, or null.
func _screen() -> CombatReadoutScreen:
	if _harness == null:
		return null
	return _harness.mounted(READOUT_SCENE) as CombatReadoutScreen


## Navigate the shipped route the way a player does. `ok` is asserted by the callers so a
## failed navigation reports the SEAM rather than a downstream empty read.
func _open() -> Dictionary:
	if _harness == null:
		return {"ok": false, "note": "no harness"}
	return _harness.navigate(ROUTE_READOUT)


## The panel's view, as primitives, through the screen's EXISTING `summary`.
func _view() -> Dictionary:
	var screen := _screen()
	if screen == null:
		return {}
	return screen.summary().get("readout", {}) as Dictionary


## Every severity the view published, as a flat `{meridian: severity}` map. A dict
## rather than the first row because a body aim may strike several channels and a suite
## that read only row 0 would pass on a ledger that happened to sort the wounded channel
## first.
func _severities() -> Dictionary:
	var out: Dictionary = {}
	for entry in _view().get("wound_rows", []) as Array:
		if entry is Dictionary:
			out[String((entry as Dictionary).get("meridian", ""))] = float(
				(entry as Dictionary).get("severity", 0.0)
			)
	return out


# --- THE BINDING -------------------------------------------------------------


## **THE LEDGER IS BOUND.** The drill body the root minted carries the wound component
## the moment the readout route is opened — which is the one production writer of it.
func test_the_mounted_readout_route_binds_a_wound_ledger_to_its_drill_body() -> void:
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	var moved := _open()
	assert_eq(
		bool(moved.get("ok", false)),
		true,
		"the readout route is reachable: %s" % String(moved.get("note", ""))
	)
	var screen := _screen()
	assert_ne(screen, null, "the route mounted the readout screen itself, not a fresh copy")
	if screen == null:
		return
	var drill := screen.target()
	assert_ne(drill, null, "the screen is aimed at the root's drill body")
	if drill == null:
		return
	assert_ne(
		CombatEngineApi.wounds_of(drill),
		null,
		(
			"MISSING SEAM: `CombatEngineApi.attach_wounds` never ran on the drill, so the "
			+ "only production writer of `body_wounds` was skipped and the readout's "
			+ "wound row can never render (ADR 0174)"
		)
	)


## The same fact as the PANEL reads it, through the screen's own payload bridge — not by
## reading the component. `_wounds_payload` is what `show_wounds` is handed, so an empty
## payload is precisely the state that rendered `No meridian carries a wound.`.
func test_the_screen_wounds_payload_is_a_ledger_rather_than_an_empty_dictionary() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	var moved := _open()
	assert_eq(bool(moved.get("ok", false)), true, "the readout route opened")
	var screen := _screen()
	if screen == null:
		return
	var payload: Dictionary = screen.call(&"_wounds_payload") as Dictionary
	assert_ne(
		payload.is_empty(),
		true,
		"the screen hands the panel a real ledger payload; an empty one is the defect"
	)
	assert_eq(
		payload.get("severity", {}) is Dictionary,
		true,
		"and the payload carries the ledger's own shape"
	)


# --- THE ACCUMULATION, which is the point of the cache -----------------------


## **A WOUND ACCUMULATES ACROSS TWO STRIKES.** The cache in
## `item_workbench_body.gd:_readout_target` exists for this sentence and nothing else:
## "a reader who re-enters the route strikes the same body twice and can watch a wound
## accumulate". Without the bound ledger the second strike is identical to the first,
## which is what makes the row unobservable rather than merely unflattering.
func test_a_second_strike_raises_the_severity_on_the_same_channel() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	var moved := _open()
	assert_eq(bool(moved.get("ok", false)), true, "the readout route opened")
	var screen := _screen()
	if screen == null:
		return
	assert_eq(bool(screen.call("act_strike")), true, "the first blow resolved")

	var first := _severities()
	assert_eq(
		first.is_empty(),
		false,
		"the first strike left a row: %s" % String(_view().get("wounds_line", ""))
	)
	var meridian := String(first.keys()[0])
	var first_line := String(_view().get("wounds_line", ""))
	assert_eq(
		KIND_WOUND in Array(_view().get("effect_kinds", [])),
		true,
		"and the blow carried the wound effect, so the rise below is the LEDGER and not the effects"
	)

	assert_eq(bool(screen.call("act_strike")), true, "the second blow resolved")

	var second := _severities()
	assert_eq(second.has(meridian), true, "the same channel is still the wounded one")
	assert_eq(
		float(second[meridian]) > float(first[meridian]),
		true,
		(
			"the second strike RAISED '%s' from %.4f to %.4f: the cache exists so a wound "
			+ (
				"accumulates, and it cannot without the bound ledger"
				% [meridian, float(first[meridian]), float(second[meridian])]
			)
		)
	)
	# The rendered sentence is what a player reads, so it is asserted as TEXT and not only
	# as numbers: the line quotes the severity, so a rise is a changed line, and it is
	# never the empty-ledger wording the panel used to print on every blow.
	var second_line := String(_view().get("wounds_line", ""))
	assert_eq(second_line == first_line, false, "the rendered wounds line CHANGED")
	assert_eq(
		second_line == NO_WOUNDS,
		false,
		"and the reader is no longer told no meridian carries a wound"
	)


## The cache half: re-opening the route keeps the SAME body, so the wound earned before
## the walk is still there afterwards. A drill reminted per mount would read as a clean
## body every time and the row would be a thing that only exists while you stare at it.
func test_re_entering_the_route_strikes_the_same_body_with_its_wounds_intact() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	var moved := _open()
	assert_eq(bool(moved.get("ok", false)), true, "the readout route opened")
	var screen := _screen()
	if screen == null:
		return
	assert_eq(bool(screen.call("act_strike")), true, "the first blow resolved")
	var struck := screen.target()
	var earned := _severities()
	assert_eq(earned.is_empty(), false, "a wound was earned before walking away")

	# Walk away and come back, through the app's own navigation rather than by
	# re-mounting anything — a fresh mount would measure a different app.
	_harness.navigate(ROUTE_LOOT)
	var again := _open()
	assert_eq(bool(again.get("ok", false)), true, "and back to the readout")
	var revisited := _screen()
	assert_ne(revisited, screen, "the route really did remount the screen")
	if revisited == null:
		return
	assert_eq(
		revisited.target(),
		struck,
		"the cached drill is the same body, which is what makes a wound persist"
	)
	assert_eq(bool(revisited.call("act_strike")), true, "the third blow resolved")
	var carried := _severities()
	var meridian := String(earned.keys()[0])
	assert_eq(
		float(carried.get(meridian, 0.0)) > float(earned[meridian]),
		true,
		"the wound survived the walk away and grew on the next strike"
	)
