class_name WorldAmbient
extends RefCounted

## What the world says about ITSELF, and when (ADR 0114, ADR 0117, DEF-0111).
##
## ## Why this is its own file and not a table in `WorldPulse`
##
## An authored event trigger is read BEFORE `EventApi.begin` writes a single beat
## (`event/api.gd:150`), so a trigger naming a fact is asking about the world **as it
## already was**. Four shipped triggers do exactly that on purpose — `beast_tide`
## waits for a sighted storm front, `the_dawn_descent` for a sounded void seam,
## `tournament_of_the_spirit_peaks` for a called tournament, `war_of_the_nine_fords`
## for a called war — and `the_dawn_descent`'s own description states the rule they
## are built on: *"Gated on what the world already remembers rather than on a
## summons."* Nothing produced those four facts, so four of seven events could never
## open and those four gates were permanently false.
##
## **This is the missing half, and it is separate from the clock.** A period elapsing
## is elapsed time; a storm being sighted is the world saying something happened. One
## file answering both is a script that needs "and" — the SRP split `tools arch`
## warns about — so [code]WorldPulse[/code] keeps the offer and this file keeps the
## news.
##
## ## Why the pulse owns them and not the events
##
## An event cannot record the fact that starts it: that is a circular trigger, and it
## is the ADR 0066 shape wearing a trigger's clothes. ADR 0114/0117 already name the
## owner of a time-driven beat — the caller that owns the moment (DEF-0111) — and
## `WorldPulse` is that caller. Authoring them as `.tres` beats instead was rejected
## and MEASURED: a `.tres` beat reaches the ledger through `EventBeatWriter.offer`,
## which bypasses the director, so a quest step watching one of these facts would
## still never complete. See `tests/app/test_world_ambient_facts.gd`, which goes red
## on exactly that half-fix.
##
## ## Once is the LEDGER's, and this file holds no copy of it
##
## Every id here is a first-occurrence claim, and `WorldFact`'s ledger is monotone, so
## `count > 0` is the whole once-rule. [method due] READS that count and this file
## stores nothing beside it: a roster carrying its own "already said this" flag is
## the ADR 0117 second-copy failure with a boolean instead of a dictionary.
##
## ## Why the periods are staggered, and why there is no rng
##
## All four on period 1 would open four events against `WorldPulse.MAX_OPENS_PER_PULL`,
## so three would sit `available` and unread. One per period is the cadence the
## pulse's own event budget implies. **No `rng`, no `randi`, no seed** — the rule
## `SectAct` documents: the world's news is a pure function of how many periods have
## passed, so a headless probe and a frame that hitched age the world identically.
##
## ## What this file is not
##
## Not a rule and not a clock. It answers one question — *which of the world's own
## facts has this world reached and not yet said?* — and the answer is a list of ids
## for [code]WorldPulse.offer[/code] to route. It holds no actor, no ledger and no
## director.

## The world's own doings, and the period each is first reported on. A flat id in
## `WorldFact`'s namespace, exactly as ADR 0113 requires — no prefix, because a
## prefixed id "reads as a working reference and silently grants nothing".
const ROSTER: Array[Dictionary] = [
	{"fact": &"storm_front_sighted", "at_period": 1},
	{"fact": &"void_seam_sounded", "at_period": 2},
	{"fact": &"tournament_called", "at_period": 3},
	{"fact": &"sect_war_called", "at_period": 4},
]

## The audit trail on an ambient beat, in ADR 0114's own vocabulary. Distinct from
## `WorldPulse.PERIOD_SOURCE` so a save says which earned the accrual: one is elapsed
## time, the other is the world saying something happened.
const SOURCE := "world:ambient"


## Every ambient fact id, in authored order.
##
## Read rather than restated by callers, so a screen, a probe and
## [method due] can never disagree about what "ambient" names.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for row in ROSTER:
		out.append(String((row as Dictionary).get("fact", "")))
	return out


## The ambient facts `actor`'s world has reached by `horizon` and not yet recorded, in
## authored order. The answer to "what has the world not said yet".
##
## `horizon` is the period count AFTER the advance, handed in rather than read: the
## pulse owns the count and a bound read from the same thing a loop grows is the loop
## that reached 67 GB.
##
## The once-check is [method WorldFact.count], so a fact already in the ledger is
## never returned twice no matter how many times this is called. `count == 0` is the
## floor `WorldFact.has` applies too, so "not yet said" and "said nothing" are the
## same answer.
static func due(actor: Actor, horizon: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null:
		return out
	for row in ROSTER:
		var entry := row as Dictionary
		if int(entry.get("at_period", 0)) > horizon:
			continue
		var fact := StringName(entry.get("fact", &""))
		if fact == &"" or WorldFact.count(actor, fact) > 0:
			continue
		out.append(fact)
	return out


## How many of the roster `actor`'s ledger already holds. A count, never a table: the
## detail is the ledger's and `app/` must hold no memory of its own.
static func recorded(actor: Actor) -> int:
	if actor == null:
		return 0
	var held := 0
	for fact in ids():
		if WorldFact.count(actor, StringName(fact)) > 0:
			held += 1
	return held
