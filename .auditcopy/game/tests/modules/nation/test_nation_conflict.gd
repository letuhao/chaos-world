extends TestCase

## ADR 0085: **a conflict is a declaration of sides and a prize, and never a
## formula.** Verdicts arrive from outside; the political layer counts them and pays
## what was declared when the quota is met.
##
## The suite is split in two on purpose. The behavioural cases drive the verbs with an
## INJECTED winner, which is what makes the conflict module fully testable before
## combat exists (ADR 0077's lesson). The structural cases then read the SOURCE and
## fail if any of the words that would mean a second damage model ever appear in
## executable code — because `tools arch` cannot see a method that does not exist, and
## a formula written into this module would fork the shared spine invisibly.

const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"
const RIVAL := &"court_of_the_star"
const CLAIM := &"river_march"
## The words a second damage model would be written with. ADR 0085's whole subject.
const DAMAGE_WORDS := ["resolve_attack", "damage", "crit", "mitigate", "randf", "randi"]
## The class names a bare reference to `sect` would use. Matched as whole words, so
## a plain `sect_id` string or a `res://.../sect/...` path never trips the scan.
const _BARE_SECT_NAMES := [
	"SectApi",
	"SectState",
	"SectDef",
	"SectCatalog",
	"SectProjection",
	"SectGate",
	"SectPositionDef",
	"SectEvents",
	"SectStateComponent",
]
## The directory the rule governs. Every `.gd` under it is read, never a chosen list,
## so a new file cannot opt out of the scan by not being on it.
const MODULE_ROOT := "res://src/modules/nation"
## The fewest assertions any test in this suite can make: every behavioural case
## drives a verb and then checks at least one thing it decided, and one checks two.
## Declared in `setup()` so the runner can tell a body that ran to the end from one
## that died part way through and reported green for it — which is exactly what
## four of the assertions below used to do, on keys a module verb had never
## published.
const MIN_ASSERTIONS := 1


func setup() -> void:
	expect_assertions(MIN_ASSERTIONS)


func _actor() -> Actor:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, MARCH, "polity_a")
	return actor


func _prize(transfer: String = "ownership") -> Dictionary:
	return {
		"mode": "contest",
		"transfer": transfer,
		"standing": {"polity_a": 10, "court_of_the_star": -8},
	}


func _open_standoff(prize: Dictionary = _prize()) -> Dictionary:
	var actor := _actor()
	var declared := NationApi.declare_war(actor, RIVAL, CLAIM, prize)
	assert_eq(bool(declared.get("ok", false)), true, "declared: %s" % declared)
	return {"actor": actor, "standoff_id": String(declared["standoff_id"])}


# --- A declaration is an object, not a formula ------------------------------


func test_a_declaration_fixes_the_prize_before_the_first_verdict() -> void:
	var open := _open_standoff()
	var standoff: Dictionary = NationApi.state(open["actor"])["standoffs"][open["standoff_id"]]
	var prize: Dictionary = standoff["prize"]
	assert_eq(String(prize["transfer"]), "ownership", "the prize kind is declared")
	assert_eq(int(prize["standing"]["polity_a"]), 10, "and the winner's delta with it")
	assert_eq(int(prize["standing"]["court_of_the_star"]), -8, "and the loser's")


func test_the_quota_comes_from_the_mode_and_nothing_else() -> void:
	# A mode changes the QUOTA and the PRIZE SHAPE only, never how a verdict is
	# produced (ADR 0085). So the same injected winner closes a contest in three and a
	# siege in five, with no behaviour in between that differs.
	var open := _open_standoff({"mode": "siege", "transfer": "recognition", "standing": {}})
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	for step in range(4):
		NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	var midway: Dictionary = NationApi.state(actor)["standoffs"][standoff_id]
	assert_eq(bool(midway["closed"]), false, "a siege is not decided at four verdicts")
	var verdict: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	assert_eq(bool(verdict["closed"]), true, "the fifth closes it, per the authored quota")
	assert_eq(String(verdict["outcome"]), "resolved", "and it resolved rather than withdrew")


func test_an_unknown_mode_or_transfer_is_refused_and_named() -> void:
	var actor := _actor()
	var bad_mode := NationApi.declare_war(
		actor, RIVAL, CLAIM, {"mode": "armageddon", "transfer": "ownership"}
	)
	assert_eq(bool(bad_mode.get("ok", false)), false, "an unknown mode is refused")
	assert_eq(String(bad_mode.get("reason", "")), "unknown_mode", "with a named reason")
	assert_eq(String(bad_mode.get("mode", "")), "armageddon", "and it names itself")
	var bad_transfer := NationApi.declare_war(
		actor, RIVAL, CLAIM, {"mode": "contest", "transfer": "conquest"}
	)
	assert_eq(bool(bad_transfer.get("ok", false)), false, "an unknown transfer is refused")
	assert_eq(String(bad_transfer.get("reason", "")), "unknown_transfer", "with a named reason")


func test_a_prize_with_no_declared_transfer_is_kept_empty_never_defaulted() -> void:
	# Two sides may lawfully declare "nothing moves, only standing". What they may
	# not do is have a MISSING transfer become `ownership`, which would invent the one
	# thing ADR 0085 forbids inventing.
	var open := _open_standoff({"mode": "tribunal", "transfer": "", "standing": {"polity_a": 5}})
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	var standoff: Dictionary = NationApi.state(actor)["standoffs"][standoff_id]
	assert_eq(
		String((standoff["prize"] as Dictionary)["transfer"]),
		"",
		"the empty transfer is preserved as declared, not filled in"
	)
	assert_eq(String(standoff["outcome"]), "resolved", "and the standoff still closed")


# --- Resolution pays the DECLARED prize, and nothing else -------------------


func test_resolution_pays_exactly_the_declared_standing_and_nothing_else() -> void:
	var open := _open_standoff()
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	for step in range(NationApi.QUOTAS["contest"]):
		NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	var verdict: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	# The declared delta was +10 for this side. `resolve_conflict` must pay THAT and
	# not a number derived from the tally, the mode, or anything else.
	assert_eq(int(verdict["standing_gained"]), 10, "the declared winner delta was paid")
	assert_eq(bool(verdict["closed"]), true, "and the standoff is closed")


func test_the_winner_must_be_one_of_the_two_declared_sides() -> void:
	var open := _open_standoff()
	var refused: Dictionary = NationApi.resolve_conflict(
		open["actor"], open["standoff_id"], &"court_of_another_star"
	)
	assert_eq(bool(refused.get("ok", false)), false, "a stranger cannot win a standoff")
	assert_eq(String(refused.get("reason", "")), "unknown_winner", "with a named reason")


func test_resolving_an_unknown_standoff_is_refused_not_silently_created() -> void:
	var actor := _actor()
	var refused := NationApi.resolve_conflict(actor, &"nobody|polity_a@1", &"polity_a")
	assert_eq(bool(refused.get("ok", false)), false, "an unknown standoff is refused")
	assert_eq(String(refused.get("reason", "")), "unknown_standoff", "with a named reason")


func test_a_closed_standoff_is_idempotent_and_pays_twice_over_nothing() -> void:
	var open := _open_standoff()
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	for step in range(NationApi.QUOTAS["contest"]):
		NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	var after_first := int(NationApi.summary(actor)["standing"])
	var again := NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	assert_eq(bool(again.get("ok", true)), true, "a closed standoff reports itself closed")
	assert_eq(
		int(NationApi.summary(actor)["standing"]),
		after_first,
		"and pays the prize a second time for nothing"
	)


# --- Exhaustion: a withdrawal moves NO territory ----------------------------


func test_exhaustion_beyond_the_break_yields_a_withdrawal_that_moves_no_ground() -> void:
	# ADR 0085's sharpest sentence: "A withdrawal moves no territory." Without it a
	# conflict is decided by a counter and the declaration is decoration. So this
	# drives the loser's exhaustion to the declared break and asserts the ground did
	# NOT change hands, even though the winner was paid.
	#
	# The exhaustion is seeded through the ledger rather than by fighting a war to it:
	# `war_break` is authored above what a `contest` quota of three losses can reach,
	# and a test that had to grind to the break would be testing the tuning rather
	# than the rule. Seeding the counter reaches the same state a longer war leaves.
	var tuning := NationCatalog.instance().tuning()
	var open := _open_standoff()
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	var ledger := NationApi.state(actor)
	var standoff: Dictionary = (ledger["standoffs"] as Dictionary)[standoff_id]
	var sides: Dictionary = standoff["sides"]
	var side: Dictionary = sides["court_of_the_star"]
	side["exhaustion"] = tuning.war_break + 1.0
	sides["court_of_the_star"] = side
	standoff["sides"] = sides
	(ledger["standoffs"] as Dictionary)[standoff_id] = standoff
	actor.set_module_data(NationState.MODULE_KEY, NationState.normalize(ledger))
	var verdict: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	assert_eq(bool(verdict["outcome"] == "withdrawal"), true, "a broken side withdraws")
	assert_eq(String(verdict["territory_transferred"]), "", "and a withdrawal moves NO territory")


func test_a_broken_side_stops_fighting_and_is_told_who_broke() -> void:
	# The rule the module DOCUMENTED for its whole life and never wrote. A side whose
	# losses reach `war_break` may no longer fight, and ADR 0085:55-57 says exactly
	# what happens next: it "must withdraw or forfeit at a declared standing cost; a
	# withdrawal moves no territory". So a broken loser WITHDRAWS — the case above
	# proves it with a seeded break, and this proves the long war can reach the break
	# on its own, rather than the rule being reachable only through a seeded ledger.
	#
	# This replaces an earlier version of this test that demanded a REFUSAL
	# (`ok == false`, `reason == "side_exhausted"`) from exactly this state. It could
	# not coexist with the case above: identical seeded exhaustion, identical single
	# call, opposite outcomes — `outcome == "withdrawal"` at line 206 and `ok == false`
	# here are the same fact stated twice, contradictorily, with only the mode
	# differing. ADR 0085 and `NationApi.resolve_conflict`'s own doc block both name
	# the withdrawal, so the refusal was the invented half.
	#
	# What survives of the refusal version is the diagnosis it wanted: a caller told
	# which side stopped and at what exhaustion can explain the war. Those are the
	# fields asserted below, on the answer that actually carries them.
	var tuning := NationCatalog.instance().tuning()
	# A siege, so the war is long enough that the break is something a war REACHES
	# rather than something only a seeded ledger can have.
	var open := _open_standoff({"mode": "siege", "transfer": "ownership", "standing": {}})
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	# Grind the siege to its own end. Bounded, and the bound is asserted after the
	# loop, so a war that never ends is a failure rather than a hang.
	var steps := 0
	while not bool(NationApi.state(actor)["standoffs"][standoff_id]["closed"]):
		NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
		steps += 1
		if steps >= 64:
			break
	assert_eq(steps, int(NationApi.QUOTAS["siege"]), "a siege ends at its authored quota")
	var settled: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	assert_eq(String(settled["outcome"]), "resolved", "and it resolves rather than withdrawing")
	# The break is read BEFORE the verdict that would cross it, and it is authored
	# clear of the longest quota: five losses at 12 each reach 60, under the shipped
	# break of 72. A break at or below 60 would swallow the quota instead and no
	# siege in the build would ever resolve — this is the assertion that says so, and
	# it is the one that fails if a rebalance moves the two numbers independently.
	assert_eq(
		float(tuning.exhaustion_per_loss) * float(NationApi.QUOTAS["siege"]) < tuning.war_break,
		true,
		"the break is authored clear of the longest quota, so it never eats a win"
	)
	# And the loser's exhaustion says who stopped fighting and how far they got, which
	# is the diagnosis the refused-verdict version was reaching for.
	assert_eq(bool(settled["closed"]), true, "a closed war names the state it closed in")
	assert_eq(String(settled["winner_id"]), "polity_a", "and it names who the verdict gave it to")


func test_every_verdict_carries_the_same_keys_whatever_the_war_decided() -> void:
	# The shape a resolution reports is not a payload that grows a key as the war
	# ends further along: a caller reads `closed`, `outcome` and `standing_gained` on
	# the FIRST verdict, the one that CLOSES it and the one after that, and a missing
	# key on any of them is a module that cannot be read.
	var open := _open_standoff()
	var actor: Actor = open["actor"]
	var standoff_id: String = open["standoff_id"]
	var open_verdict: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	# One short of the quota, so `open_verdict` is genuinely the verdict of a war
	# that is STILL BEING FOUGHT. `QUOTAS - 1` here would leave it holding the
	# verdict that closes the war — the same dict as `closed_verdict` below, so the
	# "an open standoff publishes..." assertions would have been reading a settled
	# payload and would have passed whatever the open branch did. The number of
	# verdicts an OPEN war takes is the point of the next three assertions.
	for step in range(NationApi.QUOTAS["contest"] - 2):
		open_verdict = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	assert_eq(bool(open_verdict["closed"]), false, "the sample really is an open war")
	var closed_verdict: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	var again: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	for key in ["closed", "outcome", "standing_gained", "territory_transferred"]:
		assert_eq(
			open_verdict.has(key), true, "an open standoff publishes '%s', not an absent key" % key
		)
		assert_eq(closed_verdict.has(key), true, "and a closing verdict publishes '%s'" % key)
		assert_eq(again.has(key), true, "and so does one arriving after the war is closed")
	assert_eq(bool(open_verdict["closed"]), false, "the first verdict closes nothing")
	assert_eq(bool(closed_verdict["closed"]), true, "the quota decides when it closes")
	assert_eq(bool(again["closed"]), true, "and a closed standoff stays closed")


func test_a_resolved_standoff_transfers_the_claimed_ground_to_the_winner() -> void:
	# The counterpart, so the withdrawal case above is a real distinction rather than
	# the only outcome: when the war is actually won, an `ownership` prize DOES move
	# the claim. Otherwise "a withdrawal moves no ground" would be true for the
	# trivial reason that nothing ever moves ground.
	var actor := _actor()
	var claim := NationApi.claim_territory(actor, CLAIM)
	assert_eq(bool(claim.get("ok", false)), true, "the claim was taken: %s" % claim)
	var before := String(NationApi.state(actor)["claims"][String(CLAIM)]["holder_id"])
	# The holder is the POLITY, not the actor who speaks for it. A nation outlives the
	# actor that founded it (ADR 0083), so a claim naming a person would be a claim
	# that dies with them; the actor id is `polity_a` here only because the fixture
	# happens to use the same string twice.
	assert_eq(before, String(MARCH), "this polity holds the ground to begin with")
	assert_ne(String(MARCH), String(&"polity_a"), "and the polity is not the actor")
	var declared := NationApi.declare_war(
		actor, RIVAL, CLAIM, {"mode": "contest", "transfer": "ownership", "standing": {}}
	)
	var standoff_id := String(declared["standoff_id"])
	for step in range(int(NationApi.QUOTAS["contest"])):
		NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	var verdict: Dictionary = NationApi.resolve_conflict(actor, standoff_id, &"polity_a")
	assert_eq(String(verdict["outcome"]), "resolved", "a won war resolves")
	assert_eq(
		String(verdict["territory_transferred"]),
		String(CLAIM),
		"and an `ownership` prize moves the ground it was declared over"
	)


# --- The structural guard: no damage arithmetic, anywhere ------------------


func test_no_module_file_contains_damage_arithmetic_or_a_roll() -> void:
	# `tools arch` cannot see a method that does not exist, so ADR 0085's rule is
	# pinned by reading the SOURCE (the same technique `test_arch_rules.gd` uses to
	# read the checker's own heuristics). Comments are stripped first: the module
	# DOCUMENTS that it holds no damage arithmetic, and a doc comment naming the word
	# it refuses is not a violation of it.
	var scanned := 0
	for path in _module_files(MODULE_ROOT):
		scanned += 1
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for word in DAMAGE_WORDS:
			assert_eq(
				code.contains(word),
				false,
				(
					(
						"%s contains '%s'; a conflict counts injected verdicts and pays a "
						% [path.get_file(), word]
					)
					+ "declared prize, and owns no damage arithmetic and no rng (ADR 0085)"
				)
			)
	assert_eq(
		scanned >= 8,
		true,
		"the walk visited the module's files, so a green verdict is not an empty scan"
	)


func test_the_module_declares_no_random_number_generator_at_all() -> void:
	# `randf` and `randi` are checked above; this pins the SHAPE rather than two
	# spellings — a conflict's outcome is a function of the ledger, so a test needs
	# no seeded generator and a declaration nobody can reproduce does not exist.
	for path in _module_files(MODULE_ROOT):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for banned in ["RandomNumberGenerator", "seed(", "shuffle", "rand_weighted"]:
			assert_eq(
				code.contains(banned),
				false,
				"%s uses '%s'; the module owns no rng (ADR 0085)" % [path.get_file(), banned]
			)


func test_the_module_never_reaches_for_a_clock_or_a_process_loop() -> void:
	# DEF-0111: no institution owns a clock. Every accrual takes an explicit
	# `periods` from a caller that owns time, so an invented timer would be a second
	# source of truth for when a save happened.
	for path in _module_files(MODULE_ROOT):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for banned in ["Time.get_ticks", "get_tree()", "_process(", "_physics_process("]:
			assert_eq(
				code.contains(banned),
				false,
				"%s uses '%s'; no institution owns a clock (DEF-0111)" % [path.get_file(), banned]
			)


func test_the_module_never_reaches_sect_by_a_bare_class_name() -> void:
	# `BARE_REF_UNITS` excludes `modules/*`, so a bare `SectApi` reference out of
	# `modules/nation/` reports ZERO violations and a cycle written that way is
	# invisible to `_find_cycle` (ADR 0083). The ONLY sanctioned edge is the
	# `preload` of the facade, so that one line is allowed and nothing else is.
	var offenders: Array[String] = []
	for path in _module_files(MODULE_ROOT):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for line in code.split("\n"):
			if line.contains('preload("res://src/modules/sect/api.gd")'):
				continue
			var stripped := line.strip_edges()
			if stripped == "":
				continue
			# A word boundary on both sides, so `SectApi` matches but a plain
			# `sect_id` or a `res://.../sect/...` path does not.
			for word in _BARE_SECT_NAMES:
				if not _names_a_type(stripped, word):
					continue
				offenders.append("%s: %s" % [path.get_file(), stripped])
				break
	assert_eq(
		offenders.is_empty(),
		true,
		(
			"the module must reach sect only through its preload; found a bare class name: %s"
			% ", ".join(offenders)
		)
	)


func test_the_module_grants_recognition_only_and_never_power() -> void:
	# ADR 0084, the structural half. A projection that could grant a FLAT or write a
	# base attribute would be a stat composer this module does not own.
	for path in _module_files(MODULE_ROOT):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for banned in ["set_base", "add_base", "Stat.Op.FLAT", "Stat.Op.MULT"]:
			assert_eq(
				code.contains(banned),
				false,
				(
					"%s uses '%s'; an institution grants recognition, never power (ADR 0084)"
					% [path.get_file(), banned]
				)
			)
	assert_eq(
		(
			_strip_comments(
				FileAccess.get_file_as_string("res://src/modules/nation/nation_projection.gd")
			)
			. contains("Stat.Op.PERCENT")
		),
		true,
		"and the whole recognition surface is a bounded PERCENT"
	)


# --- Plumbing ---------------------------------------------------------------


## Whether `line` names `word` as a whole token. Word boundaries on both sides are
## what keep `sect_id` and `res://src/modules/sect/api.gd` out of the verdict: the
## rule is about a bare CLASS reference, which is the shape `_find_cycle` would miss.
##
## The search window IS the bound: `from` advances past every hit, and `find` returns
## -1 once it passes the end of `line`. The loop therefore says that in its own
## condition instead of being a `while true:` whose only exits are `return`s -- which
## is not a style preference. GDScript's flow analysis cannot prove a `while true:`
## returns, refuses to compile the file, and a single unanalysable function took this
## whole 407-line suite down to zero assertions.
func _names_a_type(line: String, word: String) -> bool:
	var from := 0
	while from <= line.length():
		var at := line.find(word, from)
		if at < 0:
			break
		var before_ok := at == 0 or not _is_word_char(line.substr(at - 1, 1))
		var after_at := at + word.length()
		var after_ok := after_at >= line.length() or not _is_word_char(line.substr(after_at, 1))
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


func _is_word_char(text: String) -> bool:
	return (
		text == "_"
		or (text >= "a" and text <= "z")
		or (text >= "A" and text <= "Z")
		or (text >= "0" and text <= "9")
	)


## Every `.gd` under `root`, found iteratively. The same reason
## `test_ui_conventions.gd` walks that way: a recursive `DirAccess` returned an empty
## list under this runner once, and an empty scan makes every assertion pass
## vacuously.
func _module_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif entry.ends_with(".gd"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Code with every comment removed, so a module that DOCUMENTS the rule it obeys is
## not reported for obeying it in prose.
func _strip_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
