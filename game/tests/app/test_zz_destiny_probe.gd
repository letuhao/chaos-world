extends TestCase

## THROWAWAY probe (session diag-fate-cache): measures what FateCatalog.instance()
## holds on the very first read in this process. Delete before commit.


func test_zz_probe_catalog_first_read() -> void:
	var cat := FateCatalog.instance()
	var ids: Array[StringName] = cat.destiny_ids()
	print("PROBE destiny_ids.size=%d ids=%s" % [ids.size(), str(ids)])
	var fates: Array[StringName] = cat.fate_ids()
	print("PROBE fate_ids.size=%d ids=%s" % [fates.size(), str(fates)])
	var origins: Array[StringName] = cat.destinies_in_group(&"origin")
	print("PROBE origins.size=%d ids=%s" % [origins.size(), str(origins)])
	for id in ids:
		var def: DestinyDef = cat.destiny_definition(id)
		if def == null:
			print("PROBE %s -> NULL" % id)
		else:
			print("PROBE %s -> id=%s group=%s" % [id, def.id, def.group])
	print("PROBE DESTINY_ROOT=%s scan=%s" % [
		FateCatalog.DESTINIES_ROOT, str(ContentScan.files_under(FateCatalog.DESTINIES_ROOT))
	])
	print("PROBE dir_exists=%s" % DirAccess.dir_exists_absolute("res://data/destiny/destinies"))
	assert_eq(ids.size() > 0, true, "the catalog ships at least one destiny")
