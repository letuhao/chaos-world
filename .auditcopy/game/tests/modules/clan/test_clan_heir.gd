extends TestCase

## `household_heir_registered` — ADR 0137's fact whose real owner is `clan`.
##
## Every shipped `ClanDef.ranks` carries `heir`, and `ClanGate` can gate content on it,
## but `ClanState.with_rank` writes whatever it is told and `ClanApi` had no verb that
## told it anything: the rung was reachable from a test and from nowhere else. So
## `the_station_you_held.tres`'s "See your name entered in the household register" had
## no act behind it.
##
## What these hold: the fact lands when a registration SUCCEEDS and not at all when it
## is refused, and registration writes the position and NOTHING else — ADR 0064's
## two-part split, which is the whole politics layer.

const HOUSE := &"t_house"
const HEIR := ClanHeir.HEIR_RANK


func setup() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])


func teardown() -> void:
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


# --- the happy path ------------------------------------------------------------


func test_registering_a_member_records_that_their_name_went_in_the_register() -> void:
	var actor := _member()
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "no register yet")

	var registered := ClanHeir.register(actor)

	assert_eq(bool(registered["ok"]), true, "the registration landed")
	assert_eq(ClanApi.rank_of(actor), HEIR, "and the member holds the heir rung")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		"and the world was told, exactly once"
	)


func test_registration_writes_the_position_and_nothing_else() -> void:
	# ADR 0064's split, held from the other side: a member registered as heir on no
	# standing at all is a legitimate character. A registration that also moved standing
	# would collapse the two numbers this module exists to keep apart.
	var actor := _member(0)
	var before := ClanApi.state(actor).duplicate(true)

	var registered := ClanHeir.register(actor)

	assert_eq(int(registered["standing"]), int(before["standing"]), "standing is unchanged")
	assert_eq(
		ClanApi.standing_of(actor),
		int(before["standing"]),
		"and it is the published verb that agrees, not just the report"
	)
	assert_ne(ClanApi.rank_of(actor), String(before["rank"]), "only the position moved")


func test_a_thick_standing_member_may_still_be_registered_and_a_thin_one_too() -> void:
	# The politics is the GAP: registration and earned standing never derive from one
	# another in either direction, so both of these are ordinary outcomes.
	for standing in [0, 40, 250]:
		var actor := _member(standing)
		assert_eq(
			bool(ClanHeir.register(actor)["ok"]),
			true,
			"%d standing does not decide who the house names" % standing
		)


func test_the_rank_trait_the_gate_watches_is_the_one_registration_writes() -> void:
	# `ClanGate`'s `has_rank` reads the projected trait, so a registration that wrote the
	# ledger without rebuilding the projection would gate as still unranked.
	var actor := _member()
	ClanHeir.register(actor)
	var verdict := ClanApi.unmet(actor, {"verb": &"has_rank", "id": HEIR})
	assert_eq(bool(verdict["ok"]), true, "so the authored gate opens on it")
	assert_eq(
		bool(actor.traits.has(ClanState.rank_trait_for(HEIR))),
		true,
		"and the trait the gate reads is on the actor"
	)


# --- the refusals --------------------------------------------------------------


func test_registering_twice_records_nothing_a_second_time() -> void:
	# `WorldFact` is monotone. A second registration is the same one written twice, so it
	# is a refusal with a reason rather than a second count.
	var actor := _member()
	ClanHeir.register(actor)
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 1, "entered once")

	for repeat in 3:
		var refused := ClanHeir.register(actor)
		assert_eq(String(refused["reason"]), ClanHeir.R_ALREADY_HEIR, "repeat %d" % repeat)
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 1, "three repeats recorded nothing"
	)


func test_a_member_of_no_house_is_refused_and_records_nothing() -> void:
	var actor := Actor.new(&"wanderer")
	ClanApi.attach(actor)

	var refused := ClanHeir.register(actor)

	assert_eq(String(refused["reason"]), ClanHeir.R_NOT_A_MEMBER, "no house, no register")
	assert_eq(ClanApi.rank_of(actor), &"", "and no rank was invented")
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "nothing recorded")


func test_a_null_actor_is_refused_rather_than_throwing() -> void:
	assert_eq(String(ClanHeir.register(null)["reason"]), ClanHeir.R_NO_ACTOR, "named, not raised")


func test_a_house_that_publishes_no_heir_rung_records_nothing() -> void:
	# The rung is a NAMED constant, not something derived from the ladder, so the only
	# honest way to keep the constant honest is to refuse against a house that does not
	# publish it: a ladder that stops at `core` has no such office for anybody to fill.
	var ladderless := ClanDef.new()
	ladderless.id = &"t_ladderless"
	ladderless.ranks = [&"outer", &"inner", &"core"]
	ClanFixtureCatalog.install([ladderless])
	var actor := _member()
	ClanApi.join(actor, &"t_ladderless")

	var refused := ClanHeir.register(actor)

	assert_eq(String(refused["reason"]), ClanHeir.R_NO_HEIR_RANK, "no such rung is published")
	assert_ne(ClanApi.rank_of(actor), HEIR, "and no rank was written")
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "nothing recorded")


func test_a_refused_admission_leaves_nothing_to_register() -> void:
	# The other half of "recorded when the action succeeds": a member who never got in
	# has no register to be entered in, so the verb must refuse rather than invent one.
	var sealed := ClanFixtureCatalog.sealed(&"t_sealed", 0.99)
	ClanFixtureCatalog.install([sealed])
	var actor := _member()
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, &"hearthborn", 0.1)
	var admission := ClanApi.join(actor, &"t_sealed")

	assert_eq(bool(admission["ok"]), false, "the purity bar refused the admission")
	assert_eq(
		String(ClanHeir.register(actor)["reason"]),
		ClanHeir.R_NOT_A_MEMBER,
		"so there is no house to enter them in"
	)
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "nothing recorded")


# --- once, not per read --------------------------------------------------------


func test_reading_the_claim_never_records_a_registration() -> void:
	# The acceptance case for "recorded once, not per-read": a summary is what every
	# panel asks every frame, and a producer on that path would inflate forever.
	var actor := _member()
	ClanHeir.register(actor)
	var before := WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED)
	for cycle in 5:
		ClanApi.summary(actor)
		ClanApi.state(actor)
		ClanApi.rank_of(actor)
		ClanApi.attach(actor)
		ClanApi.unmet(actor, {"verb": &"has_rank", "id": HEIR})
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		before,
		"cycle 0..4 of reading and re-attaching records nothing"
	)


func test_the_registration_fact_is_the_acts_alone_and_nothing_ambient_reports_it() -> void:
	# ADR 0137's refusal, held as an assertion rather than left to review. The ambient
	# roster is the one producer that would turn "you were entered in the register" into
	# news the world says about itself, which is the gate's demand echoed back — and it
	# would falsify
	# `tests/app/test_world_ambient_facts.gd`'s
	# `test_a_fact_the_world_never_reports_is_still_outstanding`.
	assert_eq(
		WorldAmbient.ROSTER.has({"fact": ClanFacts.FACT_HEIR_REGISTERED}),
		false,
		"the ambient roster does not name it"
	)
	assert_eq(
		_named_in_code("res://src/app"),
		0,
		"and no file in app/ -- the composition root, the director or the pulse -- names it"
	)
	assert_eq(
		_named_in_event_content(),
		0,
		"and no authored event beat names it either, so nothing ambient can produce it"
	)


func test_exactly_two_files_name_the_id_and_only_one_of_them_writes_it() -> void:
	# The second of the two is `modules/destiny/destiny_projection.gd`'s `COUNTER_FACTS`
	# table, which maps the fact onto a fate counter. That table LOOKS like a producer and
	# is not one -- ADR 0137 says so in as many words -- so the count is pinned at two, and
	# the fact that only one of the two reaches `WorldFact.record` at all is what keeps
	# that difference from quietly closing.
	var naming: Array[String] = []
	var reaching := 0
	for path in _gdscript_files("res://src"):
		if _names_in_code(path, ClanFacts.FACT_HEIR_REGISTERED):
			naming.append(path)
			# `_reaches_the_writer`, NOT a raw `body.contains(...)`. The two differ on a
			# file whose only mention of `WorldFact.record` is PROSE, and that is exactly
			# the second of the two files: `destiny_projection.gd` discusses the
			# chokepoint in six `##` sentences (`destiny_projection.gd:81`, `:112`,
			# `:125`, `:130`, `:245`, `:256`) and calls it from none of them. A raw scan
			# therefore credited the fate-mapping table with a second producer, the
			# count reached 2, and the one assertion that keeps ADR 0137's "not ambient,
			# never will be" honest had stopped being able to fail. The same defect as
			# `_names_in_code`, one helper over.
			if _reaches_the_writer(path):
				reaching += 1
	naming.sort()
	assert_eq(reaching, 1, "exactly one of them reaches the ledger's one writer")
	assert_eq(
		naming,
		["res://src/modules/clan/clan_facts.gd", "res://src/modules/destiny/destiny_projection.gd"],
		"the producer, and the fate mapping that is deliberately not one"
	)
	assert_eq(
		_record_calls("res://src/modules/clan/clan_facts.gd", "FACT_HEIR_REGISTERED"),
		1,
		(
			"and the producer passes its own same-file const to that writer, which is the only "
			+ "spelling `tools gate_reach.py` resolves"
		)
	)


## Whether `path` names `id` in a line of CODE. One line at a time with the comment half
## stripped, the way every other rule in `tests/arch_rules` reads source, so a file that
## merely DISCUSSES the id is not counted as naming it.
func _names_in_code(path: String, id: StringName) -> bool:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.split("#")[0].contains(String(id)):
			return true
	return false


## Whether `path` CALLS `WorldFact.record` rather than merely writing the words down.
##
## Same comment half stripped, line by line, as `_names_in_code` above — and for the
## same reason. `test_sect_no_power.gd`'s `_calls` is the precedent and already does it:
## a module names the verbs it refuses inside its own class docs, so a raw
## `body.contains(needle)` scan reads the code beside those sentences as clean while
## the prose trips it. The invariant here is about what a file EXECUTES, so `##` lines
## are dropped before the scan.
func _reaches_the_writer(path: String) -> bool:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains("WorldFact.record"):
			return true
	return false


## How many lines of `path` hand `const_name` to the ledger's writer as its id argument.
## One per fact, and zero means the const is declared beside the writer without reaching
## it, which would be a fact id the census can read and nothing produces.
func _record_calls(path: String, const_name: String) -> int:
	var hits := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.split("#")[0].contains("WorldFact.record(actor, %s" % const_name):
			hits += 1
	return hits


## How many files under `root` name the id in a line of CODE.
func _named_in_code(root: String) -> int:
	var hits := 0
	for path in _gdscript_files(root):
		if _names_in_code(path, ClanFacts.FACT_HEIR_REGISTERED):
			hits += 1
	return hits


## How many authored event `.tres` name the id. `res://data/event` is where an ambient
## producer would be written, because `EventStageDef.on_enter` is a beat list and a beat
## list is content — and it is deliberately NOT the whole of `res://data`, because the
## quest step that DEMANDS the fact names it too and a demand is not a producer.
func _named_in_event_content() -> int:
	var hits := 0
	for path in _content_files("res://data/event"):
		if FileAccess.get_file_as_string(path).contains(String(ClanFacts.FACT_HEIR_REGISTERED)):
			hits += 1
	return hits


## Every `.gd` under `root`, recursively. A `while` over `DirAccess` is the one shape
## `tests/arch_rules/test_no_unbounded_wait.gd` accepts as terminating, and a `for` over
## the collected list is used everywhere else — the same walk that rule itself performs.
func _gdscript_files(root: String) -> Array[String]:
	return _files(root, ".gd")


## Every authored `.tres` under `root`, recursively. Same walk, one extension.
func _content_files(root: String) -> Array[String]:
	return _files(root, ".tres")


func _files(root: String, suffix: String) -> Array[String]:
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
				found.append_array(_files(path, suffix))
			elif entry.ends_with(suffix):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
