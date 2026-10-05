extends TestCase

## ADR 0184's manifest schema, and the failure policy behind it: every parse
## error is a NAMED cause, so a typo aborts with "bad_priority" rather than
## silently becoming a default-numbered mod.

const VALID := """{
	"id": "demo",
	"version": "1.2.0",
	"priority": 5,
	"requires_api": 1,
	"engine_version": "4.7",
	"depends_on": [{"id": "base", "min_version": "1.0"}],
	"provides": ["demo_items"],
	"overrides": ["base"],
	"content_roots": [{"family": "items", "dir": "data/items"}],
	"modules": [{"name": "demo", "api_gd": "src/modules/demo/api.gd", "deps": ["items"]}],
	"attach_hooks": [{"phase": "economy"}],
	"screens": [{"id": "demo", "scene": "res://demo.tscn", "label": "Demo"}],
	"events": ["period"]
}"""


func test_a_full_manifest_parses_and_normalizes() -> void:
	var out := ModsApi.parse_manifest(VALID, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "scriptError-free parse")
	assert_eq(out["reason"], "", "no error on the happy path")
	var m: Dictionary = out["manifest"]
	assert_eq(m["id"], "demo", "id carried")
	assert_eq(m["version"], "1.2.0", "version carried")
	assert_eq(int(m["priority"]), 5, "priority carried")
	assert_eq(int(m["requires_api"]), 1, "requires_api carried")
	assert_eq(m["engine_version"], "4.7", "engine_version carried")
	assert_eq(m["depends_on"].size(), 1, "one dep")
	assert_eq(String(m["depends_on"][0]["id"]), "base", "dep id")
	assert_eq(String(m["depends_on"][0]["min_version"]), "1.0", "dep floor")
	assert_eq(String(m["provides"][0]), "demo_items", "provides carried")
	assert_eq(m["content_roots"].size(), 1, "one root")
	assert_eq(String(m["content_roots"][0]["family"]), "items", "root family")
	assert_eq(String(m["modules"][0]["api_gd"]), "src/modules/demo/api.gd", "module row")
	assert_eq(String(m["attach_hooks"][0]["phase"]), "economy", "hook phase")
	assert_eq(String(m["screens"][0]["scene"]), "res://demo.tscn", "screen row")
	assert_eq(String(m["events"][0]), "period", "events carried")
	assert_eq(m["root"], "user://demo", "root dir derived from the path")


func test_optional_sections_default_to_empty() -> void:
	var text := '{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1}'
	var out := ModsApi.parse_manifest(text, "user://a/mod.json")
	assert_eq(bool(out["ok"]), true, "minimal manifest parses")
	assert_eq(out["manifest"]["depends_on"].size(), 0, "no deps")
	assert_eq(out["manifest"]["content_roots"].size(), 0, "no roots")
	assert_eq(out["manifest"]["screens"].size(), 0, "no screens")
	assert_eq(out["manifest"]["events"].size(), 0, "no events")


func test_not_json_is_named() -> void:
	var out := ModsApi.parse_manifest("{nope", "user://x/mod.json")
	assert_eq(bool(out["ok"]), false, "refused")
	assert_eq(out["reason"], "not_json", "named")


func test_top_level_must_be_an_object() -> void:
	var out := ModsApi.parse_manifest("[1, 2]", "user://x/mod.json")
	assert_eq(out["reason"], "manifest_not_object", "named")


func test_a_missing_required_key_names_the_key() -> void:
	for case in [
		['{"version": "1.0", "priority": 0, "requires_api": 1}', "missing_id"],
		['{"id": "a", "priority": 0, "requires_api": 1}', "missing_version"],
		['{"id": "a", "version": "1.0", "requires_api": 1}', "missing_priority"],
		['{"id": "a", "version": "1.0", "priority": 0}', "missing_requires_api"],
	]:
		var out := ModsApi.parse_manifest(case[0], "user://x/mod.json")
		assert_eq(out["reason"], case[1], "named after the key")


func test_wrong_types_are_named() -> void:
	for case in [
		['{"id": "", "version": "1.0", "priority": 0, "requires_api": 1}', "bad_id"],
		['{"id": "a", "version": "one", "priority": 0, "requires_api": 1}', "bad_version"],
		['{"id": "a", "version": "1.0", "priority": "high", "requires_api": 1}', "bad_priority"],
		['{"id": "a", "version": "1.0", "priority": 0, "requires_api": "1"}', "bad_requires_api"],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "depends_on": {}}',
			"bad_depends_on"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "depends_on": [{}]}',
			"bad_depends_on"
		],
		[
			(
				'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1,'
				+ ' "depends_on": [{"id": "b"}, {"id": "b"}]}'
			),
			"bad_depends_on"
		],
		[
			(
				'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1,'
				+ ' "depends_on": [{"id": "b", "min_version": "x"}]}'
			),
			"bad_min_version"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "provides": "items"}',
			"bad_provides"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "content_roots": [{}]}',
			"bad_content_roots"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "modules": [{"name": "x"}]}',
			"bad_modules"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "attach_hooks": ["economy"]}',
			"bad_attach_hooks"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "screens": [{"id": "x"}]}',
			"bad_screens"
		],
		[
			'{"id": "a", "version": "1.0", "priority": 0, "requires_api": 1, "events": [1]}',
			"bad_events"
		],
	]:
		var out := ModsApi.parse_manifest(case[0], "user://x/mod.json")
		assert_eq(bool(out["ok"]), false, "case refuses: %s" % case[0])
		assert_eq(out["reason"], case[1], "named after the field")
		assert_eq(String(out["detail"]).is_empty(), false, "detail says which file")


func test_version_ordering() -> void:
	assert_eq(ModManifest.version_lt("1.0", "1.1"), true, "minor rises")
	assert_eq(ModManifest.version_lt("1.10", "1.2"), false, "integers, not strings")
	assert_eq(ModManifest.version_lt("1.0", "1.0.0"), false, "trailing zeros equal")
	assert_eq(ModManifest.version_lt("2.0", "10.0"), true, "major is numeric")
	assert_eq(ModManifest.version_lt("1.0.1", "1.0"), false, "longer with real parts is newer")
