extends TestCase

## ZZ PROBE — MEASUREMENT ONLY. Prints the whole `strike -> record_verdict ->
## record_kill` chain for one WON fight, verbatim, so the defect is diagnosed from
## evidence rather than from a guess. Deleted after the run; it asserts nothing.

const SEED := 7
const MAX_BLOWS := 60
const STANDING_OFFSET := Vector2(24.0, 0.0)

var _born: Array[Node] = []
var _root: Window = null
var _deaths: Array[Dictionary] = []
var _roster: Array[Actor] = []
var _hero_actor: Actor = null


func setup() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_deaths.clear()
	DomainFight.set_death_listener(_on_death)


func teardown() -> void:
	DomainFight.set_death_listener(Callable())
	DomainBoot.reset()
	for node in _born:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()
	_born.clear()
	_roster.clear()
	_hero_actor = null


func _on_death(actor: Actor, decided_by: String, killer_id: String) -> void:
	(
		_deaths
		. append(
			{
				"actor_id": String(actor.id),
				"decided_by": String(decided_by),
				"killer_id": String(killer_id),
			}
		)
	)


# ── the probe body ───────────────────────────────────────────────────────────


func test_zz_probe_verdict() -> void:
	print("\n\n@@@@@@@@@@ ZZ PROBE VERDICT — BEGIN @@@@@@@@@@")
	print("Godot ", Engine.get_version_info().get("string", "?"))

	var hero := _hero()
	print("\n[0] hero id=", hero.id, " health=", _health_of(hero))

	print("\n[1] --- catalogue templates ---")
	for row in DomainApi.templates():
		print("    template: ", row.get("template_id", ""))

	var template_id := _template_id()
	print("[2] chosen template: ", template_id)

	print("\n[3] --- roster of the GENERATED map (test 1's path) ---")
	_probe_generated(template_id)

	print("\n[4] --- fixture-placed bodies (the _enter_with path) ---")
	_probe_fixture(template_id)

	print("@@@@@@@@@@ ZZ PROBE VERDICT — END @@@@@@@@@@\n")


## The map's OWN bodies: what `enter_domain` minted, drawn by `realize_world`.
func _probe_generated(template_id: StringName) -> void:
	var hero := _hero()
	var world := _world()
	DomainBoot.install()
	var entered := DomainBoot.enter_domain(hero, template_id, SEED)
	print("  enter_domain ok=", entered.get("ok", false))
	DomainBoot.realize_world(world, hero)
	var band := DomainRunApi.band(hero)
	print("  band.bosses = ", band.get("bosses", []))
	print("  band.domain_id = ", band.get("domain_id", ""))
	print("  roster from DomainBoot.placed_inhabitants():")
	for inhabitant in DomainBoot.placed_inhabitants():
		var actor := inhabitant as Actor
		if actor == null:
			continue
		print(
			"      id=",
			actor.id,
			" room_of=",
			DomainSpawner.room_of(actor),
			" role=",
			DomainSpawner.role_of(actor),
			" has_boss_tag=",
			DomainSpawner.has_role(actor, DomainRoles.BOSS),
			" health=",
			_health_of(actor)
		)
	var placed := _first_boss_in_reach(world)
	print("  _first_boss_in_reach -> id=", placed.id if placed != null else "<null>")
	if placed != null:
		print(
			"  that body: room_of=",
			DomainSpawner.room_of(placed),
			" has_boss_tag=",
			DomainSpawner.has_role(placed, DomainRoles.BOSS)
		)
		print(
			"  DomainFight._placed_boss(hero, '",
			placed.id,
			"') = ",
			DomainFight._placed_boss(hero, String(placed.id))
		)
		print(
			"  DomainFight._door_of(hero, '",
			placed.id,
			"')     = ",
			DomainFight._door_of(hero, String(placed.id))
		)
		_drive_press_chain("GENERATED", hero, placed)
	DomainBoot.reset()
	_free_born()


## The fixture's own bodies: minted by `DomainSpawner.spawn`, then placed into a
## boss room the FIXTURE chose.
func _probe_fixture(template_id: StringName) -> void:
	var hero := _hero()
	var world := _world()
	var placed := _body(&"warden", &"boss", 1.0, {"punish_window_blows": 1})
	_enter_with(hero, [placed], world)
	var band := DomainRunApi.band(hero)
	print("  band.bosses = ", band.get("bosses", []))
	print("  band.domain_id = ", band.get("domain_id", ""))
	print("  fixture _boss_rooms() = ", _boss_rooms(hero))
	print("  roster from DomainBoot.placed_inhabitants() (NOT the fixture bodies):")
	for inhabitant in DomainBoot.placed_inhabitants():
		var actor := inhabitant as Actor
		if actor == null:
			continue
		print(
			"      id=",
			actor.id,
			" room_of=",
			DomainSpawner.room_of(actor),
			" has_boss_tag=",
			DomainSpawner.has_role(actor, DomainRoles.BOSS)
		)
	print("  fixture body: id=", placed.id, " room_of=", DomainSpawner.room_of(placed))
	print("  fixture _door_for(placed) = ", _door_for(placed))
	print(
		"  DomainFight._placed_boss(hero, '",
		placed.id,
		"') = ",
		DomainFight._placed_boss(hero, String(placed.id))
	)
	print(
		"  DomainFight._door_of(hero, '",
		placed.id,
		"')     = ",
		DomainFight._door_of(hero, String(placed.id))
	)
	_drive_press_chain("FIXTURE", hero, placed)
	DomainBoot.reset()
	_free_born()


## Replay `DomainFight.strike`'s body one stage at a time, printing the DECIDING
## blow in full: age, press, record_verdict — then the band's before/after.
func _drive_press_chain(label: String, hero: Actor, placed: Actor) -> void:
	print("\n  ---- [", label, "] press chain ----")
	var fight := FightLoop.new(hero, placed)
	fight.begin_fight(placed)
	var band_before := DomainRunApi.band(hero)
	print("  summary BEFORE = ", _summary_view(fight.summary()))
	print(
		"  band BEFORE: kill_count=",
		band_before.get("kill_count", -1),
		" open_index=",
		band_before.get("open_index", -1),
		" open_boss=",
		band_before.get("open_boss", ""),
		" kills=",
		band_before.get("kills", {}),
		" bosses=",
		band_before.get("bosses", [])
	)
	var blows := 0
	while blows < MAX_BLOWS and _health_of(placed) > 0.0:
		blows += 1
		var opponent_before := _health_of(placed)
		var summary_before := fight.summary()
		var gate := DomainFight.age(fight, FightLoop.BASE_BLOW_INTERVAL)
		var blow := DomainFight.press(fight, SEED)
		var verdict := DomainFight.record_verdict(hero, fight)
		var opponent_after := _health_of(placed)
		if blows <= 3 or opponent_after <= 0.0:
			print(
				"  blow #",
				blows,
				" opp_health ",
				opponent_before,
				" -> ",
				opponent_after,
				" | age.ok=",
				gate.get("ok", false),
				" | press.ok=",
				blow.get("ok", false),
				" press.reason=",
				blow.get("reason", ""),
				" press.outcome=",
				blow.get("outcome", ""),
				" | summary_before.outcome=",
				summary_before.get("outcome", "")
			)
		if opponent_after <= 0.0:
			print("\n  ===== THE DECIDING BLOW (blow #", blows, ") =====")
			print("  --- fight.summary() AFTER the deciding blow ---")
			print("  ", _summary_view(fight.summary()))
			print("  --- DomainFight.press() FULL RETURN ---")
			print("  ", blow)
			print("  --- DomainFight.record_verdict() FULL RETURN ---")
			print("  ", verdict)
			print("  --- boss_id record_verdict computed ---")
			print(
				"      boss_id = '",
				String(verdict.get("boss_id", "<no boss_id key>")),
				"'   (verdict.reason = '",
				String(verdict.get("reason", "")),
				"')"
			)
			print("  --- run['bosses'] SIDE BY SIDE ---")
			print("      run bosses = ", band_before.get("bosses", []))
			print(
				"      contains computed boss_id? ",
				(band_before.get("bosses", []) as Array).has(String(verdict.get("boss_id", "")))
			)
			var band_after := DomainRunApi.band(hero)
			print("  --- DomainRunApi.band() AFTER ---")
			print(
				"      kill_count=",
				band_after.get("kill_count", -1),
				" remaining_count=",
				band_after.get("remaining_count", -1),
				" open_index=",
				band_after.get("open_index", -1),
				" cleared=",
				band_after.get("cleared", false),
				" gate=",
				band_after.get("gate", ""),
				" kills=",
				band_after.get("kills", {})
			)
			print("  --- zero crossing fired so far ---")
			print("  ", _deaths)
			return
	print(
		"\n  !!! NO DECIDING BLOW inside the bound. blows=",
		blows,
		" opp_health=",
		_health_of(placed),
		" hero_health=",
		_health_of(hero)
	)
	print("  final summary = ", _summary_view(fight.summary()))
	var band_after := DomainRunApi.band(hero)
	print(
		"  band AFTER: kill_count=",
		band_after.get("kill_count", -1),
		" open_index=",
		band_after.get("open_index", -1),
		" kills=",
		band_after.get("kills", {})
	)
	print("  deaths fired = ", _deaths)


## The SAME fight, driven by the public `strike` verb instead, so its own return
## shape is printed verbatim too.
func test_zz_probe_strike_verb() -> void:
	print("\n\n@@@@@@@@@@ ZZ PROBE — strike() verb @@@@@@@@@@")
	var template_id := _template_id()
	var hero := _hero()
	var world := _world()
	var placed := _body(&"warden", &"boss", 1.0, {"punish_window_blows": 1})
	_enter_with(hero, [placed], world)
	var fight := FightLoop.new(hero, placed)
	fight.begin_fight(placed)
	var blows := 0
	while blows < MAX_BLOWS and _health_of(placed) > 0.0:
		blows += 1
		var answer := DomainFight.strike(hero, fight, FightLoop.BASE_BLOW_INTERVAL, SEED)
		if _health_of(placed) <= 0.0 or blows <= 2:
			print("  strike #", blows, " -> ", answer)
	var band := DomainRunApi.band(hero)
	print(
		"  band: kill_count=",
		band.get("kill_count", -1),
		" open_index=",
		band.get("open_index", -1),
		" kills=",
		band.get("kills", {}),
		" remaining=",
		band.get("remaining", [])
	)
	print("@@@@@@@@@@ ZZ PROBE — strike() verb END @@@@@@@@@@\n")


# ── printing helpers ─────────────────────────────────────────────────────────


func _summary_view(summary: Dictionary) -> String:
	if summary.is_empty():
		return "<empty>"
	return (
		"{outcome="
		+ _q(summary.get("outcome", "<absent>"))
		+ ", opponent_id="
		+ _q(summary.get("opponent_id", "<absent>"))
		+ ", decided_by="
		+ _q(summary.get("decided_by", "<absent>"))
		+ ", fighting="
		+ _q(summary.get("fighting", "<absent>"))
		+ ", hero_blows="
		+ _q(summary.get("hero_blows", "<absent>"))
		+ ", hero_health="
		+ _q(summary.get("hero_health", "<absent>"))
		+ ", opponent_health="
		+ _q(summary.get("opponent_health", "<absent>"))
		+ "}"
	)


func _q(value: Variant) -> String:
	return "'" + String(value) + "'"


# ── fixture helpers (mirroring test_domain_run_chain.gd) ─────────────────────


func _world() -> Node:
	var world := Node.new()
	world.name = "ProbeWorld"
	_root.add_child(world)
	_born.append(world)
	return world


func _free_born() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()
	_born.clear()


func _hero() -> Actor:
	var hero := ActorFactory.build(&"domain_hero")
	CombatBoot.install(hero)
	_hero_actor = hero
	return hero


func _enter(hero: Actor) -> Dictionary:
	DomainBoot.install()
	return DomainBoot.enter_domain(hero, _template_id(), SEED)


func _enter_with(hero: Actor, bodies: Array[Actor], world: Node) -> Dictionary:
	var run := _enter(hero)
	var rooms := _boss_rooms(hero)
	if rooms.is_empty():
		return run
	DomainBoot.realize_world(world, hero)
	var roster: Array[Actor] = []
	for index in range(bodies.size()):
		var actor := bodies[index]
		if actor == null:
			continue
		var room_id: StringName = rooms[index % rooms.size()]
		var point := Vector2(96.0 + 32.0 * float(index), 96.0)
		var spec := DomainSpawner.boss_spec_of(actor)
		if not spec.is_empty():
			BossEncounter.bind(
				actor, float(spec.get("interval", 1.0)), int(spec.get("punish_window_blows", 0))
			)
		CombatBoot.install(actor)
		_place_body(world, actor, room_id, point)
		roster.append(actor)
	_roster = roster
	DomainBoot.register_targets(world)
	return run


func _place_body(world: Node, actor: Actor, room_id: StringName, point: Vector2) -> void:
	var root := _world_root(world)
	if root == null:
		return
	var holder := root.get_node_or_null(NodePath(DomainWorld.WORLD_INHABITANTS_NODE))
	if holder == null:
		holder = Node2D.new()
		holder.name = DomainWorld.WORLD_INHABITANTS_NODE
		root.add_child(holder)
	var body := Node2D.new()
	body.name = "ProbeBody_%s_%d" % [String(actor.id), holder.get_child_count()]
	body.position = point
	body.set_meta(&"actor", actor)
	body.set_meta(&"room_id", String(room_id))
	body.set_meta(&"role", String(DomainSpawner.role_of(actor)))
	holder.add_child(body)
	var record: Dictionary = actor.get_module_data(DomainSpawner.MODULE_KEY)
	record["room_id"] = String(room_id)
	record["position"] = [point.x, point.y]
	actor.set_module_data(DomainSpawner.MODULE_KEY, record)


func _boss_rooms(hero: Actor) -> Array:
	var out: Array = []
	var map := _map_of(hero)
	if map == null:
		return out
	for room_id in map.room_ids_sorted():
		var room := map.room(room_id) as RoomDef
		if room == null:
			continue
		if room.band() == RoomDef.BOSS_BAND:
			out.append(room_id)
			continue
		for ref in room.actor_spawn_refs:
			if StringName(ref.get("role", "")) == DomainRoles.BOSS:
				out.append(room_id)
				break
	return out


func _map_of(hero: Actor) -> DomainMap:
	var state: Variant = hero.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])


func _body(
	inhabitant_id: StringName, role: StringName, blows_to_survive: float, boss_spec: Dictionary
) -> Actor:
	var def := InhabitantDef.new()
	def.inhabitant_id = inhabitant_id
	def.display_name = String(inhabitant_id)
	def.realm_id = &"qi_refining"
	def.hostile = true
	def.blows_to_survive = blows_to_survive
	def.boss_spec = boss_spec
	return DomainSpawner.spawn(def, role)


func _first_boss_in_reach(world: Node) -> Actor:
	var holder := _holder(world)
	var adapter := _adapter(world)
	if holder == null or adapter == null:
		return null
	for body in holder.get_children():
		var node := body as Node2D
		if node == null or not node.has_meta(&"actor"):
			continue
		var actor := node.get_meta(&"actor") as Actor
		if actor == null or not DomainSpawner.is_hostile(actor):
			continue
		adapter.global_position = node.global_position + STANDING_OFFSET
		return actor
	return null


func _holder(world: Node) -> Node:
	var root := _world_root(world)
	return (
		null
		if root == null
		else root.get_node_or_null(NodePath(DomainWorld.WORLD_INHABITANTS_NODE))
	)


func _world_root(world: Node) -> Node:
	if world == null:
		return null
	return world.get_node_or_null(NodePath(DomainWorld.WORLD_NODE))


func _adapter(world: Node) -> PlayerAdapter:
	var root := _world_root(world)
	if root == null:
		return null
	return root.get_node_or_null(NodePath(DomainWorld.WORLD_PLAYER_NODE)) as PlayerAdapter


func _door_for(actor: Actor) -> String:
	var band := DomainRunApi.band(_hero_actor)
	return "%s/%s" % [String(band.get("domain_id", "")), String(DomainSpawner.room_of(actor))]


func _health_of(actor: Actor) -> float:
	if actor == null:
		return 0.0
	var pool := actor.resource(&"health") as ResourcePool
	return 0.0 if pool == null else pool.current


func _template_id() -> StringName:
	var fallback: StringName = &""
	for row in DomainApi.templates():
		var candidate := StringName(String((row as Dictionary).get("template_id", "")))
		if fallback == &"":
			fallback = candidate
		var probe_actor := _hero()
		var entered := DomainApi.generate_and_enter(probe_actor, candidate, SEED)
		if not bool(entered.get("ok", false)):
			continue
		var band: Dictionary = DomainRunApi.band(probe_actor)
		DomainApi.leave(probe_actor)
		if _holds_a_room_door(band):
			return candidate
	return fallback


func _holds_a_room_door(band: Dictionary) -> bool:
	var bosses: Array = band.get("bosses", [])
	for entry in bosses:
		if String(entry).contains("/"):
			return true
	return false
