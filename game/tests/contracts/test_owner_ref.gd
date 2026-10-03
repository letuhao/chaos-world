extends TestCase

## ADR 0097: the one owner reference. What is asserted here is mostly the FAILURE modes,
## because a ref that quietly names the wrong holder is the bug this type exists to prevent.


func test_a_known_kind_builds() -> void:
	var made := OwnerRef.create(&"sect", &"azure_flame")
	assert_eq(bool(made["ok"]), true, "a known kind builds")
	var ref: OwnerRef = made["owner"]
	assert_eq(ref.kind, &"sect", "the kind survives")
	assert_eq(ref.id, &"azure_flame", "the id survives")


func test_an_unknown_kind_refuses_closed_and_names_itself() -> void:
	# The whole point of the type: a typo must never answer as somebody else. Defaulting
	# to `actor` would let a sect's holding pass a player's check.
	for kind_value in [&"guild", &"town", &"", &"Actor"]:
		var made := OwnerRef.create(kind_value, &"x")
		assert_eq(bool(made["ok"]), false, "kind '%s' refuses" % kind_value)
		assert_eq(
			String(made["reason"]),
			OwnerRef.UNKNOWN_KIND,
			"and names the rule for '%s'" % kind_value
		)


func test_an_empty_id_refuses() -> void:
	var made := OwnerRef.create(&"clan", &"")
	assert_eq(bool(made["ok"]), false, "a kind with no id is not a holder")


func test_vacant_is_not_empty() -> void:
	# ADR 0083's three states. `{}` means no node; `{"vacant": true}` means a node with no
	# holder. Collapsing them is what a screen that renders a vacancy as a zero does wrong.
	assert_eq(OwnerRef.is_vacant(OwnerRef.vacant()), true, "vacant is vacant")
	assert_eq(OwnerRef.is_vacant({}), false, "an empty dict is not vacant")
	assert_eq(OwnerRef.is_vacant("nonsense"), false, "a non-dict is not vacant")


func test_an_empty_ref_is_the_unowned_state() -> void:
	var ref := OwnerRef.new()
	assert_eq(ref.is_empty(), true, "a fresh ref names nobody")
	assert_eq(OwnerRef.from_dict(OwnerRef.vacant()).is_empty(), true, "vacant normalizes empty")


func test_round_trips_through_json() -> void:
	# ADR 0027: an inner StringName in a ledger reaches the save untouched.
	var ref := OwnerRef.new(&"nation", &"nine_cities")
	var payload: Dictionary = ref.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(json), TYPE_DICTIONARY, "the payload is JSON-safe")
	var restored := OwnerRef.from_dict(json)
	assert_eq(restored.kind, &"nation", "the kind survives the round trip")
	assert_eq(restored.id, &"nine_cities", "the id survives the round trip")


func test_storage_key_is_stable_and_parsable() -> void:
	var ref := OwnerRef.new(&"clan", &"iron_vow")
	var key := ref.storage_key()
	assert_eq(OwnerRef.from_storage_key(key).kind, &"clan", "the kind parses back")
	assert_eq(OwnerRef.from_storage_key(key).id, &"iron_vow", "the id parses back")
	# Two different holders can never collide, which is what makes a ledger keyed by this
	# safe: one holder's holding cannot overwrite another's.
	assert_ne(
		OwnerRef.new(&"clan", &"iron_vow").storage_key(),
		OwnerRef.new(&"sect", &"iron_vow").storage_key(),
		"kind participates in the key"
	)
