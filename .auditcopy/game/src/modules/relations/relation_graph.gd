class_name RelationGraph
extends RefCounted

## Reads every owner's stance rows and projects them into ONE graph of
## `"{kind}:{id}"` nodes and symmetric pair edges. **It stores nothing.**
##
## ## A derived read model, rebuilt on every call
##
## There is no cache, no epoch bookkeeping and no ledger. `build()` is a pure
## function of what the owners currently publish, so the graph cannot drift from the
## truth it describes — there is no second copy to fall out of date, which is the
## defect class this repository keeps refusing (ADR 0066's three copies of
## `RATE_STEP`, ADR 0050's three unreconciled magnitude tables).
##
## ## The owners write; this reads, and the direction is one-way
##
## `world` owns dao faction relationships (ADR 0047), `nation` owns diplomacy
## (ADR 0085), and `sect` owns rivalry — currently recorded as a declared schism
## (BL-0197), which is the only stance `sect` has written. This file reaches all
## three through one `preload` each and **spell every other identifier as a plain
## id**, because `BARE_REF_UNITS` excludes `modules/*`: a bare `SectApi` reference
## out of a module reports zero violations and a cycle written that way is
## invisible to `_find_cycle` (ADR 0083).
##
## Nothing here is ever handed back to an owner. An owner that asked this graph a
## question would be a `sect → relations → sect` cycle, which `tools arch` fails
## hard on — so the direction is one-way by construction, and
## `tests/modules/relations/test_relations_no_back_edge.gd` proves no owner under
## `modules/{world,sect,nation}/` names this module or any `relations` symbol.

## The facade seams. One `res://` edge each, which the resolver DOES read, so every
## edge here is visible to `tools arch` rather than to review alone.
const WORLD_FACADE := preload("res://src/modules/world/api.gd")
const SECT_FACADE := preload("res://src/modules/sect/api.gd")
const NATION_FACADE := preload("res://src/modules/nation/api.gd")

## The edge's fields. `source` is PROVENANCE — which owner was read — and never
## ownership: nothing here is authoritative over the module that wrote the row.
const EDGE_A := "a"
const EDGE_B := "b"
const EDGE_VERB := "verb"
const EDGE_STANCE := "stance"
const EDGE_SOURCE := "source"
const EDGE_EPOCH := "epoch"

## `NationState.PAIR_SEPARATOR`, spelled as a plain character rather than named from
## the owner. Naming `NationState` by class name would be exactly the bare reference
## `BARE_REF_UNITS` cannot see, and a literal separator and a shared one are the same
## character — so the module's edge to `nation` stays at one `preload`.
const NATION_PAIR_SEPARATOR := "|"

## `res://data/world/factions` — ADR 0047's authored dao tree. A path rather than a
## `world` seam because the world facade ships no faction read, and adding one would
## spend a method on a facade the module cap already governs. The file TEXT is
## scanned for `faction_id = &"<id>"` first, so only a real `WorldFactionDef` is
## ever loaded — the `SectCatalog` filter, for the same reason.
const FACTIONS_ROOT := "res://data/world/factions"

## The `WorldFactionDef` script class a `.tres` must declare to be read as a faction.
const FACTION_SCRIPT_CLASS := "WorldFactionDef"


## Every edge the three owners currently publish, keyed by the canonical pair.
static func build() -> Dictionary:
	var rows: Dictionary = {}
	_read_dao(rows)
	_read_nation(rows)
	_read_sect(rows)
	return rows


# --- Internals -------------------------------------------------------------


## ADR 0047's authored dao relationships: `WorldFactionDef.relationships` is an
## `Array[Dictionary]` of `{faction_id, stance}`, symmetric by ADR.
##
## **Symmetry is taken from the AUTHOR, not imposed here.** The data declares both
## directions — `body_dao.tres` names `mind_dao` hostile and `mind_dao.tres` names
## `body_dao` hostile — so each authored row is read once and `RelationKey`'s
## canonical key collapses the two spellings into one edge. A one-sided row cannot
## therefore create a second, disagreeing edge: the two would simply resolve to one
## verdict by rank.
static func _read_dao(rows: Dictionary) -> void:
	for faction in _dao_factions():
		var self_node := RelationKey.node_key(
			RelationKey.KIND_DAO, String(faction.get("faction_id", ""))
		)
		if self_node == "":
			continue
		for relationship in faction.get("relationships", []) as Array:
			if not (relationship is Dictionary):
				continue
			var row: Dictionary = relationship as Dictionary
			var verb := String(row.get("stance", ""))
			_merge(
				rows,
				self_node,
				RelationKey.node_key(RelationKey.KIND_DAO, String(row.get("faction_id", ""))),
				verb,
				RelationKey.stance_of(verb),
				RelationKey.KIND_DAO
			)


## ADR 0085's one canonical stance row per unordered pair. `NationApi.summary`
## publishes each pair once already, so this walks the published map and adds
## nothing of its own.
##
## The node ids here are the POLITY ids the ledger stores — which the ledger itself
## fills with an actor id, not a nation id. That is ADR 0083's disclosed gap rather
## than this module's to fix, and the edge says what the owner said.
static func _read_nation(rows: Dictionary) -> void:
	var stances = _payload(NATION_FACADE).get("stances", {})
	if not (stances is Dictionary):
		return
	for raw_key in (stances as Dictionary).keys():
		var parts := String(raw_key).split(NATION_PAIR_SEPARATOR, false, 1)
		if parts.size() != 2:
			continue
		var held = (stances as Dictionary)[raw_key]
		var verb := "" if not (held is Dictionary) else String((held as Dictionary).get("verb", ""))
		_merge(
			rows,
			RelationKey.node_key(RelationKey.KIND_NATION, String(parts[0])),
			RelationKey.node_key(RelationKey.KIND_NATION, String(parts[1])),
			verb,
			RelationKey.stance_of(verb),
			RelationKey.KIND_NATION
		)


## BL-0197's declared split is the only rivalry `sect` has written, so that is what
## this reads. A split is a split, not a transfer: it is two institutions that were
## one, and the whole question a caller asks of the graph afterwards is whether they
## are still speaking.
##
## The parent node is the sect the member was sworn to — a PLAIN id read out of the
## payload. This module never asks `sect` for anything but its summary.
static func _read_sect(rows: Dictionary) -> void:
	var payload := _payload(SECT_FACADE)
	var parent_node := RelationKey.node_key(
		RelationKey.KIND_SECT, String(payload.get("sect_id", ""))
	)
	if parent_node == "":
		return
	for seceding_id in payload.get("schisms", {}) as Dictionary:
		_merge(
			rows,
			parent_node,
			RelationKey.node_key(RelationKey.KIND_SECT, String(seceding_id)),
			RelationKey.HOSTILE,
			RelationKey.HOSTILE,
			RelationKey.KIND_SECT
		)


## Fold one owner's reading into the ONE canonical row for the pair.
##
## A disagreement between two rows about the same pair resolves by RANK, so a `war`
## is never quietly downgraded to a `truce` by whichever owner was read second, and
## the row that won is the `source` the edge publishes. Provenance, never ownership.
static func _merge(
	rows: Dictionary, a_node: String, b_node: String, verb: String, stance: String, kind: String
) -> void:
	var key := RelationKey.pair_key(a_node, b_node)
	if key == "":
		return
	var held = rows.get(key, null)
	if (
		held is Dictionary
		and RelationKey.rank(String((held as Dictionary)[EDGE_STANCE])) >= RelationKey.rank(stance)
	):
		return
	var pair: Array[String] = RelationKey.split_pair(key)
	rows[key] = {
		EDGE_A: pair[0],
		EDGE_B: pair[1],
		EDGE_VERB: verb,
		EDGE_STANCE: stance,
		EDGE_SOURCE: String(kind),
		# The read epoch. `1` is this build's only epoch: the graph owns no clock
		# (DEF-0111), has no cache to invalidate and no number that could drift from
		# when it was read. It is published as a FIELD rather than omitted so a
		# consumer has one key to ask — and the contract that makes it honest is the
		# one `RelationsApi.graph` is built on: wiping every cache returns the
		# IDENTICAL dictionary, epoch included, or every call site has to rebuild.
		EDGE_EPOCH: 1,
	}


## One facade's `summary()`, or `{}` when it could not be read. No actor: the graph
## is world-wide and has none of its own, and `null` is the `no_actor` payload every
## one of these facades already answers (ADR 0083's first state, "this does not
## exist"). An unanswered question here is an empty graph, never an error and never
## a default.
static func _payload(facade: Script) -> Dictionary:
	var value: Variant = facade.summary(null)
	return (value as Dictionary) if value is Dictionary else {}


## Every authored dao faction, as `{faction_id, relationships}` primitive rows.
## One row per authored faction rather than one per location that happens to carry
## its id, so a faction controlling no place is still a node in the graph — "this
## does not exist" and "it controls nothing" are different facts and only the
## second one is true of an empty location tree.
static func _dao_factions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in ContentScan.files_under(FACTIONS_ROOT):
		var body := FileAccess.get_file_as_string(path)
		if not body.contains('script_class="%s"' % FACTION_SCRIPT_CLASS):
			continue
		var resource := load(path) as Resource
		if resource == null:
			continue
		var faction_id := String(resource.get("faction_id"))
		if faction_id == "":
			continue
		out.append({"faction_id": faction_id, "relationships": _relationships(resource)})
	out.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["faction_id"]) < String(right["faction_id"])
	)
	return out


## One faction's authored `relationships`, coerced row by row. Ids and one verb,
## nothing else: a corrupt `.tres` must not be able to put a `Resource` into this
## graph, and the graph is handed straight to a screen.
static func _relationships(faction: Resource) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var authored = faction.get("relationships")
	if not (authored is Array):
		return out
	for entry in authored as Array:
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry as Dictionary
		(
			out
			. append(
				{
					"faction_id": String(row.get("faction_id", "")),
					"stance": String(row.get("stance", "")),
				}
			)
		)
	return out
