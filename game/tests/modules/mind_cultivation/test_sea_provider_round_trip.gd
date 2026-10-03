extends TestCase

## BL-0108: the Sea of Consciousness is restored across a save/load round trip, but
## the `SeaProvider` that publishes it is not, so a loaded actor's sea has no
## published surface at all.
##
## ## What is actually lost
##
## `Actor.from_dict` restores components and never a `StatProvider` — by design,
## because providers are wiring the composition root and each module's `attach`
## install. So the load path's job is to re-attach, and `MindCultivationApi.attach`
## is the verb that does it. `attach` folds in `attach_sea` (ADR 0095's shape,
## commit `4ea786f6`), and `attach_sea` returns the component it finds BEFORE
## registering the provider. A restored actor therefore arrives carrying a sea and
## leaves `attach` still carrying none: the early return turns the only production
## enrolment path into a no-op for exactly the actors that need it.
##
## The stat this costs is `MindStats.SEA_CAPACITY`, the sea provider's whole
## published surface (`test_mind_stat_surface.gd` pins that it is one id). The
## character sheet builds its rows from `ActorStats.derived_all()`
## (`ui/screens/character_screen.gd`) and takes each row's label and precision from
## `StatPresenter.TABLE`, which carries a "Sea capacity" row. With no provider the
## id is absent from that map, so the row VANISHES after a load instead of reading
## zero — silent, with no error anywhere. That is the whole player-visible impact:
## three other sea ids were deleted as dead (BL-0163), so this defect is quieter
## than it was, but it is not masked.
##
## ## What this file must not become
##
## The tempting fix — calling `attach`/`attach_sea` from `Actor.from_dict` — is
## wrong, and the last test here is the guard. It would give EVERY restored actor a
## mind sea, including one whose payload never carried one because it was never
## enrolled on the mind path: the actor would answer "has_path: false" with a full
## sea behind it. Restoration is conditional on what the payload carries, so the
## condition lives in the module's own attach, never in core.

const RANK := &"qi_refining"

## Enough cultivation to make the sea's state distinctive: a part-filled reservoir
## and a raised clarity, so "the sea round tripped" cannot be satisfied by a default.
const CULTIVATE_STEP := 250.0


## Enrolled through the shipped composition root, so the sea, its provider and its
## synchronized capacity all exist because production code created them.
func _enrolled() -> Actor:
	var actor := ActorFactory.with_mind_cultivation(
		Actor.new(&"sea_round_trip", {Stat.COMPREHENSION: 40.0})
	)
	assert_ne(
		actor.component(MindCultivationApi.SEA_COMPONENT) == null, true, "enrolment leaves a sea"
	)
	assert_eq(_sea_providers(actor), 1, "enrolment leaves exactly one sea provider")
	return actor


## An enrolled actor with a used reservoir, so the restored reading has a value only
## a real round trip could produce.
func _used() -> Actor:
	var actor := _enrolled()
	assert_eq(MindCultivationApi.cultivate(actor), true, "one sitting of cultivation")
	var pool := actor.resource(MindStats.MIND_POWER)
	assert_eq(pool.current > 0.0, true, "the reservoir took the work")
	return actor


## The load half, written once: `Actor.from_dict` and then the module's own attach,
## which is the whole contract between core's payload and this module's wiring.
func _reloaded(payload: Dictionary) -> Actor:
	var restored := Actor.from_dict(payload)
	MindCultivationApi.attach(restored)
	MindTraining.synchronize(restored)
	return restored


## The facade never hands the module's provider type to callers, so installation is
## asserted where it happens: in `ActorStats._providers`.
func _sea_providers(actor: Actor) -> int:
	var count := 0
	for entry in actor.stats._providers:
		if entry is SeaProvider:
			count += 1
	return count


# --- The round trip -------------------------------------------------------------


## The headline. A loaded actor republishes its sea capacity, and does so through
## the provider rather than through a base attribute that happens to survive.
func test_a_reloaded_actor_republishes_its_sea_capacity() -> void:
	var actor := _used()
	var before := actor.stats.derived(MindStats.SEA_CAPACITY)
	assert_eq(before > 0.0, true, "the enrolled actor publishes a sea capacity")
	assert_almost_eq(
		before, actor.resource(MindStats.MIND_POWER).maximum, "the reservoir is the source"
	)

	var restored := _reloaded(actor.to_dict())
	var sea := MindCultivationApi.sea(restored)
	assert_ne(sea == null, true, "the sea itself rode the payload")
	assert_almost_eq(sea.clarity, MindCultivationApi.sea(actor).clarity, "clarity round tripped")
	assert_almost_eq(
		restored.resource(MindStats.MIND_POWER).current,
		actor.resource(MindStats.MIND_POWER).current,
		"stored mind power round tripped"
	)

	# The load path's own job: re-attach. This is where BL-0108 lost the provider.
	assert_eq(_sea_providers(restored), 1, "re-attaching restores the sea provider")
	assert_almost_eq(
		restored.stats.derived(MindStats.SEA_CAPACITY),
		before,
		"the sea's derived state survives the round trip"
	)
	# The character sheet renders `derived_all()`, so a stat that reads the right
	# number but is ABSENT from that map is a row that does not appear at all. Both
	# halves are asserted because only the second one is what a player would notice.
	assert_ne(
		actor.stats.derived_all().has(MindStats.SEA_CAPACITY),
		false,
		"the sheet's input map carries it before the save"
	)
	assert_ne(
		restored.stats.derived_all().has(MindStats.SEA_CAPACITY),
		false,
		"and carries it after the load"
	)


## The same state after `attach_sea` is called ON the restored actor, which is the
## call the recorded diagnosis blamed. Calling it is not supposed to change anything
## about an actor that already has a sea — and while the early return stood, it did.
func test_attach_sea_on_a_restored_actor_changes_nothing_and_publishes() -> void:
	var actor := _used()
	var restored := _reloaded(actor.to_dict())
	var expected := actor.stats.derived(MindStats.SEA_CAPACITY)

	var returned := MindCultivationApi.attach_sea(restored)
	assert_ne(returned == null, true, "attach_sea answers with the sea")
	assert_eq(
		returned, MindCultivationApi.sea(restored), "and it is the restored one, not a replacement"
	)
	assert_almost_eq(
		restored.stats.derived(MindStats.SEA_CAPACITY), expected, "capacity still published"
	)
	assert_eq(_sea_providers(restored), 1, "and still exactly one provider")


## The provider is a live surface, not a snapshot: it reads the reservoir, so a
## capacity change after the load is visible through it. A provider restored as a
## stale copy of the saved number would pass the round-trip assertion above and
## fail here, which is why both exist.
func test_the_restored_provider_is_live_not_a_snapshot() -> void:
	var actor := _used()
	var restored := _reloaded(actor.to_dict())
	var pool := restored.resource(MindStats.MIND_POWER)
	pool.set_maximum(pool.maximum * 2.0)
	restored.mark_stats_dirty()
	assert_almost_eq(
		restored.stats.derived(MindStats.SEA_CAPACITY),
		pool.maximum,
		"the restored provider reads the restored reservoir"
	)


## `ActorStats.add_provider` appends unguarded, so a second provider would publish
## the same id twice and the sheet would read whichever wrote last. Every verb that
## touches a restored actor must therefore stay idempotent.
func test_repeated_attachment_never_stacks_a_second_provider() -> void:
	var restored := _reloaded(_used().to_dict())
	MindCultivationApi.attach(restored)
	MindCultivationApi.attach(restored)
	MindCultivationApi.attach_sea(restored)
	MindCultivationApi.attach_sea(restored)
	assert_eq(_sea_providers(restored), 1, "four calls, one provider")


# --- Serialized exactly once ----------------------------------------------------


## The sea rides its own versioned payload slot (ADR 0037's shape) and nowhere else.
## A second copy would not be untidy: `from_dict` restores `module_data`
## unconditionally and the versioned slots after, so a copy outside the slot would
## silently win and a payload could resurrect a sea its own schema does not carry.
func test_the_sea_is_serialized_exactly_once() -> void:
	var payload := _used().to_dict()
	assert_ne(payload.get("sea", {}).is_empty(), true, "the sea rides its own slot")
	var module_data: Dictionary = payload.get("module_data", {})
	assert_eq(
		module_data.has(String(MindCultivationApi.SEA_COMPONENT)),
		false,
		"and no sea copy hides in the generic module_data bag"
	)
	# The slot carries the component and nothing else, so a value cannot appear in the
	# payload while disagreeing with the component it was read from.
	assert_eq(
		payload["sea"],
		MindCultivationApi.sea(_reloaded(payload)).to_dict(),
		"the slot is exactly the component's own dict"
	)


## A second trip is a fixed point. Two saved copies of the same state that could
## drift is how a restored actor ends up disagreeing with itself.
func test_a_second_round_trip_is_a_fixed_point() -> void:
	var payload := _used().to_dict()
	var once := _reloaded(payload).to_dict()
	var twice := _reloaded(once).to_dict()
	assert_eq(twice["sea"], once["sea"], "the sea does not move across a second trip")
	assert_eq(twice["sea"], payload["sea"], "nor does it differ from what was saved")
	assert_eq(twice["resources"], once["resources"], "and the reservoir is stable too")


# --- The load must not invent a sea ----------------------------------------------


## The trap. A payload with no sea slot — an actor that was never enrolled on the
## mind path — must load with no sea and no provider, or the fix has reintroduced
## 4ea786f6's defect in a new shape: every actor in the game walking around with a
## sea it never enrolled on.
func test_a_payload_without_a_sea_loads_without_one() -> void:
	var actor := _used()
	var payload := actor.to_dict()
	payload["sea"] = {}
	payload["version"] = 2
	payload["paths"] = {}

	var restored := Actor.from_dict(payload)
	assert_eq(
		restored.component(MindCultivationApi.SEA_COMPONENT) == null, true, "no sea is invented"
	)
	assert_eq(_sea_providers(restored), 0, "and no sea provider either")
	# The gate is enrolment, and only enrolment: attaching the module is what builds
	# the sea for an actor that has none.
	MindCultivationApi.attach(restored)
	assert_ne(
		restored.component(MindCultivationApi.SEA_COMPONENT) == null, true, "attaching builds one"
	)
	assert_eq(_sea_providers(restored), 1, "with its provider")


## The same question asked of the mind screen: an unenrolled actor reads `has_path`
## false, so a sea behind that answer would be state the player can never see and
## never use.
func test_an_unenrolled_payload_does_not_come_back_on_the_path() -> void:
	var qi_only := ActorFactory.with_qi_cultivation(Actor.new(&"qi_only"))
	var restored := Actor.from_dict(qi_only.to_dict())
	assert_eq(restored.path(MindPath.PATH_ID) == null, true, "the mind path was never enrolled")
	assert_eq(
		restored.component(MindCultivationApi.SEA_COMPONENT) == null,
		true,
		"a round trip does not enrol an actor on the mind path"
	)
	assert_eq(MindCultivationApi.summary(restored).get("has_path"), false, "and the screen says so")
