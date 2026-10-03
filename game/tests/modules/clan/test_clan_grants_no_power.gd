extends TestCase

## ADR 0064's hinge, made executable: **a clan grants recognition, never power.**
##
## These assert the negative twice over, because "the stat did not move" can be reached
## two ways: the module may not add one, or it may add one that happens to be zero.
## Both are failures. So each test reads the modifier stack the projection could have
## written to AND every derived combat stat the shared pipeline computes.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"

## Every id the shared derived pipeline treats as combat value, with the value this
## suite's build produces for it. An author adding a clan stat that moved one of these
## would be adding power; joining must move none of them.
##
## These are the values for an actor carrying an AWAKE `hearthborn` at 0.5, which
## `_born()` grants: `hearthborn` publishes `max_health +5%` and `qi_regen +3%`, so the
## bare-pipeline figures of 150.0 and 1.4 are already scaled to 157.5 and 1.442. The
## bloodline is what moved them, not the clan — that is the whole point of the test, so
## the baseline is measured *with* the lineage rather than without it.
const COMBAT_STATS := {
	"max_health": 157.5,
	"attack_physical": 20.0,
	"attack_spiritual": 9.5,
	"attack_speed": 1.048,
	"defense_physical": 15.0,
	"poise": 7.5,
}

## Every id the module publishes. All bounded summaries; nothing here is on the list
## above, and `test_every_clan_stat_is_a_bounded_non_combat_summary` holds each to a
## sane range.
const MODULE_STATS := [
	ClanStats.STANDING,
	ClanStats.RANK_INDEX,
	ClanStats.BAND_INDEX,
	ClanStats.PATRONAGE_TIER,
	ClanStats.RIVAL_COUNT,
]


func setup() -> void:
	(
		ClanFixtureCatalog
		. install(
			[
				ClanFixtureCatalog.open(HOUSE),
				ClanFixtureCatalog.open(RIVAL),
			]
		)
	)


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _born() -> Actor:
	var actor := (
		Actor
		. new(
			&"member",
			{
				Stat.PHYSIQUE: 10.0,
				Stat.WILL: 5.0,
				Stat.SPIRIT: 4.0,
				Stat.AGILITY: 6.0,
				Stat.COMPREHENSION: 3.0,
				Stat.APTITUDE: 3.0,
			}
		)
	)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, 0.5)
	return actor


func _recognised(standing: int = 0) -> Actor:
	var actor := _born()
	ClanApi.join(actor, HOUSE, standing)
	return actor


func _own_modifier_count(actor: Actor) -> int:
	var count := 0
	for modifier in actor.stats._modifiers:
		if ClanState.is_own_source(modifier.source):
			count += 1
	return count


# --- The modifier stack ------------------------------------------------------


func test_joining_a_clan_adds_no_stat_modifier_at_all() -> void:
	var actor := _born()
	var total_before := actor.stats.modifier_count()
	assert_eq(_own_modifier_count(actor), 0, "the clan-source stack is empty before joining")
	ClanApi.join(actor, HOUSE, 60)
	assert_eq(_own_modifier_count(actor), 0, "and empty after joining")
	assert_eq(
		actor.stats.modifier_count(),
		total_before,
		"joining changed the total modifier stack by nothing at all"
	)
	for stat_id in MODULE_STATS:
		assert_almost_eq(
			ClanProjection.contribution(actor, stat_id),
			0.0,
			"the clan contributes nothing to '%s'" % stat_id
		)


func test_no_stat_modifier_under_the_clan_source_survives_any_verb_in_the_module() -> void:
	var actor := _recognised(0)
	ClanApi.move_standing(actor, 200)
	ClanApi.attach(actor)
	ClanProjection.strip(actor)
	ClanApi.attach(actor)
	assert_eq(_own_modifier_count(actor), 0, "nothing was written under clan: at any point")
	for modifier in actor.stats._modifiers:
		assert_eq(ClanState.is_own_source(modifier.source), false, "no modifier is ours")


func test_the_projection_touches_neither_base_attributes_nor_affinities() -> void:
	var actor := _born()
	var base := actor.stats.base_dict()
	var affinities := actor.affinities.to_dict()
	ClanApi.join(actor, HOUSE, 90)
	assert_eq(actor.stats.base_dict(), base, "joining granted no base attribute")
	assert_eq(actor.affinities.to_dict(), affinities, "and no affinity")


# --- The derived pipeline ----------------------------------------------------


func test_joining_and_rising_changes_no_derived_combat_stat() -> void:
	var actor := _recognised(0)
	for stat_id in COMBAT_STATS:
		assert_almost_eq(
			actor.stats.derived(stat_id), COMBAT_STATS[stat_id], "baseline %s" % stat_id
		)
	ClanApi.move_standing(actor, 500)
	for stat_id in COMBAT_STATS:
		assert_almost_eq(
			actor.stats.derived(stat_id),
			COMBAT_STATS[stat_id],
			"500 standing moves nothing a fight reads: %s" % stat_id
		)
	ClanApi.move_standing(actor, -500)
	for stat_id in COMBAT_STATS:
		assert_almost_eq(
			actor.stats.derived(stat_id),
			COMBAT_STATS[stat_id],
			"and neither does losing it: %s" % stat_id
		)


func test_recognition_in_one_clan_is_worth_exactly_as_much_as_recognition_in_another() -> void:
	var one := _recognised(500)
	var two := _recognised(500)
	ClanApi.join(two, RIVAL, 500)
	# Two actors, identical builds, identical standing, different houses. If a clan
	# granted anything at all these would differ.
	for stat_id in COMBAT_STATS:
		assert_almost_eq(
			one.stats.derived(stat_id), two.stats.derived(stat_id), "combat %s matches" % stat_id
		)
	assert_almost_eq(
		one.stats.derived(ClanStats.RIVAL_COUNT),
		1.0,
		"but the houses are named, and each names its own rival"
	)


# --- What the module DOES publish --------------------------------------------


func test_every_clan_stat_is_a_bounded_non_combat_summary() -> void:
	var actor := _recognised(90)
	assert_almost_eq(actor.stats.derived(ClanStats.STANDING), 90.0, "standing is readable")
	assert_almost_eq(actor.stats.derived(ClanStats.RANK_INDEX), 0.0, "the entry rank is 0")
	assert_almost_eq(actor.stats.derived(ClanStats.BAND_INDEX), 4.0, "four bands are cleared")
	assert_almost_eq(actor.stats.derived(ClanStats.RIVAL_COUNT), 1.0, "one rival house")
	assert_almost_eq(
		actor.stats.derived(ClanStats.PATRONAGE_TIER),
		0.375,
		"five published terms out of the budgeted eight"
	)
	for stat_id in MODULE_STATS:
		assert_eq(COMBAT_STATS.has(stat_id), false, "'%s' is not a combat id" % stat_id)


func test_the_provider_contributes_nothing_before_a_clan_is_joined() -> void:
	var actor := _born()
	for stat_id in MODULE_STATS:
		assert_almost_eq(actor.stats.derived(stat_id), 0.0, "'%s' is absent" % stat_id)


func test_the_provider_reads_the_attached_component_and_neither_catalog_nor_ledger() -> void:
	var actor := _recognised(60)
	# The provider reads the component, never the catalog, so an actor carrying the
	# summary is enough — the catalog singleton is not consulted at all.
	var context := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	var values := ClanProvider.new().contribute(context)
	assert_almost_eq(float(values[ClanStats.STANDING]), 60.0, "the standing is readable")
	assert_almost_eq(float(values[ClanStats.RIVAL_COUNT]), 1.0, "and the rival count")
	assert_eq(values.has(&"attack_physical"), false, "and no combat id is contributed")


func test_standing_is_a_recognition_currency_and_not_a_power_dial() -> void:
	var actor := _recognised(0)
	assert_almost_eq(actor.stats.derived(ClanStats.STANDING), 0.0, "no clan, no standing")
	ClanApi.move_standing(actor, 10000)
	assert_almost_eq(actor.stats.derived(ClanStats.STANDING), 10000.0, "the number rises")
	for stat_id in COMBAT_STATS:
		assert_almost_eq(
			actor.stats.derived(stat_id),
			COMBAT_STATS[stat_id],
			"and ten thousand standing moves nothing: %s" % stat_id
		)
