extends TestCase

## ADR 0275: the sixth registration seam, end to end through the loader.
##
## `test_mod_declaration_block.gd` pins the PARSER in isolation. This file pins the
## two things only the seam and the runtime can answer:
##
## - a mod's declaration reaches `ModRuntime.finalize` and is spendable, so the
##   vocabulary is genuinely CLOSED and not merely narrowed;
## - a refusal is RECORDED and named, rather than logged and forgotten, so the
##   composition root can act on it and a test can read it back (GDScript cannot
##   intercept `push_error`, so a log line alone is not assertable).
##
## Every mod fixture is written to `user://` and REMOVED in `teardown`, because the
## headless runner shares one process across every suite.

const MOD_FIXTURE := "user://w5_declaration_mods_%d"
## gdformat collapses a parenthesised single string back onto one line, so the manifest
## is two literals JOINED rather than wrapped: the joined form is what stays under the
## 100-column limit, and the wrapper would be undone by the formatter every run.
const MANIFEST_HEAD := '{"id": "%s", "version": "1.0", "priority": %d, '
const MANIFEST_TAIL := '"requires_api": 1, "depends_on": []}'

var _root: String = ""


func setup() -> void:
	_root = MOD_FIXTURE % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
	# Idempotent and safe after an abort (`SeamHarness.teardown` sets the precedent):
	# an early `return` from a test would otherwise leave the directory behind and
	# the NEXT run would discover a stale mod.
	_remove_tree(_root, 0)
	_root = ""


## Depth-capped: a recursive walk needs a cap a `while` scan cannot see for it
## (AGENTS.md), and every directory this writes is two deep.
func _remove_tree(path: String, depth: int) -> void:
	if depth > 16 or not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var names: Array[String] = []
	# `guard` is the bound and `entry != ""` is the DirAccess terminator; the body
	# appends to `names` and does not feed either, so it cannot outrun them.
	var guard := 0
	while entry != "" and guard < 4096:
		guard += 1
		if not entry.begins_with("."):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(child):
			_remove_tree(child, depth + 1)
		else:
			DirAccess.remove_absolute(child)
	DirAccess.remove_absolute(path)


func _write_mod(dir_name: String, mod_id: String, priority: int, block: Variant) -> String:
	var dir_path := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var manifest := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string((MANIFEST_HEAD % [mod_id, priority]) + MANIFEST_TAIL)
	manifest.close()
	if block != null:
		var file := FileAccess.open(dir_path.path_join("stats.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(block))
		file.close()
	return dir_path


## A mod with NO block at all. Asserted explicitly rather than left implicit, because
## "declares nothing" is a legitimate answer (ADR 0083) and a gate that reported it
## would make the common case noisy.
func test_a_mod_with_no_declaration_block_contributes_nothing_and_no_refusal() -> void:
	_write_mod("bare", "w5_bare", 10, null)
	var out := _load()
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(
		(registrations["declaration_refusals"] as Array).size(),
		0,
		"an absent block is not a refusal: most mods declare no stats"
	)
	assert_eq((registrations["stat_declarations"] as Array).size(), 0, "and contributes no rows")
	assert_eq(registrations["declared_resources"].size(), 0, "and brings no pools")


func _load() -> Dictionary:
	return ModsApi.load_order([_root])


## A declaration block the loader cannot see is the failure this seam was added to
## end, so the block is a SIBLING FILE (`stats.json`) rather than a manifest field:
## `ModManifest.parse` normalises a fixed key set, and a mod's numbers belong to the
## mod's own directory where the Python gates can find them too.
func test_a_declaration_block_beside_the_manifest_reaches_the_runtime() -> void:
	_write_mod(
		"warlike",
		"w5_warlike",
		10,
		{
			"stats":
			[
				{
					"id": "attack_physical",
					"op": "percent",
					"resource": "wrath",
					"zero_baseline": true
				}
			],
			"resources": [{"id": "wrath"}],
		}
	)
	var out := _load()
	assert_eq(out["ok"], true, "the loader is happy with a mod carrying a block")
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(
		(registrations["declaration_refusals"] as Array).size(),
		0,
		"a well-formed declaration produces no refusal"
	)
	var stats: Array = registrations["stat_declarations"]
	assert_eq(stats.size(), 1, "the stat row reached the runtime registrations")
	assert_eq(stats[0]["mod_id"], "w5_warlike", "stamped with the mod that declared it")
	assert_eq(
		String(registrations["declared_resources"]["wrath"]),
		"w5_warlike",
		"and the pool it brought is recorded against its owner"
	)


## The load ORDER and the pool OWNER are the same question: the ctx earlier in load
## order owns the pool, so the second mod is the one refused. Asserting the ordering
## matters as much as the refusal — a rule that resolved ownership by argument order
## would refuse whichever mod happened to be listed second, and a boot is not a
## function of the ctxs' array order.
func test_the_first_mod_in_load_order_owns_a_pool_and_the_second_is_refused() -> void:
	_write_mod("first", "w5_first", 10, {"stats": [], "resources": [{"id": "wrath"}]})
	_write_mod("second", "w5_second", 20, {"stats": [], "resources": [{"id": "wrath"}]})
	var out := _load()
	assert_eq(
		(out["order"] as Array)[0],
		"w5_first",
		"the lower priority loads first, so it owns the pool"
	)
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(
		String(registrations["declared_resources"]["wrath"]),
		"w5_first",
		"and the owner is the earlier mod"
	)
	var refusals: Array = registrations["declaration_refusals"]
	assert_eq(refusals.size(), 1, "the second mod's declaration is refused")
	assert_eq(
		String(refusals[0]["reason"]),
		RegistrationContext.DUPLICATE_RESOURCE,
		"for the named cross-mod collision"
	)
	var detail := String(refusals[0]["detail"])
	assert_eq(detail.contains("w5_second"), true, "naming the mod that collided: %s" % detail)
	assert_eq(detail.contains("w5_first"), true, "and the mod that owns it: %s" % detail)


## A mod reading its OWN pool from two rows is one declaration read twice. Without
## this the seam would report a mod's own block back to it as a collision, and the
## first such false positive would train every author to ignore the channel.
func test_a_mod_reading_its_own_pool_twice_is_not_a_collision() -> void:
	_write_mod(
		"twice",
		"w5_twice",
		10,
		{
			"stats":
			[
				{"id": "attack_physical", "op": "flat", "resource": "wrath"},
				{"id": "crit_chance", "op": "flat", "resource": "wrath"},
			],
			"resources": [{"id": "wrath"}],
		}
	)
	var out := _load()
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(
		(registrations["declaration_refusals"] as Array).size(),
		0,
		"reading one declared pool from two rows is not a collision"
	)
	assert_eq((registrations["stat_declarations"] as Array).size(), 2, "and both rows are kept")


## `DUPLICATE_RESOURCE` lives on the SEAM, not on the parser: a single-mod pure
## function has no cross-mod view, so a caller validating a refusal against the
## parser's set would treat a collision as impossible. Asserted so the two sets
## cannot drift into agreeing by accident.
func test_a_cross_mod_collision_reason_is_not_in_the_parser_set() -> void:
	assert_eq(
		DeclarationBlock.reasons().has(RegistrationContext.DUPLICATE_RESOURCE),
		false,
		"the parser cannot produce a reason it cannot see"
	)


## A mod whose `stats.json` is malformed has asserted something the game cannot
## check, and reading it as "declared nothing" is the exact silent pass ADR 0184 d9
## forbids. The LOADER still succeeds — the mod's identity and dependency graph are
## sound — while the seam refuses, which is the split ADR 0275 draws between a bad
## manifest (abort) and a bad declaration (report).
func test_a_malformed_block_file_is_refused_rather_than_read_as_empty() -> void:
	var dir_path := _write_mod("broken", "w5_broken", 10, null)
	var file := FileAccess.open(dir_path.path_join("stats.json"), FileAccess.WRITE)
	file.store_string("{not json at all")
	file.close()
	var out := _load()
	assert_eq(out["ok"], true, "a broken sibling block does not abort discovery")
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	var refusals: Array = registrations["declaration_refusals"]
	assert_eq(refusals.size(), 1, "but it is refused, once, not read as an empty block")
	assert_eq(String(refusals[0]["reason"]), DeclarationBlock.BAD_BLOCK, "as a block-shape problem")
	assert_eq(
		String(refusals[0]["detail"]).contains("w5_broken"),
		true,
		"naming the mod whose file could not be read"
	)
	assert_eq((registrations["stat_declarations"] as Array).size(), 0, "and it contributes no rows")


## A `stats.json` holding something other than an object is the same refusal: a file
## the parser cannot interpret is not a declaration of nothing.
func test_a_block_file_that_is_not_an_object_is_refused() -> void:
	var dir_path := _write_mod("array_block", "w5_array", 10, null)
	var file := FileAccess.open(dir_path.path_join("stats.json"), FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	var out := _load()
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(
		(registrations["declaration_refusals"] as Array).size(),
		1,
		"a top-level array is refused rather than skipped"
	)


## The unknown-id refusals must survive the READ too, not only the direct seam call —
## a gate that only holds when a test bypasses the file proves nothing about a boot.
func test_an_unknown_id_in_a_block_on_disk_reaches_the_runtime_refusals() -> void:
	_write_mod(
		"typo",
		"w5_typo",
		10,
		{
			"stats": [{"id": "physique", "op": "flat", "resource": "raeg"}],
			"resources": [{"id": "rage"}],
		}
	)
	var out := _load()
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	var refusals: Array = registrations["declaration_refusals"]
	assert_eq(refusals.size(), 1, "the typo'd pool on disk is refused once")
	assert_eq(
		String(refusals[0]["reason"]), DeclarationBlock.UNKNOWN_RESOURCE, "with the named reason"
	)
	var detail := String(refusals[0]["detail"])
	assert_eq(detail.contains("raeg"), true, "naming the bad id: %s" % detail)
	assert_eq(detail.contains("w5_typo"), true, "and the mod: %s" % detail)


## The idempotence `declare_stats` promises, and the reason it is load-bearing rather
## than cosmetic: `ModBoot.run()` finalizes on EVERY boot, so an appending seam would
## double each row on the second pass — and a doubled pool declaration reads as a
## cross-mod collision, so the mod would be told its own block collided with itself.
func test_a_second_declare_replaces_rather_than_doubles() -> void:
	var ctx := RegistrationContext.new("w5_twice")
	var block := {
		"stats": [{"id": "physique", "op": "flat", "resource": "wrath"}],
		"resources": [{"id": "wrath"}],
	}
	ctx.declare_stats(block)
	ctx.declare_stats(block)
	assert_eq(ctx.stat_declarations.size(), 1, "one row, not two, after two identical calls")
	assert_eq(ctx.declared_resource_ids().size(), 1, "and one pool")
	var registrations := ModRuntime.finalize([ctx], ModuleRegistry.new())
	assert_eq(
		(registrations["declaration_refusals"] as Array).size(),
		0,
		"so a second boot reports no collision between the mod and itself"
	)


## A refused block leaves the ctx with NOTHING recorded, which is what "no partial
## write" has to mean AT THE SEAM. `DeclarationBlock.parse` deliberately still reports
## its good rows — the author needs to see them while fixing a typo — so the promise
## is not the parser's, and
## `test_a_refused_block_reports_its_good_rows_without_committing_them` pins that half.
func test_a_refused_declaration_records_nothing_on_the_context() -> void:
	var ctx := RegistrationContext.new("w5_bad")
	var out := (
		ctx
		. declare_stats(
			{
				"stats":
				[
					{"id": "physique", "op": "flat", "resource": "wrath"},
					{"id": "not_a_stat", "op": "flat"},
				],
				"resources": [{"id": "wrath"}],
			}
		)
	)
	assert_eq(out["ok"], false, "the block is refused")
	assert_eq(ctx.stat_declarations.size(), 0, "and the good row is not recorded either")
	assert_eq(ctx.declared_resource_ids().size(), 0, "nor is the pool it declared")
	assert_eq(
		ctx.declaration_refusals.size(), 1, "while the one refusal naming the bad row is recorded"
	)


## THE end-to-end claim: a pool this mod declared is a REAL pool, not a string the
## seam accepted. `ensure_resources` mints it from `CultivationPathDef.resource_ids`,
## and this is the same function the shipped paths use — so the closure is over the
## game's own pool creation, not over a table this slice invented.
##
## `Actor extends RefCounted`, so this test frees nothing: there is no `free()` on a
## RefCounted (it is a runtime error) and no `queue_free()` (banned in `res://src`,
## and meaningless on a non-Node). The actor is released when the function returns.
func test_a_declared_pool_is_spendable_through_ensure_resources() -> void:
	var ctx := RegistrationContext.new("w5_warlike")
	var parsed := (
		ctx
		. declare_stats(
			{
				"stats":
				[
					{
						"id": "attack_physical",
						"op": "flat",
						"resource": "wrath",
						"zero_baseline": true
					}
				],
				"resources": [{"id": "wrath"}],
			}
		)
	)
	assert_eq(parsed["ok"], true, "the declaration is accepted")
	var def := CultivationPathDef.new()
	def.resource_ids = ctx.declared_resource_ids()
	assert_eq(
		(def.resource_ids as Array).size(), 1, "the declared pool feeds a path def's resource_ids"
	)
	var actor := Actor.new()
	# Freed with `free()` and not `queue_free()`: the headless runner drives tests
	# from `SceneTree._initialize()`, so a deferred free never runs under `tools test`.
	actor.attach_core_resources()
	def.ensure_resources(actor)
	var pool := actor.resource(&"wrath")
	assert_ne(pool, null, "the declared pool EXISTS after ensure_resources")
	if pool == null:
		return
	assert_eq(pool.maximum, 0.0, "minted at zero, exactly as ensure_resources does")
	# `ResourcePool.change` CLAMPS to `[0, maximum]`, so a pool minted at zero needs
	# sizing before a spend lands. Asserting a non-zero `current` without this would
	# pass for the wrong reason — the clamp alone would have produced 0.0 and made
	# "spendable" indistinguishable from "present but inert".
	pool.set_maximum(25.0)
	actor.change_resource(&"wrath", 10.0)
	assert_eq(actor.resource(&"wrath").current, 10.0, "and it is spendable, not merely present")
	actor.change_resource(&"wrath", -4.0)
	assert_eq(actor.resource(&"wrath").current, 6.0, "and it drains")


## The negative of the test above, and the one that would have passed before this
## seam: a pool NOTHING declares is absent from the actor, so the read that used to
## yield `0.0` now has no pool to read — which is what the declaration refusal
## exists to turn into an error at declaration time instead of a mystery at runtime.
func test_a_pool_nobody_declared_does_not_exist_on_the_actor() -> void:
	var actor := Actor.new()
	actor.attach_core_resources()
	assert_eq(actor.resource(&"raeg"), null, "a typo'd pool id resolves to no pool at all")
	# `Actor.change_resource` on an id with no pool is a silent no-op — the read site
	# that made a typo'd economy look live but empty. This is why the refusal has to
	# happen at DECLARATION time: by the time a read happens there is nothing left to
	# distinguish "this actor has no wrath" from "this id is not wrath at all".
	actor.change_resource(&"raeg", 5.0)
	assert_eq(
		actor.resource(&"raeg"), null, "and no pool is minted by writing to it: nothing resolves it"
	)
