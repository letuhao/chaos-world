class_name LoadingScreen
extends UiScreen

## The loading screen: wallpaper, weather, honest progress.
##
## ## What "loading" actually is
##
## Every `ScreenRoutes` scene is loaded up front, one per `load_step()`, so
## the first navigation after boot is instant. The bar fills from work really
## done — on a fast disk it passes in a blink, which is correct. A bar that
## takes a fixed two seconds would be theater, and theater is what this
## screen exists to replace.
##
## ## Who drives the steps
##
## The composition root's `_process` calls `load_step()` once per frame (ADR
## 0106: no second tick caller under `res://src`, so this screen owns no
## `_process` of its own and reads no clock). Headless tests drive the same
## verb in a bounded `for` loop, because no frame is ever delivered there.
## Either driver converges: steps are idempotent and ordered by the route
## table, so hurrying or repeating them changes nothing.
##
## ## The seams
##
## `begin_load()` resets the walk and is called by the root's bind arm, so a
## screen mounted by hand starts unstarted and `load_step()` refuses
## `no_load_started` by name rather than loading from nowhere.
## `set_backdrop(path)` hangs the wallpaper; a missing file keeps the dark
## fallback rect, so the screen never depends on art that has not landed.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}`

const NO_LOAD_STARTED := "no_load_started"

## One cultivation tip per load, rotated by progress. Presentation copy owned
## here, not content: none of these grants anything or names a rule.
const TIPS: Array[String] = [
	"LOC_UI_SCREENS_CA1870FA5C",
	"LOC_UI_SCREENS_A21B8619C0",
	"LOC_UI_SCREENS_0C111326B2",
	"LOC_UI_SCREENS_B740C8CBE5",
	"LOC_UI_SCREENS_14185ADEDB",
]

var _backdrop: TextureRect = null
var _fairy: TextureRect = null
var _sword: TextureRect = null
var _bar: ProgressBar = null
var _status: Label = null
var _tip: Label = null
var _started := false
var _index := 0
var _scenes: Array[String] = []


## Reset the walk over the given route scenes. Idempotent: calling it again
## restarts from zero rather than stacking a second walk. The list arrives as
## an argument because `ui/` may not name `ScreenRoutes` (an `app/` type) —
## the root reads the table and hands the primitives over, like every seam.
func begin_load(scenes: Array) -> Dictionary:
	_scenes.clear()
	for path in scenes:
		var scene_path := String(path)
		if not scene_path.is_empty():
			_scenes.append(scene_path)
	_started = true
	_index = 0
	_bind_nodes()
	refresh()
	return {"ok": true, "total": _scenes.size()}


## Load the next route scene. Returns `{done, loaded, total}` every call, so
## both drivers read progress from the verdict rather than a second query.
func load_step() -> Dictionary:
	_bind_nodes()
	if not _started:
		return {
			"done": false,
			"loaded": 0,
			"total": 0,
			"ok": false,
			"reason": NO_LOAD_STARTED,
		}
	if _index < _scenes.size():
		load(_scenes[_index])
		_index += 1
	refresh()
	return {"done": _index >= _scenes.size(), "loaded": _index, "total": _scenes.size()}


## Hang the art layers. Each path is optional: a missing file leaves that
## layer empty and the layers below show through, so the screen degrades
## plate by plate instead of failing on the first absent PNG.
func set_backdrop(path: String) -> bool:
	return _hang_layer("Backdrop", path)


func set_layers(backdrop: String, fairy: String, sword: String) -> int:
	var hung := 0
	for layer in [["Backdrop", backdrop], ["Fairy", fairy], ["Sword", sword]]:
		if _hang_layer(String(layer[0]), String(layer[1])):
			hung += 1
	if hung == 0:
		set_message("no_wallpaper", TONE_ERROR)
	else:
		set_message("", TONE_OK)
	refresh()
	return hung


func _hang_layer(node_name: String, path: String) -> bool:
	_bind_nodes()
	var node := get_node_or_null("%" + node_name) as TextureRect
	if node == null or not ResourceLoader.exists(path):
		return false
	var texture := load(path) as Texture2D
	if texture == null:
		return false
	node.texture = texture
	return true


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	return {
		"started": _started,
		"loaded": _index,
		"total": _scenes.size(),
		"done": _started and _index >= _scenes.size(),
		"tip": _tip_for(_index, _scenes.size()),
	}


func _refresh_view() -> void:
	pass


func _render() -> void:
	if _bar != null:
		_bar.max_value = maxi(1, _scenes.size())
		_bar.value = _index
	if _status != null:
		if not _started:
			_status.text = L.t("LOC_UI_SCREENS_85FA8FDB40")
		elif _index >= _scenes.size():
			_status.text = L.t("LOC_UI_SCREENS_A0D73BCD75")
		else:
			_status.text = L.t("LOC_UI_SCREENS_E53E200983") % [_index, _scenes.size()]
	if _tip != null:
		_tip.text = L.t(_tip_for(_index, _scenes.size()))


## The tip for this much progress. Pure function of the counts, so the bar,
## the label and the summary never disagree about which tip is showing.
func _tip_for(loaded: int, total: int) -> String:
	if TIPS.is_empty() or total <= 0:
		return TIPS[0] if not TIPS.is_empty() else ""
	return TIPS[loaded % TIPS.size()]


func _bind_nodes() -> void:
	super()
	_backdrop = get_node_or_null("%Backdrop") as TextureRect
	_fairy = get_node_or_null("%Fairy") as TextureRect
	_sword = get_node_or_null("%Sword") as TextureRect
	_bar = get_node_or_null("%LoadBar") as ProgressBar
	_status = get_node_or_null("%StatusLabel") as Label
	_tip = get_node_or_null("%TipLabel") as Label
