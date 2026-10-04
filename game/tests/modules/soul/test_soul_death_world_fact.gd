extends TestCase

## ADR 0130: "A death is a world fact and is recorded once."
##
## ## What this suite is for
##
## ADR 0130 §Decision mandates the write, names the id as code-owned, and requires the write be
## registered with the fact-ledger writer census in the same change. Nothing in `game/src`
## referenced `WorldFact` from `soul/` or from `app/soul_death.gd` at all, so a quest step, an
## event trigger or a fate counter could not gate on how many times a soul had died — the
## feature ADR 0130 bought was half-built, and every suite that exercised the loop stayed green.
##
## ## Why the count is asserted through `WorldFact`, never through the soul ledger
##
## The soul ledger's own `damage_count` is a soul-scoped trail, not a world fact: it is a row of
## `SoulState.damage`, capped at `HISTORY_LIMIT`, and it belongs to a soul rather than to the
## world. The quest ADR 0130 is about asks the WORLD what happened, and the world's memory is
## `WorldFact`. So every assertion here reads `WorldFact.count`.
##
## ## The three claims, and what each one is protecting
##
##   1. A GUARDIAN death is not a death. The body never fell; the item was spent and the player
##      keeps the body they had. Recording it would make the count disagree with the number of
##      bodies the world buried.
##   2. A REAL death is recorded exactly once, on the body that fell.
##   3. It is NOT double-counted — neither by a repeated poll of the same body, nor by the
##      re-embodiment that mints a fresh `Actor` whose `module_data` starts empty. That second
##      half is the non-obvious one: a write to the falling body alone is erased by the very swap
##      this fact describes, and the next death would count 1 forever.

var _actor: Actor
var _soul_store: SoulWorldLedger
var _death: SoulDeath
var _minted: Array = []


func setup() -> void:
	_soul_store = SoulWorldLedger.new()
	SoulApi.set_store(_soul_store)
	_minted.clear()
	_actor = _hero(&"death_fact_hero")
	DifficultyApi.attach(_actor)
	SoulApi.attach(_actor)
	_death = SoulDeath.new(_mint, _adopt)


## Every process-wide static released on the way out, and every actor minted, so ObjectDB does
## not report leaked instances at exit with every assertion green. Idempotent, safe after an
## early return.
func teardown() -> void:
	for born in _minted:
		(born as Actor).resources.clear()
	_minted.clear()
	_actor = null
	SoulApi.set_store(null)


# --- A guardian death is not a death -----------------------------------------


func test_a_guardian_death_records_no_world_fact() -> void:
	# The no-guardian branch is the ONLY writer, and the guardian branch returns above it. If
	# the write sat on the shared path, a spent item would be a death and the count would rise
	# every time the player dodged one.
	_give_guardian()
	var before := _deaths()
	var outcome := _die()
	assert_eq(bool(outcome["died"]), false, "the body did not die")
	assert_eq(_deaths(), before, "and no death was recorded for it")
	assert_eq(int(outcome["fact_count"]), before, "the reported count is unmoved")
	assert_eq(String(outcome["fact"]), "", "and no fact id is named by a death that was not one")


# --- A real death is recorded once -------------------------------------------


func test_a_real_death_records_one_world_fact() -> void:
	# The mandate itself, measured on the ledger rather than on the return value: a fact the
	# caller cannot read from `WorldFact` is a fact nothing can gate on.
	assert_eq(_deaths(), 0, "a soul that has never died has no death recorded")
	var outcome := _die()
	assert_eq(bool(outcome["died"]), true, "the body died")
	assert_eq(_deaths(), 1, "a soul death is a world fact, recorded once")
	assert_eq(String(outcome["fact"]), String(SoulDeath.FACT_ID), "under the code-owned id")
	assert_eq(int(outcome["fact_count"]), 1, "and the caller is told the count")


func test_the_fact_is_written_against_the_body_that_fell() -> void:
	# Not decoration. `_rebody` mints a NEW actor, so "the ledger holds the fact" has to be
	# checked on the specific body the death happened to, or a test would pass against the
	# re-embodied one and prove nothing about where the write landed.
	_die()
	assert_eq(
		WorldFact.count(_minted[0] as Actor, SoulDeath.FACT_ID),
		1,
		"the body that fell carries the death"
	)


# --- Once, and not once per poll ---------------------------------------------


func test_polling_the_same_dead_body_twice_records_one_death_not_two() -> void:
	# **The same body, resolved twice.** Not a second death — a second `resolve` for a body that
	# is still lying at zero health, which is exactly what a poll that re-fires would do.
	# `app/item_workbench_app.gd::poll_death` re-arms on the actor id so the shipped path does
	# not do this, but the once-rule belongs at the WRITER: `WorldFact`'s ledger is monotone and
	# has no verb to take an accidental second accrual back (ADR 0113), so a double count here
	# would be permanent and every gate reading it silently wrong.
	var fallen := _actor
	var pool := fallen.resource(&"health")
	pool.change(-pool.maximum)
	_death.resolve(fallen)
	assert_eq(WorldFact.count(fallen, SoulDeath.FACT_ID), 1, "the first resolve records it")
	# Resolve the SAME actor again. This is the repeat-poll shape, isolated from the body swap.
	_death.resolve(fallen)
	assert_eq(
		WorldFact.count(fallen, SoulDeath.FACT_ID),
		1,
		"a repeated poll of the same body does not accrue a second death"
	)


func test_a_second_death_is_a_second_death_and_not_a_refused_repeat() -> void:
	# The counterweight to the case above, and the reason the once-rule is keyed by BODY rather
	# than by the ledger's count. The re-embodied body INHERITS the carried `soul_died: 1`, so
	# a guard reading `count >= 1` would refuse its first death and this soul could die exactly
	# once, ever.
	_die()
	assert_eq(_deaths(), 1, "one death so far")
	var reborn := _actor
	assert_ne(reborn.id, _minted[0].id, "and it is genuinely a different body")
	_die()
	assert_eq(_deaths(), 2, "the new body's own death is recorded, not refused as a repeat")


func test_the_count_accumulates_across_deaths_rather_than_restarting() -> void:
	# The carry-across-the-swap half. A reborn `Actor` is minted with EMPTY `module_data`, so a
	# write to the falling body alone is erased by the re-embodiment — and the second death
	# would record 1 forever. Two deaths must read 2.
	_die()
	_die()
	assert_eq(_deaths(), 2, "the second death is counted on top of the first, not instead of it")


func test_the_count_rides_the_reborn_body_so_a_third_death_still_sees_it() -> void:
	# And on the body that now stands, not only on the one in the grave. This is the assertion
	# that fails if `_carry_facts` is removed.
	_die()
	var reborn := _actor
	assert_eq(WorldFact.count(reborn, SoulDeath.FACT_ID), 1, "the new body inherits the history")
	_die()
	assert_eq(WorldFact.count(_actor, SoulDeath.FACT_ID), 2, "and the next death adds to it")


func test_a_soul_that_runs_out_of_lives_still_records_its_final_death() -> void:
	# `soul_spent` is a death with no body to hand back — nothing re-embodies, but the soul died
	# on the last body it had, and a quest asking how many deaths a soul has earned must hear
	# about it. Refusing to record here would make the LAST death of a run the one a world never
	# learns of.
	for _i in range(SoulState.DEFAULT_LIVES):
		_die()
	var before := _deaths()
	var outcome := _die()
	assert_eq(String(outcome["reason"]), "soul_spent", "the run ended")
	assert_eq(bool(outcome["died"]), true, "on a death")
	assert_eq(_deaths(), before + 1, "and the world was told about it")


# --- Internals ---------------------------------------------------------------


## The count on the body that currently stands — the one every later read answers from.
func _deaths() -> int:
	return WorldFact.count(_actor, SoulDeath.FACT_ID)


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


## The composition root's adopt callback: the new body becomes the one every read answers from.
func _adopt(body: Actor) -> void:
	if body != null:
		_actor = body


## An actor with a body plan and core pools, built without the composition root.
func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	_minted.append(body)
	return body


## The consumable that saves a death: spent, and the soul pays nothing.
func _give_guardian() -> void:
	if ItemsApi.inventory(_actor) == null:
		ItemsApi.attach(_actor)
	var bag := ItemsApi.inventory(_actor)
	var def := Crafting.resolve(&"guardian_vigil_ash")
	if def != null and not bag.has(&"guardian_vigil_ash", 1):
		bag.add(def, 1)
