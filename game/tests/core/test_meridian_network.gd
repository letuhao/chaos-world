extends TestCase

## ADR 0017: MeridianNetwork manages meridian unlock, state, and bonuses.


func test_unlock_for_realm() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	assert_eq(network.get_meridian(&"lung") != null, true, "lung unlocked")
	assert_eq(network.get_meridian(&"liver") != null, false, "liver not yet")
	assert_eq(network.get_meridian(&"du_mai") != null, false, "du_mai not yet")


func test_unlock_progression() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"nascent_soul")
	assert_eq(network.get_meridian(&"lung") != null, true, "lung unlocked")
	assert_eq(network.get_meridian(&"heart") != null, true, "heart unlocked")
	assert_eq(network.get_meridian(&"pericardium") != null, false, "pericardium not yet")


func test_state_transitions() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"open", "opened")
	network.expand_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"expanded", "expanded")
	network.strengthen_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"strengthened", "strengthened")


func test_damage_and_repair() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.damage_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"damaged", "damaged")
	network.repair_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"open", "repaired to open")


func test_flow_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	assert_almost_eq(network.get_flow_bonus(), 0.0, "no flow bonus when closed")
	network.open_meridian(&"lung")
	assert_almost_eq(network.get_flow_bonus(), 0.10, "flow bonus from open")


func test_capacity_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	assert_almost_eq(network.get_capacity_bonus(), 0.0, "no capacity bonus when open")
	network.expand_meridian(&"lung")
	assert_almost_eq(network.get_capacity_bonus(), 0.05, "capacity bonus from expanded")


func test_power_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.expand_meridian(&"lung")
	assert_almost_eq(network.get_power_bonus(), 0.0, "no power bonus when expanded")
	network.strengthen_meridian(&"lung")
	assert_almost_eq(network.get_power_bonus(), 0.05, "power bonus from strengthened")


func test_damaged_reduces_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	var full_bonus := network.get_flow_bonus()
	network.damage_meridian(&"lung")
	assert_almost_eq(network.get_flow_bonus(), full_bonus * 0.5, "damaged reduces flow")


func test_serialization_round_trip() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.expand_meridian(&"lung")
	var restored := MeridianNetwork.from_dict(network.to_dict())
	assert_eq(restored.get_meridian(&"lung").state, &"expanded", "state round trip")
	assert_almost_eq(restored.get_flow_bonus(), network.get_flow_bonus(), "flow round trip")
	assert_almost_eq(
		restored.get_capacity_bonus(), network.get_capacity_bonus(), "capacity round trip"
	)
