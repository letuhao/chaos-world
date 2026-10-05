extends TestCase

## DEF-0304: a passive is MASTERED, and the input is being worn (ADR 0247).
##
## ## The gap this file closes
##
## `TechniqueCasting._grant_mastery` is reached only from `activate`, and `activate`
## refuses a passive with `not_active` — so no player could ever move a passive past
## rung 0, while `TechniqueReadModel.ladder_view` published every one of them a
## five-rung ladder. `test_technique_passive_mastery.gd` proves what a rung DOES to
## a passive; this file proves there is a way to GET one.
##
## ## Why "worn", with the measurement that chose it
##
## The input is `settle_upkeep`, whose production caller is `StatusLoop.tick`
## (`app/status_loop.gd:188`, driven from `item_workbench_app.gd:570`) — a clock the
## composition root already owns and already hands this module a delta for. Two
## rivals were refused against the SHIPPED corpus, not against taste:
##
## - **Re-studying the manual.** The verb is live (`ItemUse` →
##   `TechniqueDelivery.study` → `TechniquesApi.learn`) and already monotonic, but
##   all eighteen authored passive manuals declare exactly ONE route and
##   `test_no_two_defs_claim_the_same_manual` pins the mapping one-to-one. Fifteen of
##   eighteen name a single `domain:`/`boss:`, so it closes DEF-0304 for three
##   techniques and leaves fifteen open — the DEF-0203 shape.
## - **Paying upkeep as the SOURCE.** `settle` used to skip a def with no bill, and
##   most authored passives declare none, so gating a rung on a bill most of them do
##   not carry leaves most of them unreachable.
##
## So upkeep is the gate that WITHHOLDS a rung, and wear is what earns it. See
## `docs/adr/0247-a-passive-is-mastered-by-wearing-it-and-paying-its-upkeep-is-the-gate.md`.

const MORTAL := &"qi_refining"

## `cult_qi_control` targets a STAT, which is the channel a rung scales (ADR 0160).
const STAT_OPTION := &"cult_qi_control"
const STAT_VALUE := 4.0

## A passive carrying NO upkeep: fifteen of the eighteen authored passives declare no
## bill, and that is exactly the case the old `def.upkeep.is_empty()` test skipped.
const CAPACITY_OPTION := &"core_max_qi"
const CAPACITY_VALUE := 25.0

## Long enough that the frame-delta cases stay readable, and short enough that a
## `settle_upkeep` with no delta (which charges immediately) is unambiguous.
const INTERVAL := 60.0


func _hero(qi: float = 500.0) -> Actor:
	var actor := Actor.new(&"adept", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", qi))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	actor.path(PathState.QI).progress = 100000.0
	TechniquesApi.attach(actor)
	return actor


func _passive(upkeep: Dictionary = {}, interval: float = INTERVAL) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"test_worn_mastery_%d" % (upkeep.size() * 100 + int(interval))
	def.display_name = "Mastery Manual"
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	def.upkeep = upkeep
	def.upkeep_interval = interval
	def.passive_options = [
		{"option_id": STAT_OPTION, "value": STAT_VALUE},
		{"option_id": CAPACITY_OPTION, "value": CAPACITY_VALUE},
	]
	TechniqueCatalog.instance().register(def)
	return def


## A learned, equipped passive, ready to be worn. Three facts in one so no case can
## reach a rung without having passed through learn and equip first.
func _worn_passive(actor: Actor, upkeep: Dictionary = {}) -> TechniqueDef:
	var def := _passive(upkeep)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


func _rung(actor: Actor, technique_id: StringName) -> int:
	return int(TechniquesApi.codex(actor).row(technique_id).get("rung", 0))


func _qi_control(actor: Actor) -> float:
	return actor.stats.derived(&"qi_control")


func _power(rung: int, def: TechniqueDef) -> float:
	return float(TechniqueScales.multipliers_at(rung, def.mastery_rungs)["power"])


# --- THE assertion: a passive's rung exceeds 0 ----------------------------------


## The facade's published methods, read from its own script.
##
## `TechniquesApi.new()` is the wrong door: every method on it is `static`, so
## instantiating yields a bare `RefCounted` whose script is NOT the api, and
## `get_script_method_list()` then returns nothing — every cap assertion below
## failed on an EMPTY list rather than on a count. Read the class's own script.
func _published_methods() -> Array[String]:
	var script: Script = load("res://src/modules/techniques/api.gd")
	var out: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method.get("name", ""))
		if method_name.begins_with("_") or out.has(method_name):
			continue
		out.append(method_name)
	return out


func test_wearing_a_passive_raises_its_rung_past_zero() -> void:
	var actor := _hero()
	var def := _worn_passive(actor)
	assert_eq(_rung(actor, def.id), 0, "a fresh passive sits at rung 0")
	assert_eq(def.upkeep.is_empty(), true, "and this one authors no upkeep at all")

	# THE case DEF-0304 is closed by. One settled interval, through the facade method
	# production already calls per frame, and the rung is above zero.
	var changed := TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id) > 0, true, "a passive's rung exceeds 0 after being worn")
	assert_eq(changed.has(def.id), true, "and the caller is told the state moved")


## The feature end to end: an input no caller held, reaching the multiplier ADR 0160
## already proved, observed on the ACTOR where a player would see it.
func test_the_rung_a_passive_earns_by_being_worn_scales_its_stat_channel() -> void:
	var actor := _hero()
	var def := _worn_passive(actor)
	assert_almost_eq(_qi_control(actor), STAT_VALUE, "rung 0 is the authored value", 0.0001)

	TechniquesApi.settle_upkeep(actor)

	assert_almost_eq(
		_qi_control(actor),
		STAT_VALUE * _power(1, def),
		"rung 1 contributes ADR 0055's power on the authored value",
		0.001
	)


## ADR 0160's refusal, re-asserted on a rung earned by the NEW path: the capacity
## channel stays exactly put while the stat channel moves, in the same rebuild, from
## the same input. The multiplier is read from the ladder rather than restated, so a
## retune of `POWER_STEP` cannot pass by moving both sides.
func test_the_capacity_channel_is_still_refused_for_a_rung_earned_by_wearing() -> void:
	var actor := _hero()
	var def := _worn_passive(actor)
	var at_rung_zero := actor.stats.derived(Stat.MAX_QI)

	for _period in 5:
		TechniquesApi.settle_upkeep(actor)

	# The top is `def.mastery_rungs`, not 4: `TechniqueScales.rung_for` clamps to
	# `min(rung_count, MAX_RUNGS)`, so a def authored with five rungs has rung 0
	# THROUGH 5 — six positions. Hard-coding 4 here would encode the off-by-one this
	# case exists to catch, so both figures are read from the def and the ladder.
	assert_eq(_rung(actor, def.id), def.mastery_rungs, "the ladder was climbed to its end")
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI),
		at_rung_zero,
		"wearing it to the top leaves capacity exactly where rung 0 left it",
		0.0001
	)
	assert_almost_eq(
		_qi_control(actor),
		STAT_VALUE * _power(def.mastery_rungs, def),
		"while the stat channel moved by the full ladder",
		0.001
	)


# --- Monotone, and at most one rung per period -----------------------------------


## A rung never moves backwards. `TechniqueCodex.set_rung` refuses any rung that is
## not strictly greater, so this is a property of the WRITE rather than of any
## caller's arithmetic — which is exactly why it is asserted and not reasoned about.
func test_a_lower_rung_never_replaces_a_higher_one() -> void:
	var actor := _hero()
	var def := _worn_passive(actor)
	for _period in 3:
		TechniquesApi.settle_upkeep(actor)
	var reached := _rung(actor, def.id)
	assert_eq(reached, 3, "three settled intervals is three rungs")

	assert_eq(
		bool(TechniquesApi.raise_mastery(actor, def.id, 0).get("ok")),
		false,
		"the facade refuses a downgrade"
	)
	assert_eq(
		bool(TechniquesApi.raise_mastery(actor, def.id, reached - 1).get("ok")),
		false,
		"and a rung one below"
	)
	TechniquesApi.codex(actor).learn(def.id, 0)
	assert_eq(_rung(actor, def.id), reached, "a re-study at rung 0 cannot lower it either")

	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), reached + 1, "the next period climbs one, not resets")


## One period grants AT MOST one rung. Both over-grant shapes are refused here: a
## delta spanning many intervals (which would make the rate a function of frame rate)
## and a period that hands every rung it can (which the ladder would then clamp).
func test_one_settled_period_grants_at_most_one_rung() -> void:
	var actor := _hero()
	var def := _worn_passive(actor)

	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 1, "one immediate settle is one rung")

	# The production shape: `advance` turns a delta into at most ONE settle no matter
	# how many intervals it spans, so ten intervals is not ten rungs.
	var span := _hero()
	var waited := _worn_passive(span)
	TechniquesApi.settle_upkeep(span, 600.0)
	assert_eq(_rung(span, waited.id), 1, "ten intervals of delta settle once, so one rung")

	# Five periods reach rung 4 and the ladder refuses a fifth, so a period able to
	# over-grant would show here rather than hiding behind the clamp.
	var deepest := _hero()
	var deep_def := _worn_passive(deepest)
	var highest := 0
	for _period in 5:
		TechniquesApi.settle_upkeep(deepest)
		highest = maxi(highest, _rung(deepest, deep_def.id))
	# The ladder is rung 0 THROUGH `mastery_rungs`, so its TOP is `mastery_rungs`
	# — `TechniqueScales.rung_for` clamps to `min(rung_count, MAX_RUNGS)`, and a def
	# authored with `mastery_rungs = 5` has six positions, not five. This case
	# expected 4, which reads "five positions numbered 0..4" — a different ladder,
	# the one an off-by-one would produce. Asserting the ceiling the clamp actually
	# implements is what makes this case catch an off-by-one instead of encoding one.
	assert_eq(highest, deep_def.mastery_rungs, "five periods reach the authored top")


## The cadence is the AUTHORED interval, on the caller's delta. This is the
## production path end to end, and it is what proves the rung rides the game's clock
## rather than a test's willing `settle` call.
func test_the_rung_follows_the_authored_interval_through_a_frame_delta() -> void:
	var actor := _hero()
	var def := _worn_passive(actor, {})

	# A second of frames is not yet an interval, so nothing has been worn.
	for _frame in 60:
		TechniquesApi.settle_upkeep(actor, 1.0 / 60.0)
	assert_eq(_rung(actor, def.id), 0, "one second of frames is not one interval")

	for _frame in 60 * 59:
		TechniquesApi.settle_upkeep(actor, 1.0 / 60.0)
	assert_eq(_rung(actor, def.id), 1, "and at sixty seconds one rung has been earned")


## An UNEQUIPPED passive earns nothing, and a re-equip starts the wear over: the
## settle loop is handed the equipped set, so this is a measure of wearing rather
## than of owning.
func test_an_unequipped_passive_is_never_visited() -> void:
	var actor := _hero()
	var def := _worn_passive(actor)
	TechniquesApi.settle_upkeep(actor)
	var banked := _rung(actor, def.id)
	assert_eq(banked, 1, "one rung banked while worn")

	TechniquesApi.unequip(actor, def)
	for _period in 5:
		TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), banked, "an unequipped passive climbs nothing")


# --- The gate: upkeep withholds what wear earns ----------------------------------


## Suspension is the gate. A passive owing a bill it cannot pay contributes nothing
## (ADR 0054) and must therefore deepen nothing — a rung earned while suspended
## would be mastery paid for a contribution the actor is not receiving.
func test_a_suspended_passive_earns_no_rung_while_it_is_paying_nothing() -> void:
	var actor := _hero(4.0)
	var def := _worn_passive(actor, {&"qi": 50.0})

	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 0, "the interval it stopped paying for, it did not learn from")
	assert_eq(
		(TechniquesApi.summary(actor)["suspended"] as Array).has(String(def.id)),
		true,
		"and it is suspended"
	)

	for _period in 3:
		TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 0, "three more unpaid periods teach nothing")


## The banked-rung rule, stated as a case: a rung is earned for an interval that
## was actually PAID. The interval that stops paying is the penalty, and it teaches
## nothing — mastery paid for a contribution the actor never received is the one
## answer this feature must not give.
func test_the_interval_a_passive_stops_paying_for_is_the_penalty_and_teaches_nothing() -> void:
	var actor := _hero(60.0)
	var def := _worn_passive(actor, {&"qi": 50.0})

	# First interval: paid in full, so it is both charged AND a rung.
	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 1, "the interval it paid for banked its rung")
	assert_almost_eq(actor.resource(&"qi").current, 10.0, "and the bill was charged")

	# Second: 10 qi cannot meet 50, so it neither pays nor climbs.
	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 1, "the interval it could not pay for taught nothing")
	assert_eq(
		(TechniquesApi.summary(actor)["suspended"] as Array).has(String(def.id)),
		true,
		"and the passive is suspended"
	)


## A passive suspended from its FIRST interval never banks a rung at all — the case
## that pins the pay-before-earn order. Charging the bill and granting the rung in
## the other order would hand rung 1 to a technique that had contributed exactly
## nothing.
func test_a_passive_that_cannot_pay_on_its_first_interval_never_banks_a_rung() -> void:
	var actor := _hero(4.0)
	var def := _worn_passive(actor, {&"qi": 50.0})

	for _period in 5:
		TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 0, "five unaffordable intervals, no rung")
	assert_eq(
		TechniqueEffects.applied_count(actor, def.id),
		0,
		"and it was contributing nothing the whole time"
	)


## A revived passive wears its way up again rather than cashing in the suspended
## gap. The interval that revives it is the interval it resumes paying for, and the
## one it resumes earning on is the next.
func test_a_revived_passive_earns_again_only_while_it_is_paying_again() -> void:
	var actor := _hero(60.0)
	var def := _worn_passive(actor, {&"qi": 50.0})
	TechniquesApi.settle_upkeep(actor)
	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 1, "suspended after paying for one interval")

	# Top the pool back up. Its maximum has to be raised first or the top-up clamps
	# away and the revival cannot happen at all.
	var pool := actor.resource(&"qi")
	pool.maximum = 500.0
	pool.current = 500.0

	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 1, "the reviving interval pays but does not back-pay the gap")

	TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 2, "and the next one it pays for earns a rung")


## A passive WITH a bill both pays it and climbs on the same interval — the case
## that proves `settle` still charges while it grants, rather than trading one for
## the other.
func test_a_billed_passive_pays_and_climbs_on_the_same_interval() -> void:
	var actor := _hero(500.0)
	var def := _worn_passive(actor, {&"stamina": 6.0})
	var before := actor.resource(&"stamina").current

	var changed := TechniquesApi.settle_upkeep(actor)
	assert_almost_eq(
		actor.resource(&"stamina").current, before - 6.0, "the bill is charged exactly once"
	)
	assert_eq(_rung(actor, def.id), 1, "and the interval it paid for also moved the rung")
	assert_eq(changed.size(), 1, "reported once, however many things moved")


# --- The active path is untouched ------------------------------------------------


func _active(billed: bool = false) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"test_worn_mastery_active_%s" % ("billed" if billed else "free")
	def.display_name = "Strike Manual"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = PathState.QI
	def.qi_cost = 10.0
	def.upkeep_interval = INTERVAL
	if billed:
		def.upkeep = {&"stamina": 4.0}
	TechniqueCatalog.instance().register(def)
	return def


func _casting(actor: Actor) -> TechniqueCasting:
	return actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting


## THE regression guard for the whole change: `settle` used to skip any def with no
## upkeep, and an active has none, so an active's rung must still move only from
## `activate` and never from a settled period.
func test_an_active_technique_still_climbs_only_by_being_fired() -> void:
	var actor := _hero()
	var def := _active()
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)

	for _period in 3:
		TechniquesApi.settle_upkeep(actor)
	assert_eq(_rung(actor, def.id), 0, "settling never climbs an active with no bill")

	var casting := _casting(actor)
	for _fire in 3:
		casting.tick(actor, 100.0)
		var fired := casting.activate(actor, def)
		assert_eq(
			bool(fired.get("ok")), true, "the active fires: %s" % String(fired.get("reason", ""))
		)
	assert_eq(_rung(actor, def.id), 3, "and three fires are three rungs, exactly as before")


## The visit predicate widened to PASSIVES; it must not have widened to actives. An
## active WITH a bill is still visited — for its bill, which is the behaviour that
## predates this change — and still earns nothing there.
func test_an_active_with_an_upkeep_is_charged_but_still_earns_no_rung() -> void:
	var actor := _hero()
	var def := _active(true)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var before := actor.resource(&"stamina").current

	TechniquesApi.settle_upkeep(actor)
	assert_almost_eq(actor.resource(&"stamina").current, before - 4.0, "the bill is still charged")
	assert_eq(_rung(actor, def.id), 0, "and the ladder is still casting's to climb")


# --- The ladder now says how it is climbed ---------------------------------------


## The player-visible half of DEF-0304: `mastery_ladder` rendered five rungs of a
## passive with no verb behind any of them. `mastery_by` closes that, and the two
## arms must NOT be the same string — a codex that told a passive it was climbed by
## casting would be exactly the unreachable feature this ADR removed.
func test_the_published_ladder_names_the_verb_that_climbs_it() -> void:
	var actor := _hero()
	var passive := _worn_passive(actor)
	var active := _active()
	TechniquesApi.codex(actor).learn(active.id)

	var passive_by := String(TechniquesApi.inspect(actor, passive).get("mastery_by", ""))
	var active_by := String(TechniquesApi.inspect(actor, active).get("mastery_by", ""))
	assert_eq(passive_by, String(TechniqueUpkeep.MASTERY_BY), "a passive's ladder is worn")
	assert_eq(active_by, String(TechniqueCasting.MASTERY_BY), "an active's is fired")
	assert_ne(passive_by, active_by, "and the two are different verbs, so neither screen lies")


## The facade did not grow a thirteenth verb to carry any of this. Both the input and
## the write go through methods that already existed and production already reaches,
## so ADR 0204's facade-constant census has nothing new to find here.
func test_the_facade_publishes_the_upkeep_and_mastery_verbs() -> void:
	var published := _published_methods()
	for name in ["settle_upkeep", "raise_mastery"]:
		assert_eq(published.has(name), true, "'%s' is the verb that carried it" % name)


# --- The measurement that chose this input, kept honest ---------------------------


## ADR 0247 refused upkeep as the SOURCE because most authored passives declare no
## bill. Asserted over the SHIPPED catalog so the refusal stays honest: were upkeep
## to become universal, paying it would be the cheaper input and this decision should
## be revisited rather than quietly inherited.
func test_the_corpus_still_refuses_upkeep_as_the_only_source() -> void:
	var catalog := TechniqueCatalog.instance()
	var passives := 0
	var billed := 0
	var unbilled := 0
	for technique_id in catalog.technique_ids():
		var def := catalog.definition(technique_id)
		if def == null or not def.is_passive():
			continue
		passives += 1
		if def.upkeep.is_empty():
			unbilled += 1
		else:
			billed += 1
	assert_eq(passives > 0, true, "the catalog carries authored passives")
	assert_eq(
		unbilled > billed,
		true,
		"most authored passives author no upkeep (%d unbilled, %d billed)" % [unbilled, billed]
	)


## And every one of them declares at least the rung this input grants, so no authored
## passive is left on a ladder the new rule cannot climb.
func test_every_authored_passive_declares_a_ladder_this_input_can_climb() -> void:
	var catalog := TechniqueCatalog.instance()
	var passive := 0
	var climbable := 0
	for technique_id in catalog.technique_ids():
		var def := catalog.definition(technique_id)
		if def == null or not def.is_passive():
			continue
		passive += 1
		if def.mastery_rungs > 0:
			climbable += 1
	assert_eq(passive > 0, true, "the catalog carries authored passives")
	assert_eq(climbable, passive, "and every one authors at least one rung")
