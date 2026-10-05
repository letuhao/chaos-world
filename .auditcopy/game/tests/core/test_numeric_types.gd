extends TestCase

## Godot's numeric headroom, measured rather than assumed.
##
## These were written for the one power ladder (ADR 0042), which the owner asked to have
## overflow-checked against the engine's types. The ladder is gone (ADR 0050); the engine
## facts are not, and `RealmScaling` still multiplies a stat by an authored number, so
## they are still worth pinning. Measured here rather than argued in a comment: if the
## measurement changes, the test fails rather than the prose going stale.


## GDScript `int` is 64-bit signed, not 32-bit. If it were 32-bit, any stat total that
## left the comfortable range would wrap negative instead of getting bigger.
func test_int_is_64_bit_signed() -> void:
	var big := 9223372036854775807
	assert_eq(big > 0, true, "int holds int64 max")
	assert_eq(big + 1 < 0, true, "and wraps rather than promoting to float")
	# 2^62 is comfortably inside int64 and far outside int32.
	assert_eq(4611686018427387904 > 0, true, "int holds 2^62, so it is not 32-bit")


## GDScript `float` is a 64-bit IEEE-754 double: 53 bits of mantissa, so values are exact
## to 2^53 and beyond that they round rather than wrap. That is what makes a large stat
## total degrade in precision instead of turning negative - a large multiplier must never
## be able to produce a negative health value.
func test_float_is_a_64_bit_double() -> void:
	# Built by arithmetic, not written as a literal: a large integral literal is
	# ambiguous between int and float at the parser level, and the arithmetic form tests
	# the numeric property rather than the tokenizer.
	var two_pow_53: float = pow(2.0, 53.0)
	assert_eq(two_pow_53, 9007199254740992, "2^53 is exact, as an int and as a double")
	# The spacing above 2^53 is 2, so 2^53 + 1 is not representable and rounds back down.
	assert_eq(two_pow_53 + 1.0, two_pow_53, "2^53+1 is not representable")
	# A double never wraps: it saturates toward infinity rather than going negative.
	var huge := 1.0e308
	assert_eq(huge > 0.0, true, "1e308 is positive, so no wrap")
	assert_eq(is_inf(huge * 10.0), true, "double has range far past any realm")
