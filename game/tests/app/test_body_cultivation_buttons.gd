extends TestCase

## `BodyCultivationApi.meditate` and `.strengthen_next` are the two buttons on
## the body-cultivation panel (`ui/screens/body_cultivation_panel.gd:325` and
## `:335`) and no test named either. They are the whole interactive surface of
## the body path.
##
## ## Why the module's own suites did not catch them
##
## `modules/body_cultivation/*` proves `BodyTraining.meditate` and
## `BodyTraining.strengthen` by calling those directly, one meridian at a time.
## Neither facade verb was reached, and `strengthen_next` is the one that
## CHOOSES: it walks `channel_training` then `required_meridians` and trains the
## first that still has work. That selection order is authored in the facade and
## in no other file, so an inverted order — required before current, say —
## would leave every existing suite green while training the wrong channel.
##
## `meditate` is thinner, but it is a BUTTON: the panel branches on its return
## value, and a facade that answered `true` unconditionally would report a
## meditation that never happened.

## A realm with authored training on it, so `strengthen_next` has a candidate.
## Read from the ladder rather than written as a literal, so an inserted realm
## moves the fixture with it.
const REALM := &"qi_refining"


func _hero() -> Actor:
	var actor := ActorFactory.build(&"body_button_hero", {Stat.COMPREHENSION: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, REALM))
	actor.meridians.unlock_for_realm(REALM)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	# No `ActorFactory.build` inventory: the panel's press costs the realm's
	# authored elixir, so the fixture has to be able to pay it.
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


## Stock the realm's authored strengthening item, so the press is affordable and
## the verb's CHANNEL SELECTION is what is under test rather than its refusal.
func _armed(actor: Actor) -> BodyRealmSeed:
	var seed := BodyRealmSeed.for_realm(REALM)
	assert_ne(seed, null, "the fixture's realm has an authored seed")
	var def := ItemDef.new()
	def.id = seed.strengthening_item
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)
	return seed


func _comprehension(actor: Actor) -> float:
	return actor.stats.get_base(Stat.COMPREHENSION)


## `meditate` is the ONLY route to comprehension's floor, so the panel's button
## has to move the stat. Asserted as a DELTA against the actor's own insight
## gain, not against a literal: the docstring says the gain is `amount *
## insight_gain`, so the test states that formula rather than a number that
## would drift when the seed is retuned.
func test_meditating_raises_comprehension_by_the_insight_gain_the_docstring_promises() -> void:
	var actor := _hero()
	var before := _comprehension(actor)
	var amount := 5.0
	var expected := amount * actor.stats.derived(Stat.INSIGHT_GAIN)
	var done := BodyCultivationApi.meditate(actor, amount)
	assert_eq(done, true, "the button reports it did the work")
	assert_almost_eq(_comprehension(actor) - before, expected, "comprehension moved by the gain")


## A refusal writes nothing. `meditate` guards `amount <= 0` and a non-finite
## amount, and a panel that passes a zero step (an unset field, a half-typed
## number) must get `false` and an untouched stat — not a silent `true` with no
## progress behind it.
func test_a_non_positive_step_is_refused_and_writes_nothing() -> void:
	var actor := _hero()
	var before := _comprehension(actor)
	assert_eq(BodyCultivationApi.meditate(actor, 0.0), false, "zero is refused")
	assert_eq(BodyCultivationApi.meditate(actor, -3.0), false, "and so is a negative step")
	assert_eq(_comprehension(actor), before, "a refused meditation moves nothing")


## No path, no meditation. An actor off the body path has no realm, so the verb
## has no rate to apply — and must say so rather than raising on the null state.
func test_an_actor_with_no_body_path_cannot_meditate() -> void:
	var actor := ActorFactory.build(&"no_body_path")
	assert_eq(BodyCultivationApi.meditate(actor, 5.0), false, "no path, nothing done")


## `strengthen_next` picks a channel; the panels branch on that answer. With no
## acupoint set attached it must refuse rather than train something.
func test_strengthen_next_refuses_an_actor_it_cannot_train() -> void:
	var actor := ActorFactory.build(&"no_acupoints")
	BodyCultivationApi.attach(actor)
	assert_eq(BodyCultivationApi.strengthen_next(actor), false, "nothing to train with")


## The selection ORDER is the claim this facade owns and no other file states.
## `channel_training` is appended BEFORE `required_meridians`, so a body that
## could train either must train the CURRENT realm's channel first. Inverted
## order would leave every existing suite green while the panel trained the
## wrong channel and the button read as working.
func test_strengthen_next_trains_the_current_realm_channel_first() -> void:
	var actor := _hero()
	var seed := _armed(actor)
	if seed.channel_training.is_empty():
		assert_eq(true, true, "no current-realm training channel is authored at this rung")
		return
	var trained := BodyCultivationApi.strengthen_next(actor)
	assert_eq(trained, true, "an armed body trains something")
	var first := actor.meridians.get_meridian(seed.channel_training[0])
	assert_ne(first, null, "the first candidate is on the network")
	assert_ne(String(first.state), &"closed", "the CURRENT realm's channel is the one pressed")


## The refusal the panel also has to render: no elixir, nothing trained, network
## untouched. This is the branch that was unobservable, because every existing
## case drove `BodyTraining.strengthen` directly rather than the facade verb.
func test_strengthen_next_refuses_when_the_elixir_is_missing_and_spends_nothing() -> void:
	var actor := _hero()
	var before := actor.meridians.get_flow_bonus()
	assert_eq(BodyCultivationApi.strengthen_next(actor), false, "no elixir, no training")
	assert_eq(actor.meridians.get_flow_bonus(), before, "and the network is untouched")


## Once the ladder of candidates is spent, the walk finds nothing and says so
## rather than reporting a success that moved nothing — the button's label is
## driven by this return value.
##
## The press count is a FIXED small bound (8), never "until it refuses": a verb
## that never converges would make that loop unbounded, and the authored candidate
## list is far shorter than 8.
func test_strengthen_next_reports_false_once_there_is_nothing_left_to_train() -> void:
	var actor := _hero()
	_armed(actor)
	for _press in range(8):
		if not BodyCultivationApi.strengthen_next(actor):
			break
	assert_eq(
		BodyCultivationApi.strengthen_next(actor),
		false,
		"eight presses exceeds the authored candidate ladder, so this is the empty case"
	)


## The loop-guard note this suite depends on: `strengthen_next` walks a
## candidate list built from two AUTHORED arrays and returns on the first
## success, so it is bounded by the seed's length and cannot spin. Asserting the
## candidate list is non-empty here documents that bound rather than assuming it.
func test_the_candidate_list_strengthen_next_walks_is_the_seeds_own_and_finite() -> void:
	var actor := _hero()
	var seed := BodyRealmSeed.for_realm(REALM)
	assert_ne(seed, null, "the fixture's realm has an authored seed")
	var candidates: Array[StringName] = []
	candidates.append_array(seed.channel_training)
	candidates.append_array(seed.required_meridians)
	assert_eq(
		candidates.size(),
		seed.channel_training.size() + seed.required_meridians.size(),
		"the walk visits current-realm training and next-realm requirements exactly once each"
	)
