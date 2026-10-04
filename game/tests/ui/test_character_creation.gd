extends TestCase

## Character creation, and DEF-0109.
##
## ## What this suite has to prove, and what it must NOT
##
## It proves the player answers a QUESTION and the creation layer grants one
## origin destiny exactly once — and it proves that doing so permanently closes the
## other two, by asking `DestinyApi` rather than by re-deriving the `group` rule.
## The rule has exactly one home (`DestinyGate.earnable`); a test that reimplements
## it proves nothing but that the test agrees with itself.
##
## It also proves the negative ADR 0065 demands: there is no fate picker. That is a
## structural assertion over the shipped source, not a behavioural one, because the
## defect being guarded is a control that grants an unearned fate and a control is
## not something a behavioural test can see.

const SCREEN := "res://src/ui/screens/character_creation.tscn"
const ROW_SCENE := "res://src/ui/panels/creation_branch_row.gd"
const SCREEN_SOURCE := "res://src/ui/screens/character_creation.gd"
const FLOW_SOURCE := "res://src/app/character_creation_flow.gd"
const CODEX_SOURCE := "res://src/ui/screens/destiny_screen.gd"

## The three arrivals, spelled once. Every assertion about "the other two" reads
## this list rather than restating an id, so a fourth arrival cannot leave a stale
## pair behind.
const ORIGINS := [
	"the_one_who_stayed",
	"the_one_who_returned",
	"the_chosen_instrument",
]

## Every screen node this suite instantiates, freed in `teardown()` so one test's
## tree cannot become the next test's. The runner shares one process across every
## suite, so a leak here is a leak everywhere.
var _instantiated: Array = []


## Whether Godot can actually open `path` from inside a test.
##
## ## Why these assertions are placed HERE and not in the source-read guards
##
## The structural guards below read shipped source and assert it is non-empty. That
## reads a plain FILE on disk, and it is true or false the moment the test runs —
## which makes it useless as a guard against the one thing it looks like it guards.
## A `class_name` that resolves is a property of Godot's SCRIPT CLASS CACHE, which a
## headless `--import` rebuilds: a screen that fails to compile resolves as `null`
## here, every node path inside it is unreachable, the scene instantiates with no
## children, and then `summary()` is `{}` because there was never a header to bind,
## not because the commit refused.
##
## So the guards now ask two questions at the one moment the cache is loaded and
## live: can the type be RESOLVED, and can the SCENE really mount its own nodes? A
## real defect (a broken script, a renamed node, a missing `%ConfirmButton`) fails
## HERE, by name, in the test that owns the screen — instead of surfacing four
## frames later as `asked == 0` or "a committed arrival is reported", which read like
## gameplay bugs and sent the last two agents into the creation flow to fix code
## that was already correct.
##
## Kept as an assertion about the FILE's readability too: an empty read is the other
## way this can go wrong, and it is cheap to say so.
func _resolvable_type(type_path: String, label: String) -> bool:
	# The assertion is on RESOLUTION, never on the file being non-empty.
	# `FileAccess.get_file_as_string` on a `res://src` path answers "" whenever the
	# import cache has not yet resolved that path, which in a shared headless
	# process is a normal transient — and it made three agents go looking for a
	# readability bug in files that were on disk and correct. `load()` failing is
	# the real signal: a script that does not compile, or whose `class_name` does
	# not resolve, is exactly what this is meant to catch.
	var script := load(type_path) as GDScript
	if script == null:
		assert_eq(false, true, "%s source loads as a GDScript" % label)
		return false
	if not bool(script.can_instantiate()):
		assert_eq(false, true, "%s compiles and resolves its class_name" % label)
		return false
	var instance = script.new()
	if instance == null:
		assert_eq(false, true, "%s instantiates" % label)
		return false
	instance.free()
	return true


## This screen's nodes really exist once mounted. A scene whose script failed to
## compile mounts as an empty node and every path under it reads `null`, which is
## the difference between "the commit refused" and "there is no screen".
func _screen_mounts(screen: CharacterCreation) -> bool:
	assert_ne(
		screen.get_node_or_null("Layout/Scroll/Arrivals/Branches") as VBoxContainer,
		null,
		"the creation screen mounts its branch container"
	)
	assert_ne(
		screen.get_node_or_null("%CreationHeader") as Label,
		null,
		"and its header, so the screen actually bound"
	)
	var rows := screen.get_node_or_null("Layout/Scroll/Arrivals/Branches") as VBoxContainer
	if rows == null:
		# Assert, then return: `assert_eq` is void (see `_resolvable_type`).
		assert_eq(false, true, "the screen mounted its rows")
		return false
	assert_eq(rows.get_child_count(), 3, "one row per arrival, mounted for real")
	return true


func setup() -> void:
	_instantiated = []


## Everything this suite instantiated, released.
##
## `free()`, never `queue_free()`: the headless runner executes inside
## `SceneTree._initialize()`, where the deferred path never drains, so a queued free
## is a node that outlives the run.
func teardown() -> void:
	for node in _instantiated:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.free()
	_instantiated = []


# --- The candidates ---------------------------------------------------------


func test_three_origins_are_offered_each_with_the_real_gate_answer() -> void:
	var listed := CharacterCreationFlow.new().candidates()
	assert_eq(listed.size(), ORIGINS.size(), "the three ways of arriving are offered")
	var seen: Array = []
	var published: Array = []
	for entry in listed:
		var view: Dictionary = entry
		var id := String(view.get("id", ""))
		seen.append(id)
		published.append(id)
		assert_eq(ORIGINS.has(id), true, "%s is one of the origin group" % id)
		assert_ne(String(view.get("display_name", "")), "", "%s is named" % id)
		assert_ne(String(view.get("description", "")), "", "%s describes itself" % id)
		assert_ne(String(view.get("bearing", "")), "", "%s says what it makes you" % id)
		# `available` and `unmet` must be PRESENT, not merely equal to something:
		# a missing key and a false key read the same to a caller that ignores it.
		assert_eq(view.has("available"), true, "%s publishes availability" % id)
		assert_eq(view.has("unmet"), true, "%s publishes what is unmet" % id)
		assert_eq(
			(view.get("unmet", []) as Array).is_empty(),
			bool(view.get("available", false)),
			"%s: available and unmet are the same answer, read off one gate" % id
		)
		# ## Why this compares as a SET, and why the flow was NOT re-sorted
		#
		# Two orders exist. `ORIGINS` is the order an author writes three arrivals
		# down in (`game/data/destiny/destinies/`); the list read above is
		# `FateCatalog.destinies_in_group`, a CATALOG order by STRING value, chosen
		# deliberately so a codex cannot reorder between two reads. They answer
		# different questions - one is narrative, the other determinism - so
		# asserting they agree asserts two unrelated truths happen to line up, and
		# breaks the day an author renames a file.
		#
		# So both sides are sorted here and the flow keeps the catalog's order.
		# `candidates()` already iterates `DestinyApi.summary`'s `destinies`
		# dictionary and then sorts BY ID, which is the same permutation
		# `destinies_in_group` produces; a second narrative sort on top would be
		# redundant with the determinism rule already in force, and would make this
		# test pass only while the author's list happened to match a string sort.
		# Narrative order is therefore not something any code path in this slice
		# may re-sort toward - see `CharacterCreationFlow.origin_ids`.
		#
		# A set assertion leaves ORDER untested, so order is asserted below against
		# its own source twice: the published list EQUALS the catalog's own order,
		# and two reads of `candidates()` are identical.
		seen.sort()
	var authored := ORIGINS.duplicate()
	authored.sort()
	assert_eq(seen, authored, "and they are exactly the origin group, as a SET")
	var from_catalog := []
	for origin_id in CharacterCreationFlow.new().origin_ids():
		from_catalog.append(String(origin_id))
	assert_eq(
		published,
		from_catalog,
		"and they are published in the catalog's own order, not a second convention"
	)
	var reread := []
	for entry in CharacterCreationFlow.new().candidates():
		reread.append(String((entry as Dictionary).get("id", "")))
	assert_eq(reread, published, "which does not reorder between two reads")


## A base hero with nothing earned, for asking the gate a question a player can
## still answer. `RefCounted`, so there is nothing to free.
func _hero() -> Actor:
	var hero := ActorFactory.build(&"probe")
	DestinyApi.attach(hero)
	return hero


## Every origin is open to a hero who has earned nothing — and the reason is
## asserted, not assumed: the one that looks closed is closed ONLY because
## creation brings its own prerequisite with it.
func test_the_chosen_instrument_is_open_only_because_creation_brings_the_fate() -> void:
	var by_id := {}
	for entry in CharacterCreationFlow.new().candidates():
		by_id[String((entry as Dictionary).get("id", ""))] = entry as Dictionary
	var instrument: Dictionary = by_id["the_chosen_instrument"]
	assert_eq(
		bool(instrument.get("available", false)),
		true,
		"the chosen instrument is openable, so it is not another unreachable origin"
	)
	assert_eq(
		(instrument.get("arrival_fates", []) as Array).has("reborn_in_a_lesser_vessel"),
		true,
		"and it says which fate its own arrival supplies"
	)
	var gate := DestinyApi.gate(_hero(), {"verb": &"has_fate", "id": &"reborn_in_a_lesser_vessel"})
	assert_eq(
		bool(gate.get("ok", false)),
		false,
		"the module's own gate still refuses the destiny for a bare hero, unchanged"
	)


# --- Committing -------------------------------------------------------------


func test_committing_grants_exactly_that_destiny_once() -> void:
	var flow := CharacterCreationFlow.new()
	var created := flow.build(&"the_one_who_stayed")
	assert_eq(
		bool(created.get("ok", false)), true, "an arrival commits: %s" % created.get("reason", "")
	)
	var hero := created.get("actor", null) as Actor
	assert_ne(hero, null, "and it built a hero")
	var held := DestinyApi.destinies(hero)
	assert_eq(held.size(), 1, "exactly one destiny is held")
	assert_eq(String(held[0]), "the_one_who_stayed", "and it is the one that was answered")


## Twice means twice, and neither time is a second grant.
##
## ADR 0061's precedent: a reward is decided in one place and that place refuses the
## second decision. Both shapes are checked because they are two different guards —
## `build()` refuses a second HERO (`already_created`), and `grant_origin()` refuses
## a second EARN on the same hero (`already_earned`). Testing only the first would
## leave the second one unguarded, and a flow whose two guards were the same rule
## would pass.
func test_a_second_commit_grants_nothing() -> void:
	var flow := CharacterCreationFlow.new()
	var first := flow.build(&"the_one_who_returned")
	assert_eq(bool(first.get("ok", false)), true, "the first arrival commits")
	var again := flow.build(&"the_one_who_stayed")
	assert_eq(bool(again.get("ok", false)), false, "a second arrival is refused")
	assert_eq(String(again.get("reason", "")), "already_created", "and it names why")
	var hero := first.get("actor", null) as Actor
	var fates_before := DestinyApi.fates(hero).size()
	var regrant := flow.grant_origin(hero, &"the_one_who_returned")
	assert_eq(String(regrant.get("reason", "")), "already_earned", "the regrant says so")
	assert_eq(DestinyApi.destinies(hero).size(), 1, "and no second destiny appeared")
	assert_eq(DestinyApi.fates(hero).size(), fates_before, "nor a second fate")


## The exclusivity rule is the MODULE's, so the assertion reads the module's own
## verdict. Asking `DestinyApi.gate` for `has_destiny` on the two closed arrivals
## is the honest form: it cannot tell us the rule, only report its outcome.
func test_committing_one_origin_permanently_closes_the_other_two() -> void:
	var flow := CharacterCreationFlow.new()
	var created := flow.build(&"the_one_who_stayed")
	var hero := created.get("actor", null) as Actor
	var closed := 0
	for origin_id in ORIGINS:
		if origin_id == "the_one_who_stayed":
			continue
		closed += 1
		var refused := flow.grant_origin(hero, StringName(origin_id))
		assert_eq(
			bool(refused.get("ok", false)),
			false,
			"%s is refused after an origin was earned" % origin_id
		)
		assert_eq(
			String(refused.get("reason", "")),
			"gate_unmet",
			"%s is refused BY THE GATE, not by a rule this flow invented" % origin_id
		)
		assert_ne(
			(refused.get("unmet", []) as Array).is_empty(),
			true,
			"%s carries the gate's own reason" % origin_id
		)
	assert_eq(closed, 2, "two arrivals were closed")
	assert_eq(DestinyApi.destinies(hero).size(), 1, "and the hero still holds exactly one")


## The flow must not answer its own availability question. This asserts the
## exclusivity set is still the catalog's after a commit, which is the same fact
## from the other side: if this flow had hand-closed the two arrivals locally, the
## catalog would not know about it.
func test_the_closure_is_the_catalogs_not_a_local_list() -> void:
	var flow := CharacterCreationFlow.new()
	var created := flow.build(&"the_one_who_stayed")
	var hero := created.get("actor", null) as Actor
	var group := FateCatalog.instance().destinies_in_group(CharacterCreationFlow.ORIGIN_GROUP)
	assert_eq(group.size(), ORIGINS.size(), "the group still has three members on disk")
	var open := 0
	for origin_id in group:
		if StringName(origin_id) == &"the_one_who_stayed":
			continue
		open += 1
	assert_eq(open, 2, "two members remain in the group — only the LEDGER closed them")
	assert_eq(
		(DestinyApi.summary(hero).get("destinies", {}) as Dictionary).size() > 0,
		true,
		"and the codex still reports every member, closed or not"
	)


# --- Three different heroes -------------------------------------------------


## THE assertion this whole feature exists for: three arrivals, three heroes.
## Compared as a shape rather than as three separate truths, so a change that
## collapses two of them into one hero fails with the whole difference named.
func test_the_three_origins_produce_materially_different_heroes() -> void:
	var shapes := {}
	for origin_id in ORIGINS:
		var created := CharacterCreationFlow.new().build(StringName(origin_id))
		assert_eq(
			bool(created.get("ok", false)),
			true,
			"%s commits: %s" % [origin_id, created.get("reason", "")]
		)
		shapes[origin_id] = _shape(created)
	assert_eq(shapes.size(), 3, "three arrivals were each committed once")
	var races := {}
	var bases := {}
	var paths := {}
	for origin_id in ORIGINS:
		var shape: Dictionary = shapes[origin_id]
		races[origin_id] = String(shape.get("race", ""))
		bases[origin_id] = String(shape.get("base_attributes", ""))
		paths[origin_id] = String(shape.get("open_paths", ""))
	assert_eq(_distinct_values(races), 3, "each arrival arrives in a DIFFERENT body")
	assert_eq(_distinct_values(bases), 3, "each hero's base stats DIFFER")
	assert_eq(_distinct_values(paths), 3, "each hero's enrolled paths DIFFER")
	# ## Why a COUNT is not enough, and what "materially different" actually means
	#
	# Distinct base attributes and distinct race ids both passed while two of the
	# three heroes enrolled on the SAME cultivation paths — emberblood and stoneborn
	# both close `mind_cultivation`, so they read as identical to every gate the
	# breakthrough seam consults (ADR 0109). A count hides that: the colliding pair
	# still leaves three distinct strings somewhere in the list, one of which is the
	# third origin doing all the work.
	#
	# So what is asserted is that no two arrivals land in bodies closing the same
	# path. That is the property ADR 0062/0109 is actually about — a body plan gates
	# the breakthrough it forbids, so two bodies that forbid the same thing are the
	# same character to the gate, whatever their stats say. Read from the flow's own
	# table so the pair that differs cannot drift away from the arrivals themselves.
	var closed_by_origin := {}
	for origin_id in ORIGINS:
		var created := CharacterCreationFlow.new().build(StringName(origin_id))
		closed_by_origin[origin_id] = ("|".join(created.get("closed_paths", []) as Array))
	var closed_seen: Array = []
	for origin_id in ORIGINS:
		var closed_for := String(closed_by_origin[origin_id])
		assert_eq(
			closed_seen.has(closed_for),
			false,
			"%s must not close exactly what another origin closes (ADR 0109)" % origin_id
		)
		closed_seen.append(closed_for)


func test_the_race_gates_a_path_it_forbids() -> void:
	var created := CharacterCreationFlow.new().build(&"the_one_who_returned")
	var hero := created.get("actor", null) as Actor
	# Tidecaller closes the body path (ADR 0062), so the hero is not on it and the
	# facade says the body is closed — the same answer the breakthrough reads.
	assert_eq(RaceApi.can_take_path(hero, PathState.BODY), false, "a tidecaller cannot body")
	assert_eq(hero.path(PathState.BODY), null, "so creation did not enrol it")
	assert_eq(RaceApi.can_take_path(hero, PathState.MIND), true, "and it can mind")
	assert_eq(hero.path(PathState.MIND) != null, true, "so creation enrolled that")


func test_base_stats_come_from_the_race_not_a_literal() -> void:
	var created := CharacterCreationFlow.new().build(&"the_one_who_stayed")
	var hero := created.get("actor", null) as Actor
	var def := RaceApi.race_definition(hero)
	assert_ne(def, null, "the hero has an authored race")
	# Built with NO base stats, so every number on it came from the race's own
	# `base_attributes` through `RaceApi.set_race`. A literal in the flow would
	# make this differ.
	for attribute in def.base_attributes.keys():
		assert_eq(
			hero.stats.get_base(StringName(attribute)),
			float(def.base_attributes[attribute]),
			"%s is the race's own number" % String(attribute)
		)
	assert_eq(
		hero.stats.get_base(Stat.PHYSIQUE),
		4.0,
		"a stoneborn arrives with the physique its body plan grants"
	)


# --- Refusals ----------------------------------------------------------------


## Two refusals, both named, neither minting a hero.
##
## The second case is the load-bearing one: `the_oath_bound` is a real authored
## destiny that this layer does not create, because it has no body to arrive in. It
## is refused as `unknown_origin` rather than granted with no race, because a
## raceless hero is precisely the defect ADR 0078 recorded and this layer exists to
## close it.
func test_an_id_with_no_arrival_is_refused_rather_than_minted_raceless() -> void:
	for choice in [&"no_such_arrival", &"the_oath_bound", &""]:
		var created := CharacterCreationFlow.new().build(choice as StringName)
		assert_eq(bool(created.get("ok", false)), false, "'%s' does not commit" % String(choice))
		assert_eq(
			String(created.get("reason", "")),
			"unknown_origin",
			"'%s' is refused by name" % String(choice)
		)
		assert_eq(created.has("actor"), false, "and no hero is minted for '%s'" % String(choice))


# --- The screen --------------------------------------------------------------


## One screen, wired the way the composition root wires it.
##
## `ui/` may not reference `app/` (`PRIVATE_UNITS`), so this screen cannot name
## `CharacterCreationFlow` — it takes the arrivals and the commit callable as
## arguments, exactly as `ItemWorkbenchApp._loot_bridge()` supplies the loot
## screen's. The test plays the composition root for the same reason: it is the only
## legitimate caller of that seam, and a test that reached past it would be
## asserting something no player can do.
func _screen() -> CharacterCreation:
	var screen := (load(SCREEN) as PackedScene).instantiate() as CharacterCreation
	_instantiated.append(screen)
	# The scene is mounted and its own nodes exist BEFORE any assertion about what it
	# reports. Without this, a screen that failed to compile — a stale class cache
	# after someone else edited one of its neighbours — instantiates as an empty node,
	# `_bind_nodes` finds no header, `bind_creation` renders nothing, and every later
	# assertion in this file fails as though the creation layer had refused.
	assert_eq(_screen_mounts(screen), true, "the screen mounted for real")
	screen.bind_creation(CharacterCreationFlow.new().candidates(), _commit)
	return screen


## The composition root's half of the seam. One fresh flow per press, which is what
## makes the screen's once-guard the FLOW's once-guard rather than a second copy.
func _commit(origin_id: StringName) -> Dictionary:
	return CharacterCreationFlow.new().build(origin_id)


func test_summary_is_primitives_only_and_empty_with_no_hero() -> void:
	var screen := _screen()
	# `{}` with no actor is the contract every screen here keeps (ADR 0038), and on
	# this screen it is literal: a hero does not exist until the player answers.
	assert_eq(screen.summary(), {}, "empty with no hero, not a form full of options")
	screen.refresh_candidates()
	assert_eq(screen.summary(), {}, "and still empty after the rows are fed")


func test_summary_is_primitives_only_after_a_commit() -> void:
	var screen := _screen()
	screen.refresh_candidates()
	# The verdict is asserted FIRST and verbatim. `summary()` is four frames from the
	# thing that can actually go wrong, so an empty summary on its own named nothing —
	# it could have been a refusal from the creation layer, a dead seam, or a screen
	# that never bound. Reading the layer's own answer puts the reason in the failure
	# message instead of leaving it to be guessed at.
	var outcome := screen.act_commit(&"the_one_who_stayed")
	assert_eq(
		bool(outcome.get("ok", false)),
		true,
		"the arrival commits: %s" % String(outcome.get("reason", ""))
	)
	assert_eq(String(outcome.get("choice", "")), "the_one_who_stayed", "and it is the answered one")
	var view := screen.summary()
	# ## Why this is `assert_ne(..., true)` and not `assert_ne(..., false)`
	#
	# `assert_ne(actual, unexpected)` fails when the two are EQUAL, so the second
	# argument is the value this must NOT be. `assert_ne(view.is_empty(), false)`
	# therefore demanded `view.is_empty() == true` — it asserted the summary was
	# EMPTY, the exact opposite of its own label, and it failed on a screen that had
	# correctly reported the committed arrival. The failure line said "expected not
	# false, got false", which reads like an empty summary only if you assume the
	# author had the argument order right; `framework.gd` writes the ACTUAL value out
	# as `got`, so `got false` here means the view was NOT empty and the assertion was
	# the thing that was wrong. `true` is the value "is empty" must not be.
	assert_ne(view.is_empty(), true, "a committed arrival is reported")
	assert_eq(String(view.get("committed_origin", "")), "the_one_who_stayed", "the answer is named")
	assert_eq(String(view.get("race", "")), "stoneborn", "and the body it arrived in")
	for entry in view.get("branches", []) as Array:
		_assert_primitive_tree(entry, "a branch row")


## The screen is not a second once-guard. It delegates, and the flow decides: a
## second press reaches the creation layer, which mints a hero and closes the other
## two on ITS OWN fresh ledger. So the honest assertion is about the FIRST press
## being the one this screen reports — the screen has no state that could let it
## answer a second time without asking.
func test_the_screen_asks_the_creation_layer_rather_than_deciding() -> void:
	var screen := _screen()
	# An Array, not an int, because a GDScript lambda captures by VALUE: `asked`
	# inside the closure would increment a COPY and the assertion below would read 0
	# forever, which reads exactly like "the press never reached the layer".
	var asked: Array[int] = [0]
	screen.bind_creation(
		CharacterCreationFlow.new().candidates(),
		func(origin_id: StringName) -> Dictionary:
			asked[0] += 1
			return CharacterCreationFlow.new().build(origin_id)
	)
	screen.act_commit(&"the_one_who_returned")
	assert_eq(asked[0], 1, "the press reached the creation layer")
	var first := screen.committed_origin()
	screen.act_commit(&"the_one_who_returned")
	assert_eq(asked[0], 2, "a second press asks again rather than answering locally")
	assert_eq(first, "the_one_who_returned", "and the screen reports what the layer granted")


## A screen with no seam refuses rather than quietly doing nothing, which is the
## gate ADR 0038 asks for: a refusal with a name instead of a dead control.
func test_a_screen_with_no_creation_seam_refuses_by_name() -> void:
	var screen := (load(SCREEN) as PackedScene).instantiate() as CharacterCreation
	_instantiated.append(screen)
	var outcome := screen.act_commit(&"the_one_who_stayed")
	assert_eq(bool(outcome.get("ok", false)), false, "no seam means nothing commits")
	assert_eq(String(outcome.get("reason", "")), "no_creation_seam", "and it says so by name")
	assert_eq(screen.summary(), {}, "and no hero was invented")


func test_the_rows_show_the_body_and_the_paths_it_closes() -> void:
	var screen := _screen()
	screen.refresh_candidates()
	# The screen's own summary is `{}` without a hero, so the rows are asked
	# DIRECTLY here — which is the point: the rows are fully readable before any
	# hero exists, because the answer is what the player is reading FOR.
	var branch := screen.get_node_or_null("Layout/Scroll/Arrivals/Branches/Branch0")
	assert_ne(branch, null, "the first row is mounted")
	var view: Dictionary = (branch as CreationBranchRow).summary()
	assert_eq(ORIGINS.has(String(view.get("id", ""))), true, "and it is an arrival")
	assert_ne(String(view.get("race_name", "")), "", "the row names the body")
	# The paths a body CLOSES are read from that body's own `RaceDef`, so this is
	# the body's truth rather than a re-derivation of it. The hero is built for
	# THIS row's origin and asked, which means the assertion follows the CONTENT:
	# the row whose body closes nothing passes with an empty list, instead of the
	# test hard-coding which arrival that happens to be - which broke the moment the
	# row order changed.
	var origin_id := StringName(String(view.get("id", "")))
	var built := CharacterCreationFlow.new().build(origin_id)
	assert_eq(
		bool(built.get("ok", false)), true, "the arrival builds: %s" % String(view.get("id", ""))
	)
	var hero := built.get("actor", null) as Actor
	assert_ne(hero, null, "and mints a hero to ask")
	var def := RaceApi.race_definition(hero)
	assert_ne(def, null, "whose body is authored")
	var closed: Array = []
	for path_id in (def as RaceDef).closed_paths:
		closed.append(String(path_id))
	closed.sort()
	var reported: Array = (view.get("closed_paths", []) as Array).duplicate()
	reported.sort()
	assert_eq(
		reported,
		closed,
		"%s reports the paths its %s body closes" % [origin_id, String(view.get("race_name", ""))]
	)
	# And the row says so in prose, whatever the answer is: a body that closes
	# nothing must not claim it "cannot cultivate" anything.
	var paths_line := String(view.get("paths_line", ""))
	if closed.is_empty():
		assert_eq(
			paths_line.contains("cannot cultivate"),
			false,
			"%s closes nothing, so its line must not forbid" % origin_id
		)
	else:
		assert_eq(
			paths_line.contains("cannot cultivate"), true, "%s names what it forbids" % origin_id
		)


func test_the_confirm_button_commits_through_the_flow() -> void:
	var screen := _screen()
	screen.refresh_candidates()
	# The press, not a direct `call()`: a row's button is the only control on this
	# screen, and a control that only works when a test names its handler is not a
	# control.
	var pressed := false
	for child in screen.get_node("Layout/Scroll/Arrivals/Branches").get_children():
		var row := child as CreationBranchRow
		if row == null or not row.can_commit():
			continue
		row.get_node("%ChooseButton").pressed.emit()
		pressed = not screen.committed_origin().is_empty()
		break
	assert_eq(pressed, true, "pressing a row's own button commits an arrival")
	assert_ne(screen.summary(), {}, "and the screen then reports the hero it built")


## ADR 0065's structural guard. A fate picker is a control that grants an unearned
## fate; a behavioural test cannot see a control that does not exist, so this reads
## the shipped source instead.
##
## The search runs over CODE, never over the file as written: both the screen and
## the flow DOCSTRING the very verbs they must not call, in order to state that
## they do not. Searching the raw text would fail on the prose documenting the
## rule, which is the opposite of what this guard is for.
func test_no_fate_picker_exists_anywhere_on_the_creation_screen() -> void:
	# Resolvable TYPE and mounted SCENE, not "the file is not empty" — see
	# [method _resolvable_type] for why the cache, not the file, is what fails here.
	assert_eq(_resolvable_type(SCREEN_SOURCE, "the creation screen"), true, "the screen compiles")
	assert_eq(_resolvable_type(ROW_SCENE, "its row"), true, "and the row compiles")
	var source := _code_only(SCREEN_SOURCE)
	var row_source := _code_only(ROW_SCENE)
	for verb in ["earn_fate", "earn_destiny", "fate_definition", "fate_ids"]:
		assert_eq(
			source.contains(verb),
			false,
			"the screen never calls %s: a screen grants nothing (ADR 0065)" % verb
		)
		assert_eq(
			row_source.contains(verb),
			false,
			"nor does its row call %s: a row emits a request and nothing more" % verb
		)
	# The one earn in the whole feature lives in the creation layer, and this pins
	# that there is exactly one of them rather than a second copy somewhere.
	var flow_source := _code_only(FLOW_SOURCE)
	assert_eq(
		flow_source.count("earn_destiny"),
		1,
		"exactly one earn_destiny call, and it is in the creation layer"
	)
	assert_eq(
		flow_source.contains("earn_destiny(actor, choice_id, SOURCE)"),
		true,
		"and it is the DEF-0109 call, with the source naming the moment"
	)


## The codex must still be a codex. Adding a commit button to the read-only screen
## would be the same picker wearing a different screen's clothes.
func test_the_codex_gained_no_commit_verb() -> void:
	# Resolvable type, not "the file is not empty" — same reason as the creation
	# screen guard above, and the codex is the more fragile of the two: it is the
	# read-only screen, so a compile failure there is silent.
	assert_eq(_resolvable_type(CODEX_SOURCE, "the codex"), true, "the codex compiles")
	var codex := _code_only(CODEX_SOURCE)
	for verb in ["act_commit", "committed", "earn_fate", "earn_destiny"]:
		assert_eq(
			codex.contains(verb),
			false,
			"the codex has no %s: it is read-only by design (ADR 0065)" % verb
		)


# --- Helpers -----------------------------------------------------------------


## The CODE of a GDScript file, with every comment line removed.
##
## The structural guards above search source for a forbidden verb, and the files
## they read all DOCSTRING those verbs in order to state that they never call
## them. Searching the raw text therefore fails on the very prose documenting the
## rule. Stripping comment lines keeps the assertion about code, which is what it
## was always trying to say.
##
## Trailing `#` comments are stripped too, and a line that is ONLY a comment is
## dropped entirely rather than becoming an empty line.
func _code_only(path: String) -> String:
	var code := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		code += line + "\n"
	return code


## One hero as a comparable shape: the race, the base attributes it was born with,
## and the paths it was actually enrolled on. Written as a string so a difference
## in any of the three shows up in one assertion message.
func _shape(created: Dictionary) -> Dictionary:
	var hero := created.get("actor", null) as Actor
	if hero == null:
		return {}
	var bases := hero.stats.base_dict()
	var keys: Array = bases.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		parts.append("%s=%s" % [String(key), str(float(bases[key]))])
	return {
		"race": String(created.get("race", "")),
		"base_attributes": "|".join(parts),
		"open_paths": "|".join(created.get("open_paths", []) as Array),
		"closed_paths": "|".join(created.get("closed_paths", []) as Array),
	}


## How many DISTINCT values a per-origin map holds. "Three" rather than a set, so
## the failure message names the number that collapsed.
func _distinct_values(by_origin: Dictionary) -> int:
	var seen: Array = []
	for key in by_origin.keys():
		var value: String = by_origin[key]
		if not seen.has(value):
			seen.append(value)
	return seen.size()


## Every leaf of a summary tree is a primitive. Recursive with a depth cap, because
## the arch rule requires one of any walk that could meet a cycle.
func _assert_primitive_tree(value: Variant, label: String, depth: int = 0) -> void:
	if depth > 4:
		return
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				_assert_primitive_tree((value as Dictionary)[key], label, depth + 1)
		TYPE_ARRAY:
			for entry in value as Array:
				_assert_primitive_tree(entry, label, depth + 1)
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			assert_eq(true, true, "%s carries a primitive" % label)
		_:
			assert_eq(
				true,
				false,
				"%s carries a %s, which is not a primitive" % [label, type_string(typeof(value))]
			)
