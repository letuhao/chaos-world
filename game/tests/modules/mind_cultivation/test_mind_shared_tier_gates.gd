extends TestCase

## Mind did not share one high-tier gate with body and qi, and WHICH relationship it
## had to them is not answerable from names: `MindAnchor.stage_met` and
## `Breakthrough.tier_gates_met` read like one idea written twice, so the fork was
## whether one is a subset of the other, a superset, or orthogonal — and that decides
## whether collapsing mind onto the shared schedule DELETES a requirement or merely
## ADDS one. It was measured, not inferred:
##
##   - NOT a superset. Where `MindAnchor` commits an anchor it names STAGE_NONE, so its
##     gate is open on a bare actor at exactly the boundaries where the shared
##     schedule is shut: `test_minds_stage_demands_less_than_the_shared_schedule`.
##   - NOT a subset. `ascension_ok` has no term in `MindAnchor` at all, and the clause
##     that DOES distinguish it — the anchor REINFORCED — is one the shared schedule
##     has no term for either: `test_the_two_schedules_disagree_in_opposite_directions_on_one_actor`
##     has the shared gate open where MindAnchor is shut, and the reverse two tiers down.
##   - ORTHOGONAL in kind: one gates on a walked ritual and named laws, the other on a
##     physiological milestone paid with a channel elixir. Neither names the other's
##     artifacts, so the honest shape is BOTH — never one in place of the other.
##
## So the change is additive, not a substitution. ADR 0024 delegated the ANCHOR clause
## to `MindAnchor` and nothing else ("Tier gates stay in core. Qi and Body call
## `Breakthrough.tier_gates_met`"), and the condition had gone on to delegate all four
## to it. `test_a_mind_actor_at_index_28_*` is the enumeration that decided it, and
## `test_walking_the_ascent_opens_*` is the half that says the added gate is walkable
## rather than a soft-lock.

## Every fixture and every bounded wait lives in `mind_gate_probe.gd`. This file
## re-walks the high tier through those production actions because the PRE-STATE is
## the measurement: a forged actor would answer a different question.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## Seeds searched for one that beats the published chance. `resolve_attempt` draws
## once off a generator rebuilt from the seed the COMMIT stored, so the winning seed
## follows from the chance the module published rather than from a number copied out
## of an earlier run.
const SEED_GUARD := 64

## Steps one meridian may take up the four-state channel ladder: three to reach
## `strengthened` from the bottom, plus the one that confirms it.
const CLIMB_CAP := 8

## The ladder index this file measures around, read from core's own threshold rather
## than written out, so a retuned schedule cannot leave this file asserting a boundary
## that moved. `COMMIT_MICRO` is the realm that commits the created world and BEGINS the
## ascent; the boundary above it is the first one whose gate reads that ascent.
const SOURCE := WorldAnchor.COMMIT_MICRO
const TARGET := WorldAnchor.COMMIT_MICRO + 1

## The first boundary that demands a Reinforced anchor, and the one that commits it.
const SEED_GATE := MindAnchor.COMMIT_SEED + 1
const SEED_COMMIT := MindAnchor.COMMIT_SEED

## The gates this module publishes under the same keys body publishes them under.
const SHARED_GATES: Array[String] = ["tribulation", "inside_world", "world", "ascent"]

## The climb is expensive and several tests want the same pre-state, so one actor per
## boundary is cached. Tests that ADVANCE or void anything take a fresh one instead, so
## a mid-transition actor is never handed to the next test.
static var _stands: Dictionary = {}

# --- The relationship, measured -------------------------------------------------


## Mind demands LESS than the shared schedule at the tiers where it commits an anchor,
## which is what rules out "superset". The shared schedule gates those two boundaries
## on the previous tier's inside world; `required_stage` names STAGE_NONE there, so the
## same bare actor is shut by one policy and open by the other.
func test_minds_stage_demands_less_than_the_shared_schedule() -> void:
	var committing := 0
	for index in [MindAnchor.COMMIT_POCKET, MindAnchor.COMMIT_INNER]:
		var bare := Probe.fresh_actor(Probe.realm_at(index - 1).id)
		assert_eq(
			Breakthrough.inside_world_ok(bare, index),
			false,
			"the shared schedule demands the previous inside world into index %d" % index
		)
		assert_eq(
			Breakthrough.tier_gates_met(bare, index),
			false,
			"so a bare actor is shut by the shared schedule at index %d" % index
		)
		assert_eq(
			MindAnchor.required_stage(index),
			MindAnchor.STAGE_NONE,
			"while MindAnchor names no stage at index %d, because it commits one there" % index
		)
		assert_eq(
			MindAnchor.stage_met(bare, MindAnchor.required_stage(index)),
			true,
			"so the same actor is OPEN by MindAnchor at index %d" % index
		)
		committing += 1
	assert_eq(committing, 2, "both anchoring commit tiers were audited")


## The two schedules disagree in OPPOSITE directions on the same actor, which is the
## whole "orthogonal, not subset and not superset" claim in one comparison.
##
## Into the Seed boundary the SHARED schedule says yes and MindAnchor says no: the
## shared commit imprints the law the shared gate reads, but it must not reinforce the
## anchor, because reinforcement is the one clause a commit may never grant — it is
## what the next realm's gate demands, and `Breakthrough.try_advance` runs that commit
## for every path. Into the Pocket boundary the reverse: the shared schedule demands
## the Seed inside world and MindAnchor names no stage at all.
##
## Restoring the `strengthen_anchor()` line in `WorldAnchor._commit_inside_world` is
## what turns the first half of this red, and it is the regression that made the mind
## anchor gate decorative.
func test_the_two_schedules_disagree_in_opposite_directions_on_one_actor() -> void:
	var shared_commit := Probe.fresh_actor(Probe.realm_at(SEED_COMMIT).id)
	WorldAnchor.commit(shared_commit, SEED_COMMIT)
	assert_eq(
		Breakthrough.inside_world_ok(shared_commit, SEED_GATE),
		true,
		"the shared commit imprints the law, so the shared gate into index %d is open" % SEED_GATE
	)
	assert_eq(
		MindAnchor.stage_met(shared_commit, MindAnchor.required_stage(SEED_GATE)),
		false,
		"while MindAnchor is shut: a commit must not reinforce the anchor it is gating"
	)
	assert_eq(
		shared_commit.inside_world.anchor_strengthened,
		false,
		"and the flag itself is unset, so this is the clause and not a side effect"
	)
	assert_eq(
		shared_commit.inside_world.anchor_created,
		true,
		"though the commit did create the anchor the milestone is paid against"
	)

	var bare := Probe.fresh_actor(Probe.realm_at(MindAnchor.COMMIT_POCKET - 1).id)
	assert_eq(
		Breakthrough.inside_world_ok(bare, MindAnchor.COMMIT_POCKET),
		false,
		"and into the Pocket boundary the shared schedule is shut on a bare actor"
	)
	assert_eq(
		MindAnchor.stage_met(bare, MindAnchor.required_stage(MindAnchor.COMMIT_POCKET)),
		true,
		"while MindAnchor is open, because that is the tier it commits on"
	)


## And the clause the shared schedule has no term for is still separately paid: the
## resonance milestone is the one production route to reinforcement, it costs the
## realm's channel elixir, and core's own `_inside_met` never reads the flag at all.
func test_the_reinforcement_mind_demands_is_separately_paid_and_core_never_reads_it() -> void:
	var actor := Probe.fresh_actor(Probe.realm_at(SEED_COMMIT).id)
	var stage := MindAnchor.required_stage(SEED_GATE)
	var seed := MindRealmSeed.for_realm(Probe.realm_at(SEED_COMMIT).id)
	# Standing IN R19, because `MindTraining.strengthen_anchor` refuses below the
	# Immortal threshold: the milestone is a high-tier act, so the pre-state has to be
	# a high-tier one or the fixture would be testing its own refusal.
	MindAnchor.commit(actor, SEED_COMMIT)
	assert_eq(
		MindAnchor.stage_met(actor, stage),
		false,
		"the commit alone leaves the %s stage shut" % stage
	)
	assert_eq(_paid(actor, seed.training_item), 0, "and the fixture has spent nothing")
	Probe.stock(actor, seed.training_item)
	var stocked := _paid(actor, seed.training_item)
	assert_eq(stocked, 1, "so the realm's channel elixir is in hand")
	assert_eq(MindCultivationApi.strengthen_anchor(actor), true, "the milestone is taken")
	assert_eq(
		_paid(actor, seed.training_item),
		stocked - 1,
		"and it COST that elixir, which is the whole point of the clause"
	)
	assert_eq(MindAnchor.stage_met(actor, stage), true, "which is what opens the %s stage" % stage)
	assert_eq(
		Breakthrough.inside_world_ok(actor, SEED_GATE),
		false,
		"while the shared schedule is still shut: it names a law, never a reinforcement"
	)


# --- The enumeration that decided it -------------------------------------------


## The whole finding in one measurement. The advance INTO ladder index 28 is the first
## boundary whose gate reads the walked ascent, so the actor is measured standing at
## index 27 — the realm that committed the created world and BEGINS the ascent — with
## every other thing that boundary asks for already paid.
##
## The three it satisfies are satisfied INCIDENTALLY: the shared commit inside
## `try_advance` produces their artifacts whether or not mind ever consults the gate
## that reads them, so only a mutation against that commit could ever make them bind.
## The fourth is not incidental and cannot be — `ascension_ok` wants an ascent that has
## been WALKED, and nothing on the mind path walks it.
func test_a_mind_actor_at_index_28_satisfies_three_shared_gates_and_bypasses_the_ascent() -> void:
	var actor := _standing_before(SOURCE)
	assert_eq(
		actor.path(MindPath.PATH_ID).rank_id,
		Probe.realm_at(SOURCE).id,
		"the actor stands at ladder index %d, entering %d" % [SOURCE, TARGET]
	)
	assert_eq(
		Breakthrough.tribulation_ok(actor, TARGET),
		true,
		"satisfies the tribulation gate — mind reads that one in _anchor_ready"
	)
	assert_eq(
		Breakthrough.inside_world_ok(actor, TARGET),
		true,
		"satisfies inside_world_ok, but only because the shared commit inside try_advance made it so"
	)
	assert_eq(
		Breakthrough.world_ok(actor, TARGET),
		true,
		"satisfies world_ok, on the same incidental footing"
	)
	assert_eq(
		Breakthrough.ascension_ok(actor, TARGET),
		false,
		"BYPASSES ascension_ok: the ascent has never been walked on this path"
	)
	assert_eq(
		Breakthrough.tier_gates_met(actor, TARGET),
		false,
		"so the cumulative shared gate is shut, which is what the ungated entry ignored"
	)


## Mind's OWN gate is satisfied on that same pre-state, so the enumeration above cannot
## be dismissed as "the actor was simply not ready". Every clause mind enforces itself
## is met; the shared gate is still shut.
func test_minds_own_gate_is_satisfied_where_the_shared_gate_is_shut() -> void:
	var actor := _standing_before(SOURCE)
	var stage := MindAnchor.required_stage(TARGET)
	assert_ne(
		stage, MindAnchor.STAGE_NONE, "the boundary into index %d names an anchor stage" % TARGET
	)
	assert_eq(
		MindAnchor.stage_met(actor, stage),
		true,
		"and the %s stage is met, anchor and reinforcement included" % stage
	)
	assert_eq(
		Breakthrough.ascension_ok(actor, TARGET),
		false,
		"while the shared gate is still shut on the same actor: the two are not the same gate"
	)


## The three incidental gates would stop being incidental if the shared commit were
## deleted, and the enumeration above would then be measuring something else. So the
## artifacts they read are asserted here directly: origin stamp, structure layer, the
## inside-world chain, and the ascent the fourth gate wants walked.
func test_the_three_incidental_gates_read_artifacts_that_really_exist() -> void:
	var actor := _standing_before(SOURCE)
	var world := actor.world
	assert_ne(world, null, "the created world exists")
	assert_eq(world, actor.component(&"world"), "and is mirrored for the registered providers")
	assert_eq(
		world.origin_index,
		SOURCE,
		"the created world is stamped with the ladder index that built it"
	)
	assert_ne(
		world.get_layer(WorldState.STRUCTURE_LAYER),
		null,
		"and carries the structure layer its gate reads"
	)
	assert_ne(actor.inside_world, null, "the inside-world chain committed up to the tier below")
	assert_ne(actor.ascension, null, "and the Transcendent breakthrough began the ascent")
	assert_eq(actor.ascension.steps, 0, "which walked no step of it")
	assert_eq(
		RealmDefaults.ladder().index_of(actor.path(MindPath.PATH_ID).rank_id),
		SOURCE,
		"the actor really is at index %d, so these are the gates it stands in front of" % SOURCE
	)


# --- What the gate does to a player ---------------------------------------------


## The player-facing half. Body and qi name the gate that refuses clause by clause,
## and `test_tier_gate_reporting.gd` pins that shape. Mind must name the ASCENT the
## same way, in core's own wording, or the gate is invisible to the player who meets
## it. `preview`'s `conditions` is what the mind screen renders verbatim, so what is
## asserted here is exactly what a mind player reads.
func test_the_bypassed_ascent_gate_is_named_clause_by_clause() -> void:
	var actor := _standing_before(SOURCE)
	var preview := MindAdvancement.preview(actor)
	var gates: Dictionary = preview.get("gates", {})
	var unmet: Array = preview.get("tier_gate_unmet", [])
	var ascent: Dictionary = gates.get("ascent", {})
	assert_eq(
		bool(ascent.get("required")), true, "the boundary into index %d owes the ascent" % TARGET
	)
	assert_eq(bool(ascent.get("value")), false, "and it is not met")
	assert_eq(
		String(ascent.get("outstanding")),
		WorldAnchor.ascension_unmet(actor),
		"published in core's own wording, so the report cannot drift from the rule (ADR 0034)"
	)
	assert_eq(
		int(ascent.get("steps_remaining")),
		AscensionState.ASCENT_STEPS,
		"and as a progress: a gate this actor must WALK cannot be rendered from a boolean"
	)
	assert_eq(
		unmet.size(), 1, "exactly one shared gate is shut, and it is named on its own: %s" % [unmet]
	)
	assert_eq(
		String(unmet[0]),
		WorldAnchor.ascension_unmet(actor),
		"the clause is core's wording, not a restatement here"
	)
	var conditions: Array = preview.get("conditions", [])
	assert_eq(
		conditions.size(),
		1,
		(
			"and nothing else is outstanding, so the screen offers exactly one action: %s"
			% [conditions]
		)
	)
	assert_eq(
		conditions.has(unmet[0]),
		true,
		"and the flat list the mind screen renders carries that clause"
	)
	assert_eq(bool(preview.get("ready")), false, "so the realm is not reported enterable")


## Every shared gate the preview publishes carries core's own verdict, and every shut
## one is named — at each high-tier boundary, not once. This is the property that makes
## the report a naming of the gate rather than a second gate, and the assertion that
## fails if a clause is dropped from the list or a verdict restated.
func test_every_shared_gate_is_published_with_core_s_own_verdict_at_every_boundary() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null or target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
			continue
		var actor := Probe.fresh_actor(realm.id)
		var preview := MindAdvancement.preview(actor)
		var gates: Dictionary = preview.get("gates", {})
		var conditions: Array = preview.get("conditions", [])
		var shut := 0
		for key in SHARED_GATES:
			var gate: Dictionary = gates.get(key, {})
			assert_ne(gate.is_empty(), true, "%s is published for %s" % [key, target.id])
			assert_eq(
				bool(gate.get("value")),
				_core_verdict(key, actor, target.index),
				"%s for %s is core's own verdict, not the module's" % [key, target.id]
			)
			if not bool(gate.get("value")):
				shut += 1
		# Every shut shared gate contributes exactly one clause, and each reaches the
		# screen's own list. The anchor clause is separate and is not counted here.
		var tier_clauses: Array = preview.get("tier_gate_unmet", [])
		assert_eq(
			tier_clauses.size(),
			shut,
			"%s names each of its %d shut shared gates once: %s" % [target.id, shut, tier_clauses]
		)
		for clause in tier_clauses:
			assert_eq(
				conditions.has(clause),
				true,
				"the screen's list carries the clause core named: %s" % clause
			)
			assert_ne(String(clause), "", "a clause is never a blank line")
		audited += 1
	assert_eq(
		audited,
		ladder.realms().size() - Breakthrough.IMMORTAL_REALM_THRESHOLD,
		"every high-tier boundary was audited"
	)


## Below the Immortal tier no shared gate is owed, so none is named: a gate a hero owes
## nothing of is not a row on their screen.
func test_no_shared_gate_is_reported_below_the_immortal_tier() -> void:
	var ladder := RealmDefaults.ladder()
	for index in [0, 4, Breakthrough.IMMORTAL_REALM_THRESHOLD - 2]:
		var preview := MindAdvancement.preview(Probe.fresh_actor(ladder.realms()[index].id))
		assert_eq(
			(preview.get("tier_gate_unmet", []) as Array).is_empty(),
			true,
			"realm index %d owes no high-tier gate" % index
		)


## The refusal, through the path's own public entry point, with the rank, the reservoir
## and the pill untouched. A gate the module refuses must leave the actor exactly as it
## was found — the rule body and qi advance under — because `start` spends the realm
## pill on the strength of the condition, so a gate checked only after the spend bills
## the player for a breakthrough that never happened.
func test_mind_refuses_r29_while_the_ascent_is_unwalked_and_spends_nothing() -> void:
	var actor := _standing_before_fresh(SOURCE)
	var rank_before := actor.path(MindPath.PATH_ID).rank_id
	var sea := MindCultivationApi.sea(actor)
	var sea_before := sea.current(actor)
	var pill := MindRealmSeed.for_realm(Probe.realm_at(TARGET).id).breakthrough_item
	var pill_before := _paid(actor, pill)
	assert_eq(
		Breakthrough.can_advance(actor, MindPath.PATH_ID, MindBreakthroughCondition.new()),
		false,
		"the condition refuses, so no attempt is ever started"
	)
	assert_eq(
		Breakthrough.try_advance_gated(actor, MindPath.PATH_ID),
		false,
		"and core's gated entry refuses on the same pre-state"
	)
	assert_eq(
		MindAdvancement.try_breakthrough(actor, _winning(0.5)),
		false,
		"so the one-shot entry point refuses too"
	)
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, rank_before, "the rank is unchanged")
	assert_eq(sea.current(actor), sea_before, "the reservoir is not drained")
	assert_eq(
		_paid(actor, pill),
		pill_before,
		"and the realm pill is not spent on a breakthrough that would refuse"
	)
	assert_eq(MindAdvancement.active_attempt(actor), null, "no attempt is left in flight")


## A gate that closes BETWEEN the two halves of an attempt must cost the player
## nothing: no roll consumed, no deviation, and the record CANCELLED rather than
## failed. The created world is cleared, which is the stale-state case body's own
## comment names ("an inside world that did not survive the round trip leaves the gate
## shut") — and it is a plain field with no production caller that re-creates it, so
## the gate is unambiguously shut underneath the attempt. The status is what
## distinguishes "refused before the roll" from "rolled, then the advance stopped it".
func test_a_gate_that_closes_after_the_attempt_started_costs_no_roll() -> void:
	var actor := _standing_before_fresh(SOURCE)
	_walk_the_ascent(actor)
	var rng := _winning(float(MindAdvancement.preview(actor).get("chance", -1.0)))
	var committed := MindAdvancement.start(actor, rng)
	assert_ne(committed, null, "the attempt starts while every gate is still open")
	# Lose the created world between the two halves of the attempt.
	actor.world = null
	assert_eq(
		Breakthrough.world_ok(actor, TARGET),
		false,
		"so the created-world gate is shut underneath it, on the pre-state chosen here"
	)
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "and the resolve refuses")
	assert_eq(
		actor.path(MindPath.PATH_ID).rank_id, Probe.realm_at(SOURCE).id, "the realm is unchanged"
	)
	var ended := MindAdvancement.attempt(actor)
	assert_eq(
		ended.status,
		MindAttempt.STATUS_CANCELLED,
		"the attempt is CANCELLED, not failed: no trial ran, so no deviation is owed"
	)
	assert_eq(ended.trial_complete, false, "and the record never reached the roll")


## The gate is satisfiable, which is the half that separates a difficulty from a
## soft-lock. `WorldAnchor.ascend` is a core entry point `ui/` may call directly
## (ADR 0058), so four deliberate steps and the gate is open: a mind player is stopped,
## not stranded. The realm is entered through the production verb, not by hand.
func test_walking_the_ascent_opens_the_gate_and_r29_is_then_entered() -> void:
	var actor := _standing_before_fresh(SOURCE)
	var preview := MindAdvancement.preview(actor)
	assert_eq(bool(preview.get("ready")), false, "nothing else is owed and it is still shut")
	_walk_the_ascent(actor)
	preview = MindAdvancement.preview(actor)
	assert_eq(
		(preview.get("tier_gate_unmet", []) as Array).is_empty(),
		true,
		"walking the whole ladder leaves no shared gate clause to offer"
	)
	assert_eq(WorldAnchor.ascension_unmet(actor), "", "and nothing left outstanding to report")
	assert_eq(bool(preview.get("ready")), true, "so the realm reports enterable")
	assert_eq(
		MindAdvancement.try_breakthrough(actor, _winning(float(preview.get("chance", -1.0)))),
		true,
		"and the one-shot breakthrough takes the realm"
	)
	assert_eq(
		actor.path(MindPath.PATH_ID).rank_id,
		Probe.realm_at(TARGET).id,
		"so the mind path takes the realm the gate was holding"
	)


# --- Fixtures --------------------------------------------------------------------


## A mind actor standing at `index` with EVERYTHING the next boundary asks of it paid
## through the actions a player has — the high tier fought and entered through the
## module's own entry point, each anchor committed, each resonance milestone paid, the
## source realm's sea and channel milestones met, the target's budget and
## comprehension floor earned, the reservoir filled, and the target's tribulation won —
## and with the ascent NOT walked, which is the position a mind player is actually in.
##
## Preparing the outgoing boundary is what isolates the measurement: without it the
## tribulation clause would be shut too and the enumeration could not attribute the
## refusal to one gate.
func _standing_before(index: int) -> Actor:
	if _stands.has(index):
		return _stands[index]
	var actor := _climb_and_prepare(index)
	_stands[index] = actor
	return actor


## The same pre-state, fresh. For a test that advances, voids or walks anything, so a
## mid-transition actor is never handed to the next test through the cache.
func _standing_before_fresh(index: int) -> Actor:
	return _climb_and_prepare(index)


func _climb_and_prepare(index: int) -> Actor:
	var actor := Probe.fresh_actor(Probe.realm_at(Breakthrough.IMMORTAL_REALM_THRESHOLD - 1).id)
	for tier in range(Breakthrough.IMMORTAL_REALM_THRESHOLD, index + 1):
		var source := Probe.realm_at(tier - 1)
		var target := Probe.realm_at(tier)
		_prepare(actor, source, target)
		_ensure_heart(actor, target)
		var rng := _winning(float(MindAdvancement.preview(actor).get("chance", -1.0)))
		assert_eq(
			MindAdvancement.try_breakthrough(actor, rng),
			true,
			"%s is entered, and every gate on the way to it was satisfiable" % target.id
		)
		Probe.strengthen_anchor(actor)
	# The boundary this file measures, prepared but never entered.
	_prepare(actor, Probe.realm_at(index), Probe.realm_at(index + 1))
	_ensure_heart(actor, Probe.realm_at(index + 1))
	return actor


## The deepest tier asks for a dao heart (BL-0932), earned here the way a player earns
## it: authored gear, whose fixed modifiers are what APPLY, and the two uniques below
## are what the realm-tier guard admits at the boundary that asks — 26 against the ask
## of 24 (the lantern's +40 is refused until the tier it belongs to is reached).
func _ensure_heart(actor: Actor, target: RealmDef) -> void:
	var required := float(
		Breakthrough.DAO_HEART_BY_TIER.get(RealmDefaults.ladder().tier_of(target.id), 0.0)
	)
	if required <= 0.0 or actor.stats.derived(Stat.DAO_HEART) >= required:
		return
	for def_id in [&"unique_void_coil_coiled_heart", &"unique_ironhide_hearthguard"]:
		var def := Crafting.resolve(def_id)
		assert_ne(def, null, "the authored %s resolves" % def_id)
		if def == null:
			return
		ItemsApi.inventory(actor).add(def, 1)
		assert_eq(
			ItemsApi.equip_item(actor, def.subcategory, def),
			true,
			"%s equips, opening the deepest tier's heart gate" % def_id
		)


## Walk the whole ascent, one deliberate step at a time, through core's own entry
## point. Bounded by the module's own step count: `ascend` refuses a fifth step, so
## its own `false` is the real exit and the bound only names an ascent that will not
## finish.
func _walk_the_ascent(actor: Actor) -> int:
	assert_ne(
		actor.ascension, null, "the Transcendent breakthrough began the ascent on this pre-state"
	)
	var walked := 0
	var guard := 0
	while guard < AscensionState.ASCENT_STEPS + 1 and WorldAnchor.ascend(actor):
		guard += 1
		walked += 1
	assert_eq(
		walked,
		AscensionState.ASCENT_STEPS,
		(
			"the whole ladder, one step at a time, and no more (steps now %d of %d)"
			% [actor.ascension.steps, AscensionState.ASCENT_STEPS]
		)
	)
	return walked


## Everything the boundary from `source` to `target` asks of an actor standing in
## `source`, paid through the actions a player has. Nothing here drains the sea or
## hand-writes progress: `cultivate` trains through a full reservoir and `fill` clamps,
## so draining first would hide the very refusal this file is about.
func _prepare(actor: Actor, source: RealmDef, target: RealmDef) -> void:
	var source_seed := MindRealmSeed.for_realm(source.id)
	var target_seed := MindRealmSeed.for_realm(target.id)
	assert_ne(source_seed, null, "a profile exists for %s" % source.id)
	assert_ne(target_seed, null, "a profile exists for %s" % target.id)
	actor.meridians.unlock_for_realm(target.id)
	var wanted: int = MeridianState.STATE_ORDER.get(source_seed.required_channel_state, 0)
	for meridian_id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		# Bounded, and the bound is a canary for a channel that stops climbing: it
		# spends one elixir per step, so a state that never changed would spin.
		var climbs := 0
		while MeridianState.STATE_ORDER.get(channel.state, 0) < wanted and climbs < CLIMB_CAP:
			climbs += 1
			Probe.stock(actor, source_seed.training_item)
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
	Probe.stock(actor, source_seed.sea_catalyst)
	assert_eq(
		MindTraining.strengthen_sea(actor), true, "the sea milestone completes in %s" % source.id
	)
	assert_eq(Probe.sharpen_sea(actor), true, "clarity and purity met in %s" % source.id)
	assert_eq(
		Probe.earn_gate(actor, target_seed),
		true,
		"the budget and comprehension floor for %s are earned in %s" % [target.id, source.id]
	)
	assert_eq(Probe.fill_sea(actor), true, "the reservoir for %s is filled" % target.id)
	# High tiers demand a DECIDED win, so finishing the phases is not enough.
	Probe.fight(actor, target)
	assert_eq(
		Breakthrough.tribulation_ok(actor, target.index),
		true,
		"the tribulation for %s is fought and won" % target.id
	)
	Probe.stock(actor, target_seed.breakthrough_item)


## The first seed whose single draw beats `chance`, searched rather than hoped for.
##
## Returns a FRESH generator carrying only that seed. This used to return the probe
## whose first draw the search had already consumed, which happened to be harmless
## while the commit stored `rng.seed` — but it handed a caller a generator whose
## stream disagreed with its own seed, which is the exact confusion
## `MindAttemptRoll` documents. Probing a throwaway makes the trap unrepresentable.
func _winning(chance: float) -> RandomNumberGenerator:
	for candidate in range(MindAttemptRoll.MIN_SEED, SEED_GUARD):
		if MindAttemptRoll.replay(candidate).randf() < chance:
			return _seeded(candidate)
	return _seeded(MindAttemptRoll.MIN_SEED)


## A generator carrying `seed_value` and nothing else — no draw taken off it yet.
func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Core's own predicate for one of the four shared gates, named by the key `preview`
## publishes it under. Read from core rather than restated, which is what makes the
## clause list provably a naming of the gate rather than a second gate.
func _core_verdict(key: String, actor: Actor, target_index: int) -> bool:
	match key:
		"tribulation":
			return Breakthrough.tribulation_ok(actor, target_index)
		"inside_world":
			return Breakthrough.inside_world_ok(actor, target_index)
		"world":
			return Breakthrough.world_ok(actor, target_index)
		"ascent":
			return Breakthrough.ascension_ok(actor, target_index)
	return false


## How many of `item_id` the actor is carrying, read through the facade so a test never
## reaches into inventory internals. An empty id counts as nothing stocked.
func _paid(actor: Actor, item_id: StringName) -> int:
	if item_id.is_empty():
		return 0
	return ItemsApi.inventory(actor).count(item_id)
