extends TestCase

## An aggregate gate that cannot read its own children is the worst kind of guard: it
## passes everything, so an authored `all_of` never blocks anything and no test goes red.
## These pin the vocabulary the rest of the repo already uses.

const PARTNER := &"merchant_grampa"


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(actor)
	return actor


func _cause(cause_id: StringName, standing: float, trust: float) -> void:
	SocialCauseCatalog.instance().reset()
	var cause := SocialCauseDef.new()
	cause.id = cause_id
	cause.standing = standing
	cause.trust = trust
	SocialCauseCatalog.instance().install([cause])


## The defect in one assertion: `all_of` must READ its children under the repo-wide
## `"of"` key. Read under the wrong key the list is empty, `_pass()` runs, and a gate
## written to block someone opens for everyone.
func test_all_of_reads_its_children_under_the_repo_convention_key() -> void:
	var actor := _actor()
	_cause(&"a_gift", 1.0, 0.0)
	SocialApi.apply_cause(actor, PARTNER, &"a_gift")
	var result := (
		SocialApi
		. gate(
			actor,
			{
				"verb": &"all_of",
				"of": [{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 99.0}],
			}
		)
	)
	assert_eq(
		result["ok"], false, "an unmet child under `of` blocks, so the gate read its own content"
	)


func test_all_of_passes_only_when_every_child_passes() -> void:
	var actor := _actor()
	_cause(&"a_gift", 5.0, 0.0)
	SocialApi.apply_cause(actor, PARTNER, &"a_gift")
	var met := (
		SocialApi
		. gate(
			actor,
			{
				"verb": &"all_of",
				"of": [{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 1.0}],
			}
		)
	)
	var unmet := (
		SocialApi
		. gate(
			actor,
			{
				"verb": &"all_of",
				"of":
				[
					{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 1.0},
					{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 99.0},
				],
			}
		)
	)
	assert_eq(met["ok"], true, "one met child opens a one-child all_of")
	assert_eq(unmet["ok"], false, "one unmet child closes a two-child all_of")


func test_any_of_needs_only_one_child_to_open() -> void:
	var actor := _actor()
	_cause(&"a_gift", 5.0, 0.0)
	SocialApi.apply_cause(actor, PARTNER, &"a_gift")
	var result := (
		SocialApi
		. gate(
			actor,
			{
				"verb": &"any_of",
				"of":
				[
					{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 1.0},
					{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 99.0},
				],
			}
		)
	)
	assert_eq(result["ok"], true, "one met child is enough for any_of")


func test_none_of_closes_when_a_child_is_met() -> void:
	var actor := _actor()
	_cause(&"a_gift", 5.0, 0.0)
	SocialApi.apply_cause(actor, PARTNER, &"a_gift")
	var blocked := (
		SocialApi
		. gate(
			actor,
			{
				"verb": &"none_of",
				"of": [{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 1.0}],
			}
		)
	)
	var open := (
		SocialApi
		. gate(
			actor,
			{
				"verb": &"none_of",
				"of": [{"verb": &"standing_at_least", "partner": PARTNER, "at_least": 99.0}],
			}
		)
	)
	assert_eq(blocked["ok"], false, "a met child closes none_of")
	assert_eq(open["ok"], true, "an unmet child leaves it open")


func test_an_empty_aggregate_is_ungated_rather_than_vacuous() -> void:
	var actor := _actor()
	assert_eq(
		SocialApi.gate(actor, {"verb": &"all_of", "of": []})["ok"],
		true,
		"no children means no condition, which is ungated by design"
	)


func test_an_unknown_child_verb_refuses_rather_than_passing_silently() -> void:
	var actor := _actor()
	var result := (
		SocialApi
		. gate(
			actor,
			{"verb": &"all_of", "of": [{"verb": &"no_such_verb", "partner": PARTNER}]},
		)
	)
	assert_eq(result["ok"], false, "a child the gate cannot evaluate must not open the parent")


# --- The anti-farm rule counts KINDS, not causes -------------------------------
#
# The rule once counted distinct CAUSES, which a shopkeeper defeated with two gift-tier
# causes: two causes, one kind, and a friendship the ledger never earned.


func _catalog_of_gifts() -> void:
	SocialCauseCatalog.instance().reset()
	var small := SocialCauseDef.new()
	small.id = &"gifted_item"
	small.kind = &"gift"
	small.standing = 4.0
	small.trust = 0.1
	var large := SocialCauseDef.new()
	large.id = &"gilded_gift"
	large.kind = &"gift"
	large.standing = 6.0
	large.trust = 0.2
	SocialCauseCatalog.instance().install([small, large])


func test_two_causes_of_the_same_kind_do_not_buy_a_friendship() -> void:
	_catalog_of_gifts()
	var actor := _actor()
	SocialApi.apply_cause(actor, PARTNER, &"gifted_item")
	SocialApi.apply_cause(actor, PARTNER, &"gilded_gift")
	var bond := SocialApi.social_state(actor).bond(PARTNER)
	assert_eq(bond.distinct_causes(), 2, "two distinct causes did land")
	assert_eq(bond.distinct_kinds(), 1, "but only one KIND of act")
	assert_almost_eq(bond.standing, 10.0, "and a standing past FRIEND_AT", 0.001)
	assert_eq(
		bond.bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"so the standing is refused and the merchant is not farmed"
	)


func test_two_kinds_of_act_do_buy_a_friendship() -> void:
	_catalog_of_gifts()
	var fight := SocialCauseDef.new()
	fight.id = &"spared_in_combat"
	fight.kind = &"combat"
	fight.standing = 4.0
	fight.trust = 0.2
	SocialCauseCatalog.instance().install([fight])
	var actor := _actor()
	SocialApi.apply_cause(actor, PARTNER, &"gifted_item")
	SocialApi.apply_cause(actor, PARTNER, &"spared_in_combat")
	assert_eq(
		SocialApi.social_state(actor).bond(PARTNER).bond_class(),
		SocialBondClass.FRIEND,
		"a gift and a mercy are two kinds, and that is a friendship"
	)


func test_the_kind_set_survives_a_save_round_trip() -> void:
	_catalog_of_gifts()
	var actor := _actor()
	SocialApi.apply_cause(actor, PARTNER, &"gifted_item")
	SocialApi.apply_cause(actor, PARTNER, &"gilded_gift")
	SocialApi.state(actor)
	var restored := Actor.from_dict(actor.to_dict())
	SocialApi.attach(restored)
	var bond := SocialApi.social_state(restored).bond(PARTNER)
	assert_ne(bond, null, "the bond came back")
	assert_eq(bond.distinct_kinds(), 1, "with its kind history, so it is still not a friendship")
	assert_eq(bond.bond_class(), SocialBondClass.ACQUAINTANCE, "and lands on the same class")
