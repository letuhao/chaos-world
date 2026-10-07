extends TestCase

## The C-batch CONTENT (ADR 0902, P2/P6/P7/P9 + P12/P4): the twenty shipped defs carry
## the authored family/categories taxonomy, the control defs carry a derived ICD, every
## pulsing def carries a derived counter, and the two ambient defs (a meter, a
## contagion) load with the configs their kinds require. Each claim is read off the
## shipped tree through the catalogue, never restated.

const FAMILY_BY_ELEMENT := {
	&"fire": &"burn",
	&"water": &"tide",
	&"ice": &"frost",
	&"earth": &"quake",
	&"wood": &"growth",
	&"metal": &"edge",
	&"lightning": &"spark",
	&"light": &"radiance",
	&"dark": &"decay",
	&"wind": &"gale",
}


func test_every_shipped_def_carries_its_family_and_categories() -> void:
	var ids := StatusCatalog.instance().status_ids()
	assert_eq(ids.size(), 20, "the closed twenty")
	for status_id in ids:
		var def := StatusCatalog.instance().definition(status_id)
		assert_ne(def, null, "%s resolves" % String(status_id))
		if def == null:
			continue
		assert_ne(String(def.family), "", "%s names its family" % String(status_id))
		assert_eq(
			def.family,
			FAMILY_BY_ELEMENT.get(def.element, &""),
			"%s's family is its element's word" % String(status_id)
		)
		assert_ne(def.categories.is_empty(), true, "%s names its categories" % String(status_id))
		assert_eq(
			def.categories.has(def.kind),
			true,
			"%s's category list carries its own kind" % String(status_id)
		)


## The control defs carry the derived lockout: `icd == duration` (C5's rule — a control
## cannot be re-applied until its own duration would have elapsed).
func test_every_control_authors_its_derived_icd() -> void:
	var controls := 0
	for status_id in StatusCatalog.instance().status_ids():
		var def := StatusCatalog.instance().definition(status_id)
		if def == null or def.kind != &"control":
			continue
		controls += 1
		assert_almost_eq(
			def.icd, def.duration, "%s locks out for its own duration" % String(status_id), 1e-6
		)
	assert_eq(controls > 0, true, "the catalogue ships controls to check")


## Every PULSING def carries a counter whose `every_hits` is its own cadence: the number
## of pulses `duration / tick_interval` (C2's derivation — no hand-picked number).
func test_every_pulsing_def_authors_its_derived_counter() -> void:
	var counted := 0
	for status_id in StatusCatalog.instance().status_ids():
		var def := StatusCatalog.instance().definition(status_id)
		if def == null:
			continue
		var share := float(def.payload.get("share_per_pulse", 0.0))
		if share <= 0.0:
			continue
		if def.magnitude_unit != &"health_share" and def.magnitude_unit != &"element_power":
			continue
		counted += 1
		var counter: Variant = def.payload.get("counter", {})
		assert_eq(counter is Dictionary, true, "%s authors payload.counter" % String(status_id))
		if not (counter is Dictionary):
			continue
		var expected := maxi(1, roundi(def.duration / maxf(0.001, def.tick_interval)))
		assert_eq(
			int((counter as Dictionary).get("every_hits", 0)),
			expected,
			"%s counts its own cadence" % String(status_id)
		)
	assert_eq(counted > 0, true, "the catalogue ships pulsing defs to count")


func test_the_ambient_meter_def_loads_with_its_derived_threshold() -> void:
	var def := StatusCatalog.instance().any_definition(&"blood_charge")
	assert_ne(def, null, "the ambient meter def loads")
	if def == null:
		return
	assert_eq(def.kind, &"meter", "and it is a meter")
	var meter: Variant = def.payload.get("meter", {})
	assert_eq(meter is Dictionary, true, "carrying payload.meter")
	if meter is Dictionary:
		assert_almost_eq(
			float((meter as Dictionary).get("every", 0.0)),
			def.magnitude_cap,
			"whose threshold is the def's own cap",
			1e-6
		)


func test_the_ambient_contagion_def_loads_with_its_authored_config() -> void:
	var def := StatusCatalog.instance().any_definition(&"plague")
	assert_ne(def, null, "the ambient contagion def loads")
	if def == null:
		return
	assert_eq(def.kind, &"contagion", "and it is a contagion")
	assert_eq(def.stacking, &"coexist", "with per-hop instances")
	var spread: Variant = def.payload.get("spread", {})
	assert_eq(spread is Dictionary, true, "carrying payload.spread")
	if spread is Dictionary:
		assert_eq(
			int((spread as Dictionary).get("max_hops", 0)) <= StatusSpread.MAX_HOP_DEPTH,
			true,
			"and its hop ceiling rides inside the constant"
		)
		assert_eq(
			float((spread as Dictionary).get("chance", 0.0)) > 0.0, true, "with a live chance"
		)
