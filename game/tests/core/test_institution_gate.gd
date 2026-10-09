extends TestCase

## The ONE requirement evaluator, contract-tested (ADR 0922, ADR 0942).
##
## These are contract tests because `sect`, `clan`, `nation` and any modder's
## organization all resolve requirements through `InstitutionGate`. The scout measured
## the two gates it replaces side by side: identical `_pass()` and an identical
## composite tail, different verb tables. So the shared half is tested here once, and
## each kind's own table is tested in its own module.

## A resolver with one verb of each outcome shape, so the composite fold can be driven
## without a tier module loaded. `ok_verb` passes, `no_verb` fails with an entry,
## `bad_verb` REFUSES.
##
## The three composite verbs, and the flags each hands `InstitutionGate.composite`. A
## table rather than three `match` arms: the arms differed only in two booleans, and the
## difference is data.
const COMPOSITES := {
	&"all_of": [true, false],
	&"any_of": [false, false],
	&"none_of": [false, true],
}


## The three COMPOSITE verbs dispatch back into `InstitutionGate.composite` — and that
## is not decoration, it is the pattern every implementer must follow. A tier's resolver
## receives its own composite verbs and hands the requirement back to the one composite,
## because `composite` is what REBUILDS the child probe per child. A resolver that
## answered `all_of` itself would have to re-derive that rebuild, and the first version
## of this fixture omitted the cases entirely, so its nesting test could never recurse and
## said so with a bare `false`.
func _resolve(requirement: Dictionary) -> Dictionary:
	var verb := InstitutionGate.verb_of(requirement)
	if COMPOSITES.has(verb):
		var flags: Array = COMPOSITES[verb]
		return InstitutionGate.composite(
			Callable(self, "_resolve"), requirement, bool(flags[0]), bool(flags[1])
		)
	match verb:
		&"ok_verb":
			return InstitutionGate.passed()
		&"no_verb":
			return InstitutionGate.fail(
				&"bar", &"elder", int(requirement.get("need", 0)), 3, "Needs more"
			)
		&"bad_verb":
			return InstitutionGate.refuse(InstitutionGate.R_MALFORMED, "unreadable", "bad_verb")
	return InstitutionGate.refuse(InstitutionGate.R_UNKNOWN_VERB, "no such verb", String(verb))


## The three shapes, kept apart. `malformed` and `unknown_verb` are REFUSALS — the
## requirement is unreadable, which is a content bug rather than a player being told no
## — and collapsing them into `unmet` is the defect this test exists to catch.
func test_a_pass_a_failure_and_a_refusal_are_three_shapes() -> void:
	var passed := _resolve({"verb": &"ok_verb"})
	assert_eq(passed["ok"], true, "a satisfied requirement says so")
	assert_eq(passed["unmet"], [], "with no entries")
	var failed := _resolve({"verb": &"no_verb", "need": 40})
	assert_eq(failed["ok"], false, "a failed requirement says so")
	assert_eq(failed["reason"], InstitutionGate.R_UNMET, "as a normal failure")
	assert_eq((failed["unmet"] as Array).size(), 1, "carrying one entry")
	var refused := _resolve({"verb": &"bad_verb"})
	assert_eq(refused["ok"], false, "a refusal is not a pass")
	assert_eq(
		refused["reason"], InstitutionGate.R_MALFORMED, "and names the unreadable requirement"
	)
	var unknown := _resolve({"verb": &"nothing"})
	assert_eq(unknown["reason"], InstitutionGate.R_UNKNOWN_VERB, "an unknown verb refuses by name")


## An unmet entry carries exactly the five keys a panel renders, and no others — the
## shape is what stops a caller inventing a sixth.
func test_an_unmet_entry_carries_the_five_keys() -> void:
	var failed := _resolve({"verb": &"no_verb", "need": 40})
	var entry: Dictionary = (failed["unmet"] as Array)[0]
	for key in InstitutionGate.ENTRY_KEYS:
		assert_eq(entry.has(key), true, "the entry carries '%s'" % key)
	assert_eq((entry as Dictionary).size(), InstitutionGate.ENTRY_KEYS.size(), "and nothing else")
	assert_eq(entry["kind"], "bar", "the kind is published as text")
	assert_eq(entry["id"], "elder", "so is the id")
	assert_eq(entry["required"], 40, "the bar it compared")
	assert_eq(entry["actual"], 3, "and what the member had")


## `all_of` passes only when every child passed.
func test_all_of_requires_every_child() -> void:
	var all_pass := InstitutionGate.composite(
		Callable(self, "_resolve"),
		{"of": [{"verb": &"ok_verb"}, {"verb": &"ok_verb"}]},
		true,
		false
	)
	assert_eq(all_pass["ok"], true, "two passes satisfy all_of")
	var one_fails := InstitutionGate.composite(
		Callable(self, "_resolve"),
		{"of": [{"verb": &"ok_verb"}, {"verb": &"no_verb"}]},
		true,
		false
	)
	assert_eq(one_fails["ok"], false, "one failure fails all_of")
	assert_eq((one_fails["unmet"] as Array).size(), 1, "and the failure's own entry travels")


## `any_of` passes when one child passed, and `none_of` when none did — the inverted fold.
func test_any_of_and_none_of_fold_the_other_way() -> void:
	var any_pass := InstitutionGate.composite(
		Callable(self, "_resolve"),
		{"of": [{"verb": &"ok_verb"}, {"verb": &"no_verb"}]},
		false,
		false
	)
	assert_eq(any_pass["ok"], true, "one pass satisfies any_of")
	var any_fails := InstitutionGate.composite(
		Callable(self, "_resolve"),
		{"of": [{"verb": &"no_verb"}, {"verb": &"no_verb"}]},
		false,
		false
	)
	assert_eq(any_fails["ok"], false, "no pass fails any_of")
	var none_clean := InstitutionGate.composite(
		Callable(self, "_resolve"), {"of": [{"verb": &"no_verb"}, {"verb": &"no_verb"}]}, true, true
	)
	assert_eq(none_clean["ok"], true, "none_of passes when nothing passed")
	var none_dirty := InstitutionGate.composite(
		Callable(self, "_resolve"), {"of": [{"verb": &"ok_verb"}, {"verb": &"no_verb"}]}, true, true
	)
	assert_eq(none_dirty["ok"], false, "and fails when something did")


## ## A malformed child POISONS the whole composite
##
## A nested gate that cannot be read must never be treated as satisfied: a typo in a
## `.tres` would become a free pass. The refusal travels up rather than being folded
## into an `unmet` count.
func test_a_malformed_child_poisons_the_composite() -> void:
	var poisoned := InstitutionGate.composite(
		Callable(self, "_resolve"),
		{"of": [{"verb": &"ok_verb"}, {"verb": &"bad_verb"}]},
		false,
		false
	)
	assert_eq(poisoned["ok"], false, "the composite does not pass")
	assert_eq(poisoned["reason"], InstitutionGate.R_MALFORMED, "the child's refusal travels up")
	var unknown := InstitutionGate.composite(
		Callable(self, "_resolve"),
		{"of": [{"verb": &"ok_verb"}, {"verb": &"nothing"}]},
		false,
		false
	)
	assert_eq(unknown["reason"], InstitutionGate.R_UNKNOWN_VERB, "so does an unknown verb")


## A composite naming no children, or a child that is not a map, refuses rather than
## passing vacuously — an `all_of` over nothing is a requirement nobody wrote.
func test_an_empty_or_misshapen_composite_refuses() -> void:
	assert_eq(
		InstitutionGate.composite(Callable(self, "_resolve"), {}, true, false)["reason"],
		InstitutionGate.R_MALFORMED,
		"a composite with no `of` refuses"
	)
	assert_eq(
		InstitutionGate.composite(Callable(self, "_resolve"), {"of": []}, true, false)["reason"],
		InstitutionGate.R_MALFORMED,
		"and so does an empty one"
	)
	assert_eq(
		(
			InstitutionGate
			. composite(Callable(self, "_resolve"), {"of": ["not a map"]}, true, false)["reason"]
		),
		InstitutionGate.R_MALFORMED,
		"a child that is not a map refuses"
	)


## ## A nested composite reads its OWN children
##
## The rebuild is what makes this true: building the child from the parent and
## overwriting only `of` would leave the parent's `verb` in place, so every child would
## be re-entered as the same composite and recurse on the parent's own children forever.
## This drives two levels of nesting and asserts the inner one is really evaluated.
func test_a_nested_composite_reads_its_own_children() -> void:
	var nested := (
		InstitutionGate
		. composite(
			Callable(self, "_resolve"),
			{
				"of":
				[
					{"verb": &"ok_verb"},
					{"verb": &"all_of", "of": [{"verb": &"ok_verb"}, {"verb": &"ok_verb"}]},
				]
			},
			true,
			false
		)
	)
	assert_eq(nested["ok"], true, "an inner all_of is evaluated, not skipped")
	var inner_fails := (
		InstitutionGate
		. composite(
			Callable(self, "_resolve"),
			{
				"of":
				[
					{"verb": &"ok_verb"},
					{"verb": &"all_of", "of": [{"verb": &"ok_verb"}, {"verb": &"no_verb"}]},
				]
			},
			true,
			false
		)
	)
	assert_eq(inner_fails["ok"], false, "and its failure reaches the outer fold")


## The ledger a requirement reads: an actor's own slot when one is supplied, the
## authored `ledger` when not. An authored requirement has to be evaluable with no
## actor at all, which is what lets a `.tres` carry a nested gate.
func test_the_ledger_comes_from_the_actor_or_the_requirement() -> void:
	var authored := InstitutionGate.ledger_for(
		{"ledger": {"institution": "jade_court"}}, null, Callable()
	)
	assert_eq(authored["institution"], "jade_court", "an authored ledger is read when no actor")
	var nothing := InstitutionGate.ledger_for({}, null, Callable())
	assert_eq(nothing["institution"], "", "and an absent one reads as the empty envelope")
	var foreign := InstitutionGate.ledger_for({"ledger": "not a map"}, null, Callable())
	assert_eq(foreign["institution"], "", "a foreign authored ledger reads empty, never raises")


## `verb_of` is the first question every resolver asks, and an absent verb answers `&""`
## rather than raising — so the resolver's own `unknown_verb` branch owns the refusal.
func test_verb_of_answers_empty_for_an_absent_verb() -> void:
	assert_eq(InstitutionGate.verb_of({"verb": &"x"}), &"x", "a named verb reads back")
	assert_eq(InstitutionGate.verb_of({}), &"", "an absent verb reads empty")
	assert_eq(
		InstitutionGate.verb_of({"verb": 42}), &"", "a foreign verb reads empty, never raises"
	)
