extends TestCase

## `bond_changed` is DECLARED in `contracts/npc_events.gd` and ADR 0093 publishes it, but
## nothing emitted it: `apply_cause` moved the axes and returned. A signal a consumer is
## told to subscribe to and that never fires is worse than no signal, because the code that
## depends on it is written, reviewed and green.
##
## ## Two properties, and the second is the point
##
## 1. `apply_cause` announces the bond that moved, naming a `SocialCauseDef` id.
## 2. It announces a CAUSE, never a delta. ADR 0093 §Consequences accepts this as a cost
##    deliberately: a subscriber that received `+8.0 standing` could recompute the change and
##    derive a class that disagrees with the ledger's — and the distinct-cause rule makes a
##    total alone insufficient to reach `friend`, so a recomputation would be *wrong*. The
##    subscriber must read the ledger for magnitude. The test asserts the emitted argument is
##    the authored cause id, so a future "convenience" float parameter is a red test.
##
## ## Why the bus lives on the contract
##
## `social/` owns the ledger a bond is, and may not depend on `npc/` (`tools/arch/registry.json`
## declares `social` -> `contracts`, `core`; not `npc`). The bus is therefore
## `NpcEvents.shared()`, and `NpcApi.events()` returns that same instance — so a subscriber
## that followed ADR 0093 and connected through the facade hears what `social/` publishes.
## Both halves are asserted here, because the bus being two objects is exactly the bug this
## shape exists to prevent.

const MERCHANT := &"merchant_grampa"
const SECT := &"iron_compound"

var _seen: Array[Dictionary] = []


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()
	_seen.clear()
	_disconnect_all()
	NpcEvents.shared().bond_changed.connect(
		func(npc_id, cause_id): _seen.append({"partner": npc_id, "cause": cause_id})
	)


## The bus is a PROCESS-WIDE static (ADR 0093's shape), so a connection an earlier suite or
## an earlier test left behind is still live and would append its own rows to `_seen` —
## making every count here test the accumulation rather than this test's own emissions.
## Disconnecting first is what makes "one event was announced" mean something.
func teardown() -> void:
	_disconnect_all()
	_seen.clear()


func _disconnect_all() -> void:
	for connection in NpcEvents.shared().bond_changed.get_connections():
		NpcEvents.shared().bond_changed.disconnect(connection["callable"])


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	return actor


# --- The signal fires, and names a cause ---------------------------------------


func test_applying_a_cause_announces_the_bond_it_moved() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	assert_eq(_seen.size(), 1, "one bond changed, so one announcement")
	assert_eq(String(_seen[0]["partner"]), String(MERCHANT), "naming the partner whose regard moved")
	assert_eq(String(_seen[0]["cause"]), "gifted_item", "and naming the authored cause that did it")


func test_each_cause_announces_itself_and_the_axes_are_not_the_payload() -> void:
	var actor := _actor()
	# Shipped magnitudes, deliberately: `gifted_item` is 1.0 standing / 0.02 trust and
	# `taught_technique` is 3.0 / 0.06, so together they clear neither FRIEND_AT (6.0)
	# nor CONFIDANT_AT (14.0) on the standing axis. The pair is worth ACQUAINTANCE and no
	# more no matter how many times you read the two numbers.
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	SocialApi.apply_cause(actor, MERCHANT, &"taught_technique")
	assert_eq(_seen.size(), 2, "two distinct causes, two announcements")
	assert_eq(String(_seen[0]["cause"]), "gifted_item", "the first named its own cause")
	assert_eq(String(_seen[1]["cause"]), "taught_technique", "and so did the second")
	# The anti-farm property, asserted at the seam: the payload is an id a subscriber can
	# look up, not a number it can add up. Were a delta on the wire, a subscriber would sum
	# 1.0 + 3.0 and can it reach `friend`? This is the disagreement the contract forbids.
	var bond := SocialApi.social_state(actor).bond(MERCHANT)
	assert_eq(bond.distinct_causes(), 2, "the ledger is where magnitude lives")
	assert_almost_eq(bond.standing, 4.0, "and the total is not enough on its own")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"two real causes still only read as an acquaintance"
	)
	# So a delta cannot stand in for the ledger even by accident: the same two causes at ten
	# times the magnitude WOULD clear FRIEND_AT, which is exactly why the magnitude has to be
	# read from the ledger rather than recomputed from an announcement.
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item", 10.0)
	assert_eq(
		SocialApi.social_state(actor).bond(MERCHANT).bond_class(),
		SocialBondClass.FRIEND,
		"scale moves it, which is why only the ledger is authoritative"
	)


func test_an_institution_bond_announces_under_the_institution_id() -> void:
	var actor := _actor()
	# The sect join is the production route: `sect/api.gd:_regard` calls `apply_cause` with an
	# institution id, so this is the announcement a sect subscriber would receive.
	SocialApi.apply_cause(actor, SECT, &"sworn_to_sect")
	assert_eq(_seen.size(), 1, "an institution bond is announced too")
	assert_eq(
		String(_seen[0]["partner"]),
		String(SECT),
		"under the institution id, which is the partner on that row"
	)


func test_a_refused_cause_announces_nothing() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"no_such_cause")
	SocialApi.apply_cause(actor, &"", &"gifted_item")
	SocialApi.apply_cause(null, MERCHANT, &"gifted_item")
	assert_eq(_seen.size(), 0, "nothing moved, so nothing was announced")


func test_decay_is_not_a_cause_and_does_not_announce_a_cause_id() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	_seen.clear()
	SocialApi.tick(actor, 24.0 * 60.0 * 60.0 * 30.0)
	# Drift moves the axis with no authored cause behind it, so there is no cause id that
	# could honestly be announced. Emitting a stand-in id would be worse than silence: a
	# subscriber keying on cause would branch on an event that never happened.
	assert_eq(_seen.size(), 0, "the announcement carries a CAUSE, and decay has none")


func test_forgetting_a_bond_is_not_announced_as_a_cause() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	_seen.clear()
	assert_eq(SocialApi.forget(actor, MERCHANT), true, "forgotten")
	# Retirement removes a row; there is no authored act to name. The subscriber that cares
	# about a retired npc reads `NpcApi.events().presence_changed`, which `advance_stage`
	# emits on the same terminal frame.
	assert_eq(_seen.size(), 0, "no cause, so no announcement")


# --- One bus, reachable from both modules --------------------------------------


func test_the_facade_and_the_contract_hand_out_the_same_bus() -> void:
	assert_eq(NpcApi.events(), NpcEvents.shared(), "one bus, not two objects")
	assert_eq(NpcApi.events(), NpcApi.events(), "and stable across calls")


func test_a_subscriber_that_connected_through_the_facade_hears_the_social_module() -> void:
	# The ADR 0093 recipe, verbatim: a consumer connects through `NpcApi.events()`. If the
	# two accessors ever handed out different instances this goes red, and every subscriber
	# in the game silently stops hearing bonds — a bug with no other symptom.
	_disconnect_all()
	var heard: Array[StringName] = []
	NpcApi.events().bond_changed.connect(
		func(_npc_id, cause_id): heard.append(cause_id)
	)
	SocialApi.apply_cause(_actor(), MERCHANT, &"gifted_item")
	assert_eq(heard, [&"gifted_item"] as Array[StringName], "the facade-connected subscriber heard it")