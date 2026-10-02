extends TestCase

## The character screen (ADR 0038/0042). The one screen that only reads, so it
## is the cheapest proof the UI program can render a whole Actor. It reads
## derived stats from `ActorStats` rather than recomputing, so it can never
## disagree with combat.

const SCREEN := "res://src/ui/screens/character_screen.tscn"


func _screen() -> CharacterScreen:
	return (load(SCREEN) as PackedScene).instantiate() as CharacterScreen


func _actor() -> Actor:
	var actor := Actor.new(&"sheet_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(PathState.BODY, &"qi_refining"))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 32)
	return actor


func test_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not partial")
	screen.free()


func test_it_reports_every_path_including_absent_ones() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var paths: Dictionary = screen.summary().get("paths", {})
	assert_eq(paths.size(), PathState.ALL.size(), "one entry per known path")
	assert_eq(paths.get(String(PathState.BODY), {}).get("enrolled", false), true, "body enrolled")
	# A path the actor does not carry is reported, not omitted, so a caller can
	# tell "not enrolled" from "unknown".
	assert_eq(paths.get(String(PathState.QI), {}).get("enrolled", true), false, "qi absent")
	assert_eq(paths.get(String(PathState.MIND), {}).get("enrolled", true), false, "mind absent")
	screen.free()


func test_derived_stats_come_from_the_actor_not_recomputed() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var stats: Dictionary = screen.summary().get("stats", {})
	assert_eq(stats.is_empty(), false, "stats are reported")
	assert_eq(
		float(stats.get("attack_physical", 0.0)),
		actor.stats.derived(Stat.ATTACK_PHYSICAL),
		"the sheet reads the same source combat will read"
	)
	assert_eq(
		float(stats.get("max_health", 0.0)), actor.stats.derived(Stat.MAX_HEALTH), "health too"
	)
	screen.free()


func test_pools_are_reported_as_raw_values() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var pools: Dictionary = screen.summary().get("pools", {})
	assert_eq(pools.has("body_integrity"), true, "the body's reservoir is listed")
	var entry: Dictionary = pools["body_integrity"]
	assert_eq(entry.get("maximum", 0.0), 100.0, "raw current/maximum, not a formatted string")
	for value in entry.values():
		assert_eq(view_is_primitive(value), true, "each pool value is a primitive")
	screen.free()


func test_summary_keys_are_sorted_so_two_runs_agree() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var keys: Array = screen.summary().get("stat_keys", [])
	assert_eq(keys.size() > 1, true, "several stats are reported")
	var sorted_keys := keys.duplicate()
	sorted_keys.sort()
	assert_eq(keys, sorted_keys, "order is deterministic, so a diff between runs is meaningful")
	screen.free()


func test_every_derived_stat_is_reachable_not_silently_dropped() -> void:
	var screen := _screen()
	screen.setup(_actor())
	# The sheet scrolls rather than truncates: a stat that silently vanished reads
	# as a stat the actor does not have (ADR 0043). So the sheet must compose a row
	# for every derived stat the actor has, not just the eight the scene declares.
	var stats: Dictionary = screen.summary().get("stats", {})
	assert_ne(stats.size(), 0, "there are stats to show")
	var names := {}
	for row in _screen_rows(screen):
		names[String(row.get("name", ""))] = true
	for key in stats:
		assert_eq(names.has(String(key)), true, "%s is rendered, not dropped" % key)
	screen.free()


## Every non-empty row the screen composed, so a test can count what is rendered.
func _screen_rows(screen: CharacterScreen) -> Array:
	var out: Array = []
	var list := screen.get_node_or_null("Layout/Scroll/Stats")
	if list == null:
		return out
	for child in list.get_children():
		if child is StatRow:
			var view: Dictionary = (child as StatRow).summary()
			if not view.is_empty():
				out.append(view)
	return out


func test_it_exposes_the_shared_vitals_contract() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	# The sheet offers no action, so it declares none.
	assert_eq(view.has("actions"), false, "a read-only screen has no action row")
	for key in ["actor", "paths", "pools", "stats", "vitals"]:
		assert_eq(view.has(key), true, "%s is reported" % key)
	screen.free()


func view_is_primitive(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		_:
			return false
