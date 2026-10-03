extends TestCase

## Territory as a **claim over places** (BL-0182..BL-0185).
##
## The invariant every case here exists to protect is one sentence: **a claim on held
## ground never moves ground.** A challenge writes a challenger and opens exactly one
## standoff, and `holder_id` is byte-identical before and after. Without that, a
## "claim" and a "conquest" are the same word and the module cannot tell a player
## that a war was opened.
##
## The second half is accrual: yield and upkeep settle against an **explicit `periods`
## argument** from a caller that owns time. There is no clock in this repo (DEF-0111),
## so a module that invented one would be a second source of truth for when a save
## happened — and that is checked structurally in `test_nation_conflict.gd`.

const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"
const HELD := &"river_march"
## A second authored claim, so a release leaves the first standing.
const OTHER := &"ashen_wold"
const UNKNOWN := &"a_territory_nobody_authored"


func _actor() -> Actor:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, MARCH, "polity_a")
	return actor


func _holder(actor: Actor, territory_id: StringName) -> String:
	return NationState.holder_of(NationApi.state(actor), territory_id)


func _claims(actor: Actor) -> Dictionary:
	return (NationApi.state(actor)["claims"] as Dictionary).duplicate(true)


# --- Unheld ground is a take ----------------------------------------------


func test_claiming_unheld_ground_writes_a_take_with_this_polity_as_holder() -> void:
	var actor := _actor()
	var result := NationApi.claim_territory(actor, HELD)
	assert_eq(bool(result.get("ok", false)), true, "the take succeeded: %s" % result)
	# `holder_id` is the POLITY's id, not the actor's: a claim over places belongs to
	# the nation whose law covers it, and the actor only ever speaks for that nation.
	assert_eq(
		String(result.get("holder_id", "")), String(MARCH), "and names the polity as the holder"
	)
	assert_eq(_holder(actor, HELD), String(MARCH), "the ledger agrees")
	assert_eq(
		String(result.get("challenger_id", "")),
		"",
		"a take is not a contest: there is no challenger to write"
	)


func test_claiming_ground_this_polity_already_holds_is_refused_by_a_named_reason() -> void:
	var actor := _actor()
	NationApi.claim_territory(actor, HELD)
	var refused := NationApi.claim_territory(actor, HELD)
	assert_eq(bool(refused.get("ok", false)), false, "you cannot take your own ground")
	assert_eq(
		String(refused.get("reason", "")),
		"territory_already_held",
		"refused with the authored reason, not prose"
	)


func test_an_unknown_territory_is_refused_and_names_itself() -> void:
	var actor := _actor()
	var refused := NationApi.claim_territory(actor, UNKNOWN)
	assert_eq(bool(refused.get("ok", false)), false, "an unauthored claim is refused")
	assert_eq(String(refused.get("reason", "")), "unknown_territory", "with a named reason")
	assert_eq(
		String(refused.get("territory_id", "")),
		String(UNKNOWN),
		"and it names the id the content does not ship"
	)


func test_a_claim_below_the_tier_floor_is_refused_as_a_route_not_a_wall() -> void:
	# ADR 0084: the standing floor is a ROUTE, not a wall. So the refusal names it
	# and reports both numbers, so a caller can show the player how far they are.
	#
	# ## And the case PICKS a territory whose floor its polity is actually under
	#
	# This used to `return` when the actor already met the floor, which is the shape
	# that turns a test into a silent no-op: the suite went green because the one
	# assertion that mattered never ran. A polity is AUTHORED at a starting
	# standing (`NationDef.claim`) rather than beginning at zero, so the tier has to
	# be chosen against the shipped content instead of assumed. The scan finds the
	# deepest tier the polity cannot meet, and ASSERTS it found one — so a rebalance
	# that made every tier reachable from a fresh polity fails loudly instead of
	# quietly skipping the case a second time.
	var actor := _actor()
	var standing := int(NationApi.summary(actor)["standing"])
	var tuning := NationCatalog.instance().tuning()
	var blocked := &""
	var floor := 0.0
	for territory_id in _all_territory_ids():
		var tier := NationCatalog.instance().territory_definition(territory_id).tier_index
		if float(standing) < tuning.claim_floor_for(tier):
			blocked = territory_id
			floor = tuning.claim_floor_for(tier)
			break
	assert_eq(
		blocked == &"",
		false,
		"this build authors a claim floor above a fresh polity's standing %d" % standing,
	)
	var refused := NationApi.claim_territory(actor, blocked)
	assert_eq(bool(refused.get("ok", false)), false, "below the floor the claim is refused")
	assert_eq(String(refused.get("reason", "")), "standing_below_floor", "with the authored reason")
	assert_eq(int(refused.get("standing", 0)), standing, "reporting the standing it read")
	assert_eq(float(refused.get("floor", 0.0)), floor, "and the floor it needed")
	# And the route is open: a refusal names the shortfall rather than hiding it.
	assert_eq(float(refused.get("floor", 0.0)) > standing, true, "the shortfall is visible")


## Every authored territory id, so the case above scans content rather than
## hard-coding one. A hard-coded id is a test that breaks when a `.tres` is renamed
## and says nothing about the tiers it never looked at.
func _all_territory_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for territory_id in NationCatalog.instance().territory_ids():
		out.append(territory_id)
	return out


# --- Held ground: the load-bearing invariant -------------------------------


func test_a_claim_on_held_ground_writes_a_challenger_and_moves_no_ground() -> void:
	# THE case. Ground another polity holds: this writes a challenger and opens one
	# standoff, and `holder_id` must be byte-identical before and after. If this ever
	# changes, a "claim" has become a "conquest" and the two are one word.
	var rival := _holder_actor_with_ground()
	var before := _claims(rival)
	var result := NationApi.claim_territory(rival, HELD)
	assert_eq(bool(result.get("ok", false)), true, "the challenge succeeded: %s" % result)
	assert_eq(
		String(result.get("challenger_id", "")),
		String(COURT),
		"and it wrote this polity as the challenger"
	)
	assert_eq(
		String(result.get("holder_id", "")),
		String(MARCH),
		"while still naming the INDEPENDENT holder, not the challenger"
	)

	var after := _claims(rival)
	assert_eq(
		String(after[String(HELD)]["holder_id"]),
		String(before[String(HELD)]["holder_id"]),
		"holder_id is byte-identical before and after a claim"
	)
	assert_eq(
		String(after[String(HELD)]["challenger_id"]),
		String(COURT),
		"and the challenger is what actually changed"
	)


func test_a_claim_on_held_ground_opens_exactly_one_standoff() -> void:
	var rival := _holder_actor_with_ground()
	var standoffs_before := (NationApi.state(rival)["standoffs"] as Dictionary).size()
	var result := NationApi.claim_territory(rival, HELD)
	assert_eq(bool(result.get("ok", false)), true, "the challenge succeeded: %s" % result)
	var standoffs := NationApi.state(rival)["standoffs"] as Dictionary
	assert_eq(standoffs.size(), standoffs_before + 1, "exactly one standoff was opened")
	# And it declared a prize, because a war without one cannot exist (ADR 0085).
	for standoff in standoffs.values():
		var prize: Dictionary = (standoff as Dictionary)["prize"]
		assert_ne(String(prize.get("transfer", "")), "", "the standoff declares a prize")


func test_claiming_ground_twice_over_does_not_stack_challengers() -> void:
	var rival := _holder_actor_with_ground()
	NationApi.claim_territory(rival, HELD)
	NationApi.claim_territory(rival, HELD)
	var standoffs := NationApi.state(rival)["standoffs"] as Dictionary
	assert_eq(standoffs.size(), 2, "each challenge opens its own standoff")
	# The challenger is an id, not a list, so a second challenge overwrites rather
	# than accumulating — a claim is one challenger, and the standoffs are the trail.
	assert_eq(
		String(_claims(rival)[String(HELD)]["challenger_id"]),
		"court_of_the_star",
		"the challenger stays a single id"
	)


# --- Releasing: always permitted, and it costs -----------------------------


func test_releasing_a_claim_is_always_permitted_and_removes_the_row() -> void:
	# ADR 0083 rule 3: leaving is always permitted and always costs. A player with no
	# exit is in a bad state with no out, so `release` refuses on nothing but "you do
	# not hold it".
	var actor := _actor()
	NationApi.claim_territory(actor, HELD)
	var released := NationApi.release_territory(actor, HELD)
	assert_eq(bool(released.get("ok", false)), true, "releasing is permitted: %s" % released)
	assert_eq(_claims(actor).has(String(HELD)), false, "and the claim row is gone")
	assert_eq(_holder(actor, HELD), "", "so nobody holds it")


func test_releasing_a_claim_this_polity_does_not_hold_is_refused_by_a_named_reason() -> void:
	var actor := _actor()
	var refused := NationApi.release_territory(actor, UNKNOWN)
	assert_eq(bool(refused.get("ok", false)), false, "there is nothing to release")
	assert_eq(String(refused.get("reason", "")), "territory_not_held", "with the authored reason")


# --- Accrual takes an EXPLICIT period count -------------------------------


func test_accrual_settles_only_the_periods_it_is_handed() -> void:
	# There is no clock in this repo (DEF-0111). The verb takes `periods` as an
	# argument and settles exactly that many, so the caller that owns time is the only
	# thing that decides when a period happened.
	var actor := _actor()
	NationApi.claim_territory(actor, HELD)
	var before := int(NationApi.summary(actor)["standing"])
	var settled := NationApi.accrue_territory(actor, 2)
	assert_eq(bool(settled.get("ok", false)), true, "the accrual succeeded: %s" % settled)
	assert_eq(int(settled.get("periods", 0)), 2, "and it settled the two it was handed")
	assert_eq(int(settled.get("settled", 0)), 1, "against the one claim held")


func test_accrual_moves_standing_and_reads_its_amounts_from_the_tuning() -> void:
	var actor := _actor()
	NationApi.claim_territory(actor, HELD)
	var tuning := NationCatalog.instance().tuning()
	var tier := NationCatalog.instance().territory_definition(HELD).tier_index
	# The net is summed over the whole board and rounded ONCE at the end, so the
	# expected figure is rounded after the multiply rather than before it.
	var expected := int(roundf((tuning.yield_for(tier) - tuning.upkeep_for(tier)) * 2.0))
	var before := int(NationApi.summary(actor)["standing"])
	var cap := int(NationApi.summary(actor)["standing_cap"])
	NationApi.accrue_territory(actor, 2)
	var after := int(NationApi.summary(actor)["standing"])
	var delta := after - before
	assert_eq(
		clampi(before + expected, 0, cap) - before,
		delta,
		"the delta is exactly (yield - upkeep) x periods, read from the .tres"
	)


func test_accrual_at_or_below_zero_periods_writes_nothing() -> void:
	var actor := _actor()
	NationApi.claim_territory(actor, HELD)
	var before := NationApi.state(actor)
	var settled := NationApi.accrue_territory(actor, 0)
	assert_eq(bool(settled.get("ok", false)), true, "zero periods is a no-op, not a refusal")
	assert_eq(int(settled.get("settled", 0)), 0, "and it settled nothing")
	assert_eq(NationApi.state(actor)["standing"], before["standing"], "writing no standing")


func test_accrual_pays_only_for_claims_this_polity_holds() -> void:
	# A row this actor does not speak for is not this actor's income: a claim whose
	# holder is somebody else must not accrue into this ledger.
	var rival := _holder_actor_with_ground()
	var before := int(NationApi.summary(rival)["standing"])
	var settled := NationApi.accrue_territory(rival, 3)
	assert_eq(
		int(settled.get("settled", 0)),
		0,
		"a polity that holds no claim in its own ledger accrues nothing"
	)
	assert_eq(int(NationApi.summary(rival)["standing"]), before, "and pays nothing")


func test_a_territory_def_carries_no_amount_at_all() -> void:
	# A territory is a CLAIM over places. Yield, upkeep and qi density are tuning and
	# live in `NationTuning`, so a rebalance is a `.tres` edit; ADR 0085's "territory
	# grants no combat bonus" means the authored def cannot even hold one.
	var def := NationCatalog.instance().territory_definition(HELD)
	assert_ne(def, null, "the claim is authored")
	for field in def.get_property_list():
		var name := String(field.get("name", ""))
		for word in ["damage", "defense", "combat", "yield", "upkeep", "qi_density", "bonus"]:
			assert_eq(name.contains(word), false, "a claim over places carries no %s field" % word)


# --- Plumbing ---------------------------------------------------------------


## An actor whose ledger already carries a claim held by ANOTHER polity, which is
## the state a save from a wider content build arrives in and the only state in which
## a claim becomes a challenge rather than a take.
func _holder_actor_with_ground() -> Actor:
	var holder := _actor()
	NationApi.claim_territory(holder, HELD)
	var rival := Actor.new(COURT, {Stat.PHYSIQUE: 10.0})
	NationApi.attach(rival)
	NationApi.found(rival, COURT, String(COURT))
	var ledger := NationApi.state(rival)
	var existing: Dictionary = _claims(holder)[String(HELD)]
	existing["holder_id"] = String(MARCH)
	(ledger["claims"] as Dictionary)[String(HELD)] = existing
	rival.set_module_data(NationState.MODULE_KEY, NationState.normalize(ledger))
	return rival
