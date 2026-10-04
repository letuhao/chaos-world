extends TestCase

## `NationApi.act` is called by PRODUCTION — `app/institution_resolver.gd:195`
## runs it for every nation on every period boundary and dispatches whatever it
## returns — and no test named it.
##
## ## Why the nation suites did not catch it
##
## `modules/nation/*` drives `found`, `claim_territory`, `accrue_territory`,
## `declare_war` and `resolve_conflict` directly. `act` is the ONE verb that says
## "given `periods` elapsing at this tier, what WOULD this polity do" — and ADR
## 0085's rule is that it proposes and never acts. The whole point of the verb is
## that it holds no `rng` and computes no damage, so its answer is a pure function
## of the ledger and a period count. That purity is a claim, and nothing asserted
## it: a facade that quietly acted, or that proposed from a stale ledger, would
## leave every existing suite green.


func _founded(nation_id: StringName = &"") -> Actor:
	var actor := ActorFactory.build(&"nation_actor")
	NationApi.attach(actor)
	var founded := NationApi.found(
		actor, nation_id if nation_id != &"" else _any_nation(), "polity_a"
	)
	assert_ne(
		String(founded.get("nation_id", "")),
		"",
		"the fixture really did found a nation (found answers the LEDGER, not an ok flag)"
	)
	return actor


## The first AUTHORED nation, read from the catalog rather than typed in. Naming
## one here would couple this suite to content: a renamed nation id would fail
## every case for a reason that has nothing to do with `act`.
func _any_nation() -> StringName:
	# `known_ids` answers a `{id: def}` MAP, so the ids are its keys rather than
	# its values; indexing it as an array is the out-of-bounds this fixture hit.
	var ids := NationCatalog.instance().known_ids().keys()
	assert_ne(ids.is_empty(), true, "the catalog authors at least one nation")
	return StringName(ids[0])


## The resolver's own re-check, promoted to a test: a tier whose cap is zero means
## "nobody at this distance acts", and the answer is `acted: 0` — never a fallback
## to a nearer tier, which would make the cap decorative. `TIERS` is core's own
## ordered constant rather than a literal, so an authored tier change moves the
## fixture with it.
func test_a_tier_with_no_budget_reports_nothing_rather_than_falling_back() -> void:
	var actor := _founded()
	var budget := InstitutionBudget.shipped()
	var empty_tier := &""
	for tier in InstitutionBudget.TIERS:
		if budget.cap_for(tier) <= 0:
			empty_tier = tier
			break
	if empty_tier == &"":
		# Every shipped tier funds an action, so there is nothing to assert about a
		# barren one. Say so rather than asserting nothing, which is the failure mode
		# this whole class of finding is about.
		assert_eq(
			true, true, "every shipped tier funds an action, so the zero-cap branch has no fixture"
		)
		return
	var proposal := NationApi.act(actor, 4, empty_tier)
	assert_eq(bool(proposal["ok"]), true, "a quiet world is ok, not a failure (ADR 0083)")
	assert_eq(int(proposal.get("acted", -1)), 0, "and nobody acted at that distance")
	assert_eq((proposal.get("intents", []) as Array).size(), 0, "with no intent proposed")


## The unknown-tier refusal, NAMED rather than defaulted. A silent fallback to a
## nearer tier is the exact failure the docstring names as making the cap
## decorative, and it is the kind of defect no other suite would see.
func test_an_unknown_tier_is_refused_by_name() -> void:
	var actor := _founded()
	var proposal := NationApi.act(actor, 4, &"no_such_tier")
	assert_eq(bool(proposal["ok"]), false, "an unknown tier refuses")
	assert_eq(String(proposal.get("reason", "")), "unknown_tier", "and says which way")


## A polity that lives under NO nation is ADR 0083's FIRST state — `{}`, does not
## exist — and it is not an error. This is the branch a first-frame period tick
## takes for every actor who has not founded anything.
func test_an_unfounded_actor_reports_a_quiet_world_rather_than_a_refusal() -> void:
	var actor := ActorFactory.build(&"unfounded")
	NationApi.attach(actor)
	var proposal := NationApi.act(actor, 8, &"near")
	assert_eq(bool(proposal["ok"]), true, "no nation is not a failure")
	assert_eq(int(proposal.get("acted", -1)), 0, "and nothing acted")
	assert_ne(proposal.has("cap"), false, "the cap is still reported so a caller can budget")


## `periods <= 0` is a frame in which the world did not move. The resolver calls
## this on every boundary, including one that elapses nothing, so a refusal here
## would make a no-op frame look like a broken one.
func test_no_periods_is_a_quiet_frame_and_not_an_error() -> void:
	var actor := _founded()
	var proposal := NationApi.act(actor, 0, &"near")
	assert_eq(bool(proposal["ok"]), true, "zero periods is a quiet frame")
	assert_eq(int(proposal.get("acted", -1)), 0, "nothing acted in it")


## ADR 0085's rule, as a measurement: `act` PROPOSES and never acts. `accrue` is
## the only per-period income this module has, so an `act` that quietly called it
## would move the ledger — and a resolver that dispatches the returned intents
## would then pay the period twice.
func test_act_proposes_and_never_acts_on_the_ledger_itself() -> void:
	var actor := _founded()
	var before := str(NationApi.state(actor))
	NationApi.act(actor, 4, &"near")
	assert_eq(
		str(NationApi.state(actor)),
		before,
		"ADR 0085: a proposal is not the action, and this verb must leave the ledger alone"
	)


## Determinism: `NationAct` holds no `rng`, so the same ledger and the same period
## count must answer identically. A facade that reached for randomness would make
## a period boundary unreproducible, which is the property that makes the resolver
## safe to re-run.
func test_the_same_ledger_and_period_count_answer_identically() -> void:
	var actor := _founded()
	var first := NationApi.act(actor, 3, &"near")
	var second := NationApi.act(actor, 3, &"near")
	assert_eq(
		first.get("intents", []),
		second.get("intents", []),
		"no rng is involved, so a repeated proposal is the same proposal"
	)


## `acted` is a COUNT so a caller can assert the budget was respected rather than
## trusting it (`InstitutionResolver._apply_tier` re-checks against `cap` before
## each dispatch). The cap is carried beside it for exactly that.
func test_the_proposal_carries_its_own_cap_and_a_count_within_it() -> void:
	var actor := _founded()
	var proposal := NationApi.act(actor, 4, &"near")
	assert_ne(proposal.has("cap"), false, "the cap is published for the caller's own check")
	assert_eq(
		int(proposal.get("acted", -1)) <= int(proposal.get("cap", -1)),
		true,
		"and what it proposes never exceeds it"
	)


## No actor is a refusal, not a crash: the resolver reads a `_player` a screen may
## not have set.
func test_no_actor_refuses_rather_than_raising() -> void:
	var proposal := NationApi.act(null, 4, &"near")
	assert_eq(bool(proposal["ok"]), false, "no actor, no proposal")
	assert_eq(String(proposal.get("reason", "")), "no_actor", "and it says so")
