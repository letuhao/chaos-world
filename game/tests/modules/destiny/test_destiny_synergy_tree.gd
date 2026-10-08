extends TestCase

## Fate synergy tree (ADR 0383): the graph must be acyclic, all references must
## resolve, and the unlocks/requires views must be consistent. A cycle means
## neither fate can ever be earned — a deadlock the player cannot resolve.

const OATH := &"t_oath_breaker"
const PLEDGE := &"t_blood_pledge"
const AWAKENED := &"t_awakened"
const WHISPER := &"t_whisper"
const SEAL := &"t_sealed_blood"
const CHOSEN := &"t_chosen_one"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(PLEDGE, Stat.ATTACK_PHYSICAL, 2.0),
				DestinyFixtureCatalog.flat_fate(AWAKENED, Stat.MAX_HEALTH, 25.0),
				DestinyFixtureCatalog.story_fate(WHISPER),
				DestinyFixtureCatalog.story_fate(SEAL),
			],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


# --- Acyclic validation ---------------------------------------------------


func test_the_synergy_graph_is_acyclic() -> void:
	assert_eq(FateSynergyTree.is_acyclic(), true, "no cycles in the fixture graph")


func test_a_cycle_is_detected() -> void:
	# Install a graph with a cycle: A unlocks B, B unlocks A.
	var fate_a := DestinyFixtureCatalog.story_fate(&"t_cycle_a")
	fate_a.unlocks = [&"t_cycle_b"]
	var fate_b := DestinyFixtureCatalog.story_fate(&"t_cycle_b")
	fate_b.unlocks = [&"t_cycle_a"]
	DestinyFixtureCatalog.install([fate_a, fate_b], [])
	assert_eq(FateSynergyTree.is_acyclic(), false, "a cycle is detected")
	DestinyFixtureCatalog.teardown()


# --- Reference resolution -------------------------------------------------


func test_all_unlocks_resolve_to_authored_fates() -> void:
	var errors := FateSynergyTree.validate()
	# The fixture catalog has no unlocks, so no errors.
	assert_eq(errors, [], "no dangling references in the fixture graph")


func test_a_dangling_unlock_is_reported() -> void:
	var fate := DestinyFixtureCatalog.story_fate(&"t_dangling")
	fate.unlocks = [&"t_no_such_fate"]
	DestinyFixtureCatalog.install([fate], [])
	var errors := FateSynergyTree.validate()
	assert_eq(errors.size(), 1, "one error for the dangling reference")
	assert_eq(errors[0].contains("t_no_such_fate"), true, "naming the missing id")
	DestinyFixtureCatalog.teardown()


# --- Consistency between unlocks and requires ------------------------------


func test_unlocks_and_requires_are_consistent() -> void:
	var fate_a := DestinyFixtureCatalog.story_fate(&"t_consistent_a")
	fate_a.unlocks = [&"t_consistent_b"]
	var fate_b := DestinyFixtureCatalog.story_fate(&"t_consistent_b")
	fate_b.requires = [&"t_consistent_a"]
	DestinyFixtureCatalog.install([fate_a, fate_b], [])
	var errors := FateSynergyTree.validate()
	assert_eq(errors, [], "consistent views produce no errors")
	DestinyFixtureCatalog.teardown()


func test_inconsistent_views_are_reported() -> void:
	# A unlocks B, but B.requires does not list A.
	var fate_a := DestinyFixtureCatalog.story_fate(&"t_inconsistent_a")
	fate_a.unlocks = [&"t_inconsistent_b"]
	var fate_b := DestinyFixtureCatalog.story_fate(&"t_inconsistent_b")
	fate_b.requires = []
	DestinyFixtureCatalog.install([fate_a, fate_b], [])
	var errors := FateSynergyTree.validate()
	assert_eq(errors.size(), 1, "one error for the inconsistency")
	assert_eq(errors[0].contains("t_inconsistent_b"), true, "naming the fate")
	DestinyFixtureCatalog.teardown()


# --- The gate -------------------------------------------------------------


func test_a_fate_with_unmet_requires_is_not_earnable() -> void:
	var fate := DestinyFixtureCatalog.story_fate(&"t_gated")
	fate.requires = [&"t_oath_breaker"]
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				fate,
			],
			[]
		)
	)
	var actor := _hero()
	var def := FateCatalog.instance().fate_definition(&"t_gated")
	assert_eq(
		DestinyGate.fate_earnable(DestinyApi.state(actor), def),
		false,
		"the fate is not earnable while its requirement is unmet"
	)
	DestinyApi.earn_fate(actor, OATH, "combat")
	assert_eq(
		DestinyGate.fate_earnable(DestinyApi.state(actor), def),
		true,
		"the fate is earnable once its requirement is held"
	)
	DestinyFixtureCatalog.teardown()


func test_a_fate_with_no_requires_is_always_earnable() -> void:
	var actor := _hero()
	var def := FateCatalog.instance().fate_definition(OATH)
	assert_eq(
		DestinyGate.fate_earnable(DestinyApi.state(actor), def),
		true,
		"a fate with no requirements is always earnable"
	)


func test_earn_fate_refuses_when_requires_are_unmet() -> void:
	var fate := DestinyFixtureCatalog.story_fate(&"t_gated")
	fate.requires = [&"t_oath_breaker"]
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				fate,
			],
			[]
		)
	)
	var actor := _hero()
	var ledger := DestinyApi.earn_fate(actor, &"t_gated", "combat")
	assert_eq(
		DestinyApi.has_fate(actor, &"t_gated"),
		false,
		"the fate is not earned while its requirement is unmet"
	)
	DestinyApi.earn_fate(actor, OATH, "combat")
	ledger = DestinyApi.earn_fate(actor, &"t_gated", "combat")
	assert_eq(
		DestinyApi.has_fate(actor, &"t_gated"),
		true,
		"the fate is earned once its requirement is held"
	)
	DestinyFixtureCatalog.teardown()


# --- Summary publishes synergy data ---------------------------------------


func test_summary_publishes_unlocks_and_requires() -> void:
	var fate := DestinyFixtureCatalog.flat_fate(&"t_synergy", Stat.DEFENSE_PHYSICAL, 1.0)
	fate.unlocks = [&"t_synergy_b"]
	fate.requires = [&"t_synergy_a"]
	DestinyFixtureCatalog.install([fate], [])
	var view := DestinyApi.summary(_hero())
	var fates := view["fates"] as Dictionary
	var row = fates.get(String(&"t_synergy"), null)
	if row is Dictionary:
		assert_eq((row as Dictionary)["unlocks"] as Array, ["t_synergy_b"], "unlocks published")
		assert_eq((row as Dictionary)["requires"] as Array, ["t_synergy_a"], "requires published")
	else:
		assert_eq(row is Dictionary, true, "the fate row exists")
	DestinyFixtureCatalog.teardown()


func test_summary_hides_synergy_for_hidden_unheld_fates() -> void:
	# A hidden, unheld fate does not publish its synergy edges (same rule as tags).
	var fate := DestinyFixtureCatalog.story_fate(&"t_hidden_synergy")
	fate.unlocks = [&"t_other"]
	fate.requires = [&"t_another"]
	DestinyFixtureCatalog.install([fate], [])
	var view := DestinyApi.summary(_hero())
	var fates := view["fates"] as Dictionary
	var row = fates.get(String(&"t_hidden_synergy"), null)
	if row is Dictionary:
		assert_eq((row as Dictionary)["unlocks"] as Array, [], "unlocks hidden")
		assert_eq((row as Dictionary)["requires"] as Array, [], "requires hidden")
	else:
		assert_eq(row is Dictionary, true, "the fate row exists")
	DestinyFixtureCatalog.teardown()
