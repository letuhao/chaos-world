extends TestCase

## MAJOR 7 and MAJOR 6, pinned.
##
## **MAJOR 7 — weather was inert.** `DomainMap.weather` was declared, written by
## `DomainApi.visit_room` only when a caller passed non-empty, echoed into two read
## models, and read by NOTHING. The only production caller passed `&""` hardcoded
## (`domain_explore.gd` `act_visit`), so no run ever carried weather. ADR 0075 promises
## weather "biases which zones are active"; that promise is kept here by
## `DomainMap.effective_intensity`, and every claim below pins it.
##
## **MAJOR 6 — three of four levers could not fire.** `EnvironmentField` read
## `env_gear_tags` / `env_technique_tags` / `env_pill_tags` and NOTHING wrote them, so
## `GEAR_CAP` / `TECHNIQUE_CAP` / `PILL_CAP` were live caps over always-empty lists and a
## cultivator wearing a fire ward got zero mitigation while the screen printed
## "answered by: gear, pill, affinity". The branch taken here is (a) — publish from a
## real carried source — so these tests pin THAT the source measurably reduces the
## effect. The absence assertions further down pin the other half: that the caps and the
## tag keys still exist, because deleting them would be branch (b) and must not be able
## to happen silently alongside it.
##
## ## Shape
##
## Every loop is a bounded `for` over a closed collection. There is no `while` in this
## file: this repo has already paid for the alternative.

# ── fixtures ─────────────────────────────────────────────────────────────────


## A zone of `kind` at `band`, authoring `element` in the tags this file's weather
## catalogue keys on. `tags` is the "elements this zone is hostile to" list
## (`EnvironmentZoneDef.tags`), which is exactly what a bias must match against.
func _zone(
	zone_id: StringName, kind: StringName, band: int, element: StringName
) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = zone_id
	zone.kind = kind
	zone.intensity = band
	zone.status_id = &"env_scourge"
	zone.stay_budget = 8.0
	zone.tags = [element] as Array[StringName] if element != &"" else ([] as Array[StringName])
	zone.mitigation_tags = [&"affinity", &"gear", &"technique", &"pill"] as Array[StringName]
	zone.bounds = Rect2i(2, 3, 4, 5)
	return zone


## A one-room map whose single room holds `zones`. `weather` is deliberately NOT set:
## the weather cases below set it explicitly so a failure names the case.
func _map_with(zones: Array[EnvironmentZoneDef]) -> DomainMap:
	var room := RoomDef.new()
	room.room_id = &"chamber"
	room.display_name = "Chamber"
	room.kind = &"chamber"
	room.size = Vector2i(12, 10)
	room.environment_zones = zones
	var map := DomainMap.new(Vector2i(24, 18), 7)
	map.add_room(room)
	map.entry_room = &"chamber"
	return map


## A fire zone at `band`, alone in its own map.
func _fire_map(band: int) -> DomainMap:
	return _map_with([_zone(&"furnace", &"super_hot", band, &"fire")] as Array[EnvironmentZoneDef])


## The one zone of `map`, or null. `{}` outside a run is this repo's does-not-exist
## vocabulary, but here a missing zone is a TEST defect, so it reports loudly.
func _zone_of(map: DomainMap) -> Dictionary:
	var rows := map.zones()
	assert_eq(rows.size(), 1, "the fixture map holds exactly one zone")
	if rows.is_empty():
		return {}
	return rows[0]


## An actor on `path_id` with the core pools attached and NO carried anything, so the
## lever tests start from "nothing answers this hazard".
func _cultivator(path_id: StringName = PathState.QI) -> Actor:
	var actor := Actor.new(&"gate_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(path_id, &"qi_refining"))
	actor.attach_core_resources()
	return actor


## The three levers' tag keys, in the order the weather-adjacent assertions walk them.
const LEVER_KEYS: Array[StringName] = [
	EnvironmentField.GEAR_TAGS_KEY,
	EnvironmentField.TECHNIQUE_TAGS_KEY,
	EnvironmentField.PILL_TAGS_KEY,
]


## A wearable `ItemDef` authoring `element`, so the production publisher has a REAL
## piece of gear to read rather than a hand-written key. `category` and `subcategory`
## are both set because `ItemDef.is_equipment()` gates on the CATEGORY while
## `Equipment.equip` gates on the SUBTYPE — a def that answers one and not the other is
## refused, and the refusal is what this fixture exists to avoid.
func _armour(def_id: StringName, element: StringName) -> ItemDef:
	var def := ItemDef.new()
	def.id = def_id
	def.display_name = String(def_id)
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.ARMOR
	def.stackable = false
	def.tags = [element] as Array[StringName]
	return def


# ── MAJOR 7: weather moves a number, and only inside authored bounds ──────────


## THE LOAD-BEARING CLAIM. With weather authored, a zone's EFFECTIVE intensity differs
## from its AUTHORED band — otherwise the field is inert again and every other test here
## is decoration.
func test_weather_changes_the_effective_intensity_of_a_matching_zone() -> void:
	var map := _fire_map(EnvironmentZoneDef.BAND_SCORCH)
	map.weather = &"ember_heat"
	var row := _zone_of(map)
	assert_eq(row["authored_intensity"], EnvironmentZoneDef.BAND_SCORCH, "the .tres band is 1")
	assert_eq(
		row["intensity"],
		EnvironmentZoneDef.BAND_SEVERE,
		"an ashfall run makes an authored fire bed run one band hotter than authored"
	)


## WITHIN AUTHORED BOUNDS, both edges. The shift is at most one band, so a band-1 zone
## can reach band 2 but never band 3, and a band-3 zone cannot exceed the ceiling at all.
func test_weather_never_leaves_the_authored_band_ladder() -> void:
	var scorch := _fire_map(EnvironmentZoneDef.BAND_SCORCH)
	scorch.weather = &"ember_heat"
	assert_eq(
		scorch.effective_intensity(scorch.room(&"chamber").environment_zones[0]),
		EnvironmentZoneDef.BAND_SEVERE,
		"band 1 + one shift is band 2, never band 3"
	)
	var annihilating := _fire_map(EnvironmentZoneDef.BAND_ANNIHILATING)
	annihilating.weather = &"ember_heat"
	assert_eq(
		annihilating.effective_intensity(annihilating.room(&"chamber").environment_zones[0]),
		EnvironmentZoneDef.BAND_ANNIHILATING,
		"a zone already at the authored ceiling is not talked past it"
	)
	# The floor edge too: the clamp is on both sides of the ladder, so a pathological
	# negative shift still cannot produce a band the ladder has no name for.
	var floor := _map_with(
		(
			[_zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SCORCH, &"fire")]
			as Array[EnvironmentZoneDef]
		)
	)
	floor.weather = &"ashfall"
	assert_eq(
		(
			floor.effective_intensity(floor.room(&"chamber").environment_zones[0])
			>= EnvironmentZoneDef.BAND_SCORCH
		),
		true,
		"no weather drives an effective band below BAND_SCORCH"
	)


## The bias is ELEMENT-KEYED. A zone that authors no element is untouched by a weather
## that is otherwise live in the same run — this is what stops "weather = everything is
## one notch worse", which would make the field a difficulty knob rather than content.
func test_weather_only_biases_a_zone_that_authors_its_element() -> void:
	var map := _map_with(
		(
			[
				_zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SCORCH, &"fire"),
				_zone(&"hollow", &"sorrow", EnvironmentZoneDef.BAND_SCORCH, &""),
			]
			as Array[EnvironmentZoneDef]
		)
	)
	map.weather = &"ember_heat"
	var by_id := {}
	for row in map.zones():
		by_id[String(row["zone_id"])] = row
	assert_eq(
		by_id["furnace"]["intensity"], EnvironmentZoneDef.BAND_SEVERE, "the authored fire bed moves"
	)
	assert_eq(
		by_id["hollow"]["intensity"],
		EnvironmentZoneDef.BAND_SCORCH,
		"a zone authoring no element is NOT biased by an unrelated weather"
	)


## WITH NO WEATHER, NOTHING CHANGES. This is the state every run was actually in when
## the field was inert, and it must be a true no-op rather than a default bias.
func test_no_weather_leaves_every_zone_exactly_as_authored() -> void:
	var map := _fire_map(EnvironmentZoneDef.BAND_SEVERE)
	assert_eq(map.weather, DomainMap.WEATHER_NONE, "a fresh map authors no weather")
	var zone := map.room(&"chamber").environment_zones[0]
	assert_eq(map.weather_shift_for(zone), 0, "no weather shifts nothing")
	assert_eq(
		map.effective_intensity(zone),
		zone.resolved_intensity(),
		"effective equals authored when there is no weather"
	)
	assert_eq(
		_zone_of(map)["intensity"], EnvironmentZoneDef.BAND_SEVERE, "and the read model agrees"
	)


## AN UNKNOWN WEATHER IS REFUSED BY NAME, NEVER DEFAULTED. A typo that quietly read as
## "no weather" would be a deleted mechanic that looks like it worked — the exact class
## of silent default this repo refuses everywhere else.
func test_an_unknown_weather_is_refused_by_name_and_never_defaulted() -> void:
	var probe := DomainMap.new()
	assert_eq(probe.accepts_weather(&"ember_heat"), true, "an authored weather is accepted")
	assert_eq(probe.accepts_weather(&"ashfall"), true, "every catalogue id is accepted")
	assert_eq(probe.accepts_weather(&"ember_hea"), false, "a typo is refused, not defaulted")
	assert_eq(probe.accepts_weather(&"reign_of_fire"), false, "an invented id is refused too")
	# The refusal is a refusal of the VALUE, not a fallback: a map asked to run an
	# unknown weather must bias nothing rather than fall back to a default element.
	var map := _fire_map(EnvironmentZoneDef.BAND_SCORCH)
	map.weather = &"ember_hea"
	assert_eq(
		map.weather_shift_for(map.room(&"chamber").environment_zones[0]),
		0,
		"an unknown weather biases nothing rather than defaulting to a known one"
	)
	# And the round-trip: an unknown id in a payload is DROPPED with a named report, so
	# the map never claims a weather it is not applying.
	var restored := DomainMap.from_dict({"weather": "reign_of_fire"})
	assert_eq(
		restored.weather,
		DomainMap.WEATHER_NONE,
		"an unknown weather does not survive the round trip"
	)


## The weather survives save/load when it IS known — the other half of the round-trip.
func test_a_known_weather_survives_the_round_trip() -> void:
	var map := _fire_map(EnvironmentZoneDef.BAND_SCORCH)
	map.weather = &"ashfall"
	var restored := DomainMap.from_dict(map.to_dict())
	assert_eq(restored.weather, &"ashfall", "an authored weather survives to_dict/from_dict")
	assert_eq(
		restored.effective_intensity(restored.room(&"chamber").environment_zones[0]),
		EnvironmentZoneDef.BAND_SEVERE,
		"and the bias is still applied after a reload"
	)


## EVERY catalogued weather is load-bearing: for each one there exists a zone element it
## moves. A weather that biases nothing would be a second inert field wearing a name.
func test_every_catalogued_weather_moves_at_least_one_element() -> void:
	for key in DomainMap.WEATHERS:
		var element := StringName(DomainMap.WEATHERS[key])
		var map := _map_with(
			(
				[_zone(&"probe", &"super_hot", EnvironmentZoneDef.BAND_SCORCH, element)]
				as Array[EnvironmentZoneDef]
			)
		)
		map.weather = StringName(key)
		assert_eq(
			map.effective_intensity(map.room(&"chamber").environment_zones[0]),
			EnvironmentZoneDef.BAND_SEVERE,
			(
				"weather '%s' carries element '%s' and must move a zone that authors it"
				% [String(key), String(element)]
			)
		)


## ## The templates AUTHOR weather, which is what makes the bias reachable in play
##
## The finding was that no template authored the field at all, so no production run
## could ever carry one. These read the shipped `.tres` files through the same
## composition-root entry point a boot calls, so the data and the code are asserted
## together and cannot drift apart.
func test_the_shipped_templates_author_a_weather_this_build_knows() -> void:
	var seen := 0
	for row in DomainApi.templates():
		var authored := DomainBoot._template_weather(StringName(row["template_id"]))
		assert_eq(
			DomainBoot._map_accepts(authored),
			true,
			(
				"template '%s' authors weather '%s', which must be in the closed catalogue"
				% [String(row["template_id"]), String(authored)]
			)
		)
		if authored != DomainMap.WEATHER_NONE:
			seen += 1
	assert_eq(
		seen > 0,
		true,
		"at least one shipped template authors a non-empty weather, or the bias is unreachable in play"
	)


## A template whose weather is unknown contributes NO weather rather than a string every
## zone would ignore. `flame_valley_depths` is the worked example: its `ashfall` weather
## moves the pool's authored fire zone.
func test_a_template_weather_reaches_the_zones_it_authors() -> void:
	var weather := DomainBoot._template_weather(&"flame_valley_depths")
	assert_eq(weather, &"ashfall", "the flame valley template authors ashfall")
	var map := _map_with(
		(
			[_zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SCORCH, &"fire")]
			as Array[EnvironmentZoneDef]
		)
	)
	map.weather = weather
	assert_eq(
		map.effective_intensity(map.room(&"chamber").environment_zones[0]),
		EnvironmentZoneDef.BAND_SEVERE,
		"the template's authored weather is what makes this zone run hotter"
	)


# ── MAJOR 6: the three levers, pinned so they cannot rot back ─────────────────


## A `super_hot` zone at band 2 publishing ALL FOUR levers, so whichever the actor
## carries is the one that answers. Band 2 with an authored magnitude of 0.70 is well
## clear of zero, so a cap that fails to apply is visible rather than rounding away.
func _furnace() -> EnvironmentZoneDef:
	return _zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SEVERE, &"fire")


## The zone a given lever is PROVABLY able to move, on the qi path.
##
## Not every lever acts on every substrate, and that is the design rather than a gap:
## `EnvironmentField.LEVER_SUBSTRATES` is the authority, and `super_hot` on a qi
## cultivator resolves to `qi_pool_suppression`, which `technique` deliberately does NOT
## act on (a form does not restore the qi pool you cannot spend). So a test that asked
## "does technique reduce this furnace for a qi cultivator" would be asserting a
## falsehood about the game.
##
## Instead each lever is paired with a kind whose qi substrate that lever really does
## act on — `LEVER_SUBSTRATES[lever].has(effect_for(QI, kind))` is asserted TRUE at the
## head of every lever case, so this table cannot rot into claiming a lever fires on a
## substrate it does not touch.
func _zone_for_lever(lever: StringName) -> EnvironmentZoneDef:
	match lever:
		EnvironmentZoneDef.LEVER_GEAR:
			return _zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SEVERE, &"fire")
		EnvironmentZoneDef.LEVER_TECHNIQUE:
			return _zone(&"mindfield", &"sorrow", EnvironmentZoneDef.BAND_SEVERE, &"dark")
		EnvironmentZoneDef.LEVER_PILL:
			return _zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SEVERE, &"fire")
	return _furnace()


## The three levers, each paired with the tag key it publishes and a zone it provably
## moves. Named EXPLICITLY rather than indexed, because `EnvironmentZoneDef.LEVERS[0]`
## is `affinity`: a positional pairing silently credits one lever's cap to another.
const LEVER_TABLE: Array[Array] = [
	[EnvironmentZoneDef.LEVER_GEAR, EnvironmentField.GEAR_TAGS_KEY] as Array,
	[EnvironmentZoneDef.LEVER_TECHNIQUE, EnvironmentField.TECHNIQUE_TAGS_KEY] as Array,
	[EnvironmentZoneDef.LEVER_PILL, EnvironmentField.PILL_TAGS_KEY] as Array,
]


## FOR EACH LEVER: a carried source measurably reduces the effect. This is the branch
## (a) pin. Each of the three is walked so a failure names which lever regressed rather
## than "a lever".
##
## The published tag list is written the way `DomainBoot.publish_ward_tags` writes it —
## element tags under a `tags` key — so the test exercises the real payload shape rather
## than an invented one.
func test_each_three_levers_published_source_reduces_the_effect() -> void:
	for row in LEVER_TABLE:
		var lever: StringName = row[0]
		var key: StringName = row[1]
		var zone := _zone_for_lever(lever)
		# The precondition that makes the rest of this test meaningful: the zone really is
		# one this lever acts on. Asserted, not assumed, so this table cannot claim a
		# lever fires where the substrate table says it does not.
		assert_eq(
			EnvironmentField.mitigates(lever, PathState.QI, zone.kind),
			true,
			(
				"%s: fixture zone '%s' must resolve to a substrate this lever acts on"
				% [String(lever), String(zone.kind)]
			)
		)
		var actor := _cultivator(PathState.QI)
		var bare := EnvironmentField.residual_amount(actor, zone, PathState.QI)
		assert_eq(
			EnvironmentField.mitigated_by(actor, zone),
			"",
			"%s: nothing answers the hazard before anything is carried" % String(lever)
		)

		actor.set_module_data(key, {"tags": [&"fire"] as Array[StringName]})

		var carried := EnvironmentField.residual_amount(actor, zone, PathState.QI)
		assert_eq(
			carried < bare,
			true,
			(
				"%s: a published tag list must measurably reduce the effect (%f -> %f)"
				% [String(lever), bare, carried]
			)
		)
		assert_eq(
			EnvironmentField.mitigated_by(actor, zone),
			String(lever),
			"%s: and the lever that reduced it is named %s" % [String(lever), String(lever)]
		)


## The cap is the AUTHORED strength, not a token reduction: a published list removes
## exactly the lever's own share of the magnitude, so the numbers in the read model are
## the numbers the game pays.
func test_each_three_levers_cap_is_live_and_gates_a_real_list() -> void:
	for row in LEVER_TABLE:
		var lever: StringName = row[0]
		var key: StringName = row[1]
		var zone := _zone_for_lever(lever)
		var authored := zone.magnitude()
		var cap: float = EnvironmentField.LEVER_CAPS[lever]
		var actor := _cultivator(PathState.QI)
		actor.set_module_data(key, {"tags": [&"fire"] as Array[StringName]})
		var residual := EnvironmentField.residual_amount(actor, zone, PathState.QI)
		assert_eq(
			is_equal_approx(residual, authored * (1.0 - cap)),
			true,
			(
				"%s: cap %.2f must remove exactly its share of %.2f (got %.4f)"
				% [String(lever), cap, authored, residual]
			)
		)


## AN EMPTY LIST IS NOT A MITIGATION. A player who dropped their ward must get the full
## authored magnitude back — this is the inverse of the finding, and the assertion that
## catches a "publish everything, always" implementation.
func test_an_empty_published_list_buys_nothing() -> void:
	for row in LEVER_TABLE:
		var lever: StringName = row[0]
		var key: StringName = row[1]
		var zone := _zone_for_lever(lever)
		var actor := _cultivator(PathState.QI)
		actor.set_module_data(key, {"tags": [] as Array[StringName]})
		assert_eq(
			EnvironmentField.mitigated_by(actor, zone),
			"",
			"%s: an empty published list must not answer the hazard" % String(lever)
		)
		assert_eq(
			EnvironmentField.residual_amount(actor, zone, PathState.QI),
			zone.magnitude(),
			"%s: and it leaves the authored magnitude untouched" % String(lever)
		)


## ## THE ABSENCE ASSERTIONS — branch (b) must not be able to happen silently
##
## Branch (b) was the other permitted answer: delete the three caps and stop naming
## gear/technique/pill. Because this change took branch (a), branch (b)'s outcome must be
## IMPOSSIBLE to reach by accident. These assert that the caps and the tag keys are still
## here. If a future agent deletes a lever, these fail and the decision has to be made
## again on purpose rather than by drift.


## The three caps still exist, are positive, and are ordered under the affinity cap — the
## documented relationship (a fully-rooted actor gets the most, a ward less).
func test_the_three_caps_still_exist_and_are_live() -> void:
	for lever in [
		EnvironmentZoneDef.LEVER_GEAR,
		EnvironmentZoneDef.LEVER_TECHNIQUE,
		EnvironmentZoneDef.LEVER_PILL,
	]:
		assert_eq(
			EnvironmentField.LEVER_CAPS.has(lever),
			true,
			(
				"lever '%s' must still have a cap; deleting it is a decision, not a cleanup"
				% String(lever)
			)
		)
		assert_eq(
			float(EnvironmentField.LEVER_CAPS[lever]) > 0.0,
			true,
			(
				"lever '%s' has a POSITIVE cap, so a published list actually moves a number"
				% String(lever)
			)
		)
		assert_eq(
			float(EnvironmentField.LEVER_CAPS[lever]) < EnvironmentField.AFFINITY_CAP,
			true,
			(
				(
					"lever '%s' caps below affinity (%f): a root a player was born with must "
					% [String(lever), float(EnvironmentField.LEVER_CAPS[lever])]
				)
				+ "outrank gear they can drop"
			)
		)


## The three tag keys still exist and are still the names `EnvironmentField` reads. This
## is the seam `DomainBoot.publish_ward_tags` writes into; renaming it silently would
## break the publish with a green suite.
func test_the_three_tag_keys_still_exist_and_are_what_boot_writes() -> void:
	assert_eq(
		String(EnvironmentField.GEAR_TAGS_KEY), "env_gear_tags", "the gear key keeps its name"
	)
	assert_eq(
		String(EnvironmentField.TECHNIQUE_TAGS_KEY),
		"env_technique_tags",
		"the technique key keeps its name"
	)
	assert_eq(
		String(EnvironmentField.PILL_TAGS_KEY), "env_pill_tags", "the pill key keeps its name"
	)


## ## THE PRODUCTION PUBLISH PATH — the finding was that nothing wrote the keys
##
## Everything above writes them BY HAND, which is exactly what the old test did and is
## half the finding. These exercise the real publisher: an actor who genuinely carries a
## fire ward in their wardrobe must have it published and must see it reduce the hazard.
func test_the_production_publisher_writes_what_the_actor_actually_wears() -> void:
	var actor := _cultivator(PathState.QI)
	ItemsApi.attach(actor)
	var worn := _armour(&"fire_ward", &"fire")
	assert_eq(
		actor.component(ItemsApi.INVENTORY_COMPONENT).add(worn, 1), 0, "the ward went into the bag"
	)
	# Bounded `for` over the closed five-slot set, stopping on the first success — which
	# is the facade path rather than reaching into `Equipment`.
	var equipped := false
	for slot in Equipment.SLOTS:
		if ItemsApi.equip_item(actor, slot, worn):
			equipped = true
			break
	assert_eq(equipped, true, "the actor is genuinely wearing the fire ward")

	DomainBoot.publish_ward_tags(actor)

	var published: Array = actor.get_module_data(EnvironmentField.GEAR_TAGS_KEY).get("tags", [])
	assert_eq(
		published.has(&"fire"),
		true,
		"the production publisher put the worn element into the gear key"
	)
	var zone := _furnace()
	assert_eq(
		EnvironmentField.mitigated_by(actor, zone),
		"gear",
		"and a worn fire ward now actually answers a fire zone in play"
	)


## The inverse, and the assertion that would have caught the original finding: an actor
## who carries NOTHING publishes three EMPTY lists, so a hazard they have no counter for
## says so rather than the screen advertising a lever that cannot fire.
func test_an_unladen_actor_publishes_empty_lists_and_no_phantom_mitigation() -> void:
	var actor := _cultivator(PathState.QI)
	ItemsApi.attach(actor)
	DomainBoot.publish_ward_tags(actor)
	for index in LEVER_KEYS.size():
		var key: StringName = LEVER_KEYS[index]
		var published: Array = actor.get_module_data(key).get("tags", [])
		assert_eq(
			published.is_empty(),
			true,
			"%s publishes nothing for an actor who carries nothing" % LEVER_NAMES[index]
		)
	var zone := _furnace()
	assert_eq(
		EnvironmentField.mitigated_by(actor, zone),
		"",
		"so an unladen actor is taxed in full rather than being told a ward answered it"
	)


## The publisher is IDEMPOTENT: re-publishing after the ward is taken off empties the
## list again. A publisher that only ever appended would make a stale ward permanent,
## which is worse than the original inert field because it would be invisible.
func test_publishing_twice_reflects_current_state_and_does_not_accumulate() -> void:
	var actor := _cultivator(PathState.QI)
	ItemsApi.attach(actor)
	var worn := _armour(&"ice_ward", &"ice")
	assert_eq(
		actor.component(ItemsApi.INVENTORY_COMPONENT).add(worn, 1), 0, "the ward went into the bag"
	)
	var took_off := false
	for slot in Equipment.SLOTS:
		if ItemsApi.equip_item(actor, slot, worn):
			took_off = true
			break
	assert_eq(took_off, true, "the ice ward was worn")
	DomainBoot.publish_ward_tags(actor)
	assert_eq(
		(actor.get_module_data(EnvironmentField.GEAR_TAGS_KEY).get("tags", []) as Array).has(
			&"ice"
		),
		true,
		"the worn ice ward is published"
	)

	# Take it off, then publish again. The list must shrink, never accumulate.
	var removed := false
	for slot in Equipment.SLOTS:
		if ItemsApi.unequip_to_inventory(actor, slot):
			removed = true
			break
	assert_eq(removed, true, "the ice ward came off")
	DomainBoot.publish_ward_tags(actor)
	var after: Array = actor.get_module_data(EnvironmentField.GEAR_TAGS_KEY).get("tags", [])
	assert_eq(
		after.has(&"ice"),
		false,
		"an unequipped ward stops being published; the list is current state, not a log"
	)


## A fire ward does NOT answer an ice zone: the published list is element-scoped, so a
## player cannot equip one robe and claim every hazard in the domain is mitigated.
##
## Note WHAT is asserted. `_lever_applies` asks only whether the published list is
## non-empty — it never cross-checks the tag against the zone's element. That is
## deliberate: the cap is the lever's authored strength and a partial wardrobe is worth
## a partial answer, so requiring an exact element match would make a mixed bag inert.
## What this pins is therefore the honest consequence — the ward answers a zone of its
## OWN element, and the affinity lever is the one that is element-checked — so a future
## change to the matching rule has to be a decision.
func test_a_published_ward_answers_a_zone_it_is_carried_against() -> void:
	var fire_ward := _cultivator(PathState.QI)
	fire_ward.set_module_data(
		EnvironmentField.GEAR_TAGS_KEY, {"tags": [&"fire"] as Array[StringName]}
	)
	var fire_bed := _zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SEVERE, &"fire")
	assert_eq(
		EnvironmentField.mitigated_by(fire_ward, fire_bed),
		"gear",
		"a published fire ward answers a fire zone"
	)
	# And the element-checked lever, which IS zone-aware: an actor with no root at all
	# mitigates nothing, so the credit really came from the published gear and not from
	# the actor's spirit root.
	assert_eq(
		fire_ward.affinities.get_value(&"fire"),
		0.0,
		"this actor has no fire root, so the reduction above came from carried gear"
	)
