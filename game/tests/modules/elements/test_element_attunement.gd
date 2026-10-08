extends TestCase

## The affinity door (ADR 0924, BL-0926): a body opens an element its race never gave
## it — the awakening-treasure family, the crafted awakening elixir, and the
## registered-source seam that carries everything else. The end-to-end proof is the
## first test: no spark, consume a treasure, and the practise and elixir doors both
## open.

const LIGHTNING := ElementStats.LIGHTNING
const FIRE := ElementStats.FIRE
const VOID := ElementStats.VOID


func setup() -> void:
	ElementsApi.clear_registered_sources()


func teardown() -> void:
	ElementsApi.clear_registered_sources()


func _actor(id: StringName = &"element_attunement") -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	ElementsApi.attach(actor)
	ItemsApi.attach(actor, 64)
	return actor


## Stand the actor at a realm on BOTH climbs the tier door reads (the elemental rank
## and the qi climb), so an advanced tier is legitimately open.
func _stand_at(actor: Actor, realm_id: StringName) -> void:
	actor.set_path(PathState.new(ElementMastery.PATH_ID, realm_id))
	actor.set_path(PathState.new(PathState.QI, realm_id))


func _stock(actor: Actor, item_id: StringName, count: int = 1) -> void:
	var def := Crafting.resolve(item_id)
	assert_ne(def, null, "the authored item resolves: %s" % String(item_id))
	if def == null:
		return
	ItemsApi.inventory(actor).add(def, count)


## A registered source with fixed callables, for the seam tests.
func _source(id: StringName, element_id: StringName, amount: float, once: bool) -> AffinitySource:
	var always := func(_who: Actor) -> bool: return true
	var spend := func(_who: Actor) -> bool: return true
	return AffinitySource.make(id, element_id, amount, 1, "Test Source", once, always, spend)


## One roster row, the read the screen renders.
func _row(actor: Actor, element_id: StringName) -> Dictionary:
	for entry in ElementsApi.roster(actor):
		var row := entry as Dictionary
		if StringName(row.get("id", "")) == element_id:
			return row
	return {}


## THE PIPELINE PROOF: a body with no spark for an element consumes its awakening
## treasure, the spark opens, practise lands, and the mastery elixir stops refusing
## `no_spark` — the door the audit found unwired, wired end to end.
func test_a_treasure_opens_a_root_the_race_never_gave() -> void:
	var actor := _actor()
	_stand_at(actor, &"spirit_condensation")
	assert_eq(ElementTraining.can_practise(actor, LIGHTNING), false, "no lightning spark")
	assert_eq(
		ElementsApi.use_elixir(actor, LIGHTNING).get("reason", ""),
		"no_spark",
		"and the mastery elixir refuses for the missing spark"
	)
	_stock(actor, ElementAttunement.treasure_id(LIGHTNING))
	var result := ElementsApi.attune(actor, LIGHTNING)
	assert_eq(result.get("ok", false), true, "the treasure opens the root")
	assert_almost_eq(
		actor.affinities.get_value(LIGHTNING), 3.0, "at the tier-2 treasure's gain", 1e-6
	)
	assert_eq(ElementTraining.can_practise(actor, LIGHTNING), true, "the spark is real")
	assert_eq(bool(ElementsApi.practise(actor, LIGHTNING).get("ok", false)), true, "and it trains")
	assert_eq(
		ElementsApi.use_elixir(actor, LIGHTNING).get("reason", ""),
		"no_elixir",
		"and the elixir now asks for the item, never the spark"
	)


## The realm gate is the SAME door the technique site uses: a fresh body cannot buy
## its way into a tier its climb has not reached, treasure or not.
func test_a_tier_beyond_the_climb_is_locked() -> void:
	var actor := _actor()
	_stock(actor, ElementAttunement.treasure_id(LIGHTNING))
	var result := ElementsApi.attune(actor, LIGHTNING)
	assert_eq(result.get("ok", false), false, "a tier-2 root on a tier-1 body")
	assert_eq(String(result.get("reason", "")), ElementAttunement.R_LOCKED, "is locked by name")
	assert_almost_eq(actor.affinities.get_value(LIGHTNING), 0.0, "and nothing was spent", 1e-9)
	assert_eq(
		ItemsApi.has_item(actor, ElementAttunement.treasure_id(LIGHTNING)),
		true,
		"the treasure is still held"
	)


## The triad opens at the Immortal realm, and its treasure pays the tier-3 gain.
func test_the_triad_opens_at_the_immortal_realm() -> void:
	var actor := _actor()
	_stand_at(actor, &"earth_immortal")
	_stock(actor, ElementAttunement.treasure_id(VOID))
	var result := ElementsApi.attune(actor, VOID)
	assert_eq(result.get("ok", false), true, "the void root opens")
	assert_almost_eq(actor.affinities.get_value(VOID), 5.0, "at the tier-3 gain", 1e-6)
	assert_almost_eq(float(_row(actor, VOID).get("affinity_cap", 0.0)), 18.0, "capped at 18", 1e-6)


func test_the_root_stops_at_its_cap() -> void:
	var actor := _actor()
	_stock(actor, ElementAttunement.treasure_id(FIRE), 10)
	var landed := 0
	for index in 10:
		var result := ElementsApi.attune(actor, FIRE)
		if not bool(result.get("ok", false)):
			assert_eq(
				String(result.get("reason", "")), ElementAttunement.R_AT_CAP, "the cap is the stop"
			)
			break
		landed += 1
	assert_eq(landed, 6, "six tier-1 treasures exactly fill the root")
	assert_almost_eq(actor.affinities.get_value(FIRE), 12.0, "at the tier-1 cap", 1e-6)
	assert_eq(
		ElementsApi.attune(actor, FIRE).get("reason", ""),
		ElementAttunement.R_AT_CAP,
		"and it stays capped"
	)


func test_the_crafted_elixir_pays_double_and_is_preferred() -> void:
	var actor := _actor()
	var treasure := ElementAttunement.treasure_id(FIRE)
	var elixir := ElementAttunement.awakening_elixir_id(FIRE)
	_stock(actor, treasure)
	_stock(actor, elixir)
	var result := ElementsApi.attune(actor, FIRE)
	assert_eq(result.get("ok", false), true, "the elixir attunes")
	assert_almost_eq(actor.affinities.get_value(FIRE), 4.0, "at the elixir's double gain", 1e-6)
	assert_eq(ItemsApi.has_item(actor, elixir), false, "the elixir was spent")
	assert_eq(ItemsApi.has_item(actor, treasure), true, "and the smaller treasure was left alone")


func test_a_registered_source_is_a_candidate_and_a_once_source_is_remembered() -> void:
	var actor := _actor()
	assert_eq(
		ElementsApi.register_affinity_source(_source(&"test:big", FIRE, 7.0, true)),
		true,
		"the source registers"
	)
	assert_eq(ElementsApi.attune(actor, FIRE).get("ok", false), true, "and it attunes")
	assert_almost_eq(actor.affinities.get_value(FIRE), 7.0, "at its own amount", 1e-6)
	# The once source is spent; the derived treasure is the fallback.
	_stock(actor, ElementAttunement.treasure_id(FIRE))
	assert_eq(ElementsApi.attune(actor, FIRE).get("ok", false), true, "the next attune lands")
	assert_almost_eq(
		actor.affinities.get_value(FIRE), 9.0, "on the treasure, not the spent source", 1e-6
	)


func test_a_spent_once_source_survives_a_round_trip() -> void:
	var actor := _actor()
	ElementsApi.register_affinity_source(_source(&"test:once", FIRE, 5.0, true))
	assert_eq(ElementsApi.attune(actor, FIRE).get("ok", false), true, "the once source attunes")
	var restored := Actor.from_dict(actor.to_dict())
	assert_ne(restored, null, "the body round-trips")
	if restored == null:
		return
	ElementsApi.attach(restored)
	ItemsApi.attach(restored, 64)
	var still_offered := false
	for source in ElementAttunement.offers(restored, FIRE):
		if source.id == &"test:once":
			still_offered = true
	assert_eq(still_offered, false, "the spent once source is not a candidate after the boot")


func test_a_registered_source_with_an_unmet_requirement_is_not_a_candidate() -> void:
	var actor := _actor()
	var never := func(_who: Actor) -> bool: return false
	var spend := func(_who: Actor) -> bool: return true
	var source := AffinitySource.make(&"test:locked", FIRE, 9.0, 1, "Locked", false, never, spend)
	assert_eq(ElementsApi.register_affinity_source(source), true, "it registers")
	var result := ElementsApi.attune(actor, FIRE)
	assert_eq(
		String(result.get("reason", "")), ElementAttunement.R_NO_SOURCE, "but is never a candidate"
	)


func test_malformed_sources_are_refused_at_the_door() -> void:
	var actor := _actor()
	assert_eq(ElementsApi.register_affinity_source(null), false, "a null source")
	var always := func(_who: Actor) -> bool: return true
	var no_element := AffinitySource.make(&"test:bad", &"", 1.0, 1, "Bad", false, always, always)
	assert_eq(ElementsApi.register_affinity_source(no_element), false, "no element")
	var no_check := AffinitySource.make(
		&"test:bad2", FIRE, 1.0, 1, "Bad", false, Callable(), always
	)
	assert_eq(ElementsApi.register_affinity_source(no_check), false, "no check callable")
	assert_eq(
		ElementsApi.attune(actor, FIRE).get("reason", ""),
		ElementAttunement.R_NO_SOURCE,
		"and none of them attuned"
	)


func test_the_roster_read_names_the_next_grant_and_the_block() -> void:
	var actor := _actor()
	var fire := _row(actor, FIRE)
	assert_eq(
		String(fire.get("attune_blocked", "")), ElementAttunement.R_NO_SOURCE, "no source, no press"
	)
	assert_almost_eq(float(fire.get("affinity_cap", 0.0)), 12.0, "the tier-1 cap", 1e-6)
	_stock(actor, ElementAttunement.treasure_id(FIRE))
	fire = _row(actor, FIRE)
	assert_eq(String(fire.get("attune_blocked", "")), "", "the treasure unblocks the press")
	assert_almost_eq(float(fire.get("attune_gain", 0.0)), 2.0, "at the treasure's gain", 1e-6)
	assert_eq(String(fire.get("attune_label", "")), "Awakening Treasure", "and the label names it")
	assert_eq(
		String(_row(actor, LIGHTNING).get("attune_blocked", "")),
		ElementAttunement.R_LOCKED,
		"a locked element reads locked"
	)


func test_unknown_element_and_no_actor_are_named() -> void:
	var actor := _actor()
	assert_eq(
		String(ElementsApi.attune(null, FIRE).get("reason", "")),
		ElementAttunement.R_NO_ACTOR,
		"no actor"
	)
	assert_eq(
		String(ElementsApi.attune(actor, &"no_such_element").get("reason", "")),
		ElementAttunement.R_UNKNOWN_ELEMENT,
		"unknown element"
	)
