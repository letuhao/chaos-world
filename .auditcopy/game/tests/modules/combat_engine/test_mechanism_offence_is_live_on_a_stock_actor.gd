extends TestCase

## ## The bug CLASS, not one instance: a mechanism whose offence stat is zero on a
## ## stock base-allocating actor is inert, and nothing failed when it happened.
##
## Two mechanisms were dead in exactly this shape and both were green:
##
## - **qi.** `QiDamage` prices its raw term `m_0 * ATTACK_SPIRITUAL` (ADR 0069), and
##   `ATTACK_SPIRITUAL` was `spirit * 2.0 + aptitude * 0.5`. Neither `spirit` nor
##   `aptitude` is an attribute every body in this game is born with:
##   `stoneborn.tres` — a shipped origin and the FIRST one
##   `CharacterCreationFlow.RACE_BY_ORIGIN` maps — grants `{physique: 4.0,
##   will: 1.0}` and nothing else. So the flagship mechanism proposed `0.0` and S8's
##   chip floor did all the work: a real, playable hit that reads `hit` and costs 1 HP.
##
## - **mind.** `MindDamage` prices `MENTAL_ATTACK`, which `MindProvider` derives from
##   `perception` and `mental_clarity` — the mind module's OWN base attributes, and
##   **no `RaceDef.base_attributes` in `game/data` names either.** All five races grant
##   only core's seven attributes. So `MENTAL_ATTACK` was `(0 + 0) * factor == 0.0` on
##   every actor the game can build, ADR 0171's erosion was `0.0`, and the defence
##   term it is quoted against was `0.0` on both sides of the assertion.
##
## ## Why the old suites were green
##
## Every qi fixture sets `Stat.SPIRIT: 10.0` and every mind fixture sets
## `MindStats.PERCEPTION: 20.0` / `MENTAL_CLARITY: 15.0` by hand. A pinned fixture
## proves the ARITHMETIC is right and says nothing about whether a real body can reach
## it — which is why the class needed its own assertion rather than another fixture.
##
## ## The claim this suite makes
##
## For each of the three mechanisms, the offence stat must be **non-zero on an actor
## carrying only what a race can grant** — core's seven base attributes, nothing else,
## no authored `.tres`, no hand-pinned module attribute. That is the only actor this
## game can actually build, so it is the only one the claim is about.
##
## The races are walked out of `RaceCatalog`, not restated, so a sixth race that grants
## nothing spiritual fails here by name rather than silently in play. The property
## asserted is LIVENESS (`> 0.0`), never a pinned literal: pinning the number would make
## this a balance test that fails every time someone tunes a race, and liveliness is
## what was broken.


## Every race `RaceCatalog` ships. Walked rather than restated so a race added later is
## covered by this suite the day its `.tres` lands, which is the point of asserting a
## property over the SET.
func _shipped_races() -> Array[StringName]:
	var out := RaceApi.race_ids()
	assert_eq(out.is_empty(), false, "the catalog ships at least one race")
	return out


## A stock body: a race's own authored `base_attributes` and nothing else. This is
## [code]CharacterCreationFlow._body[/code] minus the path enrolments — the allocation
## an arrival actually has before any cultivation path is touched.
func _stock_body(race_id: StringName) -> Actor:
	var actor := Actor.new(race_id, {})
	RaceApi.attach(actor)
	assert_eq(RaceApi.set_race(actor, race_id), true, "race %s is authored" % String(race_id))
	return actor


## ## qi: `ATTACK_SPIRITUAL` on every shipped race
##
## The message names the FORMULA and the consequence, because a bare "expected true,
## got false" on a four-line actor loop is the report shape this suite exists to prevent.
func test_every_race_has_a_spiritual_attack() -> void:
	for race_id in _shipped_races():
		var actor := _stock_body(race_id)
		assert_eq(
			actor.stats.derived(Stat.ATTACK_SPIRITUAL) > 0.0,
			true,
			(
				(
					"%s must be able to throw qi: ATTACK_SPIRITUAL is"
					+ " spirit*2.0 + aptitude*0.5 + will*0.6, and a race granting none of the"
					+ " three reads 0.0 -- so QiDamage's raw term is 0.0 and the S8 chip floor"
					+ " does all the work"
				)
				% String(race_id)
			)
		)


## The DEFENSIVE half of the same stat pair, asked in the same shape. `stoneborn`
## already read non-zero here (`will * 0.6`), so this is not a claim that was broken —
## it is the check that the offence half now MATCHES the defence half instead of being
## the only one of the pair that could read zero. A body that defends against qi must
## be able to deal it.
func test_every_race_has_a_spiritual_defence_to_match() -> void:
	for race_id in _shipped_races():
		var actor := _stock_body(race_id)
		assert_eq(
			actor.stats.derived(Stat.DEFENSE_SPIRITUAL) > 0.0,
			true,
			"%s must be able to resist qi (spirit*1.2 + will*0.6)" % String(race_id)
		)


## The same claim for `MENTAL_ATTACK`, on the one race that may actually take the mind
## path. Every race but `emberblood_touched` closes `mind_cultivation`, so that one is
## the only stock body a mind cultivator can be born in — and it granted only core's
## seven, so `perception` and `mental_clarity` were both `0.0` and the whole of ADR
## 0171 proposed nothing.
##
## `MindProvider` must be attached for the stat to exist at all: it is a provider
## contribution, not a core-derived one.
func test_a_mind_cultivator_can_attack_its_own_sea() -> void:
	var actor := _stock_body(&"emberblood_touched")
	assert_eq(
		RaceApi.can_take_path(actor, MindPath.PATH_ID),
		true,
		"emberblood_touched is the one race the mind path is open to"
	)
	MindCultivationApi.attach(actor)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	assert_eq(
		actor.stats.derived(MindStats.MENTAL_ATTACK) > 0.0,
		true,
		(
			"MindProvider derives MENTAL_ATTACK from perception and mental_clarity, and"
			+ " no RaceDef.base_attributes in game/data grants either -- so an unwritten"
			+ " base attribute read 0.0 and ADR 0171's erosion was 0.0 on every actor the"
			+ " game can build"
		)
	)
	assert_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE) > 0.0,
		true,
		"and the defence term ADR 0171 quotes was 0.0 on BOTH sides of its own assertion"
	)


## ## The same claim for BODY, which was never broken — and that is why it is here
##
## `ATTACK_PHYSICAL = physique * 2.0` and `stoneborn` grants `physique: 4.0`, so body
## has always been live. Including it makes the suite a property over all THREE
## mechanisms rather than a pair plus a control case, and it is the assertion that
## would fire first if `stat.gd` ever grows a fourth path whose base attribute no race
## grants. That is the shape of the bug this was: a stat nothing allocates.
func test_every_race_can_swing_the_body_path() -> void:
	for race_id in _shipped_races():
		var actor := _stock_body(race_id)
		assert_eq(
			actor.stats.derived(Stat.ATTACK_PHYSICAL) > 0.0,
			true,
			"%s must be able to swing the body path (physique*2.0)" % String(race_id)
		)


## ## The end-to-end form of the same claim: the mechanism must PROPOSE, not merely
## ## have a non-zero stat
##
## A non-zero `ATTACK_SPIRITUAL` that `QiDamage` still refuses to spend would leave
## exactly the defect this suite exists for, one layer down. So the assertion is made
## on the mechanism's own output: a stock body's qi blow must EXCEED the spine's chip
## floor, which means qi arithmetic produced the amount rather than S8 rescuing it.
##
## `chip_floor` is read from the shipped tuning rather than restated, for the reason
## `test_qi_damage_realm.gd` reads its powers off the ladder: a retune moves the test
## with the code instead of breaking it.
func test_a_stock_body_qi_blow_is_driven_by_qi_arithmetic_not_the_chip_floor() -> void:
	var actor := _stock_body(&"stoneborn")
	# The most body-denied race in the catalog: `physique: 4.0, will: 1.0` and nothing
	# else, so this is the actor the defect was measured on.
	assert_eq(actor.stats.get_base(Stat.SPIRIT), 0.0, "stoneborn is born with no spirit")
	assert_eq(actor.stats.get_base(Stat.APTITUDE), 0.0, "and no aptitude")
	ElementsApi.attach(actor)
	actor.set_affinity(ElementStats.FIRE, 10.0)
	# `CombatSpine.resolve_hit` reads its S4 mechanism off the attacker's
	# `MechanismSlot`, not off the technique, so the bind is load-bearing: without it
	# the spine asserts rather than resolving. `CombatBoot.install` is what production
	# calls; this is the one call that verb makes.
	CombatBoot.install(actor)

	var defender := Actor.new(&"stock", {Stat.PHYSIQUE: 10.0})
	defender.add_resource(ResourcePool.new(&"health", 1000.0))
	ElementsApi.attach(defender)

	var technique := TechniqueDef.new()
	technique.path = PathState.QI
	technique.magnitude = 100.0
	technique.element = ElementStats.FIRE
	technique.element_share = 0.8

	var tuning := CombatTuning.shipped()
	var outcome := CombatSpine.resolve_hit(
		actor,
		defender,
		technique,
		tuning,
		null,
		QiDamage.builder(ElementsApi.default_rules(), technique)
	)
	assert_eq(
		outcome.proposed_amount() > CombatSpine.chip_floor(outcome.base, tuning),
		true,
		(
			"a stock body's qi blow must exceed S8's chip floor, or the mechanism"
			+ " proposed nothing and the floor priced the hit"
		)
	)
	assert_eq(outcome.amount > 0.0, true, "and it spent something")
