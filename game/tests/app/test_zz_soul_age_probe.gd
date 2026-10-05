extends TestCase

## THROWAWAY DIAGNOSTIC PROBE. Not a shipped test — delete after reading.
##
## Installs the clock the way `item_workbench_app._ready` does, then re-drives the four
## failing shapes and PRINTS the raw verdict, so the branch each failure landed on is
## identified by observation rather than by reading code.

var _clock: WorldClock


func setup() -> void:
	SoulApi.set_store(SoulWorldLedger.new())
	_clock = WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)


func teardown() -> void:
	SoulApi.set_store(null)
	SaveApi._stores.erase(WorldClock.WORLD_KEY)


func test_probe_a_wired_clock_makes_the_age_cause_answerable() -> void:
	var body := _aged_hero(&"probe_aged", 10_000.0)
	var answer := SoulAge.answer_for(body)
	print("PROBE answer_for(10_000y) = ", answer)
	assert_eq(bool(answer["ok"]), true, "a wired clock answers")
	assert_eq(bool(answer["expired"]), true, "and the lifespan is reached")


func test_probe_a_non_numeric_age_on_a_TYPED_float_field() -> void:
	# The failing case drove a String into `Actor.age_years`, which is declared `float`.
	var body := _hero(&"probe_not_an_age")
	body.set(SoulAge.AGE_FIELD, "a long time")
	print(
		"PROBE age_years after set(String) = ",
		body.get(SoulAge.AGE_FIELD),
		" SoulAge.age_years = ",
		SoulAge.age_years(body)
	)
	print("PROBE answer_for = ", SoulAge.answer_for(body))
	assert_eq(SoulAge.age_years(body) < 0.0, false, "typed field clamped the String to 0.0")


func test_probe_the_out_of_lives_branch() -> void:
	var body := _aged_hero(&"probe_last", 10_000.0)
	for _i in range(SoulState.DEFAULT_LIVES):
		_die_away(body)
	print("PROBE lives before the final resolve = ", int(SoulApi.soul(body)["lives"]))
	var before := WorldFact.count(body, SoulDeath.FACT_ID)
	print("PROBE fact count before = ", before)
	var outcome := SoulDeath.new().resolve(body)
	print("PROBE final verdict = ", outcome)
	assert_eq(String(outcome["reason"]), "soul_spent", "the refusal is named")


# --- helpers, copied verbatim from test_soul_age_death.gd -------------------------------


func _die_away(body: Actor) -> Dictionary:
	var pool := body.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	return SoulDeath.new().resolve(body)


func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	DifficultyApi.attach(body)
	SoulApi.attach(body)
	return body


func _aged_hero(actor_id: StringName, years: float) -> Actor:
	var body := _hero(actor_id)
	body.set(SoulAge.AGE_FIELD, years)
	return body
