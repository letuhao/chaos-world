extends TestCase

## The shipped matrix table (ADR 0882) is DATA, and this is its gate: every row
## compiles, every aptitude feeds something, no edge double-scales the ladder, and no
## channel is fed by two different climb behaviors.


func _table() -> AptitudeTable:
	var table := AptitudeTable.shipped()
	assert_ne(table, null, "the shipped table loads")
	return table


func test_every_row_compiles_and_the_table_validates_clean() -> void:
	var table := _table()
	assert_eq(table.edge_rows.is_empty(), false, "the table has rows")
	assert_eq(
		table.to_edges().size(),
		table.edge_rows.size(),
		"every row compiles — a dropped row is a dead edge"
	)
	assert_eq(
		AptitudeMatrix.validate(table.to_edges()).is_empty(), true, "and no edge is malformed"
	)


func test_every_aptitude_feeds_something_and_no_edge_is_zero() -> void:
	var table := _table()
	var fed := {}
	for edge in table.to_edges():
		fed[edge.source] = true
		assert_eq(
			edge.k > 0.0,
			true,
			"%s -> %s carries a coefficient" % [String(edge.source), String(edge.channel)]
		)
	for id in Aptitude.all_ids():
		assert_eq(fed.has(id), true, "aptitude %s feeds at least one channel" % String(id))


func test_the_status_channels_have_a_producer() -> void:
	# DEF-0346's acceptance: the port's gate and potency channels are FED by the build.
	# Before this every status ran at parity times the defence share with no authoring
	# path at all, and the aptitude edge is the producer of record (the audit's chosen
	# direction over an item wave).
	var fed := {}
	for edge in _table().to_edges():
		fed[edge.channel] = true
	for channel in [&"status.power.omni", &"status.intensity.omni", &"status.resist.omni"]:
		assert_eq(fed.has(channel), true, "%s is produced by the matrix" % String(channel))


func test_the_status_contest_channels_do_not_ride_the_ladder() -> void:
	# ADR 0891: the gate and the net factors read ONE fixed scale over the delta
	# (`status_rate_scale`, `status_net_factor_scale`), so the delta must be share-space
	# at every realm. Under MAGNITUDE the same shares read 0.05 at R1 and ~27 at R30 and
	# the scales saturate — the gate stops being a contest down the ladder.
	var table := _table()
	for edge in table.to_edges():
		if not String(edge.channel).begins_with("status."):
			continue
		assert_eq(edge.mode, AptitudeEdge.Mode.CONTEST, "%s is share-space" % String(edge.channel))


func test_the_leech_answer_half_has_a_producer() -> void:
	# ADR 0889's pairing half: `Recoil.leech` reads `leech_resist.<pool>` against the
	# attacker's `lifesteal.<pool>` over `rate_scale`, so the ANSWER needs a producer or
	# a defender could only answer with content points. Composure feeds all three pools,
	# CONTEST — a fixed-scale contest reads share-space inputs (ADR 0891).
	var fed := {}
	for edge in _table().to_edges():
		if edge.source == &"composure":
			fed[edge.channel] = edge.mode
	for pool in [&"health", &"qi", &"stamina"]:
		var channel := StringName("leech_resist." + String(pool))
		assert_eq(fed.has(channel), true, "%s is produced by the matrix" % String(channel))
		assert_eq(fed[channel], AptitudeEdge.Mode.CONTEST, "%s is share-space" % String(channel))


func test_a_magnitude_edge_never_targets_a_realm_scaled_channel() -> void:
	# The realm MULT already scales these channels; a MAGNITUDE edge on top would apply
	# the ladder TWICE (ADR 0882).
	var table := _table()
	for edge in table.to_edges():
		if edge.mode != AptitudeEdge.Mode.MAGNITUDE:
			continue
		assert_eq(
			RealmScaling.SCALED_STATS.has(edge.channel),
			false,
			"%s must not double-scale" % String(edge.channel)
		)


func test_one_channel_carries_one_climb_behavior() -> void:
	var table := _table()
	var modes := {}
	for edge in table.to_edges():
		var previous: Variant = modes.get(edge.channel, null)
		if previous == null:
			modes[edge.channel] = edge.mode
			continue
		assert_eq(previous, edge.mode, "%s has one mode" % String(edge.channel))


func test_the_share_exponent_and_contest_span_are_positive() -> void:
	var table := _table()
	assert_eq(table.share_exponent > 0.0, true, "a positive exponent")
	assert_eq(table.contest_span > 0.0, true, "a positive contest span")
