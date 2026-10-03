extends TestCase

## ADR 0002/0108: fertility owns conception -> gestation -> birth, and birth is where the
## lineage stack runs. A child must be a real function of WHO conceived it: one race, resolved
## from the parents, and a per-lineage purity that is the blend of both parents'.


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


## Carry the whole pregnancy to term and return the child, or `null` if it never resolves.
## Bounded by the loop guard the repo requires: a pregnancy that cannot reach LABOR is a bug,
## and the guard names it rather than spinning.
func _birth(mother: Actor) -> Actor:
	FertilityApi.advance(mother, 0.1)
	for _step in 400:
		var born := FertilityApi.advance(mother, 1.0)
		if not born.is_empty():
			return born[0]
	assert_ne(mother, null, "the pregnancy reached labor")
	return null


# --- The state machine, unchanged ---------------------------------------------


func test_conception_on_low_roll() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	assert_eq(FertilityApi.try_conceive(mother, father, 0.0), true, "conceived")
	assert_eq(mother.has_status(FertilityStats.PREGNANCY), true, "pregnancy status")


func test_conception_blocked_on_high_roll() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	assert_eq(FertilityApi.try_conceive(mother, father, 1.0), false, "no conception")


func test_cannot_conceive_while_pregnant() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	FertilityApi.try_conceive(mother, father, 0.0)
	assert_eq(FertilityApi.try_conceive(mother, father, 0.0), false, "already pregnant")


func test_gestation_reaches_labor_and_birth() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	FertilityApi.try_conceive(mother, father, 0.0)
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	# Both parents hold physique 10, so the averaged base is 10. `offspring_quality` reads
	# `1.0 + (comprehension + fortune) * 0.01 = 1.2` on these parents, giving 12.0 — and the
	# child is then born `commonborn`, whose authored grant adds a further +1. The two are
	# separate on purpose (ADR 0108): a body plan is not a stat stick, so its grant lands on
	# top of the inherited average rather than being folded into it.
	assert_almost_eq(
		child.stats.get_base(Stat.PHYSIQUE), 13.0, "inherited physique plus the body's grant"
	)
	assert_eq(
		RaceApi.race_of(child), RaceCatalog.instance().baseline_race(), "born the baseline body"
	)


# --- Birth resolves a body (ADR 0062/0108) -------------------------------------


func test_a_child_is_born_exactly_one_race_and_never_a_blend() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	RaceApi.attach(mother)
	RaceApi.attach(father)
	RaceApi.set_race(mother, &"stoneborn")
	RaceApi.set_race(father, &"tidecaller")
	FertilityApi.try_conceive(mother, father, 0.0, 0.5)
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	var race_id := RaceApi.race_of(child)
	assert_ne(race_id, &"", "the child has a race at all")
	assert_eq(
		[&"stoneborn", &"tidecaller"].has(race_id),
		true,
		"and it is one of the two parents', never a mixture"
	)


func test_a_child_of_two_parents_with_no_race_is_still_born_a_race() -> void:
	# Nothing contests, so the catalog baseline answers — no actor is ever born raceless,
	# which keeps every downstream gate answerable.
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	FertilityApi.try_conceive(mother, father, 0.0, 0.5)
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	assert_ne(RaceApi.race_of(child), &"", "and carries the baseline body plan")


func test_birth_is_reproducible_for_the_same_roll() -> void:
	# The same conception resolved twice must produce the same child, which is what makes
	# birth headless-testable at all.
	var runs: Array[StringName] = []
	for _attempt in 2:
		var mother := _parent(&"mother", 20.0, 10.0)
		var father := _parent(&"father", 10.0, 20.0)
		RaceApi.attach(mother)
		RaceApi.attach(father)
		RaceApi.set_race(mother, &"stoneborn")
		RaceApi.set_race(father, &"tidecaller")
		FertilityApi.try_conceive(mother, father, 0.0, 0.75)
		var child := _birth(mother)
		runs.append(RaceApi.race_of(child))
	assert_eq(runs[0], runs[1], "the same roll gives the same body both times")


func test_the_race_roll_actually_decides_the_body() -> void:
	var bodies := {}
	for roll in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var mother := _parent(&"mother", 20.0, 10.0)
		var father := _parent(&"father", 10.0, 20.0)
		RaceApi.attach(mother)
		RaceApi.attach(father)
		RaceApi.set_race(mother, &"stoneborn")
		RaceApi.set_race(father, &"tidecaller")
		FertilityApi.try_conceive(mother, father, 0.0, roll)
		var child := _birth(mother)
		bodies[String(RaceApi.race_of(child))] = true
	assert_eq(bodies.size(), 2, "the roll moves the outcome between both parents")


# --- Birth resolves inherited purity (ADR 0063/0108) -------------------------


func test_a_child_inherits_the_blend_of_both_parents_purity() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	BloodlineApi.attach(mother)
	BloodlineApi.attach(father)
	BloodlineApi.set_purity(mother, &"hearthborn", 1.0)
	BloodlineApi.set_purity(father, &"hearthborn", 1.0)
	FertilityApi.try_conceive(mother, father, 0.0)
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	# Two pure parents give the one-generation ceiling, which is `inherit(1.0, 1.0)`.
	assert_almost_eq(
		BloodlineApi.purity_of(child, &"hearthborn"),
		0.745,
		"and the child carries the one-generation ceiling"
	)


func test_a_lineage_only_one_parent_carries_still_reaches_the_child_diluted() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	BloodlineApi.attach(mother)
	BloodlineApi.attach(father)
	BloodlineApi.set_purity(mother, &"hearthborn", 0.6)
	FertilityApi.try_conceive(mother, father, 0.0)
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	# One-sided: `inherit(0.6, 0.0) = 0.6 * 0.35 + 0.045 = 0.255`. The mean is what makes an
	# outsider spouse a real cost.
	assert_almost_eq(
		BloodlineApi.purity_of(child, &"hearthborn"), 0.255, "diluted by the absent parent"
	)


func test_a_child_of_two_lineageless_parents_carries_no_lineage_at_all() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	BloodlineApi.attach(mother)
	BloodlineApi.attach(father)
	FertilityApi.try_conceive(mother, father, 0.0)
	var child := _birth(mother)
	assert_ne(child, null, "a child was born")
	assert_eq(FertilityApi.purity_snapshot(child).keys().size(), 0, "and no ancestry was invented")


func test_birth_does_not_depend_on_the_partner_still_existing() -> void:
	# The partner's race and purity are SNAPSHOT at conception. A child can be born long
	# after the partnership ends, so reading a live partner would make the outcome depend on
	# who happens to still be around.
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
	FertilityApi.try_conceive(mother, father, 0.0, 1.0)
	# The father goes out of scope entirely before birth; the snapshot is all that remains.
	father = null
	var child := _birth(mother)
	assert_ne(child, null, "the pregnancy still resolved")
	assert_almost_eq(
		BloodlineApi.purity_of(child, &"hearthborn"), 0.745, "from the captured snapshot"
	)


# --- Reproduction parameters come from the race (ADR 0062) --------------------


func test_gestation_length_is_read_from_the_mothers_race() -> void:
	# `stoneborn` authors a longer gestation than the default, so its pregnancy must take
	# more steps at the same delta. That is the proof `SpeciesDef` is genuinely gone and the
	# body plan is now the single source of reproduction data.
	var mother := _parent(&"mother", 20.0, 10.0)
	RaceApi.attach(mother)
	RaceApi.set_race(mother, &"stoneborn")
	var authored := RaceApi.race_definition(mother).gestation_days
	assert_eq(authored > FertilityStats.DEFAULT_GESTATION_DAYS, true, "stoneborn is slower")
	var status := PregnancyStatus.new(FertilityStats.PREGNANCY)
	status.stage = PregnancyStatus.Stage.GESTATING
	mother.add_status(status)
	var before := status.progress
	FertilityApi.advance(mother, 1.0)
	var one_day := status.progress - before
	assert_almost_eq(
		one_day,
		mother.stats.derived(FertilityStats.GESTATION_SPEED) / authored,
		"one day of a stoneborn gestation"
	)
