extends TestCase

## **`install_store(key, null)` CLEARS the entry** — the uninstall path three
## suites already called and the code did not honor.
##
## `install_store` used to answer `not_a_store` for `null` and leave `_stores[key]`
## untouched, so no store-installing suite could restore isolation in the shared
## test process. A leaked `polity` store is not inert: it silently changes
## `RelationsApi.graph()`'s memo rule for every later suite (DEF-0179). This suite
## pins the fix and the two refusals that must survive it.
##
## Every loop here is a `for` over a fixed array; none appends to the container it
## walks.


## A minimal store: the seam is duck-typed, so `read_ledger` is the whole contract
## `install_store` checks.
class FakeStore:
	extends RefCounted

	func read_ledger() -> Dictionary:
		return {}


func setup() -> void:
	# A suite that mounted the app leaves the `polity` store installed; clear it so
	# the "nothing was installed" case measures the refusal rather than the leak.
	SaveApi.install_store(WorldPolityLedger.WORLD_KEY, null)


func teardown() -> void:
	# The one key this suite installs into, cleared through the fix under test —
	# which is exactly the cleanup the shared-process runner needs.
	SaveApi.install_store(WorldPolityLedger.WORLD_KEY, null)


func test_a_null_store_clears_the_entry_and_reports_success() -> void:
	var store := FakeStore.new()
	assert_eq(
		bool(SaveApi.install_store(WorldPolityLedger.WORLD_KEY, store)["ok"]), true, "installed"
	)
	assert_eq(SaveApi.store_for(WorldPolityLedger.WORLD_KEY) == store, true, "and readable back")
	var cleared := SaveApi.install_store(WorldPolityLedger.WORLD_KEY, null)
	assert_eq(bool(cleared["ok"]), true, "the clear is an ok")
	assert_eq(String(cleared["reason"]), "", "with no reason")
	assert_eq(String(cleared["key"]), WorldPolityLedger.WORLD_KEY, "naming the key")
	assert_eq(SaveApi.store_for(WorldPolityLedger.WORLD_KEY), null, "and the entry is gone")
	# A second clear is harmless, which is what makes it safe as an unconditional
	# teardown line.
	assert_eq(
		bool(SaveApi.install_store(WorldPolityLedger.WORLD_KEY, null)["ok"]), true, "clearing twice"
	)
	assert_eq(SaveApi.store_for(WorldPolityLedger.WORLD_KEY), null, "is still nothing installed")


func test_a_non_store_object_is_still_refused_by_name() -> void:
	var plain := RefCounted.new()
	var refused := SaveApi.install_store(WorldPolityLedger.WORLD_KEY, plain)
	assert_eq(bool(refused["ok"]), false, "a non-store is refused")
	assert_eq(String(refused["reason"]), "not_a_store", "by name")
	assert_eq(SaveApi.store_for(WorldPolityLedger.WORLD_KEY), null, "and nothing was installed")


func test_an_unknown_key_is_still_refused_by_name() -> void:
	var refused := SaveApi.install_store("not_a_world_key", FakeStore.new())
	assert_eq(bool(refused["ok"]), false, "an unknown key is refused")
	assert_eq(String(refused["reason"]), "unknown_world_key", "by name")
	# Even a null clear refuses an unknown key: the key check runs first, so the
	# clear cannot become a way to write into a slot this build does not carry.
	var cleared := SaveApi.install_store("not_a_world_key", null)
	assert_eq(bool(cleared["ok"]), false, "even a null clear refuses an unknown key")
	assert_eq(String(cleared["reason"]), "unknown_world_key", "for the same reason")
