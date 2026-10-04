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


## Spend `seconds` through the PRODUCTION tick: [method StatusApi.tick_statuses], the
## one call `StatusLoop.tick` makes every frame (`app/status_loop.gd:184`).
##
## `actor.tick_statuses` alone is NOT enough, and that is the whole point: it is `core`'s
## merge-and-age half, so it ages a hazard out on its authored budget and emits
## `status_ticked` while spending nothing at all. Every assertion in this file that is
## about CONSEQUENCE drives the module instead, so a status that never registers a runtime
## fails here rather than looking like a healthy hazard.
func _ticks(actor: Actor, seconds: float) -> void:
	StatusApi.tick_statuses(actor, seconds)


## The health `magnitude` spends over `seconds` against `def`, read off the def's own
## authored curve rather than restated as a literal: `share_per_pulse` per pulse, the
## pulse count the authored `tick_interval` owes, and `escalation_per_tick` applied
## ONE-based because `tick_statuses` increments `ticks_elapsed` before it pulses
## (`status/api.gd`) — a pulse that has not fired cannot have escalated. Mirrors
## `StatusRuntime.pulse_magnitude`; a bounded `for` over a pulse count derived from two
## authored numbers, never a `while`.
func _expected_spend(magnitude: float, def: StatusDef, seconds: float) -> float:
	if def == null:
		return 0.0
	var owed := int(floor(seconds / maxf(0.001, def.tick_interval)))
	var share := float(def.payload.get("share_per_pulse", 0.0))
	var escalation := float(def.payload.get("escalation_per_tick", 0.0))
	var cap := maxf(1.0, float(def.payload.get("escalation_cap", 1.0)))
	var total := 0.0
	for pulse in owed:
		total += magnitude * (1.0 + escalation * float(pulse + 1) / cap) * share
	return total


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


# ── BL-0392: the hazard must actually DO something ───────────────────────────
#
# Every test above asserted PRESENCE or EXPIRY. `has_status` is true of a status whose
# magnitude is `0.0` and whose `tick_interval` is `0.0` — one that ages out silently
# and spends nothing — so the whole suite above passed against a hazard that was
# mechanically inert. These assert CONSEQUENCE.


## The applied status carries the residual this field resolved FOR THIS ACTOR, not the
## authored magnitude and not the constructor's `0.0` default. This is the assertion the
## rest of this section rests on: a DOT with no magnitude is a comment.
func test_the_applied_status_carries_the_resolved_magnitude() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	var result := EnvironmentField.apply(actor, zone, PathState.QI)

	var carried := actor.statuses[0]
	assert_eq(carried.id, zone.status_id, "the zone's authored status id is what lands")
	assert_eq(carried.magnitude, float(result["amount"]), "it carries the RESOLVED residual")
	assert_eq(carried.magnitude > 0.0, true, "and that residual is non-zero, not the default 0.0")
	# A DOT with no cadence is the other half of the same silent failure:
	# `_pulses_due` returns 0 for it (`status_registry.gd:168`) and it never pays.
	assert_eq(
		carried.tick_interval,
		EnvironmentField.hazard_cadence(),
		"and a non-zero cadence, so the tick path can resolve it"
	)
	assert_eq(carried.kind, StatusEffect.Kind.DOT, "a hazard spends over time")
	assert_eq(
		carried.stacking,
		StatusEffect.Stacking.REFRESH,
		"REFRESH: standing still must not stack the hazard"
	)
	assert_eq(
		carried.has_mitigation(),
		true,
		"and it publishes the zone's levers, so it is not a hazard nothing answers to"
	)
	assert_eq(
		carried.mitigation_tags,
		zone.mitigation_tags,
		"copied off the zone rather than invented here"
	)


## Mitigation reaches the STATUS, not just the returned dictionary. The old code
## computed the residual, returned it, and applied a bare `0.0` — so this compares two
## actors who differ ONLY in spirit root and reads what each is actually carrying.
func test_mitigation_reaches_the_status_and_not_only_the_answer() -> void:
	var zone := _furnace()
	var race := _race("emberblood")
	assert_ne(race, null, "the authored emberblood race is loadable")
	if race == null:
		return

	var rooted := _rooted(PathState.QI, race)
	var bare := _cultivator(PathState.QI)
	var rooted_hit := EnvironmentField.apply(rooted, zone, PathState.QI)
	var bare_hit := EnvironmentField.apply(bare, zone, PathState.QI)

	assert_eq(
		rooted.statuses[0].magnitude,
		float(rooted_hit["amount"]),
		"the rooted actor's STATUS carries its mitigated amount"
	)
	assert_eq(
		bare.statuses[0].magnitude, float(bare_hit["amount"]), "and so does the unrooted one's"
	)
	assert_eq(
		rooted.statuses[0].magnitude < bare.statuses[0].magnitude,
		true,
		(
			"and the two statuses differ: %f < %f"
			% [rooted.statuses[0].magnitude, bare.statuses[0].magnitude]
		)
	)


## THE consumption proof. A DOT with a real magnitude and a real interval is
## CONSUMED: `tick_statuses` emits one `status_ticked` per pulse, carrying the
## magnitude. A hazard that stood still would emit none — which is the shape of the bug
## this section exists for.
func test_the_tick_path_consumes_the_hazard() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	var applied := EnvironmentField.apply(actor, zone, PathState.QI)
	var expected := float(applied["amount"])
	assert_eq(expected > 0.0, true, "the hazard resolved to something before it is spent")

	var pulses: Array[float] = []
	var handler := func(status_id: StringName, magnitude: float) -> void:
		if status_id == &"env_scourge":
			pulses.append(magnitude)
	actor.status_ticked.connect(handler)

	# Derived from the authored `stay_budget` and the def's `tick_interval`, so a
	# designer retuning either moves this with it instead of leaving a stale literal.
	var owed := int(zone.stay_budget / EnvironmentField.hazard_cadence())
	assert_eq(owed > 0, true, "one stay window owes at least one pulse")

	actor.tick_statuses(zone.stay_budget)
	assert_eq(pulses.size(), owed, "one pulse per authored interval across one stay window")
	for magnitude in pulses:
		assert_eq(magnitude, expected, "and every pulse pays the resolved residual")

	# A window costs its pulses and then EXPIRES — the stay budget is the hazard's
	# lifetime, so a single window cannot pay twice. Sustained exposure is the zone
	# re-applying, which is what `stay_budget` exists for: re-enter, then pay again.
	# Asserted as the pair because "expired" alone would also pass on a status that had
	# already gone inert, and "paid again" alone would pass if the first window paid
	# twice within itself.
	assert_eq(actor.has_status(&"env_scourge"), false, "one window exhausts the budget")
	EnvironmentField.apply(actor, zone, PathState.QI)
	actor.tick_statuses(zone.stay_budget)
	assert_eq(
		pulses.size(),
		owed * 2,
		"and re-entering pays a full second window rather than dying for good"
	)
	actor.status_ticked.disconnect(handler)


## ## THE CONSEQUENCE. The section above proves the hazard PULSES; this one proves the
## pulse COSTS HEALTH.
##
## A signal is not a consequence. `Actor.tick_statuses` emits `status_ticked` for any
## status with a `tick_interval` — `core/status_registry.gd:109` does that with no
## knowledge of a pulse channel — so the whole suite above went green while a furnace
## cost a player exactly nothing: the status was on the actor, `has_status` answered
## true, `status_ticked` fired four times per window, and `resource(&"health").current`
## never moved, because the pulse lives in the `status` module's runtime table and
## nothing in `domain` ever registered one.
##
## So the assertion is a NUMBER OF HEALTH POINTS, computed from the authored def rather
## than pinned as a literal, and driven through the PRODUCTION tick path
## (`StatusApi.tick_statuses`, which is what `StatusLoop.tick` calls once per frame) and
## never through `actor.tick_statuses` alone — the direct call ages a status without
## ever spending it, which is precisely how the defect survived.
func test_standing_in_the_hazard_costs_health_by_the_authored_amount() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	var def := EnvironmentField.hazard_def()
	assert_eq(def != null, true, "the hazard def is authored under res://src/data/statuses")
	var applied := EnvironmentField.apply(actor, zone, PathState.QI)
	var magnitude := float(applied["amount"])
	assert_eq(magnitude > 0.0, true, "the zone resolved to a real residual")

	var before := actor.resource(&"health").current
	# One stay window, spent through the production tick. The status expires inside the
	# same call, so nothing can be left paying after the assertion.
	_ticks(actor, zone.stay_budget)

	# The expected spend is read off the def, not restated: `share_per_pulse` per pulse,
	# the pulse count the authored cadence owes, and the def's own
	# `escalation_per_tick` curve applied one-based (a pulse that has not fired cannot
	# have escalated). A retune of the `.tres` moves this assertion with it.
	var expected := _expected_spend(magnitude, def, zone.stay_budget)

	var spent := before - actor.resource(&"health").current
	assert_almost_eq(
		spent,
		expected,
		"standing in a furnace for one stay window costs exactly what the def authors",
		0.001
	)
	assert_eq(spent > 0.0, true, "and that is a real amount of health, not a rounding dust")
	assert_eq(
		actor.has_status(&"env_scourge"),
		false,
		"the hazard expires on its own budget once it has been paid"
	)


## The CONTROL, and the reason the assertion above is trustworthy: the SAME status, the
## SAME def, the SAME drive, applied through the status module's own public verb already
## spends health. So a zero delta in the case above is this module's seam, not a harness
## that cannot see a pulse at all — which is the difference between "my fix is wrong" and
## "my test proves nothing".
func test_the_same_def_through_the_status_facade_already_costs_health() -> void:
	var def := EnvironmentField.hazard_def()
	var share := float(def.payload.get("share_per_pulse", 0.0))
	var window := 8.0

	var via_facade := _cultivator(PathState.QI)
	var untouched := _cultivator(PathState.QI)
	# `env_scourge` is CULTIVATION scope, so `apply_cultivation` is the verb that takes
	# it, and it is what the CONTROL drives.
	var applied := StatusApi.apply_cultivation(via_facade, &"env_scourge", 1.0)
	assert_eq(
		bool(applied.get("ok", false)),
		true,
		"the hazard def resolves through the status module's own verb"
	)

	_ticks(via_facade, window)
	_ticks(untouched, window)

	# UNTREATED minus TREATED: the treated actor has lost health the untouched one kept,
	# so this is positive exactly when the pulse landed. The other order would make a
	# working pulse read as a failure.
	var spent := untouched.resource(&"health").current - via_facade.resource(&"health").current
	assert_eq(
		spent > 0.0,
		true,
		"the status module's own verb already spends health — the harness can see a pulse"
	)
	# The floor any single pulse owes: one un-escalated share of a full-strength
	# application. Over several intervals the def escalates, so the real spend is higher.
	assert_eq(spent >= share, true, "and at least the authored per-pulse share of %.4f" % share)


## A re-entry must not raise the damage. STACK would compound on every re-apply, so a
## player standing still in a zone would take more and more — the opposite of the
## deadline ADR 0075 asks for.
func test_standing_still_does_not_escalate_the_hazard() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	EnvironmentField.apply(actor, zone, PathState.QI)
	var first := actor.statuses[0].magnitude

	for _window in range(EnvironmentField.PULSES_PER_STAY):
		actor.tick_statuses(zone.stay_budget)
		EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(actor.statuses.size(), 1, "still exactly one hazard instance")
	assert_eq(
		actor.statuses[0].magnitude, first, "and its magnitude is unchanged by four re-applications"
	)


## A refresh after the player mitigates must carry the SMALLER number down, not leave
## the pre-mitigation one on the actor. `StatusRegistry`'s REFRESH keeps the stronger
## magnitude (`status_registry.gd:151`), so `apply` lowers the held value explicitly.
func test_a_refresh_carries_a_smaller_amount_down() -> void:
	var actor := _cultivator(PathState.QI)
	var zone := _furnace()
	EnvironmentField.apply(actor, zone, PathState.QI)
	var unmitigated := actor.statuses[0].magnitude

	actor.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": ["fire_ward"]})
	EnvironmentField.apply(actor, zone, PathState.QI)

	assert_eq(
		actor.statuses[0].magnitude,
		unmitigated * (1.0 - EnvironmentField.GEAR_CAP),
		"the held hazard now carries the geared-down residual"
	)


## The authored def exists, is readable, and is what the field resolves its cadence
## from. BL-0392's first half was `StatusCatalog.definition("env_scourge") == null`
## with no `.tres` anywhere — so this asserts the FILE is there rather than that the
## catalogue publishes it (see the next test for why that is a different question).
func test_the_hazard_has_an_authored_def() -> void:
	var def := EnvironmentField.hazard_def()
	assert_ne(def, null, "env_scourge has a StatusDef on disk")
	if def == null:
		return
	assert_eq(def.id, &"env_scourge", "resolved by id, not by filename")
	assert_eq(def.kind, &"dot", "a hazard is a damage-over-time channel")
	assert_eq(def.scope, &"cultivation", "and never opposed by combat resistance")
	assert_eq(def.stacking, &"refresh", "one hazard is one hazard")
	assert_eq(
		def.tick_interval,
		EnvironmentField.hazard_cadence(),
		"the cadence the field applies IS the authored one, not a literal"
	)
	assert_eq(
		def.magnitude_cap,
		EnvironmentField.MAX_MAGNITUDE,
		"and the ceiling matches the authored hazard ladder's loudest row"
	)
	# The counterplay contract, which ADR 0075 makes mandatory and `problems()` checks.
	assert_eq(def.mitigation_tags.has(&"affinity"), true, "affinity answers a hazard")
	assert_eq(
		def.mitigation_tags.has(&"pill") or def.mitigation_tags.has(&"technique"),
		true,
		"and a wrong-root player has a non-affinity counterplay"
	)


## The def is DELIBERATELY not in `res://data/statuses/`, and this is why. It rides no
## element, so `StatusDef.problems()` refuses it; and that tree is a closed twenty whose
## exact id set another suite pins. Both facts are asserted rather than asserted-by-
## absence, so a future edit that quietly moves the file fails here instead of
## breaking a suite in a module this file does not own.
func test_the_hazard_def_is_element_free_on_purpose() -> void:
	var def := EnvironmentField.hazard_def()
	assert_ne(def, null, "the def is readable")
	if def == null:
		return
	assert_eq(def.element, &"", "a hazard rides no element: it is a place, not a blow")
	# `StatusCatalog` scans `res://data/statuses` only, so the def is not published
	# there — and must not be, because it could not pass that tree's gate.
	assert_eq(
		StatusCatalog.instance().definition(&"env_scourge"),
		null,
		"and is not in the element-bound catalogue, which would refuse it"
	)
	assert_eq(
		ResourceLoader.exists("res://data/statuses/env_scourge.tres"),
		false,
		"no such file is authored there either"
	)
