extends TestCase

## The half of the counter bridge that was NEVER PROVEN: that the GAME installs it.
##
## ## Why this file exists (DEF-0231 / DEF-0232)
##
## `src/app/item_workbench_app.gd:208` is `DestinyProjection.subscribe_to_fact_ledger()`.
## That one line is the entire production fix for the fact->counter bridge — ADR 0148 and
## ADR 0149 both cite it — and until this file existed NOTHING tested it. Both sibling
## destiny counter suites install the bridge themselves in `setup()` and remove it again
## in `teardown()`, so deleting the production line leaves the whole destiny suite green.
## A green suite that proves the bridge WORKS while saying nothing about whether it is
## INSTALLED is the defect class ADR 0149 is about: machinery wired to a gate nobody
## can reach.
##
## The sibling suite even says so in prose, and names a file that did not exist:
## "`test_destiny_fact_wiring_hook.gd` owns that question". Three ADRs, a deferred entry
## and a test header cited a file nobody wrote. This is that file.
##
## ## What is different about the install in HERE
##
## Every other destiny suite INSTALLS the bridge and then asks whether a writer moves a
## counter. This suite never installs it to make an assertion true. It removes the bridge,
## mounts the REAL composition root, and asks whether the game put it back. Every
## `is_subscribed_to_fact_ledger()` assertion below is therefore about `game/src`, not
## about this suite's `setup()`.
##
## The mounted path is `SeamHarness`, the same one `tests/app/test_status_clock.gd` and
## `tests/app/test_item_workbench_app.gd` use: it parents the real
## `ItemWorkbenchApp.tscn` under the tree root and drives `_ready()` once, because the
## headless runner executes suites from `SceneTree._initialize()`, where the engine would
## never deliver `_ready()` on its own. **The app CAN be mounted headlessly, so this file
## makes no weaker claim than the mounted one.**

## Where the bridge is installed, read from source rather than restated, so the scan
## below cannot pass against a file that has moved.
const APP_SCRIPT := "res://src/app/item_workbench_app.gd"
const SRC_ROOT := "res://src"
## The install verb, as it is spelled in source. Assembled from fragments so this file's
## own text — which names it dozens of times in prose — cannot satisfy its own scan. The
## same trick `tests/arch_rules/test_fact_ledger_writers.gd` uses for `WorldFact.record`.
const CALL := "Destiny" + "Projection.subscribe_to_fact_ledger()"
## The fact a duel writes, read off the module that owns it rather than written out
## again. It maps to `duels_won`, the most heavily declared counter in the shipped fate
## tree, so a bridge that moved the wrong thing would show here.
const DUELS: StringName = CombatFacts.FACT_DUELS_WON
## The counter that fact names, read off the mapping table rather than restated.
const DUEL_COUNTER := &"duels_won"

## Whether the bridge was already installed when this test began. `true` here means a
## sibling suite leaked one, or this suite's own mount outran its `setup()`.
var _arrived_with_bridge: bool = false
## The subscriber count this test found. A DELTA, never `0`, for the reason the sibling
## suites' baseline comment gives: `WorldFact._subscribers` is a `static var`, so a
## sibling suite may legitimately hold a subscriber of its own while this file runs.
var _baseline_subscribers: int = 0
## A subscriber one test installs to watch notification, held so `teardown()` can release
## it before it measures the delta. Assigned in the test body rather than declared at the
## `var` line because the runner copies a suite's properties onto a second instance and a
## `Callable` stays bound to the instance it was created from.
var _listener: Callable = Callable()


## The bridge is NOT installed here. This suite's whole claim is that the game installs
## it, so a test that switched it on first would be proving its own setup.
##
## Only the identity this suite owns is removed — never `WorldFact.clear_subscribers()`,
## which is process-wide and would trade this suite's leak for the next suite's.
func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_baseline_subscribers = WorldFact.subscriber_count()
	_arrived_with_bridge = DestinyProjection.is_subscribed_to_fact_ledger()
	DestinyProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		false,
		(
			"this test begins with the bridge REMOVED, so the mount below is the only thing "
			+ "that can make the claim true: a suite that installed it in setup() would be "
			+ "proving itself"
		)
	)


## Leave the process exactly as this suite found it.
##
## The mounted scene goes FIRST. A harness left alive across the sibling destiny suites
## would carry a live composition root whose hero is already minted — and a cosmic
## `%StartScreen` sitting in the tree offering arrival, which a body minting case in a
## suite that walks that tree could pick up. Every harness-backed suite in `tests/app/`
## tears down in `teardown()` for the same reason; here it is what keeps this file a
## well-behaved neighbour rather than a leak with its own name.
##
## The watcher is released before the delta is measured, so a subscriber this suite
## installed for a case never counts as one this suite leaked.
##
## **All THREE bridges, not just destiny's.** The mounted composition root installs
## three subscribers into the one process-wide slot — `DestinyProjection` at
## item_workbench_app.gd:318, plus `QuestFactProjection` at :337 and
## `QuestArrivalProjection` at :349 — and this teardown used to unsubscribe only the
## first. That is why this suite reported a delta of 2 with NOTHING else in the
## process: it was measuring its own two, not a neighbour's. The slot is shared state
## and the subscriber set is not destiny's alone, so the teardown has to name every
## bridge it caused. Measured before the fix: `expected 0, got 2` even with this suite
## run ALONE, which is the evidence that ruled out a foreign leaker.
func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	if not _listener.is_null():
		WorldFact.unsubscribe(_listener)
		_listener = Callable()
	DestinyProjection.unsubscribe_from_fact_ledger()
	QuestFactProjection.unsubscribe_from_fact_ledger()
	QuestArrivalProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		WorldFact.subscriber_count(),
		_baseline_subscribers,
		(
			"the subscriber slot is back to the count this test found: the runner shares one "
			+ "process, and a bridge left installed moves counters for every suite that runs "
			+ "after this one, under none of their names"
		)
	)


# --- The composition root installs it -----------------------------------------


## THE case, and the one the audit says is missing. The bridge is absent, the real
## `ItemWorkbenchApp.tscn` is mounted and `_ready()` is driven once by `SeamHarness`, and
## `DestinyProjection.is_subscribed_to_fact_ledger()` is true when the mount returns.
##
## Nothing in this body can install it: `setup()` removed it and this test never calls the
## install verb. Delete `item_workbench_app.gd:208` and this is the assertion that goes
## red — see the next case, which pins the line, and the header for why no sibling suite
## would notice the deletion.
func test_the_mounted_composition_root_installs_the_bridge() -> void:
	var harness := _boot()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		(
			"the MOUNTED composition root installed the fact->counter bridge while booting: "
			+ "setup() had removed it and nothing here reinstalls it, so this is a claim about "
			+ "src/app/item_workbench_app.gd and not about this suite"
		)
	)
	# A mount that reported a boot error would leave the assertion above passing on a
	# harness that never finished, so the error is repeated here where the case names it.
	assert_eq(harness.boot_error, "", "and the mount really did finish its _ready()")


## The install surface of the SHIPPED TREE, read off real source with the comment half of
## every line stripped — so the twenty lines of prose above the call, which discuss it,
## are documentation and not an install site. Every `.gd` under `res://src` is walked, not
## just the composition root, because "exactly one place" is a claim about the tree.
##
## ## What this case can and cannot prove
##
## Mounting cannot tell WHICH line installed the bridge, and cannot tell a boot that
## installs it from a boot that merely inherited an earlier install. Reading the source
## can, and the two halves are asserted together: one call site, in the composition root,
## inside `_ready()` itself rather than inside a helper `_ready()` merely reaches.
func test_the_bridge_is_installed_from_exactly_one_place_in_the_shipped_tree() -> void:
	var sites := _install_sites()
	assert_eq(
		sites.size(),
		1,
		(
			(
				"exactly one line in res://src installs the bridge, and it is %s. A second site "
				+ "is a second install; zero means the bridge is installed by nothing at all."
			)
			% [str(sites)]
		)
	)
	if sites.is_empty():
		return
	var path := String((sites[0] as Dictionary)["path"])
	var line := int((sites[0] as Dictionary)["line"])
	assert_eq(
		path,
		APP_SCRIPT,
		(
			(
				"the install site is the composition root, not %s: core/ may not name destiny "
				+ "(tools arch holds LAYER_DEPS core to {core, contracts}), and no module may "
				+ "own a process-wide chokepoint that six other modules write through."
			)
			% [path]
		)
	)
	assert_eq(
		_enclosing_function(_source_lines(path), line - 1),
		"_ready",
		(
			(
				"and it runs in _ready() itself, not in a helper _ready() merely calls (line "
				+ "%d): a helper the root does not reach would leave the bridge uninstalled in "
				+ "the running game while the scan above still counted one site."
			)
			% [line]
		)
	)


# --- The install happens BEFORE anything can record ---------------------------


## The ordering the ADR's own comment calls the whole reason the install is "genuinely
## fixed", measured on the real `_ready()` rather than asserted in prose: the install
## line comes before both of the two paths that put a body into the world, and both of
## those reach the module install list that can write a fact.
##
## Reordering the line below `_build_actor()` would leave every other case in this file
## green — the bridge would still be installed by the end of the mount — and only this one
## red, which is the point of measuring the ORDER rather than the outcome.
func test_the_install_is_reached_before_the_root_can_record_anything() -> void:
	var body := _ready_body()
	assert_eq(body.size() > 0, true, "the composition root still has a _ready() to read")
	var install := _first_code_line(body, CALL)
	assert_eq(
		install > 0,
		true,
		"_ready() itself installs the bridge, at a line this case can compare against"
	)
	var restore := _first_code_line(body, "restore_actor()")
	var build := _first_code_line(body, "_build_actor()")
	# Both needles are asserted to EXIST before they are compared: a scan that found
	# neither would read as "the install came first" while having measured nothing.
	assert_eq(restore > 0, true, "_ready() still runs a restore path, so the order is measurable")
	assert_eq(build > 0, true, "_ready() still builds a fresh body, so the order is measurable")
	assert_eq(
		install < restore,
		true,
		(
			(
				"the bridge is installed at line %d of _ready(), BEFORE the restore path at "
				+ "line %d: a subscriber installed after a restore has already missed every "
				+ "fact that body carried."
			)
			% [install, restore]
		)
	)
	assert_eq(
		install < build,
		true,
		(
			(
				"and BEFORE the fresh-build path at line %d, which reaches the same module "
				+ "install list — so nothing the composer mounts can record into a hero whose "
				+ "counters were already missed."
			)
			% [build]
		)
	)


## The consequence of that ordering, measured through the PRODUCTION writer rather than
## through `WorldFact.record` itself: a duel recorded while nothing was subscribed moves
## no counter, and the SAME writer's duel after the game's install moves one — by one,
## not by two. The occurrence that was missed is gone for good, because the ledger is
## monotone and there is no going back for it (ADR 0065), which is precisely why the
## install has to happen before rather than merely eventually.
func test_a_fact_recorded_before_the_install_moves_nothing_and_one_after_it_does() -> void:
	var early := _hero(&"early")
	var first := CombatFacts.record_duel_won(early)
	assert_eq(bool(first.get("ok", false)), true, "a duel won before any boot was written down")
	assert_eq(WorldFact.count(early, DUELS), 1, "so the fact ledger holds that occurrence")
	assert_eq(
		_counter(early, DUEL_COUNTER),
		0,
		(
			"and it moved no counter: this ran with the bridge absent, exactly as a boot before "
			+ "the install would have"
		)
	)

	var harness := _boot()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		"the mounted composition root installed the bridge in between"
	)

	var second := CombatFacts.record_duel_won(early)
	assert_eq(bool(second.get("ok", false)), true, "a second duel was written down")
	assert_eq(WorldFact.count(early, DUELS), 2, "so the ledger holds both occurrences")
	assert_eq(
		_counter(early, DUEL_COUNTER),
		1,
		(
			"and EXACTLY ONE counter moved. Two would mean the bridge double-counted; zero "
			+ "would mean the install is dead; one says the earlier occurrence was missed "
			+ "permanently and only what came after the install was ever credited."
		)
	)

	var hero := harness.actor
	assert_ne(hero, null, "the mounted root built the hero its own counters belong to")
	assert_eq(
		bool(CombatFacts.record_duel_won(hero).get("ok", false)),
		true,
		"and a duel won by that hero is written by the same production writer"
	)
	assert_eq(
		_counter(hero, DUEL_COUNTER),
		1,
		(
			"so the bridge the GAME installed moves a counter for the game's own hero — "
			+ "installed and functional are two different claims, and this asserts both"
		)
	)


# --- A second boot cannot double the bridge -----------------------------------


## A SECOND boot of the same root must not install a second bridge.
##
## `WorldFact.subscribe` refuses a duplicate by identity, so the second `_ready()` runs the
## same line, the line is refused, and the slot holds exactly what the first boot left it
## holding. Every installed subscriber is walked once per recorded occurrence, so a
## double-install would double EVERY counter from that point on — irreversibly, because
## counters are monotonic and never refundable (ADR 0065), which is what makes this worth
## asserting at all.
##
## Asserted as a DELTA rather than an absolute count: the slot is process-wide and a
## sibling suite may legitimately hold a subscriber of its own while this runs.
func test_a_second_boot_of_the_root_installs_no_second_bridge() -> void:
	_boot()
	var held := WorldFact.subscriber_count()
	assert_eq(
		held > 0, true, "the first mount installed something, so a delta against it means something"
	)
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		"and what it installed is the bridge under test"
	)

	var second := _boot()
	assert_eq(second.boot_error, "", "the composition root boots a second time")

	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		"the second mount left the bridge installed rather than tearing it down"
	)
	assert_eq(
		WorldFact.subscriber_count(),
		held,
		(
			"the slot holds EXACTLY what the first boot held: subscribe() refuses a duplicate "
			+ "by identity, so a second boot of the root cannot double every counter from here on"
		)
	)


# --- A refused write notifies nobody ------------------------------------------


## ADR 0148/0149's fourth bullet: "the hook fires only on `ok: true`", so a write the
## ledger refused moves no counter and cannot lower one.
##
## ## Why this one body installs the bridge itself, when no other body here does
##
## The claim is about the CHAIN — a refusal must not become a counter movement — and the
## chain only exists once something is subscribed. So this body installs the bridge the
## way `item_workbench_app.gd:208` does, by calling the same public verb, and proves it
## is live first. The claim stays honest in both directions: with the bridge live, a
## refusal that moved a counter would fail here, while every case above still proves that
## nothing BUT the game installs it.
##
## `expect_assertions` is declared because this is the one body in the file that does not
## begin from a mounted app, and a floor is what stops a body that died on its first line
## from being reported as one that passed.
func test_a_refused_write_notifies_nobody_and_moves_no_counter() -> void:
	expect_assertions(19)
	DestinyProjection.subscribe_to_fact_ledger()
	var actor := _hero(&"refused")
	var heard: Array[StringName] = []
	_listener = _listen(heard)
	assert_eq(WorldFact.subscribe(_listener), true, "this body's own watcher is installed")
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		"and the bridge it installed on purpose is live, so the refusals below face a real chain"
	)
	assert_eq(_counter(actor, DUEL_COUNTER), 0, "a fresh body has moved no counter")

	assert_eq(WorldFact.record(actor, DUELS, 0)["reason"], "non_positive", "a zero is refused")
	assert_eq(WorldFact.record(actor, DUELS, -3)["reason"], "non_positive", "and so is a negative")
	assert_eq(WorldFact.record(null, DUELS)["reason"], "no_actor", "and so is a null actor")
	assert_eq(WorldFact.record(actor, &"")["reason"], "empty_id", "and so is an empty id")
	assert_eq(_counter(actor, DUEL_COUNTER), 0, "not one of the four refusals moved a counter")
	assert_eq(heard.size(), 0, "and NO subscriber was called: not the bridge, not this watcher")

	assert_eq(WorldFact.record(actor, DUELS, 2)["ok"], true, "an accepted write still lands")
	assert_eq(_counter(actor, DUEL_COUNTER), 2, "and it moves the counter by its own amount")
	assert_eq(heard.size(), 1, "one occurrence, one notification")

	# The refusals must also fail to UNWIND, which is what makes them safe rather than
	# merely quiet. Asserted after the accepted write, so "nothing moved" cannot be read
	# as "there was nothing there to move".
	assert_eq(
		WorldFact.record(actor, DUELS, -1)["reason"], "non_positive", "a negative is still refused"
	)
	assert_eq(_counter(actor, DUEL_COUNTER), 2, "so the earned counter is not unwound")
	assert_eq(heard.size(), 1, "and a refusal still notifies nobody")

	assert_eq(_counter(_hero(&"other"), DUEL_COUNTER), 0, "no other body moved either")
	assert_eq(_counter(actor, &"enemies_spared"), 0, "no counter a refused write names moved")
	assert_eq(WorldFact.count(actor, DUELS), 2, "and the ledger holds only the accepted write")
	assert_eq(
		heard.size(),
		1,
		(
			"one notification for the one accepted occurrence and none for the four refusals: "
			+ "the hook fires only on ok: true, so a refused claim can neither grant nor revoke"
		)
	)


## The four refusals are a property of the LEDGER's own writer, not of this file's taste:
## every reason string comes back out of `WorldFact.record` itself, each naming the guard
## that fired, and none of them is asserted as a literal this suite invented.
func test_the_refusal_reasons_come_from_the_writer_and_not_from_this_suite() -> void:
	var actor := _hero(&"reasons")
	var refused: Array[String] = [
		String(WorldFact.record(null, DUELS)["reason"]),
		String(WorldFact.record(actor, &"")["reason"]),
		String(WorldFact.record(actor, DUELS, 0)["reason"]),
		String(WorldFact.record(actor, DUELS, -1)["reason"]),
	]
	assert_eq(
		refused,
		["no_actor", "empty_id", "non_positive", "non_positive"],
		(
			"all four came back refused, each naming its own guard in core/world_fact.gd — so "
			+ "the chain above is measuring core's rule rather than a local one"
		)
	)
	assert_eq(WorldFact.count(actor, DUELS), 0, "and none of them wrote a row")
	assert_eq(_counter(actor, DUEL_COUNTER), 0, "so none of them moved a counter")


# --- Fixtures and readers -----------------------------------------------------


## The real composition root, mounted and booted. A boot error is asserted HERE rather
## than returned silently, so a mount that failed fails this case by name instead of
## leaving the next assertion reading a null harness as a result.
##
## Nothing is torn down inside this helper: `SeamHarness.mount_new()` releases whatever
## the previous mount left, and `teardown()` releases this one, which is the only place
## this suite is allowed to change the tree.
func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## The value of one fate counter, read off the ledger `DestinyApi.state` publishes.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


## A body with a destiny ledger attached, so a counter has somewhere to land.
func _hero(id: StringName) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


## A watcher that records which fact ids reached a subscriber, so "notified nobody" is
## measured rather than inferred from a counter that had nothing to move anyway.
## Returned rather than declared at the `var` line for the reason on that field, and
## held by the caller so `teardown()` can release it by identity.
func _listen(heard: Array[StringName]) -> Callable:
	return func(_actor: Actor, fact_id: StringName, _amount: int) -> void: heard.append(fact_id)


## Every line of CODE under `res://src` that calls the install verb, as
## `{"path": String, "line": int}`. The whole tree is walked rather than the composition
## root alone, because "exactly one place" is a claim about the tree and a scan of one
## file could not support it. Comment halves are stripped first, so prose that names the
## verb is documentation and not an install site.
func _install_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in _gdscript_files(SRC_ROOT):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			if String(lines[index]).split("#")[0].contains(CALL):
				out.append({"path": path, "line": index + 1})
	return out


## `_ready()`'s body as lines, from the line after its declaration to the next top-level
## `func`. Empty when the composition root no longer has one, which the caller asserts
## rather than working around.
func _ready_body() -> Array[String]:
	var lines := _source_lines(APP_SCRIPT)
	var start := -1
	for index in lines.size():
		if String(lines[index]).strip_edges().begins_with("func _ready("):
			start = index
			break
	if start < 0:
		return []
	var body: Array[String] = []
	for index in range(start + 1, lines.size()):
		if String(lines[index]).begins_with("func "):
			break
		body.append(String(lines[index]))
	return body


## The 1-based position WITHIN `body` of the first line of code naming `needle`, or -1.
## The position is a comparison coordinate rather than a line number: two needles looked
## up in the same `body` are comparable to each other, which is the only comparison the
## ordering case makes.
func _first_code_line(body: Array[String], needle: String) -> int:
	for index in body.size():
		if body[index].split("#")[0].contains(needle):
			return index + 1
	return -1


## The name of the function a line sits inside, or "" when it sits outside every one.
## Scanned backwards to the nearest top-level `func`, which is what separates "the root
## installs the bridge" from "the root reaches a helper that installs it".
func _enclosing_function(lines: Array[String], line_index: int) -> String:
	for index in range(mini(line_index, lines.size() - 1), -1, -1):
		var line := String(lines[index])
		if not line.begins_with("func "):
			continue
		return line.substr(5, line.find("(") - 5)
	return ""


## One file's lines as an array of strings.
func _source_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out.append(String(line))
	return out


## Every `.gd` under `root`, recursively.
##
## The `while` over `DirAccess` is the one shape `tests/arch_rules/test_no_unbounded_wait.gd`
## accepts as terminating, and the collected list is walked with a `for` above it.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
