class_name CombatProposalReader
extends RefCounted

## Reads a mechanism's proposal. TOTAL by construction: a proposal that answers
## nothing answers `DamageProposal.NONE`.
##
## The shape this module needs is the shape ADR 0067 specifies — `{amount, effects}` —
## and it is read through `get()` rather than through a typed field so a concurrent
## edit to `contracts/DamageProposal` is a runtime zero rather than a compile break in
## the spine. The spine has to survive a mechanism written against a shape it does not
## have, and the failure that matters is a quiet one: a crash three stages later reads
## as "the mechanism did nothing".


## The amount a mechanism produced, or 0.0 for a proposal that is null, carries no
## `amount`, or answers one that is not a number.
static func amount_of(proposal: RefCounted) -> float:
	if proposal == null:
		return 0.0
	var value: Variant = proposal.get(&"amount")
	if not (value is float or value is int):
		return 0.0
	return float(value)


## The effects a mechanism carried, as the Array of Dictionaries ADR 0067 describes.
## Duplicated, so a mechanism mutating its own proposal after the spine has read it
## cannot rewrite what the outcome says happened.
static func effects_of(proposal: RefCounted) -> Array:
	if proposal == null:
		return []
	var value: Variant = proposal.get(&"effects")
	if not (value is Array):
		return []
	return (value as Array).duplicate(true)


## A proposal of this shape, for a caller that needs to hand one back. Used by the
## facade's context builder and by any test asserting the seam's output.
static func make(amount: float, effects: Array = []) -> RefCounted:
	var proposal := Proposal.new()
	proposal.amount = amount
	proposal.effects = effects
	return proposal


## The proposal shape the spine reads, stated once so the spine does not restate it in
## four places. NOT `contracts/DamageProposal`: this is the reader's own type, so the
## spine compiles whether or not the contracts wave has landed. A real
## `DamageProposal` reads identically through [method amount_of] /
## [method effects_of], because those go through `get()`.
class Proposal:
	extends RefCounted

	var amount: float = 0.0
	var effects: Array = []
