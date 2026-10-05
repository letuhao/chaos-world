extends TestCase

## `household_heir_registered` has a WRITER, a seam, and NOW A PRODUCTION CALLER — this
## suite holds both halves of that claim apart, so the gap cannot be closed by accident
## and cannot be papered over either.
##
## Named `clan_heir` so `tools test --suite clan_heir` runs it beside
## `test_clan_heir.gd`: the module's own tests and the seam's belong to one subject.
##
## ## What these hold
##
## 1. The seam WORKS. `ClanRegistry.commit` drives `ClanHeir.register` through an
##    installed verb and the fact lands.
## 2. The seam IS reached, from ONE page, installed by the composition root. `ClanScreen`
##    (ADR 0239) is the caller; the `ROUTE_CLAN` arm of `item_workbench_app.gd` installs
##    the verb at route mount and hands the page both halves of it. The whole thing is
##    driven through the real app by `game/tests/app/test_clan_join_production_path.gd`,
##    which is also where `ClanApi.join` — the door into membership the registration needs
##    — is proved.
##
## ## Why the second half is still an assertion and not a comment
##
## ADR 0113's rule is that the OWNER OF THE MOMENT writes. A poller for "has anybody
## become an heir" is the shape this repo refuses on sight, and the cheapest way to
## smuggle one past review is to add a call and describe it as boot. So the caller count
## is pinned at exactly ONE — not at "at least one" — and the one is a page rather than a
## sweep. A future owner adding a second appointment moment turns THIS test red, which is
## the review surface that change deserves.

const HOUSE := &"t_house"

## The boot file that installs the seam at route mount and hands the page both halves of
## it. `app/` is a `PRIVATE_UNIT`, so this is the only file in `src/` that may NAME the
## seam at all; the screen receives it as a `Callable`. Read by path rather than by
## scanning for `ClanRegistry.commit`, because the root binds the verb as
## `Callable(ClanRegistry, "commit")` — a dotted-call scan would find this seam's own
## definition and nothing else.
const COMPOSITION_ROOT := "res://src/app/item_workbench_app.gd"
## The exact binding the root ships: a bare `Callable` static reference, because a typed
## lambda whose body calls another script's static function killed the process with an
## access violation on the shell's first frame (the reason every other seam in that file
## is a bare reference too). Pinned as a SHAPE, not just as a verb name, because a lambda
## would pass a scan looking for `"commit"` and then crash the game on its first frame.
const ROOT_BINDS_SEAM := 'Callable(ClanRegistry, "commit")'
const ROOT_BINDS_GATE := 'Callable(ClanRegistry, "available")'
## The seam itself, and the ONE literal call `tools/gate_reach.py` walks out of `app/`
## into the writer's module. Held as a pair because the shape and the file are one claim:
## a `ClanHeir.register(` somewhere else in the program would drive the census green while
## the seam stayed opaque, so the edge is pinned *in the seam* specifically.
const SEAM_FILE := "res://src/app/clan_registry.gd"
const NAMED_WRITER_CALL := "ClanHeir.register("


func setup() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	ClanRegistry.install()


func teardown() -> void:
	# Unbind rather than only overwrite, so this suite cannot leak a live seam into
	# whichever suite runs next — the `CombatBoot.set_attack_resolver` shape.
	ClanRegistry.install(Callable())
	ClanFixtureCatalog.teardown()


func _member(standing: int = 0, actor_id: StringName = &"member") -> Actor:
	var actor := (
		Actor
		. new(
			actor_id,
			{
				Stat.PHYSIQUE: 10.0,
				Stat.WILL: 5.0,
				Stat.SPIRIT: 4.0,
				Stat.AGILITY: 6.0,
				Stat.COMPREHENSION: 3.0,
				Stat.APTITUDE: 3.0,
			}
		)
	)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, &"hearthborn", 0.5)
	ClanApi.join(actor, HOUSE, standing)
	return actor


# --- the seam works ------------------------------------------------------------


func test_committing_through_the_seam_lands_the_fact_the_four_quests_watch() -> void:
	var actor := _member()
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "no register yet")

	var entered := ClanRegistry.commit(actor)

	assert_eq(bool(entered["ok"]), true, "the house entered the member")
	assert_eq(String(entered["rank"]), String(ClanHeir.HEIR_RANK), "and it is the heir rung")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		(
			"so `household_heir_registered` is on the ledger and all four quest steps that "
			+ "watch it can be cleared by this one call"
		)
	)


func test_the_seam_refuses_before_the_module_is_asked_and_reasons_in_the_module_words() -> void:
	# The gate answers FIRST, so `clan` is never handed a question it would have to
	# refuse — and the words are the module's OWN, aliased in the seam, so a panel
	# rendering `ClanHeir.R_*` renders these too.
	var actor := _member()
	ClanRegistry.install(Callable())

	var refused := ClanRegistry.commit(actor)

	assert_eq(String(refused["reason"]), ClanRegistry.R_NO_RESOLVER, "nothing is bound")
	assert_eq(bool(refused["registered"]), false, "so nothing was registered")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		0,
		"and a seam nobody bound records nothing"
	)


func test_a_wanderer_and_a_registered_member_are_refused_by_name() -> void:
	var wanderer := Actor.new(&"wanderer")
	ClanApi.attach(wanderer)
	assert_eq(
		String(ClanRegistry.available(wanderer)["reason"]),
		ClanRegistry.R_NOT_A_MEMBER,
		"no house, no register"
	)

	var entered := _member()
	assert_eq(bool(ClanRegistry.commit(entered)["ok"]), true, "entered once")
	var again := ClanRegistry.commit(entered)
	assert_eq(String(again["reason"]), ClanRegistry.R_ALREADY_HEIR, "the ledger is monotone")
	assert_eq(
		WorldFact.count(entered, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		"and a second press writes nothing a second time"
	)


func test_a_house_whose_ladder_stops_at_core_is_refused_not_invented_around() -> void:
	# `ClanHeir` refuses `no_heir_rank` against a house that publishes no such office,
	# and the seam must reach the same answer BEFORE it calls, or a caller could not
	# tell a content gap from a wiring gap.
	var ladderless := ClanDef.new()
	ladderless.id = &"t_ladderless"
	ladderless.ranks = [&"outer", &"inner", &"core"]
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE), ladderless])
	var actor := _member()
	ClanApi.join(actor, &"t_ladderless")

	var refused := ClanRegistry.available(actor)

	assert_eq(String(refused["reason"]), ClanRegistry.R_NO_HEIR_RANK, "no such office exists")
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "and nothing recorded")


func test_registration_through_the_seam_still_moves_the_position_and_not_the_standing() -> void:
	# ADR 0064's split, held from the seam's side: the seam injects and decides
	# nothing, so the module's one-way split survives it.
	var actor := _member(40)
	var before := ClanApi.standing_of(actor)

	ClanRegistry.commit(actor)

	assert_eq(ClanApi.standing_of(actor), before, "standing is untouched by a registration")
	assert_eq(ClanApi.rank_of(actor), ClanHeir.HEIR_RANK, "and the position is what moved")


# --- and it is reached from a page, not fabricated into a sweep ----------------


func test_the_seam_is_reached_from_production_and_from_exactly_one_page() -> void:
	# The load-bearing assertion of this suite, and the one that used to say ZERO.
	#
	# `ClanScreen` is the caller the audit said was missing; the composition root installs
	# the verb at route mount. Pinned at EXACTLY ONE caller rather than "at least one",
	# because a second appointment moment — a sweep, an ambient pass, a boot hook — is
	# exactly the shape ADR 0113 refuses, and the cheapest way to smuggle one past review
	# is to add a call and describe it as boot.
	#
	# `game/src/app` is walked TOO and it is the only layer allowed to name the seam, so
	# this file's own directory is the one excluded: it IS in `app`, and its own
	# definition would otherwise be counted as a caller of itself.
	var callers: Array[String] = []
	var roots := ["res://src/modules", "res://src/core", "res://src/ui", "res://src/contracts"]
	roots.append("res://src/app")
	for root in roots:
		for path in _gdscript_files(root):
			if path.ends_with("app/clan_registry.gd"):
				continue
			# CODE only: `clan_screen.gd` and this file DISCUSS the seam by name in prose,
			# and `test_clan_heir.gd` cites it, so a scan over raw text reports every file
			# that has read the documentation as a caller of it.
			if _code_only(FileAccess.get_file_as_string(path)).contains("ClanRegistry."):
				callers.append(path)
	callers.sort()
	assert_eq(
		callers,
		[COMPOSITION_ROOT],
		(
			(
				"exactly one file in src/ names the seam in code, and it is the composition "
				+ "root that binds it at route mount — `app/` is a PRIVATE_UNIT, so the page "
				+ "receives it as a Callable and is the only thing that presses it. A second "
				+ "caller is a second appointment moment (ADR 0113). Found: %s"
			)
			% [", ".join(callers)]
		)
	)


func test_the_composition_root_installs_the_seam_and_hands_the_page_both_halves() -> void:
	# The mirror of the assertion above on the OTHER half of the seam: ADR 0239's rule 1
	# is "both halves or neither", because a screen given only `commit` would have to
	# re-derive the gate to decide whether to OFFER the press — a second authority on who
	# may be heir, which is precisely what `no_heir_rank` refuses.
	#
	# Read over `_code_only`, so this file's own prose about the binding is not mistaken for
	# the binding and a future author cannot silence the check by writing about it.
	var root := _code_only(FileAccess.get_file_as_string(COMPOSITION_ROOT))
	assert_ne(
		root.find(ROOT_BINDS_SEAM),
		-1,
		"the root binds `commit` as a bare static reference, not a lambda"
	)
	assert_ne(
		root.find(ROOT_BINDS_GATE),
		-1,
		"and the `available` gate beside it — both halves or neither"
	)


# --- and the chain is VISIBLE, which is not the same as wired ------------------


## ## THE CENSUS CANNOT SEE A `Callable`, AND THIS IS THE EDGE IT WALKS
##
## This suite proved the seam was WIRED and the gate was still red. Both were true,
## because `commit` ended `_verb.call(actor)`: a dynamic dispatch runs correctly and
## writes no static `Class.method(` edge, and `tools/gate_reach.py` answers "can the
## shipped game reach this writer?" by walking exactly those. Four authored quest steps
## watching `household_heir_registered` were reported unfinishable while the seam drove
## the very verb that produces the fact.
##
## So the load-bearing property is not "some caller presses the page" — the page test in
## `game/tests/app/test_clan_join_production_path.gd` already holds that, by mounting the
## real app. It is that **`app/` reaches the writer's module through a NAMED call**, which
## is what closes the census finding. Pinned here over `_code_only`, so this file's own
## prose naming the verb cannot satisfy it: a docstring is not an edge.
##
## It is deliberately a SHAPE (`ClanHeir.register(`) and not a whole-file scan for the
## seam's own name. A seam that collapsed back to `_verb.call` would keep every other
## test in this file green — including the one that mounts the real page and watches the
## fact land — and only this one would go red.
func test_the_seam_reaches_the_writer_module_through_a_named_call_not_a_callable() -> void:
	var root := _code_only(FileAccess.get_file_as_string(SEAM_FILE))
	assert_ne(
		root.find(NAMED_WRITER_CALL),
		-1,
		(
			(
				"%s must reach `ClanHeir` by the NAMED call `%s`, not through "
				% [SEAM_FILE, NAMED_WRITER_CALL]
			)
			+ (
				"`_verb.call`. The runtime seam works either way and every other suite here "
				+ "stays green, but `uv run python -m tools gate_reach check` measures "
				+ "reachability from a static `Class.method(` call graph: a Callable writes no "
				+ "edge, so the writer reads as unreachable and the four quest steps watching "
				+ "`household_heir_registered` are reported unfinishable while they are not."
			)
		)
	)


# --- internals -----------------------------------------------------------------


## Whether `path` names `id` in a line of CODE. The comment half is stripped first, so
## a file that merely DISCUSSES the seam is not counted as calling it — the same helper
## over, and the same reason, as `test_clan_heir.gd::_names_in_code`.
func _names_in_code(path: String, id: String) -> bool:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.split("#")[0].contains(id):
			return true
	return false


## Every `.gd` under `root`, recursively. A `while` over `DirAccess` is the one shape
## `tests/arch_rules/test_no_unbounded_wait.gd` accepts as terminating.
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


## `text` with every `#` comment and every double-quoted string literal blanked, so a
## source scan reads CODE and never prose.
##
## ## WHY THIS EXISTS HERE, in a file that was already scanning for callers
##
## The seam is DISCUSSED by name in `clan_registry.gd`'s docstring, in every paragraph of
## `clan_screen.gd`, and in this file. `_names_in_code` above splits on `#`, which handles
## a comment on a line of code but leaves the seam's own constants — `ClanHeir.R_NO_ACTOR`
## is a same-file const, so the scan would count THIS FILE's definitions — and leaves
## anything in a string literal. Strings are blanked FIRST so a `#` inside a literal is not
## mistaken for a comment, which is the order `tools/arch/enforce.py:_code_only` applies
## them (`COMMENT_RE`, then `STRING_RE`) and the reason this is the repo's own shape rather
## than a second one.
##
## ## WHAT IT DOES NOT BUY
##
## It cannot tell a string on a code line from an identifier, which is why the callers here
## scan for the SYMBOL `ClanRegistry.` and not for prose: no code path reaches the seam
## without naming that token, and no honest file mentions it in a literal.
func _code_only(text: String) -> String:
	var without_strings := ""
	var at := 0
	while true:
		var open := text.find('"', at)
		if open < 0:
			without_strings += text.substr(at)
			break
		var close := text.find('"', open + 1)
		if close < 0:
			without_strings += text.substr(at)
			break
		without_strings += text.substr(at, open - at) + '""'
		at = close + 1
	var out: Array[String] = []
	for line in without_strings.split("\n"):
		var at_hash := line.find("#")
		out.append(line if at_hash < 0 else line.substr(0, at_hash))
	return "\n".join(out)
