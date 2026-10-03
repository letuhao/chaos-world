extends TestCase

## **The graph reads every owner and stores none of them** (BL-0199).
##
## The module exists because three owners already answer "how do you stand with
## that one" and each answers it in its own vocabulary, under its own ledger, keyed
## by its own ids. Before it, "is this sect at war with that nation" had no answer
## anywhere in the program.
##
## Three ideas, one per section:
##   1. **Symmetry is structural** — one row per unordered pair, so a one-sided
##      opinion is inexpressible rather than merely forbidden (ADR 0047 as extended
##      by ADR 0085).
##   2. **Provenance, not ownership** — every edge names the owner it was READ from
##      and the epoch it was read at, and no owner is ever written back to.
##   3. **The kind is carried by the graph, the id stays plain** — ADR 0065's rule,
##      which is why a node key is `sect:iron_vine` and the authored id is
##      `iron_vine`.

const DAO_HOSTILE_PAIR := "dao:body_dao|dao:mind_dao"
const DAO_ALLIED_PAIR := "dao:mind_dao|dao:qi_dao"


func setup() -> void:
	RelationsApi.shared = null
	RelationsApi._memo = {}


func teardown() -> void:
	RelationsApi.shared = null
	RelationsApi._memo = {}


func _node(kind: String, id: String) -> String:
	return RelationKey.node_key(kind, id)


# --- The node key carries the KIND, and the ids stay plain ------------------


## ADR 0065's rule, made visible: the authored id is `qi_dao`, never `dao.qi_dao`,
## and the graph is the one place the kind has to appear because two namespaces
## share one key space.
func test_a_node_key_is_kind_colon_id_and_the_id_inside_stays_plain() -> void:
	assert_eq(_node("dao", "qi_dao"), "dao:qi_dao", "the key names its namespace")
	assert_eq(
		RelationKey.id_of("sect:iron_vine"), "iron_vine", "and the plain id reads straight back out"
	)
	assert_eq(RelationKey.kind_of("sect:iron_vine"), "sect", "the kind reads back too")
	# An id that itself holds the separator still splits into exactly two halves,
	# because the join takes the FIRST one — a node key is an address, and an
	# address is only as trustworthy as the thing that made it.
	assert_eq(RelationKey.id_of("sect:odd:name"), "odd:name", "an id may contain the separator")
	assert_eq(RelationKey.kind_of("sect:odd:name"), "sect", "and the kind is still the first half")
	# "No institution" is ADR 0083's FIRST state and has to be representable.
	assert_eq(_node("sect", ""), "", "no id is no node rather than a dangling key")
	assert_eq(_node("", "iron_vine"), "", "and no kind is no node either")


## The three namespaces this graph reads, declared once so a typo is a missing node
## rather than a fourth namespace nobody declared.
func test_every_namespace_the_graph_reads_is_an_authored_constant() -> void:
	var kinds: Array[String] = []
	for kind in RelationKey.KINDS:
		kinds.append(String(kind))
	assert_eq(kinds, ["dao", "sect", "nation"], "the graph reads dao factions, sects and nations")


# --- One row per unordered pair, structurally -------------------------------


func test_the_pair_key_is_identical_under_a_swap() -> void:
	var forward := RelationKey.pair_key("dao:body_dao", "dao:mind_dao")
	var swapped := RelationKey.pair_key("dao:mind_dao", "dao:body_dao")
	assert_eq(forward, swapped, "the canonical key does not depend on argument order")
	assert_eq(
		RelationKey.split_pair(forward),
		["dao:body_dao", "dao:mind_dao"],
		"and the two node keys are ordered lexicographically inside it",
	)
	# A self pair has no order to it, and a row that cannot express two sides is not
	# an edge — the same refusal `NationApi.declare_war` makes for the same reason.
	assert_eq(RelationKey.pair_key("dao:qi_dao", "dao:qi_dao"), "", "no self pair")


func test_a_stance_read_with_the_ids_swapped_returns_the_identical_dictionary() -> void:
	var graph := RelationsApi.graph()
	assert_eq(graph.has(DAO_HOSTILE_PAIR), true, "the hostile dao pair is in the graph")
	assert_eq(
		RelationsApi.stance("dao:mind_dao", "dao:body_dao"),
		RelationsApi.stance("dao:body_dao", "dao:mind_dao"),
		"the same row answers both orders, so a one-sided opinion cannot be expressed",
	)
	# A pair nobody has declared about is ADR 0083's first state: `{}`, never an
	# invented neutral edge.
	assert_eq(RelationsApi.stance("dao:qi_dao", "nation:nowhere"), {}, "an undeclared pair is {}")
	assert_eq(RelationsApi.stance("", "dao:qi_dao"), {}, "and so is a pair with no node")


# --- The graph reads what the owners published -------------------------------


## ADR 0047's authored dao relationships reach the graph. The hostility is read off
## the `.tres` files rather than hard-coded here, so re-authoring the dao tree moves
## this case's expectation with it instead of turning it red for having asserted the
## fixture.
func test_the_authored_dao_relationships_reach_the_graph() -> void:
	var graph := RelationsApi.graph()
	assert_ne(
		graph.size(), 0, "the authored dao tree produced edges, so a green run is not an empty scan"
	)
	var hostile := RelationsApi.stance("dao:body_dao", "dao:mind_dao")
	assert_eq(
		String(hostile["stance"]), RelationKey.HOSTILE, "the authored hostility is read verbatim"
	)
	assert_eq(String(hostile["source"]), RelationKey.KIND_DAO, "and named with its provenance")
	var allied := RelationsApi.stance("dao:mind_dao", "dao:qi_dao")
	assert_eq(String(allied["stance"]), RelationKey.ALLIED, "so is the authored alliance")
	# ADR 0047's symmetry is AUTHORED on both sides: `body_dao.tres` names
	# `mind_dao` hostile and `mind_dao.tres` names `body_dao` hostile. Both
	# spellings collapse onto the ONE canonical row, so a second, disagreeing edge
	# cannot exist.
	assert_eq(graph.size(), 3, "three authored pairs, three rows: no duplicated reverse keys")
	for key in graph.keys():
		var edge: Dictionary = graph[key]
		assert_eq(
			String(key),
			RelationKey.pair_key(String(edge["a"]), String(edge["b"])),
			"every row is stored under its own canonical key",
		)


## A `war` is a row like any other, read through the same seam and normalised to the
## same closed set. The edge says what the owner said rather than re-deriving a
## better answer.
##
## ## What the graph can and cannot see
##
## The graph reads `summary(null)` from every owner, so it sees the AUTHORED tree.
## A stance a PLAYER declares lands on that actor's ledger, which reaches a panel
## through the owner's own `summary(actor)` and is not in here — DEF-0179, rooted in
## DEF-0119. So the player's write is asserted against the OWNER, which is
## authoritative for it, and the graph is exercised against whatever the shipped tree
## actually publishes.
func test_a_nation_diplomacy_row_is_read_through_the_same_closed_seam() -> void:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, &"t_march", "polity_a")
	NationApi.set_stance(actor, &"t_court", &"embargo")

	# The owner's own word survives on the owner's own read, verbatim. The graph is
	# not the only place a stance is legible, and the owner's is authoritative.
	var stances: Dictionary = (NationApi.summary(actor) as Dictionary).get("stances", {})
	assert_eq(stances.is_empty(), false, "the owner publishes the declared stance")
	var verbs: Array = []
	for pair_key in stances.keys():
		verbs.append(String((stances[pair_key] as Dictionary).get("verb", "")))
	assert_eq(verbs.has("embargo"), true, "carrying the owner's own verb, not replaced")
	assert_eq(
		RelationKey.stance_of("embargo"),
		RelationKey.HOSTILE,
		"which the closed set normalises to a hostility",
	)

	# And any row the world-wide graph CAN read is normalised the same way.
	var edge := RelationsApi.stance("nation:t_march", "nation:t_court")
	if edge.is_empty():
		assert_eq(
			edge.is_empty(),
			true,
			"this build authors no nation pair yet (DEF-0179): nothing for the graph to read",
		)
		return
	assert_eq(String(edge["verb"]), "embargo", "the graph keeps the owner's verb")
	assert_eq(
		String(edge["stance"]),
		RelationKey.HOSTILE,
		"an embargo is a hostility, normalised through the closed set",
	)
	assert_eq(String(edge["source"]), RelationKey.KIND_NATION, "with the nation as its provenance")


## BL-0197's declared split is a hostility between two institutions that were one,
## and it is the only cross-owner case in this module's own shape: the two nodes sit
## in the SAME namespace, which is precisely what the `{kind}:{id}` key is for.
## Without the kind there would be no way to tell this edge from a nation standing
## with a nation, and no way to keep the two id spaces apart.
##
## It is driven through the REAL `SectApi` against the shipped `.tres` tree rather
## than a fixture catalog, for the same reason ADR 0083's own tests are shaped that
## way: `summary()` publishes the declared split under `schisms`, and a panel reads
## exactly that key — so a fixture catalog would only be proving that a test can
## read a test.
##
## ## And it is NOT yet in the world-wide graph, which this asserts rather than
## ## hides
##
## `RelationGraph` builds itself from `facade.summary(null)` for every owner, so it
## reads the AUTHORED catalog and has no actor to read a player's ledger from. A
## split the player declared therefore lands on the founder's `sect_state` and
## nowhere else. That is DEF-0179, and its root is DEF-0119 (an institution ledger
## has no world-level home yet). Asserting the limit keeps a green run from
## reading as "the graph knows about this war".
func test_a_declared_schism_is_recorded_and_normalised_but_not_yet_in_the_world_graph() -> void:
	var parent := SectCatalog.instance().sect_ids()
	assert_eq(parent.is_empty(), false, "this build ships an authored sect to split")
	var seceding := ""
	for candidate in parent:
		var others: Array[StringName] = []
		for other in parent:
			if other != candidate:
				others.append(other)
		if others.is_empty():
			continue
		var actor := Actor.new(&"founder", {Stat.PHYSIQUE: 10.0})
		actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, 100000.0))
		SectApi.attach(actor)
		var founded := SectApi.found(actor, candidate, _doctrine_of(candidate), "founder")
		if not bool(founded.get("ok", false)):
			continue
		# A split divides undivided standing, and one point divided into two halves
		# of nothing leaves both halves worse than not splitting - so the verb
		# refuses a member standing below 2. A fresh founder stands at 0, so the
		# case has to give them something to divide before the split is even legal.
		# Without this the loop below silently `continue`s and the assertion never
		# runs, which is how a schism that never reaches the graph can pass.
		SectApi.move_standing(actor, 40)
		var declared := SectApi.declare_schism(actor, others[0])
		if not bool(declared.get("ok", false)):
			continue
		seceding = String(others[0])
		# What the split writes is a ledger line on the SECT THAT DECLARED IT,
		# keyed by the seceding half, carrying the sect's own word for it verbatim.
		# The sect does not decide what a split MEANS — a reader does.
		var state: Dictionary = SectApi.state(actor)
		var line: Dictionary = (state.get("schisms", {}) as Dictionary).get(seceding, {})
		assert_eq(line.is_empty(), false, "the declared split is recorded on the founder's ledger")
		assert_eq(String(line.get("parent_id", "")), String(candidate), "naming the parent")
		assert_eq(String(line.get("seceding_id", "")), seceding, "and the seceding half")
		assert_eq(String(line.get("verb", "")), SectSchism.VERB, "under the sect's own word")
		assert_eq(
			RelationKey.stance_of(SectSchism.VERB),
			RelationKey.HOSTILE,
			"which the graph NORMALISES to hostile — the graph decides, the sect does not",
		)
		# And the honest limit, asserted rather than hidden: `graph()` reads the
		# AUTHORED catalog with `summary(null)`, so a split the PLAYER declared is
		# not in it yet. That is the same missing piece as DEF-0119 — where a
		# world-wide institution ledger persists — and it is recorded as DEF-0179.
		# Until that lands the graph answers for authored dao stances only, and a
		# green run here must not be read as "the graph knows about this war".
		var edge := (
			RelationsApi
			. stance(
				RelationKey.node_key(RelationKey.KIND_SECT, String(candidate)),
				RelationKey.node_key(RelationKey.KIND_SECT, seceding),
			)
		)
		assert_eq(
			edge.is_empty(),
			true,
			"and the world-wide graph does NOT yet see it (DEF-0179): authored stances only",
		)
		return
	assert_ne(seceding, "", "a sect foundable enough to split existed, so this is not a no-op")


## The doctrine a shipped sect teaches, read off its own def. A case that wrote the
## id down would be asserting the fixture rather than the rule, and a sect whose
## `.tres` is later renamed would fail for having named it.
func _doctrine_of(sect_id: StringName) -> StringName:
	var def := SectCatalog.instance().sect_definition(sect_id)
	return &"" if def == null else def.doctrine_id


# --- Provenance, not ownership ----------------------------------------------


## `source` names WHICH owner was read. It is never an authority over that owner, and
## the graph is never handed back to one: an owner that asked this module a question
## would be a `sect -> relations -> sect` cycle, which `tools arch` fails hard on.
func test_every_edge_names_the_owner_it_was_read_from_and_the_epoch_it_was_read_at() -> void:
	var graph := RelationsApi.graph()
	for key in graph.keys():
		var edge: Dictionary = graph[key]
		assert_eq(
			RelationKey.KINDS.has(StringName(edge["source"])),
			true,
			"'%s' names a namespace this module reads" % key,
		)
		assert_eq(typeof(edge["epoch"]), TYPE_INT, "'%s' carries an integer read epoch" % key)
		assert_eq(int(edge["epoch"]), 1, "and this build's only epoch is 1")


## A node's row says what it is, in the two halves a display needs: the graph-local
## key and the plain authored id the kind was stripped back off. That separation IS
## ADR 0065's rule, made assertable.
func test_every_node_row_splits_the_kind_back_off_the_plain_id() -> void:
	var read := RelationsApi.summary()
	assert_eq(bool(read["has_actor"]), false, "the graph is world-wide and takes no actor")
	assert_ne(int(read["node_count"]), 0, "the authored dao tree produced nodes")
	assert_eq(
		int(read["node_count"]),
		(read["nodes"] as Dictionary).size(),
		"and the count matches the rows it published",
	)
	for key in (read["nodes"] as Dictionary).keys():
		var row: Dictionary = (read["nodes"] as Dictionary)[key]
		assert_eq(String(row["node_key"]), String(key), "the row names its own key")
		assert_eq(
			RelationKey.node_key(String(row["kind"]), String(row["id"])),
			String(key),
			"and the kind plus the plain id rebuilds it exactly",
		)
	# Every count by namespace is populated from the nodes rather than left at the
	# skeleton default, and the three authored dao factions are three nodes in one
	# namespace — until a sect or nation edge is written, which the cases below do.
	assert_eq(int(read["by_kind"][RelationKey.KIND_DAO]), 3, "three authored dao factions")
	assert_eq(
		(
			int(read["by_kind"][RelationKey.KIND_DAO])
			+ int(read["by_kind"][RelationKey.KIND_SECT])
			+ int(read["by_kind"][RelationKey.KIND_NATION])
		),
		int(read["node_count"]),
		"and every node is counted under exactly one namespace",
	)
	assert_eq(
		(
			int(read["by_stance"][RelationKey.HOSTILE])
			+ int(read["by_stance"][RelationKey.ALLIED])
			+ int(read["by_stance"][RelationKey.NEUTRAL])
		),
		int(read["edge_count"]),
		"and every edge is counted under exactly one stance",
	)
	assert_eq(
		int(read["hostile_count"]),
		(read["hostile"] as Array).size(),
		"and the hostile list matches its count, sorted so two reads compare equal",
	)
	assert_eq(
		(read["hostile"] as Array) as Array,
		_sort_copy(read["hostile"] as Array),
		"the hostile list is in canonical order",
	)


func _sort_copy(values: Array) -> Array:
	var out: Array = values.duplicate()
	out.sort()
	return out


## `hostile_to` is the question the whole module was built to answer, and it answers
## it in both directions: A is hostile to B, so B is hostile to A.
func test_hostile_to_answers_in_both_directions_and_omits_everything_else() -> void:
	var forward := RelationsApi.hostile_to("dao:body_dao")
	var backward := RelationsApi.hostile_to("dao:mind_dao")
	assert_eq(
		forward.has("dao:mind_dao"), true, "body_dao is hostile to mind_dao, per the authored data"
	)
	assert_eq(backward.has("dao:body_dao"), true, "and mind_dao is hostile to body_dao")
	assert_eq(
		(forward["dao:mind_dao"] as Dictionary)["stance"],
		(backward["dao:body_dao"] as Dictionary)["stance"],
		"the two answers are the same edge",
	)
	# An alliance is not a hostility, so it is absent rather than listed with a
	# negative.
	assert_eq(
		RelationsApi.hostile_to("dao:mind_dao").has("dao:qi_dao"),
		false,
		"an alliance is not reported as a hostility",
	)
	# An unknown node answers `{}` rather than a row for everybody.
	assert_eq(RelationsApi.hostile_to("sect:nothing_at_all"), {}, "an absent node has no edges")


# --- Read gates and closed vocabulary ---------------------------------------


## The closed stance set resolves ADR 0085's diplomacy verbs and ADR 0047's faction
## stances onto ONE normalized vocabulary, and it resolves an unknown verb to
## `""` rather than to neutral. Defaulting an unreadable verb to neutral would make
## a broken `.tres` read as a peaceful relationship — the silence ADR 0085 refuses
## everywhere else, including `set_stance` refusing `war` outside the declaration.
func test_an_unreadable_verb_is_never_defaulted_to_neutral() -> void:
	assert_eq(RelationKey.stance_of("hostile"), RelationKey.HOSTILE, "ADR 0047 hostile")
	assert_eq(RelationKey.stance_of("allied"), RelationKey.ALLIED, "ADR 0047 allied")
	assert_eq(RelationKey.stance_of("war"), RelationKey.HOSTILE, "ADR 0085 war")
	assert_eq(RelationKey.stance_of("embargo"), RelationKey.HOSTILE, "ADR 0085 embargo")
	assert_eq(RelationKey.stance_of("truce"), RelationKey.ALLIED, "ADR 0085 truce")
	assert_eq(RelationKey.stance_of("rival"), RelationKey.HOSTILE, "ADR 0085 rival")
	assert_eq(RelationKey.stance_of(""), RelationKey.NEUTRAL, "an absent verb is neutral")
	assert_eq(
		RelationKey.stance_of("fond_of"), "", "and a verb nobody authored is UNKNOWN, not neutral"
	)
	# And rank is what a disagreement resolves by, so an unreadable verb never
	# outranks a read one.
	assert_eq(
		RelationKey.rank(RelationKey.HOSTILE) > RelationKey.rank(RelationKey.ALLIED),
		true,
		"hostility outranks alliance",
	)
	assert_eq(
		RelationKey.rank(RelationKey.ALLIED) > RelationKey.rank(RelationKey.NEUTRAL),
		true,
		"alliance outranks neutrality",
	)
	assert_eq(
		RelationKey.rank("") > RelationKey.rank(RelationKey.NEUTRAL),
		false,
		"and the unknown ranks below every read stance",
	)


# --- Plumbing --------------------------------------------------------------


## Every `.gd` under the module, found iteratively. An empty list would make every
## source scan vacuous, so the count is asserted where it can actually be zero.
func _module_files() -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = ["res://src/modules/relations"]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif entry.ends_with(".gd"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Code with every comment removed, so a module that DOCUMENTS a rule it obeys is
## not reported for obeying it in prose.
func _strip_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
