extends TestCase

## The fate/destiny ledger is a versioned plain dictionary under
## `actor.module_data` (ADR 0027), and it is the single source of truth for what
## the player is owed. These assert the shape of that ledger, that an unreadable
## payload is diagnosed as empty rather than partially applied, that an entry
## naming content the catalog no longer ships is dropped rather than persisted,
## and that the namespaced ids the projection depends on are what they claim.

const MODULE_KEY := DestinyState.MODULE_KEY
const FATE := &"t_oath_breaker"
const DESTINY := &"t_chosen_one"
const PLEDGE := &"t_blood_pledge"


## A catalog holding exactly the ids the round-trip test earns through, so the
## ledger it persists is filtered against real content rather than the shipped
## tree. The pure-shape tests below install nothing of their own and keep working
## because `normalize()` with an empty filter accepts every entry.
func setup() -> void:
	DestinyFixtureCatalog.install(
		[DestinyFixtureCatalog.flat_fate(FATE, Stat.DEFENSE_PHYSICAL, 3.0)],
		[DestinyFixtureCatalog.plain_destiny(DESTINY)]
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _ledger_with(
	fates: Dictionary = {},
	destinies: Dictionary = {},
	counters: Dictionary = {},
	history: Array = []
) -> Dictionary:
	var payload := {}
	if not fates.is_empty():
		payload["fates"] = fates
	if not destinies.is_empty():
		payload["destinies"] = destinies
	if not counters.is_empty():
		payload["counters"] = counters
	if not history.is_empty():
		payload["history"] = history
	return DestinyState.normalize(payload)


# --- The shape of the ledger -------------------------------------------------


func test_an_empty_payload_normalizes_to_the_empty_versioned_ledger() -> void:
	for payload in [{}, {"version": DestinyState.SCHEMA_VERSION}]:
		var ledger := DestinyState.normalize(payload)
		assert_eq(int(ledger["version"]), DestinyState.SCHEMA_VERSION, "always versioned")
		assert_eq(ledger["fates"] as Dictionary, {}, "no fates in %s" % [payload])
		assert_eq(ledger["destinies"] as Dictionary, {}, "no destinies in %s" % [payload])
		assert_eq(ledger["counters"] as Dictionary, {}, "no counters in %s" % [payload])
		assert_eq(ledger["history"] as Array, [], "no history in %s" % [payload])
	assert_eq(DestinyState.empty(), DestinyState.normalize({}), "empty() is that same ledger")


func test_a_legacy_payload_that_carries_no_destiny_state_at_all_loads_as_empty() -> void:
	# A save written before the module existed. Core hands the module an absent
	# key, so what the facade sees is a bare empty dictionary.
	var restored := Actor.from_dict({"id": "keeper", "base": {Stat.PHYSIQUE: 10.0}})
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no ledger")
	var ledger := DestinyState.normalize(restored.get_module_data(MODULE_KEY))
	assert_eq(int(ledger["version"]), DestinyState.SCHEMA_VERSION, "still versioned")
	assert_eq(DestinyState.fate_ids(ledger), [], "and empty, not partial")
	assert_eq(DestinyState.destiny_ids(ledger), [], "no destinies either")


func test_an_unreadable_payload_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	for payload in [
		{"version": 99, "fates": FATE},
		{"version": 1, "fates": "not a dictionary"},
		{"version": 1, "fates": [FATE]},
		{"version": 1, "destinies": 7},
		{"version": 1, "counters": "no"},
		{"version": 1, "history": "no"},
	]:
		var ledger := DestinyState.normalize(payload)
		assert_eq(ledger["fates"] as Dictionary, {}, "rejected fates in %s" % [payload])
		assert_eq(ledger["counters"] as Dictionary, {}, "rejected counters in %s" % [payload])
		assert_eq(ledger["history"] as Array, [], "rejected history in %s" % [payload])


func test_an_entry_that_cannot_be_read_is_dropped_while_its_readable_siblings_survive() -> void:
	var ledger := (
		DestinyState
		. normalize(
			{
				"version": 1,
				"fates":
				{
					"t_no_source": {"sequence": 1},
					"t_not_a_dictionary": 4,
					"t_null": null,
					"t_good": {"source": "combat", "sequence": 2},
				},
				"destinies":
				{"t_not_a_dictionary": "text", "t_good": {"source": "story", "sequence": 3}},
				"counters": {"duels_won": -4, "oaths": "three"},
				"history": ["not a record", {"kind": "fate", "id": "t_good"}],
			}
		)
	)
	# Half a ledger is worse than none: an entry that cannot be read is dropped
	# on its own, and the readable entries around it are still the player's.
	assert_eq(DestinyState.fate_ids(ledger), [&"t_good"], "one readable fate survives")
	assert_eq(DestinyState.destiny_ids(ledger), [&"t_good"], "one readable destiny survives")
	assert_eq(ledger["counters"] as Dictionary, {}, "no counter survives")
	assert_eq((ledger["history"] as Array).size(), 1, "one readable record survives")


func test_a_negative_or_non_numeric_counter_is_never_persisted() -> void:
	# A counter only ever rises, so a negative one cannot have been earned.
	var ledger := DestinyState.normalize(
		{"version": 1, "counters": {"duels_won": -1, "oaths": -0.5, "kills": "four", "duels": 0.0}}
	)
	assert_eq(ledger["counters"] as Dictionary, {"oaths": 0, "duels": 0}, "both zeroes survive")
	assert_eq(DestinyState.counter_value(ledger, &"duels_won"), 0, "a negative counter is not kept")
	assert_eq(DestinyState.counter_value(ledger, &"kills"), 0, "nor one that is not a number")


func test_an_entry_naming_content_the_catalog_no_longer_ships_is_dropped() -> void:
	var known := {"t_oath_breaker": true, "t_blood_pledge": true}
	var ledger := DestinyState.normalize(
		{
			"version": 1,
			"fates": {"t_oath_breaker": {"source": "combat"}, "t_retired": {"source": "old"}}
		},
		known,
		{}
	)
	assert_eq(
		DestinyState.fate_ids(ledger), [&"t_oath_breaker"], "a wider save cannot smuggle one in"
	)
	# An empty filter is an unanswered question, not a denial, so a catalog that
	# knows nothing yet keeps everything it is handed.
	var unfiltered := DestinyState.normalize(
		{"version": 1, "fates": {"t_retired": {"source": "old"}}}
	)
	assert_eq(
		DestinyState.fate_ids(unfiltered), [&"t_retired"], "an empty filter accepts everything"
	)
	assert_eq(
		DestinyState.fate_ids(ledger), [&"t_oath_breaker"], "the dropped entry stayed dropped"
	)


# --- Reading the ledger ------------------------------------------------------


func test_has_fate_and_has_destiny_answer_only_for_what_is_recorded() -> void:
	var ledger := _ledger_with(
		{"t_oath_breaker": {"source": "combat", "sequence": 1}},
		{"t_chosen_one": {"source": "story", "sequence": 2, "bearing": "You are bound."}}
	)
	assert_eq(DestinyState.has_fate(ledger, FATE), true, "the fate is held")
	assert_eq(
		DestinyState.has_fate(ledger, PLEDGE), false, "a fate that was never earned is not held"
	)
	assert_eq(DestinyState.has_destiny(ledger, DESTINY), true, "the destiny is held")
	assert_eq(
		DestinyState.has_destiny(ledger, &"t_never_earned"), false, "an unknown destiny is not held"
	)
	assert_eq(
		DestinyState.has_fate(DestinyState.empty(), FATE), false, "an empty ledger holds nothing"
	)


func test_fate_ids_and_destiny_ids_come_back_canonically_ordered() -> void:
	var ledger := _ledger_with(
		{
			"t_oath_breaker": {"source": "combat", "sequence": 3},
			"t_awakened": {"source": "path", "sequence": 1},
			"t_blood_pledge": {"source": "oath", "sequence": 2},
		},
		{"t_chosen_one": {"source": "story"}, "t_ascendant": {"source": "story"}}
	)
	# The order is a canonical one, so a codex that cycles the list never reorders
	# itself between reads, and two callers reading the same ledger always agree.
	# It is deliberately NOT insertion order — the entries install into a
	# dictionary, so insertion order would change with the shape of the hash.
	var fate_order: Array = []
	for fate_id in DestinyState.fate_ids(ledger):
		fate_order.append(String(fate_id))
	var destiny_order := _destiny_id_strings(ledger)
	assert_eq(
		fate_order, ["t_awakened", "t_blood_pledge", "t_oath_breaker"], "ordered by id, not earned"
	)
	assert_eq(destiny_order, ["t_ascendant", "t_chosen_one"], "destinies come back ordered")
	# Canonical means repeatable: a second read of the same ledger is identical,
	# and so is a ledger rebuilt from the same payload.
	assert_eq(_destiny_id_strings(ledger), destiny_order, "a second read returns the same order")
	var rebuilt := (
		DestinyState
		. normalize(
			{
				"version": 1,
				"fates":
				{
					"t_oath_breaker": {"source": "combat", "sequence": 3},
					"t_awakened": {"source": "path", "sequence": 1},
					"t_blood_pledge": {"source": "oath", "sequence": 2},
				},
				"destinies":
				{"t_chosen_one": {"source": "story"}, "t_ascendant": {"source": "story"}},
			}
		)
	)
	assert_eq(
		_destiny_id_strings(rebuilt),
		destiny_order,
		"and a ledger rebuilt from the same payload agrees"
	)
	# The earned order is still readable, through the per-entry sequence.
	var sequences: Array = []
	var fates := ledger["fates"] as Dictionary
	for fate_id in [FATE, &"t_awakened"]:
		var entry = fates.get(String(fate_id), null)
		if entry is Dictionary and (entry as Dictionary).has("sequence"):
			sequences.append(int((entry as Dictionary)["sequence"]))
		else:
			# Never subscript an unvalidated key into a typed local: that ABORTS
			# this function, and the runner's `suite.call(name)` cannot tell an
			# aborted test from a finished one — so the assertions below would be
			# skipped while the suite still reported green.
			assert_eq(
				fate_id, &"a readable entry", "the ledger holds a readable entry for '%s'" % fate_id
			)
			sequences.append(-1)
	assert_eq(sequences, [3, 1], "the earned order survives separately")


## The held destiny ids as strings, in the order the ledger hands them back.
func _destiny_id_strings(ledger: Dictionary) -> Array:
	var out: Array = []
	for destiny_id in DestinyState.destiny_ids(ledger):
		out.append(String(destiny_id))
	return out


func test_counter_value_reads_zero_for_a_counter_that_was_never_recorded() -> void:
	var ledger := _ledger_with({}, {}, {"duels_won": 3})
	assert_eq(DestinyState.counter_value(ledger, &"duels_won"), 3, "the recorded value")
	assert_eq(
		DestinyState.counter_value(ledger, &"oaths_taken"), 0, "an unrecorded counter is zero"
	)
	assert_eq(
		DestinyState.counter_value(ledger, &"duels_won"),
		3,
		"a missing counter and a zero one are the same answer"
	)


# --- Namespacing -------------------------------------------------------------


func test_every_stat_modifier_and_trait_the_module_writes_is_namespaced_under_destiny() -> void:
	assert_eq(
		DestinyState.source_for(FATE), &"destiny:t_oath_breaker", "the stat source is namespaced"
	)
	assert_eq(
		DestinyState.trait_for(FATE), &"destiny:t_oath_breaker", "the trait mirror matches it"
	)
	assert_eq(
		DestinyState.source_for(DESTINY),
		&"destiny:t_chosen_one",
		"a destiny is namespaced too, and identically to a fate"
	)
	assert_eq(
		DestinyState.is_own_source(&"destiny:t_oath_breaker"), true, "the module claims its own"
	)
	assert_eq(DestinyState.is_own_source(&"set:ironhide_vigil"), false, "and claims nothing else")
	assert_eq(DestinyState.is_own_source(&"t_oath_breaker"), false, "an unprefixed id is not ours")
	assert_eq(DestinyState.is_own_source(&""), false, "nor is the empty source")
	assert_eq(DestinyState.SOURCE_PREFIX, DestinyState.TRAIT_PREFIX, "one prefix names both")


# --- Boundedness -------------------------------------------------------------


func test_a_history_trail_read_from_a_payload_is_kept_exactly_as_given_and_deep_copied() -> void:
	var history: Array = []
	for index in DestinyState.HISTORY_LIMIT + 20:
		history.append({"kind": "counter", "id": "duels_won", "sequence": index})
	var ledger := DestinyState.normalize({"version": 1, "history": history})
	assert_eq(
		(ledger["history"] as Array).size(),
		DestinyState.HISTORY_LIMIT + 20,
		"a payload is read back exactly as given, cap or no cap"
	)
	# Records are copied, not aliased: a later mutation of the source array cannot
	# reach back into the ledger.
	history[0]["id"] = "tampered"
	assert_eq(
		String((ledger["history"] as Array)[0]["id"]),
		"duels_won",
		"history records are deep-copied"
	)


## The bound itself, executed rather than asserted about a constant.
##
## `_record()` returns early once the trail is at `HISTORY_LIMIT`, so this is the
## only shape that can prove it: write past the cap on a live actor and read the
## trail back. Asserting `HISTORY_LIMIT <= 256` proved nothing — it compared a
## literal with a literal, and would have kept passing if the cap were removed
## entirely.
func test_the_history_trail_stops_growing_at_the_bound_and_never_beyond_it() -> void:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	# Enough writes to overshoot by a wide margin. The catalog ships no counter
	# definitions, so every `record()` is a real movement and every one of them
	# would append to the trail if the cap were not there.
	var writes := DestinyState.HISTORY_LIMIT + 40
	for index in writes:
		DestinyApi.record(actor, &"duels_won", 1)
	var trail := DestinyApi.state(actor)["history"] as Array
	assert_eq(
		trail.size(),
		DestinyState.HISTORY_LIMIT,
		"%d writes left exactly HISTORY_LIMIT records" % writes
	)
	assert_eq(
		DestinyApi.counter(actor, &"duels_won"),
		writes,
		"while the counter itself kept every one of the writes"
	)
	# More writes past the cap change nothing at all: the bound holds however long
	# the save is played.
	for index in DestinyState.HISTORY_LIMIT:
		DestinyApi.record(actor, &"duels_won", 1)
	assert_eq(
		(DestinyApi.state(actor)["history"] as Array).size(),
		DestinyState.HISTORY_LIMIT,
		"and a further HISTORY_LIMIT writes added no record"
	)
	# What IS kept is the most recent half of the trail, not the oldest: `_record`
	# appends and stops, so the records already written are the ones that remain.
	assert_eq(
		String((trail[0] as Dictionary)["id"]),
		"duels_won",
		"and the trail still explains what the player is owed"
	)


func test_the_module_key_is_the_one_core_persists_generic_module_data_under() -> void:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0})
	actor.set_module_data(MODULE_KEY, DestinyState.empty())
	var payload: Dictionary = actor.to_dict()
	assert_eq(
		(payload["module_data"] as Dictionary).has(String(MODULE_KEY)), true, "it is module data"
	)
	assert_eq(
		DestinyApi.MODULE_KEY, DestinyState.MODULE_KEY, "the facade persists under the same key"
	)


# --- Round-tripping ----------------------------------------------------------


## The whole ledger survives `to_dict` -> `from_dict` AND a JSON hop, field for
## field — not merely "the fates are still there".
##
## This is the criterion `normalize()` exists to satisfy: a history record is
## rebuilt one field at a time and `sequence` is coerced to int, because JSON has
## a single number type. Without that coercion a round trip turns `2` into `2.0`
## and the ledger stops comparing equal to ITSELF across a save — the one state a
## persistence layer cannot be allowed to reach. Every field is compared here so a
## regression names the field that drifted rather than the whole dictionary.
func test_the_whole_ledger_survives_a_payload_round_trip_and_a_json_hop() -> void:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	DestinyApi.earn_fate(actor, FATE, "combat")
	DestinyApi.earn_destiny(actor, DESTINY, "story")
	DestinyApi.record(actor, &"duels_won", 3)
	var before := DestinyApi.state(actor)
	assert_eq((before["history"] as Array).size(), 3, "three records were written")
	# A sequence greater than 1 is what would become 2.0 on the way out, so the
	# fixture earns in an order that guarantees one.
	assert_eq(
		int((before["destinies"] as Dictionary)[String(DESTINY)]["sequence"]),
		2,
		"the destiny is the second thing earned, so its sequence is not 1"
	)
	var payload: Dictionary = actor.to_dict()
	# 1. The payload round trip: no fate type involved, core just carries it.
	var restored := Actor.from_dict(payload)
	assert_eq(
		DestinyApi.state(restored), before, "to_dict -> from_dict is field-for-field identical"
	)
	# 2. The JSON hop: what a file-backed save actually does.
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(DestinyApi.state(from_json), before, "and the JSON hop is identical too")
	# 3. The raw ledger, field by field, so a drift is named rather than hidden
	#    behind one big inequality. `sequence` is the field that used to drift.
	#    Typed as an Array because the ledger carries a LIST of history records,
	#    not a mapping: declaring it a Dictionary aborted this function on the
	#    assignment, and an aborted test reports green, so the field-by-field
	#    checks below were never actually running.
	var after: Array = DestinyApi.state(from_json)["history"]
	var expected: Array = before["history"]
	assert_eq(after.size(), expected.size(), "no record was lost")
	for index in expected.size():
		for field in ["kind", "id", "detail", "sequence"]:
			assert_eq(
				(after[index] as Dictionary).has(field),
				true,
				"record %d still carries '%s'" % [index, field]
			)
			assert_eq(
				(after[index] as Dictionary)[field],
				expected[index][field],
				"record %d field '%s' survived the hop" % [index, field]
			)
		# The specific failure this normalizes away: JSON returns every number as
		# a float, so an uncoerced `sequence` would come back as 2.0, not 2.
		assert_eq(
			typeof(after[index]["sequence"]),
			TYPE_INT,
			"record %d kept its sequence an int, not a float" % index
		)
