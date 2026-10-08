extends TestCase

## Old bytes fold in on load (D7): `normalize` stamps the current schema and
## `attach` re-derives the projection from the ledger, so the mirrors and the
## applied record exist after the load even though neither was in the bytes. And
## corrupt bytes diagnose as empty rather than aborting the load: a float where
## text belongs reads as absent through the ledger's coercion — a raw
## `String(42.0)` cast would RAISE there — and a row that cannot be read is
## dropped, never partially applied.

const MARCH := &"march_of_the_nine_provinces"


func setup() -> void:
	# The world store seam is PROCESS state: a suite that mounted the app leaves a
	# real store installed (InstitutionBoot.install wires it), and this suite's
	# cases measure the actor-side ledger with no world leg. Establish that.
	NationApi.set_world_store(null)


func test_an_old_payload_without_version_or_applied_record_folds_in_on_load() -> void:
	# Bytes as a save from before the projection recorded what it projected: no
	# version, no applied record, no history, offices held by name.
	var legacy := {
		"nation_id": "march_of_the_nine_provinces",
		"standing": 80,
		"standing_cap": 120,
		"offices": {"marshal": "mira_of_the_ford", "reeve": ""},
	}
	var actor := Actor.new(&"returning", {Stat.PHYSIQUE: 10.0})
	actor.set_module_data(NationState.MODULE_KEY, legacy)
	NationApi.attach(actor)
	var ledger := NationApi.state(actor)
	assert_eq(String(ledger["nation_id"]), "march_of_the_nine_provinces", "the polity folds in")
	assert_eq(int(ledger["standing"]), 80, "with the earned standing")
	assert_eq(
		int(ledger.get("version", 0)),
		NationState.SCHEMA_VERSION,
		"re-stamped at the current schema"
	)
	var applied: Dictionary = ledger["applied_percent"]
	assert_eq(applied.is_empty(), false, "with an applied record for the next strip to reverse")
	assert_almost_eq(
		float(applied.get("max_health", 0.0)),
		0.08,
		"re-derived from the ledger, never trusted from the bytes"
	)
	assert_almost_eq(
		NationProjection.contribution(actor, Stat.MAX_HEALTH), 0.08, "and projected onto the stack"
	)


func test_a_corrupt_payload_diagnoses_empty_instead_of_aborting_the_load() -> void:
	var corrupt := {
		"nation_id": 42.0,
		"standing": 80,
		"offices": {"marshal": 42.0, 42: "holder", "reeve": ""},
		"stances": {"not_a_pair": {"verb": "allied"}, "a|b": 7.0},
		"standoffs": {"s1": [1, 2]},
		"claims": {"river_march": {"territory_id": 7.0, "holder_id": "x"}},
	}
	var ledger := NationState.normalize(corrupt)
	assert_eq(String(ledger["nation_id"]), "", "an unreadable polity reads as none")
	assert_eq(NationState.founded(ledger), false, "so the actor lives under no nation")
	assert_eq(
		(ledger["offices"] as Dictionary).has("marshal"),
		false,
		"a seat with a corrupt holder is dropped, not coerced"
	)
	assert_eq((ledger["stances"] as Dictionary).is_empty(), true, "and no stance is taken")
	assert_eq((ledger["standoffs"] as Dictionary).is_empty(), true, "nor any standoff")
	assert_eq((ledger["claims"] as Dictionary).is_empty(), true, "nor any claim")
	assert_eq(
		InstitutionLedger.is_save_safe(ledger), true, "what remains is save-safe by construction"
	)
	# And an actor carrying those bytes attaches without aborting.
	var actor := Actor.new(&"returning", {Stat.PHYSIQUE: 10.0})
	actor.set_module_data(NationState.MODULE_KEY, corrupt)
	NationApi.attach(actor)
	assert_eq(
		NationState.founded(NationApi.state(actor)), false, "still under no nation after attach"
	)


func test_a_declared_standoff_survives_a_json_round_trip() -> void:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, MARCH, "polity_a")
	var declared := NationApi.declare_war(
		actor,
		&"court_of_the_star",
		&"river_march",
		{"mode": "contest", "transfer": "", "standing": {}}
	)
	assert_eq(bool(declared["ok"]), true, "the declaration landed")
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(round_tripped, null, "the payload is JSON-safe and round-trips")
	var reread := Actor.from_dict(round_tripped as Dictionary)
	NationApi.attach(reread)
	var before: Dictionary = NationApi.state(actor)
	var after: Dictionary = NationApi.state(reread)
	assert_eq(
		after["standoffs"], before["standoffs"], "the standoff survived with its declared prize"
	)
	assert_eq(after["applied_percent"], before["applied_percent"], "and the applied record with it")
