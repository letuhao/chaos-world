extends TestCase

## DEF-0207: mastery REACHES a passive, through ADR 0055's `power` column and
## through nothing else.
##
## **Every case here reaches its rung through `TechniquesApi.raise_mastery`, which no
## production caller holds** — `activate` refuses a passive, so this file proves what
## a rung DOES to a passive and could never prove that a player can GET one. That
## half is DEF-0304 and it lives in `test_technique_passive_worn_mastery.gd`, which
## reaches the same multiplier through `settle_upkeep` (ADR 0247). Read the two
## together: this file is the effect, that one is the input.
##
## The decision, with the evidence that made it:
##
## - **`power` scales the stat channel.** `POWER_STEP = 1.15` compounding is the
##   one multiplier of the three that means "this technique is stronger", and a
##   passive is exactly a technique that is stronger. A rung-4 `cult_bone_density`
##   of 4.0 contributes 6.996.
## - **`qi_cost` and `cooldown` do NOT scale anything.** They discount what an
##   ACTIVATION pays, and a passive has no cost block: every shipped `.tres` and
##   every authored passive pins `qi_cost == stamina_cost == cooldown == 0.0`, and
##   `TechniqueCasting.activate` refuses one with `not_active`. A discount applied
##   to a zero is a number that reads as a benefit and pays nothing.
## - **The resource-capacity channel does NOT scale.** `RealmScaling` already
##   MULTs `MAX_QI` and `MAX_STAMINA` by the realm's own `power` (1.0x to 551.46x)
##   and `QiTraining.synchronize` re-seals the qi pool from the next realm's
##   authored `dantian_capacity`. Scaling a passive's capacity contribution is a
##   fourth multiplier on a number that already has three, and the least authored
##   of them.
## - **Bounds are not breached.** The scale is at most `1.15^4 = 1.749`, and the
##   option's own `bounds.max` is 9999.0 for every `cult_*` option, so no scaled
##   value leaves the window `OptionCatalog.clamp_to_bounds` defines.
## - **Stacking is still impossible.** The contribution is rebuilt
##   remove-all-then-re-add under one `technique:<id>` tag (ADR 0054), and rung
##   scaling is a pure function of the rung, so a rebuild any number of times
##   lands on the same value.

const MORTAL := &"qi_refining"

## `cult_qi_control` targets a STAT. `core_max_qi` targets `Stat.MAX_QI` through
## the RESOURCE channel. One fixture carrying both makes the split the subject of
## the test rather than a claim about it.
const STAT_OPTION := &"cult_qi_control"
const RESOURCE_OPTION := &"core_max_qi"
const STAT_VALUE := 4.0
const RESOURCE_VALUE := 25.0


func _hero() -> Actor:
	var actor := Actor.new(&"adept", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	# ADR 0140: learning charges the qi path's `progress`, so a hero that cannot pay
	# is refused `insufficient_progress`. A fixture, not a balance claim; the price
	# itself is asserted in `test_technique_study_cost.gd`.
	actor.path(PathState.QI).progress = 100000.0
	TechniquesApi.attach(actor)
	return actor


func _passive() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"test_passive_mastery"
	def.display_name = "Mastery Manual"
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	def.passive_options = [
		{"option_id": STAT_OPTION, "value": STAT_VALUE},
		{"option_id": RESOURCE_OPTION, "value": RESOURCE_VALUE},
	]
	TechniqueCatalog.instance().register(def)
	return def


## The value the stat channel contributes right now, read off the ACTOR rather
## than off the entry. Reading the entry would test the projection against
## itself; reading the derived stat is what a player experiences.
func _qi_control(actor: Actor) -> float:
	# `&"qi_control"` rather than `StringName("qi_control")`: Godot 4 has no
	# StringName constructor, and the call fails at runtime with an error naming
	# neither this line nor the technique.
	return actor.stats.derived(&"qi_control")


# --- A rung increase IS observable ---------------------------------------------


func test_raising_a_passives_rung_scales_its_stat_channel_on_the_actor() -> void:
	var actor := _hero()
	var def := _passive()
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)

	assert_almost_eq(_qi_control(actor), STAT_VALUE, "rung 0 is the authored value", 0.0001)

	# The ONE verb that raises a rung, reached exactly as casting reaches it.
	var raised := TechniquesApi.raise_mastery(actor, def.id, 4)
	assert_eq(bool(raised.get("ok")), true, "the rung moved")
	assert_eq(int(TechniquesApi.codex(actor).row(def.id).get("rung", 0)), 4, "and persisted")

	# Immediately, without waiting for the next rebuild: `raise_mastery` commits
	# and rebuilds, so the contribution is re-derived at the new rung.
	assert_almost_eq(
		_qi_control(actor),
		STAT_VALUE * 1.749,
		"rung 4 is ADR 0055's 1.749 power on the authored value",
		0.001
	)


func test_the_power_multiplier_is_adrs_own_compounding_at_every_rung() -> void:
	# Each rung checked against `TechniqueScales.multipliers_at`, so the passive
	# path cannot drift from the table an active technique casts against.
	for rung in 5:
		var actor := _hero()
		var def := _passive()
		TechniquesApi.codex(actor).learn(def.id)
		TechniquesApi.equip(actor, def)
		TechniquesApi.raise_mastery(actor, def.id, rung)
		var power := float(TechniqueScales.multipliers_at(rung, def.mastery_rungs)["power"])
		assert_almost_eq(
			_qi_control(actor), STAT_VALUE * power, "rung %d is the ladder's power" % rung, 0.001
		)


# --- What deliberately does NOT scale, and why ----------------------------------


func test_the_resource_capacity_channel_does_not_scale_with_the_rung() -> void:
	var actor := _hero()
	var def := _passive()
	var floor_max_qi := actor.stats.derived(Stat.MAX_QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)

	var at_rung_zero := actor.stats.derived(Stat.MAX_QI)
	assert_almost_eq(
		at_rung_zero, floor_max_qi + RESOURCE_VALUE, "rung 0 adds the authored capacity", 0.0001
	)

	TechniquesApi.raise_mastery(actor, def.id, 4)
	# THE case DEF-0207 is closed by: the capacity channel is byte-identical at
	# rung 4 and at rung 0, while the stat channel above moved by 1.749. The
	# reason is the file header's — `RealmScaling` already MULTs MAX_QI by the
	# realm's own 1.0x-551.46x power, and `QiTraining.synchronize` re-seals the
	# pool from the next realm's authored dantian capacity. A fourth multiplier
	# here is the least authored one of the four.
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI),
		at_rung_zero,
		"rung 4 leaves the capacity channel exactly where rung 0 left it",
		0.0001
	)
	# And the stat channel in the SAME rebuild did move, so this is a rule about
	# one channel rather than a passive that ignores its rung.
	assert_almost_eq(
		_qi_control(actor), STAT_VALUE * 1.749, "the stat channel scaled in the same rebuild", 0.001
	)


func test_the_passive_still_has_no_cost_block_for_a_discount_to_reach() -> void:
	# `qi_cost` (0.94^n) and `cooldown` (0.96^n) are REFUSED for a passive, and
	# this is why: there is nothing for them to discount. Asserting the absence
	# is what makes "mastery does not touch the cost block" a fact about the
	# content rather than an assumption about the code.
	var def := _passive()
	assert_eq(def.is_passive(), true, "it is a passive")
	assert_almost_eq(def.qi_cost, 0.0, "which has no qi cost to discount", 0.0001)
	assert_almost_eq(def.stamina_cost, 0.0, "and no stamina cost", 0.0001)
	assert_almost_eq(def.cooldown, 0.0, "and no cooldown", 0.0001)
	# The casting table refuses it, so the discount columns are unreachable from
	# a passive by construction rather than by a branch nobody took.
	TechniquesApi.codex(_hero()).learn(def.id)
	assert_eq(
		TechniqueScales.multipliers_at(4, def.mastery_rungs)["qi_cost"] < 1.0,
		true,
		"the column exists"
	)
	assert_eq(def.qi_cost > 0.0, false, "and there is nothing for it to act on")


# --- Bounded, and stable across rebuilds ----------------------------------------


func test_a_scaled_value_stays_inside_the_options_own_bounds() -> void:
	# The unbounded-stacking objection to scaling a passive, answered by
	# measurement: `POWER_STEP^4 = 1.749`, and the catalog's own `bounds` are the
	# window `OptionCatalog.clamp_to_bounds` enforces at authoring time.
	var record := OptionCatalog.instance().option_record(STAT_OPTION)
	var bounds: Dictionary = record.get("bounds", {})
	var ceiling := float(bounds.get("max", 0.0))
	assert_eq(ceiling > 0.0, true, "the option declares a ceiling")
	for rung in 5:
		var actor := _hero()
		var def := _passive()
		TechniquesApi.codex(actor).learn(def.id)
		TechniquesApi.equip(actor, def)
		TechniquesApi.raise_mastery(actor, def.id, rung)
		assert_eq(
			_qi_control(actor) <= ceiling,
			true,
			(
				"rung %d (%.3f) stays inside the option's ceiling of %.1f"
				% [rung, _qi_control(actor), ceiling]
			)
		)
	# The multiplier itself is the bound, and it is ADR 0055's published figure.
	assert_almost_eq(
		TechniqueScales.multipliers_at(4)["power"], 1.749, "rung 4 power is 1.749", 0.001
	)
	assert_eq(
		float(TechniqueScales.multipliers_at(4)["power"]) < 2.0,
		true,
		"so a passive never doubles, let alone compounds without limit"
	)


func test_scaling_does_not_accumulate_across_rebuilds() -> void:
	# The stacking hazard ADR 0054 names. Rung scaling is a pure function of the
	# rung, and the contribution is remove-all-then-re-add under one tag, so
	# rebuilding must land on the same value every time — the same property
	# `test_rebuild_twice_does_not_accumulate_drift` pins at rung 0.
	var actor := _hero()
	var def := _passive()
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	TechniquesApi.raise_mastery(actor, def.id, 4)
	var baseline := _qi_control(actor)
	var baseline_modifiers := actor.stats.modifier_count()
	for pass_index in 4:
		TechniquesApi.rebuild(actor)
		assert_almost_eq(
			_qi_control(actor),
			baseline,
			"rebuild %d returns to the rung's value" % pass_index,
			0.001
		)
		assert_eq(
			actor.stats.modifier_count(),
			baseline_modifiers,
			"and rebuild %d adds no modifier" % pass_index
		)


func test_a_def_with_a_narrower_ladder_cannot_reach_a_rung_it_did_not_author() -> void:
	# `mastery_rungs` is authorable DOWNWARD and the multipliers are constants, so
	# the clamp reads the def's own count. A def lowered to two rungs must never
	# carry rung 4's power, which is the one way passive scaling could silently
	# exceed ADR 0055's bounds.
	var actor := _hero()
	var def := _passive()
	def.mastery_rungs = 2
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	TechniquesApi.raise_mastery(actor, def.id, 4)
	var capped := float(TechniqueScales.multipliers_at(2, 2)["power"])
	assert_almost_eq(
		_qi_control(actor), STAT_VALUE * capped, "the rung-2 ladder's power, not rung 4's", 0.001
	)
	assert_eq(capped < 1.749, true, "and that is below the full ladder's figure")


# --- The read model tells the same story as the actor ---------------------------


func test_the_inspect_view_reports_the_scaled_value_the_actor_really_has() -> void:
	# A panel renders `inspect().effects`, so the projection and the modifier
	# stack have to agree or the codex quotes a number the stat does not carry.
	var actor := _hero()
	var def := _passive()
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	TechniquesApi.raise_mastery(actor, def.id, 4)
	var view := TechniquesApi.inspect(actor, def)["effects"] as Array
	var stat_row: Dictionary = {}
	for row in view:
		if String((row as Dictionary)["option_id"]) == String(STAT_OPTION):
			stat_row = row
	assert_eq(stat_row.is_empty(), false, "the stat option is reported")
	assert_almost_eq(
		float(stat_row["value"]),
		_qi_control(actor),
		"the projected value is the value on the actor",
		0.001
	)
