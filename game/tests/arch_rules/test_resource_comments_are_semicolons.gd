extends TestCase

## Godot's text-resource comment marker is `;`, NOT `#`.
##
## A `#` line reads as a comment to a human but not to `ResourceLoaderText`: the property
## assignment following a `#` comment block loads as the export's DEFAULT. Nothing errors
## and nothing logs, so a dropped property is invisible until a gate downstream notices.
##
## Measured 2026-10-07 with minimal probes: one `#` line before `ambient = true` loads
## `ambient == false`; a block before `mitigation_tags` loads `[]`. Forty shipped `.tres`
## files carried the shape. The nine status-side files were converted the same day — the
## eight age statuses had lost `ambient`, `mitigation_tags` and `payload` and were being
## refused by the status catalogue (986/0 after the fix). The other thirty-one are listed
## in [constant KNOWN] and tracked by DEF-0355: converting them restores real content that
## un-hides gaps needing content-or-test decisions, so they are exempt here while the list
## can only ever SHRINK. A file not on the list may never carry a `#` comment.

const ROOTS: Array[String] = ["res://data", "res://src", "res://tests"]
const SUFFIXES: Array[String] = [".tres", ".tscn"]

## The files still carrying `#` comments, known and tracked (DEF-0355). Convert one, delete
## its line here in the same change: `test_the_known_list_only_ever_shrinks` fails on a
## stale entry, and `test_no_resource_file_gains_a_hash_comment` fails on a new offender.
const KNOWN: Array[String] = [
	"res://data/body_cultivation/weapons/weapon_greatsword.tres",
	"res://data/bosses/qi_body_integration_warden.tres",
	"res://data/bosses/qi_qi_refining_warden.tres",
	"res://data/items/consumable/alchemy_clarity_pill.tres",
	"res://data/items/consumable/ash_camp_pilgrims_ration.tres",
	"res://data/items/equipment/ash_furnace_sealed_jade.tres",
	"res://data/items/equipment/flame_dragon_heart_seal.tres",
	"res://data/items/equipment/tide_vault_hoard_of_shells.tres",
	"res://data/items/key/ash_arena_formation_key.tres",
	"res://data/items/key/ash_furnace_key.tres",
	"res://data/races/commonborn.tres",
	"res://data/races/emberblood.tres",
	"res://data/races/emberblood_touched.tres",
	"res://data/races/stoneborn.tres",
	"res://data/races/tidecaller.tres",
	"res://data/recipes/ash_arena_formation_key_recipe.tres",
	"res://data/recipes/ash_furnace_key_recipe.tres",
	"res://src/data/domains/inhabitants/ember_phoenix.tres",
	"res://src/data/domains/inhabitants/flame_dragon.tres",
	"res://src/data/domains/inhabitants/frost_sentinel.tres",
	"res://src/data/domains/inhabitants/frost_wyrm.tres",
	"res://src/data/domains/inhabitants/void_leviathan.tres",
	"res://src/data/domains/templates/ember_grotto.tres",
	"res://src/data/domains/templates/flame_valley_depths.tres",
	"res://src/data/domains/templates/frozen_cavern.tres",
	"res://src/data/domains/templates/stormwrack_reach.tres",
	"res://src/data/domains/templates/sunken_ruins.tres",
]


func test_no_resource_file_gains_a_hash_comment() -> void:
	var findings: Array[String] = []
	for root in ROOTS:
		for suffix in SUFFIXES:
			for path in ContentScan.files_under(root, suffix):
				var line := _hash_line(path)
				if line > 0 and not KNOWN.has(path):
					findings.append("%s:%d" % [path, line])
	assert_eq(
		findings,
		[],
		(
			"these resource files comment with '#', which silently drops the property that"
			+ " follows it; use ';' instead: %s" % ", ".join(findings)
		)
	)


func test_the_known_list_only_ever_shrinks() -> void:
	var converted: Array[String] = []
	for path in KNOWN:
		if _hash_line(path) == 0:
			converted.append(path)
	assert_eq(
		converted,
		[],
		(
			"these files are already converted, so their KNOWN entries are stale; delete"
			+ " them in this change: %s" % ", ".join(converted)
		)
	)


## The 1-based line number of the first line that STARTS with `#`, or 0. Line-start only:
## a `#` inside a quoted value is data, never a comment.
func _hash_line(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	for index in lines.size():
		if String(lines[index]).begins_with("#"):
			return index + 1
	return 0
