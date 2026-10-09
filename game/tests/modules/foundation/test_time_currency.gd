extends TestCase

## BL-0951 / ADR 0939, S6: time is the currency.
##
## Every training press spends the BODY's life — never the world's count, which modules may
## not advance (ADR 0089 / DEF-0111) — and the final band ends training while leaving one
## last, burning breakthrough attempt. Three facts, each measured:
##
##   1. a press accrues age (12 periods = one day at the authored ratios);
##   2. the cliff: in `lastlight` every training verb refuses, by the shared name;
##   3. the final attempt: a decided attempt in `lastlight` burns a year, and burns
##      nothing anywhere earlier.

const QiProbe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")
const MindProbe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")
const BodyPlay := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")

## A flat 100-year lifespan, authored by the test so the band crossings are deterministic —
## the same shape `test_age_band_statuses.gd` builds its heroes with.
const LIFESPAN_DAYS := 36500.0


func _hero(base: Dictionary) -> Actor:
	var actor := Actor.new(&"time_hero", base)
	actor.stats.add_modifier(
		StatModifier.new(&"race_lifespan", Stat.Op.FLAT, LIFESPAN_DAYS, &"test")
	)
	return actor


func _at_lifespan_share(actor: Actor, share: float) -> void:
	actor.age_years = share * LIFESPAN_DAYS / 365.0


## Give a fixture-built actor the flat lifespan the band is read against. Fixtures attach
## paths and pools but no race, and a body with no lifespan answers the youngest band —
## which would make every cliff assertion below pass for the wrong reason.
func _give_lifespan(actor: Actor) -> void:
	actor.stats.add_modifier(
		StatModifier.new(&"race_lifespan", Stat.Op.FLAT, LIFESPAN_DAYS, &"test")
	)


func test_a_sitting_advances_the_body_clock_by_one_day() -> void:
	var actor := QiProbe.fresh_actor(&"qi_refining")
	var before: float = actor.age_years
	assert_eq(QiTraining.cultivate(actor, 10.0), true, "the sitting lands")
	assert_almost_eq(actor.age_years - before, 1.0 / 365.0, "twelve periods are one day of life")


func test_a_refused_press_spends_nothing() -> void:
	var actor := QiProbe.fresh_actor(&"qi_refining")
	var before: float = actor.age_years
	assert_eq(QiTraining.cultivate(actor, 0.0), false, "a zero sitting is refused")
	assert_almost_eq(actor.age_years - before, 0.0, "and a refusal costs no life")


func test_spend_periods_guards_its_inputs() -> void:
	assert_almost_eq(FoundationApi.spend_periods(null, 12), 0.0, "no actor spends nothing")
	var actor := _hero({Stat.PHYSIQUE: 1.0})
	var before: float = actor.age_years
	assert_almost_eq(FoundationApi.spend_periods(actor, 0), 0.0, "no span spends nothing")
	assert_almost_eq(FoundationApi.spend_periods(actor, -12), 0.0, "a negative span spends nothing")
	assert_almost_eq(actor.age_years - before, 0.0, "and the body is untouched")


func test_the_band_reading_is_one_computation() -> void:
	assert_eq(
		AgeBandTable.band_for_actor(null),
		AgeBands.band_for(null),
		"no actor is the youngest band on both"
	)
	var actor := _hero({Stat.PHYSIQUE: 1.0})
	for share in [0.1, 0.3, 0.6, 0.9]:
		_at_lifespan_share(actor, share)
		assert_eq(
			AgeBandTable.band_for_actor(actor),
			AgeBands.band_for(actor),
			"the core reader and the projection agree at share %f" % share
		)
	_at_lifespan_share(actor, 0.9)
	assert_eq(
		AgeBandTable.band_for_actor(actor), AgeBandTable.LASTLIGHT, "share 0.9 is the final band"
	)


func test_the_cliff_refuses_every_training_verb_by_name() -> void:
	# Qi: a fresh actor can sit, and its channel elixir is stocked so the only refusal
	# in play is the cliff.
	var qi := QiProbe.fresh_actor(&"qi_refining")
	_give_lifespan(qi)
	_at_lifespan_share(qi, 0.9)
	assert_eq(FoundationApi.training_refusal(qi), FoundationApi.R_LASTLIGHT, "named")
	assert_eq(QiTraining.cultivate(qi, 10.0), false, "no sittings left")
	assert_eq(QiTraining.meditate(qi, 1.0), false, "no calming left")
	QiProbe.stock(qi, QiRealmSeed.for_realm(&"qi_refining").training_item)
	assert_eq(QiTraining.train_channel(qi, &"lung"), false, "no channel work left")
	# The depth step past the cap: perfect every gate channel first (while young), then
	# age — the cliff must refuse the catalyst press without spending it.
	var deep := QiProbe.fresh_actor(&"qi_refining")
	var deep_seed := QiRealmSeed.for_realm(&"core_formation")
	assert_eq(QiProbe.perfect_gate_channels(deep, deep_seed), true, "channels at the cap")
	QiProbe.stock(deep, QiRealmSeed.for_realm(&"qi_refining").meridian_catalyst)
	_give_lifespan(deep)
	_at_lifespan_share(deep, 0.9)
	var catalyst := QiRealmSeed.for_realm(&"qi_refining").meridian_catalyst
	var catalyst_before := ItemsApi.inventory(deep).count(catalyst)
	var gate_channel: StringName = deep_seed.required_meridians[0]
	assert_eq(QiTraining.deepen_past_cap(deep, gate_channel), false, "no depth past the cap left")
	assert_eq(
		ItemsApi.inventory(deep).count(catalyst), catalyst_before, "and the catalyst is unspent"
	)
	# Body: the play fixture attaches everything a press needs.
	var body: Actor = BodyPlay.new().actor(&"qi_refining")
	_give_lifespan(body)
	_at_lifespan_share(body, 0.9)
	assert_eq(BodyTraining.cultivate(body, 10.0), false, "no cultivation left")
	assert_eq(BodyTraining.meditate(body, 1.0), false, "no meditation left")
	body.meridians.unlock_for_realm(&"qi_refining")
	BodyPlay.new().stock(body, BodyRealmSeed.for_realm(&"qi_refining").strengthening_item)
	assert_eq(BodyTraining.strengthen(body, &"lung"), false, "no strengthening left")
	# Mind: a fresh actor can sit once its sea is turbulent, and its channel elixir is
	# stocked so the only refusal in play is the cliff.
	var mind := MindProbe.fresh_actor(&"qi_refining")
	_give_lifespan(mind)
	_at_lifespan_share(mind, 0.9)
	MindCultivationApi.sea(mind).turbulence = 5.0
	assert_eq(MindTraining.cultivate(mind, 10.0), false, "no sittings left")
	assert_eq(MindTraining.meditate(mind, 1.0), false, "no calming left")
	MindProbe.stock(mind, MindRealmSeed.for_realm(&"qi_refining").training_item)
	assert_eq(MindTraining.train_channel(mind, &"lung"), false, "no channel work left")


func test_young_bodies_train_and_the_refusal_is_empty() -> void:
	var qi := QiProbe.fresh_actor(&"qi_refining")
	_at_lifespan_share(qi, 0.1)
	assert_eq(FoundationApi.training_refusal(qi), "", "no refusal while young")
	assert_eq(QiTraining.cultivate(qi, 10.0), true, "and the sitting lands")


func test_the_final_attempt_burns_a_year_and_younger_attempts_burn_nothing() -> void:
	var old := _hero({Stat.PHYSIQUE: 1.0})
	_at_lifespan_share(old, 0.8)
	var before: float = old.age_years
	assert_almost_eq(FoundationApi.burn_final_attempt(old), 1.0, "the last years go by the year")
	assert_almost_eq(old.age_years - before, 1.0, "on the body that spent them")
	var young := _hero({Stat.PHYSIQUE: 1.0})
	_at_lifespan_share(young, 0.1)
	before = young.age_years
	assert_almost_eq(FoundationApi.burn_final_attempt(young), 0.0, "no burn while young")
	assert_almost_eq(young.age_years - before, 0.0, "and the body is untouched")
	assert_almost_eq(FoundationApi.burn_final_attempt(null), 0.0, "no actor burns nothing")
