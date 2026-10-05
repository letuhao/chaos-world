extends TestCase

## THROWAWAY DIAGNOSTIC PROBE #2. Not a shipped test — delete after reading.
##
## Q1: does a swap-walking `_die_away` actually exhaust the ledger and land on `soul_spent`?
## Q2: which refusal shapes are REACHABLE now that `Actor.age_years` is a typed `float`?

var _clock: WorldClock
var _minted: Array = []


func setup() -> void:
	SoulApi.set_store(SoulWorldLedger.new())
	_clock = WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)
	_minted.clear()


func teardown() -> void:
	SoulApi.set_store(null)
	SaveApi._stores.erase(WorldClock.WORLD_KEY)
	_minted.clear()


# --- Q1: the out-of-lives branch ------------------------------------------------------------


func test_probe_the_swap_walking_die_away() -> void:
	var aged := _aged_hero(&"probe_last", 10_000.0)
	var body: Actor = aged
	for pass_index in range(SoulState.DEFAULT_LIVES):
		print("PROBE pass ", pass_index, " lives BEFORE = ", int(SoulApi.soul(body)["lives"]))
		body = _die_away(body)
		print(
			"PROBE pass ",
			pass_index,
			" lives AFTER  = ",
			int(SoulApi.soul(body)["lives"]),
			" incarnation = ",
			int(SoulApi.soul(body)["incarnation"]),
			" facts        = ",
			WorldFact.count(body, SoulDeath.FACT_ID)
		)
	# Re-age the body that now stands: age is a BODY fact and the swap gave a newborn.
	body.set(SoulAge.AGE_FIELD, 10_000.0)
	var before := WorldFact.count(body, SoulDeath.FACT_ID)
	var outcome := SoulDeath.new(_mint, Callable()).resolve(body)
	print("PROBE swap-walking final verdict = ", outcome)
	assert_eq(String(outcome["reason"]), "soul_spent", "the refusal is named")
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_AGE, "on the age cause")
	assert_eq(bool(outcome["incarnated"]), false, "nothing re-embodied")
	assert_eq(String(outcome["body_id"]), "", "no body was handed back")
	assert_eq(WorldFact.count(body, SoulDeath.FACT_ID), before + 1, "the world heard about it")


func test_probe_an_aged_body_at_full_health_resolves() -> void:
	var aged := _aged_hero(&"probe_lived_out", 10_000.0)
	var outcome := SoulDeath.new(_mint, Callable()).resolve(aged)
	print("PROBE full-health aged verdict = ", outcome)
	assert_eq(bool(outcome["died"]), true, "the body ended")
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_AGE, "on the age cause")


# --- Q2: which refusal shapes are reachable now `age_years` is a typed float ---------------


func test_probe_which_age_shapes_are_reachable() -> void:
	var body := _hero(&"probe_shapes")
	body.set(SoulAge.AGE_FIELD, "a long time")
	print("PROBE String into typed field -> ", body.get(SoulAge.AGE_FIELD))
	body.set(SoulAge.AGE_FIELD, -12.5)
	print("PROBE negative age -> SoulAge.age_years = ", SoulAge.age_years(body))
	body.set(SoulAge.AGE_FIELD, 0.0 / 0.0)
	print("PROBE NAN age -> SoulAge.age_years = ", SoulAge.age_years(body))
	print("PROBE NAN answer = ", SoulAge.answer_for(body))
	body.set(SoulAge.AGE_FIELD, 10_000.0)
	print("PROBE healthy answer = ", SoulAge.answer_for(body))
	print("PROBE AGE_FIELD in actor = ", SoulAge.AGE_FIELD in body)
	assert_eq(true, true, "probe only")


# --- helpers --------------------------------------------------------------------------------


func _die_away(body: Actor) -> Actor:
	var pool := body.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	var holder := {"body": body}
	var outcome := (
		SoulDeath.new(_mint, func(new_body: Actor) -> void: holder["body"] = new_body).resolve(body)
	)
	print("PROBE die_away verdict = ", outcome)
	return holder["body"] as Actor


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


func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built
