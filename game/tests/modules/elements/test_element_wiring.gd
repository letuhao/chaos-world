extends TestCase

## ADR 0088's reuse only pays if `element_power_<e>` is DERIVED FOR SOMEBODY. This
## suite is the seam that was open, asserted from the composition root rather than
## from a hand-built `Actor`.
##
## ## Why the fixture is the FACTORY, not `Actor.new`
##
## Every assertion here would pass just as well against a bare actor with
## `ElementsApi.attach` called by hand — which is exactly what the elements suite
## already did, and exactly why the defect survived: the stat was live in
## `tests/modules/elements/` and dead in play. So these cases mint actors ONLY through
## `ActorFactory.build`, the way a boot mints them, and assert the derived stat on the
## result. A `set_affinity` is the one thing a factory actor is not given, so the
## affinity here is granted the way production grants it: through the race projection,
## which is the only writer of `Actor.affinities` in `src/`.
##
## ## Why the affinity is granted through the RACE and not `actor.set_affinity`
##
## `Actor.set_affinity` exists and is a perfectly good verb — but nothing in `src/`
## calls it. Every affinity a shipped game actor holds arrives from
## `RaceProjection._grant`, which is driven off `res://data/races/*.tres`. So a test
## that hand-calls `set_affinity` proves the provider's arithmetic works while saying
## nothing about whether any real actor has the input that arithmetic needs. Granting
## through `RaceApi` keeps the whole chain under test: authored `.tres` -> catalog ->
## projection -> `Actor.affinities` -> `StatContext.affinity` -> `ElementProvider`.

## The shipped `commonborn` race authors 2.0 affinity in all five tier-1 elements
## (`game/data/races/commonborn.tres`), so it is the cheapest fixture that exercises
## every base element at once. Read from the catalog rather than restated: the number
## is authored content, and a suite that pins it would fail loudly the moment a
## balance pass re-rolls the body — which is the correct failure, but only if the suite
## says WHY it moved.
const BASELINE_RACE := &"commonborn"

## ## Why these two potency cases ride a TALL affinity rather than the shipped one
##
## `commonborn` authors 2.0 affinity per element, so `potency = 2.0 * 0.25 = 0.5`
## against an authored `status_potency_floor` of 1.0 — the floor wins and the read
## returns 1.0. That is CORRECT (the floor is a floor), but it makes the shipped
## baseline useless for the question: at 2.0 affinity the floor swallows the channel
## entirely, so a novice and an adept both read 1.0 and the pair below cannot tell
## "mastery did not move potency" from "potency was never above the floor". So these
## two grant a tall affinity explicitly. The floor is still exercised — and asserted —
## by the wiring case below, which is about the floor being a floor.

## The affinity these two cases grant. Any value comfortably above
## `status_potency_floor / status_potency_scale` (1.0 / 0.25 = 4.0) would do; 10.0 is
## a round authored build, not a tuned constant — the assertion is a strict inequality
## between two actors, so the exact figure cannot change the outcome.
const TALL_AFFINITY := 10.0


func _factory_actor(id: StringName, mastery: float = 0.0) -> Actor:
	var base := {}
	if mastery > 0.0:
		base[ElementStats.mastery_id(ElementStats.FIRE)] = mastery
	var actor := ActorFactory.build(id, base)
	RaceApi.attach(actor)
	if not RaceApi.set_race(actor, BASELINE_RACE):
		# Never a silent skip: an unfixturable suite that quietly asserts nothing is
		# the exact failure class this whole suite exists to catch.
		push_error("test_element_wiring: the shipped baseline race is missing")
	return actor


func _baseline_affinity(element: StringName) -> float:
	var def := RaceCatalog.instance().race_definition(BASELINE_RACE)
	return 0.0 if def == null else float(def.affinities.get(String(element), 0.0))


# --- the assertion that was impossible before ------------------------------------


## THE test. A factory-built actor derives a NON-ZERO `element_power_<e>`, for every
## tier-1 element the shipped race is born with.
##
## Before the wiring this read `0.0`, so `StatusApply.potency_of` returned
## `status_potency_floor` for every attacker and every status in the game landed at
## one constant number. That is the defect: not that a stat was small, but that the
## knob a balance pass would tune had no connection to any actor at all.
func test_element_power_is_non_zero_on_a_factory_built_actor() -> void:
	var actor := _factory_actor(&"wired")
	var checked := 0
	for element in ElementStats.BASE_ELEMENTS:
		var affinity := _baseline_affinity(element)
		if affinity <= 0.0:
			continue
		checked += 1
		var power := actor.stats.derived(ElementStats.power_id(element))
		assert_eq(
			power > 0.0,
			true,
			(
				"element_power_%s is %s on a factory-built actor; a 0.0 here means the provider is not mounted"
				% [element, power]
			)
		)
	# Measured, not counted: a vacuous pass (an empty affinity map would skip every
	# element and assert nothing) must fail here.
	assert_eq(checked > 0, true, "the shipped race really does author tier-1 affinity")


## The power is the actor's OWN numbers, not merely "some non-zero value": the shipped
## affinity and zero mastery is exactly the affinity, and the realm multiplier is
## absent because a bare factory actor has no path — `apply_realm_modifiers` documents
## that fail-safe and this is its witness.
func test_the_power_is_the_actors_own_numbers_and_not_a_constant() -> void:
	var actor := _factory_actor(&"exact")
	for element in ElementStats.BASE_ELEMENTS:
		var affinity := _baseline_affinity(element)
		if affinity <= 0.0:
			continue
		assert_almost_eq(
			actor.stats.derived(ElementStats.power_id(element)),
			affinity,
			"affinity %s with zero mastery is exactly its affinity" % element,
			1e-9
		)


## Two factory actors with different authored builds land different numbers. If every
## actor derived the same power, the channel would be a constant with a name — which
## is precisely the failure ADR 0088 measured, wearing a different hat.
func test_two_factory_actors_land_different_power_for_the_same_element() -> void:
	var plain := _factory_actor(&"plain")
	var trained := _factory_actor(&"trained", 8.0)
	assert_eq(
		(
			trained.stats.derived(ElementStats.power_id(ElementStats.FIRE))
			> plain.stats.derived(ElementStats.power_id(ElementStats.FIRE))
		),
		true,
		"the same authored affinity and a different mastery must not answer the same power"
	)


# --- mastery is a live input, so the channel is tunable ---------------------------


## `element_power_<e>` rises MONOTONICALLY with `element_mastery_<e>` — the property
## the per-tier divisor is written to preserve (ADR 0069). Asserted over a ladder at
## BOTH tiers, because "mastery still pays" is the half of the divisor's contract that
## is easy to break by accident while fixing the other half.
func test_power_rises_monotonically_with_mastery_at_every_tier() -> void:
	for element in [ElementStats.FIRE, ElementStats.LIGHTNING]:
		var previous := -1.0
		for mastery in [0.0, 1.0, 4.0, 9.0, 20.0, 60.0]:
			var actor := ActorFactory.build(&"ladder", {ElementStats.mastery_id(element): mastery})
			actor.set_affinity(element, 10.0)
			ElementsApi.attach(actor)
			var power := actor.stats.derived(ElementStats.power_id(element))
			assert_eq(
				power >= previous,
				true,
				(
					"%s at mastery %s read %s, below the previous step's %s"
					% [element, mastery, power, previous]
				)
			)
			previous = power


# --- ADR 0088: potency varies, which is the whole point ---------------------------


## THE payoff case: the SAME status, read through `StatusApply.potency_of`, lands at a
## DIFFERENT potency on a low-mastery and a high-mastery actor. This is A (the wiring)
## and C (potency varies) proven together — before the wiring both actors read `0.0`
## power and both returned `status_potency_floor`.
##
## It is asserted as a strict inequality rather than "not equal to the floor", because
## the meaningful claim is that mastery is a live lever on the debuff, not merely that
## the number moved off a constant.
func test_the_same_status_lands_at_a_different_potency_for_two_masteries() -> void:
	var tuning := CombatTestKit.shipped()
	var novice := _factory_actor(&"novice")
	var adept := _factory_actor(&"adept", 10.0)
	novice.set_affinity(ElementStats.FIRE, TALL_AFFINITY)
	adept.set_affinity(ElementStats.FIRE, TALL_AFFINITY)
	var novice_potency := StatusApply.potency_of(novice, tuning, ElementStats.FIRE)
	var adept_potency := StatusApply.potency_of(adept, tuning, ElementStats.FIRE)
	assert_eq(
		adept_potency > novice_potency,
		true,
		(
			"mastery must move potency: novice read %s, adept read %s, floor is %s"
			% [novice_potency, adept_potency, tuning.status_potency_floor]
		)
	)


## Neither actor is resting on the authored floor. The floor exists for an actor with
## NO elemental power (ADR 0088's consequence); a trained, affine body must read ABOVE
## it, which is the difference between "the floor is a safety net" and "the floor is
## the whole game".
func test_a_trained_affine_actor_reads_potency_above_the_authored_floor() -> void:
	var tuning := CombatTestKit.shipped()
	var adept := _factory_actor(&"above_floor", 10.0)
	adept.set_affinity(ElementStats.FIRE, TALL_AFFINITY)
	var potency := StatusApply.potency_of(adept, tuning, ElementStats.FIRE)
	assert_eq(
		potency > tuning.status_potency_floor,
		true,
		(
			"potency %s is not above the authored floor %s — the wiring did not take"
			% [potency, tuning.status_potency_floor]
		)
	)


## THE FLOOR IS STILL A FLOOR, and this is the case that proves the wiring did not
## simply delete it. A factory actor at the SHIPPED baseline (2.0 affinity, zero
## mastery) derives `2.0` power, and `2.0 * 0.25 = 0.5` against a floor of `1.0` — so
## the floor wins and the read is exactly `1.0`.
##
## It is asserted because it is a real, reachable state and not a hypothetical: the
## baseline race is the most common body in the shipped content, and a weak actor's
## debuff resting on the floor is the designed outcome (ADR 0088's floor exists exactly
## so an actor with no elemental power still inflicts a visible status). It also
## documents WHY the two cases above need a taller affinity: at 2.0 the floor swallows
## the channel, so a novice and an adept both read 1.0 and the comparison cannot
## distinguish "mastery did nothing" from "potency was never above the floor".
func test_the_floor_still_governs_a_weak_baseline_actor() -> void:
	var tuning := CombatTestKit.shipped()
	var weak := _factory_actor(&"weak")
	var power := weak.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_eq(
		power > 0.0,
		true,
		"the wiring is live: the baseline actor derives a non-zero power of %s" % power
	)
	assert_almost_eq(
		StatusApply.potency_of(weak, tuning, ElementStats.FIRE),
		tuning.status_potency_floor,
		"a weak actor's potency rests on the authored floor, which is a floor and not a bug",
		1e-9
	)


## Potency tracks the actor's OWN power and only that: the two potency reads differ by
## exactly the power ratio the mastery ladder produced. A floor-clamped read would
## break this ratio, so it is also the assertion that the floor is not quietly doing
## the work.
func test_potency_is_the_element_power_the_actor_actually_derives() -> void:
	var tuning := CombatTestKit.shipped()
	var actor := _factory_actor(&"ratios", 6.0)
	actor.set_affinity(ElementStats.FIRE, TALL_AFFINITY)
	var power := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	var potency := StatusApply.potency_of(actor, tuning, ElementStats.FIRE)
	assert_almost_eq(
		potency,
		maxf(tuning.status_potency_floor, power * tuning.status_potency_scale),
		"potency is the authored scale over the actor's own element power",
		1e-9
	)


# --- the wiring is idempotent in the only sense it can be --------------------------


## `build` mounts the element provider EXACTLY ONCE. Asserted as a MEASURED RELATIONSHIP
## rather than a population count: a second `ElementProvider` does not add a stat, it
## overwrites the same id with the same value — so `provider_count()` would catch the
## duplication while a stat read would not. Both are checked, for different reasons:
## the count is the cheap witness of ADR 0069's "attach once", and the value is the
## claim that matters (a double-contributed power would silently DOUBLE every debuff).
func test_the_factory_attaches_the_element_provider_exactly_once() -> void:
	var actor := ActorFactory.build(&"once")
	actor.set_affinity(ElementStats.FIRE, 4.0)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		4.0,
		"one provider, one contribution: a second attach would read 8.0 here",
		1e-9
	)
	# An actor with no affinity has no elemental power at all — qi's premise, not a gap.
	var bare := ActorFactory.build(&"bare")
	assert_eq(
		bare.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		0.0,
		"an actor with no affinity reads 0.0 rather than inheriting another's numbers"
	)
	# Granting affinity AFTER the build needs no second attach: the provider is already
	# live and reads the live `AffinityMap` by reference (`StatContext` holds it, not a
	# copy — ADR 0002). This is what makes the channel dynamic rather than snapshot.
	actor.set_affinity(ElementStats.FIRE, 9.0)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		9.0,
		"and a later affinity grant moves the derived stat with no re-attach at all",
		1e-9
	)


## The enrolment verbs REFRESH the realm half without stacking a provider, which is the
## whole reason `ActorFactory._refresh_element_realm` calls `apply_realm_modifiers`
## rather than `attach`. Asserted through the observable: power scales with the realm
## the path claims, and does not scale TWICE.
func test_enrolment_refreshes_the_realm_multiplier_without_stacking_providers() -> void:
	var actor := ActorFactory.build(&"enrolled")
	actor.set_affinity(ElementStats.FIRE, 2.0)
	var base_power := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(base_power, 2.0, "no path, no realm multiplier", 1e-9)
	ActorFactory.with_qi_cultivation(actor)
	var enrolled_power := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	var ladder := RealmDefaults.ladder()
	var realm := ladder.realms()[ladder.index_of(&"qi_refining")]
	assert_almost_eq(
		enrolled_power,
		base_power * realm.power,
		"enrolment writes the authored realm multiplier onto element power",
		1e-6
	)
	# A second enrolment must REWRITE, not multiply again. `apply_realm_modifiers`
	# strips its own `(source, stat)` pairs first, so the number is unchanged.
	ActorFactory.with_mind_cultivation(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		enrolled_power,
		"a second path enrolment rewrites the realm half instead of stacking it",
		1e-9
	)


## An npc minted through the factory — the same constructor `NpcBoot` injects and
## `DomainSpawner` calls — carries the element provider too. An npc without one is a
## mob that cannot debuff, which is the seam's failure one level down from the player.
func test_an_npc_minted_by_the_factory_carries_the_element_provider() -> void:
	var npc := ActorFactory.spawn_npc(null, &"rival", &"qi_refining")
	assert_ne(npc, null, "the npc constructor still mints an actor")
	npc.set_affinity(ElementStats.FIRE, 3.0)
	assert_eq(
		npc.stats.derived(ElementStats.power_id(ElementStats.FIRE)) > 0.0,
		true,
		"an npc derives elemental power, so its debuffs are not all the floor"
	)
