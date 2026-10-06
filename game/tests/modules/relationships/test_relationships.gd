extends TestCase

## Tests for the relationships module (ADR 0123).
##
## Relationships is a standalone module that tracks dual cultivation history and
## relationships as a log. Frequent partners increase relationship and can take advantages.


func test_start_relationship() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	var result := RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.FRIEND)
	assert_eq(result.get("ok", false), true, "start_relationship ok")
	assert_eq(RelationshipsApi.relationship_type(actor, &"npc_1"), RelationshipType.FRIEND, "relationship type is FRIEND")


func test_end_relationship() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.ROMANTIC)
	var result := RelationshipsApi.end_relationship(actor, &"npc_1", &"betrayal")
	assert_eq(result.get("ok", false), true, "end_relationship ok")
	assert_eq(RelationshipsApi.relationship_type(actor, &"npc_1"), RelationshipType.ROMANTIC, "type preserved after end")



func test_log_interaction() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.FRIEND)
	var result := RelationshipsApi.log_interaction(actor, &"npc_1", &"gift", {"joy": 0.1})
	assert_eq(result.get("ok", false), true, "log_interaction ok")
	assert_eq(RelationshipsApi.interaction_count(actor, &"npc_1"), 1, "interaction count is 1")



func test_frequent_partner_tier() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.FRIEND)
	for i in range(15):
		RelationshipsApi.log_interaction(actor, &"npc_1", &"gift")
	assert_eq(RelationshipsApi.frequent_partner_tier(actor, &"npc_1"), 1, "tier 1 at 15 interactions")



func test_frequent_partner_advantage() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.FRIEND)
	for i in range(30):
		RelationshipsApi.log_interaction(actor, &"npc_1", &"gift")
	var advantage := RelationshipsApi.frequent_partner_advantage(actor, &"npc_1")
	assert_almost_eq(float(advantage.get("emotional_energy", 1.0)), 1.20, "tier 2 energy bonus", 0.001)
	assert_almost_eq(float(advantage.get("dc_efficiency", 1.0)), 1.10, "tier 2 dc bonus", 0.001)



func test_dual_cultivation_partner() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.DC_PARTNER)
	var result := RelationshipsApi.mark_dual_cultivation_partner(actor, &"npc_1")
	assert_eq(result.get("ok", false), true, "mark_dc_partner ok")
	assert_eq(RelationshipsApi.is_dual_cultivation_partner(actor, &"npc_1"), true, "is dc partner")



func test_emotional_signature() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.FRIEND)
	RelationshipsApi.log_interaction(actor, &"npc_1", &"gift", {"joy": 0.15})
	var sig := RelationshipsApi.emotional_signature(actor, &"npc_1")
	assert_almost_eq(float(sig.get("joy", 0.0)), 0.45, "joy raised by gift", 0.001)



func test_summary() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	RelationshipsApi.start_relationship(actor, &"npc_1", RelationshipType.FRIEND)
	RelationshipsApi.start_relationship(actor, &"npc_2", RelationshipType.ROMANTIC)
	var summary := RelationshipsApi.summary(actor)
	assert_eq(int(summary.get("partner_count", 0)), 2, "two partners in summary")



func test_invalid_args_refused() -> void:
	var actor := Actor.new()
	RelationshipsApi.attach(actor)
	var result := RelationshipsApi.start_relationship(actor, &"", RelationshipType.FRIEND)
	assert_eq(result.get("ok", false), false, "empty partner_id refused")

