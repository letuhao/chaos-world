extends TestCase

## A mount and its teardown are a MATCHED PAIR for the world polity seams (DEF-0387).
##
## `InstitutionBoot.install` wires the app's polity store into `RelationsApi`,
## `SectApi` and `NationApi` on every mount, and those seams are PROCESS state —
## `SeamHarness.teardown` unwires them so a suite that mounts cannot leave a later
## suite taking the world leg against the store this mount installed. Without the
## unwiring, a later suite's declaration can write the real save slot through a
## store it never asked for, and `RelationsApi`'s memo rule changes underneath it.
##
## The two cases are ordered so neither is vacuous: the first proves the mount DID
## wire the seams (or the second would pass because nothing was ever installed), and
## the second proves the teardown removes them.

var _harness: SeamHarness


func setup() -> void:
	_harness = SeamHarness.mount_new()


## Idempotent, and safe after the second case already tore the harness down.
func teardown() -> void:
	if _harness != null:
		_harness.teardown()
	_harness = null


func test_a_mount_wires_the_world_polity_seams() -> void:
	if not _booted():
		return
	assert_ne(RelationsApi._store, null, "the mounted app wired the reader")
	assert_ne(SectApi._world_store, null, "and the sect writer")
	assert_ne(NationApi._world_store, null, "and the nation writer")


func test_a_teardown_unwires_them_and_clears_the_save_slot() -> void:
	if not _booted():
		return
	_harness.teardown()
	assert_eq(RelationsApi._store, null, "the reader is unwired")
	assert_eq(SectApi._world_store, null, "the sect writer is unwired")
	assert_eq(NationApi._world_store, null, "the nation writer is unwired")
	assert_eq(
		SaveApi.store_for(WorldPolityLedger.WORLD_KEY),
		null,
		"and the polity slot is cleared, so the next suite starts from nothing"
	)


## The mount must be real, or the two cases above are assertions about a harness
## that never booted. `_booted` asserts rather than returns quietly, so a broken
## mount is named here instead of absorbed.
func _booted() -> bool:
	if _harness == null or _harness.app == null:
		return false
	assert_eq(
		_harness.boot_error, "", "the real ItemWorkbenchApp scene boots, or nothing below is proven"
	)
	return _harness.boot_error == ""
