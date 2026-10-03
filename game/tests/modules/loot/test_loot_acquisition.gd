extends TestCase

## The player pipeline a boss drop walks, driven entirely through the loot screen's
## own controls: choose a domain, enter it, see a boss, strike it until it dies,
## see what it dropped, take it, and find the encounter cleared.
##
## Every stage below names the control that drives it. Nothing calls `act_*`
## directly, because the claim being tested is that a *player* can do this — not
## that a harness holding the screen object can.

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## Stage 1-2: the screen offers every authored domain, and `Enter` starts a run in
## the one the suite names. A screen with no actor and no gameplay side reads empty
## rather than guessing.
func test_the_entry_row_offers_the_domains_and_enter_starts_a_run() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	assert_ne(view, null, "the loot screen scene loads")
	var outside := view.summary()
	assert_eq(
		int(outside["domain_count"]), LootApi.domains().size(), "every authored domain is offered"
	)
	assert_eq(bool(outside["in_domain"]), false, "nobody is in a domain yet")
	assert_eq(bool((outside["enabled"] as Dictionary)["enter"]), true, "so Enter is offered")

	assert_eq(_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN), true, "the Enter control runs")
	var inside := view.summary()
	assert_eq(bool(inside["in_domain"]), true, "Enter put the player inside a domain")
	assert_eq(
		String(inside["domain_id"]),
		str(LootScreenRig.EMBER_DOMAIN),
		"and the domain they were shown is the one they entered"
	)


## Stage 3: the boss panel shows the authored first boss and its vitality pool.
func test_the_boss_panel_shows_the_live_boss_and_its_pool() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var boss := view.summary()["boss"] as Dictionary
	assert_eq(bool(boss["in_domain"]), true, "a boss is live")
	assert_eq(
		String(boss["boss_id"]), LootScreenRig.EMBER_FIRST_BOSS, "and it is the authored first one"
	)
	assert_eq(float(boss["vitality_max"]) > 0.0, true, "it has an authored vitality pool")
	assert_eq(
		String(view.summary()["vitality_label"]),
		"%d / %d vitality" % [int(boss["vitality"]), int(boss["vitality_max"])],
		"the panel, not the screen, owns the vitality wording"
	)


## Stage 4: `Strike` resolves one exchange, so what a blow spends is decided by the
## actor's own numbers and not by a number the caller chose (ADR 0076). The loop stops on
## the encounter id, so it watches one boss die rather than clearing the whole run.
func test_strike_spends_from_the_actors_own_numbers_and_kills_the_boss_when_the_pool_empties(
) -> void:
	# A bare delver, so one exchange is a genuine fraction of the pool rather than a
	# one-shot: this stage exists to show that a blow is a share and that the boss
	# answers, and a geared hero proves neither against a shallow band.
	var view := _rig.screen(_rig.hero(24, 0.0, 0.0))
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var full := float(view.summary()["vitality_max"])
	assert_eq(_rig.press(view, "%StrikeButton"), true, "the Strike control exists")
	var hurt := view.summary()
	assert_eq(float(hurt["vitality"]) < full, true, "one exchange spends some of the pool")
	assert_eq(bool(hurt["in_domain"]), true, "and a partial hit leaves the boss alive")
	assert_eq(
		float(hurt["health"]) < float(hurt["health_max"]),
		true,
		"while the boss answers, because the exchange is two-sided"
	)

	var dead := _rig.defeat_boss(view, 200)
	assert_ne(dead, "", "the pool emptied and the boss died")
	var after := view.summary()
	assert_eq(int(after["reward_count"]), 1, "and exactly one payload exists")
	assert_eq(int(after["pending_drops"]) > 0, true, "with drops waiting to be taken")


## Stage 5: the reward list shows one payload's drops as one row per drop, and says
## which encounter the rows belong to. Nothing a payload owes may be counted as owed
## without a row the player can act on.
func test_the_reward_list_shows_one_row_per_drop_of_the_payload_it_names() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	assert_ne(dead, "", "the first boss was defeated")
	var state := view.summary()
	var listed := _rig.listed_reward(view)
	assert_eq(String(state["reward_encounter_id"]), dead, "the list names the encounter just won")
	assert_eq(String(listed["encounter_id"]), dead, "and the listed rows belong to it")
	assert_eq(int(listed["row_count"]) > 0, true, "one row per drop, so the drops are visible")
	assert_eq(int(state["pending_drops"]), int(listed["row_count"]), "and every drop is claimable")
	assert_eq(
		bool((state["reward"] as Dictionary)["settled"]),
		false,
		"so the payload reads as unsettled rather than as nothing left to take"
	)


## Stage 6-7: the row's own `Pick up` control hands the drop to the inventory with
## the realization the payload was built with, rolls intact.
func test_picking_a_row_up_delivers_the_realized_drop_intact() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	var listed := _rig.listed_reward(view)
	var rows := listed["rows"] as Array
	assert_eq(rows.is_empty(), false, "the payload has a row to pick up")
	var row := rows[0] as Dictionary
	assert_eq(bool(row["claimable"]), true, "the row is claimable")
	# Read what the payload realized *before* taking it: settling the last drop moves
	# the payload to the claim ledger, where it is deliberately no longer addressable.
	var realized := _rig.realized_for(actor, dead, String(row["drop_id"]))
	assert_ne(realized.is_empty(), true, "the payload realized the drop at defeat time")

	assert_eq(_rig.pick_up_row(view, 0), true, "the row's own Pick up control drives the pickup")

	assert_eq(
		int(view.summary()["pending_drops"]),
		int(listed["pending_count"]) - 1,
		"one drop fewer waiting"
	)
	# Read the row back from the screen: `rows` is a snapshot taken before the pickup,
	# so it cannot show that the list repainted itself.
	assert_eq(
		bool((view.summary()["reward"] as Dictionary)["rows"][0]["claimed"]),
		true,
		"and the row reads as taken"
	)

	# The inventory must hold that realization, not a re-roll: same affixes, same
	# rarity, same realm.
	var carried := _rig.carried_drop(actor, row)
	assert_ne(carried.is_empty(), true, "the inventory holds that exact realized drop")
	assert_eq(
		String(carried.get("def_id", "")),
		String(realized.get("def_id", "")),
		"the delivered item is the drop's own definition"
	)
	assert_eq(String(carried.get("rarity", "")), String(realized["rarity"]), "rarity intact")
	assert_eq(String(carried.get("realm", "")), String(realized["realm"]), "realm intact")
	assert_eq(
		carried.get("rolled", []), realized["rolled"], "and the rolled affixes are the same ones"
	)


## Stage 6, in bulk: `Take all` empties the listed payload and leaves every other
## one untouched.
func test_take_all_empties_the_listed_payload_and_leaves_the_others_alone() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)
	var second := _rig.defeat_boss(view)
	assert_ne(second, "", "a second boss was defeated too")
	var state := view.summary()
	assert_eq(int(state["reward_count"]), 2, "so two payloads are unclaimed")

	assert_eq(_rig.take_all(view), true, "the Take all control empties what is listed")
	var after := view.summary()
	assert_eq(int(after["reward_count"]), 1, "only the listed payload was settled")
	assert_eq(int(after["claimed_encounters"]), 1, "and exactly one claim was spent")
	assert_eq(
		int(after["pending_drops"]),
		int(state["pending_drops"]) - int((state["reward"] as Dictionary)["pending_count"]),
		"every drop of the listed payload stopped waiting"
	)
	assert_eq(bool(after["reward_encounter_id"] != ""), true, "the other payload is still listed")


## Stage 8: once the last boss of a run is dead the tier is cleared and the screen
## leaves the domain. Rule E2 then refuses a re-entry rather than farming it.
func test_the_run_clears_and_the_cleared_tier_cannot_be_re_entered() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	for _boss in LootScreenRig.EMBER_BOSS_COUNT:
		_rig.defeat_boss(view)
	_rig.take_everything(view)

	var state := view.summary()
	assert_eq(bool(state["in_domain"]), false, "the run is over, so nobody is in a domain")
	# The run ledger is module state, so it is read through the facade that owns it
	# rather than through a copy the screen happens to publish.
	assert_eq(
		int(
			(LootApi.summary(actor)["runs"] as Dictionary)[str(LootScreenRig.EMBER_DOMAIN)]["cleared_tier"]
		),
		LootScreenRig.EMBER_TIER,
		"and the run recorded the tier it cleared"
	)
	assert_eq(int(state["pending_drops"]), 0, "with nothing left owing")
	assert_eq(
		int(state["claimed_encounters"]),
		LootScreenRig.EMBER_BOSS_COUNT,
		"and one claim spent per boss"
	)
	assert_eq(bool((state["enabled"] as Dictionary)["enter"]), true, "so entering is offered again")

	_rig.press(view, "%EnterButton")
	var refused := view.summary()
	assert_eq(
		String(refused["message"]),
		"Rejected: domain_cleared",
		"but re-entering a cleared tier is refused and says why"
	)
	assert_eq(bool(refused["in_domain"]), false, "and nobody is put back inside")
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 0, "a refused re-entry mints no payload")


## What makes an outstanding payload reachable is that the screen says how many owe
## and then works through every one of them: settling the listed payload must bring
## the next one on screen with its own drops still claimable, until nothing is owed.
## A screen that stops after the first payload strands a drop that exists in the
## world with nothing addressing it.
func test_every_outstanding_payload_is_eventually_listed_and_claimable() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)
	var second := _rig.defeat_boss(view)
	assert_ne(second, "", "a second boss was defeated")

	var owed := view.summary()
	assert_eq(int(owed["reward_count"]), 2, "both payloads are outstanding")
	assert_eq(
		int(owed["pending_drops"]) > int((owed["reward"] as Dictionary)["row_count"]),
		true,
		"and the screen admits it is not showing all of them at once"
	)

	# Walk the drain. Each round settles what is listed; the screen must then put the
	# other payload up, and the runs ledger is the witness that both really paid.
	var seen: Array = []
	var guard := 0
	while int(view.summary()["reward_count"]) > 0 and guard < 8:
		guard += 1
		var listed := String(view.summary()["reward_encounter_id"])
		assert_ne(listed, "", "a payload is on screen and named")
		if seen.has(listed):
			break
		seen.append(listed)
		assert_eq(_rig.take_all(view), true, "the listed payload %s can be taken" % listed)
	assert_eq(seen.size(), 2, "every outstanding payload reached the screen, one per round")
	assert_eq(int(view.summary()["reward_count"]), 0, "and none is left stranded")
	assert_eq(int(view.summary()["pending_drops"]), 0, "with no drop still waiting anywhere")
	assert_eq(int(view.summary()["claimed_encounters"]), 2, "and one claim spent per payload")
	assert_eq(_claimed_ids(actor).size(), 2, "so both bosses really paid, in the ledger")


## The screen names no module type, no item type and no theme override, and formats
## no number of its own: the panels do that, and `tools arch` fails the first two.
func test_the_screen_names_no_module_type_and_formats_no_number() -> void:
	var view := _rig.screen(_rig.hero())
	var scene := FileAccess.get_file_as_string(LootScreenRig.SCREEN_SCENE)
	assert_eq(scene.contains("LootApi"), false, "the scene names no module type")
	assert_eq(scene.contains("theme_override"), false, "and no theme override anywhere")
	var script := FileAccess.get_file_as_string("res://src/ui/screens/loot_encounter.gd")
	assert_eq(script.contains("LootApi"), false, "nor does the script")
	assert_eq(script.contains("ItemDef"), false, "nor any item type")
	assert_eq(script.contains("theme_override"), false, "nor a theme override")
	assert_eq(script.contains("%d"), false, "the screen writes no %d")
	assert_eq(script.contains("%."), false, "and no decimal of its own")
	# Every panel the screen composes is mounted: the fight readout, the outstanding
	# reward and the world drop container. The reward list is the presentation path a
	# reward now travels, so its absence is not a cosmetic difference.
	for node_name in ["%BossPanel", "%RewardList", "%StashList", "%GateLabel"]:
		assert_eq(view.get_node_or_null(node_name) != null, true, "%s is mounted" % node_name)
	assert_eq(
		view.get_node_or_null("%RewardList") != view.get_node_or_null("%StashList"),
		true,
		"and the reward and the world container are two lists, so one cannot hide the other"
	)


## The outstanding-reward read model, straight from the facade: every unclaimed
## payload and every drop is addressable, whether or not the screen happens to be
## showing it. This is the claim a reward has to keep for the walk to be complete.
func test_every_unclaimed_drop_is_addressable_through_the_facade() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)
	var second := _rig.defeat_boss(view)
	assert_ne(second, "", "a second boss was defeated")

	var state := LootApi.summary(actor)
	var rewards := state["rewards"] as Array
	assert_eq(rewards.size(), 2, "both payloads are outstanding in the world")
	var reachable := 0
	for payload in rewards:
		var descriptor := payload as Dictionary
		var encounter := String(descriptor["encounter_id"])
		assert_eq(bool(LootApi.reward(actor, encounter)["ok"]), true, "%s is claimable" % encounter)
		for drop in descriptor["drops"] as Array:
			var drop_id := String((drop as Dictionary)["drop_id"])
			reachable += 1
			assert_eq(
				String(LootApi.pickup(actor, encounter, drop_id)["status"]),
				"claimed",
				"%s / %s is addressable by the drop id on the row" % [encounter, drop_id]
			)
	assert_eq(reachable > 0, true, "and there were drops to address at all")
	assert_eq(int(LootApi.summary(actor)["pending_drops"]), 0, "so nothing was left owing")
	assert_eq(int(LootApi.summary(actor)["claimed_encounters"]), 2, "and both claims settled")


## Every claim token a run mints is spent at most once: a drop that exists in the world
## is delivered once, and every later request for it is refused by name rather than
## stacking copies of the same realization.
##
## The repeat request goes through the facade on purpose. The reward list frees the row
## it is mid-way through emitting, so a second *screen* press aborts the test's frame
## before any assertion after it can run — a refusal that only a screen press can
## provoke would go unreported. The accounting this proves lives in the module, and the
## module is where the claim token is spent.
func test_a_claim_token_is_never_served_twice_however_often_the_drop_is_pressed() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	assert_ne(dead, "", "a boss was defeated")
	var first := (_rig.listed_reward(view)["rows"] as Array)[0] as Dictionary
	var drop_id := String(first["drop_id"])
	var def_id := StringName(first["def_id"])
	var quantity := int(first["quantity"])
	var realized := _rig.realized_for(actor, dead, drop_id)
	assert_ne(realized.is_empty(), true, "the payload realized the drop at defeat time")

	var inventory := ItemsApi.inventory(actor)
	# Units, not containers: a stackable drop merges into one batch, so counting
	# batches would read a triple delivery as a single one.
	assert_eq(int(inventory.count(def_id)), 0, "nothing of that item is carried yet")
	assert_eq(_rig.pick_up_row(view, 0), true, "the row's control drives the pickup")
	assert_eq(int(inventory.count(def_id)), quantity, "one press delivered the drop once")
	# A non-stackable drop is delivered one instance per unit, so the delivered id is
	# minted from the drop's id rather than reused verbatim. What must not change is
	# the realization: same definition, rarity, realm and rolled affixes.
	var carried := _rig.carried_drop(actor, first)
	assert_eq(carried.is_empty(), false, "the inventory holds the drop")
	assert_eq(
		String(carried.get("def_id", "")),
		String(realized.get("def_id", "")),
		"and it is the drop's own definition"
	)
	assert_eq(String(carried.get("rarity", "")), String(realized["rarity"]), "rarity intact")
	assert_eq(String(carried.get("realm", "")), String(realized["realm"]), "realm intact")
	assert_eq(carried.get("rolled", []), realized["rolled"], "with the very same rolled affixes")

	for attempt in 2:
		var again := LootApi.pickup(actor, dead, drop_id)
		assert_eq(
			String(again["reason"]),
			LootState.ERR_DROP_CLAIMED,
			"repeat request %d is refused by name" % (attempt + 1)
		)
		assert_eq(
			int(inventory.count(def_id)),
			quantity,
			"and delivers nothing further, on attempt %d" % (attempt + 1)
		)
	assert_eq(
		int(LootApi.summary(actor)["claimed_encounters"]),
		0,
		"and no claim was spent by a refusal: a drop of this payload is still owed"
	)
	assert_eq(
		int(LootApi.summary(actor)["reward_count"]),
		1,
		"so the payload is still outstanding rather than closed over a partial take"
	)


## The encounter ids in the claim ledger, sorted, read from the module's own state
## rather than from anything the screen mirrors.
func _claimed_ids(actor: Actor) -> Array:
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	var ids: Array = (state["claimed"] as Dictionary).keys()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	return ids
