extends TestCase

## TEMPORARY probe (deleted before commit): does `ModLoader._resolve_callable`
## resolve res:// specs, and can a STATIC method be called through the resolved
## Callable (the doctrine template's `boot` is static)?


func test_probe_resolve() -> void:
	var hook := ModLoader._resolve_callable("res://src/modules/mods/hook_fixture.gd:on_attach")
	print("PROBE hook valid=", hook.is_valid())
	var dlc := ModLoader._resolve_callable(
		"res://tests/fixtures/mods/dlc_example/hook_script.gd:on_dlc_boot"
	)
	print("PROBE dlc valid=", dlc.is_valid())
	var doctrine := ModLoader._resolve_callable(
		"res://tests/fixtures/mods/doctrine_system/api.gd:boot"
	)
	print("PROBE doctrine valid=", doctrine.is_valid())
	if doctrine.is_valid():
		var verdict: Dictionary = doctrine.call(RegistrationContext.new("probe"))
		print("PROBE doctrine verdict=", verdict)
	assert_eq(true, true, "probe ran")
