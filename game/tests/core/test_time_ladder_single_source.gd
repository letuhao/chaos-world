extends "res://tests/core/time_ladder_ssot_base.gd"


## ADR 0173: THE TREE CENSUS HALF of the single-source guard.
##
## ## Why this file is a THIN suite over [code]time_ladder_ssot_base.gd[/code]
##
## The vocabulary — the `const` tables, the `_code_only` stripper and every classifier —
## is ONE copy in the base, which this suite `extends`. A second copy of the classifier
## would drift from the census and the drift would be invisible: both suites would still
## be green against their own private rule. So this file declares NO constant and NO
## helper; it inherits them and owns only the tests that walk the REAL tree.
##
## **This file used to be a byte-for-byte copy of the base** — same constants, same
## helpers, same four tests — which GDScript rejects outright: `The member "SRC_ROOT"
## already exists in parent class`. It therefore never loaded, and the guard it was
## named for was not running at all. The census it was supposed to own lives in
## `test_time_ladder_ssot_shapes.gd` and runs there; duplicating it would have bought
## no coverage and cost the second suite entirely.
##
## ## What still has to be proven HERE, and is inherited rather than rewritten
##
## [method test_no_file_but_the_ladder_declares_a_time_constant],
## [method test_the_wall_clock_is_read_only_as_the_named_idempotency_stamp],
## [method test_the_exempted_ssot_really_declares_the_ratio] and
## [method test_the_walk_actually_reads_the_tree_it_guards] all read the shipped tree,
## and they are inherited — so running this suite is running them. Nothing was weakened
## to make this file parse: the rules, the vocabularies and the census are unchanged,
## and the only edit is that a suite which could not load now can.
func test_this_suite_reads_the_shipped_tree_and_not_a_fixture() -> void:
	# The inheritance itself is the assertion, and it is the one that had gone missing:
	# a suite that redeclares its base's members cannot load, so its tests never ran.
	# Asserting the inherited constant is what this file reads proves the split the
	# shapes suite's docstring describes — shared vocabulary, one copy — is still the
	# arrangement, and that this suite is a child rather than a second copy.
	assert_eq(
		_source_files(SRC_ROOT).size() >= SRC_FILE_FLOOR,
		true,
		"the inherited walk still reads the tree this suite guards"
	)
	assert_eq(
		SSOT,
		"res://src/core/time_ladder.gd",
		"and the inherited SSOT is the one file the guard exempts (ADR 0173)"
	)
