class_name SoulGate
extends RefCounted

## The one rule owner for "which arrival does this soul return into" (ADR 0130).
##
## ## Why the answer is not the player's
##
## ADR 0065 forbids a picker over fates and destinies. A rebirth that asked the player which
## path to return into would be exactly that picker, one layer removed — and worse, it would
## ask it after the worst moment in a run. So the answer is derived from the LEDGER: the first
## authored arrival this soul has not already lived through, in authored order.
##
## ## Determinism is the contract
##
## There is no randomness anywhere in this file, and that is deliberate rather than an
## omission. A gate that drew at random could hand two players who died identically different
## arrivals, which makes the rule untestable and the save unreproducible. The same ledger
## always yields the same answer, and a test asserts it.

## Why no arrival is left.
const NO_ARRIVALS := &""


## The arrival this ledger is owed next, or `&""` when every authored arrival has been lived
## through.
##
## `catalog` is asked for its ordered ids rather than scanned here, so the gate holds the RULE
## and the catalog holds the CONTENT. Swapping the content tree changes the answer without
## changing the rule, which is what makes both testable apart.
static func next_arrival(ledger: Dictionary, catalog: SoulCatalog) -> StringName:
	if catalog == null:
		return NO_ARRIVALS
	var held := ledger.get("origins", []) as Array
	for arrival_id in catalog.arrival_ids():
		if held.has(String(arrival_id)):
			continue
		return arrival_id
	return NO_ARRIVALS


## Whether the soul still has a body to lose. Asked of the ledger rather than re-derived from a
## difficulty row, because lives are the soul's own number and difficulty only scales the cost
## of losing one (ADR 0129).
static func can_rebody(ledger: Dictionary) -> Dictionary:
	if ledger.is_empty():
		return {"ok": false, "reason": "no_soul", "unmet": ["no_soul"]}
	if not SoulState.has_lives(ledger):
		return {
			"ok": false,
			"reason": "no_lives",
			"unmet": ["lives_exhausted"],
		}
	return {"ok": true, "reason": "", "unmet": []}


## The whole answer in one call: can this soul re-body, and into what. The pair belongs
## together because a caller that asks the first and then separately resolves the second can
## read them across a write and get a verdict describing two different souls.
static func evaluate(ledger: Dictionary, catalog: SoulCatalog) -> Dictionary:
	var verdict := can_rebody(ledger)
	verdict["arrival"] = String(next_arrival(ledger, catalog))
	return verdict
