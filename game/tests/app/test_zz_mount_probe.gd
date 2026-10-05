extends TestCase

## THROWAWAY probe (session diag-fate-cache): does mounting the app poison FateCatalog?
## Delete before commit.


func _dump(tag: String) -> void:
	var cat := FateCatalog.instance()
	var ids: Array[StringName] = cat.destiny_ids()
	print("PROBE[%s] shared_id=%d destiny_ids=%d fates=%d origins=%s" % [
		tag, cat.get_instance_id(), ids.size(), cat.fate_ids().size(),
		str(cat.destinies_in_group(&"origin")),
	])
	for id in ids:
		var def: DestinyDef = cat.destiny_definition(id)
		print("PROBE[%s] %s group=%s visibility=%s" % [tag, id, def.group, def.visibility])


func test_zz_probe_mount_poisons_catalog() -> void:
	_dump("before_mount")
	var harness := SeamHarness.mount_new()
	print("PROBE boot_error=%s" % harness.boot_error)
	_dump("after_mount")
	harness.teardown()
	_dump("after_teardown")
	assert_eq(true, true, "probe ran")
