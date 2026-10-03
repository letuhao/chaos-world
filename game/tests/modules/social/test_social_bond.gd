extends TestCase

## The social ledger is the one relationship structure every actor carries, so these
## assert the three properties that make it worth having: the class is DERIVED rather
## than bought, a persistent cause outlives time, and the whole thing round-trips
## through `Actor.to_dict` with no bespoke save slot (ADR 0076).

const MERCHANT := &"merchant_grampa"
const RIVAL := &"rival_cultivator_lan"


## The catalog is a process-wide singleton and several tests below author their own
## causes, so every test starts from the shipped set. Without this a test that runs after
## one which called `reset` would find `gifted_item` missing and silently assert nothing.
func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	return actor


## Install exactly ONE authored cause, so a test that wants to prove the
## distinct-cause rule cannot be farmed is not quietly authoring a second reason itself.
func _single_cause(cause_id: StringName, standing: float, trust: float) -> void:
	SocialCauseCatalog.instance().reset()
	var cause := SocialCauseDef.new()
	cause.id = cause_id
	cause.standing = standing
	cause.trust = trust
	SocialCauseCatalog.instance().install([cause])


# --- The class is derived, never bought ----------------------------------------


func test_a_bond_with_no_history_is_a_stranger() -> void:
	var actor := _actor()
	var entry := SocialApi.bond_entry(actor, MERCHANT)
	assert_eq(entry["present"], false, "they have never been met")
	assert_eq(entry["bond"], SocialBondClass.STRANGER, "so they are a stranger")


func test_one_generous_cause_alone_cannot_buy_a_friendship() -> void:
	_single_cause(&"a_gift", 8.0, 0.9)
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	var bond := SocialApi.social_state(actor).bond(MERCHANT)
	assert_almost_eq(bond.standing, 8.0, "the standing did move")
	assert_almost_eq(bond.trust, 0.9, "and so did the trust")
	# Standing alone clears FRIEND_AT, but a friendship needs two DISTINCT causes. This is
	# the rule that stops a merchant being farmed by one generous purchase.
	assert_eq(bond.bond_class(), SocialBondClass.ACQUAINTANCE, "one cause is not a friendship")


func test_two_distinct_causes_reach_a_friendship() -> void:
	SocialCauseCatalog.instance().reset()
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 4.0
	var taught := SocialCauseDef.new()
	taught.id = &"a_teaching"
	taught.standing = 4.0
	SocialCauseCatalog.instance().install([gift, taught])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	SocialApi.apply_cause(actor, MERCHANT, &"a_teaching")
	assert_eq(
		SocialApi.social_state(actor).bond(MERCHANT).bond_class(),
		SocialBondClass.FRIEND,
		"two distinct causes clear the friendship bar"
	)


func test_a_repeated_single_cause_is_still_not_a_friendship() -> void:
	_single_cause(&"a_gift", 4.0, 0.3)
	var actor := _actor()
	for _i in range(6):
		SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	var bond := SocialApi.social_state(actor).bond(MERCHANT)
	assert_eq(bond.distinct_causes(), 1, "one distinct cause, however many times given")
	assert_ne(bond.bond_class(), SocialBondClass.FRIEND, "so it is still not a friend")


func test_trust_and_standing_are_distinct_axes() -> void:
	SocialCauseCatalog.instance().reset()
	var famed := SocialCauseDef.new()
	famed.id = &"a_fame"
	famed.standing = 7.0
	var known := SocialCauseDef.new()
	known.id = &"a_known"
	known.trust = 0.7
	var other := SocialCauseDef.new()
	other.id = &"a_other"
	other.standing = 1.0
	SocialCauseCatalog.instance().install([famed, known, other])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_fame")
	SocialApi.apply_cause(actor, MERCHANT, &"a_known")
	SocialApi.apply_cause(actor, MERCHANT, &"a_other")
	var bond := SocialApi.social_state(actor).bond(MERCHANT)
	# A famous liar: high standing, and the trust axis says whether they can be relied on.
	assert_almost_eq(bond.standing, 8.0, "the standing accumulated")
	assert_almost_eq(bond.trust, 0.7, "and the trust moved on its own axis")


func test_a_negative_bond_resolves_to_a_hostility_class() -> void:
	SocialCauseCatalog.instance().reset()
	var robbed := SocialCauseDef.new()
	robbed.id = &"a_robbed"
	robbed.standing = -6.0
	SocialCauseCatalog.instance().install([robbed])
	var actor := _actor()
	SocialApi.apply_cause(actor, RIVAL, &"a_robbed")
	assert_eq(
		SocialApi.social_state(actor).bond(RIVAL).bond_class(),
		SocialBondClass.HOSTILE,
		"robbing someone makes them hostile"
	)


func test_the_ladder_is_ordered_so_a_friend_answers_at_least_acquaintance() -> void:
	assert_eq(
		SocialBondClass.at_least(SocialBondClass.FRIEND, SocialBondClass.ACQUAINTANCE),
		true,
		"a friend is at least an acquaintance"
	)
	assert_eq(
		SocialBondClass.at_least(SocialBondClass.STRANGER, SocialBondClass.FRIEND),
		false,
		"a stranger is not a friend"
	)
	assert_eq(
		SocialBondClass.at_least(SocialBondClass.HOSTILE, SocialBondClass.FRIEND),
		false,
		"hostility is never at least a friendship"
	)


# --- The player and an npc carry the identical structure -----------------------


func test_an_npc_carries_the_same_social_type_as_the_player() -> void:
	var hero := _actor()
	var smith := Actor.new(&"smith", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(smith)
	SocialApi.apply_cause(hero, MERCHANT, &"gifted_item")
	SocialApi.apply_cause(smith, &"hero", &"gifted_item")
	assert_eq(
		SocialApi.social_state(hero).bond_count(),
		SocialApi.social_state(smith).bond_count(),
		"both ledgers answer the same question the same way"
	)
	assert_eq(
		SocialApi.social_state(hero).bond(MERCHANT).bond_class(),
		SocialApi.social_state(smith).bond(&"hero").bond_class(),
		"and a gift lands as the same class on both sides"
	)


# --- Change is refused loudly, never silently ignored --------------------------


func test_an_unknown_cause_is_refused_and_moves_nothing() -> void:
	var actor := _actor()
	var result := SocialApi.apply_cause(actor, MERCHANT, &"no_such_cause")
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], "unknown_cause", "and it says which way it failed")
	assert_eq(SocialApi.social_state(actor).bond_count(), 0, "no bond was created")


func test_applying_a_cause_to_no_partner_is_refused() -> void:
	var actor := _actor()
	assert_eq(SocialApi.apply_cause(actor, &"", &"gifted_item")["ok"], false, "refused")
	assert_eq(
		SocialApi.apply_cause(null, MERCHANT, &"gifted_item")["ok"], false, "and so is a null actor"
	)


# --- Decay: time moves a bond toward the promise it was given ------------------


func test_a_transient_bond_drifts_back_toward_a_stranger() -> void:
	SocialCauseCatalog.instance().reset()
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 5.0
	SocialCauseCatalog.instance().install([gift])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	var before := SocialApi.social_state(actor).bond(MERCHANT).standing
	# Standing drifts one point per thirty days, so thirty days moves exactly one point.
	SocialApi.tick(actor, 24.0 * 60.0 * 60.0 * 30.0)
	var after := SocialApi.social_state(actor).bond(MERCHANT).standing
	assert_almost_eq(after, before - 1.0, "a month of silence moves it one point", 0.001)


func test_a_persistent_cause_leaves_a_floor_decay_cannot_cross() -> void:
	SocialCauseCatalog.instance().reset()
	var oath := SocialCauseDef.new()
	oath.id = &"an_oath"
	oath.standing = 9.0
	oath.persistent = true
	SocialCauseCatalog.instance().install([oath])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"an_oath")
	# Long enough that a floorless bond would be back at zero many times over.
	SocialApi.tick(actor, 24.0 * 60.0 * 60.0 * 4000.0)
	assert_almost_eq(
		SocialApi.social_state(actor).bond(MERCHANT).standing,
		9.0,
		"the honoured debt is still there after a decade",
		0.001
	)


func test_decay_moves_no_bond_at_all_when_there_is_no_time_passed() -> void:
	SocialCauseCatalog.instance().reset()
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 3.0
	SocialCauseCatalog.instance().install([gift])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	assert_eq(SocialApi.tick(actor, 0.0), 0, "nothing moved")
	assert_almost_eq(
		SocialApi.social_state(actor).bond(MERCHANT).standing, 3.0, "and nothing decayed"
	)


# --- A gate reads the ledger, so it cannot be bought ----------------------------


func test_an_empty_requirement_is_always_open() -> void:
	var actor := _actor()
	assert_eq(SocialApi.gate(actor, {})["ok"], true, "ungated content opens for a stranger")


func test_a_bond_gate_refuses_a_stranger_and_names_why() -> void:
	var actor := _actor()
	var result := SocialApi.gate(
		actor, {"verb": &"bond_at_least", "partner": MERCHANT, "at_least": SocialBondClass.FRIEND}
	)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["unmet"].size(), 1, "with one unmet reason a panel can render")


func test_a_bond_gate_opens_once_the_bond_is_earned() -> void:
	SocialCauseCatalog.instance().reset()
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 4.0
	var taught := SocialCauseDef.new()
	taught.id = &"a_teaching"
	taught.standing = 4.0
	SocialCauseCatalog.instance().install([gift, taught])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	SocialApi.apply_cause(actor, MERCHANT, &"a_teaching")
	assert_eq(
		(
			SocialApi
			. gate(
				actor,
				{
					"verb": &"bond_at_least",
					"partner": MERCHANT,
					"at_least": SocialBondClass.FRIEND,
				}
			)["ok"]
		),
		true,
		"earned, so open"
	)


func test_an_unknown_gate_verb_refuses_closed_and_names_itself() -> void:
	var actor := _actor()
	var result := SocialApi.gate(actor, {"verb": &"no_such_verb"})
	assert_eq(result["ok"], false, "refused closed rather than silently opening")
	assert_eq(result["reason"], "unknown_verb", "and it says why")


func test_a_caused_by_gate_reads_the_ledger_not_a_total() -> void:
	SocialCauseCatalog.instance().reset()
	var saved := SocialCauseDef.new()
	saved.id = &"a_saved"
	saved.standing = -3.0
	var elsewhere := SocialCauseDef.new()
	elsewhere.id = &"an_elsewhere"
	elsewhere.standing = 4.0
	SocialCauseCatalog.instance().install([saved, elsewhere])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"a_saved")
	# A positive total was never reached, so a gate reading a score would refuse. This
	# one asks whether he was ever saved, which is the question the fiction asks.
	assert_eq(
		(
			SocialApi
			. gate(actor, {"verb": &"caused_by", "partner": MERCHANT, "cause": &"a_saved"})["ok"]
		),
		true,
		"the ledger remembers the specific act"
	)


# --- Persistence ---------------------------------------------------------------


func test_the_ledger_round_trips_through_the_ordinary_actor_payload() -> void:
	SocialCauseCatalog.instance().reset()
	var oath := SocialCauseDef.new()
	oath.id = &"an_oath"
	oath.standing = 5.0
	oath.trust = 0.4
	oath.persistent = true
	var teaching := SocialCauseDef.new()
	teaching.id = &"a_teaching"
	teaching.standing = 3.0
	SocialCauseCatalog.instance().install([oath, teaching])
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"an_oath")
	SocialApi.apply_cause(actor, MERCHANT, &"a_teaching")
	SocialApi.state(actor)
	var restored := Actor.from_dict(actor.to_dict())
	SocialApi.attach(restored)
	var bond := SocialApi.social_state(restored).bond(MERCHANT)
	assert_ne(bond, null, "the bond survived the save")
	assert_almost_eq(bond.standing, 8.0, "with its standing")
	assert_almost_eq(bond.trust, 0.4, "its trust")
	assert_eq(bond.distinct_causes(), 2, "and its cause ledger, which is what a class derives from")
	assert_eq(bond.bond_class(), SocialBondClass.FRIEND, "and its derived class")


func test_the_ledger_needs_no_core_schema_bump() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	SocialApi.state(actor)
	# The whole ledger rides in the module_data block core already round-trips, so the
	# actor schema version is untouched and core never names a social type.
	assert_eq(int(actor.to_dict()["version"]), Actor.SCHEMA_VERSION, "the schema did not move")
	assert_ne(
		actor.to_dict()["module_data"][String(SocialApi.MODULE_KEY)].size(),
		0,
		"the ledger is there under its own module key"
	)


func test_forgetting_a_bond_removes_it_from_the_summary() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	assert_eq(SocialApi.forget(actor, MERCHANT), true, "forgotten")
	assert_eq(SocialApi.social_state(actor).bond_count(), 0, "the ledger is empty again")
	assert_eq(SocialApi.forget(actor, MERCHANT), false, "and forgetting it twice says so")


# --- The read model ------------------------------------------------------------


func test_the_summary_is_primitives_only_and_empty_without_an_actor() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	var summary := SocialApi.summary(actor)
	assert_eq(summary["actor_id"], "hero", "names the actor")
	assert_eq(summary["bond_count"], 1, "counts the bond")
	assert_eq(summary["bonds"][String(MERCHANT)]["present"], true, "and describes it")
	assert_eq(SocialApi.summary(null), {}, "no actor, no read model")


func test_the_provider_contributes_only_this_module_s_own_stat_ids() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	var values := SocialProvider.new().contribute(
		StatContext.new(
			actor.stats.base_ref(),
			actor.resources,
			actor.traits,
			actor.affinities,
			actor.paths,
			actor.components
		)
	)
	assert_eq(values.has(SocialStats.REPUTATION), true, "the reputation is contributed")
	assert_eq(values.has(Stat.DAO_HEART), false, "and no core id is ever emitted by this provider")
