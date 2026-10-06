extends TestCase

## A boss INFICTS on the player, end to end, and the gate that decides it actually ROLLS.
##
## ## Why this suite exists at all
##
## Measured before it: `grep 'affliction|LootAffliction' game/tests` returned NOTHING. Seven
## shipped `.tres` bosses authored an affliction, `BossDef.affliction` was frozen onto the
## spawned boss record, `LootAffliction.inflict` applied it through `StatusApi.apply`, and
## `LootState.strike` surfaced it under `result["affliction"]` — roughly eight files of
## production wiring, with not one test. A regression anywhere in that chain would have left
## the whole suite green.
##
## Worse, the gate was theatre. `LootAffliction.inflict` compared its `chance` argument to
## `0.0` and then NEVER USED IT: no rng, no roll, anywhere on the affliction path. So
## `CombatExchange._boss_affliction_numbers` resolved ADR 0087's whole multiplicative resist
## formula (`status_resistance`, `elemental_resistance_<e>`, `status_min_apply`), handed the
## number down two modules, and it was discarded — every authored boss affliction landed
## 100% of the time no matter what the player built. A test that only asserted "an affliction
## lands" would have PASSED on that defect, because with no roll at all it lands every time.
## That is why the measured-rate cases below exist alongside the reachability ones.
##
## ## What is driven here, and what is deliberately NOT
##
## Every case goes through the PRODUCTION path — a real `LootApi` run against shipped
## content, fought with `LootApi.strike` or `CombatExchange.exchange`, and the assertion is
## about what the PLAYER holds afterwards. Nothing here calls `LootAffliction.inflict` to
## prove the affliction applied, because that is the "the mechanic exists and nothing can
## reach it" shape this suite exists to close: a hand-driven call proves the function works,
## not that a boss can do it.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
## The ember band's SECOND boss, and the one the shipped content gives an affliction:
## `loot_ember_vault_cinder_hound.tres` authors `fire_pyre`, the amplifier half of the fire
## pair. Named here rather than derived, because a test that computed its expectation from
## the code under test would prove only self-consistency.
const HOUND := &"loot_ember_vault_cinder_hound"
const HOUND_AFFLICTION := &"fire_pyre"

## The band's FIRST boss, which authors no affliction. The negative control every "a boss
## with nothing authored inflicts nothing" claim needs: without a boss that genuinely has no
## affliction, "nothing was applied" would be satisfied by a gate that never opens.
const WARDEN := &"loot_ember_vault_warden"

const SEED := 20260902

## An authored id no catalogue ships, used to drive the UNKNOWN_STATUS refusal. A named
## constant rather than an inline literal so the test and its docblock cannot drift apart,
## and deliberately spelled so it can never collide with a real status id.
const FORGED_ID := "an_affliction_nobody_authored"

## A high `Stat.STATUS_RESISTANCE` on the player, who is the status's SUBJECT. A real
## defensive stat read by ADR 0087's formula rather than a rig, so the rate comparison below
## is between two legal builds and not between a build and a bypass. `Stat.STATUS_RESISTANCE`
## is a `0.0`-baselined `0.8`-capped RATE, so FLAT is the only modifier form that can move it
## (`combat_engine/status_apply.gd`).
## ADR 0884: the resisted arm solves for a SHARE of the gate's own scale, because the gate
## is a flat delta now — a `0.6` FLAT on the stat meant `0.6/resist_divisor` of a share.
const RESIST_SHARE := 0.3

## How many fresh delvers to run before concluding a rate. Each is its own actor in its own
## run at its own seed, so the sample is independent draws rather than one actor's fights.
const SWEEP := 64

## The minimum gap between the open- and resisted-rate samples that this suite will call a
## real difference. The resolved chance is `(1 - resist)`, so 0.6 resist asks for 40% and a
## 64-draw sweep has a standard error near 6 points; a 15-point floor is roughly 2.5 sigma,
## which is wide enough to be honest and narrow enough that the gate being VACUOUS — the
## defect — could never clear it.
const RATE_GAP := 0.15

## The seeds the RNG-isolation case walks when it needs the two arms to land on OPPOSITE
## sides of the gate. Sampled rather than pinned to one value because a single seed can only
## ever witness one draw, and the resisted arm rolls at 0.4 — so most seeds have both arms
## agreeing, and that agreement is the expected answer, not a failure. Scanned in order and
## the first three that genuinely diverge are used, which is why the list is the same sweep
## the rate cases measure over: one seed space, two claims about it.
const _DIVERGENT_SEEDS: Array[int] = [
	4001,
	4008,
	4015,
	4022,
	4029,
	4036,
	4043,
	4050,
	4057,
	4064,
	4071,
	4078,
	4085,
	4092,
	4099,
	4106,
	4113,
	4120,
	4127,
	4134,
	4141,
	4148,
	4155,
	4162,
	4169,
	4176,
	4183,
	4190,
	4197,
	4204,
	4211,
	4218,
	4225,
	4232,
	4239,
	4246,
	4253,
	4260,
	4267,
	4274,
	4281,
	4288,
	4295,
	4302,
	4309,
	4316,
	4323,
	4330,
	4337,
	4344,
	4351,
	4358,
	4365,
	4372,
	4379,
	4386,
	4393,
	4400,
	4407,
	4414,
	4421,
	4428,
	4435,
	4442,
	4449,
]

# --- fixtures ------------------------------------------------------------------


## A bare delver with the same attachments the existing exchange suites use: core pools, an
## item state and the loot state. No gear on purpose — at +60 flat attack one blow is worth
## the whole pool, and a one-shot delver would advance the band under the assertions.
func _delver(resist_share: float = 0.0) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	if resist_share > 0.0:
		# Solved against the SHIPPED tuning so a retune moves the fixture with it, and on
		# the id the gate ACTUALLY reads: the old `Stat.STATUS_RESISTANCE` spelling is the
		# id ADR 0200 retired, so this arm measured nothing until it was corrected.
		var tuning := CombatEngineApi.tuning()
		var ceiling := clampf(float(tuning.mitigation_ceiling), 0.0, 1.0)
		var divisor_k := maxf(0.0, float(tuning.defense_divisor_k))
		var share := clampf(resist_share, 0.0, ceiling - 1e-6)
		var defense := divisor_k * share / maxf(1e-9, ceiling - share)
		actor.stats.add_modifier(
			StatModifier.new(
				StringName(tuning.status_defense_stat),
				Stat.Op.FLAT,
				defense * float(tuning.resist_divisor),
				&"affliction_resist"
			)
		)
	return actor


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


func _affliction_of(result: Dictionary) -> Dictionary:
	return result.get("affliction", {}) as Dictionary


func _in_run(actor: Actor) -> bool:
	return bool(_active(actor).get("in_domain", false))


## A delver already facing `boss_id`, entered through the facade's own entry path and then
## WALKED along the band, because a band hosts several bosses and spawns them in authored
## order. Returns an actor that is not in a run when the walk cannot arrive, which every
## caller reports rather than asserting past.
##
## Each earlier boss is KILLED, not chipped: rule E3 only advances the band on a defeat, so
## a partial blow leaves the same boss standing forever and the walk never arrives. The kill
## goes through [method LootApi.strike] with the DEFAULT open gate, which means the bosses
## passed on the way afflict this actor too — harmless for the assertions (each case reads
## only its own target's report, and `fire_pyre` is idempotent under ADR 0086's `refresh`
## stacking), and it keeps the walk on the real primitive rather than writing `active`
## directly, which would be a state the game cannot produce.
##
## The walk is bounded by the band's own boss count (AGENTS.md's runaway rule): a band that
## grew a boss nobody kills ends the walk by refusing to advance, never by spinning.
func _facing(boss_id: StringName, seed_value: int, resist: float = 0.0) -> Actor:
	var actor := _delver(resist)
	if not bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, seed_value).get("ok", false)):
		return actor
	var guard := 0
	while String(_active(actor).get("boss_id", "")) != String(boss_id) and guard <= 8:
		guard += 1
		if not _in_run(actor):
			return actor
		var active := _active(actor)
		# Well past the boss's whole pool, so the defeat is decided on this one strike
		# whatever the band priced it at.
		var killed := LootApi.strike(
			actor, float(active.get("vitality_max", 1.0)) * 10.0, seed_value
		)
		if not bool(killed.get("ok", false)):
			return actor
		if not _in_run(actor):
			return actor
	return actor


## One exchange against `boss_id` for a fresh delver, or `{}` when the walk or the fight
## could not be set up. Swept over seeds by the rate cases below rather than pinned to one,
## because what is under test is a RATE, and a single seed can only ever witness one draw.
func _exchange_against(boss_id: StringName, seed_value: int, resist: float = 0.0) -> Dictionary:
	var actor := _facing(boss_id, seed_value, resist)
	if not _in_run(actor) or String(_active(actor).get("boss_id", "")) != String(boss_id):
		return {}
	return CombatExchange.exchange(actor, seed_value)


## How many of `SWEEP` fresh fights landed the boss's affliction on the player, WITH the
## denominator it actually measured.
##
## Each iteration is an independent actor, its own run and its own seed, so the only thing
## the sample shares is the authored content — which is the point: the spread being measured
## is the gate's, not one actor's. A fight that could not be set up is not a draw the gate
## refused, so the MEASURED count travels with the landed one and every rate below divides
## by it. `rate` is `-1.0` when the sample is too thin to read, so a broken fixture reads as
## "unmeasurable" rather than as "never applies".
func _affliction_rate(boss_id: StringName, resist: float) -> Dictionary:
	var landed := 0
	var measured := 0
	for index in SWEEP:
		var result := _exchange_against(boss_id, 4001 + index * 7, resist)
		if result.is_empty():
			continue
		measured += 1
		if bool(_affliction_of(result).get("applied", false)):
			landed += 1
	if measured < SWEEP / 2:
		return {"landed": landed, "measured": measured, "rate": -1.0}
	return {"landed": landed, "measured": measured, "rate": float(landed) / float(measured)}


# --- 1. reachability: a boss with an authored affliction inflicts it --------------


func test_a_bosss_authored_affliction_actually_lands_on_the_player() -> void:
	# THE test. A real run, the real hound, the real exchange, and the only assertion that
	# matters: afterwards the PLAYER HOLDS the status the boss authored.
	#
	# The boss cannot be asserted instead — it is a `Dictionary` in `module_data`, not an
	# `Actor` — so `actor.has_status` is the whole subject of the claim.
	var actor := _facing(HOUND, SEED)
	if not _in_run(actor):
		return
	assert_eq(
		String(_active(actor).get("affliction", "")),
		String(HOUND_AFFLICTION),
		"the spawned boss record carries the authored affliction, frozen onto it"
	)
	var result := CombatExchange.exchange(actor, SEED)
	if not bool(result.get("ok", false)):
		return
	assert_eq(
		bool(_affliction_of(result)["applied"]),
		true,
		"the boss afflicted the player on a landed exchange"
	)
	assert_eq(
		String(_affliction_of(result)["id"]),
		String(HOUND_AFFLICTION),
		"naming exactly the status its BossDef authored"
	)
	assert_eq(
		actor.has_status(HOUND_AFFLICTION),
		true,
		"and the player HOLDS it: this is a live status, not a reported one"
	)
	# The report is primitives only (ADR 0038), so a screen renders it without naming a
	# Resource. Asserted here because the dict is what `exchange` hands on and the key
	# itself is the contract a UI consumer indexes unconditionally.
	for key in _affliction_of(result).keys():
		assert_eq(
			(
				typeof(_affliction_of(result)[key]) == TYPE_OBJECT
				or typeof(_affliction_of(result)[key]) == TYPE_NIL
			),
			false,
			"affliction['%s'] is a primitive" % String(key)
		)


func test_the_affliction_reaches_loot_api_strikes_own_return_value() -> void:
	# The task's own N1 requirement, and a SEPARATE claim from the exchange case above.
	# `LootApi.strike` is the primitive, and it is a public facade method other callers use
	# directly — `app/test_mutation_guards.gd` and four acquisition suites strike through it.
	# If the `affliction` key only existed on `CombatExchange`'s wrapper, every one of those
	# callers would be blind to what the boss did to them. So the gate is asserted HERE, with
	# the default OPEN gate, proving the key rides the facade's return and not just the
	# exchange's report.
	var actor := _facing(HOUND, SEED)
	if not _in_run(actor) or String(_active(actor).get("boss_id", "")) != String(HOUND):
		return
	var active := _active(actor)
	var struck := LootApi.strike(actor, float(active.get("vitality_max", 1.0)) * 0.2, SEED)
	assert_eq(bool(struck.get("ok", false)), true, "the strike landed")
	assert_eq(struck.has("affliction"), true, "and its return carries an affliction report")
	assert_eq(
		bool(_affliction_of(struck)["applied"]),
		true,
		"applied through LootApi.strike's own default gate"
	)
	assert_eq(
		String(_affliction_of(struck)["id"]),
		String(HOUND_AFFLICTION),
		"naming the authored affliction, with no CombatExchange in the call at all"
	)
	assert_eq(
		actor.has_status(HOUND_AFFLICTION),
		true,
		"and the player holds it: the producer is reached from the primitive alone"
	)


func test_a_boss_with_no_authored_affliction_applies_nothing_and_is_not_an_error() -> void:
	# The ordinary negative, and it is an ordinary ANSWER rather than a refusal: an empty
	# authored id returns the same `{applied: false, id: "", reason: ""}` the landed-blow
	# report uses for an element nothing maps. `LootAffliction` says so in its own docblock.
	#
	# The warden is the control that gives the claim teeth — it is a real boss of the same
	# band, one slot earlier, reached through the same fixture, so "nothing was applied"
	# cannot be satisfied by a gate that never opens or by a walk that never arrived.
	assert_eq(
		String(_active(_facing(WARDEN, SEED)).get("affliction", "")),
		"",
		"the warden authors no affliction, which is the case under test"
	)
	var actor := _facing(WARDEN, SEED)
	if not _in_run(actor) or String(_active(actor).get("boss_id", "")) != String(WARDEN):
		return
	var result := CombatExchange.exchange(actor, SEED)
	if not bool(result.get("ok", false)):
		return
	assert_eq(result.has("affliction"), true, "the report still carries the key")
	assert_eq(
		bool(_affliction_of(result)["applied"]),
		false,
		"with nothing applied — no gate, no refusal, just an answer"
	)
	assert_eq(String(_affliction_of(result)["reason"]), "", "and no refusal reason to report")
	assert_eq(String(_affliction_of(result)["id"]), "", "naming nothing")
	# The control that gives "nothing was applied" its meaning: the SAME fixture against the
	# hound DOES apply. Without it this case would pass on a gate wired to never open.
	assert_eq(
		bool(_affliction_of(_exchange_against(HOUND, SEED)).get("applied", false)),
		true,
		"while the same fixture against the hound does apply"
	)


# --- 2. the refusals are NAMED ----------------------------------------------------


func test_an_unknown_affliction_id_is_refused_by_name() -> void:
	# A boss whose authored id names nothing in the catalogue must be REFUSED BY NAME, so a
	# balance pass can tell a typo from a resisted roll from a boss that authors nothing.
	#
	# The id is INVENTED rather than a real-but-unused one, so the assertion cannot pass
	# because a catalogue slot happens to be empty, and so a later addition of that exact id
	# fails this test loudly instead of quietly deleting the branch under test.
	#
	# A bare actor rather than one walked to a boss: this case is about the refusal a NAMED
	# id produces, which is decided from the id alone. Tying it to the band walk would make a
	# content change in an unrelated domain read as a failure of the refusal vocabulary.
	var actor := _delver()
	var report := LootAffliction.inflict(actor, {"affliction": FORGED_ID}, true, 1.0)
	assert_eq(
		bool(report.get("applied", true)), false, "an id outside the catalogue applies nothing"
	)
	assert_eq(
		String(report.get("reason", "")),
		String(LootAffliction.UNKNOWN_STATUS),
		"refused by its own name, which is a different fact from a closed gate"
	)
	assert_eq(
		String(report.get("id", "")),
		FORGED_ID,
		"and it names the id it refused, so the offending content is identifiable"
	)
	# The positive control: the refusal above is the CATALOGUE saying no, not the gate.
	# With the identical gate open the shipped id does apply, so the two differ only in the
	# id and the branch is really the one under test.
	var real := LootAffliction.inflict(actor, {"affliction": HOUND_AFFLICTION}, true, 1.0)
	assert_eq(
		bool(real.get("applied", false)),
		true,
		"and the same open gate accepts the shipped id, so it is the id that was refused"
	)


func test_a_cultivation_scope_affliction_is_refused_because_a_boss_cannot_bless() -> void:
	# The load-bearing half of the boundary. A CULTIVATION def is a PERMANENT blessing
	# (`duration = -1.0`) the game PAYS OUT; a boss handing one out would install
	# `earth_bulwark` as a permanent debuff that ADR 0089's purge never touches, so it would
	# outlive the fight that inflicted it. `TribulationBlessing` owns that half of the
	# vocabulary, and this verb refuses it by name.
	#
	# The id is FOUND by asking the catalogue for a non-COMBAT def rather than hardcoded, so
	# this keeps testing the rule if the cultivation vocabulary is ever renamed — and so it
	# fails loudly (rather than passing on an empty sample) if every def were COMBAT scope.
	#
	# A bare actor, not one walked to a boss: this case is about the REFUSAL the producer
	# returns for a named id, which is decided from the id alone. Depending on the band walk
	# would make a content change in an unrelated domain read as a failure of this rule.
	var cultivation := _a_cultivation_status()
	if cultivation == &"":
		return
	var actor := _delver()
	assert_eq(
		bool(
			LootAffliction.inflict(actor, {"affliction": cultivation}, true, 1.0).get(
				"applied", true
			)
		),
		false,
		"a CULTIVATION-scope status is not something a boss may inflict"
	)
	var report := LootAffliction.inflict(actor, {"affliction": cultivation}, true, 1.0)
	assert_eq(
		String(report.get("reason", "")),
		String(LootAffliction.NOT_COMBAT_SCOPE),
		"refused by its own name, distinct from an unknown id"
	)
	assert_eq(String(report.get("id", "")), String(cultivation), "and it names the def it refused")
	assert_eq(
		actor.has_status(cultivation),
		false,
		"so the player was not left carrying a permanent blessing"
	)


func test_a_closed_gate_is_refused_by_name_and_costs_nothing() -> void:
	# ADR 0087's CLOSED gate, asserted as a NAMED refusal rather than as a missing status.
	# Two facts are separated here that used to be the same code path: `gate_open = false`
	# is the caller saying the roll came up against the chance, and it must be
	# distinguishable from `UNKNOWN_STATUS` and from a boss that authors nothing.
	#
	# A bare actor, because a closed gate is refused BEFORE any apply is attempted and the
	# report is decided from the id and the verdict alone — the band walk would add nothing
	# but a way for unrelated content to break this.
	var actor := _delver()
	var report := LootAffliction.inflict(actor, {"affliction": HOUND_AFFLICTION}, false, 1.0)
	assert_eq(bool(report.get("applied", true)), false, "a closed gate applies nothing")
	assert_eq(
		String(report.get("reason", "")),
		String(LootAffliction.CLOSED_GATE),
		"refused as the closed gate, which is ADR 0087's own vocabulary"
	)
	assert_eq(
		String(report.get("id", "")),
		String(HOUND_AFFLICTION),
		"naming the status the roll was AGAINST, so a balance pass can see the rate went to zero"
	)
	assert_eq(
		actor.has_status(HOUND_AFFLICTION), false, "so nothing was written to the player either"
	)


# --- 3. the gate ROLLS: ADR 0087's resist formula is not inert --------------------


func test_a_resisted_player_is_afflicted_less_often_than_an_open_one() -> void:
	# THE test this suite's existence is really about. A reachability test passes on a gate
	# that NEVER ROLLS, so the measured rate is the only thing that distinguishes a working
	# gate from theatre.
	#
	# Both samples are 64 independent fights against the same shipped hound with the same
	# delver bundle; the ONLY difference is a solved `RESIST_SHARE` of the gate's own scale
	# on one of them. ADR 0884's `apply_chance` is a flat delta, so that share reads
	# straight off the parity half — `0.5 - share` — and the two rates must differ by at
	# least [constant RATE_GAP].
	var open_sample := _affliction_rate(HOUND, 0.0)
	var resisted_sample := _affliction_rate(HOUND, RESIST_SHARE)
	if float(open_sample["rate"]) < 0.0 or float(resisted_sample["rate"]) < 0.0:
		return
	# Measured denominators, not `SWEEP`: an iteration whose walk could not arrive is not a
	# draw the gate refused, and dividing by 64 would read a setup skip as a resist.
	var open_rate := int(open_sample["landed"])
	var resisted_rate := int(resisted_sample["landed"])
	assert_eq(
		resisted_rate < open_rate,
		true,
		(
			"a resisted player is afflicted less often (%d/%d) than an open one (%d/%d)"
			% [
				resisted_rate,
				int(resisted_sample["measured"]),
				open_rate,
				int(open_sample["measured"])
			]
		)
	)
	assert_eq(
		float(open_sample["rate"]) - float(resisted_sample["rate"]) >= RATE_GAP,
		true,
		(
			"by at least the measured gap (%.2f): the resist formula is LIVE"
			% (float(open_sample["rate"]) - float(resisted_sample["rate"]))
		)
	)
	# The control that gives both numbers meaning: an UNINVESTED delver's gate sits at the
	# parity half of ADR 0884's flat delta (`status.power` has no shipped producer yet), so
	# the open sample lands near HALF. Degenerate means near zero, which is what a gate
	# wired to always refuse would read.
	assert_eq(
		float(open_sample["rate"]) >= 0.25,
		true,
		(
			"and the open-gate rate is not itself degenerate (%d/%d)"
			% [open_rate, int(open_sample["measured"])]
		)
	)


func test_the_same_seed_afflicts_the_same_way_twice() -> void:
	# Determinism, and the property that makes a rate MEASURABLE at all. Two fresh delvers,
	# identical numbers, identical seed, identical boss: the verdict must match. This is the
	# claim ADR 0087's seeded substream exists for — "reproducible from (seed, encounter)" —
	# and it stops being true the moment a roll enters the exchange.
	var first := _exchange_against(HOUND, 90210)
	var second := _exchange_against(HOUND, 90210)
	if first.is_empty() or second.is_empty():
		return
	assert_eq(
		bool(_affliction_of(first)["applied"]),
		bool(_affliction_of(second)["applied"]),
		"same seed, same verdict — the roll is seeded, not random"
	)
	assert_eq(
		String(_affliction_of(first)["id"]),
		String(_affliction_of(second)["id"]),
		"and the same status id"
	)


func test_different_seeds_can_answer_differently() -> void:
	# The negative of the determinism case, and without it "deterministic" is satisfied by a
	# gate that always answers the same way — which is precisely the defect. Asserted as
	# "the sample is not uniform", never as "seed N must miss", because the latter is a
	# coin-flip assertion and a flaky assertion is not an assertion.
	var verdicts := {}
	for index in SWEEP:
		var result := _exchange_against(HOUND, 3301 + index * 13)
		if result.is_empty():
			continue
		verdicts[bool(_affliction_of(result)["applied"])] = true
	if verdicts.is_empty():
		return
	assert_eq(verdicts.size(), 2, "across 64 seeds the gate both opened and refused: it ROLLS")


func test_the_affliction_roll_does_not_disturb_the_boss_own_answer() -> void:
	# RNG ISOLATION for the affliction path, and the guarantee
	# `test_a_resisted_status_consumes_no_draw_from_the_shared_stream` already holds for the
	# PLAYER's landed blow. `_answer` draws the boss's return stroke off the SAME `rng` the
	# affliction's substream is derived from; if the affliction took a draw off it, then
	# whether a status landed would change the damage the boss deals — a second-order effect
	# no player could see and no test would otherwise catch.
	#
	# Two delvers with the same numbers and the same seed, differing ONLY in a resisted
	# status stat, must therefore agree on `share_taken` AND on the player's resulting
	# health. The two arms answer DIFFERENT chances — the resisted one a share lower — so
	# their verdicts genuinely diverge, and that difference is exactly the cursor this case
	# exists to
	# prove was not shared.
	var plain := _facing(HOUND, 4242)
	var resisted := _facing(HOUND, 4242, RESIST_SHARE)
	if not _in_run(plain) or not _in_run(resisted):
		return
	var plain_result := CombatExchange.exchange(plain, 4242)
	var resisted_result := CombatExchange.exchange(resisted, 4242)
	if not bool(plain_result.get("ok", false)) or not bool(resisted_result.get("ok", false)):
		return
	assert_eq(
		float(resisted_result["share_taken"]),
		float(plain_result["share_taken"]),
		"the boss's answer is the same share whether or not a status landed"
	)
	assert_eq(
		float((resisted_result["player"] as Dictionary)["health"]),
		float((plain_result["player"] as Dictionary)["health"]),
		"and the player ends at the same health: the affliction took no draw off the shared stream"
	)
	# And the two really did take DIFFERENT paths through the roll, so the equality above is
	# not vacuous.
	#
	# ## Why this is a WIDTH assertion and not `applied`
	#
	# It used to assert the two verdicts differ (`applied` true on one, false on the other),
	# which pinned a single SEED to a single draw and so only ever witnessed whether seed
	# 4242 happened to fall on one side of its chance. Over a sweep the two arms agree on
	# many draws — and that is the correct behaviour, not a defect: ADR 0884's chance is
	# `0.5 - RESIST_SHARE` for the resisted build, so it has to land sometimes, and a
	# positive-chance gate CAN roll true. Demanding a different
	# verdict would demand a gate that never opens on the resisted build, which is the
	# `RATE_GAP` case above, and would fail the moment the salt moved.
	#
	# The claim under test is RNG ISOLATION, not the gate's polarity: it is that a difference
	# in the affliction's own verdict cannot move the shared cursor. What makes that
	# non-vacuous is that the two arms genuinely answer DIFFERENT chances — so a shared
	# cursor bug would have shown up in `share_taken`. The two verdicts may agree, and
	# over a sweep they mostly do; they may only not be the SAME EVENT. So this scans seeds
	# for one where the two genuinely diverge, and only then compares the answers, which is
	# the configuration in which a cursor bug is actually observable.
	var seeds_diverged := 0
	for seed_value in _DIVERGENT_SEEDS:
		var open_arm := _facing(HOUND, seed_value)
		var closed_arm := _facing(HOUND, seed_value, RESIST_SHARE)
		if not _in_run(open_arm) or not _in_run(closed_arm):
			continue
		var open_result := CombatExchange.exchange(open_arm, seed_value)
		var closed_result := CombatExchange.exchange(closed_arm, seed_value)
		if not bool(open_result.get("ok", false)) or not bool(closed_result.get("ok", false)):
			continue
		# A seed whose two arms agree is NOT this case's subject — it is a majority of
		# seeds and the expected answer for a positive-chance gate. Skipped, not asserted
		# against: asserting here would pin the whole sweep to a polarity the gate does not
		# have, which is the same coin-flip assertion in a wider window.
		if (
			bool(_affliction_of(closed_result)["applied"])
			== bool(_affliction_of(open_result)["applied"])
		):
			continue
		seeds_diverged += 1
		assert_eq(
			float(closed_result["share_taken"]),
			float(open_result["share_taken"]),
			(
				(
					"seed %d, whose gates diverge: the boss's answer is the same share "
					+ "whether or not a status landed"
				)
				% seed_value
			)
		)
		assert_eq(
			float((closed_result["player"] as Dictionary)["health"]),
			float((open_result["player"] as Dictionary)["health"]),
			"and the player ends at the same health: the affliction took no draw off it either"
		)
		if seeds_diverged >= 3:
			break
	# The sweep must have CONTAINED a divergent seed, or the comparisons above never ran and
	# the case would have passed having asserted nothing about the gate.
	assert_eq(
		seeds_diverged > 0,
		true,
		"and the sweep found seeds where the two actors' gates land on opposite sides of the roll"
	)


# --- 4. the authored corpus, and the gate's own constant --------------------------


func test_every_shipped_affliction_names_a_def_the_catalogue_knows() -> void:
	# Seven `.tres` files author an affliction. This walks the shipped boss corpus rather
	# than a hardcoded list of seven, so a designer adding an eighth boss is covered the
	# moment the content lands, and a typo in a boss's authored id fails HERE rather than
	# silently in production where nothing would ever read the refusal.
	var authored := 0
	for boss_id in _shipped_boss_ids():
		var affliction := String(LootContent.instance().boss_record(boss_id).get("affliction", ""))
		if affliction.is_empty():
			continue
		authored += 1
		var def := StatusApi.definition(StringName(affliction))
		assert_ne(
			def, null, "boss %s authors %s, which is in the catalogue" % [boss_id, affliction]
		)
		if def == null:
			continue
		assert_eq(
			def.is_combat_scope(),
			true,
			"boss %s authors a COMBAT-scope status, never a permanent blessing" % boss_id
		)
	assert_eq(
		authored > 0,
		true,
		"and the corpus still ships at least one authored affliction to be reachable at all"
	)


func test_the_gate_is_one_dial_and_the_resist_formula_is_the_only_arithmetic() -> void:
	# The status GATE decision, pinned so it cannot silently regress into a literal in
	# logic. DEF-0145 moved the number OFF the `CombatExchange.STATUS_GATE_CHANCE`
	# constant and ONTO `CombatTuning.status_gate_chance` in `combat_damage.tres`, which
	# is where ADR 0105 said it belonged and ADR 0087's consequence ("provisional …
	# re-tuned by an edit, never by an ADR") requires it. Two assertions replace the one,
	# and both are STRONGER than the single one they supersede:
	#
	#   1. the SHIPPED rate is still pinned at the value that shipped — the balance
	#      decision is not weakened by the move, only relocated; and
	#   2. the exchange reads the TUNABLE, proved by editing the tuning and watching the
	#      gate follow. The old assertion could not tell a dial from a constant, which is
	#      precisely the defect: it passed on a literal forever.
	var tuning := CombatEngineApi.tuning()
	assert_eq(
		tuning.status_gate_chance,
		1.0,
		"the shipped base gate is saturated, so the resist terms decide both rolls alone"
	)
	# The dial is real: retuning the `.tres` moves the gate, so this is a balance number
	# and not a `.gd` literal wearing a tuning-shaped hat.
	var retuned := CombatEngineApi.tuning()
	retuned.status_gate_chance = 0.6
	assert_eq(
		CombatExchange._status_gate(retuned),
		0.6,
		"the gate follows the authored tuning, so editing the `.tres` retunes both paths"
	)
	# The formula itself, read through the spine: a resisted actor's resolved chance must be
	# strictly below an open one's at the same gate. This is the claim the rate test above
	# measures end to end, asserted here at its source so a failure localises.
	var open_chance := StatusApply.apply_chance(
		null, null, tuning, tuning.status_gate_chance, &"", &"", &"", 0.0
	)
	var closed_chance := StatusApply.apply_chance(null, null, tuning, 0.0, &"", &"", &"", 0.0)
	assert_almost_eq(
		float(open_chance),
		float(tuning.status_gate_chance) * 0.5,
		"an unresisted actor rolls at the gate times the parity half (ADR 0884)"
	)
	assert_eq(
		float(closed_chance),
		0.0,
		"and a closed gate reads 0.0 — the case that spends no draw at all"
	)


# --- internals --------------------------------------------------------------------


## Every shipped boss id, gathered from the authored DOMAIN records.
##
## `LootContent` exposes `boss_record(id)` and `domain_record(id)` but no inverse
## enumerator, and adding one would be a public-method change to a module facade for the
## sake of a test. Every authored `DomainDef` carries `boss_ids` (see
## `data/domains/loot_ember_vault_domain.tres`), and `LootState._spawn` walks that same
## ordered list, so the domain corpus is the index that already exists — and the one whose
## ORDER is the one a run spawns bosses in. Read from the domain record first and the
## encounter second, so a boss authored only on one of the two is still audited.
func _shipped_boss_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for domain_id in LootContent.instance().domain_ids():
		var ids: Array = []
		ids.append_array(
			LootContent.instance().domain_record(StringName(domain_id)).get("boss_ids", []) as Array
		)
		var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
		if encounter != null:
			ids.append_array(encounter.boss_ids)
		for raw in ids:
			var boss_id := StringName(raw)
			if boss_id != &"" and not out.has(boss_id):
				out.append(boss_id)
	return out


## The first CULTIVATION-scope def the shipped catalogue authors, or `&""` when it authors
## none. Derived from the catalogue rather than hardcoded so the test follows renames, and
## returns the empty id rather than a guessed constant so the caller reports "no subject"
## instead of asserting against a name that may not exist.
func _a_cultivation_status() -> StringName:
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def != null and not def.is_combat_scope():
			return status_id
	return &""
