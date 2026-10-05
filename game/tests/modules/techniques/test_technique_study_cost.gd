extends TestCase

## DEF-0206: learning is NOT free. `TechniquesApi.learn` charges ADR 0055's
## published study price out of the technique's own path's `PathState.progress`,
## all-or-nothing, and a refused learn writes nothing.
##
## ## What is charged and why it is that
##
## The payer is `PathState.progress`, and the reasoning is in
## `api.gd::_study_charge`. In short:
##
##   - `qi` is the CAST cost of a technique, not a study cost. Charging study out
##     of it would price acquisition in the same currency as execution, and it is
##     the one cost an actor can dodge entirely by never casting.
##   - `Stat.COMPREHENSION` is a BASE ATTRIBUTE read by three modules'
##     breakthrough gates, by `Stat.INSIGHT_GAIN`, by `TribulationEndurance` and
##     by the ascension ladder. Draining it moves gates backwards in modules this
##     one may not reach.
##   - `Stat.INSIGHT_GAIN` is a derived RATE, not a stock.
##   - `PathState.progress` is the one quantity that is both spendable and about
##     cultivation, and `LEARN_STEP = 1.03` was sized against the very
##     `progress_required` floor a study charge spends.
##
## ## Why it is not charged from a new resource
##
## A dedicated "study points" pool would be a new concept with no producer, no
## regeneration and no UI, and ADR 0055 sized `LEARN_STEP` against a quantity
## that already exists. So no new resource was invented.

const MORTAL := &"qi_refining"
const SPIRIT := &"spirit_condensation"

## One realm step below the top of the ladder, so a "higher realm costs more" case
## moves the ordinal without needing the actor to satisfy anything else.
const DEEP := &"tribulation"

## The top tier, which is what `ItemGrade.DIVINE` floors to: `required_tier()`
## maps divine to tier 4 (Transcendent), so a divine def is `realm_unmet` for
## anything short of this and a grade-comparison case must stand here.
const TRANSCENDENT := &"transcendent"


## A hero whose qi path holds `progress` units of cultivation work. The progress
## is set on the `PathState` rather than through a facade because it is the state
## under test, and `Actor.set_path` publishes it before `TechniquesApi.attach`
## runs — so nothing in the attach can reset it.
func _hero(progress: float, realm_id: StringName = MORTAL) -> Actor:
	var actor := Actor.new(&"scholar", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.path(PathState.QI).progress = progress
	TechniquesApi.attach(actor)
	return actor


func _technique(
	grade: StringName = ItemGrade.MORTAL, path_id: StringName = PathState.QI
) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = StringName("study_cost_%s_%s" % [String(grade), String(path_id)])
	def.display_name = "A Manual"
	def.grade = grade
	def.active = false
	def.path = path_id
	TechniqueCatalog.instance().register(def)
	return def


# --- The charge is real and exact ---------------------------------------------


func test_learning_costs_exactly_the_authored_price_from_the_techniques_own_path() -> void:
	var def := _technique()
	var actor := _hero(1000.0)
	var price := TechniqueGate.learn_price_for(actor, def)
	assert_almost_eq(price, 100.0, "R1 mortal is LEARN_BASE, per ADR 0055", 0.0001)

	var learned := TechniquesApi.learn(actor, def)
	assert_eq(bool(learned.get("ok")), true, "the learn happened")
	# The load-bearing assertion: the price left the pool. Not "the actor got
	# weaker", not "something was spent" — exactly the ladder's number.
	assert_almost_eq(
		actor.path(PathState.QI).progress, 1000.0 - price, "the study price was paid, exactly"
	)
	# And it is the price the READ MODEL quoted, so a panel and the charge cannot
	# quote different numbers. `inspect` is the same `learn_price_for`.
	assert_almost_eq(
		float(learned.get("learn_price")),
		float(TechniquesApi.inspect(actor, def)["learn_price"]),
		"the outcome quotes what it charged",
		0.0001
	)
	assert_almost_eq(
		float((learned.get("paid") as Dictionary)["qi_cultivation"]),
		price,
		"and names the pool it charged, by path id",
		0.0001
	)
	assert_eq(TechniquesApi.codex(actor).knows(def.id), true, "the technique is known")


# --- A refusal writes NOTHING --------------------------------------------------


func test_a_learn_the_actor_cannot_afford_is_refused_by_name_and_writes_nothing() -> void:
	var def := _technique()
	# 40.0 against a 100.0 price: genuinely short, not short by an epsilon.
	var actor := _hero(40.0)
	var codex_before := TechniquesApi.codex(actor).to_dict()

	var refused := TechniquesApi.learn(actor, def)
	assert_eq(bool(refused.get("ok")), false, "the learn is refused")
	assert_eq(String(refused.get("reason")), "insufficient_progress", "by a named reason")
	# The shortfall names itself, the way `TechniqueCasting.activate`'s
	# `short` does, so a caller can render "you need 100, you have 40".
	var short := refused.get("short") as Array
	assert_eq(short.size(), 1, "one pool is short")
	assert_eq(String((short[0] as Dictionary)["resource"]), "qi_cultivation", "named by path")
	assert_almost_eq(float((short[0] as Dictionary)["required"]), 100.0, "what it owed", 0.0001)
	assert_almost_eq(float((short[0] as Dictionary)["current"]), 40.0, "what it held", 0.0001)
	assert_almost_eq(
		float(refused.get("learn_price")), 100.0, "and the refusal quotes the price too", 0.0001
	)
	# NOTHING moved. Not partially: no progress deducted, no codex row, no
	# persisted payload. A permanent purchase that failed halfway would be the
	# worst possible outcome, so all three are asserted.
	assert_almost_eq(
		actor.path(PathState.QI).progress, 40.0, "no progress was deducted on a refusal"
	)
	assert_eq(TechniquesApi.codex(actor).knows(def.id), false, "and nothing was learned")
	assert_eq(TechniquesApi.codex(actor).to_dict(), codex_before, "the payload is byte-identical")


func test_a_refused_learn_leaves_the_gate_refusing_rather_than_half_paying() -> void:
	# The all-or-nothing proof as an ORDER: the shortfall is checked before the
	# codex row is written, so a refused learn cannot leave an entry that no
	# caller paid for. Top the path up afterwards and the SAME call succeeds,
	# which is only possible if the refusal moved nothing at all.
	var def := _technique()
	var actor := _hero(40.0)
	assert_eq(bool(TechniquesApi.learn(actor, def).get("ok")), false, "refused when short")
	actor.path(PathState.QI).progress = 100.0
	assert_eq(
		bool(TechniquesApi.learn(actor, def).get("ok")),
		true,
		"the very same call succeeds once the price is there"
	)
	assert_almost_eq(
		actor.path(PathState.QI).progress, 0.0, "and pays the price exactly once", 0.0001
	)


# --- The ladder rises ---------------------------------------------------------


func test_a_higher_realm_costs_more_because_the_price_rides_the_actor_s_ordinal() -> void:
	var def := _technique()
	var early := _hero(1000.0, MORTAL)
	var deep := _hero(1000.0, DEEP)

	var low := TechniqueGate.learn_price_for(early, def)
	var high := TechniqueGate.learn_price_for(deep, def)
	assert_almost_eq(low, 100.0, "ordinal 0 mortal", 0.0001)
	# `LEARN_STEP = 1.03` compounding: `DEEP` is ordinal 27, so the deep price is
	# exactly `100 * 1.03^27`. Asserting the RELATION rather than the literal
	# keeps the case honest if a realm is inserted below it.
	assert_almost_eq(
		high / low,
		pow(TechniqueScales.LEARN_STEP, float(TechniqueGate.path_ordinal(deep, PathState.QI))),
		"the deep price is the shallow price times the ladder",
		0.0001
	)
	assert_eq(high > low, true, "so studying higher really does cost more")

	# And the CHARGE follows, which is what makes the two halves one rule rather
	# than two: both actors start from the same 1000.0 and both pay their own.
	TechniquesApi.learn(early, def)
	TechniquesApi.learn(deep, def)
	assert_almost_eq(
		early.path(PathState.QI).progress, 1000.0 - low, "the shallow hero paid its own price"
	)
	assert_almost_eq(
		deep.path(PathState.QI).progress, 1000.0 - high, "and the deep hero paid a bigger one"
	)


func test_grade_widens_the_price_the_way_adr_0055_publishes() -> void:
	# Both techniques at the SAME grade floor, so the price difference is `MAG_GRADE`
	# alone and nothing else. `DIVINE` cannot be compared against `MORTAL` directly:
	# `TechniqueDef.required_tier()` reads the grade, so a divine def is `realm_unmet`
	# for a mortal hero and the case would be measuring the gate, not the price.
	# `SPIRIT` and `DIVINE` both sit in shipped tiers a high hero can reach, and
	# `MAG_GRADE` publishes spirit 1.6 against divine 6.5 — a 4.0625x ratio.
	var mortal := _technique(ItemGrade.SPIRIT)
	var divine := _technique(ItemGrade.DIVINE)
	var actor := _hero(100000.0, TRANSCENDENT)
	var first := TechniquesApi.learn(actor, mortal)
	assert_eq(
		bool(first.get("ok")), true, "the spirit study lands: %s" % String(first.get("reason", ""))
	)
	var mortal_cost := 100000.0 - actor.path(PathState.QI).progress
	var second := TechniquesApi.learn(actor, divine)
	assert_eq(
		bool(second.get("ok")),
		true,
		"and so does the divine: %s" % String(second.get("reason", ""))
	)
	var divine_cost := 100000.0 - mortal_cost - actor.path(PathState.QI).progress
	# Grade is a floor, not a scale (ADR 0055) — but it DOES move the price, by
	# `MAG_GRADE`. This is the assertion that keeps those two facts apart.
	assert_almost_eq(
		divine_cost / mortal_cost,
		(
			TechniqueScales.grade_factor(ItemGrade.DIVINE)
			/ TechniqueScales.grade_factor(ItemGrade.SPIRIT)
		),
		"divine study costs the authored MAG_GRADE ratio over spirit at the same realm",
		0.001
	)


# --- The payer is the technique's OWN path -------------------------------------


func test_the_charge_comes_off_the_techniques_own_path_and_not_another() -> void:
	var actor := Actor.new(&"dual", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	actor.set_path(PathState.new(PathState.MIND, MORTAL))
	actor.path(PathState.QI).progress = 1000.0
	actor.path(PathState.MIND).progress = 1000.0
	TechniquesApi.attach(actor)

	var def := _technique(ItemGrade.MORTAL, PathState.MIND)
	TechniquesApi.learn(actor, def)
	# The qi path is untouched: a mind manual does not drain the reservoir the
	# qi path's own techniques cast from.
	assert_almost_eq(actor.path(PathState.QI).progress, 1000.0, "the qi path paid nothing")
	assert_almost_eq(
		actor.path(PathState.MIND).progress, 900.0, "the mind path paid the whole price", 0.0001
	)


func test_a_shared_technique_is_never_charged_because_shared_is_not_a_path() -> void:
	# A SHARED technique takes a universal slot (ADR 0053), so it also takes no
	# path's progress. Charging the "first" path of a `shared` marker would name
	# a pool id no `PathState` carries, which is a charge against nothing.
	var def := _technique(ItemGrade.MORTAL, TechniquePolicy.SHARED)
	var actor := _hero(1000.0)
	var learned := TechniquesApi.learn(actor, def)
	assert_eq(bool(learned.get("ok")), true, "a shared manual is still learnable")
	assert_almost_eq(actor.path(PathState.QI).progress, 1000.0, "and no path's progress moved")
	assert_eq(
		(learned.get("paid") as Dictionary).is_empty(), true, "the outcome reports no payment"
	)


func test_the_technique_can_still_be_learned_at_a_price_the_actor_cannot_meet() -> void:
	# The gate is unchanged: `realm_unmet` is still reported by the GATE, and it
	# is reported BEFORE affordability, so an actor too poor for a technique is
	# never told about the price of one it may not learn.
	var def := _technique(ItemGrade.IMMORTAL)
	var actor := _hero(1000000.0)
	var refused := TechniquesApi.learn(actor, def)
	assert_eq(String(refused.get("reason")), "realm_unmet", "the gate answers first")
	assert_eq(refused.has("short"), false, "and no shortfall is quoted for a gated technique")
	assert_almost_eq(actor.path(PathState.QI).progress, 1000000.0, "and nothing was charged")


# --- The facade cap is still not spent -----------------------------------------


func test_pricing_the_learn_cost_the_facade_no_method() -> void:
	# The charge went INTO `learn` and the affordability table went into two
	# private helpers. `TechniquesApi` is at exactly 12 and may not grow a 13th.
	var script: Script = TechniquesApi.new().get_script()
	var published: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method.get("name", ""))
		if method_name.begins_with("_") or published.has(method_name):
			continue
		published.append(method_name)
	assert_eq(published.size(), 12, "still exactly twelve public methods")
	for name in ["_study_charge", "_short"]:
		assert_eq(published.has(name), false, "'%s' is an internal" % name)
