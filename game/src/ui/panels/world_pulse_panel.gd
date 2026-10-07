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
## ## The two buttons
##
## The panel emits [signal advance_requested] and [signal retreat_requested] rather than
## calling anything. The pulse lives in `app/`, which `ui/` may not reference, so the
## screen holds the bridge and the panel only says "the player asked". Both are disabled —
## with the reason on the message line — when the caller wired nothing, so an unreachable
## tick reads as unreachable instead of as a control that renders and does nothing.
##
## **The retreat's selector is what makes ADR 0167's season-scale class a CHOICE.** The
## wait button pays exactly one period and says so; the selector offers the lengths the
## clock itself authors (read from `TimeLadder`, never from a list written here) and
## prices the chosen one in periods and crossed magnitudes BEFORE the press. That cost
## line is the whole difference between a skip button and an action with a price.
##
## Contract: `summary()` is the testable surface.

## The player asked for one more world period. Whoever holds the bridge calls it.
signal advance_requested

## The player asked to sit for the chosen number of periods. ADR 0167's season-scale
## action: the chosen length IS the cost, so the payload is the ask and nobody here
## decides what it is worth.
signal retreat_requested(periods: int)

## Wording for each reason a caller can hand back. The UI program owns no rule, so it
## only says what was reported.
var REASON_TEXT := {
	"": L.t("LOC_UI_PANELS_EE322903D3"),
	"no_actor": L.t("LOC_UI_PANELS_8C6B2C3AB4"),
	"no_director": L.t("LOC_UI_PANELS_C0199FC7CA"),
	"no_world": L.t("LOC_UI_PANELS_17753763A2"),
	"no_world_clock": L.t("LOC_UI_PANELS_6B48266C7B"),
	"no_retreat": L.t("LOC_UI_PANELS_6476B66F57"),
	"unplannable_span": L.t("LOC_UI_PANELS_EE78098BE8"),
}

## What the readout says when no clock is wired. Named rather than blank so the missing
## seam is visible on the screen instead of being an empty row a player reads as "zero".
var UNWIRED_CLOCK := L.t("LOC_UI_PANELS_C9D9CF171D")
var UNWIRED_CADENCE := L.t("LOC_UI_PANELS_BAD9895BED")
var EMPTY_MEMORY := L.t("LOC_UI_PANELS_8208317A74")
var WAIT_LABEL := L.t("LOC_UI_PANELS_9C7608368A")
var UNAVAILABLE_SUFFIX := L.t("LOC_UI_PANELS_DFE3923CC6")

## ## The open-event heading, and the sentence under it
##
## **Three wordings, because "no rows" is two different things and only one of them is
## news.** A world with nothing open is an ordinary quiet state and is titled plainly; a
## screen nobody published event rows to is a MISSING SEAM and says so, because rendering
## it as "nothing is happening" would turn a broken wiring into a world that looks calm —
## which is the exact failure the bridge slot exists to make visible. A third, middle
## wording covers the case a panel cannot honestly call either: rows published, none of
## them nameable.
var EVENTS_TITLE_OPEN := L.t("LOC_UI_PANELS_18FEB73E8B")
var EVENTS_TITLE_EMPTY := L.t("LOC_UI_PANELS_AB0911EF8D")
var EVENTS_TITLE_UNWIRED := L.t("LOC_UI_PANELS_1230074BDC")
var EVENTS_TITLE_UNNAMED := L.t("LOC_UI_PANELS_A0D1357B51")
var EVENTS_EMPTY_LINE := L.t("LOC_UI_PANELS_66222545E1")
var EVENTS_UNWIRED_LINE := L.t("LOC_UI_PANELS_AA1371E549")
var EVENTS_UNNAMED_LINE := L.t("LOC_UI_PANELS_A870B91DB2")

## The heading over the season-scale control. Named rather than inlined so the wording a
## player reads is one string a test can pin.
var RETREAT_TITLE := L.t("LOC_UI_PANELS_6A5ACB6459")
var RETREAT_LABEL := L.t("LOC_UI_PANELS_9D2BC3DE40")
var RETREAT_EMPTY := L.t("LOC_UI_PANELS_0C5D8C6003")
## Shown instead of a cost line when nothing is selected or no clock is wired — an empty
## line under a selector reads as "free", which is the one thing this control must never
## suggest.
var RETREAT_NO_COST := L.t("LOC_UI_PANELS_7B66B4A655")

var _wired: bool = false
var _can_advance: bool = false
var _can_retreat: bool = false
## One `{magnitude, periods, crossed}` row per offered length, in the reader's order, and
## the index of the chosen one. Raw counts: this panel owns every `%d` and every width.
var _retreat_spans: Array[Dictionary] = []
var _retreat_index: int = -1
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
## One row per world event that is OPEN, as the root handed it over: `display_name`,
## `stage_name`, `stage_index`, `stage_count`, `periods_held`, `duration_periods`,
## `standoff_id`, `is_final_stage` and the rest of the event module's own row shape. Raw
## primitives — this panel owns every `%d` and every sentence built from them.
var _open_events: Array[Dictionary] = []
## Whether the caller published the event SEAM at all, which `[]` cannot say on its own.
## Held apart from the rows so "a world with nothing open" and "a screen nobody wired"
## stay two different sentences.
var _events_wired: bool = false
## How many published rows carried no display name. Non-zero means something is open and
## this panel cannot say what, which is a third state and not the quiet one.
var _unnamed_events: int = 0
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
var _events_title: Label = null
var _events_box: VBoxContainer = null
var _pulse_label: Label = null
var _message_label: Label = null
var _wait_button: Button = null
var _retreat_title_label: Label = null
var _retreat_option: OptionButton = null
var _retreat_cost_label: Label = null
var _retreat_button: Button = null
## Set for the length of the rebuild that re-applies the selection, so the resulting
## `item_selected` cannot be taken for a click and ask the cost line to answer for a
## selector the player has not touched. See `_render_retreat`.
var _restoring_selection: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one world view. `view` is the raw primitives the screen read: counts, the
## cadence in seconds, one `{fact, recorded}` row per news item, whether the
## player may ask for another period, and the one `{magnitude, periods, crossed}` row
## per sit length the clock publishes. Nothing here is interpreted — a count of zero
## and a count nobody reported both read as zero, which is the honest answer for a
## readout and the reason every figure arrives already resolved.
##
## ## The two event keys, and why they arrive as a PAIR
##
## `events_wired` says the root published the seam at all, and `open_events` carries one
## row per event that is open. They are separate keys because neither answers the other:
## `[]` is both "nothing is open" (ordinary) and "nothing reaches this screen" (a defect),
## and only the caller can tell those apart. A screen that passed the rows without the flag
## would render a missing seam as a quiet world, which is the failure this pair exists to
## make impossible. See [method _events_title_text].
##
## `retreat_index` is the caller's echo of the index this panel last reported in
## `summary()`, handed back so a repaint can tell "the player chose this" from "this row
## is still offered". Absent, the panel keeps what it already held — which is the
## difference between a selector that survives a refresh and one that silently returns
## to the shortest length every time the world ticks.
func show_world(view: Dictionary) -> void:
	_bind_nodes()
	_wired = bool(view.get("wired", false))
	_can_advance = _wired and bool(view.get("can_advance", false))
	_can_retreat = _wired and bool(view.get("can_retreat", false))
	_retreat_spans = _spans_of(view.get("retreat_spans", []))
	_retreat_index = _resolve_selection(int(view.get("retreat_index", _retreat_index)))
	_periods = int(view.get("periods", 0))
	_period_count = int(view.get("period_count", 0))
	_period_seconds = float(view.get("period_seconds", 0.0))
	_offered = int(view.get("offered", 0))
	_claimed = int(view.get("claimed", 0))
	_opened = int(view.get("opened", 0))
	_active_events = int(view.get("active_events", 0))
	_available_events = int(view.get("available_events", 0))
	# ## `events_wired` is read BEFORE the rows, deliberately
	#
	# An empty roster is two things and only the caller can tell them apart: a world with
	# nothing open, and a screen the root published nothing to. Absent the flag, `[]` would
	# render as the first and a missing seam would read as a calm world — which is the
	# empty list this readout exists not to be. So the flag is taken on its own terms, not
	# inferred from the rows' size.
	_events_wired = bool(view.get("events_wired", false))
	_open_events = _event_rows_of(view.get("open_events", []))
	_unnamed_events = 0
	for row in _open_events:
		if String(row.get("display_name", "")).is_empty():
			_unnamed_events += 1
	_news = _rows_of(view.get("news", []))
	_message = String(view.get("message", ""))
	_tone = StringName(view.get("tone", ""))
	_render()


## Everything this panel shows, as primitives. The rendered strings are included
## alongside the counts so a test reads the sentence a player reads.
##
## **The retreat's half is the declared cost, not the world time it already spent.**
## `retreat_declared_periods` and `retreat_crossed` describe the row the player has
## selected and can still back out of; `retreat_paid` and `retreat_unpaid` describe the
## last one they actually paid for. A preview that only reported the paid figures would
## read as "free" until the button was pressed.
func summary() -> Dictionary:
	var chosen := _chosen_span()
	return {
		"wired": _wired,
		"can_advance": _can_advance,
		"can_retreat": _can_retreat,
		"retreat_spans": _retreat_spans,
		"retreat_span_count": _retreat_spans.size(),
		"retreat_labels": _retreat_labels(),
		"retreat_index": _retreat_index,
		"retreat_declared_periods": int(chosen.get("periods", 0)),
		"retreat_declared_magnitude": String(chosen.get("magnitude", "")),
		"retreat_crossed": _crossed_of(chosen),
		"retreat_crossed_text": _retreat_cost_text(),
		"retreat_option_enabled": _retreat_option != null and not _retreat_option.disabled,
		"retreat_button_enabled": _retreat_button != null and not _retreat_button.disabled,
		"retreat_button_label": "" if _retreat_button == null else _retreat_button.text,
		"retreat_cost_label": _text_of(_retreat_cost_label),
		"periods": _periods,
		"period_count": _period_count,
		"offered": _offered,
		"claimed": _claimed,
		"opened": _opened,
		"active_events": _active_events,
		"available_events": _available_events,
		# ## The open-event half, published BOTH raw and worded
		#
		# `open_events` is the row roster this panel is holding, so a test asserts on the
		# event's own vocabulary rather than on a sentence; `open_event_lines` is what a
		# player reads, so a rename of the wording is a failure rather than a silent change.
		# Both are here because a panel that published only the first would let a reader
		# verify the data while the text went stale, and one that published only the second
		# would make every assertion a string match.
		"events_wired": _events_wired,
		"open_events": _open_events,
		"open_event_count": _open_events.size(),
		"unnamed_event_count": _unnamed_events,
		"open_event_lines": _event_lines(),
		"events_title": _text_of(_events_title),
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
	_events_title = get_node_or_null("%EventsTitle") as Label
	_events_box = get_node_or_null("%EventsBox") as VBoxContainer
	_pulse_label = get_node_or_null("%PulseLabel") as Label
	_message_label = get_node_or_null("%MessageLine") as Label
	_wait_button = get_node_or_null("%WaitButton") as Button
	_retreat_title_label = get_node_or_null("%RetreatTitle") as Label
	_retreat_option = get_node_or_null("%RetreatLength") as OptionButton
	_retreat_cost_label = get_node_or_null("%RetreatCost") as Label
	_retreat_button = get_node_or_null("%RetreatButton") as Button
	if _wait_button != null and not _wait_button.pressed.is_connected(_on_wait_pressed):
		_wait_button.pressed.connect(_on_wait_pressed)
	if _retreat_button != null and not _retreat_button.pressed.is_connected(_on_retreat_pressed):
		_retreat_button.pressed.connect(_on_retreat_pressed)
	if (
		_retreat_option != null
		and not _retreat_option.item_selected.is_connected(_on_span_selected)
	):
		_retreat_option.item_selected.connect(_on_span_selected)


func _render() -> void:
	if _title_label == null:
		return
	_clock_label.text = L.t(_clock_text())
	_cadence_label.text = L.t(_cadence_text())
	_news_title.text = L.t(_news_title_text())
	_render_news()
	# The event rows render AFTER the news and BEFORE the pulse tally, so a player reads
	# "what is happening" above the counters that describe how it got there — the same
	# order the beat tally has always been in, with the thing it counts moved up.
	if _events_title != null:
		_events_title.text = L.t(_events_title_text())
	_render_events()
	_pulse_label.text = L.t(_pulse_text())
	_wait_button.disabled = not _can_advance
	_wait_button.text = L.t(WAIT_LABEL + ("" if _can_advance else UNAVAILABLE_SUFFIX))
	_render_retreat()
	# The panel's own tone is only its own: a refusal the caller reported is painted
	# in the error ink, and nothing else here is a failure.
	if _tone == &"error":
		_message_label.theme_type_variation = &"WarnLabel"
	else:
		_message_label.theme_type_variation = &"MetaLabel"
	_message_label.text = L.t(_message)


## ## The season-scale row, and why the choice lives on the PANEL
##
## The panel emits `retreat_requested(periods)`; it does not call anything. Same rule as
## the wait button — the pulse lives in `app/`, which `ui/` may not reference — so the
## cost line is this file's and the ask is the screen's.
##
## **Rebuilt from scratch every repaint, and the selection is re-applied after the
## rebuild rather than before it.** `OptionButton.clear()` drops the selected index to
## -1, so a rebuild that kept the player's choice by re-selecting first would restore
## nothing and the cost line would silently revert to the first row — a control that
## forgets a player's choice on the next repaint is worse than no control.
##
## **The re-select runs behind `_restoring_selection`, because a programmatic
## re-select is not a click.** The engine emits `item_selected` from the
## `Button` group's selection change as well as from a click, so a `select()` that moved
## the highlight reaches `_on_span_selected` with no player behind it. That costs
## nothing while the handler only re-reads the cost line — it is the same number either
## way — and it stops being free the moment the handler can reach anything else: the
## caller is mid-`show_world()` and a re-entrant rebuild from here is a repaint that
## repaints. `DomainExploreScreen._sync_selections()` solves the same hazard by keeping
## the index in the model instead of in the widget; this panel has no model, so the
## window is the guard.
func _render_retreat() -> void:
	if _retreat_option == null:
		return
	_retreat_title_label.text = L.t(RETREAT_TITLE)
	_restoring_selection = true
	_retreat_option.clear()
	for label in _retreat_labels():
		_retreat_option.add_item(label)
	_retreat_option.disabled = not _can_retreat
	if _retreat_index >= 0:
		_retreat_option.select(_retreat_index)
	_restoring_selection = false
	_retreat_cost_label.text = L.t(_retreat_cost_text())
	_retreat_button.disabled = not _can_retreat or _retreat_index < 0
	_retreat_button.text = L.t(RETREAT_LABEL + ("" if _can_retreat else UNAVAILABLE_SUFFIX))


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
		label.text = L.t(_news_line(row))
		_news_box.add_child(label)


## One label per OPEN event row, rebuilt from scratch, plus the one line that stands in for
## an empty roster. Freed with [method free] exactly as [method _render_news] does, and for
## the same reason: a `queue_free()` row would stay parented under this runner and stack one
## more copy on every repaint.
##
## ## The empty roster renders a SENTENCE, never nothing
##
## A world with no open event gets [constant EVENTS_EMPTY_LINE] under a heading that says
## so in the title. An empty list with no line is the shape a player reads as a bug — a
## heading with nothing under it looks like the panel failed to load its data — whereas one
## honest sentence is the difference between "the world is quiet" and "this surface is
## broken". The three wordings are the three honest answers; see [method _events_title_text].
func _render_events() -> void:
	if _events_box == null:
		return
	for child in _events_box.get_children():
		_events_box.remove_child(child)
		child.free()
	for line in _event_lines():
		var label := Label.new()
		label.theme_type_variation = &"EffectLabel"
		label.text = L.t(line)
		_events_box.add_child(label)


## The heading over the event rows, and the FIRST of the three empty-state wordings.
##
## Chosen in this order, and the order is the whole point:
##
##  1. **Unwired** — the caller published no seam. Not rendered as "nothing is happening",
##     because a world that looks calm is a world nobody warns about, and a missing seam
##     that reads as calm is worse than a visible one. This is the ADR 0143 rule applied to
##     a read slot: "a screen with an unfilled bridge names the missing seam rather than
##     showing zeros."
##  2. **Open** — there is at least one row. Even if every row is unnamed, a live event
##     exists and the heading should say the world is busy.
##  3. **Unnamed** — rows exist but none carries a `display_name`. A fourth state the panel
##     can actually detect, and worth naming: something IS happening and this surface cannot
##     say what, which is neither "quiet" nor "fine".
##  4. **Empty** — wired, rows published, zero of them. An ordinary quiet world, stated
##     plainly.
func _events_title_text() -> String:
	if not _events_wired:
		return EVENTS_TITLE_UNWIRED
	if _open_events.is_empty():
		return EVENTS_TITLE_EMPTY
	if _unnamed_events >= _open_events.size():
		return EVENTS_TITLE_UNNAMED
	return EVENTS_TITLE_OPEN


## The lines under the heading: one per open event, or the ONE line that stands in for an
## empty roster. Kept as a function so `summary()` reports exactly what was rendered —
## a summary that published the rows but not the lines would let the wording rot
## unobserved, and a test asserting on data alone would never notice.
func _event_lines() -> Array[String]:
	var out: Array[String] = []
	if _open_events.is_empty():
		out.append(EVENTS_UNWIRED_LINE if not _events_wired else EVENTS_EMPTY_LINE)
		return out
	for row in _open_events:
		out.append(_event_line(row))
	return out


## One open event, as a single readable line: its name, the stage it has reached, how long
## it has held, and what it pays. Every `%d` on this surface is this file's (AGENTS.md — a
## screen passes raw values, a panel owns the formatting), and every value is read straight
## off the row the root published rather than derived here.
##
## ## The four pieces a player could not see before, and why each is worded the way it is
##
##  - **WHICH**: `display_name`, falling back to the `event_id`. An event whose def the
##    module no longer authors still has an id, and "the id" is a worse answer than no
##    answer but an honest one.
##  - **WHAT STAGE**: `stage_name` with its position as "stage 2 of 3" when the module
##    publishes a `stage_count`. The count is what turns a stage name into progress: "Oath
##    Taking" alone does not say how far along the world is.
##  - **HOW LONG**: `periods_held`, in the clock's own unit, never in seconds. Same reason
##    [method _retreat_cost_text] gives: `ui/` may not hold a cadence, so a duration here
##    would be a second calendar.
##  - **WHAT IT PAYS**: the `standoff_id` the event is currently in, which is the world
##    event's own answer to "what is at stake". The id is printed as the module's own
##    vocabulary (the same way the news rows print a fact id) rather than being looked up
##    or translated, because `ui/` may not name the event module that authored it.
##
## `is_final_stage` is published by the module and is NOT rendered as prose here: the stage
## position already says "3 of 3", and a second phrase saying "final" would be a second
## claim about the same fact that could disagree with the first. It is carried in the row
## and in `summary()` for a caller that wants the flag itself.
func _event_line(row: Dictionary) -> String:
	var name := String(row.get("display_name", ""))
	if name.is_empty():
		name = String(row.get("event_id", ""))
	if name.is_empty():
		name = "an unnamed event"
	var parts: Array[String] = [name]
	var stage := _stage_text(row)
	if not stage.is_empty():
		parts.append(stage)
	var held := _held_text(row)
	if not held.is_empty():
		parts.append(held)
	var payoff := String(row.get("standoff_id", ""))
	if not payoff.is_empty():
		parts.append("standoff %s" % payoff)
	return " - ".join(parts)


## "Oath Taking (stage 2 of 3)", or just the stage name when the module publishes no
## `stage_count`. Returns `""` when the row names no stage, which the caller reads as "this
## event has no stage to report" rather than printing an empty parenthetical.
func _stage_text(row: Dictionary) -> String:
	var stage := String(row.get("stage_name", ""))
	var total := int(row.get("stage_count", 0))
	if stage.is_empty():
		return ""
	if total < 1:
		return stage
	return "%s (stage %d of %d)" % [stage, _stage_position(row), total]


## The stage position as a 1-based number for a player. `stage_index` is 0-based — the
## module's own indexing — so a raw print would say "stage 0 of 3" and read as a bug. A row
## whose `stage_index` is out of range (negative, or past `stage_count`) prints as `1`
## rather than as a clamped lie about a stage the module did not report; the alternative is
## "stage 0", which is worse.
func _stage_position(row: Dictionary) -> int:
	var index := int(row.get("stage_index", -1))
	var total := int(row.get("stage_count", 0))
	if index < 0:
		return 1
	if total > 0 and index >= total:
		return total
	return index + 1


## "held 12 periods", or `""` when the module published no count. A count of zero is a real
## answer — an event that opened this instant — and prints as "held 0 periods" rather than
## being dropped, because "just started" and "we do not know" are different facts and only
## the second should be silent.
func _held_text(row: Dictionary) -> String:
	if not row.has("periods_held"):
		return ""
	return "held %d periods" % int(row.get("periods_held", 0))


## The open-event rows a caller published, coerced into the one shape this panel renders.
##
## ## Coerced, NOT re-derived
##
## Every field is copied out of the row as-is; nothing is computed, defaulted from another
## field, or invented. A row is dropped only if it is not a dictionary at all — an unnamed
## event is KEPT and rendered with its id, because an event the player can see but not
## identify is a real state this panel has a wording for. Dropping it would turn "something
## is open and I cannot name it" into "nothing is open", which is the false calm this whole
## seam exists to prevent.
##
## Duplicated so `summary()` hands back rows no caller can mutate back into this panel.
func _event_rows_of(rows: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in rows:
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate())
	return out


## The period readout. Two figures, not one: the pulse's own running count and the
## ledger's count of the same moment, because they disagree the moment a save restores
## one of them and a single number would hide that.
func _clock_text() -> String:
	if not _wired:
		return UNWIRED_CLOCK
	if _periods <= 0 and _period_count <= 0:
		return L.t("LOC_UI_PANELS_2948F603C6")
	return "Period %d passed - %d recorded in the world's memory" % [_periods, _period_count]


## The authored cadence, in the only form a player can use it: minutes and seconds.
func _cadence_text() -> String:
	var seconds := _period_seconds
	if not _wired or seconds <= 0.0:
		return UNWIRED_CADENCE
	return "One period every %s" % _duration_text(seconds)


func _news_title_text() -> String:
	if _news.is_empty():
		return L.t("LOC_UI_PANELS_5ACDF79B27")
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


## ## What the chosen sit COSTS, in the clock's own authored magnitudes
##
## **A period count, never a duration in seconds.** The elapsed wall-clock figure would
## be a second calendar computed here from a cadence `ui/` may not hold, and a month
## printed as "10 days" is exactly the private copy ADR 0050 and ADR 0116 exist to stop
## (`tests/core/test_time_ladder_single_source.gd`). What a player is told is the span in
## periods and the magnitudes it CROSSES, both read from `TimeLadder` by the reader and
## handed over as raw counts.
##
## Magnitudes are listed finest-first, as the ladder authors them, and each is named with
## its own count, because "4380 periods - day x365 - month x12 - year x1" says what the
## player is about to live through and no invented unit says it better. Zero counts are
## dropped rather than printed, so a short sit does not read as if it also covered a year.
func _retreat_cost_text() -> String:
	var chosen := _chosen_span()
	if _retreat_spans.is_empty():
		return RETREAT_EMPTY if _can_retreat else UNWIRED_CLOCK
	if chosen.is_empty():
		return RETREAT_NO_COST
	var crossed := _crossed_of(chosen)
	var parts: Array[String] = ["%d periods" % int(chosen.get("periods", 0))]
	for entry in crossed:
		var count := int(crossed[entry])
		if count < 1:
			continue
		parts.append("%s x%d" % [String(str(entry)), count])
	return "This sit costs %s" % " - ".join(parts)


## The selector's own entry per offered length, in the reader's order. A raw period count
## rather than a coined unit word, for the reason [method _retreat_cost_text] gives.
func _retreat_labels() -> Array[String]:
	var out: Array[String] = []
	for span in _retreat_spans:
		out.append(
			"%s - %d periods" % [String(span.get("magnitude", "")), int(span.get("periods", 0))]
		)
	return out


## The chosen row, or `{}` when nothing is chosen. Index-clamped rather than trusted:
## the list is rebuilt from the caller's payload on every repaint and a caller that
## publishes a different set of lengths must not leave this holding an index past its end.
func _chosen_span() -> Dictionary:
	if _retreat_index < 0 or _retreat_index >= _retreat_spans.size():
		return {}
	return _retreat_spans[_retreat_index]


## The chosen row's crossed magnitudes as a primitive `{magnitude: count}` copy, so
## `summary()` hands back a dictionary no caller can mutate into the panel's state.
func _crossed_of(span: Dictionary) -> Dictionary:
	return (span.get("crossed", {}) as Dictionary).duplicate()


## The index to show: whatever the player last chose while it is still on offer, else the
## shortest length. **A retreat with no default is a retreat nobody starts**, and a
## disabled button is how a control reads as broken rather than as a choice.
##
## `offered` is the caller's echo of [method summary]'s `retreat_index` rather than the
## widget's own `selected`, because the widget's value is written BY this rebuild
## (`_render_retreat` re-selects) and reading it back would make the rebuild its own
## input: every repaint would restore whatever the previous repaint left, and a screen
## that never echoed the index could never move it off the default at all.
func _resolve_selection(offered: int = -1) -> int:
	if _retreat_spans.is_empty():
		return -1
	if offered >= 0 and offered < _retreat_spans.size():
		return offered
	if _retreat_index >= 0 and _retreat_index < _retreat_spans.size():
		return _retreat_index
	return 0


## The rows a caller published as sit lengths, coerced into the one shape this panel
## renders. A row with no positive period count is dropped rather than offered: a sit of
## zero periods is the wait button under another name.
func _spans_of(rows: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in rows:
		if not entry is Dictionary:
			continue
		var row := entry as Dictionary
		if String(row.get("magnitude", "")).is_empty() or int(row.get("periods", 0)) < 1:
			continue
		(
			out
			. append(
				{
					"magnitude": String(row.get("magnitude", "")),
					"periods": int(row.get("periods", 0)),
					"crossed": (row.get("crossed", {}) as Dictionary).duplicate(),
				}
			)
		)
	return out


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


## The chosen sit, as a REQUEST carrying the player's own period count. Nothing is
## clamped and nothing is checked here — the cost is what the player chose, and the
## clock is the only thing allowed to say whether it can be paid (ADR 0173 refuses to
## truncate, so a span it cannot cover comes back as a named refusal).
func _on_retreat_pressed() -> void:
	var chosen := _chosen_span()
	if chosen.is_empty():
		return
	retreat_requested.emit(int(chosen.get("periods", 0)))


## ## The click, recorded
##
## Re-render only the cost line: picking a length changes the price and nothing else, so
## a full repaint would rebuild the news rows a player is reading for no reason.
##
## **The index is stored here, and until it was, it was stored nowhere.** `_retreat_index`
## was only ever written by `_resolve_selection`'s fallback, so a player who picked the
## widest sit length got the shortest one priced on the next repaint and the next one
## after that — the panel's own `_render_retreat` note claimed the choice survived the
## rebuild and it did not, because nothing between the click and the rebuild ever copied
## it. ADR 0167's whole claim is that the duration is the player's CHOICE.
##
## Silenced during a rebuild's own re-select: that emission carries an index this panel
## just wrote, and `clear()` leaves the widget at -1, so honouring it would erase the
## choice the rebuild was restoring. See `_render_retreat`.
func _on_span_selected(index: int) -> void:
	if _restoring_selection:
		return
	if index >= 0 and index < _retreat_spans.size():
		_retreat_index = index
	if _retreat_cost_label != null:
		_retreat_cost_label.text = L.t(_retreat_cost_text())
