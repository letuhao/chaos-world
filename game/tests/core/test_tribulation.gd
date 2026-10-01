extends TestCase

## ADR 0020: Heavenly Tribulation system tests.


func test_tribulation_start_initializes_state() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 5, 1.5)
	tribulation.start(actor, &"earth_immortal")
	assert_eq(tribulation.phase, Tribulation.WARNING, "starts in warning phase")
	assert_eq(tribulation.wave, 0, "starts at wave 0")
	assert_eq(tribulation.max_waves, 7, "max_waves computed from realm")
	assert_eq(tribulation.difficulty > 0.0, true, "difficulty computed from realm")


func test_tribulation_advance_wave_transitions() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.advance_wave()
	assert_eq(tribulation.phase, Tribulation.TRIAL, "warning -> trial")
	assert_eq(tribulation.wave, 1, "wave 1")
	tribulation.advance_wave()
	assert_eq(tribulation.wave, 2, "wave 2")
	tribulation.advance_wave()
	assert_eq(tribulation.wave, 3, "wave 3")
	tribulation.advance_wave()
	assert_eq(tribulation.phase, Tribulation.CLIMAX, "trial -> climax")
	tribulation.advance_wave()
	assert_eq(tribulation.phase, Tribulation.AFTERMATH, "climax -> aftermath")


func test_tribulation_is_complete() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	assert_eq(tribulation.is_complete(), false, "not complete at start")
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.advance_wave()
	assert_eq(tribulation.is_complete(), true, "complete after aftermath")


func test_tribulation_get_rewards() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 2.0)
	var rewards := tribulation.get_rewards()
	assert_eq(rewards.has("tribulation_essence"), true, "has essence")
	assert_eq(rewards.has("blessing"), true, "has blessing")
	assert_eq(rewards.has("insight"), true, "has insight")
	assert_eq(rewards.has("mark"), true, "has mark")
	assert_eq(rewards["tribulation_essence"], 20, "essence scales with difficulty")
	assert_eq(rewards["mark"], 1, "mark is 1")


func test_tribulation_apply_success() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 20.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, &"earth_immortal")
	actor.tribulation = tribulation
	tribulation.apply_result(actor, true)
	assert_eq(actor.tribulation, null, "tribulation cleared after result")
	assert_eq(actor.resource(&"tribulation_essence") != null, true, "essence resource added")
	assert_eq(actor.has_status(&"heavenly_blessing"), true, "blessing status added")
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION) > 20.0, true, "insight boosts comprehension")


func test_tribulation_apply_failure() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 20.0})
	actor.meridians.unlock_for_realm(&"earth_immortal")
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, &"earth_immortal")
	actor.tribulation = tribulation
	tribulation.apply_result(actor, false)
	assert_eq(actor.tribulation, null, "tribulation cleared after result")
	assert_almost_eq(
		actor.stats.get_base(Stat.COMPREHENSION), 15.0, "dao heart damage reduces comprehension"
	)


func test_tribulation_serialization() -> void:
	var tribulation := Tribulation.new(Tribulation.HEART_DEMON, 7, 2.5)
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.preparation = {"formation": 0.3, "pill": 0.2}
	var data := tribulation.to_dict()
	assert_eq(data["type"], "heart_demon", "type serialized")
	assert_eq(data["phase"], "trial", "phase serialized")
	assert_eq(data["wave"], 2, "wave serialized")
	assert_eq(data["max_waves"], 7, "max_waves serialized")
	assert_eq(data["difficulty"], 2.5, "difficulty serialized")
	assert_eq(data["preparation"]["formation"], 0.3, "preparation serialized")
	var restored := Tribulation.from_dict(data)
	assert_eq(restored.type, Tribulation.HEART_DEMON, "type restored")
	assert_eq(restored.phase, Tribulation.TRIAL, "phase restored")
	assert_eq(restored.wave, 2, "wave restored")
	assert_eq(restored.max_waves, 7, "max_waves restored")
	assert_eq(restored.difficulty, 2.5, "difficulty restored")
	assert_eq(restored.preparation["formation"], 0.3, "preparation restored")


func test_tribulation_all_types() -> void:
	var types := [
		Tribulation.LIGHTNING,
		Tribulation.HEART_DEMON,
		Tribulation.KARMIC,
		Tribulation.ELEMENTAL,
		Tribulation.SPATIAL,
		Tribulation.TEMPORAL,
	]
	for t in types:
		var tribulation := Tribulation.new(t, 3, 1.0)
		assert_eq(tribulation.type, t, "type %s set" % t)
