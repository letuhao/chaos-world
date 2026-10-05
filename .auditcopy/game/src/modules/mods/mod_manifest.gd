class_name ModManifest
extends RefCounted

## Parse one mod package's `mod.json` into a normalized dictionary (ADR 0184).
##
## Every failure is a NAMED reason — the loader's failure policy is "abort with a
## named cause, never skip silently", so this file returns reasons, never
## defaults-for-missing-fields. A field that is genuinely optional keeps its
## documented default (empty array, priority 0 is NOT optional — see below).

## The fields a manifest must carry. Anything absent is an error, named after the
## field, because guessing `id` or `version` from the directory would make a
## rename indistinguishable from a different mod.
const REQUIRED_STRINGS := ["id", "version"]


## Parse `text` from `source_path`. Returns `{ok, reason, detail, manifest}`:
## on failure `reason` is the named cause and `detail` says which file and why;
## on success `manifest` is the normalized row the loader sorts and stamps.
static func parse(text: String, source_path: String = "") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("not_json", "%s: %s" % [source_path, json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("manifest_not_object", "%s: top level must be an object" % source_path)
	var raw: Dictionary = json.data
	for key in REQUIRED_STRINGS:
		if not raw.has(key):
			return _fail("missing_%s" % key, "%s: missing required key '%s'" % [source_path, key])
		if typeof(raw[key]) != TYPE_STRING or String(raw[key]).is_empty():
			return _fail("bad_%s" % key, "%s: '%s' must be a non-empty string" % [source_path, key])
	if not is_digits_and_dots(String(raw["version"])):
		return _fail("bad_version", "%s: 'version' must be dot-separated numbers" % source_path)
	if not raw.has("priority"):
		return _fail("missing_priority", "%s: missing required key 'priority'" % source_path)
	if not _is_whole_number(raw["priority"]):
		return _fail("bad_priority", "%s: 'priority' must be an integer" % source_path)
	if not raw.has("requires_api"):
		return _fail(
			"missing_requires_api", "%s: missing required key 'requires_api'" % source_path
		)
	if not _is_whole_number(raw["requires_api"]):
		return _fail("bad_requires_api", "%s: 'requires_api' must be an integer" % source_path)
	if raw.has("engine_version"):
		if typeof(raw["engine_version"]) != TYPE_STRING:
			return _fail(
				"bad_engine_version", "%s: 'engine_version' must be a string" % source_path
			)
		if not is_digits_and_dots(String(raw["engine_version"])):
			return _fail(
				"bad_engine_version",
				"%s: 'engine_version' must be dot-separated numbers" % source_path
			)
	var depends := _parse_depends_on(raw.get("depends_on", []), source_path)
	if not depends[0]:
		return depends[1]
	var provides := _parse_string_array(raw.get("provides", []), "provides", source_path)
	if not provides[0]:
		return provides[1]
	var overrides := _parse_string_array(raw.get("overrides", []), "overrides", source_path)
	if not overrides[0]:
		return overrides[1]
	var roots := _parse_content_roots(raw.get("content_roots", []), source_path)
	if not roots[0]:
		return roots[1]
	var modules := _parse_modules(raw.get("modules", []), source_path)
	if not modules[0]:
		return modules[1]
	var hooks := _parse_attach_hooks(raw.get("attach_hooks", []), source_path)
	if not hooks[0]:
		return hooks[1]
	var screens := _parse_screens(raw.get("screens", []), source_path)
	if not screens[0]:
		return screens[1]
	var events := _parse_string_array(raw.get("events", []), "events", source_path)
	if not events[0]:
		return events[1]
	return {
		"ok": true,
		"reason": "",
		"detail": "",
		"manifest":
		{
			"id": String(raw["id"]),
			"version": String(raw["version"]),
			"priority": int(raw["priority"]),
			"requires_api": int(raw["requires_api"]),
			"engine_version": String(raw.get("engine_version", "")),
			"depends_on": depends[1],
			"provides": provides[1],
			"overrides": overrides[1],
			"content_roots": roots[1],
			"modules": modules[1],
			"attach_hooks": hooks[1],
			"screens": screens[1],
			"events": events[1],
			"path": source_path,
			"root": source_path.get_base_dir(),
		},
	}


## `"a" < "b"` over dot-separated integer parts. `int("abc")` returns 0 in
## GDScript, so the format was validated by `is_digits_and_dots` before this is
## ever called — a non-numeric manifest fails at parse, not here.
static func version_lt(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	var count := mini(pa.size(), pb.size())
	for i in range(count):
		var x := int(pa[i])
		var y := int(pb[i])
		if x != y:
			return x < y
	# The longer dotted form is newer only when its extra parts are non-zero
	# ("1.0" and "1.0.0" compare equal).
	for i in range(count, pa.size()):
		if int(pa[i]) != 0:
			return false
	for i in range(count, pb.size()):
		if int(pb[i]) != 0:
			return true
	return false


static func is_digits_and_dots(version: String) -> bool:
	if version.is_empty():
		return false
	for part in version.split("."):
		if part.is_empty():
			return false
		for character in part:
			if character < "0" or character > "9":
				return false
	return true


## JSON may deliver an integer literal as int or float depending on the
## engine version; both are accepted, 5.0 and 5 are the same integer.
static func _is_whole_number(value) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var as_float := float(value)
		return is_finite(as_float) and as_float == floor(as_float)
	return false


static func _fail(reason: String, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail, "manifest": {}}


## Each helper returns `[true, parsed]` on success and `[false, fail_dict]` on a
## named error — the caller treats a Dictionary-shaped second slot accordingly.
static func _parse_depends_on(value, source_path: String) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return [false, _fail("bad_depends_on", "%s: 'depends_on' must be an array" % source_path)]
	var out: Array[Dictionary] = []
	var seen := {}
	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY:
			return [
				false,
				_fail("bad_depends_on", "%s: a 'depends_on' entry must be an object" % source_path)
			]
		if typeof(entry.get("id", null)) != TYPE_STRING or String(entry["id"]).is_empty():
			return [
				false,
				_fail(
					"bad_depends_on",
					"%s: a 'depends_on' entry needs a non-empty 'id'" % source_path
				)
			]
		var dep_id := String(entry["id"])
		if seen.has(dep_id):
			return [
				false,
				_fail(
					"bad_depends_on",
					"%s: '%s' is listed twice in 'depends_on'" % [source_path, dep_id]
				)
			]
		seen[dep_id] = true
		var row := {"id": dep_id}
		if entry.has("min_version"):
			if (
				typeof(entry["min_version"]) != TYPE_STRING
				or not is_digits_and_dots(String(entry["min_version"]))
			):
				return [
					false,
					_fail(
						"bad_min_version",
						"%s: '%s.min_version' is not a dotted number" % [source_path, dep_id]
					)
				]
			row["min_version"] = String(entry["min_version"])
		out.append(row)
	return [true, out]


static func _parse_string_array(value, field: String, source_path: String) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return [false, _fail("bad_%s" % field, "%s: '%s' must be an array" % [source_path, field])]
	var out: Array[String] = []
	for entry in value:
		if typeof(entry) != TYPE_STRING:
			return [
				false,
				_fail(
					"bad_%s" % field, "%s: every '%s' entry must be a string" % [source_path, field]
				)
			]
		out.append(String(entry))
	return [true, out]


static func _parse_content_roots(value, source_path: String) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return [
			false,
			_fail("bad_content_roots", "%s: 'content_roots' must be an array" % source_path),
		]
	var out: Array[Dictionary] = []
	for entry in value:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or typeof(entry.get("family", null)) != TYPE_STRING
			or typeof(entry.get("dir", null)) != TYPE_STRING
		):
			return [
				false,
				_fail(
					"bad_content_roots",
					"%s: a 'content_roots' entry needs string 'family' and 'dir'" % source_path
				),
			]
		var id_field := "id"
		if entry.has("id_field") and typeof(entry["id_field"]) == TYPE_STRING:
			id_field = String(entry["id_field"])
		out.append(
			{"family": String(entry["family"]), "dir": String(entry["dir"]), "id_field": id_field}
		)
	return [true, out]


static func _parse_modules(value, source_path: String) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return [false, _fail("bad_modules", "%s: 'modules' must be an array" % source_path)]
	var out: Array[Dictionary] = []
	for entry in value:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or typeof(entry.get("name", null)) != TYPE_STRING
			or typeof(entry.get("api_gd", null)) != TYPE_STRING
		):
			return [
				false,
				_fail(
					"bad_modules",
					"%s: a 'modules' entry needs string 'name' and 'api_gd'" % source_path
				),
			]
		var deps := _parse_string_array(entry.get("deps", []), "modules.deps", source_path)
		if not deps[0]:
			return [false, deps[1]]
		var provides := _parse_string_array(
			entry.get("provides", []), "modules.provides", source_path
		)
		if not provides[0]:
			return [false, provides[1]]
		var seed_dir := ""
		if entry.has("seed_dir"):
			if typeof(entry["seed_dir"]) != TYPE_STRING:
				return [
					false,
					_fail(
						"bad_modules",
						"%s: a 'modules' entry 'seed_dir' must be a string" % source_path
					),
				]
			seed_dir = String(entry["seed_dir"])
		(
			out
			. append(
				{
					"name": String(entry["name"]),
					"api_gd": String(entry["api_gd"]),
					"deps": deps[1],
					"provides": provides[1],
					"seed_dir": seed_dir,
				}
			)
		)
	return [true, out]


static func _parse_attach_hooks(value, source_path: String) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return [
			false, _fail("bad_attach_hooks", "%s: 'attach_hooks' must be an array" % source_path)
		]
	var out: Array[Dictionary] = []
	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("phase", null)) != TYPE_STRING:
			return [
				false,
				_fail(
					"bad_attach_hooks",
					"%s: an 'attach_hooks' entry needs a string 'phase'" % source_path
				),
			]
		var row := {"phase": String(entry["phase"])}
		if entry.has("callable"):
			if typeof(entry["callable"]) != TYPE_STRING or String(entry["callable"]).is_empty():
				return [
					false,
					_fail(
						"bad_attach_hooks",
						"%s: an 'attach_hooks' 'callable' must be a non-empty string" % source_path
					),
				]
			row["callable"] = String(entry["callable"])
		out.append(row)
	return [true, out]


static func _parse_screens(value, source_path: String) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return [false, _fail("bad_screens", "%s: 'screens' must be an array" % source_path)]
	var out: Array[Dictionary] = []
	for entry in value:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or typeof(entry.get("id", null)) != TYPE_STRING
			or typeof(entry.get("scene", null)) != TYPE_STRING
		):
			return [
				false,
				_fail(
					"bad_screens",
					"%s: a 'screens' entry needs string 'id' and 'scene'" % source_path
				),
			]
		out.append(
			{
				"id": String(entry["id"]),
				"scene": String(entry["scene"]),
				"label": String(entry.get("label", ""))
			}
		)
	return [true, out]
