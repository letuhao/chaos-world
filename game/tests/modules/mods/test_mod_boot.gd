extends TestCase

## The composition root's early step: `ModBoot` computes the load order and
## stores `ctx`. It runs standalone here (no scene tree), which is the same
## code path `_ready` drives in the shipped scene.

## A temp root for generated mods; removed in teardown. A boot over it drives
## THIS node's `run()` — the same firing path production uses.
const BOOT_ROOT := "user://w8_mod_boot_%d"

var _root: String = ""


func setup() -> void:
	_root = BOOT_ROOT % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)
	W8LifecycleProbe.calls.clear()


func teardown() -> void:
	DirAccess.remove_absolute(_root.path_join("mod.json"))
	DirAccess.remove_absolute(_root)
	_root = ""


func _write_mod(mod_id: String) -> void:
	var manifest := FileAccess.open(_root.path_join("mod.json"), FileAccess.WRITE)
	(
		manifest
		. store_string(
			(
				JSON
				. stringify(
					{
						"id": mod_id,
						"version": "1.0",
						"priority": 0,
						"requires_api": 1,
						"lifecycle_hooks":
						[
							{
								"event": "on_load",
								"callable": "res://tests/fixtures/mods/lifecycle_probe.gd:on_load"
							}
						],
					}
				)
			)
		)
	)
	manifest.close()


func test_a_boot_pass_on_the_real_roots_is_loud_or_clean() -> void:
	var boot := ModBoot.new()
	var status := boot.run()
	# The shipped tree has no mod.json under res://src/modules and usually no
	# user://mods dir, so the honest answer today is an empty order — but the
	# contract under test is the SHAPE: ok flag, array order, array contexts,
	# and a NAMED reason whenever ok is false.
	assert_eq(status.has("ok"), true, "status always carries ok")
	assert_eq(boot.order is Array, true, "order is an array")
	assert_eq(boot.contexts is Array, true, "contexts is an array")
	if bool(status["ok"]):
		assert_eq(boot.order.size(), boot.contexts.size(), "one ctx per ordered mod")
	else:
		assert_eq(String(status.get("reason", "")).is_empty(), false, "a failure is NAMED")
	boot.free()


func test_external_root_is_included_only_when_the_directory_exists() -> void:
	var boot := ModBoot.new()
	var roots := boot.roots()
	assert_eq(roots.size() >= 1, true, "first-party root always listed")
	assert_eq(String(roots[0]), ModBoot.FIRST_PARTY_ROOT, "first-party root first")
	if DirAccess.dir_exists_absolute(ModBoot.EXTERNAL_ROOT):
		assert_eq(roots.has(ModBoot.EXTERNAL_ROOT), true, "external root listed when present")
	else:
		assert_eq(roots.has(ModBoot.EXTERNAL_ROOT), false, "absent external root not scanned")
	boot.free()


## The production firing: a successful boot pass runs a mod's load-time code,
## with that mod's own context, exactly once. Remove the `fire_lifecycle_event`
## call from `run()` and this goes red — which is the guard the doctrine suite's
## production leg leans on.
func test_a_boot_pass_fires_on_load_with_the_mods_context() -> void:
	_write_mod("w8_boot_on_load")
	var boot := ModBoot.new()
	var status := boot.run([_root])
	assert_eq(
		bool(status.get("ok", false)), true, "boot succeeds: %s" % str(status.get("detail", ""))
	)
	assert_eq(W8LifecycleProbe.calls.size(), 1, "on_load fired exactly once")
	var ctx: RegistrationContext = status["contexts"][0]
	assert_eq(W8LifecycleProbe.calls[0]["ctx"], ctx, "the hook received its own mod's context")
	assert_eq(
		String(W8LifecycleProbe.calls[0]["mod_id"]), "w8_boot_on_load", "stamped with the mod"
	)
	boot.free()


## A second pass is a SECOND boot, not a duplicate of the first: each pass stamps
## fresh contexts and fires THEIR hooks. Pinned so "once per pass" cannot silently
## become "once per process" — which would make a re-boot skip load-time code.
func test_a_second_boot_pass_fires_its_own_on_load() -> void:
	_write_mod("w8_boot_twice")
	var boot := ModBoot.new()
	boot.run([_root])
	assert_eq(W8LifecycleProbe.calls.size(), 1, "first pass fired")
	boot.run([_root])
	assert_eq(W8LifecycleProbe.calls.size(), 2, "second pass fired its own hook")
	assert_ne(
		W8LifecycleProbe.calls[0]["ctx"],
		W8LifecycleProbe.calls[1]["ctx"],
		"fresh context each pass"
	)
	boot.free()
