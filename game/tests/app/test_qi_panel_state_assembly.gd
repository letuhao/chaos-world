extends TestCase

## `QiCultivationApi.panel_state` is the WHOLE read model for the qi panel
## (`ui/screens/qi_cultivation_screen.gd` reads it at three call sites) and no
## test named it.
##
## ## Why the existing qi suites did not catch it
##
## `modules/qi_cultivation/*` proves the ARITHMETIC — dantian, channels,
## breakthrough chance, the realm seed — by reading `QiTraining`,
## `QiBreakthroughTransaction` and the seed directly. `panel_state` is the verb
## that ASSEMBLES those answers into the row a screen renders, and it
## re-derives three things itself: the realm gate's required channel list, the
## `id:state/refinement!` channel strings, and the dantian/pool split. A
## mis-wired key there is invisible to every suite that reads the parts.
##
## This suite asserts the ASSEMBLY, through the facade, with a real actor whose
## channel and pool state it controls.
##
## ## Why it lives in `tests/app` and not `tests/modules/qi_cultivation`
##
## The gap it closes is a WIRING one — `ui/` renders `panel_state` and nothing
## asserted the row — so it belongs with the other production-wiring suites
## (`test_combat_boot`, `test_body_cultivation_reachability`) rather than in the
## module's arithmetic suites, which read the parts and pass regardless.

const LUNG := &"lung"


## One actor, re-seated on each realm in turn rather than minted per boundary: the
## published gate is a pure function of `state.rank_id`
## (`QiCultivationApi._gate_for_next_realm`), so 29 factories would buy nothing and
## `Actor` is `RefCounted` — one body, no per-iteration node to free.
##
## A factory actor: `panel_state` reads `actor.resource(QI)`, and a bare
## `Actor.new` carries no pool, so the qi columns would be 0.0 for a reason
## that has nothing to do with the verb.
func _actor() -> Actor:
	# `attach` enrols the provider and the dantian but does NOT enrol a PATH:
	# `panel_state` opens with `actor.path(QiPath.PATH_ID)` and answers `{}`
	# without one. The rung is read from the ladder rather than written as a
	# literal, so an inserted realm moves the fixture with it (the coupling
	# `modules/qi_cultivation/test_qi_realm_seed.gd` also avoids).
	var actor := (
		ActorFactory
		. build(
			&"qi_panel_reader",
			{
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				QiStats.QI_AFFINITY: 20.0,
				QiStats.QI_CONTROL: 15.0,
				QiStats.DANTIAN_CAPACITY: 30.0,
			}
		)
	)
	QiCultivationApi.attach(actor)
	actor.set_path(PathState.new(QiPath.PATH_ID, RealmDefaults.ladder().realms()[0].id))
	return actor


## The same actor, standing in `realm_id` instead. One body re-seated, never one
## per realm: `set_path` is the only state the published gate reads.
func _seated(actor: Actor, realm_id: StringName) -> Actor:
	actor.set_path(PathState.new(QiPath.PATH_ID, realm_id))
	return actor


## An actor with no path is the `{}` case the screen branches on, so it is a
## contract rather than an accident: a panel indexing the result must not crash
## on a body that has not started cultivating.
func test_an_actor_with_no_qi_path_reads_as_empty() -> void:
	var actor := ActorFactory.build(&"no_path")
	assert_eq(QiCultivationApi.panel_state(actor), {}, "no path, nothing for a panel to render")


## The qi columns must come from the actor's OWN pool, which is the one place
## current/capacity live (the dantian contributes quality/injury only — its tier
## was deleted, ADR 0180: a three-band ladder nothing gated on).
## Asserted against the pool rather than a literal, so the test states where the
## number comes from instead of restating a number that would drift.
func test_the_qi_columns_are_the_actors_own_pool() -> void:
	var actor := _actor()
	var pool := actor.resource(QiCultivationApi.QI)
	var live := QiCultivationApi.panel_state(actor)
	assert_eq(float(live.get("qi", -1.0)), pool.current, "current qi is the pool's")
	assert_eq(float(live.get("qi_maximum", -1.0)), pool.maximum, "capacity qi is the pool's")
	assert_ne(float(live.get("qi_maximum", 0.0)), 0.0, "the fixture's pool is real, not zeroed")


## The channel list is built here, in the facade, from the actor's meridian
## network — no module does it. The `!` injury marker is the part a panel would
## silently drop, so a row that trains a channel and is injured must carry it.
func test_a_channel_row_carries_state_depth_and_the_injury_marker() -> void:
	var actor := _actor()
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(LUNG)
	actor.meridians.expand_meridian(LUNG)
	actor.meridians.strengthen_meridian(LUNG)
	var channels: Array = QiCultivationApi.panel_state(actor).get("channels", []) as Array
	assert_ne(channels.size(), 0, "the fixture trained a channel, so one is listed")
	var row := String(channels[0])
	assert_eq(row.begins_with("%s:" % LUNG), true, "the row is keyed by channel id")
	assert_eq(row.contains("!"), false, "an uninjured channel carries no marker")

	actor.meridians.damage_meridian(LUNG)
	var hurt: Array = QiCultivationApi.panel_state(actor).get("channels", []) as Array
	assert_eq(
		String(hurt[0]).ends_with("!"),
		true,
		"an injured channel is marked, which is the one glyph a panel would otherwise drop"
	)


## The gate's required channels are published HERE so a screen can offer the
## training action without reaching for the realm seed (ADR 0043).
##
## ## Why this test was rewritten (BL-0785): it proved NOTHING
##
## It built its expectation from `QiRealmSeed.for_realm(panel_state.realm)` — the
## STANDING realm — and compared it against a `panel_state` that, since ADR 0164,
## reports the NEXT realm's gate. The fixture sat at ladder index 0, and
## `foundation.tres` and `qi_refining.tres` agree on all three asserted fields
## (4 channels, `open`, depth 0), so it passed whether or not the defect was
## present: a straight regression back to the ADR 0158 bug was green.
##
## A test named for a claim that cannot fail is the defect class, so two things are
## asserted now that were not:
##
## 1. **The expectation is the NEXT realm's seed**, which is what `panel_state`
##    documents it reads (`api.gd:_gate_for_next_realm`), and the whole ladder is
##    walked rather than its first rung.
## 2. **The suite asserts its own discriminating power**: at least one boundary
##    must exist where the standing realm's gate and the next realm's DIFFER. That
##    assertion is what stops a future seed edit from silently returning this to the
##    vacuous shape it just had — the fixture cannot quietly stop being able to fail.
##
## It also covers the channel LIST, which
## `tests/modules/qi_cultivation/test_qi_gate_reported_is_gate_enforced.gd` does
## not: that suite asserts state and depth at every boundary and never the ids,
## and `required_channels` is the list a screen iterates to offer the training.
func test_the_realm_gate_is_published_for_the_panel_to_offer() -> void:
	var realms := RealmDefaults.ladder().realms()
	var actor := _actor()
	var checked := 0
	var discriminating := 0
	# Bounded by the ladder's own fixed length (`range` over a snapshot, never a
	# `while` on a container this loop grows), and neither loop appends into the
	# list it walks. The inner loops walk a seed's own fixed array into a fresh
	# list they do not test the size of (INC-0002).
	for index in range(realms.size() - 1):
		var standing_id := realms[index].id
		var target_id := realms[index + 1].id
		var target := QiRealmSeed.for_realm(target_id)
		var standing := QiRealmSeed.for_realm(standing_id)
		if target == null:
			continue
		checked += 1
		var expected_ids: Array[String] = []
		for meridian_id in target.required_meridians:
			expected_ids.append(String(meridian_id))
		var live := QiCultivationApi.panel_state(_seated(actor, standing_id))
		var published: Array = live.get("required_channels", []) as Array
		assert_eq(
			published.size(),
			expected_ids.size(),
			"%s publishes the channel count its TARGET %s demands" % [standing_id, target_id]
		)
		for position in range(expected_ids.size()):
			assert_eq(
				String(published[position]),
				expected_ids[position],
				"%s -> %s publishes channel %d by id" % [standing_id, target_id, position]
			)
		assert_eq(
			String(live.get("required_channel_state", "")),
			String(target.required_channel_state),
			"%s publishes the state %s wants" % [standing_id, target_id]
		)
		assert_eq(
			int(live.get("required_channel_depth", -1)),
			target.required_channel_refinement,
			"%s publishes the depth %s wants, not its own" % [standing_id, target_id]
		)
		if (
			standing != null
			and (
				standing.required_meridians.size() != target.required_meridians.size()
				or String(standing.required_channel_state) != String(target.required_channel_state)
				or standing.required_channel_refinement != target.required_channel_refinement
			)
		):
			discriminating += 1
	assert_eq(checked > 20, true, "the ladder's boundaries were walked (%d)" % checked)
	# The assertion that makes this test real. Without it the three per-boundary
	# comparisons above can all hold on a ladder where the standing realm's gate
	# equals the next realm's, which is exactly the fixture BL-0785 was built on.
	assert_eq(
		discriminating > 0,
		true,
		(
			"at least one boundary must DISCRIMINATE, or every comparison above is "
			+ "vacuous again (BL-0785)"
		)
	)


## The breakthrough half is delegated, not restated. Asserting it EQUALS the
## transaction's own preview is what pins the facade to the single source: a
## panel previewing one number and the action charging another is ADR 0044's
## defect, and this is the assertion that catches it.
func test_the_breakthrough_half_is_the_transactions_own_preview() -> void:
	var actor := _actor()
	var live := QiCultivationApi.panel_state(actor)
	var preview := QiBreakthroughTransaction.preview(actor)
	assert_eq(
		bool(live.get("can_attempt", false)),
		bool(preview.get("can_attempt", false)),
		"the panel and the transaction agree on whether an attempt is allowed"
	)
	assert_almost_eq(
		float(live.get("chance", -1.0)),
		float(preview.get("chance", 0.0)),
		"and on the chance, so the number shown is the number charged"
	)


## Every value a panel formats is present as a key. A missing key is a crash in
## `ui/` rather than a red test, because a screen reading `row["realm"]` on an
## absent key aborts mid-function and reports nothing.
func test_every_column_a_panel_formats_is_present() -> void:
	var live := QiCultivationApi.panel_state(_actor())
	for key in [
		"realm",
		"target",
		"progress",
		"qi",
		"qi_maximum",
		"dantian_quality",
		"dantian_injured",
		"channels",
		"required_channels",
		"required_channel_state",
		"required_channel_depth",
		"can_attempt",
		"chance",
		"unmet",
		"costs",
	]:
		assert_eq(live.has(key), true, "'%s' is published for the panel" % key)
