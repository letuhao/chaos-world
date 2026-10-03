class_name WorldPulse
extends RefCounted

## The composition root's world clock and its ONE beat offer point (ADR 0117,
## DEF-0111). Wiring, not rules — the same shape as [code]StatusLoop[/code]
## (ADR 0089) and [code]BeatDirector[/code]: a `RefCounted` in `app/` that holds
## the collaborators and calls them, owns no gameplay rule, persists nothing and is
## not an autoload.
##
## ## Why this file exists
##
## `EventApi.advance` carries NO default for `periods` and refuses `periods <= 0`
## by design (ADR 0085's pull-based tick), and DEF-0171 measured that NOTHING in
## production owned a PERIOD COUNT — so the world's stage ladders could never move.
## A pull-based tick with no puller is the same defect one layer down from the one
## ADR 0117 measured: `EventApi` was a facade with zero callers, so no module owned
## the moment ADR 0114 requires an owner of.
##
## **This is that owner, and it is the last piece.** `StatusLoop` already answered
## "what does the composition root do with elapsed time": it is handed a `delta` by
## the one `_process` in the game (`app/item_workbench_app.gd`) and turns it into an
## explicit count. This does the same thing one layer up — seconds become whole
## PERIODS here, and periods are handed down as the integer every accrual verb in
## this program already demands.
##
## ## No clock of its own
##
## Nothing here reads `Time.get_ticks*`, declares a frame callback or reaches for
## `get_tree()`. [method pull] is handed the elapsed time by the caller that owns
## it, so a headless probe, a replay and a frame that hitched all age the world
## identically. [constant PERIOD_SECONDS] is the ONE authored statement of how long
## a period is, and it lives here because the composition root is the only layer
## allowed to know real time — a module that invented a timer would be a second
## source of truth for when a save happened (ADR 0085, DEF-0111).
##
## ## Why the period is a FACT and not just a counter
##
## A period elapsing is a thing that happened, so it belongs in `WorldFact`'s
## ledger and reaches consumers through the ONE director rather than beside it.
## That is what makes the chain observable instead of decorative: with
## [constant PERIOD_FACT] in the ledger, [code]QuestBeatHandler[/code] completes a
## quest whose step watches it, an event trigger can require it, and a fate gate can
## name it — each of those authored as content, with no further wiring.
##
## **The beat id is minted HERE, by the caller**, which is ADR 0114's once-rule
## stated exactly: a monotone ledger can answer "how many times" and never "has this
## occurrence been counted", so the owner of the moment names the occurrence
## (`world_period_elapsed@3`). Nothing downstream re-derives it.
##
## ## What it does NOT own
##
## - **It does not decide whether an event opens.** [method EventApi.begin]
##   re-evaluates the trigger and is the one authority on that; this file only asks
##   [method EventApi.available] what the world allows and opens at most
##   [constant MAX_OPENS_PER_PULL] of them, so a world with many eligible events
##   cannot spend one frame opening all of them.
## - **It does not resolve a conflict.** A verdict arrives from combat or a ruling
##   (ADR 0085), never from a clock.
## - **It does not re-offer the event module's own beats.** `event/EventBeatWriter`
##   records its stage `on_enter` facts itself, so offering them here as well would
##   write one occurrence twice. They are COUNTED and reported under
##   `module_recorded_facts` instead — visible, never silently dropped, never
##   double-counted.
##
## ## The one offer point
##
## [method offer] is the ONLY place in `app/` that hands a beat to the director.
## A second dispatcher is ADR 0114's failure under a different name, so a moment that
## wants a beat calls this and nothing else.

## Seconds of elapsed time in one world period. The ONE authored cadence: retune
## the world's pace by editing this number and nothing else, because no module holds
## a competing one. Long enough that an event's authored `duration_periods` ladder
## is walked in whole steps rather than per frame, and short enough that a player
## sees the world move inside one sitting.
const PERIOD_SECONDS := 120.0

## The most whole periods one advance may hand down, whatever the elapsed time
## says. A hitch, a breakpoint or a slow-motion frame otherwise converts one delta
## into hundreds of periods and walks an authored ladder to its end in a single
## call — and the surplus is DROPPED rather than banked, because a banked surplus is
## a backlog that pays out later at a rate nobody chose.
const MAX_PERIODS_PER_PULL := 8

## The most events one advance may open. One, deliberately: an event is a story beat
## a player is meant to notice, and opening four in one frame is four beats nobody
## saw. The rest are still `available` on the next advance.
const MAX_OPENS_PER_PULL := 1

## The fact a whole elapsed period accrues to. A flat id in `WorldFact`'s namespace,
## exactly as ADR 0113 requires — no prefix, because a prefixed id "reads as a
## working reference and silently grants nothing".
const PERIOD_FACT := &"world_period_elapsed"

## The audit trail on the period beat, in ADR 0114's own vocabulary. Nothing routes
## on it; it is there so a save or a log says which system earned the accrual.
const PERIOD_SOURCE := "world:period"

## ## The world's OWN doings: delegated, and this file only routes them
##
## An event trigger is read before `EventApi.begin` writes a beat, so a trigger naming
## a fact asks about the world **as it already was** — and four shipped triggers do
## exactly that (`beast_tide` on a sighted storm front, `the_dawn_descent` on a sounded
## void seam, `tournament_of_the_spirit_peaks` on a called tournament,
## `war_of_the_nine_fords` on a called war). Nothing produced those four facts, so four
## of seven events could never open.
##
## [code]WorldAmbient[/code] holds WHICH facts the world has reached and not yet said.
## **This file holds only the offering**, because offering a beat is this file's whole
## job and a roster in a clock is the SRP split `tools arch` warns about.
const AMBIENT_FACTS := WorldAmbient.ROSTER
const AMBIENT_SOURCE := WorldAmbient.SOURCE

var _actor: Actor = null
var _director: BeatDirector = null
## Seconds owed to the world but not yet a whole period. Session-only, exactly like
## the status clock's delta: a conversion buffer, not a save.
var _elapsed: float = 0.0
## Whole periods this pulse has handed down since boot.
var _periods: int = 0
## Whole periods this pulse offered to the director.
var _offered: int = 0
## How many of those a registered sink claimed.
var _claimed: int = 0
## Beats the `event` module recorded for itself across the advances this pulse has
## run. Counted, never re-offered — see the class docstring.
var _module_recorded: int = 0
## Events this pulse has opened. A count, not a table: nothing here needs to read
## an old one back, and a table would be state a module owns.
var _opened: int = 0
## Institution actions that landed across the advances this pulse has run. A count,
## for the same reason as `_claimed`: the resolver owns the detail and `app/` must
## hold no ledger.
var _institution_acted: int = 0
## Institution proposals the resolver refused. Counted rather than dropped so a
## caller can tell "nothing happened" from "nothing was possible".
var _institution_refused: int = 0


func _init(actor: Actor = null, director: BeatDirector = null) -> void:
	_actor = actor
	_director = director
	if director != null:
		bind_director(director)


## Adopt an actor after construction, for a caller that built the pulse first. The
## pulse stays a pure wire either way.
func attach(actor: Actor) -> void:
	_actor = actor


## The director this pulse offers to, or null before one is wired.
func director() -> BeatDirector:
	return _director


## Hand `director` down and register the sinks, in the order ADR 0117 makes
## load-bearing: [b]QuestBeatHandler first[/b], because registration order IS
## priority and an actor with an active quest watching a fact must get the quest's
## completion rather than another sink's report. [b]EventBeatSink second[/b], so a
## fact no quest cares about still reaches the world's own answer.
##
## A sink already registered is not added twice, so calling this again is safe.
func bind_director(director: BeatDirector) -> void:
	_director = director
	if _director == null:
		return
	_director.add_sink(QuestBeatHandler.new())
	_director.add_sink(EventBeatSink.new())


## Advance the world by however many WHOLE periods `delta_seconds` is worth.
##
## `delta_seconds` is the engine's, passed down by the caller that owns time — never
## a clock read here (ADR 0089), and never a period count invented out of thin air.
## A frame that elapsed nothing resolves nothing and offers nothing, which is the
## property `tests/modules/event/test_event.gd` proves of the facade and this method
## preserves at the boot path.
##
## Returns a primitives-only report: `{ok, reason, periods, offered, claimed,
## opened, module_recorded_facts}`.
func pull(delta_seconds: float) -> Dictionary:
	if delta_seconds <= 0.0:
		# A frame that elapsed nothing is not a refusal of the world — it is a frame
		# in which the world did not move. Reported as ok, so a caller reading the
		# report is not told the pull failed.
		return _report(true, "")
	_elapsed += delta_seconds
	# Arithmetic, not a loop: a period count is a division, and a `while` that
	# counted periods up one at a time is the unbounded-wait shape this repo fails
	# the build on. The ceiling is applied BEFORE the surplus is dropped, so a long
	# hitch can never bank time the next pull would spend at a rate nobody chose.
	var periods := int(_elapsed / PERIOD_SECONDS)
	if periods > MAX_PERIODS_PER_PULL:
		periods = MAX_PERIODS_PER_PULL
		_elapsed = 0.0
	else:
		_elapsed -= float(periods) * PERIOD_SECONDS
	return _advance(periods)


## Advance the world by exactly `count` periods, with no elapsed time at all.
##
## **This is the player-facing half of the tick, and it is a verb rather than a
## timer.** A world whose only clock is a frame callback cannot be advanced by a
## headless probe, a replay or a "wait a season" button, and the module's pull-based
## tick refuses `periods <= 0` precisely so that nothing accrues without a caller
## saying how much. `count` is clamped to [constant MAX_PERIODS_PER_PULL] for the
## same reason a hitch is.
func advance_periods(count: int) -> Dictionary:
	return _advance(clampi(count, 0, MAX_PERIODS_PER_PULL))


## Offer one beat to the director and report what it decided. **The only place in
## `app/` that offers a beat** — see the class docstring.
##
## The occurrence id is minted here, from the ledger's own count, because ADR 0114
## makes the caller name the occurrence and a monotone ledger cannot. The source is
## carried verbatim so the director's report names which system earned the accrual.
func offer(fact: StringName, amount: int = 1, source: String = "") -> Dictionary:
	if _actor == null or _director == null:
		return {"ok": false, "reason": "no_owner", "claimed": false, "claimed_by": ""}
	var occurrence := WorldFact.count(_actor, fact) + 1
	var beat := WorldBeat.make(
		EventFacts.occurrence_id(fact, occurrence), fact, maxi(1, amount), source
	)
	var report := _director.offer(_actor, beat)
	_offered += 1
	return report


## Every world event `actor` may open right now, as primitives. Published so a
## screen can offer "walk into this" without the UI program naming `EventApi`, and
## so a missing affordance reads as an empty list rather than as silence.
func available_events() -> Array[Dictionary]:
	if _actor == null:
		return []
	return EventApi.available(_actor)


## The whole pulse as primitives: the period count, the beats, the sinks registered,
## and what the world is doing. A test asserts this rather than reaching into the
## object, and `tools ui drive` prints it as part of the app's own summary.
func summary() -> Dictionary:
	var world: Dictionary = EventApi.summary(_actor) if _actor != null else {}
	return {
		"periods": _periods,
		"elapsed_seconds": snappedf(_elapsed, 0.001),
		"period_seconds": PERIOD_SECONDS,
		"offered": _offered,
		"claimed": _claimed,
		"opened": _opened,
		"module_recorded_facts": _module_recorded,
		"institution_acted": _institution_acted,
		"institution_refused": _institution_refused,
		"sinks": [] if _director == null else _director.sink_names(),
		"period_fact": String(PERIOD_FACT),
		"period_count": WorldFact.count(_actor, PERIOD_FACT) if _actor != null else 0,
		# The world's own news, published so a test reads the roster rather than
		# hardcoding it, and so a panel can say what the world has already done.
		"ambient_facts": WorldAmbient.ids(),
		"ambient_recorded": WorldAmbient.recorded(_actor),
		"world_period": int(world.get("period", 0)),
		"active_events": int(world.get("active_count", 0)),
		"available_events": (world.get("available", []) as Array).size(),
	}


# --- Internals -------------------------------------------------------------


## The ambient roster's fact ids, in authored order. Delegated rather than restated so
## a test or a panel and [code]WorldAmbient[/code] can never disagree about what
## "ambient" names.
func _ambient_ids() -> Array[String]:
	return WorldAmbient.ids()


## How many of the ambient roster the ledger holds. A count, never a table: the
## detail is the ledger's, and `app/` must hold no memory of its own.
func _ambient_recorded() -> int:
	return WorldAmbient.recorded(_actor)


## The one place a whole advance happens, so [method pull] and
## [method advance_periods] cannot drift into two half-versions of the same moment.
## Returns a report either way, and never loops.
func _advance(periods: int) -> Dictionary:
	if _actor == null:
		return _report(false, "no_actor")
	if _director == null:
		return _report(false, "no_director")
	if periods <= 0:
		return _report(true, "")

	# **Ambient news lands BEFORE the events are consulted**, so a trigger gated on
	# what the world already remembers can be satisfied by news from the same pull
	# that sighted it. `EventApi.begin` re-checks the trigger itself, so offering
	# first cannot open an event early — it only lets a sighting and the tide it
	# causes arrive together rather than one pull apart.
	_offer_ambient(_periods + periods)

	var opened := _open_available()
	_opened += opened.size()
	# The pull the event module has been waiting for. `periods` is an explicit
	# integer from the caller that owns time, which is the whole contract ADR 0085
	# asks for: the module has no clock, and this file has no rules.
	var pulled := EventApi.advance(_actor, periods)
	_periods += periods
	# The institutions get their period on the SAME count as everything else, because
	# a sect that aged on a different cadence from a nation is two political worlds
	# whose timing nobody could reason about — ADR 0089's argument, one layer up. The
	# resolver asks each module what it PROPOSES and dispatches through the closed
	# verb set; it holds no ledger and adds no frame driver (BL-0198).
	_settle_institutions(periods)
	for row in opened:
		_module_recorded += _recorded_by_module(row as Dictionary)
	_module_recorded += _recorded_by_module(pulled)
	for index in periods:
		var report := offer(PERIOD_FACT, 1, PERIOD_SOURCE)
		if bool(report.get("claimed", false)):
			_claimed += 1
	return _report(true, "")


## Offer every fact [code]WorldAmbient[/code] says the world has reached and not yet
## recorded, through [method offer] so a registered sink sees it.
##
## **Through `offer`, never straight at `WorldFact.record`.** Recording is not
## dispatching (ADR 0114): a direct ledger write makes the fact true and leaves every
## sink unconsulted, so a quest step watching it reports outstanding forever — a green
## fact and a permanently open gate. Measured red in
## `tests/app/test_world_ambient_facts.gd`.
##
## The once-check is `WorldAmbient.due`'s ledger read, so this file adds no flag of its
## own — the ADR 0117 second copy is refused by there being nothing here to drift. The
## `for` walks that method's array, built before the loop and mutated by neither, which
## is the shape `test_no_unbounded_wait.gd` accepts; `horizon` is the period count AFTER
## this advance, snapshotted by the caller.
func _offer_ambient(horizon: int) -> void:
	for fact in WorldAmbient.due(_actor, horizon):
		var report := offer(fact, 1, AMBIENT_SOURCE)
		if bool(report.get("claimed", false)):
			_claimed += 1


## Open at most [constant MAX_OPENS_PER_PULL] of the events the world allows, in
## the order `EventApi.available` gives them. `begin` is the authority on whether an
## event may open and re-checks the trigger itself, so asking here cannot open a
## locked event — it only decides how many the composition root spends a moment on.
func _open_available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _actor == null:
		return out
	for row in EventApi.available(_actor):
		if out.size() >= MAX_OPENS_PER_PULL:
			break
		var opened := EventApi.begin(_actor, StringName(row.get("event_id", "")), _periods)
		if bool(opened.get("ok", false)):
			out.append(opened)
	return out


## How many beats the `event` module recorded for itself in one of its reports.
##
## Read rather than guessed, because the honest number is the one the module says it
## wrote. Two shapes, because the module reports them in two places: `begin` answers
## with the beats it applied on `beats`, and `advance` answers with one `beats` per
## advanced stage under `advanced`.
##
## Counted for the report only — a beat the module already wrote is not offered here,
## because `WorldFact.record` is monotone and writing it twice would make the world's
## memory claim a thing happened twice when it happened once.
func _recorded_by_module(report: Dictionary) -> int:
	var total := (report.get("beats", []) as Array).size()
	for row in report.get("advanced", []) as Array:
		total += ((row as Dictionary).get("beats", []) as Array).size()
	return total


## Settle the institutions' actions for `periods`, and keep only the counts.
##
## **A count, never a table.** The proposals and the per-tier detail are the
## resolver's to hand back; this file keeps two running integers so a panel or a
## test can read "the world has moved N institution actions" without reaching into a
## ledger — which `app/` must never hold (the `APP_STATE_MARKERS` rule).
##
## The whole budget across all three tiers is `near + distant + strategic`, a fixed
## seven with the shipped `.tres`, and none of it is multiplied by anything. A
## proposal the resolver refused is counted rather than dropped, so a caller can tell
## "nothing happened" from "nothing was possible".
func _settle_institutions(periods: int) -> void:
	var settled := InstitutionResolver.settle(_actor, periods)
	_institution_acted += int(settled.get("acted", 0))
	_institution_refused += int(settled.get("refused", 0))


## One primitives-only report. `reason` is empty on success, and `offered` counts the
## beats this pulse handed the director rather than the director's running total, so
## a caller can read one advance's answer without subtracting.
func _report(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"periods": _periods,
		"offered": _offered,
		"claimed": _claimed,
		"opened": _opened,
		"module_recorded_facts": _module_recorded,
		"institution_acted": _institution_acted,
		"institution_refused": _institution_refused,
	}
