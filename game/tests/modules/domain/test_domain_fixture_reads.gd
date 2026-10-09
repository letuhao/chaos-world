extends "res://tests/modules/domain/domain_fixture_kit.gd"

## ADR 0073 / ADR 0075: `RoomDef.fixtures` is not a field nobody reads -- the
## read-model, ledger and refusal half.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no
## method renamed: this half is the file's sections 6-8 verbatim plus the
## seam-and-cap guards and the `_row` read-model helper, and every constant,
## builder and helper it reads lives in `domain_fixture_kit.gd`, which both halves
## `extends`.
##
## The gameplay half -- telegraph, firing, mitigation, the formation gate and treasure
## -- is `test_domain_fixtures.gd`.
##
## Every loop below is a bounded `for`. There is no `while`.

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
	# A typed copy: `as Array[Dictionary]` on an untyped array raises at assignment
	# (GDScript does not convert array types), which aborted this body.
	var retagged: Array[Dictionary] = []
	for fixture in fixtures:
		retagged.append(fixture as Dictionary)
	var scratch := RoomDef.from_dict(room)
	scratch.fixtures = retagged
	# A scratch COPY of the kit's whole ring, one room retagged: a lone room is refused
	# by the map contract (`has no exit at all`), and asserting the retag against a map
	# that cannot be entered is how this case first read `no_inventory_bridge`.
	var entered := DomainApi.enter(actor, _map_with_replacement(scratch), &"scratch")
	# Asserted, not assumed: a refused scratch map leaves the PREVIOUS run active and
	# every assertion below then reads the wrong fixtures.
	assert_eq(
		bool(entered.get("ok", false)), true, "the scratch map is enterable: %s" % str(entered)
	)

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
