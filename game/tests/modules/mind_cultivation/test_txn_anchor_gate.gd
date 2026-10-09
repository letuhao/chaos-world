extends TestCase

## The Mind anchor trial was VACUOUS, and the proof is that no test could have
## caught it: the commit that created the anchor also stamped the trial flag the
## very next realm's gate asked for, so the gate was satisfied by the breakthrough
## it was gating.
##
## `test_no_commit_can_satisfy_any_demanded_anchor_stage` is the assertion that
## could not have existed before: it commits EVERY high-tier milestone against a
## bare actor and requires every demanded stage to stay shut. It needs no
## knowledge of the schedule, so re-pointing `required_stage` at a different
## milestone cannot hide a self-satisfying gate again.
##
## The satisfiability half matters as much — a gate no commit can open is a
## soft-lock, not a difficulty — so the suite also walks the high tier the way the
## real path does it (fight, advance, commit, take the resonance milestone) and
## requires every demanded stage to open.
##
## Expectations are read from the module (`MindAnchor.required_stage`, the gate
## inputs `preview` publishes), never restated.

## One realm of the ladder is one boundary; 30 realms make 29 transitions.
const LADDER_SIZE := 30

## Cultivate steps one boundary may take before the fixture gives up. Small on
## purpose: a big cap on a wait whose exit condition cannot be met is just a
## slower disk fill. Every use asserts the condition it was waiting on, so
## hitting this cap fails the suite loudly instead of spinning.
const CULTIVATE_CAP := 128

## Steps one meridian may take up the four-state channel ladder. A channel at
## the bottom needs three to reach `strengthened`, plus one that confirms it.
const CLIMB_CAP := 8


## Every stage the policy can name. Built per call rather than in a `const` so a
## stage added to `MindAnchor` without coverage here shows up as a missing case
## instead of silently shrinking the audit.
func _stages() -> Array[StringName]:
	return [
		MindAnchor.STAGE_NONE,
		MindAnchor.STAGE_SEED_ANCHOR,
		MindAnchor.STAGE_POCKET_ANCHOR,
		MindAnchor.STAGE_INNER_ANCHOR,
		MindAnchor.STAGE_MICRO_WORLD,
	]


const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


func _bare() -> Actor:
	var actor := Actor.new(&"txn_anchor_hero", {Stat.COMPREHENSION: 0.0, Stat.WILL: 0.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, _realm_at(0).id))
	actor.meridians.unlock_for_realm(_realm_at(0).id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	return actor


func _at(rank_id: StringName) -> Actor:
	var actor := Actor.new(&"txn_anchor_hero", {Stat.COMPREHENSION: 0.0, Stat.WILL: 50.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 500)
	MindTraining.synchronize(actor)
	# BL-0951: a fixture standing at `rank_id` implies it LEFT every realm below it; backfill
	# the history a real climb would have snapshotted, or the foundation wall refuses.
	Probe.backfill_foundation(actor)
	return actor


func _realm_at(index: int) -> RealmDef:
	return RealmDefaults.ladder().realms()[index]


func _stock(actor: Actor, def_id: StringName) -> void:
	if def_id.is_empty():
		return
	var def := Crafting.resolve(def_id)
	if def == null:
		return
	var guard := 0
	while not ItemsApi.has_item(actor, def_id) and guard < 64:
		ItemsApi.inventory(actor).add(def, 1)
		guard += 1


## Fight and win the tribulation bound to `target`, through the production entry
## points. Finishing the phases is not enough: a gate opens only for a decided win.
func _fight(actor: Actor, target: RealmDef) -> void:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	var guard := 0
	while Breakthrough.advance_tribulation(actor) and guard < 128:
		guard += 1
	Breakthrough.resolve_tribulation(actor, true)


## The resonance milestone, which is what pays for an anchor's reinforcement.
##
## Paid ONCE per committed anchor: ADR 0115 made the reinforcement flag the
## milestone itself, so a boundary that crosses no new commit is pressing one the
## actor already paid and the press is refused for free. Both branches assert, so a
## walk that stopped reinforcing at all would fail here rather than pass quietly.
func _reinforce(actor: Actor) -> void:
	var state := actor.path(MindPath.PATH_ID)
	if state == null or actor.inside_world == null:
		return
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return
	_stock(actor, seed.training_item)
	if MindTraining.anchor_reinforced(actor):
		assert_eq(MindTraining.strengthen_anchor(actor), false, "an already-paid milestone refuses")
	else:
		assert_eq(MindTraining.strengthen_anchor(actor), true, "the resonance milestone completed")


## One realm of the high tier, the way the real path does it: fight the
## tribulation bound to that realm, advance into it, commit the anchor it creates,
## then take the milestone that reinforces it.
func _walk_high_tier(actor: Actor, target_index: int) -> void:
	var target := _realm_at(target_index)
	_fight(actor, target)
	Breakthrough.try_advance(actor, MindPath.PATH_ID)
	MindAnchor.commit(actor, target_index)
	_reinforce(actor)


## Enter every tier up to `target_index` and commit each milestone, WITHOUT paying
## the reinforcement. That is the pre-state a player legally holds one realm after
## the commit, and it is the state the defect made indistinguishable from a paid one.
func _walk_without_reinforcing(actor: Actor, target_index: int) -> void:
	for earlier in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, target_index):
		var target := _realm_at(earlier)
		_fight(actor, target)
		Breakthrough.try_advance(actor, MindPath.PATH_ID)
		MindAnchor.commit(actor, earlier)


# --- The defect: the gate is not its own outcome ------------------------------


## Every high-tier boundary is probed against EVERY commit index, so the claim does
## not depend on knowing which realm commits which milestone: whatever the schedule
## says, no milestone commit may open any demanded stage.
func test_no_commit_can_satisfy_any_demanded_anchor_stage() -> void:
	var ladder := RealmDefaults.ladder()
	var demanded := 0
	var committing := 0
	var probes := 0
	for target_index in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, ladder.realms().size()):
		var stage := MindAnchor.required_stage(target_index)
		if stage == MindAnchor.STAGE_NONE:
			committing += 1
			continue
		demanded += 1
		for commit_index in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, ladder.realms().size()):
			var actor := _bare()
			MindAnchor.commit(actor, commit_index)
			probes += 1
			assert_eq(
				MindAnchor.stage_met(actor, stage),
				false,
				(
					"the %s stage demanded into %s stays shut after commit(%d)"
					% [stage, _realm_at(target_index).id, commit_index]
				)
			)
	assert_eq(
		demanded + committing,
		LADDER_SIZE - Breakthrough.IMMORTAL_REALM_THRESHOLD,
		"every high-tier boundary was audited"
	)
	assert_eq(committing > 0, true, "some realms commit an anchor without demanding one")
	assert_eq(probes > demanded, true, "each demanded stage was probed against every commit")


## The narrower sentence the defect broke, stated per milestone: the realm that
## commits an anchor does not open the gate its band demands.
func test_committing_a_tier_does_not_open_that_band_s_gate() -> void:
	var ladder := RealmDefaults.ladder()
	for commit_index in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, ladder.realms().size()):
		var actor := _bare()
		MindAnchor.commit(actor, commit_index)
		for target_index in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, ladder.realms().size()):
			var stage := MindAnchor.required_stage(target_index)
			if stage == MindAnchor.STAGE_NONE:
				continue
			assert_eq(
				MindAnchor.stage_met(actor, stage),
				false,
				(
					"a lone commit(%d) leaves the %s stage shut for %s"
					% [commit_index, stage, _realm_at(target_index).id]
				)
			)


## The gate is reachable, and only through a separately paid act. A gate no commit
## can open is a soft-lock, not a difficulty, so the satisfiability half is proved
## from the same production actions the real path uses.
func test_the_anchor_stage_is_reachable_through_production_actions_only() -> void:
	var ladder := RealmDefaults.ladder()
	var opened := 0
	for target_index in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, ladder.realms().size()):
		var stage := MindAnchor.required_stage(target_index)
		if stage == MindAnchor.STAGE_NONE:
			continue
		var actor := _at(_realm_at(MindAnchor.COMMIT_SEED - 1).id)
		for earlier in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, target_index):
			_walk_high_tier(actor, earlier)
		assert_eq(
			MindAnchor.stage_met(actor, stage),
			true,
			(
				"the %s stage demanded into %s is earned by playing the earlier tiers"
				% [stage, _realm_at(target_index).id]
			)
		)
		opened += 1
	assert_eq(opened > 0, true, "at least one boundary demands a stage")


## The same walk without the milestone leaves the gate shut at every high-tier
## boundary that demands one. This is the pre-state a player can legally hold —
## every other milestone paid — so it is a fresh legal actor failing the trial.
func test_the_trial_fails_until_the_reinforcement_milestone_is_paid() -> void:
	var ladder := RealmDefaults.ladder()
	var closed := 0
	for target_index in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, ladder.realms().size()):
		var stage := MindAnchor.required_stage(target_index)
		if stage == MindAnchor.STAGE_NONE:
			continue
		var actor := _at(_realm_at(MindAnchor.COMMIT_SEED - 1).id)
		_walk_without_reinforcing(actor, target_index)
		assert_eq(
			MindAnchor.stage_met(actor, stage),
			false,
			(
				"committing every earlier tier without the milestone leaves %s shut for %s"
				% [stage, _realm_at(target_index).id]
			)
		)
		_reinforce(actor)
		assert_eq(
			MindAnchor.stage_met(actor, stage),
			true,
			"and the milestone alone opens it: %s for %s" % [stage, _realm_at(target_index).id]
		)
		closed += 1
	assert_eq(closed > 0, true, "every demanding boundary was tested both ways")


# --- A real pre-state, not a forged one --------------------------------------


## Everything an R19 actor owes R20 EXCEPT the anchor is satisfied through
## production actions only, and R20 still refuses. This is the defect as a player
## meets it: the realm that committed the Seed anchor stands one step from the gate
## that anchor was supposed to open, and the gate is shut.
func test_a_legal_pre_state_in_r19_cannot_enter_r20_on_the_commit_alone() -> void:
	var actor := _entered_r19()
	var gate: Dictionary = MindAdvancement.preview(actor).get("gates", {}).get("anchor", {})
	assert_eq(gate.get("required"), true, "R20 demands an anchor stage")
	assert_eq(gate.get("value"), false, "and the Seed anchor the R19 commit left is not enough")
	assert_ne(String(gate.get("outstanding", "")), "", "the report names what is outstanding")
	assert_eq(
		MindAdvancement.start(actor), null, "the attempt is refused while the trial is unpaid"
	)

	_reinforce(actor)
	assert_eq(
		MindAdvancement.preview(actor).get("ready"),
		true,
		"paying the milestone opens R20 and nothing else changed"
	)
	assert_ne(MindAdvancement.start(actor), null, "and the attempt is accepted")


## The unpaid anchor is the ONLY thing outstanding in that pre-state, or the test
## above proves less than it claims: a refused attempt could have been refused for
## any of the other conditions.
func test_the_unpaid_anchor_is_the_only_outstanding_condition_in_r19() -> void:
	var actor := _entered_r19()
	var report := MindAdvancement.preview(actor)
	var conditions: Array = report.get("conditions", [])
	var gate: Dictionary = report.get("gates", {}).get("anchor", {})
	assert_eq(conditions.size(), 1, "exactly one condition is outstanding: the anchor")
	assert_eq(
		String(conditions[0]),
		String(gate.get("outstanding", "")),
		"preview reports the shortfall MindAnchor named, not the bare rule"
	)
	assert_eq(report.get("ready"), false, "so R20 is shut")


## An actor that legitimately REACHED R19 — every R18 milestone paid, the R19
## tribulation won and the R19 breakthrough resolved through the public entry
## points — and has then paid everything R20 asks of it except the anchor
## milestone. The anchor milestone is deliberately left unpaid: that is the
## condition under test, and paying everything else is what makes the refusal
## attributable to the anchor alone.
func _entered_r19() -> Actor:
	var r19 := MindAnchor.COMMIT_SEED
	var actor := _at(_realm_at(r19 - 1).id)
	_prepare_boundary(actor, r19 - 1, r19)
	var chance := float(MindAdvancement.preview(actor).get("chance", -1.0))
	var rng := _winning(chance)
	assert_ne(MindAdvancement.start(actor, rng), null, "the R19 attempt starts")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "and the R19 breakthrough resolves")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, _realm_at(r19).id, "so the actor stands in R19")
	assert_eq(
		actor.inside_world.tier,
		InsideWorld.SEED,
		"and the R19 breakthrough committed the Seed anchor"
	)
	_prepare_boundary(actor, r19, r19 + 1)
	return actor


## The first roll of an rng seeded `candidate` that beats `chance`, searched rather
## than hoped for. `resolve_attempt` draws once off a generator rebuilt from the
## seed the COMMIT stored, so this asks exactly the module's own question: the seed
## that wins follows from the chance the module published rather than from a number
## copied out of a previous run. Bounded and RETURNING.
func _winning(chance: float) -> RandomNumberGenerator:
	for candidate in range(MindAttemptRoll.MIN_SEED, 256):
		if MindAttemptRoll.replay(candidate).randf() < chance:
			var rng := RandomNumberGenerator.new()
			rng.seed = candidate
			return rng
	return RandomNumberGenerator.new()


## Everything the boundary from `source_index` to `target_index` asks of an actor
## standing in the source realm, paid through the actions a player has: the source
## realm's sea and channel milestones, the tribulation for the target, and the
## target's progress budget and comprehension floor earned by cultivating. The
## ANCHOR milestone is deliberately not among them.
func _prepare_boundary(actor: Actor, source_index: int, target_index: int) -> Actor:
	var source := _realm_at(source_index)
	var target := _realm_at(target_index)
	var state := actor.path(MindPath.PATH_ID)
	var source_seed := MindRealmSeed.for_realm(source.id)
	var target_seed := MindRealmSeed.for_realm(target.id)

	actor.meridians.unlock_for_realm(target.id)
	var wanted: int = MeridianState.STATE_ORDER.get(source_seed.required_channel_state, 0)
	for meridian_id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		# Bounded, and the bound is a canary for a channel that stops climbing:
		# `train_channel` consumes one elixir per step and reports success by
		# consuming it, so a state that never changes would otherwise spend
		# elixirs forever with no way out. A channel walks a four-state ladder,
		# so a handful of steps is ample and anything more names a real fault.
		var climbs := 0
		while MeridianState.STATE_ORDER.get(channel.state, 0) < wanted and climbs < CLIMB_CAP:
			climbs += 1
			_stock(actor, source_seed.training_item)
			if not MindTraining.train_channel(actor, meridian_id):
				break
			channel = actor.meridians.get_meridian(meridian_id)
		assert_eq(
			MeridianState.STATE_ORDER.get(channel.state, 0) >= wanted,
			true,
			(
				"channel %s reaches %s for %s"
				% [meridian_id, source_seed.required_channel_state, source.id]
			)
		)

	_stock(actor, source_seed.sea_catalyst)
	MindTraining.strengthen_sea(actor)
	_fight(actor, target)

	var sea := MindCultivationApi.sea(actor)
	var guard := 0
	while (
		guard < CULTIVATE_CAP
		and (
			state.progress < target_seed.progress_required
			or actor.stats.derived(Stat.COMPREHENSION) < target_seed.comprehension_required
		)
	):
		guard += 1
		# `cultivate` trains through a full sea and `fill` clamps, so the budget is
		# earnable straight off a full reservoir. Draining here would hide the very
		# refusal that deadlocked this path once.
		if not MindTraining.cultivate(actor, 500.0):
			break
	assert_eq(
		state.progress >= target_seed.progress_required,
		true,
		"the progress budget for %s is earned in %s" % [target.id, source.id]
	)
	assert_eq(
		actor.stats.derived(Stat.COMPREHENSION) >= target_seed.comprehension_required,
		true,
		"the comprehension floor for %s is earned in %s" % [target.id, source.id]
	)
	# The reservoir is topped off last, because entry also requires it full.
	guard = 0
	while not sea.is_full(actor) and guard < CULTIVATE_CAP:
		guard += 1
		if not MindTraining.cultivate(actor, 500.0):
			break
	assert_eq(sea.is_full(actor), true, "the reservoir for %s is filled" % target.id)
	_stock(actor, target_seed.breakthrough_item)
	return actor


## The outstanding report and the gate must never disagree: `stage_met` decides,
## `outstanding` explains. A screen cannot render a milestone it cannot describe,
## and it cannot describe one it is not being asked about.
func test_the_outstanding_report_agrees_with_the_gate_at_every_stage() -> void:
	var actor := _at(_realm_at(MindAnchor.COMMIT_SEED - 1).id)
	MindAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	for stage in _stages():
		var met := MindAnchor.stage_met(actor, stage)
		var outstanding := MindAnchor.outstanding(actor, stage)
		assert_eq(
			met,
			stage == MindAnchor.STAGE_NONE,
			(
				"only the un-demanded stage is met after one commit: %s"
				% MindAnchor.describe_stage(stage)
			)
		)
		assert_eq(
			outstanding == "",
			met,
			(
				"the report is silent exactly when the gate is met: %s"
				% MindAnchor.describe_stage(stage)
			)
		)
		assert_ne(MindAnchor.describe_stage(stage), "", "every stage is describable")
	assert_eq(
		MindAnchor.outstanding(_bare(), MindAnchor.STAGE_NONE),
		"",
		"no stage is ever outstanding on an actor that owes nothing"
	)
