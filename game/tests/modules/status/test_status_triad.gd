extends TestCase

## The tier-3 triad (ADR 0925): the three statuses the closed cycle above the ladder
## ships, one combat expression per element. The catalogue's own contracts live in
## `test_status_catalogue.gd`; this file asserts the EFFECTS the ruling names — void
## drains qi, time drags the rate — and the discord table's shape.

const VOID_SEVERANCE := &"void_severance"
const CHAOS_DISCORD := &"chaos_discord"
const TIME_DRAG := &"time_drag"
const DISCORD_MEMBERS: Array[StringName] = [&"metal_sever", &"water_chill", &"wind_gust"]


func _actor(id: StringName = &"triad_hero") -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	return actor


## The three defs resolve, validate clean, and each claims the landed blow — the one
## claimer per element ADR 0105's lookup needs.
func test_the_triad_defs_resolve_and_claim_their_blows() -> void:
	var pinned := {&"void": VOID_SEVERANCE, &"chaos": CHAOS_DISCORD, &"time": TIME_DRAG}
	for element in pinned.keys():
		var id: StringName = pinned[element]
		var def := StatusApi.definition(id)
		assert_ne(def, null, "%s resolves" % String(id))
		if def == null:
			continue
		assert_eq(def.problems(), [], "%s validates clean" % String(id))
		assert_eq(def.element, element, "%s rides its element" % String(id))
		assert_eq(def.on_landed_blow, true, "%s claims the landed blow" % String(id))
		assert_eq(
			StatusApi.status_for_element(element, 1.0),
			id,
			"%s is the element's single answer" % String(element)
		)


## The discord table: three members, all resolvable, none a carrier (so a draw can
## never recurse), and the pinned trio.
func test_the_discord_table_is_three_resolvable_non_carriers() -> void:
	var def := StatusApi.definition(CHAOS_DISCORD)
	assert_ne(def, null, "the carrier resolves")
	if def == null:
		return
	assert_eq(def.mechanic(), &"discord", "it is a discord carrier")
	assert_eq(def.table(), DISCORD_MEMBERS, "the pinned table")
	for member_id in def.table():
		var member := StatusApi.definition(member_id)
		assert_ne(member, null, "%s resolves" % String(member_id))
		if member == null:
			continue
		assert_ne(member.mechanic(), &"discord", "%s is not a carrier" % String(member_id))


## VOID: the drain spends the qi pool and cuts regen — "qi severance", the effect the
## ruling names.
func test_void_severance_drains_qi_and_cuts_regen() -> void:
	var actor := _actor()
	var qi := actor.resource(&"qi")
	assert_ne(qi, null, "the fixture holds a qi pool")
	if qi == null:
		return
	var regen_before := actor.stats.derived(Stat.QI_REGEN)
	assert_eq(
		bool(StatusApi.apply(actor, VOID_SEVERANCE, 1.0).get("ok", false)),
		true,
		"the severance lands"
	)
	assert_eq(actor.has_status(VOID_SEVERANCE), true, "and is held")
	assert_eq(
		actor.stats.derived(Stat.QI_REGEN) < regen_before, true, "and the regen it cuts is cut"
	)
	var before := qi.current
	StatusApi.tick_statuses(actor, 1.0)
	assert_eq(qi.current < before, true, "and a tick drains the pool")


## TIME: the drag slows the rate the fight loop reads. The cooldown axis itself is not
## a status-modifiable stat (it is a zero-baseline rate), so the rate is what a status
## can actually move — the ruling's "rate" half.
func test_time_drag_slows_the_rate() -> void:
	var actor := _actor()
	var speed_before := actor.stats.derived(Stat.ATTACK_SPEED)
	assert_eq(bool(StatusApi.apply(actor, TIME_DRAG, 1.0).get("ok", false)), true, "the drag lands")
	assert_eq(actor.has_status(TIME_DRAG), true, "and is held")
	assert_eq(
		actor.stats.derived(Stat.ATTACK_SPEED) < speed_before,
		true,
		"and the rate it slows is slowed"
	)


## CHAOS: the carrier is a real status with its own penalty, not only a table — the
## module's own verb lands it (the paths that do not go through the spine).
func test_the_carrier_lands_and_holds_its_own_penalty() -> void:
	var actor := _actor()
	var poise_before := actor.stats.derived(Stat.POISE)
	assert_eq(
		bool(StatusApi.apply(actor, CHAOS_DISCORD, 1.0).get("ok", false)), true, "the carrier lands"
	)
	assert_eq(actor.has_status(CHAOS_DISCORD), true, "and is held")
	assert_eq(actor.stats.derived(Stat.POISE) < poise_before, true, "and its own penalty applies")
