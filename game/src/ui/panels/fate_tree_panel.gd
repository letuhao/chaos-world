class_name FateTreePanel
extends PanelContainer

## The fate synergy tree: every fate as a node, with edges for unlock/requires
## relationships, color-coded by earned/unearned (ADR 0383).
##
## A pure consumer of the `destiny` facade. It reads `DestinyApi.summary(actor)`
## and holds no graph logic of its own: the synergy edges come from each fate's
## `unlocks` / `requires` lists, and the layout is a topological sort computed
## from those edges.
##
## Read-only by design (ADR 0065): no selection, no earn action, no revoke.
## `summary()` is the testable surface.

const CATEGORY_UNKNOWN := "uncategorised"
const LAYER_GAP := 8
const NODE_GAP := 4

var _view: Dictionary = {}
var _layers: Array = []  # Array of Array[StringName]
var _node_positions: Dictionary = {}  # fate_id -> Vector2
var _card_variation := &"LockedCard"

var _graph: Control = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render the tree from a `DestinyApi.summary(actor)` snapshot.
func show_tree(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_layout()
	_render()


func clear() -> void:
	_view = {}
	_layers = []
	_node_positions = {}
	_render()


## Everything the panel shows, primitives only. `{}` when empty.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"fate_count": (_view.get("fates", {}) as Dictionary).size(),
		"destiny_count": (_view.get("destinies", {}) as Dictionary).size(),
		"synergy_edge_count": _edge_count(),
		"layer_count": _layers.size(),
		"held_fates": _held_fates(),
		"unheld_fates": _unheld_fates(),
		"synergy_edges": _synergy_edges(),
		"destiny_gates": _destiny_gates(),
	}


# --- Layout ---------------------------------------------------------------


## Compute a layered layout from the synergy graph. Each layer holds fates
## whose prerequisites are all in earlier layers. Bounded by the catalog size.
func _layout() -> void:
	_layers = []
	_node_positions = {}
	var fates := _view.get("fates", {}) as Dictionary
	if fates.is_empty():
		return
	# Build adjacency: fate -> fates it unlocks
	var unlocks := {}
	var in_degree := {}
	for fate_id in fates.keys():
		var view: Dictionary = fates[fate_id]
		var edges: Array = view.get("unlocks", [])
		unlocks[String(fate_id)] = edges
		in_degree[String(fate_id)] = 0
	for fate_id in fates.keys():
		var view: Dictionary = fates[fate_id]
		for required_id in view.get("requires", []):
			var key := String(required_id)
			if in_degree.has(key):
				in_degree[String(fate_id)] = int(in_degree[String(fate_id)]) + 1
	# Topological sort into layers. Bounded by the catalog size.
	var remaining := fates.keys().size()
	var current_layer: Array = []
	for fate_id in fates.keys():
		if int(in_degree[String(fate_id)]) == 0:
			current_layer.append(String(fate_id))
	var max_layers := fates.keys().size() + 1
	var layer_index := 0
	while not current_layer.is_empty() and layer_index < max_layers:
		_layers.append(current_layer.duplicate())
		var next_layer: Array = []
		for fate_id in current_layer:
			remaining -= 1
			for unlocked_id in unlocks[fate_id]:
				var key := String(unlocked_id)
				if not in_degree.has(key):
					continue
				in_degree[key] = int(in_degree[key]) - 1
				if int(in_degree[key]) == 0:
					next_layer.append(key)
		current_layer = next_layer
		layer_index += 1
	# Any remaining fates (should not happen in an acyclic graph) go in a
	# final layer so they are still rendered.
	if remaining > 0:
		var last_layer: Array = []
		for fate_id in fates.keys():
			var key := String(fate_id)
			if int(in_degree[key]) > 0:
				last_layer.append(key)
		if not last_layer.is_empty():
			_layers.append(last_layer)


# --- Rendering ------------------------------------------------------------


func _render() -> void:
	if _graph == null:
		return
	for child in _graph.get_children():
		_graph.remove_child(child)
		child.free()
	if _view.is_empty():
		return
	var fates := _view.get("fates", {}) as Dictionary
	for layer_index in _layers.size():
		var layer: Array = _layers[layer_index]
		for node_index in layer.size():
			var fate_id := String(layer[node_index])
			var view: Dictionary = fates.get(fate_id, {})
			if view.is_empty():
				continue
			var node := _make_node(fate_id, view, layer_index, node_index)
			_graph.add_child(node)


func _make_node(
	fate_id: String, view: Dictionary, layer_index: int, node_index: int
) -> Control:
	var held := bool(view.get("held", false))
	var node := PanelContainer.new()
	node.name = "FateNode%s" % fate_id
	node.theme_type_variation = &"EarnedCard" if held else &"LockedCard"
	var vbox := VBoxContainer.new()
	node.add_child(vbox)
	var head := Label.new()
	head.text = String(view.get("display_name", "")) if held or String(view.get("display_name", "")) != "" else "Unnamed"
	head.theme_type_variation = &"EarnedLabel" if held else &"LockedLabel"
	vbox.add_child(head)
	var meta := Label.new()
	meta.text = _meta(view)
	meta.theme_type_variation = &"EffectLabel" if held else &"LockedLabel"
	vbox.add_child(meta)
	# Position in the layered layout.
	var x := 10 + node_index * 130
	var y := 10 + layer_index * 80
	node.position = Vector2(x, y)
	node.custom_minimum_size = Vector2(120, 60)
	_node_positions[fate_id] = Vector2(x, y)
	return node


func _meta(view: Dictionary) -> String:
	var parts: Array = []
	if bool(view.get("held", false)):
		parts.append("Earned")
	else:
		parts.append("Locked")
	var unlocks: Array = view.get("unlocks", [])
	if not unlocks.is_empty():
		parts.append("unlocks %d" % unlocks.size())
	var requires: Array = view.get("requires", [])
	if not requires.is_empty():
		parts.append("needs %d" % requires.size())
	return " · ".join(PackedStringArray(parts))


# --- Reporting ------------------------------------------------------------


func _held_fates() -> Array:
	var out: Array = []
	var fates := _view.get("fates", {}) as Dictionary
	for fate_id in fates.keys():
		if bool((fates[fate_id] as Dictionary).get("held", false)):
			out.append(fate_id)
	return out


func _unheld_fates() -> Array:
	var out: Array = []
	var fates := _view.get("fates", {}) as Dictionary
	for fate_id in fates.keys():
		if not bool((fates[fate_id] as Dictionary).get("held", false)):
			out.append(fate_id)
	return out


func _synergy_edges() -> Array:
	var out: Array = []
	var fates := _view.get("fates", {}) as Dictionary
	for fate_id in fates.keys():
		var view: Dictionary = fates[fate_id]
		for unlocked_id in view.get("unlocks", []):
			out.append({"from": fate_id, "to": String(unlocked_id), "kind": "unlocks"})
		for required_id in view.get("requires", []):
			out.append({"from": String(required_id), "to": fate_id, "kind": "requires"})
	return out


func _edge_count() -> int:
	return _synergy_edges().size()


func _destiny_gates() -> Array:
	var out: Array = []
	var destinies := _view.get("destinies", {}) as Dictionary
	for destiny_id in destinies.keys():
		var view: Dictionary = destinies[destiny_id]
		if not bool(view.get("held", false)):
			var blocked = view.get("blocked_by", [])
			if not (blocked as Array).is_empty():
				out.append({"destiny": destiny_id, "blocked_by": blocked})
	return out


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _graph != null:
		return
	_scroll = ScrollContainer.new()
	_scroll.name = "TreeScroll"
	add_child(_scroll)
	_graph = Control.new()
	_graph.name = "TreeGraph"
	_graph.custom_minimum_size = Vector2(800, 600)
	_scroll.add_child(_graph)
