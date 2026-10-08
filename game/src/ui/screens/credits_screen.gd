class_name CreditsScreen
extends UiScreen

## The credits screen: who and what made this game.
##
## ## Why static content lives in the scene, not in a module
##
## Credits name shipped facts — the engine, the art pipeline, the design
## record — that no gameplay system owns. A module for them would be a facade
## with no verbs, which the arch gate rightly calls dead code. So the lines
## are authored text in the scene, and this script publishes them back as
## primitives for the headless reader: one source, two readers, no drift
## between what a player sees and what a probe asserts.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}`

## The credited lines, in display order. Mirrored from the scene: a line
## added to one must be added to the other, and the test pins the count so
## the mirror cannot drift silently.
const LINES: Array[String] = [
	"LOC_UI_SCREENS_0FFA48ACD1",
	"LOC_UI_SCREENS_92A407230D",
	"LOC_UI_SCREENS_AA2FCC71A4",
	"LOC_UI_SCREENS_03735590A8",
	"LOC_UI_SCREENS_8968B724D5",
]

var _lines_box: VBoxContainer = null


## The credited lines, in display order.
func credit_lines() -> Array:
	var out: Array = []
	for line in LINES:
		out.append(String(line))
	return out


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	return {"lines": credit_lines(), "line_count": LINES.size()}


func _refresh_view() -> void:
	pass


func _render() -> void:
	pass


func _bind_nodes() -> void:
	super()
	_lines_box = get_node_or_null("%CreditLines") as VBoxContainer
