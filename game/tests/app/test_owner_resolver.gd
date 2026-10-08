extends TestCase

## The resolver is where the OPEN kind vocabulary is validated (ADR 0933): `actor` by id,
## the three shipped tiers through their authored catalogs, and every other kind against
## `InstitutionRegistry` plus the authored organizations family. Before this slice
## `OwnerRef.KINDS` was closed to four names and a pack's organization kind could hold
## nothing at all — ADR 0922's licence stopping one layer short of the holder.
##
## ## Process-wide state, returned to "not wired"
##
## A registry row and the merged org catalog are process state in the one-process runner,
## so every case here starts from nothing booted (`clear()` drops both) and teardown
## returns them there. The positive cases boot the SHIPPED family — no fixture def — so the
## kind and its id are content a player could actually meet.

const TRADING_GUILD := &"trading_guild"
const LANTERN := &"lantern_exchange"


func setup() -> void:
	InstitutionDefCatalog.clear()
	InstitutionRegistry.shared = null


func teardown() -> void:
	InstitutionRegistry.shared = null
	InstitutionDefCatalog.clear()


## ## A non-tier kind a boot registered resolves, id and all
##
## `lantern_exchange` is the shipped `trading_guild` def; the kind reaches the registry
## through `InstitutionBoot.install`, the same discovery a pack's `.tres` gets. This is
## the evidence in one call: the ref builds the kind (ADR 0933) and the resolver answers,
## where before both refused it by name.
func test_a_registered_non_tier_kind_resolves() -> void:
	var installed := InstitutionBoot.install()
	assert_eq(bool(installed["ok"]), true, "setup: the shipped family registers")
	assert_eq(
		InstitutionRegistry.instance().knows(TRADING_GUILD),
		true,
		"setup: the guild kind reached the registry"
	)
	var answered := OwnerResolver.resolve(String(TRADING_GUILD), String(LANTERN))
	assert_eq(
		bool(answered["ok"]),
		true,
		"a registered non-tier kind resolves: %s" % answered.get("reason", "")
	)


func test_a_ghost_id_of_a_registered_kind_refuses_by_name() -> void:
	InstitutionBoot.install()
	var answered := OwnerResolver.resolve(String(TRADING_GUILD), "no_such_house")
	assert_eq(bool(answered["ok"]), false, "an id that names no authored house refuses")
	assert_eq(String(answered["reason"]), OwnerResolver.UNKNOWN_INSTITUTION, "by the generic name")


## ## The open set is not unbounded
##
## A kind no boot registered is not a kind, and it must never default to `actor` — that
## would let a stranger's holding pass a player's check, the failure the ref type exists
## to prevent.
func test_an_unregistered_kind_refuses_closed() -> void:
	var answered := OwnerResolver.resolve("never_registered_guild", "the_company")
	assert_eq(bool(answered["ok"]), false, "a kind no boot registered refuses")
	assert_eq(String(answered["reason"]), OwnerRef.UNKNOWN_KIND, "and names the type's own rule")


## `actor` is the one kind with no catalog, so a non-empty id is its whole answer — both
## halves asserted here, because `actor` is what every player-authored ref carries.
func test_actor_stays_special() -> void:
	assert_eq(bool(OwnerResolver.resolve("actor", "player")["ok"]), true, "an actor resolves by id")
	assert_eq(
		String(OwnerResolver.resolve("actor", "")["reason"]),
		OwnerResolver.UNKNOWN_OWNER,
		"and an actor with no id names nobody"
	)


## The shipped tiers keep their own catalogs and their own refusal names — the open branch
## must not have swallowed them.
func test_the_three_shipped_tiers_still_refuse_by_their_own_names() -> void:
	for kind in [&"clan", &"sect", &"nation"]:
		var ghost := OwnerResolver.resolve(String(kind), "no_such_institution")
		assert_eq(bool(ghost["ok"]), false, "an un-authored %s refuses" % String(kind))
		assert_eq(String(ghost["reason"]), "unknown_%s" % String(kind), "with the tier's own name")
