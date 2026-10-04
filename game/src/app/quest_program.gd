class_name QuestProgram
extends RefCounted

## The composition root's quest program: the ONE thing in `game/src/` that calls
## [method QuestApi.accept], and the seam the quest journal commits through.
##
## ## The gap this closes
##
## `QuestApi` shipped twelve verbs and 476 green assertions with **no caller in
## `game/src/`** (BL-0663). `QuestBeatHandler.handles` asks "does an ACTIVE quest
## watch this fact?", the active set was therefore always empty, so
## `QuestFactReader` never ran and `QuestGrants.pay -> DestinyApi.earn_fate(actor,
## id, "quest:<id>")` was dead code (BL-0664). A quest was never something a
## player could see, accept or progress.
##
## ## Why a program and not a call in the screen
##
## `app` is a [code]PRIVATE_UNITS[/code] entry ([code]tools/arch/rules.py[/code]),
## so `ui/` may not name this file, and ADR 0143 says a `ui/` program reaches the
## composition root through a bridge of Callables rather than a module facade. The
## screen therefore asks for `accept` as a [Callable] and this class answers it.
## It owns no rule: every refusal, every once-guard and every gate verdict is
## [code]QuestApi[/code]'s, carried through verbatim.
##
## ## It accepts NOTHING at boot
##
## A poller that takes quests on for the player is not a player action, and
## `accept` is a commitment with a once-guard. [method open] attaches the module
## to the actor (idempotent, exactly as `DestinyApi.attach` publishes) and binds
## the seam to whatever screen the route mounted. It does **not** accept.
##
## ## ADR 0065 is untouched
##
## Nothing here grants fate, destiny or an item. Those are paid by
## `QuestGrants.pay` at the one place completion is decided (`QuestApi.complete`
## / `QuestApi.advance`), never at the moment a player presses a button.
##
## Contract: `summary()` is the testable surface, primitives only.

## The route this program binds, as `ScreenRoutes` names it.
const QUEST_ROUTE := &"quest"
## Where an offer on this board came from, recorded on the entry. ADR 0065's
## vocabulary: a source names WHERE, never WHAT is granted.
const OFFER_SOURCE := "quest:board"

var _actor: Actor = null
## The screen a route mounted, or null. Held weakly-free: this is a plain
## `RefCounted` so a test can drive it with no scene tree at all, and the caller
## owns the screen's lifetime.
var _screen: Control = null
## How many commits this program has attempted, and how many the module allowed.
## Two integers rather than a ledger: `app/` must hold no state (`APP_STATE_MARKERS`).
var _requested: int = 0
var _accepted: int = 0
var _last: Dictionary = {}


func _init(actor: Actor = null) -> void:
	_actor = actor
	if _actor != null:
		QuestApi.attach(_actor)


## Adopt an actor after construction, for a caller that built the program first.
## Attaching here is what normalises an empty ledger and drops entries naming
## content the catalog no longer ships, so `offered` is answerable immediately.
func attach(actor: Actor) -> void:
	_actor = actor
	if _actor != null:
		QuestApi.attach(_actor)


## The actor this program reads, or null.
func actor() -> Actor:
	return _actor


## Bind the seam to a mounted screen.
##
## The screen is handed ONE callable — this file's [method accept] — rather than a
## facade, because `ui/` may hold neither `QuestProgram` nor a module type. A
## screen without a `bind_quests` method is not refused: it is simply not the quest
## journal, and nothing here has to know that in advance.
func bind(screen: Control) -> Dictionary:
	_screen = screen
	if screen == null:
		return {"ok": false, "reason": "no_screen"}
	if not screen.has_method(&"bind_quests"):
		_screen = null
		return {"ok": false, "reason": "not_a_quest_screen"}
	screen.call("bind_quests", Callable(self, "accept"))
	return {"ok": true, "reason": ""}


## Open the journal on a mounted screen: bind the seam and report what it can now
## offer. **Never accepts.** A quest is taken on because a player pressed a button,
## and a boot that committed for them would make `accept`'s once-guard a lie.
##
## `ok` here means the seam is live. It is deliberately not a claim that anything
## is offered: a hero with an empty ledger legitimately has nothing to be offered,
## and reporting that as a failure would make an honest world look broken.
func open(screen: Control = null) -> Dictionary:
	var bound := bind(screen) if screen != null else {"ok": _screen != null, "reason": "no_screen"}
	if not bool(bound.get("ok", false)):
		return {"ok": false, "reason": String(bound.get("reason", "not_mounted")), "offered": 0}
	if _actor == null:
		return {"ok": false, "reason": "no_actor", "offered": 0}
	return {"ok": true, "reason": "", "offered": QuestApi.offered(_actor).size()}


## Take `quest_id` on. **The one call in `game/src/` that reaches
## `QuestApi.accept`.**
##
## `source` is recorded on the entry, so a save says where the commitment came
## from. Every refusal is the module's own verdict, carried through untouched:
## `unknown_quest`, `already_active`, `already_completed`, `gate_unmet`.
func accept(quest_id: StringName, source: String = OFFER_SOURCE) -> Dictionary:
	_requested += 1
	if _actor == null:
		_last = {"ok": false, "reason": "no_actor", "unmet": []}
		return _last
	var outcome := QuestApi.accept(_actor, quest_id, source)
	_last = outcome
	if bool(outcome.get("ok", false)):
		_accepted += 1
	return outcome


## What the program is offering and carrying, as primitives. A test asserts
## reachability through this rather than through a private field.
func summary() -> Dictionary:
	var state := QuestApi.summary(_actor) if _actor != null else {}
	return {
		"mounted": _screen != null,
		"has_actor": _actor != null,
		"actor_id": "" if _actor == null else String(_actor.id),
		"requested": _requested,
		"accepted": _accepted,
		"offered": (state.get("offered", []) as Array).size(),
		"active": (state.get("active", []) as Array).size(),
		"completed": (state.get("completed", []) as Array).size(),
		"ledger_available": bool(state.get("ledger_available", false)),
		"route": String(QUEST_ROUTE),
		"last_reason": String(_last.get("reason", "")),
	}


## The module's own count of what is offered, so a probe reads content rather than
## a restatement of it. `[]` with no actor.
func offered() -> Array[Dictionary]:
	if _actor == null:
		return []
	return QuestApi.offered(_actor)


## What is in flight, as primitives. `[]` with no actor.
func active() -> Array[Dictionary]:
	if _actor == null:
		return []
	return QuestApi.active(_actor)
