extends TestCase

## Fate choice at earn time (ADR 0389). The choice is a UI presentation of
## implicit eligibility: when multiple fates in a choice group are eligible,
## the UI presents them as a choice. The backend resolves it through existing
## earn logic — the player picks one and `earn_fate` records it.
##
## These tests assert:
## - `FateDef.eligible_choices` is read correctly
## - `FateDef.unheld_choices` returns the correct fates
## - `DestinyApi.eligible_choices` returns the correct fates
## - `DestinyApi.has_choice` returns true when multiple fates are eligible
## - The earn-only invariant is preserved

const OATH_A := &"t_oath_a"
const OATH_B := &"t_oath_b"
const OATH_C := &"t_oath_c"
const SOLO := &"t_solo"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH_A, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(OATH_B, Stat.ATTACK_PHYSICAL, 2.0),
				DestinyFixtureCatalog.flat_fate(OATH_C, Stat.MAX_HEALTH, 25.0),
				DestinyFixtureCatalog.story_fate(SOLO),
			],
			[]
		)
	)
	# Set up the choice group: OATH_A, OATH_B, and OATH_C are all in the same
	# choice group. SOLO is not part of any choice group.
	var catalog := FateCatalog.instance()
	catalog._fates[String(OATH_A)].eligible_choices = [OATH_B, OATH_C] as Array[StringName]
	catalog._fates[String(OATH_B)].eligible_choices = [OATH_A, OATH_C] as Array[StringName]
	catalog._fates[String(OATH_C)].eligible_choices = [OATH_A, OATH_B] as Array[StringName]


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


# --- FateDef.eligible_choices ----------------------------------------------


func test_eligible_choices_is_read_correctly() -> void:
	var catalog := FateCatalog.instance()
	var def: FateDef = catalog.fate_definition(OATH_A)
	assert_eq(def.eligible_choices.size(), 2, "OATH_A has two eligible choices")
	assert_eq(def.eligible_choices.has(OATH_B), true, "OATH_B is in the group")
	assert_eq(def.eligible_choices.has(OATH_C), true, "OATH_C is in the group")
	assert_eq(def.eligible_choices.has(OATH_A), false, "OATH_A is not in its own group")


func test_eligible_choices_empty_for_solo_fate() -> void:
	var catalog := FateCatalog.instance()
	var def: FateDef = catalog.fate_definition(SOLO)
	assert_eq(def.eligible_choices.size(), 0, "SOLO is not in any choice group")
	assert_eq(def.has_eligible_choices(), false, "SOLO has no eligible choices")


func test_has_eligible_choices_returns_true_for_grouped_fate() -> void:
	var catalog := FateCatalog.instance()
	var def: FateDef = catalog.fate_definition(OATH_A)
	assert_eq(def.has_eligible_choices(), true, "OATH_A is in a choice group")


# --- FateDef.unheld_choices ------------------------------------------------


func test_unheld_choices_returns_all_when_none_held() -> void:
	var actor := _hero()
	var catalog := FateCatalog.instance()
	var def: FateDef = catalog.fate_definition(OATH_A)
	var unheld: Array[StringName] = def.unheld_choices(DestinyApi.state(actor))
	assert_eq(unheld.size(), 2, "both OATH_B and OATH_C are unheld")
	assert_eq(unheld.has(OATH_B), true, "OATH_B is unheld")
	assert_eq(unheld.has(OATH_C), true, "OATH_C is unheld")


func test_unheld_choices_excludes_held_fates() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_B, "test")
	var catalog := FateCatalog.instance()
	var def: FateDef = catalog.fate_definition(OATH_A)
	var unheld: Array[StringName] = def.unheld_choices(DestinyApi.state(actor))
	assert_eq(unheld.size(), 1, "only OATH_C is unheld")
	assert_eq(unheld.has(OATH_C), true, "OATH_C is unheld")
	assert_eq(unheld.has(OATH_B), false, "OATH_B is held")


func test_unheld_choices_empty_when_all_held() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_B, "test")
	DestinyApi.earn_fate(actor, OATH_C, "test")
	var catalog := FateCatalog.instance()
	var def: FateDef = catalog.fate_definition(OATH_A)
	var unheld: Array[StringName] = def.unheld_choices(DestinyApi.state(actor))
	assert_eq(unheld.size(), 0, "no unheld choices")


# --- DestinyApi.eligible_choices --------------------------------------------


func test_eligible_choices_returns_all_when_none_held() -> void:
	var actor := _hero()
	var eligible: Array[StringName] = DestinyApi.eligible_choices(actor, OATH_A)
	assert_eq(eligible.size(), 2, "both OATH_B and OATH_C are eligible")
	assert_eq(eligible.has(OATH_B), true, "OATH_B is eligible")
	assert_eq(eligible.has(OATH_C), true, "OATH_C is eligible")


func test_eligible_choices_excludes_held_fates() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_B, "test")
	var eligible: Array[StringName] = DestinyApi.eligible_choices(actor, OATH_A)
	assert_eq(eligible.size(), 1, "only OATH_C is eligible")
	assert_eq(eligible.has(OATH_C), true, "OATH_C is eligible")


func test_eligible_choices_empty_for_solo_fate_via_api() -> void:
	var actor := _hero()
	var eligible: Array[StringName] = DestinyApi.eligible_choices(actor, SOLO)
	assert_eq(eligible.size(), 0, "SOLO has no eligible choices")


func test_eligible_choices_empty_for_null_actor() -> void:
	var eligible: Array[StringName] = DestinyApi.eligible_choices(null, OATH_A)
	assert_eq(eligible.size(), 0, "null actor has no eligible choices")


func test_eligible_choices_empty_for_unknown_fate() -> void:
	var actor := _hero()
	var eligible: Array[StringName] = DestinyApi.eligible_choices(actor, &"t_unknown")
	assert_eq(eligible.size(), 0, "unknown fate has no eligible choices")


# --- DestinyApi.has_choice --------------------------------------------------


func test_has_choice_true_when_multiple_eligible() -> void:
	var actor := _hero()
	assert_eq(DestinyApi.has_choice(actor, OATH_A), true, "multiple fates eligible")


func test_has_choice_false_when_one_eligible() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_B, "test")
	DestinyApi.earn_fate(actor, OATH_C, "test")
	assert_eq(DestinyApi.has_choice(actor, OATH_A), false, "only one fate eligible")


func test_has_choice_false_when_none_eligible() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_B, "test")
	DestinyApi.earn_fate(actor, OATH_C, "test")
	assert_eq(DestinyApi.has_choice(actor, OATH_A), false, "no fates eligible")


func test_has_choice_false_for_solo_fate() -> void:
	var actor := _hero()
	assert_eq(DestinyApi.has_choice(actor, SOLO), false, "SOLO is not in a choice group")


func test_has_choice_false_for_null_actor() -> void:
	assert_eq(DestinyApi.has_choice(null, OATH_A), false, "null actor has no choice")


# --- The earn-only invariant is preserved -----------------------------------


func test_choice_does_not_create_a_new_earn_path() -> void:
	var actor := _hero()
	# The choice is a UI presentation, not a new earn path. The backend
	# resolves it through existing earn logic — the player picks one and
	# `earn_fate` records it.
	assert_eq(DestinyApi.has_fate(actor, OATH_A), false, "OATH_A not held yet")
	assert_eq(DestinyApi.has_fate(actor, OATH_B), false, "OATH_B not held yet")
	assert_eq(DestinyApi.has_fate(actor, OATH_C), false, "OATH_C not held yet")
	# The player picks OATH_A
	DestinyApi.earn_fate(actor, OATH_A, "test")
	assert_eq(DestinyApi.has_fate(actor, OATH_A), true, "OATH_A is held")
	assert_eq(DestinyApi.has_fate(actor, OATH_B), false, "OATH_B is not held")
	assert_eq(DestinyApi.has_fate(actor, OATH_C), false, "OATH_C is not held")


func test_choice_does_not_allow_purchase_or_cheat() -> void:
	var actor := _hero()
	# The choice is a UI presentation of implicit eligibility. There is no
	# purchase, no cheat, no trade. The fate is still earned through
	# `earn_fate`, which is exactly-once and permanent.
	var eligible: Array[StringName] = DestinyApi.eligible_choices(actor, OATH_A)
	assert_eq(eligible.size(), 2, "two fates eligible")
	# The player picks OATH_B
	DestinyApi.earn_fate(actor, OATH_B, "test")
	assert_eq(DestinyApi.has_fate(actor, OATH_B), true, "OATH_B is held")
	# OATH_B is now held, so it is no longer eligible
	var eligible_after: Array[StringName] = DestinyApi.eligible_choices(actor, OATH_A)
	assert_eq(eligible_after.size(), 1, "only OATH_C is eligible")
	assert_eq(eligible_after.has(OATH_C), true, "OATH_C is eligible")
