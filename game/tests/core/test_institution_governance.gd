extends TestCase

## ## Governance in the standard: purge, authority, duty and admission on a GUILD
##
## `test_institution_membership.gd` proves join/leave/found. This suite proves the four
## governance verbs land on content that is NOT a tier: the shipped Lantern Exchange
## (whose top seat authors `expel` that nothing executed until now) and one overlay
## fixture guild with TWO expel offices, so the peer rule is reachable. No sect, clan,
## nation or mod code is loaded or named anywhere below.
##
## The five measurements:
##
##   1. A guild expels: the roster severs, the claim clears, the recognition strips,
##      and the expeller pays strictly more than the expelled forfeits (compared,
##      never two literals).
##   2. Authored authority gates: the seat holds `expel`, the floor does not, and an
##      unpowered purge is refused `not_authorised` writing nothing.
##   3. A peer is refused unless forced (`cannot_expel_equal_or_above`), and force is
##      recorded on the plan.
##   4. Duty pays through the clamp and settles to zero; a settled serve is refused
##      `nothing_owed`.
##   5. Admission tells vacant from unmet from refused, and absent rows gate nothing.
##
## ## Every loop in this file is a `for`
##
## Walks are over a fixed literal, a fixed `range`, or a materialised key list, and none
## appends to the container it walks — so no bound grows in lockstep with its own body.

## The shipped guild, read and NEVER written.
const LANTERN := "res://data/institutions/lantern_exchange.tres"
const LANTERN_ID := &"lantern_exchange"
const SEAT := &"first_ledger"
const CLERK := &"clerk"

## The overlay fixture: a second trading guild whose bench seats TWO, both authoring
## `expel`, so a purge can meet its peer. Same kind as the shipped guilds, so the boot
## folds it rather than registering anything new.
const GAVEL_ID := &"gavel_guild"
const BENCH := &"bench"
const FLOOR := &"floor"

const TEMP_DIR := "cw_institution_governance_test"
const OWNER := "governance_test"

var _registry: InstitutionRegistry = null
var _reference: Actor = null
var _overlay: String = ""
## Everything this suite mints. `Actor` extends `RefCounted`, so `free()` on one is a
## script error and dropping the array IS the release; no `Node` is minted at all.
var _born: Array = []


func setup() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	_registry = InstitutionRegistry.new()
	_publish_fixture()
	InstitutionBoot.install(_registry)
	_reference = _actor(&"reference")


func teardown() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	if InstitutionRegistry.shared != null:
		InstitutionRegistry.shared.clear()
	_born.clear()
	if _registry != null:
		_registry.clear()
		_registry = null
	if _overlay != "":
		for file in ContentScan.files_under(_overlay):
			DirAccess.remove_absolute(file)
		DirAccess.remove_absolute(_overlay)
		_overlay = ""


# --- The purge -----------------------------------------------------------------


## ## A guild casts a member out, and the expeller pays strictly more
##
## The founder's seat authors `expel`; the clerk's does not. The purge severs the roster,
## clears the claim, strips the recognition, and charges the founder the forfeited
## standing PLUS the margin — every number compared, none written twice.
func test_a_guild_expels_and_the_expeller_pays_strictly_more() -> void:
	var founder := _actor(&"founder")
	var joiner := _actor(&"joiner")
	assert_eq(
		bool(InstitutionMembership.found(_registry, founder, _guild(), "founder")["ok"]),
		true,
		"the guild is founded and the founder seated"
	)
	assert_eq(
		bool(InstitutionMembership.join(_registry, joiner, LANTERN_ID)["ok"]),
		true,
		"the joiner walks into the ordinary office"
	)
	assert_eq(
		bool(InstitutionMembership.move_standing(_registry, joiner, LANTERN_ID, 20)["ok"]),
		true,
		"the joiner holds standing worth forfeiting"
	)
	assert_eq(_own_modifiers(joiner), 2, "and its recognition is on the stack")
	var forfeited := int(InstitutionMembership.claim_of(joiner, LANTERN_ID)["standing"])

	var cast := InstitutionMembership.expel(_registry, founder, LANTERN_ID, joiner)
	assert_eq(bool(cast["ok"]), true, "the purge lands: %s" % str(cast))
	assert_eq(String(cast["target"]), String(joiner.id), "naming the cast-out member")
	assert_eq(bool(cast["forced"]), false, "an ordinary purge is not forced")
	assert_eq(
		int(cast["cost_expeller"]) > int(cast["cost_expelled"]),
		true,
		"the expeller pays strictly more than the expelled forfeits"
	)
	assert_eq(
		int(cast["cost_expeller"]),
		forfeited + InstitutionMembership.EXPEL_MARGIN,
		"forfeiture plus the authored margin, computed rather than written twice"
	)
	assert_eq(
		int(cast["applied_expeller"]),
		-(forfeited + InstitutionMembership.EXPEL_MARGIN),
		"the ledger move landed signed, forfeiture plus margin"
	)
	assert_eq(
		int(InstitutionMembership.claim_of(founder, LANTERN_ID)["standing"]),
		40 + int(cast["applied_expeller"]),
		"and the founder's ledger carries the charge"
	)
	assert_eq(InstitutionMembership.holds(joiner, LANTERN_ID), false, "the claim is cleared")
	assert_eq(
		(InstitutionMembership.roster_of(LANTERN_ID)[String(CLERK)] as Array).size(),
		0,
		"the roster no longer names them"
	)
	assert_eq(_own_modifiers(joiner), 0, "and the recognition came off the stack")
	assert_almost_eq(
		joiner.stats.derived(Stat.FORTUNE), _bare(Stat.FORTUNE), "restoring the sheet exactly"
	)


## ## Without the authority there is no purge, and the refusal writes nothing
##
## A clerk holding no `expel` casts at the founder and is refused by name. Both ledgers
## and the world roster are byte-identical before and after.
func test_a_purge_without_authority_is_refused_and_writes_nothing() -> void:
	var founder := _actor(&"founder")
	var clerk := _actor(&"clerk")
	InstitutionMembership.found(_registry, founder, _guild(), "founder")
	InstitutionMembership.join(_registry, clerk, LANTERN_ID)
	var founder_before := _fingerprint(founder)
	var clerk_before := _fingerprint(clerk)
	var roster_before := JSON.stringify(InstitutionMembership.rosters())

	var cast := InstitutionMembership.expel(_registry, clerk, LANTERN_ID, founder)
	assert_eq(bool(cast["ok"]), false, "the purge is refused")
	assert_eq(
		String(cast["reason"]),
		InstitutionMembership.R_NOT_AUTHORISED,
		"naming the missing authority"
	)
	assert_eq(_fingerprint(founder), founder_before, "the founder lost nothing")
	assert_eq(_fingerprint(clerk), clerk_before, "and the purger paid nothing")
	assert_eq(JSON.stringify(InstitutionMembership.rosters()), roster_before, "nor did the world")


## ## A peer is refused unless the purge is forced, and the force is recorded
##
## Two holders of one expel office meet on the fixture bench: the ordinary purge names
## `cannot_expel_equal_or_above`, the forced one lands and says so on the plan.
func test_a_peer_is_refused_unless_the_purge_is_forced() -> void:
	var holder := _actor(&"holder")
	var peer := _actor(&"peer")
	InstitutionMembership.found(_registry, holder, _gavel(), "holder")
	assert_eq(
		bool(InstitutionMembership.join(_registry, peer, GAVEL_ID, BENCH)["ok"]),
		true,
		"the peer takes the second half of the bench"
	)
	var refused := InstitutionMembership.expel(_registry, holder, GAVEL_ID, peer)
	assert_eq(bool(refused["ok"]), false, "equals are not purged")
	assert_eq(
		String(refused["reason"]),
		InstitutionMembership.R_CANNOT_EXPEL_EQUAL_OR_ABOVE,
		"by that name"
	)
	assert_eq(InstitutionMembership.holds(peer, GAVEL_ID), true, "so the peer still belongs")

	var forced := InstitutionMembership.expel(_registry, holder, GAVEL_ID, peer, true)
	assert_eq(bool(forced["ok"]), true, "force lands")
	assert_eq(bool(forced["forced"]), true, "and the plan records it")
	assert_eq(InstitutionMembership.holds(peer, GAVEL_ID), false, "severing the peer")


## ## The purge's own refusals, each by name
##
## Self-purges, strangers on both sides, and a null body: five faults, five names, and a
## refused verb that writes nothing on the one subject holding anything.
func test_the_purge_refuses_self_stranger_and_outsider_each_by_name() -> void:
	var founder := _actor(&"founder")
	var joiner := _actor(&"joiner")
	var stranger := _actor(&"stranger")
	InstitutionMembership.found(_registry, founder, _guild(), "founder")
	InstitutionMembership.join(_registry, joiner, LANTERN_ID)
	var kept := _fingerprint(joiner)

	var self_cast := InstitutionMembership.expel(_registry, founder, LANTERN_ID, founder)
	assert_eq(bool(self_cast["ok"]), false, "no self-purge")
	assert_eq(
		String(self_cast["reason"]),
		InstitutionMembership.R_CANNOT_EXPEL_SELF,
		"self-removal is leaving, which is always permitted and is a different verb"
	)
	var outsider := InstitutionMembership.expel(_registry, stranger, LANTERN_ID, joiner)
	assert_eq(
		String(outsider["reason"]),
		InstitutionMembership.R_NOT_A_MEMBER,
		"a stranger purges nothing"
	)
	var no_target := InstitutionMembership.expel(_registry, founder, LANTERN_ID, null)
	assert_eq(
		String(no_target["reason"]),
		InstitutionMembership.R_TARGET_NOT_A_MEMBER,
		"a null body holds no claim"
	)
	var gone := InstitutionMembership.expel(_registry, founder, LANTERN_ID, stranger)
	assert_eq(
		String(gone["reason"]),
		InstitutionMembership.R_TARGET_NOT_A_MEMBER,
		"an outsider is not a member to cast out"
	)
	assert_eq(_fingerprint(joiner), kept, "and no refusal moved a number")


## ## The asymmetry is the contract's gate, not this file's arithmetic
##
## Driven directly against `Expellable`: equal costs are refused `cost_not_asymmetric`,
## so the verb's always-passing inputs are a property of the derivation and the refusal
## itself lives exactly once, in the contract.
func test_equal_costs_are_refused_by_the_contract_that_owns_the_rule() -> void:
	var blocked := (
		Expellable
		. new()
		. expel(
			{
				"member": "holder",
				"target": "peer",
				"target_member": true,
				"target_office": "floor",
				"authorities": ["expel"],
				"target_authorities": [],
				"cost_expelled": 5,
				"cost_expeller": 5,
				"force": false,
			}
		)
	)
	assert_eq(bool(blocked["ok"]), false, "equal costs never purge")
	assert_eq(
		String(blocked["reason"]),
		InstitutionMembership.R_COST_NOT_ASYMMETRIC,
		"under the surface's own alias for the contract's reason"
	)


# --- Authority, read aloud -------------------------------------------------------


## ## The authored authorities answer as a read that writes nothing
##
## The seat holds `expel`, the floor does not, an empty question is refused, and a
## stranger is no member. The read is pure: the fingerprint never moves.
func test_authority_is_a_read_the_office_answers() -> void:
	var founder := _actor(&"founder")
	var clerk := _actor(&"clerk")
	InstitutionMembership.found(_registry, founder, _guild(), "founder")
	InstitutionMembership.join(_registry, clerk, LANTERN_ID)
	var kept := _fingerprint(clerk)

	var seat := InstitutionMembership.has_authority(_registry, founder, LANTERN_ID, &"expel")
	assert_eq(bool(seat["ok"]), true, "the seat is asked")
	assert_eq(bool(seat["has"]), true, "and it holds the purge")
	var floor := InstitutionMembership.has_authority(_registry, clerk, LANTERN_ID, &"expel")
	assert_eq(bool(floor["ok"]), true, "the floor is asked too")
	assert_eq(bool(floor["has"]), false, "and it does not — a legitimate state, never zero")
	var empty := InstitutionMembership.has_authority(_registry, clerk, LANTERN_ID, &"")
	assert_eq(
		String(empty["reason"]),
		InstitutionMembership.R_NO_AUTHORITY_ID,
		"an empty question is refused, not answered false"
	)
	var stranger := InstitutionMembership.has_authority(
		_registry, _actor(&"stranger"), LANTERN_ID, &"expel"
	)
	assert_eq(
		String(stranger["reason"]), InstitutionMembership.R_NOT_A_MEMBER, "no member, no answer"
	)
	assert_eq(_fingerprint(clerk), kept, "and asking never wrote")


# --- Duty, paid down -------------------------------------------------------------


## ## Duty pays through the clamp, settles to zero, and then refuses by name
##
## An over-settle pays what is owed per line — asserted as the `min` sum, computed from
## the lines rather than written twice — and a second serve finds nothing to move.
func test_duty_pays_through_the_clamp_and_then_refuses_nothing_owed() -> void:
	var joiner := _actor(&"joiner")
	assert_eq(
		bool(InstitutionMembership.join(_registry, joiner, LANTERN_ID)["ok"]),
		true,
		"admitted into the ordinary office"
	)
	var owed: Dictionary = InstitutionMembership.claim_of(joiner, LANTERN_ID)["obligation"]
	var total := 0
	for term in owed.keys():
		total += mini(int(owed[term]), 9)
	assert_eq(total > 0, true, "admission opened a debt worth paying")

	var paid := InstitutionMembership.serve(_registry, joiner, LANTERN_ID, 9)
	assert_eq(bool(paid["ok"]), true, "the over-settle lands: %s" % str(paid))
	assert_eq(int(paid["plan"]["settled"]), total, "paying what was owed, never what was asked")
	assert_eq(int(paid["plan"]["remaining"]), 0, "leaving nothing behind")
	assert_eq(int(paid["discharged"]), owed.size(), "crossing every line it touched")
	assert_eq(
		InstitutionMembership.claim_of(joiner, LANTERN_ID)["obligation"],
		{"duty_clerk": 0, "duty_lantern_exchange": 0},
		"with zero keys kept, the settled shape"
	)

	var again := InstitutionMembership.serve(_registry, joiner, LANTERN_ID, 1)
	assert_eq(bool(again["ok"]), false, "a settled serve is no serve")
	assert_eq(String(again["reason"]), InstitutionMembership.R_NOTHING_OWED, "by that name")
	var instant := InstitutionMembership.serve(_registry, joiner, LANTERN_ID, 0)
	assert_eq(String(instant["reason"]), InstitutionMembership.R_NO_PERIODS, "no periods, no serve")
	var stranger := InstitutionMembership.serve(_registry, _actor(&"stranger"), LANTERN_ID, 1)
	assert_eq(
		String(stranger["reason"]), InstitutionMembership.R_NOT_A_MEMBER, "no member, no debt"
	)


# --- Admission, gated --------------------------------------------------------------


## ## Vacant is not unmet, unmet is not refused, and absent rows gate nothing
##
## One table, four candidates: no value for a row is `vacant`, a short value is
## `below_requirement`, no invitation is `not_invited`, and the qualified walk in.
func test_admission_tells_vacant_from_unmet_from_refused() -> void:
	var table := {"seniority": {"kind": "standing", "need": 10}}

	var novice := _actor(&"novalue")
	var vacant := InstitutionMembership.join(_registry, novice, LANTERN_ID, &"", _table(table, {}))
	assert_eq(bool(vacant["ok"]), false, "no value is no admission")
	assert_eq(
		String(vacant["reason"]), InstitutionMembership.R_VACANT, "but a vacancy, never a zero"
	)

	var junior := _actor(&"junior")
	var short := InstitutionMembership.join(
		_registry, junior, LANTERN_ID, &"", _table(table, {"seniority": 3})
	)
	assert_eq(bool(short["ok"]), false, "a short value falls short")
	assert_eq(
		String(short["reason"]),
		InstitutionMembership.R_BELOW_REQUIREMENT,
		"naming the bar it missed"
	)

	var uninvited := InstitutionMembership.join(
		_registry,
		_actor(&"outsider"),
		LANTERN_ID,
		&"",
		_admit(true, false, table, {"seniority": 25})
	)
	assert_eq(bool(uninvited["ok"]), false, "a closed door stays closed")
	assert_eq(String(uninvited["reason"]), InstitutionMembership.R_NOT_INVITED, "a door, not a bar")

	var before := JSON.stringify(InstitutionMembership.rosters())
	var member := _actor(&"member")
	var entered := InstitutionMembership.join(
		_registry, member, LANTERN_ID, &"", _admit(true, true, table, {"seniority": 25})
	)
	assert_eq(bool(entered["ok"]), true, "the invited and qualified walk in: %s" % str(entered))
	assert_eq(String(entered["position"]), String(CLERK), "through the ordinary office")
	assert_eq(
		JSON.stringify(InstitutionMembership.rosters()) == before,
		false,
		"and the world roster says so"
	)


## ## A refused admit writes nothing, and an empty table gates nothing
##
## The three refusals above leave no ledger and no roster row; a join with no table at
## all is today's open house, unchanged.
func test_a_refused_admit_writes_nothing_and_an_empty_table_gates_nothing() -> void:
	var table := {"seniority": {"kind": "standing", "need": 10}}
	var candidate := _actor(&"candidate")
	var roster_before := JSON.stringify(InstitutionMembership.rosters())
	var refused := InstitutionMembership.join(
		_registry, candidate, LANTERN_ID, &"", _table(table, {})
	)
	assert_eq(bool(refused["ok"]), false, "refused")
	assert_eq(
		candidate.get_module_data(InstitutionMembership.MEMBERSHIP_KEY), {}, "no claim was stored"
	)
	assert_eq(
		JSON.stringify(InstitutionMembership.rosters()), roster_before, "and no roster row opened"
	)
	var open_house := InstitutionMembership.join(_registry, _actor(&"walkin"), LANTERN_ID)
	assert_eq(bool(open_house["ok"]), true, "an empty table is an open house")


# --- The save hop ------------------------------------------------------------------


## ## Governance state survives the JSON hop as facts, not representation
##
## `JSON.parse_string` returns every number as a float, so both sides go through the hop
## and the read model is compared rather than the bytes — the shape suite's own rule.
func test_governance_state_round_trips_through_the_actor_save() -> void:
	var actor := _actor(&"saved")
	InstitutionMembership.join(_registry, actor, LANTERN_ID)
	InstitutionMembership.move_standing(_registry, actor, LANTERN_ID, 13)
	InstitutionMembership.serve(_registry, actor, LANTERN_ID, 1)
	var before := InstitutionMembership.summary(actor)
	assert_eq((before["institutions"] as Dictionary).size() > 0, true, "something to save")

	var parsed = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(parsed, null, "the payload parses")
	var restored := Actor.from_dict(parsed as Dictionary)
	assert_ne(restored, null, "and the body comes back")
	_born.append(restored)
	assert_eq(
		_through_json(InstitutionMembership.summary(restored)),
		_through_json(before),
		"the read model survives the hop unchanged"
	)
	assert_eq(InstitutionMembership.holds(restored, LANTERN_ID), true, "so the body still belongs")


# --- Fixture and helpers -----------------------------------------------------------


## The shipped guild, loaded and read. Nothing is written: `load()` caches process-wide.
func _guild() -> InstitutionDef:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	return def


## The fixture guild as the CATALOG serves it — the object `join` resolves, so every
## case drives the production path rather than a copy the verb never sees.
func _gavel() -> InstitutionDef:
	var def := InstitutionDefCatalog.instance().definition(GAVEL_ID)
	assert_ne(def, null, "the fixture guild is in the catalog")
	return def


## Publish the fixture guild through the MOD SEAM: written as text under the OS temp
## directory, merged by overlay, so nothing in `game/src` was touched to make it appear.
func _publish_fixture() -> void:
	_overlay = OS.get_environment("TEMP").path_join(TEMP_DIR).path_join("guilds")
	if not DirAccess.dir_exists_absolute(_overlay):
		DirAccess.make_dir_recursive_absolute(_overlay)
	var text := (
		'[gd_resource type="Resource" script_class="InstitutionDef" load_steps=5 format=3]\n\n'
		+ '[ext_resource type="Script" path="res://src/core/institution_def.gd" id="1_def"]\n'
		+ '[ext_resource type="Script" path="res://src/core/institution_position_def.gd" id="2"]\n\n'
		+ '[sub_resource type="Resource" id="bench"]\n'
		+ 'script = ExtResource("2")\n'
		+ 'id = &"bench"\n'
		+ 'display_name = "Bench"\n'
		+ "capacity = 2\n"
		+ "duty_per_period = 1\n"
		+ "patronage_per_period = 0\n"
		+ 'authorities = Array[StringName]([&"expel"])\n'
		+ 'standing_percent_stats = {"insight_gain": 0.0, "poise": 0.0}\n\n'
		+ '[sub_resource type="Resource" id="floor"]\n'
		+ 'script = ExtResource("2")\n'
		+ 'id = &"floor"\n'
		+ 'display_name = "Floor"\n'
		+ "capacity = 0\n"
		+ "duty_per_period = 1\n"
		+ "patronage_per_period = 0\n"
		+ 'standing_percent_stats = {"insight_gain": 0.0, "poise": 0.0}\n\n'
		+ "[resource]\n"
		+ 'script = ExtResource("1_def")\n'
		+ 'kind = &"trading_guild"\n'
		+ 'capabilities = Array[StringName]([&"has_offices"])\n'
		+ 'id = &"gavel_guild"\n'
		+ 'display_name = "Gavel Guild"\n'
		+ 'positions = Array[InstitutionPositionDef]([SubResource("bench"), SubResource("floor")])\n'
		+ 'top_position_id = &"bench"\n'
		+ "standing_cap = 100\n"
		+ "founder_standing = 20\n"
		+ "founding_cost = 100\n"
		+ "member_duty_per_period = 1\n"
	)
	var path := _overlay.path_join("gavel_guild.tres")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_ne(file, null, "the fixture is writable")
	file.store_string(text)
	file.close()
	InstitutionDefCatalog.set_overlay_roots(
		[{"dir": _overlay, "owner": OWNER, "declared_overrides": [], "id_field": "id"}]
	)
	var catalog := InstitutionDefCatalog.instance()
	assert_eq(catalog.has(GAVEL_ID), true, "the fixture merged")
	assert_eq(catalog.has(LANTERN_ID), true, "and the shipped family is still there")


## One admission table for the common case: open house, one row, one candidate value.
func _table(requirements: Dictionary, values: Dictionary) -> Dictionary:
	return _admit(false, false, requirements, values)


## One admission table, built the way a caller builds one: invitation policy plus
## requirement rows plus what this candidate carries.
func _admit(
	invite_only: bool, invited: bool, requirements: Dictionary, values: Dictionary
) -> Dictionary:
	return {
		"invite_only": invite_only,
		"invited": invited,
		"requirements": requirements,
		"values": values,
	}


## An actor with a funded founding pool and every base attribute at one realm's authored
## power, so a derived stat reads non-zero for want of no intended investment.
func _actor(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {})
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 9000.0))
	_born.append(actor)
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var power := maxf(1.0, (realms[0] as RealmDef).power)
	for attribute in Stat.BASE_ATTRIBUTES:
		actor.stats.set_base(attribute, 10.0 * power)
	return actor


## A stat's value on an actor carrying no grant at all, read off the reference body.
func _bare(stat_id: StringName) -> float:
	return _reference.stats.derived(stat_id)


## Every modifier on `actor` under this family's own namespace.
func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if InstitutionLedger.owns_source(InstitutionMembership.SOURCE_PREFIX, modifier.source):
			total += 1
	return total


## The sheet, the stack and the store as one comparable value, so a refused verb that
## moved anything fails here rather than reading as plausibly unchanged.
func _fingerprint(actor: Actor) -> Dictionary:
	var sheet := {}
	for stat_id in actor.stats.derived_all().keys():
		sheet[String(stat_id)] = actor.stats.derived(stat_id)
	var stack: Array = []
	for modifier in actor.stats._modifiers:
		stack.append("%s:%s:%f" % [modifier.source, modifier.stat, modifier.value])
	return {
		"sheet": sheet,
		"mods": actor.stats.modifier_count(),
		"own": _own_modifiers(actor),
		"store": JSON.stringify(actor.get_module_data(InstitutionMembership.MEMBERSHIP_KEY)),
		"stack": stack,
	}


## A payload through the JSON hop, so both sides of a round-trip assertion share one
## representation. Numbers return as floats, which is why facts are compared, not bytes.
func _through_json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))
