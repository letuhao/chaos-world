class_name CombatOutcome
extends RefCounted

## What one resolved hit did, in primitives (ADR 0067, ADR 0038).
##
## Every field is a primitive — float, bool, String, StringName, or an Array of
## Dictionaries — so `to_dict()` feeds a screen's `summary()` unchanged and no UI code
## ever names this class (ADR 0038's "primitives only, so `ui/` can render it").
##
## ## The four `false` semantics
##
## `missed` means the attack never arrived, so nothing else happened: `amount` is 0.0
## and nothing was spent. `parried` and `blocked` mean the attack DID arrive and the
## defender answered it — the mechanism ran, and the stage list's own post-arrival
## stages (S6..S11) still ran, because the ADR fixes their order relative to S2 and
## not relative to "arrived". A caller that wants "clean hits only" tests `clean`, not
## `missed`; a caller that wants "did it cost me anything" tests `is_landed`.
##
## The read model exists so a parry is a DEFENSIVE RESPONSE to the blow rather than an
## exemption from it: `CombatSpine.PARRY_COST` and `CombatSpine.BLOCK_COST` are the
## NEUTRAL shares of the landed amount that survive a parry or a block, applied at S9's
## entrance (after S8's floor, before the health write) and moved from the neutral by
## the response's own `strength`/`shred` pair (ADR 0878). They are refusals, not
## nullifications — a refusal can never refuse every hit, because the chip floor runs
## before the refusal AND the removal is capped by `CombatTuning.refusal_cap`.
##
## ## The sign convention
##
## Everything here is NON-NEGATIVE except `health_delta`, which is negative on a
## defender and positive on an attacker. The spine's own arithmetic never negates
## anything; the one place an amount becomes a negative delta is S9's
## `change_resource(&"health", -overflow)`, and `health_delta` is a RECORD of that one
## call rather than a second sign flip waiting to disagree with it.

## S1's base: the authored magnitude after the realm rate gate. Every stage reads
## THIS number, not the mechanism's output, so a mechanism cannot see a pre-gate value.
var base: float = 0.0
## S6's crit multiplier, what `amount` is scaled by on a crit. What the crit multiplies.
var amount: float = 0.0
## S9: what the shield removed. A fully absorbed hit has `absorbed == amount` and
## `overflow == 0.0`, which is exactly why it reflects nothing (ADR 0068).
var absorbed: float = 0.0
## S9: what survived the shield and reached health.
var overflow: float = 0.0
## S9: what the target's health actually lost. Negative on the target, and equal to
## `-overflow` unless the pool had less left than the overflow, in which case the pool
## is the smaller number and the actor died on the floor it was standing on.
var health_delta: float = 0.0
## S10: what the defender's reflect bounced back, post-shield and post-resist.
var reflected: float = 0.0
## S11: the separate leech packet, returned to the attacker after the HP write.
var lifesteal: float = 0.0
## S2: nothing arrived.
var missed: bool = true
## S2: arrived, and was parried.
var parried: bool = false
## S2: arrived, and was blocked.
var blocked: bool = false
## S3: a clean hit that critted.
var crit: bool = false
## S10: the chain ended because `CHAIN_DEPTH_LIMIT` was reached and the bounce was
## DROPPED. The distinction matters: a drop is visible truncation, a clamp to zero
## would be silent rounding (ADR 0068).
var chain_dropped: bool = false

## The mechanism's proposal as it left S5, or null. Exposed deliberately: `effects[]`
## are the path's own state writes applied AFTER health (ADR 0067), and a caller that
## needs them must be able to read them without this class knowing what any of them
## means. Held untyped so `contracts/DamageProposal` is this module's only edge to a
## class another file owns.
var proposal: RefCounted = null


## S4/S5's proposal effects, as the Array of Dictionaries the proposal carried. Duplicated
## so a mechanism mutating its own proposal afterwards cannot rewrite history.
func effects() -> Array:
	return CombatProposalReader.effects_of(proposal)


## S4/S5's proposal amount, or 0.0 when there was no proposal. What the mechanism
## produced, BEFORE S6's crit multiplier and BEFORE S7's amplification.
func proposed_amount() -> float:
	return CombatProposalReader.amount_of(proposal)


## The attack arrived: not missed. A parry or a block is a landed hit.
func is_landed() -> bool:
	return not missed


## The attack arrived untouched: not missed, not parried, not blocked. The predicate
## S3 gates on — a parried or blocked hit NEVER crits (ADR 0068).
func is_clean() -> bool:
	return not missed and not parried and not blocked


## Nothing at all was spent: missed, or a landed hit that a parry and a block between
## them refused in full. The chip floor guarantees a landed hit always spends something,
## so this is only reachable by a refusal, never by an author stacking enough
## `DAMAGE_REDUCTION` (ADR 0067's immunity invariant).
func is_neutral() -> bool:
	return missed or overflow <= 0.0 and health_delta >= 0.0


## Primitives only, so a screen's `summary()` can consume it unchanged (ADR 0038).
##
## The empty miss is `{}` — the screen contract's own "no actor" convention — because a
## miss has nothing to say and a panel that renders `0` for a swing that never landed
## teaches the reader that a whiff and a gut-punch are the same event.
func to_dict() -> Dictionary:
	if missed:
		return {}
	return {
		"base": base,
		"amount": amount,
		"proposed": proposed_amount(),
		"absorbed": absorbed,
		"overflow": overflow,
		"health_delta": health_delta,
		"reflected": reflected,
		"lifesteal": lifesteal,
		"crit": crit,
		"parried": parried,
		"blocked": blocked,
		"landed": is_landed(),
		"clean": is_clean(),
		"neutral": is_neutral(),
		"chain_dropped": chain_dropped,
		"effects": effects(),
	}


## One readout line, for a log or a floating number. No formatting decisions the caller
## would otherwise make twice.
func describe() -> String:
	if missed:
		return "missed"
	var verdict := "crit" if crit else "hit"
	if parried:
		verdict += " parried"
	elif blocked:
		verdict += " blocked"
	return "%s for %s" % [verdict, String.num(amount, 2)]
