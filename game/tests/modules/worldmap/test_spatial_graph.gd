extends TestCase

## THE SPATIAL GRAPH: containment and travel are independent.
##
## A cave contains a secret realm while its portal lands in another universe;
## a domain sits inside a world yet owns a separate map. Every case below
## builds that shape and asserts the graph tells containment and travel
## apart — because a system that derives travel from parentage cannot model a
## portal, and one that derives containment from edges cannot model a nested
## world with no door back.


func _graph() -> WorldmapGraph:
	var graph := WorldmapGraph.new()
	WorldmapApi.clear_graph()
	return graph


func test_nodes_register_and_duplicates_refuse() -> void:
	var graph := _graph()
	assert_eq(
		graph.add_node({"id": "cave", "kind": &"wilderness", "parent": "hills"}),
		{"ok": true, "reason": "", "id": "cave"},
		"a node registers"
	)
	assert_eq(
		String(graph.add_node({"id": "cave", "kind": &"wilderness"}).get("reason", "")),
		"duplicate_node",
		"and twice is refused by name"
	)
	assert_eq(
		String(graph.add_node({"kind": &"town"}).get("reason", "")),
		"empty_node_id",
		"as is a node with no id"
	)


func test_children_read_containment_not_travel() -> void:
	var graph := _graph()
	graph.add_node({"id": "world", "kind": &"world", "parent": ""})
	graph.add_node({"id": "sect", "kind": &"sect", "parent": "world"})
	graph.add_node({"id": "pocket", "kind": &"pocket_world", "parent": "sect"})
	assert_eq(graph.children_of("world"), ["sect"], "one level, not the transitive set")
	assert_eq(graph.children_of("sect"), ["pocket"], "a sect contains its pocket world")


func test_an_edge_to_nowhere_is_refused() -> void:
	var graph := _graph()
	graph.add_node({"id": "town", "kind": &"town", "parent": ""})
	assert_eq(
		String(
			graph.add_edge({"from": "town", "to": "elsewhere", "kind": &"portal"}).get("reason", "")
		),
		"unknown_endpoint",
		"a portal to a wall is reported, not stored"
	)


func test_a_cycle_terminates_and_a_portal_crosses_worlds() -> void:
	var graph := _graph()
	graph.add_node({"id": "town", "kind": &"town", "parent": ""})
	graph.add_node({"id": "far", "kind": &"universe", "parent": ""})
	graph.add_edge({"from": "town", "to": "far", "kind": &"portal"})
	graph.add_edge({"from": "far", "to": "town", "kind": &"portal"})
	assert_eq(
		graph.reachable("town"),
		["far"],
		"a portal joins nodes that share no parent, and the cycle ends"
	)


func test_the_facade_builds_a_graph_or_names_the_refusal() -> void:
	WorldmapApi.clear_graph()
	var outcome := (
		WorldmapApi
		. build_graph(
			[
				{"id": "world", "kind": &"world", "parent": ""},
				{"id": "cave", "kind": &"dungeon", "parent": "world"},
			],
			[{"from": "world", "to": "cave", "kind": &"doorway"}]
		)
	)
	assert_eq(bool(outcome.get("ok", false)), true, "a small graph builds")
	assert_eq(int(outcome.get("nodes", 0)), 2, "naming its count")
	assert_eq(WorldmapApi.children_of("world"), ["cave"], "containment reads back")
	assert_eq(WorldmapApi.edges_from("world").size(), 1, "and so does travel")
	WorldmapApi.clear_graph()
