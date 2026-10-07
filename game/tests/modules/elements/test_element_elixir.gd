extends TestCase

## ADR 0917 / ADR 0004: the ELIXIR door of the mastery loop ("practice, domains and
## elixirs"). One authored elixir per element, consumed by `ElementsApi.use_elixir`,
## granting the ELEMENT's tier's gain — so the table that prices the family is the
## element's own authored tier and not a second per-element list.


func _actor(id: StringName) -> Actor:
	var actor := ActorFactory.build(id)
	ItemsApi.attach(actor, 64)
	return actor


func _stock(actor: Actor, def_id: StringName) -> bool:
	var def := Crafting.resolve(def_id)
	if def == null:
		return false
	ItemsApi.inventory(actor).add(def, 1)
	return ItemsApi.has_item(actor, def_id)


## Every element ships the elixir the convention names. A missing item fails here
## rather than reading as "this element has no elixir" the first time a player drinks.
func test_every_element_ships_its_mastery_elixir() -> void:
	for def in ElementDefaults.all():
		var elixir := ElementStats.mastery_elixir_id(def.id)
		assert_ne(Crafting.resolve(elixir), null, "%s ships '%s'" % [def.id, elixir])


## The behaviour: one drink spends one item and raises the element's mastery by the
## element's tier's gain.
func test_drinking_an_elixir_raises_mastery_and_spends_the_item() -> void:
	var actor := _actor(&"elixir_hero")
	actor.set_affinity(ElementStats.FIRE, 10.0)
	var elixir := ElementStats.mastery_elixir_id(ElementStats.FIRE)
	assert_eq(_stock(actor, elixir), true, "the authored elixir is in the pack")
	var before := ElementsApi.mastery_of(actor, ElementStats.FIRE)
	var outcome := ElementsApi.use_elixir(actor, ElementStats.FIRE)
	assert_eq(bool(outcome.get("ok", false)), true, "the elixir is drunk: %s" % str(outcome))
	assert_almost_eq(
		ElementsApi.mastery_of(actor, ElementStats.FIRE),
		before + ElementTraining.elixir_gain(ElementStats.FIRE),
		"mastery rose by the tier's gain"
	)
	assert_eq(ItemsApi.has_item(actor, elixir), false, "and the item was spent")


## The practice gate's own rule travels: a body refines what it can sense, so an
## element with no spark is refused and NOTHING is spent.
func test_a_body_with_no_spark_cannot_refine_an_element() -> void:
	var actor := _actor(&"elixir_sparkless")
	var elixir := ElementStats.mastery_elixir_id(ElementStats.LIGHTNING)
	assert_eq(_stock(actor, elixir), true, "the elixir is in the pack")
	var outcome := ElementsApi.use_elixir(actor, ElementStats.LIGHTNING)
	assert_eq(
		String(outcome.get("reason", "")),
		"no_spark",
		"refused by the practice gate's own rule: %s" % str(outcome)
	)
	assert_eq(ItemsApi.has_item(actor, elixir), true, "and nothing was spent")
	assert_almost_eq(
		ElementsApi.mastery_of(actor, ElementStats.LIGHTNING), 0.0, "and no mastery moved"
	)


## An empty pack and an element the rules do not know are NAMED refusals, not silent
## no-ops.
func test_an_empty_pack_and_an_unknown_element_are_named_refusals() -> void:
	var actor := _actor(&"elixir_empty")
	actor.set_affinity(ElementStats.FIRE, 10.0)
	assert_eq(
		String(ElementsApi.use_elixir(actor, ElementStats.FIRE).get("reason", "")),
		"no_elixir",
		"an empty pack names the price it lacks"
	)
	assert_eq(
		String(ElementsApi.use_elixir(actor, &"no_such_element").get("reason", "")),
		"unknown_element",
		"an unknown element is not an elixir door"
	)


## The tier table is what makes an advanced element's elixir worth more: tier 2 pays
## strictly more than tier 1, an unnamed element pays nothing, and a tier the table
## does not name would read tier 1 rather than becoming un-drinkable.
func test_the_tier_gain_is_strictly_bigger_for_advanced_elements() -> void:
	var base_gain := ElementTraining.elixir_gain(ElementStats.FIRE)
	var advanced_gain := ElementTraining.elixir_gain(ElementStats.LIGHTNING)
	assert_eq(base_gain > 0.0, true, "tier 1 pays something")
	assert_eq(advanced_gain > base_gain, true, "tier 2 pays more")
	assert_almost_eq(
		ElementTraining.elixir_gain(&"no_such_element"), 0.0, "an unknown element pays nothing"
	)
