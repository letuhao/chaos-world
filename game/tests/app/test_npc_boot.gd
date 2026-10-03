extends TestCase

## The composition root's wiring is the difference between a feature and a facade
## nobody can call (ADR 0074, ADR 0092). These assert the three injection points —
## constructor, roster, clock — actually close, using the AUTHORED `.tres` cast rather
## than a fixture, so a typo in shipped content fails here instead of in a room.

const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"
const DRIFTER := &"drifter"
const GATE_KEEPER := &"gate_keeper_bo"

const CAST_DIR := "res://data/npc/cast/"


func setup() -> void:
	NpcRegistry.instance().reset()
	SocialCauseCatalog.instance().install_defaults()


func teardown() -> void:
	NpcRegistry.instance().reset()


func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 12.0, Stat.WILL: 8.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	return actor


func _load_cast() -> void:
	var catalog := NpcCatalog.instance()
	catalog.reset()
	for file_name in [
		"elder_wei.tres", "smith_bearcutter.tres", "drifter.tres", "gate_keeper_bo.tres"
	]:
		var def := load(CAST_DIR + file_name) as NpcDef
		if def != null:
			catalog.install([def])


# --- The shipped cast loads ----------------------------------------------------


func test_every_authored_cast_member_loads_as_an_npc_def() -> void:
	_load_cast()
	for npc_id in [ELDER, SMITH, DRIFTER, GATE_KEEPER]:
		var def := NpcCatalog.instance().definition(npc_id)
		assert_ne(def, null, "%s loads" % String(npc_id))
		assert_eq(def.display_name != "", true, "%s is named, not blank" % String(npc_id))
		assert_eq(def.realm_id != &"", true, "%s cultivates" % String(npc_id))


func test_the_shipped_cast_covers_both_tracked_and_untracked_tiers() -> void:
	_load_cast()
	assert_eq(NpcCatalog.instance().definition(ELDER).tracked(), true, "the elder is remembered")
	assert_eq(NpcCatalog.instance().definition(SMITH).tracked(), true, "so is the smith")
	assert_eq(NpcCatalog.instance().definition(DRIFTER).tracked(), false, "the drifter is not")
	assert_eq(NpcCatalog.instance().definition(GATE_KEEPER).tracked(), false, "nor the gatekeeper")


func test_the_elder_ships_a_three_stage_ladder_ending_in_a_terminal_stage() -> void:
	_load_cast()
	var elder := NpcCatalog.instance().definition(ELDER)
	assert_eq(elder.stage_count(), 3, "gatekeeper, sworn, retired")
	assert_eq(elder.starting_stage_id(), &"gatekeeper", "and he starts at the first rung")
	assert_eq(elder.next_stage_id(&"gatekeeper"), &"sworn_servant", "one step forward")
	assert_eq(elder.next_stage_id(&"sworn_servant"), &"retired", "then the last")
	assert_eq(elder.next_stage_id(&"retired"), &"", "and the ladder ends")
	assert_eq(elder.stage(&"retired").terminal, true, "the last stage is terminal")


func test_a_stage_ids_tag_mirror_is_readable_without_importing_the_module() -> void:
	_load_cast()
	assert_eq(
		String(NpcCatalog.instance().definition(SMITH).stage(&"trusted_smith").tag_id()),
		"npc_stage:trusted_smith",
		"content can key a gate off the stage without naming the module"
	)


# --- The composition root closes the inversion ---------------------------------


func test_boot_installs_the_constructor_so_spawn_stops_returning_null() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.install(player)
	var actor := NpcApi.spawn(SMITH)
	assert_ne(actor, null, "spawn works once the root injected a constructor")
	assert_eq(actor is Actor, true, "and what comes out is the shared Actor type")
	assert_eq(actor.display_name, "Smith Bearcutter", "named from the authored def")


func test_boot_binds_the_roster_to_the_player_it_was_given() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.install(player)
	NpcApi.spawn(ELDER)
	assert_eq(
		NpcApi.state(player)["tracked_ids"], ["elder_wei"], "the elder is on the player's roster"
	)


func test_boot_is_idempotent_so_a_load_can_re_install_it() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.install(player)
	NpcApi.spawn(SMITH)
	NpcBoot.install(player)
	NpcBoot.install(player)
	assert_eq(
		NpcApi.state(player)["tracked_ids"],
		["smith_bearcutter"],
		"re-installing never duplicates or drops a roster entry"
	)


func test_boot_on_a_null_actor_is_a_no_op_rather_than_a_crash() -> void:
	NpcBoot.install(null)


# --- The clock is the one already in app/ --------------------------------------


func test_the_composition_root_clock_drives_bond_decay() -> void:
	_load_cast()
	var player := _player()
	var cause := SocialCauseDef.new()
	cause.id = &"a_gift"
	cause.standing = 5.0
	SocialCauseCatalog.instance().reset()
	SocialCauseCatalog.instance().install([cause])
	SocialApi.apply_cause(player, ELDER, &"a_gift")
	# One month on the composition root's single clock moves the bond exactly one point.
	# This asserts the ROOT's tick verb, which is the seam `StatusLoop` also calls; it does
	# not route through `StatusApi`, so it stays a test of this feature's wiring rather
	# than of the status module's runtime store.
	var decayed := NpcBoot.tick(player, 24.0 * 60.0 * 60.0 * 30.0)
	assert_eq(decayed, 1, "one bond was tracked and moved")
	assert_almost_eq(
		SocialApi.social_state(player).bond(ELDER).standing,
		4.0,
		"the composition root's clock ages a relationship",
		0.001
	)


func test_the_composition_root_clock_is_a_no_op_without_an_actor_or_a_delta() -> void:
	assert_eq(NpcBoot.tick(null, 1.0), 0, "no actor, no tick")
	assert_eq(NpcBoot.tick(_player(), 0.0), 0, "and no elapsed time means no drift")


# --- The seam future features and the app itself will use ----------------------


func test_the_player_carries_social_state_so_a_bond_can_be_earned_toward_him() -> void:
	_load_cast()
	var player := _player()
	# One cause is still not enough: the anti-farm rule caps the positive ladder at an
	# acquaintance however generous the act was (ADR 0091). The player is subject to
	# exactly the same rule as an npc, which is the point of the symmetry.
	SocialApi.apply_cause(player, ELDER, &"shared_brotherhood")
	assert_eq(
		SocialApi.bond_entry(player, ELDER)["bond"],
		SocialBondClass.ACQUAINTANCE,
		"a single sworn act does not buy a friendship for anyone"
	)
	SocialApi.apply_cause(player, ELDER, &"taught_technique")
	assert_eq(
		SocialApi.bond_entry(player, ELDER)["bond"],
		SocialBondClass.FRIEND,
		"and the second distinct reason does"
	)


func test_an_institution_gate_reads_the_ledger_and_names_its_reason() -> void:
	_load_cast()
	var player := _player()
	var locked := SocialApi.gate(
		player, {"verb": &"bond_at_least", "partner": SMITH, "at_least": SocialBondClass.FRIEND}
	)
	assert_eq(locked["ok"], false, "a stranger cannot open the smith's forge tier")
	assert_eq(locked["unmet"].size(), 1, "with a reason a panel can render")
	SocialApi.apply_cause(player, SMITH, &"shared_brotherhood")
	SocialApi.apply_cause(player, SMITH, &"honoured_a_debt")
	assert_eq(
		(
			SocialApi
			. gate(
				player,
				{"verb": &"bond_at_least", "partner": SMITH, "at_least": SocialBondClass.FRIEND}
			)["ok"]
		),
		true,
		"earned, so open"
	)


func test_a_saved_and_restored_actor_keeps_both_ledgers() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.install(player)
	NpcApi.spawn(SMITH)
	SocialApi.apply_cause(player, SMITH, &"gifted_item")
	SocialApi.state(player)
	NpcApi.state(player)
	var restored := Actor.from_dict(player.to_dict())
	assert_eq(NpcApi.state(restored)["tracked_ids"], ["smith_bearcutter"], "the roster came back")
	SocialApi.attach(restored)
	assert_eq(
		SocialApi.social_state(restored).bond(SMITH).bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"and so did the relationship, with no core schema bump either"
	)


# --- A room loads its authored population --------------------------------------


func test_populating_a_room_returns_who_is_standing_there() -> void:
	_load_cast()
	var player := _player()
	var result := NpcBoot.populate_room(
		player, [&"drifter", &"drifter", &"gate_keeper_bo"], NpcApi.ROLE_NPC, &"mortal_plains"
	)
	assert_eq(result["spawned"], 3, "three bodies stood up")
	assert_eq(NpcRegistry.instance().present_count(), 3, "and the live table agrees")
	assert_eq(NpcApi.state(player)["tracked_ids"], [], "none of them is remembered")


func test_a_room_reload_replaces_the_cast_rather_than_stacking_it() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.populate_room(player, [&"drifter", &"drifter"])
	NpcBoot.populate_room(player, [&"drifter"])
	assert_eq(NpcRegistry.instance().present_count(), 1, "yesterday's drifters left the room")


func test_a_tracked_cast_member_can_be_stocked_into_a_room_and_is_remembered() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.populate_room(player, [&"elder_wei", &"drifter"])
	assert_eq(
		NpcApi.state(player)["tracked_ids"],
		["elder_wei"],
		"the drifter left nothing, the elder is on the roster"
	)
	assert_eq(NpcApi.summary(ELDER)["presence"], "Present", "and he is standing here")


func test_the_whole_read_model_is_primitives_for_one_panel() -> void:
	_load_cast()
	var player := _player()
	NpcBoot.populate_room(player, [&"elder_wei", &"drifter"])
	var model := NpcBoot.read_model(player)
	assert_eq(model["has_actor"], true, "names the actor")
	assert_eq(model["roster"]["tracked_ids"], ["elder_wei"], "the roster is a list")
	assert_eq(model["here"]["count"], 2, "and the room holds both")
	assert_eq(model["bond_with"]["actor_id"], "hero", "with the player's own social ledger")
