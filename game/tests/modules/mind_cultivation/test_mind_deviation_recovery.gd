extends TestCase

## BL-0101: a failed Mind breakthrough must be recoverable at the SAME realm,
## through the public facade and nothing else — and no wait in this module may
## fail to terminate.
##
## The defect this pins. `MindTraining.cultivate` refused to work once the
## reservoir was full. Entry into the next realm demands BOTH a filled reservoir
## and a met progress floor, and the reservoir fills first, so the refusal left
## the actor unable to earn the very progress the same gate demanded. A
## deviation made it permanent: `_deviate` halves progress and clouds the sea
## without draining it, and `cultivate` was the only source of either. Thirteen
## test files answered that stall by calling `sea.drain()` themselves, so the
## suite stayed green while the game was unplayable, and every "wait until the
## sea is full" in the suite was a wait on an unreachable condition — which is
## what wrote a 1 GB/s Godot log onto the user's disk.
##
## These tests are written so that restoring the refusal, or reintroducing a bare
## `while`, makes them fail.
##
## Every wait below is bounded and names its condition, because a test that
## cannot converge must fail loudly rather than spin (AGENTS.md).

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

const RANK := &"qi_refining"
const NEXT := &"foundation"

## One press of the facade's Cultivate button: `MindCultivationApi.CULTIVATE_STEP`.
const STEP := MindCultivationApi.CULTIVATE_STEP

## Presses of Cultivate allowed to recover R1's whole entry gate. R1 is the
## neutral realm, so one press is worth exactly STEP of work; the gate needs 100
## progress and 10 comprehension, and insight is `INSIGHT_RATE` per unit of work,
## so comprehension is the binding side at 20 presses. The bound is that plus
## slack: a canary for "cultivation stopped earning anything", not a budget.
const PRESS_BOUND := 64

## Presses of Meditate allowed to clear a deviation's 0.5 of turbulence at the
## facade's 0.1 step. Five is the requirement; the bound names it.
const MEDITATE_BOUND := 12


func _actor() -> Actor:
	var actor := Actor.new(
		&"recovery_hero", {Stat.COMPREHENSION: 0.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, RANK))
	actor.meridians.unlock_for_realm(RANK)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 500)
	MindTraining.synchronize(actor)
	return actor


## Fully prepared for the next realm, using only facade verbs where one exists.
## Sized work goes through `MindTraining.cultivate` because a test is not a UI
## pressing one button; the facade verbs are what prove player-reachability, and
## that is what `test_a_deviation_is_recoverable_through_facade_verbs_only` does.
##
## Assertion-free on purpose. The seed searches below call this once per
## candidate, so an assertion here would multiply into hundreds of failures inside
## one test method and trip the framework's crash backstop — which reports nothing
## at all and hides the real fault.
func _prepared() -> Actor:
	var actor := _actor()
	var source_seed := MindRealmSeed.for_realm(RANK)
	Probe.stock(actor, MindRealmSeed.for_realm(NEXT).breakthrough_item)
	Probe.stock(actor, source_seed.sea_catalyst)
	MindCultivationApi.strengthen_sea(actor)
	Probe.train_channels(actor, source_seed)
	Probe.sharpen_sea(actor)
	Probe.earn_gate(actor, MindRealmSeed.for_realm(NEXT))
	Probe.fill_sea(actor)
	return actor


## The fixture itself is worth one assertion, made once. A search over seeds is
## meaningless if the state it searches over was never ready, because a refused
## attempt and a lost attempt look identical to the caller.
func test_a_prepared_actor_is_actually_ready() -> void:
	var preview := MindCultivationApi.preview(_prepared())
	assert_eq(
		preview.get("ready"),
		true,
		"the fixture reaches the gate, unmet: %s" % [preview.get("conditions", [])]
	)


## A roll that loses the evaluated chance, searched deterministically. Every
## probe is fully prepared, so the roll is the only variable.
func _losing_seed() -> int:
	for candidate in range(1, 64):
		var probe := _prepared()
		var trial := RandomNumberGenerator.new()
		trial.seed = candidate
		if not MindAdvancement.try_breakthrough(probe, trial):
			return candidate
	return 0


## A roll that wins it. The retry is a real trial, so it is searched for rather
## than assumed — a fixed seed would make this test a coin flip.
func _winning_seed() -> int:
	for candidate in range(1, 64):
		var probe := _prepared()
		var trial := RandomNumberGenerator.new()
		trial.seed = candidate
		if MindAdvancement.try_breakthrough(probe, trial):
			return candidate
	return 0


# --- The precondition of every "wait until it is ready" ----------------------


## THE regression assertion, and the one that would have caught the original
## damage: the reservoir the entry gate demands is reachable from a bare actor by
## the production actions alone. Before the fix this was false — `cultivate`
## refused the moment the sea was full, and `fill_sea` returned false after
## burning its whole bound, so every downstream wait had an unreachable exit.
func test_the_sea_fill_gate_is_reachable_without_reaching_behind_the_facade() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	var fill_required := MindRealmSeed.for_realm(NEXT).sea_fill_required
	assert_eq(fill_required > 0.0, true, "the gate really does demand a filled sea")
	assert_eq(sea.ratio(actor) < fill_required, true, "and it is closed on a bare actor")
	assert_eq(Probe.fill_sea(actor), true, "cultivation fills the reservoir")
	assert_eq(sea.ratio(actor) >= fill_required, true, "the sea-fill gate is now open")


## A full reservoir must not stop the progress budget being earned, because both
## are entry gates and the reservoir fills first. This is the deadlock in one
## assertion.
##
## Progress and comprehension are zeroed after being filled, and both are real
## states rather than conveniences: `try_advance` resets progress to zero on every
## single advance, so "full reservoir, nothing earned" is exactly where every
## realm transition starts. Filling the sea first and only then measuring is also
## what makes this isolate the claim — a single sized `cultivate` satisfies both
## gates at once, so a version of this test that measured straight after filling
## would pass even with the refusal restored.
func test_progress_is_earnable_after_the_reservoir_is_already_full() -> void:
	var actor := _actor()
	var state := actor.path(MindPath.PATH_ID)
	assert_eq(Probe.fill_sea(actor), true, "reservoir full first")
	assert_eq(MindCultivationApi.sea(actor).is_full(actor), true, "confirmed full")
	state.progress = 0.0
	actor.stats.set_base(Stat.COMPREHENSION, 0.0)
	actor.mark_stats_dirty()
	assert_eq(MindTraining.cultivate(actor, 500.0), true, "a full reservoir still accepts work")
	assert_eq(state.progress > 0.0, true, "progress is still earnable with a full reservoir")
	assert_eq(
		actor.stats.get_base(Stat.COMPREHENSION) > 0.0, true, "insight is too, and it gates entry"
	)


# --- A failed breakthrough, recovered the way a player would -----------------


## The whole point of BL-0101, end to end, using ONLY `MindCultivationApi`
## verbs. Every wound `_deviate` inflicts is closed here: turbulence by
## `meditate`, the burned channel by `train_channel`, and the halved progress and
## clarity by `cultivate`. No drain, no module internals, no higher realm.
##
## Restoring the full-sea refusal turns the Cultivate presses into no-ops, so the
## entry gate never reopens and the final `ready` assertion fails.
func test_a_deviation_is_recoverable_through_facade_verbs_only() -> void:
	var losing := _losing_seed()
	assert_ne(losing, 0, "a deterministic losing roll exists at R1")

	var actor := _prepared()
	var sea := MindCultivationApi.sea(actor)
	var source_seed := MindRealmSeed.for_realm(RANK)

	var trial := RandomNumberGenerator.new()
	trial.seed = losing
	assert_eq(MindAdvancement.try_breakthrough(actor, trial), false, "the attempt deviated")

	# The deviation's four wounds, all of them real.
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, RANK, "the realm was kept")
	assert_eq(sea.turbulence > 0.0, true, "the sea clouded")
	assert_eq(sea.clarity < source_seed.clarity_required, true, "clarity was halved below the gate")
	var burned := _burned_channel(actor, source_seed)
	assert_ne(burned, &"", "a channel was burned")
	assert_eq(MindCultivationApi.preview(actor).get("ready"), false, "and the gate is now shut")

	# 1. Turbulence. The sea's own recovery, and the only one that touches it.
	var calmed := 0
	while MindCultivationApi.sea(actor).turbulence > 0.0 and calmed < MEDITATE_BOUND:
		calmed += 1
		if not MindCultivationApi.meditate(actor):
			break
	assert_eq(MindCultivationApi.sea(actor).turbulence, 0.0, "meditation calmed the sea")

	# 2. The burned channel. `meets` fails on the injury flag alone, so the
	#    elixir has to be spent before the channel counts again.
	Probe.stock(actor, source_seed.training_item)
	assert_eq(MindCultivationApi.train_channel(actor, burned), true, "channel repaired")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), false, "no longer injured")

	# 3. A fresh pill. `start` spends the realm pill to commit the attempt and a
	#    deviation does not refund it, so the retry needs another one. That is part
	#    of what "recoverable" means here, not an incidental top-up.
	Probe.stock(actor, MindRealmSeed.for_realm(NEXT).breakthrough_item)

	# 4. Progress, comprehension and clarity. Cultivation is the only source of
	#    all three, and after the fix it works with the reservoir still full.
	var pressed := 0
	while pressed < PRESS_BOUND and MindCultivationApi.preview(actor).get("ready") != true:
		pressed += 1
		if not MindCultivationApi.cultivate(actor):
			break

	var preview := MindCultivationApi.preview(actor)
	assert_eq(
		preview.get("ready"),
		true,
		(
			"the same realm's gate reopens within %d cultivate presses, unmet: %s"
			% [PRESS_BOUND, preview.get("conditions", [])]
		)
	)
	assert_eq(pressed <= PRESS_BOUND, true, "recovery finished inside its bound")

	# And the recovered actor can actually break through, which is what makes
	# "recoverable" mean something.
	var retry := RandomNumberGenerator.new()
	retry.seed = _winning_seed()
	assert_ne(retry.seed, 0, "a deterministic winning roll exists at R1")
	assert_eq(
		MindCultivationApi.try_breakthrough(actor, retry),
		true,
		"and the retry through the facade succeeds"
	)


func _burned_channel(actor: Actor, source_seed: MindRealmSeed) -> StringName:
	for meridian_id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel != null and channel.is_injured():
			return meridian_id
	return &""


# --- The invariant that would have caught the damage -------------------------


## No `while` on game state without a bounded cap, anywhere in this module's
## source or its tests. This is the assertion for the disk-safety rule itself
## rather than for any one loop: the original defect was nine separate bare
## `while`s in five files, and a per-loop cap would have had to be written nine
## times and remembered nine times.
##
## A `while` here must compare something against a bounded counter, so the
## condition text has to contain an ordering operator over an integer. `for` is
## bounded by construction and is deliberately not flagged — the bounded waits in
## `mind_gate_probe.gd` use it.
func test_no_wait_in_this_module_is_unbounded() -> void:
	var audited := 0
	for path in _module_sources():
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s is readable" % path)
		for entry in _while_conditions(text):
			audited += 1
			assert_eq(
				_is_bounded(entry, text),
				true,
				(
					(
						"%s has an unbounded `while %s` — a wait whose exit condition "
						% [path.get_file(), entry]
					)
					+ "cannot be met will spin and fill the disk"
				)
			)
	# The scan must still be finding loops, or it has gone blind and would pass
	# forever after every wait was converted to a `for`.
	assert_eq(audited > 0, true, "the scan still finds `while` loops to audit")


func _module_sources() -> Array[String]:
	var found: Array[String] = []
	for root in ["res://src/modules/mind_cultivation", "res://tests/modules/mind_cultivation"]:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with(".") and entry.ends_with(".gd"):
				found.append(root.path_join(entry))
			entry = dir.get_next()
		dir.list_dir_end()
	return found


## Every `while` condition in a file, reassembled across continuation lines and
## stripped of comments, so a multi-line condition cannot hide from the scan.
func _while_conditions(text: String) -> Array[String]:
	var found: Array[String] = []
	var collecting := false
	var depth := 0
	var current := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		if not collecting and line.begins_with("while "):
			collecting = true
			current = line.substr(6)
			depth = _paren_depth(current)
			if depth <= 0:
				found.append(current)
				collecting = false
				current = ""
			continue
		if collecting:
			current += " " + line
			depth = _paren_depth(line)
			if depth <= 0:
				found.append(current)
				collecting = false
				current = ""
	return found


func _paren_depth(text: String) -> int:
	var depth := 0
	for index in text.length():
		match text[index]:
			"(":
				depth += 1
			")":
				depth -= 1
	return depth


## Bounded means the loop moves a COUNTER that its own condition reads. That is
## stricter than "the condition has a `<` in it", and the difference is the whole
## point: `while MeridianState.STATE_ORDER.get(channel.state, 0) < wanted:` is
## exactly the shape of the original defect — a comparison against a state value
## that may simply never be reached — and an ordering operator alone would wave it
## through.
##
## The one accepted exception is the `DirAccess` terminator, `while entry != ""`,
## which this repo already uses in `run_tests.gd`: `get_next()` returns the empty
## string at the end of the listing, so the condition is bounded by the
## directory's contents rather than by game state.
##
## `for` is bounded by construction and is deliberately not flagged — the bounded
## waits in `mind_gate_probe.gd` use it.
func _is_bounded(condition: String, source: String) -> bool:
	if condition.contains('!= ""'):
		return true
	for identifier in _identifiers(condition):
		if source.contains(identifier + " += ") or source.contains(identifier + " -= "):
			return true
	return false


func _identifiers(text: String) -> Array[String]:
	var found: Array[String] = []
	var current := ""
	for index in text.length():
		var character := text[index]
		var is_word := (
			character >= "a" and character <= "z"
			or character >= "A" and character <= "Z"
			or character >= "0" and character <= "9"
			or character == "_"
		)
		if is_word:
			current += character
		elif current != "":
			found.append(current)
			current = ""
	if current != "":
		found.append(current)
	return found
