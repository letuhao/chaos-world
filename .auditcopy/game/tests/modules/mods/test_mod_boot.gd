extends TestCase

## The composition root's early step: `ModBoot` computes the load order and
## stores `ctx`. It runs standalone here (no scene tree), which is the same
## code path `_ready` drives in the shipped scene.


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
