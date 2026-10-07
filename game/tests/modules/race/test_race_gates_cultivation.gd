extends TestCase

## ADR 0109: a body plan gates the breakthrough it forbids.
##
## ADR 0078 recorded that race gated nothing. These prove it now does, from the
## CONSUMER side — through the real cultivation facades and the real advancement entry
## points, never by calling `RaceGate` directly, because a gate that only its own module
## calls is theatre.
##
## **Why every test here names an entry point rather than a helper.** The previous
## version of this suite's last test claimed to prove all three paths and proved only
## that `RaceGate.path_unmet` returns an entry. It passed on the code that shipped the
## bypass: the gate sat on the facade convenience wrappers, so `begin_breakthrough`,
## `resolve_breakthrough` and `app/mind_cultivation_ui.gd`'s direct
## `MindAdvancement.try_breakthrough` call all walked straight past it and a stoneborn
## could still reach mind cultivation. The rule is that a gate is only real if a CALLER
## cannot walk around it, so every test below drives a call a caller would actually make
## and asserts the actor's real rank afterwards. Delete the gate from the advancement
## layer and these fail; move it back up to the facade and they still pass.

const STONE := &"stoneborn"  # closes mind_cultivation, realm_ceiling 17
const TIDE := &"tidecaller"  # closes body_cultivation
const SOURCE := &"qi_refining"

## The lanes this suite refuses on. `PathState` names the same ids the authored
## `closed_paths` use, so a lane and its id can never drift apart in the test.
const CLOSED := [PathState.BODY, PathState.MIND]
const OPEN := [PathState.QI]


## These assertions are about the SHIPPED content tree, so the catalog singleton has to be
## the shipped one. Sibling suites install a fixture catalog with `t_`-prefixed ids that does
## not contain `stoneborn`, and the runner calls `teardown` after each test but a suite that
## installs without undoing it would leave that fixture live for this one.
func teardown() -> void:
	RaceFixtureCatalog.teardown()


## One actor on all three paths at `rank_id`, fully wired, carrying `race_id`.
##
## The three cultivation modules and the item inventory are attached because a
## breakthrough is refused for a dozen reasons OTHER than the gate — no path, no pill, no
## dantian, an empty sea — and a test that asserts `false` without ruling the others out
## passes even when the gate is gone. So each of these tests prepares the lane it drives
## to the brink of the next realm through the production actions first, and asserts that
## the SAME preparation succeeds for a body the lane is open to. A refusal afterwards is
## attributable to the gate and to nothing else.
func _actor(race_id: StringName, rank_id: StringName = SOURCE) -> Actor:
	var actor := Actor.new(&"body", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 50.0})
	actor.set_path(PathState.new(PathState.QI, rank_id))
	actor.set_path(PathState.new(PathState.BODY, rank_id))
	actor.set_path(PathState.new(PathState.MIND, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	QiCultivationApi.attach(actor)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 256)
	QiTraining.synchronize(actor)
	BodyTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	# Re-assert the race LAST. A body plan is a projected ledger, and anything that
	# re-attaches afterwards can reset it — so the actor's body is settled last, then the
	# gate is read.
	RaceApi.set_race(actor, race_id)
	return actor


## The realm each lane is trying to enter, or `&""` when the ladder has none above
## `rank_id`. Read off the SHARED ladder rather than pasted, so a realm inserted in the
## middle cannot make this suite test the wrong boundary.
func _target(rank_id: StringName) -> StringName:
	var target := RealmDefaults.ladder().next(rank_id)
	return &"" if target == null else target.id


## The order to answer the two gate questions in: a path the body plan closes is the
## complaint a player reads, and the ceiling is only consulted when the path is open.
## Both refusal paths are driven below; this is the half that refuses.
func _closed_lane(race_id: StringName) -> StringName:
	for path_id in CLOSED:
		var def := RaceCatalog.instance().race_definition(race_id)
		if def != null and def.closed_paths.has(path_id):
			return path_id
	return &""


## The other half: a lane this body plan leaves open, which is the control that proves the
## preparation itself is not what refuses.
func _open_lane(race_id: StringName) -> StringName:
	for path_id in OPEN:
		var def := RaceCatalog.instance().race_definition(race_id)
		if def != null and not def.closed_paths.has(path_id):
			return path_id
	return OPEN[0]


## Whether the authored plan for `race_id` closes `path_id`. Read from the CONTENT rather
## than asserted as a literal, so a `.tres` edit that reopened a path fails here instead of
## turning the refusal tests into tests of a gate that is no longer closed.
func _content_closes(race_id: StringName, path_id: StringName) -> bool:
	var def := RaceCatalog.instance().race_definition(race_id)
	return def != null and def.closed_paths.has(path_id)


# --- The two breakthroughs the module hands a caller -------------------------
#
# Every entry point, named. This table IS the fix: the refusal lives at
# `QiBreakthroughTransaction.execute`, at `BodyAdvancement.start_attempt` and at
# `MindAdvancement.start`, and these are the calls that reach those three places.


## The qi's production entry point, taken by its facade and by `QiAdvancement`.
## `rng` is accepted so every lane helper has the same shape and a caller can pass a
## seeded generator; this lane's facade verb draws nothing itself, so it is unused here.
func _qi_attempt(actor: Actor, _rng: RandomNumberGenerator = null) -> bool:
	return QiCultivationApi.attempt_breakthrough(actor)


## The body's durable two-phase lifecycle: spend the pill and persist the attempt, then
## roll it on a later call so the trial can span a save. Returning both halves is what
## makes this the DURABLE path rather than another spelling of the one-press one.
func _body_two_phase(actor: Actor, _rng: RandomNumberGenerator) -> bool:
	if BodyCultivationApi.begin_breakthrough(actor).is_empty():
		return false
	return BodyCultivationApi.resolve_breakthrough(actor)


## The body's one-press verb, for completeness: the test above is worthless if the
## one-press path is the only thing that works.
func _body_one_press(actor: Actor, _rng: RandomNumberGenerator) -> bool:
	return BodyCultivationApi.attempt_breakthrough(actor)


## What `app/mind_cultivation_ui.gd` presses. That file calls `MindAdvancement`
## DIRECTLY and skips `MindCultivationApi` altogether, so this is the call the bypass
## actually lived on.
func _mind_advancement(actor: Actor, rng: RandomNumberGenerator) -> bool:
	return MindAdvancement.try_breakthrough(actor, rng)


## The mind path through its facade.
func _mind_facade(actor: Actor, rng: RandomNumberGenerator) -> bool:
	return MindCultivationApi.try_breakthrough(actor, rng)


## The qi transaction itself. The facade delegates here and `QiAdvancement` delegates
## here, so this is the one call the qi seam is really made of.
func _qi_transaction(actor: Actor, rng: RandomNumberGenerator) -> bool:
	return QiBreakthroughTransaction.execute(actor, rng)


## Every breakthrough call this suite drives, with the lane it drives and the name a
## failure message should print for it. The lane is whatever the body plan closes, and for
## STONE that is mind; for TIDE it is body.
func _gated_attempts(race_id: StringName) -> Array:
	var lanes: Array = []
	if _content_closes(race_id, PathState.BODY):
		lanes.append([PathState.BODY, "begin_breakthrough/resolve_breakthrough", _body_two_phase])
		lanes.append([PathState.BODY, "attempt_breakthrough", _body_one_press])
	if _content_closes(race_id, PathState.MIND):
		lanes.append([PathState.MIND, "MindAdvancement.try_breakthrough", _mind_advancement])
		lanes.append([PathState.MIND, "MindCultivationApi.try_breakthrough", _mind_facade])
	if _content_closes(race_id, PathState.QI):
		lanes.append([PathState.QI, "QiCultivationApi.attempt_breakthrough", _qi_attempt])
		lanes.append([PathState.QI, "QiBreakthroughTransaction.execute", _qi_transaction])
	return lanes


# --- Preparation: a refusal that proves nothing ------------------------------


## Bring one lane to the brink of the next realm through the production actions only.
## The loops below are bounded and their reports are ignored: the CONTROL test is what
## turns "we never reached the gate" into a located failure, so an unbounded wait is not
## a risk and a silently-unfinished prepare is not a pass.
##
## Mind and qi both stock through the suite's OWN helpers rather than through their
## modules' probes. The probes cache one actor per realm for the whole process, so
## re-preparing an actor they already own silently returns a stale body — and a refusal
## test that re-prepares between attempts needs a preparation it owns.
func _prepare(actor: Actor, path_id: StringName) -> void:
	var state := actor.path(path_id)
	if state == null:
		return
	if _target(state.rank_id) == &"":
		return
	match path_id:
		PathState.BODY:
			_prepare_body(actor)
		PathState.MIND:
			_prepare_mind(actor)
		PathState.QI:
			_prepare_qi(actor)


## The shared tier gates that stand between this actor and the realm above, satisfied
## through the production entry points only. Crossings into the Immortal tier carry a live
## tribulation gate, and a fixture that leaves it shut reports a body that "cannot reach the
## seam" for a reason that has nothing to do with the race — which is exactly the confusion
## the control test exists to prevent.
##
## The ascent is NOT walked here: nothing in this suite crosses into the Transcendent tier,
## and a walk is four deliberate calls that would be dead weight.
func _satisfy_tier_gates(actor: Actor, rank_id: StringName) -> void:
	var target := RealmDefaults.ladder().next(rank_id)
	if target == null or target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	for _wave in 16:
		if not Breakthrough.advance_tribulation(actor):
			break
	Breakthrough.resolve_tribulation(actor, true)


## Body: the fixture module's own play-only preparation, then a second pass. Two passes
## because the FIRST breakthrough spends the realm's pill and the second needs one in
## hand; a single pass leaves the retry pressing an empty inventory, which reads as a
## refusal and is not one.
func _prepare_body(actor: Actor) -> void:
	_satisfy_tier_gates(actor, actor.path(PathState.BODY).rank_id)
	BodyPlayFixture.new().prepare(actor)
	BodyPlayFixture.new().prepare(actor)


## Mind: the realm's pill, the source realm's channels and sea, then the target realm's
## progress budget. Every item is resolved through `Crafting.resolve`, so a realm whose
## content does not exist leaves the pill at zero and the CONTROL fails with a number
## rather than hanging.
func _prepare_mind(actor: Actor) -> void:
	var state := actor.path(PathState.MIND)
	var target := _target(state.rank_id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	var target_seed := MindRealmSeed.for_realm(target)
	if source_seed == null or target_seed == null:
		return
	_satisfy_tier_gates(actor, state.rank_id)
	actor.meridians.unlock_for_realm(state.rank_id)
	actor.meridians.unlock_for_realm(target)
	_stock(actor, target_seed.breakthrough_item)
	_stock(actor, source_seed.training_item)
	_stock(actor, source_seed.sea_catalyst)
	_stock(actor, source_seed.recovery_item)
	for meridian_id in source_seed.required_meridians:
		# The elixir is stocked PER STEP because `train_channel` consumes one and a
		# refusal spends none: stocking once left a two-channel gate with nothing for the
		# second, and the shortfall reads as "the channel is not ready" forever.
		for _step in 6:
			var channel := actor.meridians.get_meridian(meridian_id)
			if channel != null and channel.meets(source_seed.required_channel_state):
				break
			_stock(actor, source_seed.training_item)
			if not MindCultivationApi.train_channel(actor, meridian_id):
				break
	MindCultivationApi.strengthen_sea(actor)
	# The sea is a RESERVOIR and the fill gate is a fraction of it, so cultivation only
	# refills an amount that already carries some progress: filling it alone would eat the
	# whole work budget and leave the actor exactly where it started. Grown first, then
	# filled, then topped back up.
	for _work in 6:
		if state.progress >= target_seed.progress_required:
			break
		MindTraining.cultivate(actor, 5000.0)
		MindCultivationApi.meditate(actor)
	var sea := MindCultivationApi.sea(actor)
	for _fill in 4:
		if sea != null and sea.is_full(actor):
			break
		MindTraining.cultivate(actor, 5000.0)


## Qi: the realm's pill and training elixir, a dantian carried to the target realm's
## capacity, then progress and comprehension earned by cultivation and meditation.
func _prepare_qi(actor: Actor) -> void:
	var state := actor.path(PathState.QI)
	var target := _target(state.rank_id)
	var seed := QiRealmSeed.for_realm(target)
	var source := QiRealmSeed.for_realm(state.rank_id)
	if seed == null or source == null:
		return
	actor.meridians.unlock_for_realm(state.rank_id)
	actor.meridians.unlock_for_realm(target)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, source.training_item)
	var dantian := QiTestKit.dantian(actor)
	if dantian == null:
		return
	dantian.set_structural_capacity(seed.dantian_capacity)
	for meridian_id in seed.required_meridians:
		for _step in 8:
			var channel := actor.meridians.get_meridian(meridian_id)
			if channel != null and seed.channel_met(channel):
				break
			# Per step, for the same reason as the mind lane: the elixir is consumed.
			_stock(actor, source.training_item)
			if not QiCultivationApi.train_channel(actor, meridian_id):
				break
	# The dantian's fill gate is a FRACTION of its capacity and cultivation tops up an
	# amount scaled by the realm rate, so progress and fill are earned by the same calls
	# and neither one waits for the other. Both are loop conditions rather than a fixed
	# count, so a realm whose authored numbers move cannot leave one of them short.
	for _work in 12:
		var met_progress := state.progress >= seed.progress_required
		var met_insight := actor.stats.derived(Stat.COMPREHENSION) >= seed.comprehension_required
		var met_fill := dantian.ratio(actor) >= seed.dantian_fill_required
		if met_progress and met_insight and met_fill:
			break
		QiCultivationApi.cultivate(actor, 5000.0)
		QiCultivationApi.meditate(actor, QiCultivationApi.MEDITATE_STEP)
	QiTraining.synchronize(actor)


## Put a real authored item in the actor's inventory. Returns false when the content does
## not resolve, so a caller can see the shortfall rather than quietly stocking nothing —
## an empty pill count is the fixture failing, and the CONTROL is where that is located.
func _stock(actor: Actor, def_id: StringName) -> bool:
	if def_id.is_empty():
		return false
	var def := Crafting.resolve(def_id)
	if def == null:
		return false
	ItemsApi.inventory(actor).add(def, 1)
	return true


## Whether the next realm's pill is in hand. Used to assert that a refusal SPENT nothing
## — a refusal that costs the actor its pill is a refusal the player would notice and
## hate, and it is the cheapest proof that the gate refused rather than half-ran.
##
## Every realm authors its pill, so `-1` can only mean "there is no realm above this one",
## and that makes a broken seam visible as a distinct number rather than a silent zero.
func _pill_count(actor: Actor, path_id: StringName) -> int:
	var state := actor.path(path_id)
	if state == null:
		return -1
	var target := _target(state.rank_id)
	if target == &"":
		return -1
	var pill: StringName = &""
	match path_id:
		PathState.BODY:
			var body_seed := BodyRealmSeed.for_realm(target)
			pill = &"" if body_seed == null else body_seed.breakthrough_item
		PathState.MIND:
			var mind_seed := MindRealmSeed.for_realm(target)
			pill = &"" if mind_seed == null else mind_seed.breakthrough_item
		PathState.QI:
			var qi_seed := QiRealmSeed.for_realm(target)
			pill = &"" if qi_seed == null else qi_seed.breakthrough_item
	if pill == &"":
		return -1
	return ItemsApi.inventory(actor).count(pill)


# --- The control: this fixture really can reach a breakthrough ----------------


## **This is what makes the rest of the suite worth reading.**
##
## Every refusal test below asserts `false`, and an assertion that a call refused passes
## just as happily when the call refused for the WRONG reason — an actor that never had a
## pill, never filled a sea, never opened a dantian, never trained a channel. So the
## control drives each lane on a body plan that leaves it OPEN, and asserts the thing that
## distinguishes "the gate refused" from "the fixture never got ready": **the realm pill was
## spent.** A pill is spent at the one point in the lifecycle that sits BEHIND every
## ordinary precondition, so if the spend happened, the fixture reached the breakthrough
## seam and the seam chose to run.
##
## Deliberately never asserts on the OUTCOME. A roll is a roll — the authored floor at R2 is
## 5%, and a deviation leaves the actor on the same rank — so `true` would be an assertion
## about luck. The spend is deterministic and it is what the gate is in front of.
func test_the_control_lane_really_spends_a_pill_to_break_through() -> void:
	var tide := _actor(TIDE)
	# A tidecaller closes BODY, so MIND and QI are its open lanes. QI is the one with no
	# phase of its own, which makes "the transaction ran" observable in a single return.
	var path_id := _open_lane(TIDE)
	assert_ne(_content_closes(TIDE, path_id), true, "the control lane is one %s leaves open" % TIDE)
	for lane: StringName in [path_id, PathState.MIND, PathState.QI]:
		_prepare(tide, lane)
		var before := _pill_count(tide, lane)
		assert_ne(before, 0, "the %s pill was stocked" % lane)
		assert_eq(tide.path(lane).rank_id, SOURCE, "and %s stands where the fixture put it" % lane)
	# Now the claim: the same fixture, on the open lanes, really does get as far as
	# spending the pill. Any outcome is fine; a refusal is not.
	for lane: StringName in [PathState.QI, PathState.MIND]:
		_prepare(tide, lane)
		assert_eq(
			_spends_the_pill(tide, lane),
			true,
			"an OPEN %s lane reaches the seam: %s" % [lane, _unmet(tide, lane)]
		)


## The body's open lane for a body plan that closes it is nobody's — there is no shipped
## race that opens BODY while closing something else — so the body lane's control is a body
## plan with NO restriction at all, which is exactly the boundary rule ADR 0109 states.
func test_the_control_body_lane_really_spends_a_pill_to_break_through() -> void:
	var bare := _actor(&"")
	_prepare(bare, PathState.BODY)
	var before := _pill_count(bare, PathState.BODY)
	assert_ne(before, 0, "the body pill was stocked")
	assert_eq(
		_spends_the_pill(bare, PathState.BODY),
		true,
		"an ungated body lane reaches the seam: %s" % _unmet(bare, PathState.BODY)
	)


## The gates this lane's OWN preview reports as outstanding, as one string. Printed into
## every control assertion, because "the fixture never reached the seam" and "the gate
## refused" look identical from the outside and the difference is the whole claim.
func _unmet(actor: Actor, lane: StringName) -> String:
	match lane:
		PathState.BODY:
			return str(BodyAdvancement.preview(actor).get("unmet", []))
		PathState.MIND:
			return str(MindAdvancement.preview(actor).get("conditions", []))
		PathState.QI:
			return str(QiBreakthroughTransaction.preview(actor).get("unmet_conditions", []))
	return "?"


## Whether `lane` is actually taken to the breakthrough on this actor: re-prepared and
## re-pressed up to four times, and true only once the realm's pill has been SPENT.
##
## The pill count is read BETWEEN the prepare and the press, never across them. That is
## the whole measurement: a preparation stocks the realm's pill, and the press that
## follows either spends one or refuses. Comparing the count before a preparation with
## the count after the next one would compare two different inventories, and a fixture
## that restocks between presses would look like a gate that stopped them.
##
## Every press re-prepares first, because a press that deviates costs progress and a
## deviation is a legitimate outcome that must not be read as a refusal. The bound is the
## number of presses, and a gate that stops the lane reports here as `false` with the pill
## untouched — exactly the signal the refusal tests read.
func _spends_the_pill(actor: Actor, lane: StringName) -> bool:
	for _press in 4:
		_prepare(actor, lane)
		var stocked := _pill_count(actor, lane)
		if stocked == 0:
			continue
		_press_breakthrough(actor, lane)
		if _pill_count(actor, lane) < stocked:
			return true
	return false


## One breakthrough press on `lane`, through whichever call that lane's callers use.
func _press_breakthrough(actor: Actor, lane: StringName) -> bool:
	var rng := _rng(3)
	match lane:
		PathState.BODY:
			if not BodyCultivationApi.begin_breakthrough(actor).is_empty():
				return BodyCultivationApi.resolve_breakthrough(actor)
			return false
		PathState.MIND:
			return MindAdvancement.try_breakthrough(actor, rng)
		PathState.QI:
			return QiCultivationApi.attempt_breakthrough(actor)
	return false


# --- The gate refuses, through every entry point ------------------------------


## **The suite's load-bearing test.** For every body plan in the SHIPPED tree that
## closes a lane, and for EVERY breakthrough call on that lane, the gate refuses and the
## actor's rank does not move.
##
## It reads the authored `closed_paths` rather than a literal, so it covers every authored
## partition rather than the two the suite was written against — three of the four shipped
## races close mind, and the old suite never noticed.
func test_every_closed_lane_is_refused_on_every_entry_point() -> void:
	var refused := 0
	for race_id: StringName in RaceApi.race_ids():
		var lanes: Array = _gated_attempts(race_id)
		for lane: Array in lanes:
			var path_id: StringName = lane[0]
			var label: String = lane[1]
			var attempt: Callable = lane[2]
			var actor := _actor(race_id)
			# Prepared twice on purpose: the first pass earns the gates, the second
			# tops up whatever the first pass spent, so a refusal afterwards is not
			# "the pill ran out mid-fixture".
			_prepare(actor, path_id)
			_prepare(actor, path_id)
			var rank: StringName = actor.path(path_id).rank_id
			var pills := _pill_count(actor, path_id)
			var landed: bool = attempt.call(actor, _rng(7))
			assert_eq(landed, false, "%s cannot reach %s through %s" % [race_id, path_id, label])
			assert_eq(
				actor.path(path_id).rank_id, rank, "and it stayed in its realm (%s)" % race_id
			)
			assert_eq(
				_pill_count(actor, path_id),
				pills,
				"and the refusal spent nothing: a gate that costs the player a pill is a bug"
			)
			refused += 1
	assert_ne(refused, 0, "at least one shipped body plan closes a lane")


## The bypass this suite was written for, named as its own test so it cannot be deleted
## with a refactor.
##
## A tidecaller is the authored body plan that closes BODY. Before the gate moved into
## `BodyAdvancement.start_attempt`, `BodyCultivationApi.begin_breakthrough` called that
## method with no gate at all: the documented DURABLE two-phase lifecycle, the one where
## the pill is spent and the attempt is persisted so it can span a save. That call
## returned a committed attempt to a body whose body plan says it cannot take the body
## path, and `resolve_breakthrough` then rolled it. Both halves are asserted here.
func test_the_durable_two_phase_body_lifecycle_is_gated() -> void:
	var tide := _actor(TIDE)
	assert_eq(_content_closes(TIDE, PathState.BODY), true, "a tidecaller cannot body")
	_prepare(tide, PathState.BODY)
	_prepare(tide, PathState.BODY)
	var rank := tide.path(PathState.BODY).rank_id
	var pills := _pill_count(tide, PathState.BODY)
	var committed := BodyCultivationApi.begin_breakthrough(tide)
	assert_eq(
		committed.is_empty(),
		true,
		"begin_breakthrough refuses, and its empty view is what a screen renders"
	)
	assert_eq(
		BodyAdvancement.attempt(tide) == null, true, "and no attempt was committed to persist"
	)
	assert_eq(
		BodyCultivationApi.resolve_breakthrough(tide),
		false,
		"and resolve_breakthrough has nothing to roll"
	)
	assert_eq(tide.path(PathState.BODY).rank_id, rank, "the rank never moved")
	assert_eq(_pill_count(tide, PathState.BODY), pills, "and the pill was never spent")


## The other bypass, named. `app/mind_cultivation_ui.gd` presses
## `MindAdvancement.try_breakthrough` DIRECTLY — it does not go through
## `MindCultivationApi` at all — so a gate on the facade was a gate the Breakthrough
## button walked straight past. A stoneborn is the authored body plan that closes mind.
func test_the_advancement_entry_a_ui_uses_is_gated() -> void:
	var stone := _actor(STONE)
	assert_eq(_content_closes(STONE, PathState.MIND), true, "a stoneborn cannot mind")
	_prepare(stone, PathState.MIND)
	var rank := stone.path(PathState.MIND).rank_id
	var pills := _pill_count(stone, PathState.MIND)
	# The call `mind_cultivation_ui.gd:159` makes, verbatim.
	assert_eq(
		MindAdvancement.try_breakthrough(stone, _rng(7)),
		false,
		"the direct MindAdvancement entry a UI presses is refused"
	)
	assert_eq(MindAdvancement.attempt(stone) == null, true, "and committed no attempt")
	assert_eq(stone.path(PathState.MIND).rank_id, rank, "the rank never moved")
	assert_eq(_pill_count(stone, PathState.MIND), pills, "and the pill was never spent")


## A lane the body plan leaves OPEN must not be refused by the gate. This is the
## precondition clause of the rule: the gate may refuse, it may never make a
## breakthrough easier — and equally it may not make one harder for a body it permits.
func test_a_lane_the_body_plan_leaves_open_still_breaks_through() -> void:
	var stone := _actor(STONE)
	# A stoneborn opens qi and body; qi is the lane with no phase of its own, so it is
	# the one where "the transaction ran" is observable in a single return value.
	_prepare(stone, PathState.QI)
	assert_ne(
		_pill_count(stone, PathState.QI), 0, "the qi pill was stocked, so a refusal is not about it"
	)
	# Outcome is a roll; REACHABILITY is the claim, and the spend is the deterministic
	# proof of it.
	assert_eq(
		_spends_the_pill(stone, PathState.QI),
		true,
		"qi stays open to a stoneborn, and the attempt really was made"
	)


# --- The refusal is the vocabulary a screen already has -----------------------


## A refusal with a reason: the entry is the `{kind, id, required, actual, label}` shape
## `ItemRequirement.unmet()` already produces, so a breakthrough screen renders it without
## inventing wording (ADR 0034).
##
## `RaceGate` is read directly HERE and only here, and this is not the load-bearing part
## of the suite — the tests above are. This asserts the payload a caller would forward to
## a panel, and it is here to prove the gate still produces the five keys after the move,
## not to prove the gate is consulted.
func test_the_refusal_carries_the_five_key_entry_a_screen_renders() -> void:
	var entries := RaceGate.path_unmet(_actor(STONE), PathState.MIND)
	assert_eq(entries.is_empty(), false, "there is a complaint to render")
	for key in ["kind", "id", "required", "actual", "label"]:
		assert_eq(entries[0].has(key), true, "the entry names '%s'" % key)
	# `str()` rather than `String()`: this Godot build has no callable `String`
	# constructor for a Variant, and using one throws instead of formatting.
	assert_ne(str(entries[0]["label"]), "", "and says something a player can read")


# --- The ceiling is the second half of the rule -------------------------------


## `realm_ceiling` is enforced at the same seam as the closed path (ADR 0109), and it is
## enforced on the RANK, not on the path: a stoneborn authors `realm_ceiling = 17`, so a
## stoneborn standing in `spirit_sea` (ordinal 10) is still under it and a body plan that
## closes mind must not be the thing that refuses it.
func test_a_realm_above_the_authored_ceiling_is_refused_on_every_lane() -> void:
	var stone := _actor(STONE, &"spirit_sea")
	assert_eq(RaceApi.race_definition(stone).realm_ceiling, 17, "the authored ceiling")
	# The ceiling is the realm a body may HOLD, so the realm ABOVE it is the one at
	# ordinal 18. Stoneborn opens both of these lanes, so nothing but the ceiling can be
	# what refuses.
	var rank := _realm_at(18)
	for lane: StringName in [PathState.BODY, PathState.QI]:
		var actor := _actor(STONE, rank)
		assert_ne(_content_closes(STONE, lane), true, "%s is open to a stoneborn" % lane)
		_prepare(actor, lane)
		var stocked := _pill_count(actor, lane)
		assert_ne(stocked, 0, "the %s pill was stocked, so a refusal is not about it" % lane)
		# Four presses, re-prepared between: a ceiling that refused would refuse all
		# four, while a lane the ceiling did NOT catch would spend the pill on the first.
		# The count is read between a preparation and its press, never across both, so a
		# restock is not mistaken for a spend.
		var spent := false
		for _press in 4:
			_prepare(actor, lane)
			var held := _pill_count(actor, lane)
			if held == 0:
				continue
			_press_breakthrough(actor, lane)
			if _pill_count(actor, lane) < held:
				spent = true
				break
		assert_eq(spent, false, "a stoneborn past 17 cannot enter %s on %s" % [rank, lane])
		assert_eq(actor.path(lane).rank_id, rank, "and it stayed where it stood (%s)" % lane)


## The boundary the other way. The ceiling is the realm a body may HOLD, not the one
## above it, so a stoneborn standing at ordinal 17 is not over it — a ceiling that refused
## at the boundary would silently truncate the ladder one rung short.
##
## The attempt is made from ordinal 16, because 17 -> 18 crosses into the Immortal tier,
## which carries its own tribulation gate; a refusal there would say nothing about the race
## ceiling and this assertion could not tell the two apart. Ordinal 16 -> 17 stays inside
## the Spirit tier, where the ceiling is the only thing that can refuse.
func test_a_body_below_its_own_ceiling_is_not_refused() -> void:
	var rank := _realm_at(16)
	var stone := _actor(STONE, rank)
	assert_eq(
		RaceGate.realm_ceiling_unmet(stone).is_empty(),
		true,
		"a body below its ceiling is not refused by it"
	)
	_prepare(stone, PathState.QI)
	# `_unmet` returns the preview as a FORMATTED STRING for a failure message, so it
	# cannot be walked. The question here is narrower anyway: did the RACE refuse, which is
	# `realm_ceiling_unmet`, and it was already asserted empty two lines up. What is worth
	# checking here is that a real attempt was actually attempted and was not stopped by the
	# ceiling — so ask the qi preview directly for a ceiling entry.
	var preview := QiBreakthroughTransaction.preview(stone)
	var conditions: Array = preview.get("unmet_conditions", [])
	var about_the_ceiling := false
	for entry in conditions:
		if str(entry).find("ceiling") >= 0:
			about_the_ceiling = true
	assert_eq(
		about_the_ceiling,
		false,
		(
			"and whatever the attempt was refused by below the ceiling, it was not the race: %s"
			% _unmet(stone, PathState.QI)
		)
	)


## A race that authors no ceiling takes none from it. `tidecaller` ships `realm_ceiling = 0`,
## which `realm_ceiling_unmet` reads as "no opinion" rather than "ceiling at the bottom".
func test_a_race_with_no_ceiling_is_never_refused_by_one() -> void:
	var tide := _actor(TIDE, _realm_at(29))
	assert_eq(RaceApi.race_definition(tide).realm_ceiling, 0, "no ceiling authored")
	assert_eq(RaceGate.realm_ceiling_unmet(tide).is_empty(), true, "so the ceiling never refuses")


# --- An unauthored body must not lock anyone out ------------------------------


## A content gap is not a reason to gate content: an unauthored body would otherwise
## lock a player out of a path nobody ever denied them. `set_race` refuses an empty id and
## leaves the previous race in place, so a raceless actor is built without ever setting
## one — and the claim is made on a CALLER, not on `RaceGate`.
func test_an_actor_with_no_race_takes_no_restriction() -> void:
	var bare := _actor(&"")
	assert_eq(RaceApi.race_of(bare), &"", "no race was ever assigned")
	_prepare(bare, PathState.QI)
	assert_ne(
		_pill_count(bare, PathState.QI),
		0,
		"and the qi pill was stocked, so a refusal is not about it"
	)
	assert_eq(
		_spends_the_pill(bare, PathState.QI), true, "an unauthored body reached the seam, ungated"
	)
	# The same for an actor that was never given a race at all: `RaceApi.attach` with no
	# `set_race` leaves the ledger naming nothing.
	var untouched := Actor.new(&"plain", {Stat.PHYSIQUE: 10.0})
	RaceApi.attach(untouched)
	assert_eq(RaceApi.race_of(untouched), &"", "still no race")
	assert_eq(
		RaceGate.path_unmet(untouched, PathState.MIND).is_empty(),
		true,
		"nor for a fresh actor: no path is closed by a body plan that does not exist"
	)


# --- Helpers -----------------------------------------------------------------


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The realm at an ordinal on the shared ladder, by position rather than by id, so the
## ceiling boundary is expressed in the same units `realm_ceiling_unmet` reads.
func _realm_at(index: int) -> StringName:
	var realms := RealmDefaults.ladder().realms()
	if index < 0 or index >= realms.size():
		return &""
	return realms[index].id
