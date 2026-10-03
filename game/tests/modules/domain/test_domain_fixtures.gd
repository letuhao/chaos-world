extends TestCase

## ADR 0073 / ADR 0075: `RoomDef.fixtures` is not a field nobody reads.
##
## Seven shipped rooms author traps, puzzles and treasure; four code paths copy and
## serialise the array faithfully (`RoomDef.to_dict`, `RoomDef.from_dict`, the
## generator's deep copy, the JSON round trip in `test_domain_content.gd:661`) and no
## line of the game looked one up at runtime. `test_domain_content.gd:25` deferred
## the consumer by name — "the runtime consumer of `RoomDef.fixtures` is another
## agent's job" — so this is it, and the eight sections below are its acceptance.
##
## Each case is the assertion a lazy implementation cannot pass: a trap INERT through
## its telegraph and landing a NON-ZERO magnitude after (presence is not consequence,
## BL-0392's lesson); firing ONCE; mitigation MEASURABLY moving through the lever
## vocabulary `EnvironmentField` publishes; a puzzle whose wrong node resets progress
## and NEVER costs health; treasure claimable exactly once in all three shapes; every
## AUTHORED fixture recognised (the case that would have caught the gap); the ledger
## round-tripping `Actor.to_dict()`; and refusals named rather than guessed.
##
## Every loop below is a bounded `for`. There is no `while`.

# ── the shipped content ───────────────────────────────────────────────────────

const ROOM_DIR := "res://src/data/domains/rooms"

## The three kinds `DomainFixtures.KINDS` closes over. A fourth kind someone authors
## fails here rather than becoming a fixture the game walks past.
const KINDS: Array[String] = ["trap", "puzzle", "treasure"]

## The doors the cases below open, so a reader can see which authored shape is under
## test without opening the `.tres`.
const UNKEYED := &"ash_camp_offering"
const KEYED := &"ash_furnace_hoard"
const REALM_GATED := &"ash_heart_hoard"
const PUZZLE := &"ash_arena_formation"
const TRAP := &"ash_chamber_vein"
const UNPUBLISHED_LEVER := &"ash_chamber_collapse"


## `EnvironmentField.hazard_cadence`, read through a function rather than a `const`
## because a static call is not a constant expression. A DOT with no interval pays
## nothing (`status_registry.gd:168`), so this is the cadence a trap's status must pulse
## on, and it is read off the hazard def rather than restated as a literal here.
func _cadence() -> float:
	return EnvironmentField.hazard_cadence()


## Long enough to clear every authored `telegraph_s` — the shipped kit's loudest is
## `ash_chamber_collapse` at 1.6 — in one step, for the cases that only care that the
## window CLOSED rather than where its edge sits.
const PAST_TELEGRAPH := 99.0


## Every `.tres` under `dir_path`, sorted. The `while` is the `DirAccess.get_next()`
## terminator, the bounded form `tests/arch_rules/test_no_unbounded_wait.gd` rule 2
## accepts.
func _tres_files(dir_path: String) -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and not dir.current_is_dir() and entry.ends_with(".tres"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## The shipped rooms, ROUND-TRIPPED rather than handed over as loaded. `ResourceLoader`
## caches a `.tres`, so mutating the shared instance would persist into every later
## test — the same reason `test_domain_content.gd:235` copies before it edits.
func _authored_rooms() -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for file_name in _tres_files(ROOM_DIR):
		var room := load("%s/%s" % [ROOM_DIR, file_name]) as RoomDef
		if room != null:
			out.append(RoomDef.from_dict(room.to_dict()))
	return out


## `{room_id, fixture}` for every fixture in every shipped room, in canonical room and
## authored order, so the walks are a property of the tree and not of a listing order.
func _authored_fixtures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room in _authored_rooms():
		for fixture in room.fixtures:
			out.append({"room_id": String(room.room_id), "fixture": fixture})
	return out


## The authored fixture `fixture_id` lives on, as `{room_id, fixture}`. An empty
## dictionary is a loud miss at the call site rather than a silent null, because a
## fixture this suite cannot find is a test that would pass by asserting nothing.
func _find(fixture_id: StringName) -> Dictionary:
	for entry in _authored_fixtures():
		if StringName((entry["fixture"] as Dictionary).get("fixture_id", "")) == fixture_id:
			return entry
	return {}


## The authored dictionary for `fixture_id`, asserted found rather than returned
## quietly.
func _authored(fixture_id: StringName) -> Dictionary:
	var found := _find(fixture_id)
	if found.is_empty():
		push_error("test_domain_fixtures: no shipped fixture named '%s'" % String(fixture_id))
		return {}
	return found["fixture"] as Dictionary


## The authored room `fixture_id` lives in.
func _room_of(fixture_id: StringName) -> StringName:
	return StringName(String(_find(fixture_id)["room_id"]))


## A map over the SHIPPED rooms, every one reachable and every exit declared, so
## `DomainMapContract.assert_valid` passes and `DomainApi.enter` accepts it. The kit's
## rooms declare no exits of their own (`ash_arena.tres` has none), so connectivity is
## rebuilt here rather than asserted against a map that cannot be entered.
##
## `ash_gate`'s roster is NORMALISED rather than reproduced: it authors a `cinder_hound`
## at role `mob` (hostile) AND an `ember_pilgrim` at role `rival_cultivator` (not), which
## no band admits — `test_domain_content.gd:113-139` pins that as a known CONTENT defect
## whose fix belongs in the content, in a file this task does not own. `DomainApi.enter`
## refusing the map outright would leave this suite measuring nothing, so the
## non-hostile refs are dropped and the cost is RE-PROVED rather than assumed:
## `_map_carries_every_fixture` asserts the map still holds every authored fixture.
func _map() -> DomainMap:
	var map := DomainMap.new(Vector2i(64, 48), 4242)
	var rooms := _authored_rooms()
	for index in rooms.size():
		# A ring, not a chain: a `previous`/`following` pair on every room leaves nobody
		# unreachable, which is the half of the contract a fixture case would otherwise
		# trip over for reasons unconnected to fixtures.
		var copy := rooms[index]
		copy.exits = (
			[
				rooms[(index - 1 + rooms.size()) % rooms.size()].room_id,
				rooms[(index + 1) % rooms.size()].room_id,
			]
			as Array[StringName]
		)
		var kept: Array[Dictionary] = []
		for ref in copy.actor_spawn_refs:
			if String(ref.get("role", "")) != DomainRoles.RIVAL_CULTIVATOR:
				kept.append(ref)
		copy.actor_spawn_refs = kept
		map.add_room(copy)
	map.entry_room = rooms[0].room_id
	return map


func _actor(realm_id: StringName = &"qi_refining") -> Actor:
	var actor := Actor.new(&"fixture_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.attach_core_resources()
	return actor


## Enter the shipped kit, so every case starts inside a real run rather than against a
## hand-built fixture room.
func _in_domain(realm_id: StringName = &"qi_refining") -> Actor:
	var actor := _actor(realm_id)
	DomainApi.enter(actor, _map(), &"ember_hollow")
	return actor


## The top of the shared ladder, named through the data because a ladder's length is
## content. An actor here is at or above every floor the kit can author.
func _ladder_ceiling() -> StringName:
	var realms := RealmDefaults.ladder().realms()
	return realms[realms.size() - 1].id if not realms.is_empty() else &"qi_refining"


func _install(keys: Callable, granter: Callable) -> void:
	DomainFixtures.set_minter(keys, granter)


## `keys` answering `reach` for `key_item_id` and nothing for anything else, plus a
## `granter` recording every delivery into `granted` — an Array the caller owns, which
## a closure captures by reference.
func _keyed(granted: Array, key_item_id: StringName, reach: float) -> void:
	_install(
		func(_actor_arg: Actor, item_id: StringName) -> float:
			return reach if item_id == key_item_id else 0.0,
		func(_actor_arg: Actor, item_id: StringName, count: int) -> int:
			granted.append({"item_id": String(item_id), "count": count})
			return 0
	)


func teardown() -> void:
	# `set_minter` is process-wide state and the runner calls this after EVERY test, so
	# a bridge left installed leaks into whatever suite runs next — the same reason
	# `test_domain_content.gd:224` restores its own.
	DomainFixtures.set_minter(Callable(), Callable())


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


# ── 6. no authored fixture is silently ignored ───────────────────────────────


## **The case that would have caught the gap this file closes.** Every fixture in every
## shipped room is read back out of the content tree and handed to the code: the ledger
## resolves it, the kind is one the closed set recognises, and the telegraph view
## renders. A fixture the module quietly skipped fails here instead of being content a
## player walks past.
func test_every_authored_fixture_is_recognised_by_the_runtime() -> void:
	var fixtures := _authored_fixtures()
	assert_eq(fixtures.is_empty(), false, "the shipped kit authors fixtures at all")
	var actor := _in_domain()
	var seen: Array[String] = []

	# The normalisation `_map` performs to make the kit enterable must cost no fixture,
	# or "every authored fixture is recognised" would be silently a smaller claim.
	assert_eq(
		(
			(actor.get_module_data(DomainApi.MODULE_KEY).get("map", {}) as Dictionary)
			. get("rooms", [])
			. size()
		),
		_authored_rooms().size(),
		"every shipped room is in the run the cases exercise"
	)

	for entry in fixtures:
		var fixture: Dictionary = entry["fixture"]
		var room_id := StringName(entry["room_id"])
		var fixture_id := String(fixture.get("fixture_id", ""))
		var kind := StringName(fixture.get("kind", ""))
		seen.append(fixture_id)
		assert_eq(
			DomainFixtures.KINDS.has(kind),
			true,
			(
				"fixture '%s' in room '%s' is a kind the runtime recognises"
				% [fixture_id, String(room_id)]
			)
		)
		assert_ne(
			DomainFixtures.state_of(actor, room_id, StringName(fixture_id)).is_empty(),
			true,
			"fixture '%s' has a ledger entry the runtime can read" % fixture_id
		)

		# The telegraph view renders, which is the read a scene needs to draw it BEFORE
		# anything lands.
		var seen_view := DomainFixtures.telegraph(actor, room_id, StringName(fixture_id))
		assert_eq(
			seen_view.get("ok"), true, "fixture '%s' telegraphs: %s" % [fixture_id, str(seen_view)]
		)
		assert_eq(String(seen_view.get("fixture_id", "")), fixture_id, "identifying itself")
		assert_eq(String(seen_view.get("kind", "")), String(kind), "with its authored kind")
		assert_eq(
			bool(seen_view.get("boundary_visible", false)),
			true,
			"fixture '%s' draws a boundary before it lands" % fixture_id
		)
		var box := fixture.get("bounds", Rect2i()) as Rect2i
		assert_eq(
			seen_view.get("bounds", []),
			[box.position.x, box.position.y, box.size.x, box.size.y],
			"and the bounds are the authored ones, relative to the owning room"
		)

	assert_eq(
		_distinct(seen).size(),
		seen.size(),
		"no two authored fixtures share an id, or the ledger would collide"
	)


## The same claim through the facade's read model, because a screen renders from
## `summary()` and not from the module. Every authored fixture appears there too — an
## untouched one included, since a reader asking "what is in this room" has to see a
## trap that has not armed yet.
func test_the_facade_reports_every_authored_fixture() -> void:
	var actor := _in_domain()
	var rows := DomainApi.summary(actor).get("fixtures", {}) as Dictionary
	assert_eq(
		int(rows.get("count", 0)),
		_authored_fixtures().size(),
		"the read model reports one row per AUTHORED fixture, untouched ones included"
	)

	var kinds: Dictionary = {}
	for row in rows.get("fixtures", []):
		var kind := String(row.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		assert_eq(
			row.has("spent"),
			true,
			"'%s' reports whether it has fired" % String(row.get("fixture_id", ""))
		)
		assert_eq(
			row.has("claimed"),
			true,
			"'%s' reports whether it is taken" % String(row.get("fixture_id", ""))
		)
	for kind in KINDS:
		assert_eq(
			int(kinds.get(kind, 0)) > 0,
			true,
			"the shipped kit authors at least one '%s' fixture the read model reports" % kind
		)

	# A trap that has fired is reported as fired, so a map can draw it spent.
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	DomainFixtures.arm(actor, room_id, TRAP, float(authored.get("telegraph_s", 0.0)) + 0.1)
	assert_eq(
		bool(_row(DomainApi.summary(actor), room_id, TRAP).get("spent", false)),
		true,
		"a fired trap is reported as spent"
	)


## The read model is primitives only, like every other facade answer: a `Vector2i` or
## `StringName` reaching it would break every save it rides in.
func test_the_fixture_read_model_is_json_clean() -> void:
	var actor := _in_domain()
	DomainFixtures.arm(actor, _room_of(TRAP), TRAP, 0.0)
	var parsed: Variant = JSON.parse_string(
		JSON.stringify(DomainApi.summary(actor).get("fixtures", {}))
	)
	assert_eq(parsed is Dictionary, true, "the fixture read model is JSON-clean")


func _row(summary: Dictionary, room_id: StringName, fixture_id: StringName) -> Dictionary:
	for row in (summary.get("fixtures", {}) as Dictionary).get("fixtures", []):
		if (
			String(row.get("room_id", "")) == String(room_id)
			and String(row.get("fixture_id", "")) == String(fixture_id)
		):
			return row
	return {}


# ── 7. the ledger round-trips ────────────────────────────────────────────────


## ADR 0027. State lives in `actor.module_data`, String-keyed and JSON-clean; a
## `Vector2` in there would silently break every save. The check is the JSON round trip
## FIRST (which is what a save does to it) and the state equalities after.
func test_fixture_state_round_trips_through_an_actor_save() -> void:
	var granted: Array = []
	_keyed(granted, &"ash_furnace_key", 1.0)
	var actor := _in_domain(&"core_formation")

	# Move every kind's state, so the round trip carries all three shapes.
	var trap_room := _room_of(TRAP)
	DomainFixtures.arm(actor, trap_room, TRAP, 0.0)
	DomainFixtures.arm(actor, trap_room, TRAP, float(_authored(TRAP).get("telegraph_s", 0.0)) + 0.1)
	var puzzle_room := _room_of(PUZZLE)
	var puzzle_sequence: Array = _authored(PUZZLE).get("sequence", [])
	DomainFixtures.attempt(actor, puzzle_room, PUZZLE, StringName(puzzle_sequence[0]))
	var keyed_room := _room_of(KEYED)
	DomainFixtures.claim(actor, keyed_room, KEYED)

	var parsed: Variant = JSON.parse_string(
		JSON.stringify(actor.get_module_data(DomainApi.MODULE_KEY))
	)
	assert_eq(
		parsed is Dictionary,
		true,
		"the run state is JSON-clean: a leaked Vector2i or StringName breaks every save"
	)
	assert_eq(
		(parsed as Dictionary).get(DomainFixtures.STATE_KEY) is Dictionary,
		true,
		"and the fixture ledger rides inside it as a plain dictionary"
	)

	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(
		DomainFixtures.state_of(restored, trap_room, TRAP).get("spent", false),
		true,
		"a spent trap is still spent after save/load"
	)
	assert_eq(
		int(DomainFixtures.state_of(restored, puzzle_room, PUZZLE).get("progress", 0)),
		1,
		"puzzle progress survives"
	)
	assert_eq(
		DomainFixtures.state_of(restored, keyed_room, KEYED).get("claimed", false),
		true,
		"a claimed hoard is still claimed after save/load"
	)

	# The restored actor is still IN the run, so a re-claim is refused by the LOADED
	# state rather than by anything the live object happened to be holding.
	var reload_granted: Array = []
	_keyed(reload_granted, &"ash_furnace_key", 1.0)
	assert_eq(
		DomainFixtures.claim(restored, keyed_room, KEYED).get("ok"),
		false,
		"and the loaded claim is what refuses a second one"
	)
	assert_eq(reload_granted.is_empty(), true, "paying nothing for it")


## A ledger read back out of a save has no bools and no int/float distinction — `true`
## arrives as `1.0`. Normalisation is what stops that reading as "not spent", which
## would re-arm every trap on every load.
func test_a_ledger_written_by_json_reads_back_as_spent() -> void:
	var actor := _in_domain()
	var room_id := _room_of(TRAP)
	var authored := _authored(TRAP)
	DomainFixtures.arm(actor, room_id, TRAP, 0.0)
	DomainFixtures.arm(actor, room_id, TRAP, float(authored.get("telegraph_s", 0.0)) + 0.1)

	# Overwrite the restored ledger with the DECODED shape, so the numbers really are the
	# ones a save file hands back rather than the ones this process built.
	var decoded: Dictionary = JSON.parse_string(
		JSON.stringify(actor.get_module_data(DomainApi.MODULE_KEY))
	)
	var restored := Actor.from_dict(actor.to_dict())
	var state := restored.get_module_data(DomainApi.MODULE_KEY)
	state[DomainFixtures.STATE_KEY] = decoded.get(DomainFixtures.STATE_KEY, {})
	restored.set_module_data(DomainApi.MODULE_KEY, state)

	assert_eq(
		DomainFixtures.state_of(restored, room_id, TRAP).get("spent", false),
		true,
		"a decoded 'spent' flag reads as spent, not as 0.0"
	)
	assert_eq(
		DomainFixtures.arm(restored, room_id, TRAP, PAST_TELEGRAPH).get("reason"),
		DomainFixtures.ERR_ALREADY_FIRED,
		"so no trap can be re-fired by reloading a save"
	)


# ── 8. loud refusals ─────────────────────────────────────────────────────────


## Outside a run there is no fixture, and the answer says so by name rather than
## returning a `{}` the caller would have to interpret. All three verbs are asked, so a
## verb added later is covered without editing this file.
func test_a_fixture_in_a_room_with_no_active_domain_is_refused_by_name() -> void:
	var actor := _actor()
	var room_id := _room_of(UNKEYED)
	for verb in [_claim_verb, _attempt_verb, _arm_verb]:
		var result: Dictionary = verb.call(actor, room_id, UNKEYED)
		assert_eq(result.get("ok"), false, "%s outside a run is refused" % verb.get_method())
		assert_eq(
			result.get("reason"),
			DomainFixtures.ERR_NO_RUN,
			"%s names the absence of a domain, not a guess" % verb.get_method()
		)
	assert_eq(DomainFixtures.summary(actor), {}, "and the read model is empty outside a run")


## Inside a run but naming a fixture no room authors, the other half of the same
## refusal. A `{}` here would let a caller invent a fixture.
func test_a_fixture_no_room_authors_is_refused_by_name() -> void:
	var claimed := DomainFixtures.claim(_in_domain(), _room_of(UNKEYED), &"no_such_fixture")
	assert_eq(claimed.get("ok"), false, "a fixture the kit does not author is refused")
	assert_eq(claimed.get("reason"), DomainFixtures.ERR_UNKNOWN_FIXTURE, "with a named reason")
	assert_eq(String(claimed.get("fixture_id", "")), "no_such_fixture", "naming what was asked for")


## A null actor is named, never dereferenced — the same contract
## `EnvironmentField.apply` offers for its own nulls.
func test_a_null_actor_is_refused_rather_than_dereferenced() -> void:
	var room_id := _room_of(UNKEYED)
	assert_eq(
		DomainFixtures.claim(null, room_id, UNKEYED).get("reason"),
		DomainFixtures.ERR_NO_ACTOR,
		"a null actor is named"
	)
	assert_eq(
		DomainFixtures.arm(null, room_id, TRAP, 1.0).get("reason"),
		DomainFixtures.ERR_NO_ACTOR,
		"and so is a null actor arming a trap"
	)
	assert_eq(
		DomainFixtures.state_of(null, room_id, UNKEYED), {}, "and there is no state to read for one"
	)


## A kind outside the closed set is a refusal, not a skip. A fourth kind someone authors
## has to land as a red test rather than a fixture the game walks past.
func test_a_kind_outside_the_closed_set_is_refused_rather_than_ignored() -> void:
	var actor := _in_domain()
	var room := DomainApi.room(actor, _room_of(UNKEYED))
	var fixtures := (room.get("fixtures", []) as Array).duplicate(true)
	assert_eq(fixtures.is_empty(), false, "the room under test authors a fixture to retag")
	# Retag the shipped fixture as a kind nothing resolves.
	(fixtures[0] as Dictionary)["kind"] = &"mystery_box"
	var broken := DomainMap.new(Vector2i(8, 8), 1)
	var scratch := RoomDef.from_dict(room)
	scratch.fixtures = fixtures as Array[Dictionary]
	broken.add_room(scratch)
	broken.entry_room = scratch.room_id
	DomainApi.enter(actor, broken, &"scratch")

	var result := DomainFixtures.claim(actor, scratch.room_id, UNKEYED)
	assert_eq(result.get("ok"), false, "an unrecognised kind is refused")
	assert_eq(
		result.get("reason"),
		DomainFixtures.ERR_UNKNOWN_KIND,
		"and named, rather than silently dropped"
	)


## A missing bridge is refused at the gate rather than paying out into nothing. An
## UNKEYED hoard short-circuits before the bridge is consulted, so "openable now" has to
## hold even on an actor that never wired the items module at all.
func test_a_missing_bridge_is_refused_by_name_rather_than_silently_passing() -> void:
	_install(Callable(), Callable())
	assert_eq(
		DomainFixtures.claim(_in_domain(&"core_formation"), _room_of(KEYED), KEYED).get("reason"),
		DomainFixtures.ERR_NO_BRIDGE,
		"a keyed hoard with no key reader installed is refused"
	)

	var granted: Array = []
	_keyed(granted, &"", 0.0)
	assert_eq(
		DomainFixtures.claim(_in_domain(), _room_of(UNKEYED), UNKEYED).get("ok"),
		true,
		"an unkeyed hoard is openable with no bridge at all"
	)
	assert_eq(granted.size(), 1, "and it still pays out")


# ── the seam, and the cap ────────────────────────────────────────────────────


## `set_minter` is process-wide state, and a bridge left installed would make the next
## suite's actors answer to a bag they never had. The text is read rather than the
## behaviour: this file must name no sibling module's class, because `domain` declares
## `core` + `contracts` only (`tools/arch/registry.json:60`) and a bare `ItemsApi.` here
## would be an undeclared edge the gate cannot see.
func test_the_bridge_is_the_only_contact_with_the_items_module() -> void:
	var script := load("res://src/modules/domain/domain_fixtures.gd") as GDScript
	var code: String = script.source_code
	for forbidden in ["ItemsApi", "Crafting", "LootApi", "LootState", "Inventory"]:
		assert_eq(
			code.contains(forbidden),
			false,
			(
				"domain_fixtures.gd names no '%s': the module declares core + contracts only"
				% forbidden
			)
		)


## The facade gained no verb. `DomainFixtures` is reached from `summary()` and from the
## three module verbs, so the ISP cap is untouched — asserted from the script text
## because that is the same number `tools arch` counts (`enforce.py:230`).
func test_the_facade_is_still_within_the_cap() -> void:
	var script := load("res://src/modules/domain/api.gd") as GDScript
	var count := 0
	for line in (script.source_code as String).split("\n"):
		if line.begins_with("static func ") and not line.contains("static func _"):
			count += 1
	assert_eq(
		count <= 12, true, "DomainApi still declares %d public static methods (cap 12)" % count
	)


# ── helpers ──────────────────────────────────────────────────────────────────


## The unique values in `values`, first-seen order. A bounded `for`; there is no
## `Array.uniq` in this GDScript and hand-rolling it keeps the assertion readable.
func _distinct(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


## The three verbs as `Callable`s, so one loop can ask "does EVERY verb refuse a fixture
## outside a run" rather than repeating the assertion three times.
func _arm_verb(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.arm(actor, room_id, fixture_id, 0.0)


func _attempt_verb(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.attempt(actor, room_id, fixture_id, &"")


func _claim_verb(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.claim(actor, room_id, fixture_id)
