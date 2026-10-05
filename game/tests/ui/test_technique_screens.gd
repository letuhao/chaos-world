extends TestCase

## The two technique screens (ADR 0053, DEF-0093): the unbounded read-only codex
## and the limited path-typed loadout. They answer different questions, so these
## tests assert the distinction as much as the contents — the codex publishes no
## action and the loadout's one action is a release, never a loss.
##
## Nothing here asserts pixels or a formatted number out of a screen. The rows
## own every format; the screens carry raw values.

const CODEX_SCENE := "res://src/ui/screens/technique_codex.tscn"
const LOADOUT_SCENE := "res://src/ui/screens/technique_loadout.tscn"
const MORTAL := &"qi_refining"
const SPIRIT := &"spirit_condensation"

var _screen: UiScreen = null


func teardown() -> void:
	# The damage seam is a PROCESS-WIDE binding, and `run_tests.gd` calls `teardown`
	# after every test precisely because one leaks into the next suite otherwise. An
	# empty Callable clears it deterministically.
	TechniqueCasting.set_resolver(Callable())
	# `_mount` already frees the previous screen before installing the next one, so
	# by the time teardown runs `_screen` may be a stale reference to something the
	# runner has collected. Guarding on `is_instance_valid` alone is not enough:
	# `free()` on an already-freed object raises "Nonexistent function in base
	# 'previously freed'". Nulling the field in `_mount` after freeing makes the
	# lifetime unambiguous from either side.
	_screen = null


## Frees whatever `_screen` points at and leaves the field null, so neither
## `_mount` nor `teardown` can double-free.
func _release_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null


func _mount(scene_path: String) -> UiScreen:
	_release_screen()
	var screen: UiScreen = load(scene_path).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_screen = screen
	return screen


func _codex() -> UiScreen:
	return _mount(CODEX_SCENE)


func _loadout() -> UiScreen:
	return _mount(LOADOUT_SCENE)


## A hero on all three paths with the techniques module attached, which is what a
## screen meets at boot: `TechniquesApi.attach` is idempotent, so the screen
## re-attaching changes nothing.
func _actor(realm_id: StringName = MORTAL) -> Actor:
	var actor := Actor.new(&"technique_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 400.0))
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.set_path(PathState.new(PathState.BODY, realm_id))
	actor.set_path(PathState.new(PathState.MIND, realm_id))
	TechniquesApi.attach(actor)
	return actor


## A passive on `path_id`, registered with the catalog the way a `.tres` would be,
## so `inspect` can resolve it by id the way a rendered row needs it to.
##
## The return type is stated because an untyped return leaves `TechniqueDef.new()`
## un-inferrable at every call site, which this project treats as an error.
func _technique(
	technique_id: StringName, path_id: StringName, grade: StringName = ItemGrade.MORTAL
) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = technique_id
	def.display_name = "Manual %s" % String(technique_id)
	def.grade = grade
	def.path = path_id
	def.active = false
	def.mastery_rungs = 4
	TechniqueCatalog.instance().register(def)
	return def


## An active technique on `path_id`, so the cast verb has something to fire. The
## return type is stated because an untyped return leaves `TechniqueDef.new()`
## un-inferrable at every call site, which this project treats as an error.
func _active(technique_id: StringName, qi_cost: float = 0.0, cooldown: float = 0.0) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = technique_id
	def.display_name = "Strike %s" % String(technique_id)
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = PathState.QI
	def.qi_cost = qi_cost
	def.cooldown = cooldown
	def.mastery_rungs = 4
	TechniqueCatalog.instance().register(def)
	return def


## The casting table the facade NAMES, reached exactly as the screen reaches it —
## through `TechniquesApi.CASTING_COMPONENT` and no thirteenth facade method.
func _casting(actor: Actor) -> TechniqueCasting:
	return actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting


## The shape the composition root binds the damage seam to, installed so a cast
## resolves a real descriptor instead of an empty one.
class _Resolver:
	extends RefCounted

	var calls: int = 0

	func resolve(_attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		calls += 1
		return {"amount": 12.0, "target": String(target.id), "id": String(def.id)}


## The same seam answering the shape `CombatOutcome.to_dict()` actually returns, so a
## test asserting `health_delta` is asserting the ENGINE's figure arriving intact rather
## than a number this suite invented.
class _OutcomeResolver:
	extends RefCounted

	var calls: int = 0

	func resolve(_attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		calls += 1
		return {
			"amount": 18.0,
			"health_delta": -18.0,
			"landed": true,
			"crit": false,
			"target": String(target.id),
			"id": String(def.id),
		}


## The mastery rung `inspect` reports for a technique — the read that says whether a
## cast was counted as a use, and so whether a refused one spent anything.
func _mastery_of(actor: Actor, technique_id: StringName) -> int:
	return int(TechniquesApi.inspect(actor, technique_id).get("rung", 0))


## Press the row's real cast button, the way a player does, and report whether the row
## let the press through at all. Going through the BUTTON rather than the signal is
## deliberate: an unguarded signal would pass a press the row's own gate should have
## dropped, which is exactly the dead verb this change removed.
func _press_cast_button(loadout: UiScreen, technique_id: StringName) -> bool:
	for row in _rows_of(loadout):
		var view: Dictionary = row.call(&"summary")
		if String(view.get("technique_id", "")) != String(technique_id):
			continue
		var button := row.get_node_or_null("%CastButton") as Button
		if button == null or not button.visible or button.disabled:
			return false
		button.pressed.emit()
		return true
	return false


## The slot rows the screen is showing, reached through its own `_slot_rows` so a test
## never re-walks the scene tree the screen already owns.
func _rows_of(loadout: UiScreen) -> Array:
	var rows: Array = loadout.get(&"_slot_rows")
	return rows


## The codex entry view for one technique id, or `{}` when the page does not list it.
## Read off `summary()`, which is the screen's own contract, so a test asserts what a
## consumer of the page sees rather than reaching into the screen's fields.
func _entry_for(screen: UiScreen, technique_id: StringName) -> Dictionary:
	for entry in screen.summary()["entries"] as Array:
		var view: Dictionary = entry as Dictionary
		if String(view.get("id", "")) == String(technique_id):
			return view
	return {}


## The row NODE the codex used for one technique, so a label can be asserted on the
## real widget rather than on the row's own summary — a value in `summary()` that no
## label ever shows is published-but-unreachable, which is the defect class here.
func _row_of(screen: UiScreen, technique_id: StringName) -> Control:
	for row in screen.get(&"_rows") as Array:
		if String(row.call(&"entry_id")) == String(technique_id):
			return row as Control
	return null


# --- The empty-summary contract ---------------------------------------------


func test_both_screens_report_an_empty_summary_with_no_actor() -> void:
	assert_eq(_codex().summary(), {}, "the codex reports nothing, not keys")
	assert_eq(_loadout().summary(), {}, "the loadout reports nothing, not keys")


func test_both_screens_report_raw_values_and_nest_their_rows() -> void:
	var actor := _actor()
	var def := _technique(&"qi_seed", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)

	var codex := _codex()
	codex.setup(actor)
	var codex_view := codex.summary()
	for key in ["actor", "read_only", "realm_tier", "codex_count", "entries", "entry_ids"]:
		assert_eq(codex_view.has(key), true, "%s is in the codex summary" % key)
	# Raw, not rendered: the screen carries the module's own counts so a test can
	# assert against the facade rather than against a string.
	assert_eq(
		int(codex_view["codex_count"]), int(TechniquesApi.summary(actor)["codex_count"]), "raw"
	)
	var entries: Array = codex_view["entries"]
	assert_eq(entries.size(), 1, "one learned technique is listed")
	var row: Dictionary = entries[0]
	assert_eq(String(row["id"]), String(def.id), "the row names the technique")
	assert_eq(bool(row["known"]), true, "the row knows it is known")
	assert_eq(int(row["rung"]), 0, "raw rung")
	assert_eq(int(row["rung_count"]), 4, "raw mastery reach")
	assert_ne(String(row["mastery_line"]), "", "the row owns the mastery format")

	var loadout := _loadout()
	loadout.setup(actor)
	var loadout_view := loadout.summary()
	for key in ["actor", "is_loadout", "slot_total", "slot_free", "slots", "filled_slots", "pools"]:
		assert_eq(loadout_view.has(key), true, "%s is in the loadout summary" % key)
	assert_eq(
		int(loadout_view["slot_total"]),
		int(TechniquesApi.summary(actor)["slot_total"]),
		"the budget is the module's, not the screen's"
	)
	var slots: Array = loadout_view["slots"]
	assert_eq(slots.size(), 7, "Mortal publishes seven slots")
	# Matched by POOL rather than by position: `slot_keys` publishes the three path
	# pools in `PathState.ALL` order and the qi technique lands wherever qi sits in
	# that order, so "the first slot" is an accident of the vocabulary rather than a
	# property anything should rely on.
	assert_eq(
		slots.any(func(row: Dictionary) -> bool: return bool(row.get("filled", false))),
		true,
		"exactly one published slot is bound"
	)
	assert_eq(int(loadout_view["equipped_count"]), 1, "and the module agrees on the count")


# --- The two questions stay separate ----------------------------------------


func test_the_codex_is_not_the_loadout() -> void:
	var actor := _actor()
	var def := _technique(&"qi_only", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	var codex := _codex()
	codex.setup(actor)
	var view := codex.summary()
	assert_eq(bool(view["read_only"]), true, "the codex is read-only")
	assert_eq(bool(view["is_loadout"]), false, "and says it is not the loadout")
	# Read-only means no action surface at all: no picker, no equip, no unequip.
	for action in ["equip", "unequip", "learn", "act_equip", "act_unequip", "act_learn"]:
		assert_eq(
			codex.has_method(action),
			false,
			"the codex publishes no '%s'; equipping is the loadout's business" % action
		)
	assert_eq(bool(view["is_loadout"]), false, "the codex never claims the budget")


func test_the_loadout_says_it_is_the_limited_half() -> void:
	var actor := _actor()
	var loadout := _loadout()
	loadout.setup(actor)
	var view := loadout.summary()
	assert_eq(bool(view["is_loadout"]), true, "the loadout says so")
	assert_eq(view.has("read_only"), false, "and is not the read-only half")
	# Every slot the facade publishes is on the page, each with its pool and its
	# occupant — the 7/8/9/10 budget is legible because nothing is collapsed.
	var kinds: Array = []
	for slot in view["slots"]:
		kinds.append(String((slot as Dictionary)["kind"]))
	assert_eq(kinds.size(), 7, "seven rows")
	assert_eq(kinds.count(PathState.QI), 3, "qi holds three")
	assert_eq(kinds.count(PathState.BODY), 2, "body holds two")
	assert_eq(kinds.count(PathState.MIND), 2, "mind holds two")


func test_the_budget_grows_with_the_realm_tier() -> void:
	for tier_case in [[MORTAL, 7], [SPIRIT, 8]]:
		var actor := _actor(tier_case[0])
		var loadout := _loadout()
		loadout.setup(actor)
		var view := loadout.summary()
		assert_eq(int(view["slot_total"]), int(tier_case[1]), "%s budget" % tier_case[0])
		assert_eq((view["slots"] as Array).size(), int(tier_case[1]), "one row per slot")


# --- Releasing a slot never loses the technique -----------------------------


func test_releasing_a_slot_empties_the_slot_and_keeps_the_codex_entry() -> void:
	var actor := _actor()
	var def := _technique(&"qi_held", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id, 3)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)
	assert_eq(int(loadout.summary()["equipped_count"]), 1, "bound to start")

	assert_eq(loadout.call(&"act_unequip", def.id), true, "the release went through")
	var view := loadout.summary()
	assert_eq(int(view["equipped_count"]), 0, "the slot is free again")
	assert_eq((view["filled_slots"] as Array).size(), 0, "no slot is bound")
	assert_eq(String(view["message"]), "Released %s to the codex" % String(def.id), "reported")
	# The load-bearing half of ADR 0053: the technique is still known, with its
	# rung, because releasing a slot is a build choice and never a loss.
	var codex := _codex()
	codex.setup(actor)
	var codex_view := codex.summary()
	assert_eq(int(codex_view["codex_count"]), 1, "the codex still holds it")
	assert_eq(int((codex_view["entries"] as Array)[0]["rung"]), 3, "and its rung survived")


func test_releasing_a_technique_that_is_not_equipped_is_refused_and_reported() -> void:
	var actor := _actor()
	var def := _technique(&"qi_loose", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	var loadout := _loadout()
	loadout.setup(actor)
	assert_eq(loadout.call(&"act_unequip", def.id), false, "nothing to release")
	assert_eq(String(loadout.summary()["tone"]), "error", "the refusal is reported")
	assert_eq(int(loadout.summary()["codex_count"]), 1, "and nothing was touched")


func test_a_filled_slot_offers_a_release_and_an_empty_one_does_not() -> void:
	var actor := _actor()
	var def := _technique(&"qi_one", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)
	var slots: Array = loadout.summary()["slots"]
	var can_release := 0
	for slot in slots:
		if bool((slot as Dictionary)["can_unequip"]):
			can_release += 1
	assert_eq(can_release, 1, "only the bound slot can be released")


# --- Binding a learned technique ---------------------------------------------


func test_a_learned_unbound_technique_is_offered_and_can_be_bound() -> void:
	var actor := _actor()
	var def := _technique(&"qi_to_bind", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	var loadout := _loadout()
	loadout.setup(actor)

	# The picker offers it, and says it can be bound — which is the affordance the
	# codex deliberately does not have (ADR 0053).
	var offers: Array = loadout.summary()["offers"]
	assert_eq(offers.size(), 1, "the learned technique is offered")
	assert_eq(String((offers[0] as Dictionary)["id"]), String(def.id), "and names itself")
	assert_eq(bool((offers[0] as Dictionary)["can_equip"]), true, "and can be bound")
	assert_eq(loadout.call(&"act_equip", def.id), true, "the bind went through the facade")

	var view := loadout.summary()
	assert_eq(int(view["equipped_count"]), 1, "a slot now holds it")
	# The offer survives the bind rather than vanishing from the list: a player needs
	# to see it is ALREADY bound, and the picker says so in its own words.
	assert_eq(bool((view["offers"][0] as Dictionary)["equipped"]), true, "marked bound")
	assert_eq(
		bool((view["offers"][0] as Dictionary)["can_equip"]), false, "and no longer offerable"
	)
	assert_eq(String(view["tone"]), "ok", "the bind is reported")


func test_binding_a_slotless_technique_is_refused_and_reported_honestly() -> void:
	var actor := _actor()
	# Fill every qi slot but the body and mind pools, so one qi technique has nowhere
	# to land: `claimable` returns [] and the facade refuses `no_free_slot`.
	var def := _technique(&"qi_nowhere", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	for index in 3:
		var filler := _technique(StringName("qi_filler_%d" % index), PathState.QI)
		TechniquesApi.codex(actor).learn(filler.id)
		TechniquesApi.equip(actor, filler)
	var loadout := _loadout()
	loadout.setup(actor)

	assert_eq(loadout.call(&"act_equip", def.id), false, "the bind is refused")
	var view := loadout.summary()
	assert_eq(String(view["tone"]), "error", "the refusal is reported")
	# The player is told WHY in words, not left with a bare failure — and the module's
	# own reason is never printed as machine vocabulary at them.
	assert_eq(String(view["message"]), "qi_nowhere: No free slot in its pool", "said why")
	assert_eq(int(view["equipped_count"]), 3, "and nothing else was touched")


func test_the_codex_still_publishes_no_binding_action() -> void:
	# ADR 0053's separation survives the addition of the verb: a BINDING is a slot
	# decision, so it lives on the loadout and the codex stays read-only.
	var codex := _codex()
	for action in ["equip", "act_equip", "unequip", "act_unequip", "cast", "act_cast"]:
		assert_eq(codex.has_method(action), false, "the codex publishes no '%s'" % action)


# --- Firing an active technique ----------------------------------------------


func test_a_bound_active_technique_offers_a_cast_and_fires_through_the_resolver() -> void:
	var actor := _actor()
	var def := _active(&"qi_strike", 40.0, 10.0)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)

	# The slot offers the verb, and reports it ready before anything is spent.
	var slots: Array = loadout.summary()["slots"]
	var firing := 0
	for slot in slots:
		if bool((slot as Dictionary)["can_cast"]):
			firing += 1
	assert_eq(firing, 1, "exactly the active slot can be fired")

	# The composition root's binding is what production uses; install the same shape so
	# the cast resolves a real descriptor instead of an empty one.
	var resolver := _Resolver.new()
	var target := Actor.new(&"training_dummy", {})
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	var qi_before := actor.resource(&"qi").current

	var fired: Dictionary = loadout.call(&"act_cast", def.id, target)
	assert_eq(bool(fired["ok"]), true, "the cast fired")
	assert_eq(resolver.calls, 1, "and resolved through the installed seam")
	assert_eq(bool(fired["resolved"]), true, "with a real descriptor")
	# `activate` pays the qi and starts the cooldown; the screen neither skips the
	# payment nor restates the number.
	assert_ne(actor.resource(&"qi").current, qi_before, "the cast paid what it owed")
	assert_eq(_casting(actor).is_ready(def.id), false, "and started the cooldown")

	var view := loadout.summary()
	assert_eq(String(view["tone"]), "ok", "the cast is reported")
	# And the slot now says so in the row's own words, rather than offering the button
	# as if it were still ready.
	var after: Array = view["slots"]
	var cooling := 0
	for slot in after:
		if String((slot as Dictionary)["ready"]).begins_with("Ready in"):
			cooling += 1
	assert_eq(cooling, 1, "the fired slot now shows a countdown")
	TechniqueCasting.set_resolver(Callable())


func test_casting_a_technique_on_cooldown_is_refused_and_says_why() -> void:
	var actor := _actor()
	var def := _active(&"qi_twice", 0.0, 30.0)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)
	TechniqueCasting.set_resolver(Callable(_Resolver.new(), "resolve"))
	var target := Actor.new(&"training_dummy", {})

	assert_eq(bool((loadout.call(&"act_cast", def.id, target) as Dictionary)["ok"]), true, "first")
	var second: Dictionary = loadout.call(&"act_cast", def.id, target)
	assert_eq(bool(second["ok"]), false, "the second is refused")
	assert_eq(String(second["reason"]), "on_cooldown", "for the module's own reason")
	var view := loadout.summary()
	assert_eq(String(view["message"]), "qi_twice: Still cooling down", "said in words")
	TechniqueCasting.set_resolver(Callable())


func test_casting_a_passive_is_refused_and_says_why() -> void:
	var actor := _actor()
	var def := _technique(&"qi_passive_cast", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)

	# The button is not even offered: a passive is ADR 0054's contribution, not an
	# action, so a row advertising a cast it can only refuse would be a lie.
	var slots: Array = loadout.summary()["slots"]
	for slot in slots:
		if bool((slot as Dictionary)["filled"]):
			assert_eq(bool((slot as Dictionary)["can_cast"]), false, "no cast offered")

	# Calling it anyway is refused honestly rather than crashing or silently succeeding.
	var fired: Dictionary = loadout.call(&"act_cast", def.id)
	assert_eq(bool(fired["ok"]), false, "a passive cannot be fired")
	assert_eq(
		String(loadout.summary()["message"]),
		"qi_passive_cast: That one is a passive, not an action",
		"said why"
	)


func test_the_cast_reached_the_facade_no_further() -> void:
	# The cast had to be reachable without growing the facade, so it is reached the way
	# `TechniqueUpkeep` is: as a component the facade NAMES.
	var published: Array[String] = []
	for method in load("res://src/modules/techniques/api.gd").get_script_method_list():
		var method_name := String(method.get("name", ""))
		if not method_name.begins_with("_") and not published.has(method_name):
			published.append(method_name)
	assert_eq(published.has("cast"), false, "and no per-verb cast verb on the facade")


# --- The target is what makes the cast reach the resolver -------------------
#
# These four tests are the guard for the defect this file exists to close: a technique
# fired from the loadout screen paid its qi, spent its cooldown and hit nothing, because
# `_on_cast` called `act_cast(technique_id)` with NO target and
# `TechniqueCasting._resolve` answers `{}` for a null one. The damage path was real the
# whole time — `_resolve_technique_hit` -> `CombatEngineApi.resolve_hit` -> `to_dict()` —
# it was simply unreachable from the player's action.


## A bound ACTIVE technique on `actor`, the shape a cast is fired from. The actor is
## LAST because it is the context every case here shares, so
## `_equipped_active(&"qi_strike", 40.0, 10.0, actor)` reads left to right as the qi
## cost, the cooldown, and whose hero it is.
func _equipped_active(
	technique_id: StringName, qi: float, cooldown: float, actor: Actor
) -> TechniqueDef:
	var def := _active(technique_id, qi, cooldown)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


func test_a_cast_fired_from_the_row_reaches_the_resolver_with_the_bound_target() -> void:
	# The route a PLAYER takes, not a headless call: the row's cast button is pressed and
	# the screen has to supply the target itself. This is the test the old code failed —
	# `_on_cast` passed nothing, so the resolver was never reached from the button.
	var actor := _actor()
	var def := _equipped_active(&"qi_row_fires", 40.0, 10.0, actor)
	var loadout := _loadout()
	loadout.setup(actor)
	var resolver := _Resolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	loadout.call(&"bind_target", Actor.new(&"training_dummy", {}))

	assert_eq(bool(loadout.summary()["has_target"]), true, "the target is bound")

	# Press the row's button, the way a player does. The row's own guard is on
	# `can_fire`, so it forwards only with a target — and the screen supplies it.
	var pressed := _press_cast_button(loadout, def.id)
	assert_eq(pressed, true, "the bound target made the row's button live")
	assert_eq(resolver.calls, 1, "the press reached the damage seam")
	TechniqueCasting.set_resolver(Callable())


## A cast WITH a target reaches the resolver AND the screen reports what it resolved.
## The outcome is the engine's own `damage` payload — `amount` and `health_delta` are
## numbers the UI never computes, only relays.
func test_a_cast_with_a_target_reaches_the_resolver_and_reports_the_outcome() -> void:
	var actor := _actor()
	var def := _equipped_active(&"qi_reports", 0.0, 0.0, actor)
	var loadout := _loadout()
	loadout.setup(actor)
	var resolver := _OutcomeResolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	loadout.call(&"bind_target", Actor.new(&"training_dummy", {}))

	var fired: Dictionary = loadout.call(&"act_cast", def.id)
	assert_eq(bool(fired["ok"]), true, "the cast fired")
	assert_eq(resolver.calls, 1, "and resolved through the installed seam once")
	assert_eq(bool(fired["resolved"]), true, "so it reports a real descriptor")

	# The descriptor reaches the caller verbatim: these are the engine's figures.
	var damage: Dictionary = fired["damage"]
	assert_eq(float(damage["health_delta"]), -18.0, "the engine's own health delta")
	assert_eq(float(damage["amount"]), 18.0, "and the damage it was worth")
	# And the screen's summary relays it rather than re-deriving it.
	var view := loadout.summary()
	assert_eq(float(view["last_health_delta"]), -18.0, "the screen reports that outcome")
	assert_eq(String(view["last_target"]), "training_dummy", "against the named target")
	TechniqueCasting.set_resolver(Callable())


## THE DEFECT, as a test. A cast with NO target is refused with a named reason naming the
## missing thing, and it costs NOTHING — no qi spent, no cooldown started, no mastery
## rung. Before the fix this succeeded, paid and resolved `{}`.
func test_a_cast_with_no_target_is_refused_by_name_and_costs_nothing() -> void:
	var actor := _actor()
	var def := _equipped_active(&"qi_untargeted", 40.0, 10.0, actor)
	var loadout := _loadout()
	loadout.setup(actor)
	var resolver := _Resolver.new()
	TechniqueCasting.set_resolver(Callable(resolver, "resolve"))
	# No `bind_target`: nobody is here. The qi and the rung-0 mastery are both read
	# BEFORE, so "nothing was spent" is an assertion about state and not about a message.
	var qi_before: float = actor.resource(&"qi").current
	var rung_before: int = _mastery_of(actor, def.id)

	var refused: Dictionary = loadout.call(&"act_cast", def.id)

	assert_eq(bool(refused["ok"]), false, "the cast did not succeed")
	assert_eq(String(refused["reason"]), "no_target", "for a named reason")
	assert_eq(bool(refused["fired"]), false, "and says nothing was fired")
	assert_eq(bool(refused["resolved"]), false, "and nothing was hit")
	# The refusal NAMES the missing thing in the player's own words, not a bare false.
	assert_eq(
		String(loadout.summary()["message"]),
		"qi_untargeted: Nothing to aim at, so nothing was fired and nothing was spent.",
		"said in words a player can act on"
	)
	# And it is free. This is the part the old code got wrong: `activate` paid here.
	assert_eq(actor.resource(&"qi").current, qi_before, "no qi was spent")
	assert_eq(_casting(actor).is_ready(def.id), true, "no cooldown was started")
	assert_eq(_mastery_of(actor, def.id), rung_before, "and no rung was granted")
	assert_eq(resolver.calls, 0, "the damage seam was never even reached")
	TechniqueCasting.set_resolver(Callable())


## `summary()` publishes the target, so the whole thing is assertable on a contract
## rather than on pixels: with one bound and with none, the two states are told apart
## without reading a single label.
func test_the_summary_publishes_the_target_so_the_affordance_is_assertable() -> void:
	var actor := _actor()
	var def := _equipped_active(&"qi_affordance", 0.0, 0.0, actor)
	var loadout := _loadout()
	loadout.setup(actor)

	var bare: Dictionary = loadout.summary()
	assert_eq(bool(bare["has_target"]), false, "nobody is here yet")
	assert_eq(String(bare["target_id"]), "", "and no id is published")

	# A targetless castable row says so instead of advertising a press that can only be
	# refused, and `can_cast` still reports the technique's OWN business.
	for slot in bare["slots"]:
		var view := slot as Dictionary
		if bool(view["can_cast"]):
			assert_eq(bool(view["has_target"]), false, "the row knows it has nowhere to aim")
			assert_eq(bool(view["can_fire"]), false, "so it cannot be thrown")
			assert_eq(String(view["ready"]), "No target", "and says so in its own words")

	loadout.call(&"bind_target", Actor.new(&"training_dummy", {}))
	var aimed: Dictionary = loadout.summary()
	assert_eq(bool(aimed["has_target"]), true, "now there is somewhere to aim")
	assert_eq(String(aimed["target_id"]), "training_dummy", "and it is published by id")
	assert_eq(bool(aimed["can_fire"]), true, "so a ready technique can be thrown")
	for slot in aimed["slots"]:
		var view := slot as Dictionary
		if bool(view["can_cast"]):
			assert_eq(bool(view["can_fire"]), true, "the row's button is live")
			assert_eq(String(view["ready"]), "Ready", "and reads as ready, not aimless")

	# Unbinding is a decision a caller can make, not only a state to be born into.
	loadout.call(&"bind_target")
	assert_eq(bool(loadout.summary()["has_target"]), false, "and it can be taken away again")


## The module's own refusals are NOT swallowed by the target gate. A passive is refused
## as `not_active` in the module's words, because `activate` refuses it for free — where
## a `no_target` answer would have replaced a precise, fixable refusal with an
## irrelevant one about the room.
func test_a_passive_still_gets_the_module_s_own_refusal_not_no_target() -> void:
	var actor := _actor()
	var def := _technique(&"qi_passive_untargeted", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)

	var refused: Dictionary = loadout.call(&"act_cast", def.id)
	assert_eq(bool(refused["ok"]), false, "a passive cannot be fired")
	assert_eq(
		String(loadout.summary()["message"]),
		"qi_passive_untargeted: That one is a passive, not an action",
		"said why, in the module's own words"
	)


## The target seam is untouched by the facade: the target is an argument on a SCREEN
## method, so a screen adding one needs no verb from `TechniquesApi` at all. ADR 0265
## deleted the width cap that used to make "still exactly twelve" the claim here.
func test_binding_a_target_added_no_facade_method() -> void:
	var published: Array[String] = []
	for method in load("res://src/modules/techniques/api.gd").get_script_method_list():
		var method_name := String(method.get("name", ""))
		if not method_name.begins_with("_") and not published.has(method_name):
			published.append(method_name)
	assert_eq(
		published.size() > 0,
		true,
		"the facade really publishes something, so the count read nothing"
	)


# --- The codex shows the range a copy may read (DEF-0302) ----------------------
#
# `band_for` was WIRED (draw rolled it) and UNPUBLISHED: no surface told a hero that
# the sheet saying 6.0 might arrive as 4.5. These drive the real screen and assert the
# rendered VALUE, and every expected number is read from `band_for` — the one
# declaration of the width — so a test cannot drift from the roll it is guarding.


## The codex row publishes the two edges AND the range in the sheet's own figures,
## and they are `TechniqueMarginalia.band_for`'s edges. A row that published a band
## of its own would be a second reader of ADR 0196's rule, in `ui/`.
func test_the_codex_publishes_the_band_band_for_declares() -> void:
	var actor := _actor()
	var def := _technique(&"qi_band", PathState.QI)
	# A band needs something to band. `_technique` authors no inscribed options, and
	# a manual with nothing to vary is correctly reported UNBANDED (`1.0 .. 1.0`) —
	# so without an option on the fixture this case asserted a sentinel and passed
	# for the wrong reason, which is the same inertness it was written to catch.
	def.rarity = ItemRarity.LEGENDARY
	def.passive_options = [{"option_id": &"cult_qi_control", "value": 6.0}]
	TechniquesApi.codex(actor).learn(def.id)
	var codex := _codex()
	codex.setup(actor)

	var declared := TechniqueMarginalia.band_for(def.rarity)
	var row: Dictionary = _entry_for(codex, def.id)
	# Read the row's OWN published `marginal_band`. The defect this case now guards
	# was inside `band_view()` itself: it read a `marginal_band` key out of the
	# MODULE's view — which the module never wrote — so it returned its `1.0 .. 1.0`
	# default for every row and the surface was inert while the assertion passed
	# against the sentinel. Reading the row's published value is what makes the
	# wiring part of the claim rather than a coincidence.
	assert_eq(bool(row.get("marginal_banded", false)), true, "and the row says the band bites")
	# `marginal_span` is the MULTIPLIER window `band_for` declares; `marginal_band`
	# beside it is the PRICE window on this manual's own values (4.5 and 7.5 on a
	# 6.0 sheet). Comparing the price window against 0.75/1.25 is what made this
	# case look like a broken surface when the numbers under the right key were
	# correct all along.
	var span: Dictionary = row.get("marginal_span", {})
	assert_almost_eq(
		float(span.get("floor", -1.0)),
		float(declared.x),
		"the row publishes band_for's floor",
		0.000001
	)
	assert_almost_eq(
		float(span.get("ceiling", -1.0)), float(declared.y), "and band_for's ceiling", 0.000001
	)
	# ## Why the WIDTH is re-derived here rather than read from `band_for` again
	#
	# `declared` above and the value under test both come from `band_for`, so on
	# their own they agree even if `band_for` is wrong — a `band_for` hard-wired to
	# the identity `1.0 .. 1.0` left this whole case GREEN while the surface it
	# guards reported "a copy may read exactly the sheet", which is the one thing
	# the publication exists to contradict. Asserting the span against `declared`
	# also cannot distinguish "no band" from "the right band".
	#
	# So the edges are re-derived from the two published CONSTANTS — the rarity's
	# reach and `BAND_REACH` — which are inputs rather than the rule being tested.
	# `reach * BAND_REACH` is the half-width ADR 0204's rule is, and these two
	# numbers can only both hold if the row really published the declared window.
	var reach := clampf(ItemRarity.magnitude_budget(def.rarity), 0.0, 1.0)
	var half_width := reach * TechniqueMarginalia.BAND_REACH
	assert_almost_eq(
		float(span.get("floor", -1.0)),
		1.0 - half_width,
		"the floor is the declared half-width below the sheet",
		0.000001
	)
	assert_almost_eq(
		float(span.get("ceiling", -1.0)),
		1.0 + half_width,
		"and the ceiling the same half-width above it",
		0.000001
	)
	# And the window is WIDE: an identity span would satisfy nothing above, because
	# every expected figure would have collapsed onto 1.0.
	assert_eq(half_width > 0.0, true, "a legendary manual's band is not the identity")
	assert_eq(float(span.get("ceiling", 0.0)) > float(span.get("floor", 0.0)), true, "two-sided")
	# And the price window is a real, separate figure in the sheet's own units.
	var price: Dictionary = row.get("marginal_band", {})
	assert_almost_eq(
		float(price.get("floor", -1.0)), 4.5, "and the price window below the sheet", 0.000001
	)
	assert_almost_eq(float(price.get("ceiling", -1.0)), 7.5, "and above it", 0.000001)


## The authored column and the range a copy may read sit on the SAME row, and the
## row quotes the module's own figures. This is the promise ADR 0204 made — "this
## sheet says 6.0; a copy may read 4.5-7.5" — so the assertion is that the rendered
## line contains BOTH the sheet's figure and the range's, and reaches a label.
##
## A fixture manual with no inscribed options has nothing to band, so the option is
## authored here: an option the catalog knows, on a passive, at a known value.
func test_the_row_prints_the_sheet_beside_the_range_a_copy_may_read() -> void:
	var actor := _actor()
	var def := _technique(&"qi_sheet", PathState.QI)
	def.rarity = ItemRarity.LEGENDARY
	def.passive_options = [{"option_id": &"cult_qi_control", "value": 6.0}]
	TechniquesApi.codex(actor).learn(def.id)
	var codex := _codex()
	codex.setup(actor)

	var declared := TechniqueMarginalia.band_for(def.rarity)
	var row: Dictionary = _entry_for(codex, def.id)
	assert_eq(bool(row.get("marginal_banded", false)), true, "this row carries variance")

	# The module's own figures, one per bandable option, in the sheet's units.
	var figures: Array = row.get("marginal_band_figures", [])
	assert_eq(figures.size(), 1, "the range names the option it may move")
	var figure: Dictionary = figures[0]
	assert_almost_eq(float(figure["authored"]), 6.0, "against the authored sheet", 0.0001)
	assert_almost_eq(
		float(figure["floor"]), 6.0 * float(declared.x), "the low end is the band applied", 0.0001
	)
	assert_almost_eq(
		float(figure["ceiling"]), 6.0 * float(declared.y), "and the high end likewise", 0.0001
	)

	# Rendered: the sheet's figure and the range are BOTH in the line, and the line
	# is on a label — because a value in `summary()` that no label shows is the
	# published-but-unreachable defect this test exists to close.
	var line := String(row.get("band_line", ""))
	assert_ne(line, "", "the row owns a margin line")
	assert_ne(line.find("6.00"), -1, "which quotes the authored sheet")
	assert_ne(line.find("%.2f" % float(figure["floor"])), -1, "and the low end a copy may read")
	assert_ne(line.find("%.2f" % float(figure["ceiling"])), -1, "and the high end")
	var label := _row_of(codex, def.id).get_node_or_null("%BandLabel") as Label
	assert_ne(label, null, "the row has a band label")
	assert_eq(label.text, line, "and the label shows what summary publishes")


## A row whose range cannot bite prints NOTHING rather than "1.00x - 1.00x". The
## three such rows are a COMMON manual, an ACTIVE one (no options to vary) and a
## capacity-only one (ADR 0160's refusal). A common manual is the interesting case:
## its rarity band is legitimately `1.0 .. 1.0`, and printing it would promise a
## precision nobody authored.
func test_a_row_that_cannot_vary_prints_no_band_at_all() -> void:
	var actor := _actor()
	var def := _technique(&"qi_common_band", PathState.QI)
	def.rarity = ItemRarity.COMMON
	def.passive_options = [{"option_id": &"cult_qi_control", "value": 6.0}]
	TechniquesApi.codex(actor).learn(def.id)
	var codex := _codex()
	codex.setup(actor)

	var row: Dictionary = _entry_for(codex, def.id)
	assert_eq(bool(row.get("marginal_banded", false)), false, "a common copy cannot vary")
	assert_eq(String(row.get("band_line", "")), "", "so the row says nothing about a band")
	var label := _row_of(codex, def.id).get_node_or_null("%BandLabel") as Label
	assert_eq(label.text, "", "and the label is cleared rather than showing 1.00x")


# --- The ScreenStack contract -----------------------------------------------


func test_both_screens_implement_the_screen_stack_hooks() -> void:
	var actor := _actor()
	var def := _technique(&"qi_hook", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	# One screen at a time. `_mount` frees whatever was mounted before it, so
	# building both inside the `for` header handed the loop the codex it had already
	# freed — "Nonexistent function in base 'previously freed'" at the first call.
	for scene_path in [CODEX_SCENE, LOADOUT_SCENE]:
		var screen := _mount(scene_path)
		screen.setup(actor)
		screen.call(&"on_screen_shown")
		assert_ne(screen.summary().is_empty(), true, "showing repaints it")
		screen.call(&"on_screen_hidden")
		assert_ne(screen.summary().is_empty(), true, "hiding keeps it readable")
		assert_eq(
			screen.call(&"on_stack_input", InputEventKey.new()),
			false,
			"the screen consumes nothing, so ui_cancel still pops"
		)
		screen.call(&"focus_initial")
		assert_ne(String(screen.summary()["focus_target"]), "", "focus lands on something real")
