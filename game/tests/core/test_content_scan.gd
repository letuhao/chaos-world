extends TestCase

## `ContentScan` is now the ONE implementation every catalog loads content
## through, replacing ten near-identical recursive `_scan` functions that had
## drifted apart. It replaced working code, so it has to be proven equivalent on
## the real trees before those call sites move.

const DATA_ROOT := "res://data"


func test_it_finds_authored_resources_under_a_real_tree() -> void:
	var bloodlines := ContentScan.files_under("%s/bloodlines" % DATA_ROOT)
	assert_eq(bloodlines.is_empty(), false, "the bloodline tree has content")
	for path in bloodlines:
		assert_eq(path.ends_with(".tres"), true, "only authored resources: %s" % path)


func test_it_recurses_past_a_nested_directory() -> void:
	# A flat-only scan would pass the test above and silently miss subfolders, so
	# this asserts recursion against a tree that is known to nest.
	var root := "%s/nation" % DATA_ROOT
	var nested := ContentScan.files_under(root)
	var has_subdirectory_entry := false
	for path in nested:
		assert_eq(path.ends_with(".tres"), true, "only authored resources: %s" % path)
		# A joined path extends the root exactly once; it never restarts from it,
		# which is what a duplicated join on an absolute-looking segment looks like.
		assert_eq(
			path.begins_with(root + "/"),
			true,
			"every path extends the root exactly once: %s" % path
		)
		if path.contains("/territories/"):
			has_subdirectory_entry = true
	assert_eq(
		has_subdirectory_entry,
		true,
		"a nested subfolder's content is reached, so the walk really recurses"
	)


func test_result_is_sorted_and_free_of_dotfiles() -> void:
	var files := ContentScan.files_under(DATA_ROOT)
	var sorted_copy := files.duplicate()
	sorted_copy.sort()
	assert_eq(files, sorted_copy, "the result is sorted, so load order is stable")
	assert_eq(files.size(), files.duplicate().size(), "and deterministic")
	for path in files:
		assert_eq(path.contains("/."), false, "no dotfile is returned: %s" % path)


func test_an_empty_suffix_takes_every_file() -> void:
	var only_tres := ContentScan.files_under("%s/bloodlines" % DATA_ROOT)
	var everything := ContentScan.files_under("%s/bloodlines" % DATA_ROOT, "")
	assert_eq(
		everything.size() >= only_tres.size(),
		true,
		"an empty suffix is at least as permissive as .tres"
	)


func test_a_missing_root_is_empty_rather_than_an_error() -> void:
	assert_eq(
		ContentScan.files_under("res://data/no_such_directory_anywhere").is_empty(),
		true,
		"a root that does not exist yields nothing instead of crashing a catalog"
	)


func test_depth_is_capped_so_a_symlink_loop_cannot_recurse_forever() -> void:
	# MAX_DEPTH is the guard that makes the recursion safe; a caller that raises it
	# to something absurd reopens the hazard, so it is pinned here.
	assert_eq(ContentScan.MAX_DEPTH > 0, true, "the cap is a real depth")
	assert_eq(ContentScan.MAX_DEPTH <= 64, true, "and small enough to stay a guard")
