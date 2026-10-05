extends TestCase

## The kind registry: what an institution kind IS, and the two answers a caller must
## never confuse.
##
## The suite exists because the registry has exactly one interesting failure mode —
## collapsing "no such kind" into "this kind does not teach" — and because the
## duplicate-kind rule is a decision rather than a default. Everything else here is
## the ADR 0084 structural half: the published surface grants no power, and a
## capability is never a stat.

## A def script the tests register against. **A script under `res://tests/` rather
## than a module's**, because `core/` may not name `modules/` and a registration that
## reached for `SectDef` would be the boundary violation the design exists to avoid.
const DEF := preload("res://tests/core/institution_registry_fixture_def.gd")

## Every verb a kind registry must never grow. If one of these appears on
## `InstitutionRegistry`, an institution has grown a way to hand out a stat, and
## ADR 0084 says it never may. `tools arch` cannot see a method that does not exist,
## so the guard is this test — the same shape `test_sect_no_power.gd` uses.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"grant_modifier",
	"contribute",
]

## The three shipped kinds, and what each one is.
##
## `clan` is BORN TO and teaches nothing and authors offices; `sect` is sworn to,
## teaches, and authors offices; `nation` is lived under, teaches nothing, and has
## territory. The flags are the whole registry surface, so a wrong flag here is a
## wrong gate somewhere later.
const CLAN := &"clan"
const SECT := &"sect"
const NATION := &"nation"

var _registry: InstitutionRegistry = null


func setup() -> void:
	_registry = InstitutionRegistry.new()


## Every suite in this process shares it, so a registration a suite leaves behind is
## handed to every suite after it. `InstitutionRegistry.clear()` is the counterpart to
## `register` for exactly that reason.
func teardown() -> void:
	if _registry != null:
		_registry.clear()
		_registry = null


## The three shipped kinds, registered. Returns the registry so a case can chain.
func _shipped() -> InstitutionRegistry:
	_registry.register(
		CLAN,
		"ClanDef",
		[InstitutionRegistry.CAP_IS_BORN_TO, InstitutionRegistry.CAP_HAS_OFFICES],
		DEF
	)
	(
		_registry
		. register(
			SECT,
			"SectDef",
			[
				InstitutionRegistry.CAP_TEACHES,
				InstitutionRegistry.CAP_HAS_OFFICES,
				InstitutionRegistry.CAP_HAS_TERRITORY,
			],
			DEF
		)
	)
	_registry.register(
		NATION,
		"NationDef",
		[InstitutionRegistry.CAP_HAS_OFFICES, InstitutionRegistry.CAP_HAS_TERRITORY],
		DEF
	)
	return _registry


# --- Registration -------------------------------------------------------------


## The happy path, and the whole point of the registry: a kind is a row, so a modder
## adds one by REGISTERING it. No module was edited and `core/` named no module.
func test_a_kind_is_added_by_registering_it_and_no_module_is_named() -> void:
	var report := _registry.register(
		&"compact", "CompactDef", [InstitutionRegistry.CAP_HAS_TERRITORY], DEF
	)
	assert_eq(bool(report["ok"]), true, "the registration landed")
	assert_eq(_registry.knows(&"compact"), true, "the kind exists afterwards")
	assert_eq(_registry.def_type_of(&"compact"), "CompactDef", "its def type is named")
	assert_eq(_registry.def_script_of(&"compact"), DEF, "and its def script is bound")


## ## An unknown kind is REFUSED BY NAME, and never a silent default
##
## This is the case the whole three-state discipline exists for. A registry that
## answered `false` — or worse, an empty capability list — for an unregistered kind
## would let a profile invent an institution of a type nothing defines, and the
## failure would surface as a gate that never fires rather than as a refusal.
func test_an_unknown_kind_refuses_by_name_and_never_defaults_to_a_capability() -> void:
	var report := _registry.has_capability(&"no_such_kind", InstitutionRegistry.CAP_TEACHES)
	assert_eq(bool(report["ok"]), false, "the lookup refused")
	assert_eq(String(report["reason"]), InstitutionRegistry.R_UNKNOWN_KIND, "and named the cause")
	assert_eq(bool(report["has"]), false, "and grants nothing")
	# And the ROW is `{}` — ADR 0083's FIRST state, "this does not exist" — which is
	# a different answer from the refusal above, not a plainer version of it.
	assert_eq(_registry.row(&"no_such_kind"), {}, "and the row is does-not-exist")
	assert_eq(_registry.def_type_of(&"no_such_kind"), "", "with no def type")
	assert_eq(_registry.def_script_of(&"no_such_kind"), null, "and no def script")
	# `knows` is the cheap branch, and it must agree with all of the above.
	assert_eq(_registry.knows(&"no_such_kind"), false, "and `knows` agrees")


## ## A kind WITHOUT the capability and a kind that DOES NOT EXIST are two answers
##
## This is the other half of the same discipline, and the prompt's requirement that a
## kind without `teaches` is a legitimate state. `clan` exists and does not teach;
## `no_such_kind` does not exist. A registry that collapsed these into one `false`
## would make an authored clan indistinguishable from a typo.
func test_a_kind_without_a_capability_is_a_legitimate_state_and_not_an_error() -> void:
	_shipped()
	var clan_teaches := _registry.has_capability(CLAN, InstitutionRegistry.CAP_TEACHES)
	assert_eq(bool(clan_teaches["ok"]), true, "the clan EXISTS, so the lookup succeeded")
	assert_eq(String(clan_teaches["reason"]), "", "with no reason")
	assert_eq(bool(clan_teaches["has"]), false, "and it simply does not teach")
	# The same query on a kind that does not exist is a refusal, not `has: false`.
	var ghost := _registry.has_capability(&"no_such_kind", InstitutionRegistry.CAP_TEACHES)
	assert_eq(bool(ghost["ok"]), false, "the ghost kind refused rather than answering")
	assert_eq(String(ghost["reason"]), InstitutionRegistry.R_UNKNOWN_KIND, "naming the cause")
	# A capability list is the honest empty for a kind that has none, and for a kind
	# that does not exist — but the two are told apart by `knows`.
	assert_eq(
		_registry.capabilities_of(CLAN).has(InstitutionRegistry.CAP_TEACHES),
		false,
		"clan teaches nothing"
	)
	assert_eq(_registry.knows(CLAN), true, "and it does exist")
	assert_eq(_registry.knows(&"no_such_kind"), false, "while the ghost does not")


## ## A duplicate kind is REFUSED, and the refusal names the offender
##
## Refused rather than idempotent and rather than overwritten. Idempotence would have
## to GUESS that two rows agree, and a registry that guesses agreement on a mod's
## behalf is the silent id collision ADR 0184 §5 forbids: "an id collision requires an
## explicit `overrides:` declaration or it is a loud load error, never silent".
func test_a_duplicate_kind_is_refused_by_name_and_the_first_registration_stands() -> void:
	_shipped()
	var again := _registry.register(SECT, "SectDef", [InstitutionRegistry.CAP_TEACHES], DEF)
	assert_eq(bool(again["ok"]), false, "the second registration refused")
	assert_eq(String(again["reason"]), InstitutionRegistry.R_DUPLICATE_KIND, "naming the cause")
	# The loser did not overwrite the winner: the capability set is still the
	# three the first registration authored.
	assert_eq(_registry.capabilities_of(SECT).size(), 3, "the first row still stands")
	assert_eq(
		_registry.capabilities_of(SECT).has(InstitutionRegistry.CAP_HAS_TERRITORY),
		true,
		"including the flag the loser's one-entry list omitted"
	)


## A duplicate is refused EVEN WHEN THE ROW WOULD IDENTICAL. This is the rule stated
## as a case, because it is the one an implementer would relax first.
func test_a_duplicate_is_refused_even_when_the_second_row_is_identical() -> void:
	_registry.register(CLAN, "ClanDef", [InstitutionRegistry.CAP_IS_BORN_TO], DEF)
	var again := _registry.register(CLAN, "ClanDef", [InstitutionRegistry.CAP_IS_BORN_TO], DEF)
	assert_eq(bool(again["ok"]), false, "an identical re-registration is still refused")
	assert_eq(String(again["reason"]), InstitutionRegistry.R_DUPLICATE_KIND, "by name")


## The shape-local faults, each named. A registration with no kind, no def type or an
## invented capability is knowable from the call alone, so it refuses eagerly rather
## than waiting for the gate that would silently never fire.
func test_a_registration_with_no_kind_no_def_type_or_an_invented_capability_refuses() -> void:
	var no_kind := _registry.register(&"", "SomeDef", [], DEF)
	assert_eq(String(no_kind["reason"]), InstitutionRegistry.R_NO_KIND, "no kind names the cause")
	var no_def := _registry.register(&"thing", "", [], DEF)
	assert_eq(
		String(no_def["reason"]),
		InstitutionRegistry.R_EMPTY_DEF_TYPE,
		"no def type names the cause"
	)
	var invented := _registry.register(&"thing", "ThingDef", [&"reads_minds"], DEF)
	assert_eq(
		String(invented["reason"]),
		InstitutionRegistry.R_UNKNOWN_CAPABILITY,
		"an invented capability names the cause"
	)
	# And none of the three refusals registered anything.
	assert_eq(_registry.knows(&"thing"), false, "a refused registration registers nothing")


## A capability named twice in ONE call is folded, not refused. That is a deliberate
## asymmetry against the duplicate KIND: a repeated flag states the same thing twice,
## while a repeated kind is two owners of one identity.
func test_a_capability_named_twice_in_one_call_is_folded() -> void:
	var report := _registry.register(
		SECT, "SectDef", [InstitutionRegistry.CAP_TEACHES, InstitutionRegistry.CAP_TEACHES], DEF
	)
	assert_eq(bool(report["ok"]), true, "the registration landed")
	assert_eq(_registry.capabilities_of(SECT).size(), 1, "and the flag is stored once")


## An unbound def script is a STATE, not a gap: a kind can be registered and named
## before its def type is written. `null` and `""` mean different things, which is why
## they are two reads.
func test_a_def_script_may_be_unbound_and_that_is_distinguishable_from_a_missing_kind() -> void:
	var report := _registry.register(&"pending", "PendingDef", [], null)
	assert_eq(bool(report["ok"]), true, "a kind registers with no def script bound")
	assert_eq(_registry.def_type_of(&"pending"), "PendingDef", "its type is still named")
	assert_eq(_registry.def_script_bound(&"pending"), false, "but nothing is bound")
	assert_eq(_registry.knows(&"pending"), true, "and it does exist")


## A wrong-typed def label reads as ABSENT rather than aborting the registration. The
## reasoning is `String(42.0)` RAISING in GDScript, which a corrupt profile would turn
## into a script error at a caller rather than a refusal here.
func test_a_wrong_typed_def_label_reads_as_absent_rather_than_raising() -> void:
	var report := _registry.register(&"thing", 42.0, [], DEF)
	assert_eq(String(report["reason"]), InstitutionRegistry.R_EMPTY_DEF_TYPE, "it refuses")
	assert_eq(_registry.knows(&"thing"), false, "and registers nothing")


# --- The three shipped kinds --------------------------------------------------


## The shipped rows, asserted as a whole. A wrong capability flag here is a gate that
## opens on a clan or a transmission axis that exists on a nation, and neither failure
## is visible from a single flag read.
func test_the_three_shipped_kinds_carry_the_capabilities_adr_0083_describes() -> void:
	_shipped()
	assert_eq(
		_registry.kinds(),
		[CLAN, NATION, SECT] as Array[StringName],
		"three kinds, canonically ordered"
	)
	# clan: born to, authors offices, NO fit axis at all.
	assert_eq(_has(CLAN, InstitutionRegistry.CAP_IS_BORN_TO), true, "a clan is born to")
	assert_eq(_has(CLAN, InstitutionRegistry.CAP_HAS_OFFICES), true, "and authors offices")
	assert_eq(_has(CLAN, InstitutionRegistry.CAP_TEACHES), false, "and has NO fit axis")
	# sect: sworn to, teaches, authors offices, and holds territory claims.
	assert_eq(_has(SECT, InstitutionRegistry.CAP_TEACHES), true, "a sect teaches")
	assert_eq(_has(SECT, InstitutionRegistry.CAP_HAS_OFFICES), true, "and authors offices")
	assert_eq(_has(SECT, InstitutionRegistry.CAP_HAS_TERRITORY), true, "and claims territory")
	assert_eq(_has(SECT, InstitutionRegistry.CAP_IS_BORN_TO), false, "and is sworn to, not born to")
	# nation: lived under, offices may be vacant, claims territory, teaches nothing.
	assert_eq(_has(NATION, InstitutionRegistry.CAP_HAS_OFFICES), true, "a nation authors offices")
	assert_eq(_has(NATION, InstitutionRegistry.CAP_HAS_TERRITORY), true, "and claims territory")
	assert_eq(_has(NATION, InstitutionRegistry.CAP_TEACHES), false, "and teaches nothing")
	assert_eq(_has(NATION, InstitutionRegistry.CAP_IS_BORN_TO), false, "and is lived under")


## ## NATION IS A PEER KIND, NOT THE CAP — and this is the structural half of the ADR
##
## The module graph reads `clan -> bloodline/race/social`, `sect -> clan/social`,
## `nation -> sect/social`, which is a literal nesting chain, while ADR 0083 says the
## three are "**not** nested in a containment tree". So `nation` is effectively the
## cap today. **The registry makes that structurally impossible**: a kind is a row in
## a flat table, so there is no field in which a parent could be written.
##
## This case is the guard for that claim. A future agent adding a `parent_kind` or a
## `tier` field has to fail here, and the failure names why.
func test_a_kind_row_carries_no_parent_no_tier_and_no_containment_of_any_kind() -> void:
	_shipped()
	for kind in _registry.kinds():
		var row := _registry.row(kind)
		for forbidden in ["parent", "parent_kind", "tier", "contains", "children", "rank_above"]:
			assert_eq(row.has(forbidden), false, "'%s' row authors no '%s'" % [kind, forbidden])
		# And the row's own keys are exactly the four the registry publishes, so a
		# new key is a visible addition rather than a silent one.
		assert_eq(
			row.keys().size(),
			3,
			"'%s' row is def_type, def_script and capabilities — nothing else" % kind
		)
	# A nation's row says nothing about a sect: it names no sect and knows of none.
	var nation := _registry.row(NATION)
	assert_eq(nation.has(SECT), false, "a nation's row contains no sect")
	assert_eq(String(nation["def_type"]), "NationDef", "and names only its own def type")


## ## `is_born_to` is the ONLY place the foundable answer is written
##
## A second `can_found` flag would be two fields that can disagree about one fact, and
## a registry that reads the wrong one lets a clan be founded. This case pins that the
## registry publishes exactly the four ADR 0083 flags and no derived foundable flag.
func test_the_registry_publishes_no_derived_foundable_flag_to_disagree_with() -> void:
	# A clan is born to, so it cannot be founded — and the answer comes from that ONE
	# flag, which is what `InstitutionFounding` reads.
	_shipped()
	assert_eq(_has(CLAN, InstitutionRegistry.CAP_IS_BORN_TO), true, "the clan is born to")
	for forbidden in [&"can_found", &"founded", &"founding"]:
		assert_eq(
			InstitutionRegistry.CAPABILITIES.has(forbidden),
			false,
			"no '%s' flag exists to disagree with `is_born_to`" % forbidden
		)
	assert_eq(InstitutionRegistry.CAPABILITIES.size(), 4, "and the set is the four ADR 0083 flags")


# --- ADR 0084: the refusal is STRUCTURAL --------------------------------------

## Every verb a kind registry must never grow. If one of these appears on
## `InstitutionRegistry`, an institution has grown a way to hand out a stat, and
## ADR 0084 says it never may. `tools arch` cannot see a method that does not exist,
## so the guard is this test — the same shape `test_sect_no_power.gd` uses.
const FORBIDDEN_VERBS_UNUSED := []


## A capability is a DESCRIPTOR of what a kind IS, never a magnitude it hands out.
## So the registry has no number in its published surface at all — the one structural
## statement that keeps "a percent, never a flat" from being restated here.
func test_the_registry_publishes_no_power_granting_verb_and_no_magnitude() -> void:
	for verb in FORBIDDEN_VERBS:
		assert_eq(
			_published(InstitutionRegistry).has(verb),
			false,
			"InstitutionRegistry publishes no '%s'" % verb
		)
	# Every published value is a Dictionary of ids and flags. A caller asking for a
	# capability gets a BOOLEAN about a KIND — never an amount.
	var report := _registry.has_capability(SECT, InstitutionRegistry.CAP_TEACHES)
	for key in report.keys():
		assert_eq(
			typeof(report[key]) in [TYPE_BOOL, TYPE_STRING],
			true,
			"'%s' is a bool or a reason" % key
		)


## ## The `_text` reasoning, preserved as a case rather than as a comment
##
## `String(42.0)` RAISES in GDScript rather than yielding `"42.0"`. A registration
## that reached for a raw cast would therefore abort the CALLER on a wrong-typed label
## instead of refusing here — and the failure would read as a crash in the composition
## root rather than as a bad field in one profile.
func test_a_wrong_typed_value_is_refused_rather_than_raising() -> void:
	# Every one of these would RAISE under a raw `String(...)` cast.
	for bad in [42.0, {"a": 1}, [1, 2], Vector2(1.0, 2.0)]:
		var report := _registry.register(&"thing", bad as String, [], DEF)
		assert_eq(
			String(report["reason"]),
			InstitutionRegistry.R_EMPTY_DEF_TYPE,
			"a wrong-typed label refuses rather than raising"
		)
	assert_eq(_registry.knows(&"thing"), false, "and nothing was registered")


# --- Helpers ------------------------------------------------------------------


func _has(kind: StringName, capability: StringName) -> bool:
	return bool(_registry.has_capability(kind, capability)["has"])


## Every public method name on `klass`, read from the class itself. The facade is all
## static functions and GDScript refuses a non-static call on a class reference, so
## `load()` is the one way in — the same trick `test_sect_no_power.gd` uses on a
## facade script.
func _published(klass: GDScript) -> Array[String]:
	var out: Array[String] = []
	if klass == null:
		return out
	for method in klass.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out
