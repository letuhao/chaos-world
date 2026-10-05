extends TestCase

## `household_heir_registered` has a WRITER and a seam, and still no caller — this suite
## holds both halves of that claim apart, so the gap cannot be closed by accident and
## cannot be papered over either.
##
## Named `clan_heir` so `tools test --suite clan_heir` runs it beside
## `test_clan_heir.gd`: the module's own tests and the seam's belong to one subject.
##
## ## What these hold
##
## 1. The seam WORKS. `ClanRegistry.commit` drives `ClanHeir.register` through an
##    installed verb and the fact lands — so when a clan surface does get built, the
##    one call it needs is already known to work, and the four `household_heir_registered`
##    quest steps become completable the moment somebody calls it.
## 2. The seam is NOT a fabricated consumer. Nothing in `game/src/` calls
##    `ClanRegistry.commit`, no boot installs it, and no timer sweeps for it — asserted
##    here by walking the source tree, the same walk `test_clan_heir.gd` already uses
##    for the same fact.
##
## ## Why the second half is an assertion and not a comment
##
## ADR 0113's rule is that the OWNER OF THE MOMENT writes. A poller for "has anybody
## become an heir" is the shape this repo refuses on sight, and the cheapest way to
## smuggle one past review is to add a call and describe it as boot. So the caller count
## is pinned at zero: if a future owner adds the real call, THIS test fails and they
## update it in the same commit, which is the review surface the change deserves.

const HOUSE := &"t_house"


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


# --- and it is not a fabricated consumer ---------------------------------------


func test_nothing_in_game_src_calls_the_seam_so_the_gap_is_still_an_open_one() -> void:
	# The load-bearing assertion of this suite. `ClanRegistry` exists and works, which
	# is exactly when a fabricated caller becomes tempting; pinning the count at zero
	# means adding one is a deliberate act that turns THIS test red.
	#
	# `game/src/app` is excluded on purpose: this file IS in `app`, and its own
	# definition would otherwise be counted as a caller of itself. Only the module
	# half and the other layers are walked — which is the same reasoning
	# `test_clan_heir.gd` uses when it asks whether `app/` names the FACT.
	var callers: Array[String] = []
	for root in ["res://src/modules", "res://src/core", "res://src/ui", "res://src/contracts"]:
		for path in _gdscript_files(root):
			if path.ends_with("app/clan_registry.gd"):
				continue
			if _names_in_code(path, "ClanRegistry.commit"):
				callers.append(path)
	assert_eq(
		callers.size(),
		0,
		(
			"no module, core, contract or ui file calls the seam — the appointment moment "
			+ "does not exist in the shipped game, which is what DEF entry for clan_heir "
			+ "records. If this fails, a real caller was added: update the deferral too."
		)
	)


func test_no_boot_path_installs_the_seam_yet() -> void:
	# The mirror of the assertion above on the other half of the seam. `CombatMercy` is
	# installed at `combat_boot.gd:519`; this one has no equivalent line yet because the
	# boot file that would carry it (`item_workbench_app.gd`) belongs to another slice.
	var installs: Array[String] = []
	for root in ["res://src/modules", "res://src/core", "res://src/ui", "res://src/contracts"]:
		for path in _gdscript_files(root):
			if _names_in_code(path, "ClanRegistry.install"):
				installs.append(path)
	assert_eq(
		installs.size(),
		0,
		"nothing outside this seam installs it either — the install belongs to the boot path"
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
