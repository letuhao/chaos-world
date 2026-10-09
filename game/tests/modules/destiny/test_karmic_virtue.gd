extends TestCase

## BL-0951 / ADR 0939, S12: karmic virtue — the deeds the world remembers are spent to mend
## a scarred past realm.
##
## The price is a DEED, and the deed is read from the shared `WorldFact` ledger (ADR 0113),
## so the two halves are asserted, not described: the virtue is what the ledger counts, and
## a mend SPENDS it — a spent ledger tracks what `WorldFact` (monotone) never lowers.
##
## Every loop is a bounded `for`; there is no `while`.

const SPARED := &"third_man_spared"
const OATH := &"oaths_discharged"


func _hero() -> Actor:
	return Actor.new(&"virtue_hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})


func _deeds(actor: Actor, fact: StringName, count: int) -> void:
	for _i in count:
		WorldFact.record(actor, fact, 1)


func _seed(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"seed snapshot %s at %f" % [String(realm_id), perfection]
	)


func test_a_deed_mends_foundation() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.1)
	_deeds(actor, SPARED, DestinyKarmicVirtue.VIRTUE_PER_MEND)
	var result := DestinyApi.karmic_virtue(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", false)), true, "the avenue resolves: %s" % str(result))
	assert_eq(String(result.get("reason", "")), DestinyKarmicVirtue.OK_MENDED, "named")
	var mended: Dictionary = result.get("mended", {})
	assert_almost_eq(
		float(mended.get("after", -1.0)),
		0.1 + DestinyKarmicVirtue.VIRTUE_MEND,
		"by exactly the authored step"
	)
	assert_eq(
		int(result.get("spent", -1)), DestinyKarmicVirtue.VIRTUE_PER_MEND, "and the deeds are spent"
	)
	assert_eq(int(result.get("available", -1)), 0, "leaving none available")


## Both authored deed kinds are virtue, and they sum — a mercy and a kept oath are one
## currency because both are deeds the world remembers.
func test_both_deed_kinds_count() -> void:
	var actor := _hero()
	_deeds(actor, SPARED, 1)
	_deeds(actor, OATH, 1)
	assert_eq(
		DestinyKarmicVirtue.available(actor),
		DestinyKarmicVirtue.VIRTUE_PER_MEND,
		"one of each kind is one mend's worth"
	)


func test_no_virtue_is_refused() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.1)
	var result := DestinyApi.karmic_virtue(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", true)), false, "no deeds, no mend")
	assert_eq(String(result.get("reason", "")), DestinyKarmicVirtue.R_NO_VIRTUE, "refused by name")


## A refusal costs nothing: the deeds are spent only once the mend has been accepted.
func test_a_refusal_costs_no_virtue() -> void:
	var actor := _hero()
	_deeds(actor, SPARED, 1)
	var before := DestinyKarmicVirtue.available(actor)
	var result := DestinyApi.karmic_virtue(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", true)), false, "one deed is below the cost")
	assert_eq(DestinyKarmicVirtue.spent(actor), 0, "and nothing is spent")
	assert_eq(DestinyKarmicVirtue.available(actor), before, "so the deed is still there to spend")


func test_the_mend_stops_at_the_mended_ceiling() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.45)
	_deeds(actor, SPARED, DestinyKarmicVirtue.VIRTUE_PER_MEND)
	var result := DestinyApi.karmic_virtue(actor, &"qi_refining")
	var mended: Dictionary = result.get("mended", {})
	assert_almost_eq(
		float(mended.get("after", -1.0)), FoundationApi.MEND_CAP, "capped, never past it"
	)


func test_a_realm_at_the_ceiling_is_refused() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.6)
	_deeds(actor, SPARED, DestinyKarmicVirtue.VIRTUE_PER_MEND)
	var result := DestinyApi.karmic_virtue(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", true)), false, "a realm at the ceiling has nothing to win")
	assert_eq(String(result.get("reason", "")), DestinyKarmicVirtue.R_MEND_CAPPED, "named")
	assert_eq(DestinyKarmicVirtue.spent(actor), 0, "and no deed is spent on the refusal")


## Virtue is SPENT, not destroyed: a deed stays in the world-fact ledger (which is
## monotone), and the avenue tracks only what it has already spent — so a second mend needs
## a second deed.
func test_virtue_is_spent_not_destroyed() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.1)
	_deeds(actor, SPARED, DestinyKarmicVirtue.VIRTUE_PER_MEND + 1)
	assert_eq(
		WorldFact.count(actor, SPARED),
		DestinyKarmicVirtue.VIRTUE_PER_MEND + 1,
		"the ledger holds every deed"
	)
	assert_eq(bool(DestinyApi.karmic_virtue(actor, &"qi_refining").get("ok", false)), true, "first")
	assert_eq(DestinyKarmicVirtue.available(actor), 1, "one deed remains after the first mend")
	var second := DestinyApi.karmic_virtue(actor, &"qi_refining")
	assert_eq(bool(second.get("ok", true)), false, "the second mend is refused")
	assert_eq(
		String(second.get("reason", "")), DestinyKarmicVirtue.R_NO_VIRTUE, "for want of deeds"
	)


## The realm defaults to the weakest scar, and a realm never left has nothing to mend.
func test_the_realm_defaults_to_the_weakest_scar() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.4)
	_seed(actor, &"spirit_condensation", 0.2)
	_deeds(actor, SPARED, DestinyKarmicVirtue.VIRTUE_PER_MEND)
	var result := DestinyApi.karmic_virtue(actor)
	assert_eq(bool(result.get("ok", false)), true, "the avenue resolves")
	assert_eq(String(result.get("realm", "")), "spirit_condensation", "on the weakest scar")
	assert_almost_eq(
		FoundationApi.snapshot_for(actor, &"spirit_condensation"),
		0.2 + DestinyKarmicVirtue.VIRTUE_MEND,
		"the weakest is lifted"
	)
	var bare := _hero()
	_deeds(bare, SPARED, DestinyKarmicVirtue.VIRTUE_PER_MEND)
	assert_eq(
		String(DestinyApi.karmic_virtue(bare).get("reason", "")),
		DestinyKarmicVirtue.R_NO_SNAPSHOT,
		"a realm never left has nothing to mend"
	)
