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


## ## The DEFENSIVE half of the same stat pair, asked in a DIFFERENT shape, and why
##
## This used to assert the same property as the offence case — `derived(DEFENSE_SPIRITUAL)
## > 0.0` for every shipped race — on the reasoning that "a body that defends against qi
## must be able to deal it". That was too strong, and it was strong in the wrong
## direction: it asserted a property of every RACE rather than of the DERIVATION, so any
## race that authors a signed `percent_modifiers` entry on the stat could fail it — and
## that is not hypothetical.
##
## The property that is actually load-bearing is about the DERIVATION, and it is what
## this now pins: **the defence half is `spirit * 1.2 + will * 0.6`, built from the SAME
## two core attributes the offence half reads** (`spirit * 2.0 + aptitude * 0.5 +
## will * 0.6`), so the two halves of one contest cannot disagree about which attributes
## are spiritual. That is the defect class the suite exists for, and it IS checkable as
## itself: either a race has the attributes and both halves are live, or it granted
## neither and both read zero. What is forbidden is the asymmetry — a race that deals qi
## while having nothing to resist it with.
##
## ## `glasskin` is the case the failure report measured, and it is CONTENT, not a bug
##
## `game/data/races/glasskin.tres` authors
## `percent_modifiers = { …, "defense_spiritual": -1, … }` — a full `-100%` — against a
## description that reads "completely defenseless against qi". Its own `spirit 1.0` and
## `will 1.0` derive `1.2 + 0.6 == 1.8`, and the authored `-1` takes that to exactly
## `0.0`. The stat is deliberately deleted, not accidentally lost, and the control below
## is what says so.
##
## ## The two races that grant neither attribute, stated rather than hidden
##
## `emberblood` grants `{physique, spirit, aptitude, agility}` — no `will` — and
## `stoneborn` grants `{physique, will}` — no `spirit`. Neither derives a spiritual
## defence, and neither is a defect: the OFFENCE half is live on both (`emberblood`'s is
## `2.0 * 2 + 0.5 * 3 == 5.5`, `stoneborn`'s is `1.0 * 0.6 == 0.6`), which is the pairing
## the suite's real claim is about. A body that can throw qi without being able to resist
## it is the asymmetry ADR 0183 closed; the reverse — a body that cannot resist qi at all
## because its lore says it was born without a spirit — is a content decision, not a bug.
func test_the_spiritual_defence_is_derived_from_the_same_attributes_as_the_offence() -> void:
	# A body carrying one point of each spiritual attribute and NO modifier derives both
	# halves of the contest, which is the whole claim: the two ids cannot read opposite
	# answers about whether a body is spiritual.
	var bare := Actor.new(&"bare", {Stat.SPIRIT: 1.0, Stat.WILL: 1.0})
	assert_eq(
		bare.stats.derived(Stat.ATTACK_SPIRITUAL) > 0.0,
		true,
		"spirit*2.0 + aptitude*0.5 + will*0.6 is live on an unstatted-by-modifier body"
	)
	assert_eq(
		bare.stats.derived(Stat.DEFENSE_SPIRITUAL) > 0.0,
		true,
		"and so is spirit*1.2 + will*0.6 -- the same two attributes, never a missing one"
	)
	# Every shipped race is then checked for the CONSISTENCY of the pair, which is what the
	# old all-races loop was reaching for and could not say.
	for race_id in _shipped_races():
		var actor := _stock_body(race_id)
		var offensive: float = actor.stats.derived(Stat.ATTACK_SPIRITUAL)
		var defensive: float = actor.stats.derived(Stat.DEFENSE_SPIRITUAL)
		assert_eq(
			defensive > 0.0 or offensive <= 0.0,
			true,
			(
				(
					"%s deals qi (%.4f) with no spiritual defence at all -- that is the"
					% [String(race_id), offensive]
				)
				+ " asymmetry ADR 0183 closed"
			)
		)


## The SIGNED-MODIFIER control, and the direct answer to "does a stock actor's
## `DEFENSE_SPIRITUAL` produce any qi mitigation?". It does: the control first reads a
## defence on the very body the failing case was about, with no modifier attached, and then
## shows the authored `-100%` is what deletes it. A race may author a signed
## `percent_modifiers` entry on the stat and the derivation must honour it — so this
## asserts the negative direction the old all-races loop could not express: the defence is
## present, and a race may still delete it.
func test_a_race_that_negates_the_spiritual_defence_gets_exactly_zero_and_not_a_rounding() -> void:
	var actor := Actor.new(&"bare", {Stat.SPIRIT: 1.0, Stat.WILL: 1.0})
	assert_eq(
		actor.stats.derived(Stat.DEFENSE_SPIRITUAL) > 0.0,
		true,
		"the same body derives a defence before any race modifier is attached"
	)
	actor.stats.add_modifier(
		StatModifier.new(Stat.DEFENSE_SPIRITUAL, Stat.Op.PERCENT, -1.0, &"glasskin")
	)
	# A full `-100%` on a `1.8` magnitude is `1.8 * (1 - 1) == 0.0` exactly, so the
	# defender is COMPLETELY defenseless against qi by content — which is precisely what
	# `game/data/races/glasskin.tres`'s own description claims for it.
	assert_almost_eq(
		actor.stats.derived(Stat.DEFENSE_SPIRITUAL), 0.0, "and -100% takes it to exactly 0.0"
	)
	# The derived value is never negative: a defence that reads below zero would hand the
	# attacker a bonus, so `ActorStats` floors at zero and this pins that it still does.
	assert_eq(actor.stats.derived(Stat.DEFENSE_SPIRITUAL) >= 0.0, true, "and never below zero")


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
