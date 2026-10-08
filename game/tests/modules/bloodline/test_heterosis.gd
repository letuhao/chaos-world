extends TestCase

## Tests for the heterosis mechanic (ADR 0894).
##
## Heterosis is a pair-level divergence term added to BloodlineState.inherit().
## The excess term 0.70 * m * D * (1−m) fires only when parents carry different
## lineage sets (D > 0), fixing the collision where partial × partial and pure ×
## outsider both landed at 0.395.


func test_inherit_unchanged_when_divergence_is_zero() -> void:
	# Same family (D=0): the excess term is identically zero.
	assert_almost_eq(BloodlineState.inherit(1.0, 1.0, 0.0), 0.745, "pure x pure same family", 0.001)
	assert_almost_eq(
		BloodlineState.inherit(0.5, 0.5, 0.0), 0.395, "partial x partial same family", 0.001
	)
	assert_almost_eq(BloodlineState.inherit(0.0, 0.0, 0.0), 0.045, "outsider x outsider", 0.001)


func test_inherit_excess_fires_when_divergence_is_nonzero() -> void:
	# Unrelated lineages (D=1): the excess term fires.
	# m=0.5, excess = 0.70 * 0.5 * 1.0 * 0.5 = 0.175
	# child = 0.5 * 0.70 + 0.045 + 0.175 = 0.570
	assert_almost_eq(
		BloodlineState.inherit(1.0, 0.0, 1.0), 0.570, "pure x outsider unrelated", 0.001
	)


func test_collision_is_fixed() -> void:
	# partial × partial (unrelated) now differs from partial × partial (same family).
	var same_family := BloodlineState.inherit(0.5, 0.5, 0.0)
	var unrelated := BloodlineState.inherit(0.5, 0.5, 1.0)
	assert_almost_eq(same_family, 0.395, "same family", 0.001)
	assert_almost_eq(unrelated, 0.570, "unrelated", 0.001)
	assert_ne(unrelated, same_family, "unrelated differs from same family")


func test_inbred_fixed_point_is_intact() -> void:
	# When D=0, the affine map converges to exactly FLOOR (0.150).
	var purity := 0.5
	for _i in range(50):
		purity = BloodlineState.inherit(purity, purity, 0.0)
	assert_almost_eq(purity, BloodlineState.FLOOR, "inbred converges to FLOOR", 0.001)


func test_first_generation_ceiling_is_intact() -> void:
	# inherit(1.0, 1.0) with D=0 is still 0.745.
	assert_almost_eq(BloodlineState.first_generation_ceiling(), 0.745, "first gen ceiling", 0.001)


func test_instability_discount_at_carrier_floor() -> void:
	# At the carrier floor, spike_remaining=0, discount=1.0 (no discount).
	assert_almost_eq(
		BloodlineState.instability_discount(0.417), 1.0, "carrier floor no discount", 0.001
	)


func test_instability_discount_at_peak_spike() -> void:
	# At first-gen ceiling (0.745), spike_remaining=1.0, discount=0.66 (34% discount).
	assert_almost_eq(
		BloodlineState.instability_discount(0.745), 0.66, "peak spike 34% discount", 0.001
	)


func test_instability_discount_mid_spike() -> void:
	# At 0.570: spike_remaining = (0.570 - 0.417) / (0.745 - 0.417) = 0.466
	# discount = 1.0 - 0.34 * 0.466 = 0.841
	assert_almost_eq(BloodlineState.instability_discount(0.570), 0.841, "mid spike discount", 0.01)


func test_inherit_default_divergence_preserves_backward_compat() -> void:
	# Calling inherit() without divergence arg behaves exactly as before.
	assert_almost_eq(BloodlineState.inherit(1.0, 1.0), 0.745, "default divergence pure", 0.001)
	assert_almost_eq(BloodlineState.inherit(0.5, 0.5), 0.395, "default divergence partial", 0.001)
	assert_almost_eq(BloodlineState.inherit(1.0, 0.0), 0.395, "default divergence outsider", 0.001)
