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
