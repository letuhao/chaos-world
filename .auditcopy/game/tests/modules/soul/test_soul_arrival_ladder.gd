extends TestCase

## ADR 0130: each death consumes exactly one arrival, so the authored ladder is the ladder a
## soul WALKS rather than one arrival repeating forever.
##
## ## Why the old case could not fail
##
## `test_soul_ledger`'s `test_the_arrival_is_the_gate_answer_and_not_a_caller_named_one` reads
## `out["arrival"]` the instant `reincarnate` returns, so it asserts the value the same call
## just wrote and never re-evaluates the gate. A gate that answered the SAME arrival forever
## would still pass it. These cases re-ask the gate AFTER every death and compare the whole
## ladder, which is the only shape a repeating arrival cannot survive.

var _actor: Actor
var _store: SoulWorldLedger
var _minted: Array = []


func setup() -> void:
	_store = SoulWorldLedger.new()
	SoulApi.set_store(_store)
	_actor = _hero(&"ladder_bearer")
	SoulApi.attach(_actor)


func teardown() -> void:
	for born in _minted:
		(born as Actor).resources.clear()
	_minted.clear()
	_actor = null
	_store = null
	SoulApi.set_store(null)


## An actor with core pools, built without the composition root so this suite needs no scene
## tree. Tracked so [method teardown] can release it.
func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	_minted.append(body)
	return body


# --- The ladder --------------------------------------------------------------


func test_three_deaths_walk_three_different_arrivals_in_authored_order() -> void:
	# ADR 0130: "the first authored origin the ledger does not already hold, in authored
	# order". Re-asked AFTER each write, which is what the old case never did.
	var owed: Array[String] = []
	for step in range(3):
		var answer := String(SoulApi.next_arrival(_actor))
		assert_ne(answer, "", "death %d has an arrival to earn" % (step + 1))
		owed.append(answer)
		var out := SoulApi.reincarnate(_actor, StringName("body_%d" % step))
		assert_eq(
			bool(out["ok"]), true, "death %d re-bodies: %s" % [step + 1, out.get("reason", "")]
		)
	var distinct: Array[String] = []
	for arrival in owed:
		if not distinct.has(arrival):
			distinct.append(arrival)
	assert_eq(distinct.size(), 3, "each death consumed its own arrival: %s" % ", ".join(owed))
	var authored: Array[String] = []
	for arrival in SoulCatalog.instance().arrival_ids():
		authored.append(String(arrival))
	assert_eq(owed, authored, "in authored gate order, and every authored arrival is reached")


func test_every_death_resolves_a_different_arrival_through_the_real_play_path() -> void:
	# The module-only ladder is half the claim. The other half is that a REAL death — which
	# reads the gate BEFORE `reincarnate` records anything, and mints through
	# `CharacterCreationFlow.build_forced` in between — still spends a different arrival each
	# time. `build_forced` writes no destiny and grants no origin, so nothing but
	# `SoulState.incarnate` advances the ladder; this case is what proves it does.
	var death := SoulDeath.new(_mint, _adopt)
	var seen: Array[String] = []
	for _step in range(3):
		var before := String(SoulApi.next_arrival(_actor))
		var outcome := death.resolve(_kill(_actor))
		assert_eq(
			bool(outcome["incarnated"]),
			true,
			"the body died and re-bodied: %s" % outcome.get("reason", "")
		)
		seen.append(before)
	assert_eq(seen.size(), 3, "three deaths")
	assert_eq(seen[0] != seen[1], true, "the second arrival differs: %s" % ", ".join(seen))
	assert_eq(seen[1] != seen[2], true, "the third arrival differs: %s" % ", ".join(seen))
	assert_eq(seen[0] != seen[2], true, "and no arrival repeats at all: %s" % ", ".join(seen))
	assert_eq(
		(SoulApi.state(_actor)["origins"] as Array).size(),
		3,
		"the ledger recorded three distinct arrivals: %s" % str(SoulApi.state(_actor)["origins"])
	)


func test_a_fourth_death_refuses_with_a_named_reason_when_no_arrival_is_left() -> void:
	# A hand-written ledger holding EVERY authored arrival with lives to spare: the gate has
	# nothing left to give, so the refusal is named rather than the first arrival handed back
	# a second time.
	var authored := SoulCatalog.instance().arrival_ids()
	var payload := SoulState.empty()
	var spent: Array = []
	for arrival in authored:
		spent.append(String(arrival))
	payload["origins"] = spent
	payload["lives"] = SoulState.DEFAULT_LIVES + 1
	_store.write_ledger(payload)
	assert_eq(String(SoulApi.next_arrival(_actor)), "", "nothing is left to earn")
	var out := SoulApi.reincarnate(_actor, &"beyond_the_ladder")
	assert_eq(bool(out["ok"]), false, "so the death cannot re-body")
	assert_eq(String(out["reason"]), "no_arrival", "and the refusal names the exhausted ladder")
	assert_eq(String(SoulApi.state(_actor)["body_id"]), "", "and no body was written")


func test_a_soul_out_of_lives_is_refused_by_the_lives_and_not_by_an_arrival_it_still_owes() -> void:
	# Arrivals and lives are separate numbers on purpose, so the two refusals must never be
	# reported for each other. Written by hand rather than played out, because the authored
	# ladder and the authored life count are the SAME number: a soul spends its last life
	# earning the last arrival, so "out of lives" and "out of arrivals" arrive together and
	# the two refusals cannot be told apart by playing. The gate is asked which it is.
	assert_eq(
		SoulCatalog.instance().arrival_ids().size(),
		SoulState.DEFAULT_LIVES,
		"the authored ladder is exactly as long as a soul's lives, so the last arrival is earned"
	)
	var payload := SoulState.empty()
	payload["origins"] = [String(SoulCatalog.instance().arrival_ids()[0])]
	payload["lives"] = 0
	_store.write_ledger(payload)
	assert_ne(String(SoulApi.next_arrival(_actor)), "", "an arrival is still owed")
	var out := SoulApi.reincarnate(_actor, &"one_too_many")
	assert_eq(bool(out["ok"]), false, "a fourth death cannot re-body")
	assert_eq(String(out["reason"]), "no_lives", "and the life count is what stopped it")


func test_a_repeated_death_for_one_body_consumes_exactly_one_arrival() -> void:
	# Re-running a resolution must not eat a second arrival: `reincarnate` is once per body, so
	# one body costs one arrival whatever a caller does afterwards.
	var first := String(SoulApi.next_arrival(_actor))
	SoulApi.reincarnate(_actor, &"body_two")
	var again := SoulApi.reincarnate(_actor, &"body_two")
	assert_eq(bool(again["ok"]), false, "the same body is refused: %s" % again.get("reason", ""))
	assert_eq(
		(SoulApi.state(_actor)["origins"] as Array).size(),
		1,
		"one body spent exactly one arrival, never %s twice" % first
	)


func test_the_arrival_that_saves_a_death_is_never_spent() -> void:
	# A guardian costs the ITEM and nothing else: no life, no incarnation, and therefore no
	# arrival. If a guardian consumed one, the ladder would shorten without a death.
	var gate := SoulDeath.new(_mint, _adopt)
	var owed := String(SoulApi.next_arrival(_actor))
	_give_guardian()
	var outcome := gate.resolve(_kill(_actor))
	assert_eq(String(outcome["reason"]), "guardian_spent", "the guardian was spent")
	assert_eq(bool(outcome["incarnated"]), false, "the soul did not re-body")
	assert_eq((SoulApi.state(_actor)["origins"] as Array).size(), 0, "and spent no arrival")
	assert_eq(String(SoulApi.next_arrival(_actor)), owed, "the next death owes the same one")


# --- Internals -----------------------------------------------------------------


## The composition root's mint callback. Records what the gate ANSWERED, so a case can see the
## ladder rather than infer it from the ledger.
func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built


## The composition root's adopt callback: the new body becomes the one every read answers from.
func _adopt(body: Actor) -> void:
	if body != null:
		_actor = body


## Take a body to zero health through the pool's own `change` so its signal fires.
func _kill(body: Actor) -> Actor:
	body.attach_core_resources()
	var pool := body.resource(&"health")
	pool.change(-pool.maximum)
	return body


## Give the body the consumable that saves a death, attaching an inventory only when it has none.
func _give_guardian() -> void:
	if ItemsApi.inventory(_actor) == null:
		ItemsApi.attach(_actor)
	var bag := ItemsApi.inventory(_actor)
	var def := Crafting.resolve(&"guardian_vigil_ash")
	if def != null and not bag.has(&"guardian_vigil_ash", 1):
		bag.add(def, 1)
