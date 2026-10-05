extends TestCase

## The brief's load-bearing claim is that an npc and the player are NOT DIFFERENT, and
## that their social state lives "in an extended feature of the actor base". Both are
## easy to assert in prose and easy to get wrong in code, so these assert the TYPE and
## the LOCATION rather than the behaviour.
##
## Specifically: `SocialState` must hang off `actor.components`, the roster off the
## player's `module_data`, and the provider must be registered on `actor.stats` — so a
## new actor assembled by any path picks all three up. A parallel `PlayerSocial` table or
## an `NpcActor` subclass would fail every one of these.

const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"


func setup() -> void:
	NpcRegistry.instance().reset()
	SocialCauseCatalog.instance().install_defaults()


func teardown() -> void:
	NpcRegistry.instance().reset()


func _cast() -> void:
	var catalog := NpcCatalog.instance()
	catalog.reset()
	catalog.install([load("res://data/npc/cast/elder_wei.tres") as NpcDef])
	catalog.install([load("res://data/npc/cast/smith_bearcutter.tres") as NpcDef])


# --- There is one social type, and it is reachable from any actor --------------


func test_the_social_ledger_is_a_single_type_not_a_player_one_and_an_npc_one() -> void:
	var player := Actor.new(&"hero")
	var smith := Actor.new(&"smith")
	SocialApi.attach(player)
	SocialApi.attach(smith)
	assert_eq(
		typeof(SocialApi.social_state(player)),
		typeof(SocialApi.social_state(smith)),
		"both actors hold the same type"
	)
	assert_eq(SocialApi.social_state(player) is SocialState, true, "and it is the ledger")


func test_the_ledger_hangs_off_the_actor_base_component_slot() -> void:
	var player := Actor.new(&"hero")
	SocialApi.attach(player)
	# Read it back off the ACTOR, with no reference to the api object in scope. This is
	# what "stored in the actor base" means mechanically: a save, a clone or a
	# `to_dict` round trip carries it because it was never anywhere else.
	assert_ne(player.component(&"social_state"), null, "the ledger is a component of the actor")
	assert_eq(player.component(&"social_state") is SocialState, true, "and is the social type")


func test_the_provider_is_registered_on_the_actor_s_own_stat_stack() -> void:
	var player := Actor.new(&"hero")
	var before := player.stats.provider_count()
	SocialApi.attach(player)
	assert_eq(
		player.stats.provider_count(), before + 1, "the social provider joined the actor's stats"
	)
	SocialApi.attach(player)
	assert_eq(player.stats.provider_count(), before + 1, "and re-attaching never doubles it")


func test_a_bond_mutated_through_one_reference_is_visible_through_the_actor() -> void:
	var player := Actor.new(&"hero")
	SocialApi.attach(player)
	SocialApi.apply_cause(player, ELDER, &"shared_brotherhood")
	# No api call: straight off the component, proving it is the same live object and not
	# a copy the facade kept to itself.
	var ledger := player.component(&"social_state") as SocialState
	assert_ne(ledger, null, "the ledger is on the actor")
	assert_ne(ledger.bond(ELDER), null, "and the bond the facade wrote is visible from it")


# --- An npc is the same type as the player, not a lookalike --------------------


func test_a_spawned_npc_and_the_player_are_the_same_gdscript_type() -> void:
	_cast()
	var player := Actor.new(&"hero")
	SocialApi.attach(player)
	NpcApi.set_minter(
		func(def: NpcDef, role: StringName = &"npc") -> Actor:
			var npc := Actor.new(&"npc")
			SocialApi.attach(npc)
			npc.tags.append(role)
			return npc
	)
	NpcApi.attach(player)
	var npc := NpcApi.spawn(ELDER)
	assert_ne(npc, null, "an npc was minted")
	assert_eq(npc.get_script() == player.get_script(), true, "and it is literally the same class")
	assert_eq(npc is Actor, true, "not a subclass, not a wrapper")


func test_an_npc_and_the_player_answer_the_same_social_question_identically() -> void:
	_cast()
	var player := Actor.new(&"hero")
	var smith := Actor.new(&"smith")
	SocialApi.attach(player)
	SocialApi.attach(smith)
	var cause := SocialCauseDef.new()
	cause.id = &"a_gift"
	cause.standing = 4.0
	SocialCauseCatalog.instance().reset()
	SocialCauseCatalog.instance().install([cause])
	SocialApi.apply_cause(player, ELDER, &"a_gift")
	SocialApi.apply_cause(smith, ELDER, &"a_gift")
	assert_eq(
		SocialApi.bond_entry(player, ELDER)["bond"],
		SocialApi.bond_entry(smith, ELDER)["bond"],
		"the same act produces the same class on both sides of the table"
	)


func test_there_is_no_npc_actor_subclass_anywhere_in_the_module() -> void:
	# Structural, not behavioural: ADR 0074 forbids a per-tier type, and a class that
	# existed would have to be named here. The role lives on `tags` and nowhere else.
	_cast()
	NpcApi.set_minter(
		func(def: NpcDef, role: StringName = &"npc") -> Actor:
			var npc := Actor.new(&"npc")
			npc.tags.append(role)
			return npc
	)
	var player := Actor.new(&"hero")
	NpcApi.attach(player)
	for role in [&"mob", &"miniboss", &"boss", &"npc", &"rival_cultivator"]:
		var npc := NpcApi.spawn(SMITH, role)
		assert_eq(npc.get_script() == player.get_script(), true, "%s is the same class" % role)
		assert_eq(npc.tags.has(role), true, "%s is a tag" % role)


# --- The roster is on the player actor too, not in a side file -----------------


func test_the_roster_also_hangs_off_the_player_actor() -> void:
	_cast()
	var player := Actor.new(&"hero")
	SocialApi.attach(player)
	NpcApi.set_minter(
		func(def: NpcDef, role: StringName = &"npc") -> Actor:
			var npc := Actor.new(&"npc")
			npc.tags.append(role)
			return npc
	)
	NpcApi.attach(player)
	NpcApi.spawn(ELDER)
	# Read the roster off the actor, not through the facade.
	assert_eq(player.module_data.has(&"npc_state"), true, "the roster is module_data on the player")
	assert_ne(player.component(&"npc_state"), null, "and is live on the player as a component")


func test_both_ledgers_survive_a_save_together_with_no_core_schema_bump() -> void:
	_cast()
	var player := Actor.new(&"hero")
	SocialApi.attach(player)
	NpcApi.set_minter(
		func(def: NpcDef, role: StringName = &"npc") -> Actor:
			var npc := Actor.new(&"npc")
			npc.tags.append(role)
			return npc
	)
	NpcApi.attach(player)
	NpcApi.spawn(ELDER)
	SocialApi.apply_cause(player, ELDER, &"shared_brotherhood")
	SocialApi.state(player)
	NpcApi.state(player)
	var payload := player.to_dict()
	assert_eq(int(payload["version"]), Actor.SCHEMA_VERSION, "core's schema never moved")
	var restored := Actor.from_dict(payload)
	SocialApi.attach(restored)
	NpcApi.attach(restored)
	# `state()` publishes `tracked_ids` as Strings; the live ledger holds StringNames.
	# Assert against the ledger itself rather than guessing which one a round trip keeps.
	assert_eq(
		NpcApi.state(restored)["tracked_ids"].size(),
		1,
		"the roster came back through the ordinary actor payload"
	)
	assert_eq(
		String((NpcApi.state(restored)["tracked_ids"] as Array)[0]),
		String(ELDER),
		"and it is the elder"
	)
	assert_ne(
		SocialApi.social_state(restored).bond(ELDER),
		null,
		"and so did the relationship, from the same save"
	)
