extends TestCase

## BL-0951 / ADR 0939, S15: the foundation row on the qi breakthrough preview.
##
## The read model publishes the carried foundation and the target realm's authored floor, so
## a screen renders met/unmet and the wall AHEAD without reaching for the seed (ADR 0043).


func _actor() -> Actor:
	var actor := (
		ActorFactory
		. build(
			&"qi_row_reader",
			{
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				QiStats.QI_AFFINITY: 20.0,
				QiStats.QI_CONTROL: 15.0,
				QiStats.DANTIAN_CAPACITY: 30.0,
			}
		)
	)
	QiCultivationApi.attach(actor)
	actor.set_path(PathState.new(QiPath.PATH_ID, RealmDefaults.ladder().realms()[0].id))
	return actor


func test_the_panel_publishes_the_carried_foundation() -> void:
	var actor := _actor()
	var live := QiCultivationApi.panel_state(actor)
	assert_eq(live.has("foundation"), true, "the carried foundation is published")
	assert_almost_eq(
		float(live.get("foundation", -1.0)), FoundationApi.foundation(actor), "matching the facade"
	)


func test_the_panel_publishes_the_wall_ahead() -> void:
	var actor := _actor()
	var live := QiCultivationApi.panel_state(actor)
	assert_eq(live.has("min_foundation"), true, "the target realm's floor is published")
	var target := StringName(live.get("target", ""))
	if target != &"":
		var seed := QiRealmSeed.for_realm(target)
		if seed != null:
			assert_almost_eq(
				float(live.get("min_foundation", -1.0)),
				seed.min_foundation,
				"and it is the floor the preview enforces"
			)
