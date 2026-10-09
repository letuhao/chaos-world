extends TestCase

## The body screen's refusals name the PRICE, and never deny a wound that is there
## (ADR 0150, which names this panel as the worst instance of the collapse).
##
## `act_recover` rendered every refusal as one sentence:
##
## ```
## "Repaired" if repaired else "Nothing damaged to repair"
## ```
##
## and ADR 0150's own words for why that cannot stand: "a hero with damaged channels
## and no repair elixir is told *Nothing damaged to repair* — while the same screen's
## `unmet` line, rendered from the same `panel_state`, says the opposite." The screen
## contradicted itself on the fail-recoverably leg of the acceptance gate, and the real
## cause — the missing elixir — was named nowhere on it.
##
## `act_strengthen` carried the same collapse for a second reason: since a burn is
## priced by the realm's recovery elixir (ADR 0141), "No channel elixir to spend"
## became false in exactly the state the module fix creates.
##
## **What is asserted here is the CONTRACT, not the prose** (ADR 0150: the screen
## renders the name it is given and says nothing it cannot back):
##
##  - a wound present  -> the message must NOT deny it, and must name a price;
##  - no wound present -> the message must NOT name a price, because none is owed.
##
## A test pinning one exact sentence would fail the moment a correct refusal was
## reworded, and a reword is not the defect. Both invariants go red when the denial
## sentence is restored.
##
## Driven as a player drives them: the instantiated panel's `act_recover()` /
## `act_strengthen()`, reading the message off `summary()`.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"

## The sentence the defect printed, verbatim. Named once so the negative is about this
## exact string.
const DENIAL := "Nothing damaged to repair"

const PATH := BodyPath.PATH_ID


func _screen() -> BodyCultivationPanel:
	var panel := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(panel, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	return panel


func _actor() -> Actor:
	var actor := ActorFactory.with_body_cultivation(
		Actor.new(&"body_truth_hero", {Stat.PHYSIQUE: 20.0})
	)
	ItemsApi.attach(actor, 64)
	BodyTraining.synchronize(actor)
	return actor


func _seed(actor: Actor) -> BodyRealmSeed:
	return BodyRealmSeed.for_realm(actor.path(PATH).rank_id)


func _message(panel: BodyCultivationPanel) -> String:
	return String(panel.summary().get("message", ""))


func _mentions_a_price(message: String) -> bool:
	return message.to_lower().contains("elixir")


func _mentions_the_recovery_price(message: String) -> bool:
	return message.to_lower().contains("recovery")


## The first channel `strengthen_next` offers, read from the seed's own candidate
## list, so the fixture and the verb agree on which channel is pressed first — which is
## what decides the price the panel reports. Bounded by that fixed list.
func _first_candidate(actor: Actor) -> StringName:
	var seed := _seed(actor)
	if seed == null:
		return &""
	if not seed.channel_training.is_empty():
		return seed.channel_training[0]
	return seed.required_meridians[0] if not seed.required_meridians.is_empty() else &""


## Tear EVERY channel on this actor's network, not one. `strengthen_next` walks past a
## torn channel to the next healthy one, so a single tear would have been trained with
## the channel elixir on a later candidate and the panel would have had no refusal to
## report at all. Bounded by the network the actor has unlocked — a fixed list this
## loop does not grow.
func _tear_every_channel(actor: Actor) -> void:
	for channel in actor.meridians.get_all_meridians():
		actor.meridians.damage_meridian(channel.id)


## Jam one acupoint on `meridian_id`, and report its id so the assertion can name it.
func _jam_a_huyet(actor: Actor, meridian_id: StringName) -> StringName:
	for point in BodyCultivationApi.acupoints(actor):
		if AcupointDefaults.meridian_of(point.id) == meridian_id:
			point.block()
			return point.id
	return &""


# --- act_recover -------------------------------------------------------------


## The defect, exactly: a torn channel, no elixir, and the panel says nothing is
## damaged.
func test_a_refused_recovery_names_the_price_when_a_channel_is_torn() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	actor.meridians.damage_meridian(_first_candidate(actor))
	assert_eq(panel.act_recover(), false, "no elixir, no repair")
	var said := _message(panel)
	assert_eq(said == DENIAL, false, "a tear must not be denied (%s)" % said)
	assert_eq(_mentions_a_price(said), true, "the price is named (%s)" % said)
	assert_eq(_mentions_the_recovery_price(said), true, "and it is the wound's price (%s)" % said)
	panel.free()


## The other wound this panel's recovery verb closes. A jam with no elixir is a
## purchase to make, and `panel_state` publishes the blocked count, so the refusal can
## be truthful from the facade's own report.
func test_a_refused_recovery_names_the_price_when_a_huyet_is_jammed() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	var point_id := _jam_a_huyet(actor, _first_candidate(actor))
	assert_ne(point_id, &"", "a acupoint on this meridian exists")
	assert_eq(panel.act_recover(), false, "no elixir, no repair")
	var said := _message(panel)
	assert_eq(said == DENIAL, false, "a jam must not be denied (%s)" % said)
	assert_eq(_mentions_a_price(said), true, "a jam with no elixir is a purchase (%s)" % said)
	panel.free()


## The other branch, so the panel cannot pass by always naming a price: with nothing
## wrong there is nothing to buy, and naming one would invent a debt the player does
## not owe.
func test_a_refused_recovery_with_nothing_wrong_names_no_price() -> void:
	var panel := _screen()
	panel.setup(_actor())
	assert_eq(panel.act_recover(), false, "nothing to repair")
	var said := _message(panel)
	assert_ne(said.is_empty(), true, "the refusal says something")
	assert_eq(_mentions_a_price(said), false, "and invents no purchase (%s)" % said)
	panel.free()


## The reachability proof. Every damage state a body hero can actually be driven into,
## with an empty pack, and the denial sentence must not appear in any of them.
## Enumerated by `for` over a fixed list this suite writes out — the loop appends
## nothing and tests no size of its own.
##
## **THE `healthy` CASE IS NOT IN THIS LIST, AND THAT IS THE POINT.** This
## assertion used to sweep `healthy` in with the rest and demanded the denial
## sentence never appeared at all — which is only satisfiable by refusing to say it
## even when it is TRUE. Now that the module publishes the cause (ADR 0150), the
## denial is published exactly where it holds, so the sweep became an assertion that
## the screen lies in the one state where it does not.
##
## `test_the_panel_says_nothing_is_damaged_when_nothing_is_damaged` covers `healthy`
## from the other side: the same sentence, asserted as the truth it now is.
func test_the_denial_sentence_is_unreachable_in_every_state_a_player_can_be_in() -> void:
	var states := [&"torn_channel", &"jammed_huyet", &"tear_and_jam"]
	for state in states:
		var panel := _screen()
		var actor := _actor()
		panel.setup(actor)
		var meridian_id := _first_candidate(actor)
		match state:
			&"torn_channel":
				actor.meridians.damage_meridian(meridian_id)
			&"jammed_huyet":
				_jam_a_huyet(actor, meridian_id)
			&"tear_and_jam":
				actor.meridians.damage_meridian(meridian_id)
				_jam_a_huyet(actor, meridian_id)
		assert_eq(panel.act_recover(), false, "%s refuses an empty pack" % state)
		assert_eq(_message(panel) == DENIAL, false, "%s must not be told %s" % [state, DENIAL])
		# A refused press spends nothing and closes nothing: measured on the wound,
		# not only on the message, because a refusal that quietly repaired would be
		# a different defect wearing the same screen.
		var left: int = BodyCultivationApi.panel_state(actor).get("blocked", 0)
		var still_wrong := left > 0
		still_wrong = still_wrong or actor.meridians.get_meridian(meridian_id).is_injured()
		assert_eq(still_wrong, true, "%s is untouched by the refusal" % state)
		panel.free()


## The other branch, asserted as a FACT rather than as an absence: with nothing
## damaged, the sentence the defect used for every cause is the true one, and it is
## what the screen says. Without this the fix could pass by never naming anything.
func test_the_panel_says_nothing_is_damaged_when_nothing_is_damaged() -> void:
	var panel := _screen()
	panel.setup(_actor())
	assert_eq(panel.act_recover(), false, "nothing is damaged")
	assert_eq(_message(panel), DENIAL, "so the screen says so, in those words")
	panel.free()


## And the true branch is still reachable and still true: once the wound is closed and
## the elixir spent, a further press has nothing to repair, so no purchase is named.
## The fix is not dead code dressed as one.
func test_the_nothing_to_repair_branch_is_reachable_once_the_wound_is_closed() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	var seed := _seed(actor)
	actor.meridians.damage_meridian(_first_candidate(actor))
	var def := Crafting.resolve(seed.recovery_item)
	assert_ne(def, null, "authored item %s exists" % seed.recovery_item)
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(panel.act_recover(), true, "the wound closes")
	assert_eq(panel.act_recover(), false, "and a second press has nothing left")
	var said := _message(panel)
	assert_eq(_mentions_a_price(said), false, "no purchase is owed (%s)" % said)
	assert_ne(said.is_empty(), true, "and the press is still explained")
	panel.free()


## ADR 0150's own contradiction, pinned: the message line names the price and the gate
## line names the wound, so the panel can no longer disagree with itself about whether
## anything is wrong.
func test_the_panel_no_longer_contradicts_its_own_gate_line() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	var meridian_id := _first_candidate(actor)
	var point_id := _jam_a_huyet(actor, meridian_id)
	assert_ne(point_id, &"", "a acupoint on this meridian exists")
	var blocked_before: int = BodyCultivationApi.panel_state(actor).get("blocked", 0)
	assert_eq(blocked_before > 0, true, "the facade reports the jam")
	assert_eq(panel.act_recover(), false, "no elixir, no repair")
	var said := _message(panel)
	assert_eq(_mentions_a_price(said), true, "the message names the price (%s)" % said)
	var blocked_after: int = BodyCultivationApi.panel_state(actor).get("blocked", 0)
	assert_eq(
		blocked_after, blocked_before, "and the wound is still there, as the message said it was"
	)
	panel.free()


# --- act_strengthen ----------------------------------------------------------


## A burn is priced by the realm's RECOVERY elixir (ADR 0141), so a hero holding only
## the channel elixir and standing on a torn channel is refused for the OTHER item.
## The panel used to name the one the player was not missing.
func test_a_refused_strengthen_names_the_recovery_elixir_for_a_torn_channel() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	var seed := _seed(actor)
	_tear_every_channel(actor)
	# Only the wrong elixir: exactly the one the panel must NOT name.
	var elixir := Crafting.resolve(seed.strengthening_item)
	assert_ne(elixir, null, "authored item %s exists" % seed.strengthening_item)
	ItemsApi.inventory(actor).add(elixir, 1)
	assert_eq(panel.act_strengthen(), false, "no recovery elixir, no repair")
	var said := _message(panel)
	assert_eq(
		_mentions_the_recovery_price(said), true, "the burn's price, not the ladder's (%s)" % said
	)
	assert_eq(
		said.to_lower().contains("channel elixir"),
		false,
		"and never the elixir the player is holding (%s)" % said
	)
	panel.free()


## The other price, so the panel cannot pass by always naming one.
func test_a_refused_strengthen_names_the_channel_elixir_for_a_healthy_channel() -> void:
	var panel := _screen()
	panel.setup(_actor())
	assert_eq(panel.act_strengthen(), false, "no elixir, no training")
	var said := _message(panel)
	assert_eq(_mentions_a_price(said), true, "a price is named (%s)" % said)
	assert_eq(
		_mentions_the_recovery_price(said),
		false,
		"and it is the channel elixir, not the wound's (%s)" % said
	)
	panel.free()
