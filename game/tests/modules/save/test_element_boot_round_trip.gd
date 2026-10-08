extends TestCase

## BL-0929: the ELEMENT state must survive a BOOT, not merely a payload round trip.
##
## ## What is asserted, and why each is separate
##
## The element system's state is three things in three places: `element_mastery_<e>` is a
## base stat (core serialises it), the affinity map is core's own, and an attunement's
## spent-`once` record rides `module_data`. The payload suites prove the first two; what
## they do not prove is the composition root's re-attach — the `ElementProvider` that
## turns the stat and the map into `element_power_<e>` — which is the seam
## `test_cultivation_boot_round_trip.gd` documents for mind. This suite boots the shipped
## scene for the same reason.

const FIRE := ElementStats.FIRE

var _born: Array = []


func setup() -> void:
	_clear_disk()
	SaveApi.reset_clock()
	ElementsApi.clear_registered_sources()


func teardown() -> void:
	# The harness mounts the REAL scene under the tree root, so it owns Nodes and must be
	# freed; a test that aborted mid-function would otherwise leak a whole app into the
	# next. The actor cycle is broken the way `test_cultivation_boot_round_trip` does it.
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	for born in _born:
		var body := born as Actor
		if body != null:
			body.resources.clear()
	_born.clear()
	ElementsApi.clear_registered_sources()
	_clear_disk()
	SaveApi.reset_clock()


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


## A hero the composition root can restore: the factory plus the enrolment verbs the app
## itself uses.
func _hero() -> Actor:
	var hero := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	hero.attach_core_resources()
	ActorFactory.with_body_cultivation(hero)
	ActorFactory.with_qi_cultivation(hero)
	ElementsApi.apply_realm_modifiers(hero)
	ItemsApi.attach(hero, 200)
	return hero


## Train and open a root through the shipped verbs: one treasure attune, one practise
## sitting, and one ONCE source spent (the arts' shape), so every kind of element state
## is non-default before the save.
func _prepare(hero: Actor) -> void:
	ItemsApi.inventory(hero).add(Crafting.resolve(ElementAttunement.treasure_id(FIRE)), 1)
	assert_eq(bool(ElementsApi.attune(hero, FIRE).get("ok", false)), true, "the treasure opens")
	# Registered AFTER the treasure, because `attune` picks the BIGGEST available source:
	# with the once source live first, the treasure press would spend it instead.
	var always := func(_who: Actor) -> bool: return true
	var keep := func(_who: Actor) -> bool: return true
	ElementsApi.register_affinity_source(
		AffinitySource.make(&"boot:once", FIRE, 3.0, 1, "Boot Test", true, always, keep)
	)
	var once_result := ElementsApi.attune_source(hero, &"boot:once")
	assert_eq(
		bool(once_result.get("ok", false)),
		true,
		"and the once source opens further (%s)" % String(once_result.get("reason", ""))
	)
	assert_eq(
		bool(ElementsApi.practise(hero, FIRE, 25.0).get("ok", false)), true, "and a sitting trains"
	)


## The element state of `actor`, as the roster and the module's own record publish it.
func _element_state(actor: Actor) -> Dictionary:
	var row := {}
	for entry in ElementsApi.roster(actor):
		var candidate := entry as Dictionary
		if StringName(candidate.get("id", "")) == FIRE:
			row = candidate
	return {
		"mastery": float(row.get("mastery", -1.0)),
		"affinity": float(row.get("affinity", -1.0)),
		"spent": actor.get_module_data(ElementAttunement.MODULE_KEY).get("spent", []),
	}


func test_mastery_and_an_opened_root_survive_a_boot() -> void:
	var hero := _hero()
	_prepare(hero)
	var expected := _element_state(hero)
	assert_eq(float(expected["mastery"]) > 0.0, true, "the fixture really trained")
	assert_eq(float(expected["affinity"]) > 0.0, true, "and really opened a root")
	assert_eq((expected["spent"] as Array).has("boot:once"), true, "and really spent a once source")
	_born.append(hero)
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")

	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the shipped scene booted")
	if harness.boot_error != "":
		return
	var booted := harness.actor
	assert_ne(booted == null, true, "the boot produced a body")
	if booted == null:
		return
	assert_ne(booted == hero, true, "the booted body is rebuilt from the payload, not reused")

	var state := _element_state(booted)
	assert_almost_eq(
		float(state["mastery"]), float(expected["mastery"]), "the mastery survived the boot", 0.001
	)
	assert_almost_eq(
		float(state["affinity"]), float(expected["affinity"]), "and the opened root", 0.001
	)
	assert_eq(
		(state["spent"] as Array).has("boot:once"),
		true,
		"and the once record, so a save cannot re-open the art's grant"
	)
	# The PROVIDER, not the stat: `Actor.from_dict` restores the base stat and the map, so
	# every assertion above passes on a body nobody re-attached. What the attach installs
	# is the `ElementProvider` that publishes `element_power_<e>` into `derived_all()`, and
	# the damage path reads exactly that id — with it missing the id is ABSENT rather than
	# zero, and a restored hero's elemental damage would silently read the floor.
	var published := booted.stats.derived_all()
	assert_eq(
		published.has(ElementStats.power_id(FIRE)),
		true,
		"the re-attach installed the element PROVIDER, so the power id is published"
	)
	assert_eq(
		float(published.get(ElementStats.power_id(FIRE), 0.0)) > 0.0,
		true,
		"and that id reads the restored root's power"
	)
