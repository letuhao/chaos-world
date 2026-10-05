extends TestCase

## ADR 0002: the composition root (app/) registers module providers with actors.

# --- BL-0523: the mind enrolment verb must leave a USABLE actor ----------------
#
# `MindCultivationApi.attach_sea` had exactly ONE reference in `res://src`: its own
# definition at `api.gd:38`. `ActorFactory.with_mind_cultivation` — the only
# production enrolment, reached from `app/item_workbench_app.gd:243` and
# `app/character_creation_flow.gd:291` — calls `attach` and `synchronize` and never
# `attach_sea`, and `synchronize` returns early on a null sea
# (`MindTraining.synchronize:25`). So every actor the game built had NO Sea of
# Consciousness: `MindTraining.cultivate` refused at `training.gd:56`, `recover`
# refused at `training.gd:125`, and `summary` reported `mind_power: 0.0`. The whole
# Mind path was inert in play while reporting itself healthy.
#
# Why 10,186 green assertions never saw it: all 38 `attach_sea` call sites live in
# `game/tests/`, and every hand-built fixture calls it — see
# `tests/modules/mind_cultivation/test_mind_training.gd:14`. The FIXTURE supplied
# exactly what PRODUCTION withholds. Only two tests ever call
# `with_mind_cultivation` (`tests/modules/elements/test_element_wiring.gd:317`,
# `tests/ui/test_mind_ascent.gd:243`, which attaches the sea by hand on the next
# line) and neither asserted the actor was usable afterwards.
#
# So build the actor the way production builds it — through the verb — and assert
# the verb's RESULT. A call to `attach` proves nothing;
# `test_body_cultivation_reachability.gd:260` already says so. Nothing below calls
# `attach_sea`: doing that would rebuild the very hole this file closes.
#
# Written while `attach` still withheld the sea, and RED on that tree: 6 passed,
# 5 failed. Folding `attach_sea` into `attach` — the fix ADR 0095 made for qi —
# turns all 15 green, and nothing else here changed. It is the same one line that
# moved the suite, which is what makes it a guard rather than a description.

## The ladder's first realm, which is what `with_mind_cultivation`'s own default
## `rank_id` enrols on — production calls it with no rank at all.
const START_REALM := &"qi_refining"


## An actor enrolled the way `app/item_workbench_app.gd` enrols it, on the weakest
## fixture that can still run: `ActorFactory.build` and the enrolment verb, nothing
## else. No base stats, no items, no manual attach, no second path. Anything this
## needs is something the verb owes its caller, so a failure here cannot be blamed
## on an under-provisioned actor.
func _enrolled() -> Actor:
	return ActorFactory.with_mind_cultivation(ActorFactory.build(&"student"))


## The sea is where the mind path stores cultivation. Absent it, `cultivate`,
## `meditate`, `recover`, `train_channel` and `strengthen_sea` all refuse and
## `summary` reports a power of zero.
func test_mind_enrolment_leaves_an_actor_with_a_sea() -> void:
	var sea := MindCultivationApi.sea(_enrolled())
	assert_ne(
		sea,
		null,
		"the Sea of Consciousness exists on an actor the factory enrolled on the mind path"
	)


## The consequence, asked of the verb a player actually presses. `cultivate`
## refuses on a null sea at `training.gd:56`, so on an unenrolled actor it returns
## false and the path never advances.
func test_mind_enrolment_leaves_an_actor_that_can_actually_cultivate() -> void:
	var actor := _enrolled()
	var state := actor.path(MindPath.PATH_ID)
	assert_ne(state, null, "the enrolment put the actor on the mind path")
	if state == null:
		return
	var progress_before: float = state.progress
	assert_eq(
		MindCultivationApi.cultivate(actor),
		true,
		"one session of cultivation is accepted on a factory-enrolled actor"
	)
	assert_eq(
		state.progress > progress_before, true, "and it advanced real progress on the enrolled path"
	)


## The capacity is DERIVED from the code under test, never pasted:
## `MindTraining.synchronize:27` writes
## `seed.sea_capacity * (1.0 + actor.meridians.get_capacity_bonus())`, so that
## expression IS the contract. Reading it back off the seed keeps the assertion
## honest if the entry realm's authored capacity is ever retuned.
func test_mind_enrolment_sizes_the_sea_from_the_realm_seed() -> void:
	var actor := _enrolled()
	var sea := MindCultivationApi.sea(actor)
	assert_ne(sea, null, "the sea exists")
	if sea == null:
		return
	var state := actor.path(MindPath.PATH_ID)
	assert_eq(
		String(state.rank_id),
		String(START_REALM),
		"and the actor is on the realm this test derives the capacity for"
	)
	var seed := MindRealmSeed.for_realm(START_REALM)
	var expected: float = seed.sea_capacity * (1.0 + actor.meridians.get_capacity_bonus())
	assert_eq(sea.structural_capacity > 0.0, true, "the sea holds a capacity above zero")
	assert_almost_eq(
		sea.structural_capacity, expected, "sized by synchronize from the realm seed's capacity"
	)
	# The pool the sea reads and fills (`SeaOfConsciousness.fill:56`) is capped to
	# that capacity at `training.gd:33`, so a sea with no ceiling would also be a
	# path that cannot store anything.
	assert_almost_eq(
		sea.maximum(actor), sea.structural_capacity, "and the reservoir is capped to it"
	)


## Enrolling twice must not stack a second sea. `ActorStats.add_provider` appends
## UNGUARDED (`actor_factory.gd:41`), so a second `MindProvider` or `SeaProvider`
## would silently double every mind-path contribution — which is why `attach` and
## `attach_sea` both guard on a `_has_provider` / `existing != null` check
## (`api.gd:26`, `api.gd:39`, `api.gd:45`) and the enrolment verbs refresh the
## element realm instead of re-attaching. Asserted on the VERB, because
## `test_sea_of_consciousness.gd:106` already pins it on `attach_sea` alone.
func test_mind_enrolment_twice_does_not_stack_a_second_sea() -> void:
	var actor := _enrolled()
	var sea := MindCultivationApi.sea(actor)
	var providers := actor.stats.provider_count()
	ActorFactory.with_mind_cultivation(actor)
	assert_eq(
		MindCultivationApi.sea(actor),
		sea,
		"re-enrolling keeps the same sea rather than replacing it"
	)
	assert_eq(
		actor.stats.provider_count(),
		providers,
		"and stacks no second provider, which `add_provider` would append unguarded"
	)
	assert_eq(
		MindCultivationApi.cultivate(actor), true, "so the actor is left usable, not half-built"
	)


# --- The two registrations this file already covered --------------------------


func test_dual_cultivation_registration() -> void:
	var actor := ActorFactory.with_dual_cultivation(
		Actor.new(&"hero", {DualCultivationApi.CHARM: 10.0})
	)
	assert_eq(actor.stats.provider_count(), 1, "provider registered")
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 20.0, "module stat live")


func test_fertility_registration() -> void:
	var actor := ActorFactory.with_fertility(
		Actor.new(&"mother", {DualCultivationApi.FERTILITY: 10.0})
	)
	assert_eq(actor.stats.provider_count(), 1, "provider registered")
