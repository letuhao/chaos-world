class_name RelationshipEntry
extends RefCounted

## One partner's relationship row (ADR 0123).
##
## **Compositional, not a second bond.** This reads `SocialBond`'s standing/trust/class
## through the social facade but never writes them. It layers relationship-specific
## state on top: emotional signature, interaction log, DC partner flag, frequent partner
## tier.

const MAX_ROMANTIC_SPOUSE := 5
const MAX_DC_PARTNER := 10

var partner_id: StringName = &""
var relationship_type: StringName = RelationshipType.NONE
var emotional_signature: EmotionalSignature = null
var interaction_log: InteractionLog = null
var is_dual_cultivation_partner: bool = false
var dual_cultivation_history: Array[Dictionary] = []
var total_interactions: int = 0
var frequent_partner_tier: int = 0
var relationship_started_at: float = 0.0
var relationship_ended_at: float = 0.0
var end_reason: StringName = &""


func _init(p_partner_id: StringName = &"", p_type: StringName = RelationshipType.NONE) -> void:
	partner_id = p_partner_id
	relationship_type = p_type
	emotional_signature = EmotionalSignature.new()
	interaction_log = InteractionLog.new()


## True when this relationship is currently active (not ended).
func is_active() -> bool:
	return relationship_ended_at == 0.0


## Mark this relationship as ended. History is preserved — the entry is never deleted.
func mark_ended(reason: StringName, timestamp: float) -> void:
	relationship_ended_at = timestamp
	end_reason = reason
	is_dual_cultivation_partner = false
	# Emotional signature shifts: Sadness +0.2, Anger +0.15, decaying over 7 days.
	emotional_signature.add(&"sadness", 0.2)
	emotional_signature.add(&"anger", 0.15)


## Record an interaction and update the frequent partner tier.
func record_interaction(type: StringName, emotional_delta: Dictionary = {}, timestamp: float = 0.0, dc_session: bool = false) -> void:
	interaction_log.add(type, emotional_delta, timestamp, dc_session)
	for axis in emotional_delta:
		emotional_signature.add(axis, float(emotional_delta[axis]))
	total_interactions += 1
	_update_frequent_partner_tier()
	if dc_session:
		is_dual_cultivation_partner = true


func _update_frequent_partner_tier() -> void:
	if total_interactions >= 50:
		frequent_partner_tier = 3
	elif total_interactions >= 25:
		frequent_partner_tier = 2
	elif total_interactions >= 10:
		frequent_partner_tier = 1
	else:
		frequent_partner_tier = 0


## Record a dual cultivation session in the DC-specific history.
func record_dc_session(technique_id: StringName, essence_transferred: float, harmony_achieved: float, timestamp: float, partner_bond_class: StringName) -> void:
	dual_cultivation_history.append({
		"technique_id": String(technique_id),
		"essence_transferred": essence_transferred,
		"harmony_achieved": harmony_achieved,
		"timestamp": timestamp,
		"partner_bond_class": String(partner_bond_class),
	})
	is_dual_cultivation_partner = true


func to_dict() -> Dictionary:
	return {
		"partner_id": String(partner_id),
		"relationship_type": String(relationship_type),
		"emotional_signature": emotional_signature.to_dict(),
		"interaction_log": interaction_log.to_dict(),
		"is_dual_cultivation_partner": is_dual_cultivation_partner,
		"dual_cultivation_history": dual_cultivation_history,
		"total_interactions": total_interactions,
		"frequent_partner_tier": frequent_partner_tier,
		"relationship_started_at": relationship_started_at,
		"relationship_ended_at": relationship_ended_at,
		"end_reason": String(end_reason),
	}


static func from_dict(data: Dictionary) -> RelationshipEntry:
	var entry := RelationshipEntry.new(
		StringName(data.get("partner_id", &"")),
		StringName(data.get("relationship_type", RelationshipType.NONE))
	)
	entry.emotional_signature = EmotionalSignature.from_dict(data.get("emotional_signature", {}))
	entry.interaction_log = InteractionLog.from_dict(data.get("interaction_log", []))
	entry.is_dual_cultivation_partner = bool(data.get("is_dual_cultivation_partner", false))
	entry.dual_cultivation_history = data.get("dual_cultivation_history", [])
	entry.total_interactions = int(data.get("total_interactions", 0))
	entry.frequent_partner_tier = int(data.get("frequent_partner_tier", 0))
	entry.relationship_started_at = float(data.get("relationship_started_at", 0.0))
	entry.relationship_ended_at = float(data.get("relationship_ended_at", 0.0))
	entry.end_reason = StringName(data.get("end_reason", &""))
	return entry
