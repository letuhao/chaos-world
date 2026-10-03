extends TestCase

## **A cache here is free to be wrong** (BL-0199).
##
## `RelationsApi.shared` is an opt-in memo and never a source. The whole property is
## one inequality: **wipe the cache and `graph()` returns the IDENTICAL dictionary.**
## A cache whose loss changed an answer would be a cache every call site had to
## defend against, which is a cache with no benefit — and the graph is cheap enough
## to rebuild that the honest answer is to have no cache at all and keep the memo as
## a convenience for a caller that wants one.
##
## These cases are written so that adding an invalidation bug — a stale entry
## surviving a write, an epoch that increments on a read, a memo that is consulted
## before it is filled — turns something red rather than silently changing a number.


## The graph read through the memo, and the graph read with no memo at all.
func _fresh() -> Dictionary:
	RelationsApi.shared = null
	RelationsApi._memo = {}
	return RelationsApi.graph()


func test_no_memo_and_a_memo_return_the_identical_dictionary() -> void:
	var cold := _fresh()
	RelationsApi.shared = RelationsApi.new()
	var warm := RelationsApi.graph()
	assert_eq(warm, cold, "taking the memo changes nothing a caller can observe")
	# And the memo was actually filled, so the previous line is not comparing a
	# filled cache against an empty one by accident.
	assert_eq(RelationsApi._memo.size(), cold.size(), "and the memo holds the same rows")
	assert_ne(cold.size(), 0, "the graph is not empty, so this is a real comparison")


func test_wiping_the_memo_returns_the_identical_dictionary_including_the_epoch() -> void:
	RelationsApi.shared = RelationsApi.new()
	var before := RelationsApi.graph()
	RelationsApi.shared = null
	RelationsApi._memo = {}
	var after := RelationsApi.graph()
	assert_eq(after, before, "a wiped cache is indistinguishable from a warm one")
	# The epoch is the field that would drift if the graph owned a clock, so it is
	# compared explicitly rather than left to the dictionary equality above.
	for key in before.keys():
		assert_eq(
			int((after[key] as Dictionary)["epoch"]),
			int((before[key] as Dictionary)["epoch"]),
			"'%s' was read at the same epoch after the wipe" % key,
		)


## A write the owner makes is visible on the very next read, whether or not a memo
## was taken. This is the case that separates "free to be wrong" from "wrong and
## nobody notices": a cache that survived a write would still be *consistent with
## itself*, and only an observation against the owner would catch it.
func test_a_stance_the_owner_writes_appears_on_the_next_read_through_a_warm_memo() -> void:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, &"t_march", "polity_a")
	var key := "nation:t_court|nation:t_march"

	# Cold first: nothing has been declared yet.
	assert_eq(_fresh().has(key), false, "no stance has been declared")

	# Take a memo over that empty answer, then write through the OWNER — never
	# through this module, which has no verb that writes.
	RelationsApi.shared = RelationsApi.new()
	RelationsApi.graph()
	assert_eq(RelationsApi.graph().has(key), false, "and the memo agrees it is absent")

	NationApi.set_stance(actor, &"t_court", &"rival")
	assert_eq(
		RelationsApi.graph().has(key),
		true,
		"the owner's write is visible even through a memo taken before it",
	)


## The memo is handed out as a COPY. A caller mutating what it was given must not be
## able to write back into the cache, which would make the cache authoritative over
## the owners — the exact inversion this module refuses to exist.
func test_a_caller_mutating_the_graph_it_was_given_cannot_write_back_into_the_cache() -> void:
	RelationsApi.shared = RelationsApi.new()
	var borrowed := RelationsApi.graph()
	borrowed.clear()
	assert_ne(
		(RelationsApi.graph() as Dictionary).size(),
		0,
		"emptying the borrowed dictionary left the cache alone",
	)
	assert_eq(borrowed.size(), 0, "and the caller's own copy is genuinely its own")


## With no memo in play the facade still answers, and `shared` staying `null` is the
## default rather than something a caller must opt out of.
func test_a_process_that_never_asks_for_a_memo_mints_none() -> void:
	RelationsApi.shared = null
	RelationsApi._memo = {}
	assert_eq(RelationsApi.shared, null, "no memo is created by asking a question")
	var read := RelationsApi.summary()
	assert_eq(bool(read["has_actor"]), false, "and the read model answers without one")
	assert_eq(
		int(read["edge_count"]),
		(RelationsApi.graph() as Dictionary).size(),
		"reporting the same edges a direct read does",
	)
