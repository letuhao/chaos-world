extends TestCase

## An authored `DomainDef` a player cannot enter is LOUD, not silent (BL-0338).
##
## ## What the entry said, and what the tree actually holds NOW
##
## BL-0338 reported 128 of 160 domains invisible: `LootApi.domains()` enumerates encounters,
## so a domain with no `LootEncounterDef` is one no surface offers and `enter_domain` answers
## `unknown_domain` — a lie, because the domain exists. Re-measured on this tree (BL-0619:
## verify a finding before dispatching against it): **160 authored domains, 160 authored
## encounters, zero orphans**. A content wave completed the corpus, so every authored domain
## is reachable through the shipped verb.
##
## The defect was real, and the class comes straight back: a domain dropped into
## `res://data/domains/` without an encounter is exactly as invisible as it ever was, and
## nothing in the tree said so. So the deliverable is the GUARD, and — per INC-0016, a green
## guard is not a tested guard — it is proved against the REAL implementation in both
## directions. A scratch `LootContent` carries the seed, so the shared index every other
## caller reads is never touched and the corpus assertion stays honest.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
## Domain ids nothing on disk declares, so a report naming one cannot be a coincidence.
const PROBE := "probe_orphan_domain_with_no_encounter"
const SECOND_PROBE := "probe_second_orphan_domain"
## The word the report uses for what a player is actually told when they try to enter one.
const REFUSAL_WORD := "unknown_domain"


## A scratch corpus over the real content tree, carrying any seeds the caller supplies.
## `LootContent.new()` rather than `instance()` on purpose: `orphan_domains` is per instance,
## so a seed here cannot make the shipped corpus look broken to every other suite.
func _scratch(orphans: Array = []) -> LootContent:
	var corpus := LootContent.new()
	for domain_id in orphans as Array[String]:
		corpus.provide_domain(StringName(domain_id))
	return corpus


func _content() -> LootContent:
	return LootContent.instance()


func _hero() -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, 24)
	LootApi.attach(actor)
	return actor


## ## The corpus is WHOLE.
##
## Every authored domain has an encounter, so the set of enterable domains is the set of
## authored domains. Asserted as an equality of the two SETS rather than as a count, because
## a count passes just as happily with one domain added and another orphaned.
func test_every_authored_domain_has_an_encounter_so_none_is_invisible() -> void:
	var domains := _content().domain_ids()
	assert_eq(domains.is_empty(), false, "the corpus is not empty")
	assert_eq(
		_content().orphan_domains(),
		[],
		"no authored domain lacks an encounter, so none is invisible"
	)
	# The other half, which a set comparison alone would miss: an encounter whose domain_id
	# names nothing on disk is not an orphan DOMAIN, but it is still a domain nobody enters.
	var hosted := 0
	for encounter_id in _content().encounter_ids():
		var encounter := _content().encounter_by_id(StringName(encounter_id))
		assert_ne(encounter, null, "%s loads" % encounter_id)
		if encounter != null and domains.has(String(encounter.domain_id)):
			hosted += 1
	assert_eq(hosted, domains.size(), "every authored domain is hosted by an encounter")


## ## The guard is MEANINGFUL, against the REAL implementation.
##
## This is the half that fails if the reporting is deleted (INC-0016). It runs
## `LootContent.orphan_domains` and `LootValidator.validate_domains` as written — seeded with
## one unhosted domain on a scratch corpus — rather than a stand-in that returns whatever the
## test wants, which is how a guard ends up green because nothing exercised it.
func test_an_authored_domain_with_no_encounter_is_reported_rather_than_swallowed() -> void:
	var scratch := _scratch([PROBE])
	# The seed really is a domain the corpus authors, and really is unhosted. Both asserted,
	# because a report naming a domain the corpus never had would prove nothing.
	assert_eq(
		scratch.domain_ids().has(PROBE), true, "the seeded domain is a domain the content authors"
	)
	assert_eq(scratch.orphan_domains(), [PROBE], "and no encounter hosts it")

	var problems := "\n".join(LootValidator.validate_domains(scratch))
	assert_eq(problems.contains(PROBE), true, "so the orphan is named, and its absence is visible")
	assert_eq(
		problems.contains(REFUSAL_WORD),
		true,
		"and the report says what a player would actually be told"
	)

	# BOTH directions from the same code: a whole corpus is silent. Without this half the
	# reporting above could be satisfied by a message that names everything.
	assert_eq(
		LootValidator.validate_domains(_scratch()), [], "a corpus with no orphans reports nothing"
	)
	assert_eq(_scratch().orphan_domains(), [], "and finds none to find")

	# A LIST, not a single answer: two orphans are both named, and only they.
	var two := _scratch([PROBE, SECOND_PROBE])
	assert_eq(two.orphan_domains().size(), 2, "two seeds give two orphans")
	var text := "\n".join(LootValidator.validate_domains(two))
	assert_eq(text.contains(PROBE) and text.contains(SECOND_PROBE), true, "and both are named")
	assert_eq(text.contains(String(EMBER_DOMAIN)), false, "while every hosted domain is not")


## The check runs as part of the DEFAULT validation, not only when asked for by name — a
## check nobody calls is not a gate. Proved by its effect on a corpus that IS broken, through
## the facade a caller actually reaches.
func test_the_orphan_check_runs_in_the_default_validation() -> void:
	assert_eq(
		LootValidator.validate(LootValidator.SCOPE_DOMAINS),
		[],
		"the shipped corpus passes the domain scope on its own"
	)
	# Every scope contributes to the default, and the domain scope contributes even though it
	# is silent today — which is exactly the assertion that would fail if the call were
	# dropped, since a silent scope adds nothing an equality could see.
	var every := LootValidator.validate().size()
	var tables := LootValidator.validate(LootValidator.SCOPE_TABLES).size()
	var encounters := LootValidator.validate(LootValidator.SCOPE_ENCOUNTERS).size()
	var domains := LootValidator.validate(LootValidator.SCOPE_DOMAINS).size()
	assert_eq(
		every >= maxi(tables, maxi(encounters, domains)),
		true,
		"the default is at least as strict as every single scope"
	)
	assert_eq(
		LootValidator.validate_domains(_scratch([PROBE])).size(),
		1,
		"and the scope this test proved is a real function of the corpus, not a constant"
	)


## ## Reachability, not just enumerability.
##
## A domain being listed is not a domain being enterable — `enter_domain` has its own gate,
## and a gate that refused everything would leave the corpus "whole" too. So this half is
## proved on the shipped verb itself, against a domain that declares no gate.
func test_a_domain_from_the_corpus_is_enterable_by_a_concrete_call() -> void:
	var actor := _hero()
	var entered := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 7)
	assert_eq(bool(entered.get("ok", false)), true, "the ember vault opens for a bare delver")
	var live := LootApi.summary(actor).get("active", {}) as Dictionary
	assert_eq(bool(live.get("in_domain", false)), true, "with a boss live inside it")
	assert_ne(String(live.get("boss_id", "")), "", "and that boss is authored")
	assert_eq(
		String(live.get("domain_id", "")), String(EMBER_DOMAIN), "in the domain that was asked for"
	)


## The corpus is offered as a LIST too, so the guard is not the only thing between an orphan
## and a player: every domain the content authors appears in the surface's own enumeration,
## with at least one band to enter.
func test_every_authored_domain_appears_in_the_surfaces_domain_list() -> void:
	var offered := {}
	for entry in LootApi.domains():
		var descriptor := entry as Dictionary
		var domain_id := String(descriptor.get("domain_id", ""))
		assert_ne(domain_id.is_empty(), true, "a domain id is reported")
		assert_ne(
			(descriptor.get("tiers", []) as Array).is_empty(), true, "%s offers a band" % domain_id
		)
		offered[domain_id] = true
	var missing: Array[String] = []
	for domain_id in _content().domain_ids():
		if not offered.has(domain_id):
			missing.append(domain_id)
	assert_eq(missing, [], "the surface offers every authored domain, so none is invisible")


## ## FAILURE REACHABLE, from a named input state.
##
## The concrete input is a domain the corpus authors that no encounter hosts — one record in
## `res://data/domains/` with no counterpart under `res://data/loot/encounters/`. Named
## through the real enumeration, so the guard is shown to be a function of exactly that
## difference and of nothing else about the corpus.
func test_the_guard_is_a_function_of_the_hosted_difference() -> void:
	var content := _content()
	var hosted := {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter != null:
			hosted[String(encounter.domain_id)] = true
	var unhosted: Array[String] = []
	for domain_id in content.domain_ids():
		if not hosted.has(domain_id):
			unhosted.append(domain_id)
	assert_eq(
		unhosted,
		[],
		"the shipped corpus holds no such record, which is why the probe above is needed"
	)
	# Adding exactly one unhosted domain moves exactly one thing: the orphan list. Nothing
	# else about the corpus changes, which is what makes this a report and not a rebuild.
	var seeded := _scratch([PROBE])
	assert_eq(seeded.orphan_domains(), [PROBE], "the seed is the only orphan")
	assert_eq(
		seeded.domain_ids().size(),
		content.domain_ids().size() + 1,
		"and the corpus grew by exactly the one domain"
	)
	assert_eq(
		seeded.encounter_ids().size(),
		content.encounter_ids().size(),
		"while the encounters are untouched, so the report is about hosting alone"
	)
