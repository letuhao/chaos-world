extends TestCase

## The root-refining arts (ADR 0924, BL-0926): the app-side pair of loops. The
## OPENING applies once when the art is learned, through the wrapped learner the app
## installs; the REFINE is the repeatable +1 that runs to the per-element cap. Both
## are registered sources, so the module and the screen treat them like any other.

const FIRE := ElementStats.FIRE
const VOID := ElementStats.VOID


func setup() -> void:
	ElementsApi.clear_registered_sources()
	ElementArts.install()


func teardown() -> void:
	ElementsApi.clear_registered_sources()


## A scholar whose qi path can pay a study charge — the fixture
## `test_technique_study_cost.gd` documents — stood where an art's floor is met.
func _hero(realm_id: StringName = &"foundation") -> Actor:
	var actor := Actor.new(&"root_refiner", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.path(PathState.QI).progress = 100000.0
	TechniquesApi.attach(actor)
	ElementsApi.attach(actor)
	ItemsApi.attach(actor, 64)
	return actor


## THE AUTHORED FAMILY: every element ships its art and its manual, and the art
## claims the manual that delivers it.
func test_every_element_ships_its_art_and_manual() -> void:
	for entry in ElementDefaults.all():
		var def := entry as ElementDef
		var art := TechniqueCatalog.instance().definition(ElementArts.art_id(def.id))
		assert_ne(art, null, "an art for %s" % String(def.id))
		if art == null:
			continue
		assert_eq(art.delivered_by, ElementArts.manual_id(def.id), "delivered by its manual")
		assert_eq(art.active, false, "a passive")
		assert_ne(Crafting.resolve(ElementArts.manual_id(def.id)), null, "the manual resolves")


## THE OPENING LOOP: learning the art opens the root once, through the exact learner
## the app installs.
func test_learning_the_art_opens_the_root_once() -> void:
	var actor := _hero()
	assert_eq(ElementTraining.can_practise(actor, FIRE), false, "no fire spark yet")
	var outcome := ElementArts.learn_with_root_grant(actor, ElementArts.art_id(FIRE))
	assert_eq(bool(outcome.get("ok", false)), true, "the art is learned")
	assert_almost_eq(actor.affinities.get_value(FIRE), 2.0, "and the opening lands", 1e-6)
	assert_eq(ElementTraining.can_practise(actor, FIRE), true, "the spark is real")
	var again := ElementArts.grant_on_learn(actor, ElementArts.art_id(FIRE))
	assert_eq(bool(again.get("ok", false)), false, "the opening does not repeat")
	assert_almost_eq(actor.affinities.get_value(FIRE), 2.0, "and nothing more was written", 1e-6)


## THE REFINE LOOP: with the art learned and no items held, Attune spends the art's
## refine source — +1 a press, to the cap.
func test_the_refine_runs_to_the_cap_one_step_a_press() -> void:
	var actor := _hero()
	var learned := ElementArts.learn_with_root_grant(actor, ElementArts.art_id(FIRE))
	assert_eq(bool(learned.get("ok", false)), true, "the art is learned")
	assert_almost_eq(actor.affinities.get_value(FIRE), 2.0, "the opening landed", 1e-6)
	var pressed := 0
	for index in 20:
		var result := ElementsApi.attune(actor, FIRE)
		if not bool(result.get("ok", false)):
			assert_eq(
				String(result.get("reason", "")), ElementAttunement.R_AT_CAP, "the cap is the stop"
			)
			break
		pressed += 1
	assert_eq(pressed, 10, "ten refinements fill the tier-1 root from the opening")
	assert_almost_eq(actor.affinities.get_value(FIRE), 12.0, "at the tier-1 cap", 1e-6)


## The opening waits for the climb: an art learned on a body whose ELEMENTAL rank has
## not reached the tier is refused by the element door's own name, and the art stays
## learned for when it does.
func test_the_opening_waits_for_the_elemental_climb() -> void:
	var actor := _hero(&"dao_ancestor")
	var outcome := ElementArts.learn_with_root_grant(actor, ElementArts.art_id(VOID))
	assert_eq(bool(outcome.get("ok", false)), true, "the art is learned")
	assert_almost_eq(actor.affinities.get_value(VOID), 0.0, "but the grant waits", 1e-9)
	assert_eq(
		String(ElementArts.grant_on_learn(actor, ElementArts.art_id(VOID)).get("reason", "")),
		ElementAttunement.R_LOCKED,
		"and the refusal is the element door's own"
	)


## A re-install (the app runs it per actor build) leaves one source per id, not two.
func test_install_is_idempotent() -> void:
	var actor := _hero()
	ElementArts.learn_with_root_grant(actor, ElementArts.art_id(FIRE))
	ElementArts.install()
	var refine_count := 0
	for source in ElementAttunement.offers(actor, FIRE):
		if source.id == ElementArts.refine_id(ElementArts.art_id(FIRE)):
			refine_count += 1
	assert_eq(refine_count, 1, "a re-install leaves one refine source")


## The wrapper grants nothing for a technique that is not an art: learning an
## ordinary passive still works and writes no affinity.
func test_a_non_art_learn_grants_nothing() -> void:
	var actor := _hero(&"spirit_sea")
	var outcome := ElementArts.learn_with_root_grant(actor, &"passive_marrow_circulation")
	assert_eq(bool(outcome.get("ok", false)), true, "an ordinary passive still learns")
	assert_almost_eq(actor.affinities.get_value(FIRE), 0.0, "and grants no root", 1e-9)
