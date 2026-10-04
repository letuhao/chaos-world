extends TestCase

## The body screen offers RESOLVE for a committed attempt instead of a fresh
## breakthrough, and a press that commits says so.
##
## ## What was missing
##
## ADR 0150 recorded the fork and left it open: the facade documents that "a panel
## renders 'an attempt is committed' from it and offers resolve rather than a fresh
## breakthrough", and no panel did. `panel_state`'s `attempt` was permanently `""` because
## the only breakthrough verb the screen pressed ran both halves inside one call, so no
## state a player could produce had an attempt in flight.
##
## ## Why the affordance is asserted on the CONTRACT, not on prose
##
## A test pinning "Resolve into foundation" would fail the moment the wording was
## reworded, and a reword is not the defect. What is asserted is the SHAPE: which of the
## two actions is offered, whether a commit is reported as a success or a refusal, and —
## the part that cannot be faked — that the pill the module spent is gone and the module
## still reports an attempt in flight afterwards. A screen that relabelled its button
## without ever reaching `begin_breakthrough` would pass every wording assertion here and
## fail that one.
##
## ## Why almost nothing here presses a ROLL it did not choose
##
## `begin_breakthrough` and `resolve_breakthrough` take no generator, so they commit and
## roll against seed 0 and the roll is not knowable in advance. A case that asserted "the
## hero advanced" would be testing seed 0. So the cases below assert the invariants that
## hold whichever way it fell, and the ONE case that needs a deviation commits through
## `BodyAdvancement.start_attempt` with a seed chosen to lose — the same escape hatch the
## module's own once-only suite uses.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"

var _play: BodyPlayFixture
var _born: Array = []


func setup() -> void:
	_play = BodyPlayFixture.new()
	_clear_disk()
	SaveApi.reset_clock()


func teardown() -> void:
	for born in _born:
		var body := born as Actor
		if body != null:
			body.resources.clear()
	_born.clear()
	_clear_disk()
	SaveApi.reset_clock()


func _screen() -> BodyCultivationPanel:
	var panel := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(panel == null, false, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	return panel


## A hero at the brink of its next realm, brought there by play, so a press is refused
## only by the thing under test.
func _prepared() -> Actor:
	var hero := _play.actor()
	_born.append(hero)
	assert_ne(_play.prepare(hero) == null, false, "prepared for the next realm by play")
	return hero


func _actions(panel: BodyCultivationPanel) -> Dictionary:
	return panel.summary().get("actions", {}) as Dictionary


func _committed_id(actor: Actor) -> String:
	return String(BodyCultivationApi.panel_state(actor).get("attempt", ""))


func _button_text(panel: BodyCultivationPanel) -> String:
	# `get_node_or_null`, not `get_node`: these panels are never added to a tree in the
	# headless runner, and a miss has to read as "" rather than abort the test.
	var button := panel.get_node_or_null("%BreakthroughButton") as Button
	return "" if button == null else button.text


func _pill_count(actor: Actor) -> int:
	var seed := _play.seed_for(actor)
	if seed == null:
		return 0
	var inventory := ItemsApi.inventory(actor)
	return 0 if inventory == null else inventory.count(seed.breakthrough_item)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The smallest seed whose first draw LOSES against `chance`. Bounded by the 255
## candidates this sweep tries and it RETURNS rather than growing anything, so the loop
## cannot be the thing that does not terminate.
func _seed_losing(chance: float) -> int:
	for candidate in range(1, 256):
		if _rng(candidate).randf() >= chance:
			return candidate
	return 0


# --- The two actions are mutually exclusive ------------------------------------


## **The headline.** A fresh attempt and a resolve are never offered together, because the
## module forbids the first while the second is owed — and that is the module's rule, read
## off the read model, not this screen's.
func test_a_prepared_hero_is_offered_a_fresh_attempt_and_no_resolve() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	var actions := _actions(panel)
	assert_eq(bool(actions.get("breakthrough", false)), true, "a prepared hero may attempt")
	assert_eq(bool(actions.get("resolve", true)), false, "and nothing to resolve yet")
	panel.free()


## The first press commits a DURABLE attempt: it returns "did not advance", it is reported
## as a success rather than a refusal, and the module now holds an attempt. Asserting the
## middle one is what stops a commit being rendered as a failed press — which is how a
## player learns their pill was spent.
func test_the_first_press_commits_a_durable_attempt_and_says_so() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	var pills := _pill_count(hero)

	assert_eq(panel.act_breakthrough(), false, "a commit is not an advance")
	assert_eq(
		String(panel.summary().get("tone", "")),
		"ok",
		"and it is reported as a success, not a refusal"
	)
	assert_ne(
		String(panel.summary().get("message", "")).is_empty(), false, "the press is explained"
	)
	assert_ne(_committed_id(hero).is_empty(), false, "the module holds an attempt in flight")
	assert_eq(_pill_count(hero), pills - 1, "and exactly one pill was spent")
	panel.free()


## The committed attempt is what the control offers next, and the fresh attempt is
## withdrawn — a hero stays `ready` while its attempt is committed, so keying the fresh
## attempt on `ready` alone would offer both at once.
func test_a_committed_attempt_is_offered_resolve_instead_of_a_fresh_attempt() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	panel.act_breakthrough()
	var attempt_id := _committed_id(hero)
	assert_ne(attempt_id.is_empty(), false, "an attempt is in flight")

	var actions := _actions(panel)
	assert_eq(bool(actions.get("resolve", false)), true, "so resolve is offered")
	assert_eq(
		bool(actions.get("breakthrough", true)),
		false,
		"and a second fresh attempt is not, even though the hero is still ready"
	)
	# The control a player presses must SAY it resolves, or the offer exists only in a
	# dictionary. Read back off the button rather than the summary, because the summary
	# is the contract and the label is the thing a player sees.
	assert_ne(_button_text(panel).contains("Resolve"), false, "and the button offers resolve")
	panel.free()


## The second press rolls it, and the attempt is gone afterwards whichever way it fell —
## a stranded attempt is the exact failure this feature exists to remove, so it is the one
## thing asserted here.
func test_the_second_press_resolves_the_committed_attempt() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	panel.act_breakthrough()
	var attempt_id := _committed_id(hero)
	assert_ne(attempt_id.is_empty(), false, "an attempt is in flight")

	panel.act_breakthrough()
	assert_eq(_committed_id(hero), "", "and the resolve left nothing in flight")
	var record := BodyAdvancement.attempt(hero)
	assert_ne(record == null, true, "the record is kept for its verdict")
	if record == null:
		panel.free()
		return
	assert_eq(
		String(record.attempt_id),
		attempt_id,
		"and it is the SAME attempt the first press committed"
	)
	assert_ne(String(panel.summary().get("message", "")).is_empty(), false, "the roll is reported")
	panel.free()


## The label is handed BACK once the attempt is no longer in flight. A screen that only
## ever relabelled would leave a hero who has just broken through holding a button that
## offers to resolve an attempt which no longer exists.
##
## Only the two seed-independent halves are asserted: whether a FRESH attempt is offered
## afterwards depends on the realm just entered's own gates, which is a different question
## and is covered by the prepared-hero case above.
func test_the_resolve_offer_is_withdrawn_once_the_attempt_is_resolved() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	var authored := _button_text(panel)
	assert_eq(authored.contains("Resolve"), false, "the scene authored a breakthrough label")

	panel.act_breakthrough()
	assert_ne(_button_text(panel).contains("Resolve"), false, "which became resolve")
	panel.act_breakthrough()
	assert_eq(_button_text(panel), authored, "and is handed back once the attempt is done")
	assert_eq(bool(_actions(panel).get("resolve", true)), false, "so resolve is withdrawn")
	panel.free()


## A refused COMMIT is still a refusal, rendered from the module's own clause list. The
## durable lifecycle did not make the press failure-proof, and this is the half of the
## screen that still reports a named cause.
func test_a_refused_commit_is_rendered_as_a_refusal_not_a_commit() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	ItemsApi.inventory(hero).clear()
	assert_eq(panel.act_breakthrough(), false, "no pill, no attempt")
	assert_eq(
		String(panel.summary().get("tone", "")), "error", "and the press is reported as a refusal"
	)
	assert_eq(_committed_id(hero), "", "so nothing was committed and resolve is not offered")
	var said := String(panel.summary().get("message", ""))
	assert_ne(
		said.contains("Missing breakthrough pill"),
		false,
		"and the gate's own wording is quoted (%s)" % said
	)
	panel.free()


## A resolve that does not grant is explained by the RECORD, never by the breach list.
##
## This is the case a plausible-looking implementation gets wrong: `unavailable` is
## non-empty for exactly as long as an attempt is in flight, so joining it here ALWAYS
## produces a sentence — "an attempt into X is already committed; resolve it first" — and a
## hero whose trial just deviated is told to resolve the attempt that has already been
## resolved. A refusal that always has an answer is how the four-cause collapse ADR 0150
## removed comes back, wearing the sentence that was supposed to fix it.
##
## The deviation is CHOSEN: the commit goes through `start_attempt` with a seed that loses,
## and the press goes through the screen, so the roll is known without the screen knowing
## anything about it.
func test_a_resolve_that_deviates_is_reported_by_the_record_and_not_by_the_lockout() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	var chance := float(BodyAdvancement.preview(hero).get("chance", 0.0))
	assert_ne(chance, 0.0, "the fixture commits against a real chance")
	var losing := _seed_losing(chance)
	assert_ne(losing, 0, "a losing seed exists for this chance")
	assert_ne(
		BodyAdvancement.start_attempt(hero, _rng(losing)) == null,
		true,
		"an attempt committed against a roll that will lose"
	)
	# The clause list that must NOT be the source of this message.
	var lockout: Array = (
		(BodyCultivationApi.panel_state(hero).get("unavailable", {}) as Dictionary)
		. get("breakthrough", [])
	)
	assert_ne(lockout.is_empty(), false, "the in-flight lockout is published while committed")

	assert_eq(panel.act_breakthrough(), false, "the screen resolves, and the trial deviates")
	var said := String(panel.summary().get("message", ""))
	assert_ne(said.is_empty(), false, "a refused resolve is still explained (%s)" % said)
	assert_eq(
		said.contains("already committed"),
		false,
		"and it is not the lockout clause the player just satisfied (%s)" % said
	)
	panel.free()


## Focus lands on the control that owes the player something. A committed attempt outranks
## cultivate, because the pill is already spent and the roll is the only thing left.
func test_focus_goes_to_the_committed_attempts_control() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	panel.focus_initial()
	assert_eq(String(panel.summary().get("focus_target", "")), "CultivateButton", "at rest")
	panel.act_breakthrough()
	panel.focus_initial()
	assert_eq(
		String(panel.summary().get("focus_target", "")),
		"BreakthroughButton",
		"and on the attempt that is committed"
	)
	panel.free()


# --- Acceptance criterion 1, end to end through the screen ---------------------


## **A player begins an attempt, quits, reloads, and resolves the SAME attempt** — driven
## entirely through this screen's own verbs, with the autosave and the slot read between
## the two presses.
##
## The module suite (`test_body_attempt_survives_the_save.gd`) proves the record and the
## award survive the envelope. This proves the thing that would still be missing if only
## that were true: **the reloaded screen has to OFFER the resolve.** An affordance that
## only exists in the session that created the attempt outlives nothing, which is the
## whole reason the two presses exist.
func test_a_committed_attempt_rides_out_a_save_and_this_screen_offers_to_resolve_it() -> void:
	var panel := _screen()
	var hero := _prepared()
	panel.setup(hero)
	assert_eq(panel.act_breakthrough(), false, "the first press commits rather than advances")
	var attempt_id := _committed_id(hero)
	assert_ne(attempt_id.is_empty(), false, "an attempt is in flight")
	panel.free()

	# --- the player quits here ---
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the autosave landed")
	var envelope := SaveStore.restore().get("envelope", {}) as Dictionary
	assert_ne(envelope.is_empty(), false, "the slot reads back")
	if envelope.is_empty():
		return
	var reloaded := Actor.from_dict(envelope.get("actor", {}) as Dictionary)
	_born.append(reloaded)
	BodyCultivationApi.attach(reloaded)
	BodyCultivationApi.attach_acupoints(reloaded)
	ItemsApi.attach(reloaded)
	BodyTraining.synchronize(reloaded)

	# --- and comes back ---
	var next := _screen()
	next.setup(reloaded)
	var actions := _actions(next)
	assert_eq(
		String(next.summary().get("attempt", "")),
		attempt_id,
		"the reloaded screen reports the attempt that rode out on the save"
	)
	assert_eq(bool(actions.get("resolve", false)), true, "and offers to resolve it")
	assert_ne(_button_text(next).contains("Resolve"), false, "the control says so")
	assert_eq(
		bool(actions.get("breakthrough", true)),
		false,
		"and offers no fresh attempt over the top of it"
	)
	assert_eq(next.act_breakthrough(), _committed_id(reloaded).is_empty(), "one press resolves it")
	assert_eq(_committed_id(reloaded), "", "and the attempt is settled either way")
	next.free()


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
