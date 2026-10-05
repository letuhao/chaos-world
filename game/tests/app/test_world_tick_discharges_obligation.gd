extends TestCase

## DEF-0196, re-measured: the leg nobody had watched.
##
## `test_sect_serve_duty.gd` drives `InstitutionResolver.settle` and
## `test_sect_facts.gd` drives `SectDuty.serve` directly. Both are the correct
## public entries for what they measure, and neither proves the thing DEF-0196 was
## filed about, which is that the WORLD discharges a duty: a member's debt clears
## because periods elapsed, with no press, no verb and no test reaching in first.
##
## ## Why this suite lives under `tests/app/` and not `tests/modules/sect/`
##
## What it measures is the composition root's tick, not the sect module: the first
## link of the chain belongs to `app/WorldPulse`, and the file it drives from there
## is `app/institution_resolver.gd`. `tests/app/` is where the ambient-fact and
## retreat suites that already drive `WorldPulse.advance_periods` live, so this
## suite sits beside the two that would otherwise be the only readers of it.
## `SectFixtureCatalog` is still borrowed from `tests/modules/sect/`, because the
## sect CONTENT is what keeps the two satisfiability halves honest.
##
## ## Why this suite exists: mutation A
##
## Severing `_settle_institutions(periods, _crossed)` out of `WorldPulse._advance` —
## the single line that makes the world's tick reach the institution layer at all —
## left `tools test --suite sect` at **1555 passed, 0 failed**, byte-identical to the
## baseline. Severing the production path from the ledger was free. The resolver's
## own dispatch arm is covered (mutating `return bool(SectDuty.serve(...))` to
## `return bool(false)` gives 11 failures), so the gap is precisely this hop and not
## the verb underneath it.
##
## So the chain has three links and one of them was unobserved:
## `WorldPulse._advance` -> `InstitutionResolver.settle` -> `SectDuty.serve`. This
## suite drives the FIRST, through the real composition root, and asserts the whole
## chain landed.
##
## ## Both halves of satisfiable-and-non-trivial, proven on the shipped content
##
## NON-TRIVIAL: the fixture installs a sect with `min_purity = 0`, which is
## `jade_court` exactly, so `member_obligation_lines()` opens `duty_t_house` alone.
## One period of service pays that one-period line to zero, so this suite would fail
## if the mechanic were theatre and a fresh member already satisfied the debt.
##
## SATISFIABLE: the fixture's only office is a `bare_position`, whose
## `succession_method` `is_walkable_method()` answers false for, so no vacancy is ever
## open, no vacancy outranks serving, and the ladder reaches `serve_duty` on the very
## first period. A prior state that needed more periods than the term owed would be a
## permanent door;
## `test_the_debt_is_dischargeable_from_the_state_join_produces` is the leg that would
## catch it.

const HOUSE := &"t_house"


## One sect, one bare member office, and **`min_purity = 0`**. Zero is the point and
## it is not invented: `jade_court.tres` ships `min_purity = 0`, so this fixture is
## the shipped shape of "a house that asks nothing of your ear", and
## `member_obligation_lines()` therefore opens `duty_t_house` and no second line. The
## non-trivial half needs a member who OWES at join, and a two-line fixture would owe
## on a line whose size is a content decision rather than the one under test.
func setup() -> void:
	var defs: Array[SectDef] = [
		SectFixtureCatalog.sect(HOUSE, [SectFixtureCatalog.bare_position(&"t_member")], 100, 0)
	]
	SectFixtureCatalog.install(defs)


## The shipped catalog is named explicitly rather than handed to `install()`'s empty
## default, for the reason `test_sect_serve_duty.gd` gives: the catalog is SHARED, so a
## suite that installs and never restores hands every later suite a different world.
func teardown() -> void:
	SectFixtureCatalog.install([SectFixtureCatalog.default_sect()])


## A member of the fixture house, sworn, with no office — the state DEF-0196 was
## filed about, reproduced rather than hand-built.
func _joined(actor_id: StringName = &"ticker") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	SectApi.join(actor, HOUSE)
	return actor


## The production composition root's world, built the two lines
## `app/item_workbench_app.gd:350` builds: a fresh `BeatDirector` handed to a
## `WorldPulse`. Written out rather than reached through the mounted scene, because a
## scene whose boot another agent broke must not be able to turn this into a vacuous
## pass — `test_world_ambient_facts.gd` states the same rule for the same reason.
func _world(actor: Actor) -> WorldPulse:
	return WorldPulse.new(actor, BeatDirector.new())


func _owed(actor: Actor, term: String) -> int:
	return SectState.claim(SectApi.state(actor)).owed(StringName(term))


func _duty() -> String:
	return "duty_%s" % String(HOUSE)


## THE CLAIM. A whole elapsed period, driven through the world's own tick, pays down
## the membership duty the `join` opened — and records the discharge in the world fact
## ledger, which is the only thing `tools gate_reach` reads.
##
## No `SectDuty.serve` anywhere in this suite. If it appears, this case has stopped
## measuring the production path and started measuring the verb.
func test_the_world_tick_discharges_the_membership_duty() -> void:
	var actor := _joined()
	assert_eq(
		_owed(actor, _duty()),
		SectDef.MEMBER_DUTY_PERIODS,
		"joining opened the membership duty, so the debt is real before the tick runs"
	)
	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)

	_world(actor).advance_periods(1)

	assert_eq(_owed(actor, _duty()), 0, "one elapsed period cleared the duty line")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		before + 1,
		"and the world was told one sworn term was discharged"
	)


## The non-trivial half, stated on the OTHER side of the verb: a member who has just
## joined does **not** already satisfy the debt. Asserted before the tick rather than
## after, so a fixture that quietly opened a settled claim would fail here instead of
## passing the case above for the wrong reason.
func test_a_member_who_has_just_joined_is_not_already_settled() -> void:
	var actor := _joined()

	assert_eq(
		bool(SectApi.summary(actor)["settled"]),
		false,
		"a member who has only just sworn owes the membership duty: the mechanic is not theatre"
	)
	assert_eq(
		_owed(actor, _duty()),
		SectDef.MEMBER_DUTY_PERIODS,
		"and the open line is the authored membership duty, not a number invented here"
	)


## The satisfiable half: the debt is dischargeable from the state `join` produces,
## with no press and no intervening verb. This is the case that would fail if serving
## sat behind a gate a fresh member cannot pass — a duty that could never be paid is a
## permanent door wearing the shape of a mechanic.
func test_the_debt_is_dischargeable_from_the_state_join_produces() -> void:
	var actor := _joined()
	assert_eq(bool(SectApi.summary(actor)["settled"]), false, "in debt at join")

	_world(actor).advance_periods(1)

	assert_eq(
		bool(SectApi.summary(actor)["settled"]),
		true,
		"one period of the world's own tick is what makes it so: a legal prior state discharged"
	)


## Idempotence, which is a separate obligation from discharge and the reason `settle`
## is safe to reach from a periodic tick at all. A settled claim proposes nothing, so
## the second and third tick act on nothing and cannot make the debt worse.
##
## The bound is SNAPSHOT before the loop and is a literal, and the body never grows
## what it walks — the shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts.
func test_further_ticks_change_nothing_once_the_debt_is_cleared() -> void:
	var actor := _joined()
	_world(actor).advance_periods(1)
	var owed_after_serving := _owed(actor, _duty())
	var fact_after_serving := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)
	assert_eq(owed_after_serving, 0, "the first tick cleared the debt")
	assert_eq(fact_after_serving, 1, "and recorded exactly one oath")

	# Three ticks, never a `while`: this suite is scanned by the same rule as `res://src`.
	for tick in 3:
		_world(actor).advance_periods(1)
		assert_eq(
			_owed(actor, _duty()),
			owed_after_serving,
			"tick %d left the debt exactly where it was: a settle cannot make debt worse" % tick
		)
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		fact_after_serving,
		"and a line already clear is not an oath discharged again, however many ticks pass"
	)


## The ladder is what chooses this verb, and choosing it is only possible because the
## fixture authors no walkable office: `bare_position` leaves `succession_method`
## unwalkable, so `_vacant_office` finds nothing and serving is not outranked. Asserted
## rather than assumed, because a fixture that drifted into authoring a walkable seat
## would make every case above pass for a different reason than the one they claim.
func test_the_ladder_reaches_serving_on_the_very_first_period() -> void:
	var actor := _joined()
	var def := SectCatalog.instance().sect_definition(HOUSE)
	var vacancy := SectState.succession(SectApi.state(actor), &"t_member")
	assert_eq(
		vacancy.is_empty(),
		true,
		"the fixture opens no walk, so nothing outranks serving on the first period"
	)
	var intent := SectAct.intent(SectApi.state(actor), def)
	assert_eq(
		StringName(String(intent.get("verb", ""))),
		SectAct.VERB_SERVE_DUTY,
		"which is why the first tick discharges rather than waiting for a seat nobody is running"
	)
