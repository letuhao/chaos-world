extends TestCase

## Can a player SEE why they were refused?
##
## `test_failure_branches_reachable.gd` answers "can a player cause it". This file
## answers the other half, on the surfaces a player actually touches: the shipped
## screens' `act_*` verbs and their `summary()["message"]` line.
##
## ## What this file found
##
## **On the tribulation leg the naming is real and the player never sees it.**
## `TribulationScreen._report` renders a refusal's `reason` verbatim, so the
## vocabulary works — and then `_offered` disables the very control whose press
## would produce the refusal. All four reachable refusals are behind a disabled
## button. That is a different defect from "unobservable because nothing names it",
## and the two need different fixes, so both halves are asserted: the reason IS
## renderable, and the button IS disabled.
##
## **On the breakthrough, train and recovery legs the naming now reaches the player.**
## Those facades still answer `false`, but the body module publishes its refusals as
## named clauses (`unavailable`) and the screen joins them, so each cause reads as its
## own sentence: a missing pill names the pill, the terminal realm names the ladder's
## end, a missing recovery elixir names the elixir. The deviation is the one cause the
## screen cannot know before the roll, so it is read from the record
## (`attempt_outcome.reason`) — the branch this file keeps reachable.
##
## Every loop is bounded by a constant naming the condition it stops on. Every
## screen instantiated here is freed.

# --- The shipped surfaces -----------------------------------------------------

const BODY_SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const TRIBULATION_SCREEN := "res://src/ui/screens/tribulation_screen.tscn"

## Guards.
## Stops a wave driver whose phase machine stopped converging.
const WAVE_GUARD := 16
## Stops a comprehension grind that stopped reaching its floor.
const INSIGHT_GUARD := 4096
## Stops a refinement grind that stopped reaching its cap.
const REFINE_GUARD := 32
## Stops a count over the ladder that stopped ending.
const LADDER_GUARD := 64

# --- The shipped messages, named once -----------------------------------------
#
# Named rather than restated so a reword turns this file red instead of letting it
# pass against a copy of itself. Read from the screen SOURCE, so a message that
# drifts and a test that drifts together cannot hide.

## The named clauses the body module publishes for a refused breakthrough (ADR 0150).
const M_MISSING_PILL := "Missing breakthrough pill"
const M_NO_REALM_AHEAD := "Already at the highest realm"
## The named clause for a refused repair whose remedy is absent.
const M_NO_RECOVERY_ELIXIR := "No recovery elixir to spend"
## The deviation sentence the module authors for the record — the one cause the
## screen cannot know before the roll.
const M_DEVIATED := "The attempt into %s deviated; repair the wound before trying again"
## `BodyCultivationPanel.act_strengthen`'s one refusal line.
const M_NO_ELIXIR := "No channel elixir to spend"
## `BodyCultivationPanel.act_ascend`'s refusal line once an ascent IS owed.
const M_ASCENT_WILL_NOT_OPEN := "The ascent will not open"

## `WorldAnchor`'s sentinel for "there is no ascent to walk".
const NO_ASCENT := "No ascent begun"

# --- Fixtures ------------------------------------------------------------------

var _born: Array[Node] = []


func setup() -> void:
	_born.clear()


## Free everything a test instantiated. Called after EVERY test, so a test that
## returns early still releases its screen — which is the whole point of tracking
## them here rather than freeing at each call site.
func teardown() -> void:
	for node in _born:
		if is_instance_valid(node):
			node.free()
	_born.clear()


func _instantiate(scene_path: String) -> Control:
	var packed := load(scene_path) as PackedScene
	assert_ne(packed, null, "%s loads" % scene_path)
	if packed == null:
		return null
	var node := packed.instantiate() as Control
	assert_ne(node, null, "%s instantiates to a Control" % scene_path)
	if node == null:
		return null
	_born.append(node)
	return node


func _button(screen: Control, unique_name: String) -> Button:
	return screen.get_node_or_null("%%%s" % unique_name) as Button


## The message line the player reads, as the screen publishes it.
func _message(screen: Control) -> String:
	return String((screen.summary() as Dictionary).get("message", ""))


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _gate() -> int:
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


## A body-path hero with the body module attached the way `app/` attaches it.
func _body_hero(rank: StringName = &"qi_refining") -> Actor:
	var actor := Actor.new(&"observability_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, rank))
	actor.meridians.unlock_for_realm(rank)
	ItemsApi.attach(actor)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	return actor


## A body hero brought to the brink of its next realm, through the same field writes
## the shipped training uses. Needed wherever a refusal has to be reached PAST the
## preparation gate, because an unprepared hero is refused by a different guard.
func _prepared_hero(rank: StringName = &"qi_refining") -> Actor:
	var actor := _body_hero(rank)
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	assert_ne(target, null, "the ladder has a realm ahead of this hero")
	if target == null:
		return actor
	var seed := BodyRealmSeed.for_realm(target.id)
	assert_ne(seed, null, "that realm ships a body seed")
	if seed == null:
		return actor
	actor.meridians.unlock_for_realm(target.id)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.is_injured():
			actor.meridians.repair_meridian(meridian_id)
		actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
		# Bound FIRST, then the side-effecting call: 	est_no_unbounded_wait reads the
		# counter's position in the condition to see what terminates the loop, and a
		# call that mutates the actor ahead of the bound hides that from it.
		var refine := 0
		while (
			refine < REFINE_GUARD
			and actor.meridians.refine_meridian(meridian_id, seed.required_refinement)
		):
			refine += 1
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	points.fill(seed.integrity_maximum)
	state.progress = seed.progress_required
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		actor.stats.set_base(Stat.PHYSIQUE, seed.physique_required)
	var meditate := 0
	while (
		meditate < INSIGHT_GUARD
		and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required
	):
		meditate += 1
		BodyTraining.meditate(actor, 1.0)
	_stock(actor, seed.breakthrough_item)
	return actor


## One authored item into the actor's inventory, asserted rather than assumed.
func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory, null, "the actor carries an inventory")
	if inventory == null:
		return
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	inventory.add(def, quantity)


## How many copies of `item_id` the actor is holding, or 0.
func _held(actor: Actor, item_id: StringName) -> int:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return 0
	return inventory.count(item_id)


# --- 1. Breakthrough: four causes, one message --------------------------------


## **THE BREAKTHROUGH FINDING.** `BodyCultivationPanel.act_breakthrough` has ONE
## `else`, and its message names a DEVIATION. Three refusals that are not a
## deviation all reach it, and the player is told the attempt rolled badly.
##
## The three are chosen to be deterministic, so this is not a probabilistic claim:
##
##   no pill        refused at `consume_item`, nothing spent
##   no huyệt set   refused at `points == null`, nothing spent
##   no realm ahead refused at `_next_index`, nothing spent
##
## A deviation is the fourth cause and cannot be forced through the facade, which
## takes no rng — so that half is asserted from the sources instead: the screen's
## refusal reads the record (`attempt_outcome`), and the module authors the
## deviation sentence.
func test_four_different_refusals_each_name_their_own_cause() -> void:
	var screen := _instantiate(BODY_SCREEN)
	if screen == null:
		return

	# (1) The realm pill is absent. Everything else about the attempt is ready.
	var no_pill := _prepared_hero()
	_take_item(no_pill, _pill_id(no_pill))
	var refusal_pill := _press_breakthrough(screen, no_pill)

	# (2) No huyệt set at all, so the verb refuses before it can look at anything.
	var no_points := _body_hero()
	no_points.set_component(&"acupoints", null)
	var refusal_points := _press_breakthrough(screen, no_points)

	# (3) The terminal realm: no next realm exists to enter. Written directly rather
	# than prepared, because preparing a hero with nothing ahead of it is the one
	# thing `_prepared_hero` cannot do.
	var at_top := _body_hero(_realm_id(RealmDefaults.ladder().realms().size() - 1))
	var refusal_top := _press_breakthrough(screen, at_top)

	assert_eq(refusal_pill, M_MISSING_PILL, "a missing pill names the pill")
	assert_eq(
		refusal_points.contains("Acupoint quality below the realm requirement"),
		true,
		"a missing huyệt set names the acupoint requirement"
	)
	assert_eq(refusal_top, M_NO_REALM_AHEAD, "the terminal realm names the ladder's end")
	# The three are genuinely three sentences, which is the whole point: one message
	# for all of them was the loss this file originally measured.
	assert_ne(refusal_pill, refusal_points, "and the refusals read differently")
	assert_ne(refusal_pill, refusal_top, "each naming its own cause")
	assert_ne(refusal_points, refusal_top, "rather than sharing one sentence")
	# The three are genuinely three: each hero really is refused, and for a
	# different reason, which is what makes the single message a loss rather than
	# an accurate summary.
	assert_eq(BodyCultivationApi.attempt_breakthrough(no_pill), false, "the pill really is missing")
	assert_eq(
		BodyCultivationApi.attempt_breakthrough(no_points), false, "the huyệt set really is absent"
	)
	assert_eq(
		BodyCultivationApi.attempt_breakthrough(at_top),
		false,
		"the ladder really has no next realm"
	)
	# None of them moved, so nothing was spent: the refusal is free, which is the one
	# thing the message gets right.
	assert_eq(_held(no_pill, _pill_id(no_pill)), 0, "and the refused press spent nothing")
	# And the structural half: the one cause the screen cannot know before the roll is
	# read from the RECORD, and the module authors its sentence — so the deviation
	# branch stays reachable instead of collapsing into the clauses.
	var code := _code_of(BODY_SCREEN)
	assert_eq(
		_function_body(code, "_breakthrough_refusal").contains("attempt_outcome"),
		true,
		"the refusal falls back to the roll's record"
	)
	assert_eq(
		_function_body(code, "_resolve_refusal").contains("attempt_outcome"),
		true,
		"and the resolve half reads the record alone"
	)
	assert_eq(
		_code_of("res://src/modules/body_cultivation/refusal.gd").contains(M_DEVIATED),
		true,
		"and the module authors the deviation sentence"
	)


## The refusal is FREE — nothing spent, nothing moved — which is the property that
## makes the single message survivable rather than a data-loss defect. Asserted on
## its own because it is the thing that would break first if someone moved the pill
## consumption above a check.
func test_a_refused_breakthrough_costs_the_hero_nothing() -> void:
	var hero := _prepared_hero()
	var pill := _pill_id(hero)
	var held_before := _held(hero, pill)
	var rank_before := String(hero.path(BodyPath.PATH_ID).rank_id)
	assert_ne(held_before, 0, "the prepared hero really is holding its pill")
	# Take the pill away rather than leaving the hero unprepared, so the refusal is
	# the ITEM guard and nothing else: an unprepared hero would be refused by several
	# guards at once and would prove nothing about which one is free.
	_take_item(hero, pill)
	assert_eq(
		BodyCultivationApi.attempt_breakthrough(hero),
		false,
		"a press with nothing left to spend is refused"
	)
	assert_eq(_held(hero, pill), 0, "and spent no pill")
	assert_eq(String(hero.path(BodyPath.PATH_ID).rank_id), rank_before, "and moved no realm")


# --- 2. Recovery: the message contradicts the screen's own checklist ----------


## **THE FAIL-RECOVERABLY FINDING, FIXED.** A hero carrying a deviation and no elixir
## used to be told there is nothing to repair — on a screen whose own `unmet` line
## said the opposite, one property away. The refusal now names the missing remedy
## (ADR 0150): the wound is on the checklist and the elixir is in the message, so the
## screen agrees with itself and the player knows what to go and find.
func test_a_damaged_hero_with_no_elixir_is_told_the_elixir_is_missing() -> void:
	var hero := _prepared_hero()
	# A real deviation's wound: `BodyAdvancement._deviate` tears the required channel
	# the hero trained deepest and jams a huyệt on it. The tear is the one the
	# breakthrough checklist names, so this inflicts the TARGET realm's required
	# channel — which is the list `_wounded_channels` reads.
	var target_seed := BodyRealmSeed.for_realm(
		RealmDefaults.ladder().next(hero.path(BodyPath.PATH_ID).rank_id).id
	)
	var meridian_id := target_seed.required_meridians[0]
	hero.meridians.damage_meridian(meridian_id)
	assert_eq(
		hero.meridians.get_meridian(meridian_id).is_injured(),
		true,
		"the hero really is carrying an injured channel"
	)
	# The elixir is the CURRENT realm's, because `BodyTraining.recover` prices the
	# repair off the realm the hero is standing in, not the one it is aiming at.
	_take_item(hero, BodyRealmSeed.for_realm(hero.path(BodyPath.PATH_ID).rank_id).recovery_item)

	var screen := _instantiate(BODY_SCREEN)
	if screen == null:
		return
	screen.call("setup", hero)
	var unmet := (screen.summary() as Dictionary).get("unmet", []) as Array
	assert_eq(
		_clauses_about(unmet, "Damaged channels need repair").size(),
		1,
		"and the screen's own checklist says the wound is blocking the breakthrough"
	)
	var repaired: bool = screen.call("act_recover")
	assert_eq(repaired, false, "so recovery genuinely refuses")
	assert_eq(
		_message(screen),
		M_NO_RECOVERY_ELIXIR,
		"and the player is told the elixir is what is missing"
	)
	# The remedy is named in the published refusal DATA, not only in the sentence:
	# `unavailable.recover` carries the clause, so a screen renders the item without
	# re-deriving it.
	var published := BodyCultivationApi.panel_state(hero)
	var clauses: Array = (published.get("unavailable", {}) as Dictionary).get("recover", [])
	var labels: Array[String] = []
	for clause in clauses:
		labels.append(String((clause as Dictionary).get("label", "")))
	assert_eq(labels.has(M_NO_RECOVERY_ELIXIR), true, "and the published refusal names the elixir")


## With the elixir in hand the same press works and the message is right, so the
## failure above really is the MISSING ITEM and not a broken repair. A positive case
## beside a negative is what stops the negative proving only that recovery is broken.
func test_the_same_repair_succeeds_once_the_elixir_is_held() -> void:
	var hero := _prepared_hero()
	var target_seed := BodyRealmSeed.for_realm(
		RealmDefaults.ladder().next(hero.path(BodyPath.PATH_ID).rank_id).id
	)
	var meridian_id := target_seed.required_meridians[0]
	hero.meridians.damage_meridian(meridian_id)
	assert_eq(
		hero.meridians.get_meridian(meridian_id).is_injured(),
		true,
		"the hero carries an injured channel"
	)
	_stock(hero, BodyRealmSeed.for_realm(hero.path(BodyPath.PATH_ID).rank_id).recovery_item, 1)
	var screen := _instantiate(BODY_SCREEN)
	if screen == null:
		return
	screen.call("setup", hero)
	var repaired: bool = screen.call("act_recover")
	assert_eq(repaired, true, "with the elixir held, the same press repairs")
	assert_eq(_message(screen), "Repaired", "and says so")
	var unmet := (screen.summary() as Dictionary).get("unmet", []) as Array
	assert_eq(
		_clauses_about(unmet, "Damaged channels need repair"),
		[],
		"and the checklist no longer lists the wound"
	)


# --- 3. Training: two causes, one message -------------------------------------


## `act_strengthen` says "No channel elixir to spend" for a hero who has no elixir
## AND for a hero whose channels are already at the realm's cap. The second is a
## different situation with a different answer — there is nothing left to buy — and
## the message tells the player to go and find an item they do not need.
func test_strengthen_reports_a_missing_elixir_for_a_channel_already_at_its_cap() -> void:
	var hero := _prepared_hero()
	# Take the elixir away, so a refusal can only be about the cap.
	var seed := BodyRealmSeed.for_realm(hero.path(BodyPath.PATH_ID).rank_id)
	_take_item(hero, seed.strengthening_item)
	# Everything the realm trains is already trained by `_prepared_hero`, so there
	# is genuinely nothing left to train at this realm.
	var screen := _instantiate(BODY_SCREEN)
	if screen == null:
		return
	screen.call("setup", hero)
	var trained: bool = screen.call("act_strengthen")
	assert_eq(trained, false, "there is no channel left to train")
	assert_eq(
		_message(screen),
		M_NO_ELIXIR,
		"and the player is told to go and find an elixir they do not need"
	)


# --- 4. The ascent's refusal line is UNREACHABLE -------------------------------


## `act_ascend` has two refusals: "No ascent is owed yet" (offered but not owed) and
## "The ascent will not open" (owed, but the walk refused). The second is UNREACHABLE
## in play.
##
## `required` is `not ascension_ok(target)`, and at the only indices where it can be
## true `ascension_ok` is `actor.ascension != null and is_complete()`. So `required`
## with `steps == 0` — the only state that reaches the second message — requires an
## actor with NO ascent at all. The only thing that creates one is `WorldAnchor.commit`
## on entering R28, which `Breakthrough.try_advance` runs on every advance. A hero at
## R28 without an ascent is a hand-written rank, which is a test's privilege.
func test_the_ascent_will_not_open_line_needs_a_hand_written_rank() -> void:
	var hand_written := _body_hero(_realm_id(WorldAnchor.COMMIT_MICRO))
	assert_eq(hand_written.ascension, null, "a rank written by hand begins no ascent")
	var screen := _instantiate(BODY_SCREEN)
	if screen == null:
		return
	screen.call("setup", hand_written)
	var ascent := (screen.summary() as Dictionary).get("ascent", {}) as Dictionary
	assert_eq(bool(ascent["required"]), true, "and the screen therefore owes an ascent")
	assert_eq(int(ascent["steps"]), 0, "with nothing to walk")
	assert_eq(String(ascent["outstanding"]), NO_ASCENT, "which core states as a sentinel")
	var stepped: bool = screen.call("act_ascend")
	assert_eq(stepped, false, "so the walk refuses")
	assert_eq(
		_message(screen),
		M_ASCENT_WILL_NOT_OPEN,
		"and this is the ONLY state that reaches the 'will not open' line"
	)
	# The other half: the state a player actually reaches. Walking the ascent from a
	# committed one works, so the refusal above is the sentinel and not a broken verb.
	var earned := _body_hero(_realm_id(WorldAnchor.COMMIT_MICRO))
	WorldAnchor.commit(earned, WorldAnchor.COMMIT_MICRO)
	assert_ne(earned.ascension, null, "an actor that EARNED R28 has an ascent")
	var live := _instantiate(BODY_SCREEN)
	if live == null:
		return
	live.call("setup", earned)
	var walked: bool = live.call("act_ascend")
	assert_eq(walked, true, "and the same press walks it")


# --- 5. Tribulation: named, rendered, and behind a disabled button ------------


## **THE TRIBULATION OBSERVABILITY FINDING.** `TribulationScreen` renders a refusal's
## `reason` verbatim — the naming works. And `_offered` then disables the very
## control whose press would produce it, so no player ever gets to read it.
##
## Both halves are asserted, because they are different defects: the screen is not
## missing a renderer, it is hiding a control. A fix that only added prose would
## change nothing a player can reach.
func test_every_named_tribulation_refusal_sits_behind_a_disabled_button() -> void:
	var screen := _instantiate(TRIBULATION_SCREEN)
	if screen == null:
		return

	# (a) Nothing owed. The facade names the refusal; the control is dead.
	var mortal := _tribulation_hero(0)
	screen.call("setup", mortal)
	var before := screen.summary() as Dictionary
	assert_eq(
		String(HeavenlyTribulationApi.begin(mortal).get("reason", "")),
		"no realm above the Immortal gate is owed yet",
		"and the facade names why: the realm below the gate owes no fight"
	)
	assert_eq(bool((before["actions"] as Dictionary)["begin"]), false, "so Begin is not offered")
	assert_eq(
		_button(screen, "BeginButton").disabled,
		true,
		"and the button a player would press is disabled — so the reason is unreachable"
	)

	# (b) A fight already in the air. Same shape. `refresh` is called after the external
	# mutation because a button's `disabled` is whatever the LAST refresh set, and
	# `summary()` does not repaint — reading it without the refresh would assert the
	# state from BEFORE the press, which is a different and wrong claim.
	var hero := _tribulation_hero()
	screen.call("setup", hero)
	assert_eq(
		bool(HeavenlyTribulationApi.begin(hero).get("ok", false)), true, "Begin starts a fight"
	)
	screen.call("refresh")
	var during := screen.summary() as Dictionary
	assert_eq(
		bool((during["actions"] as Dictionary)["begin"]), false, "Begin is withdrawn once active"
	)
	assert_eq(
		_button(screen, "BeginButton").disabled,
		true,
		"so 'a tribulation is already in progress' is a reason no player can be shown"
	)

	# (c) No record at all: Fight is offered only while a record is active.
	var idle := _tribulation_hero()
	screen.call("setup", idle)
	assert_eq(
		bool((screen.summary() as Dictionary)["actions"]["fight"]),
		false,
		"Fight is not offered before a fight begins"
	)
	assert_eq(
		_button(screen, "FightButton").disabled,
		true,
		"so 'no tribulation has begun' is a reason no player can be shown"
	)

	# (d) A decided record: Fight and Withdraw both go dead.
	var done := _tribulation_hero()
	screen.call("setup", done)
	HeavenlyTribulationApi.begin(done)
	var guard := 0
	while guard < WAVE_GUARD and done.tribulation.outcome == Tribulation.OUTCOME_UNRESOLVED:
		guard += 1
		HeavenlyTribulationApi.fight_wave(done)
	assert_ne(done.tribulation.outcome, Tribulation.OUTCOME_UNRESOLVED, "the fight is decided")
	screen.call("refresh")
	var settled := screen.summary() as Dictionary
	assert_eq(
		bool((settled["actions"] as Dictionary)["fight"]), false, "Fight goes dead once decided"
	)
	assert_eq(bool((settled["actions"] as Dictionary)["withdraw"]), false, "and so does Withdraw")
	assert_eq(
		_button(screen, "FightButton").disabled,
		true,
		"so 'the tribulation is already decided' is a reason no player can be shown"
	)


## The other half of the same finding, and the reason it is a DISABLED-CONTROL defect
## rather than a missing-renderer one: drive the verb directly and the reason reaches
## the message line verbatim. The screen can render it. Nothing lets a player ask.
func test_the_tribulation_screen_does_render_a_refusals_reason_when_asked() -> void:
	var screen := _instantiate(TRIBULATION_SCREEN)
	if screen == null:
		return
	var mortal := _tribulation_hero(0)
	screen.call("setup", mortal)
	var began: bool = screen.call("act_begin")
	assert_eq(began, false, "Begin on a hero that owes nothing returns false")
	assert_eq(
		_message(screen),
		"no realm above the Immortal gate is owed yet",
		"and the reason reaches the player's message line verbatim"
	)
	assert_eq(
		String((screen.summary() as Dictionary).get("tone", "")),
		"error",
		"in the error tone, so it is styled as a refusal and not as a message"
	)


## What the screen DOES tell the player instead, so the fix is an addition rather
## than a replacement: the refusal's underlying FACT is published as data even when
## the reason is not shown. `owed` false is the honest answer "nothing to do here",
## and it is what the nav table should key a hint on.
func test_the_facts_behind_the_disabled_buttons_are_published_as_data() -> void:
	var screen := _instantiate(TRIBULATION_SCREEN)
	if screen == null:
		return
	var mortal := _tribulation_hero(0)
	screen.call("setup", mortal)
	var view := screen.summary() as Dictionary
	assert_eq(bool(view["owed"]), false, "nothing is owed")
	assert_eq(bool(view["gate_open"]), true, "and the gate reads open, so nothing is shut")
	assert_eq(bool(view["has_record"]), false, "with no fight in the air")
	assert_eq(String(view["target"]), "", "and no realm named")


# --- Helpers -------------------------------------------------------------------


## A body-path hero with the meridian network laid out, for the tribulation verbs.
func _tribulation_hero(index: int = -1) -> Actor:
	var at := _gate() - 1 if index < 0 else index
	var realm_id := _realm_id(at)
	var actor := Actor.new(&"observability_tribulation_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## The pill the hero's next realm's breakthrough spends, as the seed names it.
func _pill_id(hero: Actor) -> StringName:
	var target := RealmDefaults.ladder().next(hero.path(BodyPath.PATH_ID).rank_id)
	if target == null:
		return &""
	var seed := BodyRealmSeed.for_realm(target.id)
	return &"" if seed == null else seed.breakthrough_item


## Bind `hero` to `screen` and press Breakthrough, returning what the player reads.
func _press_breakthrough(screen: Control, hero: Actor) -> String:
	screen.call("setup", hero)
	var advanced: bool = screen.call("act_breakthrough")
	assert_eq(advanced, false, "the press was refused")
	return _message(screen)


## Take every copy of `item_id` out of the actor's inventory, asserted rather than
## assumed: a silent no-op here would make a "missing item" test prove nothing.
func _take_item(hero: Actor, item_id: StringName) -> void:
	if item_id == &"":
		return
	var inventory := ItemsApi.inventory(hero)
	assert_ne(inventory, null, "the actor carries an inventory")
	if inventory == null:
		return
	var held := inventory.count(item_id)
	while inventory.count(item_id) > 0:
		inventory.remove(item_id, 1)
	assert_eq(
		inventory.count(item_id),
		0,
		"every copy of '%s' was really removed (it started at %d)" % [String(item_id), held]
	)


## The unmet clauses naming `subject`, so a negative can name the gate refusing
## without also swallowing the body's own training work.
func _clauses_about(unmet: Array, subject: String) -> Array[String]:
	var found: Array[String] = []
	for clause in unmet:
		if String(clause).to_lower().contains(subject.to_lower()):
			found.append(String(clause))
	return found


## `source` with every comment line dropped, so prose about a shape is not the shape.
func _code_of(scene_path: String) -> String:
	var script_path := String(scene_path).replace(".tscn", ".gd")
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(script_path).split("\n"):
		if String(line).strip_edges().begins_with("#"):
			continue
		out.append(String(line))
	return "\n".join(out)


## The body of `func_name` in `source`: from its declaration to the next line at or
## below its indent. `""` when not found, which callers treat as a failure.
func _function_body(source: String, func_name: String) -> String:
	var lines := source.split("\n")
	var start := -1
	var indent := ""
	for index in lines.size():
		var line := String(lines[index])
		var stripped := line.strip_edges()
		if stripped.begins_with("func ") and stripped.contains("%s(" % func_name):
			start = index
			indent = line.substr(0, line.length() - stripped.length())
			break
	if start < 0:
		return ""
	var out: Array[String] = []
	for index in range(start + 1, lines.size()):
		var line := String(lines[index])
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		var here := line.substr(0, line.length() - stripped.length())
		if here.length() <= indent.length() and not stripped.begins_with("#"):
			break
		out.append(line)
	return "\n".join(out)


func _occurrences(haystack: String, needle: String) -> int:
	var count := 0
	var at := haystack.find(needle)
	while at >= 0 and count < LADDER_GUARD * 1024:
		count += 1
		at = haystack.find(needle, at + needle.length())
	return count
