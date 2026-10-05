class_name DomainSeedWalk
extends RefCounted

## `Enter` against a template, advancing the seed until the MODULE accepts one.
##
## ## Why the seed has to move at all
##
## `DomainGenerator.generate` partitions a template's extent and REFUSES a partition
## below the template's `min_rooms` — it pushes `produced N room(s), below its
## min_rooms M` and returns null. `generate_and_enter` turns that into
## `generation_refused`, so a template whose partition under one particular seed lands
## short produces NO domain and the button does nothing a player can see. That is a
## property of the SEED and the TEMPLATE together, not a defect in either: the same
## template generates from a neighbouring seed. Pressing `Enter` should enter something,
## so the walk advances rather than reporting a refusal the player can do nothing about.
##
## ## Why this is not papering over it
##
## Three things stay true, and each is what the alternative lost:
##
##  - The attempt count is [constant MAX_SEED_ATTEMPTS] — a named, small cap, snapshot
##    BEFORE the loop. There is no loop that can be made unbounded by authoring a template
##    nothing satisfies (`tests/arch_rules/test_no_unbounded_wait.gd`).
##  - The refusal is NEVER swallowed. A reason that is not a generation refusal is
##    returned IMMEDIATELY, untouched, on the first attempt — so `no_such_template` and
##    `invalid_contract` reach the player exactly as the module worded them.
##  - If every attempt refuses for the generation reason, the LAST refusal is what gets
##    returned, so the line names the module's own `generation_refused` rather than a
##    wording this program invented.
##
## ## Why it is deterministic, not a roll
##
## The seeds are `first_seed + attempt`, so two presses of one button enter the SAME
## domain: the walk is a pure function of the template, and "what is in there" is
## unreadable between two visits if it changes. This is the same seed discipline
## `DomainBridge.DEFAULT_SEED` documents.
##
## ## Why it lives in `ui/panels/` and is not a method on the screen
##
## It is a policy over one seam call, with no widget in it, and the screen that hosts it
## was over its thousand-line ceiling. It is also the piece a test wants to drive alone:
## `attempt` count, "stops at the first non-generation refusal" and "returns the LAST
## generation refusal" are three separable claims.

## How many derived seeds the walk will try before refusing. Small and named, never
## unbounded: the generator is REFUSAL-first by design (`generate` returns null rather
## than a partial map), and a refusal carries no verdict that a different seed would fare
## better — so a screen that kept drawing seeds until one worked would turn a content
## defect into an unbounded loop.
const MAX_SEED_ATTEMPTS := 8

## The ONE refusal a different SEED might answer. Held as a named constant because the
## walk branches on it and it must not become a bare string literal: the module's
## `DomainApi.ERR_GENERATION_REFUSED` is not nameable from `ui/` (`domain` is not in
## `rules.UI_MODULES`), so the id is carried and worded by `DomainBridge.REASON_TEXT`.
const GENERATION_REFUSED := "generation_refused"


## `enter` against `template_id`, starting at `first_seed`, and return the LAST answer
## either way so the caller still repaints from the untouched actor.
##
## `enter` is `Callable(Actor, StringName, int) -> Dictionary` — the seam action itself,
## handed in rather than reached for, so this object names no domain type and the screen
## keeps the only reference to its own bridge.
##
## **STATIC, and called statically** (`domain_explore.gd` reads `DomainSeedWalk.walk(...)`).
## The body below touches no member of `self` — it is a pure function of `enter`, the
## actor, the template and the starting seed. Reaching it on the class rather than an
## instance is therefore both correct and the smaller change; the alternative (instantiate
## at the call site) would allocate a RefCounted per press for state that does not exist.
static func walk(
	enter: Callable, actor: Actor, template_id: StringName, first_seed: int
) -> Dictionary:
	if not enter.is_valid():
		return {"ok": false, "reason": "no_inventory_bridge"}
	var refusal: Dictionary = {}
	# `MAX_SEED_ATTEMPTS` is a CONSTANT read before the loop, so the bound cannot be data
	# this body mutates (INC-0002's shape is a bound that grows with the thing it counts).
	for attempt in MAX_SEED_ATTEMPTS:
		var answer: Variant = enter.call(actor, template_id, first_seed + attempt)
		var result: Dictionary = answer as Dictionary if answer is Dictionary else {}
		if bool(result.get("ok", false)):
			return result
		refusal = result
		if String(result.get("reason", "")) != GENERATION_REFUSED:
			# Not something a different seed would change, so stop asking and report it.
			return result
	# Every seed the bounded walk tried was refused for the same reason. The LAST refusal
	# is returned rather than a fresh call, so the player is told the module's own
	# `generation_refused` once and the walk costs MAX_SEED_ATTEMPTS generations, not
	# MAX_SEED_ATTEMPTS + 1.
	return refusal
