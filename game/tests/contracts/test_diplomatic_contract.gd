extends TestCase

## Slice 8b: diplomacy and territory as SHARED capabilities (goal 40d9bc19).
##
## The design answer, measured rather than assumed: `Territorial` (Slice 1)
## needed NO widening — a sovereign's claim over places fans out to one plan
## per place, and the two sovereign-side gates with no contract counterpart (the
## standing floor, the yield accrual) live one layer up BY DESIGN (ADR 0085: a
## claim plan carries no yield surface). What is NEW is `Diplomatic`: the closed
## stance set, the canonical unordered-pair row, and war through exactly one
## prize-declaring door, all drivable by any kind with no tier module in the
## path. The one measured divergence is the truce span: the contract charges
## one (D8 cost), the sovereign's `set_stance` writes truces without — reported
## in the contract's class note, not taken.
##
## ## D8: the cost, the counter and the scarcity of each shared behavior
##
## Transition (rival/neutral/allied/embargo) — cost: none beyond the declaration
## itself. Counter: the row is public and rewritable, one canonical row per
## pair, so either side's later verb replaces the earlier one. Scarcity: the
## pair can hold exactly one stance; a rewrite never adds a second row.
## Truce — cost: the authored `span` in periods, charged up front
## (`truce_needs_a_span` below one). Counter: the span is published on the plan,
## so both sides read when it ends. Scarcity: one row per pair, as above.
## War — cost: the declared prize both sides put at stake (transfer + standing
## deltas). Counter: the prize is fixed BEFORE the first verdict, so both sides
## know what is at stake. Scarcity: `transition` refuses `war`, so the
## declaration verb is the single door and no second one can be built quietly.
##
## Three-state vocabulary throughout: `{}` (no such row — `stance` answers a
## missing row with `verb: ""`, never a refusal), the visible row (the plan, ids
## and counts only), and `{"ok": false, "reason": <named constant>}` (refused).
## No clock anywhere: every span arrives as an explicit count. Position and
## standing never derive from each other: nothing here promotes, seats or moves
## regard, and the only standing named is the prize's own declared deltas.
##
## ## Every loop in this file is a `for`
##
## Walks are over literal verb lists, fixed probe arrays, or a shipped def's own
## authored place list; no body appends to the container it walks, so no bound
## grows in lockstep with its own body and `test_no_unbounded_wait.gd` has
## nothing to reject.

## The shipped trading guild, READ and never mutated.
const LANTERN := "res://data/packs/guilds/organizations/lantern_exchange.tres"
const LANTERN_ID := "lantern_exchange"


func setup() -> void:
	InstitutionContract.instance().clear()
	expect_assertions(2)


func teardown() -> void:
	InstitutionContract.instance().clear()


# --- the shipped suite holds, and a pack claims both --------------------------


## The suite Slice 8b ships holds on its own class, and a non-tier kind
## registers both shared capabilities with no tier module loaded.
func test_shipped_diplomatic_suite_holds_and_a_pack_claims_both() -> void:
	assert_eq(Diplomatic.new().contract_findings(), [], "diplomatic holds its own suite")
	assert_eq(Territorial.new().contract_findings(), [], "territorial still holds its own suite")
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"trading_guild", [Territorial.new(), Diplomatic.new()])["ok"]),
		true,
		"a guild claiming territory and diplomacy registers with no tier module"
	)
	assert_eq(
		contract.capabilities_of(&"trading_guild"),
		[&"diplomatic", &"territorial"] as Array[StringName],
		"both capabilities are reachable in canonical order"
	)


# --- one vocabulary, not two --------------------------------------------------


## The closed set is the sovereign's spelling, pinned word for word so the two
## lists cannot drift into a second vocabulary. The reason WORDS match too: a
## refusal a panel already renders must read the same from either side.
func test_the_closed_set_is_the_sovereigns_spelling_word_for_word() -> void:
	var closed: Array[String] = ["rival", "neutral", "allied", "truce", "embargo", "war"]
	var verbs: Array[String] = []
	for verb in Diplomatic.VERBS:
		verbs.append(String(verb))
	assert_eq(verbs, closed, "the six stance words, in order")
	var sovereign: Array[String] = []
	for verb in NationState.VERBS:
		sovereign.append(String(verb))
	assert_eq(verbs, sovereign, "and they are the sovereign's six words exactly")
	assert_eq(
		Diplomatic.R_UNKNOWN_VERB,
		NationState.R_UNKNOWN_VERB,
		"an unknown verb refuses under one name"
	)
	assert_eq(
		Diplomatic.R_WAR_REQUIRES_A_PRIZE,
		NationState.R_WAR_REQUIRES_A_PRIZE,
		"and so does a war without a prize"
	)
	assert_eq(Diplomatic.R_UNKNOWN_MODE, NationState.R_UNKNOWN_MODE, "and a bad mode")
	assert_eq(Diplomatic.R_UNKNOWN_TRANSFER, NationState.R_UNKNOWN_TRANSFER, "and a bad transfer")
	var modes: Array[String] = []
	for mode in Diplomatic.MODES:
		modes.append(String(mode))
	assert_eq(modes, ["contest", "siege", "tribunal"], "the three modes, in order")
	var transfers: Array[String] = []
	for transfer in Diplomatic.TRANSFERS:
		transfers.append(String(transfer))
	assert_eq(transfers, ["ownership", "recognition", "tribute"], "the three prize shapes")


## The canonical pair key is identical under a swap, splits back apart, and
## agrees with the sovereign's own join — one row per unordered pair, spelled
## once, so a one-sided opinion is structurally impossible on either side.
func test_the_pair_key_is_canonical_and_matches_the_sovereigns_join() -> void:
	var forward := Diplomatic.pair_key("lantern_exchange", "ashen_guild")
	var swapped := Diplomatic.pair_key("ashen_guild", "lantern_exchange")
	assert_eq(forward, swapped, "the key does not depend on argument order")
	assert_eq(
		Diplomatic.split_pair(forward),
		["ashen_guild", "lantern_exchange"],
		"and splits back into the ordered pair"
	)
	assert_eq(
		forward,
		NationState.pair_key(&"lantern_exchange", &"ashen_guild"),
		"spelled exactly as the sovereign spells it"
	)
	assert_eq(Diplomatic.split_pair("no_separator_here"), [], "an unreadable key splits to nothing")


# --- transitions: the free declarations ---------------------------------------


## A transition plans, answers identically twice, and writes nothing — not on
## success and not on refusal (ADR 0044, measured on the exact object handed).
func test_a_transition_plans_deterministically_and_writes_nothing() -> void:
	var impl := Diplomatic.new()
	var ctx := _stance_ctx("rival")
	var first := impl.transition(ctx.duplicate(true))
	var second := impl.transition(ctx.duplicate(true))
	assert_eq(JSON.stringify(first), JSON.stringify(second), "two runs answer by text")
	assert_eq(bool(first.get("ok", false)), true, "the transition plans")
	var plan: Dictionary = first["plan"]
	assert_eq(String(plan["verb"]), "rival", "naming the requested stance")
	assert_eq(
		String(plan["pair_key"]),
		Diplomatic.pair_key(LANTERN_ID, "probe_rival"),
		"under the canonical pair key"
	)
	assert_eq(int(plan["span"]), 0, "a non-truce carries no span it was never given")
	var pristine := JSON.stringify(ctx)
	var handed := ctx.duplicate(true)
	var refused := impl.transition(_war_ctx(handed))
	assert_eq(
		String(refused.get("reason", "")), Diplomatic.R_WAR_REQUIRES_A_PRIZE, "the refusal is named"
	)
	assert_eq(JSON.stringify(handed), pristine, "and the handed context is byte-identical")


## An unknown verb refuses and names itself; `war` refuses at the only door
## that is not one. A rewrite of the same pair plans again — one row per pair,
## so a later verb replaces rather than accumulates.
func test_unknown_verbs_name_themselves_and_war_has_one_door() -> void:
	var impl := Diplomatic.new()
	var strange := _stance_ctx("hostile")
	var refused := impl.transition(strange)
	assert_eq(bool(refused.get("ok", false)), false, "'hostile' is not in the closed set")
	assert_eq(
		String(refused.get("reason", "")), Diplomatic.R_UNKNOWN_VERB, "refused as unknown_verb"
	)
	assert_eq(String(refused.get("verb", "")), "hostile", "and naming the offending value")
	var war := impl.transition(_war_ctx(_stance_ctx("rival")))
	assert_eq(bool(war.get("ok", false)), false, "`war` is refused by transition")
	assert_eq(
		String(war.get("reason", "")), Diplomatic.R_WAR_REQUIRES_A_PRIZE, "with the named reason"
	)
	var allied := _stance_ctx("allied")
	assert_eq(bool(impl.transition(allied).get("ok", false)), true, "a later verb plans again")
	var read := impl.stance(_read_ctx("allied"))
	assert_eq(String(read.get("verb", "")), "allied", "and the read carries the reported row")
	var missing := _read_ctx("")
	assert_eq(
		String(impl.stance(missing).get("verb", "")), "", "no row reads as empty, not refused"
	)


## A truce without a span refuses by name; with one it plans carrying it. The
## span is the truce's whole cost, and only the truce is asked for it.
func test_a_truce_without_a_span_is_refused_and_with_one_plans() -> void:
	var impl := Diplomatic.new()
	var bare := _stance_ctx("truce")
	bare["span"] = 0
	assert_eq(
		String(impl.transition(bare).get("reason", "")),
		Diplomatic.R_TRUCE_NEEDS_A_SPAN,
		"a truce with no end refuses"
	)
	var spanned := _stance_ctx("truce")
	spanned["span"] = 4
	var planned := impl.transition(spanned)
	assert_eq(bool(planned.get("ok", false)), true, "an authored span plans")
	assert_eq(int((planned["plan"] as Dictionary)["span"]), 4, "and the plan carries it")


# --- declare: the single door to war ------------------------------------------


## A declaration plans a war with its prize verbatim — mode, transfer and every
## side's delta, exactly as handed in. Two identical declarations answer by
## text: the door is walked, never rolled.
func test_a_declaration_plans_a_war_with_its_prize_verbatim() -> void:
	var impl := Diplomatic.new()
	var ctx := _war_ctx(_stance_ctx("rival"))
	var first := impl.declare(ctx.duplicate(true))
	var second := impl.declare(ctx.duplicate(true))
	assert_eq(JSON.stringify(first), JSON.stringify(second), "deterministic across two runs")
	assert_eq(bool(first.get("ok", false)), true, "the declaration plans")
	var plan: Dictionary = first["plan"]
	assert_eq(String(plan["verb"]), "war", "and it is a war")
	assert_eq(plan["mode"], "contest", "the mode rides verbatim")
	assert_eq(plan["transfer"], "ownership", "and so does the transfer")
	assert_eq(
		plan["standing"],
		{LANTERN_ID: 10, "probe_rival": -5},
		"with every side's delta exactly as declared"
	)
	assert_eq(
		String(plan["pair_key"]),
		Diplomatic.pair_key(LANTERN_ID, "probe_rival"),
		"under the one canonical row for the pair"
	)


## Every fault at the single door refuses by name: a war against yourself, an
## unknown mode, an unknown transfer, and a prize the contract cannot read.
func test_the_single_door_refuses_every_fault_by_name() -> void:
	var impl := Diplomatic.new()
	var itself := _war_ctx(_stance_ctx("rival"))
	itself["other"] = LANTERN_ID
	assert_eq(
		String(impl.declare(itself).get("reason", "")),
		Diplomatic.R_SELF_DEALING,
		"a standoff needs two sides"
	)
	var strange_mode := _war_ctx(_stance_ctx("rival"))
	strange_mode["mode"] = "skirmish"
	assert_eq(
		String(impl.declare(strange_mode).get("reason", "")),
		Diplomatic.R_UNKNOWN_MODE,
		"an undeclared mode"
	)
	var strange_transfer := _war_ctx(_stance_ctx("rival"))
	strange_transfer["transfer"] = "annexation"
	assert_eq(
		String(impl.declare(strange_transfer).get("reason", "")),
		Diplomatic.R_UNKNOWN_TRANSFER,
		"an undeclared transfer"
	)
	var empty_transfer := _war_ctx(_stance_ctx("rival"))
	empty_transfer["transfer"] = ""
	assert_eq(
		bool(impl.declare(empty_transfer).get("ok", false)),
		true,
		"an EMPTY transfer declares nothing moving — a tribunal's shape, not a bug"
	)
	var broken_prize := _war_ctx(_stance_ctx("rival"))
	broken_prize["standing"] = "ten"
	assert_eq(
		String(impl.declare(broken_prize).get("reason", "")),
		InstitutionCapability.R_MALFORMED,
		"a prize the contract cannot read"
	)
	var nobody := _war_ctx(_stance_ctx("rival"))
	nobody["other"] = ""
	assert_eq(
		String(impl.declare(nobody).get("reason", "")),
		Diplomatic.R_NO_OTHER,
		"a declaration against nobody"
	)


# --- D3: the red path ----------------------------------------------------------


## A capability that lets `war` through the transition fails its own suite —
## the finding names the rule — and the KIND is refused at registration, whole.
func test_d3_a_war_through_the_transition_is_refused_at_registration() -> void:
	var broken := _WarThroughTransition.new()
	var findings := broken.contract_findings()
	assert_eq(findings.is_empty(), false, "the mutant fails its own suite")
	assert_eq(_names(findings, "war_requires_a_prize").is_empty(), false, "naming the rule")
	var contract := InstitutionContract.instance()
	var answer := contract.register(&"war_door_mutant", [broken])
	assert_eq(bool(answer.get("ok", false)), false, "and the KIND is refused")
	assert_eq(String(answer.get("reason", "")), InstitutionContract.R_CONTRACT_FAILED, "by name")
	assert_eq(String(answer.get("capability", "")), "diplomatic", "naming the offender")
	assert_eq(contract.knows(&"war_door_mutant"), false, "and no row was written")


## A capability that mutates its context fails its own suite, and registration
## refuses it with the findings published for the pack's author to read.
func test_d3_a_context_mutating_diplomat_is_refused_at_registration() -> void:
	var broken := _MutatingDiplomat.new()
	var findings := broken.contract_findings()
	assert_eq(findings.is_empty(), false, "the mutant fails its own suite")
	assert_eq(_names(findings, "mutated the context").is_empty(), false, "naming the mutation")
	var contract := InstitutionContract.instance()
	var answer := contract.register(&"mutant_diplomat", [broken])
	assert_eq(String(answer.get("reason", "")), InstitutionContract.R_CONTRACT_FAILED, "refused")
	assert_eq(
		(answer.get("findings", []) as Array).is_empty(), false, "publishing what it got wrong"
	)


# --- the reference implementation: a guild with NO tier code -------------------


## The Lantern Exchange claims BOTH shared capabilities with NO tier module: it
## plans a place claim through `Territorial` and a stance walk plus a war
## declaration through `Diplomatic`. The guild authors no ground (measured, as
## in Slice 8a), so the place universe is the case's — a generic house authors
## no map, and where a kind authors its numbers is its own content question.
func test_the_guild_claims_ground_and_keeps_house_with_no_tier_code() -> void:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	assert_eq(String(def.kind), "trading_guild", "and it is a trading guild, not a nation")
	assert_eq(def.claimed_territories(), [], "authoring no ground: the case authors the universe")
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"trading_guild", [Territorial.new(), Diplomatic.new()])["ok"]),
		true,
		"the kind registers with no tier module"
	)
	var ground := contract.of(&"trading_guild", &"territorial")["capability"] as Territorial
	var house := contract.of(&"trading_guild", &"diplomatic")["capability"] as Diplomatic
	var places: Array = []
	var claim_ctx := {
		"kind": "trading_guild",
		"institution": LANTERN_ID,
		"member": "probe_factor",
		"places": places,
		"authored": ["probe_meadow", "probe_harbour"],
		"holder": "",
		"place": "probe_harbour",
	}
	var planned := ground.claim(claim_ctx.duplicate(true))
	assert_eq(bool(planned.get("ok", false)), true, "an authored, unheld place plans")
	assert_eq(
		String((planned["plan"] as Dictionary)["institution"]),
		LANTERN_ID,
		"in the guild's own name"
	)
	# The applier writes the plan; the next claim over the same place refuses.
	places.append("probe_harbour")
	var held_ctx := claim_ctx.duplicate(true)
	held_ctx["places"] = places
	assert_eq(
		bool(ground.holds(held_ctx, &"probe_harbour")["has"]), true, "the written claim reads held"
	)
	var again := held_ctx.duplicate(true)
	again["place"] = "probe_harbour"
	assert_eq(
		String(ground.claim(again).get("reason", "")),
		Territorial.R_ALREADY_CLAIMED,
		"and a re-claim refuses by name"
	)
	# And the guild keeps house: rival, then a spanned truce, then allied.
	var rival := house.transition(_guild_stance("rival"))
	assert_eq(bool(rival.get("ok", false)), true, "the guild declares a rivalry")
	var truce := _guild_stance("truce")
	truce["span"] = 3
	var truced := house.transition(truce)
	assert_eq(bool(truced.get("ok", false)), true, "then a spanned truce")
	assert_eq(int((truced["plan"] as Dictionary)["span"]), 3, "carrying its span")
	var allied := house.transition(_guild_stance("allied"))
	assert_eq(bool(allied.get("ok", false)), true, "then an alliance")
	assert_eq(
		String(house.transition(_guild_war_door()).get("reason", "")),
		Diplomatic.R_WAR_REQUIRES_A_PRIZE,
		"while war through the transition refuses"
	)
	var declared := house.declare(_guild_declaration())
	assert_eq(bool(declared.get("ok", false)), true, "and the declaration door plans the war")
	assert_eq(String((declared["plan"] as Dictionary)["verb"]), "war", "naming the war it planned")
	# Both plans are JSON-stable: parse, write, parse again is a fixed point, so
	# a save/load cycle cannot drift them.
	for plan in [planned["plan"], declared["plan"]]:
		var text := JSON.stringify(plan)
		var once = JSON.parse_string(text)
		assert_ne(once, null, "the plan parses")
		assert_eq(JSON.parse_string(JSON.stringify(once)), once, "and survives a round-trip")


## No clock and no generator in the new contract: diplomacy is a pure function
## of its context. Comment prose is skipped — the class notes name the banned
## words to document the ban, so only executable lines are read.
func test_the_new_contract_consults_no_clock_or_generator() -> void:
	var body := FileAccess.get_file_as_string("res://src/contracts/diplomatic.gd")
	assert_ne(body, "", "the file is readable")
	for banned in [
		"RandomNumberGenerator",
		"randi(",
		"randf(",
		"randomize(",
		"Time.get_ticks_msec(",
		"Time.get_ticks_usec(",
	]:
		assert_eq(_calls(body, banned), 0, "diplomatic.gd never calls %s" % banned)


# --- contexts -------------------------------------------------------------------


## One stance context for the guild's own house, in the guild's own name.
func _guild_stance(verb: String) -> Dictionary:
	return {
		"kind": "trading_guild",
		"institution": LANTERN_ID,
		"member": "probe_factor",
		"other": "ashen_guild",
		"verb": verb,
		"current": "",
		"span": 0,
		"mode": "contest",
		"transfer": "",
		"standing": {},
	}


## The guild's war through the wrong door: always refused, whatever it carries.
func _guild_war_door() -> Dictionary:
	var ctx := _guild_stance("war")
	return ctx


## The guild's declaration: a war with its prize fixed up front.
func _guild_declaration() -> Dictionary:
	var ctx := _guild_stance("rival")
	ctx["mode"] = "contest"
	ctx["transfer"] = "recognition"
	ctx["standing"] = {LANTERN_ID: 5, "ashen_guild": -3}
	return ctx


## One probe stance context, keyed by the requested verb.
func _stance_ctx(verb: String) -> Dictionary:
	return {
		"kind": "contract_probe",
		"institution": LANTERN_ID,
		"member": "probe_member",
		"other": "probe_rival",
		"verb": verb,
		"current": "",
		"span": 3,
		"mode": "contest",
		"transfer": "ownership",
		"standing": {LANTERN_ID: 10, "probe_rival": -5},
	}


## The same probe, asking for `war` through the transition — always refused.
func _war_ctx(ctx: Dictionary) -> Dictionary:
	var out := ctx.duplicate(true)
	out["verb"] = "war"
	return out


## One probe read context, reporting the given current row.
func _read_ctx(current: String) -> Dictionary:
	return {
		"kind": "contract_probe",
		"institution": LANTERN_ID,
		"member": "probe_member",
		"other": "probe_rival",
		"current": current,
	}


## The findings naming `needle`, so a red suite is asserted on the RULE it
## broke rather than on a bare non-empty.
func _names(findings: Array[String], needle: String) -> Array[String]:
	var out: Array[String] = []
	for finding in findings:
		if finding.contains(needle):
			out.append(finding)
	return out


## How many times `needle` appears in CODE, ignoring `##` prose: a class doc
## names the verbs it refuses, so a raw substring scan reads the sentence as
## the call.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## A diplomat that lets `war` through the transition: the single door broken,
## so the suite — and registration — must refuse it.
class _WarThroughTransition:
	extends Diplomatic

	func transition(ctx: Dictionary) -> Dictionary:
		if InstitutionCapability.text(ctx.get("verb", ""), "") == "war":
			return InstitutionCapability.ok({"plan": {"verb": "war"}})
		return super(ctx)


## A diplomat that writes into the context it was handed: the ADR 0044 mutant.
class _MutatingDiplomat:
	extends Diplomatic

	func transition(ctx: Dictionary) -> Dictionary:
		(ctx as Dictionary)["mutated"] = true
		return super(ctx)
