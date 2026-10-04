class_name CharacterCreationProgram
extends RefCounted

## Opens character creation at BOOT, for a player who has no hero yet (ADR 0130).
##
## ## Why this exists at all
##
## `character_creation.gd` and its scene shipped with a full suite and no player could reach
## them: a repo-wide grep found references only in their own `.tscn`, their `.uid` and their
## test. A passing suite on an unreachable screen is the exact shape DEF-0109 and DEF-0151
## record in this repo.
##
## ## It OPENS a route rather than pushing its own screen
##
## `ScreenRoutes.ROUTES` now names `character_creation` (commit da1a390f), so the nav bar can
## open it too. **This program therefore opens that same route** rather than instantiating a
## second copy of the scene: two doors to one screen means a player can be looking at a
## creation screen the route table does not know about, and `test_screen_reachability` exists
## precisely to catch a screen no route names.
##
## ## It opens ONLY when there is no hero
##
## A returning player with a restored body must not be sent back through creation. The check is
## here rather than unconditional for that reason alone — and because the hero a restored boot
## holds arrives through [method adopt], [method open] refuses it on its own terms rather than
## trusting the caller to have checked.

## ## Why it also ADOPTS the hero a commit makes
##
## The program answers one question — how did this hero arrive — and the answer is worthless if
## the hero it builds is not the one the player then plays. This class holds the composition
## root's `adopt` seam for that, in the same shape `SoulDeath` uses and for the same reason:
## naming the root would be a dependency the module-graph rules are right to forbid.

## The route id the nav table uses for the arrival screen.
const CREATION_ROUTE := &"character_creation"

## Where the stack is, so the program can open and observe. Held rather than inherited: this is
## a plain `RefCounted`, so it can be driven by a test with no scene tree at all.
var _stack: ScreenStack = null
## The flow the candidates come from and the commit goes through.
var _flow: CharacterCreationFlow = null
## Opens a route by id. Injected so this class names no navigation method and stays testable.
var _open_route: Callable = Callable()
## The composition root's actor-adoption callback, handed the created hero so it becomes the
## body the player PLAYS. See [method commit] for why a commit that did not call this built a
## hero nobody ever played.
var _adopt_body: Callable = Callable()
## The body creation produced, or null until it commits.
var _created: Actor = null


func _init(
	stack: ScreenStack = null,
	flow: CharacterCreationFlow = null,
	open_route: Callable = Callable(),
	adopt_body: Callable = Callable()
) -> void:
	_stack = stack
	_flow = flow
	_open_route = open_route
	_adopt_body = adopt_body


## Whether this program holds a hero. The one question boot asks to decide whether to offer
## creation at all.
func has_hero() -> bool:
	return _created != null


## The hero creation produced, or null.
func hero() -> Actor:
	return _created


## Adopt a hero this program did not create — a restored save, or one built elsewhere. Without
## it a boot flow that mints its own hero would still offer creation, because this program only
## ever learns about a hero it made.
func adopt(body: Actor) -> void:
	if body != null:
		_created = body


## Open the arrival screen, or answer why it could not.
##
## `{}` — not a refusal — when nothing is mounted, because "the program is not mounted" is the
## honest answer and a shell with no creation program must still boot.
func open() -> Dictionary:
	if _stack == null or _flow == null:
		return {"ok": false, "reason": "not_mounted", "opened": false}
	# **The returning-player gate lives HERE, not only in the caller.** A hero that already exists
	# -- restored from a save, or adopted by [method adopt] -- must not be sent back through
	# arrival. Putting the check in the program rather than only at the call site means every
	# caller gets it, including a test that opens it directly.
	if has_hero():
		return {"ok": false, "reason": "already_has_hero", "opened": false}
	if not _open_route.is_valid():
		return {"ok": false, "reason": "no_route_opener", "opened": false}
	_open_route.call(CREATION_ROUTE)
	var live := _stack.current()
	if live == null:
		return {"ok": false, "reason": "route_did_not_open", "opened": false}
	# The screen takes its candidates and its commit through injected callables, because `ui/`
	# may not reference `app/` (`rules.py` `PRIVATE_UNITS`) — the ADR 0076 loot-bridge shape.
	if live.has_method(&"bind_creation"):
		live.call("bind_creation", _flow.candidates(), Callable(self, "commit"))
	return {"ok": true, "reason": "", "opened": true, "candidates": _flow.candidates().size()}


## Commit `origin_id` through the flow, record the hero, and HAND IT TO THE ROOT.
##
## **The screen is NOT popped here.** It is opened through the route table, so popping it would
## leave the nav bar pointing at a route that is no longer on the stack — and the screen's own
## `act_commit` already reports the committed arrival, so there is nothing to dismiss.
##
## ## Why the adopt call is here and not merely in `adopt`
##
## **This method used to write `_created` and return, and nothing reassigned the root's actor.**
## The result was a player who answered "how did you arrive?", read "Arrival committed. What it
## carried is yours for good", and then played the generic boot hero: no origin destiny, no
## race-closed paths, a different body plan. The exclusivity the screen promises was enforced on
## a hero nobody played, and `has_hero()` answered true the whole time — the program's own
## opinion of itself, which is exactly what a reachability assertion on `hero()` measures.
##
## The seam is an injected `Callable`, which is what `SoulDeath` does for the rebirth path and
## what `NpcApi.set_minter` does for spawning. Naming `ItemWorkbenchApp` here would make this
## class depend on the composition root it is already a part of, and `app/` is a `PRIVATE_UNIT`
## (`tools/arch/rules.py`), so the injection is the shape that survives a boundary rule change
## rather than the one that would have to be undone by it.
##
## A commit with no adopt seam still succeeds and still records its hero — a bare
## `CharacterCreationProgram` driven by a test has no root to hand it to. It reports
## `adopted: false`, so the difference is observable rather than silent.
func commit(origin_id: StringName) -> Dictionary:
	if _flow == null:
		return {"ok": false, "reason": "not_mounted"}
	var outcome := _flow.build(origin_id)
	if not bool(outcome.get("ok", false)):
		return outcome
	_created = outcome.get("actor", null) as Actor
	# The whole point of the program: a created hero must be the body the player then plays.
	var adopted := false
	if _created != null and _adopt_body.is_valid():
		_adopt_body.call(_created)
		adopted = true
	var answer := outcome.duplicate()
	answer["adopted"] = adopted
	return answer


## What the program is showing, as primitives. A probe asserts reachability through this rather
## than through a private field.
##
## `adopt_seam` is published because "has a hero" and "the player plays that hero" are two
## different claims, and `has_hero` only ever answered the first — which is how a created hero
## went unplayed while every suite asserting this summary stayed green.
func summary() -> Dictionary:
	return {
		"mounted": _stack != null and _flow != null,
		"has_hero": has_hero(),
		"hero_id": "" if _created == null else String(_created.id),
		"candidates": 0 if _flow == null else _flow.candidates().size(),
		"route": String(CREATION_ROUTE),
		"adopt_seam": _adopt_body.is_valid(),
	}
