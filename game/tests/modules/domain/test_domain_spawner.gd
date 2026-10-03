extends TestCase

## ADR 0074: a domain's inhabitants are `Actor`s. Every role — mob, miniboss, boss, npc,
## rival cultivator — comes out of one constructor, and the role is a TAG.
##
## These are the acceptance criteria for that claim, asserted hard:
##   AC2 — `spawn` returns an `Actor` for every role in the closed set, and no parallel
##         NPC/Mob/Boss actor class exists anywhere in the domain module.
##   AC3 — a map with N spawn refs yields N live Actors (respecting `count`), and a
##         handcrafted and a generated map with the same refs resolve to the same actors.
##   plus: a rival cultivator is a real cultivator, a missing inhabitant is refused loudly,
##   and every spawned Actor round-trips through `to_dict`/`from_dict` with its role intact.
##
## Maps are built INLINE, exactly as `test_domain_map_contract.gd` does. Nothing here depends
## on `DomainGenerator`: the parity claim is between two maps, not between a class and its
## absence.

# ── fixtures ─────────────────────────────────────────────────────────────────

## The seven roles a handcrafted map mints, in canonical ref order.
const SEVEN_ROLES: Array[String] = [
	"mob",
	"mob",
	"npc",
	"miniboss",
	"miniboss",
	"miniboss",
	"boss",
]


## The spine `app/` installs for a domain spawn, stood up by hand so the claim under test is
## the domain's and not the factory's. `app/actor_factory.gd` is where this is really wired;
## the domain module cannot reach it itself (see `DomainSpawner.set_minter`).
func _core_minter(def_id: StringName, base: Dictionary) -> Actor:
	var actor := Actor.new(def_id, base)
	actor.attach_core_resources()
	DomainSpawner.attach_high_tier(actor)
	return actor


func setup() -> void:
	DomainSpawner.set_minter(Callable(self, "_core_minter"))


func _def(
	inhabitant_id: StringName,
	display_name: String,
	realm_id: StringName = &"",
	physique: float = 10.0,
	cultivates: bool = false,
	hostile: bool = false,
	tags: Array[StringName] = []
) -> InhabitantDef:
	var def := InhabitantDef.new()
	def.inhabitant_id = inhabitant_id
	def.display_name = display_name
	def.realm_id = realm_id
	def.base = {Stat.PHYSIQUE: physique} as Dictionary
	def.cultivates = cultivates
	def.hostile = hostile
	def.tags = tags
	return def


## One inhabitant per role. The mini-boss and the boss differ by AUTHORED MAGNITUDE ONLY:
## same class, same providers, same everything else.
func _catalog() -> Dictionary:
	return {
		&"cinder_hound": _def(&"cinder_hound", "Cinder Hound", &"", 8.0, false, true),
		&"ash_sentinel": _def(&"ash_sentinel", "Ash Sentinel", &"", 18.0, false, true),
		&"ash_warden":
		_def(
			&"ash_warden",
			"Ash Warden",
			&"core_formation",
			24.0,
			true,
			true,
			[&"sentinel"] as Array[StringName]
		),
		&"elder_qi": _def(&"elder_qi", "Elder of the Qi", &"", 9.0, false, false),
		&"rival_qi":
		_def(&"rival_qi", "Rival of the Seven Peaks", &"spirit_transformation", 14.0, true, false),
	}


func _spawn(ref_id: String, inhabitant_id: String, role: String, count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": inhabitant_id, "role": role, "count": count}


func _room(room_id: StringName, kind: StringName, exits: Array[StringName]) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	return room


## A HANDCRAFTED domain: three rooms in a line with an authored core. Four refs whose counts
## are 2 + 1 + 3 + 1, so `count` is load-bearing rather than decorative.
func handcrafted_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(32, 24), 0)
	map.add_room(_room(&"entry_grove", &"floor", [&"ember_flue"] as Array[StringName]))
	var flue := _room(
		&"ember_flue", &"corridor", [&"entry_grove", &"heart_of_ashes"] as Array[StringName]
	)
	flue.actor_spawn_refs = (
		[
			_spawn("g1", "cinder_hound", "mob", 2),
			_spawn("g2", "elder_qi", "npc", 1),
		]
		as Array[Dictionary]
	)
	map.add_room(flue)
	var core := _room(&"heart_of_ashes", &"core", [&"ember_flue"] as Array[StringName])
	core.actor_spawn_refs = (
		[
			_spawn("b1", "ash_sentinel", "miniboss", 3),
			_spawn("b2", "ash_warden", "boss", 1),
		]
		as Array[Dictionary]
	)
	map.add_room(core)
	map.entry_room = &"entry_grove"
	return map


## A GENERATED-shaped domain at a given seed, assembled from the same authored room kit and
## carrying the SAME four refs, so a spawner that could tell the producers apart would resolve
## the two maps differently. `DomainMap` has no provenance field, so it cannot.
func generated_map(seed_value: int) -> DomainMap:
	var map := DomainMap.new(Vector2i(48, 32), seed_value)
	map.add_room(_room(&"entry", &"floor", [&"hall"] as Array[StringName]))
	var hall := _room(&"hall", &"chamber", [&"entry", &"vault"] as Array[StringName])
	hall.actor_spawn_refs = (
		[
			_spawn("g1", "cinder_hound", "mob", 2),
			_spawn("g2", "elder_qi", "npc", 1),
		]
		as Array[Dictionary]
	)
	map.add_room(hall)
	var vault := _room(&"vault", &"core", [&"hall"] as Array[StringName])
	vault.actor_spawn_refs = (
		[
			_spawn("b1", "ash_sentinel", "miniboss", 3),
			_spawn("b2", "ash_warden", "boss", 1),
		]
		as Array[Dictionary]
	)
	map.add_room(vault)
	map.entry_room = &"entry"
	return map


## A deterministic tile lookup, standing in for the scene's placement.
func _position_of(_room_id: StringName, ref_id: String, index: int) -> Vector2:
	return Vector2(float(index) * 16.0, float(ref_id.length()))


# ── AC2: one constructor, every role ─────────────────────────────────────────


## The headline acceptance criterion, as ONE loop over the closed set: every role yields an
## `Actor`. Five roles, five assertions, and the loop reads `DomainRoles.ROLES` rather than a
## copied list, so a sixth role cannot be added without being covered here.
func test_every_role_spawns_an_actor() -> void:
	var catalog := _catalog()
	for role in DomainRoles.ROLES:
		var actor := DomainSpawner.spawn(catalog[_inhabitant_for(role)], role)
		assert_eq(actor is Actor, true, "role '%s' spawns an Actor" % String(role))
		assert_ne(actor, null, "role '%s' is not a silent null" % String(role))


## And not merely "an Actor" — the EXACT type. Every role's script is `Actor`'s own script,
## which is the whole claim: there is no second type, and so there is nothing to downcast.
func test_every_role_is_exactly_an_actor() -> void:
	var catalog := _catalog()
	var actor_script: Variant = Actor.new(&"probe").get_script()
	for role in DomainRoles.ROLES:
		var actor := DomainSpawner.spawn(catalog[_inhabitant_for(role)], role)
		assert_eq(actor.get_script(), actor_script, "role '%s' is Actor exactly" % String(role))


## The structural half of AC2, read off the module's own source. A `MobActor extends Actor` in
## this directory would satisfy every assertion above while defeating the claim, so the tree is
## searched for a class that extends `Actor` and for a `class_name` naming a role as a type.
func test_domain_module_declares_no_actor_subclass() -> void:
	var offenders := _actor_classes_under("res://src/modules/domain")
	assert_eq(
		offenders.is_empty(),
		true,
		"no Mob/Npc/Boss actor class exists in the domain module: %s" % ", ".join(offenders)
	)


## An unknown role is refused, loudly, rather than defaulted to `npc`. A typo that quietly
## spawned a shopkeeper instead of a boss is exactly what ADR 0074 exists to stop.
func test_unknown_role_is_refused() -> void:
	assert_eq(DomainSpawner.spawn(_catalog()[&"ash_warden"], &"dragon"), null, "no such role")


func test_empty_role_is_refused() -> void:
	assert_eq(DomainSpawner.spawn(_catalog()[&"ash_warden"], &""), null, "no role at all")


func test_null_def_is_refused() -> void:
	assert_eq(DomainSpawner.spawn(null, DomainRoles.BOSS), null, "no def, no spawn")


# ── roles are tags, and tags are data ────────────────────────────────────────


func test_role_is_stamped_on_the_actor_as_a_tag() -> void:
	var actor := DomainSpawner.spawn(_catalog()[&"ash_warden"], DomainRoles.BOSS)
	assert_eq(actor.tags.has(&"boss"), true, "the role is on Actor.tags itself")
	assert_eq(DomainSpawner.has_role(actor, DomainRoles.BOSS), true, "readable as the role")
	assert_eq(DomainSpawner.role_of(actor), &"boss", "and as the role it is")


## The role rides `tags`, which `Actor.to_dict()` already serialises. No bespoke save field.
func test_role_travels_on_tags_not_a_private_slot() -> void:
	var payload: Dictionary = (
		DomainSpawner.spawn(_catalog()[&"ash_warden"], DomainRoles.BOSS).to_dict()
	)
	assert_eq((payload.get("tags", []) as Array).has("boss"), true, "in the ordinary tags array")


## A mini-boss is a bigger number and a tag. Same def shape, same providers, same class.
func test_miniboss_is_magnitude_and_a_tag_only() -> void:
	var catalog := _catalog()
	var miniboss := DomainSpawner.spawn(catalog[&"ash_sentinel"], DomainRoles.MINIBOSS)
	var boss := DomainSpawner.spawn(catalog[&"ash_warden"], DomainRoles.BOSS)
	assert_eq(miniboss.stats.get_base(Stat.PHYSIQUE), 18.0, "the mini-boss authors its own build")
	assert_eq(boss.stats.get_base(Stat.PHYSIQUE), 24.0, "and the boss a larger one")
	assert_eq(miniboss.get_script(), boss.get_script(), "the same class")
	assert_eq(DomainSpawner.has_role(miniboss, DomainRoles.MINIBOSS), true, "its own tag")
	assert_eq(
		miniboss.stats.provider_count(),
		boss.stats.provider_count(),
		"and the identical provider count: a role changed no mechanism"
	)


# ── hostility is content, read from tags ──────────────────────────────────────


## A rival cultivator is NEUTRAL by tag; a boss is HOSTILE by tag. Neither fact is a type, and
## neither is something a mechanism learns by branching on the role.
func test_rival_is_not_hostile_and_boss_is() -> void:
	var catalog := _catalog()
	var rival := DomainSpawner.spawn(catalog[&"rival_qi"], DomainRoles.RIVAL_CULTIVATOR)
	var boss := DomainSpawner.spawn(catalog[&"ash_warden"], DomainRoles.BOSS)
	assert_eq(rival.tags.has(DomainSpawner.HOSTILE_TAG), false, "a rival is not hostile")
	assert_eq(DomainSpawner.is_hostile(rival), false, "and does not read as hostile")
	assert_eq(boss.tags.has(DomainSpawner.HOSTILE_TAG), true, "a boss is hostile")
	assert_eq(DomainSpawner.is_hostile(boss), true, "and does read as hostile")


## A role that cannot be hostile is never hostile, however the def is authored. The band is a
## permission, the def is the opt-in, and both must agree.
func test_a_role_that_cannot_be_hostile_never_is() -> void:
	var peaceful := _def(&"peaceful", "Peaceful", &"", 10.0, false, true)
	var actor := DomainSpawner.spawn(peaceful, DomainRoles.RIVAL_CULTIVATOR)
	assert_eq(DomainSpawner.is_hostile(actor), false, "an authored-hostile npc is still not")


## Authored tags ride along beside the role, exactly as an author wrote them.
func test_authored_tags_reach_the_actor() -> void:
	var actor := DomainSpawner.spawn(_catalog()[&"ash_warden"], DomainRoles.BOSS)
	assert_eq(actor.tags.has(&"sentinel"), true, "the def's own tag is on the actor")


# ── a rival cultivator is a CULTIVATOR ───────────────────────────────────────


func test_rival_cultivator_carries_a_real_path_at_its_realm() -> void:
	var rival := DomainSpawner.spawn(_catalog()[&"rival_qi"], DomainRoles.RIVAL_CULTIVATOR)
	var path := rival.path(PathState.QI)
	assert_ne(path, null, "a rival cultivator is enrolled on the qi path")
	assert_eq(path.rank_id, &"spirit_transformation", "at the realm its def authored")
	assert_eq(rival.realm(), &"spirit_transformation", "and reports it as its realm")
	assert_eq(RealmDefaults.ladder().index_of(rival.realm()) >= 0, true, "a real ladder realm id")


## A boss is a cultivator too, for the same reason and with the same machinery. A boss that
## could not cultivate would be a mob with a bigger number and a title.
func test_boss_is_enrolled_like_the_player_is() -> void:
	var boss := DomainSpawner.spawn(_catalog()[&"ash_warden"], DomainRoles.BOSS)
	assert_eq(boss.path(PathState.QI) != null, true, "the boss has a path state")
	assert_eq(boss.realm(), &"core_formation", "at its authored realm")


## A mob is not a cultivator merely by standing in a room. `cultivates` is the def's field; the
## role only says what it permits.
func test_a_mob_carries_no_cultivation_path() -> void:
	var mob := DomainSpawner.spawn(_catalog()[&"cinder_hound"], DomainRoles.MOB)
	assert_eq(mob.path(PathState.QI), null, "a mob has no path")
	assert_eq(mob.realm(), &"", "and no realm")


## A def that claims to cultivate while authoring no realm cannot be built: a rival cultivator
## with no realm is a mob with a name, so the spawn is refused rather than half-finished.
func test_a_cultivator_with_no_realm_is_refused() -> void:
	var nameless := _def(&"nameless_rival", "Nameless Rival", &"", 12.0, true, false)
	assert_eq(DomainSpawner.spawn(nameless, DomainRoles.RIVAL_CULTIVATOR), null, "refused")


## The realm the def authors is real MAGNITUDE, applied the way the player has it applied:
## read off the rank through the PathState by core's own `RealmScaling`, keyed by realm id.
func test_an_authored_realm_scales_the_inhabitant_the_way_it_scales_the_player() -> void:
	var catalog := _catalog()
	var mob := DomainSpawner.spawn(catalog[&"cinder_hound"], DomainRoles.MOB)
	var boss := DomainSpawner.spawn(catalog[&"ash_warden"], DomainRoles.BOSS)
	# 50 + physique * 10, unscaled, because the mob authors no realm to scale by.
	assert_almost_eq(
		mob.stats.derived(Stat.MAX_HEALTH), 130.0, "a mob is exactly its authored base"
	)
	# The same formula scaled by its authored realm, which is strictly above 1.0.
	assert_eq(
		boss.stats.derived(Stat.MAX_HEALTH) > 290.0,
		true,
		"a boss at core_formation carries that realm's magnitude"
	)


## A rival answers the same derived stats the player does, because it was enrolled rather than
## dressed up.
func test_a_rival_reports_the_same_derived_shape_as_the_player() -> void:
	var rival := DomainSpawner.spawn(_catalog()[&"rival_qi"], DomainRoles.RIVAL_CULTIVATOR)
	var player := _core_minter(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0} as Dictionary
	)
	player.set_path(PathState.new(PathState.QI, &"spirit_transformation"))
	for stat_id in [Stat.MAX_HEALTH, Stat.MAX_QI, Stat.ATTACK_PHYSICAL, Stat.DEFENSE_PHYSICAL]:
		assert_eq(
			rival.stats.derived_all().has(stat_id),
			player.stats.derived_all().has(stat_id),
			"a rival answers '%s' the player does" % String(stat_id)
		)


# ── AC3: a map's refs become live actors ─────────────────────────────────────


## N refs honouring `count` yield exactly N actors, in canonical ref order, every one an
## `Actor`.
func test_a_map_with_n_refs_yields_n_actors_respecting_count() -> void:
	var spawned := DomainSpawner.spawn_map(
		handcrafted_map(), _catalog(), Callable(self, "_position_of")
	)
	assert_eq(spawned.size(), 7, "four refs counting 2 + 1 + 3 + 1")
	for actor in spawned:
		assert_eq(actor is Actor, true, "every minted actor is an Actor")
	assert_eq(_roles_of(spawned), SEVEN_ROLES, "canonical ref order, each role count times")


## The parity claim itself. A handcrafted and a generated map carrying the same refs resolve to
## the same actors, in the same order, with the same roles — so the spawner cannot be telling
## the producers apart.
func test_handcrafted_and_generated_maps_resolve_to_the_same_actors() -> void:
	var catalog := _catalog()
	var handcrafted := DomainSpawner.spawn_map(
		handcrafted_map(), catalog, Callable(self, "_position_of")
	)
	var generated := DomainSpawner.spawn_map(
		generated_map(7), catalog, Callable(self, "_position_of")
	)
	assert_eq(
		handcrafted_map().spawn_refs().size(),
		generated_map(7).spawn_refs().size(),
		"both maps carry the same number of refs"
	)
	assert_eq(generated.size(), handcrafted.size(), "so they mint the same number of Actors")
	assert_eq(_roles_of(generated), _roles_of(handcrafted), "and the same roles, in order")
	assert_eq(_roles_of(generated), SEVEN_ROLES, "which is the canonical walk of the four refs")


## Determinism, as far as the spawner is concerned: the same map mints the same actors in the
## same order with the same roles every time.
func test_the_same_map_spawns_the_same_actors_twice() -> void:
	var catalog := _catalog()
	var first := DomainSpawner.spawn_map(
		generated_map(1234), catalog, Callable(self, "_position_of")
	)
	var second := DomainSpawner.spawn_map(
		generated_map(1234), catalog, Callable(self, "_position_of")
	)
	assert_eq(first.size(), second.size(), "the same count")
	assert_eq(_roles_of(first), _roles_of(second), "the same roles in the same order")


## Placement is recorded per instance and rides the ordinary actor payload, so a save carries
## it with no bespoke spawner field.
func test_placement_is_recorded_on_the_actor() -> void:
	var spawned := DomainSpawner.spawn_map(
		generated_map(7), _catalog(), Callable(self, "_position_of")
	)
	var restored := Actor.from_dict(spawned[0].to_dict())
	assert_eq(DomainSpawner.room_of(restored), &"hall", "the room survives a save/load")
	assert_eq(
		DomainSpawner.placement(restored),
		_position_of(&"hall", "g1", 0),
		"and so does the position"
	)


## An unknown role on a ref is refused: that ref mints nothing, and the refs around it still
## do. A silently demoted boss would be worse than an empty room.
func test_a_ref_with_an_unknown_role_mints_nothing() -> void:
	var map := generated_map(7)
	map.room(&"vault").actor_spawn_refs[1]["role"] = "dragon"
	var spawned := DomainSpawner.spawn_map(map, _catalog(), Callable(self, "_position_of"))
	assert_eq(spawned.size(), 6, "two hounds, one elder, three mini-bosses; the boss refused")
	var roles := _roles_of(spawned)
	assert_eq(roles.has("boss"), false, "the boss was refused, not defaulted")
	assert_eq(roles.has("mob"), true, "and the other refs in the same map still spawned")


# ── a missing inhabitant is refused loudly ────────────────────────────────────


## A ref naming an inhabitant the catalog does not ship is reported by room, ref and id, and
## mints NOTHING. A placeholder Actor would look like content and answer for none; the count
## below is what makes a silent default impossible to smuggle through as "one fewer".
func test_a_ref_naming_a_missing_inhabitant_is_refused_loudly() -> void:
	var map := _one_ref_map("x1", "not_a_real_inhabitant", "mob", 3)
	assert_eq(
		DomainSpawner.spawn_map(map, _catalog(), Callable(self, "_position_of")).size(),
		0,
		"no placeholder, no stub, nothing"
	)


## The refusal is LOCAL. One broken ref does not silence the map around it.
func test_a_missing_inhabitant_does_not_silence_the_rest_of_the_map() -> void:
	var map := handcrafted_map()
	map.room(&"ember_flue").actor_spawn_refs = (
		[
			_spawn("g1", "cinder_hound", "mob", 2),
			_spawn("g2", "who_is_this", "npc", 1),
		]
		as Array[Dictionary]
	)
	var spawned := DomainSpawner.spawn_map(map, _catalog(), Callable(self, "_position_of"))
	assert_eq(spawned.size(), 6, "two hounds, three mini-bosses and one boss")


## A catalog may be keyed by `String` or by `StringName`; both resolve. A ref carries a string
## and a loader hands back string keys, so a `StringName`-only lookup would report a perfectly
## good inhabitant as missing.
func test_a_catalog_keyed_by_string_resolves() -> void:
	var by_string := {"cinder_hound": _def(&"cinder_hound", "Cinder Hound", &"", 8.0, false, true)}
	var map := _one_ref_map("x1", "cinder_hound", "mob", 1)
	assert_eq(
		DomainSpawner.spawn_map(map, by_string, Callable(self, "_position_of")).size(),
		1,
		"a String-keyed catalog resolves a ref's StringName"
	)


## A null map or a missing placement callable is refused outright, not silently turned into an
## empty room.
func test_null_map_and_null_placement_are_refused() -> void:
	assert_eq(DomainSpawner.spawn_map(null, _catalog(), Callable()).size(), 0, "no map")
	assert_eq(
		DomainSpawner.spawn_map(generated_map(7), _catalog(), Callable()).size(),
		0,
		"no placement callable, no spawn"
	)


## An authored `count` nobody wrote by hand is bounded and refused by name, so one bad ref
## cannot mint a population that fills the disk.
func test_an_absurd_count_is_refused() -> void:
	var map := generated_map(7)
	map.room(&"hall").actor_spawn_refs[0]["count"] = DomainSpawner.MAX_COUNT_PER_REF + 1
	var spawned := DomainSpawner.spawn_map(map, _catalog(), Callable(self, "_position_of"))
	assert_eq(spawned.size(), 5, "the bad ref mints nothing; the other three still do")


func test_a_zero_count_ref_mints_nothing() -> void:
	var map := generated_map(7)
	map.room(&"vault").actor_spawn_refs[0]["count"] = 0
	var spawned := DomainSpawner.spawn_map(map, _catalog(), Callable(self, "_position_of"))
	assert_eq(spawned.size(), 4, "two hounds, one elder, one boss")


# ── persistence is the ordinary actor path ───────────────────────────────────


## Every spawned Actor round-trips through `to_dict()`/`from_dict()` — the SAME path every
## other actor uses, with no bespoke spawner save field — and keeps its role.
func test_every_spawned_actor_round_trips_and_keeps_its_role() -> void:
	var spawned := DomainSpawner.spawn_map(
		handcrafted_map(), _catalog(), Callable(self, "_position_of")
	)
	assert_eq(spawned.size(), 7, "the map's seven inhabitants")
	for actor in spawned:
		var role := DomainSpawner.role_of(actor)
		var restored := Actor.from_dict(actor.to_dict())
		assert_eq(restored is Actor, true, "a '%s' restores as an Actor" % String(role))
		assert_eq(DomainSpawner.role_of(restored), role, "role '%s' survives" % String(role))
		assert_eq(DomainSpawner.has_role(restored, role), true, "and is still a tag")


## A rival cultivator restores ON its path, at its realm — so a saved rival is still a rival
## cultivator rather than a mob that came back with a name.
func test_a_saved_rival_is_still_a_cultivator() -> void:
	var rival := DomainSpawner.spawn(_catalog()[&"rival_qi"], DomainRoles.RIVAL_CULTIVATOR)
	var restored := Actor.from_dict(rival.to_dict())
	assert_eq(restored.path(PathState.QI) != null, true, "the path is restored")
	assert_eq(restored.realm(), &"spirit_transformation", "at the same realm")
	assert_eq(DomainSpawner.has_role(restored, DomainRoles.RIVAL_CULTIVATOR), true, "still a rival")


## The whole payload is JSON-clean. A leaked `StringName` or `Vector2` would break every save
## without breaking a single assertion above.
func test_the_spawned_payload_is_json_clean() -> void:
	var spawned := DomainSpawner.spawn_map(
		generated_map(7), _catalog(), Callable(self, "_position_of")
	)
	var parsed: Variant = JSON.parse_string(JSON.stringify(spawned[0].to_dict()))
	assert_eq(parsed is Dictionary, true, "an inhabitant's payload survives JSON")


# ── InhabitantDef ────────────────────────────────────────────────────────────


func test_a_def_round_trips() -> void:
	var original := _def(
		&"rival_qi",
		"Rival of the Seven Peaks",
		&"spirit_transformation",
		14.0,
		true,
		false,
		[&"duelist", &"sword"] as Array[StringName]
	)
	var restored := InhabitantDef.from_dict(original.to_dict())
	assert_eq(String(restored.inhabitant_id), "rival_qi", "the id survives")
	assert_eq(restored.realm_id, &"spirit_transformation", "the realm survives as a StringName")
	assert_eq(restored.base.get(Stat.PHYSIQUE), 14.0, "the authored base survives")
	assert_eq(restored.cultivates, true, "the cultivates flag survives")
	assert_eq(restored.hostile, false, "the hostile flag survives")
	assert_eq(restored.tags.size(), 2, "and the authored tags survive")


func test_a_def_survives_json() -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(_catalog()[&"ash_warden"].to_dict()))
	assert_eq(parsed is Dictionary, true, "a def is JSON-clean")
	assert_eq(String(InhabitantDef.from_dict(parsed).inhabitant_id), "ash_warden", "and reloads")


## A def carries a realm for exactly one reason: so a rival is a rival CULTIVATOR. Nothing in
## the spawner invents one.
func test_the_realm_is_authored_never_invented() -> void:
	var nameless := _def(&"nameless_rival", "Nameless Rival")
	assert_eq(nameless.realm_id, &"", "an un-authored realm is empty")
	assert_eq(DomainSpawner.spawn(nameless, DomainRoles.NPC) != null, true, "and an npc needs none")


# ── helpers ──────────────────────────────────────────────────────────────────


func _one_ref_map(ref_id: String, inhabitant_id: String, role: String, count: int) -> DomainMap:
	var map := DomainMap.new(Vector2i(16, 16), 0)
	var only := _room(&"only", &"chamber", [] as Array[StringName])
	only.actor_spawn_refs = [_spawn(ref_id, inhabitant_id, role, count)] as Array[Dictionary]
	map.add_room(only)
	map.entry_room = &"only"
	return map


## One catalog inhabitant per role, chosen by the ROLE's own semantics rather than by a table
## that could fall out of step with `DomainRoles.ROLES`.
func _inhabitant_for(role: StringName) -> StringName:
	if role == DomainRoles.MOB:
		return &"cinder_hound"
	if role == DomainRoles.MINIBOSS:
		return &"ash_sentinel"
	if role == DomainRoles.BOSS:
		return &"ash_warden"
	if role == DomainRoles.NPC:
		return &"elder_qi"
	return &"rival_qi"


func _roles_of(actors: Array[Actor]) -> Array[String]:
	var out: Array[String] = []
	for actor in actors:
		out.append(String(DomainSpawner.role_of(actor)))
	return out


## Every `.gd` under `root` that extends `Actor`, or whose `class_name` names a role as a type.
## The structural half of AC2: an assertion that a spawn returns an `Actor` cannot see a
## parallel subclass, so the tree itself is read.
func _actor_classes_under(root: String) -> Array[String]:
	var offenders: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with("."):
				var full := dir_path.path_join(entry)
				if dir.current_is_dir():
					pending.append(full)
				elif entry.ends_with(".gd"):
					offenders.append_array(_actor_offenders_in(full))
			entry = dir.get_next()
		dir.list_dir_end()
	return offenders


func _actor_offenders_in(path: String) -> Array[String]:
	var out: Array[String] = []
	# Read the TEXT, never the loaded script: `load()` would drag in every other class this file
	# references and turn a sibling agent's half-written module into a parse error inside this
	# test. What is under test is a DECLARATION, and a declaration is visible in the source.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var source := file.get_as_text()
	file.close()
	var lines := source.split("\n")
	for index in lines.size():
		var stripped := String(lines[index]).strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("extends ") and stripped.substr(7).strip_edges() == "Actor":
			out.append("%s:%d extends Actor" % [path, index + 1])
		elif stripped.begins_with("class_name ") and _names_a_role(stripped):
			out.append("%s:%d %s" % [path, index + 1, stripped])
	return out


## Whether a `class_name` line ends in a role, which is what a parallel `Mob`/`Npc`/`Boss`
## actor class would look like.
func _names_a_role(line: String) -> bool:
	for role in ["Mob", "MiniBoss", "Miniboss", "Npc", "Boss"]:
		if line.contains(role):
			return true
	return false
