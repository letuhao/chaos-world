extends "res://tests/modules/domain/domain_fixture_kit.gd"

## ADR 0073 / ADR 0075: `RoomDef.fixtures` is not a field nobody reads -- the
## gameplay half.
##
## Seven shipped rooms author traps, puzzles and treasure; four code paths copy and
## serialise the array faithfully (`RoomDef.to_dict`, `RoomDef.from_dict`, the
## generator's deep copy, the JSON round trip in `test_domain_content.gd:661`) and no
## line of the game looked one up at runtime. `test_domain_content.gd:25` deferred the
## consumer by name -- "the runtime consumer of `RoomDef.fixtures` is another agent's
## job" -- so this is it, and the sections below are its acceptance.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no
## method renamed: this half is the file's first five sections verbatim, and every
## constant, builder and helper it uses now lives in `domain_fixture_kit.gd`, which
## both halves `extends`.
##
## The read-model, ledger and refusal half is `test_domain_fixture_reads.gd`.
##
## Each case is the assertion a lazy implementation cannot pass: a trap INERT through
## its telegraph and landing a NON-ZERO magnitude after (presence is not consequence,
## BL-0392's lesson); firing ONCE; mitigation MEASURABLY moving through the lever
## vocabulary `EnvironmentField` publishes; a puzzle whose wrong node resets progress
## and NEVER costs health; treasure claimable exactly once in all three shapes.
##
## Every loop below is a bounded `for`. There is no `while`.

# ── 1. telegraph, then damage, through a status ──────────────────────────────


## **The headline.** ADR 0075's "telegraph before damage" is only true if the window
## is genuinely INERT. Presence is checked before and after, and the magnitude is
## asserted NON-ZERO afterwards: a DOT that ages out silently and pays nothing would
## pass every presence assertion this repo already has, which is the defect BL-0392
## records.
func test_a_trap_is_inert_through_its_telegraph_and_lands_one_after() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	var status_id := StringName(authored.get("status_id", ""))
	var telegraph_s := float(authored.get("telegraph_s", 0.0))
	assert_eq(telegraph_s > 0.0, true, "the shipped trap authors a telegraph window")

	var armed := DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	assert_eq(armed.get("ok"), true, "arming succeeds: %s" % str(armed))
	assert_eq(armed.get("reason"), DomainFixtures.OK_TELEGRAPHING, "and reports telegraphing")
	assert_eq(actor.has_status(status_id), false, "NOTHING lands during the telegraph")
	assert_eq(actor.resource(&"health").current > 0.0, true, "and no health is spent either")

	# A tenth short of the window, so a `>=` boundary cannot be mistaken for the claim.
	var waiting := DomainFixtures.arm(actor, room_id, TRAP, telegraph_s - 0.1)
	assert_eq(
		waiting.get("reason"),
		DomainFixtures.OK_TELEGRAPHING,
		"still telegraphing one frame short of the window"
	)
	assert_eq(actor.has_status(status_id), false, "still nothing on the actor")

	var fired := DomainFixtures.arm(actor, room_id, TRAP, 0.2)
	assert_eq(fired.get("ok"), true, "the trap fires once the telegraph elapses")
	assert_eq(fired.get("reason"), DomainFixtures.OK_FIRED, "and names the outcome")
	assert_eq(actor.has_status(status_id), true, "the authored status_id is on the actor")

	var carried := actor.statuses[0]
	assert_eq(carried.id, status_id, "it is the trap's own status")
	assert_eq(
		carried.magnitude > 0.0,
		true,
		"and carries a NON-ZERO magnitude: a status that pays nothing is a comment"
	)
	assert_eq(
		carried.magnitude,
		float(fired.get("share")),
		"which is the share the answer reported, not the constructor's 0.0 default"
	)
	assert_eq(
		carried.tick_interval, _cadence(), "and a non-zero cadence, so the tick path can resolve it"
	)
	assert_eq(carried.kind, StatusEffect.Kind.DOT, "a trap spends over time")
	assert_eq(
		carried.scope,
		StatusEffect.Scope.CULTIVATION,
		"and is never opposed by combat resistance: it is a place, not a blow"
	)
	assert_eq(
		carried.has_mitigation(),
		true,
		"the status publishes the fixture's levers, so it is a hazard something answers"
	)


## The consequence half of the same claim: `Actor.tick_statuses` really pays the trap,
## and the status ends on the authored `duration_s` rather than lingering.
func test_the_trap_status_pays_and_then_expires() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	var status_id := StringName(authored.get("status_id", ""))
	var pulses: Array[float] = []
	var handler := func(signal_id: StringName, magnitude: float) -> void:
		if signal_id == status_id:
			pulses.append(magnitude)
	actor.status_ticked.connect(handler)

	DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	DomainFixtures.arm(actor, room_id, TRAP, float(authored.get("telegraph_s", 0.0)) + 0.1)
	var duration := float(authored.get("duration_s", 0.0))
	actor.tick_statuses(duration)

	var owed := int(duration / _cadence())
	assert_eq(owed > 0, true, "the authored duration owes at least one pulse")
	assert_eq(pulses.size(), owed, "one pulse per authored interval across one window")
	for magnitude in pulses:
		assert_eq(magnitude > 0.0, true, "and every pulse pays a real magnitude")
	assert_eq(
		actor.has_status(status_id),
		false,
		"the status ends on the authored duration rather than lingering"
	)
	actor.status_ticked.disconnect(handler)


## ADR 0075's other half, and the reason a telegraph exists: **a player must be able to
## LEAVE during the window.** A long frame still only arms — nothing fires on the frame
## the trap spawns, because a trap that bites the instant it becomes visible is a trap
## and not a telegraph.
func test_a_player_can_leave_during_the_telegraph() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)

	# Step 1: the trap spawns. A frame that only SPAWNS the trap arms it and nothing more,
	# however long that frame was — a trap that bites the instant it becomes visible is a
	# trap, not a telegraph.
	var spawned := DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	assert_eq(spawned.get("reason"), DomainFixtures.OK_TELEGRAPHING, "spawning only arms")
	assert_eq(
		actor.has_status(StringName(authored.get("status_id", ""))),
		false,
		"nothing lands on the frame the trap appears"
	)

	# Step 2: the player takes a SHORT step, still inside the window. Half the AUTHORED
	# telegraph — read from the def, not from `PAST_TELEGRAPH`, which is 99.0 and would
	# overshoot any real window and fire the trap. The remaining warning shrinks and still
	# nothing lands: this is the window being real.
	var half_step := float(authored.get("telegraph_s", 1.0)) * 0.5
	var ticking := DomainFixtures.arm(actor, room_id, TRAP, half_step)
	assert_eq(ticking.get("ok"), true, "a step inside the window is accepted")
	assert_eq(
		float(ticking.get("telegraph_remaining_s", 0.0)) > 0.0,
		true,
		"and the warning still has time left on it"
	)
	assert_eq(
		actor.has_status(StringName(authored.get("status_id", ""))),
		false,
		"still no damage: the player had somewhere to go"
	)
	assert_eq(
		DomainFixtures.state_of(actor, room_id, TRAP).get("armed", false),
		true,
		"but it is still armed and still owes its warning"
	)


# ── 2. a trap fires ONCE ─────────────────────────────────────────────────────


## A trap is spent after it fires and is NEVER re-armed in the run. Each later `arm`
## carries a delta past the whole telegraph, so an implementation that re-armed on the
## clock would fire a second time here; nothing changes.
func test_a_trap_fires_once_and_is_spent() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	var status_id := StringName(authored.get("status_id", ""))

	DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	DomainFixtures.arm(actor, room_id, TRAP, float(authored.get("telegraph_s", 0.0)) + 0.1)
	assert_eq(actor.has_status(status_id), true, "it fired once")

	# Age the status out, so a second landing would be plainly visible rather than
	# merged into the held instance by REFRESH.
	actor.tick_statuses(float(authored.get("duration_s", 0.0)) + 0.1)
	assert_eq(actor.has_status(status_id), false, "the first firing has aged out")

	for _attempt in range(3):
		var again := DomainFixtures.arm(actor, room_id, TRAP, PAST_TELEGRAPH)
		assert_eq(again.get("ok"), false, "re-arming a spent trap is refused")
		assert_eq(again.get("reason"), DomainFixtures.ERR_ALREADY_FIRED, "and says so by name")
		assert_eq(actor.has_status(status_id), false, "and nothing lands a second time")
	assert_eq(actor.statuses.size(), 0, "not one status is left behind")


## And the refusal is STATE, not a clock: the ledger records it, which is what makes it
## survive a save rather than re-deriving from elapsed time on load.
func test_a_spent_trap_is_recorded_as_spent() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	DomainFixtures.arm(actor, room_id, TRAP, float(authored.get("telegraph_s", 0.0)) + 0.1)

	var record := DomainFixtures.state_of(actor, room_id, TRAP)
	assert_eq(record.get("spent", false), true, "the ledger knows it is spent")
	assert_eq(record.get("armed", false), true, "and that it armed before firing")


## A fresh RUN re-arms everything. `DomainApi.enter` is the only place the ledger is
## cleared, so this is the assertion that a second run is not one where every trap is
## already used up.
func test_entering_again_re_arms_a_spent_trap() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	DomainFixtures.arm(actor, room_id, TRAP, float(authored.get("telegraph_s", 0.0)) + 0.1)
	assert_eq(DomainFixtures.state_of(actor, room_id, TRAP).get("spent", false), true, "spent")

	DomainApi.enter(actor, _map(), &"ember_hollow")
	var rearmed := DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	assert_eq(rearmed.get("ok"), true, "a new run arms it again: %s" % str(rearmed))
	assert_eq(rearmed.get("reason"), DomainFixtures.OK_TELEGRAPHING, "telegraphing, not spent")


# ── 3. mitigation is real, and it is the SAME lever vocabulary ───────────────


## Two actors identical except for a published `gear` tag, against the same fixture.
## The residual must be measurably lower for the warded one, and the cap applied must
## be read from `EnvironmentField.LEVER_CAPS` — so a retune of the environment's caps
## moves the trap's with it rather than leaving a stale copy behind.
func test_mitigation_measures_lower_through_the_environment_lever() -> void:
	var bare := _in_domain()
	var warded := _in_domain()
	var authored := _authored(TRAP)
	# `ash_chamber_vein` publishes `gear` and `affinity`. Asserted rather than assumed:
	# the whole claim is that the code reads the FIXTURE's levers, not a table of its own.
	assert_eq(
		(authored.get("mitigation_tags", []) as Array).has(&"gear"),
		true,
		"the shipped trap publishes a gear lever"
	)
	assert_eq(
		(EnvironmentField.LEVER_SUBSTRATES.get(EnvironmentField.LEVER_GEAR, []) as Array).has(
			DomainFixtures.SUBSTRATE
		),
		true,
		"and gear moves the substrate a trap resolves to"
	)
	warded.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": ["fire_ward"]})

	var unmitigated := DomainFixtures.residual_share(bare, authored)
	var mitigated := DomainFixtures.residual_share(warded, authored)
	assert_eq(String(mitigated["mitigated_by"]), "gear", "the named lever is gear")
	assert_eq(String(unmitigated["mitigated_by"]), "", "an unwarded actor is credited nothing")
	assert_eq(
		float(mitigated["amount"]) < float(unmitigated["amount"]),
		true,
		"gear reduces it: %f < %f" % [float(mitigated["amount"]), float(unmitigated["amount"])]
	)
	assert_almost_eq(
		float(unmitigated["amount"]),
		float(authored.get("damage_share", 0.0)),
		"an unmitigated actor carries the AUTHORED share"
	)
	assert_almost_eq(
		float(mitigated["amount"]),
		float(authored.get("damage_share", 0.0)) * (1.0 - EnvironmentField.GEAR_CAP),
		"and the geared residual is the authored share times the environment's own cap"
	)
	assert_almost_eq(
		float(mitigated["authored"]),
		float(authored.get("damage_share", 0.0)),
		"the authored share is reported UNCHANGED: a resolved number would leak their gear"
	)


## The mitigation reaches the STATUS, not just the returned dictionary. Comparing two
## actors who differ ONLY in a published tag is what kills a field that computes a
## residual and then applies the contract default.
func test_mitigation_reaches_the_status_the_actor_carries() -> void:
	var room_id := _room_of(TRAP)
	var window := float(_authored(TRAP).get("telegraph_s", 0.0)) + 0.1
	var bare := _in_domain()
	var warded := _in_domain()
	warded.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": ["fire_ward"]})

	for actor in [bare, warded]:
		DomainFixtures.arm(actor, room_id, TRAP, 0.0)
		DomainFixtures.arm(actor, room_id, TRAP, window)
	assert_eq(bare.statuses.size(), 1, "the bare actor carries one hazard")
	assert_eq(warded.statuses.size(), 1, "and so does the warded one")
	assert_eq(
		warded.statuses[0].magnitude < bare.statuses[0].magnitude,
		true,
		(
			"and the two STATUSES differ: %f < %f"
			% [warded.statuses[0].magnitude, bare.statuses[0].magnitude]
		)
	)


## A lever the trap does not PUBLISH is never credited. `ash_chamber_collapse`
## publishes `technique` and `pill`; a gear ward does not answer it, so crediting one
## would be an invention rather than a mitigation.
func test_an_unpublished_lever_is_never_credited() -> void:
	var authored := _authored(UNPUBLISHED_LEVER)
	assert_eq(
		(authored.get("mitigation_tags", []) as Array).has(&"gear"),
		false,
		"this trap publishes no gear lever"
	)

	var actor := _in_domain()
	actor.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": ["stone_ward"]})
	var resolved := DomainFixtures.residual_share(actor, authored)
	assert_eq(String(resolved["mitigated_by"]), "", "so a gear ward is credited nothing")
	assert_almost_eq(
		float(resolved["amount"]),
		float(authored.get("damage_share", 0.0)),
		"and the share is the full authored one"
	)


## ADR 0075's counterplay rule, held against the shipped kit rather than asserted in
## prose: every hazard publishes a lever, the lever is a real one, and it is not
## affinity-alone.
func test_every_authored_hazard_publishes_a_real_non_affinity_lever() -> void:
	var hazards := 0
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		var kind := String(fixture.get("kind", ""))
		if kind != "trap" and kind != "puzzle":
			continue
		hazards += 1
		var fixture_id := String(fixture.get("fixture_id", ""))
		var levers: Array = fixture.get("mitigation_tags", [])
		assert_eq(
			levers.is_empty(),
			false,
			"fixture '%s' is a '%s' and publishes no mitigation_tags" % [fixture_id, kind]
		)
		var non_affinity := false
		for lever in levers:
			assert_eq(
				EnvironmentZoneDef.LEVERS.has(StringName(lever)),
				true,
				"fixture '%s' lever '%s' names a real lever" % [fixture_id, String(lever)]
			)
			if StringName(lever) != EnvironmentField.LEVER_AFFINITY:
				non_affinity = true
		assert_eq(
			non_affinity,
			true,
			(
				"fixture '%s' is mitigated by affinity alone, so a wrong root has no counterplay"
				% fixture_id
			)
		)
	assert_eq(hazards > 0, true, "the shipped kit authors at least one hazard")


# ── 4. the formation gate ────────────────────────────────────────────────────


## The correct sequence completes the formation and grants `reward_item_id` x
## `reward_count` — through the SAME granter a treasure uses, because one delivery path
## in the game is the whole point of the injected bridge.
func test_the_correct_sequence_completes_and_grants_its_reward() -> void:
	var granted: Array = []
	_keyed(granted, &"", 0.0)
	var actor := _in_domain()
	var room_id := _room_of(PUZZLE)
	var authored := _authored(PUZZLE)
	var sequence: Array = authored.get("sequence", [])

	# The loop deliberately stops SHORT of the last node: the completing node CLAIMS the
	# fixture, so walking the whole sequence here would leave the final assertion below
	# re-attempting an already-claimed puzzle and reading `already_claimed`.
	for index in maxi(0, sequence.size() - 1):
		var health_before := actor.resource(&"health").current
		var step := DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[index]))
		assert_eq(step.get("ok"), true, "node %d is accepted: %s" % [index, str(step)])
		assert_eq(
			actor.resource(&"health").current,
			health_before,
			"the CORRECT path costs no health directly"
		)
		if index < sequence.size() - 1:
			assert_eq(step.get("reason"), DomainFixtures.OK_ADVANCED, "and advances")
			assert_eq(int(step.get("progress", 0)), index + 1, "reporting where it got to")

	var last := DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[-1]))
	assert_eq(last.get("reason"), DomainFixtures.OK_CLAIMED, "the last node completes it")
	assert_eq(granted.size(), 1, "the reward is handed over exactly once")
	assert_eq(
		String(granted[0]["item_id"]),
		String(authored.get("reward_item_id", "")),
		"and it is the authored item"
	)
	assert_eq(
		int(granted[0]["count"]), int(authored.get("reward_count", 0)), "in the authored quantity"
	)
	assert_eq(
		int(last.get("count", 0)),
		int(authored.get("reward_count", 0)),
		"the answer reports what was paid"
	)


## A wrong node applies `wrong_status_id` and sends the sequence back to the start —
## and costs NO health. "Never costs health directly" is the load-bearing claim here: a
## puzzle that kills you is a second fight wearing a costume.
func test_a_wrong_node_applies_the_status_resets_and_never_costs_health() -> void:
	var actor := _in_domain()
	var room_id := _room_of(PUZZLE)
	var authored := _authored(PUZZLE)
	var sequence: Array = authored.get("sequence", [])
	var wrong_status := StringName(authored.get("wrong_status_id", ""))
	assert_ne(wrong_status, &"", "the puzzle authors a status for a wrong node")

	# Advance two nodes, so the reset is visible rather than a no-op from the start.
	DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[0]))
	DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[1]))
	assert_eq(
		int(DomainFixtures.state_of(actor, room_id, PUZZLE).get("progress", 0)), 2, "two nodes in"
	)

	# A node the formation places, but NOT the one owed next.
	var wrong := String(sequence[0])
	for node in sequence:
		if String(node) != String(sequence[2]):
			wrong = String(node)
			break

	var health_before := actor.resource(&"health").current
	var result := DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(wrong))
	assert_eq(result.get("ok"), true, "a wrong node is answered, not ignored")
	assert_eq(result.get("reason"), DomainFixtures.OK_WRONG_NODE, "and says so by name")
	assert_eq(actor.has_status(wrong_status), true, "the authored wrong_status_id is applied")
	assert_eq(
		actor.resource(&"health").current,
		health_before,
		"and NO health is spent by the wrong node itself"
	)
	assert_eq(
		int(DomainFixtures.state_of(actor, room_id, PUZZLE).get("progress", 0)),
		0,
		"progress resets to the FIRST node, not to where it was"
	)
	# CONTROL, not DOT: a drain here would be the bespoke second damage channel
	# ADR 0075 forbids.
	assert_eq(
		actor.statuses[0].kind,
		StatusEffect.Kind.CONTROL,
		"the wrong-node status gates an action rather than draining a pool"
	)
	assert_eq(actor.statuses[0].magnitude > 0.0, true, "and carries a real gate strength")


## The reset really is resumable: the player restarts from the first node and can still
## finish, rather than being stranded against a half-solved formation.
func test_a_puzzle_resets_to_the_beginning_and_can_still_be_completed() -> void:
	var granted: Array = []
	_keyed(granted, &"", 0.0)
	var actor := _in_domain()
	var room_id := _room_of(PUZZLE)
	var sequence: Array = _authored(PUZZLE).get("sequence", [])

	DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[0]))
	DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[1]))
	DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(sequence[1]))
	assert_eq(
		int(DomainFixtures.state_of(actor, room_id, PUZZLE).get("progress", 0)),
		0,
		"back to the start"
	)
	assert_eq(granted.is_empty(), true, "and nothing was paid for the wrong nodes")

	for node in sequence:
		DomainFixtures.attempt(actor, room_id, PUZZLE, StringName(node))
	assert_eq(granted.size(), 1, "the full run still pays out, exactly once")
	assert_eq(
		DomainFixtures.state_of(actor, room_id, PUZZLE).get("complete", false),
		true,
		"and the formation is marked complete"
	)


## A node the formation does not place is a caller error, refused by name — it must not
## be read as a wrong strike and cost the player their sequence.
func test_a_node_the_formation_does_not_place_is_refused_by_name() -> void:
	var actor := _in_domain()
	var room_id := _room_of(PUZZLE)
	var wrong_status := StringName(_authored(PUZZLE).get("wrong_status_id", ""))
	var result := DomainFixtures.attempt(actor, room_id, PUZZLE, &"not_a_five_phase")
	assert_eq(result.get("ok"), false, "a node not in the formation is refused")
	assert_eq(result.get("reason"), DomainFixtures.ERR_UNKNOWN_NODE, "with a named reason")
	assert_eq(actor.has_status(wrong_status), false, "and it is not charged as a wrong strike")
	assert_eq(actor.resource(&"health").current > 0.0, true, "nor does it touch any pool")


# ── 5. treasure: unkeyed, keyed, realm-gated, once each ──────────────────────


## The three shapes, told apart by what gates them — the read
## `test_domain_content.gd:578` makes of the authored kit, asked of the CODE.
func test_treasure_is_unkeyed_keyed_or_realm_gated_and_each_opens_once() -> void:
	var granted: Array = []
	_keyed(granted, &"", 0.0)
	var actor := _in_domain()
	var room_id := _room_of(UNKEYED)
	var authored := _authored(UNKEYED)
	assert_eq(String(authored.get("key_item_id", "")), "", "this one is authored unkeyed")

	var opened := DomainFixtures.claim(actor, room_id, UNKEYED)
	assert_eq(opened.get("ok"), true, "an unkeyed hoard opens for anyone: %s" % str(opened))
	assert_eq(granted.size(), 1, "and it pays out once")
	assert_eq(
		String(granted[0]["item_id"]),
		String(authored.get("reward_item_id", "")),
		"the authored item"
	)

	var again := DomainFixtures.claim(actor, room_id, UNKEYED)
	assert_eq(again.get("ok"), false, "a second claim is refused")
	assert_eq(again.get("reason"), DomainFixtures.ERR_ALREADY_CLAIMED, "BY NAME, not silently")
	assert_eq(granted.size(), 1, "and nothing is paid a second time")


## A keyed hoard, first without the key and then with it. The refusal carries the key it
## wanted, so a reader can say what was missing.
func test_a_keyed_treasure_refuses_without_the_key_and_opens_with_it() -> void:
	var granted: Array = []
	_keyed(granted, &"no_key_anywhere", 0.0)
	# At the ladder CEILING, not the default realm: `ash_furnace_hoard` is authored with
	# BOTH a key and a `requires_realm` floor, and the floor is checked after the key. An
	# actor at the default realm would be refused for its REALM on both attempts, so this
	# test would silently be about the realm gate and never exercise the key at all. The
	# floor has its own test below.
	var actor := _in_domain(_ladder_ceiling())
	var room_id := _room_of(KEYED)
	var key_item_id := String(_authored(KEYED).get("key_item_id", ""))
	assert_ne(key_item_id, "", "this one is authored keyed")

	var refused := DomainFixtures.claim(actor, room_id, KEYED)
	assert_eq(refused.get("ok"), false, "no key, no hoard")
	assert_eq(refused.get("reason"), DomainFixtures.ERR_MISSING_KEY, "with a named reason")
	assert_eq(String(refused.get("key_item_id", "")), key_item_id, "naming the key it wanted")
	assert_eq(granted.is_empty(), true, "and nothing is paid")

	# The SAME fixture and actor, a bridge that answers the authored key.
	var opened_granted: Array = []
	_keyed(opened_granted, StringName(key_item_id), 1.0)
	assert_eq(DomainFixtures.claim(actor, room_id, KEYED).get("ok"), true, "with the key it opens")
	assert_eq(opened_granted.size(), 1, "and pays out exactly once")


## The realm floor, by ladder INDEX and never by string. `ash_furnace_hoard` gates on
## `core_formation`, index 2 of the shared ladder, so `qi_refining` (index 0) is refused
## and `core_formation` itself is admitted.
func test_a_realm_gate_is_compared_by_ladder_index() -> void:
	var ladder := RealmDefaults.ladder()
	var floor_index := ladder.index_of(&"core_formation")
	assert_eq(floor_index >= 0, true, "'core_formation' is a realm on the shared ladder")
	assert_eq(
		ladder.index_of(&"qi_refining") < floor_index,
		true,
		"and it sits above 'qi_refining', which is what makes this a gate"
	)
	var room_id := _room_of(KEYED)

	var below_granted: Array = []
	_keyed(below_granted, &"ash_furnace_key", 1.0)
	var refused := DomainFixtures.claim(_in_domain(&"qi_refining"), room_id, KEYED)
	assert_eq(refused.get("ok"), false, "below the floor the hoard stays shut")
	assert_eq(refused.get("reason"), DomainFixtures.ERR_REALM_TOO_LOW, "with a named reason")
	assert_eq(String(refused.get("actor_realm", "")), "qi_refining", "naming where they stand")
	assert_eq(below_granted.is_empty(), true, "and nothing is paid")

	# AT the floor, not merely above it: `>=` is the whole rule.
	var at_floor_granted: Array = []
	_keyed(at_floor_granted, &"ash_furnace_key", 1.0)
	assert_eq(
		DomainFixtures.claim(_in_domain(&"core_formation"), room_id, KEYED).get("ok"),
		true,
		"at the floor it opens"
	)
	assert_eq(at_floor_granted.size(), 1, "and pays out exactly once")

	var above_granted: Array = []
	_keyed(above_granted, &"ash_furnace_key", 1.0)
	assert_eq(ladder.index_of(&"nascent_soul") > floor_index, true, "and one rung higher")
	assert_eq(
		DomainFixtures.claim(_in_domain(&"nascent_soul"), room_id, KEYED).get("ok"),
		true,
		"it opens there too"
	)
	assert_eq(above_granted.size(), 1, "paying out once")


## `ash_heart_hoard` is the THIRD authored shape: unkeyed but behind a realm floor, so
## the two gates are independent rather than one implying the other.
func test_an_unkeyed_hoard_can_still_be_sealed_behind_a_realm() -> void:
	var authored := _authored(REALM_GATED)
	assert_eq(String(authored.get("key_item_id", "")), "", "this one authors NO key")
	assert_eq(String(authored.get("requires_realm", "")), "core_formation", "but does gate")
	var room_id := _room_of(REALM_GATED)

	var granted: Array = []
	_keyed(granted, &"", 0.0)
	var refused := DomainFixtures.claim(_in_domain(&"qi_refining"), room_id, REALM_GATED)
	assert_eq(
		refused.get("reason"),
		DomainFixtures.ERR_REALM_TOO_LOW,
		"no key is not the obstacle: the realm is"
	)

	var opened := DomainFixtures.claim(_in_domain(&"core_formation"), room_id, REALM_GATED)
	assert_eq(opened.get("ok"), true, "at the floor it opens: %s" % str(opened))
	assert_eq(granted.size(), 1, "and pays out once")


## Every shipped treasure is claimable exactly once, read off the AUTHORED kit rather
## than the three the other cases name — so a hoard authored later is covered without
## editing this file.
func test_every_authored_treasure_is_claimable_exactly_once() -> void:
	var treausures := 0
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		if String(fixture.get("kind", "")) != "treasure":
			continue
		treausures += 1
		var room_id := StringName(entry["room_id"])
		var fixture_id := StringName(fixture.get("fixture_id", ""))
		var granted: Array = []
		# Every gate satisfied at once: the authored key at full reach, and a realm at
		# the very top of the ladder, so the assertion is about ONCE and nothing else.
		_keyed(granted, StringName(fixture.get("key_item_id", "")), 1.0)
		var actor := _in_domain(_ladder_ceiling())

		var opened := DomainFixtures.claim(actor, room_id, fixture_id)
		assert_eq(
			opened.get("ok"),
			true,
			"treasure '%s' opens with every gate satisfied: %s" % [String(fixture_id), str(opened)]
		)
		assert_eq(granted.size(), 1, "'%s' pays out once" % String(fixture_id))
		var again := DomainFixtures.claim(actor, room_id, fixture_id)
		assert_eq(again.get("ok"), false, "'%s' refuses a second claim" % String(fixture_id))
		assert_eq(
			again.get("reason"),
			DomainFixtures.ERR_ALREADY_CLAIMED,
			"'%s' refuses it BY NAME" % String(fixture_id)
		)
		assert_eq(granted.size(), 1, "'%s' pays nothing further" % String(fixture_id))
	assert_eq(treausures > 0, true, "the shipped kit authors at least one treasure")


## A delivery that could not fit leaves the claim UNTOUCHED. A claim consumed by a
## pickup that never happened is the one silent loss this module could ship.
func test_a_failed_delivery_does_not_consume_the_claim() -> void:
	var room_id := _room_of(UNKEYED)
	# A granter that refuses everything, the shape a full bag produces.
	_install(Callable(), func(_a: Actor, _item: StringName, count: int) -> int: return count)

	var actor := _in_domain()
	var refused := DomainFixtures.claim(actor, room_id, UNKEYED)
	assert_eq(refused.get("ok"), false, "a delivery that does not fit is not a claim")
	assert_eq(refused.get("reason"), DomainFixtures.ERR_INVENTORY_FULL, "with a named reason")
	assert_eq(
		DomainFixtures.state_of(actor, room_id, UNKEYED).get("claimed", false),
		false,
		"and the claim is NOT consumed, so it stays retrievable"
	)

	# With room in the bag, the very same claim succeeds — which is what "leaves the
	# claim untouched" has to mean in practice.
	var granted: Array = []
	_keyed(granted, &"", 0.0)
	assert_eq(
		DomainFixtures.claim(actor, room_id, UNKEYED).get("ok"),
		true,
		"and it succeeds once the delivery can land"
	)
	assert_eq(granted.size(), 1, "paying out exactly once in the end")
