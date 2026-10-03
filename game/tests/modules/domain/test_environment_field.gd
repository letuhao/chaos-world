extends TestCase

## AC4 / ADR 0075: what standing in an environment zone DOES.
##
## The point of these tests is to kill a lazy implementation. Three claims are held
## here and each one is the assertion a flat damage-over-time field cannot pass:
##
## 1. `apply` applies a STATUS and leaves health untouched by the call itself.
## 2. The three cultivation paths resolve to three DIFFERENT SUBSTRATES, not one
##    mechanism with three numbers.
## 3. Mitigation is real and is measured, and it is honest about being inert: a zone
##    that publishes `affinity` does NOT help a body cultivator in `super_hot`.
##
## Every loop below is a bounded `for` over a closed collection. There is no `while`.

# ── fixtures ─────────────────────────────────────────────────────────────────


## The unique values in `values`, in first-seen order. A bounded `for`; there is no
## `Array.uniq` in this GDScript and hand-rolling it keeps the assertion readable.
func _distinct(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


## A super_hot zone at band 2, publishing both levers, so a test can strip one out
## without re-authoring the zone.
func _furnace(
	mitigation: Array[StringName] = [&"affinity", &"gear"] as Array[StringName]
) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = &"furnace"
	zone.kind = &"super_hot"
	zone.intensity = EnvironmentZoneDef.BAND_SEVERE
	zone.status_id = &"env_scourge"
	zone.stay_budget = 8.0
	zone.tags = [&"fire"] as Array[StringName]
	zone.mitigation_tags = mitigation
	zone.bounds = Rect2i(2, 3, 4, 5)
	return zone


## A bare actor on `path_id` with the core pools attached. No path module is attached:
## nothing here needs a dantian or a sea, and staying off them keeps the fixture honest
## about what this class actually reads.
func _cultivator(path_id: StringName = PathState.QI) -> Actor:
	var actor := Actor.new(&"gate_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(path_id, &"qi_refining"))
	actor.attach_core_resources()
	return actor


## An actor with core pools and NO cultivation path at all, for the cases that need one
## to be genuinely absent. Passing `""` to `_cultivator` would build a `PathState` with
## an empty id and register it, which is not the same thing.
func _pathless() -> Actor:
	var actor := Actor.new(&"gate_hero", {Stat.PHYSIQUE: 20.0})
	actor.attach_core_resources()
	return actor


## An actor carrying the affinities a `RaceDef` grants. Built from the def rather than
## from literals, so the test is measuring the real spirit-root lever.
func _rooted(path_id: StringName, race: RaceDef) -> Actor:
	var actor := _cultivator(path_id)
	for key in race.affinities.keys():
		actor.affinities.set_value(StringName(str(key)), float(race.affinities[key]))
	return actor


## An actor rooted in ONE element at full strength, for a case where the authored race
## of the day does not carry the affinity under test.
func _rooted_in(path_id: StringName, element: StringName) -> Actor:
	var actor := _cultivator(path_id)
	actor.affinities.set_value(element, EnvironmentField.AFFINITY_STRONG)
	return actor


## The authored races read through the content tree, so a retuned `.tres` moves these
## tests with it instead of leaving a stale literal behind. Returns an empty dict on a
## missing file rather than asserting: a content-loading failure is reported by the
## race module's own tests, and duplicating it here only makes two suites fail.
func _race(relative_path: String) -> RaceDef:
	var path := "res://data/races/%s.tres" % relative_path
	if not ResourceLoader.exists(path):
		return null
	return load(path) as RaceDef


# ── AC4.1: a zone applies a STATUS, and the call itself takes no health ───────


func test_apply_adds_a_status_and_touches_no_pool() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	var health_before := actor.resource(&"health").current
	var stamina_before := actor.resource(&"stamina").current

	var result := EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(result["applied"], true, "a super_hot zone applies to a qi cultivator")
	assert_eq(actor.has_status(zone.status_id), true, "the status is on the actor")
	assert_eq(result["status_id"], "env_scourge", "one authored status id for every path")
	# The load-bearing claim: `apply` is not a damage call. A field that subtracted
	# here would be the bespoke channel ADR 0075 forbids.
	assert_eq(
		actor.resource(&"health").current, health_before, "apply() itself subtracts no health"
	)
	assert_eq(
		actor.resource(&"stamina").current, stamina_before, "apply() itself subtracts no stamina"
	)


func test_the_status_does_the_work_over_ticks() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(actor.has_status(zone.status_id), true, "the status is present before ticking")
	actor.tick_statuses(zone.stay_budget + 0.1)

	assert_eq(actor.has_status(zone.status_id), false, "the status ends on its own budget")


func test_every_path_receives_the_same_status_id() -> void:
	var zone := _furnace()
	for path_id in EnvironmentField.PATHS:
		var actor := _cultivator(path_id)
		var result := EnvironmentField.apply(actor, zone, path_id)
		assert_eq(
			result["status_id"],
			"env_scourge",
			"%s gets the one authored status id" % String(path_id)
		)
		assert_eq(actor.has_status(&"env_scourge"), true, "%s carries it" % String(path_id))


# ── AC4.2: the three paths differ STRUCTURALLY ────────────────────────────────


## The assertion that kills "one flat DoT with three numbers". Three names, three
## values, one pair of comparisons that a swapped magnitude can never satisfy.
func test_the_three_paths_resolve_to_three_different_substrates() -> void:
	var qi := EnvironmentField.effect_for(PathState.QI, &"super_hot")
	var body := EnvironmentField.effect_for(PathState.BODY, &"super_hot")
	var mind := EnvironmentField.effect_for(PathState.MIND, &"super_hot")

	assert_ne(qi, "", "qi resolves to a substrate")
	assert_ne(body, "", "body resolves to a substrate")
	assert_ne(mind, "", "mind resolves to a substrate")
	assert_ne(qi, body, "qi and body are not the same mechanism")
	assert_ne(body, mind, "body and mind are not the same mechanism")
	assert_ne(qi, mind, "qi and mind are not the same mechanism")
	assert_eq(
		qi, EnvironmentField.SUBSTRATE_QI_POOL, "qi loses the qi pool: they cannot cast or flee"
	)
	assert_eq(
		body,
		EnvironmentField.SUBSTRATE_REGEN_DEADLINE,
		"body loses regeneration: a deadline, not a damage race"
	)
	assert_eq(
		mind,
		EnvironmentField.SUBSTRATE_PERCEPTION_FAULT,
		"mind is deceived: misinformation, not injury"
	)


## Structural, not numeric: the substrates differ by NAME, so the amount is free to
## move without the mechanism changing. Every authored kind resolves, and no kind
## hands two paths the same substrate unless it is genuinely the same mechanism.
func test_every_authored_kind_resolves_for_every_path() -> void:
	for kind in EnvironmentZoneDef.KINDS:
		var seen: Array[String] = []
		for path_id in EnvironmentField.PATHS:
			var substrate := EnvironmentField.effect_for(path_id, kind)
			assert_ne(
				substrate, "", "kind '%s' resolves for '%s'" % [String(kind), String(path_id)]
			)
			seen.append(substrate)
		assert_eq(
			seen.size() == _distinct(seen).size(),
			true,
			"kind '%s' gives distinct mechanisms: %s" % [String(kind), ", ".join(seen)]
		)


func test_an_unknown_path_has_no_substrate() -> void:
	assert_eq(
		EnvironmentField.effect_for(&"alchemy", &"super_hot"),
		"",
		"an unknown path resolves to nothing, not a default"
	)
	assert_eq(
		EnvironmentField.effect_for(PathState.QI, &"lava"),
		"",
		"an unknown kind resolves to nothing either"
	)


# ── AC4.3: mitigation is real, and measurably so ─────────────────────────────


## The same zone, the same actor, the same stats — one carrying the matching spirit
## root and one not. Strictly less, not merely different.
func test_a_matching_spirit_root_strictly_reduces_the_amount() -> void:
	var race := _race("emberblood")
	assert_ne(race, null, "the authored emberblood race is loadable")
	if race == null:
		return

	var zone := _furnace([&"affinity", &"gear"] as Array[StringName])
	var rooted := _rooted(PathState.QI, race)
	var bare := _cultivator(PathState.QI)

	var with_root := EnvironmentField.residual_amount(rooted, zone, PathState.QI)
	var without_root := EnvironmentField.residual_amount(bare, zone, PathState.QI)

	assert_eq(
		with_root < without_root,
		true,
		"a fire root blunts a super_hot zone: %f < %f" % [with_root, without_root]
	)
	assert_eq(without_root, zone.magnitude(), "an unmitigated actor carries the authored magnitude")
	assert_almost_eq(
		with_root, zone.magnitude() * 0.5, "a fully-rooted actor gets the authored affinity cap"
	)
	assert_eq(
		EnvironmentField.mitigated_by(rooted, zone),
		"affinity",
		"the named lever is the one that fired"
	)
	assert_eq(
		EnvironmentField.mitigated_by(bare, zone), "", "an unrooted actor is credited with nothing"
	)


## The magnitude is what actually varies, not a hidden stat: two actors differing ONLY
## in affinity differ in the resolved amount.
func test_mitigation_survives_the_whole_call_not_just_the_helper() -> void:
	var race := _race("emberblood")
	if race == null:
		return
	var zone := _furnace()
	var rooted := _rooted(PathState.QI, race)
	var bare := _cultivator(PathState.QI)

	var hit_rooted := EnvironmentField.apply(rooted, zone, PathState.QI)
	var hit_bare := EnvironmentField.apply(bare, zone, PathState.QI)

	assert_eq(hit_rooted["applied"], true, "the rooted actor is affected")
	assert_eq(hit_bare["applied"], true, "the bare actor is affected")
	assert_eq(
		float(hit_rooted["amount"]) < float(hit_bare["amount"]),
		true,
		(
			"apply() reports the mitigated amount: %f < %f"
			% [float(hit_rooted["amount"]), float(hit_bare["amount"])]
		)
	)
	assert_eq(hit_rooted["mitigated_by"], "affinity", "the lever is named, not inferred")
	assert_eq(hit_bare["mitigated_by"], "", "and is absent when nothing answered it")


## The non-affinity levers are real too, and an author who strips `affinity` still gets
## a measured counterplay.
func test_gear_reduces_the_amount_when_affinity_is_not_published() -> void:
	var zone := _furnace([&"gear", &"technique"] as Array[StringName])
	var actor := _cultivator(PathState.QI)
	var bare := EnvironmentField.residual_amount(actor, zone, PathState.QI)

	actor.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": ["fire_ward"]})
	var geared := EnvironmentField.residual_amount(actor, zone, PathState.QI)

	assert_eq(geared < bare, true, "gear reduces it: %f < %f" % [geared, bare])
	assert_eq(EnvironmentField.mitigated_by(actor, zone), "gear", "the named lever is gear")


func test_affinity_is_preferred_but_never_the_only_counterplay() -> void:
	var zone := _furnace()
	var actor := _rooted(PathState.QI, _race("emberblood"))
	actor.set_module_data(EnvironmentField.PILL_TAGS_KEY, {"tags": ["cooling_pill"]})

	assert_eq(
		EnvironmentField.mitigated_by(actor, zone),
		"affinity",
		"affinity loads first: it is what the actor was born with"
	)
	assert_eq(
		zone.has_non_affinity_mitigation(),
		true,
		"the audit's guarantee still holds: a wrong-root player has a lever"
	)
	assert_eq(
		EnvironmentField.mitigates(EnvironmentZoneDef.LEVER_PILL, PathState.QI, &"super_hot"),
		true,
		"and the pill acts on the substrate qi actually resolves to"
	)


# ── AC4.4: the deadline case — affinity does NOT save a body cultivator ───────


## THE assertion. A `super_hot` zone publishing `affinity` gives a fire-rooted body
## cultivator nothing at all: a root reduces DRAIN, and the body cultivator is not
## being drained — they are losing regeneration. A field that read `mitigation_tags`
## and scaled one number would report a mitigation that never happened.
func test_affinity_does_not_help_a_body_cultivator_in_super_hot() -> void:
	var race := _race("emberblood")
	assert_ne(race, null, "the authored emberblood race is loadable")
	if race == null:
		return

	var zone := _furnace([&"affinity", &"gear"] as Array[StringName])
	assert_eq(
		zone.mitigates(EnvironmentZoneDef.LEVER_AFFINITY), true, "the zone does publish affinity"
	)
	assert_eq(race.affinities.has("fire"), true, "and the actor really is fire-rooted")

	var actor := _rooted(PathState.BODY, race)
	var result := EnvironmentField.apply(actor, zone, PathState.BODY)

	assert_eq(result["applied"], true, "the zone still applies to a body cultivator")
	assert_eq(result["mitigated_by"], "", "a fire root is structurally inert on a regen deadline")
	assert_almost_eq(
		float(result["amount"]),
		zone.magnitude(),
		"the amount is the full authored magnitude: no mitigation was invented"
	)
	assert_eq(
		EnvironmentField.mitigates(EnvironmentZoneDef.LEVER_AFFINITY, PathState.BODY, &"super_hot"),
		false,
		"affinity does not act on the body substrate"
	)
	assert_eq(
		EnvironmentField.mitigates(EnvironmentZoneDef.LEVER_AFFINITY, PathState.QI, &"super_hot"),
		true,
		"the very same lever DOES act on the qi substrate — so this is the substrate, not the zone"
	)


## And the converse, so the split cannot be quietly inverted: a body cultivator whose
## root matches the hazard IS mitigated on a substrate that grades damage. `toxic` is
## hostile to `wood`, and `wood` is what a `verdant`/`tidecaller`-style root carries, so
## this exercises affinity exactly where it is honest.
func test_affinity_helps_a_body_cultivator_on_a_graded_substrate() -> void:
	var zone := _furnace()
	zone.kind = &"toxic"

	var actor := _rooted_in(PathState.BODY, &"wood")
	var result := EnvironmentField.apply(actor, zone, PathState.BODY)

	assert_eq(result["applied"], true, "a toxic zone applies to a body cultivator")
	assert_eq(
		result["mitigated_by"],
		"affinity",
		"a wood root blunts graded trauma, because there is something to blunt"
	)
	assert_eq(
		float(result["amount"]) < zone.magnitude(),
		true,
		"and the amount is measurably lower: %f < %f" % [float(result["amount"]), zone.magnitude()]
	)
	assert_eq(
		EnvironmentField.mitigates(EnvironmentZoneDef.LEVER_AFFINITY, PathState.BODY, &"toxic"),
		true,
		"affinity DOES act on the body substrate here — so the inertness above is the substrate"
	)


## BL-0247: for pressure no spirit root mitigates at all, whatever the def publishes.
func test_pressure_is_mitigated_by_no_spirit_root() -> void:
	var race := _race("emberblood")
	if race == null:
		return
	var zone := _furnace()
	zone.kind = &"pressure"

	var actor := _rooted(PathState.QI, race)
	var result := EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(result["applied"], true, "a pressure zone still applies")
	assert_eq(
		result["mitigated_by"], "", "pressure is hostile to no element, so no root answers it"
	)
	assert_almost_eq(
		float(result["amount"]), zone.magnitude(), "full magnitude: nothing mitigated it"
	)


# ── lifecycle: entry, refresh, expiry ─────────────────────────────────────────


func test_the_status_expires_after_the_stay_budget() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	EnvironmentField.apply(actor, zone, PathState.QI)
	assert_eq(actor.has_status(&"env_scourge"), true, "applied")

	actor.tick_statuses(zone.stay_budget - 0.01)
	assert_eq(actor.has_status(&"env_scourge"), true, "still standing inside it, still burning")

	actor.tick_statuses(0.02)
	assert_eq(actor.has_status(&"env_scourge"), false, "past the stay_budget the status is gone")
	assert_eq(actor.statuses.size(), 0, "and nothing is left behind")


func test_a_zero_stay_budget_is_floored_never_made_permanent() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	zone.stay_budget = 0.0
	EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(actor.has_status(&"env_scourge"), true, "applied")
	assert_eq(
		actor.statuses[0].is_permanent(),
		false,
		"a zero budget must not hand out a permanent status; the floor does"
	)
	actor.tick_statuses(EnvironmentField.MIN_DURATION + 0.01)
	assert_eq(actor.has_status(&"env_scourge"), false, "and it expires on the floor")


## Re-entry refreshes rather than stacking: there is no stacking rule for statuses
## anywhere in the repo, so a zone that appended on every frame would be unbounded.
func test_re_entry_refreshes_rather_than_stacking() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	EnvironmentField.apply(actor, zone, PathState.QI)
	actor.tick_statuses(zone.stay_budget - 1.0)
	var again := EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(actor.statuses.size(), 1, "one status, not a stack")
	assert_eq(again["applied"], false, "a refresh is reported as not-newly-applied")
	assert_eq(again["reason"], "refreshed an existing status", "and says why")
	assert_almost_eq(
		actor.statuses[0].remaining, zone.stay_budget, "the budget is restored in full"
	)


# ── telegraph before damage ───────────────────────────────────────────────────


func test_telegraph_reports_the_boundary_and_nothing_is_applied() -> void:
	var zone := _furnace()
	var seen := EnvironmentField.telegraph(zone, false)

	assert_eq(seen["zone_id"], "furnace", "names the zone")
	assert_eq(seen["status_id"], "env_scourge", "names the status that WILL land")
	assert_eq(seen["amount"], zone.magnitude(), "and the unmagnitude an actor should expect")
	assert_eq(seen["boundary_visible"], true, "the boundary is visible before entry")
	assert_eq(seen["entered"], false, "an actor outside the bounds has not entered")
	# Elements compared one by one: `Array == Array` works, but the four numbers say
	# which coordinate drifted, and that is the thing a scene author needs told.
	var bounds: Array = seen["bounds"]
	assert_eq(bounds.size(), 4, "bounds are x, y, w, h in tiles, relative to the room")
	assert_eq(int(bounds[0]), zone.bounds.position.x, "x is relative to the owning room")
	assert_eq(int(bounds[1]), zone.bounds.position.y, "y is relative to the owning room")
	assert_eq(int(bounds[2]), zone.bounds.size.x, "width in tiles")
	assert_eq(int(bounds[3]), zone.bounds.size.y, "height in tiles")
	assert_eq(
		seen["mitigation_levers"], ["affinity", "gear"], "the published levers are telegraphed too"
	)


func test_telegraph_tells_the_scene_the_boundary_was_crossed() -> void:
	var inside := EnvironmentField.telegraph(_furnace(), true)
	assert_eq(inside["entered"], true, "crossing is announced")
	assert_eq(inside["applies_status_on_entry"], true, "and the status lands only then")


# ── loud failures ────────────────────────────────────────────────────────────


func test_an_unknown_path_fails_loudly_with_a_named_reason() -> void:
	var actor := _cultivator(PathState.QI)
	var result := EnvironmentField.apply(actor, _furnace(), &"alchemy")

	assert_eq(result["applied"], false, "an unknown path applies nothing")
	assert_eq(result["amount"], 0.0, "and reports no amount, rather than a default one")
	assert_eq(actor.has_status(&"env_scourge"), false, "no status is left behind")
	assert_eq(
		result["reason"].find("unknown cultivation path 'alchemy'") >= 0,
		true,
		"the reason names the offender: %s" % result["reason"]
	)
	assert_eq(
		result["reason"].find("qi_cultivation") >= 0,
		true,
		"and names what was allowed instead: %s" % result["reason"]
	)


func test_an_unknown_zone_kind_fails_loudly() -> void:
	var zone := _furnace()
	zone.kind = &"lava"
	var result := EnvironmentField.apply(_cultivator(PathState.QI), zone, PathState.QI)

	assert_eq(result["applied"], false, "an unknown kind applies nothing")
	assert_eq(
		result["reason"].find("unknown kind 'lava'") >= 0,
		true,
		"the reason names the kind: %s" % result["reason"]
	)


func test_a_zone_with_no_status_id_is_refused() -> void:
	var zone := _furnace()
	zone.status_id = &""
	var result := EnvironmentField.apply(_cultivator(PathState.QI), zone, PathState.QI)

	assert_eq(result["applied"], false, "a zone authoring no status applies nothing")
	assert_eq(
		result["reason"].find("no status_id") >= 0,
		true,
		"the reason names the missing field: %s" % result["reason"]
	)


func test_a_null_actor_or_zone_is_refused_not_crashed() -> void:
	assert_eq(
		EnvironmentField.apply(null, _furnace(), PathState.QI)["reason"],
		"actor is null",
		"a null actor is named, not dereferenced"
	)
	assert_eq(
		EnvironmentField.apply(_cultivator(PathState.QI), null, PathState.QI)["reason"],
		"zone is null",
		"a null zone is named, not dereferenced"
	)
	assert_eq(EnvironmentField.telegraph(null), {}, "a null zone telegraphs nothing")
	assert_eq(
		EnvironmentField.mitigated_by(_cultivator(PathState.QI), null), "", "and mitigates nothing"
	)


## A mitigation belongs to whoever HAS it: `apply` credits nothing to a path the actor
## does not cultivate, even when the caller asks for that path.
func test_mitigation_is_not_credited_to_a_path_the_actor_does_not_hold() -> void:
	var race := _race("emberblood")
	if race == null:
		return
	var zone := _furnace()
	var actor := _cultivator(PathState.QI)

	var result := EnvironmentField.apply(actor, zone, PathState.BODY)

	assert_eq(result["applied"], true, "the zone is a real hazard, so entry still applies")
	assert_eq(result["mitigated_by"], "", "no root is credited to a path this actor does not hold")
	assert_almost_eq(float(result["amount"]), zone.magnitude(), "and the amount is unmagnitude")


func test_primary_path_is_the_path_the_actor_actually_holds() -> void:
	assert_eq(
		EnvironmentField.primary_path(_cultivator(PathState.MIND)), PathState.MIND, "the held path"
	)
	assert_eq(
		EnvironmentField.primary_path(_pathless()),
		&"",
		"an actor with no path resolves to none, not a guess"
	)
	assert_eq(
		EnvironmentField.residual_amount(_pathless(), _furnace()),
		0.0,
		"and an actor cultivating nothing is measured as nothing, never defaulted onto a path"
	)
