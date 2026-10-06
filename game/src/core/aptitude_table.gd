class_name AptitudeTable
extends Resource

## The authored aptitude matrix (ADR 0881/0882): the edge ROWS, the share exponent and
## the contest span every resolve reads, as DATA — retuned by editing this resource's
## values, never by editing `AptitudeMatrix`.
##
## ## Why rows are Dictionaries and the resolver reads Resources
##
## The file stays reviewable: one row per line, one coefficient per row, the same shape
## `core/time_ladder_table.tres` uses for its own table. [method to_edges] compiles the
## rows into the typed [AptitudeEdge] array the resolver takes, once, and a row that
## cannot compile is DROPPED — which the table's own test catches by pinning
## `to_edges().size() == edge_rows.size()`.
##
## ## The seed coefficients are an initial authored pass, not balance
##
## Same posture Keepverse states for its own unmeasured constants: shipping a guess is
## fine, calling it balance is not. The balance pass owns these numbers.

const TABLE_PATH := "res://src/core/aptitude_table.tres"

## `gamma` in `k * share^gamma * span`: `1.0` is linear, and a value above it taxes a
## build that spreads its points instead of concentrating them.
@export var share_exponent: float = 1.0
## What a CONTEST edge's `span` reads: `1.0` is the neutral.
@export var contest_span: float = 1.0
## One row per edge: `{channel: StringName, source: StringName, k: float, mode: String}`
## with mode `"contest"` or `"magnitude"`.
@export var edge_rows: Array[Dictionary] = []

static var _shipped: AptitudeTable = null

var _compiled: Array[AptitudeEdge] = []


## The shipped table, loaded once. `null` only when the resource cannot load, which the
## table's own test refuses — a shipped game always has one.
static func shipped() -> AptitudeTable:
	if _shipped == null:
		_shipped = load(TABLE_PATH) as AptitudeTable
	return _shipped


## The rows as the resolver's typed edges, compiled once and cached.
func to_edges() -> Array[AptitudeEdge]:
	if not _compiled.is_empty() or edge_rows.is_empty():
		return _compiled
	for row in edge_rows:
		var edge := _compile(row)
		if edge != null:
			_compiled.append(edge)
	return _compiled


static func _compile(row: Dictionary) -> AptitudeEdge:
	var mode := -1
	match String(row.get("mode", "")).to_lower():
		"contest":
			mode = AptitudeEdge.Mode.CONTEST
		"magnitude":
			mode = AptitudeEdge.Mode.MAGNITUDE
	if mode < 0:
		return null
	var edge := AptitudeEdge.new()
	edge.channel = StringName(row.get("channel", &""))
	edge.source = StringName(row.get("source", &""))
	edge.k = float(row.get("k", 0.0))
	edge.mode = mode
	return edge
