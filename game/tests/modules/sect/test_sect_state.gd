extends TestCase

## The claim ledger is a versioned plain dictionary under `actor.module_data`
## (ADR 0027) and it is the single source of truth for what a member is owed.
##
## These assert the shape of that ledger, that an unreadable payload is diagnosed
## as empty rather than partially applied, that a claim naming content the build no
## longer ships is dropped rather than persisted, and that every inner key is a
## `String` — because `Actor.to_dict` converts only the OUTER `module_data` key, so
## a `StringName` in here reaches the save untouched and breaks every round trip
## (ADR 0084).

const MODULE_KEY := SectState.MODULE_KEY
const SECT := &"t_house"
const KNOWN := {"t_member": true, "t_steward": true, "t_reader": true}
const SKELETON := [
	"applied_standing",
	"doctrine",
	"fit",
	"founder_id",
	"granted_percent",
	"history",
	"institution",
	"obligation",
	"position",
	"roster",
	"standing",
	"standing_cap",
	"succession",
	"treasury",
	"version",
]


func _claim(
	institution: String = "t_house",
	position: String = "t_steward",
	standing: int = 40,
	known: Dictionary = KNOWN
) -> Dictionary:
	return (
		SectState
		. normalize(
			{
				"institution": institution,
				"position": position,
				"standing": standing,
				"standing_cap": 100,
				"doctrine": "t_house_doctrine",
				"obligation": {"t_dues_outer": 2},
				"fit": {"t_house_doctrine": 40},
				"applied_standing": standing,
				"granted_percent": {"insight_gain": 0.04},
				"history": [{"kind": "join", "id": "t_house", "detail": "", "sequence": 1}],
			},
			known
		)
	)


# --- The shape of the ledger -------------------------------------------------


func test_an_empty_payload_normalizes_to_the_full_versioned_skeleton() -> void:
	for payload in [{}, {"version": SectState.SCHEMA_VERSION}, {"unrelated": 4}]:
		var ledger := SectState.normalize(payload)
		assert_eq(int(ledger["version"]), SectState.SCHEMA_VERSION, "always versioned")
		assert_eq(String(ledger["institution"]), "", "no sect in %s" % [payload])
		assert_eq(String(ledger["position"]), "", "no office in %s" % [payload])
		assert_eq(int(ledger["standing"]), 0, "no standing in %s" % [payload])
		assert_eq(int(ledger["standing_cap"]), 100, "the default cap in %s" % [payload])
		assert_eq(ledger["obligation"] as Dictionary, {}, "no obligation in %s" % [payload])
		assert_eq(ledger["fit"] as Dictionary, {}, "no fit in %s" % [payload])
		assert_eq(ledger["roster"] as Dictionary, {}, "no roster in %s" % [payload])
		assert_eq(ledger["treasury"] as Dictionary, {}, "no treasury in %s" % [payload])
		assert_eq(ledger["succession"] as Dictionary, {}, "no walk in %s" % [payload])
		assert_eq(ledger[SectState.FOUNDER_KEY] as String, "", "no founder in %s" % [payload])
		assert_eq(int(ledger["applied_standing"]), 0, "nothing applied in %s" % [payload])
		assert_eq(ledger["granted_percent"] as Dictionary, {}, "nothing granted in %s" % [payload])
		assert_eq(ledger["history"] as Array, [], "no history in %s" % [payload])
		var keys: Array = ledger.keys()
		keys.sort()
		assert_eq(keys, SKELETON, "the skeleton is the whole shape, not a subset")
	assert_eq(SectState.empty(), SectState.normalize({}), "empty() is that same ledger")


func test_an_unreadable_payload_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	# Half a ledger is worse than none: a partial one silently changes what the
	# player is owed, so a payload that cannot be read is refused as a whole.
	for payload in [
		{"version": 1, "institution": 12.5, "standing": "many"},
		{"version": 1, "obligation": "no", "fit": 3, "history": "no"},
		{"version": 1, "standing_cap": -4},
		{"version": 1, "granted_percent": ["not", "a", "map"]},
		# The founder is a CLAIM field, not a neighbour of one: it names who the
		# sect belongs to, so an object under that key is not a ledger.
		{"version": 1, "institution": "t_house", "founder_id": {"actor": "nobody"}},
	]:
		var ledger := SectState.normalize(payload as Dictionary)
		assert_eq(String(ledger["institution"]), "", "rejected institution in %s" % [payload])
		assert_eq(ledger["obligation"] as Dictionary, {}, "rejected obligation in %s" % [payload])
		assert_eq(ledger["fit"] as Dictionary, {}, "rejected fit in %s" % [payload])
		assert_eq(ledger["history"] as Array, [], "rejected history in %s" % [payload])
		assert_eq(ledger["granted_percent"] as Dictionary, {}, "rejected grant in %s" % [payload])
		assert_eq(ledger[SectState.FOUNDER_KEY] as String, "", "rejected founder in %s" % [payload])
	# A payload that is not a dictionary at all cannot be typed into the signature, so
	# the rule is pinned through `Actor`: core hands the module whatever the save
	# held under the key, and a non-dictionary there must read as the empty ledger
	# rather than as a half-applied claim.
	for corrupt in ["not a ledger", 7, [1, 2, 3]]:
		var actor := Actor.new(&"corrupt")
		actor.module_data[MODULE_KEY] = corrupt
		var ledger := SectState.normalize(actor.get_module_data(MODULE_KEY))
		assert_eq(String(ledger["institution"]), "", "a non-dictionary payload %s" % [corrupt])
		assert_eq(ledger["obligation"] as Dictionary, {}, "reads as empty, not partial")
	# A cap that cannot be computed is repaired rather than persisted, because a
	# claim whose cap is zero reports a zero ratio and reads as a member nobody
	# respects (ADR 0084).
	assert_eq(int(SectState.normalize({"standing_cap": 0})["standing_cap"]), 1, "zero is repaired")
	assert_eq(
		int(SectState.normalize({"standing_cap": -9})["standing_cap"]), 1, "and so is a negative"
	)


func test_an_entry_naming_a_position_this_build_does_not_ship_is_dropped() -> void:
	# Standing survives even when the seat does not: a member who earned standing
	# earned it, and losing the authored office must not silently strip what the
	# sect gave them for holding it.
	var ledger := _claim("t_house", "t_retired_seat", 60)
	assert_eq(String(ledger["position"]), "", "an unshipped office is dropped")
	assert_eq(int(ledger["standing"]), 60, "but the standing it earned survives")
	# An empty filter is an unanswered question, not a denial, so a catalog that
	# knows nothing yet keeps everything it is handed.
	var unfiltered := _claim("t_house", "t_retired_seat", 60, {})
	assert_eq(String(unfiltered["position"]), "t_retired_seat", "an empty filter accepts anything")
	# A known office is kept, which is what makes the filter a filter.
	assert_eq(String(_claim()["position"]), "t_steward", "a shipped office is kept")


func test_standing_clamps_into_its_own_authored_cap_and_never_below_zero() -> void:
	assert_eq(int(_claim("t_house", "t_steward", 500)["standing"]), 100, "over the cap clamps")
	assert_eq(int(_claim("t_house", "t_steward", -40)["standing"]), 0, "and never goes negative")
	assert_eq(
		SectState.standing({"standing": 900, "standing_cap": 120}), 120, "the read clamps too"
	)
	assert_eq(SectState.standing({}), 0, "an empty ledger holds no standing")


func test_every_inner_key_is_a_string_so_the_payload_survives_a_json_hop() -> void:
	# `Actor.to_dict` converts the OUTER `module_data` key with `String(key)` and
	# nothing else, so a `StringName` key in here reaches the save untouched and no
	# checker in this repo can see it (ADR 0084).
	var ledger := _claim()
	for container in ["obligation", "fit", "granted_percent"]:
		for key in (ledger[container] as Dictionary).keys():
			assert_eq(typeof(key), TYPE_STRING, "%s inner key is a String" % container)
	# And the whole payload round trips as JSON. `JSON` renders every number as a
	# float, so the claim's own fields compare exactly while a history record's
	# `sequence` does not — which is why the trail is read field by field below
	# rather than compared as a whole.
	var parsed = JSON.parse_string(JSON.stringify(ledger))
	assert_ne(parsed, null, "the ledger is JSON-safe")
	var restored := SectState.normalize(parsed as Dictionary, KNOWN)
	for field in ["version", "institution", "position", "standing", "standing_cap", "doctrine"]:
		assert_eq(restored[field], ledger[field], "'%s' survives the hop" % field)
	assert_eq(restored["obligation"], ledger["obligation"], "and the obligation")
	assert_eq(restored["fit"], ledger["fit"], "and the fit")
	assert_eq(restored["granted_percent"], ledger["granted_percent"], "and the grant record")
	assert_eq(
		String((restored["history"] as Array)[0]["kind"]),
		"join",
		"and the trail came back with its content intact"
	)
	for container in ["obligation", "fit", "granted_percent"]:
		for key in (restored[container] as Dictionary).keys():
			assert_eq(typeof(key), TYPE_STRING, "%s key is a String after the hop" % container)
	assert_eq((restored["fit"] as Dictionary).get("t_house_doctrine", 0), 40, "and the fit value")


func test_the_position_and_standing_are_two_facts_and_neither_is_written_from_the_other() -> void:
	# ADR 0064's two-part split, carried forward by ADR 0083 and made mechanical
	# here: `normalize` reads each field from its own key and never derives one
	# from the other, so a claim can hold a high office on thin standing and thick
	# standing in no office at all.
	var high_office := _claim("t_house", "t_steward", 1)
	assert_eq(String(high_office["position"]), "t_steward", "a high office on thin standing")
	assert_eq(int(high_office["standing"]), 1, "with the thin standing it actually has")
	var thick := _claim("t_house", "", 100)
	assert_eq(String(thick["position"]), "", "thick standing in no office at all")
	assert_eq(int(thick["standing"]), 100, "with the standing intact")
	assert_eq(thick["institution"], "t_house", "and still sworn to something")


func test_is_affiliated_and_institution_answer_only_for_a_claimed_sect() -> void:
	assert_eq(SectState.is_affiliated(SectState.empty()), false, "an empty ledger is nobody")
	assert_eq(SectState.institution(SectState.empty()), &"", "and names no sect")
	assert_eq(SectState.is_affiliated(_claim()), true, "a claimed sect is a membership")
	assert_eq(SectState.institution(_claim()), SECT, "and reads back by id")


func test_the_stat_and_trait_mirror_ids_are_namespaced_under_sect() -> void:
	assert_eq(SectState.source_for(SECT), &"sect:t_house", "the stat source is namespaced")
	assert_eq(SectState.trait_for(SECT), &"sect:t_house", "the trait mirror matches it")
	assert_eq(SectState.is_own_source(&"sect:t_house"), true, "the module claims its own")
	assert_eq(SectState.is_own_source(&"set:ironhide_vigil"), false, "and claims nothing else")
	assert_eq(SectState.is_own_source(SECT), false, "an unprefixed id is not ours")
	assert_eq(SectState.is_own_source(&""), false, "nor is the empty source")
	assert_eq(SectState.is_own_trait(&"sect:t_house"), true, "and the same on the mirror")
	assert_eq(SectState.is_own_trait(&"t_house"), false, "an unprefixed trait is not ours")
	assert_eq(SectState.SOURCE_PREFIX, "sect:", "one prefix names both carriers")


func test_the_history_trail_is_bounded_so_a_save_cannot_grow_without_limit() -> void:
	var history: Array = []
	for index in SectState.HISTORY_LIMIT + 20:
		history.append({"kind": "standing", "id": "t_house", "detail": "1", "sequence": index})
	var ledger := SectState.normalize({"version": 1, "history": history})
	assert_eq((ledger["history"] as Array).size(), SectState.HISTORY_LIMIT, "the trail is capped")
	assert_eq(SectState.HISTORY_LIMIT <= 256, true, "and the cap is small enough to stay cheap")
	# Records are copied, not aliased: a later mutation of the source array cannot
	# reach back into the ledger.
	history[0]["id"] = "tampered"
	assert_eq(String((ledger["history"] as Array)[0]["id"]), "t_house", "records are deep-copied")


func test_the_module_key_is_the_one_core_persists_generic_module_data_under() -> void:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0})
	actor.set_module_data(MODULE_KEY, SectState.empty())
	var payload: Dictionary = actor.to_dict()
	assert_eq(
		(payload["module_data"] as Dictionary).has(String(MODULE_KEY)), true, "it is module data"
	)
	assert_eq(SectApi.MODULE_KEY, SectState.MODULE_KEY, "the facade persists under the same key")
