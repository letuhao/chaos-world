extends TestCase

## ADR 0097, ADR 0933: the one owner reference. Its kind vocabulary is OPEN — membership is
## validated at `OwnerResolver.resolve`, never here — so this suite asserts the STRUCTURE
## the value owns: the failure modes a ref that quietly names the wrong holder would ship,
## the world fact a save must keep, and the JSON/storage-key round trips a ledger needs.


func test_a_tier_kind_builds() -> void:
	var made := OwnerRef.create(&"sect", &"azure_flame")
	assert_eq(bool(made["ok"]), true, "a tier kind builds")
	var ref: OwnerRef = made["owner"]
	assert_eq(ref.kind, &"sect", "the kind survives")
	assert_eq(ref.id, &"azure_flame", "the id survives")


## ## A non-tier kind builds; whether it RESOLVES is the resolver's question (ADR 0933).
##
## The kind set is open — a pack's `trading_guild` is a holder kind the moment a boot
## registers it — and a leaf contract cannot see a registry, so the ref must not be the
## thing that says no. Asserted with a shipped kind and a synthetic one, because the ref
## draws no line between them.
func test_a_non_tier_kind_builds() -> void:
	for kind_value in [&"trading_guild", &"wayfarer_guild"]:
		var made := OwnerRef.create(kind_value, &"the_house")
		assert_eq(bool(made["ok"]), true, "kind '%s' builds" % kind_value)
		assert_eq((made["owner"] as OwnerRef).kind, kind_value, "and holds its own kind")


## The one refusal the ref can still answer alone: a kind that names nothing is not a kind
## that can pass as somebody else. A kind nobody registered still BUILDS a ref (above) and
## refuses by this same name at the resolver.
func test_an_empty_kind_refuses_closed_and_names_itself() -> void:
	var made := OwnerRef.create(&"", &"x")
	assert_eq(bool(made["ok"]), false, "an empty kind refuses")
	assert_eq(String(made["reason"]), OwnerRef.UNKNOWN_KIND, "and names the rule")


func test_an_empty_id_refuses() -> void:
	var made := OwnerRef.create(&"clan", &"")
	assert_eq(bool(made["ok"]), false, "a kind with no id is not a holder")
	assert_eq(String(made["reason"]), "unknown_owner", "and says so by name")


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


## ## A kind this build does not register is KEPT, because a holder is a world fact.
##
## Dropping it would turn a held node into a VACANT one — free ground for the next
## claimant — and the next autosave would erase the holder for good. Nothing acts on an
## unresolvable holder: every USE refuses by name at the resolver, so the ref can afford
## to be faithful where the build is incomplete (ADR 0933).
func test_from_dict_keeps_a_kind_this_build_does_not_register() -> void:
	var ref := OwnerRef.from_dict({"kind": "gone_guild", "id": "the_house"})
	assert_eq(ref.is_empty(), false, "the ref survives")
	assert_eq(ref.kind, &"gone_guild", "the kind is intact")
	assert_eq(ref.id, &"the_house", "the id is intact")
	assert_eq(ref.to_dict(), {"kind": "gone_guild", "id": "the_house"}, "and round-trips")


## A corrupt field is diagnosed as empty, never aborted (`InstitutionLedger._text` records
## why): a `StringName(42.0)` cast RAISES, so a save load would crash the composition root
## over one bad field instead of reading the holder as absent.
func test_from_dict_diagnoses_a_wrong_typed_field_as_no_holder() -> void:
	var bad_kind := OwnerRef.from_dict({"kind": 42, "id": "x"})
	assert_eq(bad_kind.is_empty(), true, "a numeric kind is no kind")
	var bad_id := OwnerRef.from_dict({"kind": "sect", "id": 17})
	assert_eq(bad_id.is_empty(), true, "a numeric id is no id")


func test_round_trips_through_json() -> void:
	# ADR 0027: an inner StringName in a ledger reaches the save untouched.
	var ref := OwnerRef.new(&"nation", &"nine_cities")
	var payload: Dictionary = ref.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(json), TYPE_DICTIONARY, "the payload is JSON-safe")
	var restored := OwnerRef.from_dict(json)
	assert_eq(restored.kind, &"nation", "the kind survives the round trip")
	assert_eq(restored.id, &"nine_cities", "the id survives the round trip")


## The non-tier half of the same round trip: the kinds a pack ships survive JSON exactly
## as the shipped tiers do, so a travelling save cannot lose a guild's holding to the
## serializer.
func test_a_non_tier_kind_round_trips_through_json() -> void:
	var ref := OwnerRef.new(&"trading_guild", &"lantern_exchange")
	var json: Variant = JSON.parse_string(JSON.stringify(ref.to_dict()))
	var restored := OwnerRef.from_dict(json)
	assert_eq(restored.kind, &"trading_guild", "the pack kind survives")
	assert_eq(restored.id, &"lantern_exchange", "and its id")


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


## The storage-key pair is what a ledger counts a holder by, so a kind the build cannot
## resolve must still key (and parse) exactly like a shipped one.
func test_a_non_tier_storage_key_round_trips() -> void:
	var ref := OwnerRef.new(&"trading_guild", &"lantern_exchange")
	var parsed := OwnerRef.from_storage_key(ref.storage_key())
	assert_eq(parsed.kind, &"trading_guild", "the kind parses back")
	assert_eq(parsed.id, &"lantern_exchange", "the id parses back")
	assert_ne(
		OwnerRef.new(&"trading_guild", &"lantern_exchange").storage_key(),
		OwnerRef.new(&"trading_guild", &"other_house").storage_key(),
		"and id still participates"
	)
