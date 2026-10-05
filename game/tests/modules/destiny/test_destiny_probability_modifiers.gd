extends TestCase

## Tests for the probability-modifier half of the destiny/fortune system
## (ADR 0274). Fate and destiny tendencies modify probabilities — rates, not
## magnitudes — and are read through the facade as derived values.

const OATH := &"t_oath_breaker"
const CHOSEN := &"t_chosen_instrument"
const INSTRUMENT_FATE := &"t_heaven_s_chosen_instrument"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.ATTACK_PHYSICAL, 7.0),
				_fate_with_probability(INSTRUMENT_FATE, &"loot_bonus", 0.5, &"evasion", -0.03),
			],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
				_destiny_with_probability(
					&"t_the_chosen_instrument", &"breakthrough_chance", 0.03, &"crit_chance", -0.02
				),
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


static func _fate_with_probability(
	fate_id: StringName,
	plus_id: StringName,
	plus_value: float,
	minus_id: StringName,
	minus_value: float
) -> FateDef:
	var def := FateDef.new()
	def.id = fate_id
	def.display_name = String(fate_id)
	def.description = "A fixture fate with probability modifiers."
	def.category = &"fixture"
	def.tier = 1
	def.visibility = FateDef.REVEALED
	var mods := {}
	mods[plus_id] = plus_value
	mods[minus_id] = minus_value
	def.probability_modifiers = mods
	return def


static func _destiny_with_probability(
	destiny_id: StringName,
	plus_id: StringName,
	plus_value: float,
	minus_id: StringName,
	minus_value: float
) -> DestinyDef:
	var def := DestinyDef.new()
	def.id = destiny_id
	def.display_name = String(destiny_id)
	def.description = "A fixture destiny with probability modifiers."
	def.bearing = "You are bound to %s." % destiny_id
	def.tier = 1
	def.visibility = DestinyDef.REVEALED
	var mods := {}
	mods[plus_id] = plus_value
	mods[minus_id] = minus_value
	def.probability_modifiers = mods
	return def


# --- Probability modifiers are earned, not stored ---------------------------


func test_probability_modifier_is_derived_not_stored() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, INSTRUMENT_FATE)
	assert_eq(DestinyApi.probability_modifier(actor, &"loot_bonus"), 0.5, "loot_bonus")
	assert_eq(DestinyApi.probability_modifier(actor, &"evasion"), -0.03, "evasion")
	# Nothing was written to the stat stack: probability modifiers are
	# derived, never stored (ADR 0274).
	assert_eq(DestinyProjection.modifier_count(actor), 0, "modifier_count")


func test_probability_modifier_defaults_to_zero() -> void:
	var actor := _hero()
	assert_eq(DestinyApi.probability_modifier(actor, &"crit_chance"), 0.0, "crit_chance")
	assert_eq(DestinyApi.probability_modifiers(actor).size(), 0, "size")


func test_probability_modifier_null_actor_is_zero() -> void:
	assert_eq(DestinyApi.probability_modifier(null, &"crit_chance"), 0.0, "crit_chance")
	assert_eq(DestinyApi.probability_modifiers(null).size(), 0, "size")


# --- Yin-yang: every positive carries a negative counterpart --------------


func test_yin_yang_pair_is_authored_together() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, INSTRUMENT_FATE)
	assert_eq(DestinyApi.probability_modifier(actor, &"loot_bonus"), 0.5, "loot_bonus")
	assert_eq(DestinyApi.probability_modifier(actor, &"evasion"), -0.03, "evasion")
	assert_eq(DestinyApi.probability_modifier(actor, &"crit_chance"), 0.0, "crit_chance")


# --- Destiny tendencies modify probabilities while held --------------------


func test_destiny_probability_modifier() -> void:
	var actor := _hero()
	DestinyApi.earn_destiny(actor, &"t_the_chosen_instrument")
	assert_eq(
		DestinyApi.probability_modifier(actor, &"breakthrough_chance"), 0.03, "breakthrough_chance"
	)
	assert_eq(DestinyApi.probability_modifier(actor, &"crit_chance"), -0.02, "crit_chance")


# --- Multiple sources sum ---------------------------------------------------


func test_probability_modifiers_sum_across_fates_and_destinies() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, INSTRUMENT_FATE)
	DestinyApi.earn_destiny(actor, &"t_the_chosen_instrument")
	assert_eq(DestinyApi.probability_modifier(actor, &"loot_bonus"), 0.5, "loot_bonus")
	assert_eq(DestinyApi.probability_modifier(actor, &"crit_chance"), -0.02, "crit_chance")
	assert_eq(
		DestinyApi.probability_modifier(actor, &"breakthrough_chance"), 0.03, "breakthrough_chance"
	)


func test_probability_modifiers_dictionary_lists_all() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, INSTRUMENT_FATE)
	DestinyApi.earn_destiny(actor, &"t_the_chosen_instrument")
	var all: Dictionary = DestinyApi.probability_modifiers(actor)
	assert_eq(all.size(), 4, "size")
	assert_eq(float(all.get("loot_bonus", 0.0)), 0.5, "loot_bonus")
	assert_eq(float(all.get("evasion", 0.0)), -0.03, "evasion")
	assert_eq(float(all.get("breakthrough_chance", 0.0)), 0.03, "breakthrough_chance")
	assert_eq(float(all.get("crit_chance", 0.0)), -0.02, "crit_chance")


# --- Earn-only invariant -----------------------------------------------------


func test_probability_modifier_is_never_removed() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, INSTRUMENT_FATE)
	assert_eq(DestinyApi.probability_modifier(actor, &"loot_bonus"), 0.5, "loot_bonus")
	# Earning the same fate again does not double the modifier.
	DestinyApi.earn_fate(actor, INSTRUMENT_FATE)
	assert_eq(DestinyApi.probability_modifier(actor, &"loot_bonus"), 0.5, "loot_bonus")


# --- Distinct from stat modifiers -------------------------------------------


func test_probability_modifier_is_distinct_from_stat_modifier() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH)
	assert_eq(
		DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL)["flat"], 7.0, "attack_physical"
	)
	assert_eq(DestinyApi.probability_modifier(actor, &"crit_chance"), 0.0, "crit_chance")
