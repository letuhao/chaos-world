extends TestCase

## ## The integration proof, not another unit test
##
## Every other suite in this module installs `DestinyFixtureCatalog` and gates on
## `t_`-prefixed ids the fixture built in code. That is correct for proving LOGIC,
## and it is exactly why two unsatisfiable content cycles shipped undetected
## (DEF-0181, DEF-0182): a fixture catalog is a different universe from
## `res://data/destiny/`, so a broken authored `.tres` is invisible to all of
## them. `test_quest_content.gd` walks the shipped ids but never runs a hero
## through them.
##
## This suite is the one that closes that gap, and it is written as a CONSUMER
## rather than as a second reader of the module. Everything here is the shape a
## `story` module has to speak:
##
##   - read the REAL catalog — `FateCatalog.instance()`, never `install()`;
##   - earn a REAL fate and watch a gate open because of it;
##   - be refused, and read WHY out of `{ok, reason, unmet}` without opening the
##     ADR to learn the field names;
##   - trust exactly-once, and cross-check `has_fate` / `fates` / `state` /
##     `summary` against each other rather than against one of them;
##   - survive a call made before it has an actor at all.
##
## **It does not work around a broken id.** A shipped `.tres` that cannot load,
## or whose stat ids are not real `Stat` constants, fails here by name rather
## than being skipped — the defect is reported, not absorbed.

## The shipped tree, read once. Every id below is asserted to exist here before
## it is used, so a content deletion fails as a NAMED failure and not as an
## earn that silently recorded nothing.
const FATE_TREE := "res://data/destiny/fates"
const DESTINY_TREE := "res://data/destiny/destinies"

## REAL authored ids, chosen for what each one proves rather than for being
## easy.
##
## `oath_breaker` — `revealed`, a flat AND a percent modifier, and the fate a
## shipped quest gate (`the_severed_calling`) actually names. Earn it, and a
## gate a player could really be refused opens.
## `the_third_man_spared` — `hidden` visibility: unearned it must be listed but
## UNNAMED, and earning it is the only thing that reveals it. A consumer that
## caches a pre-earn snapshot must not be able to spoil it.
## `vigil_broken_by_hand` — `revealed`, two modifiers, and a stat-modifying
## fate whose contribution is measurable, so exactly-once can be asserted on the
## STACK rather than only on the ledger.
## `household_registered_as_heir` — a PURE-NARRATIVE fate: it grants no stat at
## all, so it proves the codex and the gate carry a fate whose entire weight is
## narrative. It is the closest shipped analogue to what a story module wants.
const OATH_BREAKER := &"oath_breaker"
const THIRD_MAN := &"the_third_man_spared"
const VIGIL := &"vigil_broken_by_hand"
const HEIR := &"household_registered_as_heir"

## A real fate whose shipped `visibility` is `teaser`, named here rather than
## reached through the authored tree, so this suite asserts the OMIT RULE on a real
## entry instead of asking a helper to prove a premise it cannot verify.
##
## It was read out of `res://data/destiny/fates/heaven_s_warning_unread.tres` on
## purpose. The brief this suite was written against claimed that fate carried a
## codex view and the test went red; it does not, and that is the CONTRACT working
## (see `test_a_teaser_fate_is_omitted_from_the_codex_entirely`).
const TEASER_FATE := &"heaven_s_warning_unread"

## A real gate requirement over real ids, exactly as `the_severed_calling.tres`
## authors it.
const REAL_FATE_GATE := {"verb": &"has_fate", "id": "oath_breaker"}


func setup() -> void:
	# Nothing is installed. `FateCatalog.shared` is whatever the process held,
	# and the only catalog this suite can see is the one the shipped tree builds.
	# A fixture left over from another suite is not possible — every fixture
	# suite calls `teardown()`, which nulls the singleton — and if it ever were,
	# the id assertions below would fail rather than pass quietly.
	pass


func teardown() -> void:
	# Nothing installed, so nothing to restore. Deliberately NOT calling
	# `DestinyFixtureCatalog.teardown()`: this suite never installed a fixture,
	# and nulling the singleton here would force the next suite to rebuild the
	# real catalog for no reason.
	pass


# --- The shipped tree, read as a consumer -------------------------------------


## The catalog the player actually ships with, and every id this suite is about.
##
## The id assertions are the point. A suite that gates on ids it invented
## cannot fail when content is deleted; this one fails, by name, the moment a
## `.tres` this contract depends on stops shipping.
func test_the_real_catalog_ships_every_id_this_contract_gates_on() -> void:
	var catalog := FateCatalog.instance()
	assert_ne(catalog, null, "the real catalog is reachable without a fixture")
	for fate_id in [OATH_BREAKER, THIRD_MAN, VIGIL, HEIR]:
		var def := catalog.fate_definition(fate_id)
		var where := "%s/%s.tres" % [FATE_TREE, fate_id]
		assert_ne(
			def,
			null,
			(
				(
					"the shipped tree defines the fate '%s' (%s); a consumer that gates on it would"
					% [fate_id, where]
				)
				+ " silently never open"
			)
		)
		if def != null:
			assert_eq(String(def.id), String(fate_id), "and it loads under the id it is filed as")
	# A catalog that failed to load would make every earn below refuse, and every
	# gate below report `unmet` — a whole suite of plausible-looking assertions
	# about a module that is quietly holding nothing. Assert the tree is real
	# before trusting any of it.
	assert_eq(
		catalog.fate_ids().is_empty(),
		false,
		"the shipped fate tree loaded at all (res://data/destiny/fates/)"
	)
	assert_eq(
		catalog.destiny_ids().is_empty(),
		false,
		"and the shipped destiny tree did (res://data/destiny/destinies/)"
	)


## A consumer has to be able to enumerate what exists before it gates on it.
## The catalog is not on the facade — `summary()` is — so this is the facade's
## answer and it is asserted as one: every shipped, codex-visible fate appears
## under its own id, with a primitive view.
func test_summary_enumerates_the_real_shipped_fates_a_consumer_can_gate_on() -> void:
	var actor := _hero()
	var view := DestinyApi.summary(actor)
	var fates: Dictionary = view["fates"] as Dictionary
	for fate_id in [OATH_BREAKER, THIRD_MAN, VIGIL, HEIR]:
		assert_eq(
			fates.has(String(fate_id)), true, "'%s' is in the codex a consumer reads" % fate_id
		)
	# A `teaser` fate is omitted from the codex ENTIRELY, and a hidden one is
	# listed but unnamed. Both are shipped, and both are load-bearing for a
	# consumer that caches a snapshot before anything is earned.
	var hidden := _fate_view(fates, THIRD_MAN)
	assert_eq(bool(hidden["visible"]), true, "a hidden fate is listed")
	assert_eq(
		String(hidden["display_name"]),
		"",
		"but unnamed before it is earned, so a cached snapshot cannot spoil it"
	)
	assert_ne(String(hidden["teaser"]), "", "and it carries a teaser instead")
	assert_eq(
		_primitives_only(view), true, "the whole snapshot is primitives, as the contract says"
	)


## A `teaser` fate is omitted from the codex ENTIRELY, which is a DIFFERENT promise
## from `hidden` above: hidden shows an unnamed row, teaser shows nothing at all.
## A consumer must not treat an absent row as "not earned" — for a teaser it is
## "not disclosed", and the two are indistinguishable from the snapshot alone, which
## is exactly why the visibility field exists.
##
## **Its own test, on purpose.** The version of this assertion that lived inside
## `test_summary_enumerates_the_real_shipped_fates_a_consumer_can_gate_on` went
## through `_fate_view`, a helper that reports "no view" as a FAILURE. Asking a
## helper to prove an ABSENCE means its passing is the only outcome it can produce:
## it would go red when the contract worked and green only if the teaser leaked. The
## rule is now stated directly against the snapshot — `has()` must be `false` — so
## a leak and an omission are opposite answers to one assertion.
##
## The premise is read off the real catalog rather than assumed, and `heaven_s_
## warning_unread` is named because it is the shipped entry with `visibility =
## &"teaser"`; if a retune promotes it to `revealed` this test says so by name
## instead of quietly proving nothing.
func test_a_teaser_fate_is_omitted_from_the_codex_entirely() -> void:
	var actor := _hero()
	var def := FateCatalog.instance().fate_definition(TEASER_FATE)
	assert_ne(def, null, "the shipped fate tree still defines '%s'" % TEASER_FATE)
	if def == null:
		return
	assert_eq(
		String(def.visibility),
		"teaser",
		"and it is still authored as the strictest of the three visibilities"
	)
	assert_eq(def.is_visible(), false, "which the catalog itself agrees is not codex-visible")
	var fates: Dictionary = DestinyApi.summary(actor)["fates"] as Dictionary
	assert_eq(
		fates.has(String(TEASER_FATE)),
		false,
		(
			"a teaser fate carries no codex row at all, so a consumer cannot tell"
			+ " 'undisclosed' from 'unearned' by absence alone"
		)
	)


# --- A gate that a real fate opens --------------------------------------------


## The core of the contract: a consumer earns a REAL fate through the public
## facade, and a gate authored on that REAL id opens because of it. Both halves
## are the shipped content — no fixture, no synthetic id — because a gate that
## opens against a fixture proves the code path and nothing about the content.
func test_earning_a_real_fate_opens_a_gate_that_was_closed_before() -> void:
	var actor := _hero()
	var closed := DestinyApi.gate(actor, REAL_FATE_GATE)
	assert_eq(bool(closed["ok"]), false, "the gate is shut before the deed")
	assert_eq(
		bool(DestinyApi.gate(actor, {"verb": &"has_fate", "id": String(HEIR)})["ok"]),
		false,
		"and it is shut on a second real fate this hero has not earned either"
	)
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	var open := DestinyApi.gate(actor, REAL_FATE_GATE)
	assert_eq(
		bool(open["ok"]),
		true,
		"earning the real fate opens the real gate, with no re-attach and no cache to clear"
	)
	assert_eq(open["unmet"] as Array, [], "an open gate has nothing left to report")


## The other half of the contract: the gate a consumer asked the WRONG question
## about stays shut, and the refusal carries the five fields a panel renders
## without inventing any of them.
func test_a_gate_on_a_real_fate_that_was_not_earned_refuses_with_a_renderable_reason() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	var verdict := DestinyApi.gate(actor, {"verb": &"has_fate", "id": String(VIGIL)})
	assert_eq(bool(verdict["ok"]), false, "a fate that was not earned refuses")
	# The refusal shape, asserted as a SHAPE rather than as one example: a
	# consumer that renders `unmet[i].label` must be able to do it for every
	# entry, whichever verb produced it.
	assert_eq(verdict.has("ok"), true, "{ok, reason, unmet}: ok is present")
	assert_eq(verdict.has("reason"), true, "reason is present")
	assert_eq(verdict.has("unmet"), true, "unmet is present")
	assert_eq(String(verdict["reason"]), "unmet", "an ordinary unmet, not a malformed gate")
	var entry = _unmet_entry(verdict, 0)
	assert_eq(entry.keys().size(), 5, "exactly the five keys a consumer renders")
	for key in ["kind", "id", "required", "actual", "label"]:
		assert_eq(entry.has(key), true, "'%s' is one of them" % key)
	assert_eq(String(entry["kind"]), "fate", "the kind names which ledger it was about")
	assert_eq(String(entry["id"]), String(VIGIL), "the id is the REAL one that is missing")
	assert_eq(bool(entry["required"]), true, "it is required")
	assert_eq(bool(entry["actual"]), false, "and not held")
	assert_ne(String(entry["label"]), "", "and the label has text to render")
	# The refusal is closed, so it is not an error the consumer must catch: the
	# same gate read twice is stable, which is what lets a screen gate on it.
	assert_eq(
		DestinyApi.gate(actor, {"verb": &"has_fate", "id": String(VIGIL)}),
		verdict,
		"reading the same refusal twice gives the same answer"
	)


# --- Exactly-once, on the STACK not just the ledger ---------------------------


## Exactly-once is the earn-only invariant (ADR 0065), and a consumer that pays
## for a deed twice must not be charged twice. Asserted on the modifier STACK as
## well as the ledger, because a double-charge would show up in the numbers long
## before anyone read the ledger.
func test_earning_the_same_real_fate_twice_does_not_double_its_contribution() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, VIGIL, "combat")
	var after_first := DestinyApi.state(actor)
	var stacked := DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL)
	var modifiers_after_first := DestinyProjection.modifier_count(actor)
	assert_eq(stacked["flat"] > 0.0, true, "the real fate contributes a flat modifier")
	# The replay: a quest that pays twice, a beat that fires twice, a save that
	# re-runs an earn. All three are production shapes.
	for replay in 2:
		DestinyApi.earn_fate(actor, VIGIL, "combat")
		assert_eq(
			DestinyApi.state(actor),
			after_first,
			"replay %d appended nothing to the ledger" % replay
		)
		assert_eq(
			DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL),
			stacked,
			"and re-projected nothing, so the number never doubled"
		)
	assert_eq(
		DestinyProjection.modifier_count(actor),
		modifiers_after_first,
		"and the modifier stack holds exactly what one earn put there"
	)
	# The gate agrees, so a consumer cannot be told 'earned' twice either.
	assert_eq(
		DestinyApi.state(actor)["fates"] as Dictionary,
		after_first["fates"] as Dictionary,
		"one entry, one sequence"
	)


## Exactly-once for a DESTINY too, over the real authored `grants_fates`. This
## is the shape a story module is most likely to build: earn a branch, and the
## consequences it carries must land once — including a fate the consumer also
## pays separately.
func test_earning_a_real_destiny_carries_its_granted_fates_exactly_once() -> void:
	var actor := _hero()
	var def := FateCatalog.instance().destiny_definition(&"the_one_who_stayed")
	assert_ne(def, null, "the shipped tree defines 'the_one_who_stayed'")
	if def == null:
		return
	assert_eq(def.grants_fates.is_empty(), false, "and it carries its consequence with it")
	var ledger := DestinyApi.earn_destiny(actor, &"the_one_who_stayed", "story")
	assert_eq(DestinyApi.has_destiny(actor, &"the_one_who_stayed"), true, "the branch is held")
	for fate_id in def.grants_fates:
		assert_eq(
			DestinyApi.has_fate(actor, fate_id),
			true,
			"and it carried the real fate '%s' with it" % fate_id
		)
	var after_first := DestinyApi.state(actor)
	var stack_after_first := DestinyProjection.modifier_count(actor)
	DestinyApi.earn_destiny(actor, &"the_one_who_stayed", "story")
	# And the consumer pays one of the same fates itself, which is the overlap a
	# quest + a destiny routinely produce.
	for fate_id in def.grants_fates:
		DestinyApi.earn_fate(actor, fate_id, "quest:test")
	assert_eq(
		DestinyApi.state(actor),
		after_first,
		"a replayed branch and a repeated grant both add nothing"
	)
	assert_eq(
		DestinyProjection.modifier_count(actor),
		stack_after_first,
		"and the stack is untouched by either"
	)
	# The branch is earned once; the ledger says so.
	assert_eq(
		(after_first["destinies"] as Dictionary).keys().size(), 1, "exactly one destiny is recorded"
	)


# --- The read verbs must not contradict each other ----------------------------


## The four read verbs a consumer picks between, cross-checked against each
## other on ONE actor after ONE real earn. A consumer cannot know which verb is
## the authoritative one, so a disagreement between any two of them is a bug it
## will inherit whichever it happens to call.
func test_the_consumer_facing_read_verbs_agree_after_a_real_earn() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	DestinyApi.earn_fate(actor, HEIR, "story")
	DestinyApi.record(actor, &"oaths_sworn", 2)

	var summary := DestinyApi.summary(actor)
	var state := DestinyApi.state(actor)
	var fates := DestinyApi.fates(actor)

	# `fates()` vs `state()` vs `summary().fates`: NOT the same set, and the
	# difference is the thing a consumer must not get wrong. `fates()` and `state()`
	# answer "what does this actor HOLD"; `summary()` also carries every LOCKED row
	# so a codex can render what is still out of reach. Assert the relationship
	# rather than pretending the two are one list, or a consumer would read the
	# codex as a possession list and report 16 fates for an actor holding two.
	assert_eq(_string_list(fates), _sorted(state["fates"] as Dictionary), "fates() == state()")
	var summary_held: Array[String] = []
	for fate_id in _string_list(fates):
		var view: Dictionary = (summary["fates"] as Dictionary).get(fate_id, {})
		if bool(view.get("held", false)):
			summary_held.append(fate_id)
	assert_eq(
		summary_held,
		_string_list(fates),
		"every held fate is present in the summary AND marked held"
	)
	assert_eq(
		int(summary["fate_count"]), fates.size(), "and the summary's held count agrees with fates()"
	)
	# `has_fate` is the boolean form of the same question, for every shipped id
	# in play and for one that is emphatically not.
	for fate_id in [OATH_BREAKER, HEIR, VIGIL]:
		assert_eq(
			DestinyApi.has_fate(actor, fate_id),
			fates.has(fate_id),
			"has_fate('%s') agrees with fates()" % fate_id
		)
	assert_eq(
		DestinyApi.has_fate(actor, &"no_such_fate_anywhere"),
		fates.has(&"no_such_fate_anywhere"),
		"and answers false for an id nothing defines, without recording it"
	)
	# The `held` flag in the codex is the fourth answer to the same question.
	for fate_id in fates:
		var view := _fate_view(summary["fates"] as Dictionary, fate_id)
		assert_eq(
			bool(view.get("held", false)),
			true,
			"the codex marks '%s' held, because fates() lists it" % fate_id
		)
		assert_eq(
			String(view.get("display_name", "")) != "",
			true,
			"and holding it revealed the name, so the codex can name it"
		)
	# Counters: `counter()` reads the same number `state` and `summary` carry.
	assert_eq(
		_counter(actor, &"oaths_sworn"),
		int((state["counters"] as Dictionary).get("oaths_sworn", 0)),
		"counter() == state()"
	)
	assert_eq(
		_counter(actor, &"oaths_sworn"),
		int((summary["counters"] as Dictionary).get("oaths_sworn", 0)),
		"counter() == summary()"
	)
	# And the ledger the facade reports is the ledger that is persisted, so a
	# consumer that saves from `state()` loses nothing a later read would miss.
	assert_eq(state, actor.get_module_data(DestinyApi.MODULE_KEY), "state() is the saved payload")


## The `state()` view is what a consumer writes into a save, so it has to survive
## the JSON hop a file-backed save takes. Asserted over REAL content, because a
## real earned fate carries an authored `source` string and a real counter name,
## and a synthetic fixture's ids would not catch a field that only round-trips
## for `t_`-prefixed values.
func test_the_ledger_a_consumer_would_save_survives_the_hop_over_real_content() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	DestinyApi.record(actor, &"oaths_sworn", 2)
	var before := DestinyApi.state(actor)
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(DestinyApi.state(restored), before, "the payload carried the ledger verbatim")
	var parsed = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(parsed, null, "the payload is JSON-safe")
	assert_eq(
		DestinyApi.state(Actor.from_dict(parsed as Dictionary)),
		before,
		"and it survives a JSON hop"
	)


# --- A consumer that calls before it has an actor -----------------------------


## Every read verb, called with no actor at all. A screen mounts before it has a
## hero and a story module resolves its content before it knows whose it is;
## neither may crash on the way there. All of these answers are deliberately
## "nothing held", never an error and never a partial answer.
func test_every_read_verb_is_safe_on_a_null_actor() -> void:
	assert_eq(DestinyApi.has_fate(null, OATH_BREAKER), false, "has_fate(null) holds nothing")
	assert_eq(DestinyApi.has_destiny(null, &"the_one_who_stayed"), false, "has_destiny(null) too")
	assert_eq(DestinyApi.fates(null), [], "fates(null) is empty, not null")
	assert_eq(DestinyApi.destinies(null), [], "destinies(null) is empty")
	assert_eq(_counter(null, &"oaths_sworn"), 0, "and counter(null) is zero")
	# `state(null)` is the empty ledger, versioned — the shape a save writer
	# would serialize, so it has to be a dictionary and not a null.
	var state := DestinyApi.state(null)
	assert_eq(state.has("fates"), true, "state(null) is a ledger, not a null")
	assert_eq(state["fates"] as Dictionary, {}, "holding nothing")
	assert_eq(_primitives_only(state), true, "and it is primitives all the way down")
	# `summary(null)` is the snapshot a codex renders with no hero bound. The
	# screen contract says a screen reports `{}` in that case, and this is the
	# facade half of the same rule: the snapshot still exists and says so.
	var summary := DestinyApi.summary(null)
	assert_eq(bool(summary["has_actor"]), false, "summary(null) says there is no actor")
	assert_eq(String(summary["actor_id"]), "", "names nobody")
	assert_eq(int(summary["fate_count"]), 0, "and holds nothing")
	assert_eq(_primitives_only(summary), true, "still primitives only")
	# The gate verb is the one a consumer calls most eagerly, so it is the one
	# most worth proving: a null actor holds nothing, so every real gate on a
	# real fate refuses — with the same renderable shape it always uses.
	for requirement in [
		REAL_FATE_GATE,
		{"verb": &"has_fate", "id": String(HEIR)},
		{"verb": &"has_destiny", "id": &"the_one_who_stayed"},
		{"verb": &"counter", "id": "oaths_sworn", "need": 1},
	]:
		var verdict := DestinyApi.gate(null, requirement)
		assert_eq(bool(verdict["ok"]), false, "no actor holds %s" % [requirement])
		assert_eq(
			(verdict["unmet"] as Array).size() > 0,
			true,
			"and the refusal still carries something to render (%s)" % [requirement]
		)
	# An ungated requirement is open regardless, because ungated means ungated.
	assert_eq(
		bool(DestinyApi.gate(null, {})["ok"]),
		true,
		"and an empty requirement is still ungated with no actor"
	)


## The earn verbs are NOT safe on a null actor, and a consumer must never
## discover that by crashing. Asserted here so the behaviour is a stated fact
## rather than an accident: a null actor earns nothing and changes nothing,
## which means `has_fate` stays false afterwards.
func test_a_null_actor_earns_nothing_rather_than_crashing() -> void:
	var earned = DestinyApi.earn_fate(null, OATH_BREAKER, "combat")
	assert_eq(earned.has("fates"), true, "earn_fate(null) still returns a ledger")
	# `earn_fate(null)` MUTATES the empty ledger it built and then reaches
	# `_persist(null, ...)`, which aborts on `actor.set_module_data`. So the ledger
	# it hands back is `{"oath_breaker": {"source": "combat", "sequence": 1}}` — an
	# earn recorded against a hero that does not exist. That is a PRODUCTION
	# defect (the null guard `record()` got at api.gd:118 was never given to
	# `earn_fate`/`earn_destiny`), and it is also the exact shape the next
	# assertion would have hidden, so the null case is asked FIRST and on its own.
	#
	# This suite does NOT own `src/modules/destiny`, so the defect is reported
	# rather than patched, and the remaining null-actor assertions are asked about
	# an actor that is never actually written to — where they test the READ
	# contract, which is what they were written for.
	assert_eq(
		DestinyApi.has_fate(null, OATH_BREAKER),
		false,
		"so nothing is held by the null actor, despite the ledger 'earn' handed back"
	)
	assert_eq(
		int(DestinyApi.record(null, &"oaths_sworn", 3)),
		0,
		"record(null) moves no counter and reports zero"
	)
	assert_eq(
		DestinyApi.state(null)["fates"] as Dictionary,
		{},
		"and state(null) is the empty ledger it says it is"
	)
	var empty := Actor.new(&"no_actor_here")
	DestinyApi.attach(empty)
	DestinyApi.earn_fate(empty, OATH_BREAKER, "combat")
	assert_eq(
		DestinyApi.has_fate(null, OATH_BREAKER),
		false,
		"and an earn on a real hero is still invisible to the null one"
	)
	assert_eq(DestinyApi.has_fate(empty, OATH_BREAKER), true, "while that hero really holds it")


## The recorded value of one counter, read off the ledger [method DestinyApi.state]
## publishes rather than off a facade verb. `counter(actor, id)` was retired when
## the twelve-method cap forced a choice to pay for `events()`: it was the one
## public verb with no caller in `game/src` at all, so what it answered was already
## one dictionary key away from every one of its twenty read sites.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


# --- Helpers ------------------------------------------------------------------


## A hero bound to the real module. `ActorFactory` is not used: this suite wants
## exactly an `Actor` with a ledger, and nothing a factory might attach on top.
func _hero(actor_id: StringName = &"story_keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


## The nth unmet entry, with its SHAPE asserted before it is read.
##
## Indexing `verdict["unmet"]` into a typed `Dictionary` aborts this function
## whenever the entry is missing, and the runner calls each test with
## `suite.call(name)` — so the abort reads as a finished test: every assertion
## after it is skipped while the suite still reports green.
##
## It returns `{}` on a miss, so the caller's own assertion is the failure a reader
## sees rather than an abort that hides it.
func _unmet_entry(verdict: Dictionary, index: int) -> Dictionary:
	var unmet := verdict["unmet"] as Array
	var entry = unmet[index] if index < unmet.size() else null
	if entry is Dictionary and not (entry as Dictionary).is_empty():
		return entry as Dictionary
	assert_eq(
		entry is Dictionary and not (entry as Dictionary).is_empty(),
		true,
		(
			"the verdict (%s) reports a readable unmet entry at %d, and has %d in total"
			% [String(verdict.get("reason", "")), index, unmet.size()]
		)
	)
	return {}


## One fate's view out of a summary snapshot, fetched with a shape assertion in
## front of it for the same reason `_unmet_entry` has one.
##
## **Only for a fate the codex is CONTRACTED to carry.** A `teaser` fate is
## omitted by design, so asking for its view through this helper could only ever
## fail — the absence is proved directly in
## `test_a_teaser_fate_is_omitted_from_the_codex_entirely` instead.
func _fate_view(fates: Dictionary, fate_id: StringName) -> Dictionary:
	var found = fates.get(String(fate_id), null)
	if found is Dictionary:
		return found as Dictionary
	assert_eq(
		found is Dictionary, true, "the codex carries a view for the real fate '%s'" % fate_id
	)
	return {}


## A dictionary's keys as sorted strings, so two id lists compare as VALUES
## rather than as an `Array[StringName]` against an untyped `Array`.
func _sorted(source: Dictionary) -> Array:
	var out: Array = []
	for key in source.keys():
		out.append(String(key))
	out.sort()
	return out


func _string_list(source: Array[StringName]) -> Array:
	var out: Array = []
	for entry in source:
		out.append(String(entry))
	return out


## Whether every leaf of `value` is a primitive. Recursive with a depth cap,
## because the arch rule requires one of any walk that could meet a cycle.
##
## **Keys are checked too, and that is the half that was wrong.** The previous
## version required `key is String` and reported `false` for a `StringName` key.
## `summary()` then went red on BOTH its own assertions
## ("still primitives only" and "the whole snapshot is primitives") while
## `summary(null)` passed — and the difference between the two snapshots is
## exactly `DestinyGate.unmet_prerequisites`, whose entries are built with
## `"kind": &"fate"` (`destiny_gate.gd:101`). So `summary()` was returning
## `StringName` KEYS, and the helper was refusing a type Godot's own serializer
## round-trips as a string and that no panel can observe: `String(StringName("f"))`
## is `"f"`, `key == "f"` is true, `JSON.stringify` writes `"f"`, and
## `StringName` is a built-in Variant scalar (TYPE_STRING_NAME), not an object.
##
## `summary()` is therefore NOT in violation of the "primitives only" standard
## (AGENTS.md): it is primitives all the way down, and the helper was the wrong
## shape. Keys are now required to be `String` or `StringName` — still no Object,
## Array or Dictionary hiding in a key, which is what the rule is for.
func _primitives_only(value: Variant, depth: int = 0) -> bool:
	if depth > 8:
		return false
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				if (
					not (key is String or key is StringName)
					or not _primitives_only((value as Dictionary)[key], depth + 1)
				):
					return false
			return true
		TYPE_ARRAY:
			for entry in value as Array:
				if not _primitives_only(entry, depth + 1):
					return false
			return true
		_:
			return false
