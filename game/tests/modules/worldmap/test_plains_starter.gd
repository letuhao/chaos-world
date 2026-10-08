extends TestCase

## THE STARTER ZONE: the Mortal Plains node generates everything DEF-0064
## names — beasts to meet, herbs and ore to harvest, a shelter with the elder
## at its doorstep, a gate whose mouth is the arena threshold — and the arena
## descends into a real run plus a real paying band. Built straight off the
## demo graph and configs, so the proof and the played game describe one place.

const PLAINS_SEED := 20261007

## Walk cap for the route helper below: sealed ground answers as no route,
## and the cap keeps a mistyped door from becoming a whole-map sweep.
const WALK_CAP := 512

var _scene: WorldmapScene = null
var _hero: Actor = null
var _born: Array = []
var _entered: Array = []


func setup() -> void:
	WorldmapApi.clear_domain()
	WorldmapApi.clear_loot()
	WorldmapApi.clear_returns()
	_scene = null
	_hero = null
	_entered.clear()


func teardown() -> void:
	WorldmapApi.clear_domain()
	WorldmapApi.clear_loot()
	WorldmapApi.clear_returns()
	if _scene != null and is_instance_valid(_scene):
		if _scene.get_parent() != null:
			_scene.get_parent().remove_child(_scene)
		_scene.free()
	_scene = null
	for actor in _born:
		(actor as Actor).resources.clear()
	_born.clear()


func _actor() -> Actor:
	var body := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	body.attach_core_resources()
	ItemsApi.attach(body, 24)
	LootApi.attach(body)
	_born.append(body)
	return body


func _entry(template_id: String, seed: int) -> Dictionary:
	_entered.append(template_id)
	if _hero == null:
		return {"ok": false, "reason": "no_actor"}
	return DomainApi.generate_and_enter(_hero, StringName(template_id), seed)


func _exit() -> Dictionary:
	if _hero == null:
		return {"ok": false, "reason": "no_actor"}
	return DomainApi.leave(_hero)


func _loot_entry(domain_id: String, tier: int, seed: int) -> Dictionary:
	if _hero == null:
		return {"ok": false, "reason": "no_actor"}
	return LootApi.enter_domain(_hero, StringName(domain_id), tier, seed)


func _loot_exit() -> Dictionary:
	if _hero == null:
		return {"ok": false, "reason": "no_actor"}
	return LootApi.abandon(_hero)


func _install() -> void:
	assert_eq(
		bool(
			WorldmapApi.install_domain(Callable(self, "_entry"), Callable(self, "_exit")).get(
				"ok", false
			)
		),
		true,
		"the domain seam installs"
	)
	assert_eq(
		bool(
			(
				WorldmapApi
				. install_loot(Callable(self, "_loot_entry"), Callable(self, "_loot_exit"))
				. get("ok", false)
			)
		),
		true,
		"the loot seam installs"
	)


func _open(node: String) -> void:
	_scene = WorldmapScene.new()
	var outcome := _scene.open(VentureBoot._demo_graph(), node, VentureBoot._demo_configs())
	assert_eq(bool(outcome.get("ok", false)), true, "the %s opens" % node)


func _chunk() -> WorldChunk:
	return _scene.streamer().chunk_data("plains", 0, 0, 12, PLAINS_SEED)


func _prop_at(archetype: String) -> Dictionary:
	for prop in _chunk().props:
		var row := prop as Dictionary
		if String(row.get("archetype", "")) == archetype:
			return row
	return {}


## A prop whose cells overlap the given anchor cell + footprint, excluding
## the anchors themselves by archetype. What the scatter-family avoidance
## must never leave standing.
func _overlaps(chunk: WorldChunk, cell: Vector2i, fp: Vector2i, skip: Array) -> Array:
	var out: Array = []
	for prop in chunk.props:
		var row := prop as Dictionary
		if String(row.get("archetype", "")) in skip:
			continue
		var base := row.get("cell", Vector2i(-1, -1)) as Vector2i
		var pfp := row.get("footprint", Vector2i.ONE) as Vector2i
		if WorldmapPlacement.rects_overlap(cell, fp, base, pfp, 0):
			out.append(String(row.get("archetype", "")))
	return out


# --- The ground ------------------------------------------------------------------


func test_the_road_runs_both_ways() -> void:
	_open("overworld")
	_walk_to_door(Vector2i(6, 1))
	var crossed := _step_onto(Vector2i(6, 1))
	assert_eq(bool(crossed.get("traveled", false)), true, "the road carries over")
	assert_eq(_scene.debug_summary().get("node"), "plains", "standing in the plains")
	assert_eq(_scene.player_cell(), Vector2i(0, 2), "at its entry pad")
	_walk_to_door(Vector2i(0, 3))
	var home := _step_onto(Vector2i(0, 3))
	assert_eq(bool(home.get("traveled", false)), true, "the return pad carries back")
	assert_eq(_scene.debug_summary().get("node"), "overworld", "home again")
	assert_eq(_scene.player_cell(), Vector2i(6, 2), "at the measured door")


func test_the_pads_and_gate_mouth_are_open_ground() -> void:
	_open("plains")
	var chunk := _chunk()
	assert_eq(chunk.standable(0, 2), true, "the entry pad is open")
	assert_eq(chunk.standable(0, 3), true, "and so is the return pad")
	assert_eq(chunk.standable(8, 5), true, "and the gate's mouth")


func test_the_authored_anchors_stand_and_decor_avoids_them() -> void:
	_open("plains")
	var chunk := _chunk()
	var shelter := _prop_at("settlement_and_domain_prop.shelter")
	var gate := _prop_at("landmark_and_environment_detail.domain_entrance")
	assert_eq(shelter.is_empty(), false, "the shelter stands")
	assert_eq(gate.is_empty(), false, "the gate stands")
	assert_eq(shelter.get("cell"), Vector2i(2, 2), "where it was authored")
	assert_eq(gate.get("cell"), Vector2i(6, 1), "where it was authored")
	var anchors: Array = [
		"settlement_and_domain_prop.shelter",
		"landmark_and_environment_detail.domain_entrance",
	]
	assert_eq(
		_overlaps(chunk, Vector2i(2, 2), Vector2i(2, 2), anchors).is_empty(),
		true,
		"nothing roots in the shelter"
	)
	assert_eq(
		_overlaps(chunk, Vector2i(6, 1), Vector2i(4, 4), anchors).is_empty(),
		true,
		"nothing roots in the gate"
	)


func test_the_gate_names_the_chunk_as_its_landmark() -> void:
	_open("plains")
	var layer := _chunk().layers.get("landmark", {}) as Dictionary
	assert_eq(layer.is_empty(), false, "the gate is the landmark")
	assert_eq(
		String(layer.get("archetype", "")),
		"landmark_and_environment_detail.domain_entrance",
		"as the arena mouth"
	)
	assert_eq(bool(layer.get("suggests_edge", false)), true, "suggesting the way in")
	assert_eq(layer.get("cell", []) as Array, [6, 1], "at the gate")


func test_beasts_mark_the_ground_and_an_elder_waits() -> void:
	_open("plains")
	var chunk := _chunk()
	assert_eq(
		(chunk.layers.get("encounters", []) as Array).is_empty(), false, "beasts mark the ground"
	)
	var elder := {}
	for mark in chunk.layers.get("npc_spawns", []) as Array:
		var row := mark as Dictionary
		if String(row.get("role", "")) == "elder":
			elder = row
	assert_eq(elder.is_empty(), false, "an elder waits")
	assert_eq(String(elder.get("npc_id", "")), "elder_wei", "as a named individual")
	var at := elder.get("cell", []) as Array
	assert_eq(at == [2, 4] or at == [3, 4], true, "by the shelter's doorstep")
	assert_eq(chunk.standable(int(at[0]), int(at[1])), true, "on open ground")


# --- Gathering -------------------------------------------------------------------


func test_gathering_a_herb_grants_once_and_spends_the_node() -> void:
	_open("plains")
	var herb := _prop_at("flora.cultivation_herb")
	assert_eq(herb.is_empty(), false, "a herb grows")
	var root := herb.get("cell", Vector2i(-1, -1)) as Vector2i
	var taken := _scene.gather_at(root)
	assert_eq(bool(taken.get("ok", false)), true, "the ground gives it up")
	assert_eq(
		int((taken.get("yield", {}) as Dictionary).get("alchemy_ash_herb", 0)), 1, "one herb, named"
	)
	_hero = _actor()
	var delivered := MapGatherAction.deliver(_hero, taken.get("yield", {}) as Dictionary)
	assert_eq(bool(delivered.get("ok", false)), true, "the bag takes it")
	assert_eq(ItemsApi.inventory(_hero).count(&"alchemy_ash_herb"), 1, "and the herb is in it")
	assert_eq(_chunk().spent(root.x, root.y), true, "the node is spent")
	var again := _scene.gather_at(root)
	assert_eq(bool(again.get("ok", false)), false, "a spent node gives nothing")
	assert_eq(String(again.get("reason", "")), "spent", "by name")


func test_gathering_ore_frees_the_cell_it_sealed() -> void:
	_open("plains")
	var vein := _prop_at("stone_and_ore.ore_vein")
	assert_eq(vein.is_empty(), false, "a vein surfaces")
	var root := vein.get("cell", Vector2i(-1, -1)) as Vector2i
	assert_eq(_chunk().standable(root.x, root.y), false, "it seals its ground")
	var taken := _scene.gather_at(root)
	assert_eq(bool(taken.get("ok", false)), true, "the vein is broken open")
	assert_eq(
		int((taken.get("yield", {}) as Dictionary).get("alchemy_cinder_ore", 0)),
		2,
		"two ore, named"
	)
	assert_eq(_chunk().standable(root.x, root.y), true, "and the ground opens behind it")
	var again := _scene.gather_at(root)
	assert_eq(String(again.get("reason", "")), "spent", "never twice")


func test_gathering_empty_ground_refuses() -> void:
	_open("plains")
	var refused := _scene.gather_at(Vector2i(0, 2))
	assert_eq(bool(refused.get("ok", false)), false, "bare ground owes nothing")
	assert_eq(String(refused.get("reason", "")), "nothing_here", "and says so")


# --- The elder -------------------------------------------------------------------


func test_the_elder_speaks_where_he_stands() -> void:
	_open("plains")
	var elder := {}
	for mark in _chunk().layers.get("npc_spawns", []) as Array:
		elder = mark as Dictionary
	assert_eq(elder.is_empty(), false, "the marker stands")
	var at := elder.get("cell", []) as Array
	_scene.warp(Vector2i(int(at[0]), int(at[1])))
	var speaker := VentureBoot._speaker_here(_scene)
	assert_eq(String(speaker.get("role", "")), "elder", "the ground answers an elder")
	assert_eq(String(speaker.get("npc_id", "")), "elder_wei", "by name")
	_hero = _actor()
	DialogueApi.attach(_hero)
	var opened := DialogueApi.start(_hero, &"elder_wei")
	assert_eq(bool(opened.get("ok", false)), true, "the conversation opens")
	assert_eq(String(opened.get("dialog_id", "")), "elder_wei_intro", "at his intro")


func test_beasts_roll_on_a_marked_cell() -> void:
	_open("plains")
	_hero = _actor()
	EncounterApi.attach(_hero)
	var mark := (_chunk().layers.get("encounters", []) as Array)[0] as Dictionary
	assert_eq(mark.is_empty(), false, "a beast mark stands")
	var at := mark.get("cell", [0, 0]) as Array
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("plains:%d,%d" % [int(at[0]), int(at[1])])
	var rolled := EncounterApi.trigger_encounter(_hero, &"plains", 0, rng)
	assert_eq(bool(rolled.get("triggered", false)), true, "the wild answers at the mark")
	assert_eq(String(rolled.get("encounter_id", "")).is_empty(), false, "with a real encounter")


# --- The fight -------------------------------------------------------------------


func test_the_arena_gate_descends_into_a_real_fight_that_pays() -> void:
	_hero = _actor()
	_install()
	_open("overworld")
	_walk_to_door(Vector2i(6, 1))
	_step_onto(Vector2i(6, 1))
	assert_eq(_scene.debug_summary().get("node"), "plains", "in the plains")
	_walk_to_door(Vector2i(8, 5))
	var entered := _step_onto(Vector2i(8, 5))
	assert_eq(bool(entered.get("traveled", false)), true, "the gate's mouth descends")
	assert_eq(_scene.debug_summary().get("node"), "arena", "into the arena")
	assert_eq(DomainApi.rooms(_hero).is_empty(), false, "with a real run")
	var band := LootApi.summary(_hero).get("active", {}) as Dictionary
	assert_eq(bool(band.get("in_domain", false)), true, "and a live band behind it")
	assert_eq(String(band.get("boss_id", "")), "beast_ironhide_bear", "facing the bear")
	var struck := LootApi.strike(_hero, float(band.get("vitality_max", 1.0)) * 10.0, 7)
	assert_eq(String(struck.get("reason", "")), "defeated", "the blow fells it")
	assert_eq(int(struck.get("drop_count", 0)) > 0, true, "minting drops")
	var encounter := String(struck.get("encounter_id", ""))
	var back := _scene.return_from_domain()
	assert_eq(bool(back.get("ok", false)), true, "the way back opens")
	assert_eq(
		bool((LootApi.summary(_hero).get("active", {}) as Dictionary).get("in_domain", false)),
		false,
		"with the band abandoned"
	)
	assert_eq(
		bool(LootApi.reward(_hero, encounter).get("ok", false)),
		true,
		"but the reward survives the return"
	)


# --- Walking helpers -------------------------------------------------------------


## Walk adjacent to `door` without stepping on it: entering is the caller's
## verb, so reaching is the assertion and no route is precomputed. Door cells
## of OTHER edges are forbidden — a travel cannot be backtracked out of.
## Bounded by a visited set and a cap: sealed ground answers as no route.
func _walk_to_door(door: Vector2i) -> void:
	var route := _route(_scene.player_cell(), door)
	assert_eq(route.is_empty(), false, "a route exists to %s" % str(door))
	_walk(route.slice(0, route.size() - 1))


func _step_onto(door: Vector2i) -> Dictionary:
	var last: Vector2i = door - _scene.player_cell()
	return _scene.step(last.x, last.y)


func _walk(route: Array) -> void:
	for i in range(1, route.size()):
		var leg: Vector2i = (route[i] as Vector2i) - (route[i - 1] as Vector2i)
		var outcome := _scene.step(leg.x, leg.y)
		assert_eq(bool(outcome.get("moved", false)), true, "every routed step moves")


func _route(from: Vector2i, to: Vector2i) -> Array:
	var doors := _door_cells()
	var prev := {from: -1}
	var queue: Array = [from]
	while not queue.is_empty() and prev.size() < WALK_CAP:
		var current := queue.pop_front() as Vector2i
		if current == to:
			break
		for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + delta
			if prev.has(next):
				continue
			if next != to and next in doors:
				continue
			if not _scene.is_standable(next):
				continue
			prev[next] = current
			queue.append(next)
	if not prev.has(to):
		return []
	var route: Array = [to]
	var cursor: Vector2i = to
	while cursor != from:
		cursor = prev[cursor] as Vector2i
		route.push_front(cursor)
	return route


func _door_cells() -> Array:
	var out: Array = []
	for edge in _scene.debug_summary().get("edges", []) as Array:
		var at = (edge as Dictionary).get("from_cell", Vector2i(-1, -1))
		# Raw graph edges carry Vector2i cells; only the boot's trimmed read
		# uses pairs. Read both, believe neither blindly.
		if at is Vector2i:
			out.append(at)
		elif at is Array and (at as Array).size() == 2:
			out.append(Vector2i(int((at as Array)[0]), int((at as Array)[1])))
	return out
