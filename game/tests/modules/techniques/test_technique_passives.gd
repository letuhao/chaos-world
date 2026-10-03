extends TestCase

## Passive delivery (ADR 0054): a passive technique is a namespaced set of
## `StatModifier`s applied and removed through `ItemEffects`, rebuilt
## remove-all-then-re-add, and suspended — never unequipped — when its upkeep
## cannot be paid.

const MORTAL := &"qi_refining"
const SHARED_TAG_PREFIX := "technique:"

## `cult_qi_control` is one of the 36 technique-legal pool options (ADR 0054), and
## `core_max_qi` is a resource-capacity target, so this one passive exercises both
## the stat channel and the resource channel of the pipeline.
const STAT_OPTION := &"cult_qi_control"
const RESOURCE_OPTION := &"core_max_qi"


func _actor(qi: float = 500.0) -> Actor:
	var actor := Actor.new(&"practitioner", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", qi))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	TechniquesApi.attach(actor)
	return actor


## A passive carrying one stat option and one resource-capacity option. The def is
## registered with the catalog so `settle` and `inspect` can resolve it by id, the
## same way a `.tres` would be.
func _passive(upkeep: Dictionary = {}) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"test_passive_control"
	def.display_name = "Breath Control Manual"
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	def.passive_options = [
		{"option_id": STAT_OPTION, "value": 4.0},
		{"option_id": RESOURCE_OPTION, "value": 25.0},
	]
	def.upkeep = upkeep
	def.upkeep_interval = 60.0
	TechniqueCatalog.instance().register(def)
	return def


# --- Source tag ---------------------------------------------------------------


func test_equipping_a_passive_applies_modifiers_under_a_namespaced_source_tag() -> void:
	var actor := _actor()
	var def := _passive()
	var max_qi_before := actor.stats.derived(Stat.MAX_QI)
	TechniquesApi.codex(actor).learn(def.id)
	assert_eq(actor.stats.modifier_count(), 0, "nothing applied before the equip")
	TechniquesApi.equip(actor, def)
	var max_qi_equipped := actor.stats.derived(Stat.MAX_QI)
	# The tag is a namespaced prefix, never a bare id: `remove_modifiers_from` is an
	# exact-string filter, so a bare id could collide with `&"realm"` or an
	# equipment instance id.
	var expected := StringName("%s%s" % [SHARED_TAG_PREFIX, def.id])
	assert_eq(TechniqueEffects.source_for(def.id), expected, "the tag is prefixed")
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 2, "both channels applied under it")
	# The stat moved by exactly its authored value, once. The baseline is the
	# actor's DERIVED max qi (80 from its two attributes), not its pool maximum
	# (500, set by the fixture): a modifier lands on the stat, and only a system
	# that re-syncs pools would carry it onto the pool. Asserting against the pool
	# asked for 525 and so could never hold.
	assert_almost_eq(
		actor.stats.get_base(StringName("qi_control")), 0.0, "base untouched by a modifier"
	)
	assert_almost_eq(
		max_qi_equipped, max_qi_before + 25.0, "the resource capacity channel applied once"
	)
	# And the tag is genuinely namespaced: it is not the bare id.
	assert_ne(TechniqueEffects.source_for(def.id), def.id, "never a bare id")


func test_two_passives_do_not_annihilate_each_other() -> void:
	# The hazard ADR 0054 names: `remove_modifiers_from` has no prefix matching, so
	# a shared bare tag would silently delete both owners' contributions on one
	# rebuild. Distinct tags must stay independently toggleable.
	var actor := _actor()
	var first := _passive()
	TechniquesApi.codex(actor).learn(first.id)
	TechniquesApi.equip(actor, first)
	var second := TechniqueDef.new()
	second.id = &"test_passive_second"
	second.active = false
	second.path = PathState.QI
	second.passive_options = [{"option_id": STAT_OPTION, "value": 9.0}]
	TechniqueCatalog.instance().register(second)
	TechniquesApi.codex(actor).learn(second.id)
	TechniquesApi.equip(actor, second)
	assert_eq(TechniqueEffects.applied_count(actor, first.id), 2, "first intact")
	assert_eq(TechniqueEffects.applied_count(actor, second.id), 1, "second intact")
	TechniquesApi.rebuild(actor)
	assert_eq(TechniqueEffects.applied_count(actor, first.id), 2, "still intact after rebuild")
	assert_eq(TechniqueEffects.applied_count(actor, second.id), 1, "and so is the second")


# --- Rebuild does not drift ---------------------------------------------------


func test_rebuild_twice_does_not_accumulate_drift() -> void:
	var actor := _actor()
	var def := _passive()
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var baseline_modifiers := actor.stats.modifier_count()
	var baseline_max_qi := actor.stats.derived(Stat.MAX_QI)
	assert_eq(baseline_modifiers, 2, "the passive contributes exactly two modifiers")
	for pass_index in 4:
		TechniquesApi.rebuild(actor)
		assert_eq(
			actor.stats.modifier_count(),
			baseline_modifiers,
			"modifier count is unchanged on rebuild %d" % pass_index
		)
		assert_almost_eq(
			actor.stats.derived(Stat.MAX_QI),
			baseline_max_qi,
			"the stat returns to its baseline on rebuild %d" % pass_index
		)


func test_repeated_equip_and_unequip_returns_to_the_same_stat_stack() -> void:
	var actor := _actor()
	var def := _passive()
	# The floor the stat returns to is the actor's own derived max qi with nothing
	# equipped, captured before the first equip. It is NOT the pool maximum: a
	# modifier lands on the stat, and the pool is a separate quantity this test
	# never syncs, so comparing against it asked for 500 and could never hold.
	var floor_max_qi := actor.stats.derived(Stat.MAX_QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var baseline_max_qi := actor.stats.derived(Stat.MAX_QI)
	for cycle in 3:
		TechniquesApi.equip(actor, def)
		TechniquesApi.unequip(actor, def)
		assert_eq(actor.stats.modifier_count(), 0, "nothing left after cycle %d" % cycle)
		assert_almost_eq(
			actor.stats.derived(Stat.MAX_QI),
			floor_max_qi,
			"the capacity bonus is gone on cycle %d" % cycle
		)
	TechniquesApi.equip(actor, def)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI), baseline_max_qi, "re-equipping restores it exactly"
	)


func test_re_equipping_a_passive_does_not_stack_its_own_modifiers() -> void:
	var actor := _actor()
	var def := _passive()
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var first := actor.stats.derived(Stat.MAX_QI)
	# Equipping an already-equipped technique moves it rather than stacking it.
	var again := TechniquesApi.equip(actor, def)
	assert_eq(bool(again["ok"]), true, "re-equipped")
	assert_eq(actor.stats.modifier_count(), 2, "still exactly two modifiers")
	assert_almost_eq(actor.stats.derived(Stat.MAX_QI), first, "and the same stat value")


# --- Suspension ---------------------------------------------------------------


func test_an_unpaid_upkeep_suspends_the_passive_without_unequipping_it() -> void:
	var actor := _actor(10.0)
	var def := _passive({&"qi": 50.0})
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 2, "contributing while paid for")
	var before := actor.stats.derived(Stat.MAX_QI)

	# 50 qi a tick against a 10 qi pool: the payment is refused.
	var changed := TechniquesApi.settle_upkeep(actor)
	assert_eq(changed.has(def.id), true, "the technique changed state")
	assert_eq(
		TechniquesApi.summary(actor)["suspended"].has("test_passive_control"), true, "suspended"
	)
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 0, "contributes NOTHING")
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI), before - 25.0, "the stat is back to its unsuspended value"
	)
	assert_ne(actor.stats.derived(Stat.MAX_QI), before, "the bonus really was removed")
	# The load-bearing part: still equipped. An unaffordable upkeep is an ongoing
	# obligation, not an equip gate — it must never unequip and never cascade.
	assert_eq(TechniquesApi.slots(actor).is_equipped(def.id), true, "STILL equipped")
	assert_eq(TechniquesApi.codex(actor).knows(def.id), true, "and still known")


func test_a_suspended_passive_is_not_revived_by_a_rebuild() -> void:
	# The gap ADR 0054 calls out in equipment, which a rebuild must not reopen: a
	# suspended technique rebuilds as an empty contribution, never as its modifiers.
	var actor := _actor(10.0)
	var def := _passive({&"qi": 50.0})
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	TechniquesApi.settle_upkeep(actor)
	for pass_index in 3:
		TechniquesApi.rebuild(actor)
		assert_eq(
			TechniqueEffects.applied_count(actor, def.id),
			0,
			"still nothing on rebuild %d" % pass_index
		)
	assert_eq(TechniquesApi.slots(actor).is_equipped(def.id), true, "equipped throughout")


func test_a_suspended_passive_never_blocks_an_equip() -> void:
	# Suspension is per technique and keyed by id, so one unaffordable technique
	# cannot bar another from being equipped.
	var actor := _actor(10.0)
	var dear := _passive({&"qi": 50.0})
	TechniquesApi.codex(actor).learn(dear.id)
	TechniquesApi.equip(actor, dear)
	TechniquesApi.settle_upkeep(actor)
	assert_eq(TechniqueEffects.applied_count(actor, dear.id), 0, "the dear one is suspended")

	var cheap := TechniqueDef.new()
	cheap.id = &"test_passive_cheap"
	cheap.active = false
	cheap.path = PathState.QI
	TechniqueCatalog.instance().register(cheap)
	TechniquesApi.codex(actor).learn(cheap.id)
	var equipped := TechniquesApi.equip(actor, cheap)
	assert_eq(bool(equipped["ok"]), true, "the free technique still equips")
	assert_eq(TechniquesApi.slots(actor).is_equipped(dear.id), true, "the suspended one stays put")


func test_paying_upkeep_again_reactivates_the_contribution() -> void:
	# 10 qi against a 15.0 upkeep and no reserve: the first tick cannot pay, so the
	# technique suspends; the second tick still cannot pay, so nothing changes.
	# An earlier version used a 5.0 upkeep against a 10 qi pool, which is
	# AFFORDABLE (10 - 5 >= 0), so the technique never suspended and the case
	# asserted a suspension that could never happen.
	var actor := _actor(10.0)
	var def := _passive({&"qi": 15.0})
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	TechniquesApi.settle_upkeep(actor)
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 0, "suspended on the first tick")
	# A second settle at the same deficit reports no change, which is the property
	# that keeps a settled upkeep from rebuilding every tick.
	var changed := TechniquesApi.settle_upkeep(actor)
	assert_eq(changed.has(def.id), false, "an unchanged suspension reports nothing")
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 0, "and still contributes nothing")
	# Pay the pool back up and the next settle reactivates it. The pool is created
	# with its maximum AT the starting value, so a top-up is clamped away and the
	# technique can never become affordable again — the pool's maximum has to be
	# raised first, or this asserts a reactivation that cannot happen.
	var pool := actor.resource(&"qi")
	pool.maximum = 100.0
	pool.current = 40.0
	var revived := TechniquesApi.settle_upkeep(actor)
	assert_eq(revived.has(def.id), true, "it changed state again")
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 2, "contributing again")
	assert_eq(actor.resource(&"qi").current < 40.0, true, "and it really was paid")


# --- The frame cadence ---------------------------------------------------------


func test_a_frame_tick_does_not_settle_before_the_interval_elapses() -> void:
	# `settle_upkeep` charges IMMEDIATELY, and `StatusLoop.tick` calls it once per
	# frame. Passing the delta makes the facade accumulate it and settle only when an
	# authored interval has passed; without that, a 60-second upkeep would be charged
	# sixty times a second and the technique would suspend within one second of being
	# equipped — an upkeep nobody could ever keep.
	var actor := _actor(5000.0)
	var def := _passive({&"qi": 10.0})
	def.upkeep_interval = 60.0
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var before := actor.resource(&"qi").current

	# Sixty frames at 1/60s is one second: not yet due.
	for _frame in 60:
		TechniquesApi.settle_upkeep(actor, 1.0 / 60.0)
	assert_almost_eq(actor.resource(&"qi").current, before, "a second of frames charges nothing")

	# Cross the interval and it charges exactly once, not sixty times.
	for _frame in 60 * 59:
		TechniquesApi.settle_upkeep(actor, 1.0 / 60.0)
	assert_almost_eq(
		actor.resource(&"qi").current,
		before - 10.0,
		"and at sixty seconds it has been charged once, not once per frame"
	)


func test_an_unaffordable_upkeep_suspends_through_the_frame_tick() -> void:
	# The production path end to end: driven by a delta, not by calling the facade's
	# immediate settle. This is what `StatusLoop.tick` does, and it is what an
	# unaffordable upkeep has to look like from the game's point of view.
	var actor := _actor(10.0)
	var def := _passive({&"qi": 15.0})
	def.upkeep_interval = 1.0
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 2, "contributing at first")

	var changed := TechniquesApi.settle_upkeep(actor, 1.5)
	assert_eq(changed.has(def.id), true, "the interval elapsed and the payment was refused")
	assert_eq(TechniquesApi.slots(actor).is_equipped(def.id), true, "still equipped (ADR 0054)")
	assert_eq(TechniqueEffects.applied_count(actor, def.id), 0, "and contributing nothing")
