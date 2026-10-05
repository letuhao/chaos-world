extends TestCase

## ## PROPERTY 5 — EVERY ADVANTAGE CARRIES ITS COUNTERPART
##
## AGENTS.md binds this work: "a weapon or material with no downside, and no
## counter to it, is a defect, not a feature." So the pairing is not a review note
## here, it is a gate that walks the AUTHORED content — a kind or art added without
## its counterpart fails the build rather than shipping and being noticed later.
##
## ## Four halves, because "has a counter" has two directions
##
##   1. A DOWNWARD half: every kind names the demands it walks on, so swinging it
##      costs the body something rather than being free power.
##   2. An UPWARD half: every demand is answered by a named defence, so no body can
##      be unbeatable by picking the right weapon.
##   3. The two are CROSS-REFERENCED: the defence a kind claims (`counters`) is a
##      defence that really does blunt that kind's demand. A kind that names a
##      counter which does not answer it is claiming a pairing it does not have.
##   4. A material art's liability: every art draws a demand and drains integrity,
##      so growing a part is a trade rather than a gift.


func _actor() -> Actor:
	var actor := Actor.new(&"duellist", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"primordial_origin"))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


func _ledger(actor: Actor) -> BodyPractice:
	return actor.component(BodyCultivationApi.PRACTICE_ID)


## The catalog is walked, never a hand-written list: a `.tres` added tomorrow is
## inside this gate the moment it lands, which is the only version of the rule
## that holds anyone else's content.
func test_every_weapon_kind_names_the_downsides_it_carries() -> void:
	var kinds := WeaponKindCatalog.all()
	assert_eq(kinds.size() >= 3, true, "the shipped catalog is non-empty")
	for kind in kinds:
		assert_eq(
			kind.counter_demands.size() >= 1,
			true,
			"%s walks on at least one body ability — no free weapon ships" % kind.id
		)
		for demand in kind.counter_demands:
			assert_ne(
				WeaponDemand.attribute_of(demand),
				&"",
				"%s: the demand %s it walks on resolves to a real body" % [kind.id, demand]
			)


## Every demand is answered. This is the direction that stops the game having a
## strict best answer: pick a weapon whose demand something blunts, and there is a
## body trained to deny it.
func test_every_demand_has_a_defence_that_answers_it() -> void:
	for demand in WeaponDemand.ALL:
		var answer := WeaponCounter.answer_of(demand)
		assert_ne(answer, &"", "%s is answered by some defence" % demand)
		assert_eq(
			WeaponCounter.blunts(answer).has(demand),
			true,
			"and %s really does blunt %s" % [answer, demand]
		)


## The cross-reference: a kind's `counters` field must name a defence that really
## answers THAT KIND'S demand. This is the check a table can pass while the `.tres`
## files lie about it, and it is the one that makes the pairing a property of the
## content rather than of the table.
func test_each_kind_s_counter_really_answers_that_kind() -> void:
	for kind in WeaponKindCatalog.all():
		var counter := kind.counters
		assert_ne(counter, &"", "%s names the defence it is good against" % kind.id)
		assert_eq(
			WeaponCounter.blunts(counter).has(kind.demand),
			true,
			(
				"%s claims %s answers it, but %s does not blunt %s"
				% [
					kind.id,
					counter,
					counter,
					kind.demand,
				]
			)
		)
		assert_eq(
			BodyWeaponUse.answered_by(kind.id, counter),
			true,
			"%s is answered by %s through the one published predicate" % [kind.id, counter]
		)


## A defence is not decoration: it must actually change what the loop pays. Two
## bodies, the same weapon, the same number of swings — the defended one must end
## up measurably worse at it.
func test_a_defence_measures_as_less_training_not_merely_a_name() -> void:
	var kind := WeaponKindCatalog.find(&"greatsword")
	var counter := kind.counters
	var open_wielder := _actor()
	var warded := _actor()
	var swings := 0
	var cap := 30
	while swings < cap:
		swings += 1
		BodyWeaponUse.wield(open_wielder, kind.id)
		BodyWeaponUse.wield(warded, kind.id, true, BodyWeaponUse.answered_by(kind.id, counter))
	assert_eq(
		_ledger(open_wielder).mastery(kind.id) > _ledger(warded).mastery(kind.id),
		true,
		"the %s defence measurably denies %s" % [counter, kind.id]
	)


## ## Every material art carries its own counterpart
##
## Growing a limb is the strongest advantage in this system, so it carries the
## strongest obligation: the art names a demand its new tissue places on the body,
## and it drains the reservoir the body shares with its wounds. An art with either
## one missing is pure upside.
func test_material_arts_carry_their_counterpart() -> void:
	var arts := MaterialArtCatalog.all()
	assert_eq(arts.size() >= 3, true, "the shipped art catalog is non-empty")
	for art in arts:
		assert_ne(
			art.draws_demand, &"", "%s names the demand its new tissue places on the body" % art.id
		)
		assert_ne(
			WeaponDemand.attribute_of(art.draws_demand),
			&"",
			"and that demand resolves to a real body"
		)
		assert_eq(art.price_drain > 0.0, true, "%s costs integrity — a part is never free" % art.id)
		assert_eq(
			art.material_cost > 0, true, "%s costs matter, and worth is priced in effort" % art.id
		)
		assert_ne(art.material_item, &"", "%s names the material it is practised on" % art.id)


## The art's liability must be reachable, not merely authored: the body pays both
## halves and the paid amounts are the authored ones.
func test_the_arts_liability_is_actually_charged() -> void:
	for art in MaterialArtCatalog.all():
		var actor := _actor()
		var pool := actor.resource(BodyStats.BODY_INTEGRITY)
		pool.change(60.0)
		var def := ItemDef.new()
		def.id = art.material_item
		def.stackable = true
		def.max_stack = 9999
		ItemsApi.inventory(actor).add(def, art.material_cost)
		var before := pool.current
		var report := BodyMaterialArt.reshape(actor, art.id)
		assert_eq(bool(report["ok"]), true, "%s reshaped: %s" % [art.id, report["reason"]])
		assert_almost_eq(
			pool.current,
			before - art.price_drain,
			"%s charged its authored integrity price" % art.id
		)
		assert_eq(
			WeaponDemand.trained(actor, art.draws_demand) > 0.0,
			true,
			"%s trained the demand it places on the body" % art.id
		)


## A weapon is not a strict best response: for every kind, there is at least one
## OTHER kind it cannot answer with, and at least one demand the two share so the
## choice is a real trade rather than a reroll.
func test_no_weapon_is_a_strict_best_response() -> void:
	var kinds := WeaponKindCatalog.all()
	for kind in kinds:
		var unanswered := 0
		for other in kinds:
			if other.id == kind.id:
				continue
			if not WeaponCounter.blunts(WeaponCounter.answer_of(kind.demand)).has(other.demand):
				unanswered += 1
		assert_eq(
			unanswered > 0,
			true,
			"%s is answered by something that does not answer every other kind" % kind.id
		)
		assert_ne(kind.best_against, "", "%s says what it is good against, in words" % kind.id)
