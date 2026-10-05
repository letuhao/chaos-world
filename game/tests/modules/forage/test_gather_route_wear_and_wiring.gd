extends "res://tests/modules/forage/gather_route_fixture.gd"

## ## This file holds the UPKEEP / DEPLETION, STRUCTURAL-GUARD and SCREEN-BINDING half
##
## What a node costs its holder and spends of its own condition, the named refusals on
## the accrue path, the boundary the design exists to keep (neither facade may name an
## inventory), and the question a screen's enabled state binds to.
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
## The delivery half is `test_gather_route.gd`.

# --- upkeep, depletion, resting ------------------------------------------------


## Upkeep is charged on a node that declares it, and is charged AGAINST THE HOLDER'S LINE
## keyed by the holder — never out of the yield. That is what makes a claim a decision
## rather than a free grab (ADR 0097), and it is why a node with upkeep can net cost the
## player money while still paying out.
func test_a_node_with_upkeep_charges_it_and_a_node_without_does_not() -> void:
	_claim(_actor, &"t_costly")
	ForageAction.gather(_actor, &"t_costly", 4)
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	# `_charge_upkeep` keys the line `"<kind>:upkeep:<holder id>"` and NOTHING else, so this
	# is the holder's single upkeep line across every node they hold — the node id is
	# deliberately absent, because an institution's upkeep is one visible obligation rather
	# than a second pile of goods per node (BL-0191).
	var upkeep_key := "actor:upkeep:%s" % String(_actor.id)
	assert_eq(
		int(line.get(upkeep_key, 0)),
		12,
		"upkeep_per_period 3 over 4 periods is charged against the holder's own line"
	)

	# Working a node that declares no upkeep must leave that line byte-identical. The
	# previous form of this assertion read a `...:upkeep:<node id>` key, which holdings can
	# never write — so it answered 0 whatever the code did, and a harvest that charged
	# upkeep for a free node would have passed. Comparing across the call is the only
	# version of this that can actually fail.
	var before := int(line.get(upkeep_key, 0))
	_claim(_actor, &"t_shallow")
	ForageAction.gather(_actor, &"t_shallow", 4)
	var after: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(after.get(upkeep_key, 0)), before, "and a node that declares no upkeep is charged none"
	)


## Depletion spends CONDITION and refuses once it is gone. A node that silently yielded
## nothing would leave a player pressing a button that does nothing forever, so the refusal
## is the point: `depleted` is named, not an empty result.
func test_a_depleted_node_refuses_rather_than_yielding_nothing_silently() -> void:
	_claim(_actor, &"t_vein")
	# `depletion = 2`, so two periods of accrual spend the condition and the third refuses.
	var first := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(first["ok"]), true, "the first period works")
	assert_eq(int(first["condition"]), 1, "and spends one period of condition")
	var second := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(second["ok"]), true, "the second period works")
	assert_eq(int(second["condition"]), 0, "and spends the last of it")
	var third := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(third["ok"]), false, "the next one refuses rather than yielding nothing")
	assert_eq(String(third["reason"]), HoldingsState.DEPLETED, "and names the rule")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(String(second["item_id"])), 4),
		true,
		"the units already paid out are still in the bag: depletion is not a retroactive loss"
	)


## A refused depletion must not charge upkeep, or an exhausted holding would keep billing
## the player for a node that produces nothing. Asserted because `accrue` refuses BEFORE it
## charges, and that ordering is the only thing protecting the player.
func test_a_refused_depleted_node_charges_no_upkeep() -> void:
	_claim(_actor, &"t_vein")
	ForageAction.gather(_actor, &"t_vein", 1)
	ForageAction.gather(_actor, &"t_vein", 1)
	# `t_vein` declares upkeep 0, so the holder's upkeep line is 0 before the refusal and
	# must still be 0 after it. Read across the refusal rather than at a key holdings never
	# writes: the original `...:upkeep:t_vein` lookup answered 0 for a code that charged
	# upkeep anyway, so the assertion could not fail.
	var upkeep_key := "actor:upkeep:%s" % String(_actor.id)
	var before: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	var refused := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(String(refused["reason"]), HoldingsState.DEPLETED, "the node is spent")
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(line.get(upkeep_key, 0)),
		int(before.get(upkeep_key, 0)),
		"and a refusal charges no upkeep, so an exhausted holding is not a bill"
	)


## `periods <= 0` refuses with `no_periods`, and the id is HELDINGS' — this module surfaces
## the constant rather than inventing a synonym, so one `no_periods` covers the whole accrue
## path whichever module a caller reached it through.
func test_a_non_positive_period_count_refuses() -> void:
	_claim(_actor, &"t_shallow")
	for bad in [0, -1, -100]:
		var result := ForageAction.gather(_actor, &"t_shallow", bad)
		assert_eq(bool(result["ok"]), false, "periods %d refuses" % bad)
		assert_eq(String(result["reason"]), ForageApi.NO_PERIODS, "periods %d names the rule" % bad)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and a refused period count moved nothing at all"
	)


# --- the structural guard -------------------------------------------------------


## The boundary this whole design exists to keep. `holdings` may not name an inventory, so
## the conversion has to live somewhere else — and this asserts from the facade's own SOURCE
## rather than by reflection, because a `has_method` probe on a class of static verbs
## answers for the instance side and would pass for reasons unrelated to the claim.
func test_holdings_still_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/holdings/api.gd")
	assert_eq(source.is_empty(), false, "the facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack"]:
		assert_eq(
			source.contains(verb),
			false,
			"holdings/api.gd never names %s, so the conversion had to live elsewhere" % verb
		)


## And the `forage` module is just as bounded: it declares no `items` edge, so it must not
## name an inventory either. The granter is the seam that keeps that true.
func test_the_forage_facade_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/forage/api.gd")
	assert_eq(source.is_empty(), false, "the forage facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack", "Crafting"]:
		assert_eq(
			source.contains(verb),
			false,
			"forage/api.gd never names %s, so the item half is genuinely injected" % verb
		)


## Every node this module can forage is a node the game actually authors, and every authored
## node has a yield. Without this, a yield table could drift from the content tree and a
## node could quietly become un-gatherable with nothing failing.
func test_every_authored_node_has_an_authored_yield() -> void:
	var problems := ForageApi.validate()
	assert_eq(
		problems,
		[],
		"the yield table and the authored node catalog agree: %s" % ", ".join(problems)
	)


## The route is shipped because there is a verb, and the verb is reachable from `game/src`.
## Both halves are asserted: a `shipped` flag without a production call site is the exact
## lie `tools/data.py`'s `call_sites` exists to prevent.
func test_the_route_is_backed_by_a_verb_and_an_installed_granter() -> void:
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_GATHER),
		true,
		"gather ships because ForageApi.harvest exists, not because the flag moved"
	)
	assert_eq(bool(ForageApi.has_granter()), true, "and the granter is installed by this suite")


## Without a granter the verb refuses LOUDLY rather than accruing yield it can never
## deliver. A forager that produced accruals and no items is the exact bug that kept
## `gather` unshipped, so the unwired case is asserted rather than assumed away.
func test_an_unwired_granter_refuses_instead_of_accruing_unreachable_yield() -> void:
	_claim(_actor, &"t_shallow")
	ForageApi.set_granter(Callable())
	var result := ForageAction.gather(_actor, &"t_shallow", 2)
	assert_eq(bool(result["ok"]), false, "an unwired route refuses")
	assert_eq(
		String(result["reason"]),
		ForageApi.NO_GRANTER,
		"and names the missing seam rather than failing quietly"
	)
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(line.get("t_shallow", 0)),
		0,
		"and credits nothing, so nothing was accrued that could not be delivered"
	)


## A node with no authored yield refuses BY NAME. This is the gap that made `gather`
## unshipped — nothing in `game/src` knew what a node produced — and it must never come
## back as a silent empty bag.
func test_a_node_with_no_authored_yield_refuses_named() -> void:
	ResourceNodeCatalog.instance().install([_node(&"t_unmapped", SHALLOW_REALM, 5, 0, 0)])
	_claim(_actor, &"t_unmapped")
	var result := ForageAction.gather(_actor, &"t_unmapped", 1)
	assert_eq(bool(result["ok"]), false, "a node nothing names an item for cannot be foraged")
	assert_eq(
		String(result["reason"]),
		ForageApi.NO_YIELD_CONTENT,
		"and it says so, rather than yielding an empty bag"
	)


# --- the entry point a screen binds ---------------------------------------------


## `ForageAction.workable` is the question a button's enabled state binds to. It must agree
## with the verb: a button that is enabled where the verb refuses is a control that lies.
func test_workable_agrees_with_the_verb_on_every_gate() -> void:
	_claim(_actor, &"t_shallow")
	assert_eq(ForageAction.workable(_actor, &"t_shallow"), true, "a held, shallow node works")
	assert_eq(
		ForageAction.workable(_actor, &"t_deep"),
		false,
		"an unheld deep node is not workable, whatever else is true of it"
	)
	_claim(_actor, &"t_deep")
	assert_eq(
		ForageAction.workable(_actor, &"t_deep"),
		false,
		"and a HELD deep node is still not workable by a shallow actor"
	)
	var rival := _miner(&"t_rival_2", SHALLOW_REALM)
	_claim(rival, &"t_shallow")
	# ADR 0085: a claim on HELD ground opens a standoff and leaves `holder` byte-identical
	# (`test_holdings_claim` pins exactly this). So `rival`'s challenge did not take the
	# node — `_actor` is still its holder, and `workable` must say so for BOTH of them. This
	# assertion used to claim the rival's own ref made it workable, which is only true if a
	# challenge silently transfers ground, i.e. if `holdings` is broken.
	assert_eq(
		ForageAction.workable(rival, &"t_shallow"),
		false,
		"a challenger never holds the node, so it is not workable for them either"
	)
	assert_eq(
		ForageAction.workable(_actor, &"t_shallow"),
		true,
		"and the real holder still works it: the standoff moved nothing"
	)
