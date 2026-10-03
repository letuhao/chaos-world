extends TestCase

## ADR 0090's refusal rules, asserted BEHAVIOURALLY rather than by reading the tree.
##
## A test that only checked the shipped twenty would pass on a loader that had no
## refusal at all. These build the bad defs the ADR names and prove each one is turned
## away — an element outside all ten, an empty `mitigation_tags`, an affinity-only one, a
## FLAT on a rate stat, a PERCENT on a zero-baseline stat — so the gate is tested as a
## gate and not as an absence.
##
## ## What ADR 0110 changed here
##
## The tier-2 refusal is GONE, and it goes from this file's headline case to its absence:
## `StatusDef.problems()` accepts every one of the ten authored elements and refuses only
## an element outside all of them. So `test_a_tier_two_element_is_refused` is INVERTED
## rather than deleted — same strength, opposite truth — into a test that a tier-2 def is
## ADMITTED and an invented element is REFUSED. Both halves matter: a gate that widened to
## "everything is fine" and a gate that never widened are equally broken, and only a
## boundary test separates them.
##
## The refusal is still REPORTED rather than silently dropped, and that is now the more
## load-bearing half of the file: with the tier-2 mass refusal gone, a refused def is a
## single malformed `.tres` rather than a whole tier of content, so "the loader said so, and
## here is the reason" is the whole contract.

var _defs: Array[StatusDef] = []


func setup() -> void:
	for def in _defs:
		if def.id != &"":
			_forget(def.id)
	_defs.clear()


## Both halves of a registration undone. `StatusCatalog` is a process-wide singleton and
## the suites in this tree assert on its exact twenty, so a probe left in `_definitions` or
## `_ids` would be reported as a content change by a suite that never made one — and a
## probe left in `_rejected` would put a phantom refusal in the shipped tree's report.
func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


func _tracked(def: StatusDef) -> StatusDef:
	_defs.append(def)
	return def


## A well-formed def, then mutated by the caller into the shape under test. The element
## defaults to `metal` because that is one of the ten AUTHORED elements under ADR 0110 —
## a probe that started on an unknown one would report two problems where the test means
## one, and the "this is the only reason" assertions would stop being about the defect.
func _good(id: StringName) -> StatusDef:
	var def := StatusDef.new()
	def.id = id
	def.element = &"metal"
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = &"refresh"
	def.duration = 10.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test bleed",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
	}
	return def


func test_the_baseline_def_is_accepted_so_the_negatives_mean_something() -> void:
	var def := _good(&"probe_accept")
	assert_eq(def.problems(), [], "the baseline def has no problem")
	assert_eq(StatusCatalog.instance().register(def), true, "and the loader admits it")


func test_every_authored_element_is_admitted_where_only_an_invented_one_is_refused() -> void:
	# The INVERTION of ADR 0090's headline refusal. Its ten tier-2 statuses used to be
	# WITHHELD because ADR 0069 measured every advanced matchup row strictly dominant;
	# ADR 0110 lifts that clause and the balance objection is answered at the provider
	# instead. So a def on each of the FIVE advanced elements is now a legal status, and
	# the refusal moves to the boundary that actually exists: an element outside all ten.
	#
	# Both halves are asserted over every element rather than one sample. A gate that
	# widened to "any element at all" would pass the admission loops and fail the refusal;
	# a gate that never widened fails the admission loops. Only the boundary separates
	# them, so the whole test is the boundary and neither half is a sample of it.
	for element in ElementStats.ADVANCED_ELEMENTS:
		var def := _tracked(_good(StringName("probe_tier2_%s" % String(element))))
		def.element = element
		assert_eq(def.problems(), [], "a %s def is legal now (ADR 0110)" % String(element))
		assert_eq(StatusCatalog.instance().register(def), true, "%s is admitted" % String(element))
	for element in ElementStats.BASE_ELEMENTS:
		var def := _tracked(_good(StringName("probe_tier1_%s" % String(element))))
		def.element = element
		assert_eq(StatusCatalog.instance().register(def), true, "%s is admitted" % String(element))
		assert_eq(def.problems(), [], "and is legal")

	var invented := _tracked(_good(&"probe_unknown_element"))
	invented.element = &"aether"
	var problems := invented.problems()
	assert_eq(problems.size(), 1, "one problem for an element nobody authored")
	assert_eq(
		String(problems[0]).contains("not one of the ten authored elements"),
		true,
		"the refusal names the ten authored elements (aether)"
	)
	assert_eq(StatusCatalog.instance().register(invented), false, "an invented element is refused")
	assert_eq(StatusApi.definition(invented.id), null, "and does not reach the catalogue")


func test_an_empty_mitigation_tags_is_refused() -> void:
	# ADR 0090 restating ADR 0075: a status nothing answers to is a flat damage tax, and
	# the audit rejects it rather than warning about it.
	var def := _good(&"probe_no_mitigation")
	def.mitigation_tags = []
	assert_eq(
		String(def.problems()[0]).contains("mitigation_tags"),
		true,
		"the refusal names mitigation_tags"
	)
	assert_eq(StatusCatalog.instance().register(def), false, "refused")


func test_an_affinity_only_mitigation_is_refused() -> void:
	# The rule `domain_map_contract.gd:168` already enforces for a hazard zone: a player
	# with the wrong spirit root must still have an authored counterplay.
	var def := _good(&"probe_affinity_only")
	def.mitigation_tags = [&"affinity"]
	assert_eq(String(def.problems()[0]).contains("affinity"), true, "named as the reason")
	assert_eq(StatusCatalog.instance().register(def), false, "refused")


func test_an_unknown_mitigation_lever_is_refused() -> void:
	# A closed lever set is what lets the gate hard-fail a typo instead of shipping a
	# counterplay tag that mitigates nothing.
	var def := _good(&"probe_bad_lever")
	def.mitigation_tags = [&"affinity", &"luck"]
	assert_eq(String(def.problems()[0]).contains("names no lever"), true, "named as a typo")
	assert_eq(StatusCatalog.instance().register(def), false, "refused")


func test_the_op_is_validated_against_the_stat_not_the_status() -> void:
	# ADR 0090's load-bearing authoring rule, and the ADR 0022 defect class it prevents:
	# FLAT on a rate stat multiplies a 0..1 baseline, PERCENT on a zero-baseline stat is a
	# guaranteed no-op. Either silently deletes the status, so neither is clamped at runtime
	# — the def is refused instead.
	var on_rate := _good(&"probe_flat_on_rate")
	on_rate.magnitude_unit = &"stat_modifier"
	on_rate.payload["modifiers"] = [{"stat": &"attack_speed", "op": &"flat", "value": 0.3}]
	assert_eq(String(on_rate.problems()[0]).contains("RATE_STATS"), true, "FLAT on a rate id")
	assert_eq(StatusCatalog.instance().register(on_rate), false, "refused")

	var on_zero := _good(&"probe_percent_on_zero")
	on_zero.magnitude_unit = &"stat_modifier"
	on_zero.payload["modifiers"] = [{"stat": &"damage_reduction", "op": &"percent", "value": 0.3}]
	assert_eq(
		String(on_zero.problems()[0]).contains("0.0 baseline"),
		true,
		"PERCENT on a zero-baseline id"
	)
	assert_eq(StatusCatalog.instance().register(on_zero), false, "refused")


func test_a_def_with_no_ticker_is_refused() -> void:
	# A `tick_interval` of zero can never resolve: the DoT channel would spin without ever
	# firing, which is the loop AGENTS.md's disk-safety rule names as a bug.
	var def := _good(&"probe_no_tick")
	def.tick_interval = 0.0
	assert_eq(String(def.problems()[0]).contains("tick_interval"), true, "named as the reason")
	assert_eq(StatusCatalog.instance().register(def), false, "refused")


func test_a_def_that_expires_the_moment_it_lands_is_refused() -> void:
	var def := _good(&"probe_zero_duration")
	def.duration = 0.0
	assert_eq(String(def.problems()[0]).contains("expires"), true, "named as the reason")
	assert_eq(StatusCatalog.instance().register(def), false, "refused")


func test_an_unbounded_def_is_refused() -> void:
	# No cap means an unbounded application has nothing to stop at, which is what
	# `Stacking.STACK` adds into.
	var def := _good(&"probe_no_cap")
	def.magnitude_cap = 0.0
	assert_eq(String(def.problems()[0]).contains("magnitude_cap"), true, "named as the reason")
	assert_eq(StatusCatalog.instance().register(def), false, "refused")


func test_a_refused_def_is_reported_not_silently_dropped() -> void:
	# A loader that refused without saying so would make the withholding a convention
	# instead of a rule, and a designer who authored one would find out in play. Under ADR
	# 0110 that is now a single malformed `.tres` rather than a tier of content, so this is
	# the load-bearing half of the file: the refusal has to arrive WITH A REASON a designer
	# can act on, and it has to arrive at all.
	var def := _good(&"probe_reported")
	def.element = &"aether"
	assert_eq(StatusCatalog.instance().register(def), false, "refused")
	var found := false
	for entry in StatusApi.summary()["rejected"]:
		if String(entry.get("id", "")) == String(def.id):
			found = true
			assert_ne(
				String(entry.get("reason", "")).contains("not one of the ten authored elements"),
				false,
				"and the reported reason is the element gate's, not an empty string"
			)
	assert_eq(found, true, "the refusal is reported through the facade")


func test_applying_an_unknown_or_refused_status_is_refused_by_the_facade() -> void:
	var actor := ActorFactory.build(&"probe")
	var unknown := StatusApi.apply(actor, &"not_a_status")
	assert_eq(bool(unknown["ok"]), false, "an unknown id does not apply")
	assert_eq(String(unknown["reason"]), "unknown_status", "with a named reason")
	assert_eq(actor.has_status(&"not_a_status"), false, "and nothing landed on the actor")
