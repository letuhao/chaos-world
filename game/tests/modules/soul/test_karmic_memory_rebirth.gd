extends TestCase

## BL-0951 / ADR 0939, S14: the karmic-memory fate raises the next body's starting
## foundation, driven through the REAL `SoulDeath.resolve`.
##
## The karmic-memory fates (`soul_marked_once` / `soul_marked_twice` / `soul_marked_thrice`)
## are the arrival marks each death already grants (ADR 0190). This asserts the half that was
## missing — that the held marks raise the re-embodied body's foundation through
## `KarmicFoundation` — and that the raise is PRICED by the deaths themselves: a first life,
## which has died none, has no floor.
##
## The harness is `test_soul_death_world_fact.gd`'s, verbatim, because both suites walk the
## same real rebirth and a second harness would let them drift into measuring different things.
##
## Every loop is a bounded `for`; there is no `while`.

var _actor: Actor
var _soul_store: SoulWorldLedger
var _death: SoulDeath
var _minted: Array = []


func setup() -> void:
	_soul_store = SoulWorldLedger.new()
	SoulApi.set_store(_soul_store)
	_minted.clear()
	_actor = _hero(&"karmic_rebirth_hero")
	DifficultyApi.attach(_actor)
	SoulApi.attach(_actor)
	_death = SoulDeath.new(_mint, _adopt)


## Every actor minted is released and the process-wide store cleared, so ObjectDB does not
## report leaks at exit with every assertion green. Idempotent, safe after an early return.
func teardown() -> void:
	for born in _minted:
		(born as Actor).resources.clear()
	_minted.clear()
	_actor = null
	SoulApi.set_store(null)


func test_a_first_life_has_no_floor() -> void:
	assert_almost_eq(FoundationApi.karmic(_actor), 0.0, "a first body remembers nothing")
	assert_almost_eq(FoundationApi.foundation(_actor), 0.0, "and starts at nothing")


func test_each_death_raises_the_next_bodys_starting_foundation() -> void:
	var expected := 0.0
	for _step in range(3):
		_die()
		expected += KarmicFoundation.KARMIC_PER_MARK
		assert_almost_eq(
			FoundationApi.karmic(_actor), expected, "each death's mark raises the next body's floor"
		)
		assert_almost_eq(
			FoundationApi.foundation(_actor), expected, "and the starting foundation reads it"
		)


## The floor is PRICED by deaths and nothing else: no item, no choice, no counter can raise
## it — only dying does, and each death raises it by exactly one authored step.
func test_the_floor_is_priced_by_deaths() -> void:
	var before := FoundationApi.karmic(_actor)
	_die()
	assert_almost_eq(
		FoundationApi.karmic(_actor),
		before + KarmicFoundation.KARMIC_PER_MARK,
		"one death, one step"
	)


func test_the_verdict_names_the_floor() -> void:
	var outcome := _die()
	assert_almost_eq(
		float(outcome.get("karmic_foundation", -1.0)),
		KarmicFoundation.KARMIC_PER_MARK,
		"the verdict reports the floor it seeded"
	)


# --- Internals ---------------------------------------------------------------


## Kill the current body and resolve it, exactly as the frame driver does.
func _die() -> Dictionary:
	var pool := _actor.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	return _death.resolve(_actor)


## The composition root's mint callback, through the real arrival table.
func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built


## The composition root's adopt callback: the new body becomes the one every read answers
## from, and `DestinyApi.attach` runs exactly as the composition root runs it — so a mark the
## rebind could not resolve is dropped here, not silently kept.
func _adopt(body: Actor) -> void:
	if body != null:
		DestinyApi.attach(body)
		_actor = body


## An actor with a body plan and core pools, built without the composition root.
func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	_minted.append(body)
	return body
