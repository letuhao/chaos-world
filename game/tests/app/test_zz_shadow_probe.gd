extends TestCase

## THROWAWAY PROBE #3: which seam stores a value the base `float` would reject?
## MUTATION PROBE THROWAWAY


func test_probe_the_shadow_seam() -> void:
	var a := TestShadowProbe.new(&"direct")
	a.set_direct("a long time")
	print("PROBE direct   -> ", a.inspect())
	var b := TestShadowProbe.new(&"dynamic")
	b.set_dynamic("a long time")
	print("PROBE dynamic  -> ", b.inspect())
	assert_eq(true, true, "probe only")


func test_probe_the_negative_case() -> void:
	var a := TestShadowProbe.new(&"direct_neg")
	a.set_direct(-12.5)
	print("PROBE direct neg  -> ", a.inspect())
	var b := TestShadowProbe.new(&"dynamic_neg")
	b.set_dynamic(-12.5)
	print("PROBE dynamic neg -> ", b.inspect())
	assert_eq(true, true, "probe only")
