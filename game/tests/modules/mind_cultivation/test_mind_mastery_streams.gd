extends TestCase

## THE MIND MASTERY TRACKS: two of them, advanced by USE, not by realm rank, and
## genuinely different.
##
## ## What this file asserts, and why each assertion is a DIFFERENCE
##
## Every property here is stated as a difference or a bound rather than a restated
## number, because the numbers are authored in `.tres` files a balance pass is
## entitled to move and a test that pinned them would be deleted rather than fixed.
## What cannot be moved is the SHAPE: that mastery is earned, that the two tracks
## are separate vectors, that neither can reach the other's spend currency, and that
## both resolve against authored vocabulary rather than an open key.

const RANK := &"qi_refining"

## Uses walked by the "advances by use" walk. A snapshotted CONSTANT read before the
## `for`, and the loop breaks on arrival — nothing inside it grows the bound, which is
## what `test_no_unbounded_wait.gd` reads.
const EARN_BOUND := 20

## A mid-ladder realm, so the "not realm rank" assertion is made against an actor who
## HAS advanced rather than one standing at the bottom.
const MID_RANK := &"spirit_sea"


func _actor(rank_id: StringName = RANK) -> Actor:
	var actor := ActorFactory.build(
		&"mind_mastery", {Stat.WILL: 30.0, MindStats.PERCEPTION: 25.0, Stat.COMPREHENSION: 10.0}
	)
	return ActorFactory.with_mind_cultivation(actor, rank_id)


## A control def, read through the `status` catalogue the way production does.
func _control(shape: StringName) -> MindStatusDef:
	var catalog := MindStatusCatalog.instance()
	for status_id in catalog.ids_of_role(MindVocabulary.ROLE_CONTROL):
		var def := catalog.definition(status_id)
		if def != null and def.shape() == shape:
			return def
	return null


func _expression(channel: StringName) -> MindStatusDef:
	var catalog := MindStatusCatalog.instance()
	for status_id in catalog.ids_of_role(MindVocabulary.ROLE_EXPRESSION):
		var def := catalog.definition(status_id)
		if def != null and def.channel() == channel:
			return def
	return null


# --- PROPERTY 3: mastery advances by USE ------------------------------------------


## THE property. A mastery ledger moves when the mind CONTESTS, and moves by nothing
## else. Three parts, each a different failure the others would pass:
##
## 1. A fresh ledger reads zero (so a rise is a writer, not an initialiser).
## 2. A single contest moves it — resolved through the `status` module's OWN verb, so
##    the loop a player performs is the loop under test.
## 3. Realm rank does NOT move it: a `cultivate` sitting on a mid-ladder actor leaves
##    the ledger untouched, because mastery is not the realm ladder wearing a name.
func test_mastery_advances_by_using_a_mind_technique_and_not_by_cultivating() -> void:
	var def := _control(MindVocabulary.SHAPE_SLOW)
	assert_ne(def, null, "a daze-shaped control is authored")
	if def == null:
		return
	var actor := _actor()
	var ledger := MindAccess.mastery(actor)
	assert_ne(ledger, null, "attach mints a ledger")
	if ledger == null:
		return
	var key := MindMastery.key_for(def)
	assert_almost_eq(
		ledger.uses_of(MindMastery.TRACK_STATUS, key),
		0.0,
		"a fresh ledger reads zero, so any rise below is a writer"
	)

	assert_eq(
		StatusApi.mind_confront(actor, _actor(), def.id, null).has("ok"), true, "the verb ran"
	)
	assert_eq(
		ledger.uses_of(MindMastery.TRACK_STATUS, key) > 0.0,
		true,
		(
			"ONE confrontation moved the ledger: %f uses"
			% ledger.uses_of(MindMastery.TRACK_STATUS, key)
		)
	)

	# (3) The realm ladder is NOT a mastery source. A deep-realm actor who has never
	# fought reads exactly zero, and a sitting does not move it.
	var deep := _actor(MID_RANK)
	var deep_ledger := MindAccess.mastery(deep)
	assert_ne(deep_ledger, null, "a deep actor carries a ledger too")
	if deep_ledger == null:
		return
	assert_almost_eq(
		deep_ledger.uses_of(MindMastery.TRACK_STATUS, key),
		0.0,
		"a mid-ladder realm with zero confrontations has ZERO mastery in it"
	)
	var before := deep_ledger.uses_of(MindMastery.TRACK_STATUS, key)
	assert_eq(MindCultivationApi.cultivate(deep), true, "a sitting applied")
	assert_almost_eq(
		deep_ledger.uses_of(MindMastery.TRACK_STATUS, key),
		before,
		"and cultivating moved the mastery ledger not at all: it is not the realm ladder"
	)


## The LOOP, walked: the ladder advances a bounded number of times and each advance
## is a real step, so the counter is a loop rather than a single grant.
##
## `EARN_BOUND` is snapshotted before the `for` and the loop breaks on arrival, so the
## bound cannot chase the counter it is measuring — the INC-0002 shape.
func test_the_mastery_ladder_advances_one_step_at_a_time() -> void:
	var def := _control(MindVocabulary.SHAPE_SLOW)
	assert_ne(def, null, "a daze-shaped control is authored")
	if def == null:
		return
	var actor := _actor()
	var ledger := MindAccess.mastery(actor)
	assert_ne(ledger, null, "attach mints a ledger")
	if ledger == null:
		return
	var key := MindMastery.key_for(def)
	var steps: Array[int] = []
	for _attempt in EARN_BOUND:
		steps.append(ledger.step_of(MindMastery.TRACK_STATUS, key))
		MindStatusApi.earn_mastery(actor, def, 1.0)
	assert_eq(steps.size(), EARN_BOUND, "the walk ran its bounded length")
	# Monotonic non-decreasing is the real claim: each step is >= the one before, and
	# the LAST is strictly greater than the FIRST. A counter that advanced but never
	# stepped would pass a "total uses > 0" check and fail here.
	for index in range(1, steps.size()):
		assert_eq(
			steps[index] >= steps[index - 1],
			true,
			"step %d did not go backwards (%d -> %d)" % [index, steps[index - 1], steps[index]]
		)
	assert_eq(
		steps[steps.size() - 1] > steps[0],
		true,
		(
			"and %d confrontations advanced %d ladder steps"
			% [steps.size(), steps[steps.size() - 1] - steps[0]]
		)
	)


# --- PROPERTY 4: the two tracks are NOT reskins ------------------------------------


## THE property. The two tracks are separate VECTORS, separate earn keys, and — the
## load-bearing part — neither advances the other's entry. A contest that imposes a
## `slow` moves the `status` track and leaves every `expression` entry at exactly
## zero, and the reverse. A design where both tracks banked into one counter would
## pass "two track names exist" and fail this.
func test_the_two_tracks_are_separate_ledgers_and_one_never_advances_the_other() -> void:
	var slow := _control(MindVocabulary.SHAPE_SLOW)
	var voice := _expression(MindVocabulary.CHANNEL_VOICE)
	assert_ne(slow, null, "a slow control is authored")
	assert_ne(voice, null, "a voice projection is authored")
	if slow == null or voice == null:
		return
	var actor := _actor()
	var ledger := MindAccess.mastery(actor)
	assert_ne(ledger, null, "attach mints a ledger")
	if ledger == null:
		return
	MindStatusApi.earn_mastery(actor, slow, 5.0)
	var status_key := MindMastery.key_for(slow)
	var voice_key := MindMastery.key_for(voice)
	assert_eq(
		ledger.uses_of(MindMastery.TRACK_STATUS, status_key) > 0.0,
		true,
		"imposing banked the status track"
	)
	assert_almost_eq(
		ledger.uses_of(MindMastery.TRACK_EXPRESSION, voice_key),
		0.0,
		"and projecting was NOT a side effect of it: the two tracks are separate vectors"
	)
	MindStatusApi.earn_mastery(actor, voice, 5.0)
	assert_eq(
		ledger.uses_of(MindMastery.TRACK_EXPRESSION, voice_key) > 0.0,
		true,
		"projecting banked the expression track"
	)
	# And the status entry did not move on the SECOND earn either — a shared counter
	# would have doubled it rather than leaving it.
	assert_almost_eq(
		ledger.uses_of(MindMastery.TRACK_STATUS, status_key),
		5.0,
		"a projection left the status entry exactly where it was"
	)


## ## The two tracks SPEND DIFFERENT CURRENCIES, which is what makes them not reskins
##
## `status` mastery adds to `steepness` (how decisively a contest resolves) and
## `expression` mastery multiplies `harm` (what a projection costs composure). Neither
## moves the other's number: a body deep in the status track projects EXACTLY as hard
## as it did at zero, and a body deep in the expression track wins contests EXACTLY as
## decisively as it did at zero.
##
## The bound on `steepness` is the load-bearing half. It saturates at `1.0`, and
## `MindContest` resolves `clampf(0.5 + edge, 0, 1)` over an `edge` that is itself a
## RATIO in `[-1, 1]` — so even a maxed-out status track cannot make a contest
## CERTAIN. That is the property asserted, and it is the reason a status track can be
## maxed without becoming the hard counter the yin-yang rule forbids.
func test_the_two_tracks_spend_different_currencies_and_neither_moves_the_others_number() -> void:
	var slow := _control(MindVocabulary.SHAPE_SLOW)
	var voice := _expression(MindVocabulary.CHANNEL_VOICE)
	if slow == null or voice == null:
		return
	var state := MindMasteryState.new()
	assert_almost_eq(
		MindMastery.status_bonus(state, MindVocabulary.SHAPE_SLOW),
		0.0,
		"an empty ledger adds no steepness and multiplies no harm"
	)
	assert_almost_eq(
		MindMastery.expression_bonus(state, MindVocabulary.CHANNEL_VOICE),
		1.0,
		"so the expression multiplier starts at the identity"
	)

	# Deep in the STATUS track only.
	for _step in EARN_BOUND * 10:
		state.bank(MindMastery.TRACK_STATUS, MindVocabulary.SHAPE_SLOW, 1.0)
	var steep := MindMastery.status_bonus(state, MindVocabulary.SHAPE_SLOW)
	var harm := MindMastery.expression_bonus(state, MindVocabulary.CHANNEL_VOICE)
	assert_eq(steep > 0.0, true, "a full status track sharpened the contest")
	assert_almost_eq(
		harm, 1.0, "and moved the expression multiplier NOT AT ALL: two currencies, not one"
	)

	# The bound. A saturated status track saturates at `1.0`, not above it, and an
	# `edge` at its ratio ceiling of `1.0` still resolves strictly below 1.0 because
	# the coin-flip NEUTRAL is 0.5. So even the ceiling leaves a gap the target owns.
	assert_almost_eq(
		steep, 1.0, "the status bonus saturates at the bound rather than running past it"
	)
	var landing := MindContest.resolve(slow, 1.0e9, 0.0, null)
	var answer := float(landing.get("p_answer", 0.0))
	assert_eq(answer < 1.0, true, "even a saturating attacker faces a real refusal rate")
	assert_eq(answer > 0.0, true, "and a real one, not a refusal in the other direction either")


# --- the ladder's shape --------------------------------------------------------------


## The two step constants are ONE number and not two. `MindMasteryState.THRESHOLD_STEP`
## is the reader and `MindMastery.THRESHOLD_STEP` is the writer, and two copies of a
## ladder step drift — which is how a reward ladder ends up charging twice as much for
## one track as the other.
func test_the_two_ladder_steps_are_one_number() -> void:
	assert_almost_eq(
		MindMasteryState.THRESHOLD_STEP,
		MindMastery.THRESHOLD_STEP,
		"the ledger's ladder step and the module's banked step are one authored number"
	)


## A restore round trip preserves the ledger, and a MALFORMED entry is dropped rather
## than banked. A ledger that admits `NaN` poisons every level derived from it, and
## every level is a `clampf` that `NaN` survives.
func test_the_ledger_round_trips_and_refuses_a_non_finite_entry() -> void:
	var state := MindMasteryState.new()
	state.bank(MindMastery.TRACK_STATUS, MindVocabulary.SHAPE_INVERT, 7.0)
	var restored := MindMasteryState.from_dict(state.to_dict())
	assert_ne(restored, null, "a payload restores into a ledger")
	if restored == null:
		return
	assert_almost_eq(
		restored.uses_of(MindMastery.TRACK_STATUS, MindVocabulary.SHAPE_INVERT),
		7.0,
		"and the uses survive the round trip"
	)
	var poisoned := {"uses": NAN, "key": "invert", "step": 0, "level": 0.0, "to_next": 0.0}
	var payload := state.to_dict()
	(payload[MindMastery.TRACK_STATUS] as Dictionary)["entries"] = [poisoned]
	var clean := MindMasteryState.from_dict(payload)
	assert_almost_eq(
		clean.uses_of(MindMastery.TRACK_STATUS, MindVocabulary.SHAPE_INVERT),
		0.0,
		"a non-finite use count is dropped rather than banked: NaN survives every clampf"
	)


## ## The vocabulary is CLOSED, and the registration follows it
##
## `Stat.RATE_STATS` is the ONE membership list both content gates read, so the eight
## mind-control ids have to be IN it or a `FLAT` on one validates clean and applies as
## +1000%. This asserts the registration is DERIVED from the vocabulary rather than
## hand-listed, so a shape or channel added later fails here naming the id instead of
## shipping a legal-looking `FLAT` on an unregistered rate.
func test_every_mind_control_stat_is_registered_as_a_rate() -> void:
	var derived: Array[StringName] = []
	for suffix in MindVocabulary.SHAPES + MindVocabulary.CHANNELS:
		derived.append(MindVocabulary.offence_id(suffix))
		derived.append(MindVocabulary.defence_id(suffix))
	for id in derived:
		assert_eq(
			Stat.RATE_STATS.has(id),
			true,
			"%s is published as a rate, so a FLAT on it is refused" % String(id)
		)
	# The positive control, so the loop above is not vacuously true over an empty set.
	assert_eq(derived.size(), 12, "four shapes and two channels, each with a pair of halves")
	# ADR 0215. The assertion used to read `mind_avoidance` is registered, which was
	# true while that stat still carried its `minf(0.6, …)` and was therefore a rate.
	# ADR 0215 deleted the cap and renamed the id to `mind_veil`, so BOTH halves of that
	# fact moved at once: the old spelling is no longer published, and the new one is an
	# unbounded MAGNITUDE rather than a rate — so it correctly LEFT `RATE_STATS` with
	# `mind_clarity`. Asserting the new id here would be asserting the OPPOSITE of what
	# the twelve above prove, which is why this line now pins the retirement instead.
	assert_eq(
		Stat.RATE_STATS.has(&"mind_avoidance"),
		false,
		"and ADR 0215's de-capped, renamed mind pair left the registration list"
	)
	assert_eq(
		Stat.RATE_STATS.has(&"mind_veil"),
		false,
		"mind_veil is an unbounded magnitude, so a FLAT on it is legal content"
	)


## A FLAT on one of the eight is refused BY NAME, and the PERCENT form is accepted —
## the pair that proves the registration is enforcing rather than decorating.
func test_a_flat_on_a_mind_control_rate_is_refused() -> void:
	var probe := MindStatusDef.new()
	probe.id = &"probe_mind_rate"
	probe.display_name = "probe"
	probe.role = MindVocabulary.ROLE_CONTROL
	probe.payload = {
		"shape": MindVocabulary.SHAPE_SLOW,
		"beat": 1.0,
		"floor_resist": 0.5,
		"headroom": 0.3,
		"duration": 3.0,
		"magnitude_cap": 0.4,
		"text": "probe",
		"modifiers":
		[
			{
				"stat": MindVocabulary.defence_id(MindVocabulary.SHAPE_SLOW),
				"op": &"flat",
				"value": 5.0
			}
		],
	}
	# The def's own `_modifier_problems` accepts a legal pair; the RATE gate lives in
	# `StatusDef`, so a mind def asserts the same rule through `Stat.RATE_STATS`
	# membership here rather than by casting itself to a `StatusDef`.
	var id := MindVocabulary.defence_id(MindVocabulary.SHAPE_SLOW)
	assert_eq(Stat.RATE_STATS.has(id), true, "the composure id is a registered rate")
	assert_eq(
		Stat.RATE_STATS.has(MindStatusDef.DEFENCE_PREFIX + "nonsense"),
		false,
		"and an invented one is not"
	)


# --- the provider's published surface -------------------------------------------------


## The eight ids are LIVE on a stock actor — the defect class ADR 0183 fixed for
## `MENTAL_ATTACK`, which read `0.0` on every actor the game could build because mind's
## two base attributes are granted by no shipped race. Without the core fallback these
## would be dead in production while every authored `.tres` looks fine.
func test_the_eight_contest_stats_are_live_on_a_stock_actor() -> void:
	var actor := _actor()
	for suffix in MindVocabulary.SHAPES + MindVocabulary.CHANNELS:
		for id in [MindVocabulary.offence_id(suffix), MindVocabulary.defence_id(suffix)]:
			assert_eq(
				actor.stats.derived(id) > 0.0,
				true,
				(
					(
						"%s reads > 0 on a stock actor, so the contest is not silently reading "
						% String(id)
					)
					+ "nothing (the ADR 0183 defect)"
				)
			)
			assert_eq(
				actor.stats.derived(id) <= 1.0,
				true,
				(
					"and %s stays a RATE: a contest that saturates at 1.0 is a hard counter"
					% String(id)
				)
			)


## The ONE non-symmetry: `intent` — and every OFFENCE half — is answered by
## perception, while the other five DEFENCE halves answer to conviction. A design
## where every counter answered the same attribute would be one axis with six names,
## which is exactly the reskin the design refuses.
func test_intent_is_answered_by_perception_and_the_other_counters_by_conviction() -> void:
	var perceiver := ActorFactory.build(
		&"perceiver", {Stat.WILL: 10.0, MindStats.PERCEPTION: 40.0, Stat.COMPREHENSION: 10.0}
	)
	ActorFactory.with_mind_cultivation(perceiver, RANK)
	var will_built := ActorFactory.build(
		&"will_built", {Stat.WILL: 40.0, MindStats.PERCEPTION: 10.0, Stat.COMPREHENSION: 10.0}
	)
	ActorFactory.with_mind_cultivation(will_built, RANK)
	var perceiver_intent := perceiver.stats.derived(
		MindVocabulary.defence_id(MindVocabulary.CHANNEL_INTENT)
	)
	var will_intent := will_built.stats.derived(
		MindVocabulary.defence_id(MindVocabulary.CHANNEL_INTENT)
	)
	var perceiver_voice := perceiver.stats.derived(
		MindVocabulary.defence_id(MindVocabulary.CHANNEL_VOICE)
	)
	var will_voice := will_built.stats.derived(
		MindVocabulary.defence_id(MindVocabulary.CHANNEL_VOICE)
	)
	assert_eq(perceiver_intent > will_intent, true, "intent tracks perception, not conviction")
	assert_eq(will_voice > perceiver_voice, true, "while voice tracks conviction, not perception")
	assert_eq(
		perceiver_intent > perceiver_voice,
		true,
		(
			"so the two channels ask for different points rather than one attribute "
			+ "twice: a will build has a real gap in its matchup profile"
		)
	)
