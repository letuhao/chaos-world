class_name WorldmapGraph
extends RefCounted

## The spatial graph: nodes contain, edges connect, and the two never imply
## each other. A cave's `parent` is the hillside while its portal edge lands
## in another universe; a domain sits inside a world yet owns a separate map.
## All traversal is bounded breadth-first over snapshots — a graph with a
## cycle in it is legal data here, so no walk may assume acyclicity.

var _nodes: Dictionary = {}
var _edges: Array = []


## Register a node (`id`, `kind`, `parent`). Refuses empties and duplicates
## by name; the graph never holds two versions of one place.
func add_node(node: Dictionary) -> Dictionary:
	var node_id := String(node.get("id", ""))
	if node_id.is_empty():
		return {"ok": false, "reason": "empty_node_id"}
	if _nodes.has(node_id):
		return {"ok": false, "reason": "duplicate_node", "id": node_id}
	_nodes[node_id] = {
		"id": node_id,
		"kind": StringName(node.get("kind", "")),
		"parent": String(node.get("parent", "")),
	}
	return {"ok": true, "reason": "", "id": node_id}


## Register a travel edge. Endpoints must exist first: an edge to nowhere is
## a portal to a wall, and walls are reported, not stored.
func add_edge(edge: Dictionary) -> Dictionary:
	var from_id := String(edge.get("from", ""))
	var to_id := String(edge.get("to", ""))
	if not _nodes.has(from_id) or not _nodes.has(to_id):
		return {"ok": false, "reason": "unknown_endpoint"}
	(
		_edges
		. append(
			{
				"from": from_id,
				"to": to_id,
				"kind": StringName(edge.get("kind", "")),
				"from_cell": edge.get("from_cell", Vector2i(-1, -1)),
				"to_cell": edge.get("to_cell", Vector2i(-1, -1)),
				"two_way": bool(edge.get("two_way", true)),
				"hook": String(edge.get("hook", "")),
				"toll": _normalize_toll(edge.get("toll", {})),
			}
		)
	)
	return {"ok": true, "reason": ""}


## The price of crossing, repaired never believed: `{amount}` with a
## non-negative int, or `{}` for a free crossing. A malformed toll is a free
## crossing rather than a corrupt edge — the gate still decides, and a gate
## with no price to read leaves the purse alone.
static func _normalize_toll(toll: Variant) -> Dictionary:
	if not (toll is Dictionary):
		return {}
	var amount = (toll as Dictionary).get("amount", 0)
	if (amount is int or amount is float) and not (amount is bool) and int(amount) > 0:
		return {"amount": int(amount)}
	return {}


## The node, or `{}` when no such place exists.
func node(node_id: String) -> Dictionary:
	return (_nodes.get(node_id, {}) as Dictionary).duplicate(true)


## Every node id, sorted. Sorted so two runs enumerate the same graph.
func node_ids() -> Array:
	var out := _nodes.keys()
	out.sort()
	return out


## Children contained in `node_id` — containment only, never travel.
func children_of(node_id: String) -> Array:
	var out: Array = []
	for id in node_ids():
		if String((_nodes[id] as Dictionary).get("parent", "")) == node_id:
			out.append(id)
	return out


## Edges leaving `node_id`, in registration order.
func edges_from(node_id: String) -> Array:
	var out: Array = []
	for edge in _edges:
		if String((edge as Dictionary).get("from", "")) == node_id:
			out.append((edge as Dictionary).duplicate(true))
	return out


## Every node reachable from `node_id` over travel edges, breadth-first.
## Bounded by the node count: cycles are legal, so the visited set — not a
## depth — is what terminates the walk.
func reachable(node_id: String) -> Array:
	var seen := {node_id: true}
	var queue: Array = [node_id]
	while not queue.is_empty():
		var current := String(queue.pop_front())
		for edge in edges_from(current):
			var next := String(edge.get("to", ""))
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	var out: Array = []
	for id in node_ids():
		if seen.has(id) and id != node_id:
			out.append(id)
	return out
