class_name RelationshipEvents
extends RefCounted

## Typed event contract for the `relationships` module (ADR 0123). The observation half
## of the seam: a consumer subscribes to these without the relationships module naming it.
##
## **Every signal here announces what already happened.** None is a request and none may
## be vetoed. Shaped like `npc_events.gd` and `destiny_events.gd`: primitives only, one
## fact per signal.

## A relationship started between `actor_id` and `partner_id`. `type` is one of
## FRIEND, ROMANTIC, SPOUSE, DC_PARTNER.
signal relationship_started(actor_id: String, partner_id: String, type: StringName)

## A relationship ended between `actor_id` and `partner_id`. `reason` names why.
signal relationship_ended(actor_id: String, partner_id: String, reason: StringName)

## An interaction was logged between `actor_id` and `partner_id`.
signal interaction_logged(actor_id: String, partner_id: String, interaction_type: StringName)

## A frequent partner tier was reached between `actor_id` and `partner_id`.
signal frequent_partner_reached(actor_id: String, partner_id: String, tier: int)
