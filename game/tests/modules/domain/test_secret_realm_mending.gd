extends "res://tests/modules/domain/domain_fixture_kit.gd"

## BL-0951 / ADR 0939, S9: the secret realm — a one-time authored SITE that reforges a
## scarred past realm, priced in danger and in the body's own life.
##
## The site is authored in `void_shrine.tres`; every case below drives the SHIPPED row
## through `DomainSecretRealm` rather than a hand-built fixture, for the reason the
## fixture suites read the shipped kit: a hand-built room would agree with itself and
## prove nothing about the content a player meets.
##
## Both halves of the price are asserted, not described: the trial is a STATUS resolved
## through the status module (never a bespoke damage channel, ADR 0075), and the life is
## the BODY's years spent through `FoundationApi.spend_periods` (BL-0951 S6).
##
## Every loop is a bounded `for`; there is no `while`.

const SITE_REALM := &"qi_refining"
const OTHER_REALM := &"spirit_condensation"


func _seed(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"seed snapshot %s at %f" % [String(realm_id), perfection]
	)


func _reforge(actor: Actor, realm_id: StringName = &"") -> Dictionary:
	return DomainSecretRealm.reforge(actor, _room_of(SITE), SITE, realm_id)


func _site_row(actor: Actor, fixture_id: StringName) -> Dictionary:
	var sites := DomainApi.summary(actor).get("sites", {}) as Dictionary
	for row in sites.get("sites", []):
		if String(row.get("fixture_id", "")) == String(fixture_id):
			return row
	return {}


## The happy path: the shipped site mends the realm it authors, by the step it authors,
## at the cost of the body's life — and is then spent for good.
func test_reforge_mends_the_authored_realm_and_spends_life() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.1)
	var age_before := actor.age_years
	var step := float(_authored(SITE).get("foundation_mend", 0.0))
	assert_eq(step > 0.0, true, "the shipped site authors a mend step")
	var result := _reforge(actor)
	assert_eq(bool(result.get("ok", false)), true, "the site reforges: %s" % str(result))
	assert_eq(String(result.get("reason", "")), DomainSecretRealm.OK_REFORGED, "named reforged")
	var mended: Dictionary = result.get("mended", {})
	assert_eq(bool(mended.get("ok", false)), true, "the mend lands")
	assert_almost_eq(float(mended.get("after", -1.0)), 0.1 + step, "by exactly the authored step")
	assert_almost_eq(FoundationApi.snapshot_for(actor, SITE_REALM), 0.1 + step, "on the record")
	assert_eq(float(result.get("years", 0.0)) > 0.0, true, "and it costs the body's life")
	assert_eq(actor.age_years > age_before, true, "which really ages the actor")
	assert_eq(String(result.get("trial_status", "")) != "", true, "and it inflicts its trial")
	assert_eq(
		actor.has_status(StringName(result.get("trial_status", ""))),
		true,
		"through a real status, never a bespoke damage channel"
	)
	assert_eq(bool(result.get("spent", false)), true, "and the site is now spent")
	# One time EVER: a second reforge at the same site is refused by name.
	assert_eq(
		String(_reforge(actor).get("reason", "")),
		DomainSecretRealm.ERR_ALREADY_REFORGED,
		"a second reforge is refused by name"
	)


## The telegraph is the read a screen renders BEFORE a player commits: free, non-mutating,
## and honest about both halves of the price.
func test_the_telegraph_is_free_and_leaves_the_actor_untouched() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.1)
	var age_before := actor.age_years
	var read := DomainSecretRealm.telegraph(actor, _room_of(SITE), SITE)
	assert_eq(bool(read.get("ok", false)), true, "the site telegraphs")
	assert_eq(String(read.get("realm_id", "")), String(SITE_REALM), "naming the realm it lands on")
	assert_eq(float(read.get("mend_step", 0.0)) > 0.0, true, "the step it pays")
	assert_eq(int(read.get("period_cost", 0)) > 0, true, "the life it spends")
	assert_eq(String(read.get("trial_status", "")) != "", true, "the trial it inflicts")
	assert_eq(bool(read.get("spent", true)), false, "unspent before it is committed")
	assert_almost_eq(FoundationApi.snapshot_for(actor, SITE_REALM), 0.1, "the record is untouched")
	assert_almost_eq(actor.age_years, age_before, "and so is the body's life")
	# A free read writes no ledger, so the site is still there to commit afterwards.
	assert_eq(bool(_reforge(actor).get("ok", false)), true, "so the site is still committable")


## A refusal costs nothing (ADR 0044): a site that could not pay must not age the actor
## who asked it to.
func test_reforge_refuses_a_realm_never_left_and_spends_nothing() -> void:
	var actor := _in_domain()
	var age_before := actor.age_years
	var result := _reforge(actor)
	assert_eq(bool(result.get("ok", true)), false, "a realm never left has no scar to mend")
	assert_eq(String(result.get("reason", "")), DomainSecretRealm.ERR_NO_SNAPSHOT, "named")
	assert_almost_eq(actor.age_years, age_before, "and a refusal costs no life")


func test_reforge_refuses_a_realm_at_the_mended_ceiling() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.9)
	var result := _reforge(actor)
	assert_eq(bool(result.get("ok", true)), false, "a realm at the ceiling has nothing to win")
	assert_eq(String(result.get("reason", "")), DomainSecretRealm.ERR_MEND_CAPPED, "named")


## The module owns the ceiling, not the avenue: a site whose step would overshoot stops at
## `MEND_CAP` rather than erasing the scar.
func test_a_reforge_stops_at_the_mended_ceiling() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.45)
	var result := _reforge(actor)
	assert_eq(bool(result.get("ok", false)), true, "the site reforges")
	var mended: Dictionary = result.get("mended", {})
	assert_almost_eq(
		float(mended.get("after", -1.0)), FoundationApi.MEND_CAP, "capped, never past it"
	)


## A caller may name the realm; the site's own authored realm is only the default.
func test_reforge_targets_an_explicit_realm() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.1)
	_seed(actor, OTHER_REALM, 0.2)
	var step := float(_authored(SITE).get("foundation_mend", 0.0))
	var result := _reforge(actor, OTHER_REALM)
	assert_eq(bool(result.get("ok", false)), true, "the site reforges the named realm")
	assert_almost_eq(FoundationApi.snapshot_for(actor, OTHER_REALM), 0.2 + step, "the named one")
	assert_almost_eq(FoundationApi.snapshot_for(actor, SITE_REALM), 0.1, "and not the site's own")


## Every refusal is named, never a `{}` a caller has to interpret.
func test_reforge_refusals_are_named() -> void:
	var actor := _in_domain()
	assert_eq(
		String(_reforge(actor, OTHER_REALM).get("reason", "")),
		DomainSecretRealm.ERR_NO_SNAPSHOT,
		"a realm with no snapshot is refused"
	)
	assert_eq(
		String(DomainSecretRealm.reforge(actor, _room_of(SITE), &"no_such_site").get("reason", "")),
		DomainSecretRealm.ERR_UNKNOWN_SITE,
		"a site no room authors is refused"
	)
	assert_eq(
		String(DomainSecretRealm.reforge(actor, _room_of(TRAP), TRAP).get("reason", "")),
		DomainSecretRealm.ERR_UNKNOWN_SITE,
		"a trap is not a mending site"
	)
	assert_eq(
		String(DomainSecretRealm.reforge(null, _room_of(SITE), SITE).get("reason", "")),
		DomainSecretRealm.ERR_NO_ACTOR,
		"a null actor is named"
	)


func test_reforge_refuses_outside_a_run() -> void:
	var actor := _actor()
	_seed(actor, SITE_REALM, 0.1)
	var result := DomainSecretRealm.reforge(actor, _room_of(SITE), SITE)
	assert_eq(bool(result.get("ok", true)), false, "outside a run there is no site")
	assert_eq(String(result.get("reason", "")), DomainSecretRealm.ERR_NO_RUN, "named")


## The ledger is a SIBLING of the fixture ledger, so `DomainApi.enter` (which re-arms
## traps) must NOT re-arm a consumed site: a secret realm is spent for the life of the
## actor, not per run.
func test_a_site_is_spent_for_the_life_of_the_actor_not_the_run() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.1)
	assert_eq(bool(_reforge(actor).get("ok", false)), true, "the site is spent once")
	DomainApi.leave(actor)
	assert_eq(
		bool(DomainApi.enter(actor, _map(), &"ember_hollow").get("ok", false)),
		true,
		"the actor re-enters a domain"
	)
	assert_eq(
		String(_reforge(actor).get("reason", "")),
		DomainSecretRealm.ERR_ALREADY_REFORGED,
		"and the consumed site is still consumed"
	)


## ADR 0027: state rides in `actor.module_data`, String-keyed and JSON-clean, so a spent
## site survives a save without a leaked `StringName` breaking it.
func test_a_spent_site_survives_a_save() -> void:
	var actor := _in_domain()
	_seed(actor, SITE_REALM, 0.1)
	assert_eq(bool(_reforge(actor).get("ok", false)), true, "reforged")
	var parsed: Variant = JSON.parse_string(
		JSON.stringify(actor.get_module_data(DomainApi.MODULE_KEY))
	)
	assert_eq(parsed is Dictionary, true, "the run state stays JSON-clean with a site in it")
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(
		String(DomainSecretRealm.reforge(restored, _room_of(SITE), SITE).get("reason", "")),
		DomainSecretRealm.ERR_ALREADY_REFORGED,
		"a loaded site is still spent"
	)


## The facade read model reports the site and its true state, so a screen has one place
## to read it — the same move `fixtures` made rather than a thirteenth facade verb.
func test_the_read_model_reports_the_site_and_its_spent_state() -> void:
	var actor := _in_domain()
	var sites := DomainApi.summary(actor).get("sites", {}) as Dictionary
	assert_eq(int(sites.get("count", 0)), _authored_sites().size(), "one row per authored site")
	assert_eq(bool(_site_row(actor, SITE).get("spent", true)), false, "unspent before")
	assert_eq(
		String(_site_row(actor, SITE).get("realm_id", "")), String(SITE_REALM), "naming its realm"
	)
	_seed(actor, SITE_REALM, 0.1)
	assert_eq(bool(_reforge(actor).get("ok", false)), true, "reforged")
	assert_eq(bool(_site_row(actor, SITE).get("spent", false)), true, "reported spent after")
	var parsed: Variant = JSON.parse_string(JSON.stringify(sites))
	assert_eq(parsed is Dictionary, true, "and the site read model is JSON-clean")
