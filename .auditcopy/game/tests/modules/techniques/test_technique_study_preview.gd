extends TestCase

## DEF-0244: the study price is knowable BEFORE the manual is spent.
##
## ADR 0160 made `learn` charge the technique's own path's `PathState.progress`, all
## or nothing. That made both the price and the shortfall knowable in advance, and
## `TechniqueReadModel` publishes both through `TechniquesApi.inspect`.
##
## This asserts the READ side, because the defect was never the charge: it was that
## nothing reachable published the number. A charge with no published price is a price
## a player only learns by losing.
##
## It belongs here rather than in the UI suite because the rule is the module's.
## `technique_codex.gd` republishes these keys; a screen computing its own
## affordability would restate the rule and the two would drift.

const MORTAL := &"qi_refining"
var _serial := 0


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
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("study_preview_%d" % _serial)
	def.display_name = "A Manual"
	def.grade = grade
	def.active = false
	def.path = path_id
	TechniqueCatalog.instance().register(def)
	return def


func test_an_unlearned_technique_publishes_its_price_and_whether_the_actor_can_pay() -> void:
	var actor := _hero(100000.0)
	var def := _technique()
	var view := TechniquesApi.inspect(actor, def.id)
	assert_eq(float(view.get("learn_price", 0.0)) > 0.0, true, "the price is published")
	assert_eq(bool(view.get("can_pay", false)), true, "and this actor can pay it")
	assert_eq(
		bool(view.get("can_pay_known", false)), true, "and the answer is known, not defaulted"
	)
	assert_eq((view.get("learn_short", []) as Array).size(), 0, "with nothing owed")


func test_a_short_actor_is_shown_the_shortfall_not_only_a_refusal() -> void:
	var actor := _hero(40.0)
	var def := _technique()
	var view := TechniquesApi.inspect(actor, def.id)
	assert_eq(bool(view.get("can_pay", false)), false, "40 cannot pay a 100 study")
	var short := view.get("learn_short", []) as Array
	assert_eq(short.size(), 1, "and the shortfall names one pool")
	assert_eq(String((short[0] as Dictionary)["resource"]), "qi_cultivation", "by path")
	assert_almost_eq(float((short[0] as Dictionary)["required"]), 100.0, "what it owed")
	assert_almost_eq(float((short[0] as Dictionary)["current"]), 40.0, "and what it held")


func test_the_published_shortfall_is_the_one_learn_actually_refuses_on() -> void:
	# The point of publishing rather than recomputing: the preview and the charge
	# must be the SAME numbers. If the read model computed its own affordability,
	# this is where a divergence would show — a panel promising a study the learn
	# then refuses, which is worse than showing no price at all.
	var actor := _hero(40.0)
	var def := _technique()
	var view := TechniquesApi.inspect(actor, def.id)
	var preview := view.get("learn_short", []) as Array
	var refused := TechniquesApi.learn(actor, def)
	assert_eq(bool(refused.get("ok", true)), false, "the learn is refused")
	assert_eq(String(refused.get("reason", "")), "insufficient_progress", "by that same reason")
	assert_almost_eq(
		float((refused.get("short", []) as Array)[0]["required"]),
		float((preview[0] as Dictionary)["required"]),
		"and for the same amount the preview published",
		0.0001
	)
	assert_eq(TechniquesApi.codex(actor).knows(def.id), false, "a refused preview costs nothing")


func test_a_shared_technique_is_never_charged_so_there_is_no_price_to_show() -> void:
	var actor := _hero(0.0)
	var def := _technique(ItemGrade.MORTAL, TechniquePolicy.SHARED)
	var view := TechniquesApi.inspect(actor, def.id)
	assert_eq(bool(view.get("can_pay", false)), true, "a shared manual is free")
	assert_eq(bool(view.get("can_pay_known", false)), true, "and that answer is real")
	assert_eq((view.get("learn_short", []) as Array).size(), 0, "with nothing owed")
