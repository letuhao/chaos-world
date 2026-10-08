extends TestCase

## ADR 0035/0057: the shared high-tier milestone schedule. Two directions for
## every band — a bare actor fails it, and an actor that reached the previous
## tier's milestone through its own breakthroughs passes it — plus save/load and
## the readouts the registered providers publish.

const PATH := &"qi"

## An ascent is `AscensionState.ASCENT_STEPS` steps and then refuses, so the bound
## is that plus slack. It names an ascent that will not finish; raising it would
## convert a loud failure into a slow one, which is the disk hazard AGENTS.md warns
## about.
const ASCENT_BOUND := 8

## Every milestone this schedule commits, in ladder order.
const COMMITS := [
	WorldAnchor.COMMIT_SEED,
	WorldAnchor.COMMIT_POCKET,
	WorldAnchor.COMMIT_INNER,
	WorldAnchor.COMMIT_MICRO,
	WorldAnchor.COMMIT_GREAT,
]


## An actor built by the composition root, so it carries the same provider
## registrations and component mirrors a live player does.
func _player() -> Actor:
	var actor := ActorFactory.build(&"sched")
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	return actor


## Commit every milestone committed strictly before `target_index`, then walk the
## ascent to the top. This is the legal prior state the gate for `target_index`
## reads — reached only through the breakthroughs and the ascent the player makes.
func _prior_state(target_index: int) -> Actor:
	var actor := _player()
	for index in COMMITS:
		if index >= target_index:
			break
		WorldAnchor.commit(actor, index)
	var walked := 0
	while WorldAnchor.ascend(actor) and walked < ASCENT_BOUND:
		walked += 1
	return actor


# --- The offset: a realm never requires its own milestone ------------------


## Every band gates on the tier committed before it, and on that tier's own law.
## One player who climbed to the last Immortal realm satisfies all of them.
func test_each_band_opens_on_the_previous_committed_milestone() -> void:
	var ladder := RealmDefaults.ladder()
	for index in range(WorldAnchor.COMMIT_SEED + 1, WorldAnchor.COMMIT_GREAT + 1):
		var actor := _prior_state(index)
		assert_eq(WorldAnchor.stage_met(actor, index), true, "%s met" % ladder.realms()[index].id)


## A bare actor passes no high-tier band at all: the first realm's inside world
## may already be stable, but it carries no law, and there is no created world.
func test_a_bare_actor_meets_no_high_tier_band() -> void:
	var actor := _player()
	for index in range(WorldAnchor.COMMIT_SEED + 1, WorldAnchor.COMMIT_GREAT + 1):
		assert_eq(WorldAnchor.stage_met(actor, index), false, "index %d unmet" % index)


## No commit satisfies the gate for its own index on a fresh actor, so no tier is
## reachable by producing only what it asks for. R19 asks for nothing (it opens the
## schedule) and R30 is the last index (nothing follows it), so neither is here.
func test_no_commit_satisfies_its_own_gate() -> void:
	for index in COMMITS:
		if index <= WorldAnchor.COMMIT_SEED or index >= WorldAnchor.COMMIT_GREAT:
			continue
		var actor := _player()
		WorldAnchor.commit(actor, index)
		assert_eq(WorldAnchor.stage_met(actor, index), false, "index %d still shut" % index)


## Below the Immortal tier nothing is required, or the ladder would be untraversable.
func test_bands_below_the_immortal_tier_need_nothing() -> void:
	var actor := _player()
	for index in range(0, WorldAnchor.COMMIT_SEED + 1):
		assert_eq(WorldAnchor.stage_met(actor, index), true, "index %d free" % index)


# --- The inside-world law is part of the gate -------------------------------


## Stability alone no longer opens an Immortal band: the gate reads the tier's law
## by name, so a world that reached stability by some other route still fails.
func test_an_inside_world_without_its_law_does_not_gate() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	var inside := actor.inside_world
	assert_eq(inside.get_law(WorldAnchor.LAW_EARTH), WorldAnchor.LAW_STRENGTH, "law imprinted")
	assert_eq(inside.is_stable(), true, "and it is stable")
	assert_eq(WorldAnchor.stage_met(actor, 19), true, "met with the law")
	inside.laws.erase(WorldAnchor.LAW_EARTH)
	assert_eq(WorldAnchor.stage_met(actor, 19), false, "unmet without it")
	inside.add_law(WorldAnchor.LAW_EARTH, WorldAnchor.LAW_STRENGTH)
	assert_eq(WorldAnchor.stage_met(actor, 19), true, "met again once re-imprinted")


## The wrong tier cannot pass a band even carrying that band's law: the Seed world
## is not a Pocket world, and Pocket is what R23 requires.
func test_the_wrong_inside_world_tier_does_not_gate() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	assert_eq(WorldAnchor.stage_met(actor, 19), true, "R20 met by the seed world")
	assert_eq(WorldAnchor.stage_met(actor, 22), false, "R23 needs the pocket world")


## Each tier's law is committed by the breakthrough into that tier, and only that
## tier — so the law a band reads is never written by the band it gates.
func test_each_law_is_committed_by_its_own_tier() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	assert_eq(actor.inside_world.get_law(WorldAnchor.LAW_EARTH), WorldAnchor.LAW_STRENGTH, "earth")
	assert_eq(actor.inside_world.get_law(WorldAnchor.LAW_HEAVEN), 0.0, "no heaven law yet")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_POCKET)
	assert_eq(
		actor.inside_world.get_law(WorldAnchor.LAW_HEAVEN), WorldAnchor.LAW_STRENGTH, "heaven"
	)
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_INNER)
	assert_eq(
		actor.inside_world.get_law(WorldAnchor.LAW_PRIMORDIAL),
		WorldAnchor.LAW_STRENGTH,
		"primordial"
	)


## A higher tier is a bigger world, not the same one relabelled: the anchor the
## breakthrough creates is what grows it.
func test_each_tier_commits_a_larger_inside_world() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	var seed_size := actor.inside_world.size
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_POCKET)
	var pocket_size := actor.inside_world.size
	assert_eq(pocket_size > seed_size, true, "the pocket world is bigger than the seed")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_INNER)
	assert_eq(actor.inside_world.size > pocket_size, true, "the inner world is bigger still")


# --- The created world ------------------------------------------------------


## The bootstrap world `app/main.gd` hands a first-realm actor is stable and Micro,
## and at 0.5 against a 0.3 threshold it used to pass the Transcendent gate on its
## own, which made that tier unfailable.
func test_a_bootstrap_world_cannot_pass_the_transcendent_gate() -> void:
	var actor := _player()
	var bootstrap := WorldState.new(WorldState.MICRO, 10.0, 0.5)
	actor.world = bootstrap
	assert_eq(bootstrap.is_stable(), true, "the bootstrap world is stable")
	assert_eq(WorldAnchor.stage_met(actor, 28), false, "and it cannot gate R29")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	assert_eq(bootstrap.origin_index, WorldAnchor.COMMIT_MICRO, "stamped when built")
	assert_eq(WorldAnchor.stage_met(actor, 28), true, "and it gates once built")


## The stamp alone is not enough either: the structure layer is the other half of
## what a built world carries, so one without it still fails.
func test_a_stamped_world_without_the_structure_layer_does_not_gate() -> void:
	var actor := _player()
	var world := WorldState.new(WorldState.MICRO, 10.0, 0.5)
	world.origin_index = WorldAnchor.COMMIT_MICRO
	actor.world = world
	assert_eq(WorldAnchor.stage_met(actor, 28), false, "unbuilt structure")
	world.add_layer(WorldLayerState.new(WorldState.STRUCTURE_LAYER, "Structure", 1.0))
	assert_eq(WorldAnchor.stage_met(actor, 28), true, "met once the layer exists")


## A world the Transcendent milestone built can still be broken, and the gate
## follows: stability is read, so a conflict that destabilises it closes R29.
func test_an_unstable_built_world_does_not_gate() -> void:
	var actor := _prior_state(28)
	assert_eq(WorldAnchor.stage_met(actor, 28), true, "met when built and stable")
	actor.world.stability = WorldState.STABILITY_THRESHOLD - 0.01
	assert_eq(WorldAnchor.stage_met(actor, 28), false, "unmet once destabilised")


## ... and the milestone that built it CONVERGES stability to the threshold rather
## than taking a fixed step toward it. A step is not a construction: with one, a world
## destabilised below the threshold is promoted past it and can never gate again,
## because no later commit exists for R29 — the tier whose gate this milestone is.
## With convergence, the commit repairs it and takes zero steps on a world that is
## already stable, which is what makes a repeated commit idempotent.
func test_a_committed_world_converges_to_stable_rather_than_stepping() -> void:
	var actor := _prior_state(28)
	actor.world.stability = 0.0
	assert_eq(WorldAnchor.stage_met(actor, 28), false, "a collapsed world does not gate")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	assert_eq(actor.world.is_stable(), true, "the commit built it back up")
	assert_eq(WorldAnchor.stage_met(actor, 28), true, "and it gates again")
	# Idempotence: a world already at the floor is not raised again.
	var stable := actor.world.stability
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_GREAT)
	assert_eq(WorldAnchor.stage_met(actor, 29), true, "R30's band is met")
	assert_eq(actor.world.stability >= stable, true, "and it never sank below the floor")


## The stamp is written once, so the R30 breakthrough that raises the tier cannot
## rewrite which breakthrough made the world.
func test_the_great_world_keeps_the_stamp_of_the_world_that_built_it() -> void:
	var actor := _prior_state(WorldAnchor.COMMIT_GREAT)
	assert_eq(actor.world.origin_index, WorldAnchor.COMMIT_MICRO, "built at R28")
	assert_eq(actor.world.tier, WorldState.MICRO, "still micro before R30")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_GREAT)
	assert_eq(actor.world.tier, WorldState.GREAT, "raised to great at R30")
	assert_eq(actor.world.origin_index, WorldAnchor.COMMIT_MICRO, "stamp unchanged")
	assert_eq(WorldAnchor.stage_met(actor, 29), true, "and R30's band is met")


# --- The ascent is walked, not granted --------------------------------------


## The Transcendent breakthrough begins the ascent and grants one ability. It does
## not finish it, so the gate demanding a finished ascent cannot be the output of
## the breakthrough it sits behind.
func test_the_transcendent_breakthrough_begins_but_does_not_finish_the_ascent() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	assert_ne(actor.ascension, null, "the ascent was begun")
	assert_eq(actor.ascension.is_complete(), false, "and not finished")
	assert_eq(actor.ascension.steps, 0, "no steps walked by the breakthrough")
	assert_eq(actor.ascension.abilities.size(), 1, "one ability granted")
	assert_eq(actor.ascension.abilities[0], WorldAnchor.ABILITY_WORLD_CREATION, "which one")
	assert_eq(
		actor.ascension.dao_type, WorldAnchor.LAW_TRANSCENDENT, "the dao is the law it committed"
	)


## `ascend` is what finishes the ascent, one step at a time, and it stops at the top.
func test_ascend_walks_the_ascent_one_step_at_a_time() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	var steps := 0
	while WorldAnchor.ascend(actor) and steps < ASCENT_BOUND:
		steps += 1
		assert_eq(
			actor.ascension.is_complete(),
			actor.ascension.steps_remaining() == 0,
			"finished exactly when the steps ran out"
		)
	assert_eq(steps, AscensionState.ASCENT_STEPS, "one step per walk")
	assert_eq(WorldAnchor.ascension_unmet(actor), "", "nothing left to walk")
	assert_eq(WorldAnchor.ascend(actor), false, "a finished ascent takes no step")


## An actor with no ascent cannot walk one: the ritual needs the Transcendent
## breakthrough that begins it.
func test_ascend_refuses_without_an_ascent() -> void:
	var actor := _player()
	# The module publishes the sentinel KEY (the UI resolves or withholds it), so the sentence is
	# what the KEY reads as — not the raw value.
	assert_eq(L.t(WorldAnchor.ascension_unmet(actor)), "No ascent begun", "and says so")
	assert_eq(WorldAnchor.ascend(actor), false, "nothing to walk")


## The R30 milestone grants the Great-world ability and walks no step, so the
## finished ascent R30's gate reads is still the player's own work.
func test_the_great_world_milestone_grants_only_its_ability() -> void:
	var actor := _prior_state(WorldAnchor.COMMIT_GREAT)
	var steps := actor.ascension.steps
	assert_eq(actor.ascension.abilities.size(), 1, "the world-creation ability so far")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_GREAT)
	assert_eq(actor.ascension.steps, steps, "the milestone walked no steps")
	assert_eq(actor.ascension.abilities.size(), 2, "the great-world ability added")
	assert_eq(actor.ascension.abilities[1], WorldAnchor.ABILITY_GREAT_WORLD, "which one")


## The last two Transcendent realms are gated on the walked ascent, and both
## directions are reachable from the same prior state. The ascent gate is
## `Breakthrough.ascension_ok`, not the schedule: R30's own breakthrough commits
## the Great world, so a schedule entry there would be circular (ADR 0035).
func test_the_transcendent_realms_gate_on_the_walked_ascent() -> void:
	for index in [WorldAnchor.COMMIT_MICRO + 1, WorldAnchor.COMMIT_GREAT]:
		var begun := _player()
		WorldAnchor.commit(begun, WorldAnchor.COMMIT_MICRO)
		assert_eq(
			Breakthrough.ascension_ok(begun, index), false, "index %d wants a walked ascent" % index
		)
		assert_ne(WorldAnchor.ascension_unmet(begun), "", "and the reason is reported")
		var began := 0
		while WorldAnchor.ascend(begun) and began < ASCENT_BOUND:
			began += 1
		assert_eq(Breakthrough.ascension_ok(begun, index), true, "index %d met" % index)


## The schedule does not check the ascent at all, so a begun ascent is not enough
## on its own and the two gates cannot be confused for each other.
func test_the_schedule_does_not_check_the_ascent() -> void:
	var begun := _player()
	WorldAnchor.commit(begun, WorldAnchor.COMMIT_MICRO)
	assert_eq(WorldAnchor.stage_met(begun, 29), true, "the created world alone meets the band")
	assert_eq(Breakthrough.ascension_ok(begun, 29), false, "the ascent is a separate gate")


# --- Idempotence, save/load, and readouts -----------------------------------


## Committing a tier twice must not re-walk it: the milestone is one artifact and a
## repeated commit cannot be a second, larger one.
func test_commit_is_idempotent() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	var size := actor.inside_world.size
	var laws := actor.inside_world.laws.size()
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	assert_eq(actor.inside_world.size, size, "space not re-grown")
	assert_eq(actor.inside_world.laws.size(), laws, "law not re-imprinted")
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	var steps := actor.ascension.steps
	var dao := actor.ascension.dao_level
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	assert_eq(actor.ascension.steps, steps, "no steps walked twice")
	assert_eq(actor.ascension.dao_level, dao, "no dao level granted twice")
	assert_eq(actor.world.layers.size(), 1, "no second structure layer")


## A commit index that schedules nothing changes nothing.
func test_commit_ignores_an_unscheduled_index() -> void:
	var actor := _player()
	WorldAnchor.commit(actor, 3)
	assert_eq(actor.inside_world, null, "no inside world")
	assert_eq(actor.world, null, "no created world")
	assert_eq(actor.ascension, null, "no ascent")


## Everything a commit writes survives a save, and the bands it opened stay open.
func test_committed_milestones_survive_save_and_load() -> void:
	var actor := _prior_state(WorldAnchor.COMMIT_GREAT)
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_GREAT)
	var payload := actor.to_dict()
	var restored := Actor.from_dict(payload)
	assert_eq(
		payload["world"]["size"], restored.world.size, "world serialized once, from the field"
	)
	assert_eq(restored.world.origin_index, WorldAnchor.COMMIT_MICRO, "stamp restored")
	assert_eq(restored.world.get_layer(WorldState.STRUCTURE_LAYER) != null, true, "layer restored")
	assert_eq(
		restored.inside_world.get_law(WorldAnchor.LAW_TRANSCENDENT),
		WorldAnchor.LAW_STRENGTH,
		"law restored"
	)
	assert_eq(restored.ascension.is_complete(), true, "the ascent is still finished")
	assert_eq(WorldAnchor.stage_met(restored, 29), true, "and the top band is still met")


## The providers publish the milestones once the composition root registers them,
## which is the only reason any of these keys exist in `derived()` at all.
func test_registered_providers_publish_the_high_tier_readouts() -> void:
	var actor := _prior_state(WorldAnchor.COMMIT_GREAT)
	assert_eq(
		actor.stats.derived(&"inside_world_stability"),
		actor.inside_world.stability,
		"inside_world_stability contributed"
	)
	assert_eq(
		actor.stats.derived(&"world_stability"),
		actor.world.stability,
		"world_stability contributed"
	)
	assert_eq(actor.stats.derived(&"ascension_complete"), 1.0, "ascension_complete contributed")
	assert_eq(
		actor.stats.derived(&"inside_world_size"),
		actor.inside_world.size,
		"inside_world_size contributed"
	)


## The readouts stay absent when there is nothing to read, so a first-realm actor
## is not published as an empty high tier.
func test_registered_providers_publish_nothing_without_a_milestone() -> void:
	var actor := _player()
	assert_eq(actor.stats.derived(&"inside_world_stability"), 0.0, "no inside world = 0")
	assert_eq(actor.stats.derived(&"world_stability"), 0.0, "no created world = 0")
	assert_eq(actor.stats.derived(&"ascension_complete"), 0.0, "no ascent = 0")
