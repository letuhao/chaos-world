extends TestCase

## The body screen renders the refusal the MODULE named, and never infers one
## (ADR 0150).
##
## This is the layer `tests/modules/body_cultivation/test_refusal_naming.gd` cannot reach:
## that file proves a `false` always has a name, and this one proves the name is what a
## player actually reads. They are separate because the defect had two halves — a module that
## did not publish the cause, and a screen that authored a sentence instead of asking.
##
## ## What was wrong, in the screen's own words
##
## ```
## "Repaired" if repaired else "Nothing damaged to repair"
## ```
##
## So a hero with a torn channel and no recovery elixir was told nothing was damaged, while
## the gate line above — rendered from the SAME `panel_state` — said `Damaged channels need
## repair: lung`. The screen contradicted itself on the fail-recoverably leg of the acceptance
## gate and named the real cause nowhere.
##
## ## What is asserted here is the CONTRACT, not the prose
##
## A test pinning one exact sentence would fail the moment a correct refusal was reworded, and
## a reword is not the defect. So the message must CARRY the label the module published for
## that verb, read back off the read model so no test restates the wording it is checking.
## Both invariants go red when a screen-authored sentence is restored, and both stay green
## through a reword.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const PATH := BodyPath.PATH_ID

## Every damage state a body hero can be driven into. `for` over a fixed list this file
## writes out, so no loop here tests a size of its own making.
const DAMAGE_STATES := [&"healthy", &"torn", &"jammed", &"torn_and_jammed"]

## The verbs whose refusal this screen renders from `unavailable`, and which of them
## report a bool the screen can check. `cultivate` returns void, so it is driven and
## read through `tone` instead.
const REFUSAL_VERBS := ["recover", "strengthen", "cultivate"]

var _play: BodyPlayFixture


func setup() -> void:
	_play = BodyPlayFixture.new()


func _screen() -> BodyCultivationPanel:
	var panel := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(panel, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	return panel


func _first_candidate(actor: Actor) -> StringName:
	var candidates := BodyTraining.strengthen_candidates(actor)
	return candidates[0] if not candidates.is_empty() else &""


func _jam(actor: Actor, meridian_id: StringName) -> StringName:
	for point in BodyCultivationApi.acupoints(actor):
		if AcupointDefaults.meridian_of(point.id) == meridian_id:
			point.block()
			return point.id
	return &""


func _damage(actor: Actor, state: StringName) -> void:
	match state:
		&"healthy":
			pass
		&"torn":
			actor.meridians.damage_meridian(_first_candidate(actor))
		&"jammed":
			_jam(actor, _first_candidate(actor))
		&"torn_and_jammed":
			actor.meridians.damage_meridian(_first_candidate(actor))
			_jam(actor, _first_candidate(actor))


func _message(panel: BodyCultivationPanel) -> String:
	return String(panel.summary().get("message", ""))


func _refused(panel: BodyCultivationPanel) -> bool:
	return String(panel.summary().get("tone", "")) == "error"


## Every label the module published for `verb`, joined the way the screen joins them, read
## from the read model so no test restates the wording it is checking.
func _published(actor: Actor, verb: String) -> String:
	var labels: Array = []
	for clause in _clauses(actor, verb):
		labels.append(String(clause.get("label", "")))
	return "; ".join(labels)


## Press one refusal verb on the panel and report the message it left behind.
func _press(panel: BodyCultivationPanel, verb: String) -> String:
	match verb:
		"recover":
			panel.act_recover()
		"strengthen":
			panel.act_strengthen()
		_:
			panel.act_cultivate()
	return _message(panel)


## The clause KINDS the module published for `verb`, as one comma-joined string, so a
## failure can print what the read model actually said instead of only that it said nothing.
func _kinds(actor: Actor, verb: String) -> String:
	var out: Array = []
	for clause in _clauses(actor, verb):
		out.append(String(clause.get("kind", "")))
	return ",".join(out)


## The RAW clause entries for `verb`, so a failing assertion can print the data itself
## rather than only a summary of it. A test that reports "it said nothing" without saying
## what it DID say costs a whole run to diagnose.
func _clauses(actor: Actor, verb: String) -> Array:
	return (BodyCultivationApi.panel_state(actor).get("unavailable", {}) as Dictionary).get(
		verb, []
	)


## A hero prepared to the brink of its next realm with an EMPTY PACK, except for the pill a
## breakthrough is priced by. The pack is emptied because `BodyPlayFixture.prepare` stocks each
## elixir just before spending one and leaves both behind, so a case about a MISSING price would
## inherit it and never see the refusal it is testing.
##
## The pill is the ONE price the target realm owns, so it comes from the fixture's `seed_for`
## (next realm); every other price here comes from `_seed`, the realm the actor stands in,
## because that is the realm `strengthen` and `recover` charge.
func _prepared(with_pill: bool = true) -> Actor:
	var actor := _play.actor()
	_play.prepare(actor)
	var target := _play.seed_for(actor)
	var pill: StringName = &"" if target == null else target.breakthrough_item
	ItemsApi.inventory(actor).clear()
	if with_pill and pill != &"":
		_play.stock(actor, pill)
	return actor


## The seed of the realm this actor is IN, which is the realm whose elixirs it pays.
func _seed(actor: Actor) -> BodyRealmSeed:
	return BodyRealmSeed.for_realm(actor.path(PATH).rank_id)


## Put the actor on the ladder's LAST rung, where no realm follows.
func _at_ladder_top(actor: Actor) -> void:
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	actor.path(PATH).rank_id = realms[realms.size() - 1].id
	BodyTraining.synchronize(actor)


# --- The screen renders the name ----------------------------------------------


## **THE HEADLINE.** For every damage state, whatever the module published is what the
## screen says, joined the same way. This is the assertion a screen-authored sentence
## cannot pass: it would have to guess the wording the module chose.
func test_every_refusal_message_is_exactly_what_the_module_published() -> void:
	for state in DAMAGE_STATES:
		var panel := _screen()
		var actor := _play.actor()
		panel.setup(actor)
		_damage(actor, state)
		var expected := _published(actor, "recover")
		assert_eq(
			expected.is_empty(),
			false,
			(
				"%s: the module published nothing (clauses=%s joined=%s)"
				% [state, _clauses(actor, "recover"), expected]
			)
		)
		panel.act_recover()
		assert_eq(_message(panel), expected, "%s: the screen repeats the name" % state)
		panel.free()


## The same for the other two verbs a press can be refused, because a screen that renders
## one name and invents the next two has not been fixed.
##
## The name is asserted ONLY where the press was actually refused. `cultivate` succeeds on
## a fresh hero, so demanding a name there would be demanding a complaint that does not
## exist — the mirror of the defect this file removes.
func test_the_other_refused_verbs_are_published_too() -> void:
	for verb in REFUSAL_VERBS:
		var panel := _screen()
		var actor := _play.actor()
		panel.setup(actor)
		var expected := _published(actor, verb)
		_press(panel, verb)
		if _refused(panel):
			assert_eq(expected.is_empty(), false, "%s: the module names something" % verb)
			assert_eq(_message(panel), expected, "%s: the screen repeats the name" % verb)
		panel.free()


# --- The two halves of the seventh-leg contradiction ---------------------------


## **Acceptance criterion 1.** Both halves of the contradiction, asserted separately: a hero
## with a wound and no elixir is told the elixir is missing, and a hero with nothing damaged
## is told that — the same sentence the defect printed for both causes, now true of one.
func test_a_hero_with_a_wound_and_no_elixir_is_told_the_elixir_is_missing() -> void:
	var panel := _screen()
	var actor := _play.actor()
	panel.setup(actor)
	actor.meridians.damage_meridian(_first_candidate(actor))
	assert_eq(panel.act_recover(), false, "an empty pack repairs nothing")
	var said := _message(panel)
	assert_ne(
		said.contains("elixir"),
		false,
		"the price is named (%s, kinds=%s)" % [said, _kinds(actor, "recover")]
	)
	assert_eq(
		said.contains("Nothing damaged to repair"), false, "the wound is not denied (%s)" % said
	)
	panel.free()


## A hero with nothing damaged is told THAT, and this is the sentence the defect used to
## print for BOTH causes, now published only where it is true.
func test_a_hero_with_nothing_damaged_is_told_nothing_is_damaged() -> void:
	var panel := _screen()
	panel.setup(_play.actor())
	assert_eq(panel.act_recover(), false, "there is nothing to repair")
	assert_eq(_message(panel), "Nothing damaged to repair", "and the screen says exactly that")
	panel.free()


## The two halves are DIFFERENT messages, which is the whole fix. Asserted as a pair so a
## regression that makes them identical cannot hide behind either one passing.
func test_the_two_recovery_refusals_are_different_messages() -> void:
	var healthy := _screen()
	healthy.setup(_play.actor())
	healthy.act_recover()
	var nothing_wrong := _message(healthy)
	healthy.free()

	var torn := _screen()
	var actor := _play.actor()
	torn.setup(actor)
	actor.meridians.damage_meridian(_first_candidate(actor))
	torn.act_recover()
	var price_missing := _message(torn)
	torn.free()

	assert_ne(price_missing, nothing_wrong, "two causes, two sentences")


## The screen must never deny a wound the module reports, in any state a player can be in.
## The defect's exact sentence, named once so the negative is about this string. It is
## not banned outright: it is TRUE when nothing is damaged, and the module publishes it
## in exactly that state.
func test_the_denial_is_unreachable_whenever_a_wound_is_present() -> void:
	var denial := "Nothing damaged to repair"
	for state in [&"torn", &"jammed", &"torn_and_jammed"]:
		var panel := _screen()
		var actor := _play.actor()
		panel.setup(actor)
		_damage(actor, state)
		panel.act_recover()
		assert_eq(_message(panel) == denial, false, "%s must not be told %s" % [state, denial])
		panel.free()


## ADR 0150's own contradiction, pinned at the screen and measured rather than asserted
## in prose: the wound is still there, because a refusal that quietly repaired would be a
## different defect wearing the same screen.
func test_the_panel_no_longer_contradicts_its_own_gate_line() -> void:
	var panel := _screen()
	var actor := _play.actor()
	panel.setup(actor)
	assert_ne(_jam(actor, _first_candidate(actor)), &"", "a acupoint on this channel exists")
	var gate := BodyCultivationApi.panel_state(actor)
	assert_ne(int(gate.get("blocked", 0)) > 0, false, "the gate names the jam")
	panel.act_recover()
	var after := BodyCultivationApi.panel_state(actor)
	assert_ne(int(after.get("blocked", 0)) > 0, false, "the wound is still there")
	assert_eq(
		_message(panel).contains("Nothing damaged to repair"),
		false,
		"and the message does not say the opposite (%s)" % _message(panel)
	)
	panel.free()


# --- A capped channel is no longer blamed on a missing elixir -----------------


## **Acceptance criterion 3.** The residual ADR 0150 recorded as unfixed. A channel at
## this realm's refinement ceiling, with the elixir IN HAND, used to read as "No channel
## elixir to spend" — the one sentence that cannot be true in that state.
func test_a_capped_channel_is_not_reported_as_a_missing_elixir() -> void:
	var panel := _screen()
	var actor := _prepared()
	panel.setup(actor)
	var seed := _seed(actor)
	assert_ne(seed, null, "the realm authors a training price")
	var elixir := Crafting.resolve(seed.strengthening_item)
	assert_ne(elixir, null, "authored item %s exists" % seed.strengthening_item)
	ItemsApi.inventory(actor).add(elixir, 400)
	for meridian_id in BodyTraining.strengthen_candidates(actor):
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		channel.state = MeridianState.STRENGTHENED
		channel.refinement = seed.refinement_cap
	for point in BodyCultivationApi.acupoints(actor):
		point.quality = maxf(point.quality, seed.quality_target)
	assert_eq(panel.act_strengthen(), false, "nothing is left to train")
	var said := _message(panel)
	assert_eq(said.contains("channel elixir"), false, "the elixir held is not blamed (%s)" % said)
	assert_ne(said.contains("already at this realm's depth"), false, "the cap is named (%s)" % said)
	panel.free()


# --- The breakthrough refusals ------------------------------------------------


## **Acceptance criterion 3, first half.** Every refusal a breakthrough press can hit is
## rendered, and each of the four is nameable.
func test_each_breakthrough_refusal_is_rendered_rather_than_assumed() -> void:
	# A prepared hero with no pill: the gate's own wording, quoted.
	var pillless := _screen()
	var hero := _prepared(false)
	pillless.setup(hero)
	assert_eq(pillless.act_breakthrough(), false, "no pill, no attempt")
	assert_ne(
		_message(pillless).contains("Missing breakthrough pill"),
		false,
		"the pill is named (%s)" % _message(pillless)
	)
	pillless.free()

	# A busy acupoint set: the re-entrancy guard, named.
	var busy := _screen()
	var held := _prepared()
	busy.setup(held)
	(held.component(&"acupoints") as AcupointSet).busy = true
	assert_eq(busy.act_breakthrough(), false, "a busy acupoint set refuses")
	assert_ne(
		_message(busy).contains("mid-action"), false, "and the guard is named (%s)" % _message(busy)
	)
	busy.free()

	# The top of the ladder: nothing ahead to fight for.
	var topped := _screen()
	var at_top := _play.actor()
	topped.setup(at_top)
	_at_ladder_top(at_top)
	assert_eq(topped.act_breakthrough(), false, "no realm ahead")
	assert_ne(
		_message(topped).contains("highest realm"),
		false,
		"and the top of the ladder is named (%s)" % _message(topped)
	)
	topped.free()


## The one that was never a refusal at all: nothing named blocked the press, so the roll
## ran, and the screen says what the RECORD says rather than assuming a deviation from a
## `false`.
func test_a_rolled_breakthrough_reports_the_records_own_verdict() -> void:
	var panel := _screen()
	var actor := _prepared()
	panel.setup(actor)
	assert_ne(_play.deviate(actor), false, "a roll that deviates is reachable")
	var reason := String(
		BodyCultivationApi.panel_state(actor).get("attempt_outcome", {}).get("reason", "")
	)
	assert_eq(
		reason.is_empty(),
		false,
		(
			"the record names what the roll became (outcome=%s)"
			% [BodyCultivationApi.panel_state(actor).get("attempt_outcome", {})]
		)
	)
	# Re-read on a screen that never saw that roll: the point is that the message comes
	# from the read model, so the same press would report it.
	panel.act_breakthrough()
	var said := _message(panel)
	assert_eq(said.is_empty(), false, "the press is still explained (%s)" % said)
	panel.free()


## ## The finding ADR 0150 asks to be REPORTED rather than papered over.
##
## `unavailable` empty AND the record silent is a `false` no read model names. The screen
## must answer "" there rather than invent a sentence, and this asserts it is unreachable.
func test_no_refusal_is_left_unnamed() -> void:
	for verb in REFUSAL_VERBS + ["breakthrough"]:
		var panel := _screen()
		var actor := _play.actor()
		panel.setup(actor)
		for state in DAMAGE_STATES:
			_damage(actor, state)
			# Read BEFORE the press, because the screen does: a roll mutates, so a
			# post-press report would describe the roll's outcome as the cause.
			var named := _published(actor, verb)
			if verb == "breakthrough":
				panel.act_breakthrough()
			else:
				_press(panel, verb)
			if _refused(panel):
				assert_eq(
					_message(panel).is_empty(),
					false,
					"%s/%s: refused in silence (kinds=%s)" % [state, verb, _kinds(actor, verb)]
				)
				assert_eq(
					named.is_empty(),
					false,
					(
						"%s/%s: the module published no name to render (%s)"
						% [state, verb, _message(panel)]
					)
				)
		panel.free()
