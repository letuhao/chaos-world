extends SceneTree


func _initialize() -> void:
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	print("runtime total realms: ", realms.size())
	for r in realms:
		var id := String(r.id)
		if id in ["qi_refining", "spirit_ascension", "tribulation", "nascent_soul"]:
			print("  runtime theta ", ladder.index_of(r.id), " ", id)
	var catalog := OptionCatalog.instance()
	print("spirit_ascension rare attack window: ", catalog.magnitude_bounds("magnitude", 17, 2))
	quit(0)
