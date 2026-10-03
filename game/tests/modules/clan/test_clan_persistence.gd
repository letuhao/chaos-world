extends TestCase

## The ledger is a versioned plain dictionary under `actor.module_data`, so core
## persists it without ever naming a clan (ADR 0027). These assert the payload round
## trips through `Actor.to_dict`/`from_dict` and a JSON hop, that a save written before
## the module existed loads clean as empty, and that attaching to a restored actor
## re-derives the live projection from the ledger rather than trusting the payload.

const MODULE_KEY := ClanState.MODULE_KEY
const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"


func setup() -> void:
	(
		ClanFixtureCatalog
		. install(
			[
				ClanFixtureCatalog.open(HOUSE),
				ClanFixtureCatalog.sealed(RIVAL, 0.9),
			]
		)
	)


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _member(actor_id: StringName = &"member", standing: int = 0) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, 0.5)
	ClanApi.join(actor, HOUSE, standing)
	return actor


func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"clan": String(ClanApi.clan_of(actor)),
		"rank": String(ClanApi.rank_of(actor)),
		"standing": ClanApi.standing_of(actor),
		"traits": actor.traits.to_array(),
		"own_sources": _own_sources(actor),
		"base": actor.stats.base_dict(),
		"standing_stat": actor.stats.derived(ClanStats.STANDING),
	}


func _own_sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		if ClanState.is_own_source(modifier.source):
			out.append(String(modifier.source))
	out.sort()
	return out


# --- The payload -------------------------------------------------------------


func test_the_ledger_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _member(&"child", 30)
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), ClanState.SCHEMA_VERSION, "versioned")
	assert_eq(String(stored["clan"]), String(HOUSE), "the clan is recorded")
	assert_eq(String(stored["rank"]), "outer", "the entry position is recorded alongside it")
	assert_eq(int(stored["standing"]), 30, "and so is the earned standing")
	assert_eq(
		(ClanState.applied(stored) as Dictionary).get("clan"),
		String(HOUSE),
		"the applied record says what was projected, so a strip can reverse it"
	)
	assert_eq(ClanApi.state(actor), stored, "the facade reports the persisted payload")


func test_a_membership_survives_a_payload_round_trip_and_a_json_hop() -> void:
	var actor := _member(&"child", 42)
	var before: Dictionary = ClanApi.state(actor)
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	assert_eq(
		restored.get_module_data(MODULE_KEY), before, "the payload carried the ledger verbatim"
	)
	assert_eq(String(ClanApi.clan_of(restored)), String(HOUSE), "the clan is still the actor's")
	assert_eq(ClanApi.standing_of(restored), 42, "and the standing survived the hop")
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(ClanApi.state(from_json), before, "JSON round trip")
	assert_eq(String(ClanApi.rank_of(from_json)), "outer", "and the position too")


func test_a_restored_actor_re_derives_the_projection_from_the_ledger() -> void:
	var actor := _member(&"child", 11)
	var before := _fingerprint(actor)
	var restored := Actor.from_dict(actor.to_dict())
	# Trait mirrors DO come back in the payload because core serializes `traits`, but
	# the summary component does not. Attaching must therefore be careful: re-adding a
	# mirror that survived is harmless because `traits` is a set, and the ledger's
	# applied record is what keeps the strip exact for content the catalog has dropped.
	ClanApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "the same ledger, mirrors and totals")
	ClanApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "and re-attaching never doubles a mirror")


func test_a_legacy_payload_with_no_clan_state_loads_cleanly_as_the_empty_ledger() -> void:
	var actor := _member(&"child", 5)
	var legacy: Dictionary = actor.to_dict()
	legacy["module_data"] = {}
	var restored := Actor.from_dict(legacy)
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no ledger")
	ClanApi.attach(restored)
	var state := ClanApi.state(restored)
	assert_eq(int(state["version"]), ClanState.SCHEMA_VERSION, "still versioned")
	assert_eq(String(state["clan"]), "", "and empty, not partial")
	assert_eq(String(ClanApi.clan_of(restored)), "", "nothing is joined")
	assert_eq(String(ClanApi.rank_of(restored)), "", "and no position is held")


func test_normalize_drops_an_entry_naming_content_the_catalog_no_longer_ships() -> void:
	var payload := {
		"version": 1,
		"clan": String(HOUSE),
		"rank": "inner",
		"standing": 44,
		"applied": {"clan": String(HOUSE), "rank": "inner"},
	}
	var normalized := ClanState.normalize(payload, {String(RIVAL): true})
	assert_eq(String(normalized["clan"]), "", "the retired clan is dropped")
	assert_eq(String(normalized["rank"]), "", "and with it the position it granted")
	assert_eq(int(normalized["standing"]), 0, "and the standing, which was earned there")
	# `applied` is deliberately NOT filtered: those mirrors are still on the actor and
	# have to be taken back, which is exactly when it matters.
	assert_eq(
		(ClanState.applied(normalized) as Dictionary).get("clan"),
		String(HOUSE),
		"but the applied record survives"
	)


func test_a_live_record_is_kept_whole_while_the_definition_ships() -> void:
	var actor := _member(&"child", 8)
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	# Re-reading a live payload through the catalog filter must be lossless while the
	# definition ships, or a save round trip would quietly strip the applied record the
	# projection needs in order to reverse itself.
	assert_eq(ClanState.normalize(stored, {String(HOUSE): true}), stored, "kept whole")


func test_an_unreadable_ledger_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	for payload in [
		{"version": 1, "clan": 42},
		{"version": 1, "applied": "not a dictionary"},
		{"version": 1, "applied": {}},
		{"version": 1, "applied": {"clan": ""}},
		{"version": 1, "clan": String(HOUSE), "standing": "many"},
		{"version": 1, "clan": String(HOUSE), "rank": 17},
	]:
		var restored := Actor.new(&"corrupt", {Stat.PHYSIQUE: 10.0})
		restored.set_module_data(MODULE_KEY, payload)
		ClanApi.attach(restored)
		var state := ClanApi.state(restored)
		assert_eq(
			ClanState.is_member(state) and int(state["standing"]) > 0,
			false,
			"rejected payload %s" % [payload]
		)
		assert_eq(String(state["rank"]), "", "including any position the payload named")


func test_a_fresh_actor_belongs_to_no_clan_and_claims_nothing() -> void:
	var actor := Actor.new(&"nobody")
	ClanApi.attach(actor)
	assert_eq(String(ClanApi.clan_of(actor)), "", "no clan is invented at attach")
	assert_eq(ClanApi.standing_of(actor), 0, "and no standing is minted")
	assert_eq(String(ClanApi.rank_of(actor)), "", "and no position")
	assert_eq(actor.traits.to_array().size(), 0, "and no mirror is projected")
	assert_eq(ClanApi.state(null), ClanState.empty(), "a null actor reads as the empty ledger")


func test_source_trait_and_rank_ids_are_namespaced_so_a_rebuild_can_find_them() -> void:
	assert_eq(String(ClanState.source_for(HOUSE)), "clan:t_house", "the modifier source")
	assert_eq(String(ClanState.trait_for(HOUSE)), "clan:t_house", "the clan mirror id")
	assert_eq(String(ClanState.rank_trait_for(&"core")), "clan_rank:core", "the rank mirror")
	assert_eq(ClanState.is_own_source(ClanState.source_for(HOUSE)), true, "recognised as ours")
	assert_eq(ClanState.is_own_source(&"sect:tower"), false, "and a sibling's is not")


func test_leaving_returns_the_actor_to_the_empty_ledger_and_drops_the_mirrors() -> void:
	var actor := _member(&"child", 70)
	assert_eq(ClanApi.leave(actor), true, "left")
	assert_eq(ClanApi.state(actor), ClanState.empty(), "the ledger is empty, not partial")
	assert_eq(actor.traits.has(ClanState.trait_for(HOUSE)), false, "the clan mirror is gone")
	assert_eq(actor.traits.has(ClanState.rank_trait_for(&"outer")), false, "and the rank mirror")
	assert_eq(ClanApi.leave(actor), false, "leaving twice is refused, not re-applied")


func test_leaving_an_actor_who_belongs_to_no_clan_is_refused_and_changes_nothing() -> void:
	var actor := Actor.new(&"nobody")
	ClanApi.attach(actor)
	assert_eq(ClanApi.leave(actor), false, "refused")
	assert_eq(ClanApi.state(actor), ClanState.empty(), "and nothing moved")
	assert_eq(ClanApi.leave(null), false, "a null actor is refused too")
