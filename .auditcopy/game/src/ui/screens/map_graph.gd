class_name MapGraph
extends Control

## Draws directed edges between location nodes on the world map.
## Receives edge data and node screen positions, renders lines with
## arrowheads. Edges are colored by the tier of the destination node.

const TIER_EDGE_COLORS := {
	&"mortal_world": Color(0.3, 0.6, 0.9, 0.45),
	&"spirit_world": Color(0.9, 0.7, 0.2, 0.45),
	&"immortal_world": Color(0.7, 0.4, 0.9, 0.45),
	&"transcendent_world": Color(0.9, 0.4, 0.4, 0.45),
}

const EDGE_WIDTH := 2.0
const ARROW_SIZE := 8.0
const NODE_RADIUS_PAD := 28.0

var _edges: Array[Dictionary] = []
var _node_positions: Dictionary = {}


## Update the graph data and trigger a redraw.
func set_graph(edges: Array[Dictionary], node_positions: Dictionary) -> void:
	_edges = edges
	_node_positions = node_positions
	queue_redraw()


func _draw() -> void:
	if _edges.is_empty():
		return
	for edge in _edges:
		var from_id := StringName(edge.get("from", &""))
		var to_id := StringName(edge.get("to", &""))
		var from_pos: Vector2 = _node_positions.get(from_id, Vector2.ZERO)
		var to_pos: Vector2 = _node_positions.get(to_id, Vector2.ZERO)
		if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
			continue
		var tier: StringName = edge.get("tier", &"mortal_world")
		var color: Color = TIER_EDGE_COLORS.get(tier, Color(0.5, 0.5, 0.5, 0.35))
		_draw_edge(from_pos, to_pos, color)


func _draw_edge(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	var start := from + dir * NODE_RADIUS_PAD
	var end := to - dir * NODE_RADIUS_PAD
	draw_line(start, end, color, EDGE_WIDTH)
	_draw_arrow_head(end, start, color)


func _draw_arrow_head(tip: Vector2, from_pos: Vector2, color: Color) -> void:
	var dir := (tip - from_pos).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var base := tip - dir * ARROW_SIZE
	draw_line(tip, base + perp * ARROW_SIZE * 0.5, color, EDGE_WIDTH)
	draw_line(tip, base - perp * ARROW_SIZE * 0.5, color, EDGE_WIDTH)
