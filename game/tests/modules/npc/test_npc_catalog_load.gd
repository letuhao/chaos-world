extends TestCase

## BL-0626: **the cast must load FROM DISK, not from a test-owned install.**
##
## Every other npc suite installs its own defs — which is why a catalog that never
## scanned anything at all still passed 269 tests. Every assertion in this file
## therefore REFUSES to install a fixture and reaches the catalog only through the
## production path (`NpcCatalog.load_authored`, which `NpcBoot.install` calls on boot).
## If the scan is deleted, or the boot call removed, this suite goes red.
##
## The four ids are read from the files rather than restated, so adding a cast
## member does not make this file lie about "every shipped individual".

const CAST_ROOT := "res://data/npc/cast"

## The two the boot path is proven to MINT an actor from, rather than merely resolve.
const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"


func setup() -> void:
	# A process-wide singleton carries state between suites, and the runner reuses this
	# suite's catalog reference in the next `setup`. Resetting here is what makes each
	# test start from the same place the game boots from: an empty, unread catalog.
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()
	# `attach(null)` is a no-op BY DESIGN (it refuses to rebind nothing), so the bound
	# player is cleared directly. Left bound, the next `spawn` would write a roster
	# onto whichever actor a previous suite left here and the read-model assertions
	# below would be about that actor rather than this test's own.
	NpcApi._current_player = null
	SocialCauseCatalog.instance().install_defaults()


func teardown() -> void:
	# Both singletons are process-wide and the runner calls this after EVERY test, so
	# leaving the shipped tree loaded would hand it to whichever npc suite runs next as
	# if it were that suite's own fixture.
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcApi.set_minter(Callable())


func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 12.0, Stat.WILL: 8.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	return actor


# --- The catalog reads the authored tree ---------------------------------------


## THE load-bearing assertion of this file. Reset the singleton, ask the production
## path for the shipped cast, and read it back — with no `install` anywhere in sight.
func test_the_production_read_finds_every_shipped_cast_member_on_disk() -> void:
	NpcCatalog.instance().reset()
	var shipped := NpcCatalog.instance().load_authored()
	assert_ne(shipped, 0, "the authored tree is what a production read finds, not an empty catalog")
	for path in ContentScan.files_under(CAST_ROOT):
		var npc_id := StringName(path.get_file().get_basename())
		assert_ne(
			NpcCatalog.instance().definition(npc_id), null, "%s was read from disk" % String(npc_id)
		)


## The four individuals ADR 0092 names, by id. A restated list is the point: an id the
## file authors under another name is a cast member nothing in the game can name.
func test_all_four_shipped_individuals_resolve_after_the_production_read() -> void:
	NpcCatalog.instance().load_authored()
	for npc_id in [&"elder_wei", &"smith_bearcutter", &"drifter", &"gate_keeper_bo"]:
		assert_ne(NpcCatalog.instance().definition(npc_id), null, "%s is shipped" % String(npc_id))


## What "loads from disk" means that a hand-installed `NpcDef` does not: the instance
## the catalog holds is the one the ENGINE loaded from the path, cache and all, not a
## copy a test composed.
func test_the_definition_is_the_resource_the_engine_loaded_not_a_copy() -> void:
	NpcCatalog.instance().load_authored()
	assert_eq(
		NpcCatalog.instance().definition(ELDER),
		load("%s/elder_wei.tres" % CAST_ROOT) as NpcDef,
		"the catalog hands back the loaded resource itself"
	)


## A def read off disk carries the authored fields, so the tiers ADR 0092 relies on are
## real data rather than a fixture's default.
func test_the_read_cast_carries_both_tracked_tiers_and_both_untracked_ones() -> void:
	NpcCatalog.instance().load_authored()
	assert_eq(NpcCatalog.instance().definition(ELDER).tracked(), true, "the elder is remembered")
	assert_eq(NpcCatalog.instance().definition(SMITH).tracked(), true, "so is the smith")
	assert_eq(NpcCatalog.instance().definition(&"drifter").tracked(), false, "the drifter is not")
	assert_eq(
		NpcCatalog.instance().definition(&"gate_keeper_bo").tracked(), false, "nor the gatekeeper"
	)


func test_the_read_cast_carries_the_authored_stage_ladder() -> void:
	NpcCatalog.instance().load_authored()
	assert_eq(
		NpcCatalog.instance().definition(ELDER).stage_count(),
		3,
		"the elder's three rungs came off disk, not from a fixture"
	)


## `reset()` clears the loaded FLAG as well as the rows. Asserted because it is what
## makes the seam a seam rather than a one-way door: if it forgot the flag, the tests
## above would pass against a catalog that had been filled once by an earlier suite and
## had read nothing itself — which is the exact failure this file exists to catch.
func test_a_reset_catalog_re_reads_the_authored_tree() -> void:
	NpcCatalog.instance().load_authored()
	NpcCatalog.instance().reset()
	assert_eq(
		NpcCatalog.instance().definition(ELDER), null, "after a reset the catalog really is empty"
	)
	assert_ne(NpcCatalog.instance().load_authored(), 0, "and the next production read re-scans")
	assert_ne(NpcCatalog.instance().definition(ELDER), null, "which finds him again")


func test_the_read_is_idempotent_so_a_re_install_costs_no_second_scan() -> void:
	var first := NpcCatalog.instance().load_authored()
	assert_eq(
		NpcCatalog.instance().load_authored(), first, "a second production read changes nothing"
	)


## The seam is still a seam. `install` is explicit and immediate, so a suite can hold
## exactly one def and see exactly one — which is what every OTHER npc suite relies on
## and what merging the two paths would have broken.
func test_install_stays_the_test_seam_and_still_holds_exactly_what_it_was_given() -> void:
	var probe := NpcDef.new()
	probe.npc_id = &"a_probe_nobody_ships"
	NpcCatalog.instance().install([probe])
	assert_eq(
		NpcCatalog.instance().npc_ids(),
		[&"a_probe_nobody_ships"],
		"installing one def installed one def"
	)
	assert_eq(
		NpcCatalog.instance().definition(ELDER),
		null,
		"and did not drag the authored tree in behind it"
	)


# --- The boot path, end to end ------------------------------------------------


## The whole point in one test: the composition root's boot verb is what puts the
## authored cast in the catalog, so a boot alone — with no test-owned `install`
## anywhere — leaves a player able to meet the cast.
func test_the_composition_root_boot_installs_the_authored_cast_by_itself() -> void:
	NpcBoot.install(_player())
	assert_ne(
		NpcCatalog.instance().definition(ELDER),
		null,
		"boot read the tree, so the catalog is not the empty one the audit found"
	)


## And boot does not merely resolve ids: it mints a real inhabitant out of one, with
## the authored name on it. This is `NpcApi.spawn`'s old refusal at `api.gd:131`,
## taken from the other side.
func test_a_boot_with_no_test_installed_fixture_can_spawn_a_cast_member() -> void:
	NpcBoot.install(_player())
	var actor := NpcApi.spawn(SMITH)
	assert_ne(actor, null, "spawn stopped returning null")
	assert_eq(
		L.t(actor.display_name), "Smith Bearcutter", "named from the def that was read off disk"
	)


## `install` is documented as callable again after a load, and the catalog read must
## survive that: the second call re-announces the cast rather than emptying it.
func test_re_installing_after_a_load_keeps_the_cast() -> void:
	var player := _player()
	NpcBoot.install(player)
	NpcBoot.install(player)
	assert_ne(NpcCatalog.instance().definition(SMITH), null, "the cast survived a re-install")
	assert_ne(NpcApi.spawn(ELDER), null, "and the roster re-announced rather than reset")


## `install(null)` is a no-op for the ROSTER and is still a read for the CATALOG.
## Asymmetric on purpose — the cast is process-wide content, not per-player state — and
## asserted here so a later "tidy up" cannot quietly move the read below the guard and
## re-break the boot for the next caller.
func test_a_null_install_still_brings_the_cast_in_but_binds_no_player() -> void:
	NpcBoot.install(null)
	assert_ne(NpcCatalog.instance().definition(ELDER), null, "content is not per-player")
	assert_eq(NpcApi._player(), null, "and nothing was bound")


# --- The room the boot stocks ---------------------------------------------------


## `populate_room` has a production caller now (the boot), so a room is actually
## stocked rather than only reachable: three authored ids in, three bodies out, and the
## tracked one is on the player's roster.
func test_the_boot_stocks_a_room_with_the_cast_read_off_disk() -> void:
	var player := _player()
	var room := NpcBoot.populate_room(
		player,
		[&"gate_keeper_bo", &"smith_bearcutter", &"drifter"],
		NpcApi.ROLE_NPC,
		&"mortal_plains"
	)
	assert_eq(room["spawned"], 3, "three authored bodies stood up")
	assert_eq(NpcRegistry.instance().present_count(), 3, "and the live table agrees")
	assert_eq(
		NpcApi.state(player)["tracked_ids"],
		["smith_bearcutter"],
		"the smith is remembered; the other two leave nothing behind"
	)
	assert_eq(room["location_id"], "mortal_plains", "and the room named its place")
