extends TestCase

## Attach is the one entry point every actor passes through, and it runs at birth, on a
## restored save and on a re-attach after `set_race`. These assert it is free of
## consequence when called again — that the modifier stack, the base attributes and the
## affinity map all land where they should and come back exactly once.

const STONE := &"t_stone"
const TIDE := &"t_tide"
const BASE := &"t_base"

## The 30-step shared ladder's mid and high ordinals, used to drive the ceiling.
const MID_REALM := &"core_formation"
const TOP_REALM := &"primordial_origin"


func setup() -> void:
	(
		RaceFixtureCatalog
		. install(
			[
				RaceFixtureCatalog.capped(STONE, &"mind_cultivation", 8, Stat.PHYSIQUE),
				RaceFixtureCatalog.closed(TIDE, &"body_cultivation", 0.5),
				RaceFixtureCatalog.closed(BASE, &"mind_cultivation", 0.2),
			],
			BASE
		)
	)


func teardown() -> void:
	RaceFixtureCatalog.teardown()


func _hero() -> Actor:
	var actor := Actor.new(&"body", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	RaceApi.attach(actor)
	return actor


## Everything a drift assertion needs: the race, the trait mirror, the base map, the
## affinity map, this module's modifier sources and the two derived totals that move.
func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"race": String(RaceApi.race_of(actor)),
		"traits": actor.traits.to_array(),
		"base": actor.stats.base_dict(),
		"affinities": actor.affinities.to_dict(),
		"sources": _own_sources(actor),
		"defense": RaceProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		"derived_physique_driven": actor.stats.derived(Stat.MAX_HEALTH),
	}


func _own_sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		if RaceState.is_own_source(modifier.source):
			out.append(String(modifier.source))
	out.sort()
	return out


# --- Attach is idempotent ----------------------------------------------------


func test_attaching_an_actor_with_no_race_leaves_it_empty_and_harmless() -> void:
	var actor := _hero()
	assert_eq(RaceApi.race_of(actor), &"", "no race is authored, so none is assigned")
	assert_eq(_own_sources(actor), [], "and nothing was projected")
	assert_eq(actor.component(RaceApi.DEF_COMPONENT), null, "no definition was attached")
	assert_eq(actor.stats.provider_count(), 1, "the provider registered exactly once")
	RaceApi.attach(actor)
	RaceApi.attach(actor)
	assert_eq(actor.stats.provider_count(), 1, "re-attaching never registers a second provider")
	assert_eq(_own_sources(actor), [], "and never projects anything")


func test_attaching_twice_produces_the_same_actor_the_first_time_produced() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	var once := _fingerprint(actor)
	RaceApi.attach(actor)
	RaceApi.attach(actor)
	RaceApi.attach(actor)
	assert_eq(_fingerprint(actor), once, "attach is idempotent")


func test_attach_registers_one_provider_even_when_called_repeatedly() -> void:
	var actor := Actor.new(&"body")
	RaceApi.attach(actor)
	var provider := actor.component(&"race_provider")
	assert_ne(provider, null, "the provider component is registered")
	assert_eq(actor.stats.provider_count(), 1, "and added to the stat stack once")
	RaceApi.attach(actor)
	assert_eq(actor.component(&"race_provider"), provider, "the same provider is reused")
	assert_eq(actor.stats.provider_count(), 1, "so the stack still holds one")


func test_attach_on_a_null_actor_is_a_no_op() -> void:
	RaceApi.attach(null)
	assert_eq(RaceApi.race_of(null), &"", "and reads nothing")


# --- The projection actually lands ------------------------------------------


func test_a_race_grants_base_attributes_through_set_base_and_a_base_cannot_be_lowered() -> void:
	var actor := _hero()
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	assert_eq(before, 10.0, "the actor's own build")
	RaceApi.set_race(actor, STONE)
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 14.0, "the race added its grant on top")
	assert_ne(actor.stats.get_base(Stat.WILL), 9.0, "and left attributes it says nothing about")
	# The derived stat the base attribute drives moved with it, so the grant is live
	# rather than a number sitting in a map.
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 190.0, "max_health follows physique")


func test_a_percent_grant_lands_on_the_modifier_stack_under_the_race_source() -> void:
	var actor := _hero()
	var def := RaceDef.new()
	def.id = &"t_percent"
	def.percent_modifiers = {Stat.DEFENSE_PHYSICAL: 0.5}
	def.closed_paths = [&"mind_cultivation"]
	RaceCatalog.shared._races["t_percent"] = def
	assert_eq(RaceApi.set_race(actor, &"t_percent"), true, "authored")
	assert_eq(_own_sources(actor), ["race:t_percent"], "tagged with the namespaced source")
	assert_eq(
		RaceProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		0.5,
		"the fraction is on the stack"
	)
	# `_hero()` starts at physique 10, so the core defense_physical baseline is
	# 10 * 1.5 = 15.0 and a 50% race grant lands it at 22.5. The grant is a PERCENT,
	# so it rides the actor's own physique rather than adding a flat number.
	assert_almost_eq(actor.stats.derived(Stat.DEFENSE_PHYSICAL), 22.5, "and reached derived()")


func test_a_race_projects_its_trait_mirror_and_swaps_it_cleanly() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	assert_eq(actor.traits.has(RaceState.trait_for(STONE)), true, "the held race is mirrored")
	RaceApi.set_race(actor, TIDE)
	assert_eq(actor.traits.has(RaceState.trait_for(STONE)), false, "the old mirror is removed")
	assert_eq(actor.traits.has(RaceState.trait_for(TIDE)), true, "and the new one added")


func test_a_race_subtracts_its_own_base_grant_when_it_is_replaced() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 14.0, "stoneborn grants +4 physique")
	RaceApi.set_race(actor, TIDE)
	assert_eq(
		actor.stats.get_base(Stat.PHYSIQUE),
		10.0,
		"tidecaller grants nothing, so the 4 comes back off"
	)
	assert_eq(actor.stats.get_base(Stat.WILL), 5.0, "and the actor's own build is untouched")


func test_a_race_subtracts_only_its_own_affinity_grant_and_leaves_a_strangers_alone() -> void:
	var actor := _hero()
	# A foreign grant into the same map, which the race must neither read as its own nor
	# destroy when it strips.
	actor.set_affinity(&"fire", 7.0)
	var def := RaceDef.new()
	def.id = &"t_affinity"
	def.affinities = {&"fire": 3.0, &"water": 2.0}
	def.closed_paths = [&"mind_cultivation"]
	RaceCatalog.shared._races["t_affinity"] = def
	assert_eq(RaceApi.set_race(actor, &"t_affinity"), true, "authored")
	assert_eq(actor.affinities.get_value(&"fire"), 10.0, "7 from elsewhere plus 3 from the race")
	assert_eq(actor.affinities.get_value(&"water"), 2.0, "and water, which nobody else held")
	RaceProjection.strip(actor)
	assert_eq(actor.affinities.get_value(&"fire"), 7.0, "only the race's own 3 came back")
	assert_eq(actor.affinities.get_value(&"water"), 0.0, "the rest of its grant went too")
	assert_eq(actor.affinities.has(&"wood"), false, "and the map was never wiped")


func test_setting_an_unknown_race_is_refused_and_changes_nothing() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	var before := _fingerprint(actor)
	assert_eq(RaceApi.set_race(actor, &"t_no_such_race"), false, "refused")
	assert_eq(_fingerprint(actor), before, "and nothing moved")
	assert_eq(RaceApi.set_race(null, STONE), false, "a null actor is refused too")


func test_strip_removes_the_modifiers_the_trait_mirror_and_the_definition() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	RaceProjection.strip(actor)
	assert_eq(_own_sources(actor), [], "no modifiers left")
	assert_eq(actor.traits.has(RaceState.trait_for(STONE)), false, "no mirror left")
	assert_eq(actor.component(RaceApi.DEF_COMPONENT), null, "no definition left")
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 10.0, "no grant left")
	# The race itself survives a strip: stripping is a projection reset, not a
	# transformation. Only conception writes a race.
	assert_eq(RaceApi.race_of(actor), STONE, "the race is unchanged")


func test_projection_onto_a_null_actor_is_a_no_op() -> void:
	RaceProjection.apply(null, STONE)
	RaceProjection.strip(null)
	assert_eq(RaceProjection.contribution(null, Stat.PHYSIQUE), 0.0, "and reads nothing")


# --- The provider ------------------------------------------------------------


func test_the_provider_contributes_the_race_vocabulary_from_the_attached_definition() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	assert_almost_eq(actor.stats.derived(RaceStats.REALM_CEILING), 8.0, "the ceiling")
	assert_almost_eq(actor.stats.derived(RaceStats.LIFESPAN), 36500.0, "the lifespan")
	assert_almost_eq(actor.stats.derived(RaceStats.PATH_COUNT), 2.0, "two paths remain open")
	assert_almost_eq(actor.stats.derived(RaceStats.AFFINITY_COUNT), 0.0, "no affinity authored")
	assert_almost_eq(actor.stats.derived(RaceStats.DOMINANCE), 0.45, "the authored dominance")
	assert_almost_eq(
		actor.stats.derived(RaceStats.MANIFESTATION_THRESHOLD), 0.1, "and the threshold"
	)


func test_the_provider_contributes_nothing_before_a_race_is_assigned() -> void:
	var actor := _hero()
	assert_almost_eq(actor.stats.derived(RaceStats.PATH_COUNT), 0.0, "no definition, no stats")
	assert_almost_eq(actor.stats.derived(RaceStats.REALM_CEILING), 0.0, "and no ceiling")


func test_the_provider_does_not_re_derive_the_percent_grants_the_projection_applied() -> void:
	var actor := _hero()
	var def := RaceDef.new()
	def.id = &"t_double"
	def.percent_modifiers = {Stat.DEFENSE_PHYSICAL: 1.0}
	def.closed_paths = [&"mind_cultivation"]
	RaceCatalog.shared._races["t_double"] = def
	RaceApi.set_race(actor, &"t_double")
	# defense_physical = physique * 1.5 = 15.0. A 100% grant is 30.0. Contributing it
	# a second time through the provider would read 30.0 * 2 = 60.0.
	assert_almost_eq(actor.stats.derived(Stat.DEFENSE_PHYSICAL), 30.0, "counted exactly once")


func test_a_stranger_casting_the_race_provider_alone_reads_the_same_component() -> void:
	var actor := _hero()
	RaceApi.set_race(actor, STONE)
	# The provider reads the component, never the catalog, so an actor carrying the
	# definition is enough — the catalog singleton is not consulted at all.
	var context := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	var values := RaceProvider.new().contribute(context)
	assert_almost_eq(float(values[RaceStats.REALM_CEILING]), 8.0, "the ceiling is readable")
	assert_almost_eq(float(values[RaceStats.PATH_COUNT]), 2.0, "and the open path count")
	assert_eq(
		float(values.get(RaceStats.AFFINITY_COUNT, -1.0)), 0.0, "and a zero, not a missing key"
	)


func test_the_provider_caps_a_badly_scaled_affinity_count() -> void:
	var actor := _hero()
	var def := RaceDef.new()
	def.id = &"t_many"
	def.closed_paths = [&"mind_cultivation"]
	for element in ElementStats.BASE_ELEMENTS + ElementStats.ADVANCED_ELEMENTS:
		def.affinities[element] = 99.0
	RaceCatalog.shared._races["t_many"] = def
	RaceApi.set_race(actor, &"t_many")
	assert_almost_eq(
		actor.stats.derived(RaceStats.AFFINITY_COUNT), 10.0, "ten affinities, capped at ten"
	)
	assert_almost_eq(
		actor.affinities.get_value(ElementStats.FIRE), 99.0, "the raw grant is untouched"
	)
