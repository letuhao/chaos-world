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
		# Rows are labelled, not keyed by id: `acupoint_quality` is shown as
		# "Huyệt quality", so this compares the stat id to the label the sheet would
		# print for it. Comparing id to id instead would pass again the moment the
		# sheet went back to printing raw ids.
		assert_eq(
			names.has(StatPresenter.label_for(StringName(key))),
			true,
			"%s is rendered, not dropped" % key
		)
	screen.free()


## The test above passed while the sheet rendered NOTHING, and this is why.
##
## `_screen_rows` walked the children looking for `StatRow`, and `StatRow.new()`
## children are `StatRow`s -- they just have no `%StatLabel` or `%ValueLabel`, so
## they draw an empty box. Their `summary()` still answered with a name, a current
## and a `text` read off plain fields, so "is this stat rendered?" was answered yes
## by rows that were not on screen. A row has to be able to report that it failed
## to render, and the sheet has to be asked.
func test_every_row_on_the_sheet_actually_draws() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var rows := _screen_rows(screen)
	assert_ne(rows.size(), 0, "there are rows")
	for row in rows:
		var name := String(row.get("name", ""))
		assert_eq(
			bool(row.get("rendered", false)), true, "%s has a value label and can draw" % name
		)
		assert_eq(
			String(row.get("label_text", "")),
			name,
			"%s puts its name in the label node, not only in a field" % name
		)
	screen.free()


## The sheet binds its rows by `%` unique name, and those names are CASE-SENSITIVE.
## It used to ask for `%pool0Row` while the scene declares `Pool0Row`, so
## `get_node_or_null` answered null for every row, the screen concluded it had none,
## and composed all 38 itself -- as childless rows. A pool is the resource the
## player spends, so "the reservoir does not appear" is the sharpest form of this.
func test_the_resource_pools_reach_the_sheet_as_rows() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var vitals: Dictionary = screen.summary().get("vitals", {})
	assert_eq(
		vitals.has("Body integrity"), true, "body_integrity is drawn as a row, keyed by its label"
	)
	var row: Dictionary = vitals.get("Body integrity", {})
	assert_eq(bool(row.get("rendered", false)), true, "and it draws")
	assert_eq(bool(row.get("bar_visible", false)), true, "a pool is shown as a bar")
	screen.free()


## The defect as a figure. `acupoint_quality` is 0.5 on a fresh R1 body actor and
## used to read "1"; `crit_chance` is 0.05 and used to read "0", which told a player
## they could never crit. A row that is present and wrong fails this.
## `breakthrough_chance` is `0.1 + comprehension*0.01 + will*0.005` on this actor's
## stats, so it reads 0.100 here. The 0.2 figure is `test_stat_presenter.gd`'s,
## which pins the format against a literal rather than against a derived actor.
func test_fraction_stats_are_not_rounded_on_the_sheet() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var rows := _by_name(_screen_rows(screen))
	assert_eq(
		rows.get("Huyệt quality", {}).get("text", ""),
		"0.50",
		"acupoint_quality = 0.5 must read 0.50, not 1"
	)
	assert_eq(
		rows.get("Crit chance", {}).get("text", ""),
		"0.050",
		"crit_chance = 0.05 must read 0.050, not 0"
	)
	assert_eq(
		rows.get("Breakthrough chance", {}).get("text", ""),
		"0.100",
		"breakthrough_chance must read 0.100, not 0"
	)
	screen.free()


## The raw id is not a label. A sheet that prints `acupoint_quality` tells the
## player nothing about what the number means.
func test_no_row_on_the_sheet_shows_a_raw_stat_id() -> void:
	var screen := _screen()
	screen.setup(_actor())
	for row in _screen_rows(screen):
		var name := String(row.get("name", ""))
		assert_eq(name, StatPresenter.label_for(StringName(name)), "%s is labelled" % name)
		assert_eq(name.contains("_"), false, "%s is not a raw id" % name)
	screen.free()


## The line above the sheet names the path a player reads, not the module id.
func test_the_paths_line_is_written_for_a_player() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var label := screen.get_node_or_null("%PathsLabel") as Label
	assert_ne(label, null, "the paths label exists")
	assert_eq(
		label.text.contains("body_cultivation"),
		false,
		"the sheet does not print a module id to the player"
	)
	assert_eq(label.text.contains("Body qi_refining"), true, "it says Body: %s" % label.text)
	screen.free()


func _by_name(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row in rows:
		out[String(row.get("name", ""))] = row
	return out


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
