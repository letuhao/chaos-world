extends TestCase

## AUDIT PROBE (MUTATION-e1). `Actor.from_dict` now SKIPS any `module_data` slot that is not a
## Dictionary. The skip was written for one key (`world_polity_version`, a bare int). What does
## a module see when a slot it owns is skipped, and is the loss silent?


func _payload_with_slot(key: String, value: Variant) -> Dictionary:
	var probe := Actor.new(&"probe", {})
	var payload := probe.to_dict()
	var module_data := payload.get("module_data", {}) as Dictionary
	module_data[key] = value
	payload["module_data"] = module_data
	return payload


## The case the skip was written for: a bare-int stamp is skipped by the module_data loop and
## restored instead by `_restore_versioned`, so this key loses nothing.
func test_a_bare_int_polity_stamp_is_still_restored() -> void:
	var restored := Actor.from_dict(_payload_with_slot("world_polity_version", 6))
	assert_ne(restored, null, "the body still restores")
	assert_eq(restored.polity_version(), 6, "and the stamp rides the versioned path")


## A DIFFERENT key, malformed. Nothing names it, nothing warns, and the module's `normalize`
## turns the absent slot into a legal-looking state that is not the state that was saved.
func test_a_malformed_difficulty_slot_silently_becomes_the_neutral_preset() -> void:
	var restored := Actor.from_dict(_payload_with_slot("difficulty_state", ["hard"]))
	assert_ne(restored, null, "the body restores rather than aborting")
	DifficultyApi.attach(restored)
	assert_eq(
		String(DifficultyApi.current_id(restored)),
		"standard",
		"a malformed slot reads as the neutral preset, silently"
	)


## The same shape where the default is NOT the saved value: a soul mirror that never arrives
## normalizes to a fresh soul at FULL integrity.
func test_a_malformed_soul_slot_reads_as_a_whole_soul() -> void:
	var restored := Actor.from_dict(_payload_with_slot("soul_state", "not-a-dict"))
	assert_ne(restored, null, "the body restores rather than aborting")
	assert_eq(
		int(SoulApi.soul(restored).get("integrity", -1)),
		int(SoulApi.soul(restored).get("integrity_max", 0)),
		"the soul reads as WHOLE - the same answer a first-session soul gives"
	)