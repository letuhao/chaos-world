extends TestCase

## ADR 0270 §2: the lifespan-extending elixir.
##
## A guardian buys a re-body; the elixir moves the deadline. It raises the AUTHORED
## LIFESPAN the body was born with, it is consumed once, it has no effect on a body
## already past its span, and it does NOT make expiry survivable.
##
## ## Why these tests exist
##
## The elixir is a NEW verb, not a re-skin of the guardian (ADR 0270 §2). It needs its
## own option, its own content and its own guard. These tests pin all three:
##
##   - The option `extend_lifespan` is keyed by NAME (ADR 0050), never by row index.
##   - The elixir raises `Actor.lifespan_bonus_days`, which `RealmLifespan` adds to
##     the authored baseline.
##   - The elixir is consumed once (the stack decrements).
##   - A body already past its span is refused, not extended.
##   - The elixir does NOT make expiry survivable: it moves the deadline, and a body
##     that reaches the NEW lifespan still expires.

const ELIXIR := &"lifespan_extension_elixir"
const RACE := &"commonborn"
const DAYS_PER_YEAR := 365.0

## The authored table, loaded once. Two cases below were each `load()`ing the same
## `.tres`, which gdlint reports as `duplicated-load` and which was also a second and
## third trip through the resource cache for a file the suite needs in every case.
const LIFESPAN_TABLE := preload("res://src/core/realm_lifespan_table.tres")


func setup() -> void:
	pass


func teardown() -> void:
	pass


## An actor with a body plan, an inventory and an age, standing on a mortal realm.
func _body(age_years: float = 0.0) -> Actor:
	var actor := Actor.new(&"elixir_test")
	RaceApi.attach(actor)
	RaceApi.set_race(actor, RACE)
	ItemsApi.attach(actor)
	actor.age_years = age_years
	return actor


## The authored baseline lifespan for the test race, in days.
func _baseline_days() -> float:
	return RaceCatalog.instance().race_definition(RACE).lifespan


## The elixir's authored extension, in days.
func _elixir_days() -> float:
	var def := Crafting.resolve(ELIXIR)
	assert_ne(def, null, "%s resolves from the shipped content tree" % ELIXIR)
	if def == null:
		return 0.0
	var effects := def.effects()
	for effect in effects:
		if StringName(effect.get("target_type", &"")) == OptionTarget.LIFESPAN:
			return float(effect.get("value", 0.0))
	return 0.0


func test_the_elixir_is_authored_with_the_extend_lifespan_option() -> void:
	var def := Crafting.resolve(ELIXIR)
	assert_ne(def, null, "%s resolves from the shipped content tree" % ELIXIR)
	if def == null:
		return
	assert_eq(def.category, ItemCategory.CONSUMABLE, "it is a consumable")
	assert_eq(def.activation(), ItemActivation.CONSUMED, "it is consumed")
	var effects := def.effects()
	var lifespan_effects: Array[Dictionary] = []
	for effect in effects:
		if StringName(effect.get("target_type", &"")) == OptionTarget.LIFESPAN:
			lifespan_effects.append(effect)
	assert_eq(lifespan_effects.size(), 1, "exactly one lifespan effect")
	assert_eq(
		StringName(lifespan_effects[0].get("option_id", &"")),
		&"extend_lifespan",
		"keyed by NAME (ADR 0050)"
	)
	assert_almost_eq(
		float(lifespan_effects[0].get("value", 0.0)), _elixir_days(), "the authored value", 0.01
	)


func test_the_elixir_raises_the_authored_lifespan() -> void:
	var actor := _body(50.0)
	var table := LIFESPAN_TABLE
	assert_ne(table, null, "the lifespan table loads")
	if table == null:
		return
	var before := table.effective_lifespan_for(actor)
	assert_almost_eq(before, _baseline_days(), "baseline at mortal tier", 0.01)
	var def := Crafting.resolve(ELIXIR)
	assert_ne(def, null, "the elixir resolves")
	if def == null:
		return
	assert_ne(ItemsApi.generate(actor, def, 42), null, "the elixir is acquired")
	var result := ItemsApi.use_item(actor, ELIXIR, 1)
	assert_eq(bool(result.get("ok", false)), true, "the elixir is consumed")
	assert_almost_eq(actor.lifespan_bonus_days, _elixir_days(), "the bonus is applied", 0.01)
	assert_almost_eq(
		table.effective_lifespan_for(actor),
		before + _elixir_days(),
		"the effective lifespan rises by the elixir's days",
		0.01
	)


func test_the_elixir_is_consumed_once() -> void:
	var actor := _body(50.0)
	var def := Crafting.resolve(ELIXIR)
	assert_ne(def, null, "the elixir resolves")
	if def == null:
		return
	assert_ne(ItemsApi.generate(actor, def, 42), null, "the elixir is acquired")
	var inv := ItemsApi.inventory(actor)
	assert_eq(inv.count(ELIXIR), 1, "one unit in the bag")
	var result := ItemsApi.use_item(actor, ELIXIR, 1)
	assert_eq(bool(result.get("ok", false)), true, "the elixir is consumed")
	assert_eq(inv.count(ELIXIR), 0, "the stack is empty afterwards")


func test_the_elixir_has_no_effect_on_a_body_already_past_its_span() -> void:
	var actor := _body(0.0)
	var table := LIFESPAN_TABLE
	assert_ne(table, null, "the lifespan table loads")
	if table == null:
		return
	# Set the age to exactly the lifespan, so the body is at its span.
	actor.age_years = _baseline_days() / DAYS_PER_YEAR
	assert_eq(table.is_past_span(actor), true, "the body is at its span")
	var def := Crafting.resolve(ELIXIR)
	assert_ne(def, null, "the elixir resolves")
	if def == null:
		return
	assert_ne(ItemsApi.generate(actor, def, 42), null, "the elixir is acquired")
	var result := ItemsApi.use_item(actor, ELIXIR, 1)
	assert_eq(bool(result.get("ok", false)), false, "the elixir is refused")
	assert_eq(String(result.get("reason", "")), &"no_applicable_effect", "the refusal is named")
	assert_almost_eq(actor.lifespan_bonus_days, 0.0, "the bonus is not applied", 0.01)
	assert_almost_eq(
		table.effective_lifespan_for(actor),
		_baseline_days(),
		"the effective lifespan is unchanged",
		0.01
	)


func test_the_elixir_does_not_make_expiry_survivable() -> void:
	var actor := _body(50.0)
	var table := LIFESPAN_TABLE
	assert_ne(table, null, "the lifespan table loads")
	if table == null:
		return
	var def := Crafting.resolve(ELIXIR)
	assert_ne(def, null, "the elixir resolves")
	if def == null:
		return
	assert_ne(ItemsApi.generate(actor, def, 42), null, "the elixir is acquired")
	var result := ItemsApi.use_item(actor, ELIXIR, 1)
	assert_eq(bool(result.get("ok", false)), true, "the elixir is consumed")
	# The body is NOT past its span after the elixir.
	assert_eq(table.is_past_span(actor), false, "the body is not past its span")
	# But if the body reaches the NEW lifespan, it still expires.
	actor.age_years = (_baseline_days() + _elixir_days()) / DAYS_PER_YEAR
	assert_eq(table.is_past_span(actor), true, "the body expires at the NEW lifespan")


func test_the_elixir_option_is_in_the_master_pool() -> void:
	var catalog := OptionCatalog.instance()
	assert_eq(catalog.has_option(&"extend_lifespan"), true, "the option is registered")
	assert_eq(
		catalog.allows_activation(&"extend_lifespan", ItemActivation.CONSUMED),
		true,
		"the option is legal on a consumable"
	)
	assert_eq(
		catalog.allows_activation(&"extend_lifespan", ItemActivation.EQUIPPED),
		false,
		"the option is not legal on equipment"
	)
