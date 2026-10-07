extends TestCase

## The qi screen's refusals name the PRICE, and never deny a wound that is there
## (ADR 0150).
##
## `act_recover` rendered every refusal as one sentence:
##
## ```
## "Repaired" if repaired else "Nothing damaged to repair"
## ```
##
## so a hero carrying a burned channel and no recovery elixir — the seventh leg of the
## acceptance gate, the recoverable deviation — was told there was nothing wrong with
## them. That is the one answer that cannot be true, and it sent the player looking
## for a wound that did not exist instead of buying the elixir that closes the one
## they had.
##
## `act_train_next_channel` had the mirror defect: a refused press read "No channel
## left to train" for every cause, including a player who had simply spent their
## elixirs — while the same screen's `unmet` line listed the channels still owed.
##
## **What is asserted here is the CONTRACT, not the prose** (ADR 0150: the screen
## renders the name it is given and says nothing it cannot back):
##
##  - a wound present  -> the message must NOT deny it, and must name a price;
##  - no wound present -> the message must NOT name a price, because none is owed.
##
## A test that pinned one exact sentence would fail the moment another agent reworded
## a correct refusal, and a reword is not the defect. Both invariants below go red when
## the denial sentence is restored.
##
## Driven as a player drives them: `act_recover()` / `act_train_next_channel()` on the
## instantiated screen, reading the message off `summary()`.

const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"

## The sentence the defect printed, verbatim. Named once so the negative is about this
## exact string.
const DENIAL := "Nothing damaged to repair"

const PATH := QiPath.PATH_ID


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


func _actor() -> Actor:
	var actor := Actor.new(
		&"qi_truth_hero", {Stat.COMPREHENSION: 10.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	QiTraining.synchronize(actor)
	return actor


func _seed(actor: Actor) -> QiRealmSeed:
	return QiRealmSeed.for_realm(actor.path(PATH).rank_id)


func _message(screen: QiCultivationScreen) -> String:
	return String(screen.summary().get("message", ""))


func _mentions_a_price(message: String) -> bool:
	return message.to_lower().contains("elixir")


func _mentions_the_recovery_price(message: String) -> bool:
	return message.to_lower().contains("recovery")


func _claims_no_work_is_left(message: String) -> bool:
	return message.to_lower().contains("no channel left")


func _burn_every_channel(actor: Actor) -> void:
	## The whole network, not one channel: the price the facade publishes is read off
	## the FIRST channel still owed, so burning a single arbitrary channel would leave
	## the discriminator resting on the candidate order. Bounded by the actor's own
	## network — a fixed list this loop does not grow.
	for channel in actor.meridians.get_all_meridians():
		actor.meridians.damage_meridian(channel.id)


func _burn_first_channel(actor: Actor) -> void:
	## ONE wound, which is what a single deviation leaves: `recover_next` closes one
	## wound per elixir, so "the wound is closed and there is nothing left" needs the
	## network to hold exactly one.
	for channel in actor.meridians.get_all_meridians():
		actor.meridians.damage_meridian(channel.id)
		return


# --- act_recover -------------------------------------------------------------


## The defect, exactly: damage present, no elixir, and the screen says the damage
## does not exist.
func test_a_refused_recovery_names_the_price_when_a_channel_is_burned() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	_burn_every_channel(actor)
	assert_eq(screen.act_recover(), false, "no elixir, no repair")
	var said := _message(screen)
	assert_eq(said == DENIAL, false, "a burn must not be denied (%s)" % said)
	assert_eq(_mentions_a_price(said), true, "the price is named (%s)" % said)
	assert_eq(_mentions_the_recovery_price(said), true, "and it is the wound's price (%s)" % said)
	screen.free()


## The qi deviation scars the dantian as well as burning a channel, and `recover`
## closes both. A player in that state with no elixir is owed a purchase, so the
## refusal has to say so on the scar alone — the scar is a second, independent source
## of the same false sentence.
func test_a_refused_recovery_names_the_price_when_the_dantian_is_scarred() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var dantian := QiTestKit.dantian(actor)
	assert_ne(dantian, null, "the dantian is attached")
	dantian.damage(actor)
	assert_eq(screen.act_recover(), false, "no elixir, no repair")
	var said := _message(screen)
	assert_eq(said == DENIAL, false, "a scar must not be denied (%s)" % said)
	assert_eq(_mentions_a_price(said), true, "a scar with no elixir is a purchase (%s)" % said)
	screen.free()


## The other branch, so the screen cannot pass by always naming a price: with nothing
## wrong there is nothing to buy, and naming one would invent a debt the player does
## not owe.
func test_a_refused_recovery_with_nothing_wrong_names_no_price() -> void:
	var screen := _screen()
	screen.setup(_actor())
	assert_eq(screen.act_recover(), false, "nothing to repair")
	var said := _message(screen)
	assert_ne(said.is_empty(), true, "the refusal says something")
	assert_eq(_mentions_a_price(said), false, "and invents no purchase (%s)" % said)
	screen.free()


## The reachability proof. Every damage state a qi hero can actually be driven into,
## with an empty pack, the denial sentence must not appear — and in the states where
## there IS no damage it is allowed to, because there it is true.
##
## Enumerated by `for` over a fixed list this suite writes out — the loop appends
## nothing and tests no size of its own.
func test_the_denial_sentence_is_unreachable_wherever_damage_exists() -> void:
	var states := [&"healthy", &"burned_channel", &"scarred_dantian", &"scar_and_burn"]
	for state in states:
		var screen := _screen()
		var actor := _actor()
		screen.setup(actor)
		match state:
			&"burned_channel":
				_burn_every_channel(actor)
			&"scarred_dantian":
				QiTestKit.dantian(actor).damage(actor)
			&"scar_and_burn":
				_burn_every_channel(actor)
				QiTestKit.dantian(actor).damage(actor)
		assert_eq(screen.act_recover(), false, "%s refuses an empty pack" % state)
		if state != &"healthy":
			assert_eq(_message(screen) == DENIAL, false, "%s must not be told %s" % [state, DENIAL])
		screen.free()


## And the true branch is still reachable and still true: once the wound is closed and
## the elixir spent, a further press has nothing to repair, and then — and only then —
## no purchase is owed. The fix is not dead code dressed as one.
func test_the_nothing_to_repair_branch_is_reachable_once_the_wound_is_closed() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var seed := _seed(actor)
	_burn_first_channel(actor)
	var def := Crafting.resolve(seed.recovery_item)
	assert_ne(def, null, "authored item %s exists" % seed.recovery_item)
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(screen.act_recover(), true, "the wound closes")
	assert_eq(screen.act_recover(), false, "and a second press has nothing left")
	var said := _message(screen)
	assert_eq(_mentions_a_price(said), false, "no purchase is owed (%s)" % said)
	assert_ne(said.is_empty(), true, "and the press is still explained")
	screen.free()


# --- act_train_next_channel --------------------------------------------------


## The price is a function of the STATE, and a burn is the discriminator: the facade
## publishes the recovery role because `train_channel` hands a burn to `recover`
## (ADR 0141). So an empty pack plus a burned network must name the wound's elixir.
func test_the_train_button_names_the_recovery_elixir_for_a_burn() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	_burn_every_channel(actor)
	var owed := int(QiCultivationApi.panel_state(actor).get("owed_channels", 0))
	assert_eq(owed > 0, true, "the gate is not met, so channels are owed")
	assert_eq(screen.act_train_next_channel(), false, "no elixir, no training")
	var said := _message(screen)
	assert_eq(
		_mentions_the_recovery_price(said),
		true,
		"a burn is priced by the recovery elixir (%s)" % said
	)
	assert_eq(said.contains(str(owed)), true, "and the outstanding count is reported (%s)" % said)
	assert_eq(_claims_no_work_is_left(said), false, "never 'nothing left' (%s)" % said)
	screen.free()


## The other price, so the button cannot pass by always naming one.
func test_the_train_button_names_the_channel_elixir_for_a_healthy_channel() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var owed := int(QiCultivationApi.panel_state(actor).get("owed_channels", 0))
	assert_eq(owed > 0, true, "the gate is not met, so channels are owed")
	assert_eq(screen.act_train_next_channel(), false, "no elixir, no training")
	var said := _message(screen)
	assert_eq(_mentions_a_price(said), true, "a price is named (%s)" % said)
	assert_eq(
		_mentions_the_recovery_price(said),
		false,
		"and it is the channel elixir, not the wound's (%s)" % said
	)
	assert_eq(said.contains(str(owed)), true, "and the outstanding count is reported (%s)" % said)
	screen.free()


## The terminal branch the defect used to reach wrongly. It says "no channel left"
## only where every candidate already met the gate — where it is true — so a player
## out of elixirs is never sent looking for content that exists.
func test_the_nothing_left_branch_is_never_reached_while_a_channel_is_owed() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	# Out of both elixirs, and every channel on the network still below the gate — the
	# exact state the old terminal message was printed in.
	_burn_every_channel(actor)
	assert_eq(screen.act_train_next_channel(), false, "no elixir, no training")
	var said := _message(screen)
	assert_eq(_mentions_a_price(said), true, "the price is named (%s)" % said)
	assert_eq(
		_claims_no_work_is_left(said),
		false,
		"and the one answer that cannot be true is never printed (%s)" % said
	)
	screen.free()
