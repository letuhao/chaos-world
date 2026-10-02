class_name CharacterScreen
extends UiScreen

## Character sheet (ADR 0038/0042). Renders the whole actor: every derived stat,
## every resource pool, and the paths it is enrolled on. It owns no game rule and
## calls no action — it is the one screen that only reads, so it is the cheapest
## possible proof that the UI program can render an Actor.
##
## Contract: `summary()` is the testable surface, with child panel summaries
## nested under their own key.

const MAX_LISTED_POOLS := 16
const POOL_ROW := &"pool"

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
			parts.append("%s %s" % [path_id, entry.get("realm", "")])
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
	for index in MAX_LISTED_POOLS:
		var row := _list.get_node_or_null("%s%dRow" % [POOL_ROW, index]) as StatRow
		if row == null:
			continue
		if index < 8:
			_stat_rows.append(row)
		else:
			_pool_rows.append(row)


## Pool rows come first in the scene, so fill them from the pool map and the stat
## rows from the derived map, in a fixed order so two runs agree.
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
						"name": String(keys[index]),
						"current": entry.get("current", 0.0),
						"maximum": entry.get("maximum", 0.0),
						"mode": StatRow.MODE_BAR,
					}
				)
			)
		else:
			row.set_state({})
		index += 1


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
			row.set_state({"name": String(keys[index]), "current": stats[keys[index]]})
		else:
			row.set_state({})
		index += 1


## Grow or shrink the row pool to match the data, so scrolling shows everything.
func _ensure_row_count(needed: int) -> void:
	if _list == null:
		return
	while _stat_rows.size() < needed:
		var row := StatRow.new()
		row.name = "ExtraStatRow%d" % _stat_rows.size()
		_list.add_child(row)
		_stat_rows.append(row)
	while _stat_rows.size() > needed and not _stat_rows.is_empty():
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
