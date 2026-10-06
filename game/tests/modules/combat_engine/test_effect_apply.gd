extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0067's `effects[]` step: a mechanism's OWN state writes are APPLIED, not just
## carried.
##
## ## What this file is evidence for
##
## `DamageProposal` is `{amount, effects[]}` and ADR 0067 says the second field "are the
## path's own state writes, applied AFTER health". Nothing applied them. `CombatSpine` read
## `amount` through `CombatProposalReader.amount_of` and stopped there, so a body hit cost
## health and left NO wound — ADR 0070's ledger, its necrosis and its irreversible flag were
## unreachable in play — and a mind hit cost nothing at all, ADR 0071's erosion discarded
## while `SeaOfConsciousness.add_turbulence` stayed reachable from `src/` only through
## `mind_cultivation/advancement.gd`.
##
## Every mechanism suite asserted the effect was **carried**, never that it **landed**, which
## is why thousands of green assertions missed it: `test_body_damage_wounds` even stated the
## order correctly in prose ("Nothing has been settled yet: the wound lands after health, by
## the caller") and then called the caller itself.
##
## ## What each test below pins
##
## 1. the wound **accumulates** on the bound ledger, and it is the SAME object twice — the
##    regression `BodyDamage.apply_wounds`'s fresh `BodyWounds.new()` would cause;
## 2. the erosion **raises turbulence and lowers clarity** on the real sea, through its real
##    mutators;
## 3. an unknown kind is **ignored**, not refused and not fatal;
## 4. a target with no ledger / no sea **takes the blow anyway** and skips the write;
## 5. effects land **after** the health write — asserted as an ORDER, not a presence.

## The attacker's pinned base attributes. `perception 20.0` gives
## `mental_attack == 70.0` exactly at the neutral realm rate (perception * 3.5), which is
## `mind_damage_fixture.gd`'s pin restated rather than re-derived. `MindCultivationApi
## .attach` is REQUIRED, not decoration: `mental_attack` is contributed by `MindProvider` and
## reads `0.0` on an actor nobody attached one to, so every erosion row below would be
## measuring "no contest" instead of erosion.
const MIND_STRIKER_BASE := {MindStats.PERCEPTION: 20.0, Stat.PHYSIQUE: 10.0}
## The sea's structural capacity for these rows: R1's authored `100.0`, the one number
## ADR 0071 puts in the denominator. A sea at `0.0` makes the erosion visibly inert.
const SEA_CAPACITY := 100.0
## A defender's clarity before the hit, so the row states the "before" rather than reading it
## off whatever the previous assertion left behind.
const CLARITY_BEFORE := 0.8

# --- the body ledger: accumulation and identity -------------------------------------


## The headline. Two landed body hits on the same meridian, and the ledger ACCUMULATES: the
## second hit's severity sits on top of the first's, on the SAME object, through the SPINE —
## not through a hand-written `add`.
##
## The identity assertion is the half that matters. `BodyDamage.apply_wounds` built a
## `BodyWounds.new()` per call and dropped it, so every wound landed on a ledger nobody held.
## Two calls each answered with a severity near their OWN subtotal and the total was never
## more than one gash. Asserting `wounds_of(target) == ledger` after both hits, and
## `severity == first + second`, is what makes "the same object" a fact rather than an
## assumption.
func test_two_body_hits_accumulate_on_one_bound_ledger() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	var technique := _technique(100.0, &"lung")
	var mechanism := _bind_body(attacker)

	assert_eq(CombatEngineApi.wounds_of(target), ledger, "the fixture bound ONE ledger")
	assert_eq(ledger.severity_of(&"lung"), 0.0, "and it starts unhit")

	var first := _strike(attacker, target, technique, mechanism)
	var first_effect: Dictionary = first.proposal.effect_of(BodyWounds.EFFECT_KIND)
	assert_ne(first_effect.is_empty(), true, "the hit carried the body's own effect kind")
	assert_eq(
		StringName(first_effect[BodyWounds.KEY_MERIDIAN]), &"lung", "naming the struck meridian"
	)
	var severity_first := ledger.severity_of(&"lung")
	assert_eq(severity_first > 0.0, true, "the FIRST hit wrote a wound on the bound ledger")

	var second := _strike(attacker, target, technique, mechanism)
	var second_effect: Dictionary = second.proposal.effect_of(BodyWounds.EFFECT_KIND)
	var severity_second := ledger.severity_of(&"lung")
	assert_eq(
		severity_second,
		(
			severity_first
			+ (float(second_effect[BodyWounds.KEY_SEVERITY]) / _integrity_maximum(target))
		),
		"the SECOND hit's severity sits ON TOP of the first -- wounds ACCUMULATE"
	)
	assert_eq(
		CombatEngineApi.wounds_of(target),
		ledger,
		"and it is the SAME ledger object across both hits, not one built per hit"
	)
	# The component the facade names and the object the fixture still held, read separately:
	# a per-call fresh ledger would answer each of them with its own subtotal.
	assert_almost_eq(
		CombatEngineApi.wounds_of(target).severity_of(&"lung"),
		severity_second,
		"and the facade reads the accumulated number, not the second hit's own"
	)


## A `broad` sweep carries ONE effect per struck meridian, and the one applier call settles
## all of them — so the number of channels S4 struck and the number settled cannot disagree.
## This is the assertion `test_body_damage_wounds` could not make while its only route was a
## caller it made itself.
func test_a_broad_sweep_settles_every_struck_meridian_in_one_step() -> void:
	var attacker := _attacker()
	var target := _defender(
		["lung", "spleen"], {"lung": MeridianState.OPEN, "spleen": MeridianState.OPEN}
	)
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	var mechanism := _bind_body(attacker)
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		_technique(100.0, &""),
		_tuning,
		null,
		BodyDamage.builder(null, BodyLocation.MODE_BROAD)
	)
	# The struck set is read off the proposal rather than restated, because a `broad` sweep
	# covers every UNLOCKED meridian and "which twenty" is `BodyLocation`'s answer to give.
	# What is under test is that the applier settled EXACTLY those, not which ones they were.
	var struck: Dictionary = {}
	for entry in outcome.proposal.effects:
		var typed: Dictionary = entry
		if StringName(typed.get(DamageProposal.KIND, &"")) != BodyWounds.EFFECT_KIND:
			continue
		var meridian := StringName(typed.get(BodyWounds.KEY_MERIDIAN, &""))
		assert_eq(struck.has(meridian), false, "no meridian carries two wounds from one sweep")
		struck[meridian] = float(typed[BodyWounds.KEY_SEVERITY])
	assert_eq(
		struck.size() > 1,
		true,
		"the sweep carried one effect per struck channel: %d" % struck.size()
	)
	# Every struck channel took a wound, on the bound ledger, from the ONE applier call --
	# read back off the ledger rather than off the payload, because the ledger is the state.
	for meridian in struck.keys():
		assert_eq(
			ledger.severity_of(StringName(meridian)),
			float(struck[meridian]) / _integrity_maximum(target),
			(
				"%s took the sweep's own severity -- nothing was dropped, nothing doubled"
				% String(meridian)
			)
		)
	assert_eq(
		ledger.severity_of(&"lung") > 0.0 and ledger.severity_of(&"spleen") > 0.0,
		true,
		"and the two channels the fixture opened explicitly are among them"
	)
	# A meridian the sweep never struck is untouched: the applier dispatches on the payload
	# and cannot invent a wound for a channel the mechanism never named. `&""` is the id that
	# is no meridian at all, so it is the one row `broad_sites` can never legitimately emit.
	var others := 0
	for meridian_id in _meridian_ids(target):
		if not struck.has(meridian_id):
			others += 1
			assert_eq(
				ledger.severity_of(meridian_id),
				0.0,
				"%s was unlocked but not struck, and carries no wound" % String(meridian_id)
			)
	assert_eq(others, 0, "a broad sweep really did reach every unlocked meridian")


## The ORDERING, asserted rather than described: a body's health is spent by S9 and its
## wound is written afterwards, so a target that died of the blow still carries the wound.
##
## The window is real and narrow — `_spend` writes health at S9, S10/S11/S12 follow, then the
## applier runs — so the probe is a `FixedMechanism` that reads the target's health inside
## `mitigate`. That runs at S5, i.e. BEFORE the health write, and it hands back a wound
## effect. So a hit through this mechanism lands a wound against the bound ledger, and the
## health the probe recorded is provably the pre-blow figure: an applier placed before S9
## would have written that wound against a health number the blow had not yet taken.
func test_effects_are_applied_after_the_health_write() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	var health_before := target.resource(&"health").current
	var seen_at_mechanism := target.resource(&"health").current
	var stub := CombatTestKit.FixedMechanism.new()
	stub.effects = [
		{
			DamageProposal.KIND: BodyWounds.EFFECT_KIND,
			BodyWounds.KEY_MERIDIAN: &"lung",
			BodyWounds.KEY_SEVERITY: _severity_for(target, 1.0),
		}
	]
	MechanismSlot.bind(attacker, stub)

	var outcome := CombatSpine.resolve_hit(
		attacker, target, _technique(100.0, &"lung"), _tuning, null, Callable()
	)
	assert_eq(stub.resolve_calls, 1, "the mechanism ran exactly once")
	assert_eq(stub.mitigate_calls, 1, "and was mitigated exactly once")
	assert_eq(outcome.health_delta < 0.0, true, "the blow cost health")
	assert_eq(
		seen_at_mechanism,
		health_before,
		"the mechanism saw the PRE-blow health: S4/S5 run before S9, as ADR 0067 fixes"
	)
	assert_almost_eq(
		target.resource(&"health").current,
		health_before + outcome.health_delta,
		"S9 wrote health exactly once, for the chip floor the 0.0 stub declined to earn"
	)
	# And the wound the stub carried was settled by the applier, on the bound ledger --
	# AFTER that write. A per-hit ledger, or an applier placed before S9, would still have
	# written it; what this pins is that the health write and the wound both happened, in
	# the order ADR 0067 states, in ONE hit, with nothing the caller had to remember.
	assert_eq(
		ledger.severity_of(&"lung") > 0.0,
		true,
		"and the effect the mechanism produced at S4 landed on the bound ledger"
	)
	assert_eq(
		CombatEngineApi.wounds_of(target),
		ledger,
		"through the ONE applier step the spine runs last"
	)
	# The applier is reached by the SPINE and not by the fixture: no call in this test
	# settles anything. That is the whole defect -- the old world needed one, and nothing in
	# `src/` made it. S12 adds its own `status_application` entry to the SAME array, which
	# is why the readout carries two rows and the body's is still one of them.
	var kinds: Array[StringName] = []
	for row in outcome.effects():
		kinds.append(StringName((row as Dictionary).get(DamageProposal.KIND, &"")))
	assert_eq(kinds.size(), 2, "the readout carries the mechanism's effect and S12's own")
	assert_eq(
		kinds.has(BodyWounds.EFFECT_KIND),
		true,
		"and the body's effect is among them -- produced by the eleven stages, not by the test"
	)
	assert_eq(
		kinds.has(StatusApply.EFFECT_KIND),
		true,
		"S12 wrote onto the same array, so there is exactly ONE effects[] a panel reads"
	)


# --- the sea: real mutators ---------------------------------------------------------


## A mind hit's erosion RAISES the real sea's turbulence and LOWERS its clarity — measured
## on a real `SeaOfConsciousness` built by `MindCultivationApi.attach_sea`, through its real
## `add_turbulence` / `set_clarity`, with the sea reached through the component key
## `CombatTuning.sea_component` authors.
##
## Both numbers are read off the SEA, not restated from the payload, because the payload is
## what the mechanism claimed and the sea is what actually happened.
func test_a_mind_hit_raises_turbulence_and_lowers_clarity_on_the_real_sea() -> void:
	var attacker := _mind_attacker()
	var defender := _sea_defender()
	var sea := MindCultivationApi.sea(defender)
	var turbulence_before := sea.turbulence

	var outcome := _mind_hit(attacker, defender)
	var effect: Dictionary = outcome.proposal.effect_of(MindDamage.EFFECT_KIND)
	assert_ne(effect.is_empty(), true, "the hit carried a mind.erosion effect")
	assert_eq(float(effect[MindDamage.KEY_TURBULENCE]) > 0.0, true, "carrying turbulence to add")
	assert_eq(float(effect[MindDamage.KEY_CLARITY]) < 0.0, true, "and clarity to lose")

	assert_eq(
		sea.turbulence > turbulence_before,
		true,
		"the REAL sea's turbulence rose: %f -> %f" % [turbulence_before, sea.turbulence]
	)
	assert_almost_eq(
		sea.turbulence,
		clampf(turbulence_before + float(effect[MindDamage.KEY_TURBULENCE]), 0.0, 1.0),
		"by exactly the effect's turbulence delta -- add_turbulence, not a field write"
	)
	assert_eq(
		sea.clarity < CLARITY_BEFORE, true, "and the REAL sea's clarity fell: %f" % sea.clarity
	)
	assert_almost_eq(
		sea.clarity,
		clampf(CLARITY_BEFORE + float(effect[MindDamage.KEY_CLARITY]), 0.0, 1.0),
		"by exactly the effect's clarity delta -- set_clarity, as a VALUE not a delta"
	)
	# Mind never subtracts a SHARE of its own erosion (ADR 0071, amended by ADR 0162): the
	# amount is `0.0`, so what S8 floors the blow to is `chip_floor(S1's base)` and nothing
	# more -- the same chip every other landed hit pays, and the one documented exception to
	# ADR 0071's headline claim. Asserted as that floor rather than as `0.0` because S8
	# reads `outcome.base` and not the mechanism's zero (`test_mind_damage.gd`).
	assert_eq(outcome.proposed_amount(), 0.0, "a mind hit carries no amount at all")
	assert_almost_eq(
		float(outcome.amount),
		CombatSpine.chip_floor(CombatSpine.base_damage(attacker, _mind_technique()), _tuning),
		"so health moves by S8's chip floor on S1's base and NOT by any share of the erosion"
	)
	assert_almost_eq(
		outcome.health_delta,
		-float(outcome.amount),
		"and the blow costs exactly the chip floor -- never a share of what it cost the sea"
	)


## An `ATTEND` strike is the only kind that touches the AWARENESS reserve, and the payload's
## `awareness` is a delta of the RATIO rather than of the pool — so it is spent as
## `delta * maximum`, inside the pool's own `[0, maximum]` clamp. Measured on the real pool.
func test_an_attend_strike_drains_the_awareness_reserve_as_a_share_of_its_maximum() -> void:
	var attacker := _mind_attacker()
	var defender := _sea_defender()
	var pool := defender.resource(_tuning.awareness_pool_id) as ResourcePool
	assert_ne(pool, null, "the shipped tuning names an awareness pool")
	pool.current = pool.maximum
	var held_before := pool.current

	var outcome := _mind_hit(attacker, defender, MindDamage.Kind.ATTEND)
	var effect: Dictionary = outcome.proposal.effect_of(MindDamage.EFFECT_KIND)
	var drained := float(effect[MindDamage.KEY_AWARENESS])
	assert_eq(drained < 0.0, true, "ATTEND drains the reserve, and DISRUPT does not")
	assert_almost_eq(
		pool.current,
		clampf(held_before + drained * pool.maximum, 0.0, pool.maximum),
		"the reserve fell by exactly the RATIO delta scaled to pool units",
		0.0001
	)
	assert_eq(
		pool.current < held_before,
		true,
		"and it really fell: %f -> %f" % [held_before, pool.current]
	)
	assert_eq(pool.current >= 0.0, true, "a strike can empty the reserve, never invert it")


## A `DISRUPT` strike does NOT touch the reserve, so the effect shape never changes with the
## kind (`MindDamage.KEY_AWARENESS` is `0.0`, not absent). Asserted because the applier
## spends it unconditionally: a `0.0` delta that moved the pool would be a drain nobody
## authored.
func test_a_disrupt_strike_leaves_the_awareness_reserve_alone() -> void:
	var attacker := _mind_attacker()
	var defender := _sea_defender()
	var pool := defender.resource(_tuning.awareness_pool_id) as ResourcePool
	pool.current = pool.maximum
	var held_before := pool.current

	var outcome := _mind_hit(attacker, defender, MindDamage.Kind.DISRUPT)
	var effect: Dictionary = outcome.proposal.effect_of(MindDamage.EFFECT_KIND)
	assert_almost_eq(float(effect[MindDamage.KEY_AWARENESS]), 0.0, "the shape carries a 0.0")
	assert_almost_eq(pool.current, held_before, "so the reserve is untouched")


# --- degradation: nothing here may crash a hit --------------------------------------


## An UNKNOWN effect kind is ignored, quietly. A mechanism may carry anything at all —
## `DamageProposal` is an open vocabulary by contract — and a fourth path's effect arriving
## before its applier arm exists must not turn a landed blow into a crash. The count is
## REPORTED rather than merely survived, because "ignored" and "crashed" are different
## answers and only one of them is testable.
func test_an_unknown_effect_kind_is_ignored_and_never_crashes_the_hit() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	var carried: Array[Dictionary] = [
		{DamageProposal.KIND: &"some.future.path", &"payload": 42.0},
		{DamageProposal.KIND: &"", &"payload": 1.0},
		{"no_kind_at_all": true}
	]
	var report := CombatEffectApply.apply(target, carried, _tuning)
	assert_eq(int(report[CombatEffectApply.KEY_IGNORED]), 3, "all three unknown kinds ignored")
	assert_eq(int(report[CombatEffectApply.KEY_SKIPPED]), 0, "and none counted as a skip")
	assert_eq(
		(report[CombatEffectApply.KEY_APPLIED] as Dictionary).is_empty(), true, "nothing applied"
	)
	assert_eq(
		ledger.severity_of(&"lung"), 0.0, "and the ledger is untouched by a kind nobody wrote"
	)
	# And through the SPINE, so "never crashes the hit" is asserted on the whole pipeline
	# rather than on one call: a hit carrying an unknown effect still lands and still costs
	# health.
	var attacker := _attacker()
	var health_before := target.resource(&"health").current
	var stub := CombatTestKit.FixedMechanism.new()
	stub.effects = carried
	MechanismSlot.bind(attacker, stub)
	var outcome := CombatSpine.resolve_hit(
		attacker, target, _technique(100.0, &"lung"), _tuning, null, Callable()
	)
	assert_eq(outcome.missed, false, "the hit landed")
	assert_eq(target.resource(&"health").current < health_before, true, "and cost health")
	assert_eq(ledger.severity_of(&"lung"), 0.0, "while settling no wound nobody authored")


## A target with NO wound ledger takes the blow normally and simply loses the wound. The
## blow is not refused, not halved and not crashed: the defect this prevents is a missing
## component turning a landed hit into an exception three stages after the damage.
func test_a_target_with_no_ledger_takes_the_damage_normally_and_skips_the_wound() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	assert_eq(CombatEngineApi.wounds_of(target), null, "the fixture really did bind no ledger")
	var health_before := target.resource(&"health").current
	var mechanism := _bind_body(attacker)

	var outcome := _strike(attacker, target, _technique(100.0, &"lung"), mechanism)
	assert_eq(outcome.missed, false, "the hit landed")
	assert_eq(outcome.health_delta < 0.0, true, "which is a real loss, not a no-op")
	assert_eq(
		target.resource(&"health").current,
		health_before + outcome.health_delta,
		"and health moved exactly as a ledgered target's would"
	)
	# The applier called directly: a known kind whose component is absent is a SKIP,
	# reported separately from an unknown kind so the two answers stay distinguishable.
	var report := (
		CombatEffectApply
		. apply(
			target,
			[
				{
					DamageProposal.KIND: BodyWounds.EFFECT_KIND,
					BodyWounds.KEY_MERIDIAN: &"lung",
					BodyWounds.KEY_SEVERITY: 10.0,
				}
			],
			_tuning
		)
	)
	assert_eq(int(report[CombatEffectApply.KEY_SKIPPED]), 1, "the wound was SKIPPED")
	assert_eq(
		(report[CombatEffectApply.KEY_APPLIED] as Dictionary).is_empty(), true, "and not applied"
	)
	# And the applier attaches nothing on the way past: a body nobody bound a ledger to is a
	# body nobody can save one for, so growing it here would invent state.
	assert_eq(CombatEngineApi.wounds_of(target), null, "still no ledger -- it attached nothing")


## The same for the mind half: no sea attached means the erosion is skipped and the hit still
## lands. `MindDamage`'s denominator already reads `0.0` for such a target, so this is the
## belt to that braces -- the applier must not be the thing that decides a missing sea is a
## crash.
func test_a_target_with_no_sea_skips_the_erosion_and_still_takes_the_hit() -> void:
	var attacker := _mind_attacker()
	var bare := CombatTestKit.actor(&"no_sea", 500.0)
	assert_eq(bare.component(_tuning.sea_component), null, "the fixture really bound no sea")
	var health_before := bare.resource(&"health").current

	var outcome := _mind_hit(attacker, bare)
	assert_eq(outcome.missed, false, "the hit landed")
	# A mind amount is `0.0`, so the ONLY health a mind hit may cost is S8's chip floor on
	# S1's base -- the same chip any landed hit pays, and the documented exception ADR 0071
	# was amended to record (ADR 0162). Asserting it as that floor rather than as `0.0` is
	# what "takes the hit normally" means here: the erosion was skipped, not the blow.
	assert_almost_eq(
		float(outcome.amount),
		CombatSpine.chip_floor(CombatSpine.base_damage(attacker, _mind_technique()), _tuning),
		"the blow costs S8's chip floor and nothing more"
	)
	assert_eq(
		bare.resource(&"health").current,
		health_before + outcome.health_delta,
		"and the pool moved by exactly that, because the missing sea cost the target nothing extra"
	)
	var report := CombatEffectApply.apply(
		bare,
		[
			{
				DamageProposal.KIND: MindDamage.EFFECT_KIND,
				MindDamage.KEY_TURBULENCE: 0.5,
				MindDamage.KEY_CLARITY: -0.1
			}
		],
		_tuning
	)
	assert_eq(int(report[CombatEffectApply.KEY_SKIPPED]), 1, "the erosion was SKIPPED")
	assert_eq(
		(report[CombatEffectApply.KEY_APPLIED] as Dictionary).is_empty(), true, "and not applied"
	)


## A null actor, a null effects array, an empty one and a non-dictionary entry are all
## supported. The applier is the last thing a landed hit runs and the one place a
## half-built actor would take the whole exchange down with it, so every refusal has to be a
## number rather than an exception.
func test_null_and_malformed_inputs_are_refused_rather_than_crashing() -> void:
	var target := CombatTestKit.actor(&"bare", 100.0)
	assert_eq(
		(
			(
				CombatEffectApply.apply(null, [], _tuning)[CombatEffectApply.KEY_APPLIED]
				as Dictionary
			)
			. is_empty()
		),
		true,
		"a null target settles nothing"
	)
	for bad in [null, "not an array", {}, 7]:
		var report := CombatEffectApply.apply(target, bad, _tuning)
		assert_eq(
			int(report[CombatEffectApply.KEY_IGNORED]) + int(report[CombatEffectApply.KEY_SKIPPED]),
			0,
			"%s settles nothing and is not an error" % str(bad)
		)
	assert_eq(
		int(
			CombatEffectApply.apply(target, ["nonsense", 42, null], _tuning)[
				CombatEffectApply.KEY_IGNORED
			]
		),
		3,
		"three non-dictionary entries are ignored, one apiece"
	)
	# A non-finite delta is refused rather than written: `maxf(NaN, 0.0)` is `NaN`, and the
	# spine's single non-finite guard sits at S6's entrance -- which a mind amount of `0.0`
	# never reaches, so nothing upstream would catch it.
	var sea_holder := _sea_defender()
	var sea := MindCultivationApi.sea(sea_holder)
	var turbulence_before := sea.turbulence
	for junk in [NAN, INF, -INF, "not a number", null]:
		CombatEffectApply.apply(
			sea_holder,
			[{DamageProposal.KIND: MindDamage.EFFECT_KIND, MindDamage.KEY_TURBULENCE: junk}],
			_tuning
		)
	assert_almost_eq(
		sea.turbulence,
		turbulence_before,
		"a junk turbulence delta wrote nothing, so the sea is still finite"
	)


# --- the fresh-ledger regression, named ----------------------------------------------


## `BodyDamage.apply_wounds` is the OTHER route onto the same ledger, and it is the one that
## carried the fresh-`BodyWounds` bug. Two proposals, two calls, one target -- and the ledger
## they wrote to is the bound one, so the severities accumulate.
##
## This is the assertion the old `test_body_damage_wounds` could not make: it called
## `apply_wounds` once and checked the returned total, which a per-call fresh ledger answers
## perfectly. Calling it TWICE is what distinguishes "settled on the bound ledger" from
## "answered on a throwaway".
func test_apply_wounds_settles_onto_the_bound_ledger_and_not_a_fresh_one() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	var mechanism := _bind_body(attacker)
	var technique := _technique(100.0, &"lung")

	var outcome := _strike(attacker, target, technique, mechanism)
	assert_almost_eq(
		CombatEffectApply.apply(target, [], _tuning)[CombatEffectApply.KEY_IGNORED],
		0.0,
		"an empty effect list is not an error -- it is what a declined mechanism returns"
	)
	var first_total := ledger.severity_of(&"lung")
	assert_eq(
		first_total > 0.0,
		true,
		"the SPINE had already settled this proposal's wound onto the bound ledger"
	)
	assert_eq(
		CombatEngineApi.wounds_of(target),
		ledger,
		"so the direct route settles onto the BOUND ledger, not a BodyWounds.new() it drops"
	)
	# A second, INDEPENDENT proposal through the same function must land ON TOP of the
	# first rather than beside it in a void. Deliberately resolved BY HAND rather than
	# through the spine, so this `apply_wounds` is the ONLY writer in the step and the
	# difference between the two severities is the whole assertion: identical attack,
	# identical defender, identical damage, so the only thing that can make the second
	# number exceed the first is that both landed on ONE ledger.
	#
	# The wound threshold is CROSSED on purpose, which is why the second proposal's own
	# damage is not the first's: at `WOUND_THRESHOLD` the ledger calls
	# `MeridianNetwork.damage_meridian`, the channel becomes INJURED, and an injured
	# channel raises the damage taken there (ADR 0070). The total therefore accumulates to
	# `first + second` where `second > first`, which is still the property under test --
	# a fresh ledger per call would answer with `second` alone, and nothing else.
	var second := mechanism.resolve(_context(attacker, target, technique, BodyLocation.MODE_NAMED))
	var second_own := (
		float(second.effect_of(BodyWounds.EFFECT_KIND)[BodyWounds.KEY_SEVERITY])
		/ _integrity_maximum(target)
	)
	assert_eq(
		target.meridians.get_meridian(&"lung").injured,
		true,
		"the first wound CROSSED WOUND_THRESHOLD, so the channel is now injured"
	)
	assert_eq(
		second_own > first_total,
		true,
		"and an injured channel takes MORE damage -- which is why the severities differ"
	)
	assert_eq(
		mechanism.apply_wounds(target, second, _tuning).size(), 1, "the second proposal settled too"
	)
	assert_almost_eq(
		ledger.severity_of(&"lung"),
		first_total + second_own,
		"and the ledger holds BOTH -- a fresh one per call would answer with `second` alone",
		0.0001
	)
	assert_almost_eq(
		CombatEngineApi.wounds_of(target).severity_of(&"lung"),
		ledger.severity_of(&"lung"),
		"and the facade and the fixture hold the same number, so a save can carry it"
	)


## A target with no ledger is a supported state for the direct route too, and `apply_wounds`
## writes nothing rather than quietly growing a ledger nobody can save. Asserted because the
## old implementation's fresh `BodyWounds.new()` would have written the wound happily -- into
## an object that was then discarded, which is the bug in its quietest form.
func test_apply_wounds_on_an_unledgered_target_writes_nothing_rather_than_a_throwaway() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var mechanism := _bind_body(attacker)
	var proposal := mechanism.resolve(
		_context(attacker, target, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
	)
	assert_eq(proposal.effects.size(), 1, "the mechanism really produced a wound effect")
	assert_eq(
		mechanism.apply_wounds(target, proposal, _tuning).size(),
		0,
		"so apply_wounds had a wound to settle and settled none"
	)
	assert_eq(CombatEngineApi.wounds_of(target), null, "and grew no ledger on the way past")


## The composition root binds the ledger, so the path from a wound to a SAVE is closed from
## production and not from a test: `CombatBoot.bind_mechanisms` is the call the documented
## save-load path makes, and before this it was the only caller `attach_wounds` had.
func test_the_composition_root_binds_the_ledger_a_hit_can_accumulate_onto() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	assert_eq(CombatEngineApi.wounds_of(target), null, "nothing bound it yet")
	var report := CombatBoot.bind_mechanisms(target)
	assert_eq(bool(report["wounds"]), true, "CombatBoot bound a ledger")
	var ledger := CombatEngineApi.wounds_of(target)
	assert_ne(ledger, null, "and the facade finds it")
	assert_ne(ledger.tuning, null, "bound to the shipped tuning, so its thresholds are real")
	ledger.add(target, &"lung", _severity_for(target, 1.0), _tuning)
	# Idempotent, like the mechanism binding beside it: a re-boot must not erase a wound.
	var again := CombatBoot.bind_mechanisms(target)
	assert_eq(bool(again["wounds"]), true, "a second boot still reports one")
	assert_eq(
		CombatEngineApi.wounds_of(target), ledger, "and it is the SAME ledger, not a fresh one"
	)
	assert_almost_eq(ledger.severity_of(&"lung"), 1.0, "so the wound survived the re-boot")


# --- builders ------------------------------------------------------------------------


## A mind attacker whose `mental_attack` is pinned BY CONSTRUCTION at `40.0`, with a sea of
## its own so `MindDamage._sea_of` has a component to reach on either side of the seam.
func _mind_attacker() -> Actor:
	var actor := Actor.new(&"mind_striker", MIND_STRIKER_BASE)
	actor.add_resource(ResourcePool.new(&"health", 150.0))
	MindCultivationApi.attach(actor)
	return actor


## A defender carrying a REAL attached sea at R1's capacity, its clarity pinned, and its
## AWARENESS reserve HELD — a held reserve is what makes `coherence` the damped-but-nonzero
## figure rather than the neutral `1.0`, and a hit that had to be damped proves more than one
## that started at the ceiling.
func _sea_defender() -> Actor:
	var actor := Actor.new(&"mind_ward", {Stat.PHYSIQUE: 10.0, MindStats.MENTAL_CLARITY: 0.5})
	actor.add_resource(ResourcePool.new(&"health", 150.0))
	MindCultivationApi.attach(actor)
	var sea := MindCultivationApi.attach_sea(actor)
	# Assigned AFTER attachment: `attach_sea` seeds `structural_capacity` from a base stat
	# an actor with no realm does not carry, which is `0.0` -- and a `0.0` capacity makes the
	# erosion visibly inert.
	sea.set_structural_capacity(SEA_CAPACITY)
	sea.set_clarity(CLARITY_BEFORE)
	var pool := actor.resource(_tuning.awareness_pool_id) as ResourcePool
	if pool != null:
		pool.current = pool.maximum
	return actor


## Bind a `BodyDamage` with the shipped tuning, which is what every row here measures
## against.
func _bind_body(attacker: Actor) -> BodyDamage:
	var mechanism := BodyDamage.new()
	mechanism.tuning = _tuning
	MechanismSlot.bind(attacker, mechanism)
	return mechanism


## One landed body hit through the SPINE, aimed `named` at the technique's own meridian and
## carrying the bound ledger on the context. A null `rng` lands every attack and never crits,
## so what each row reads is the arithmetic and not a roll.
func _strike(
	attacker: Actor, target: Actor, technique: TechniqueDef, _mechanism: BodyDamage
) -> CombatOutcome:
	return CombatSpine.resolve_hit(
		attacker,
		target,
		technique,
		_tuning,
		null,
		BodyDamage.builder(technique, BodyLocation.MODE_NAMED)
	)


## One landed mind hit through the SPINE, with the kind and the sea injected the way
## `CombatBoot` injects them. Mind's proposal carries `amount == 0.0`, so the health pool is
## untouched by construction and the sea is the only thing that can move.
func _mind_hit(
	attacker: Actor, defender: Actor, kind_value: MindDamage.Kind = MindDamage.Kind.DISRUPT
) -> CombatOutcome:
	var mechanism := MindDamage.new()
	mechanism.tuning = _tuning
	MechanismSlot.bind(attacker, mechanism)
	var carry := MindDamage.builder(kind_value, MindCultivationApi.sea(defender))
	return CombatSpine.resolve_hit(
		attacker,
		defender,
		_mind_technique(),
		_tuning,
		null,
		func(ctx: AttackContext) -> AttackContext:
			var staged: AttackContext = carry.call(ctx) as AttackContext
			staged.set_data(MindDamage.SHARE_KEY, 1.0)
			return staged
	)


func _mind_technique() -> TechniqueDef:
	var def := CombatTestKit.technique(100.0)
	def.id = &"mind_effect_apply"
	return def
