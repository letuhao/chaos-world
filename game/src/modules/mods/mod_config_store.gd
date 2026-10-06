class_name ModConfigStore
extends RefCounted

## Persists mod configuration to `user://mods/<mod_id>/config.json`.
##
## Config is loaded at boot before mods are attached, and saved whenever
## `set_config` is called. The store validates values against the manifest's
## config schema: an unknown key is refused, and a value that does not match
## the declared type is refused.
##
## The store is deliberately simple: one JSON file per mod, no locking, no
## atomic rename. A mod's config is small and written rarely, so the
## complexity of atomic writes is not warranted.

## The directory under which per-mod config files live.
const CONFIG_DIR := "user://mods"


## The config file path for a given mod id.
static func path_for(mod_id: String) -> String:
	return CONFIG_DIR.path_join(mod_id).path_join("config.json")


## Load a mod's config from disk, merged over the schema defaults.
## Returns `{ok, reason, detail, values}` where `values` is a Dictionary
## keyed by config key. On failure `values` is empty.
static func load(mod_id: String, schema: Array) -> Dictionary:
	var path := path_for(mod_id)
	if not FileAccess.file_exists(path):
		return {"ok": true, "reason": "", "detail": "", "values": _defaults(schema)}
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(path)
	if json.parse(text) != OK:
		return {
			"ok": false,
			"reason": "bad_config_file",
			"detail": "%s: %s" % [path, json.get_error_message()],
			"values": {},
		}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"reason": "bad_config_file",
			"detail": "%s: top level must be an object" % path,
			"values": {},
		}
	var values := _defaults(schema)
	var raw: Dictionary = json.data
	for key in raw:
		if not _has_key(schema, String(key)):
			return {
				"ok": false,
				"reason": "unknown_config_key",
				"detail": "%s: '%s' is not declared in the manifest" % [path, String(key)],
				"values": {},
			}
		values[String(key)] = raw[key]
	return {"ok": true, "reason": "", "detail": "", "values": values}


## Save a mod's config values to disk. Creates the directory if needed.
static func save(mod_id: String, values: Dictionary) -> Dictionary:
	var dir := CONFIG_DIR.path_join(mod_id)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var path := path_for(mod_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"reason": "config_write_failed",
			"detail": "%s: could not open for writing" % path,
		}
	file.store_string(JSON.stringify(values))
	file.close()
	return {"ok": true, "reason": "", "detail": ""}


## Build a defaults dictionary from the schema.
static func _defaults(schema: Array) -> Dictionary:
	var out := {}
	for entry in schema:
		out[String(entry["key"])] = entry.get("default", null)
	return out


## Whether the schema declares a given key.
static func _has_key(schema: Array, key: String) -> bool:
	for entry in schema:
		if String(entry["key"]) == key:
			return true
	return false
