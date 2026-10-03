extends TestCase

## The one ledger every system that must remember something writes (ADR 0113).
##
## These assert the PROPERTIES the ADR buys, not the shape this file happens to
## have: a ledger that starts empty, rises only, records WHEN a thing first
## happened, refuses a caller that asks for nothing, survives the JSON hop a save
## makes, and reads a garbage payload as "nothing happened" instead of throwing.
## The `since` half is what a "first time" gate is built on, and the monotone
## half is the property ADR 0065's house position rests on — a fact that could be
## revoked is a fact that can lie.

const BOAR := &"killed_boar"
const DUELS := &"duels_won"
const THIRD_BEAR := &"killed_boar@3"


func _hero() -> Actor:
	return Actor.new(&"hero")


# --- An empty ledger is empty, not absent -------------------------------------


## A fact nobody recorded counts zero and is not held. "Never happened" and
## "happened zero times" are the same answer, because a count never falls.
func test_an_actor_with_no_ledger_remembers_nothing() -> void:
	var actor := _hero()
	assert_eq(WorldFact.count(actor, BOAR), 0, "a fact never recorded counts zero")
	assert_eq(WorldFact.has(actor, BOAR), false, "so it is not held")
	assert_eq(WorldFact.has(actor, BOAR, 3), false, "and three of them is not held either")
	assert_eq(WorldFact.fact(actor, BOAR).since, 0, "its row is the empty one")


## Every read works on an actor that has never been attached to anything, and on
## a null actor. `get_module_data` already answers `{}` for a payload that is not
## a dictionary, so the ledger must be the same answer here rather than a throw
## three stages later in whichever system asked.
func test_reads_tolerate_a_missing_and_a_foreign_payload() -> void:
	assert_eq(WorldFact.count(null, BOAR), 0, "a null actor remembers nothing")
	assert_eq(WorldFact.has(null, BOAR), false, "and holds nothing")
	assert_eq(WorldFact.to_dict(null), WorldFact.empty(), "and carries an empty ledger")
	var actor := _hero()
	actor.set_module_data(WorldFact.MODULE_KEY, {"facts": {"killed_boar": 7}})
	assert_eq(WorldFact.count(actor, BOAR), 0, "a row that is not a dictionary is unreadable")
	var parked := _hero()
	parked.set_module_data(WorldFact.MODULE_KEY, {"facts": {"killed_boar": {"count": 7}}})
	assert_eq(WorldFact.count(parked, BOAR), 7, "a hand-parked row is still read")
	var junk := _hero()
	junk.set_module_data(WorldFact.MODULE_KEY, {"version": 99, "rows": {}})
	assert_eq(WorldFact.normalize(junk), WorldFact.empty(), "a foreign shape normalises to empty")


# --- Recording is monotone, and it records WHEN ------------------------------


## A record raises the count, and `has` answers true the moment there is one —
## `need` defaults to 1 so the common question is a single argument.
func test_a_record_raises_the_count_and_is_then_held() -> void:
	var actor := _hero()
	var first := WorldFact.record(actor, BOAR)
	assert_eq(first["ok"], true, "the first record lands")
	assert_eq(first["count"], 1, "and the count is one")
	assert_eq(WorldFact.count(actor, BOAR), 1, "so the ledger holds one")
	assert_eq(WorldFact.has(actor, BOAR), true, "so the fact is held")
	assert_eq(WorldFact.has(actor, BOAR, 1), true, "one is all it asks for")
	assert_eq(WorldFact.has(actor, BOAR, 2), false, "but two is not there yet")


## A later record raises the count again. Amounts are caller-owned and explicit
## (DEF-0111), so "three at once" is a different act from "three times".
func test_amount_is_the_caller_and_the_count_only_rises() -> void:
	var actor := _hero()
	assert_eq(WorldFact.record(actor, BOAR, 3)["count"], 3, "three in one act")
	assert_eq(WorldFact.record(actor, BOAR)["count"], 4, "and a fourth on top")
	assert_eq(WorldFact.has(actor, BOAR, 4), true, "so four is held")
	assert_eq(WorldFact.has(actor, BOAR, 5), false, "but five is not")


## `since` is the count at first record and is NEVER advanced afterwards. This
## is the whole reason the field exists: a fact whose `since` still equals its
## count has happened exactly once, so a "first time" gate is answerable from a
## single row instead of a second dispatch ledger.
func test_since_is_written_once_and_never_advances() -> void:
	var actor := _hero()
	WorldFact.record(actor, BOAR, 2)
	assert_eq(WorldFact.fact(actor, BOAR).since, 2, "the first record sets since to its total")
	assert_eq(WorldFact.fact(actor, BOAR).count, 2, "and count agrees")
	WorldFact.record(actor, BOAR, 5)
	var fact := WorldFact.fact(actor, BOAR)
	assert_eq(fact.count, 7, "the count moved to seven")
	assert_eq(fact.since, 2, "but since is still the count at first record")
	assert_ne(fact.since, fact.count, "so count and since no longer agree")
	WorldFact.record(actor, BOAR)
	assert_eq(WorldFact.fact(actor, BOAR).since, 2, "and a third record does not touch it")


## A ledger has no verb that lowers a count, and the stored rows carry nothing
## that could. ADR 0113 is explicit: a fact is monotone, cannot be spent and
## cannot be revoked — a "consumed" thing is a quest step, not a fact. Asserted
## against the API surface rather than a behaviour, because the property IS the
## absence of a verb.
func test_the_api_surface_has_no_verb_that_lowers_a_count() -> void:
	var mutators: Array[String] = []
	# Read the class's OWN script methods, not the whole Object surface:
	# `remove_meta` and `remove_user_signal` are inherited from Object, and
	# "WorldFact has no remove verb" was never a claim about every GDScript
	# class. Filtering to this script is what makes the assertion honest.
	for method in WorldFact.new().get_script().get_script_method_list():
		var name := String(method["name"])
		var lowered := name.contains("spend") or name.contains("consume")
		lowered = lowered or name.contains("revoke") or name.contains("remove")
		lowered = lowered or name.contains("clear") or name.contains("reset")
		lowered = lowered or name.contains("set_count") or name.contains("decay")
		if lowered:
			mutators.append(name)
	assert_eq(mutators, [], "WorldFact exposes no verb that could lower a count")


# --- A refused record mutates NOTHING ----------------------------------------


## Zero and negative amounts are refused with a reason, and the ledger is
## byte-equal before and after. Absorbing a zero would leave the ledger claiming
## a thing happened that did not, which is the one lie the world's memory must
## not be able to tell.
func test_a_non_positive_amount_is_refused_and_mutates_nothing() -> void:
	var actor := _hero()
	WorldFact.record(actor, BOAR)
	WorldFact.record(actor, DUELS, 4)
	var before := JSON.stringify(WorldFact.to_dict(actor))
	assert_eq(WorldFact.record(actor, BOAR, 0)["reason"], "non_positive", "zero is refused")
	assert_eq(WorldFact.record(actor, BOAR, -3)["reason"], "non_positive", "and so is a negative")
	assert_eq(WorldFact.record(actor, BOAR, 0)["ok"], false, "the refusal is visible")
	assert_eq(WorldFact.record(actor, BOAR, -3)["ok"], false, "for a negative too")
	assert_eq(JSON.stringify(WorldFact.to_dict(actor)), before, "the ledger is byte-equal")
	assert_eq(WorldFact.count(actor, BOAR), 1, "so the count did not move")
	assert_eq(WorldFact.count(actor, DUELS), 4, "nor did any other")


## A beat with no id is refused too, and names itself. An empty fact id is a
## caller bug, and a row filed under `""` would be a fact about nothing that
## every other gate would read as a held one.
func test_an_empty_fact_id_is_refused_rather_than_recorded() -> void:
	var actor := _hero()
	assert_eq(WorldFact.record(actor, &"")["reason"], "empty_id", "an empty id names itself")
	assert_eq(WorldFact.count(actor, &""), 0, "and nothing is recorded under it")
	assert_eq(WorldFact.normalize(actor), WorldFact.empty(), "so the ledger is untouched")


# --- A garbage payload reads as empty, never as a throw -----------------------


## A hand-edited or foreign save is untrusted input. Every unusable field is
## repaired or dropped, a payload that cannot be read is diagnosed as EMPTY
## rather than partially applied — half a ledger is worse than none — and
## nothing here raises.
func test_normalize_repairs_a_garbage_payload_instead_of_throwing() -> void:
	var actor := _hero()
	(
		actor
		. set_module_data(
			WorldFact.MODULE_KEY,
			{
				"facts":
				{
					"killed_boar": {"count": 3, "since": 1},
					"duels_won": {"count": -5, "since": -5},
					"slain_boss": {"count": "four", "since": "yesterday"},
					"cleared_den": 9,
					"": {"count": 2},
				}
			}
		)
	)
	var ledger := WorldFact.normalize(actor)
	assert_eq(ledger["version"], WorldFact.SCHEMA_VERSION, "the schema version is stamped")
	assert_eq(WorldFact.count(actor, BOAR), 3, "a readable row survives verbatim")
	assert_eq(WorldFact.fact(actor, BOAR).since, 1, "with its since intact")
	assert_eq(WorldFact.count(actor, DUELS), 0, "a negative count is dropped, never persisted")
	assert_eq(WorldFact.count(actor, &"cleared_den"), 0, "so is a row that is not a dictionary")
	assert_eq(WorldFact.count(actor, &"slain_boss"), 0, "and one whose fields are strings")
	assert_eq((ledger["facts"] as Dictionary).size(), 1, "so only the one honest row remains")
	assert_eq(WorldFact.has(actor, DUELS), false, "and nothing unreadable reads as held")


## `since` is clamped into `[0, count]` on the way in, because the storage
## invariant "written on the first record, never advanced" is only worth anything
## if a hand-edited save cannot state otherwise.
func test_a_hand_edited_since_is_clamped_into_range() -> void:
	var actor := _hero()
	actor.set_module_data(
		WorldFact.MODULE_KEY, {"facts": {"killed_boar": {"count": 4, "since": 99}}}
	)
	assert_eq(WorldFact.fact(actor, BOAR).since, 4, "a since above the count clamps down")
	assert_eq(WorldFact.fact(actor, BOAR).total, 4, "and the count is untouched")
	var dropped := _hero()
	dropped.set_module_data(WorldFact.MODULE_KEY, {"facts": {"killed_boar": {"count": 6}}})
	assert_eq(WorldFact.fact(dropped, BOAR).since, 0, "a missing since is not invented")
	assert_eq(WorldFact.count(dropped, BOAR), 6, "and the count still reads")


## The ledger value object round-trips by itself, and it is primitives-only:
## an inner `StringName` key would reach the save untouched and break every
## round trip, because `Actor.to_dict` converts only the OUTER key.
func test_the_ledger_payload_is_json_round_trippable() -> void:
	var actor := _hero()
	WorldFact.record(actor, BOAR, 2)
	WorldFact.record(actor, DUELS)
	var restored := WorldFact.normalize_payload(
		JSON.parse_string(JSON.stringify(WorldFact.to_dict(actor)))
	)
	assert_eq(restored, WorldFact.to_dict(actor), "the ledger survives the JSON hop")
	for key in (restored["facts"] as Dictionary).keys():
		assert_eq(typeof(key), TYPE_STRING, "and every inner key is a String")


# --- It survives the actor ---------------------------------------------------


## One serialization, because this is a module_data ledger (ADR 0027) rather
## than a bespoke save slot. The JSON hop is included because a file-backed save
## makes one and JSON has a single number type.
func test_the_ledger_survives_an_actor_round_trip() -> void:
	var actor := _hero()
	WorldFact.record(actor, BOAR, 3)
	WorldFact.record(actor, DUELS, 7)
	var restored := Actor.from_dict(JSON.parse_string(JSON.stringify(actor.to_dict())))
	assert_eq(WorldFact.count(restored, BOAR), 3, "the boars came back")
	assert_eq(WorldFact.count(restored, DUELS), 7, "and the duels")
	assert_eq(WorldFact.fact(restored, BOAR).since, 3, "with since still the first total")
	assert_eq(WorldFact.fact(restored, DUELS).since, 7, "on both rows")
	assert_eq(WorldFact.has(restored, DUELS, 7), true, "and the gate still opens")


## Occurrence ids are recorded as counts, which is what makes "once" answerable
## by counting at all (ADR 0114). The caller mints the unique id; the ledger
## stores whatever it is handed and never invents a namespace of its own.
func test_each_occurrence_is_its_own_row_under_the_same_flat_namespace() -> void:
	var actor := _hero()
	WorldFact.record(actor, BOAR)
	WorldFact.record(actor, THIRD_BEAR)
	WorldFact.record(actor, THIRD_BEAR)
	assert_eq(WorldFact.count(actor, THIRD_BEAR), 2, "the third boar's id holds two")
	assert_eq(WorldFact.count(actor, BOAR), 1, "and the plain id holds one")
	assert_eq((WorldFact.normalize(actor)["facts"] as Dictionary).size(), 2, "two rows")


## One row per fact id, and no prefix namespace: ADR 0065 refused an id scheme
## that "reads as a working reference and silently grants nothing", so the ledger
## stores bare ids and nothing rewrites them.
func test_ids_are_bare_and_never_rewritten() -> void:
	var actor := _hero()
	WorldFact.record(actor, &"quest:found_the_ledger", 2)
	var rows := WorldFact.normalize(actor)["facts"] as Dictionary
	assert_eq(rows.has("quest:found_the_ledger"), true, "the caller's id is stored as given")
	assert_eq(rows.has("found_the_ledger"), false, "and no derived id is invented")


## A beat is a PROPOSAL: building and validating one moves nothing. Recording is
## not dispatching, and nothing about a beat may touch the ledger before the
## owner of the moment calls `record` (ADR 0114).
func test_a_beat_is_a_proposal_and_moves_nothing_on_its_own() -> void:
	var actor := _hero()
	WorldFact.record(actor, BOAR, 2)
	var before := JSON.stringify(WorldFact.to_dict(actor))
	var beat := WorldBeat.make(THIRD_BEAR, BOAR, 1, "combat")
	assert_eq(beat.is_valid(), true, "the beat is valid")
	assert_eq(WorldFact.count(actor, THIRD_BEAR), 0, "but no occurrence exists yet")
	assert_eq(JSON.stringify(WorldFact.to_dict(actor)), before, "and the ledger is untouched")
	WorldFact.record(actor, beat.fact, beat.amount)
	assert_eq(WorldFact.count(actor, BOAR), 3, "recording the fact is the caller's act")
	assert_eq(JSON.stringify(WorldFact.to_dict(actor)) != before, true, "and it is the only one")
