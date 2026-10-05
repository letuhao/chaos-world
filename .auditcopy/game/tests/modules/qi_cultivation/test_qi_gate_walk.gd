extends TestCase

## ADR 0142: the qi ladder is walkable with the facade's verbs and nothing else.
##
## ADR 0095 gave the ladder real gates — `required_channel_refinement` on 26 of
## 30 seeds, all of them `strengthened` — but nothing could reach the depth half.
## The only verb that deepens a channel is `train_channel`, and every caller that
## chose WHICH channel to train skipped on `MeridianState.meets(required_state)`,
## which is state-only by design (`meridian_state.gd:39`). From the first
## depth-demanding gate on, every channel already met the state, so every channel
## was skipped and `QiTraining.refine_meridian` was never reached.
##
## The three suites that walked the ladder stayed green because every one of them
## drove `train_channel` with an id it had already chosen
## (`qi_gate_probe.train_to_gate`, `test_qi_channel_ladder`), so the selection
## rule — the part that was broken — was never executed. And the one UI suite
## that drove the real selection loop (`tests/ui/test_qi_channel_training.gd`)
## asserts it at `qi_refining`, whose gate asks for depth 0, the single realm
## where a state-only skip is accidentally correct.
##
## So the claim here is deliberately narrow and mechanical: for every boundary
## from the first depth-demanding realm to the top, a real actor satisfies EVERY
## channel gate's state AND depth by pressing `QiCultivationApi.train_next_channel`
## and nothing else. No `unlock_for_realm`, no `open_meridian`, no forged
## refinement, and no seed read to decide what to press.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID

## Seed index 4 is `body_integration`, the first realm whose gate asks for depth.
## Every boundary walked from here on therefore exercises the depth half.
const FIRST_DEPTH_INDEX := 4

## The ceiling on presses for one whole gate. The gate names a handful of channels
## and the body holds twenty, so a walk that touched all of them would climb three
## states and refine to the deepest cap on the ladder: `20 x (3 + 30)`. Bounded by
## a FIXED number, never by a count read off whatever the walk grows, so a walk
## that cannot converge reports a named reason instead of pressing forever.
const WALK_BOUND := 700


## An actor on the qi path with nothing earned, built the way the app builds one:
## the facade attaches the pool and the dantian. `meridians` is left empty on
## purpose — `QiCultivationApi.attach` does not unlock channels and production
## unlocks them in `QiTraining.synchronize`, so a suite that calls
## `unlock_for_realm` itself measures a state it wrote rather than one the path
## earned. The `cultivate` below is what does the unlocking, and it is asserted so
## this fixture cannot silently stop being production wiring.
func _joined(rank_id: StringName) -> Actor:
	var actor := Actor.new(
		&"qi_walk_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(PATH, rank_id))
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 512)
	assert_eq(QiCultivationApi.cultivate(actor, 1.0), true, "cultivate drives synchronization")
	return actor


## Press the facade's verb until it stops offering anything, then report the first
## channel of `gate` still short — state or depth — or "" when it converged.
##
## The verb decides when the walk is over: it returns `&""` only when no channel
## the gate names owes anything, so asking it again is cheaper and more truthful
## than re-deriving the rule here. The press count is bounded by a FIXED constant,
## never by a count read off whatever the walk grows, so a walk that cannot
## converge names its shortfall instead of pressing forever.
func _walk_gate(actor: Actor, gate: QiRealmSeed) -> String:
	var source := QiRealmSeed.for_realm(actor.path(PATH).rank_id)
	if source == null:
		return "no source seed"
	var budget := Probe.gate_elixir_budget(actor, gate)
	if not Probe.stock(actor, source.training_item, budget + 1):
		return "no authored elixir for %s" % source.training_item
	var pressed := 0
	while pressed < WALK_BOUND:
		if QiCultivationApi.train_next_channel(actor).is_empty():
			break
		pressed += 1
	return _first_short(actor, gate, pressed)


## The first gate channel that is not satisfied, named with what it holds and what
## the gate wants.
func _first_short(actor: Actor, gate: QiRealmSeed, pressed: int) -> String:
	for meridian_id in gate.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			return "%s is not on the network" % meridian_id
		if gate.channel_met(channel):
			continue
		return (
			"%s holds %s at depth %d, not %s at depth %d, after %d presses"
			% [
				meridian_id,
				channel.state,
				channel.refinement,
				gate.required_channel_state,
				gate.required_channel_refinement,
				pressed,
			]
		)
	return ""


## THE test. At every boundary from the first depth-demanding realm to the top of
## the ladder, the realm's channel gate — both halves — is satisfiable by pressing
## the facade's own verb. A gate above what standing in the realm below can train
## to is exactly the defect that made 28 of 29 qi transitions unplayable before
## ADR 0036, and only walking it catches that class.
func test_every_depth_gate_from_the_first_asking_realm_is_walkable_by_the_facade_verb() -> void:
	var realms := RealmDefaults.ladder().realms()
	var walked := 0
	var depth_asked := 0
	# Every boundary's verdict in ONE assertion. Twenty-six separate ones either
	# drown the message or trip MAX_FAILURES before the report, and a red that does
	# not name which realms failed is a red nobody can act on.
	var reasons: Array[String] = []
	for index in range(FIRST_DEPTH_INDEX, realms.size() - 1):
		var target := Probe.target_after(realms[index].id)
		var gate := Probe.target_seed_after(realms[index].id)
		if gate == null or target == null:
			reasons.append("%s: no seed" % realms[index].id)
			continue
		walked += 1
		if gate.required_channel_refinement > 0:
			depth_asked += 1
		var actor := _joined(realms[index].id)
		var reason := _walk_gate(actor, gate)
		if reason.is_empty():
			# The verb stops AT the gate rather than running past it: the demanded
			# depth exactly, never zero (the defect) and never the standing cap.
			for meridian_id in gate.required_meridians:
				var held := actor.meridians.get_meridian(meridian_id).refinement
				if held != gate.required_channel_refinement:
					reason = (
						"%s rests at depth %d, not the demanded %d"
						% [meridian_id, held, gate.required_channel_refinement]
					)
					break
		if not reason.is_empty():
			reasons.append("%s: %s" % [target.id, reason])
	assert_eq(
		"\n".join(reasons),
		"",
		"boundaries walked: %d, of which asking for depth: %d" % [walked, depth_asked]
	)
	assert_eq(walked, Probe.BOUNDARY_COUNT - FIRST_DEPTH_INDEX, "every depth boundary walked")
	assert_eq(
		depth_asked, walked, "and every one of them asked for depth, so none passed as trivial"
	)


## The depth half where it is most visible: the deepest gate on the ladder, 26
## steps of refinement, reachable only because the verb keeps pressing a channel
## that has long since met the state. Before the fix the walk stopped on press
## three with every channel `strengthened` at depth 0.
func test_the_deepest_gate_is_walked_to_its_full_depth() -> void:
	var realms := RealmDefaults.ladder().realms()
	var here := realms[realms.size() - 2]
	var target := Probe.target_after(here.id)
	var gate := Probe.target_seed_after(here.id)
	if gate == null or target == null:
		assert_eq(true, false, "a seed and a realm above %s" % here.id)
		return
	assert_eq(gate.required_channel_refinement > 1, true, "the top gate asks for real depth")
	var actor := _joined(here.id)
	var subject: StringName = gate.required_meridians[0]
	var named := "channel_not_ready:%s" % subject
	assert_eq(
		Probe.preview(actor)["unmet_conditions"].has(named),
		true,
		"a bare actor fails the gate, so it discriminates"
	)
	assert_eq(_walk_gate(actor, gate), "", "the verb walks the deepest gate")
	assert_eq(
		actor.meridians.get_meridian(subject).refinement,
		gate.required_channel_refinement,
		"%s reached the demanded depth" % subject
	)
	assert_eq(
		Probe.preview(actor)["unmet_conditions"].has(named),
		false,
		"and the preview agrees the gate is open (ADR 0044)"
	)


## The verb never spends an elixir it cannot use. Once every channel the gate
## names is trained to it, the verb returns empty and the elixir count is
## untouched — an elixir burned for no progress is the defect ADR 0095 named, and
## the whole walk must also fit inside the budgeted elixirs, which is the same
## claim from the other side.
func test_the_verb_spends_nothing_once_the_gate_is_met() -> void:
	var realms := RealmDefaults.ladder().realms()
	var here := realms[FIRST_DEPTH_INDEX]
	var source := QiRealmSeed.for_realm(here.id)
	var gate := Probe.target_seed_after(here.id)
	if source == null or gate == null:
		assert_eq(true, false, "seeds for %s and its gate" % here.id)
		return
	var actor := _joined(here.id)
	var budget := Probe.gate_elixir_budget(actor, gate)
	assert_eq(Probe.stock(actor, source.training_item, budget), true, "budgeted elixirs stocked")
	var pressed := 0
	while pressed < WALK_BOUND:
		if QiCultivationApi.train_next_channel(actor).is_empty():
			break
		pressed += 1
	assert_eq(
		_first_short(actor, gate, pressed),
		"",
		"the budgeted elixirs were enough to walk the gate from %s" % here.id
	)
	var held := ItemsApi.inventory(actor).count(source.training_item)
	assert_eq(
		QiCultivationApi.train_next_channel(actor).is_empty(),
		true,
		"the verb offers nothing once the gate is met"
	)
	assert_eq(
		ItemsApi.inventory(actor).count(source.training_item),
		held,
		"and the refusal cost no elixir"
	)
