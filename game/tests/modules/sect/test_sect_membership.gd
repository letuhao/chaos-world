extends TestCase

## Leaving is always permitted and always costs; an overflow is a refused admit and
## never a silent trim; and `seat_occupied` is a different answer from
## `capacity_full` because they are different player-facing situations (ADR 0084).
##
## These pin all three. The capacity cases run against a **fixture roster supplied
## by the case** rather than a member list this module keeps: a claim names one sect
## and `actor.module_data` is the only persistence root in the repo, so ADR 0083
## records where a polity-wide ledger lives as an open question. `promote` therefore
## takes the held count as an argument, and a sect that DOES hold a roster asks
## `SectDef.seat_state` the same question — one answer, one place.

const HOUSE := &"t_house"
const MEMBER := &"t_member"
const STEWARD := &"t_steward"
const READER := &"t_reader"
const ARCHIVIST := &"t_archivist"
## The authored cap of the room this suite fills, read off the definition rather
## than written down beside the offices that author it. `READER` and `ARCHIVIST` are
## the only offices of three in this sect, and a case that asked about "3 of 3"
## against either of the others would be asserting a room that does not exist.
const ROOM_CAPACITY := 3


func setup() -> void:
	(
		SectFixtureCatalog
		. install(
			[
				(
					SectFixtureCatalog
					. sect(
						HOUSE,
						[
							SectFixtureCatalog.bare_position(MEMBER),
							SectFixtureCatalog.seat(STEWARD, 60),
							SectFixtureCatalog.room(READER, 3, 20),
							SectFixtureCatalog.wide_position(ARCHIVIST, 2, 40),
						]
					)
				),
				SectFixtureCatalog.rival_sect(),
			]
		)
	)


func teardown() -> void:
	SectFixtureCatalog.teardown()


func _member(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	return actor


## A sworn member with `standing`, which is what most of these cases start from.
func _sworn(actor_id: StringName, standing: int) -> Actor:
	var actor := _member(actor_id)
	SectApi.join(actor, HOUSE)
	SectApi.move_standing(actor, standing)
	return actor


func _def() -> SectDef:
	return SectCatalog.instance().sect_definition(HOUSE)


# --- Leaving is never refused for standing -----------------------------------


## **The only thing `leave` refuses on is `not_a_member`.** A player with no exit is
## in a bad state with no out, so there is no standing threshold, no office check
## and no doctrine gate on the way out — a Steward on max standing leaves exactly as
## freely as a fresh Disciple, and the cost is that the standing is settled against
## the sect rather than refunded.
func test_leaving_is_never_refused_for_standing_or_position() -> void:
	var actor := _sworn(&"maximal", 100)
	SectApi.promote(actor, STEWARD, true)
	assert_eq(String(SectApi.state(actor)["position"]), String(STEWARD), "holds the top seat")
	assert_eq(int(SectApi.state(actor)["standing"]), 100, "at the authored cap")
	var left := SectApi.leave(actor)
	assert_eq(bool(left["ok"]), true, "a maximal member may still leave")
	assert_eq(String(left["reason"]), "", "with no reason at all")
	var state := SectApi.state(actor)
	assert_eq(String(state["institution"]), "", "the claim is closed")
	assert_eq(String(state["position"]), "", "and so is the office")
	assert_eq(int(state["standing"]), 0, "the standing the sect gave is settled, not carried")
	assert_eq(_own_modifiers(actor), 0, "nothing of ours is left projected")


## A second `leave` is refused, and it is refused with a NAMED reason rather than a
## silently successful no-op: "there is nothing to leave" is a different statement
## from "you are not allowed to leave", and only one of them is a refusal.
func test_leaving_with_nothing_to_leave_is_refused_by_name_and_writes_nothing() -> void:
	var actor := _member()
	var before := SectApi.state(actor)
	var left := SectApi.leave(actor)
	assert_eq(bool(left["ok"]), false, "there was nothing to leave")
	assert_eq(String(left["reason"]), SectApi.NOT_A_MEMBER, "and it names itself")
	assert_eq(SectApi.state(actor), before, "and the ledger is byte-for-byte as found")
	# The same refusal after a real departure, which is the case a double-click hits.
	SectApi.join(actor, HOUSE)
	SectApi.leave(actor)
	var after := SectApi.state(actor)
	assert_eq(bool(SectApi.leave(actor)["ok"]), false, "a second leave is refused too")
	assert_eq(SectApi.state(actor), after, "and writes nothing")


func test_leaving_a_sect_something_refuses_on_would_c_still_be_permitted() -> void:
	# A seat with capacity 1 is the case that matters: refusing a departure because
	# the seat is taken would leave an institution holding a member it cannot be rid
	# of, which is the "bad state with no out" ADR 0084 rules out. The overflow
	# refusal below never applies to `leave`.
	var actor := _sworn(&"seated", 100)
	# A capacity of 1 refused as `capacity_full` rather than taken, because the floor
	# is 60 and this member has 100. So the refusal under test is the seat, not the
	# standing: `promote` answers about the room only once the route to it is open.
	var occupied := SectApi.promote(actor, STEWARD, false, 1)
	assert_eq(String(occupied["reason"]), SectApi.SEAT_OCCUPIED, "the seat is already taken")
	# Filling it is what forces the promotion, and the trail has to say so: a panel
	# reading "in the occupied seat" from a forced admit is reading a true sentence.
	SectApi.promote(actor, STEWARD, true, 1)
	assert_eq(String(SectApi.state(actor)["position"]), String(STEWARD), "in the occupied seat")
	assert_eq(bool(SectApi.leave(actor)["ok"]), true, "and leaving is still permitted")


# --- Overflow is a refused admit, never a silent trim ------------------------


## `seat_occupied` when the authored cap is **1**. The refusal names the seat, the
## ledger is untouched, and the roster is not trimmed — a refused admit that quietly
## promoted somebody else would be an admission by surprise.
func test_a_capacity_overflow_is_a_refused_admit_named_seat_occupied_and_changes_nothing() -> void:
	var actor := _sworn(&"disciple", 100)
	var before := SectApi.state(actor)
	var promoted := SectApi.promote(actor, STEWARD, false, 1)
	assert_eq(bool(promoted["ok"]), false, "the seat is occupied")
	assert_eq(String(promoted["reason"]), SectApi.SEAT_OCCUPIED, "and it says so by name")
	assert_eq(SectApi.state(actor), before, "the ledger is byte-for-byte as found")
	assert_eq(String(SectApi.state(actor)["position"]), "", "no office was invented for them")
	assert_eq(_own_modifiers(actor), 0, "and the overflow granted nothing at all")
	# The same office with room to take the promotion lands, which is what makes the
	# refusal about the seat rather than about the actor.
	assert_eq(bool(SectApi.promote(actor, STEWARD, false, 0)["ok"]), true, "an empty seat admits")
	assert_eq(String(SectApi.state(actor)["position"]), String(STEWARD), "and grants the office")


## `capacity_full` when the authored cap is **above 1** and every slot is filled.
## Same ledger guarantee, different word — and the word is the whole point.
func test_a_capacity_overflow_on_a_multi_seat_office_is_refused_named_capacity_full() -> void:
	var actor := _sworn(&"disciple", 100)
	var before := SectApi.state(actor)
	var promoted := SectApi.promote(actor, ARCHIVIST, false, 2)
	assert_eq(bool(promoted["ok"]), false, "the room is full")
	assert_eq(String(promoted["reason"]), SectApi.CAPACITY_FULL, "and it says so by name")
	assert_eq(SectApi.state(actor), before, "the ledger is byte-for-byte as found")
	assert_eq(_own_modifiers(actor), 0, "and the overflow granted nothing")
	# One holder in a two-seat office is not full, so the same call lands.
	assert_eq(
		bool(SectApi.promote(actor, ARCHIVIST, false, 1)["ok"]),
		true,
		"one holder in a two-seat office still admits"
	)
	assert_eq(bool(SectApi.promote(actor, ARCHIVIST, false, 2)["ok"]), false, "the second does not")


## The two words are distinct, and the distinction is load-bearing: a seat produces
## a succession contest and a room produces a queue. One string for both would
## collapse "somebody has to leave, die or be expelled" into "come back later".
func test_seat_occupied_and_capacity_full_are_distinct_words_from_the_same_authored_def() -> void:
	var def := _def()
	var seat := def.seat_state(STEWARD, 0)
	assert_eq(bool(seat["has_room"]), true, "an empty seat has room")
	assert_eq(String(seat["reason"]), "", "and no refusal to name")
	var taken := def.seat_state(STEWARD, 1)
	assert_eq(bool(taken["has_room"]), false, "a taken seat does not")
	assert_eq(String(taken["reason"]), SectApi.SEAT_OCCUPIED, "and it is a seat, not a room")
	var room_open := def.seat_state(ARCHIVIST, 1)
	assert_eq(bool(room_open["has_room"]), true, "a two-seat office with one holder has room")
	var room_full := def.seat_state(ARCHIVIST, 2)
	assert_eq(bool(room_full["has_room"]), false, "with two holders it does not")
	assert_eq(String(room_full["reason"]), SectApi.CAPACITY_FULL, "and it is a room, not a seat")
	assert_ne(
		String(taken["reason"]), String(room_full["reason"]), "the two words are not the same word"
	)
	# The boundary is inclusive on `held`, so a room refuses its second admit at
	# exactly its authored cap and not one earlier. Read off the definitions rather
	# than assumed: `ARCHIVIST` is a room of two and `READER` a room of three, so a
	# loop asking "three of three" of either of the others would be asserting a room
	# this sect does not author.
	for office_id in [READER, ARCHIVIST]:
		var capacity := _def().position(office_id).capacity
		assert_eq(
			capacity, ROOM_CAPACITY if office_id == READER else 2, "%s' authored cap" % office_id
		)
		for held in capacity:
			assert_eq(
				bool(_def().seat_state(office_id, held)["has_room"]),
				true,
				"'%s' with %d of %d held still has room" % [office_id, held, capacity]
			)
		assert_eq(
			bool(_def().seat_state(office_id, capacity)["has_room"]),
			false,
			"'%s' with all %d held is full" % [office_id, capacity]
		)
		assert_eq(
			String(_def().seat_state(office_id, capacity)["reason"]),
			SectApi.CAPACITY_FULL,
			"'%s' full is a shut room, never a succession contest" % office_id
		)
	# An office nobody authored cannot admit anybody, and it is the full reason
	# rather than the seat reason: there is no seat here at all.
	assert_eq(
		String(_def().seat_state(&"t_no_such_office", 0)["reason"]),
		SectApi.CAPACITY_FULL,
		"an unshipped office admits nobody"
	)


func test_a_refused_promotion_never_trims_the_roster() -> void:
	# "A refused admit, never a silent trim" (ADR 0084): the overflowing member gets
	# nothing, and nobody who already holds the seat loses it. This module holds no
	# roster, so the guarantee is that the refused caller is left exactly as found.
	var holder := _sworn(&"holder", 100)
	SectApi.promote(holder, ARCHIVIST, false, 1)
	var holder_before := SectApi.state(holder)
	var refused := _sworn(&"refused", 100)
	var promoted := SectApi.promote(refused, ARCHIVIST, false, 2)
	assert_eq(bool(promoted["ok"]), false, "the second admit was refused")
	assert_eq(SectApi.state(holder), holder_before, "and the incumbent's claim is untouched")
	assert_eq(String(SectApi.state(holder)["position"]), String(ARCHIVIST), "office retained")
	assert_eq(String(SectApi.state(refused)["position"]), "", "the refused caller got nothing")


# --- The other refusals, named -----------------------------------------------


func test_every_membership_refusal_is_named_and_writes_nothing() -> void:
	var stranger := _member()
	var before := SectApi.state(stranger)
	# A sect nothing defines teaches nothing and grants nothing, so a claim against
	# one is a content bug rather than a player outcome.
	assert_eq(
		String(SectApi.join(stranger, &"t_no_such_house")["reason"]),
		SectApi.UNKNOWN_SECT,
		"an unknown sect is refused by name"
	)
	assert_eq(SectApi.state(stranger), before, "and writes nothing")
	# Joining twice is refused rather than silently re-sworn: the tiers are peers,
	# not a containment tree (ADR 0083).
	assert_eq(bool(SectApi.join(stranger, HOUSE)["ok"]), true, "the first join lands")
	var sworn := SectApi.state(stranger)
	assert_eq(String(SectApi.join(stranger, HOUSE)["reason"]), SectApi.ALREADY_SWORN, "named")
	assert_eq(
		String(SectApi.join(stranger, &"t_rival_house")["reason"]), SectApi.ALREADY_SWORN, "named"
	)
	assert_eq(SectApi.state(stranger), sworn, "neither wrote anything")
	# An office this sect does not author cannot be filled.
	assert_eq(
		String(SectApi.promote(stranger, &"t_no_such_office", true)["reason"]),
		SectApi.UNKNOWN_POSITION,
		"an unknown office is refused by name"
	)
	# And a standing move by a member of nothing is refused the same way.
	var unaffiliated := _member(&"nobody")
	assert_eq(
		String(SectApi.move_standing(unaffiliated, 10)["reason"]),
		SectApi.NOT_A_MEMBER,
		"standing needs a membership"
	)
	assert_eq(
		String(SectApi.promote(unaffiliated, STEWARD, true)["reason"]),
		SectApi.NOT_A_MEMBER,
		"and so does a promotion"
	)


## `standing_below_floor` is **a route, not a wall** (ADR 0084): it refuses by name,
## reports how far short the member fell, and leaves the exception expressible. A
## gate that made the exception unreachable would have thrown the politics away —
## that is exactly what ADR 0064's two-part split exists for.
func test_the_promotion_floor_is_a_named_route_and_stays_expressible() -> void:
	var actor := _sworn(&"thin", 5)
	var promoted := SectApi.promote(actor, STEWARD)
	assert_eq(bool(promoted["ok"]), false, "thin standing does not take the top seat")
	assert_eq(String(promoted["reason"]), SectApi.STANDING_BELOW_FLOOR, "and it names the floor")
	assert_eq(int(promoted["required"]), 60, "reporting what the office needs")
	assert_eq(int(promoted["actual"]), 5, "and what the member actually has")
	assert_eq(String(SectApi.state(actor)["position"]), "", "so nothing was written")
	# The exception is reachable, and it says in the trail that it was forced.
	assert_eq(bool(SectApi.promote(actor, STEWARD, true)["ok"]), true, "the route is open")
	assert_eq(String(SectApi.state(actor)["position"]), String(STEWARD), "so the seat filled")
	assert_eq(int(SectApi.state(actor)["standing"]), 5, "and standing is still exactly 5")
	assert_eq(
		_history_kinds(SectApi.state(actor)), ["promote_forced"], "the trail names the exception"
	)
	# Earning the standing first is the ordinary route, and it leaves no mark.
	var earned := _sworn(&"earned", 60)
	assert_eq(bool(SectApi.promote(earned, STEWARD)["ok"]), true, "the floor is met")
	assert_eq(_history_kinds(SectApi.state(earned)), ["promote"], "and the trail says promote")


func test_standing_moves_both_ways_and_a_move_that_lands_nothing_is_refused_by_name() -> void:
	var actor := _sworn(&"climber", 50)
	# The office is what carries the recognition: `standing_percent_stats` is
	# authored per position, so a member holding no office contributes nothing
	# however much standing they have. Seated first, or the grant below is 0.0
	# for a reason that has nothing to do with standing moving.
	assert_eq(bool(SectApi.promote(actor, STEWARD, true)["ok"]), true, "seated first")
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		0.05,
		"the seat recognises on its own",
	)
	assert_eq(int(SectApi.move_standing(actor, 30)["applied"]), 30, "standing rises")
	assert_eq(int(SectApi.state(actor)["standing"]), 80, "and the ledger moved with it")
	# Standing can FALL — a demotion has to be as well tested as a promotion, because
	# a falling number is the only way a member ever loses a grant.
	assert_eq(int(SectApi.move_standing(actor, -30)["applied"]), -30, "standing falls")
	assert_eq(int(SectApi.state(actor)["standing"]), 50, "and the ledger moved again")
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		0.05,
		"so the granted percent fell with it"
	)
	# A move that cannot land is a refusal writing nothing, not a silent success.
	# `applied` is what ACTUALLY landed rather than what was asked for: this claim
	# stands at 50 under a cap of 100, so a 1000-point gain can only be 50, and a
	# facade that published the request would have a caller credit a member with
	# standing it never earned.
	var at_cap := SectApi.move_standing(actor, 1000)
	assert_eq(
		int(at_cap["applied"]), 50, "the cap bounds what a huge gain applies, not the request"
	)
	assert_eq(bool(at_cap["ok"]), true, "a partly-landed move is a success, not a refusal")
	assert_eq(int(SectApi.state(actor)["standing"]), 100, "and the claim rests at the cap")
	var before := SectApi.state(actor)
	var refused := SectApi.move_standing(actor, 10)
	assert_eq(bool(refused["ok"]), false, "a claim already at its cap gains nothing")
	assert_eq(String(refused["reason"]), SectApi.NO_CHANGE, "and it says so by name")
	assert_eq(SectApi.state(actor), before, "writing nothing at all")
	assert_eq(bool(SectApi.move_standing(actor, 0)["ok"]), false, "a zero move is refused too")


# --- Helpers -----------------------------------------------------------------


func _history_kinds(ledger: Dictionary) -> Array:
	var out: Array = []
	for record in ledger["history"] as Array:
		out.append(String(record["kind"]))
	return out


func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if SectState.is_own_source(modifier.source):
			total += 1
	return total
