extends TestCase

## BL-0938: the mastery channel is BOTH saturating and capped.
##
## The finding: `practise` was free and unlimited and the provider multiplied mastery
## linearly, so a mortal could out-train the entire 30-realm ladder with no price and no
## ceiling (measured: ~61 free presses read `element_power_<e>` ~271x). The ruling bounds
## the OUTPUT with one shared saturation curve (power and crit) and the INPUT with a
## per-element cap keyed to the tier the body is preparing for — and the cap must keep
## the qi ladder's three authored element gates (900/1800/2700 at the tier rises)
## reachable ON ONE ELEMENT, which the `cap_at_rank` cases below prove against the
## authored seeds rather than against a copied number.

const FIRE := ElementStats.FIRE


func _actor(id: StringName, rank_id: StringName = &"qi_refining") -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.set_path(PathState.new(PathState.QI, rank_id))
	actor.set_affinity(FIRE, 10.0)
	ElementsApi.attach(actor)
	return actor


func _stock_elixir(actor: Actor, count: int) -> bool:
	ItemsApi.attach(actor, 64)
	var def := Crafting.resolve(ElementStats.mastery_elixir_id(FIRE))
	if def == null:
		return false
	ItemsApi.inventory(actor).add(def, count)
	return true


# --- the saturation curve -----------------------------------------------------------


## Bounds and shape: zero at zero, exactly half at `MASTERY_HALF`, strictly rising and
## strictly below 1.0 everywhere after. A curve that reached 1.0 would make the ceiling
## an arrival rather than an asymptote — and every further point must still pay.
func test_saturation_is_bounded_monotone_and_half_at_the_half() -> void:
	assert_eq(ElementMastery.saturation(0.0), 0.0, "no mastery, no term")
	assert_almost_eq(ElementMastery.saturation(-5.0), 0.0, "a negative reads zero")
	assert_almost_eq(
		ElementMastery.saturation(ElementMastery.MASTERY_HALF),
		0.5,
		"the half point is exactly half",
		1e-12
	)
	var previous := -1.0
	for mastery in [0.0, 1.0, 30.0, 300.0, 1200.0, 3000.0, 1.0e9]:
		var value := ElementMastery.saturation(mastery)
		assert_eq(value > previous, true, "strictly rising at %s" % mastery)
		assert_eq(value < 1.0, true, "and strictly below 1.0 at %s" % mastery)
		previous = value


# --- the cap is the rise the body is preparing for -----------------------------------


## The cap read at every band boundary: a mid-tier realm reads its own tier, and the
## LAST realm of a tier reads the next tier up — that is the mechanism that keeps each
## rise's authored gate reachable while a body is still standing below it.
func test_the_cap_reads_the_tier_the_body_is_preparing_for() -> void:
	assert_almost_eq(ElementMastery.cap_at_rank(&"qi_refining"), 600.0, "mortal")
	assert_almost_eq(ElementMastery.cap_at_rank(&"foundation"), 600.0, "mid mortal")
	assert_almost_eq(
		ElementMastery.cap_at_rank(&"tribulation"), 1200.0, "the mortal rise prepares spirit"
	)
	assert_almost_eq(ElementMastery.cap_at_rank(&"spirit_sea"), 1200.0, "spirit")
	assert_almost_eq(
		ElementMastery.cap_at_rank(&"spirit_ascension"), 2000.0, "the spirit rise prepares immortal"
	)
	assert_almost_eq(ElementMastery.cap_at_rank(&"earth_immortal"), 2000.0, "immortal")
	assert_almost_eq(
		ElementMastery.cap_at_rank(&"immortal_sovereign"),
		3000.0,
		"the immortal rise prepares transcendent"
	)
	assert_almost_eq(ElementMastery.cap_at_rank(&"transcendent"), 3000.0, "transcendent")
	assert_almost_eq(ElementMastery.cap_at_rank(&"unknown"), 600.0, "unknown reads tier 1")


## THE CONTRACT THE RULING NAMES: every authored element gate is reachable on ONE
## element. Read from the authored qi seeds (`element_mastery_required`), through the
## same facade read the qi gate takes, and compared against the cap at the realm a body
## attempts the rise from — so a content edit that raises a gate past its cap fails
## here rather than in a traversal minutes later.
func test_every_authored_element_gate_is_reachable_under_its_cap() -> void:
	var realms := RealmDefaults.ladder().realms()
	var checked := 0
	for index in range(1, realms.size()):
		var realm := realms[index]
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null or seed.element_mastery_required <= 0.0:
			continue
		var source := realms[index - 1]
		var cap := ElementMastery.cap_at_rank(source.id)
		assert_eq(
			cap >= seed.element_mastery_required,
			true,
			(
				"%s asks %s total mastery but a body standing in %s may hold only %s per element"
				% [realm.id, seed.element_mastery_required, source.id, cap]
			)
		)
		checked += 1
	assert_eq(checked, 3, "exactly the three authored rises carry the gate")


# --- the training verbs enforce the cap ----------------------------------------------


## A sitting below the cap lands ON it rather than past it and reports what it applied;
## a sitting at the cap refuses by NAME and writes nothing.
func test_a_sitting_lands_on_the_cap_and_then_refuses_by_name() -> void:
	var actor := _actor(&"bound_sitting")
	var cap := ElementMastery.cap_for(actor)
	var outcome := ElementsApi.practise(actor, FIRE, cap * 10.0)
	assert_eq(bool(outcome.get("ok", false)), true, "a huge sitting still lands")
	assert_almost_eq(
		ElementMastery.mastery_of(actor, FIRE), cap, "and lands exactly ON the cap", 1e-6
	)
	assert_almost_eq(float(outcome.get("gain", 0.0)), cap, "reporting what it applied", 1e-6)
	var refused := ElementsApi.practise(actor, FIRE, 25.0)
	assert_eq(bool(refused.get("ok", true)), false, "at the cap it refuses")
	assert_eq(String(refused.get("reason", "")), "mastery_capped", "by the cap's own name")
	assert_almost_eq(ElementMastery.mastery_of(actor, FIRE), cap, "and nothing moved", 1e-6)


## The elixir door obeys the same cap: at the cap it refuses BEFORE spending the item,
## so a drink at the bound costs the player nothing; one that would cross the cap lands
## exactly on it and is still spent, because the mastery moved.
func test_an_elixir_at_the_cap_refuses_without_consuming() -> void:
	var actor := _actor(&"bound_elixir")
	var elixir := ElementStats.mastery_elixir_id(FIRE)
	assert_eq(_stock_elixir(actor, 2), true, "the authored elixir resolves and is stocked")
	var inventory := ItemsApi.inventory(actor)
	ElementsApi.practise(actor, FIRE, 1.0e6)
	var before := inventory.count(elixir)
	var refused := ElementsApi.use_elixir(actor, FIRE)
	assert_eq(String(refused.get("reason", "")), "mastery_capped", "refused at the cap")
	assert_eq(inventory.count(elixir), before, "and nothing was consumed")


## A drink that would cross the cap applies only the remainder. The elixir is spent
## because the mastery moved, and the gain it reports is the remainder it actually paid.
func test_an_elixir_that_would_cross_the_cap_lands_on_it() -> void:
	var actor := _actor(&"bound_elixir_cross")
	assert_eq(_stock_elixir(actor, 1), true, "the authored elixir resolves and is stocked")
	var cap := ElementMastery.cap_for(actor)
	ElementsApi.practise(actor, FIRE, cap - 10.0)
	assert_almost_eq(
		ElementMastery.mastery_of(actor, FIRE), cap - 10.0, "ten below the bound", 1e-6
	)
	var outcome := ElementsApi.use_elixir(actor, FIRE)
	assert_eq(bool(outcome.get("ok", false)), true, "the drink lands")
	assert_almost_eq(float(outcome.get("gain", 0.0)), 10.0, "for the remainder", 1e-6)
	assert_almost_eq(ElementMastery.mastery_of(actor, FIRE), cap, "and lands ON the cap", 1e-6)


## The cap is PER ELEMENT and the gate reads TOTAL mastery: two elements can each hold
## the cap, which is the breadth the total-mastery ladder pays for.
func test_the_cap_is_per_element_not_a_shared_budget() -> void:
	var actor := _actor(&"bound_breadth")
	actor.set_affinity(ElementStats.WATER, 10.0)
	ElementsApi.practise(actor, FIRE, 1.0e6)
	ElementsApi.practise(actor, ElementStats.WATER, 1.0e6)
	var cap := ElementMastery.cap_for(actor)
	assert_almost_eq(ElementMastery.mastery_of(actor, FIRE), cap, "fire at its own cap", 1e-6)
	assert_almost_eq(
		ElementMastery.mastery_of(actor, ElementStats.WATER), cap, "water at its own cap", 1e-6
	)
	assert_almost_eq(
		ElementMastery.total_mastery(actor), cap * 2.0, "and the total sums both", 1e-6
	)


# --- the ceiling is an asymptote in the provider -------------------------------------


## The provider's power term is bounded by `1 + POWER_CEILING` times the affinity at
## every tier, and the crit term reaches its paired `CRIT_MASTERY_CEILING`: absurd
## mastery cannot exceed either, which is the whole point of the bond.
func test_the_provider_ceilings_are_asymptotes_that_mastery_cannot_cross() -> void:
	var actor := Actor.new(&"ceiling", {ElementStats.mastery_id(FIRE): 1.0e9})
	actor.set_affinity(FIRE, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(FIRE)),
		10.0 * (1.0 + ElementProvider.POWER_CEILING),
		"the tier-1 power asymptote",
		1e-3
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.crit_id(FIRE)),
		(
			ElementProvider.CRIT_BASE
			+ 10.0 * ElementProvider.CRIT_AFFINITY_STEP
			+ ElementProvider.CRIT_MASTERY_CEILING
		),
		"the crit asymptote",
		1e-3
	)
