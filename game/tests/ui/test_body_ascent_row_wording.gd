extends TestCase

## WHAT THE ASCENT ROW PAINTS, read off the widgets themselves.
##
## `BodyCultivationPanel._render_ascent` chose between three wordings with an
## `if/elif` chain whose second and third arms tested the SAME condition. The first
## arm won, so the branch naming an owed requirement was unreachable code. A hero at
## R28 with four unwalked steps reported `ascent.required = true`,
## `ascent.offered = true`, `ascent.outstanding = "Walk the ascent: 4 of 4 steps to
## walk"` -- and an EMPTY row, because the label was set to `""` and `StatRow` takes
## no space on an empty name.
##
## The read model was correct the entire time, and that is exactly why it survived
## every check that asked `summary()`: the summary reports the DATA, and a correct
## summary says nothing about whether a word reached a `Label`. Driving the screen
## earlier in the day and reading the summary said the ascent was observable. It was
## not. So this file reads `%AscentRow.visible`, `%StatLabel.text` and
## `%StatBar.visible` and NEVER asks the summary what the screen said. Asserting
## `summary()["ascent"]["outstanding"]` here would pass on the broken screen, which
## is the shape this defect shipped as.
##
## The three states, and why each earns what it earns:
##
##  - An ascent OWED, i.e. core states steps. The requirement, verbatim. The row
##    exists to sit beside a live control and say what that control buys; a bar that
##    drains as the player walks it is the progress the sentence does not carry.
##  - `WorldAnchor.NO_ASCENT`. Nothing. There is no `AscensionState` to walk, so a
##    bar beside this sentence would read 0/4 for a ritual that does not exist, and
##    the control is not offered either. The sentinel and an owed requirement are
##    disjoint by construction, so suppressing the sentinel costs nothing a player
##    needed -- see `test_the_three_states_never_collide`.
##  - `outstanding == ""`, i.e. the walk is finished. "The ascent is walked". The
##    ritual retiring its control is a state the player has to be able to SEE; a row
##    that vanishes the instant the last step lands is indistinguishable from one
##    that never existed, which is the confusion that made `met` unusable as a key.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const SCRIPT := "res://src/ui/screens/body_cultivation_panel.gd"
## Entering the first Transcendent realm is what commits the milestone, and
## therefore what BEGINS the ascent. Nothing before it produces an `AscensionState`.
const TRANSCENDENT_INDEX := WorldAnchor.COMMIT_MICRO
## The finished ritual's own wording. Asserted as string equality so a reworded
## state is a deliberate edit here rather than a silent drift.
const WALKED := "The ascent is walked"

var _born: Array[Node] = []


## Everything a screen mints is freed here rather than at each call site: the runner
## shares one process across every suite, so a screen a test returned early on would
## outlive the test that made it.
func teardown() -> void:
	for node in _born:
		node.free()
	_born.clear()


# --- The owed case, read off the widgets ---------------------------------------


## THE REGRESSION, asserted on the `Label` node rather than on the screen's own
## summary of it. `rendered` is `StatRow`'s honest half: a row built without
## `%ValueLabel` reports a plausible name while drawing an empty box, so a name alone
## is not evidence of anything.
func test_an_owed_ascent_paints_the_requirement_in_the_label_node() -> void:
	var actor := _transcendent()
	var screen := _screen(actor)
	var row := _row_of(screen)
	assert_ne(row, null, "the ascent row is bound")
	if row == null:
		return
	var label := _label_of(row)
	var bar := _bar_of(row)
	assert_eq(
		String(label.text),
		WorldAnchor.ascension_unmet(actor),
		"an owed ascent states core's own requirement, in the node the player reads"
	)
	assert_ne(
		String(label.text),
		"",
		"which is the whole regression: the row was blank while the gate was owed"
	)
	assert_eq(row.visible, true, "the row is on screen, not collapsed")
	assert_eq(bar.visible, true, "with the walk's bar beside it")


## A requirement that never changes is a caption, not a control. Walking one step
## through the screen's own verb has to move the LABEL, because the sentence names
## the count: this is the leg that separates "the summary changed" from "the player
## can see that it changed".
func test_walking_a_step_repaints_the_label_the_player_reads() -> void:
	var actor := _transcendent()
	var screen := _screen(actor)
	var row := _row_of(screen)
	assert_ne(row, null, "the ascent row is bound")
	if row == null:
		return
	var label := _label_of(row)
	var bar := _bar_of(row)
	var before := String(label.text)
	assert_eq(screen.act_ascend(), true, "the screen's own verb walks a step")
	var after := String(label.text)
	assert_eq(after, WorldAnchor.ascension_unmet(actor), "the label re-reads core afterwards")
	assert_ne(after, before, "so the sentence the player reads changed with the walk")
	assert_almost_eq(
		bar.value / bar.max_value,
		float(actor.ascension.steps_remaining()) / float(AscensionState.ASCENT_STEPS),
		"and the bar drained to the fraction of the walk still owed"
	)


# --- The other two states ------------------------------------------------------


## The sentinel is core declining to state a requirement, so the row takes no space
## at all. Asserted as `visible` on the row rather than as a missing summary key,
## because "nothing was painted" is a fact about a widget.
func test_the_sentinel_paints_nothing_and_keeps_the_read_model_intact() -> void:
	var actor := _transcendent()
	# No `AscensionState`, so core has nothing to state and nothing to walk.
	actor.ascension = null
	var screen := _screen(actor)
	var row := _row_of(screen)
	assert_ne(row, null, "the ascent row is bound")
	if row == null:
		return
	var label := _label_of(row)
	assert_eq(
		WorldAnchor.ascension_unmet(actor),
		WorldAnchor.NO_ASCENT,
		"precondition: core declines to state a requirement here"
	)
	assert_eq(row.visible, false, "so the row is not on screen at all")
	assert_eq(label.text, "", "and paints no sentinel as if it were one")
	# The screen suppresses a SENTENCE, never the data a caller reads.
	var ascent := _ascent(screen)
	assert_eq(
		String(ascent.get("outstanding", "")),
		WorldAnchor.NO_ASCENT,
		"the read model still publishes the sentinel untouched"
	)
	assert_eq(
		bool(ascent.get("offered", true)),
		false,
		"and the control stays retired: there is no walk to offer"
	)


## A finished ritual is a state, and the player has to be able to SEE it retire.
## Silence here would make "I walked it all" and "I never had one" the same screen.
func test_a_walked_ascent_says_so_instead_of_vanishing() -> void:
	var screen := _screen(_transcendent())
	# The bound names a walk that would not finish; the screen's verb returning
	# false is the real exit, so the loop cannot outrun the state.
	var guard := 0
	while guard < 8 and screen.act_ascend():
		guard += 1
	var row := _row_of(screen)
	assert_ne(row, null, "the ascent row is bound")
	if row == null:
		return
	var label := _label_of(row)
	assert_eq(label.text, WALKED, "the finished ritual is named on screen")
	assert_eq(row.visible, true, "and the row is still there saying it")
	assert_eq(
		String((_ascent(screen).get("row", {}) as Dictionary).get("name", "")),
		WALKED,
		"with no steps left to walk"
	)


## All three at once, and pairwise distinct. Two `elif` arms testing one condition
## left only two wordings reachable out of three, so the three are driven together
## here: the sentence core states, the silence when it states nothing, and the
## screen's own sentence when the walk is done.
func test_the_three_states_are_told_apart_and_never_collide() -> void:
	var owed_actor := _transcendent()
	var owed := _text_of(_screen(owed_actor))
	var walked := _text_of(_screen(_walked_out(_transcendent())))
	var bare := _transcendent()
	bare.ascension = null
	var silent := _text_of(_screen(bare))

	assert_eq(
		owed, WorldAnchor.ascension_unmet(owed_actor), "the owed state states the requirement"
	)
	assert_ne(owed, walked, "so the owed state is not the finished state")
	assert_ne(owed, silent, "and not the silence: the sentinel never reaches the label")
	assert_ne(walked, silent, "nor is the finished state the silence")
	assert_eq(silent, "", "core's sentinel is never rendered as a gate")


## Why suppressing the sentinel cannot cost a player the owed case: `ascension_unmet`
## is a three-way, so the two are disjoint rather than merely ordered. If core ever
## answered `NO_ASCENT` for an actor that owes steps, this row would go quiet on a
## real requirement again -- and the behaviour above would still pass, because it
## only drives states that exist today.
func test_the_three_states_never_collide() -> void:
	var owed := _transcendent()
	assert_ne(
		WorldAnchor.ascension_unmet(owed),
		WorldAnchor.NO_ASCENT,
		"an actor with steps to walk never reads as core declining to state one"
	)
	assert_ne(WorldAnchor.ascension_unmet(owed), "", "nor as having nothing outstanding")
	# And `required` implies a non-empty sentence, so the row's key is well founded:
	# a hero owed the gate is never the "" branch.
	var walked := _walked_out(_transcendent())
	assert_eq(WorldAnchor.ascension_unmet(walked), "", "a walked ascent leaves nothing outstanding")
	assert_eq(
		bool(_ascent(_screen(walked)).get("required", true)),
		false,
		"and is therefore never the owed state either"
	)


# --- The root cause, pinned structurally ---------------------------------------


## One predicate, one job. `required` answers "is this the gate on my next
## breakthrough" and belongs to `_ascend_offered`, which decides the CONTROL. The
## render function asked it too, and the duplicate arm is how a player was owed an
## ascent and shown nothing: `lint`, `arch` and every `summary()` assertion stayed
## green, because a duplicated condition in a dead `elif` is legal GDScript.
func test_the_row_render_never_reads_the_required_flag() -> void:
	var body := _function_body(FileAccess.get_file_as_string(SCRIPT), "func _render_ascent(")
	assert_ne(body.is_empty(), true, "the render function was found and read")
	var hits := _required_reads(body)
	assert_eq(
		hits.size(),
		0,
		(
			(
				"the ascent row reads `required` at %s, which `_ascend_offered` already answers "
				% [", ".join(hits)]
			)
			+ "for the control. Key the row on `outstanding` instead: a second reader of one "
			+ "predicate is what made this row blank while the gate was owed."
		)
	)


## The detector proven on strings, so a guard cannot rot into passing because it
## stopped matching. Mirrors `test_no_deferred_free.gd`.
func test_the_detector_still_recognises_a_required_read() -> void:
	var offending := (
		"func _render_ascent(view: Dictionary) -> void:\n"
		+ '\tvar a = view.get("ascent", {}).get("required", false)\n'
		+ "\n\nfunc other() -> void:\n"
		+ "\tpass\n"
	)
	assert_eq(
		_required_reads(_function_body(offending, "func _render_ascent(")).size(),
		1,
		"a read is found"
	)
	# Prose naming the flag is documentation, not a read -- the doc block above this
	# function is full of it.
	var documented := (
		"## `required` is the button's question, not the row's.\n"
		+ "func _render_ascent(view: Dictionary) -> void:\n"
		+ '\tvar label := ""\n'
	)
	assert_eq(
		_required_reads(_function_body(documented, "func _render_ascent(")).size(),
		0,
		"a comment naming it is not a read"
	)
	# The slice stops at the next `func`, or the guard would blame this rule for the
	# one legitimate reader a few lines above it.
	var followed := (
		"func _render_ascent(view: Dictionary) -> void:\n"
		+ '\tvar label := ""\n'
		+ "\n\nfunc _ascend_offered(view: Dictionary) -> bool:\n"
		+ '\treturn bool(view.get("ascent", {}).get("required", false))\n'
	)
	assert_eq(
		_required_reads(_function_body(followed, "func _render_ascent(")).size(),
		0,
		"the reader that is allowed to ask is not counted against the render"
	)
	assert_eq(
		_function_body("nothing here at all\n", "func _render_ascent("),
		"",
		"a missing function reads as empty"
	)


## The text of one top-level `func`, from its signature to the next one. Doc
## comments live above the signature, so the block's own reasoning about the flag is
## outside the slice and cannot trip the guard that forbids the code from asking.
func _function_body(text: String, signature: String) -> String:
	var lines := text.split("\n")
	var start := -1
	for index in lines.size():
		if String(lines[index]).begins_with(signature):
			start = index
			break
	if start < 0:
		return ""
	var out: Array[String] = []
	for index in range(start + 1, lines.size()):
		var line: String = lines[index]
		if line.begins_with("func "):
			break
		out.append(line)
	return "\n".join(out)


## Every line of `body` that READS `required`, as `"<line number>: <text>"`.
## Comment-only lines are skipped so the rule's own prose never counts against it.
func _required_reads(body: String) -> Array[String]:
	var out: Array[String] = []
	if body.is_empty():
		return out
	var lines := body.split("\n")
	for index in lines.size():
		var line: String = lines[index].strip_edges()
		if line.begins_with("#"):
			continue
		if line.split("#")[0].contains("required"):
			out.append("%d: %s" % [index + 1, line])
	return out


# --- Fixtures ------------------------------------------------------------------


func _screen(actor: Actor) -> BodyCultivationPanel:
	var screen := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(screen, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	_born.append(screen)
	screen.setup(actor)
	return screen


## A body hero standing in the first Transcendent realm with that realm's committed
## milestone already applied: the state a player reaches after R28, not a shortcut
## past it. The milestone BEGINS the ritual, so the whole walk is owed.
func _transcendent() -> Actor:
	var actor := ActorFactory.with_body_cultivation(
		Actor.new(&"ascent_row_hero", {Stat.PHYSIQUE: 20.0})
	)
	ItemsApi.attach(actor)
	actor.path(BodyPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX)
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	BodyTraining.synchronize(actor)
	assert_ne(actor.ascension, null, "the R28 milestone produced an ascent")
	return actor


## The same hero after walking the whole ritual. Bounded by the walk's own refusal:
## `AscensionState.ascend` returns false once `steps` reaches the cap, so the loop
## terminates on the state and not on the number.
func _walked_out(actor: Actor) -> Actor:
	var guard := 0
	while guard < 8 and WorldAnchor.ascend(actor):
		guard += 1
	assert_eq(actor.ascension.is_complete(), true, "the whole walk is taken")
	return actor


func _realm_at(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _ascent(screen: BodyCultivationPanel) -> Dictionary:
	return screen.summary().get("ascent", {}) as Dictionary


func _row_of(screen: BodyCultivationPanel) -> StatRow:
	var row := screen.get_node_or_null("%AscentRow") as StatRow
	assert_ne(row, null, "the scene declares %AscentRow")
	return row


func _label_of(row: StatRow) -> Label:
	return null if row == null else row.get_node_or_null("%StatLabel") as Label


func _bar_of(row: StatRow) -> ProgressBar:
	return null if row == null else row.get_node_or_null("%StatBar") as ProgressBar


## What the ascent row PAINTS, off the `Label` node. "" when the row is unbound,
## which every caller above has already asserted is not the case.
func _text_of(screen: BodyCultivationPanel) -> String:
	var label := _label_of(_row_of(screen))
	return "" if label == null else String(label.text)
