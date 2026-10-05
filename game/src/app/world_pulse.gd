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
## identically. [constant PERIOD_SECONDS] is how long a period is, and it is NOT
## authored here any more: it reads `TimeLadder.PERIOD_SECONDS` (ADR 0173), because
## this layer being the only one allowed to know real time is a reason to CONSUME the
## ratio, not to own a private copy of it (ADR 0085, DEF-0111).
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
## - **It does not re-offer the event module's own beats.** An event's authored
##   `on_enter` facts reach the director by the seam below, not from here: it is
##   the OWNER OF THE MOMENT that records such a beat, and re-offering a fact the
##   module already wrote would write one occurrence twice because the ledger is
##   monotone. They are COUNTED and reported under `module_recorded_facts` instead
##   — visible, never silently dropped, never double-counted.
##
## ## The one offer point
##
## [method offer] is the ONLY place in `app/` that hands a beat to the director.
## A second dispatcher is ADR 0114's failure under a different name, so a moment that
## wants a beat calls this and nothing else.
##
## ## The event module's seam, and why it comes back here
##
## [method offer_event_beat] is the reverse door: `event/EventBeatWriter` is handed
## a `Callable` pointing at it (`EventBeatWriter.set_offer_resolver`, the
## `NpcApi.set_minter` inversion). A module may not reach a director, so the beat
## cannot be offered downward — it is pushed UP to the composition root, which
## records it FIRST and then consults its sinks, in ADR 0117's order. Before this
## existed `EventBeatSink` was registered at [method bind_director] and never
## consulted for an authored event beat (DEF-0171), and `EventBeatSink` stopped
## being decoration.
##
## ## The reconcile stamp, and why it lives HERE rather than in `app/` proper
##
## ADR 0170 put staleness in `core/reconcile_stamp.gd` and the epoch beside it in
## `core/world_epoch.gd`, and both had **zero production callers** — a place never aged
## while you were away. [method observe_place] is ADR 0170's trigger (a), and
## `WorldStage` carries a player's arrival to it through an injected `Callable`
## (`WorldStage.set_reconciler`, the `set_location_publisher` inversion one layer down).
##
## **The holder is this file because this file is the OWNER OF TIME.** ADR 0170: the
## staleness stamp is "a per-tier stamp held by the owner of time"; `_periods` is what an
## observation has to be measured against, and a second accumulator beside it would be the
## second clock in the one layer allowed to know time (ADR 0089). `_stamps` is a COUNT
## like every other field here and is written once per observation, so `app/` still
## holds no ledger — `WorldReconcile` owns the folding, this file owns the number.
##
## **And the hazard is why the wiring is unconditional.** ADR 0173 (c): an
## observation-driven clock deadlocks if every advance source is gated on someone being
## present. The fold already is unconditional; what this file must not add is a presence
## check IN FRONT OF IT. See [method observe_place].

## Seconds of elapsed time in one world period. **No longer authored here:** it reads
## `TimeLadder.PERIOD_SECONDS` (`core/time_ladder.gd:110`), where ADR 0173 moved the
## one statement of the cadence, so no second copy can sit beside it (ADR 0085, DEF-0111).
## This keeps the readers' name because `WorldPulse` is the only layer allowed to know
## real time — a reason to CONSUME the ratio, not to own a private copy of it.
const PERIOD_SECONDS := TimeLadder.PERIOD_SECONDS

## The most whole periods one advance may hand down, whatever the elapsed time
## says. A hitch, a breakpoint or a slow-motion frame otherwise converts one delta
## into hundreds of periods and walks an authored ladder to its end in a single
## call — and the surplus is DROPPED rather than banked, because a banked surplus is
## a backlog that pays out later at a rate nobody chose.
const MAX_PERIODS_PER_PULL := 8

## The most events one advance may OPEN. One, deliberately: an event is a story beat
## a player is meant to notice, and opening four in one frame is four beats nobody
## saw. The rest are still `available` on the next advance.
##
## **This is a budget on openings, not on ATTEMPTS** — see `_open_available`, which is
## where the distinction is load-bearing.
const MAX_OPENS_PER_PULL := 1

## The most events one advance may ASK `EventApi.begin` about, in the worst case this
## loop can actually reach.
##
## **The bounded-wait rule, and this is what it is here for.** `tools arch`'s
## `test_no_unbounded_wait` accepts a `for` only when it walks something the engine
## bounds for it (`Array.size()`), so the loop cannot be driven by a list `max_opens`
## would have to grow. That makes the SCAN cost proportional to how many events the
## world allows — which is the authored tree, and the tree is bounded by content
## rather than by this file — and the count above bounds only the part of it that
## opens something.
const MAX_OPEN_ATTEMPTS_PER_PULL := 16

## The fact a whole elapsed period accrues to. A flat id in `WorldFact`'s namespace,
## exactly as ADR 0113 requires — no prefix, because a prefixed id "reads as a
## working reference and silently grants nothing".
const PERIOD_FACT := &"world_period_elapsed"

## The audit trail on the period beat, in ADR 0114's own vocabulary. Nothing routes
## on it; it is there so a save or a log says which system earned the accrual.
const PERIOD_SOURCE := "world:period"

## **The world's own news: delegated, and this file only routes it.**
##
## An event trigger is read before `EventApi.begin` writes a beat, so a trigger naming
## a fact asks about the world **as it already was** — and four shipped triggers do
## exactly that (`beast_tide` on a sighted storm front, `the_dawn_descent` on a sounded
## void seam, `tournament_of_the_spirit_peaks` on a called tournament,
## `war_of_the_nine_fords` on a called war). Nothing produced those four facts, so four
## of seven events could never open.
##
## [code]WorldAmbient[/code] holds WHICH facts the world has reached and not yet said;
## this file holds only the offering, which is this file's whole job.
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
## The magnitudes the LAST advance's elapsed span crossed, as
## `TimeLadder.magnitudes_crossed` published them. Kept as the fold's own answer so
## `summary()` reports what the clock crossed rather than a second copy of the ladder.
var _crossed: Dictionary = {}
## How stale each place is, per authored magnitude (ADR 0170). The OWNER OF TIME holds
## it, because `core/` is a layer and `app/` holds no ledger — this is the same shape
## `WorldPulse._periods` is, and one magnitude of arithmetic per observation.
##
## **Session state, exactly like `_elapsed`**: "a conversion buffer, not a save"
## (`:142-144`). The stamp is DERIVED and DISCARDABLE — delete it and the next
## observation is a full pass (`reconcile_stamp.gd`'s whole argument for existing).
var _stamps: Dictionary = ReconcileStamp.empty()
## Which history each world is currently living (ADR 0170, "The epoch"). The sibling of
## `_stamps`, same owner and the same discardability: drop it and every world resolves to
## epoch 1, which is a full re-read rather than a corruption.
var _epochs: Dictionary = WorldEpoch.empty()


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
	# Same verb as [method advance_periods]: a frame's periods are a DECLARED span, so
	# they are paid in full through the chunk plan or refused — never truncated to the
	# ceiling here. ADR 0173 refuses a real-time world tick outright, so this path has no
	# production caller; it exists to keep the two entry points from being two answers.
	return advance_periods(periods)


## Advance the world by exactly `count` periods, with no elapsed time at all.
##
## **This is the player-facing half of the tick, and it is a verb rather than a
## timer.** A world whose only clock is a frame callback cannot be advanced by a
## headless probe, a replay or a "wait a season" button, and the module's pull-based
## tick refuses `periods <= 0` precisely so that nothing accrues without a caller
## saying how much.
##
## ## A declared span is PAID FOR IN FULL, or refused — never truncated
##
## It used to be `clampi(count, 0, MAX_PERIODS_PER_PULL)`: a player declaring a
## 10^9-year retreat got **8 periods, no error, no interruption and no budget spend**,
## which ADR 0173 refuses outright ("Exceeding the budget FAILS LOUDLY. It never
## truncates", `AGENTS.md:56`, `:75`). The ceiling is still there and still bounds ONE
## advance — it is now [method _advance]'s per-call bound rather than the span's.
##
## A span above the ceiling goes through `TimeLadder.chunks_for`, which grows the chunk
## SIZE with the span so the plan stays inside `MAX_CHUNKS` and sums to exactly `count`
## (ADR 0173 "Chunking and interruption are bounded"). So 10^9 years is a handful of
## spends, not 10^9, and not 8 either.
##
## **A span the chunk plan cannot cover is REFUSED, not shortened.** `chunks_for` pushes
## its own error naming the span and the chunk size for the one input it cannot satisfy;
## an empty plan here is therefore a refusal, and this returns `{ok: false}` rather than
## advancing a prefix of it — a world quietly advanced by part of what the caller paid
## for is the defect this replaces.
func advance_periods(count: int) -> Dictionary:
	if count <= 0:
		return _advance(0)
	if count <= MAX_PERIODS_PER_PULL:
		return _advance(count)
	var plan := TimeLadder.chunks_for(count, MAX_PERIODS_PER_PULL)
	if plan.is_empty():
		return _report(false, "unplannable_span")
	var moved := 0
	# The plan is `TimeLadder`'s own array, sized and built before this loop and mutated
	# by neither, which is the shape `test_no_unbounded_wait.gd` accepts.
	for chunk in plan:
		var report := _advance(int(chunk), true)
		moved += int(chunk)
		if not bool(report.get("ok", false)):
			return report
	return _report(true, "").merged({"declared": count, "chunks": plan.size(), "moved": moved})


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
	# The director owns the fact -> destiny-counter dispatch, and this method is the
	# ONE offer point in `app/` (class docstring), so a fate's `counter` gate verb
	# is answerable from the same beat that made the fact true. Adding it here would
	# be a second writer beside the director's own — the ADR 0114 failure with a
	# different name — so nothing is re-offered; `report["counter_total"]` already
	# carries what the beat moved.
	_offered += 1
	return report


## Every world event `actor` may open right now, as primitives. Published so a
## screen can offer "walk into this" without the UI program naming `EventApi`, and
## so a missing affordance reads as an empty list rather than as silence.
func available_events() -> Array[Dictionary]:
	if _actor == null:
		return []
	return EventApi.available(_actor)


## ## THE OBSERVATION TRIGGER (ADR 0170 trigger (a), ADR 0173 (c))
##
## Someone is standing in `location_id`: fold this place's clock up to the span the fold
## has actually moved, and answer what it became. **O(1) in places and O(magnitudes) in
## arithmetic** — one division per authored row against a stored stamp, never a walk over
## the world — so nothing ticks while nobody is there and nothing walks with the span.
##
## ## THE HAZARD THIS METHOD IS ORDERED TO NOT SHIP — READ IT BEFORE EDITING
##
## ADR 0173 (c), verbatim: "an observation-driven clock DEADLOCKS if every advance source
## is itself gated on someone being present. The world freezes forever, every elapsed
## calculation returns zero, and the failure is silent."
##
## **THE RULE: ANY observation advances FIRST, then reads.** The rule is in the ORDER of
## the three lines below, not in a guard on them, because a guard is the defect: `if
## visited: fold()` answers false for every place nobody stood in, which is a silent zero
## and a frozen world. So `WorldReconcile.observe` is called with NO presence check in
## front of it, its result is written back UNCONDITIONALLY, and only then is `elapsed`
## read out of the answer. **A reader is a trigger, never a precondition of the trigger,
## and there must never be an `if` between this method's entry and `_stamps = ...`.**
## `tests/app/test_reconcile_reachability.gd` pins it by reading a place nobody has
## visited and requiring a NON-ZERO elapsed — the one assertion that cannot be softened.
##
## ## `span` is the fold's OWN delta, not a second clock
##
## `_periods` is what this pulse has handed down since boot, so the span is the same
## count the beat offer, the event advance and the institution settle were paid on. A
## separate accumulator here would be a second clock in the one layer allowed to know
## time (ADR 0089), and the two could disagree — which is the "period count not owned by
## anything" defect DEF-0171 measured, one layer down from this one.
func observe_place(location_id: StringName) -> Dictionary:
	# The span is this fold's own running total, read BEFORE the fold so a re-entry
	# cannot pay a span the world has not moved yet.
	var span := _periods
	# ADVANCE FIRST, unconditionally. No presence check, ever — see the hazard above.
	var seen := WorldReconcile.observe(_stamps, location_id, span)
	_stamps = seen["stamps"]
	# And only now, SECOND, is the place read. The stamp is folded, so the read answers
	# the place's whole folded age rather than this observation's contribution.
	return {
		"ok": true,
		"reason": "",
		"location_id": String(location_id),
		"span_periods": int(seen["span_periods"]),
		"stamped_before": bool(seen["stamped_before"]),
		"elapsed_periods": int(seen["elapsed_periods"]),
		"crossed": (seen["crossed"] as Dictionary).duplicate(),
		"advanced": bool(seen["advanced"]),
		"folded_periods": ReconcileStamp.folded_periods(_stamps, location_id),
	}


## What `location_id` IS NOW, derived from (ledger, epoch) — ADR 0170's epoch overlay
## and its only read shape. Never stored and never decremented: `state_of` computes, so
## the monotone ledger keeps every occurrence a retired world ever recorded while a
## successor reads the history it is actually living.
##
## `occurrences` is the caller's list, handed in UNMODIFIED. A reconcile READS the
## ledger's count for a place and never rewrites it, which is the same rule the fold
## holds: "reconciliation changes what a place HAS BECOME, never what it PROMISES".
func place_state(location_id: StringName, occurrences: Array = []) -> Dictionary:
	return WorldEpoch.state_of(_epochs, location_id, occurrences)


## Read `location_id`'s own epoch. Separate from [method place_state] because "which
## history is this world living" is answerable without any occurrence at all, and a
## panel asking that question should not have to build a ledger to ask it.
func epoch_of(world_id: StringName) -> int:
	return WorldEpoch.current(_epochs, world_id)


## Advance `world_id`'s epoch over `span_periods` of history and report whether it was
## allowed. The budget check is `WorldEpoch`'s own, routed through
## `TimeLadder.exceeds_budget` so there is ONE event budget in the repository.
func retire_world(world_id: StringName, successor_id: StringName) -> Dictionary:
	_epochs = WorldEpoch.successor(_epochs, world_id, successor_id)
	return {"ok": true, "reason": "", "world_id": String(world_id), "epoch": epoch_of(world_id)}


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
		# The SSOT's own division over the LAST span, published rather than
		# re-derived by a reader: `tools ui drive` prints it and a test asserts on it,
		# and a panel that restated the ladder would be a second calendar.
		"magnitudes": _crossed.duplicate(true),
		# ADR 0170's read model, primitives all the way down so `tools ui drive` prints a
		# place's age with no display at all (ADR 0038's contract, the same one
		# `WorldStage.summary` keeps). DELEGATED rather than re-derived: two copies of a
		# summary is how this repo got four copies of `RATE_STEP` (ADR 0116).
		"reconciled": WorldReconcile.summary(_stamps, _epochs),
		"stamps": _stamps.duplicate(),
		"epochs": _epochs.duplicate(),
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


## Offer one AUTHORED EVENT beat through the director, and report what it decided.
##
## This is the reverse seam DEF-0171 names: `event/EventBeatWriter` writes the fact
## ledger itself, so its beat cannot also be re-offered from `_advance` (a monotone
## ledger would count one occurrence twice). The fix is not a second offer of the
## same fact but an offer of the SAME OCCURRENCE through the one director — and the
## director records BEFORE it resolves (ADR 0117 line 46), because a sink proposes
## against the ledger and resolving first would decide a crossing stage against a
## count that does not yet include this beat.
##
## `beat_id` is the occurrence id the caller already minted (`EventFacts
## .occurrence_id`), carried verbatim: "once" is the caller's to name (ADR 0114).
## The caller — the event module, which owns that moment — routes through [method
## offer], so the direction of the edge is the composition root's alone.
##
## The `npc_tally` destination is NOT handled here: the director may not reach a
## module's internals (ADR 0093), so the writer tallies the roster after this
## returns. That second destination is a module concern, not a beat-dispatch one.
func offer_event_beat(
	actor: Actor, fact: StringName, amount: int, beat_id: StringName, source: String
) -> Dictionary:
	if _actor == null or _director == null:
		return {"ok": false, "reason": "no_owner", "claimed": false, "claimed_by": ""}
	var claim := WorldBeat.make(beat_id, fact, maxi(1, amount), source)
	var report := _director.offer(actor, claim)
	_offered += 1
	if bool(report.get("claimed", false)):
		_claimed += 1
	return report


# --- Internals -------------------------------------------------------------


## The one place a whole advance happens, so [method pull] and
## [method advance_periods] cannot drift into two half-versions of the same moment.
## Returns a report either way, and never loops.
##
## `is_spend` marks ONE CHUNK of a planned long skip: a chunk is a single budget spend
## however many periods it spans (ADR 0173), so its beats are bounded by
## `EVENT_BUDGET` rather than refused for exceeding it. An ordinary advance is the other
## shape and is checked against the budget outright.
func _advance(periods: int, is_spend: bool = false) -> Dictionary:
	if _actor == null:
		return _report(false, "no_actor")
	if _director == null:
		return _report(false, "no_director")
	if periods <= 0:
		return _report(true, "")

	# **The budget is checked FIRST, before anything moves.** An unplanned advance that
	# asks for more beats than the budget covers is refused HERE, so no event opened, no
	# institution settled and no period was counted before the refusal — a refusal that
	# arrives after the world has already advanced reports a world the caller did not get
	# to keep, which is the truncation ADR 0173 refuses in a slower voice. A PLANNED chunk
	# is exempt because one chunk IS one budget spend however many periods it spans.
	if not is_spend and TimeLadder.exceeds_budget(periods, PERIOD_FACT, periods):
		return _report(false, "over_budget")

	# **Ambient news lands BEFORE the events are consulted**, so a trigger gated on
	# what the world already remembers is satisfied by news from the same pull that
	# sighted it. `EventApi.begin` re-checks the trigger, so this cannot open early.
	_offer_ambient(_periods + periods)

	var opened := _open_available()
	_opened += opened.size()
	# The pull the event module has been waiting for. `periods` is an explicit
	# integer from the caller that owns time, which is the whole contract ADR 0085
	# asks for: the module has no clock, and this file has no rules.
	var pulled := EventApi.advance(_actor, periods)
	_periods += periods
	# ## The SSOT's magnitudes reach the institution cadence HERE
	#
	# This is the one place an elapsed span is converted into the clock's own authored
	# units, so it is the one place they may be handed to a consumer: `_settle_institutions`
	# below already folds a period count into a frequency, and folding the crossed
	# magnitudes into the SAME cadence is what gives the ladder a reader in production
	# (`institution_resolver.gd:_magnitude_periods`). A span that crossed nothing beyond
	# the base row settles on exactly the cadence it always did.
	_crossed = TimeLadder.magnitudes_crossed(periods)
	# The institutions get their period on the SAME count as everything else, because
	# a sect that aged on a different cadence from a nation is two political worlds
	# whose timing nobody could reason about — ADR 0089's argument, one layer up. The
	# resolver asks each module what it PROPOSES and dispatches through the closed
	# verb set; it holds no ledger and adds no frame driver (BL-0198).
	_settle_institutions(periods, _crossed)
	for row in opened:
		_module_recorded += _recorded_by_module(row as Dictionary)
	_module_recorded += _recorded_by_module(pulled)
	# The budget was already settled at the TOP of this method, before anything moved, so
	# this call only offers. It still returns a bool because that is the shape a caller
	# reads, and a false here would mean the budget changed under an advance that had
	# already been authorised — which the early check makes unreachable by construction.
	_offer_period_beats(periods, is_spend)
	return _report(true, "")


## Offer the period's own beats for ONE advance — at most `TimeLadder.EVENT_BUDGET`.
##
## ## This is the loop ADR 0173 (b) retires, and the budget is what replaced it
##
## It was `for index in periods: offer(PERIOD_FACT, 1, PERIOD_SOURCE)` — one beat per
## period, with a bound that is DATA-DERIVED. `AGENTS.md:52` verbatim: "a data-derived
## row count is not a fixed count either", and that is the shape of the recorded 67 GB
## incident. A 10^12-period meditation was 10^12 offers.
##
## ## A CHUNK is one budget spend, and it may be LONGER than the budget
##
## ADR 0173: "The chunk size GROWS with the elapsed span... One chunk is one budget
## spend". So a chunk of 6.8e7 periods spends `EVENT_BUDGET` events, not 6.8e7 — the
## span says what became POSSIBLE, the budget says how much of it HAPPENS. `offered` is
## therefore `min(periods, EVENT_BUDGET)` and a chunk longer than the budget is not an
## overspend; it is a complete spend.
##
## ## An UNPLANNED advance is one period per beat, and THAT can overspend
##
## A caller that skips [method advance_periods]'s plan and asks for more periods than
## the budget covers is the over-budget case: its beats go through
## [method TimeLadder.exceeds_budget], which `push_error`s naming the place, the span and
## the count and returns true, and this returns false so `_advance` refuses. ADR 0173's
## "It never truncates", and `AGENTS.md:56`: silently emitting `EVENT_BUDGET` and
## dropping the rest would hide the drop from a player and from the monotone ledger,
## which cannot un-record it.
##
## Either way the offered count never exceeds the periods that elapsed and never exceeds
## the budget, so a one-period advance still offers exactly one beat and every beat still
## goes through [method offer] — the ONE offer point (ADR 0117), which is what keeps a
## quest step watching the period completing by the same chain it always was.
func _offer_period_beats(periods: int, _is_spend: bool) -> bool:
	# **No budget check here.** It was here, and it was unreachable twice over: a caller
	# that skipped the plan could only reach it for `count` in 5..8, and by then `_advance`
	# had already opened events and settled institutions — so a "refusal" arrived after the
	# world had moved. The check now lives at the TOP of `_advance`, before anything moves,
	# which is the only position a refusal can mean anything from.
	var offered := mini(maxi(0, periods), TimeLadder.EVENT_BUDGET)
	for index in offered:
		var report := offer(PERIOD_FACT, 1, PERIOD_SOURCE)
		if bool(report.get("claimed", false)):
			_claimed += 1
	return true


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
##
## **A REFUSAL DOES NOT SPEND THE BUDGET, and that is the whole point of this method.**
##
## It used to break out of the loop as soon as `out.size()` reached the budget —
## `out` being the list of events this pull SUCCESSFULLY opened. So an event that
## `begin` declined — for any of its five named reasons, and in particular the
## `too_many_active_events` cap that fires as soon as anything else is open — consumed
## a slot in the budget that had not been spent, and everything after it in
## `available` went unasked. **The loop's budget then belonged to the world's refusals
## rather than to the world's openings.**
##
## Measured (BL-0747): `MAX_OPENS_PER_PULL` is 1, and the shipped tree puts two
## events at `mortal_plains` behind the same ambient trigger. The pull that first
## satisfies that trigger opens `beast_tide_of_the_mortal_plains`, spends its single
## open, and stops — so `the_favour_of_elder_wei`, whose trigger was satisfied on that
## very same pull, is not asked about. It is still `available`, and the NEXT pull opens
## it. Nothing was refused wrongly; a *refusal* is no longer charged to the budget.
##
## **What this does NOT promise, and where two agents were misled:** it does not
## promise that ONE pull opens every event the world allows, nor that the budget
## spares a particular event. It promises only that the budget is spent on OPENINGS —
## a refused candidate no longer consumes the one open. Which event wins a pull's single
## open is decided by `available`'s order, and that order is the catalog's STRING order
## (BL-0747, `_sorted_ids`), so with two events at one location behind one trigger the
## alphabetically first takes the pull and the second waits for the next one. That is a
## content-tree fact, not a bug: a caller that wants its event open must pull until it
## is, which is what `tests/modules/npc/test_npc_tally_production_path.gd`'s
## `_pull_until_open` does after this note cost two agents a wrong diagnosis.
##
## So the budget is now spent on OPENINGS: `begin` is still asked about every event
## `available` offers, in order, and the loop stops when this pull has opened
## [constant MAX_OPENS_PER_PULL]. The two budgets are separate on purpose — the second
## one is not a player-facing one at all, it exists so the scan cannot become
## unbounded work on a content tree with thousands of events, and it is not reached
## by the shipped eight.
func _open_available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _actor == null:
		return out
	var candidates := EventApi.available(_actor)
	var attempts := 0
	for index in candidates.size():
		if out.size() >= MAX_OPENS_PER_PULL or attempts >= MAX_OPEN_ATTEMPTS_PER_PULL:
			break
		attempts += 1
		var opened := EventApi.begin(
			_actor, StringName((candidates[index] as Dictionary).get("event_id", "")), _periods
		)
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
##
## `crossed` is the SSOT's own `magnitudes_crossed` answer for the span, handed
## through rather than re-derived here: the resolver folds it into the tier cadence it
## already owns (`institution_resolver.gd:_magnitude_periods`), and this file adds no
## calendar of its own.
func _settle_institutions(periods: int, crossed: Dictionary = {}) -> void:
	var settled := InstitutionResolver.settle(_actor, periods, crossed)
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
