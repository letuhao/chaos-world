extends TestCase

## Full R1->R30 traversal for the qi path (ADR 0032/0035/0095). The whole ladder is
## walked through public actions only — cultivate, train a channel, meditate,
## recover, and breakthrough. Nothing here writes rank, channel state, world
## systems, or success flags; a failed attempt is recovered from content and
## retried.
##
## The high tier is only reachable because the breakthrough *commits* the inside
## world, world, and ascension its own tier produces (`WorldAnchor`), so this suite
## is also the proof that R19-R30 are reachable in play.
##
## Items are resolved from the authored content tree, not fabricated, so the walk
## proves each realm's content exists and carries the real `max_stack` and
## `stackable`. It used to mint `ItemDef.new()` with `max_stack = 9999`, which
## asserted nothing about whether the content it was spending is loadable.
##
## No wait below is unbounded: each names the condition it waits on and bounds it
## small, so a gate that cannot be satisfied fails an assertion instead of hanging.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID

## The ladder has 30 realms, so advancing through it is 29 transitions.
const TRANSITIONS := 29


## Attempts allowed per boundary before declaring a realm unreachable, sized from
## the evaluated chance so the traversal cannot flake on a legitimate deviation. The
## tail is 1-in-10,000: a tighter one just trades a flake for minutes of re-preparing
## a boundary that was never going to converge.
func _attempt_budget(chance: float) -> int:
	if chance >= 1.0 or chance <= 0.0:
		return 1
	return maxi(3, ceili(log(0.0001) / log(1.0 - chance)))


## Bring the actor to the brink of the next realm using only public actions.
## Returns the target seed, or null when there is no next realm OR when a step could
## not converge — a null here ends the walk with one clear assertion, instead of the
## caller re-preparing the same unachievable state until the framework's failure
## backstop fires on 200 identical messages.
func _prepare(actor: Actor) -> QiRealmSeed:
	var target := Probe.target_after(actor.path(PATH).rank_id)
	if target == null:
		return null
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	_satisfy_tier_gates(actor, target)
	# A deviation injures a channel and scars the dantian, and neither can be
	# climbed or filled around, so close every wound before training and again
	# before the attempt. Each step below must SUCCEED or the walk cannot proceed.
	# They are chained with `and` so a step that fails stops the rest, exactly as
	# the early return it replaced did -- `and` short-circuits.
	var ready := (
		Probe.recover_all(actor)
		and Probe.stock(actor, seed.breakthrough_item)
		and Probe.stock(actor, seed.training_item)
		# BL-0951: the traversal is the PERFECTED run — every departure snapshots at 1.0,
		# so the foundation wall (R4's floor and up) never bites it. The sloppy run that
		# hits the wall is `test_qi_foundation_wall.gd`'s proof.
		and Probe.perfect_gate_channels(actor, seed)
		and Probe.recover_all(actor)
		and Probe.earn_progress(actor, seed)
		and Probe.earn_element_mastery(actor, seed)
		and Probe.meditate_to_floor(actor, seed.comprehension_required)
		and Probe.fill_and_refine(actor, seed)
		# Recovering closes a scar, and a scar costs 25% of capacity, so the reservoir
		# is topped up again afterwards. `recover` deliberately does not restore the
		# quality a deviation halved -- circulation does that, above.
		and Probe.fill_and_refine(actor, seed)
		and Probe.stock(actor, seed.breakthrough_item)
	)
	if not ready:
		return null
	return seed


## Fight and win the tribulation for the realm being entered, and walk whatever
## ascent the tier has begun, through the production entry points only. The world
## systems a tier produces are committed by the breakthrough itself, so this must not
## write them (ADR 0032), a finished-but-undecided fight is not a survivor (ADR
## 0041), and the Transcendent ascent is walked rather than auto-completed (ADR 0058).
func _satisfy_tier_gates(actor: Actor, target: RealmDef) -> void:
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		Probe.fight(actor, target)
	_ensure_dao_heart(actor, target)
	Probe.walk_ascent(actor)


## The DEEPEST trials ask for a dao heart (BL-0932), earned here the way a player earns
## it: the probe equips the authored artifact whose grant opens the tier, so the walk
## proves the gate is REACHABLE through play rather than a wall.
func _ensure_dao_heart(actor: Actor, target: RealmDef) -> void:
	Probe.ensure_dao_heart(actor, target.id)


func _breakthrough(actor: Actor, rng: RandomNumberGenerator) -> bool:
	var budget := _attempt_budget(float(Probe.preview(actor)["chance"]))
	for _attempt in budget:
		if QiBreakthroughTransaction.execute(actor, rng):
			return true
		if _prepare(actor) == null:
			return false
	return false


func test_qi_full_traversal_all_30_realms() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ladder := RealmDefaults.ladder()
	var visited: Array[StringName] = [actor.path(PATH).rank_id]
	var breakthroughs := 0
	var guard := 0
	# The bound is in the CONDITION and not only in the body: GDScript's flow analysis
	# cannot prove a `while true:` terminates and refuses to compile the file when the
	# function has a return type, which turns one unanalysable loop into a whole suite
	# that never loads. The body check names the condition that failed to converge.
	while guard <= 64:
		guard += 1
		if guard > 64:
			push_error("qi traversal did not reach the terminal realm")
			break
		var state := actor.path(PATH)
		var target := ladder.next(state.rank_id)
		if target == null:
			break
		var seed := _prepare(actor)
		assert_ne(seed, null, "seed for %s" % target.id)
		if seed == null:
			break
		# The preview and the transaction must agree, or the gate is decorative.
		var preview := Probe.preview(actor)
		assert_eq(
			bool(preview["can_attempt"]),
			true,
			"preview ready for %s: %s" % [target.id, preview["unmet_conditions"]]
		)
		assert_eq(_breakthrough(actor, rng), true, "breakthrough succeeded for %s" % target.id)
		breakthroughs += 1
		visited.append(target.id)
		assert_eq(actor.path(PATH).rank_id, target.id, "advanced to %s" % target.id)
	assert_eq(visited.size(), 30, "visited all 30 realms")
	assert_eq(breakthroughs, TRANSITIONS, "advanced 29 times")
	assert_eq(visited[-1], &"primordial_origin", "at the terminal realm")
	assert_eq(ladder.next(visited[-1]), null, "no realm after R30")


## Every realm's authored consumables resolve to real content. The traversal spends
## them all 29 times over, so a missing item would surface there — but only after a
## long walk, and only as a confusing "the gate never closed".
func test_every_realm_spends_content_that_resolves() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		assert_ne(seed, null, "seed for %s" % realm.id)
		if seed == null:
			continue
		for role in [
			["breakthrough", seed.breakthrough_item],
			["training", seed.training_item],
			["recovery", seed.recovery_item],
		]:
			var item_id: StringName = role[1]
			assert_ne(item_id, &"", "%s item for %s" % [role[0], realm.id])
			var def := Crafting.resolve(item_id)
			assert_ne(def, null, "authored %s item %s" % [role[0], item_id])
			if def != null:
				assert_eq(def.category, &"consumable", "%s is a consumable" % item_id)


## The dantian is attached by the one production call the composition root makes.
## Nothing ever called `attach_dantian`, so every qi actor the game built had none:
## `cultivate`, `recover`, the preview and the breakthrough condition all refuse an
## actor without one, and the whole path was inert in play while every test that
## built its actor by hand passed.
func test_attaching_the_path_attaches_the_dantian() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	assert_ne(QiAccess.dantian(actor), null, "the dantian exists after attach")
	assert_ne(actor.component(&"dantian"), null, "and is a component on the actor")
	assert_ne(actor.resource(QiCultivationApi.QI), null, "and the reservoir exists")
	# `synchronize` is void, so the claim is on what it left behind: the dantian
	# sealed at the realm's own capacity, with the reservoir re-sealed to match.
	QiTraining.synchronize(actor)
	var dantian := QiTestKit.dantian(actor)
	assert_almost_eq(
		dantian.structural_capacity,
		QiRealmSeed.for_realm(&"qi_refining").dantian_capacity,
		"sealed at the realm's capacity",
		0.0001
	)
	assert_almost_eq(
		actor.resource(QiCultivationApi.QI).maximum,
		dantian.effective_capacity(),
		"and the reservoir re-sealed to match",
		0.0001
	)


## The high tier is reachable because the breakthrough commits what the next tier
## gates on (ADR 0035). Entering R19 must produce the Seed inside world with
## nothing having forged it.
func test_qi_high_tier_commits_its_own_anchors() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var guard := 0
	while actor.path(PATH).rank_id != &"spirit_ascension" and guard < 96:
		guard += 1
		if _prepare(actor) == null:
			break
		if not _breakthrough(actor, rng):
			break
	assert_eq(actor.path(PATH).rank_id, &"spirit_ascension", "reached the last mortal realm")
	assert_eq(actor.inside_world, null, "no inside world below the Immortal tier")
	_prepare(actor)
	assert_eq(_breakthrough(actor, rng), true, "entered R19")
	assert_eq(actor.path(PATH).rank_id, &"earth_immortal", "advanced to R19")
	assert_ne(actor.inside_world, null, "R19 committed the inside world")
	assert_eq(actor.inside_world.is_stable(), true, "and it is stable")


## The Transcendent breakthrough builds the micro world, and the gate the next tier
## reads is the ASCENSION — which the breakthrough begins rather than finishes, so
## the player walks it through core's own entry point (ADR 0058). Nothing here writes
## an ascension stage or an ability.
func test_qi_transcendent_tier_builds_the_world_and_the_player_walks_the_ascent() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var guard := 0
	while actor.path(PATH).rank_id != &"immortal_sovereign" and guard < 96:
		guard += 1
		if _prepare(actor) == null:
			break
		if not _breakthrough(actor, rng):
			break
	assert_eq(actor.path(PATH).rank_id, &"immortal_sovereign", "reached the last immortal realm")
	_prepare(actor)
	assert_eq(_breakthrough(actor, rng), true, "entered the Transcendent tier")
	assert_eq(actor.path(PATH).rank_id, &"transcendent", "advanced to R28")
	assert_ne(actor.world, null, "R28 built the micro world")
	assert_eq(actor.world.tier, WorldState.MICRO, "at the Micro tier")
	# Whether R29 is gated on the ascent is core's rule, not this module's; what the
	# qi path owns is that the walk is available and closes the gate.
	var gated_before := Breakthrough.ascension_ok(actor, 29)
	assert_eq(
		Probe.walk_ascent(actor), true, "the player walks the ascent through core's entry point"
	)
	assert_eq(
		Breakthrough.ascension_ok(actor, 29),
		true,
		"which is what the R29 gate reads (it was %s before the walk)" % gated_before
	)
	# And the ladder actually closes: the traversal above proves it, so R29 and R30
	# are reachable from here through public actions alone.
	_prepare(actor)
	assert_eq(_breakthrough(actor, rng), true, "entered R29")
	assert_eq(actor.path(PATH).rank_id, &"dao_ancestor", "advanced to R29")
