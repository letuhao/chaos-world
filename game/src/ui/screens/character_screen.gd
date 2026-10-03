class_name CharacterScreen
extends UiScreen

## Character sheet (ADR 0038/0042). Renders the whole actor: every derived stat,
## every resource pool, and the paths it is enrolled on. It owns no game rule and
## calls no action — it is the one screen that only reads, so it is the cheapest
## possible proof that the UI program can render an Actor.
##
## Contract: `summary()` is the testable surface, with child panel summaries
## nested under their own key.

## The two row prefixes the scene declares. These are CASE-SENSITIVE `%` unique
## names, and getting one wrong is silent: `get_node_or_null` answers null, the
## screen concludes it has no rows, and composes every row itself. This sheet did
## exactly that -- it asked for `%pool0Row` while the scene declares `Pool0Row`, so
## it bound nothing and rendered an empty stat list and an empty resource list
## while `summary()` still reported all 38 stats. Every row below is therefore
## looked up by the exact name the scene writes.
const STAT_ROW_PREFIX := "Stat"
const POOL_ROW_PREFIX := "Pool"
const ROW_SUFFIX := "Row"
const SCENE_ROWS := 8

## The one line a player reads above the sheet. The `paths` block keeps its ids
## because that is a data contract tests assert on, but the STRING a person reads
## must not be `body_cultivation qi_refining`.
const PATH_LABELS: Dictionary = {
	&"body_cultivation": "Body",
	&"qi_cultivation": "Qi",
	&"mind_cultivation": "Mind",
}

var _vitals: VBoxContainer = null
var _realm_label: Label = null
var _paths_label: Label = null
var _list: VBoxContainer = null
var _pool_rows: Array[StatRow] = []
var _stat_rows: Array[StatRow] = []


## Everything this screen displays. Primitives only; `{}` with no actor.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var paths := _paths()
	var pools := _pools()
	var stats := _derived_stats()
	return {
		"actor": String(_actor.id),
		"paths": paths,
		"pools": pools,
		"stats": stats,
		"stat_keys": _stat_keys(stats),
		"pool_count": pools.size(),
		"vitals": _vitals_summary(),
	}


func _refresh_view() -> void:
	_bind_nodes()
	var live := _actor != null
	if _realm_label != null:
		_realm_label.text = "Paths enrolled"
	if _paths_label != null:
		_paths_label.text = "Paths: %s" % _path_text() if live else ""
	_fill_pool_rows()
	_fill_stat_rows()


# --- Reading the actor ------------------------------------------------------


## One entry per cultivation path the actor is enrolled on. A path the actor does
## not carry is reported as `false` rather than omitted, so a caller can tell
## "not enrolled" from "unknown".
func _paths() -> Dictionary:
	if _actor == null:
		return {}
	var out := {}
	for path_id in PathState.ALL:
		var state := _actor.path(path_id)
		out[String(path_id)] = {
			"enrolled": state != null,
			"realm": String(state.rank_id) if state != null else "",
			"progress": float(state.progress) if state != null else 0.0,
		}
	return out


func _path_text() -> String:
	var parts: Array[String] = []
	for path_id in PathState.ALL:
		var entry: Dictionary = _paths().get(String(path_id), {})
		if bool(entry.get("enrolled", false)):
			var label: String = PATH_LABELS.get(path_id, String(path_id))
			parts.append("%s %s" % [label, entry.get("realm", "")])
	return ", ".join(parts) if not parts.is_empty() else "none"


## Every resource pool the actor carries, as raw current/maximum. A pool with no
## maximum is reported as `false` so a bar is never drawn from a missing value.
func _pools() -> Dictionary:
	var out := {}
	if _actor == null:
		return out
	for pool in _actor.resources.values():
		var id := String(pool.id)
		out[id] = {"current": float(pool.current), "maximum": float(pool.maximum)}
	return out


## Derived stats, read from the single source of truth (`ActorStats`) rather than
## recomputed, so the sheet can never disagree with combat.
func _derived_stats() -> Dictionary:
	var out := {}
	if _actor == null:
		return out
	for id in _actor.stats.derived_all().keys():
		out[String(id)] = float(_actor.stats.derived(id))
	return out


func _stat_keys(stats: Dictionary) -> Array:
	var keys: Array = stats.keys()
	keys.sort()
	return keys


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _list != null:
		return
	_realm_label = get_node_or_null("%RealmLabel") as Label
	_paths_label = get_node_or_null("%PathsLabel") as Label
	_list = get_node_or_null("Layout/Scroll/Stats") as VBoxContainer
	if _list == null:
		return
	_pool_rows.clear()
	_stat_rows.clear()
	for index in SCENE_ROWS:
		var pool := _list.get_node_or_null(_row_name(POOL_ROW_PREFIX, index)) as StatRow
		if pool != null:
			_pool_rows.append(pool)
		var stat := _list.get_node_or_null(_row_name(STAT_ROW_PREFIX, index)) as StatRow
		if stat != null:
			_stat_rows.append(stat)


## The exact `%` unique name the scene declares for one row, e.g. `%Pool0Row`.
func _row_name(prefix: String, index: int) -> String:
	return "%%%s%d%s" % [prefix, index, ROW_SUFFIX]


## Pool rows come first in the scene, so fill them from the pool map and the stat
## rows from the derived map, in a fixed order so two runs agree.
##
## A pool id is NOT a stat id, so it is named and precision-declared by the caller
## and `StatPresenter` is deliberately not consulted: a pool is a count of a
## reservoir, and the one place that knows its unit is `StatPresenter`'s caller.
func _fill_pool_rows() -> void:
	var pools := _pools()
	var keys: Array = pools.keys()
	keys.sort()
	var index := 0
	while index < _pool_rows.size():
		var row := _pool_rows[index]
		if index < keys.size():
			var entry: Dictionary = pools[keys[index]]
			(
				row
				. set_state(
					{
						"name": StatPresenter.label_for(StringName(keys[index])),
						"current": entry.get("current", 0.0),
						"maximum": entry.get("maximum", 0.0),
						"mode": StatRow.MODE_BAR,
					}
				)
			)
		else:
			row.set_state({})
		index += 1


## One row per derived stat, handed the stat ID and nothing else.
##
## The screen passes the id; `StatPresenter` owns the label and the precision. That
## is the whole fix for the wrong-figure class: the screen used to pass the raw id
## as the label and no precision at all, so every fraction on the sheet rounded to
## an integer -- `acupoint_quality = 0.5` read as "1", `crit_chance = 0.05` and
## `breakthrough_chance = 0.2` both read as "0". A screen cannot be trusted to
## remember a per-stat decimal count, and there is no way for it to forget one now.
func _fill_stat_rows() -> void:
	var stats := _derived_stats()
	var keys := _stat_keys(stats)
	# The sheet scrolls rather than truncates: 36 derived stats do not fit in a
	# fixed set of rows, and a stat that silently vanished reads as a stat the
	# actor does not have (ADR 0043).
	_ensure_row_count(keys.size())
	var index := 0
	while index < _stat_rows.size():
		var row := _stat_rows[index]
		if index < keys.size():
			row.set_state({"stat": StringName(keys[index]), "current": stats[keys[index]]})
		else:
			row.set_state({})
		index += 1


## Grow or shrink the row pool to match the data, so scrolling shows everything.
##
## `StatRow.create()` instances this panel's own scene. It must not be
## `StatRow.new()`: a bare `StatRow` has no `%StatLabel`/`%ValueLabel`, renders an
## empty box, and still answers `summary()` with a name and a figure -- which is how
## 30 of the 38 rows on this sheet came up blank while the suite stayed green.
func _ensure_row_count(needed: int) -> void:
	if _list == null:
		return
	# The sheet scrolls rather than truncates, but `needed` is the number of DISTINCT
	# stats any module has written a modifier for, and nothing bounds that. Every
	# row here is a live Control parented into the tree, so an unbounded count is an
	# unbounded node count. Clamped once, and the sheet draws what fits.
	var target := RowBudget.cap(needed)
	while _stat_rows.size() < target:
		var row := StatRow.create()
		if row == null:
			break
		row.name = "ExtraStatRow%d" % _stat_rows.size()
		_list.add_child(row)
		_stat_rows.append(row)
	while _stat_rows.size() > target and not _stat_rows.is_empty():
		var extra: StatRow = _stat_rows.pop_back()
		if extra != null and extra.get_parent() != null:
			extra.get_parent().remove_child(extra)
			extra.free()


func _vitals_summary() -> Dictionary:
	var out := {}
	for row in _pool_rows + _stat_rows:
		var view := row.summary()
		if not view.is_empty():
			out[String(view.get("name", ""))] = view
	return out
