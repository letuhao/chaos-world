extends TestCase

## The actor-builder seam at birth (ADR 0002, 0025, 0074, 0108).
##
## `resolve_offspring` is the only place a child is built, and it builds through a constructor
## `app/` injects. This suite holds BOTH halves of that claim, because the defect it exists for
## was invisible while only the first was tested:
##
## - **The injected path carries a spine.** A child minted by a builder that calls
##   `attach_core_resources` has a health pool and a stamina pool sized from its own derived
##   capacities, and is therefore damageable. Before the seam, `Actor.new` at `api.gd:147`
##   produced a child with NO pools: `Actor.change_resource` found no pool and did nothing, so a
##   newborn could not be hurt or healed and nothing said so.
## - **The un-injected path is byte-for-byte the old behaviour.** Every other fertility suite
##   drives birth with nothing installed, so if the default drifted, those suites would change
##   meaning. These tests assert that explicitly rather than relying on them to notice.
##
## The builder here is a local fixture that calls `Actor.attach_core_resources` — the core verb
## `ActorFactory.build` calls at `app/actor_factory.gd:12`. It is deliberately NOT `ActorFactory`:
## this suite is under `modules/`, and naming `app/` here would be the undeclared private-unit
## edge the gate exists to catch.

## What `_echo_builder` was last handed, so the builder-receives-the-inherited-base test can read
## it. Suite state, declared above the functions because `gdlint` holds a test file to the same
## `class-definitions-order` as any other script.
var _echoed_id: StringName = &""
var _echoed_base: Dictionary = {}


## The provider spine half a real composition root installs, reduced to what core can name.
## Installed over `set_actor_builder` for a test, never shipped.
func _core_spine_builder(actor_id: StringName, base: Dictionary) -> Actor:
	var actor := Actor.new(actor_id, base)
	actor.attach_core_resources()
	return actor


## A builder that ignores everything it is handed, so the tests can prove birth still reads the
## mother and the captured snapshot rather than trusting whatever comes back.
func _echo_builder(actor_id: StringName, base: Dictionary) -> Actor:
	_echoed_id = actor_id
	_echoed_base = base
	return Actor.new(actor_id, base)


func _parent(id: StringName, fertility: float, potency: float) -> Actor:
	var actor := (
		Actor
		. new(
			id,
			{
				Stat.PHYSIQUE: 10.0,
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				Stat.COMPREHENSION: 10.0,
				Stat.WILL: 10.0,
				Stat.FORTUNE: 10.0,
				DualCultivationApi.FERTILITY: fertility,
				DualCultivationApi.POTENCY: potency,
			}
		)
	)
	FertilityApi.attach(actor)
	return actor


## Carry the pregnancy to term and return the child, or null if it never resolves. Bounded by the
## same loop guard the other fertility suites use: a pregnancy that cannot reach LABOR is a bug,
## and the guard names it rather than spinning.
func _birth(mother: Actor) -> Actor:
	FertilityApi.advance(mother, 0.1)
	for _step in 400:
		var born := FertilityApi.advance(mother, 1.0)
		if not born.is_empty():
			return born[0]
	assert_ne(mother, null, "the pregnancy reached labor")
	return null


## Both parents hold physique 10 and comprehension/fortune 10, so the child's inherited base is
## `10 * 0.5 * offspring_quality` and then the born race's authored grant lands on top. Asserted
## rather than assumed, because these tests exist precisely to catch a child built from the wrong
## numbers.
func _conceive(race_roll: float = 0.5) -> Actor:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	FertilityApi.try_conceive(mother, father, 0.0, race_roll)
	return mother


func teardown() -> void:
	# `set_actor_builder` is process-wide static state and the runner calls this after EVERY
	# test, so a builder left installed would leak a spine into whatever suite runs next. This
	# is the same reason `test_domain_content.gd:224` restores its own.
	FertilityApi.set_actor_builder(Callable())


# ── 1. the injected builder, and the pools it buys ────────────────────────────


## **The headline.** The defect: a child born in play had no health pool and no stamina pool,
## because `api.gd:147` minted a bare `Actor` and `attach_core_resources` runs only inside
## `ActorFactory.build`. This asserts both pools exist AND carry a capacity derived from the
## child's own stats — a pool of the right name and the wrong size would still be a broken actor.
func test_a_child_built_through_the_injected_builder_carries_the_core_pools() -> void:
	FertilityApi.set_actor_builder(Callable(self, "_core_spine_builder"))
	var child := _birth(_conceive())
	assert_ne(child, null, "a child was born")
	assert_ne(child.resource(&"health"), null, "and it has a health pool")
	assert_ne(child.resource(&"stamina"), null, "and a stamina pool")
	assert_eq(
		child.resource(&"health").maximum,
		child.stats.derived(Stat.MAX_HEALTH),
		"the health pool's capacity is the child's own derived max_health"
	)
	assert_eq(
		child.resource(&"stamina").maximum,
		child.stats.derived(Stat.MAX_STAMINA),
		"and stamina's is its own derived max_stamina"
	)
	# Non-zero is the load-bearing half. `derived` answers a real number whether or not a pool
	# consumes it, so a derived capacity alone proves nothing — the pool has to be sized from it.
	assert_eq(
		child.stats.derived(Stat.MAX_HEALTH) > 0.0,
		true,
		"and that capacity is non-zero, so the pool is a body and not an empty slot"
	)
	assert_eq(
		child.resource(&"health").current > 0.0,
		true,
		"born alive: a fresh pool starts full (ADR 0025)"
	)


## The consequence stated as behaviour, not as a field check: a pooled child can be damaged and
## healed. `Actor.change_resource` on a poolless actor is a silent no-op, which is why the bug
## survived — nothing errored, nothing returned a failure, the number just never moved.
func test_an_injected_child_can_actually_be_damaged_and_healed() -> void:
	FertilityApi.set_actor_builder(Callable(self, "_core_spine_builder"))
	var child := _birth(_conceive())
	assert_ne(child, null, "a child was born")
	var full := child.resource(&"health").current
	child.change_resource(&"health", -25.0)
	assert_almost_eq(
		child.resource(&"health").current, full - 25.0, "damage lands on the child's health"
	)
	child.change_resource(&"health", 25.0)
	assert_almost_eq(child.resource(&"health").current, full, "and healing puts it back")


## The builder receives the child id and the INHERITED base, not an empty actor. If the seam
## were wired in the wrong order — after the base was computed, or with a default — the child
## would be raceless and statless at birth and would still pass the pool assertions above.
func test_the_builder_receives_the_child_id_and_the_inherited_base() -> void:
	FertilityApi.set_actor_builder(Callable(self, "_echo_builder"))
	var mother := _conceive()
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	assert_eq(_echoed_id, &"mother_offspring", "named for the mother, as before")
	assert_eq(_echoed_base.size() > 0, true, "and built from a non-empty inherited base")
	assert_almost_eq(
		float(_echoed_base.get(Stat.PHYSIQUE, 0.0)),
		(
			(
				float(mother.stats.get_base(Stat.PHYSIQUE))
				+ float(mother.stats.get_base(Stat.PHYSIQUE))
			)
			* 0.5
			* mother.stats.derived(FertilityStats.OFFSPRING_QUALITY)
		),
		"the base is the parents' average scaled by offspring_quality"
	)


# ── 2. the default path is unchanged ──────────────────────────────────────────


## Nothing is installed above, so this child is a bare `Actor` — and stays one. This is the
## promise the seam makes to every caller that never injects a builder, which is all of the
## other fertility suites. If a pool appeared here, an existing assertion somewhere else would
## have changed meaning and the suite would go quietly green rather than red.
func test_the_default_path_barely_behaves_exactly_as_before() -> void:
	var child := _birth(_conceive())
	assert_ne(child, null, "a child was born")
	assert_eq(child.resource(&"health"), null, "no health pool, exactly as before the seam")
	assert_eq(child.resource(&"stamina"), null, "and no stamina pool")
	assert_eq(child.id, &"mother_offspring", "the same id")
	assert_eq(child.resources.size(), 0, "and no resources at all")
	# The pre-existing contract: still a real `Actor`, built from the averaged base.
	assert_ne(RaceApi.race_of(child), &"", "still born into the baseline body")
	assert_eq(
		child.stats.get_base(Stat.PHYSIQUE) > 0.0, true, "and still built from the inherited base"
	)


## The seam is a static, so a builder installed by one call must not leak into the next. Teardown
## resets it for the other suites; this proves the seam itself has no hidden persistence, which is
## what makes the reset sufficient.
func test_clearing_the_builder_restores_the_bare_default_immediately() -> void:
	FertilityApi.set_actor_builder(Callable(self, "_core_spine_builder"))
	FertilityApi.set_actor_builder(Callable())
	var child := _birth(_conceive())
	assert_ne(child, null, "a child was born")
	assert_eq(child.resource(&"health"), null, "and is bare again, with no composition root")
	assert_eq(child.resource(&"stamina"), null, "both pools, gone")


## Lineage must not depend on the spine. Race and purity are resolved AFTER the child is minted
## (ADR 0108), so a builder that already carries a race ledger must not be able to pre-empt the
## birth roll — otherwise installing the seam would silently change who is born.
func test_the_injected_spine_does_not_change_who_is_born() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	RaceApi.attach(mother)
	RaceApi.attach(father)
	RaceApi.set_race(mother, &"stoneborn")
	RaceApi.set_race(father, &"tidecaller")
	BloodlineApi.attach(mother)
	BloodlineApi.attach(father)
	BloodlineApi.set_purity(mother, &"hearthborn", 1.0)
	BloodlineApi.set_purity(father, &"hearthborn", 1.0)
	FertilityApi.try_conceive(mother, father, 0.0, 0.5)

	# The same roll, once bare and once through the spine, must produce the same body.
	var bare := _birth(mother)
	var bare_race := RaceApi.race_of(bare)
	var bare_purity := BloodlineApi.purity_of(bare, &"hearthborn")

	FertilityApi.set_actor_builder(Callable(self, "_core_spine_builder"))
	var second_mother := _parent(&"mother", 20.0, 10.0)
	var second_father := _parent(&"father", 10.0, 20.0)
	RaceApi.attach(second_mother)
	RaceApi.attach(second_father)
	RaceApi.set_race(second_mother, &"stoneborn")
	RaceApi.set_race(second_father, &"tidecaller")
	BloodlineApi.attach(second_mother)
	BloodlineApi.attach(second_father)
	BloodlineApi.set_purity(second_mother, &"hearthborn", 1.0)
	BloodlineApi.set_purity(second_father, &"hearthborn", 1.0)
	FertilityApi.try_conceive(second_mother, second_father, 0.0, 0.5)
	var pooled := _birth(second_mother)

	assert_ne(pooled, null, "a child was born through the spine too")
	assert_ne(pooled.resource(&"health"), null, "and it has the pool the bare one lacked")
	assert_eq(RaceApi.race_of(pooled), bare_race, "born the same body as the bare child")
	assert_almost_eq(
		BloodlineApi.purity_of(pooled, &"hearthborn"),
		bare_purity,
		"and carrying the same inherited purity (ADR 0108)"
	)


# ── 3. lineage still lands, on the injected path ──────────────────────────────


## The regression guard for ADR 0108 stated in the positive: a child built through the spine is
## still EXACTLY ONE race and still carries the parents' blend of purity. The injected builder
## attaches providers before `resolve_race` and `set_purity` run, so this is the test that would
## catch the ordering being broken by the seam.
func test_an_injected_child_still_receives_its_race_and_purity() -> void:
	FertilityApi.set_actor_builder(Callable(self, "_core_spine_builder"))
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	RaceApi.attach(mother)
	RaceApi.attach(father)
	RaceApi.set_race(mother, &"stoneborn")
	RaceApi.set_race(father, &"tidecaller")
	BloodlineApi.attach(mother)
	BloodlineApi.attach(father)
	BloodlineApi.set_purity(mother, &"hearthborn", 1.0)
	BloodlineApi.set_purity(father, &"hearthborn", 1.0)
	FertilityApi.try_conceive(mother, father, 0.0, 0.5)

	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	var race_id := RaceApi.race_of(child)
	assert_eq(
		[&"stoneborn", &"tidecaller"].has(race_id),
		true,
		"exactly one of the two parents' bodies, never a mixture"
	)
	# Two pure parents give the one-generation ceiling, which is `inherit(1.0, 1.0)`.
	assert_almost_eq(
		BloodlineApi.purity_of(child, &"hearthborn"),
		0.745,
		"and the one-generation ceiling of the parents' shared lineage"
	)
	assert_ne(child.resource(&"health"), null, "with the core spine attached too")


## The mother is built by this suite, not by the seam, so her own pools are irrelevant to the
## child's — this pins which actor the spine landed on. A seam wired to the mother, or applied
## twice, would show up here.
func test_the_spine_lands_on_the_child_and_not_on_the_parents() -> void:
	FertilityApi.set_actor_builder(Callable(self, "_core_spine_builder"))
	var mother := _conceive()
	assert_eq(mother.resource(&"health"), null, "the mother is untouched by the builder")
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	assert_ne(child.resource(&"health"), null, "and only the child was given the spine")
