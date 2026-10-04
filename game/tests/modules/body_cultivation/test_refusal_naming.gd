extends TestCase

## ADR 0150's guard, and the check that would have caught the seventh-leg
## contradiction: **a `false` from a player-facing body verb ALWAYS has a name the
## screen can render.**
##
## Before this file existed the guarantee was prose. `body_cultivation_panel.gd`
## rendered four distinct refusals as one sentence, so a hero with a torn channel and
## no recovery elixir was told *"Nothing damaged to repair"* while the same screen's
## gate line, read from the same `panel_state`, said `Damaged channels need repair:
## lung`. Nothing asserted that the two could not disagree, which is why they did.
##
## What is asserted here is the INVARIANT, not the wording: a `false` implies a name,
## and every published clause carries a label a screen can render. **The other
## direction is not claimed and must not be** — see
## `test_a_verb_that_succeeds_may_still_publish_a_complaint`.
##
## The reports are also asserted PURE, because `panel_state` calls them on every
## repaint and a read model that consumed would be an action in disguise.
##
## Everything is driven through the PUBLIC FACADE on an actor `BodyPlayFixture`
## prepared through public actions, so a guard cannot pass against a body no player
## can be in.

const PATH := BodyPath.PATH_ID

## The damage states a body hero can be driven into, by name, so a failure says which
## state lost its name rather than "some state". A fixed list: the loops below test
## nothing of their own making.
const DAMAGE_STATES := [&"healthy", &"torn", &"jammed", &"torn_and_jammed"]

## Every player-facing verb `panel_state` publishes a refusal for.
const VERBS := ["cultivate", "recover", "strengthen", "breakthrough"]

var _play: BodyPlayFixture


func setup() -> void:
	_play = BodyPlayFixture.new()


func _hero() -> Actor:
	return _play.actor()


## The first channel the facade would offer, from the list the verb itself walks.
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


func _unavailable(actor: Actor, verb: String) -> Array:
	return (
		(BodyCultivationApi.panel_state(actor).get("unavailable", {}) as Dictionary).get(verb, [])
		as Array
	)


func _kinds(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String((entry as Dictionary).get("kind", "")))
	return out


func _labels(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String((entry as Dictionary).get("label", "")))
	return out


## Drive one verb through the facade and report whether it refused.
func _refuses(actor: Actor, verb: String) -> bool:
	match verb:
		"recover":
			return not BodyCultivationApi.recover_next(actor)
		"strengthen":
			return not BodyCultivationApi.strengthen_next(actor)
		"cultivate":
			return not BodyCultivationApi.cultivate(actor, 25.0)
		_:
			return not BodyCultivationApi.attempt_breakthrough(actor)


## A clause a screen cannot render is a clause that was not published, so the label is
## part of the shape rather than a nicety. An empty list passes: there is nothing to
## render, which is a different question.
func _every_label_present(entries: Array) -> bool:
	return not _labels(entries).has("")


func _seed(actor: Actor) -> BodyRealmSeed:
	return BodyRealmSeed.for_realm(actor.path(PATH).rank_id)


## A hero prepared to the brink of its next realm with an EMPTY PACK, except for the pill
## the attempt itself is priced by.
##
## **The pack is emptied deliberately.** `BodyPlayFixture.prepare` stocks each elixir just
## before it spends one, so it leaves both elixirs behind — and a case about a MISSING elixir
## must not inherit one. Each case then stocks exactly the price it means to test, so "which
## price is named" is decided by the case rather than by what the fixture happened to leave.
##
## **A PRICE IS THE CURRENT REALM'S, NOT THE TARGET'S.** `BodyPlayFixture.seed_for` answers
## the NEXT realm (the pill a breakthrough is priced by), which is the wrong answer for an
## elixir: `strengthen` and `recover` charge the realm the actor is standing in. Reading one
## for the other stocks an item nothing will ever consume.
func _prepared(with_pill: bool = true) -> Actor:
	var actor := _hero()
	_play.prepare(actor)
	# The pill is the ONE price the target realm owns, so it is read through the fixture's
	# `seed_for` (which answers the next realm) rather than through `_seed`.
	var target := _play.seed_for(actor)
	var pill: StringName = &"" if target == null else target.breakthrough_item
	ItemsApi.inventory(actor).clear()
	if with_pill and pill != &"":
		_play.stock(actor, pill)
	return actor


# --- THE INVARIANT ------------------------------------------------------------


## The invariant, run over enough states to be awkward: for every damage state and
## every player-facing verb, **a `false` implies a name**, and every published clause
## carries a renderable label.
##
## A fresh hero per verb, because `_refuses` may spend, fill or roll: a verb that
## mutates must not hand the next verb a state it did not start in.
func test_a_refusal_always_has_a_name_on_the_read_model() -> void:
	for state in DAMAGE_STATES:
		for verb in VERBS:
			var actor := _hero()
			_damage(actor, state)
			var refused := _refuses(actor, verb)
			var named := _unavailable(actor, verb)
			if refused:
				assert_eq(
					named.is_empty(),
					false,
					"%s: %s returned false with an EMPTY unavailable list" % [state, verb]
				)
			assert_eq(
				_every_label_present(named),
				true,
				"%s/%s: every clause carries a label" % [state, verb]
			)


## `unavailable` is not an occasional key: it is on every repaint, for every verb, and
## reading it changes nothing. Asserted as one test because the failure mode it rules
## out — a report that quietly spent — needs the item counts and the body state
## together to be visible.
func test_reading_the_reports_spends_nothing() -> void:
	var actor := _prepared()
	actor.meridians.damage_meridian(_first_candidate(actor))
	_jam(actor, _first_candidate(actor))
	var home := _seed(actor)
	assert_ne(home, null, "the realm authors a recovery price")
	_play.stock(actor, home.recovery_item)
	var meridian_id := _first_candidate(actor)
	var pack := ItemsApi.inventory(actor)
	var before := {
		"recovery": pack.count(home.recovery_item),
		"strengthening": pack.count(home.strengthening_item),
		"injured": actor.meridians.get_meridian(meridian_id).is_injured(),
		"blocked": int(BodyCultivationApi.panel_state(actor).get("blocked", 0)),
		"progress": float(actor.path(PATH).progress),
		"attempt": String(BodyCultivationApi.panel_state(actor).get("attempt", "")),
	}
	for _read in 8:
		var view := BodyCultivationApi.panel_state(actor)
		for verb in VERBS:
			assert_ne(
				(view.get("unavailable", {}) as Dictionary).has(verb),
				false,
				"%s is published for every player-facing verb" % verb
			)
	var after := BodyCultivationApi.panel_state(actor)
	assert_eq(pack.count(home.recovery_item), before["recovery"], "no recovery elixir spent")
	assert_eq(
		pack.count(home.strengthening_item), before["strengthening"], "no channel elixir spent"
	)
	assert_eq(
		actor.meridians.get_meridian(meridian_id).is_injured(), before["injured"], "no repair"
	)
	assert_eq(int(after.get("blocked", 0)), before["blocked"], "no jam cleared")
	assert_eq(float(actor.path(PATH).progress), before["progress"], "no progress spent")
	assert_eq(String(after.get("attempt", "")), before["attempt"], "and no attempt committed")


## The other direction of the union, stated so the next agent does not "fix" it: a verb
## that ACTED may still publish complaints. One capped channel and one trainable channel
## both appear while `strengthen_next` succeeds on the second, and a report that hid
## the cap to make the pair look tidy would be lying the other way.
func test_a_verb_that_succeeds_may_still_publish_a_complaint() -> void:
	var actor := _prepared()
	var seed := _seed(actor)
	assert_ne(seed, null, "the realm authors a training price")
	assert_ne(seed.refinement_cap > 0, false, "and the cap is above zero, or nothing trains")
	var elixir := Crafting.resolve(seed.strengthening_item)
	assert_ne(elixir, null, "authored item %s exists" % seed.strengthening_item)
	ItemsApi.inventory(actor).add(elixir, 400)
	var candidates := BodyTraining.strengthen_candidates(actor)
	assert_ne(candidates.is_empty(), false, "this realm offers channels")
	# Cap every candidate but the last, and put the last one step below its cap so it is
	# trainable. `range` over a size this loop does not grow.
	for index in range(maxi(0, candidates.size() - 1)):
		var capped := actor.meridians.get_meridian(candidates[index])
		if capped == null:
			continue
		capped.state = MeridianState.STRENGTHENED
		capped.refinement = seed.refinement_cap
	var trainable := actor.meridians.get_meridian(candidates[candidates.size() - 1])
	assert_ne(trainable, null, "the last candidate is on this body")
	if trainable == null:
		return
	trainable.state = MeridianState.STRENGTHENED
	trainable.refinement = seed.refinement_cap - 1
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "one candidate is still trainable")
	var kinds := _kinds(_unavailable(actor, "strengthen"))
	assert_eq(
		kinds.has(BodyRefusal.KIND_CHANNEL_AT_CAP),
		true,
		"and the capped ones are still named, because they really are (%s)" % [kinds]
	)


## The report asks the verb's OWN candidate list, so a screen can never be told a cause
## the verb never reached. This is where two lists would drift, and where the screen
## would start blaming channels no press touches.
func test_the_strengthen_report_only_names_channels_the_verb_walks() -> void:
	var actor := _hero()
	var candidates := BodyTraining.strengthen_candidates(actor)
	assert_ne(candidates.is_empty(), false, "this realm offers channels")
	for entry in _unavailable(actor, "strengthen"):
		var clause := entry as Dictionary
		var kind := String(clause.get("kind", ""))
		if kind == BodyRefusal.KIND_CHANNEL_AT_CAP or kind == BodyRefusal.KIND_CHANNEL_UNKNOWN:
			assert_eq(
				candidates.has(StringName(clause.get("id", ""))),
				true,
				"a per-channel clause names a channel the verb walks (%s)" % clause
			)


# --- recover: the two halves of the contradiction ----------------------------


## **The headline.** A wound with an empty pack has exactly one remaining cause — the
## elixir — because a jam or a tear is a wound the recovery elixir exists to close.
func test_a_wound_with_no_elixir_is_named_as_the_missing_elixir() -> void:
	var actor := _hero()
	actor.meridians.damage_meridian(_first_candidate(actor))
	assert_eq(BodyCultivationApi.recover_next(actor), false, "an empty pack repairs nothing")
	assert_eq(
		_kinds(_unavailable(actor, "recover")),
		[BodyRefusal.KIND_NO_RECOVERY_ITEM],
		"and the only cause is the elixir"
	)


## A jammed huyệt is the other wound this verb closes, and it reaches a channel that
## is not injured at all — so it proves the report asks about BLOCKED huyệt and not
## only torn channels.
func test_a_jam_is_a_wound_the_elixir_closes() -> void:
	var actor := _hero()
	assert_ne(_jam(actor, _first_candidate(actor)), &"", "a huyệt on this channel exists")
	assert_eq(BodyCultivationApi.recover_next(actor), false, "an empty pack repairs nothing")
	assert_eq(
		_kinds(_unavailable(actor, "recover")),
		[BodyRefusal.KIND_NO_RECOVERY_ITEM],
		"a jam is a wound, so the price is named"
	)


## The other branch, DISJOINT by construction: no wound, so no price is named. The two
## clauses together are what the screen could not tell apart.
func test_no_wound_names_no_price() -> void:
	var actor := _hero()
	assert_eq(BodyCultivationApi.recover_next(actor), false, "there is nothing to repair")
	assert_eq(
		_kinds(_unavailable(actor, "recover")),
		[BodyRefusal.KIND_NO_DAMAGE],
		"and nothing is named that a player does not owe"
	)


## The elixir PRESENT removes the price and leaves nothing to name, because there is no
## refusal left: the repair happens. The fix is not dead code.
func test_a_held_elixir_repairs_and_publishes_no_price() -> void:
	var actor := _hero()
	actor.meridians.damage_meridian(_first_candidate(actor))
	var seed := _seed(actor)
	assert_ne(seed, null, "the realm authors a recovery price")
	_play.stock(actor, seed.recovery_item)
	assert_eq(BodyCultivationApi.recover_next(actor), true, "the wound closes")
	assert_eq(
		_kinds(_unavailable(actor, "recover")),
		[BodyRefusal.KIND_NO_DAMAGE],
		"which is named as a wound's absence, never as a price"
	)


# --- strengthen: a burn's price, and a cap that is not one -------------------


## ADR 0141's price, and the sentence the panel used to make impossible: a torn channel
## is repaired with the RECOVERY elixir, so a hero holding only the channel elixir is
## refused for the other item.
func test_a_torn_channel_is_priced_by_the_recovery_elixir() -> void:
	var actor := _prepared()
	var seed := _seed(actor)
	assert_ne(seed, null, "the realm authors both prices")
	# Every channel on the network, because `strengthen_next` walks past one tear to the
	# next healthy candidate. Bounded by the network the actor unlocked.
	for channel in actor.meridians.get_all_meridians():
		actor.meridians.damage_meridian(channel.id)
	var wrong := Crafting.resolve(seed.strengthening_item)
	assert_ne(wrong, null, "authored item %s exists" % seed.strengthening_item)
	ItemsApi.inventory(actor).add(wrong, 1)
	assert_eq(BodyCultivationApi.strengthen_next(actor), false, "the wrong elixir, no repair")
	var kinds := _kinds(_unavailable(actor, "strengthen"))
	assert_eq(kinds.has(BodyRefusal.KIND_NO_RECOVERY_ITEM), true, "the burn's own price is named")
	assert_eq(
		kinds.has(BodyRefusal.KIND_NO_CHANNEL_ELIXIR),
		false,
		"and never the elixir the player is holding (%s)" % [kinds]
	)


## The other price, so the report cannot pass by always naming one.
func test_a_healthy_channel_is_priced_by_the_channel_elixir() -> void:
	var actor := _hero()
	assert_eq(BodyCultivationApi.strengthen_next(actor), false, "an empty pack trains nothing")
	var kinds := _kinds(_unavailable(actor, "strengthen"))
	assert_eq(kinds.has(BodyRefusal.KIND_NO_CHANNEL_ELIXIR), true, "the ladder's price is named")
	assert_eq(
		kinds.has(BodyRefusal.KIND_NO_RECOVERY_ITEM), false, "and not the wound's (%s)" % [kinds]
	)


## **The residual ADR 0150 recorded as unfixed.** A channel at its refinement cap with
## its huyệt trained to target used to read as "No channel elixir to spend", because the
## screen was handed one `bool` over a walk it could not see.
func test_a_capped_channel_is_not_blamed_on_a_missing_elixir() -> void:
	var actor := _prepared()
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
	assert_eq(BodyCultivationApi.strengthen_next(actor), false, "nothing is left to train")
	var kinds := _kinds(_unavailable(actor, "strengthen"))
	assert_eq(kinds.has(BodyRefusal.KIND_CHANNEL_AT_CAP), true, "the cap is named (%s)" % [kinds])
	assert_eq(
		kinds.has(BodyRefusal.KIND_NO_CHANNEL_ELIXIR),
		false,
		"and the elixir the player is holding is not blamed (%s)" % [kinds]
	)
