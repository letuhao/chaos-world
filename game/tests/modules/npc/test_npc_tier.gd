extends TestCase

## The tier system answers exactly one question: is this individual remembered? These
## assert that a tracked npc keeps a roster entry and a stage, an untracked one leaves
## nothing behind, and that every role comes out of the constructor as the same `Actor`
## the player is (ADR 0074, ADR 0077).

const SMITH := &"smith_bearcutter"
const ELDER := &"elder_wei"
const DRIFTER := &"drifter"
const GATE_KEEPER := &"gate_keeper_bo"


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()
	var elder_first := _stage(&"elder", "Elder", 0)
	var elder_taught := _stage(&"elder_taught", "Taught", 1)
	elder_taught.terminal = true
	var smith_new := _stage(&"smith_new", "New acquaintance", 0)
	# The threshold lives on the stage you are LEAVING, not the one you reach: two favours
	# earn you the next stage, so `smith_new` is what counts them.
	smith_new.advance_after = 2
	var smith_friend := _stage(&"smith_friend", "Friend", 1)
	var cast: Array[NpcDef] = [
		_def(ELDER, "Elder Wei", NpcTier.STORY, [elder_first, elder_taught]),
		_def(SMITH, "Smith Bearcutter", NpcTier.MAJOR, [smith_new, smith_friend]),
		_def(DRIFTER, "A Drifter", NpcTier.TRANSIENT, []),
		_def(GATE_KEEPER, "Gatekeeper Bo", NpcTier.MINOR, []),
	]
	NpcCatalog.instance().reset()
	NpcCatalog.instance().install(cast)
	NpcRegistry.instance().reset()
	# A lambda rather than a class reference: every verb on the factory is static, and
	# binding a static through a class object is not a Callable in Godot 4. The point of
	# `set_minter` is that `npc/` names no concrete type, and a lambda proves it.
	NpcApi.set_minter(_mint)
	NpcApi.attach(_player())


## The injected constructor. Stands in for `ActorFactory.spawn_npc`, which the composition
## root wires at boot. Building the actor inline keeps this suite independent of whatever
## else `app/` happens to attach, and it demonstrates the point of `set_minter`: the npc
## module cannot name a concrete constructor, so a test can supply one.
func _mint(def: NpcDef, role: StringName = NpcApi.ROLE_NPC) -> Actor:
	var actor := Actor.new(StringName("npc_%s" % String(def.npc_id)), def.base)
	actor.attach_core_resources()
	SocialApi.attach(actor)
	actor.tags.append(role)
	actor.display_name = def.display_name
	actor.faction = def.faction
	return actor


func teardown() -> void:
	NpcRegistry.instance().reset()


func _player() -> Actor:
	return Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})


func _stage(stage_id: StringName, label: String, index: int) -> NpcStageDef:
	var stage := NpcStageDef.new()
	stage.stage_id = stage_id
	stage.display_name = label
	stage.index = index
	return stage


func _def(npc_id: StringName, label: String, tier: StringName, stages: Array) -> NpcDef:
	var def := NpcDef.new()
	def.npc_id = npc_id
	def.display_name = label
	def.tier = tier
	for stage in stages:
		def.stages.append(stage)
	def.realm_id = &"qi_refining"
	return def


# --- Tier: the one question the module answers ---------------------------------


func test_a_major_npc_is_tracked_and_a_transient_one_is_not() -> void:
	assert_eq(NpcTier.is_tracked(NpcTier.MAJOR), true, "a major npc is remembered")
	assert_eq(NpcTier.is_tracked(NpcTier.STORY), true, "so is a story npc")
	assert_eq(NpcTier.is_tracked(NpcTier.MINOR), false, "a minor npc is not")
	assert_eq(NpcTier.is_tracked(NpcTier.TRANSIENT), false, "and neither is a transient one")


func test_an_unknown_tier_normalizes_to_the_default_rather_than_tracking() -> void:
	assert_eq(NpcTier.normalize(&"no_such_tier"), NpcTier.DEFAULT, "an unknown tier is untracked")
	assert_eq(
		NpcTier.is_tracked(NpcTier.normalize(&"no_such_tier")),
		false,
		"so nothing is remembered by accident"
	)


# --- Tracked vs untracked lifecycle --------------------------------------------


func test_a_tracked_npc_takes_a_roster_entry_and_an_untracked_one_does_not() -> void:
	NpcApi.spawn(SMITH)
	assert_eq(
		NpcApi.state(NpcApi._player()).has("tracked_ids"), true, "the roster reports what it knows"
	)
	assert_eq(
		NpcApi.state(NpcApi._player())["tracked_ids"],
		["smith_bearcutter"],
		"and the smith is on it"
	)
	NpcApi.spawn(DRIFTER)
	assert_eq(
		NpcApi.state(NpcApi._player())["tracked_ids"],
		["smith_bearcutter"],
		"a drifter leaves no trace at all"
	)


func test_a_tracked_npc_survives_leaving_the_room() -> void:
	NpcApi.spawn(SMITH)
	assert_eq(NpcApi.despawn(SMITH), true, "released")
	assert_eq(NpcRegistry.instance().is_present(SMITH), false, "and no longer live in this room")
	assert_eq(NpcApi.summary(SMITH)["known"], true, "but the player still knows them")
	assert_eq(NpcApi.summary(SMITH)["presence"], "Known", "off-stage, not forgotten")


func test_an_untracked_npc_leaves_nothing_when_it_leaves() -> void:
	NpcApi.spawn(DRIFTER)
	NpcApi.despawn(DRIFTER)
	assert_eq(NpcApi.summary(DRIFTER)["known"], false, "the drifter is a stranger again next visit")


func test_populating_a_room_is_bounded_and_replaces_whoever_was_there() -> void:
	NpcApi.spawn(DRIFTER)
	var ids: Array[StringName] = []
	for index in range(20):
		ids.append(DRIFTER)
	var spawned := NpcApi.populate(ids)
	assert_eq(spawned.size(), NpcApi.MAX_ROOM_POPULATION, "capped at the named bound")
	assert_eq(
		NpcRegistry.instance().present_count(),
		NpcApi.MAX_ROOM_POPULATION,
		"and the live table agrees"
	)


# --- Stage change ---------------------------------------------------------------


func test_an_authored_stage_ladder_starts_at_the_first_stage() -> void:
	NpcApi.spawn(SMITH)
	assert_eq(NpcApi.summary(SMITH)["stage_id"], "smith_new", "they begin where the ladder begins")


func test_advancing_a_stage_is_monotone_and_idempotent() -> void:
	NpcApi.spawn(SMITH)
	assert_eq(NpcApi.advance_stage(SMITH, &"smith_friend", "quest")["ok"], true, "advanced")
	assert_eq(NpcApi.summary(SMITH)["stage_id"], "smith_friend", "they moved")
	assert_eq(
		NpcApi.advance_stage(SMITH, &"smith_friend", "quest")["ok"],
		true,
		"re-advancing succeeds and changes nothing"
	)
	assert_eq(
		NpcApi.advance_stage(SMITH, &"smith_new", "quest")["reason"],
		"stage_regression",
		"and rewinding is refused"
	)


func test_advancing_to_an_unknown_stage_is_refused() -> void:
	NpcApi.spawn(SMITH)
	var result := NpcApi.advance_stage(SMITH, &"no_such_stage")
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], "unknown_stage", "and named")


func test_a_terminal_stage_retires_the_npc_and_they_never_spawn_again() -> void:
	NpcApi.spawn(ELDER)
	NpcApi.advance_stage(ELDER, &"elder_taught", "story")
	assert_eq(NpcApi.summary(ELDER)["presence"], "Retired", "the elder is done")
	NpcApi.despawn(ELDER)
	assert_eq(NpcApi.spawn(ELDER), null, "and will not appear again")


## ## Retirement also forgets the bond (BL-0627)
##
## `SocialApi.forget`'s own docstring promises "a dead minor does not haunt the ledger
## forever", and until `advance_stage` called it the verb had NO production caller — the
## promise existed only in a comment. These assert the two halves of the real promise: the
## row is gone from the live ledger AND from the save payload, because a forget that flushed
## nothing would resurrect the bond on the next load.
func test_retiring_an_npc_forgets_the_bond_so_a_dead_minor_does_not_haunt_the_ledger() -> void:
	var player := NpcApi._player()
	SocialApi.apply_cause(player, ELDER, &"shared_brotherhood")
	assert_ne(
		SocialApi.social_state(player).bond(ELDER),
		null,
		"the elder is somebody the player has sworn to"
	)
	NpcApi.spawn(ELDER)
	NpcApi.advance_stage(ELDER, &"elder_taught", "story")
	assert_eq(SocialApi.social_state(player).bond(ELDER), null, "retirement forgets the bond")
	assert_eq(SocialApi.summary(player)["bond_count"], 0, "so the read model no longer names them")


func test_a_forgotten_bond_stays_forgotten_across_a_save() -> void:
	var player := NpcApi._player()
	SocialApi.apply_cause(player, ELDER, &"shared_brotherhood")
	NpcApi.spawn(ELDER)
	NpcApi.advance_stage(ELDER, &"elder_taught", "story")
	# The whole point of the flush: a forget that did not reach `module_data` would save the
	# OLD ledger and hand the player their dead friend back on the next load.
	var restored := Actor.from_dict(player.to_dict())
	NpcApi.attach(restored)
	SocialApi.attach(restored)
	assert_eq(
		SocialApi.social_state(restored).bond(ELDER),
		null,
		"the save carries the retirement, not the bond it erased"
	)


## The mirror half of the same bug: a bond earned toward a npc who is STILL HERE must not
## be swept up by the retirement wiring. Forgetting the wrong row would be worse than not
## forgetting at all, so this asserts the forget is targeted.
func test_retiring_one_npc_leaves_every_other_bond_alone() -> void:
	var player := NpcApi._player()
	SocialApi.apply_cause(player, ELDER, &"shared_brotherhood")
	SocialApi.apply_cause(player, SMITH, &"gifted_item")
	NpcApi.spawn(ELDER)
	NpcApi.advance_stage(ELDER, &"elder_taught", "story")
	assert_eq(SocialApi.social_state(player).bond(ELDER), null, "the retired one is gone")
	assert_ne(SocialApi.social_state(player).bond(SMITH), null, "the smith is still a stranger-turned-friend")
	assert_eq(SocialApi.summary(player)["bond_count"], 1, "and exactly one bond remains")


func test_a_stage_magnitude_is_applied_once_and_never_stacks() -> void:
	NpcCatalog.instance().reset()
	var weak := _stage(&"weak", "Weak", 0)
	weak.stat_multipliers = {Stat.ATTACK_PHYSICAL: 2.0}
	var strong := _stage(&"strong", "Strong", 1)
	strong.stat_multipliers = {Stat.ATTACK_PHYSICAL: 3.0}
	var boss := _def(ELDER, "Elder Wei", NpcTier.STORY, [weak, strong])
	NpcCatalog.instance().install([boss])
	var actor := NpcApi.spawn(ELDER)
	assert_almost_eq(
		NpcStageProjection.contribution(actor, Stat.ATTACK_PHYSICAL), 2.0, "the first stage applied"
	)
	NpcApi.advance_stage(ELDER, &"strong", "story")
	# 3.0, not 2.0*3.0: strip-then-apply, so an npc never carries both stages at once.
	assert_almost_eq(
		NpcStageProjection.contribution(actor, Stat.ATTACK_PHYSICAL),
		3.0,
		"the second replaced the first rather than stacking on it",
		0.0001
	)


func test_a_tally_advances_the_stage_when_the_authored_count_is_met() -> void:
	NpcApi.spawn(SMITH)
	NpcApi.tally(SMITH, &"favours")
	assert_eq(NpcApi.summary(SMITH)["stage_id"], "smith_new", "one favour is not enough")
	NpcApi.tally(SMITH, &"favours")
	assert_eq(
		NpcApi.summary(SMITH)["stage_id"],
		"smith_friend",
		"two are, because the ladder authored two"
	)


# --- Every role is one Actor ----------------------------------------------------


func test_every_role_mints_the_same_actor_type_there_is_no_npc_subclass() -> void:
	for role in [
		NpcApi.ROLE_MOB, NpcApi.ROLE_MINIBOSS, NpcApi.ROLE_BOSS, NpcApi.ROLE_NPC, NpcApi.ROLE_RIVAL
	]:
		var actor := NpcApi.spawn(DRIFTER, role)
		assert_eq(actor != null, true, "%s minted" % String(role))
		assert_eq(actor.tags.has(role), true, "%s is a tag on the actor" % String(role))


func test_spawning_without_a_minter_fails_loudly_rather_than_returning_nothing_silent() -> void:
	# The module never names ActorFactory; `app/` injects the constructor. With nothing
	# injected, spawn must refuse loudly instead of dereferencing a null callable.
	NpcApi.set_minter(Callable())
	assert_eq(NpcApi.spawn(SMITH), null, "no constructor, no actor")
	assert_eq(NpcApi.spawn(&"no_such_npc"), null, "and an authored id the catalog does not ship")


# --- Persistence ----------------------------------------------------------------


func test_the_roster_round_trips_through_the_player_payload() -> void:
	NpcApi.spawn(SMITH)
	NpcApi.advance_stage(SMITH, &"smith_friend", "quest")
	NpcApi.despawn(SMITH)
	var player := NpcApi._player()
	var restored_player := Actor.from_dict(player.to_dict())
	NpcRegistry.instance().reset()
	NpcApi.attach(restored_player)
	assert_eq(NpcApi.summary(SMITH)["stage_id"], "smith_friend", "the stage survived the save")
	assert_eq(NpcApi.summary(SMITH)["known"], true, "and they are still known")


func test_the_roster_needs_no_second_save_file() -> void:
	NpcApi.spawn(SMITH)
	NpcApi.state(NpcApi._player())
	var payload := NpcApi._player().to_dict()
	assert_eq(int(payload["version"]), Actor.SCHEMA_VERSION, "the actor schema did not move")
	assert_ne(
		payload["module_data"][String(NpcApi.MODULE_KEY)].size(),
		0,
		"the roster rides in module_data"
	)
