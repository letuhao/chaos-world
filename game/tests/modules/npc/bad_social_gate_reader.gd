class_name BadReaders
extends RefCounted

## ## A DOUBLE whose whole job is to answer badly (the test half of ADR 0264)
##
## The social-gate seam is a `Callable`, so the interesting cases are readers that do not
## behave like `SocialApi` at all: one that answers a non-verdict, one that answers a
## dictionary carrying no `ok` key, and one that simply records what it was handed.
##
## **A separate file, and not an inner `class`, for the reason DEF-0233 records**: a
## preloaded script constant exposes only that class's STATIC surface, and an inner class in
## a `TestCase` extension is not a shape this runner loads. The failure mode is expensive
## because it is a PARSE error — the suite never runs and the tally silently UNDERCOUNTS
## every test in the file — so the helper is a real class file with a `class_name`, and a
## suite names it directly the way `floor_surface_fixture.gd` is named.
##
## **Every reader here is a NAMED method rather than a lambda.** `npc_boot.gd` records that
## a typed lambda whose body calls another script's static function killed the shell with an
## access violation, and a test suite is not the place to rediscover that.

## Every requirement this double was handed, whole. **Static** because each double is
## per-call while the requirement has to outlive the call and reach an assertion.
static var seen: Array = []


## Drop the record. A harness verb, because the runner shares one process across every suite.
static func reset() -> void:
	seen.clear()


## Answers `anything` regardless of what it was asked — a reader with no opinion at all, and
## the case that must read NEUTRAL rather than a refusal.
func answer(_player: Actor, _requirement: Dictionary, anything: Variant) -> Variant:
	return anything


## A dictionary that is not a verdict — no `ok` key. An unanswered question is not a refusal.
func no_verdict(_player: Actor, _requirement: Dictionary) -> Dictionary:
	return {"warm": 1}


## Records the requirement verbatim, then opens the gate. This is what proves the seam hands
## the AUTHORED dictionary over whole, which is the positive half of the one-evaluator rule.
func record_and_pass(_player: Actor, requirement: Dictionary) -> Dictionary:
	seen.append(requirement.duplicate(true))
	return {"ok": true, "reason": "", "unmet": []}
