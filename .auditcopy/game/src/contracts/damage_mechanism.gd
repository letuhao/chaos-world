class_name DamageMechanism
extends RefCounted

## The seam: how ONE cultivation path turns a landed attack into damage
## (ADR 0067). Two virtuals, and nothing else.
##
## ## Why an abstract base and not a `Dictionary` of callables
##
## A dictionary has no name, so the repo rule "any script implementing a
## `contracts/` interface must pass the same contract tests" would have nothing to
## point at: a per-path mechanism written as a lambda can only be tested against
## whatever the caller happened to write. A named class is what makes "qi, body and
## mind all ship the same contract tests" a thing anyone can be held to.
##
## ## Why not a bare component lookup with a downcast
##
## `Actor.component()` returns `RefCounted`, so `as DamageMechanism` on null is
## SILENT and surfaces three stages later as "the mechanism did nothing" — a
## balance bug rather than a missing binding. `modules/combat/mechanism_slot.gd` owns
## that cast and fails loudly; this file only has to be the thing it casts to.
##
## ## The two stages are separate ON PURPOSE
##
## S4 (`resolve`) produces what the path DOES. S5 (`mitigate`) applies the path's own
## defence. Splitting them lets the spine assert S4 and S5 independently: a test can
## prove the mechanism produced X and that the reduction of X is Y, instead of only
## observing one fused number. qi/body read `Stat.DAMAGE_REDUCTION` here; mind reads
## nothing here at all, because `Stat.DAMAGE_REDUCTION` must NEVER touch a mind hit
## (BRIEF 2.3) and a seam that offered the field would invite it.
##
## ## The contract, in full
##
## **PURE.** No RNG of its own beyond `ctx.rng` — and when `ctx.rng` is null a
## mechanism MUST NOT roll at all, because a deterministic caller is asking for the
## one answer that consults no randomness. No mutation of the actor, the contexts or
## the proposal it was handed: `mitigate` returns a proposal and does not edit the
## caller's. No scene tree, no `Actor`, no frame time. State the whole thing as one
## testable property: `resolve` called twice on the same context returns the same
## proposal, and neither call leaves the context changed.
##
## Returns the empty proposal for a hit it declines to convert. That is a legitimate
## answer — the spine's S8 chip floor is what guarantees a LANDED hit is non-zero, so
## a mechanism has no vocabulary for "I refuse this hit", and it must not invent one.

## The component id this contract is bound under on an actor. Owned here so a
## mechanism and its slot cannot spell it two ways; `MechanismSlot.COMPONENT_ID`
## holds the same string.
const COMPONENT_ID := &"damage_mechanism"


## S4: what this path's mechanism PRODUCES for one landed hit. `ctx.base` is S1's
## output; a mechanism never sees the band roll (S2 came first) and never sees crit as
## an input (S6 comes after).
##
## The default declines: a mechanism that does not override this contributes nothing,
## which is the correct behaviour for a stub and a loud one for a real path.
func resolve(_ctx: AttackContext) -> DamageProposal:
	return DamageProposal.none()


## S5: this path's own mitigation, applied to `proposal` and RETURNED. The default
## returns the proposal unchanged, so a mechanism that has no mitigation of its own
## needs no override.
func mitigate(_ctx: AttackContext, _proposal: DamageProposal) -> DamageProposal:
	return _proposal
