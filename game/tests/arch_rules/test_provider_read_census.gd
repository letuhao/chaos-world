extends TestCase

## BL-0833: the nine provider-published stat ids are READ by production code, not only
## published.
##
## `ActorFactory` mounts `InsideWorldProvider`, `WorldCreationProvider` and
## `AscensionProvider` on EVERY actor so the ids answer a value rather than a missing
## key. That is deliberate — but a stat every actor carries and no code reads is dead
## weight, and the owner's ruling named the surface each family feeds:
##
##   - `inside_world_size` / `inside_world_stability` / `inside_world_qi_density` /
##     `inside_world_time_flow` -> the mind screen's world/anchor row;
##   - `world_size` / `world_stability` -> the venture/domain surface;
##   - `ascension_stage` / `ascension_dao_level` / `ascension_complete` -> the
##     breakthrough preview's tier-gate block.
##
## WHY SOURCE TEXT. The ids are `StringName` literals at every call site — there are no
## `Stat` constants for the three provider families — so the file text IS the call. A
## rename or a deleted read turns this red rather than silently re-orphaning the id: the
## shape `test_fact_ledger_writers.gd` pins for the fact ledger, one layer down.
##
## NOT VACUOUS: each entry names the file the RULING named, so a reader that moved to
## another file (or a copy pasted into a second one) shows up in the diff that would edit
## this table, instead of being absorbed by a `contains` over the whole tree.

const READERS := {
	&"inside_world_size": "res://src/ui/screens/mind_cultivation_screen.gd",
	&"inside_world_stability": "res://src/ui/screens/mind_cultivation_screen.gd",
	&"inside_world_qi_density": "res://src/ui/screens/mind_cultivation_screen.gd",
	&"inside_world_time_flow": "res://src/ui/screens/mind_cultivation_screen.gd",
	&"world_size": "res://src/ui/screens/venture_screen.gd",
	&"world_stability": "res://src/ui/screens/venture_screen.gd",
	&"ascension_stage": "res://src/modules/qi_cultivation/breakthrough_transaction.gd",
	&"ascension_dao_level": "res://src/modules/qi_cultivation/breakthrough_transaction.gd",
	&"ascension_complete": "res://src/modules/qi_cultivation/breakthrough_transaction.gd",
}


func test_every_provider_id_is_read_by_its_ruled_surface() -> void:
	for id in READERS.keys():
		var path := String(READERS[id])
		assert_eq(FileAccess.file_exists(path), true, "%s exists" % path)
		var source := FileAccess.get_file_as_string(path)
		assert_eq(source.contains(String(id)), true, "%s reads %s" % [path, String(id)])
