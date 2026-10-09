extends TestCase

## THE REACHABILITY PROOF FOR `TechniqueCastView`, at the one layer that can run it.
##
## ## Why this file exists at all
##
## `tests/modules/techniques/test_technique_cast_view.gd` asserts the readback's own
## arithmetic over 90 assertions and is green, and `tests/app/test_cast_target_wiring.gd`
## asserts the readback through the mounted composition root. Both were unrunnable while
## `src/app/item_workbench_app.gd` failed to parse (a duplicate-constant breakage in
## `src/modules/loot/`, owned by another session), so the turn assertions had NO
## executable home for as long as that lasted.
##
## **The mutation check is what justifies this file, and it is the load-bearing part.**
## Remove the production `view.call(&"of", fired, before, _actor, aimed)` from
## `TechniqueLoadoutScreen._turn_of` and the entire `technique_screens` suite stays
## 132/0 green — the turn was published in `summary()` and printed in the message, but
## no runnable suite asserted a VALUE off it. `turn`, `turn_measured`, `turn_cast`,
## `turn_activity`, `turn_landed`, `turn_health_lost` and `turn_remaining_health` were
## all asserted only from the app suite, and that suite cannot boot.
##
## So the assertion that catches it lives here, in a suite that needs nothing but the
## module and the screen. Asserting the readback THROUGH the screen's own `summary()`
## channel — rather than through the app — is what makes the proof survive the one
## layer that is currently broken. And `ui/` decides no damage: every number below is
## read off the descriptor the resolver returned, so the test asserts the engine's
## figures arriving intact, not a figure this file invented.
##
## ## Why the screen owns the pair, and the app owns nothing
##
## `TechniquesApi` used to publish exactly 12 public methods at `MAX_FACADE_PUBLIC_METHODS`,
## so the readback could not become a thirteenth `static func`. ADR 0265 deleted that cap, so
## the constraint is gone — but the SHAPE is kept deliberately, because a type reached by name
## is a better seam than a thirteenth verb regardless of how many verbs a facade may publish.
## It is reached as a named type the facade publishes as the CONSTANT `CAST_VIEW`, exactly as
## `TechniqueCasting` and `TechniqueDelivery` are reached —
## `game/src/ui/screens/technique_loadout.gd:121`
## `_readback_type()` and `:595` `_snapshot_of()` / `:606` `_turn_of()`. `act_cast` takes
## the snapshot immediately before `activate` and the readback immediately after
## (`:380-382`), which is the only place that can see both sides of the call. The app
## already owns aiming (ADR 0185); it adds no cast readback and grows no facade verb.

const LOADOUT_SCENE := "res://src/ui/screens/technique_loadout.tscn"
const REALM := &"qi_refining"

var _screen: UiScreen = null


func teardown() -> void:
	# The damage seam is PROCESS-WIDE and the runner shares one process across every
	# suite, so it is cleared here exactly as `tests/ui/test_technique_screens.gd` does.
	TechniqueCasting.set_resolver(Callable())
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null


## The shipped scene, mounted the way a shell mounts it. Nothing here instantiates the
## screen's logic by hand: the whole claim is that the page a player presses reaches the
## readback, so a hand-rolled double would prove nothing about the shipped page.
func _loadout() -> UiScreen:
	_screen = load(LOADOUT_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_screen)
	return _screen


## A hero on the qi path with the techniques module attached — what a screen meets at
## boot. `TechniquesApi.attach` is idempotent, so the screen re-attaching changes nothing.
func _hero() -> Actor:
	var actor := Actor.new(&"readback_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 400.0))
	actor.set_path(PathState.new(PathState.QI, REALM))
	actor.set_path(PathState.new(PathState.BODY, REALM))
	actor.set_path(PathState.new(PathState.MIND, REALM))
	TechniquesApi.attach(actor)
	return actor


## The foe a cast lands on. It carries a `health` pool because `remaining_health` is
## read off the POOL, not off the descriptor — a pool-less target answers 0.0 and the
## readback would then be reporting "it died" about a body that was never wounded.
func _foe(foe_id: StringName) -> Actor:
	var foe := Actor.new(foe_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	foe.add_resource(ResourcePool.new(&"health", 100.0))
	return foe


## An active qi technique, learned and EQUIPPED on `hero` so `activate` cannot refuse
## `not_equipped` — a refusal would prove nothing about the readback.
##
## `TechniqueCatalog` is process-wide, so a second register of the same id would silently
## replace the first. The unique prefix keeps this file's ids out of every other suite's.
func _equipped(hero: Actor) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"readback_reachable_strike"
	def.display_name = "Strike"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = PathState.QI
	def.qi_cost = 40.0
	def.cooldown = 10.0
	def.mastery_rungs = 4
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(hero).learn(def.id)
	TechniquesApi.equip(hero, def)
	return def


## The seam answering the shape `CombatOutcome.to_dict()` really returns, so an
## assertion about `health_lost` is asserting the ENGINE's figure arriving intact.
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


# --- THE REACHABILITY CLAIM ------------------------------------------------------


## **THE TURN IS PRODUCED BY A PRODUCTION CAST.** The page takes the before, the module
## fires, and the readback comes back MEASURED — asserted on values, never on a call
## having happened, because a test that asserts "the method was called" is exactly what
## stays green when the call is deleted.
##
## This is the assertion the mutation check bites on. With `of(...)` removed from
## production, `turn` is `{}` and `turn_measured` is false, so the first two assertions
## below go red.
func test_a_production_cast_reports_a_measured_turn_through_the_screen() -> void:
	var hero := _hero()
	var def := _equipped(hero)
	var loadout := _loadout()
	loadout.setup(hero)
	# THE SEAM IS HELD IN A LOCAL, and that is load-bearing rather than stylistic.
	# `Callable(resolver.new(), "resolve")` binds to a `RefCounted` nothing else
	# references, so it is freed before `activate` runs, the Callable goes invalid, and
	# `_seam_for` falls back to the empty process-wide binding: `activate` returns
	# `ok: true` with `damage: {}` and the turn honestly reads `activity: "none"`. The
	# cast still pays, so the readback still reports qi — which is exactly how a
	# resolver-less turn masquerades as a real one.
	var resolver := _OutcomeResolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))

	# Before any cast there is no turn, and the honest reading is "nothing measured yet"
	# rather than a turn that moved nothing.
	var before: Dictionary = loadout.summary()
	assert_eq(
		(before.get("turn", {}) as Dictionary).is_empty(),
		true,
		"no turn is published before the first cast"
	)
	assert_eq(
		bool(before.get("turn_measured", false)), false, "and nothing claims to have measured one"
	)

	loadout.call(&"bind_target", _foe(&"readback_dummy"))
	var fired: Dictionary = loadout.call(&"act_cast", def.id)
	assert_eq(bool(fired.get("ok", false)), true, "the cast fired through the installed seam")

	var view := loadout.summary()
	var turn: Dictionary = view.get("turn", {}) as Dictionary

	# THE LOAD-BEARING THREE. Each is a fact `CombatOutcome` alone does not carry.
	assert_eq(
		bool(view.get("turn_measured", false)),
		true,
		(
			"MISSING READBACK: the cast produced no measured turn, so `TechniqueCastView.of` "
			+ "is not being called on the production path (DEF-0097)"
		)
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
	# it and computes none of it — a second negation here could disagree with the spine's.
	assert_eq(
		float(view.get("turn_health_lost", 0.0)),
		18.0,
		"and reports the health the foe lost, not a number this screen derived"
	)
	# The qi charge is the fourth fact, and the one `CombatOutcome` does not publish at
	# all — it lives on the ACTIVATION's `paid`, not in the descriptor. `turn_spent` is
	# what says a charge happened without this file restating the module's arithmetic.
	assert_eq(bool(view.get("turn_spent", false)), true, "so the turn also reports the charge")
	assert_eq(
		(turn.get("paid", {}) as Dictionary).get("qi", 0.0) != null,
		true,
		"and the charge the module published, under the pool id it uses"
	)
	# `remaining_health` is the one number no delta answers: it is what tells a fight
	# layer the target died on this cast.
	assert_eq(
		float(view.get("turn_remaining_health", 0.0)) > 0.0,
		true,
		"and the target's remaining health, which no difference of pools can answer"
	)


## The MESSAGE channel is the other half of the same report, and it is the half a player
## actually reads. `"Fired <id>"` for a sea erosion and for a killing blow is the readout
## that hid DEF-0097 in the first place, so the message must SAY the turn.
##
## The measurement halves are separate because they are separate claims: deleting the
## production `of(...)` call drops every one of them at once.
func test_the_cast_message_says_what_the_turn_did_not_only_that_a_verb_ran() -> void:
	var hero := _hero()
	var def := _equipped(hero)
	var loadout := _loadout()
	loadout.setup(hero)
	var resolver := _OutcomeResolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	loadout.call(&"bind_target", _foe(&"readback_dummy2"))
	loadout.call(&"act_cast", def.id)

	var message := String(loadout.summary().get("message", ""))
	assert_eq(
		message.contains(String(def.id)), true, "the message names the technique: %s" % message
	)
	assert_eq(
		message.length() > ("Fired %s" % String(def.id)).length(),
		true,
		"and says what the turn DID rather than only that a verb ran: %s" % message
	)
	# Spelled out so a regression names the fact it lost rather than only a length
	# comparison, so the third assertion names the charge specifically.
	assert_eq(
		message.contains("Landed"),
		true,
		"it states the landing, from the spine's own descriptor: %s" % message
	)
	assert_eq(
		message.contains("spent"),
		true,
		"and it states the charge, which no descriptor carries: %s" % message
	)


## A REFUSED cast reports nothing moved. `activate` pays before it resolves, so the
## refusal has to happen above the pay — and the page's own `no_target` gate is the only
## layer positioned to refuse without spending.
##
## Asserted on STATE (qi, cooldown, rung) rather than on the message, because "it cost
## nothing" is a claim about the world and not about what the page said about it.
func test_a_refused_cast_reports_nothing_moved() -> void:
	var hero := _hero()
	var def := _equipped(hero)
	var loadout := _loadout()
	loadout.setup(hero)
	var resolver := _Resolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))

	var qi_before: float = hero.resource(&"qi").current
	var rung_before: int = int(TechniquesApi.inspect(hero, def.id).get("rung", 0))

	# No `bind_target`: nobody is here. `_refuse_no_target` answers above the pay.
	var refused: Dictionary = loadout.call(&"act_cast", def.id)
	assert_eq(bool(refused.get("ok", false)), false, "the cast did not succeed")
	assert_eq(String(refused.get("reason", "")), "no_target", "for the named reason")
	assert_eq(resolver.calls, 0, "the damage seam was never reached")
	assert_eq(hero.resource(&"qi").current, qi_before, "no qi was spent, so the cast cost nothing")
	assert_eq(
		(hero.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting).is_ready(def.id),
		true,
		"no cooldown was started"
	)
	assert_eq(
		int(TechniquesApi.inspect(hero, def.id).get("rung", 0)),
		rung_before,
		"and no mastery rung was granted"
	)
	# The refusal is a message the player can act on, not a silent false.
	assert_eq(
		String(loadout.summary().get("message", "")),
		"%s: %s" % [String(def.id), L.t(String(TechniqueLoadoutScreen.NO_TARGET_BODY))],
		"the page says, in words, that nothing was fired and nothing was spent"
	)


## The readback is a named type the facade NAMES, so closing the gap grew no facade
## verb. `ui/` decides no damage and the app owns only the aim.
##
## The bare `TechniqueCastView` name would itself be the cross-module edge the arch gate
## refuses, which is why production reaches it through `load()` + the constant, not by
## naming the class.
func test_the_readback_is_reached_through_the_facade_constant_not_a_thirteenth_verb() -> void:
	var published: Array[String] = []
	for method in load("res://src/modules/techniques/api.gd").get_script_method_list():
		var method_name := String(method.get("name", ""))
		if not method_name.begins_with("_") and not published.has(method_name):
			published.append(method_name)
	assert_eq(published.size(), 12, "still exactly twelve, found %d" % published.size())
	for forbidden in [&"cast_view", &"cast_readback", &"snapshot", &"cast_turn"]:
		assert_eq(
			published.has(String(forbidden)),
			false,
			"and no verb named '%s' crept onto the facade" % String(forbidden)
		)
	assert_eq(
		String(TechniquesApi.CAST_VIEW),
		"technique_cast_view",
		"the facade NAMES the readback, which is how the cap is honoured"
	)


## A seam that answers nothing leaves the turn UNMEASURED rather than fabricating
## zeros — the whole of DEF-0097's refusal to look like it did nothing. This is the
## honest-degradation half: with the resolver seam returning a bare `{amount: …}`, the
## readback still runs and still reports `activity: resolved`, but the pool deltas are
## absent, and `turn_measured` stays TRUE because a snapshot WAS taken.
##
## It is asserted separately so a future edit that fabricates `{"qi": 0.0}` rows for an
## unmeasured pool names that edit at this line rather than at the reachability claim.
class _BareResolver:
	extends RefCounted

	func resolve(_attacker: Actor, _target: Actor, _def: TechniqueDef) -> Dictionary:
		return {"amount": 9.0}


func test_a_bare_descriptor_still_reads_back_rather_than_degrading_to_zeros() -> void:
	var hero := _hero()
	var def := _equipped(hero)
	var loadout := _loadout()
	loadout.setup(hero)
	var resolver := _BareResolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	loadout.call(&"bind_target", _foe(&"readback_dummy3"))

	var fired: Dictionary = loadout.call(&"act_cast", def.id)
	assert_eq(bool(fired.get("ok", false)), true, "the cast fired")
	var turn: Dictionary = loadout.summary().get("turn", {}) as Dictionary
	assert_eq(
		bool(loadout.summary().get("turn_measured", false)),
		true,
		"a snapshot WAS taken, so the turn is measured even when the descriptor is bare"
	)
	assert_eq(
		String(turn.get("activity", "")) != "",
		true,
		"and it still names an activity rather than degrading to 'none'"
	)
	assert_eq(float(turn.get("damage", 0.0)), 9.0, "relaying the seam's own `amount` verbatim")


## Counts the resolver's calls, so "the seam was never reached" is a statement about the
## seam rather than an inference from a message.
class _Resolver:
	extends RefCounted

	var calls: int = 0

	func resolve(_attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		calls += 1
		return {"amount": 12.0, "target": String(target.id), "id": String(def.id)}
