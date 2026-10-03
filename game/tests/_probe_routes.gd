extends SceneTree

## Replicates test_ui_conventions._source_texts + the reachability scan exactly.
const UI_ROOT := "res://src/ui"
const SCREENS_DIR := "res://src/ui/screens"
const PROGRAM_ROOTS := ["res://src", "res://scenes"]
const SCANNED_SUFFIXES := [".gd", ".tscn"]
const EXCLUDED_DIRS := ["tests", "addons", "data", "assets"]


func _source_texts(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and not EXCLUDED_DIRS.has(entry):
				out.append_array(_source_texts(path))
		elif SCANNED_SUFFIXES.has(entry.get_extension()):
			out.append({"path": path, "text": FileAccess.get_file_as_string(path)})
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _initialize() -> void:
	for p in ["res://src", "res://scenes", "res://", "res://src/app", "res://src/ui"]:
		var d2 := DirAccess.open(p)
		var ok := d2 != null
		var count := -1
		var first: Array = []
		if ok:
			d2.list_dir_begin()
			var e2 := d2.get_next()
			count = 0
			while e2 != "":
				count += 1
				if first.size() < 8:
					first.append(e2)
				e2 = d2.get_next()
			d2.list_dir_end()
		print(
			(
				"PROBE %s open_ok=%s entries=%d first=%s err=%s"
				% [p, ok, count, first, DirAccess.get_open_error()]
			)
		)
	var sources: Array[Dictionary] = []
	for root in PROGRAM_ROOTS:
		sources.append_array(_source_texts(root))
	var paths: Array = []
	for entry in sources:
		paths.append(entry["path"])
	paths.sort()
	print("PROBE scanned file count: ", paths.size())
	print("PROBE first 30: ", paths.slice(0, 30))
	var app_hits := 0
	for entry in sources:
		if (entry["path"] as String).ends_with("app/screen_routes.gd"):
			app_hits += 1
			print("PROBE routes found, len: ", (entry["text"] as String).length())
			print(
				"PROBE routes contains qi scene: ",
				(entry["text"] as String).contains("qi_cultivation_screen.tscn")
			)
	print("PROBE app/screen_routes.gd hits: ", app_hits)
	var dir := DirAccess.open(SCREENS_DIR)
	var screens: Array = []
	dir.list_dir_begin()
	var e := dir.get_next()
	while e != "":
		if e.ends_with(".tscn"):
			screens.append(e)
		e = dir.get_next()
	dir.list_dir_end()
	screens.sort()
	print("PROBE screens: ", screens)
	for s in screens:
		var found := false
		for entry in sources:
			if (entry["text"] as String).contains(String(s)):
				found = true
				break
		print("PROBE   %s referenced=%s" % [s, found])
	quit(0)
