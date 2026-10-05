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


func test_rate_reads_come_from_the_realm_rate() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "no path, neutral")
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"spirit_sea"))
	# One bounded per-realm rate shapes every realm-scaled contribution. Reading
	# the seed's authored field here is what let this suite keep passing while the
	# provider moved off the legacy 601x curve and then off the shared ladder;
	# deriving from `RealmRate` is what makes a change land as a failure.
	var rate := RealmRate.factor(&"spirit_sea")
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
	var rate := RealmRate.factor(&"primordial_origin")
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


## The meridian network is core state on the Actor, reached by providers through
## `StatContext.meridian_network()`. These two used to hand-register it as a module
## component first, which is exactly what production never does and what hid a bug
## that made every meridian, refinement and resonance bonus silently 0 (ADR 0057).
func test_meridian_power_bonus_scales_stats_without_component_registration() -> void:
	var actor := _actor_with_module()
	assert_eq(actor.component(&"meridians"), null, "nobody registers it as a component")
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "no meridian bonus")
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	# No `mark_stats_dirty` by hand: connecting `meridians.changed` in `_init` is
	# what makes this recompute on its own.
	# lung power_bonus 0.05, so the body bonus scales by 1.05: 20 + 30 * 1.05
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 51.5, "meridian power bonus")


func test_meridian_power_bonus_scales_body_cultivation_power() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "no meridian bonus"
	)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.75, "meridian power on bcp"
	)


## The end-to-end proof the completeness audit found missing: an actor built the
## way the game builds one, where training a channel actually pays. This test
## fails against the pre-ADR-0057 code, where the provider read null.
func test_training_a_channel_pays_out_on_a_factory_built_actor() -> void:
	var actor := (
		ActorFactory
		. with_body_cultivation(
			(
				Actor
				. new(
					&"body_hero",
					{
						Stat.PHYSIQUE: 10.0,
						BodyStats.BONE_DENSITY: 10.0,
						BodyStats.MUSCLE_FIBER: 10.0,
						BodyStats.ORGAN_VITALITY: 10.0,
					}
				)
			)
		)
	)
	ItemsApi.attach(actor)
	assert_eq(actor.component(&"meridians"), null, "nobody registers it as a component")
	assert_almost_eq(actor.meridians.get_power_bonus(), 0.0, "a closed network gives no power")
	var before_bonus := actor.meridians.get_power_bonus()
	var before_attack := actor.stats.derived(BodyStats.PHYSICAL_ATTACK)
	var before_power := actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER)
	var before_physique := actor.stats.get_base(Stat.PHYSIQUE)
	# Strengthen through the public action the player uses, spending real elixirs.
	var elixir := BodyRealmSeed.for_realm(&"qi_refining").strengthening_item
	var def := ItemDef.new()
	def.id = elixir
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 8)
	# One call advances one state step, so reaching `strengthened` takes three.
	for _step in 3:
		assert_eq(BodyTraining.strengthen(actor, &"lung"), true, "lung advanced a step")
	assert_eq(actor.meridians.get_meridian(&"lung").state, &"strengthened", "lung strengthened")
	assert_almost_eq(
		ItemsApi.inventory(actor).count(elixir), 5, "each step spent exactly one elixir"
	)
	# No `mark_stats_dirty` by hand: connecting `meridians.changed` in `Actor._init`
	# is what makes these recompute.
	var after_bonus := actor.meridians.get_power_bonus()
	assert_eq(after_bonus > before_bonus, true, "the network now gives power")
	# The provider emits `unshaped_base * (1 + meridian_power)`, so a network bonus
	# scales the BONUS, not the stat. Assert the relationship, not `stat * 1.05`,
	# which would describe a mechanism the game does not have.
	var scale := (1.0 + after_bonus) / (1.0 + before_bonus)
	# Two mechanics land in one `strengthen` call and must not be conflated:
	#  - the realm MILESTONE grants physique once, which raises the CORE baseline
	#    (core attack = physique * 2), and
	#  - the meridian bonus raises the BODY bonus only.
	# Assert both, or this test "fails" against correct code.
	var seed := BodyRealmSeed.for_realm(&"qi_refining")
	var milestone := seed.integrity_maximum * BodyProgress.MILESTONE_PHYSIQUE_RATIO
	assert_eq(milestone > 0.0, true, "the milestone pays something")
	assert_almost_eq(
		actor.stats.get_base(Stat.PHYSIQUE),
		before_physique + milestone,
		"training in a realm grants its milestone physique exactly once",
		0.0001
	)
	var body_bonus_before := before_attack - before_physique * 2.0
	assert_almost_eq(
		actor.stats.derived(BodyStats.PHYSICAL_ATTACK),
		(before_physique + milestone) * 2.0 + body_bonus_before * scale,
		"attack = core(physique) + body bonus scaled by the network",
		0.0001
	)
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER),
		before_power * scale,
		"body power follows the network power bonus",
		0.0001
	)
	assert_eq(
		actor.stats.derived(BodyStats.PHYSICAL_ATTACK) > before_attack,
		true,
		"training a channel makes the actor measurably stronger"
	)


## Refinement depth and resonance each raise body stats on their own account.
## With the test above, this is the payoff the body ladder was supposed to sell -
## and it is the payoff that was silently zero.
##
## Note the shape: the provider emits `base * (1 + meridian_power)`, so a network
## bonus scales the BONUS, not the whole stat. Resonance rank 4 multiplies the
## network's power total by exactly 1.2, which moves the stat by less than 1.2x,
## and by less the larger the base grows. Asserting `stat * 1.2` would be asserting
## a different mechanism than the one that ships.
func test_refinement_and_resonance_each_raise_body_stats() -> void:
	var actor := _actor_with_module()
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	var base_power := actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER)
	var plain_bonus := actor.meridians.get_power_bonus()
	assert_eq(plain_bonus > 0.0, true, "a strengthened channel has power to give")
	# One call is one refinement step.
	assert_eq(actor.meridians.refine_meridian(&"lung", 4), true, "refined one step")
	assert_eq(actor.meridians.get_meridian(&"lung").refinement, 1, "depth is one step")
	var refined_bonus := actor.meridians.get_power_bonus()
	assert_almost_eq(refined_bonus, plain_bonus * 1.1, "one step adds 10% of the power")
	assert_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER) > base_power,
		true,
		"refinement raises body power"
	)
	# Resonance multiplies the network total by exactly 1 + 0.05 * rank.
	actor.meridians.set_resonance_rank(4)
	assert_almost_eq(actor.meridians.resonance_multiplier(), 1.2, "rank 4 is +20% on the network")
	assert_almost_eq(
		actor.meridians.get_power_bonus(), refined_bonus * 1.2, "network total lifted 20%"
	)
	var after := actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER)
	# `base_power` was read before refinement, so it is paired with `plain_bonus`.
	# Recover the unshaped base and re-apply the reshaped bonus.
	var unshaped := base_power / (1.0 + plain_bonus)
	assert_almost_eq(
		after,
		unshaped * (1.0 + refined_bonus * 1.2),
		"the stat follows the bonus, not a multiple of itself",
		0.0001
	)
	assert_eq(after > base_power, true, "refinement and resonance together raise the stat")


## The network is always present - it is core state, not an optional module
## component - so "no bonus" now means "no channel trained", which is the real
## invariant and the one that was silently inverted before ADR 0057.
func test_an_untrained_network_contributes_nothing() -> void:
	var actor := _actor_with_module()
	assert_eq(actor.component(&"meridians"), null, "still not a module component")
	assert_almost_eq(actor.meridians.get_power_bonus(), 0.0, "no channel is strengthened")
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 50.0, "no meridian bonus")
	assert_almost_eq(actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "no bonus")


func test_provider_retrievable() -> void:
	var actor := _actor_with_module()
	var provider := BodyCultivationApi.provider(actor)
	assert_eq(provider != null, true, "provider retrievable")
	assert_eq(provider is BodyProvider, true, "provider type")
