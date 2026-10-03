class_name LocationResolver
extends RefCounted

## The BODY path's location axis, as a contract (ADR 0067, ADR 0070).
##
## ## Why this is in `contracts/` at all
##
## Granularity is the MERIDIAN — 20 of them, not 60 acupoints — and `actor.meridians`
## already exists on every actor for all three paths. So the question the spine and
## the body mechanism must both be able to ask is "does this target have a location
## axis?", and it must be askable WITHOUT the body module in the frame. That is what a
## contract is for: it lives in the layer that may depend on nothing, so anything may
## name it and nothing has to own it.
##
## ## What this file deliberately does NOT contain
##
## The body mechanism's arithmetic — `gross * penetration * point_multiplier *
## channel_multiplier * (1 - DAMAGE_REDUCTION)` — belongs in
## `modules/combat/body_damage.gd` (wave D). This file is the SHAPE of the answer and
## nothing else. A contract that grew the arithmetic would be a second, divergent copy
## of the rule ADR 0070 owns, and a place for the two to disagree.
##
## ## Why `supports()` is not a null check
##
## `Actor.component()` returns `RefCounted`, so a mechanism cannot ask "is there a
## resolver" by casting: `as LocationResolver` on null is silent. `supports(actor)` is
## the honest question and returns a bool. An actor with no location axis — an NPC, a
## training dummy, a qi-only fighter — answers false and the body mechanism falls back
## to its ungated form. Nothing here names `Actor`; `contracts/` may not.

## The component id this contract is bound under on an actor. One string, owned here,
## so a resolver and its binder cannot spell it two ways.
const COMPONENT_ID := &"location_resolver"


## Whether `actor` has a location axis at all. An actor that answers false has no
## meridian network this path can aim at, and the caller must treat its strike as
## ungated rather than as hitting a point that does not exist.
func supports(_actor: Variant) -> bool:
	return false


## Which location this attack lands on, and at what multiplier.
##
## Deliberately returns a PRIMITIVES-ONLY dictionary rather than a typed location
## object: `contracts/` may not name `MeridianState`, `Acupoint` or anything else in
## `core/`, and a typed return would be an arch violation. The three keys below are
## therefore the whole vocabulary, and adding a fourth is an ADR:
##
## ```
## meridian_id     -> StringName   which meridian (a body_target.id)
## point_id        -> StringName   which acupoint within it
## multiplier      -> float        the combined point * channel multiplier
## ```
##
## `rng` may be null and the resolver MUST then derive its choice from STATE rather
## than rolling: the `random` aim mode is defined as "the highest
## `point_multiplier`", which is state-derived, deterministic and readable to the
## player (ADR 0070). `mode` is the authored aim mode — `named`, `random` or `broad`.
func resolve_location(
	_attacker: Variant, _target: Variant, _technique: Variant, _rng: RandomNumberGenerator = null
) -> Dictionary:
	return {"meridian_id": &"", "point_id": &"", "multiplier": 1.0}


## Apply one wound to `meridian_id`, at `severity`. Wounds accumulate per meridian and
## are the BODY path's own state write, so they travel back as a
## `DamageProposal` effect of kind `wound` rather than as a return value here.
##
## Deliberately returns nothing. A wound is a state write on the defender, and the
## spine applies `effects` AFTER health (ADR 0067) — so a resolver that applied it
## here would make the wound land BEFORE the health it was earned by, which is the
## one ordering the whole effects-after-health rule exists to prevent. The caller
## turns this into an effect entry; the arithmetic is the body module's.
func apply_wound(_target: Variant, _meridian_id: StringName, _severity: float) -> void:
	pass
