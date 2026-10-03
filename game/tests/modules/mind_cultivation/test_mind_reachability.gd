extends TestCase

## Systematic reachability audit, SATISFIABILITY half: is every gate the entry
## rules apply reachable from a legal pre-state standing in the SOURCE realm?
##
## ADR 0029 records the bug class twice, both times on this module:
##   1. the entry condition compared the sea against the TARGET realm's targets,
##      so R1 -> R2 was unreachable because `strengthen_sea` in R1 maxes clarity at
##      0.40 while R2 demanded 0.42;
##   2. a gate required the outcome of the attempt it was gating.
##
## A per-gate unit test cannot catch either: every gate passes on its own while
## the ladder as a whole stops being traversable. The whole-ladder walk in
## `test_full_traversal.gd` is the proof that it IS traversable; this suite is what
## makes the coverage systematic rather than incidental, by asking every one of
## the 29 boundaries the same question and reading the requirements out of the
## module rather than restating them.
##
## The other half — is each demand actually DISCRIMINATING, or does it quietly
## always pass — is `test_mind_gate_permissiveness.gd`.
##
## Every expectation is computed from the code under test and the authored seeds.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


func test_every_boundary_on_the_ladder_is_audited() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		if ladder.next(realm.id) == null:
			continue
		assert_ne(Probe.gates_at(realm.id).is_empty(), true, "gates reported at %s" % realm.id)
		audited += 1
	assert_eq(audited, Probe.BOUNDARY_COUNT, "every boundary between the 30 realms was audited")


## The whole point of reading the SOURCE realm's milestones (ADR 0029): while
## standing in realm R the sea can be brought to exactly R's clarity and purity
## targets and no further, so R+1 must not demand more of them than R grants. The
## required value is read off the module's own report, so this fails if the gate
## ever starts comparing against the target realm again.
func test_clarity_and_purity_demand_never_exceed_what_the_source_realm_grants() -> void:
	for realm in RealmDefaults.ladder().realms():
		if Probe.gates_at(realm.id).is_empty():
			continue
		var source_seed := MindRealmSeed.for_realm(realm.id)
		var actor := Probe.prepared(realm.id)
		for key: String in ["clarity", "purity"]:
			assert_eq(
				Probe.required_of(actor, key),
				source_seed.get(key + "_required"),
				"%s reads the source realm's own milestone, not the target's" % key
			)
			assert_eq(
				Probe.required_of(actor, key) <= 1.0,
				true,
				"%s demand at %s is inside the sea's own 0..1 range" % [key, realm.id]
			)
		assert_eq(
			Probe.value_of(actor, "clarity") >= Probe.required_of(actor, "clarity"),
			true,
			"clarity reachable at %s" % realm.id
		)
		assert_eq(
			Probe.value_of(actor, "purity") >= Probe.required_of(actor, "purity"),
			true,
			"purity reachable at %s" % realm.id
		)


## Progress and comprehension ARE genuinely the target's own demands — progress
## resets to zero on every advance, so each budget must be earned again from
## nothing, and comprehension only ever accrues through cultivation. Both must be
## reachable while standing in the source realm.
func test_the_targets_own_progress_and_comprehension_are_earnable() -> void:
	for realm in RealmDefaults.ladder().realms():
		var target := RealmDefaults.ladder().next(realm.id)
		if target == null:
			continue
		var target_seed := MindRealmSeed.for_realm(target.id)
		var actor := Probe.prepared(realm.id)
		assert_eq(
			Probe.value_of(actor, "progress") >= target_seed.progress_required,
			true,
			"the progress budget for %s is earned while in %s" % [target.id, realm.id]
		)
		assert_eq(
			Probe.value_of(actor, "comprehension") >= target_seed.comprehension_required,
			true,
			"the comprehension floor for %s is earned while in %s" % [target.id, realm.id]
		)


## The sea-fill demand is a fraction of capacity, so anything above 1.0 would be a
## gate no pre-state could ever satisfy.
func test_the_sea_fill_demand_is_a_reachable_fraction() -> void:
	for realm in RealmDefaults.ladder().realms():
		if RealmDefaults.ladder().next(realm.id) == null:
			continue
		var actor := Probe.prepared(realm.id)
		assert_eq(
			Probe.required_of(actor, "sea_fill") <= 1.0,
			true,
			"the sea fill demand at %s is a fraction of capacity" % realm.id
		)
		assert_eq(
			Probe.value_of(actor, "sea_fill") >= Probe.required_of(actor, "sea_fill"),
			true,
			"the sea is filled to the demand at %s" % realm.id
		)


## The channels the gate names must be trainable while standing in the source
## realm. A channel unlocked only by the advance itself would be a circular
## prerequisite, so eligibility is checked against a network unlocked for the
## SOURCE realm and attainment against a fully trained source-realm actor.
func test_required_channels_are_trainable_from_the_source_realm() -> void:
	for realm in RealmDefaults.ladder().realms():
		var target := RealmDefaults.ladder().next(realm.id)
		if target == null:
			continue
		var source_seed := MindRealmSeed.for_realm(realm.id)
		var network := MeridianNetwork.new()
		network.unlock_for_realm(realm.id)
		for meridian_id in source_seed.required_meridians:
			assert_ne(
				network.get_meridian(meridian_id),
				null,
				"%s is unlocked while standing in %s" % [meridian_id, realm.id]
			)
		var actor := Probe.prepared(realm.id)
		var channels: Array = Probe.gate(actor, "channels")
		assert_eq(channels.is_empty(), false, "channels reported at %s" % realm.id)
		for entry: Dictionary in channels:
			assert_eq(
				entry.get("met"),
				true,
				(
					"%s trained to %s for the gate into %s"
					% [entry.get("id"), entry.get("required"), target.id]
				)
			)


## The anchor gate, read from the module's own stage policy rather than restated:
## a demanded stage must be openable by committing PREVIOUSLY, through the
## production entry points, in ladder order. A boundary that demanded the anchor
## its own attempt creates is ADR 0029's second form and is unreachable forever.
func test_the_anchor_demand_is_satisfiable_from_prior_commitments() -> void:
	for realm in RealmDefaults.ladder().realms():
		var target := RealmDefaults.ladder().next(realm.id)
		if target == null:
			continue
		var stage := MindAnchor.required_stage(target.index)
		var anchor: Dictionary = Probe.gates_at(realm.id).get("anchor", {})
		assert_eq(
			anchor.get("required"),
			stage != MindAnchor.STAGE_NONE,
			"an anchor is demanded into %s only when a stage is named" % target.id
		)
		assert_eq(
			anchor.get("stage"), String(stage), "%s is the stage named for the gate" % target.id
		)
		if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
			assert_eq(stage, MindAnchor.STAGE_NONE, "no anchor below the Immortal tier")
			continue
		var actor := Probe.prepared(realm.id)
		# Walked in ladder order and STOPPED the moment this boundary's own demand is
		# earned. Walking on past it is not extra proof: a later tier's commit
		# REPLACES the inside world this demand reads (`MindAnchor._commit_inside_world`
		# builds a fresh world at the new tier), so the walk would destroy the stage it
		# had already paid for and fail a boundary whose gate is in fact satisfiable.
		# The ladder as a whole is `test_full_traversal.gd`'s claim; this one asks
		# whether THIS gate can be opened by committing earlier tiers.
		for earlier in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, target.index):
			Probe.walk_high_tier(actor, earlier)
			if MindAnchor.stage_met(actor, stage):
				break
		assert_eq(
			stage == MindAnchor.STAGE_NONE or MindAnchor.stage_met(actor, stage),
			true,
			"the %s anchor demanded into %s is committed by an EARLIER realm" % [stage, target.id]
		)
		# And the tribulation bound to THIS realm is winnable beforehand. Fought
		# last, and read through `tribulation_ok` rather than `preview`: walking
		# the earlier tiers moved the actor's rank on, so `preview` would now be
		# describing a later boundary than the one being audited.
		Probe.fight(actor, target)
		assert_eq(
			Breakthrough.tribulation_ok(actor, target.index),
			true,
			"the tribulation for %s is winnable before the attempt" % target.id
		)


## No authored threshold may exceed what the code it feeds can represent. The sea
## clamps clarity and purity to 0..1 and the reservoir is a fraction, so a seed
## demanding more than that is permanently unsatisfiable — a gate that fails
## silently rather than loudly.
func test_no_authored_threshold_exceeds_the_clamp_of_what_it_measures() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		assert_ne(seed, null, "seed for %s" % realm.id)
		for key: String in ["clarity_required", "purity_required"]:
			assert_eq(
				float(seed.get(key)) <= 1.0,
				true,
				"%s at %s fits the sea's own 0..1 clamp" % [key, realm.id]
			)
		assert_eq(
			seed.sea_fill_required <= 1.0,
			true,
			"sea_fill_required at %s is a fraction of capacity" % realm.id
		)
		assert_eq(seed.sea_capacity > 0.0, true, "sea_capacity at %s is positive" % realm.id)
		assert_eq(
			seed.progress_required > 0.0, true, "progress_required at %s is positive" % realm.id
		)


## Progress resets to zero on every advance, so the price of a breakthrough —
## `progress_required` converted at the rate it is spent in — must rise strictly
## with depth. Progress is the only gate that fully resets, so this is the one
## place a regression makes the deep realms cheaper than the shallow ones.
func test_the_price_of_a_breakthrough_rises_strictly_with_depth() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous_price := 0.0
	var priced := 0
	for index in range(1, realms.size()):
		var target := realms[index]
		var below := realms[index - 1]
		var price := (
			MindRealmSeed.for_realm(target.id).progress_required / RealmRate.factor(below.id)
		)
		assert_eq(
			price > previous_price,
			true,
			"%s costs %s work-units, more than %s's" % [target.id, price, below.id]
		)
		previous_price = price
		priced += 1
	assert_eq(priced, Probe.BOUNDARY_COUNT, "every boundary was priced")


## The rate must not outrun the budget it converts, or cultivation work buys more
## than the realm's own price says. The first transition sets the baseline and has
## no predecessor realm to be cheaper than, and mind's R1 and R2 budgets are
## authored equal, so the comparison starts at the second — the boundary the
## power-curve suite documents for the same reason.
func test_the_rate_step_never_outruns_the_budget_step_it_converts() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous_rate := 0.0
	var previous_budget := 0.0
	var checked := 0
	for index in range(1, realms.size()):
		var budget := MindRealmSeed.for_realm(realms[index].id).progress_required
		var rate := RealmRate.factor(realms[index].id)
		if checked > 0:
			assert_eq(
				rate / previous_rate <= budget / previous_budget,
				true,
				"the rate step stays within the budget step at %s" % realms[index].id
			)
		previous_rate = rate
		previous_budget = budget
		checked += 1
	assert_eq(checked, Probe.BOUNDARY_COUNT, "every transition was walked")
