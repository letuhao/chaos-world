extends TestCase

## ADR 0037 / DEF-0053: `Actor.SCHEMA_VERSION` is not write-only. A payload
## written by an older build must load, must not invent state it never had, and
## must re-save at the current version.
##
## The fixture at res://tests/fixtures/save_v2.json is a real v2 payload: it has
## no `sea` (added in v3) and no `mind_attempt` (added in v4). Both omissions are
## load-bearing, so the file is checked in rather than built by the test --
## a hand-built dictionary cannot prove that a real old save is still readable.

const FIXTURE := "res://tests/fixtures/save_v2.json"


func _legacy() -> Dictionary:
	var exists := FileAccess.file_exists(FIXTURE)
	assert_eq(exists, true, "the v2 fixture ships with the repo")
	if not exists:
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if typeof(parsed) != TYPE_DICTIONARY:
		assert_eq(typeof(parsed), TYPE_DICTIONARY, "the v2 fixture is a JSON object")
		return {}
	return parsed as Dictionary


func test_fixture_is_a_genuine_v2_payload() -> void:
	var data := _legacy()
	assert_eq(int(data.get("version", 0)), 2, "declares version 2")
	# The two slots that did not exist yet. If either appears, the fixture has
	# been edited into a later shape and stops proving anything about v2.
	assert_eq(data.has("sea"), false, "v2 predates the sea slot")
	assert_eq(data.has("mind_attempt"), false, "v2 predates the attempt slot")


func test_v2_loads_without_inventing_later_state() -> void:
	var actor := Actor.from_dict(_legacy())
	assert_eq(actor.id, &"legacy_warden", "identity restored")
	assert_eq(actor.display_name, "Warden of the Old Compact", "name restored")
	assert_eq(actor.stats.get_base(Stat.WILL), 30.0, "base stats restored")
	assert_eq(actor.path(&"qi").rank_id, &"core_formation", "qi path restored")
	assert_eq(actor.path(&"qi").stage, 2, "qi stage restored")
	assert_eq(actor.path(&"mind").progress, 12.5, "mind progress restored")
	# Absent means "never had one", never "start empty and call it progress".
	assert_eq(actor.component(&"sea_of_consciousness"), null, "no sea invented")
	assert_eq(actor.get_module_data(&"mind_attempt").is_empty(), true, "no attempt invented")


func test_v2_resaves_at_the_current_version() -> void:
	var actor := Actor.from_dict(_legacy())
	var resaved := actor.to_dict()
	assert_eq(
		int(resaved.get("version", 0)), Actor.SCHEMA_VERSION, "re-saving upgrades the payload"
	)
	# And the upgraded payload round-trips without losing the old content.
	var again := Actor.from_dict(resaved)
	assert_eq(again.path(&"qi").rank_id, &"core_formation", "still restored after upgrade")
	assert_eq(again.stats.get_base(Stat.WILL), 30.0, "stats survive the upgrade")


## A current save must still load, so the dispatch did not become a v2-only path.
func test_current_payload_still_loads() -> void:
	var actor := Actor.new(&"modern", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored.path(&"qi").rank_id, &"qi_refining", "path restored")
	assert_eq(int(actor.to_dict().get("version", 0)), Actor.SCHEMA_VERSION, "declares v4")
