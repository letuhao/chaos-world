extends TestCase

## THE DESCENT: a node naming a domain template enters a REAL run, and the
## return stands on the exact cell left from.
##
## The seam doubles below call the REAL `DomainApi` on a REAL actor — a mock
## run would prove the scene remembers a cell and nothing about the run being
## one. Every claim about the run (rooms stand, discovered is kept) reads the
## module's own answers, never the double's.

const ENV := "mortal_greenwood"
const TEMPLATE := &"ember_grotto"
const SEED := 20261003

var _scene: WorldmapScene = null
var _hero: Actor = null
var _born: Array = []
var _entered: Array = []
var _exits := 0


func setup() -> void:
	WorldmapApi.clear_domain()
	WorldmapApi.clear_loot()
	WorldmapApi.clear_returns()
	_scene = null
	_hero = null
	_entered.clear()
	_exits = 0


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
	_entered.append({"template": template_id, "seed": seed})
	if _hero == null:
		return {"ok": false, "reason": "no_actor"}
	return DomainApi.generate_and_enter(_hero, StringName(template_id), seed)


func _exit() -> Dictionary:
	_exits += 1
	if _hero == null:
		return {"ok": false, "reason": "no_actor"}
	return DomainApi.leave(_hero)


func _install() -> void:
	var outcome := WorldmapApi.install_domain(Callable(self, "_entry"), Callable(self, "_exit"))
	assert_eq(bool(outcome.get("ok", false)), true, "the seam installs")


func _configs() -> Dictionary:
	return {
		"overworld":
		{
			"environment": ENV,
			"chunk_size": 8,
			"seed": 1234,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"scatter":
			[
				{"archetype": "flora.shrub", "density": 0.05, "blocking": true},
				{"archetype": "flora.flower_cluster", "density": 0.08, "blocking": false},
			],
		},
		"cave":
		{
			"environment": ENV,
			"chunk_size": 6,
			"seed": 99,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"water": false,
			"authored_terrain": [],
			"scatter": [],
			"domain_template": String(TEMPLATE),
			"domain_seed": SEED,
		},
	}


func _open() -> void:
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "cave",
				"kind": &"doorway",
				"from_cell": Vector2i(1, 1),
				"to_cell": Vector2i(1, 1),
			}
		)
	)
	_scene = WorldmapScene.new()
	var outcome := _scene.open(graph, "overworld", _configs())
	assert_eq(bool(outcome.get("ok", false)), true, "the overworld opens")


func test_the_way_back_survives_the_scene_that_pushed_it() -> void:
	# Navigation frees the scene mid-descent. The return lives module-side,
	# so a fresh scene over the same graph still knows the way back.
	_hero = _actor()
	_install()
	_open()
	_scene.step(1, 0)
	assert_eq(_scene.debug_summary().get("node"), "cave", "inside")
	_scene.free()
	_scene = null
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	_scene = WorldmapScene.new()
	var outcome := _scene.open(graph, "overworld", _configs())
	assert_eq(bool(outcome.get("ok", false)), true, "a fresh scene opens above ground")
	assert_eq(
		(_scene.debug_summary().get("domain", {}) as Dictionary).is_empty(),
		false,
		"reading the standing descent as its own"
	)
	var back := _scene.return_from_domain()
	assert_eq(bool(back.get("ok", false)), true, "and the way back still opens")
	assert_eq(_scene.player_cell(), Vector2i(1, 1), "on the exact cell")
	assert_eq(DomainApi.rooms(_hero).is_empty(), true, "with the run left through the seam")


func test_a_descent_with_no_seam_refuses_by_name() -> void:
	_open()
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), false, "nothing installed, nothing entered")
	assert_eq(String(outcome.get("reason", "")), "no_domain_seam", "and it says so")
	assert_eq(_scene.debug_summary().get("node"), "overworld", "on the same node")


func test_a_refused_entry_leaves_the_player_where_they_stood() -> void:
	WorldmapApi.install_domain(Callable(self, "_entry_refused"), Callable(self, "_exit"))
	_open()
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), false, "a refused run is not entered")
	assert_eq(String(outcome.get("reason", "")), "sealed", "passing the refusal through")
	assert_eq(_scene.player_cell(), Vector2i(1, 1), "on the gate cell, above ground")


func _entry_refused(_template_id: String, _seed: int) -> Dictionary:
	return {"ok": false, "reason": "sealed"}


func test_descending_enters_a_real_run_and_freezes_the_feet() -> void:
	_hero = _actor()
	_install()
	_open()
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), true, "the doorway descends")
	assert_eq(_entered.size(), 1, "through the installed seam once")
	assert_eq(
		String((_entered[0] as Dictionary).get("template", "")),
		String(TEMPLATE),
		"naming the template"
	)
	assert_eq(int((_entered[0] as Dictionary).get("seed", 0)), SEED, "at the authored seed")
	assert_eq(_scene.debug_summary().get("node"), "cave", "on the domain node")
	assert_eq(
		String((_scene.debug_summary().get("domain", {}) as Dictionary).get("template", "")),
		String(TEMPLATE),
		"which the summary owns"
	)
	assert_eq(
		DomainApi.rooms(_hero).is_empty(), false, "and the run is REAL: rooms stand on the actor"
	)
	var step := _scene.step(1, 0)
	assert_eq(String(step.get("reason", "")), "inside_domain", "while the feet stay still")
	var broken := _scene.destroy_at(Vector2i(1, 1))
	assert_eq(String(broken.get("reason", "")), "inside_domain", "and nothing breaks in a room")


func test_the_return_stands_on_the_exact_cell_with_the_overworld_intact() -> void:
	_hero = _actor()
	_install()
	_open()
	var victim := _blocking_cell()
	_scene.streamer().mutate("overworld", 0, 0, victim.x, victim.y, false)
	assert_eq(_scene.is_standable(victim), true, "ground broken before the descent")
	_scene.step(1, 0)
	assert_eq(_scene.debug_summary().get("node"), "cave", "inside")
	var back := _scene.return_from_domain()
	assert_eq(bool(back.get("ok", false)), true, "the way back opens")
	assert_eq(_exits, 1, "leaving the run through the seam")
	assert_eq(_scene.debug_summary().get("node"), "overworld", "on the overworld again")
	assert_eq(_scene.player_cell(), Vector2i(1, 1), "on the exact cell left from")
	assert_eq(_scene.is_standable(victim), true, "with the broken ground still broken")
	assert_eq(DomainApi.rooms(_hero).is_empty(), true, "and the run gone from the actor")


func test_returning_above_ground_refuses() -> void:
	_install()
	_open()
	var back := _scene.return_from_domain()
	assert_eq(bool(back.get("ok", false)), false, "nothing to return from")
	assert_eq(String(back.get("reason", "")), "not_inside", "by name")
	assert_eq(_exits, 0, "without touching the seam")


func _blocking_cell() -> Vector2i:
	var chunk := _scene.streamer().chunk_data("overworld", 0, 0, 8, 1234)
	for prop in chunk.props:
		var placement := prop as Dictionary
		if not bool(placement.get("blocking", false)):
			continue
		var base := placement.get("cell", Vector2i(-1, -1)) as Vector2i
		if chunk.standable(base.x, base.y):
			continue
		return Vector2i(base.x, base.y)
	assert_eq(true, false, "the config grows a blocking prop to break")
	return Vector2i(-1, -1)


# --- The boss band joins the descent --------------------------------------------------


func _loot_configs() -> Dictionary:
	var configs := _configs()
	(configs["cave"] as Dictionary)["loot_domain"] = "amulet_storm_phoenix_domain"
	(configs["cave"] as Dictionary)["loot_tier"] = 1
	return configs


func _open_loot() -> void:
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "cave",
				"kind": &"doorway",
				"from_cell": Vector2i(1, 1),
				"to_cell": Vector2i(1, 1),
			}
		)
	)
	_scene = WorldmapScene.new()
	var outcome := _scene.open(graph, "overworld", _loot_configs())
	assert_eq(bool(outcome.get("ok", false)), true, "the overworld opens")


func _install_loot() -> void:
	_install()
	var outcome := WorldmapApi.install_loot(
		Callable(self, "_loot_entry"), Callable(self, "_loot_exit")
	)
	assert_eq(bool(outcome.get("ok", false)), true, "the loot seam installs")


func _loot_entry(domain_id: String, tier: int, seed: int) -> Dictionary:
	return LootApi.enter_domain(_hero, StringName(domain_id), tier, seed)


func _loot_exit() -> Dictionary:
	return LootApi.abandon(_hero)


func _band() -> Dictionary:
	return LootApi.summary(_hero).get("active", {}) as Dictionary


func test_a_descent_with_a_loot_domain_also_enters_the_band() -> void:
	_hero = _actor()
	_install_loot()
	_open_loot()
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), true, "the doorway descends")
	assert_eq(DomainApi.rooms(_hero).is_empty(), false, "with a real run")
	assert_eq(bool(_band().get("in_domain", false)), true, "and a live band behind it")
	assert_eq(String(_band().get("boss_id", "")), "amulet_storm_phoenix", "facing its first boss")


func test_a_struck_boss_mints_and_the_return_keeps_the_reward() -> void:
	_hero = _actor()
	_install_loot()
	_open_loot()
	_scene.step(1, 0)
	var active := _band()
	var struck := LootApi.strike(_hero, float(active.get("vitality_max", 1.0)) * 10.0, 7)
	assert_eq(String(struck.get("reason", "")), "defeated", "the blow fells the boss")
	assert_eq(int(struck.get("drop_count", 0)) > 0, true, "minting drops")
	var encounter := String(struck.get("encounter_id", ""))
	var back := _scene.return_from_domain()
	assert_eq(bool(back.get("ok", false)), true, "the way back opens")
	assert_eq(bool(_band().get("in_domain", false)), false, "with the band abandoned")
	var reward := LootApi.reward(_hero, encounter)
	assert_eq(bool(reward.get("ok", false)), true, "but the reward survives the return")


func test_a_refused_band_unwinds_the_run() -> void:
	_hero = _actor()
	_install()
	WorldmapApi.install_loot(Callable(self, "_loot_refused"), Callable(self, "_loot_exit"))
	_open_loot()
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), false, "no band, no descent")
	assert_eq(String(outcome.get("reason", "")), "sealed", "passing the refusal through")
	assert_eq(DomainApi.rooms(_hero).is_empty(), true, "with the run unwound")
	assert_eq(WorldmapApi.return_depth(), 0, "and no return pushed")


func _loot_refused(_domain_id: String, _tier: int, _seed: int) -> Dictionary:
	return {"ok": false, "reason": "sealed"}


func test_a_descent_without_a_loot_seam_refuses_by_name() -> void:
	_hero = _actor()
	_install()
	_open_loot()
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), false, "nothing installed, nothing entered")
	assert_eq(String(outcome.get("reason", "")), "no_loot_seam", "and it says so")
	assert_eq(DomainApi.rooms(_hero).is_empty(), true, "with the run unwound")
