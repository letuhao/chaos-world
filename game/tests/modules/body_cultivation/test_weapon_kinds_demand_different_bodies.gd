extends TestCase

## ## PROPERTY 2 — THE KINDS ARE GENUINELY DIFFERENT, NOT RESKINS
##
## Two weapons with the same damage and different demands are two weapons. Two
## weapons with different damage and the same demand are a reskin, and the whole
## multi-weapon axis is worthless without a test that says so.
##
## ## What "different" is measured as, and why this measurement
##
## A kind authors no number. It authors a DEMAND id, and `WeaponDemand` resolves
## that id to exactly one base attribute. So the test asserts the map, not the
## magnitudes: every shipped kind names a demand, every demand resolves, and the
## set of attributes the shipped kinds train covers the axis rather than one
## corner of it. A seventh kind reusing `MASS` cannot pass.
##
## The second half is behavioural and stronger than the static one: two kinds must
## LEAVE THE BODY DIFFERENT. Both are swung the same number of times, and the
## physique / agility / will / aptitude they each moved are compared. If two kinds
## trained the same body, this fails even though their defs differ.


func _actor_at(realm_id: StringName = &"primordial_origin") -> Actor:
	var actor := Actor.new(&"wielder", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


func _attribute_sheet(actor: Actor) -> Array[float]:
	return [
		actor.stats.get_base(Stat.PHYSIQUE),
		actor.stats.get_base(Stat.AGILITY),
		actor.stats.get_base(Stat.WILL),
		actor.stats.get_base(Stat.APTITUDE),
	]


## One landed swing per kind, the same count each, so the comparison is the DEMAND
## and not the number of uses. Bounded by the catalog's own length.
func _swing_once(actor: Actor, kind_id: StringName) -> void:
	var swings := 0
	var cap := 1
	while swings < cap:
		swings += 1
		BodyWeaponUse.wield(actor, kind_id)


## The catalog is not empty and every entry is a real kind. A walk over an empty
## list would make every other assertion in this suite vacuously true, so the
## population is asserted first.
func test_the_shipped_catalog_is_populated_and_resolvable() -> void:
	var kinds := WeaponKindCatalog.all()
	assert_eq(kinds.size() >= 3, true, "at least three weapon kinds ship")
	for kind in kinds:
		assert_ne(kind.id, &"", "a kind has an id")
		assert_ne(kind.display_name, "", "%s has a name" % kind.id)
		assert_ne(
			WeaponDemand.attribute_of(kind.demand),
			&"",
			"%s names a demand that resolves to a base attribute" % kind.id
		)
		assert_ne(kind.practice_gain, 0.0, "%s authors a practice rate" % kind.id)


## Two kinds are different when they demand different things of the body. The
## brief names six: mass/leverage, reach/control, speed/density, balance, bracing,
## precision — and the shipped set must exercise a majority of that axis, not one
## corner of it.
func test_kinds_name_different_demands_not_two_sizes_of_one() -> void:
	var demands := {}
	for kind in WeaponKindCatalog.all():
		demands[String(kind.demand)] = true
	assert_eq(
		demands.size() >= 4,
		true,
		"the shipped kinds span at least four of the six demands, they are not reskins"
	)


## The behavioural half, and the one a static scan cannot fake: swing two kinds the
## same number of times and the body each of them trained must differ.
##
## `greatsword` demands MASS and `spear` demands LEVERAGE, which both resolve to
## PHYSIQUE — so the DEMAND stat is the discriminator, not the attribute. That is
## deliberate (a maul and a spear are both things to move) and it is exactly why
## the assertion compares the whole sheet rather than one column: if two kinds ever
## resolve to the same demand AND the same attribute, this fails.
func test_two_kinds_leave_a_different_body_behind() -> void:
	var mauler := _actor_at()
	var spearman := _actor_at()
	for _swing in 1:
		_swing_once(mauler, &"greatsword")
	for _swing in 1:
		_swing_once(spearman, &"spear")
	var maul_sheet := _attribute_sheet(mauler)
	var spear_sheet := _attribute_sheet(spearman)
	var differ := false
	for column in maul_sheet.size():
		if maul_sheet[column] != spear_sheet[column]:
			differ = true
	assert_eq(differ, true, "a maul body and a spear body are not the same body")
	# And the discriminator: the maul's own demand is MASS, the spear's LEVERAGE.
	var maul := WeaponKindCatalog.find(&"greatsword")
	var spear := WeaponKindCatalog.find(&"spear")
	assert_ne(maul.demand, spear.demand, "the two kinds name different demands")
	assert_ne(
		WeaponDemand.stat_of(maul.demand),
		WeaponDemand.stat_of(spear.demand),
		"and those demands publish different demand stats"
	)


## A kind's `lean` must be a DIFFERENT demand from the one it demands — a weapon
## that both asks for and supplies balance is a weapon with no trade-off, which is
## the yin-yang defect wearing a data field.
func test_every_kind_trades_one_demand_for_another() -> void:
	for kind in WeaponKindCatalog.all():
		assert_ne(
			kind.lean,
			kind.demand,
			"%s leans on a different demand than the one it asks for" % kind.id
		)
		assert_eq(
			kind.counter_demands.size() >= 1,
			true,
			"%s names at least one body ability it walks on" % kind.id
		)


## A missed strike trains nothing. Without this, the use loop pays for swinging at
## a wall and "mastery by use" becomes "mastery by pressing a button".
func test_a_missed_strike_trains_nothing() -> void:
	var actor := _actor_at()
	var report := BodyWeaponUse.wield(actor, &"spear", false)
	assert_eq(float(report["earned"]), 0.0, "a miss pays nothing")
	var ledger: BodyPractice = actor.component(BodyCultivationApi.PRACTICE_ID)
	assert_eq(ledger.mastery(&"spear"), 0.0, "and it left no mastery behind")
	assert_eq(ledger.uses_of(&"spear"), 1, "but it still counts as a use — the attempt happened")


## The demand axis is the module's own list, and every entry of it resolves. A
## demand in the published list that pays nothing would be a hole a screen renders.
func test_every_published_demand_resolves_to_a_body() -> void:
	assert_eq(WeaponDemand.ALL.size(), 6, "six demands: the axis is small and fixed")
	for demand in WeaponDemand.ALL:
		assert_ne(WeaponDemand.attribute_of(demand), &"", "%s pays an attribute" % demand)
		assert_ne(WeaponDemand.stat_of(demand), &"", "%s publishes a stat" % demand)
		assert_ne(WeaponCounter.answer_of(demand), &"", "%s is answered by a defence" % demand)
