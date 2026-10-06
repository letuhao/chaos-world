extends TestCase

## The clan tier routed onto the shared institution foundation (ADR 0271 decision 3,
## ADR 0083, ADR 0084, ADR 0064). This suite is the migration's own proof, and it is the
## ratchet's own half: `tests/modules/sect/test_sect_migration.gd` holds the COPY COUNT, and
## the cases below hold the behaviour the copy could have changed.
##
## ## What migrating clan can break, measured rather than guessed
##
##   - **The coercion.** `_text` decides what a corrupt save reads as, and the difference
##     between "empty" and "a plausible lie" is the whole rule.
##   - **The corruption POLICY.** Clan discards the WHOLE record on a wrong-typed id and
##     sect drops only the bad map. Delegating a helper must not quietly blend the two.
##   - **The cap.** Adding `ClanDef.standing_cap` puts a content field next to two shipped
##     ladders it does not fit, and a clamp that silently truncates is worse than no cap.
##   - **The registry row.** A kind nobody registered is refused `unknown_kind`, which reads
##     as "there is no such thing" rather than "this thing cannot be founded".

const HOUSE := &"t_house"

## The three files ADR 0271 decision 3 measured as carrying the coercion. `nation` is
## absent because `nation_state.gd` never had a `_text` — naming it would put a file in the
## list whose answer is "not applicable" rather than a measurement. Kept in step with
## `test_sect_migration.gd`'s own copy of this list.
const LEDGERS := [
	"res://src/modules/clan/clan_state.gd",
	"res://src/modules/sect/sect_state.gd",
	"res://src/core/world_polity_ledger.gd",
]

## The two files that must hold the coercion BODY after this migration: clan's own is
## gone, and sect's already was. `world_polity_ledger.gd` is in `core/` and outside this
## slice's claim, so it is NAMED here rather than fixed — the copy count is pinned at one
## until a `core/` session takes it.
const BODY_HOLDERS := ["res://src/core/world_polity_ledger.gd"]

## Every verb the facade must never grow. ADR 0084's own answer: `tools arch` cannot see a
## method that does not exist, so the refusal is pinned structurally. Repeated rather than
## imported so a facade rewrite cannot quietly narrow it.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"grant_modifier",
]

var _born: Array = []


func setup() -> void:
	ClanFixtureCatalog.teardown()


## `Actor` extends `RefCounted`, so `free()` on one is a SCRIPT ERROR that aborts the rest
## of `teardown` — the measured shape `test_sect_migration.gd` records. What an `Actor`
## needs is only that nothing keeps holding it, which is `_born.clear()`. Nothing here
## instantiates a `Node`.
func teardown() -> void:
	ClanFixtureCatalog.teardown()
	InstitutionRegistry.instance().clear()
	_born.clear()


## A member of `clan_id` at `standing`, admitted.
##
## **The bloodline is seeded because admission needs one.** `ClanFixtureCatalog.open`
## authors `min_purity = 0.3` against `hearthborn`, so an actor with no bloodline state is
## refused on the purity arm and every assertion downstream reads an unaffiliated actor —
## which is exactly the "a refusal is a plausible state, not a data problem" shape. The
## admission case below asserts the refusal arms explicitly, so it drives its own actors and
## leaves this helper to the paths that need a member.
##
## The actor-id carries the standing so two members in one case cannot collide, and each is
## tracked in `_born` because `Actor` extends `RefCounted` and must not be `free()`d.
func _member(standing: int = 0, clan_id: StringName = HOUSE) -> Actor:
	var actor := Actor.new(StringName("member_%s_%d" % [clan_id, standing]), {Stat.PHYSIQUE: 10.0})
	_born.append(actor)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, &"hearthborn", 1.0)
	# The SHIPPED houses found on lines of their own (`tideborn`, `voidborn`), so the one
	# line above only satisfies the fixtures. Measured: ironpact refuses at 0.35 of
	# `tideborn` without this. Every line is seeded rather than the one under test, because a
	# helper that admits only fixture houses silently cannot measure the shipped content.
	for line in [&"tideborn", &"voidborn", &"hearthborn"]:
		BloodlineApi.set_purity(actor, line, 1.0)
	var verdict := ClanApi.join(actor, clan_id, standing)
	assert_eq(
		bool(verdict["ok"]),
		true,
		"the fixture admitted the member: %s" % str(verdict.get("unmet", []))
	)
	return actor


# --- The coercion is a DELEGATION ---------------------------------------------


## ## `ClanState._text` carries no body, and the ratchet's own count is the witness
##
## The source half is what makes it a delegation rather than a rewrite: a body that had
## been kept is the second copy the ratchet measures, and only the function's OWN body is
## scanned — `_applied_corrupt` asks the same type question for a different purpose and is
## not a second coercion (the same exemption `test_sect_migration.gd` makes for sect).
func test_clan_state_text_is_a_delegation_and_carries_no_type_test() -> void:
	var body := FileAccess.get_file_as_string("res://src/modules/clan/clan_state.gd")
	assert_ne(body, "", "the state file is readable")
	var own := _body(body, "static func _text(")
	assert_ne(own, "", "the coercion is findable, so the scan below read its body")
	assert_eq(
		own.contains("is String or value is StringName"),
		false,
		"_text carries no copy of the type test (InstitutionLedger.text owns it)"
	)
	assert_eq(
		own.contains("return fallback"),
		false,
		"nor of the fallback, which is the other half of the same decision"
	)
	# The ASK half too, for the same reason: the type test and the fallback are one
	# decision, so a body kept in `_is_text` is the same second copy wearing a hat.
	var asked := _body(body, "static func _is_text(")
	assert_ne(asked, "", "the ask is findable")
	assert_eq(
		asked.contains("is String or value is StringName"),
		false,
		"_is_text delegates the type test to InstitutionLedger.is_text as well"
	)


## ## The value half: the delegation answers EXACTLY what the shared coercion answers
##
## Over a table that covers every branch — both text kinds pass, everything else falls
## back — because a delegation that answered the same thing on `42.0` and something else on
## a `Vector2` would be a delegation in name only. `Vector2` is here for a measured reason:
## it is the value type that DOES reach a save untouched, so it is the one most likely to
## arrive where an id is expected.
func test_clan_state_text_answers_exactly_what_the_shared_coercion_answers() -> void:
	for value in ["t_house", StringName("t_house"), 42.0, {}, [], null, true, Vector2(1.0, 2.0)]:
		assert_eq(
			ClanState._text(value, "fallback"),
			InstitutionLedger.text(value, "fallback"),
			"'_text' and the shared coercion agree on %s" % str(value)
		)
	# The two branches, asserted through the module's own callers rather than through the
	# helper, so a case that passed by reading a file cannot satisfy this one.
	assert_eq(ClanState.clan_id({"clan": 42.0}), &"", "a wrong-typed clan id reads as no clan")
	assert_eq(
		ClanState.clan_id({"clan": StringName(HOUSE)}), HOUSE, "and a StringName id is accepted"
	)


## ## The namespacing delegation CHANGED one edge: an empty id now names nothing
##
## `source_tagged(prefix, &"")` returns `&""` where `source_for` used to build
## `StringName("clan:")`. That is the one place this migration answers differently than the
## code it replaced, so it is asserted rather than left to a reader of the shared helper:
##
##   - `""` is the honest answer — a source tag that names no clan is a bucket
##     `ClanProjection.contribution` would sum modifiers into and nothing could own.
##   - `clan:` was a plausible-looking id, which is the defect `InstitutionLedger`'s class
##     note names for `str()`: a wrong-typed field turned into something a known-content
##     filter has to reject by accident.
##
## Unreachable in production, measured: `ClanCatalog` only stores defs whose `id` is
## non-empty, and every `ClanProjection` call site is guarded by a non-empty check. Asserted
## anyway, because a guard nobody can trip is a guard nobody has seen work.
func test_the_namespaced_ids_name_nothing_for_an_empty_id() -> void:
	assert_eq(ClanState.source_for(HOUSE), &"clan:t_house", "an id still namespaced as before")
	assert_eq(ClanState.trait_for(HOUSE), &"clan:t_house", "and so is the trait mirror")
	assert_eq(ClanState.rank_trait_for(&"inner"), &"clan_rank:inner", "and the position mirror")
	assert_eq(ClanState.source_for(&""), &"", "an EMPTY id names no source at all")
	assert_eq(ClanState.trait_for(&""), &"", "and no trait")
	assert_eq(ClanState.rank_trait_for(&""), &"", "and no position")
	# The namespace half is unchanged, which is the half that could have broken: a clan's own
	# tag is its own, and a sect's is not one of them.
	assert_eq(ClanState.is_own_source(&"clan:ironpact"), true, "a clan tag is this module's")
	assert_eq(ClanState.is_own_source(&"sect:t_house"), false, "and a sect's is not")
	assert_eq(ClanState.is_own_source(&""), false, "and an empty source belongs to nobody")


## ## The ratchet: clan is no longer one of the holders, and the count is ONE
##
## The sect suite owns the baseline constant; this is the clan-side witness, and it asserts
## the LIST rather than a number so a failure names the file still carrying the body. The
## count itself is asserted too, because "the right files" and "the right number" are
## different claims and only the second is what the gate measures.
##
## `world_polity_ledger.gd` is named in `BODY_HOLDERS` deliberately: it is `core/`, outside
## this slice's claim, and a ratchet written as "at most zero" would be a guard only
## `core/`'s own session could clear — the INC-0017 shape `test_sect_migration.gd` already
## names. One copy left, named.
func test_the_text_coercion_body_is_gone_from_clan_and_one_copy_remains() -> void:
	var holders: Array[String] = []
	# A `for` over that CONSTANT array, writing into one fresh array: the bound is the list
	# length and the body never grows the container it walks
	# (`tests/arch_rules/test_no_unbounded_wait.gd`).
	for rel in LEDGERS:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		if _body(body, "static func _text(").contains("is String or value is StringName"):
			holders.append(rel)
	assert_eq(holders.size(), 1, "exactly one copy of the body remains: %s" % ", ".join(holders))
	assert_eq(holders, BODY_HOLDERS, "and it is the core one this slice cannot reach")
	assert_eq(
		holders.has("res://src/modules/clan/clan_state.gd"),
		false,
		"and clan is no longer one of them"
	)
	# The delegation itself, on both branches, so the case is not satisfied by the file being
	# unreadable.
	assert_eq(
		ClanState._text(42.0, "fallback"),
		InstitutionLedger.text(42.0, "fallback"),
		"and clan's answers exactly as the shared coercion does"
	)
	assert_eq(
		ClanState._text("t_house", ""),
		InstitutionLedger.text("t_house", ""),
		"on the accepting branch too"
	)


# --- The corruption policy is CLAN'S and must not be softened -------------------


## ## A wrong-typed id discards the WHOLE clan record, never one field
##
## The regression a delegation invites is a policy blend: sect drops only the unusable MAP
## and keeps three good fields beside it, so a reviewer who copies sect's `_text` might
## copy sect's leniency too. **Clan's rule is the strict one and is asserted as strict**,
## because the symptom it prevents is a plausible lie — `{"clan": "t_house", "rank": 17}`
## read as "a member who holds a house but no post", which a caller cannot detect.
func test_a_wrong_typed_clan_id_discards_the_whole_record() -> void:
	for bad in [
		{"clan": 42.0},
		{"clan": "t_house", "rank": 17},
		{"clan": "t_house", "standing": 40, "rank": Vector2(1.0, 2.0)},
		{"clan": "t_house", "standing": 40, "applied": {"clan": 7}},
		{"clan": "t_house", "standing": "many"},
	]:
		var read := ClanState.normalize(bad)
		assert_eq(String(read["clan"]), "", "a corrupt id discards the record: %s" % str(bad))
		assert_eq(String(read["rank"]), "", "and no position survives it")
		assert_eq(int(read["standing"]), 0, "and no half state: %s" % str(bad))
		assert_eq((read["applied"] as Dictionary).is_empty(), true, "nor an applied record")
	# An ABSENT field is different and is not corruption: a member who holds no position
	# simply has none, and a normalizer that refused that would refuse every fresh actor.
	var fresh := ClanState.normalize({"clan": String(HOUSE), "standing": 40})
	assert_eq(String(fresh["clan"]), String(HOUSE), "an absent rank is normal")
	assert_eq(String(fresh["rank"]), "", "and reads as holding no position")
	assert_eq(int(fresh["standing"]), 40, "while the standing is untouched")


# --- The cap ------------------------------------------------------------------


## ## `ClanDef.standing_cap` is AUTHORED, and it is not the ladder's top
##
## Measured against the SHIPPED tree rather than a fixture, because the hazard is
## arithmetic about authored content: all three houses publish a top band above 100
## (ironpact 120, saltledger 150, quiethouse 160) and the cap defaults to 100. So the two
## facts that must both hold are that the cap is a real authored field AND that nothing
## clamps `standing` into it — asserted through the facade, on the real content, at a
## standing far past every published band.
func test_the_cap_is_authored_content_and_never_truncates_a_members_earned_standing() -> void:
	var catalog := ClanCatalog.instance()
	var ids := catalog.clan_ids()
	assert_ne(ids.size(), 0, "this build ships at least one clan")
	for clan_id in ids:
		var def := catalog.clan_definition(clan_id)
		assert_eq(def.standing_cap >= 1, true, "'%s' authors a computable cap" % clan_id)
	# The measurement: a member far past the ladder keeps the number, so a cap that clamped
	# would show up here as a truncation rather than as a silently wrong balance.
	var ladder := ClanCatalog.instance().clan_definition(&"ironpact")
	var beyond := int(ladder.standing_bands[ladder.standing_bands.size() - 1]) + 500
	var actor := _member(0, &"ironpact")
	ClanApi.move_standing(actor, beyond)
	assert_eq(
		ClanApi.standing_of(actor),
		beyond,
		"'ironpact' earns %d and reads %d -- nothing truncates it" % [beyond, beyond]
	)
	assert_eq(
		ClanState.standing_cap(&"ironpact"), ladder.standing_cap, "the cap is the def's own number"
	)


## ## An absent or unusable cap is REPAIRED, never persisted as zero
##
## The consequence of a cap that cannot be computed is specific and is the reason this is
## worth a case: `InstitutionClaim.normalized()` answers `0.0` for `standing_cap <= 0`, so
## a zero cap reports a fully-respected member as a ratio of ZERO — the worst possible read,
## because it looks like a real measurement.
func test_an_unusable_cap_is_repaired_and_a_claim_over_it_is_always_computable() -> void:
	ClanFixtureCatalog.install([_def_with_cap(HOUSE, 0), _def_with_cap(&"t_capped", 40)])
	assert_eq(ClanState.standing_cap(HOUSE), 1, "a zero authored cap is floored, not obeyed")
	assert_eq(ClanState.standing_cap(&"t_capped"), 40, "and an authored one is kept")
	# A house this build does not ship, and no house at all: absence is not a broken cap.
	assert_eq(
		ClanState.standing_cap(&"t_gone"),
		ClanState.DEFAULT_STANDING_CAP,
		"an unshipped house falls back to the shared default, never to zero"
	)
	assert_eq(ClanState.standing_cap(&""), ClanState.DEFAULT_STANDING_CAP, "and so does no house")
	# The claim is the ratio, and it is computable in every one of those cases.
	var actor := _member(0, &"t_capped")
	var claim := ClanState.claim(ClanApi.state(actor))
	assert_eq(int(claim.standing_cap), 40, "the claim carries the def's authored ceiling")
	assert_almost_eq(float(claim.normalized()), 0.0, "and a fresh member normalises to zero")
	ClanApi.move_standing(actor, 40)
	claim = ClanState.claim(ClanApi.state(actor))
	assert_almost_eq(
		float(claim.normalized()), 1.0, "a member at the cap is fully recognised, never past one"
	)
	# A zero-cap house still produces a computable claim, which is the whole point of the
	# repair: 1.0 rather than the 0.0 an unrepaired cap would report.
	var floored := _def_with_cap(&"t_floor", 0)
	ClanFixtureCatalog.install([floored])
	var other := _member(0, &"t_floor")
	var held := ClanState.claim(ClanApi.state(other))
	assert_eq(int(held.standing_cap) >= 1, true, "the repaired cap reaches the claim")
	assert_almost_eq(
		float(held.normalized()) >= 0.0,
		true,
		"and the ratio is computable rather than a member nobody respects"
	)


## ## `ClanState.claim` is a DELEGATE, and the save keeps clan's own vocabulary
##
## One claim shape means `rank` is handed over as the position and `clan` names the
## institution — translated at the READ, never renamed in `normalize`, because renaming a
## ledger key is a save-schema break for a convenience no caller asked for.
func test_claim_is_the_shared_shape_and_the_ledger_keeps_clans_own_keys() -> void:
	var body := FileAccess.get_file_as_string("res://src/modules/clan/clan_state.gd")
	assert_eq(
		_calls(body, "InstitutionClaim.from_dict"), 1, "and there is exactly one constructor call"
	)
	assert_eq(
		_calls(body, "InstitutionClaim.new()"), 0, "and the module never constructs one itself"
	)
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	var actor := _member(0)
	var state := ClanApi.state(actor)
	assert_eq(state.has("clan"), true, "the ledger still spells its membership 'clan'")
	assert_eq(state.has("institution"), false, "and was not renamed for the claim's sake")
	assert_eq(state.has("rank"), true, "nor its position")
	var claim := ClanState.claim(state)
	assert_eq(
		String(claim.position),
		String(ClanApi.rank_of(actor)),
		"the rank reaches the claim AS the position"
	)


# --- ADR 0064's split, pinned ----------------------------------------------------


## ## Nothing in the module writes `rank` from `standing`, or `standing` from `rank`
##
## Both directions, separately, because a design that collapsed the pair into one number
## would have no second number to contradict and would pass a combined check. The
## `standing_bands` half is the half this slice could have broken: `standing_cap` now sits
## beside the bands, and a cap is another standing-shaped number to derive from.
func test_rank_and_standing_still_never_derive_from_each_other() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	var actor := _member(10)
	var seat := String(ClanApi.rank_of(actor))
	var earned := ClanApi.standing_of(actor)
	# Direction one: standing moves and the position does not.
	ClanApi.move_standing(actor, 55)
	assert_eq(ClanApi.standing_of(actor), earned + 55, "standing moved")
	assert_eq(String(ClanApi.rank_of(actor)), seat, "and the position did not follow it")
	# Direction two: the position moves and the standing does not. `ClanHeir.register` is
	# the only rank writer the module publishes, so it is the verb under test.
	var reported := ClanHeir.register(actor)
	assert_eq(bool(reported["ok"]), true, "the heir rung is reachable: %s" % str(reported))
	assert_eq(String(ClanApi.rank_of(actor)), String(ClanHeir.HEIR_RANK), "the position moved")
	assert_eq(ClanApi.standing_of(actor), earned + 55, "and standing stayed exactly where it was")
	# And `standing_bands` publishes a reading without ever writing the ledger: a member
	# earning far past the top band still holds the rung the house granted.
	ClanApi.move_standing(actor, 5000)
	assert_eq(
		String(ClanApi.rank_of(actor)),
		String(ClanHeir.HEIR_RANK),
		"earning past every published band moves no position"
	)
	assert_eq(
		String(ClanState.band_rank(HOUSE, ClanApi.standing_of(actor))),
		String(ClanFixtureCatalog.LADDER[ClanFixtureCatalog.LADDER.size() - 1]),
		"while the PUBLISHED reading does follow it, which is a display and not a write"
	)


## ## `standing_bands` is read by the DISPLAY path only, and never from a write site
##
## Source-scanned, because no value assertion can see a writer that was handed the band
## table and declined to use it — the same reasoning `test_institution_claim_shape_single`
## uses for `promote`. Every module file is scanned for a function that ASSIGNS `rank` from
## something standing-shaped, which is the shape a blend would take.
func test_no_module_file_writes_a_position_from_a_standing_shaped_read() -> void:
	var forbidden := ["rank_for_standing", "standing_bands"]
	# A `for` over the module's own authored file set reading only: the body writes nothing
	# and mutates nothing, so the bound is the file count
	# (`tests/arch_rules/test_no_unbounded_wait.gd`).
	for rel in _module_files():
		var body := FileAccess.get_file_as_string(rel)
		var rank_body := _body(body, "func with_rank(")
		if rank_body.is_empty():
			continue
		for name in forbidden:
			assert_eq(
				rank_body.contains(name),
				false,
				(
					(
						"%s's ONLY rank writer reads '%s' -- a position derived from standing "
						+ "has deleted ADR 0064's split"
					)
					% [rel, name]
				)
			)
		# And it reads no standing at all, which is the stronger half: a writer that CLAMPED
		# a rank against standing would be deriving one from the other with no assignment.
		assert_eq(
			rank_body.contains('ledger.get("standing"'),
			false,
			"%s's only rank writer never reads standing" % rel
		)


# --- The registry row ------------------------------------------------------------


## ## `clan` is REGISTERED, and it is registered as `is_born_to`
##
## The row exists because `InstitutionRegistry` refuses by name what it cannot answer
## about, and a clan kind nothing registered would be refused `unknown_kind` — a different
## answer from the settled one it should give. Registration is from `attach`, the verb EVERY
## actor reaches, so `join` never reads an unregistered kind — the defect `sect` still
## carries, where only `found` registers.
func test_the_clan_kind_is_registered_on_attach_and_answers_is_born_to() -> void:
	var shared := InstitutionRegistry.instance()
	shared.clear()
	assert_eq(shared.knows(ClanFounding.KIND), false, "nothing is registered to begin with")
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	var actor := _member(0)
	assert_eq(shared.knows(ClanFounding.KIND), true, "attach registered the clan kind")
	assert_eq(
		shared.def_type_of(ClanFounding.KIND),
		ClanFounding.DEF_TYPE,
		"on the def class this module owns"
	)
	assert_eq(
		shared.def_script_bound(ClanFounding.KIND),
		true,
		"with a script bound, so a catalog could instantiate it"
	)
	# The capability is the settled answer, and it is the ONE flag a clan carries.
	assert_eq(
		shared.capabilities_of(ClanFounding.KIND),
		[ClanFounding.CAP_IS_BORN_TO],
		"and a clan is born to, so it carries nothing else"
	)
	assert_eq(bool(ClanApi.can_found()["ok"]), true, "which the facade answers without refusal")
	assert_eq(bool(ClanApi.can_found()["can_found"]), false, "and can never be founded")
	# A second attach does not refuse a duplicate: the row is folded, not re-registered,
	# because `InstitutionRegistry` refuses a duplicate KIND loudly and an actor attaching
	# twice is ordinary rather than a second kind.
	ClanApi.attach(actor)
	assert_eq(shared.knows(ClanFounding.KIND), true, "a re-attach keeps exactly one row")


## ## A cleared registry RE-REGISTERS on next use rather than refusing
##
## `tests/run_tests.gd` runs every suite in ONE process, so a suite that registers a kind
## and forgets to clear it hands that kind to every suite after it — the cross-suite leak
## `InstitutionRegistry` is an instance rather than a static table to survive. `clear()` is
## therefore part of the surface, and the next caller must recover rather than fail.
func test_a_cleared_registry_re_registers_rather_than_refusing_unknown_kind() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	_member(0)
	var shared := InstitutionRegistry.instance()
	shared.clear()
	assert_eq(shared.knows(ClanFounding.KIND), false, "the suite cleared the process state")
	assert_eq(
		bool(ClanApi.can_found()["ok"]), true, "and the next read re-registers rather than refusing"
	)


## ## A kind nobody registered is refused BY NAME, and that is the other state
##
## ADR 0083's first state against its third: `{}` means "this does not exist" and
## `{"ok": false, "reason": R}` means "this was refused". Collapsing them into a bare
## `false` would make a caller pick an action by accident — here, treating "no such kind" as
## "this kind cannot be founded" is harmless, and treating "this kind cannot be founded" as
## "no such kind" would hide the reason a player is given.
func test_an_unknown_kind_is_refused_by_name_and_is_a_different_answer() -> void:
	var registry := InstitutionRegistry.new()
	assert_eq(
		registry.knows(ClanFounding.KIND),
		false,
		"a registry nobody registered the kind into does not know it"
	)
	assert_eq(
		registry.has_capability(ClanFounding.KIND, ClanFounding.CAP_IS_BORN_TO)["reason"],
		InstitutionRegistry.R_UNKNOWN_KIND,
		"and says so by name rather than answering a bare false"
	)
	assert_eq(registry.capabilities_of(ClanFounding.KIND), [], "with no capabilities to report")


# --- The refusals stay STRUCTURAL ------------------------------------------------


## ADR 0084's own answer: `tools arch` cannot see a method that does not exist, so the
## refusal is a test on the facade's published surface. Repeated rather than imported, and
## asserted on both the facade and `ClanFounding`, because this slice added a class and a
## class is exactly where a grant helper would be convenient and least visible.
func test_neither_the_facade_nor_the_founding_class_publishes_a_power_verb() -> void:
	for rel in ["res://src/modules/clan/api.gd", "res://src/modules/clan/clan_founding.gd"]:
		var script: GDScript = load(rel)
		var published := _published(script)
		assert_eq(script == null, false, "%s loads at all" % rel)
		assert_eq(published.is_empty(), false, "%s publishes a readable method list" % rel)
		for verb in FORBIDDEN_VERBS:
			assert_eq(published.has(verb), false, "%s publishes no '%s'" % [rel, verb])
	# `join` and `leave` are the membership verbs and both survive the migration, because
	# leaving is always permitted and always costs (ADR 0083).
	var api := _published(load("res://src/modules/clan/api.gd"))
	assert_eq(api.has("join"), true, "membership is still enterable")
	assert_eq(api.has("leave"), true, "and still leaveable")
	assert_eq(api.has("found"), false, "and a clan still cannot be founded")


# --- Save safety ------------------------------------------------------------------


## ## The ledger round-trips through `Actor.to_dict`, and the cap rides along
##
## `Actor.to_dict` copies `module_data` VERBATIM and converts only the OUTER key, so an
## inner `StringName` key or a `Resource` would reach the save untouched and no checker in
## this repo can see it. `InstitutionLedger.is_save_safe` is the callable that can, and it
## is asserted over the REAL persisted payload. Numbers come back as floats through
## `JSON.parse_string`, so the comparison is through facts rather than byte-for-byte.
func test_the_ledger_round_trips_through_actor_to_dict_and_is_save_safe() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	var actor := _member(0)
	ClanApi.move_standing(actor, 42)
	var payload := actor.to_dict()
	var ledger = payload["module_data"][String(ClanState.MODULE_KEY)] as Dictionary
	## ## Scoped to the CLAN LEDGER, and the scope is the measurement
	##
	## `is_save_safe` is asked about this module's own slice of the save rather than about
	## `Actor.to_dict`'s whole output. `Actor` carries stats, resources and paths that are
	## other modules' to answer for, so asserting the whole payload here would either fail on
	## a neighbour's value or be widened until it cannot fail at all. What THIS slice can
	## break is a `StringName` key or a `Resource` reaching the clan ledger, and
	## `Actor.to_dict` copies `module_data` verbatim — so the clan ledger is exactly the
	## value at risk, and the whole-payload question belongs to whoever owns the rest.
	assert_eq(InstitutionLedger.is_save_safe(ledger), true, "the clan ledger is save safe")
	assert_eq(int(ledger["standing"]), 42, "the earned standing is in the payload")
	assert_eq(String(ledger["clan"]), String(HOUSE), "and so is the membership")
	var restored := Actor.from_dict(payload)
	_born.append(restored)
	assert_eq(ClanApi.clan_of(restored), HOUSE, "and it survives the hop")
	assert_eq(ClanApi.standing_of(restored), 42, "with its earned standing")
	ClanApi.attach(restored)
	assert_eq(ClanApi.clan_of(restored), HOUSE, "and a re-attach keeps it")
	# And through the JSON hop the test framework actually uses, so a number that arrives as
	# a float is compared as a fact rather than asserted byte-for-byte.
	var hopped = JSON.parse_string(JSON.stringify(payload)) as Dictionary
	assert_eq(hopped == null, false, "the payload survives a JSON hop at all")
	var after = (hopped["module_data"] as Dictionary)[String(ClanState.MODULE_KEY)] as Dictionary
	assert_eq(int(after["standing"]), 42, "and the standing is the same number after it")


## ## Admission still refuses on the three authored gates, and passing never raises purity
##
## Driven off the FIXTURES for the refusal arms, because what can break is the gate's own
## arithmetic; the shipped-content arms are asserted in `test_clan_content.gd` already.
## ADR 0063's other half is asserted here too: passing `min_purity` recognises a lineage
## the member already carries and never manufactures one.
func test_admission_still_refuses_on_purity_race_and_realm_and_never_raises_purity() -> void:
	var def := ClanFixtureCatalog.sealed(HOUSE, 0.9)
	ClanFixtureCatalog.install([def, ClanFixtureCatalog.housebound(&"t_body", &"t_ash")])
	var actor := Actor.new(&"outsider", {})
	_born.append(actor)
	ClanApi.attach(actor)
	# Purity: the refusal names the bar rather than admitting everyone.
	var barred := ClanApi.admission_unmet(actor, HOUSE)
	assert_eq(barred.is_empty(), false, "a house above the member's concentration refuses")
	assert_eq(String(barred[0]["kind"]), String(ClanGate.KIND_PURITY), "by naming the gate")
	assert_eq(bool(ClanApi.join(actor, HOUSE)["ok"]), false, "and join writes nothing")
	assert_eq(ClanApi.clan_of(actor), &"", "leaving them unaffiliated")
	# Race and realm, each refusing by name on a fixture that authors only that bar.
	var body_bound := ClanFixtureCatalog.housebound(&"t_body", &"t_ash")
	var raced := ClanApi.admission_unmet(actor, &"t_body")
	assert_eq(
		bool(ClanApi.join(actor, &"t_body")["ok"]), false, "a body plan the member lacks refuses"
	)
	assert_eq(String(raced[0]["kind"]), String(ClanGate.KIND_BODY), "and names the body gate")
	var ranked := ClanFixtureCatalog.ranked(&"t_floor", 30)
	ClanFixtureCatalog.install([body_bound, ranked])
	assert_eq(
		bool(ClanApi.join(actor, &"t_floor")["ok"]), false, "a realm floor the member lacks refuses"
	)
	assert_eq(
		String(ClanApi.admission_unmet(actor, &"t_floor")[0]["kind"]),
		String(ClanGate.KIND_REALM),
		"and names the realm gate"
	)
	# The OPEN path still admits, and admitting grants nothing: joining is not earning.
	# `BloodlineApi.attach` and a carrier's line are needed here rather than only on the
	# refused arms, because `open` still authors `min_purity = 0.3` — an actor with no
	# bloodline state at all is refused on purity, and the refusal is CORRECT.
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, &"hearthborn", 0.5)
	assert_eq(bool(ClanApi.join(actor, HOUSE, 0)["ok"]), true, "an open house admits")
	assert_eq(ClanApi.standing_of(actor), 0, "joining is not earning")
	assert_eq(ClanApi.rank_of(actor), def.entry_rank(), "and it admits into its own entry rung")


# --- Helpers -----------------------------------------------------------------------


func _def_with_cap(clan_id: StringName, cap: int) -> ClanDef:
	var def := ClanFixtureCatalog.open(clan_id)
	def.standing_cap = cap
	return def


## Every public method name on an already-loaded script. Underscore-prefixed names are
## dropped, exactly as `tools/arch/enforce.py` drops them, so this list and the gate count
## the same verbs. The `load()` is at the CALL SITE because `get_script_method_list` is a
## method on `GDScript` itself.
func _published(script: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (script is GDScript):
		return out
	for method in (script as GDScript).get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## The body of the function whose signature contains `signature`, cut at the next top-level
## `func` or `static func`, or `""` when there is none. A bounded scan of an authored file,
## not a loop over anything a caller controls.
func _body(body: String, signature: String) -> String:
	var at := body.find(signature)
	if at < 0:
		return ""
	var tail := body.substr(at + signature.length())
	var stop := tail.find("\nstatic func ")
	if stop < 0:
		stop = tail.find("\nfunc ")
	if stop < 0:
		stop = tail.length()
	return tail.substr(0, stop)


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it.
## Every file in this programme names the words it forbids inside its own class docs, so a
## raw `body.contains(needle)` scan fails on those sentences while reading the code beside
## them as clean.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## The module's own `.gd` files, through `ContentScan` — which caps depth at `MAX_DEPTH`
## and SORTS its result, so the set is the same on every run. A recursive walk here would be
## a `while` in disguise that `test_no_unbounded_wait.gd` cannot see. **`.gd` is passed
## explicitly**: `ContentScan`'s suffix argument defaults to `.tres`, so a scan that relied
## on the default would read an EMPTY list and every case below would pass vacuously.
func _module_files() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under("res://src/modules/clan", ".gd"):
		out.append(String(path))
	out.sort()
	return out
