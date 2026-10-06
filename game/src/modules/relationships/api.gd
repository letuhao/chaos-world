class_name RelationshipsApi
extends RefCounted

## Public facade for the `relationships` module (ADR 0892). Other modules may reference ONLY
## this file (`api.gd`).
##
## **Compositional, not a second bond.** This module reads `SocialBond`'s standing/trust/class
## through the social facade but never writes them. It layers relationship-specific state
## on top: emotional signature, interaction log, DC partner flag, frequent partner tier.
##
## **A relationship is a log, not a score.** Every interaction is recorded with its emotional
## delta and timestamp. The log is bounded (100 entries per partner, 30-day prune) and the
## aggregate counts are stored separately so eviction never loses them.

const STATE_COMPONENT := RelationshipsProvider.STATE_COMPONENT
const MODULE_KEY := RelationshipState.MODULE_KEY

const _PROVIDER_COMPONENT := &"relationships_provider"

static var _events: RelationshipEvents

static func _get_events() -> RelationshipEvents:
	if _events == null:
		_events = RelationshipEvents.new()
	return _events


static func _persist(state: RelationshipState, actor: Actor) -> void:
	if state == null or actor == null:
		return
	state.mark_changed()
	actor.set_module_data(MODULE_KEY, state.to_dict())


static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var provider := actor.component(_PROVIDER_COMPONENT) as RelationshipsProvider
	if provider == null:
		provider = RelationshipsProvider.new()
		actor.set_component(_PROVIDER_COMPONENT, provider)
		actor.stats.add_provider(provider)
	var state := relationship_state(actor)
	actor.set_component(STATE_COMPONENT, state)
	if not state.changed.is_connected(actor.mark_stats_dirty):
		state.changed.connect(actor.mark_stats_dirty)


static func relationship_state(actor: Actor) -> RelationshipState:
	if actor == null:
		return null
	var state := actor.component(STATE_COMPONENT) as RelationshipState
	if state != null:
		return state
	state = RelationshipState.from_dict(actor.get_module_data(MODULE_KEY))
	actor.set_component(STATE_COMPONENT, state)
	return state


# --- Relationship lifecycle ---

static func start_relationship(actor: Actor, partner_id: StringName, type: StringName) -> Dictionary:
	if actor == null or partner_id == &"" or not RelationshipType.is_valid(type):
		return {"ok": false, "reason": "invalid_args"}
	var state := relationship_state(actor)
	if state == null:
		return {"ok": false, "reason": "no_state"}
	var entry := state.ensure_entry(partner_id, type)
	entry.relationship_type = type
	entry.relationship_started_at = 0.0  # Set by caller with world clock
	entry.relationship_ended_at = 0.0
	entry.end_reason = &""
	_persist(state, actor)
	_get_events().relationship_started.emit(String(actor.id), String(partner_id), type)
	return {"ok": true}


static func end_relationship(actor: Actor, partner_id: StringName, reason: StringName) -> Dictionary:
	if actor == null or partner_id == &"":
		return {"ok": false, "reason": "invalid_args"}
	var state := relationship_state(actor)
	if state == null:
		return {"ok": false, "reason": "no_state"}
	var entry := state.entry(partner_id)
	if entry == null:
		return {"ok": false, "reason": "no_entry"}
	entry.mark_ended(reason, 0.0)  # Set by caller with world clock
	_persist(state, actor)
	_get_events().relationship_ended.emit(String(actor.id), String(partner_id), reason)
	return {"ok": true}


static func relationship_type(actor: Actor, partner_id: StringName) -> StringName:
	var state := relationship_state(actor)
	if state == null:
		return RelationshipType.NONE
	var entry := state.entry(partner_id)
	if entry == null:
		return RelationshipType.NONE
	return entry.relationship_type


# --- Interaction logging ---

static func log_interaction(actor: Actor, partner_id: StringName, interaction_type: StringName, emotional_delta: Dictionary = {}) -> Dictionary:
	if actor == null or partner_id == &"" or interaction_type == &"":
		return {"ok": false, "reason": "invalid_args"}
	var state := relationship_state(actor)
	if state == null:
		return {"ok": false, "reason": "no_state"}
	var entry := state.ensure_entry(partner_id)
	entry.record_interaction(interaction_type, emotional_delta)
	_persist(state, actor)
	_get_events().interaction_logged.emit(String(actor.id), String(partner_id), interaction_type)
	return {"ok": true}


static func interaction_count(actor: Actor, partner_id: StringName) -> int:
	var state := relationship_state(actor)
	if state == null:
		return 0
	var entry := state.entry(partner_id)
	if entry == null:
		return 0
	return entry.total_interactions


# --- Emotional signature ---

static func emotional_signature(actor: Actor, partner_id: StringName) -> Dictionary:
	var state := relationship_state(actor)
	if state == null:
		return {}
	var entry := state.entry(partner_id)
	if entry == null:
		return {}
	return entry.emotional_signature.to_dict()


static func emotional_energy(actor: Actor) -> float:
	var state := relationship_state(actor)
	if state == null:
		return 0.0
	return state.emotional_energy()


# --- Dual cultivation tracking ---

static func mark_dual_cultivation_partner(actor: Actor, partner_id: StringName) -> Dictionary:
	if actor == null or partner_id == &"":
		return {"ok": false, "reason": "invalid_args"}
	var state := relationship_state(actor)
	if state == null:
		return {"ok": false, "reason": "no_state"}
	var entry := state.ensure_entry(partner_id)
	entry.is_dual_cultivation_partner = true
	_persist(state, actor)
	return {"ok": true}


static func is_dual_cultivation_partner(actor: Actor, partner_id: StringName) -> bool:
	var state := relationship_state(actor)
	if state == null:
		return false
	var entry := state.entry(partner_id)
	if entry == null:
		return false
	return entry.is_dual_cultivation_partner


static func dual_cultivation_history(actor: Actor, partner_id: StringName) -> Array:
	var state := relationship_state(actor)
	if state == null:
		return []
	var entry := state.entry(partner_id)
	if entry == null:
		return []
	return entry.dual_cultivation_history


# --- Frequent partner advantages ---

static func frequent_partner_tier(actor: Actor, partner_id: StringName) -> int:
	var state := relationship_state(actor)
	if state == null:
		return 0
	var entry := state.entry(partner_id)
	if entry == null:
		return 0
	return entry.frequent_partner_tier


static func frequent_partner_advantage(actor: Actor, partner_id: StringName) -> Dictionary:
	var tier := frequent_partner_tier(actor, partner_id)
	return FrequentPartner.advantage(tier)


# --- Read model ---

static func summary(actor: Actor) -> Dictionary:
	var state := relationship_state(actor)
	if state == null:
		return {}
	var partners: Array[Dictionary] = []
	for key in state._entries.keys():
		var entry := state._entries[key] as RelationshipEntry
		if entry != null and entry.is_active():
			partners.append({
				"partner_id": String(entry.partner_id),
				"relationship_type": String(entry.relationship_type),
				"frequent_partner_tier": entry.frequent_partner_tier,
				"is_dual_cultivation_partner": entry.is_dual_cultivation_partner,
				"total_interactions": entry.total_interactions,
			})
	return {
		"partner_count": partners.size(),
		"partners": partners,
		"emotional_energy": state.emotional_energy(),
		"active_romantic_count": state.active_romantic_count(),
		"active_dc_partner_count": state.active_dc_partner_count(),
		"highest_tier": state.highest_tier(),
	}


static func tick(actor: Actor, delta: float) -> int:
	var state := relationship_state(actor)
	if state == null:
		return 0
	var pruned := 0
	for key in state._entries.keys():
		var entry := state._entries[key] as RelationshipEntry
		if entry != null and entry.interaction_log != null:
			pruned += entry.interaction_log.prune(0.0)  # Prune with current world clock
	if pruned > 0:
		_persist(state, actor)
	return pruned
