extends TestCase

## ADR 0130: character creation is REACHABLE, and there is exactly ONE door to it.
##
## ## Why this suite exists
##
## The screen and its scene shipped with a full suite and no player could reach them: a
## repo-wide grep found references only in their own `.tscn`, their `.uid` and their test. A
## passing suite on an unreachable screen is the exact shape DEF-0109 and DEF-0151 record in this
## repo, so reachability is asserted here rather than assumed from the screen's own tests.
##
## ## One door, not two
##
## `ScreenRoutes.ROUTES` names `character_creation`, so the nav bar can open it. The boot program
## therefore opens THAT SAME ROUTE rather than pushing a second copy of the scene — two doors to
## one screen means a player can be looking at a screen the route table does not know about,
## which is what `test_screen_reachability` exists to catch.

var _stack: ScreenStack
var _flow: CharacterCreationFlow
var _program: CharacterCreationProgram
var _opened: Array[StringName] = []
var _home: Control = null


func setup() -> void:
	_stack = ScreenStack.new()
	_home = Control.new()
	_home.name = "Home"
	_stack.push(_home)
	_flow = CharacterCreationFlow.new()
	_opened.clear()
	_program = CharacterCreationProgram.new(_stack, _flow, _open_route)


## Free everything this suite mounted. The stack frees its own screens, so only the stack needs
## releasing; a suite that leaves a stack parented leaks a subtree per navigation, which is the
## 67 GB incident AGENTS.md records.
##
## **`is_instance_valid` guards every cast.** The stack's own `pop` frees the screens it holds,
## so by teardown the home screen may already be a freed object — and casting one is a runtime
## error rather than a null, so the guard is the difference between a clean teardown and four
## script errors on a green suite. Idempotent and safe after an early return.
func teardown() -> void:
	for node in [_stack, _home]:
		if node == null or not is_instance_valid(node):
			continue
		var control := node as Control
		if control == null:
			continue
		if control.get_parent() != null:
			control.get_parent().remove_child(control)
		control.free()
	_program = null
	_flow = null
	_stack = null
	_home = null
	_opened.clear()


# --- Reachability ------------------------------------------------------------


func test_the_route_table_names_the_arrival_screen() -> void:
	# The concrete defect this closes. Asserted on the ROUTE rather than on the program, because
	# the route is what the nav bar and every probe answer from.
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has("character_creation"), true, "creation is a named route")


func test_the_program_is_mounted_and_offers_the_arrivals() -> void:
	var summary := _program.summary()
	assert_eq(bool(summary["mounted"]), true, "the program is mounted")
	assert_eq(int(summary["candidates"]) > 0, true, "and it has arrivals to offer")
	assert_eq(bool(summary["has_hero"]), false, "no hero until one is committed")


func test_opening_goes_through_the_route_rather_than_pushing_a_second_copy() -> void:
	var out := _program.open()
	assert_eq(bool(out["ok"]), true, "creation opened: %s" % out.get("reason", ""))
	assert_eq(_opened.size(), 1, "exactly one door was opened")
	assert_eq(
		_opened.has(CharacterCreationProgram.CREATION_ROUTE),
		true,
		"it opened the NAMED route, so the nav bar and boot agree on one door"
	)
	assert_eq(_stack.current() == _home, true, "and did not push its own screen over the stack")


func test_a_committed_arrival_produces_a_hero_and_the_program_knows_it() -> void:
	_program.open()
	var origin := StringName(FateCatalog.instance().destinies_in_group(&"origin")[0])
	var outcome := _program.commit(origin)
	assert_eq(bool(outcome["ok"]), true, "the arrival committed: %s" % outcome.get("reason", ""))
	assert_eq(_program.hero() != null, true, "a hero exists")
	assert_eq(bool(_program.summary()["has_hero"]), true, "and the program knows it")


func test_a_refused_arrival_makes_no_hero_and_says_why() -> void:
	# Popping or clearing on every outcome would leave a player who has not finished with nothing
	# to answer again, and a screen that silently forgets it asked.
	var refused := _program.commit(&"an_arrival_no_content_defines")
	assert_eq(bool(refused["ok"]), false, "an unknown arrival is refused")
	assert_eq(String(refused["reason"]), "unknown_origin", "and the reason is named")
	assert_eq(_program.hero() == null, true, "and no hero was made")


func test_boot_opens_creation_only_when_there_is_no_hero() -> void:
	# The returning-player half. A player with a restored body must not be sent back through
	# arrival, which is why the check is conditional rather than unconditional.
	var body := _hero()
	_program.adopt(body)
	assert_eq(bool(_program.summary()["has_hero"]), true, "a hero already exists")
	_opened.clear()
	_program.open()
	assert_eq(_opened.size(), 0, "so nothing is opened for a returning player")


# --- The seam ---------------------------------------------------------------------


func test_the_program_refuses_to_open_unmounted_rather_than_crashing() -> void:
	# A shell with no creation program must still boot, so "not mounted" is an answer and not an
	# exception.
	var bare := CharacterCreationProgram.new(null, null)
	var out := bare.open()
	assert_eq(bool(out["ok"]), false, "nothing to open")
	assert_eq(String(out["reason"]), "not_mounted", "and it is named")
	assert_eq(bare.summary()["mounted"], false, "which the summary agrees with")


func test_a_program_with_no_route_opener_refuses_rather_than_silently_doing_nothing() -> void:
	# A program that cannot open the route must SAY so, not push a screen the table does not
	# know about.
	var orphan := CharacterCreationProgram.new(_stack, _flow, Callable())
	var out := orphan.open()
	assert_eq(String(out["reason"]), "no_route_opener", "the missing seam is named")


# --- Internals ----------------------------------------------------------------------


## Stand in for the composition root's `open_route`. Records the id rather than navigating, so a
## test asserts WHICH door was used without needing the whole shell mounted.
func _open_route(route_id: StringName) -> void:
	_opened.append(route_id)


## A body an actor with a body plan, so `adopt` has something real to hold.
func _hero() -> Actor:
	var body := ActorFactory.build(&"returning_hero")
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	return body
