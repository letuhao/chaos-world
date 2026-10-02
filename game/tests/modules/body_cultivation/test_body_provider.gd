extends TestCase

## ADR 0012/0026/0028: the body provider. Core-owned stats are contributed
## ADDITIVELY (a provider value replaces the core baseline for the id it emits,
## so an absolute body value for `move_speed` erased `100 + agility * 2`).
## Module-owned stats have no core baseline and are defined outright. P/C/F/T
## come from the shared power ladder, not from the actor's realm seed.


## physique 10, and 10 of each body attribute. Core baselines for this actor:
## attack = physique * 2 = 20, defense = physique * 1.5 = 15,
## move speed = 100 + agility * 2 = 100, poise = physique * 0.5 + will * 0.5 = 5.
func _actor_with_module() -> Actor:
	var actor := (
		Actor
		. new(
			&"body_cultivator",
			{
				Stat.PHYSIQUE: 10.0,
				BodyStats.BONE_DENSITY: 10.0,
				BodyStats.MUSCLE_FIBER: 10.0,
				BodyStats.ORGAN_VITALITY: 10.0,
			}
		)
	)
	BodyCultivationApi.attach(actor)
	return actor


## The core baseline alone: an actor with no body path and no body provider.
func _core_only(agility: float = 0.0, will: float = 0.0) -> Actor:
	return Actor.new(&"plain", {Stat.PHYSIQUE: 10.0, Stat.AGILITY: agility, Stat.WILL: will})


# --- The regression this file exists for ------------------------------------


## Attaching the body path must never shrink a core stat. Before the additive
## fix, MOVE_SPEED collapsed from 100 to 0.5 — a 200x drop the moment any
## cultivator existed.
func test_attaching_the_body_path_never_reduces_core_stats() -> void:
	var plain := _core_only()
	var trained := _actor_with_module()
	for stat_id in [
		BodyStats.PHYSICAL_ATTACK,
		BodyStats.PHYSICAL_DEFENSE,
		BodyStats.MOVE_SPEED,
		BodyStats.POISE,
	]:
		var core := plain.stats.derived(stat_id)
		var with_body := trained.stats.derived(stat_id)
		assert_eq(with_body >= core, true, "%s not reduced by the body path" % String(stat_id))


func test_move_speed_keeps_the_core_baseline() -> void:
	var actor := _actor_with_module()
	# core 100 + body bonus (muscle_fiber 10 * 0.5 = 5) = 105
	assert_almost_eq(actor.stats.derived(BodyStats.MOVE_SPEED), 105.0, "core baseline preserved")


func test_move_speed_scales_with_agility_before_body_bonus() -> void:
	var actor := (
		Actor
		. new(
			&"agile_cultivator",
			{
				Stat.PHYSIQUE: 10.0,
				Stat.AGILITY: 20.0,
				BodyStats.BONE_DENSITY: 10.0,
				BodyStats.MUSCLE_FIBER: 10.0,
				BodyStats.ORGAN_VITALITY: 10.0,
			}
		)
	)
	BodyCultivationApi.attach(actor)
	# core 100 + agility 20 * 2 = 140, plus the body bonus of 5
	assert_almost_eq(actor.stats.derived(BodyStats.MOVE_SPEED), 145.0, "agility still counts")


# --- Composition ------------------------------------------------------------


func test_physical_attack_adds_to_core() -> void:
	var actor := _actor_with_module()
	# core 20 + (muscle_fiber 10 * 2 + bone_density 10 * 1) = 20 + 30
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "physical attack")


func test_physical_defense_adds_to_core() -> void:
	var actor := _actor_with_module()
	# core 15 + (bone_density 10 * 1.5 + organ_vitality 10 * 1) = 15 + 25
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_DEFENSE), 40.0, "physical defense")


func test_poise_adds_to_core() -> void:
	var actor := _actor_with_module()
	# core (physique 10 * 0.5) = 5, plus (bone_density 10 * 0.8 + physique 10 * 0.5) = 13
	assert_almost_eq(actor.stats.derived(BodyStats.POISE), 18.0, "poise")


# --- Module-owned stats have no core baseline -------------------------------


func test_carry_capacity_is_body_owned() -> void:
	var actor := _actor_with_module()
	# bone_density 10 * 10 + muscle_fiber 10 * 5 = 150
	assert_almost_eq(actor.stats.derived(BodyStats.CARRY_CAPACITY), 150.0, "carry capacity")


func test_regeneration_is_body_owned() -> void:
	var actor := _actor_with_module()
	# organ_vitality 10 * 0.3 = 3
	assert_almost_eq(actor.stats.derived(BodyStats.REGENERATION), 3.0, "regeneration")


func test_body_cultivation_power_is_body_owned() -> void:
	var actor := _actor_with_module()
	# (10 + 10 + 10) * 0.5 = 15
	assert_almost_eq(actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "power")


# --- Integrity, profile, and meridians --------------------------------------


func test_integrity_affects_stats() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "full integrity")
	actor.change_resource(BodyStats.BODY_INTEGRITY, -50.0)
	# integrity_ratio = 0.5, factor = 0.5 + 0.5 * 0.5 = 0.75, so the body bonus
	# halves to 22.5 and the core baseline of 20 is untouched
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 42.5, "half integrity")


func test_profile_reads_come_from_the_realm_profile() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "no path, neutral")
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"spirit_sea"))
	# One bounded per-realm rate shapes every realm-scaled contribution. Reading
	# the seed's authored field here is what let this suite keep passing while the
	# provider moved off the legacy 601x curve and then off the shared ladder;
	# deriving from `BodyRealmProfile` is what makes a change land as a failure.
	var rate := BodyRealmProfile.factor(&"spirit_sea")
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 20.0 + 30.0 * rate, "attack")
	assert_almost_eq(actor.stats.derived(BodyStats.MOVE_SPEED), 100.0 + 5.0 * rate, "speed")
	assert_almost_eq(actor.stats.derived(BodyStats.REGENERATION), 3.0 * rate, "regeneration")
	assert_almost_eq(actor.stats.derived(BodyStats.CARRY_CAPACITY), 150.0 * rate, "carry capacity")


## The provider must be scaled by the rate and nothing else. Its realm MAGNITUDES
## belong to `RealmScaling` (core, for the shared stats it contributes additively
## on top of) and to `integrity_maximum` (the reservoir), so anything larger than
## the rate here would count the same realm twice.
func test_no_stat_is_scaled_by_anything_but_the_bounded_rate() -> void:
	var actor := _actor_with_module()
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"primordial_origin"))
	var rate := BodyRealmProfile.factor(&"primordial_origin")
	var plain := _actor_with_module()
	for stat_id in [
		BodyStats.PHYSICAL_ATTACK,
		BodyStats.PHYSICAL_DEFENSE,
		BodyStats.MOVE_SPEED,
		BodyStats.POISE,
		BodyStats.CARRY_CAPACITY,
		BodyStats.REGENERATION,
		BodyStats.BODY_CULTIVATION_POWER,
	]:
		# Module-owned stats have no core baseline, so the ratio is exactly the
		# rate. The core-owned ones carry an additive core baseline, so compare
		# the body BONUS, which is what the provider actually shapes.
		var shaped := actor.stats.derived(stat_id)
		var plain_value := plain.stats.derived(stat_id)
		assert_almost_eq(
			(shaped - _core_baseline(stat_id)) / (plain_value - _core_baseline(stat_id)),
			rate,
			"%s is exactly the rate" % String(stat_id),
			0.0001
		)


## The core baseline the body provider contributes ON TOP of, for the ids it does
## not own. Derived from the core actor, so it cannot go stale against core.
func _core_baseline(stat_id: StringName) -> float:
	var plain := Actor.new(&"plain", {Stat.PHYSIQUE: 10.0})
	return plain.stats.derived(stat_id)


func test_meridian_power_bonus_scales_stats() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "no meridian bonus")
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	# lung power_bonus 0.05, so the body bonus scales by 1.05: 20 + 30 * 1.05
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 51.5, "meridian power bonus")


func test_meridian_power_bonus_scales_body_cultivation_power() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "no meridian bonus"
	)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.75, "meridian power on bcp"
	)


func test_no_meridian_component_gives_no_bonus() -> void:
	var actor := _actor_with_module()
	# No meridians component attached — should default to no bonus
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "no meridian component")


func test_provider_retrievable() -> void:
	var actor := _actor_with_module()
	var provider := BodyCultivationApi.provider(actor)
	assert_eq(provider != null, true, "provider retrievable")
	assert_eq(provider is BodyProvider, true, "provider type")
