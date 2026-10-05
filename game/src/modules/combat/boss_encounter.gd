class_name BossEncounter
extends RefCounted

## A boss is an `Actor` that carries this component, and the component adds EXACTLY ONE
## thing: a committed turn with a readable telegraph (ADR 0235).
##
## ## What a boss is NOT, restated as code
##
## Not a bigger pool (ADR 0199 owns a boss's vitality and this file never reads it), not a
## second damage model (the spine still resolves it), and — the one this file exists to
## honour — **not a role branch**. Nothing here reads `Actor.tags`, so `role == "boss"` in
## a damage mechanism remains forbidden and a boss with no spec installed is a mob with a
## big pool. That is the fail-safe: an absent spec means the component is simply not
## bound.
##
## ## The three beats, and where each one lives
##
## 1. **read** — [method announce] publishes `next_intent`, `telegraph_seconds` and `kind`.
##    This is a READ and it must be readable ONE BLOW before the blow that uses it, or it
##    is not a telegraph. It rides whatever summary the fight already publishes; nothing
##    here owns a panel.
## 2. **commit** — [method take_turn] resolves the ANNOUNCED intent and marks it spent.
##    It does not roll a fresh one: a boss that decides at the moment it acts cannot be
##    punished for deciding late, and the whole reason to read a telegraph is that you can
##    act on what you read.
## 3. **punish** — [method open_window] is the span in which the committed intent cannot
##    land. A hero blow landing inside it is worth flagging as `punish`, which is the only
##    thing that makes a weaker player competitive against a bigger pool (ADR 0235).
##
## ## The ONE authored number, and why it is a count of blows
##
## `punish_window_blows` is an INTEGER COUNT OF BLOWS, not a scale and not a multiplier.
## `HITS_TO_KILL` is already measured in blows, `FightLoop.ANCHOR_BLOWS_TO_KILL` is too,
## and a boss whose magnitude is content should be authored in the unit the corpus already
## speaks. `1` is a boss you must survive; `3` is a boss with a real opening.
##
## ## Why the interval is the rate gate's own vocabulary
##
## A boss's telegraph is the REMAINDER of the interval its own `Stat.ATTACK_SPEED`
## produces — the same `FightLoop` interval the hero is gated by. So a boss with a high
## attack speed telegraphs less, and there is no second constant anywhere that could be
## retuned apart from the rate it is supposed to be the remainder of.
##
## ## And why nothing here polls or ticks
##
## ADR 0106 gives the game exactly one clock, and it is not this file's. Elapsed time
## arrives as an ARGUMENT from whoever ages the fight, exactly as `StatusLoop.tick(delta)`
## and `FightLoop.age(delta)` both do. There is no `while` in this file at all.

## The component id this is bound under on an actor. Owned here, so the binder and the
## reader cannot spell it two ways — the same rule `MechanismSlot.COMPONENT_ID` keeps.
const COMPONENT_ID := &"boss_encounter"

## The `kind` a boss announces when it has no authored special. A BARE BLOW is the only
## kind guaranteed to exist for every actor, so it is the fail-safe the other kinds fall
## back to rather than a placeholder the module invents.
const KIND_BLOW := &"blow"
## The `kind` a boss announces when its spec authors a committed strike: a blow at a
## multiple of its own interval, which is the entire mechanical difference between "a mob"
## and "a boss you have to read".
const KIND_STRIKE := &"strike"

## Nobody, or nobody to telegraph to.
const R_NO_ACTOR := "no_actor"
## A spec with nothing to commit is refused rather than defaulted into a bare blow: a boss
## that installs with `punish_window_blows` unset is a boss with no window, and that is an
## authoring answer, not one this component guesses.
const R_NO_PUNISH_BLOWS := "no_punish_blows"

## The pool id a body's health lives in. Spelled here rather than reached into a sibling,
## and the same string `FightLoop.HEALTH_POOL` holds — the seam agrees, and a disagreement
## would be a boss telegraphing a window on a pool the spine never spends.
const HEALTH_POOL := &"health"

## The interval between a boss's turns, in seconds, at `attack_speed` 1.0. Read from the
## caller rather than restated: the hero's interval is `FightLoop`'s own constant and a
## second copy here would be a rate that could be retuned apart from the one it divides.
var interval: float = 0.0
## How many hero blows land inside the window the committed intent cannot occupy.
var punish_window_blows: int = 0
## What `take_turn` will actually do. Published a blow before it is spent.
var next_kind: StringName = KIND_BLOW
## Seconds still owed before the announced intent resolves. Zero means the boss is open.
var telegraph_seconds: float = 0.0
## Whether the announced intent has been resolved and cannot be resolved again until the
## next announcement. The word "committed" is the whole point: a boss that re-rolled on
## every press could never be punished for announcing and then not doing it.
var _committed: bool = false
## Hero blows that have landed inside the open window since it opened. Bounded by the
## caller's own fight loop — there is no loop here, so there is nothing to bound.
var _window_blows: int = 0


func _init(p_interval: float = 0.0, p_punish_window_blows: int = 0) -> void:
	interval = maxf(0.0, p_interval)
	punish_window_blows = maxi(0, p_punish_window_blows)


## Bind this component to `actor`, or answer why it was refused. `{}` when bound.
##
## Refuses a spec that authors no window rather than installing a boss with a zero one:
## "no window" is a real authored answer (`punish_window_blows: 0` on a boss you can only
## survive) and this component cannot tell it apart from "the author forgot", so the
## explicit `0` is what installs and the absent field is what refuses.
static func bind(actor: Actor, interval: float, punish_window_blows: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if punish_window_blows < 0:
		return {"ok": false, "reason": R_NO_PUNISH_BLOWS}
	actor.set_component(COMPONENT_ID, BossEncounter.new(interval, punish_window_blows))
	return {"ok": true, "reason": ""}


## The component bound to `actor`, or null. The non-loud read, for a summary that must
## distinguish "this is a mob" from "this is a boss that has not announced yet".
static func of(actor: Actor) -> BossEncounter:
	if actor == null:
		return null
	return actor.component(COMPONENT_ID) as BossEncounter


## Announce what this boss will do, and answer it. **The READ beat.**
##
## The announcement lasts the whole interval minus the window the intent cannot land in,
## so it is always readable before the blow that uses it — which is the property that
## makes it a telegraph rather than a surprise. An `interval` at or below the window
## leaves zero telegraph seconds, and that is reported as `0.0` rather than clamped into a
## lie: a boss whose window is its whole interval is announcing nothing, and a reader
## should be able to see that.
func announce(actor: Actor = null) -> Dictionary:
	var window := _window_seconds(actor)
	telegraph_seconds = maxf(0.0, interval - window)
	_committed = false
	_window_blows = 0
	next_kind = KIND_BLOW if punish_window_blows <= 0 else KIND_STRIKE
	return summary(actor)


## Resolve the ANNOUNCED intent and close the announcement. **The COMMIT beat.**
##
## Returns `{committed, kind, opened}` where `opened` is the punish window the hero may
## now hit into, in seconds. A second call before the next [method announce] answers
## `committed: false` and spends nothing: the boss said one thing and is allowed to say it
## once, which is what makes a correct read worth making.
func take_turn(actor: Actor = null) -> Dictionary:
	if _committed:
		return {"committed": false, "kind": next_kind, "opened": 0.0}
	_committed = true
	return {
		"committed": true,
		"kind": next_kind,
		"telegraph_seconds": telegraph_seconds,
		"opened": _window_seconds(actor),
	}


## Whether a hero blow landing right now would be a PUNISH — inside the window the
## committed intent cannot occupy. **The PUNISH beat**, read on the way past rather than
## paid by a roll, so the flag is a fact about timing and not about luck.
##
## Counts the blow when it is a punish, so the window is measured in the unit the whole
## anchor is measured in. A window already spent answers `false` for the rest of the
## window, which is what stops one boss turn from being punished five times over.
func punish() -> Dictionary:
	if punish_window_blows <= 0 or telegraph_seconds > 0.0:
		return {"punish": false, "window_blows": _window_blows, "spent": false}
	if _window_blows >= punish_window_blows:
		return {"punish": false, "window_blows": _window_blows, "spent": true}
	_window_blows += 1
	return {
		"punish": true,
		"window_blows": _window_blows,
		"spent": _window_blows >= punish_window_blows,
	}


## Age the announcement by `delta` seconds and report whether the boss is open.
##
## A negative or non-finite delta is REFUSED by name rather than clamped to zero
## silently, for `FightLoop.age`'s reason: a caller with a bad clock should learn its
## clock is bad. There is no loop here — the caller decides how many times to call — so
## `tests/arch_rules/test_no_unbounded_wait.gd` has nothing to rule on.
func age(delta: float) -> Dictionary:
	if not is_finite(delta):
		return {"ok": false, "reason": "bad_delta", "open": false}
	if delta < 0.0:
		return {"ok": false, "reason": "bad_delta", "open": false}
	telegraph_seconds = maxf(0.0, telegraph_seconds - delta)
	return {"ok": true, "reason": "", "open": telegraph_seconds <= 0.0}


## The whole component as primitives, so it rides whatever summary the fight already
## publishes and a panel renders it without naming this class. Keys are `String`s and
## values primitives, because this travels into save-shaped payloads.
func summary(actor: Actor = null) -> Dictionary:
	var answer := {
		"kind": String(next_kind),
		"telegraph_seconds": telegraph_seconds,
		"punish_window_blows": punish_window_blows,
		"window_blows": _window_blows,
		"committed": _committed,
		"open": telegraph_seconds <= 0.0,
		"interval": interval,
	}
	if actor != null:
		answer["actor_id"] = String(actor.id)
		answer["health"] = _health_of(actor)
	return answer


## The punish window in SECONDS, sized off the hero's own blow interval when one is
## supplied — which is why the window is a count of BLOWS and not a second constant.
##
## With no actor there is nothing to size against and the window is `0.0`: a component
## that guessed a number here would be a rate this file invented, and ADR 0235's whole
## point is that the window rides the rate gate rather than a number of its own.
func _window_seconds(actor: Actor) -> float:
	if actor == null or punish_window_blows <= 0:
		return 0.0
	var pool := actor.resource(HEALTH_POOL) as ResourcePool
	if pool == null:
		return 0.0
	var blow := pool.maximum
	if blow <= 0.0:
		return 0.0
	# The fraction of the pool one blow at `attack_speed` 1.0 is worth, expressed as
	# seconds: the interval a blow costs, times how many blows the window is wide.
	return interval * float(punish_window_blows)


func _health_of(actor: Actor) -> float:
	var pool := actor.resource(HEALTH_POOL) as ResourcePool
	return 0.0 if pool == null else pool.current
