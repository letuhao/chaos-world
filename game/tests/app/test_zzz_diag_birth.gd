extends TestCase

## THROWAWAY diagnostic. Deleted before delivery.

var _harness: SeamHarness = null


func setup() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_harness = SeamHarness.mount_new()


func teardown() -> void:
	if _harness != null:
		_harness.teardown()
	_harness = null


func test_dump_the_registry_row() -> void:
	var app := _harness.app
	var hero := _harness.app.get("_actor") as Actor
	assert_eq(hero != null, true, "a hero stands")
	BloodlineApi.set_purity(hero, &"tideborn", 1.0)
	assert_eq(BloodlineApi.is_awake(hero, &"tideborn"), true, "the hero is awake on tideborn")
	assert_eq(BloodlineApi.purity_of(hero, &"tideborn"), 1.0, "at full concentration")
	var conceived := FertilityApi.try_conceive(hero, null, 0.0, 0.0)
	assert_eq(conceived, true, "conceived")
	var status := FertilityApi.pregnancy(hero)
	assert_ne(status, null, "a pregnancy exists")
	assert_eq(status.species_id, RaceApi.race_of(hero), "the status captured the mother's race")
	assert_eq(
		FertilityApi.purity_snapshot(hero).has("tideborn"),
		true,
		"the mother's purity snapshot carries tideborn"
	)

	var frames := 0
	while frames < 5000:
		app.call("_process", 1.0 / 60.0)
		frames += 1
		var born: Dictionary = app.get("_born") as Dictionary
		if not born.is_empty():
			var row: Dictionary = born.values()[0] as Dictionary
			printerr("PROBE frames=%d row=%s" % [frames, str(row)])
			for key in row.keys():
				printerr(
					"PROBE   %s = %s (%s)" % [key, str(row[key]), type_string(typeof(row[key]))]
				)
			for kid in born.keys():
				printerr("PROBE key=%s" % kid)
			# Now inspect the actual child actor on the status.
			var st := FertilityApi.pregnancy(hero)
			if st != null:
				printerr("PROBE stage=%d offspring=%d" % [st.stage, st.offspring.size()])
				for off in st.offspring:
					printerr(
						(
							"PROBE   child id='%s' race='%s'"
							% [String(off.id), String(RaceApi.race_of(off))]
						)
					)
					for lid in BloodlineApi.awake(off):
						printerr(
							(
								"PROBE     awake lineage '%s' purity=%f"
								% [String(lid), BloodlineApi.purity_of(off, lid)]
							)
						)
					printerr(
						"PROBE     full purity snapshot=%s" % str(FertilityApi.purity_snapshot(off))
					)
			else:
				printerr("PROBE no pregnancy status any more")
			assert_eq(row.is_empty(), false, "a row exists")
			return
	printerr("PROBE no birth after %d frames" % frames)
	assert_eq(true, false, "a birth happened")
