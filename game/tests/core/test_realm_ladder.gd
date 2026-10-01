extends TestCase

## ADR 0005: one shared 30-realm ladder in four tiers for every cultivation system.


func test_ladder_shape() -> void:
	var ladder := RealmDefaults.ladder()
	assert_eq(ladder.size(), 30, "30 realms")
	assert_eq(ladder.tier_realms(RealmDefaults.MORTAL).size(), 9, "9 mortal")
	assert_eq(ladder.tier_realms(RealmDefaults.SPIRIT).size(), 9, "9 spirit")
	assert_eq(ladder.tier_realms(RealmDefaults.IMMORTAL).size(), 9, "9 immortal")
	assert_eq(ladder.tier_realms(RealmDefaults.TRANSCENDENT).size(), 3, "3 transcendent")


func test_lookup_and_tier() -> void:
	var ladder := RealmDefaults.ladder()
	assert_eq(ladder.index_of(&"qi_refining"), 0, "first index")
	assert_eq(ladder.index_of(&"primordial_origin"), 29, "last index")
	assert_eq(ladder.tier_of(&"qi_refining"), RealmDefaults.MORTAL, "mortal tier")
	assert_eq(ladder.tier_of(&"spirit_sea"), RealmDefaults.SPIRIT, "spirit tier")
	assert_eq(ladder.tier_of(&"earth_immortal"), RealmDefaults.IMMORTAL, "immortal tier")
	assert_eq(ladder.tier_of(&"dao_ancestor"), RealmDefaults.TRANSCENDENT, "transcendent tier")


func test_next_realm() -> void:
	var ladder := RealmDefaults.ladder()
	assert_eq(ladder.next(&"qi_refining").id, &"foundation", "next realm")
	assert_eq(ladder.next(&"tribulation").id, &"spirit_condensation", "tier boundary")
	assert_eq(ladder.next(&"primordial_origin"), null, "no realm past the top")


func test_unknown_realm() -> void:
	var ladder := RealmDefaults.ladder()
	assert_eq(ladder.has(&"nope"), false, "unknown id")
	assert_eq(ladder.index_of(&"nope"), -1, "unknown index")
	assert_eq(ladder.tier_of(&"nope"), 0, "unknown tier")
