class_name WorldPulsePanel
extends PanelContainer

## The world's clock and the world's news, as one readout.
##
## ## Why this is a panel and not a screen
##
## A player opening the "World" route came to look at the world. Whether time has
## passed, what the world has heard, and a control that lets them WAIT for the next
## period are the same question asked of the same subject, so they belong beside the
## map rather than on a route of their own. That also keeps the panel's seam honest: a
## screen of its own would need a `ScreenRoutes` entry, a `nav_route_*` input action
## and its own binding arm, and an unrouted screen measures as shipped-but-dead —
## which is precisely the failure this panel is here to end.
##
## ## What it owns
##
## Every `%d`, every `%s` and every duration on this surface. The screen hands raw
## primitives from one [method show_world] call and formats nothing (AGENTS.md, UI
## standard). `summary()` reports both the raw counts and the text actually set on the
## labels, so a headless test asserts the wording instead of pixels.
##
## ## The button
##
## The panel emits [signal advance_requested] rather than calling anything. The pulse
## lives in `app/`, which `ui/` may not reference, so the screen holds the bridge and
## the panel only says "the player asked". The button is disabled — with the reason on
## the message line — when the caller wired nothing, so an unreachable tick reads as
## unreachable instead of as a control that renders and does nothing.
##
## Contract: `summary()` is the testable surface.

## The player asked for one more world period. Whoever holds the bridge calls it.
signal advance_requested

## Wording for each reason a caller can hand back. The UI program owns no rule, so it
## only says what was reported.
const REASON_TEXT := {
	"": "A season passes",
	"no_actor": "The world has no one to remember it",
	"no_director": "No one is listening for what happens",
	"no_world": "The world has no clock",
	"no_world_clock": "This screen is not wired to the world clock",
}

## What the readout says when no clock is wired. Named rather than blank so the missing
## seam is visible on the screen instead of being an empty row a player reads as "zero".
const UNWIRED_CLOCK := "No world clock is wired to this screen."
const UNWIRED_CADENCE := "The world's cadence is not published here."
const EMPTY_MEMORY := "The world remembers nothing yet."
const WAIT_LABEL := "Wait a season"
const UNAVAILABLE_SUFFIX := " (unavailable)"

var _wired: bool = false
var _can_advance: bool = false
var _periods: int = 0
var _period_count: int = 0
## The authored cadence in seconds, as the caller reported it. Kept as a field rather
## than read back out of the last payload so `_cadence_text` never has to reach into
## a dictionary mid-format.
var _period_seconds: float = 0.0
var _offered: int = 0
var _claimed: int = 0
var _opened: int = 0
var _active_events: int = 0
var _available_events: int = 0
## One `{fact, recorded}` row per thing the world has heard of, in the order the
## caller listed them. Never rebuilt into widgets, so the readout has no rows to leak.
var _news: Array[Dictionary] = []
var _message: String = ""
var _tone: StringName = &""
var _title_label: Label = null
var _clock_label: Label = null
var _cadence_label: Label = null
var _news_title: Label = null
var _news_box: VBoxContainer = null
var _pulse_label: Label = null
var _message_label: Label = null
var _wait_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one world view. `view` is the raw primitives the screen read: counts, the
## cadence in seconds, one `{fact, recorded}` row per news item, and whether the
## player may ask for another period. Nothing here is interpreted — a count of zero
## and a count nobody reported both read as zero, which is the honest answer for a
## readout and the reason every figure arrives already resolved.
func show_world(view: Dictionary) -> void:
	_bind_nodes()
	_wired = bool(view.get("wired", false))
	_can_advance = _wired and bool(view.get("can_advance", false))
	_periods = int(view.get("periods", 0))
	_period_count = int(view.get("period_count", 0))
	_period_seconds = float(view.get("period_seconds", 0.0))
	_offered = int(view.get("offered", 0))
	_claimed = int(view.get("claimed", 0))
	_opened = int(view.get("opened", 0))
	_active_events = int(view.get("active_events", 0))
	_available_events = int(view.get("available_events", 0))
	_news = _rows_of(view.get("news", []))
	_message = String(view.get("message", ""))
	_tone = StringName(view.get("tone", ""))
	_render()


## Everything this panel shows, as primitives. The rendered strings are included
## alongside the counts so a test reads the sentence a player reads.
func summary() -> Dictionary:
	return {
		"wired": _wired,
		"can_advance": _can_advance,
		"periods": _periods,
		"period_count": _period_count,
		"offered": _offered,
		"claimed": _claimed,
		"opened": _opened,
		"active_events": _active_events,
		"available_events": _available_events,
		"news": _news,
		"news_count": _news.size(),
		"heard_count": _heard(),
		"title_text": _text_of(_title_label),
		"clock_text": _text_of(_clock_label),
		"cadence_text": _text_of(_cadence_label),
		"news_title": _text_of(_news_title),
		"news_text": _news_lines(),
		"pulse_text": _text_of(_pulse_label),
		"message_text": _text_of(_message_label),
		"tone": String(_tone),
		"wait_label": "" if _wait_button == null else _wait_button.text,
		"wait_enabled": _wait_button != null and not _wait_button.disabled,
	}


## The sentence a caller should show for `reason`. Public because the screen sets the
## same line before it repaints, and two spellings of one refusal is how a panel and
## its screen start disagreeing.
func reason_text(reason: String) -> String:
	return String(REASON_TEXT.get(reason, "The world did not move: %s" % reason))


# --- Plumbing ----------------------------------------------------------------


func _bind_nodes() -> void:
	if _title_label != null:
		return
	_title_label = get_node_or_null("%TitleLabel") as Label
	_clock_label = get_node_or_null("%ClockLabel") as Label
	_cadence_label = get_node_or_null("%CadenceLabel") as Label
	_news_title = get_node_or_null("%NewsTitle") as Label
	_news_box = get_node_or_null("%NewsBox") as VBoxContainer
	_pulse_label = get_node_or_null("%PulseLabel") as Label
	_message_label = get_node_or_null("%MessageLine") as Label
	_wait_button = get_node_or_null("%WaitButton") as Button
	if _wait_button != null and not _wait_button.pressed.is_connected(_on_wait_pressed):
		_wait_button.pressed.connect(_on_wait_pressed)


func _render() -> void:
	if _title_label == null:
		return
	_clock_label.text = _clock_text()
	_cadence_label.text = _cadence_text()
	_news_title.text = _news_title_text()
	_render_news()
	_pulse_label.text = _pulse_text()
	_wait_button.disabled = not _can_advance
	_wait_button.text = WAIT_LABEL + ("" if _can_advance else UNAVAILABLE_SUFFIX)
	# The panel's own tone is only its own: a refusal the caller reported is painted
	# in the error ink, and nothing else here is a failure.
	if _tone == &"error":
		_message_label.theme_type_variation = &"WarnLabel"
	else:
		_message_label.theme_type_variation = &"MetaLabel"
	_message_label.text = _message


## One label per news row, rebuilt from scratch.
##
## **Freed immediately, never queued.** `queue_free()` defers to the end of the frame
## and the headless runner never processes one, so a deferred row would stay parented
## and every repaint would stack another copy on top of it — the same accumulation
## `WorldMapScreen._clear_graph` documents. `remove_child` first, then `free`, because
## a node still parented does not release.
func _render_news() -> void:
	if _news_box == null:
		return
	for child in _news_box.get_children():
		_news_box.remove_child(child)
		child.free()
	for row in _news:
		var label := Label.new()
		label.theme_type_variation = (
			&"EffectLabel" if bool(row.get("recorded", false)) else &"MetaLabel"
		)
		label.text = _news_line(row)
		_news_box.add_child(label)


## The period readout. Two figures, not one: the pulse's own running count and the
## ledger's count of the same moment, because they disagree the moment a save restores
## one of them and a single number would hide that.
func _clock_text() -> String:
	if not _wired:
		return UNWIRED_CLOCK
	if _periods <= 0 and _period_count <= 0:
		return "No period has passed yet."
	return "Period %d passed - %d recorded in the world's memory" % [_periods, _period_count]


## The authored cadence, in the only form a player can use it: minutes and seconds.
func _cadence_text() -> String:
	var seconds := _period_seconds
	if not _wired or seconds <= 0.0:
		return UNWIRED_CADENCE
	return "One period every %s" % _duration_text(seconds)


func _news_title_text() -> String:
	if _news.is_empty():
		return "The world's news (nothing heard)"
	return "The world's news (%d/%d heard)" % [_heard(), _news.size()]


## One news row. The fact id is spoken as the world's own vocabulary, and a row the
## world has not heard yet is grey rather than hidden: a player must be able to see
## that something is coming.
func _news_line(row: Dictionary) -> String:
	var fact := String(row.get("fact", ""))
	return "%s - %s" % [fact, "heard" if bool(row.get("recorded", false)) else "not yet"]


## What the world did with the beats it was offered. Reported even when nothing is
## live, because a quiet world and a broken one look identical otherwise.
func _pulse_text() -> String:
	if not _wired:
		return ""
	return (
		"Beats offered %d - claimed %d - events opened %d - live now %d, ready %d"
		% [_offered, _claimed, _opened, _active_events, _available_events]
	)


## `120.0` reads as `2m 00s`. Whole seconds, because a period is the authored unit and
## a fraction of one is not a thing a player is waiting for.
func _duration_text(seconds: float) -> String:
	var whole := int(roundf(seconds))
	return "%dm %02ds" % [whole / 60, whole % 60]


## How many listed facts the world has heard. Read off the rows rather than off a
## separate counter so the headline and the rows can never disagree.
func _heard() -> int:
	var count := 0
	for row in _news:
		if bool(row.get("recorded", false)):
			count += 1
	return count


func _news_lines() -> Array[String]:
	var out: Array[String] = []
	for row in _news:
		out.append(_news_line(row))
	return out


## The rows a caller handed over, coerced into the one shape this panel renders.
## Anything that is not a named row is dropped rather than rendered as a blank line.
func _rows_of(rows: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in rows:
		if entry is Dictionary and not String((entry as Dictionary).get("fact", "")).is_empty():
			out.append(
				{
					"fact": String((entry as Dictionary).get("fact", "")),
					"recorded": bool(entry.get("recorded", false))
				}
			)
	return out


func _text_of(node: Label) -> String:
	return "" if node == null else node.text


func _on_wait_pressed() -> void:
	# A pressed button is a request, never an advance: the panel has no clock and no
	# ledger, so it hands the request up and lets whoever owns the bridge answer.
	advance_requested.emit()
