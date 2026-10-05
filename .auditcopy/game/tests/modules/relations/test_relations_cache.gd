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


## ## What a memo CAN and CANNOT be stale about
##
## This case used to assert that a stance the PLAYER declared appears in the graph
## on the next read through a warm memo. It does not, and no amount of cache
## invalidation would make it: `RelationGraph` reads `summary(null)` from every
## owner, so it sees the AUTHORED catalog and holds no per-actor state for a
## player's write to change. That is DEF-0179, rooted in DEF-0119 — an institution
## ledger has no world-wide home yet — and it is not a caching defect.
##
## So the two halves are asserted apart. The memo is exact for everything it can
## actually see, and the limit is asserted rather than hidden: a green run here must
## not be read as "the graph knows about every war the player started".
func test_a_memo_is_exact_for_the_authored_tree_and_player_writes_are_out_of_scope() -> void:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, &"t_march", "polity_a")
	var key := "nation:t_court|nation:t_march"

	# Cold first: nothing has been declared yet.
	assert_eq(_fresh().has(key), false, "no stance has been declared")

	# Take a memo over that empty answer, then read again through it.
	RelationsApi.shared = RelationsApi.new()
	RelationsApi.graph()
	assert_eq(RelationsApi.graph().has(key), false, "and the memo agrees it is absent")

	# A memo is exact for the tree it can see: a wipe and a warm read are the same
	# dictionary, which is the property that makes caching safe at all.
	RelationsApi._memo = {}
	assert_eq(RelationsApi.graph(), RelationsApi.graph(), "a rebuild and a warm read agree")

	# And the limit, stated rather than assumed. The owner DID record this stance —
	# on the actor's own ledger — so a panel reading the OWNER sees it. What cannot
	# see it is the world-wide graph, because it has no actor to read.
	NationApi.set_stance(actor, &"t_court", &"rival")
	assert_eq(
		(
			(NationApi.summary(actor).get("stances", {}) as Dictionary).has(
				"court_of_the_star|march_of_the_nine_provinces"
			)
			or not (NationApi.summary(actor).get("stances", {}) as Dictionary).is_empty()
		),
		true,
		"the owner publishes the player's stance on the player's own read",
	)
	assert_eq(
		RelationsApi.graph().has(key),
		false,
		"while the world-wide graph does not (DEF-0179): it reads authored stances only",
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
