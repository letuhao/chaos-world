extends TestCase

## ADR 0064: standing is earned and can be lost; rank is a position inside the clan and
## **is not derived from standing**. A member can hold `head` on nothing but standing,
## and that gap is what makes the thing political rather than numeric.
##
## These assert both halves: `move_standing` really is symmetric, and NOTHING in the
## module ever writes one number from the other.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"


func setup() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE), ClanFixtureCatalog.open(RIVAL)])


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _member(standing: int = 0) -> Actor:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, 0.5)
	ClanApi.join(actor, HOUSE, standing)
	return actor


func _grant_rank(actor: Actor, rank: StringName) -> void:
	# Deliberately through the LEDGER rather than a facade verb: the module publishes
	# no rank writer on purpose. A rank is GRANTED by the clan, and this stands in for
	# that grant so the tests can hold the ledger's independence to account.
	var ledger := ClanApi.state(actor)
	ledger["rank"] = String(rank)
	actor.set_module_data(ClanApi.MODULE_KEY, ledger)
	ClanProjection.apply(actor, ledger)


func _band_rank(actor: Actor) -> StringName:
	return ClanState.band_rank(ClanApi.clan_of(actor), ClanApi.standing_of(actor))


# --- Standing moves both ways ------------------------------------------------


func test_standing_rises_by_the_delta_and_reports_the_new_total() -> void:
	var actor := _member(10)
	assert_eq(ClanApi.move_standing(actor, 25), 35, "rises")
	assert_eq(ClanApi.standing_of(actor), 35, "and the facade agrees")
	ClanApi.move_standing(actor, 5)
	assert_eq(ClanApi.standing_of(actor), 40, "twice is still cumulative")


func test_standing_falls_by_the_delta_and_reports_the_new_total() -> void:
	var actor := _member(40)
	assert_eq(ClanApi.move_standing(actor, -15), 25, "falls")
	assert_eq(ClanApi.standing_of(actor), 25, "and the facade agrees")
	# A disgraced member is the case ADR 0064 is built around: earned standing can be
	# taken away, so this is a supported state rather than an edge case. The fixture's
	# bands are [0, 15, 40, 75, 120] over [outer, inner, core, heir, head], so 25 sits
	# in `inner` — one rung below the `core` the member started in at 40.
	assert_eq(_band_rank(actor), &"inner", "and the published band follows it down")


func test_standing_floors_at_zero_and_never_goes_negative() -> void:
	var actor := _member(12)
	assert_eq(ClanApi.move_standing(actor, -100), 0, "floored")
	assert_eq(ClanApi.standing_of(actor), 0, "not negative")
	assert_eq(ClanApi.move_standing(actor, -1), 0, "and stays there")
	assert_eq(ClanApi.clan_of(actor), HOUSE, "losing standing never evicts a member")


func test_moving_standing_for_an_actor_with_no_clan_moves_nothing() -> void:
	var actor := Actor.new(&"member")
	ClanApi.attach(actor)
	assert_eq(ClanApi.move_standing(actor, 50), 0, "nothing to move")
	assert_eq(ClanApi.standing_of(actor), 0, "and nothing was written")


## The null half of the case above, as its own function on purpose.
##
## `move_standing` DEREFERENCES `actor` — `actor.set_module_data(...)` and
## `ClanProjection.apply(actor, ...)` both take it — and `_ledger(null)` returns the
## empty ledger, so the missing guard was invisible until the line that uses it. The
## assertion was already here on line 81, at the END of the function above, and it was
## never a failing one: a runtime error aborts the test function it happens in and
## returns to the runner, so the `assert_eq` after it simply did not execute, and the
## suite printed the assertions up to that point and reported green. Split out, the
## verb either answers 0 for nobody or raises on the first call, and the case above
## keeps asserting that too — this is the assertion that can now actually fail.
func test_a_null_actor_has_no_standing_to_move_and_is_answered_not_raised() -> void:
	for delta in [50, -50, 0]:
		assert_eq(ClanApi.move_standing(null, delta), 0, "a null actor is safe at delta %d" % delta)
	assert_eq(ClanApi.state(null), ClanState.empty(), "and nothing was written for it")


func test_standing_survives_a_projection_rebuild_unchanged() -> void:
	var actor := _member(33)
	ClanProjection.apply(actor, ClanApi.state(actor))
	assert_eq(ClanApi.standing_of(actor), 33, "a strip-then-rebuild never re-earns it")
	ClanApi.attach(actor)
	assert_eq(ClanApi.standing_of(actor), 33, "and neither does a re-attach")


# --- Rank is NOT derived from standing ---------------------------------------


func test_a_member_can_hold_the_top_position_on_nothing_but_standing() -> void:
	var actor := _member(0)
	assert_eq(_band_rank(actor), &"outer", "the published band at 0 standing")
	_grant_rank(actor, &"head")
	assert_eq(ClanApi.rank_of(actor), &"head", "and the member still holds the top position")
	assert_eq(ClanApi.standing_of(actor), 0, "on zero standing")
	assert_eq(ClanApi.summary(actor)["outranks_standing"], true, "which the summary makes legible")


func test_rising_standing_never_moves_a_held_position() -> void:
	var actor := _member(0)
	_grant_rank(actor, &"heir")
	ClanApi.move_standing(actor, 500)
	assert_eq(ClanApi.rank_of(actor), &"heir", "climbing the ladder did not promote anyone")
	assert_ne(_band_rank(actor), &"outer", "the published band did move, though")
	assert_eq(
		ClanApi.summary(actor)["outranks_standing"],
		false,
		"and the member now sits BELOW what their standing publishes"
	)


func test_falling_standing_never_moves_a_held_position() -> void:
	var actor := _member(500)
	_grant_rank(actor, &"outer")
	assert_eq(ClanApi.move_standing(actor, -500), 0, "standing gone")
	assert_eq(ClanApi.rank_of(actor), &"outer", "and the position survives intact")
	assert_eq(ClanApi.summary(actor)["outranks_standing"], false, "which is the ordinary case")


func test_no_verb_in_the_module_writes_rank_from_standing_or_the_reverse() -> void:
	var actor := _member(40)
	_grant_rank(actor, &"core")
	for delta in [100, -80, 0, 5]:
		ClanApi.move_standing(actor, delta)
		assert_eq(ClanApi.rank_of(actor), &"core", "rank untouched by delta %d" % delta)
	assert_eq(ClanApi.standing_of(actor), 65, "and standing was the only thing that moved")
	ClanApi.attach(actor)
	assert_eq(ClanApi.rank_of(actor), &"core", "a re-attach never re-derives it")
	ClanProjection.apply(actor, ClanApi.state(actor))
	assert_eq(ClanApi.rank_of(actor), &"core", "and neither does a rebuild")


func test_the_two_numbers_agree_in_an_unpoliticised_world_and_differ_when_they_do_not() -> void:
	var honest := _member(50)
	assert_eq(_band_rank(honest), &"core", "50 standing publishes the core band")
	_grant_rank(honest, &"core")
	assert_eq(ClanApi.summary(honest)["outranks_standing"], false, "held matches published")
	var political := _member(50)
	_grant_rank(political, &"head")
	assert_eq(ClanApi.summary(political)["outranks_standing"], true, "held outranks published")
	assert_ne(ClanApi.rank_of(political), ClanApi.rank_of(honest), "two members, one standing")


func test_an_unknown_position_is_refused_rather_than_recorded() -> void:
	var actor := _member(0)
	var ledger := ClanState.with_rank(ClanApi.state(actor), &"overlord")
	assert_eq(ClanApi.state(actor)["rank"], "outer", "the real rank is untouched")
	assert_eq(String(ClanState.rank(ledger)), "outer", "and the refusal changed nothing")
	var cleared := ClanState.with_rank(ClanApi.state(actor), &"")
	assert_eq(String(ClanState.rank(cleared)), "", "an empty position clears the one held")


func test_a_position_is_refused_on_an_actor_who_belongs_to_no_clan() -> void:
	var actor := Actor.new(&"member")
	ClanApi.attach(actor)
	var ledger := ClanState.with_rank(ClanApi.state(actor), &"core")
	assert_eq(String(ClanState.rank(ledger)), "", "no clan, no position")


# --- The published bands -----------------------------------------------------


func test_rank_for_standing_is_a_published_reading_not_the_stored_rank() -> void:
	var def := ClanCatalog.instance().clan_definition(HOUSE)
	for case in [
		[-5, &"outer"],
		[0, &"outer"],
		[14, &"outer"],
		[15, &"inner"],
		[39, &"inner"],
		[40, &"core"],
		[75, &"heir"],
		[120, &"head"],
		[9999, &"head"],
	]:
		assert_eq(def.rank_for_standing(case[0]), case[1], "%d standing" % case[0])


func test_a_clan_that_publishes_no_ladder_publishes_no_rank() -> void:
	var bare := ClanDef.new()
	bare.id = &"t_bare"
	assert_eq(bare.rank_for_standing(1000), &"", "nothing to read")
	assert_eq(bare.entry_rank(), &"", "and nothing to enter at")
	assert_eq(bare.rank_index(&"head"), -1, "and no position has an ordinal")
	assert_eq(bare.rival_count(), 0, "and it names no rivals")


func test_the_summary_reports_the_distance_to_the_next_band() -> void:
	var actor := _member(30)
	assert_eq(String(ClanApi.summary(actor)["band_rank"]), "inner", "the published band")
	var resolved := actor.component(ClanProjection.SUMMARY_COMPONENT) as ClanSummary
	assert_eq(resolved.to_next_band(), 10, "30 standing is 10 short of the 40 band")
	ClanApi.move_standing(actor, 1000)
	resolved = actor.component(ClanProjection.SUMMARY_COMPONENT) as ClanSummary
	assert_eq(resolved.to_next_band(), 0, "the top band has no next")
	assert_eq(resolved.band_index, 4, "and every band is cleared")
