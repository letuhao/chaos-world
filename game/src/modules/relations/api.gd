class_name RelationsApi
extends RefCounted

## Public facade for the `relations` module (BL-0199). Other modules may reference
## ONLY this file (`api.gd`).
##
## ## One question: "who is hostile to whom", across every tier at once
##
## Three owners already answer that question about themselves and each answers it
## in its own vocabulary — ADR 0047's authored dao relationships, ADR 0085's one
## canonical diplomacy row per pair, BL-0197's declared schism. Before this module
## existed, "is this sect at war with that nation" had no answer anywhere, because
## every row lives under a different ledger keyed by a different id.
##
## ## ## The graph READS every owner and STORES none of them
##
## That is the whole architectural claim, and it is why the module exists rather
## than a `relations` sub-table in each owner. A second writer of a stance would be
## a fourth place for the answer to live and a second thing to fall out of date.
## Here there is nothing to keep: `graph()` is a pure function of what the owners
## publish, so the graph cannot be stale, and `stance()` cannot disagree with the
## module that wrote the row.
##
## ## ## A cache here is FREE TO BE WRONG
##
## `RelationsApi.shared` is an opt-in memo, never a source. Wipe it, or never take
## it, and `graph()` returns the IDENTICAL dictionary — `tests/modules/relations/
## test_relations_cache.gd` asserts exactly that, because a cache whose loss changed
## an answer would be a cache every call site had to defend against, which is a
## cache with no benefit. `RelationsApi.epoch()` is the read epoch each edge carries;
## there is no clock and no invalidation (DEF-0111).
##
## ## ## Owners must NEVER ask this graph a question
##
## `sect → relations → sect` is a cycle and `tools arch` fails hard on cycles, so
## the dependency is one-way by construction: owners WRITE their own stance, the
## graph READS. `tests/modules/relations/test_relations_no_back_edge.gd` scans every
## `.gd` under `modules/{world,sect,nation}/` for `RelationsApi` or any `relations`
## symbol and fails on a hit — the arch-level proof, because `BARE_REF_UNITS`
## excludes `modules/*` and a back edge written in code would otherwise be invisible
## to the gate exactly as `nation → sect` is.
##
## ## ## The node key is `"{kind}:{id}"`, and the ids inside stay PLAIN
##
## ADR 0065's rule: an authored id is `qi_dao`, never `dao.qi_dao`, because the kind
## is carried by the catalog that holds it. This graph is the one place two
## namespaces have to share a key space, so the KIND appears here and nowhere else —
## `RelationKey.id_of("sect:iron_vine")` is `iron_vine`, which is the id a catalog
## lookup uses. A node key is a graph-local address, never an authored id.

## The process-wide memo, for a caller that wants one. Never read as the truth: wipe
## it and every answer is identical. `null` until somebody asks for it, so a process
## that never uses this module mints nothing.
static var shared: RelationsApi = null

## The single memoized instance, built lazily. A facade of statics has no instance
## to hang state on, so this is the one thing `shared` exists to hold.
static var _memo: Dictionary = {}


## The graph, or the memoized copy when one has been taken. Rebuild it by assigning
## `RelationsApi.shared = null` — legal, free, and produces the identical dictionary,
## and that property is the contract rather than an accident.
##
## ## The memo is a SPEEDUP over a rebuild, never a source of its own
##
## It is not invalidated on a write, because **there is nothing to invalidate on**:
## `RelationGraph` reads `summary(null)` from every owner, so what it sees is the
## AUTHORED catalog, and it holds no per-actor state for an owner write to change.
##
## ## Player-driven stances arrive through the world ledger, never an actor
##
## A stance the player declares — a schism, a war — lives on the WORLD polity
## ledger beside the actor (ADR 0931), and reaches `graph()`, `stance()` and
## `hostile_to()` when the caller hands that ledger in as `world_polity`. Reading
## the caller's actor instead would make the graph world-wide in name and
## single-player in fact, which DEF-0179 forbids. Bare `graph()` still answers the
## authored catalog only. The memo covers the bare call alone: a ledger-handed
## call always rebuilds, because the ledger is the thing that moves.
static func graph(world_polity: Dictionary = {}) -> Dictionary:
	if shared != null and not _memo.is_empty() and world_polity.is_empty():
		return _memo.duplicate(true)
	var built := RelationGraph.build(world_polity)
	if shared != null and world_polity.is_empty():
		_memo = built
	return built


static func _fingerprint(edges: Dictionary) -> String:
	var parts: Array[String] = []
	for key in edges.keys():
		var edge = edges[key]
		var stance := (
			"" if not (edge is Dictionary) else String((edge as Dictionary).get("stance", ""))
		)
		parts.append("%s=%s" % [key, stance])
	parts.sort()
	return "|".join(parts)


## The edge between two node keys, or `{}` when the two have never been declared in
## any order.
##
## `{}` is ADR 0083's FIRST state and it is the honest answer for a pair nobody has
## spoken about — **never** a neutral edge invented to fill the gap, because an
## invented edge is an answer to a question nobody asked. Read it with the ids
## swapped and you get the identical dictionary: the row is stored once under the
## lexicographically ordered pair, so a one-sided opinion is structurally impossible
## (ADR 0047 as extended by ADR 0085).
static func stance(a_node: String, b_node: String, world_polity: Dictionary = {}) -> Dictionary:
	var key := RelationKey.pair_key(String(a_node), String(b_node))
	if key == "":
		return {}
	var held = graph(world_polity).get(key, null)
	return (held as Dictionary).duplicate(true) if held is Dictionary else {}


## Every node `node_key` is hostile to, as `{node_key: edge}`. Keys are `String`s in
## `"{kind}:{id}"` form; the values are the same edges `stance()` returns, so a
## caller gets the verdict and its provenance in one pass.
##
## An unreadable or absent node answers `{}` rather than a neutral row, for the same
## reason `stance()` does.
static func hostile_to(node_key: String, world_polity: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	# Bound once: two builds could disagree, and a ledger-handed build must never
	# be read through the bare one.
	var edges := graph(world_polity)
	for key in edges.keys():
		var held = edges[key]
		if not (held is Dictionary):
			continue
		var edge: Dictionary = held as Dictionary
		if not RelationKey.is_hostile(String(edge["stance"])):
			continue
		var other := ""
		if String(edge["a"]) == node_key:
			other = String(edge["b"])
		elif String(edge["b"]) == node_key:
			other = String(edge["a"])
		else:
			continue
		out[other] = edge.duplicate(true)
	return out


## One primitive-only read for a screen: every edge, every node, and the counts by
## namespace and by stance.
##
## The whole graph is published rather than a filtered slice because there is no
## actor to filter by — this is a world-wide question — and because the facade's
## cap is real, so the read a screen wants folds in here instead of becoming a
## fifth method.
##
## `actor` is accepted and deliberately unused beyond an emptiness flag: a screen
## holds one, and a module whose summary took none would be the odd shape. It is
## never consulted as authority over the graph — the owners are.
static func summary(actor: Actor = null) -> Dictionary:
	var edges := graph()
	# The hostile pair keys are collected into a LOCAL array rather than into the
	# skeleton: a typed `var hostile: Array = out["hostile"]` reads a `Variant` and
	# raises at runtime the moment the literal beside it is a Dictionary, so the
	# skeleton holds `{}` and the array is built and assigned at the end.
	var hostile: Array = []
	var out: Dictionary = {
		"has_actor": actor != null,
		"edge_count": edges.size(),
		"edges": edges.duplicate(true),
		"nodes": {},
		"node_count": 0,
		"hostile_count": 0,
		"by_kind": {},
		"by_stance": {},
		"hostile": [],
	}
	for kind in RelationKey.KINDS:
		out["by_kind"][String(kind)] = 0
	for stance_name in RelationKey.STANCES:
		out["by_stance"][String(stance_name)] = 0
	for key in edges.keys():
		var held = edges[key]
		if not (held is Dictionary):
			continue
		var edge: Dictionary = held as Dictionary
		_register(out, String(edge["a"]))
		_register(out, String(edge["b"]))
		var stance_name := String(edge["stance"])
		if out["by_stance"].has(stance_name):
			out["by_stance"][stance_name] = int(out["by_stance"][stance_name]) + 1
		if RelationKey.is_hostile(stance_name):
			out["hostile_count"] = int(out["hostile_count"]) + 1
			hostile.append(String(key))
	# Sorted so two reads of the same graph compare equal as arrays, not only as
	# maps: a display built from this cannot depend on dictionary iteration order.
	hostile.sort()
	out["hostile"] = hostile
	return out


# --- Internals -------------------------------------------------------------


## One node into the read model: the key, its namespace, and the plain id that key
## stands for. ADR 0065's rule made visible — the kind is separated here so a panel
## can label the row without ever having to re-parse the key.
static func _register(out: Dictionary, node_key: String) -> void:
	var nodes: Dictionary = out["nodes"]
	if nodes.has(node_key):
		return
	var kind := RelationKey.kind_of(node_key)
	nodes[node_key] = {
		"node_key": node_key,
		"kind": kind,
		"id": RelationKey.id_of(node_key),
	}
	if out["by_kind"].has(kind):
		out["by_kind"][kind] = int(out["by_kind"][kind]) + 1
	out["node_count"] = int(out["node_count"]) + 1
