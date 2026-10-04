extends TestCase

## ## `sworn` is reachable, and reaching it is not the same as being told it happened
##
## ADR 0091's ladder ships nine rungs and `SocialCauseCatalog` authors
## `shared_brotherhood` with `"promotes_to": SocialBondClass.SWORN`, but nothing read that
## field: `grep -rn promotes_to game/src` returned the declaration, the author site and the
## assignment, and no reader. So the deepest rung of the positive ladder could not be
## produced by any code path — a player could reach confidant and stop, and every gate
## authored `at_least: SWORN` would have been permanently unreachable (BL-0659).
##
## These assert both halves of the fix: the rung is reachable, AND it is reachable only
## through a bond whose AXES already earned a confidant. The second half is the load-bearing
## one. A promotion that trusts its own cause makes the top of a relationship ladder a thing
## a third purchase triggers, which is exactly the shape ADR 0091 exists to refuse.

const PARTNER := &"elder_wei"


## The catalog is a process-wide singleton and several tests here author their own causes,
## so every test starts from the shipped set rather than from whatever ran before it.
func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	return actor


## One authored cause. `promotes_to` is the last argument so a test that is not about the
## promotion does not have to name it at all.
func _cause(
	cause_id: StringName,
	kind: StringName,
	standing: float,
	trust: float,
	promotes: StringName = &""
) -> SocialCauseDef:
	var cause := SocialCauseDef.new()
	cause.id = cause_id
	cause.kind = kind
	cause.standing = standing
	cause.trust = trust
	cause.persistent = true
	cause.promotes_to = promotes
	return cause


## ## A bond on which the ladder has genuinely been climbed to a confidant
##
## One SHIPPED `shared_brotherhood` is the act that carries the promise; the other five are
## what put the axes over `CONFIDANT_AT` with `CONFIDANT_TRUST` behind them. So the oath and
## the standing that backs it arrive from DIFFERENT acts — which is the point: the promise
## cannot grant itself. The six shipped causes sum to standing 24.0 and trust 0.59, so both
## halves of the ladder's own confidant bar are cleared by real history, not by one act.
##
## Every cause here is persistent, so `standing_floor` rises with each one and the tick
## cannot drift the bond back down through the promotion gate while we assert.
func _confidant(actor: Actor) -> SocialBond:
	for cause_id in [
		&"shared_brotherhood",
		&"helped_in_combat",
		&"spared_in_combat",
		&"taught_technique",
		&"protected_from_death",
		&"honoured_a_debt"
	]:
		SocialApi.apply_cause(actor, PARTNER, cause_id)
	return SocialApi.social_state(actor).bond(PARTNER)


# --- The rung the ladder advertises can be produced ---------------------------


## ## The load-bearing positive: the ladder's top rung is reachable at all
##
## Delete the `promoted_to` branch from `SocialBondClass.classify` (or the recording line
## from `SocialBond.apply`) and `promoted` is `""`, so this lands on CONFIDANT and goes red.
## There is no other writer of the field, so nothing else can paper over it.
func test_a_bond_whose_axes_earned_a_confidant_and_shared_a_brotherhood_is_sworn() -> void:
	var actor := _actor()
	var bond := _confidant(actor)
	assert_eq(bond.promoted_to, SocialBondClass.SWORN, "the act recorded the promise")
	assert_eq(bond.bond_class(), SocialBondClass.SWORN, "so the ladder's top rung is reachable")


## `at_least` is what a gate reads, so the promotion has to be visible to it — otherwise
## content authored `at_least: SWORN` opens on the rung below and the fix is invisible.
func test_a_sworn_bond_answers_at_least_sworn_for_a_gate() -> void:
	var actor := _actor()
	_confidant(actor)
	var gate := SocialApi.gate(
		actor, {"verb": &"bond_at_least", "partner": PARTNER, "at_least": SocialBondClass.SWORN}
	)
	assert_eq(gate["ok"], true, "a gate authored for the top rung opens on it")
	assert_eq(
		SocialApi.bond_entry(actor, PARTNER)["label"], "Sworn", "and a panel reads it as sworn"
	)


## ## The promise is sticky, and only ever a ceiling
##
## `promoted_to` records that the ladder MAY end at SWORN. A later betrayal must not
## silently rewrite the record — the oath was sworn, and the ledger says so — and must not
## let the bond keep READING as sworn once the axes no longer support it. `classify`
## re-checks the floor on every read, so the two facts stay separate instead of one being
## derived from the other.
func test_a_promoted_bond_demoted_by_a_later_act_keeps_the_promise_but_not_the_class() -> void:
	var actor := _actor()
	var bond := _confidant(actor)
	assert_eq(bond.bond_class(), SocialBondClass.SWORN, "sworn while the axes hold")
	SocialApi.apply_cause(actor, PARTNER, &"betrayed_oath")
	assert_eq(bond.promoted_to, SocialBondClass.SWORN, "the promise is on the ledger and stays")
	assert_ne(bond.bond_class(), SocialBondClass.SWORN, "but the axes no longer clear the bar")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.FRIEND,
		(
			"so the ladder reads the betrayal rather than the oath: 24.0 - 12.0 standing, and the"
			+ " betrayal's own -0.4 trust takes the axis under CONFIDANT_TRUST"
		)
	)


# --- The anti-farm rule still holds: a promise is not a shortcut ---------------


## ## The regression this fix must not cause: two gift-kind causes never reach SWORN
##
## This is the case the design has to get right, and it is why the anti-farm guard has to
## sit ABOVE the promotion rather than beside it. `gifted_item` and `helped_in_combat` are
## shipped causes whose `kind` falls out of their first tag; here both are re-authored
## `kind: &"gift"` — two different cause IDS of one KIND of act, which is exactly the farming
## shape ADR 0091 describes (a shopkeeper offering several gift-tier causes).
##
## **Both carry `promotes_to: SWORN`**, which is the worst case and the one worth testing:
## a merchant who sells oaths would otherwise be the fastest route to the top of the ladder.
## Standing sums to 25.0 and trust to a clamped 1.0, so every AXIS clears every bar on the
## ladder. What is missing is a history worth one — the ledger holds one kind of act.
##
## Delete the `distinct_causes` guard from `SocialBondClass.classify`, or move the promotion
## check above it — which is the mistake a reader is most likely to make when reading this
## file — and this test goes red at SWORN. That is the exact regression the ADR was written
## to close, one rung higher than before.
func test_two_gift_kind_causes_never_reach_sworn_however_generous_the_promise() -> void:
	SocialCauseCatalog.instance().reset()
	var first := _cause(&"a_gift", &"gift", 15.0, 0.6, SocialBondClass.SWORN)
	var second := _cause(&"another_gift", &"gift", 6.0, 0.3, SocialBondClass.SWORN)
	SocialCauseCatalog.instance().install([first, second])
	var actor := _actor()
	for cause_id in [&"a_gift", &"another_gift", &"another_gift"]:
		SocialApi.apply_cause(actor, PARTNER, cause_id)
	var bond := SocialApi.social_state(actor).bond(PARTNER)
	assert_eq(bond.distinct_kinds(), 1, "two gift-tier causes are one kind of act")
	assert_almost_eq(bond.standing, 27.0, "and the standing is past every bar on the ladder")
	assert_almost_eq(bond.trust, 1.0, "with the trust axis full")
	assert_eq(bond.promoted_to, SocialBondClass.SWORN, "so a promised oath is on the ledger")
	assert_eq(
		SocialBondClass.classify(bond.standing, bond.trust, 1, SocialBondClass.SWORN),
		SocialBondClass.ACQUAINTANCE,
		"and even handed straight to `classify`, one kind of act cannot be promoted"
	)
	assert_eq(
		bond.bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"a friendship bought twice must not become an oath by a third purchase"
	)


## ## A gift and a deed ARE two kinds, and the oath on top of them is the top of the ladder
##
## The positive control for the test above, and the reason the guard is drawn where it is
## rather than one rung higher: `gift` and `deed` are two different KINDS of act, so this
## history genuinely earns the friendship the promotion is built on. The answer has to be
## SWORN by the end, or the rung is unreachable for anyone who is not hiding a merchant.
func test_two_kinds_earn_the_friendship_and_the_oath_on_top_of_it_reaches_sworn() -> void:
	SocialCauseCatalog.instance().reset()
	var gift := _cause(&"a_gift", &"gift", 6.0, 0.3)
	var deed := _cause(&"a_deed", &"deed", 3.0, 0.2)
	var oath := _cause(&"an_oath", &"oath", 5.0, 0.2, SocialBondClass.SWORN)
	SocialCauseCatalog.instance().install([gift, deed, oath])
	var actor := _actor()
	SocialApi.apply_cause(actor, PARTNER, &"a_gift")
	SocialApi.apply_cause(actor, PARTNER, &"a_deed")
	var bond := SocialApi.social_state(actor).bond(PARTNER)
	assert_eq(bond.distinct_kinds(), 2, "a gift and a deed are two kinds of act")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.FRIEND,
		"a friendship, but not yet an oath — nothing has promised one"
	)
	SocialApi.apply_cause(actor, PARTNER, &"an_oath")
	assert_almost_eq(bond.standing, 14.0, "and the oath carries the axes over CONFIDANT_AT")
	assert_almost_eq(bond.trust, 0.7, "with CONFIDANT_TRUST behind it")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.SWORN,
		"so the oath stands on top of a friendship, which is what a sworn bond IS"
	)


## ## One kind of act is not even a friendship, promotion or no promotion
##
## This is the distinct-KIND rule that a recent change installed, restated against the
## promotion: `shared_brotherhood` applied three times is one cause and one kind, so the
## anti-farm branch in `classify` returns BEFORE any promotion is read. Asserted against
## the SHIPPED cause so the magnitude is the one a player actually meets.
func test_one_sworn_cause_repeated_does_not_reach_sworn_however_generous_it_is() -> void:
	var actor := _actor()
	for _i in range(6):
		SocialApi.apply_cause(actor, PARTNER, &"shared_brotherhood")
	var bond := SocialApi.social_state(actor).bond(PARTNER)
	assert_eq(bond.distinct_kinds(), 1, "one cause, one kind of act, however many times sworn")
	assert_almost_eq(bond.standing, 30.0, "the standing compounded regardless")
	assert_almost_eq(bond.trust, 0.9, "and so did the trust")
	assert_eq(bond.promoted_to, SocialBondClass.SWORN, "the promise was still recorded")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"so the anti-farm rule caps it below a friendship, promotion included"
	)


## ## Standing is not enough on its own — the trust axis is half the gate
##
## The axes must clear `CONFIDANT_AT` AND `CONFIDANT_TRUST`, which is the ladder's own
## confidant rule and not a rule invented for the promotion. A famous liar with no trust is
## a `friend`, so a brotherhood promised on top of that ledger must not skip the trust the
## class it is built on required.
func test_a_brotherhood_whose_axes_have_no_trust_does_not_reach_sworn() -> void:
	SocialCauseCatalog.instance().reset()
	var oath := SocialCauseDef.new()
	oath.id = &"an_oath"
	oath.kind = &"oath"
	oath.standing = 20.0
	oath.persistent = true
	oath.promotes_to = SocialBondClass.SWORN
	var known := SocialCauseDef.new()
	known.id = &"a_known_face"
	known.kind = &"deed"
	known.standing = 4.0
	SocialCauseCatalog.instance().install([oath, known])
	var actor := _actor()
	SocialApi.apply_cause(actor, PARTNER, &"a_known_face")
	SocialApi.apply_cause(actor, PARTNER, &"an_oath")
	var bond := SocialApi.social_state(actor).bond(PARTNER)
	assert_almost_eq(bond.standing, 24.0, "the standing is far past the confidant bar")
	assert_almost_eq(bond.trust, 0.0, "but no trust was ever earned")
	assert_eq(bond.bond_class(), SocialBondClass.FRIEND, "so the ladder stops at a friend")


## ## A cause may only lift, never lower
##
## `promotes_to` is authored, so an author could name a rung BELOW where the axes already
## are. Returning it would mean a lesser cause demotes a bond — a class negotiated by
## authoring rather than derived, which is the thing ADR 0091 refused.
func test_a_promotion_may_only_lift_and_never_demote() -> void:
	var actor := _actor()
	var bond := _confidant(actor)
	assert_eq(bond.bond_class(), SocialBondClass.SWORN, "climbed to the top")
	# Re-point the recorded promise at a rung the axes are already past.
	bond.promoted_to = SocialBondClass.FRIEND
	assert_eq(
		bond.bond_class(),
		SocialBondClass.CONFIDANT,
		"a ceiling below the earned class is ignored, and the ladder's own answer stands"
	)


## A class that is not on the positive ladder cannot be promoted to at all, so a typo in
## authored data is inert instead of inventing a rung `at_least` cannot place.
func test_a_promotion_to_something_off_the_positive_ladder_is_inert() -> void:
	var actor := _actor()
	var bond := _confidant(actor)
	bond.promoted_to = SocialBondClass.NEMESIS
	assert_eq(
		bond.bond_class(),
		SocialBondClass.CONFIDANT,
		"the axes still decide, and they say confidant"
	)


# --- The new field survives the save -----------------------------------------


## ## `promoted_to` round-trips, and the class after a reload is the class before it
##
## The whole save path, byte for byte: `actor.to_dict()` and nothing else, which is what
## `SaveApi.persist` does. A `to_dict` that dropped the field would restore an empty
## ceiling and land this bond back on CONFIDANT after a reload — a class that disagrees with
## the one the player was just shown.
func test_a_promoted_bond_keeps_its_class_across_a_save() -> void:
	var actor := _actor()
	var before := _confidant(actor)
	assert_eq(before.bond_class(), SocialBondClass.SWORN, "sworn before the save")
	var restored := Actor.from_dict(actor.to_dict())
	SocialApi.attach(restored)
	var bond := SocialApi.social_state(restored).bond(PARTNER)
	assert_ne(bond, null, "the bond came back through the ordinary actor payload")
	assert_eq(bond.promoted_to, SocialBondClass.SWORN, "and so did the promise")
	assert_eq(bond.bond_class(), SocialBondClass.SWORN, "so the class is the same on both sides")
	assert_eq(
		SocialApi.bond_entry(restored, PARTNER)["bond"],
		SocialBondClass.SWORN,
		"and a panel reading the reloaded ledger says the same word"
	)


## ## An old save has no `promoted_to`, and must land where it always did
##
## The field is new, so every save written before it exists restores without one. A missing
## ceiling is the SAFE direction — it can only hold a bond at the class its axes earned —
## and this asserts that a pre-BL-0659 payload on a confessed bond reads CONFIDANT, exactly
## what it read before the field existed.
func test_a_save_written_before_the_field_existed_restores_and_does_not_promote() -> void:
	var actor := _actor()
	_confidant(actor)
	var payload := actor.to_dict()
	var bond_payload := payload["module_data"][String(SocialApi.MODULE_KEY)]["bonds"] as Dictionary
	bond_payload[String(PARTNER)].erase("promoted_to")
	var restored := Actor.from_dict(payload)
	SocialApi.attach(restored)
	var bond := SocialApi.social_state(restored).bond(PARTNER)
	assert_eq(bond.promoted_to, &"", "no promise was on that ledger")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.CONFIDANT,
		"so it lands on the class it always did rather than jumping a rung on load"
	)
