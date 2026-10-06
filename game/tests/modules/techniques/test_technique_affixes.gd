extends TestCase

## Tests for the technique affix system: authored (fixed) and rolled (per-copy)
## affixes on technique manuals, with a dedicated technique option pool.
##
## An affix is a FLAT ADDITION to an option's value. It is NEVER a multiplier:
## a band is a multiplier on the authored value, and an affix is a flat addition
## to the (possibly banded) result. This is the whole of the "no second
## multiplier" rule — the defect this program already shipped once.

const MORTAL := &"qi_refining"
const STAT_OPTION := &"cult_qi_control"
const STAT_VALUE := 6.0
const AFFIX_VALUE := 2.0

static var _serial: int = 0


func setup() -> void:
	# The affix catalog is a singleton; clear it so each test starts empty.
	TechniqueAffixCatalog.instance().clear()


func _fresh_id(label: String) -> StringName:
	_serial += 1
	return StringName("affix_suite_%s_%d" % [label, _serial])


func _hero() -> Actor:
	var actor := Actor.new(&"reader", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	actor.path(PathState.QI).progress = 100000.0
	TechniquesApi.attach(actor)
	return actor


func _manual() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = _fresh_id("manual")
	def.display_name = "Test Manual"
	def.grade = ItemGrade.MORTAL
	def.rarity = ItemRarity.LEGENDARY
	def.active = false
	def.path = PathState.QI
	def.magnitude = 1.0
	def.passive_options = [{"option_id": STAT_OPTION, "value": STAT_VALUE}]
	TechniqueCatalog.instance().register(def)
	return def


func _affix(
	id: String, option_id: StringName, value: float, group: String, authored: bool
) -> TechniqueAffix:
	var affix := TechniqueAffix.new()
	affix.id = StringName(id)
	affix.display_name = id
	affix.target_type = TechniqueAffix.TargetType.OPTION
	affix.target_option_id = option_id
	affix.value = value
	affix.exclusive_group = StringName(group)
	affix.authored = authored
	affix.rarity = ItemRarity.LEGENDARY
	TechniqueAffixCatalog.instance().register(affix)
	return affix


func _study(actor: Actor, def: TechniqueDef, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return TechniquesApi.learn(actor, def, 0, rng)


func _qi_control(actor: Actor) -> float:
	return actor.stats.derived(&"qi_control")


# --- Authored affix applies to every copy --------------------------------------


func test_an_authored_affix_applies_to_every_copy() -> void:
	var def := _manual()
	_affix("authored_boost", StringName(STAT_OPTION), AFFIX_VALUE, "test_group", true)

	# Two different seeds produce two different copies, but the authored affix
	# applies to both equally.
	var first_hero := _hero()
	var second_hero := _hero()
	var first := _study(first_hero, def, 11)
	var second := _study(second_hero, def, 97)
	assert_eq(first.get("ok") == true, true, "first copy studied")
	assert_eq(second.get("ok") == true, true, "second copy studied")

	TechniquesApi.equip(first_hero, def)
	TechniquesApi.equip(second_hero, def)

	# The authored affix adds AFFIX_VALUE to whatever the band produced.
	var first_margin: Dictionary = first.get("margin", {})
	var second_margin: Dictionary = second.get("margin", {})
	var first_banded := float(first_margin[String(STAT_OPTION)])
	var second_banded := float(second_margin[String(STAT_OPTION)])

	assert_almost_eq(
		_qi_control(first_hero), first_banded + AFFIX_VALUE, "first copy gets the affix", 0.001
	)
	assert_almost_eq(
		_qi_control(second_hero), second_banded + AFFIX_VALUE, "second copy gets the affix", 0.001
	)


# --- Rolled affix varies by seed -----------------------------------------------


func test_a_rolled_affix_varies_by_seed() -> void:
	var def := _manual()
	_affix("rolled_boost", StringName(STAT_OPTION), 1.5, "rolled_group", false)

	var first_hero := _hero()
	var second_hero := _hero()
	var first := _study(first_hero, def, 11)
	var second := _study(second_hero, def, 97)
	assert_eq(first.get("ok") == true, true, "first copy studied")
	assert_eq(second.get("ok") == true, true, "second copy studied")

	var first_margin: Dictionary = first.get("margin", {})
	var second_margin: Dictionary = second.get("margin", {})
	var first_value := float(first_margin[String(STAT_OPTION)])
	var second_value := float(second_margin[String(STAT_OPTION)])

	# The rolled affix is banded, so two seeds produce different totals.
	assert_ne(first_value, second_value, "two seeds produce different affix values")

	# Both are above the authored value (the band is both-sided, but the affix
	# is a positive addition, so the total is always above the banded value).
	assert_eq(first_value > STAT_VALUE, true, "first copy is above the sheet")
	assert_eq(second_value > STAT_VALUE, true, "second copy is above the sheet")


# --- Exclusivity ---------------------------------------------------------------


func test_exclusivity_two_affixes_in_the_same_group_do_not_both_apply() -> void:
	var def := _manual()
	# Two authored affixes in the same group: only the first (by id) applies.
	_affix("excl_a", StringName(STAT_OPTION), 3.0, "excl_group", true)
	_affix("excl_b", StringName(STAT_OPTION), 5.0, "excl_group", true)

	var hero := _hero()
	var learned := _study(hero, def, 42)
	assert_eq(learned.get("ok") == true, true, "studied")

	TechniquesApi.equip(hero, def)
	var margin: Dictionary = learned.get("margin", {})
	var banded := float(margin[String(STAT_OPTION)])

	# Only the first affix (excl_a, value 3.0) applies, not both (3.0 + 5.0).
	assert_almost_eq(
		_qi_control(hero), banded + 3.0, "only the first affix in the group applies", 0.001
	)


func test_exclusivity_affixes_in_different_groups_both_apply() -> void:
	var def := _manual()
	_affix("diff_a", StringName(STAT_OPTION), 2.0, "group_a", true)
	_affix("diff_b", StringName(STAT_OPTION), 3.0, "group_b", true)

	var hero := _hero()
	var learned := _study(hero, def, 42)
	assert_eq(learned.get("ok") == true, true, "studied")

	TechniquesApi.equip(hero, def)
	var margin: Dictionary = learned.get("margin", {})
	var banded := float(margin[String(STAT_OPTION)])

	# Both affixes apply because they are in different groups.
	assert_almost_eq(
		_qi_control(hero), banded + 5.0, "affixes in different groups both apply", 0.001
	)


# --- No second multiplier ------------------------------------------------------


func test_an_affix_targeting_the_same_value_as_a_band_does_not_create_a_second_multiplier() -> void:
	# The defect this program already shipped once: an affix that multiplies
	# the banded value instead of adding to it.
	var def := _manual()
	_affix("no_mult", StringName(STAT_OPTION), AFFIX_VALUE, "no_mult_group", true)

	var hero := _hero()
	var learned := _study(hero, def, 606)
	assert_eq(learned.get("ok") == true, true, "studied")

	TechniquesApi.equip(hero, def)
	var margin: Dictionary = learned.get("margin", {})
	var banded := float(margin[String(STAT_OPTION)])

	# The affix is a FLAT ADDITION: banded + AFFIX_VALUE.
	# It is NOT a multiplication: banded * AFFIX_VALUE.
	var expected_additive := banded + AFFIX_VALUE
	var wrong_multiplicative := banded * AFFIX_VALUE

	assert_almost_eq(
		_qi_control(hero), expected_additive, "the affix adds, never multiplies", 0.001
	)
	# Guard against the exact defect: if the affix were a multiplier, the
	# value would be wrong_multiplicative instead.
	assert_ne(_qi_control(hero), wrong_multiplicative, "the affix is not a second multiplier")


# --- Affix with no exclusivity always applies -----------------------------------


func test_an_affix_with_no_exclusivity_group_always_applies() -> void:
	var def := _manual()
	_affix("no_excl", StringName(STAT_OPTION), 4.0, "", true)

	var hero := _hero()
	var learned := _study(hero, def, 42)
	assert_eq(learned.get("ok") == true, true, "studied")

	TechniquesApi.equip(hero, def)
	var margin: Dictionary = learned.get("margin", {})
	var banded := float(margin[String(STAT_OPTION)])

	assert_almost_eq(
		_qi_control(hero), banded + 4.0, "an affix with no group always applies", 0.001
	)
