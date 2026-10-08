extends TestCase

## ADR 0925's discord, end to end through the SHIPPED producer: `CombatBoot.ctx_builder_for`
## stages the carrier's member requests as DATA, and `StatusApply.apply` draws one and
## lands it through the same pipeline as the carrier. The staging is the app's and the
## landing is the engine's, which is why the engine needs no `status` edge to impose a
## member — the table crosses the seam as request data.

const CHAOS_DISCORD := &"chaos_discord"
const CHAOS_TECHNIQUE := &"qi_chaos_edict"
const MEMBERS: Array[StringName] = [&"metal_sever", &"water_chill", &"wind_gust"]


## An attacker whose status power opens the gate, and a bare defender — the same
## fixture `test_status_application.gd` uses, because the gate is the same gate.
func _pair() -> Dictionary:
	var tuning := CombatEngineApi.tuning()
	var attacker := CombatTestKit.quiet_actor(&"discord_attacker")
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(
			StringName(tuning.status_power_prefix + "omni"), tuning.status_rate_scale, &"test"
		)
	)
	return {"attacker": attacker, "target": CombatTestKit.quiet_actor(&"discord_target")}


## The builder stages the carrier AND its members, each a full request.
func test_the_builder_stages_the_carrier_and_its_members() -> void:
	var pair := _pair()
	var technique := TechniqueCatalog.instance().definition(CHAOS_TECHNIQUE)
	assert_ne(technique, null, "the chaos technique resolves")
	if technique == null:
		return
	var tuning := CombatEngineApi.tuning()
	var builder := CombatBoot.ctx_builder_for(pair["attacker"], pair["target"], technique)
	var ctx := AttackContext.new(pair["attacker"], pair["target"], technique, tuning)
	var built: AttackContext = builder.call(ctx)
	var request: Variant = built.data_value(StatusApply.REQUEST_KEY, null)
	assert_eq(request is Dictionary, true, "the carrier request is staged")
	if request is Dictionary:
		assert_eq(
			String((request as Dictionary).get("id", "")),
			String(CHAOS_DISCORD),
			"and names the carrier"
		)
	var members: Variant = null
	if request is Dictionary:
		members = (request as Dictionary).get(StatusApply.KEY_DISCORD, null)
	assert_eq(members is Array, true, "the members are staged inside the carrier's request")
	if members is Array:
		assert_eq((members as Array).size(), MEMBERS.size(), "all three members")
		assert_eq(
			String(((members as Array)[0] as Dictionary).get("id", "")),
			String(MEMBERS[0]),
			"each with its own request"
		)


## The landing: a clean blow through the spine, then S12 imposes the carrier and draws
## exactly one member.
func test_a_landed_chaos_blow_imposes_a_drawn_member() -> void:
	var pair := _pair()
	var technique := TechniqueCatalog.instance().definition(CHAOS_TECHNIQUE)
	if technique == null:
		return
	var tuning := CombatEngineApi.tuning()
	var rng := CombatTestKit.rng(4242)
	MechanismSlot.bind(pair["attacker"], CombatTestKit.FixedMechanism.new())
	var outcome := CombatSpine.resolve_hit(
		pair["attacker"], pair["target"], technique, tuning, rng, Callable(), 0, 0
	)
	var builder := CombatBoot.ctx_builder_for(pair["attacker"], pair["target"], technique)
	var ctx := AttackContext.new(pair["attacker"], pair["target"], technique, tuning)
	var built: AttackContext = builder.call(ctx)
	var result := StatusApply.apply(
		pair["attacker"], pair["target"], tuning, built, outcome, rng, technique, 0
	)
	assert_eq(bool(result.get(StatusApply.APPLIED, false)), true, "the carrier lands")
	var target: Actor = pair["target"]
	assert_eq(target.has_status(CHAOS_DISCORD), true, "and is held")
	var drawn := 0
	for member_id in MEMBERS:
		if target.has_status(member_id):
			drawn += 1
	assert_eq(drawn, 1, "and exactly one member of the table landed")
