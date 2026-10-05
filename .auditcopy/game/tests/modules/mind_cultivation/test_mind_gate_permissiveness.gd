extends TestCase

## Systematic reachability audit, NON-TRIVIALITY half: is every gate the entry
## rules apply actually DISCRIMINATING, or does it quietly always pass?
##
## This is the half of ADR 0029's bug class that a shared-power-ladder deletion
## can produce silently. A gate that compared against a ladder-derived number does
## not fail to compile when that number goes away — it goes permanently open, and
## the whole ladder becomes a formality while every unit test still passes. A gate
## that always passes is worse than one that errors: it hides the retirement.
##
## So at every one of the 29 boundaries each demand must demand MORE than a
## freshly-attached actor standing in that realm happens to have. The companion
## suite `test_mind_reachability.gd` asks the opposite question of the same
## boundaries — is each demand reachable — and both must hold.
##
## Expectations are computed from the code under test and the authored seeds.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## Progress and comprehension start at zero on a bare actor, so any positive demand
## is real work.
const FROM_ZERO: Array[String] = ["progress", "comprehension"]


## Every boundary: progress and comprehension must demand more than a bare actor
## has. Cloned from `FROM_ZERO` per iteration so the loop cannot mutate the const.
func test_progress_and_comprehension_demand_more_than_a_bare_actor_has() -> void:
	var audited := 0
	for realm in RealmDefaults.ladder().realms():
		if RealmDefaults.ladder().next(realm.id) == null:
			continue
		var gates := Probe.gates_at(realm.id)
		for key: String in FROM_ZERO:
			var gate: Dictionary = gates.get(key, {})
			audited += 1
			assert_eq(
				Probe.number(gate, "required") > Probe.number(gate, "value"),
				true,
				(
					"the %s gate into %s demands %s above the bare %s"
					% [
						key,
						realm.id,
						Probe.number(gate, "required"),
						Probe.number(gate, "value"),
					]
				)
			)
	assert_eq(
		audited, Probe.BOUNDARY_COUNT * FROM_ZERO.size(), "every demanded threshold was audited"
	)


## The channel gate must discriminate too: a bare actor's channels are all closed,
## so demanding `strengthened` is real work at every realm.
func test_the_channel_demand_is_above_the_bare_default() -> void:
	var audited := 0
	for realm in RealmDefaults.ladder().realms():
		if RealmDefaults.ladder().next(realm.id) == null:
			continue
		for entry: Dictionary in Probe.gates_at(realm.id).get("channels", []):
			audited += 1
			assert_eq(
				entry.get("met"),
				false,
				(
					"%s is not already %s at a bare %s"
					% [entry.get("id"), entry.get("required"), realm.id]
				)
			)
	assert_eq(audited > 0, true, "the channel gate was audited at every boundary")


## The sea starts EMPTY, so demanding it full is real work too.
func test_the_sea_fill_gate_is_closed_for_a_bare_actor() -> void:
	var audited := 0
	for realm in RealmDefaults.ladder().realms():
		if RealmDefaults.ladder().next(realm.id) == null:
			continue
		var actor := Probe.fresh_actor(realm.id)
		audited += 1
		assert_eq(
			Probe.value_of(actor, "sea_fill") < Probe.required_of(actor, "sea_fill"),
			true,
			"the sea fill gate into %s is closed on an empty reservoir" % realm.id
		)
	assert_eq(audited, Probe.BOUNDARY_COUNT, "every boundary was audited")


## A fresh sea defaults to 0.5 clarity and 0.5 purity, and the shallow realms
## author demands BELOW that, so at R1 a bare actor already clears both. That is
## not a permanently-open gate, because cultivation pins clarity to the realm's own
## target from both sides: raising it stops at the target and lowering it is pulled
## up to it. So the gate converges on exactly the realm's demand however much work
## is done, at every realm — which is what makes the demand a real target rather
## than a default that happens to be higher.
##
## There is no drain here, and that is the point. This test used to empty the sea
## itself before every convergence run, because `cultivate` refused a full
## reservoir — and a full reservoir is the state a real actor reaches first. The
## fixture was doing the player's job, which is exactly why the refusal survived
## a green suite.
func test_cultivation_converges_clarity_and_purity_on_the_realm_targets() -> void:
	for realm in RealmDefaults.ladder().realms():
		if RealmDefaults.ladder().next(realm.id) == null:
			continue
		var seed := MindRealmSeed.for_realm(realm.id)
		# From ABOVE each target: neither may be pushed further by more work.
		var high := Probe.fresh_actor(realm.id)
		var high_sea := MindCultivationApi.sea(high)
		high_sea.set_clarity(minf(1.0, seed.clarity_required))
		high_sea.set_purity(minf(1.0, seed.purity_required))
		MindTraining.cultivate(high, 5000.0)
		assert_almost_eq(
			high_sea.clarity,
			minf(1.0, seed.clarity_required),
			"clarity is capped at %s's own target from above" % realm.id,
			0.0001
		)
		assert_almost_eq(
			high_sea.purity,
			minf(1.0, seed.purity_required),
			"purity is capped at %s's own target from above" % realm.id,
			0.0001
		)
		# From BELOW: cultivation alone lifts each to the target.
		var low := Probe.fresh_actor(realm.id)
		var low_sea := MindCultivationApi.sea(low)
		low_sea.set_clarity(0.0)
		low_sea.set_purity(0.0)
		assert_eq(Probe.sharpen_sea(low), true, "clarity and purity converge at %s" % realm.id)
		assert_almost_eq(
			low_sea.clarity,
			minf(1.0, seed.clarity_required),
			"cultivation lifts clarity to %s's target from below" % realm.id,
			0.0001
		)
		assert_almost_eq(
			low_sea.purity,
			minf(1.0, seed.purity_required),
			"cultivation lifts purity to %s's target from below" % realm.id,
			0.0001
		)


## The tribulation gate is the one gate a bare actor cannot fake, and it must
## genuinely be closed: no tribulation record at all means no survivor, at every
## high tier, and a survivor of ANOTHER realm must not stand in for this one
## (ADR 0032).
func test_the_tribulation_gate_is_closed_until_that_realms_fight_is_won() -> void:
	for realm in RealmDefaults.ladder().realms():
		var target := RealmDefaults.ladder().next(realm.id)
		if target == null or target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
			continue
		var actor := Probe.fresh_actor(realm.id)
		assert_eq(
			Breakthrough.tribulation_ok(actor, target.index),
			false,
			"the tribulation gate into %s is closed on a bare actor" % target.id
		)
		Probe.fight(actor, Probe.realm_at(target.index - 1))
		assert_eq(
			Breakthrough.tribulation_ok(actor, target.index),
			false,
			"a survivor of the previous realm does not open the gate into %s" % target.id
		)
		Probe.fight(actor, target)
		assert_eq(
			Breakthrough.tribulation_ok(actor, target.index),
			true,
			"the fight for %s itself opens its own gate" % target.id
		)


## The anchor gate must discriminate at every high tier that names a stage. The
## three realms that COMMIT an anchor name STAGE_NONE and demand nothing — that is
## the deliberate non-circularity — so they are checked for the absence of a
## demand and every other high tier for a real one.
func test_the_anchor_gate_is_closed_until_a_prior_realm_commits_one() -> void:
	var demanded := 0
	var committing := 0
	for realm in RealmDefaults.ladder().realms():
		var target := RealmDefaults.ladder().next(realm.id)
		if target == null or target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
			continue
		var stage := MindAnchor.required_stage(target.index)
		var actor := Probe.fresh_actor(realm.id)
		if stage == MindAnchor.STAGE_NONE:
			committing += 1
			assert_eq(
				Breakthrough.can_advance(actor, MindPath.PATH_ID, MindBreakthroughCondition.new()),
				false,
				"entering %s is not open on a bare actor just because it commits one" % target.id
			)
			continue
		demanded += 1
		assert_eq(
			MindAnchor.stage_met(actor, stage),
			false,
			"the %s anchor demanded into %s is absent on a bare actor" % [stage, target.id]
		)
	assert_eq(
		demanded + committing,
		RealmDefaults.ladder().realms().size() - Breakthrough.IMMORTAL_REALM_THRESHOLD,
		"every high-tier boundary was audited"
	)
	assert_eq(committing > 0, true, "some realms commit an anchor without demanding one")


## No boundary may be open on a bare actor's defaults alone. This is the assertion
## that would catch a gate quietly going always-true: individual gates may be
## satisfiable for free, but not all of them at once.
func test_no_boundary_is_open_on_the_bare_default() -> void:
	for realm in RealmDefaults.ladder().realms():
		var target := RealmDefaults.ladder().next(realm.id)
		if target == null:
			continue
		var actor := Probe.fresh_actor(realm.id)
		assert_eq(
			MindAdvancement.preview(actor).get("ready"),
			false,
			"entry into %s is not open on defaults alone" % target.id
		)


## The sea-fill demand must stay a REAL fraction rather than decaying to zero as
## the capacity ladder grows. A demand of 0.0 would mean "the sea need not be full"
## and would silently retire the fill milestone at every realm.
func test_the_sea_fill_demand_stays_a_meaningful_fraction() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		assert_eq(
			seed.sea_fill_required > 0.0,
			true,
			"the sea fill demand at %s is a real fraction, not zero" % realm.id
		)
