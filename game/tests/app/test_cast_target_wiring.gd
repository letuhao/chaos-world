extends TestCase

## PROOF AT THE SEAM: the cast program is reachable from the RUNNING game, not merely
## from a test (ADR 0185).
##
## ## What was broken, and why a green suite did not see it
##
## Two features were complete and tested, and neither could be reached by a player:
##
##   - `TechniqueLoadoutScreen.bind_target` (`technique_loadout.gd:323`) existed, and
##     its only caller in the whole tree was `tests/ui/test_technique_screens.gd`. No
##     production code ever aimed the page at anything, so every real press on the row's
##     cast button fell through `act_cast`'s `_refuse_no_target`: no qi spent, no
##     cooldown started, and the message "Nothing to aim at" on every attempt.
##   - `TechniqueCastView` (`modules/techniques/technique_cast_view.gd`) had
##     `tests/modules/techniques/test_technique_cast_view.gd` and no production caller
##     at all, so the turn ledger nobody read was a turn ledger nobody produced.
##
## `technique_screens` was 132/0 and `techniques` 3260/0 with both dead. That is the
## defect class this file exists to make unfalsifiable again.
##
## ## WHY THE ASSERTIONS BELOW WALK THE REAL APP
##
## Every case here mounts the SHIPPED `ItemWorkbenchApp.tscn` through `SeamHarness` and
## drives its real `_ready`, then navigates the real route. Nothing instantiates the
## screen itself, because a self-instantiated screen can never satisfy any of these: the
## whole claim is that the COMPOSITION ROOT binds the seam, and a test that binds it
## itself proves only that `bind_target` works — which was already green.
##
## The negative case is the load-bearing one and it is what a mutation check bites on:
## delete `_bind_target_screen(screen)` from the route arm and
## `test_a_cast_from_the_row_reaches_the_resolver_on_the_mounted_app` goes red while
## every behavioural test in `tests/ui/test_technique_screens.gd` stays green.

const LOADOUT_SCENE := "res://src/ui/screens/technique_loadout.tscn"
const ROUTE_LOADOUT := &"technique_loadout"
const ELEMENT := &"fire"

## `TechniqueCatalog` is process-wide, so a second register of the same id would
## silently replace the first. A serial keeps every fixture id in this file unique, the
## same rule `test_combat_reachability.gd` uses.
static var _serial: int = 0
var _harness: SeamHarness = null


func setup() -> void:
	_harness = SeamHarness.mount_new()


func teardown() -> void:
	# The damage seam is a PROCESS-WIDE binding and the runner shares one process
	# across every suite, so this suite must leave it as it found it. An empty Callable
	# clears it deterministically.
	TechniqueCasting.set_resolver(Callable())
	if _harness != null:
		_harness.teardown()
	_harness = null


## The mounted cast page, or null. `mounted()` only ever returns a node the composition
## root parented, which is the property the whole file rests on.
func _page() -> UiScreen:
	if _harness == null:
		return null
	return _harness.mounted(LOADOUT_SCENE) as UiScreen


## Navigate to the cast route the way a player does — through the app's own
## `navigate_to`, not by instantiating the scene.
func _open_loadout() -> Dictionary:
	var moved := _harness.navigate(ROUTE_LOADOUT)
	if bool(moved.get("ok", false)):
		return moved
	return moved


## The app's own hero — built and fully installed by the mounted `_ready`, not by this
## suite. A fixture actor built here would hide the very wiring under test.
func _hero() -> Actor:
	return _harness.actor


## An active technique on `path_id`, learned and EQUIPPED through the real facade verbs
## on the app's own hero, so `activate` will not refuse `not_equipped` and a refusal
## would prove nothing. `codex.learn` rather than `TechniquesApi.learn`, because `learn`
## is paid for out of cultivation progress and the study price is not what this file is
## about.
func _equipped(path_id: StringName, meridian: StringName = &"") -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("cast_target_wiring_%d" % _serial)
	def.display_name = "Strike"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = path_id
	def.magnitude = 100.0
	def.element = ELEMENT
	def.aim_meridian = meridian
	def.qi_cost = 25.0
	def.cooldown = 10.0
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(_hero()).learn(def.id)
	var equipped: Dictionary = TechniquesApi.equip(_hero(), def)
	assert_eq(
		bool(equipped.get("ok", false)),
		true,
		"the fixture def is bound into a real slot (%s)" % String(equipped.get("reason", ""))
	)
	return def


## The qi the hero held before a press, read off the POOL rather than off a message, so
## "nothing was spent" is a statement about state.
func _qi() -> float:
	return float(_hero().resource(&"qi").current)


## The mastery rung, which `activate` grants on a fired cast and which a refused cast
## leaves alone. The third thing "it cost nothing" has to mean.
func _rung(technique_id: StringName) -> int:
	return int(TechniquesApi.inspect(_hero(), technique_id).get("rung", 0))


## Press the row's REAL cast button — a `Button`, its real `pressed` signal, the screen's
## real handler — rather than calling `act_cast` directly. This is the defect's exact
## shape: the verb worked and the player's press never reached it.
func _press_cast(page: UiScreen, technique_id: StringName) -> bool:
	for row in page.get(&"_slot_rows") as Array:
		var view: Dictionary = row.call(&"summary")
		if String(view.get("technique_id", "")) != String(technique_id):
			continue
		var button := row.get_node_or_null("%CastButton") as Button
		if button == null or not button.visible or button.disabled:
			return false
		button.pressed.emit()
		return true
	return false


# --- THE BINDING: the composition root aims the page, and nothing else --------


## **THE REACHABILITY CLAIM.** Mounting the shipped app and navigating the shipped route
## must leave the page AIMED — without this suite ever touching the screen.
##
## Before the fix this read `has_target: false` with a production-castable row sitting
## on screen, and `test_a_cast_from_the_row_reaches_the_resolver_on_the_mounted_app`
## below refused with `no_target`. Both halves are asserted here so a failure names
## WHICH of them broke rather than only that "the wiring is gone".
func test_the_mounted_route_binds_a_target_without_a_test_touching_the_screen() -> void:
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	var moved := _open_loadout()
	assert_eq(
		bool(moved.get("ok", false)),
		true,
		"the cast route is reachable: %s" % String(moved.get("note", ""))
	)
	var page := _page()
	assert_ne(page, null, "the route mounted the cast page itself, not a fresh copy")
	if page == null:
		return

	var view := page.summary()
	assert_eq(
		bool(view.get("has_target", false)),
		true,
		(
			"MISSING SEAM: the cast route mounted and the page has nowhere to aim, so "
			+ "`bind_target` still has no production caller and every press is refused "
			+ "`no_target` (ADR 0185)"
		)
	)
	var target_id := String(view.get("target_id", ""))
	assert_ne(target_id, "", "and the aim names the foe it will land on")
	assert_eq(bool(view.get("can_fire", false)), true, "so a castable row is actually FIREABLE")

	# Published through the app's own probe, not by reading a private field — the same
	# contract `routes()` and `summary()` offer. It is the question a player asks
	# ("what would a press hit?") answered by the root that owns the answer.
	var probe: Dictionary = _harness.app.call(&"cast_target_summary")
	assert_eq(bool(probe.get("has_target", false)), true, "and the root reports the same aim")


## The WIRING itself, as its own case: the `bind_target` call exists ON THE PATH THAT
## RUNS. `test_the_mounted_route_binds_a_target_without_a_test_touching_the_screen`
## proves the observable consequence; this proves the seam is what produces it, so an
## arm that happened to aim the page some other way could not satisfy the suite by
## accident.
##
## Asserted against the MOUNTED screen object rather than against source text, because a
## source-text check would pass on a comment — and a docblock describing the injection
## without the injection is precisely how the previous state looked.
func test_the_root_binds_the_seam_through_the_screens_own_method() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	assert_ne(page, null, "the cast page is mounted")
	if page == null:
		return
	assert_eq(
		page.has_method(&"bind_target"),
		true,
		"the mounted page still publishes the seam the root injects through"
	)
	var app := _harness.app as ItemWorkbenchApp
	assert_ne(app, null, "the mounted root is the composition root")
	assert_eq(
		app.has_method(&"clear_cast_target"),
		true,
		"and it publishes the deterministic unbind, so a stale aim is not one call away"
	)


# --- WITH A BOUND TARGET: the press reaches the resolver ----------------------


## **THE CAST ACTUALLY LANDS.** A press on the row's real button, on the mounted page,
## reaches `TechniqueCasting.activate`'s resolver and the screen reports the outcome.
##
## This is the test a mutation on the route arm turns red. Delete
## `_bind_target_screen(screen)` from `ROUTE_TECHNIQUE_LOADOUT`'s arm and `activate` is
## never called: `act_cast` refuses `no_target` above the pay, `resolver.calls` stays 0,
## and no qi moves. Every case in `tests/ui/test_technique_screens.gd` stays green,
## because each of them binds the target ITSELF.
func test_a_cast_from_the_row_reaches_the_resolver_on_the_mounted_app() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	if page == null:
		return
	var resolver := _Resolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	var def := _equipped(PathState.QI)
	var qi_before := _qi()
	var rung_before := _rung(def.id)

	assert_eq(_press_cast(page, def.id), true, "the row's button was a live control")
	assert_eq(
		resolver.calls,
		1,
		(
			"the press never reached the damage seam: the page was mounted unbound, so "
			+ "`act_cast` refused `no_target` above the pay and `activate` was never called"
		)
	)
	# The consequences, read off STATE rather than off the message: the cast that
	# reached the resolver also paid and cooled down. A press that reached nothing would
	# leave all three untouched, so this distinguishes "fired" from "was refused" even
	# if a future edit made both say "Nothing to aim at".
	assert_eq(_qi() < qi_before, true, "and it spent the caster's own qi")
	assert_eq(
		_hero().component(TechniquesApi.CASTING_COMPONENT).is_ready(def.id),
		false,
		"so the cooldown started, which a refused `no_target` never does"
	)
	assert_eq(_rung(def.id) > rung_before, true, "and it counted as a use")


## With the target bound, the screen reports what the cast did — through its EXISTING
## `summary()` and message channel, with no new UI concept. The turn readback rides the
## same contract the three `last_*` rows already publish.
func test_the_screen_reports_the_turn_through_its_existing_summary() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	if page == null:
		return
	TechniqueCasting.set_resolver(Callable(_OutcomeResolver.new(), "resolve"))
	var def := _equipped(PathState.QI)
	# Before any cast there is no turn, and the honest reading is "nothing measured yet"
	# rather than a turn that moved nothing. A fabricated zero here is what DEF-0097
	# exists to prevent.
	var before: Dictionary = page.summary()
	assert_eq(
		(before.get("turn", {}) as Dictionary).is_empty(),
		true,
		"no turn is published before the first cast"
	)
	assert_eq(
		bool(before.get("turn_measured", false)), false, "and nothing claims to have measured one"
	)

	_press_cast(page, def.id)
	var view := page.summary()
	var turn: Dictionary = view.get("turn", {}) as Dictionary
	assert_eq(
		bool(view.get("turn_measured", false)), true, "the cast was measured against a snapshot"
	)
	assert_eq(
		String(view.get("turn_cast", "")), String(def.id), "the turn names the cast it read back"
	)
	assert_eq(
		String(view.get("turn_activity", "")) != "",
		true,
		"and reports an activity, so 'never resolved' is distinguishable from 'missed'"
	)
	assert_eq(bool(view.get("turn_landed", false)), true, "the seam's descriptor landed")
	# `health_lost` is the ENGINE's figure, negated once by the module. The screen relays
	# it; it does not compute it — a second negation here could disagree with the spine's.
	assert_eq(float(view.get("turn_health_lost", 0.0)), 18.0, "and reports the health the foe lost")
	# The message channel is the OTHER half of the same report. It must SAY the turn, not
	# merely repeat that a verb ran — "Fired <id>" for a sea erosion and for a killing
	# blow is the readout that hid DEF-0097 in the first place.
	var message := String(view.get("message", ""))
	assert_eq(
		message.contains(String(def.id)), true, "the message names the technique: %s" % message
	)
	assert_eq(
		message.length() > ("Fired %s" % String(def.id)).length(),
		true,
		"and says what the turn DID rather than only that a verb ran: %s" % message
	)


## **`_turn_of` DID NOT RETURN `{}` FOR A CAST THAT RESOLVED.** The direct assertion on
## the function whose return value the whole readout rests on.
##
## The mutation this pins is narrower and more brutal than a wrong number: the production
## call was replaced by `var produced: Variant = {}`, which is indistinguishable from
## "the module is absent" at the one call site that reads it. `_readback_type()` still
## returned a script, the null guard still passed, and `_turn_of` still returned a
## well-typed `Dictionary` — so nothing type-checked, nothing crashed, and every
## downstream consumer (`summary()`, `_fired_text`) received a LEGAL shape that happened
## to be empty. `measured: false` is the readback's own "nothing was recorded" answer,
## so the empty result read as an honest unmeasured turn rather than as a failure.
##
## Which is why this asserts NON-EMPTINESS at the seam and not only the fields the
## summary relays: every other assertion in this file reads the summary's RELAY of the
## turn, so a `_turn_of` that returned `{}` and a summary that dropped a good turn would
## both leave those green for different reasons. Calling the private function directly is
## the only way to name which of the two broke.
func test_the_turn_readback_itself_is_not_empty_for_a_resolved_cast() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	if page == null:
		return
	TechniqueCasting.set_resolver(Callable(_OutcomeResolver.new(), "resolve"))
	var def := _equipped(PathState.QI)
	# The same foe the page is aimed at — the root's own `_cast_target()`, not a fixture.
	# A fixture would measure the wrong pair: `of` refuses a snapshot that was not taken
	# from the actors it is handed, so aiming at a stranger yields `{}` for reasons that
	# have nothing to do with the bug under test.
	var target := _harness.app.call(&"_cast_target") as Actor
	assert_ne(target, null, "the root has a foe to aim the cast at")
	if target == null:
		return
	var before: Dictionary = page.call(&"_snapshot_of", target)
	var fired: Dictionary = _hero().component(TechniquesApi.CASTING_COMPONENT).activate(
		_hero(), def.id, target
	)
	var turn: Dictionary = page.call(&"_turn_of", fired, before, target) as Dictionary

	# The bug's exact shape: a well-typed but empty dictionary, which every caller
	# accepts and no caller reports.
	assert_ne(
		turn.is_empty(),
		true,
		"_turn_of returned {} for a cast that fired; the readback was never called"
	)
	# And the emptiness that matters is not the container's — it is `measured`, the one
	# field the module uses to say "I diffed something". A turn full of defaults still
	# fails the readout, so this is the assertion a stubbed call cannot satisfy.
	assert_eq(
		bool(turn.get("measured", false)),
		true,
		"the turn reports itself MEASURED, so a stub returning {} cannot pass: %s" % str(turn)
	)
	assert_eq(
		float(turn.get("health_lost", 0.0)), 18.0, "and it carries the engine's figure, not a zero"
	)
	assert_eq(String(turn.get("cast", "")), String(def.id), "and it names the cast it read back")


# --- WITH NO TARGET: refused, and it costs nothing ---------------------------


## **NO TARGET, NO COST.** `clear_cast_target` unbinds the mounted page, and a press
## after that is refused `no_target` with NO qi spent, NO cooldown started and NO rung
## granted — because `activate` pays before it resolves, so the refusal has to happen
## above the pay.
##
## This is the case that makes "a stale target is worse than none" concrete: the
## unbound state is not a degraded one, it is the state in which a press is free.
func test_no_target_is_refused_by_name_and_costs_nothing() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	if page == null:
		return
	var resolver := _Resolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	var def := _equipped(PathState.QI)
	var qi_before := _qi()
	var rung_before := _rung(def.id)

	var cleared: Dictionary = _harness.app.call(&"clear_cast_target")
	assert_eq(int(cleared.get("cleared", 0)) > 0, true, "the root unbound the page it mounted")
	assert_eq(
		bool(page.summary().get("has_target", false)),
		false,
		"so the page reads as having nowhere to aim"
	)

	# `act_cast` directly, because with no target the row's own guard refuses to enable
	# the button — which is correct, and is asserted below. The claim here is that the
	# press that DOES get through costs nothing.
	var refused: Dictionary = page.call(&"act_cast", def.id)
	assert_eq(bool(refused.get("ok", false)), false, "the cast did not succeed")
	assert_eq(String(refused.get("reason", "")), "no_target", "for the named reason")
	assert_eq(bool(refused.get("fired", false)), false, "and it says nothing was fired")
	assert_eq(bool(refused.get("resolved", false)), false, "and nothing was hit")
	assert_eq(resolver.calls, 0, "the damage seam was never reached")
	assert_eq(_qi(), qi_before, "no qi was spent")
	assert_eq(
		_hero().component(TechniquesApi.CASTING_COMPONENT).is_ready(def.id),
		true,
		"no cooldown was started"
	)
	assert_eq(_rung(def.id), rung_before, "and no mastery rung was granted")
	# And the refusal is a MESSAGE the player can act on, not a silent false.
	assert_eq(
		String(page.summary().get("message", "")),
		"%s: %s" % [String(def.id), String(TechniqueLoadoutScreen.NO_TARGET_BODY)],
		"the page says, in words, that nothing was fired and nothing was spent"
	)
	# With nowhere to aim the row refuses to offer the press at all, so a player is
	# never handed a button whose only possible outcome is the refusal above.
	assert_eq(
		_press_cast(page, def.id), false, "and the row's own button is disabled rather than live"
	)


# --- A TARGET THAT HAS GONE AWAY --------------------------------------------


## **A STALE TARGET IS A BUG, NOT A FEATURE.** A foe that has gone away must not be cast
## at: the page is unbound, the press is refused for free, and the whole drill is
## dropped so the NEXT encounter cannot inherit it either.
##
## The two halves matter separately. Unbinding the page is what stops the immediate
## press; dropping the cached body is what stops a LATER one, because `_cast_target()`
## would otherwise hand the same foe back to a fresh mount.
func test_a_target_that_has_gone_away_is_not_cast_at() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	if page == null:
		return
	var resolver := _Resolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	# The encounter was live and the page was aimed at it.
	assert_eq(
		bool(page.summary().get("has_target", false)),
		true,
		"the encounter is live and the page is aimed"
	)
	var during := String(page.summary().get("target_id", ""))

	# The encounter ENDS.
	_harness.app.call(&"clear_cast_target")
	assert_eq(
		bool(page.summary().get("has_target", false)),
		false,
		"the encounter ended, so the page is not aimed"
	)
	var qi_before := _qi()
	var def := _equipped(PathState.QI)
	var refused: Dictionary = page.call(&"act_cast", def.id)
	assert_eq(
		String(refused.get("reason", "")),
		"no_target",
		"a cast at a foe that has gone away is refused, never spent"
	)
	assert_eq(resolver.calls, 0, "and it never reached the seam")
	assert_eq(_qi(), qi_before, "so it cost nothing")

	# And the NEXT encounter gets a DIFFERENT body, so the old foe cannot reappear as
	# the aim of a later mount.
	_open_loadout()
	var after := String(page.summary().get("target_id", ""))
	assert_eq(after != "", true, "a later encounter is aimed again")
	assert_eq(
		after != during,
		true,
		(
			"at a DIFFERENT foe: the cache was not dropped, so a body from an encounter "
			+ "that ended ('%s') is still what a later mount aims at" % during
		)
	)


## The unbind is a DOOR a production path walks, not only a verb a test calls. A rebirth
## replaces the hero under a mounted page, and that is the one event that can leave the
## page aimed at a foe the fallen body was fighting — so `adopt_actor` unbinds beside
## its re-`setup`.
func test_a_rebirth_clears_the_aim_rather_than_leaving_it_pointed_at_the_old_foe() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	_open_loadout()
	var page := _page()
	if page == null:
		return
	assert_eq(bool(page.summary().get("has_target", false)), true, "the page starts aimed")
	var before := String(page.summary().get("target_id", ""))

	# The rebirth, through the root's own public verb — the same call the soul and death
	# loop makes. Built and installed the way `_build_actor` builds one, so the adopted
	# body is a complete hero rather than a half-wired shell.
	var reborn := ActorFactory.build(&"reborn_hero")
	ActorFactory.with_body_cultivation(reborn)
	ActorFactory.with_qi_cultivation(reborn)
	ActorFactory.with_mind_cultivation(reborn)
	var app := _harness.app as ItemWorkbenchApp
	app.adopt_actor(reborn)

	assert_eq(
		bool(page.summary().get("has_target", false)),
		false,
		(
			(
				"MISSING SEAM: a rebirth left the cast page aimed at '%s', so a press would "
				+ "spend real qi on a foe the fallen hero was fighting (ADR 0185)"
			)
			% before
		)
	)
	assert_ne(
		page.call(&"actor"), reborn, "and the page is pointed at the body that replaced the old one"
	)


# --- The facade cap is untouched ---------------------------------------------


## Neither gap was closed by growing `TechniquesApi`. The readback is a named type the
## facade publishes as a CONSTANT, exactly as `TechniqueCasting` and `TechniqueDelivery`
## are reached, and the target seam is a method on a SCREEN.
func test_neither_gap_added_a_thirteenth_facade_method() -> void:
	var published: Array[String] = []
	for method in load("res://src/modules/techniques/api.gd").get_script_method_list():
		var method_name := String(method.get("name", ""))
		if not method_name.begins_with("_") and not published.has(method_name):
			published.append(method_name)
	assert_eq(published.size(), 12, "still exactly twelve, found %d" % published.size())
	for forbidden in [&"cast_view", &"cast_readback", &"bind_target", &"snapshot"]:
		assert_eq(
			published.has(String(forbidden)),
			false,
			"and no verb named '%s' crept onto the facade" % String(forbidden)
		)
	# The readback is reached through the constant, which is what the cap forces.
	assert_eq(
		String(TechniquesApi.CAST_VIEW), "technique_cast_view", "the facade NAMES the readback"
	)


## The shape a UI test hands to `TechniqueCasting.set_resolver` in place of the spine.
## Installed here so a refusal above the pay is visible as `calls == 0` rather than
## inferred from a message.
class _Resolver:
	extends RefCounted

	var calls: int = 0

	func resolve(_attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		calls += 1
		return {"amount": 12.0, "target": String(target.id), "id": String(def.id)}


## The same seam answering the shape `CombatOutcome.to_dict()` actually returns, so a
## test asserting `health_lost` is asserting the ENGINE's figure arriving intact rather
## than a number this suite invented.
class _OutcomeResolver:
	extends RefCounted

	func resolve(_attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		return {
			"amount": 18.0,
			"health_delta": -18.0,
			"landed": true,
			"crit": false,
			"missed": false,
			"effects": [],
			"target": String(target.id),
			"id": String(def.id),
		}
