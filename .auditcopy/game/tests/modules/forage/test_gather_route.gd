extends "res://tests/modules/forage/gather_route_fixture.gd"

## ## This file holds the DELIVERY half of the `gather` acquisition route
##
## The realm gate a shallow actor is stopped by, and then the granter's own probe --
## refuse, measure, grant short, grant whole -- driven end to end through
## `ForageAction.gather`, with the ledger and the bag read on the two sides of it.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every case below is the original body verbatim, and every constant, fixture
## and helper it uses lives in `gather_route_fixture.gd`, which both halves `extends`.
##
## `setup()` / `teardown()` and the fixtures live in that base, because the catalog
## singleton, the holdings store and the granter seam are PROCESS-WIDE: state installed
## by one half and cleared by the other outlives the suite.
##
## The upkeep/depletion, structural-guard and screen-binding half is
## `test_gather_route_wear_and_wiring.gd`.

# --- the realm gate ------------------------------------------------------------


## A deep node refuses a shallow actor BY NAME, and the refusal costs the shallow actor
## nothing — no yield, no upkeep, no condition spent.
##
## This is ADR 0097's gate: realm is a GATE and never a yield multiplier, and the reason
## `ResourceNodeDef.realm` exists at all. A gate that returned true for anyone, or that
## charged a shallow actor for asking, would not be a gate.
func test_a_deep_node_refuses_a_shallow_actor_with_the_named_reason() -> void:
	_claim(_actor, &"t_deep")
	var result := ForageAction.gather(_actor, &"t_deep", 3)
	assert_eq(bool(result["ok"]), false, "a shallow actor cannot work a deep node")
	assert_eq(
		String(result["reason"]),
		ForageApi.REALM_BELOW_GATE,
		"and the refusal names the rule, not free text"
	)
	assert_eq(int(result["yielded"]), 0, "and no yield was credited")
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the bag is untouched: a refused gate costs nothing"
	)


## The same actor, the same node, and one rung of standing: the gate is a comparison on the
## ladder, not a whitelist, so an actor AT the node's realm works it.
func test_an_actor_at_the_node_realm_is_permitted() -> void:
	var deep := _miner(&"t_deep_miner", DEEP_REALM)
	_claim(deep, &"t_deep")
	var result := ForageAction.gather(deep, &"t_deep", 2)
	assert_eq(
		bool(result["ok"]), true, "an actor at the node's realm works it: %s" % result["reason"]
	)
	assert_eq(int(result["yielded"]), 12, "yield_per_period 6 over 2 periods")


## The gate is "at or above", not "strictly above": an actor DEEPER than the node must still
## work it, or the ladder would forbid a veteran from a beginner's field.
func test_an_actor_above_the_node_realm_is_still_permitted() -> void:
	var old_hand := _miner(&"t_old_hand", &"nascent_soul")
	_claim(old_hand, &"t_shallow")
	var result := ForageAction.gather(old_hand, &"t_shallow", 1)
	assert_eq(
		bool(result["ok"]), true, "a deeper actor works a shallow node: %s" % result["reason"]
	)


# --- the delivery --------------------------------------------------------------


## THE probe, and the one hole in this suite until now.
##
## ## What was missing, and why every case above missed it
##
## Every case in this section forages into an EMPTY bag, where the probe's answer and "yes,
## all of it fits" are the same number. Nothing here ever made `ForageGranary._fits` report
## LESS than what was asked, so the function could be rewritten to `return maxi(0, quantity)`
## -- a probe that ALWAYS promises delivery -- and all 99 cases across the two gather suites
## stayed green. The claim in the docblock ("so a full bag accrues nothing") was asserted by
## nothing; this section is what asserts it.
##
## ## Why these fixtures block the bag with STACKS
##
## ## A bag is only "full" to `_add_batch` when its STACKS are full, and that is not the same
## ## question `used_slots()` answers. `Inventory._add_batch` refuses a new stack on
## ## `if _stacks.size() >= capacity`, counting `_stacks` ALONE -- while `_add_instances`
## ## refuses on `used_slots() < capacity`, which also counts instances. So a bag whose slots
## ## are all taken by non-stackable `ItemInstance`s still accepts stack after stack.
## ##
## ## Two earlier attempts at this fixture were wrong in exactly that way: both filled the bag
## ## with non-stackable goods, the bag reported `is_full() == true`, and the probe then
## ## cheerfully appended a fresh stack past capacity. So the blockers here are all
## ## `ItemStack`s, which is what `_add_batch` actually counts.
##
## ## And the yielded good is a 99-max STACKABLE, which is the only shape that makes the
## ## probe's answer exact. A stack already at `max_stack` cannot be grown by a merge, so the
## ## only room left in a bag holding one is a free SLOT -- and how much of the request fits
## ## then depends on how many slots are left, which is a number this section measures rather
## ## than assumes.
func test_a_full_bag_refuses_the_harvest_and_accrues_nothing() -> void:
	var packed := _miner(&"t_packer", SHALLOW_REALM, 1)
	_fill_bag(packed)
	assert_eq(
		ItemsApi.inventory(packed).is_full(),
		true,
		(
			"setup: the bag is full (%d of %d slots)"
			% [ItemsApi.inventory(packed).used_slots(), ItemsApi.inventory(packed).capacity]
		)
	)

	_claim(packed, &"t_vein")
	var result := ForageAction.gather(packed, &"t_vein", 1)
	# ## The refusal, and WHICH constant it is
	#
	# `ForageApi.GRANT_REFUSED`, reached by the `int(room["granted"]) <= 0` guard -- and that is
	# the correct answer, not a quirk of my reading. `ForageGranary.deliver` wraps its
	# `BAG_FULL` probe answer in `_answer(ok = true, ...)`, so the granter reports "nothing
	# fits" as a SUCCESSFUL read of a full bag, and `harvest` is the module that turns "zero
	# would fit" into a refusal. `ForageGranary.BAG_FULL` is therefore NOT reachable through
	# this path; asserting it would have asserted a branch that cannot execute. What is asserted
	# is the id the route really produces, and asserting it by name rather than only
	# `ok == false` means a forager that refused EVERYTHING could not pass.
	assert_eq(bool(result["ok"]), false, "a bag with no room is not foraged: %s" % result["reason"])
	assert_eq(
		String(result["reason"]),
		ForageApi.GRANT_REFUSED,
		"named `grant_refused`: the probe answered zero and the route refused on it"
	)
	assert_eq(
		int(result["granted"]),
		0,
		"and the caller is told the harvest delivered NOTHING rather than a short count"
	)
	# ## The atomicity itself: the bag is consulted BEFORE `accrue`, so nothing was charged
	#
	# This is the sentence the docblock makes. Without it a bag-full harvest could still credit
	# the node and bill its upkeep, and the player would pay for a delivery that could not
	# happen -- which is the entire reason `harvest` probes before it mutates anything.
	var line: Dictionary = HoldingsApi.state(packed)["line"] as Dictionary
	assert_eq(int(line.get("t_vein", 0)), 0, "no yield is accrued onto the node's line")
	assert_eq(
		int(line.get("actor:upkeep:%s" % String(packed.id), 0)),
		0,
		"and no upkeep is charged, so a refused harvest costs the holder nothing"
	)


## The probe's NUMBER, which is the half `harvest` short-circuits past on a full bag.
##
## ## Why this is a separate case from the refusal above
##
## Because `harvest` returns at `granted <= 0` before it ever reads a positive count, so the
## case above proves the probe's "refuse" half and nothing else. The answer asserted here is
## non-zero AND strictly less than the request, so it is an assertion on the VALUE: a probe
## that refused everything and a probe that promised everything both fail it, and the mutation
## under test (`return maxi(0, quantity)`) fails it by answering the whole request.
func test_the_probe_reports_how_many_units_actually_fit_rather_than_how_many_were_asked_for(
) -> void:
	var good := _plain_stackable()
	assert_ne(good, null, "setup: the measured good is on disk, where Crafting.resolve can find it")
	_assert_plain(good)
	var stack_size := good.max_stack
	var request := stack_size + 1

	# ## The fixture: a ONE-STACK bag already holding one of the measured good
	#
	# Capacity 1, so no second stack can ever be opened. One unit is in the bag, so the open
	# stack has `stack_size - 1` of room, and asking for `stack_size + 1` merges `stack_size - 1`
	# into it and leaves 2 with nowhere to go. The measured answer is `stack_size - 1`: large,
	# exact, and strictly less than the request, which is the only shape that tests the VALUE.
	var tight := _miner(&"t_tight", SHALLOW_REALM, 1)
	var inventory := ItemsApi.inventory(tight)
	assert_eq(inventory.add(good, 1), 0, "setup: one unit landed")
	assert_eq(inventory.used_slots(), 1, "setup: one stack")
	assert_eq(inventory.is_full(), true, "setup: and the bag is full of STACKS")

	var measured := ForageGranary.deliver(tight, good.id, request, true)
	assert_eq(
		bool(measured["ok"]),
		true,
		"the probe answers rather than refusing: %s" % measured.get("reason", "")
	)
	assert_eq(
		int(measured["granted"]),
		stack_size - 1,
		"and it MEASURED %d of the %d asked for" % [stack_size - 1, request]
	)
	assert_eq(
		int(measured["granted"]) < request,
		true,
		"the shortfall is a number strictly less than the request, which is the claim"
	)
	# The probe is a pure read, which is the other half of the atomicity and the reason
	# `snapshot()` exists at all.
	assert_eq(
		inventory.used_slots(),
		1,
		"and it moved nothing: a snapshot the probe adds onto cannot reach the live bag"
	)
	assert_eq(inventory.count(good.id), 1, "including the stack it measured against")
	# And the ZERO answer on a bag with no room at all, which no partial fixture can give.
	var blocked := _miner(&"t_blocked", SHALLOW_REALM, 1)
	_fill_bag(blocked)
	var none := ForageGranary.deliver(blocked, StringName(FIXTURE_ITEM), 2, true)
	assert_eq(bool(none["ok"]), true, "a bag with no room is still a question the probe answers")
	assert_eq(
		int(none["granted"]),
		0,
		"and it answers ZERO: a probe that always promises delivery is not a probe"
	)


## The route refuses a SHORT harvest, names it, and reports the short count.
##
## ## Why the shortfall has to live INSIDE one stack
##
## `harvest` PROBES with `yield_per_period` and GRANTS `yield_per_period * periods`. For the
## grant to come up short it must exceed the room the probe found, and with the measured good
## in a one-stack bag that room is exactly one stack. So the grant asked for is one unit beyond
## it, the probe answers the stack, and the grant delivers the stack and leaves the rest behind.
## The node yields 6 per period, so eleven periods is 66 units against a 63-unit room: three
## over. Eleven is not a trick -- it is the same verb with a bigger count, and the exact counts
## are derived from `stack_size` below rather than written in.
##
## ## Why `grant_short` and not `grant_refused`
##
## `ok == false` in both branches, and only the NAME separates "the granter took nothing" from
## "the granter took part of it". A caller rendering "your bag was full" against a harvest
## that delivered 63 of 66 is showing a false fact, so the constant is asserted by value.
func test_a_harvest_the_bag_cannot_hold_whole_is_named_grant_short_with_the_real_count() -> void:
	var good := _plain_stackable()
	assert_ne(good, null, "setup: the measured good is on disk, where Crafting.resolve can find it")
	_assert_plain(good)
	var stack_size := good.max_stack
	# A node whose yield does not divide the stack size evenly leaves an awkward remainder, so
	# the period count is CEILING and the grant is `6 * that` -- assertably more than the room,
	# and checked rather than assumed.
	var periods := (stack_size + 5) / 6
	var asked := periods * 6
	assert_eq(
		asked > stack_size,
		true,
		(
			"setup: the grant asked for %d exceeds the %d a one-stack bag can take"
			% [asked, stack_size]
		)
	)

	var half := _miner(&"t_half", SHALLOW_REALM, 1)
	# One unit in the bag, so the open stack has `stack_size - 1` of room: the probe answers
	# `stack_size - 1` and the grant of `asked` delivers `stack_size - 1` and leaves the rest.
	assert_eq(ItemsApi.inventory(half).add(good, 1), 0, "setup: one unit landed")

	# The node has to yield `good`, so it is installed here rather than reusing a fixture whose
	# yield table points at the charm. Installing a node is the same seam `setup` uses.
	#
	# The realm is SHALLOW, matching the miner above: a `DEEP_REALM` node is correctly
	# refused `realm_below_gate` before the bag is ever consulted, so measuring a shortfall
	# against it measures the gate instead of the granter.
	_install_node(PLAIN_NODE, SHALLOW_REALM, 6, 0, 0)
	_claim(half, PLAIN_NODE)
	var result := ForageAction.gather(half, PLAIN_NODE, periods)
	assert_eq(
		bool(result["ok"]),
		false,
		(
			"a harvest the bag cannot hold whole is a refusal, not a partial success: %s"
			% result["reason"]
		)
	)
	assert_eq(
		String(result["reason"]),
		ForageApi.GRANT_SHORT,
		(
			(
				"named `grant_short` rather than `grant_refused`: part of it DID arrive "
				+ "(granted=%d of %d, item=%s)"
			)
			% [int(result["granted"]), asked, String(result["item_id"])]
		)
	)
	# The granter moved a real number of units and `granted` reports it, so a caller can render
	# "98 of 102 delivered" rather than a bare refusal. Asserted because the mutation this suite
	# was written against makes exactly this number WRONG.
	assert_eq(
		int(result["granted"]),
		stack_size - 1,
		(
			"and the short count is the measured one: %d of the %d really did land"
			% [stack_size - 1, asked]
		)
	)
	# The line is settled BEFORE the grant, so the ledger must not still be holding the units
	# nobody received -- the reason a short delivery has to be named rather than banked.
	# Keyed on PLAIN_NODE: this used to read "t_plain", a literal that happened to match the
	# node the fixture installed, so it stayed correct by coincidence while the node id moved.
	var line: Dictionary = HoldingsApi.state(half)["line"] as Dictionary
	assert_eq(
		int(line.get(String(PLAIN_NODE), 0)),
		0,
		"and the accrued line was settled, so the ledger and the bag cannot both claim them"
	)
	assert_eq(
		ItemsApi.has_item(half, good.id, stack_size - 1),
		true,
		"while the bag really did receive the units that fit"
	)


## THE end-to-end claim of this suite: foraging a held node credits
## `yield_per_period * periods` units AND the actor ends up holding real items.
##
## Both halves are asserted, because either alone is satisfiable by a lie. A forager that
## credited units and granted nothing would pass a ledger assertion; one that conjured
## items without accruing would pass a bag assertion. The yield is read from the LEDGER and
## the goods from the BAG, so the two sides cannot be satisfied by the same fiction.
func test_foraging_a_held_node_accrues_the_authored_yield_and_grants_items() -> void:
	_claim(_actor, &"t_shallow")
	var result := ForageAction.gather(_actor, &"t_shallow", 3)
	assert_eq(bool(result["ok"]), true, "the harvest is accepted: %s" % result.get("reason", ""))
	assert_eq(int(result["periods"]), 3, "the caller's periods are honoured verbatim")
	assert_eq(
		int(result["yielded"]), 15, "yield_per_period 5 over 3 periods is credited to the line"
	)
	assert_eq(int(result["granted"]), 15, "and the same units reach the bag")
	var item_id := String(result["item_id"])
	assert_ne(item_id, "", "the node names an item, which is the fact a node cannot carry")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(item_id), 15),
		true,
		"and the actor really holds them: %d of '%s'" % [15, item_id]
	)
	# The line was settled, so the ledger and the bag never both claim the same units.
	assert_eq(
		int(HoldingsApi.state(_actor)["line"].get("t_shallow", 0)),
		0,
		"the accrued line is settled, not double-counted"
	)


## The yield really is `yield_per_period * periods` and not a constant: two different
## period counts on the same node must produce two different totals.
func test_the_granted_quantity_scales_with_periods() -> void:
	_claim(_actor, &"t_shallow")
	ForageAction.gather(_actor, &"t_shallow", 1)
	var two := ForageAction.gather(_actor, &"t_shallow", 2)
	assert_eq(int(two["yielded"]), 10, "2 periods of a 5-unit node is 10")
	assert_eq(int(two["granted"]), 10, "and all ten are granted")


## Foraging a node you do NOT hold refuses — with the holder mismatch named by the module
## that owns the ledger, rather than a restatement here.
func test_foraging_a_node_you_do_not_hold_refuses() -> void:
	var rival := _miner(&"t_rival", SHALLOW_REALM)
	_claim(rival, &"t_shallow")
	var result := ForageAction.gather(_actor, &"t_shallow", 1)
	assert_eq(bool(result["ok"]), false, "a non-holder cannot forage a held node")
	assert_eq(
		String(result["reason"]),
		HoldingsState.HOLDER_MISMATCH,
		"and the refusal is holdings' own id, passed through by name"
	)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the trespasser's bag is empty"
	)


## An unclaimed node is not a node the caller may work: `no_holder`, not `holder_mismatch`.
## The two are different facts and a caller that saw only "refused" could not tell a vacant
## vein from someone else's.
func test_foraging_an_unclaimed_node_refuses_no_holder() -> void:
	var result := ForageAction.gather(_actor, &"t_shallow", 1)
	assert_eq(bool(result["ok"]), false, "a node nobody holds cannot be foraged")
	assert_eq(String(result["reason"]), HoldingsState.NO_HOLDER, "and names the vacant state")


## A node that is not in the catalog at all refuses `unknown_node`, so a stale node id is a
## named refusal rather than a null dereference somewhere downstream.
func test_foraging_an_unknown_node_refuses() -> void:
	var result := ForageAction.gather(_actor, &"no_such_node", 1)
	assert_eq(bool(result["ok"]), false, "an unknown node refuses")
	assert_eq(String(result["reason"]), HoldingsState.UNKNOWN_NODE, "and names the rule")
