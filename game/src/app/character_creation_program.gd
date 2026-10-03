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
## ## Why it opens ONLY when there is no hero
##
## A returning player with a restored body must not be sent back through creation. The check is
## here rather than unconditional for that reason alone.

## The route id the nav table uses for the arrival screen.
const CREATION_ROUTE := &"character_creation"

## Where the stack is, so the program can open and observe. Held rather than inherited: this is
## a plain `RefCounted`, so it can be driven by a test with no scene tree at all.
var _stack: ScreenStack = null
## The flow the candidates come from and the commit goes through.
var _flow: CharacterCreationFlow = null
## Opens a route by id. Injected so this class names no navigation method and stays testable.
var _open_route: Callable = Callable()
## The body creation produced, or null until it commits.
var _created: Actor = null


func _init(
	stack: ScreenStack = null, flow: CharacterCreationFlow = null, open_route: Callable = Callable()
) -> void:
	_stack = stack
	_flow = flow
	_open_route = open_route


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


## Commit `origin_id` through the flow and record the hero.
##
## **The screen is NOT popped here.** It is opened through the route table, so popping it would
## leave the nav bar pointing at a route that is no longer on the stack — and the screen's own
## `act_commit` already reports the committed arrival, so there is nothing to dismiss.
func commit(origin_id: StringName) -> Dictionary:
	if _flow == null:
		return {"ok": false, "reason": "not_mounted"}
	var outcome := _flow.build(origin_id)
	if not bool(outcome.get("ok", false)):
		return outcome
	_created = outcome.get("actor", null) as Actor
	return outcome


## What the program is showing, as primitives. A probe asserts reachability through this rather
## than through a private field.
func summary() -> Dictionary:
	return {
		"mounted": _stack != null and _flow != null,
		"has_hero": has_hero(),
		"hero_id": "" if _created == null else String(_created.id),
		"candidates": 0 if _flow == null else _flow.candidates().size(),
		"route": String(CREATION_ROUTE),
	}
