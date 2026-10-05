class_name Seduction
extends RefCounted

## The two-actor moment that starts a pregnancy — the producer the lineage stack has
## never had (ADR 0108).
##
## ## What this file is, and what it is not
##
## It is a COMPONENT beside `api.gd`, not a facade verb. `SectSuccession` is the
## precedent: a verb a caller needs, published on a module-level class rather than
## spent on a thirteenth public method, because `rules.MAX_FACADE_PUBLIC_METHODS`
## caps every `api.gd` at twelve. Adding `attempt` to `FertilityApi` would buy one
## method and cost the facade the headroom a later reader needs; a component buys
## the same seam and costs the facade nothing.
##
## ## Why the producer lives in `fertility` and not in `dual_cultivation`
##
## It was authored in `dual_cultivation`, and `tools arch` called that a cycle:
## `dual_cultivation -> fertility -> dual_cultivation`. Both halves of that loop
## were real rather than accidental — the coupling was written long before this file
## existed, because `FertilityApi.conception_chance` ALREADY multiplies by the
## partner's `DualCultivationApi.POTENCY` (ADR 0002), and what was missing was the
## only thing that can call it. Giving the producer a caller therefore closed the
## loop, and deleting the older edge instead would have traded a reported structural
## fact for a hidden one.
##
## So the coupling stays and the PRODUCER moves. `fertility` has declared
## `dual_cultivation` since ADR 0002, so everything this file needs from that module
## is already declared and already read through its facade. The new `social` edge
## is likewise a fan-out: `social` declares `contracts` and `core` and nothing else,
## so the graph is one node with four outgoing edges rather than a loop.
##
## ## Conception here is a CLINICAL MECHANIC, and the writing has to stay there
##
## A stat roll, a status, and an inheritance outcome (ADR 0063/0108). Nothing in this
## file may become anything else, so the register is a breeding ledger: one roll
## measured against one threshold, one refusal reason per way it can fail, and one
## authored cause recorded afterwards. There is no flavour text here for a reader to
## find suggestive, because there is nothing to be suggestive about.
##
## ## `roll` is ALWAYS a parameter. There is no `randf()` in this file.
##
## `attempt` takes the roll the caller already owns — the same shape as
## `SectSuccession.step`, which reads no clock and rolls nothing. A component that drew
## its own number would be untestable headlessly, and would make conception the one
## place in the lineage stack whose outcome could not be reproduced — exactly what ADR
## 0108's determinism rule forbids. `chance` is the pure read of the same threshold, so
## a caller that owns an rng compares its own roll against it and nobody rolls twice.

## The one `res://` edge this component owns, and the ONLY one
##
## `BARE_REF_UNITS` excludes `modules/*` (rules.py), so a bare `SocialApi` here would
## report zero violations and the whole reason this file changed module would be
## invisible to `_find_cycle` — the `nation -> sect` trap, and the reason ADR 0083
## insists on a `preload`. `dual_cultivation` is read by bare name on purpose: it is
## the same shape `FertilityProvider.contribute` and `FertilityApi.conception_chance`
## already use for that module, and the edge it belongs to has been declared since ADR
## 0002. Nothing else in this module's tree may name a class of either dependency.
const SOCIAL_FACADE := preload("res://src/modules/social/api.gd")

## The authored cause recorded on the bond when an attempt succeeds. One id, owned by
## `social`'s catalog and read here rather than reimplemented.
const CAUSE := &"bound_in_intimacy"

## The standing a bond must ALREADY hold before the attempt is made at all.
##
## ## Why the gate is a number and not merely "a bond exists"
##
## The act this component records is irreversible and permanent — it writes a
## pregnancy that carries a child's inherited lineage (ADR 0108) — so the floor is
## set at the standing the authored cause itself earns. A stranger, or an
## acquaintance met last week, does not clear it; an established partner does. It is
## a single authored figure rather than a bond CLASS so the gate cannot be satisfied by
## repeating one generous cause until `SocialBondClass`'s distinct-cause count happens
## to reach two — that is the anti-farm rule, and a class requirement would be
## sidestepped by exactly the behaviour it exists to stop.
##
## ## It is not a stat, and it is never a sum
##
## A stat can be satisfied by an item, so a gate that read one would be a gate the
## player could buy (ADR 0076). It is read through `SocialApi.gate`, which reads the
## ledger and nothing else. Nothing above the threshold is multiplied in:
## `FertilityApi.conception_chance` already applies the actor's own `fertility` and the
## partner's `potency`, and stacking a second copy of that arithmetic here would be a
## second thing to retune that drifts on the first retune — the argument
## `resolve_offspring` makes about `inherit_from`.
const REQUIRED_STANDING := 6.0

## ## Every refusal names itself
##
## Authored constants rather than free text, for the reason ADR 0083 gives: a panel
## renders the reason it is handed and must not have to invent one. They are also
## distinct game states, not synonyms — `already_pregnant` and `roll_failed` are two
## different things that happened, and a caller that showed the same text for both
## would be reporting the wrong one.
const R_NO_ACTOR := "no_actor"
const R_NO_PARTNER := "no_partner"
const R_ALREADY_PREGNANT := "already_pregnant"
const R_NO_BOND := "no_bond"
const R_ROLL_FAILED := "roll_failed"

## The `verb` of the authored requirement handed to `SocialApi.gate`. Spelled as its
## wire value rather than as `SocialGate`'s constant, because a bare class reference
## into `social` is exactly the invisible edge the `preload` above exists to avoid,
## and `SocialGate` publishes the requirement as a plain `Dictionary` (ADR 0076).
const VERB_STANDING_AT_LEAST := &"standing_at_least"


## Attempt one conception between `actor` and `partner`, measured by the supplied
## `roll`. Returns `{ok: bool, reason: String}`; every refusal leaves the actor's
## statuses and the bond's axes exactly as found.
##
## The ORDER of the refusals is part of the contract. The most specific state is
## checked first, so a caller can tell "there is nobody here" from "you are already
## carrying a pregnancy" from "the social floor is not met" from "this outcome did not
## occur" without parsing prose.
##
## `FertilityApi.try_conceive` is called EXACTLY ONCE, and only after every refusal has
## been ruled out. That is what makes "a refusal writes no status" structural rather
## than something this function has to remember: the only path that reaches the status
## machine is the path that was going to write a pregnancy anyway.
static func attempt(actor: Actor, partner: Actor, roll: float) -> Dictionary:
	if actor == null:
		return _refuse(R_NO_ACTOR)
	if partner == null:
		return _refuse(R_NO_PARTNER)
	if not FertilityApi.can_conceive(actor):
		return _refuse(R_ALREADY_PREGNANT)
	if not can_meet(actor, partner):
		return _refuse(R_NO_BOND)
	if not FertilityApi.try_conceive(actor, partner, roll):
		return _refuse(R_ROLL_FAILED)
	# One-sided by construction, and deliberately so: `SocialApi.apply_cause` writes one
	# bond and the mirror is the caller's transaction (ADR 0091). A child is a fact
	# between two actors, and only the module that owns the interaction knows whether
	# the other party regarded it.
	SOCIAL_FACADE.apply_cause(actor, partner.id, CAUSE)
	return {"ok": true, "reason": ""}


## The chance `attempt` compares `roll` against, or `0.0` when the attempt could not
## be made at all.
##
## A pure read: no `rng`, no mutation, no status. Calling it twice on the same pair
## returns the same number, which is what lets a panel show an odds line next to a
## roll it does not own.
static func chance(actor: Actor, partner: Actor) -> float:
	if actor == null or partner == null:
		return 0.0
	if not FertilityApi.can_conceive(actor):
		return 0.0
	if not can_meet(actor, partner):
		return 0.0
	return FertilityApi.conception_chance(actor, partner)


## The social gate on its own: whether the ledger says these two are established
## enough for the attempt. `true` says the floor is met — never that a conception will
## follow, which is the roll's business and nobody else's.
static func can_meet(actor: Actor, partner: Actor) -> bool:
	if actor == null or partner == null:
		return false
	var requirement := {
		"verb": VERB_STANDING_AT_LEAST,
		"partner": String(partner.id),
		"at_least": REQUIRED_STANDING,
	}
	return bool(SOCIAL_FACADE.gate(actor, requirement).get("ok", false))


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
