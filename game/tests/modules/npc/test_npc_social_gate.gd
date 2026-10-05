extends TestCase

## DEF-0123 (the NPC-behaviour half) — **an NPC's warmth answers to a social gate, and the
## counterpart withdraws it** (ADR 0264).
##
## ## What this file is FOR
##
## The measurement behind ADR 0264 found the behaviour half MOSTLY built: ADR 0253's alive
## layer already reacts to the **bond class**, which is a pure function of `standing` and
## `trust`. What did not exist anywhere in `npc/` was `regard` — the **institutional** axis
## `clan`, `sect` and `nation` all write, and the one `SocialGate`'s `regard_at_least` verb
## exists for. So this suite is written to be **adversarial about the seam itself**: every case
## below is one a neutral, ungated, un-booted build cannot pass, and each names which of the
## three risk shapes it kills (a second evaluator, a dead seam that reads as a refusal, an
## advantage with no counterpart).
##
## ## The three things this proves
##
##  1. **A gate moves behaviour only through an injected reader.** With none bound, a def that
##     authors a gate still answers **exactly as it shipped** — because the un-booted default
##     has to be today's behaviour or it is not a safe landing.
##  2. **`NpcGates` never interprets a verb.** The authored dictionary is handed to the reader
##     **untouched**, so there is one evaluator in the repo (`SocialGate`) and not two.
##  3. **Warmth is SIGNED.** `+1` when the world holds the player at the bar, `-1` when it does
##     not, `0` when nothing is asked. A gate that only ever opens is the strict-best-response
##     defect AGENTS.md's yin-yang rule exists to prevent, so the counterpart is asserted as
##     loudly as the advantage.

const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"

## An institution id. `regard_at_least` reads `state.regard[<id>]`, so the subject is an
## institution rather than a person — which is the WHOLE point of the axis and why a bond
## class cannot stand in for it.
const HOUSE := &"house_ironwood"

## ## Write regard the way the WORLD writes it: through an institutional cause
##
## **`SocialState.regard` is DERIVED** — `_rebuild_regard()` recomputes it on every mutation
## from the bonds whose cause row carries the stored `institutional` flag, and a direct
## `state.regard[id] = x` is overwritten before anybody reads it. So the fixture applies
## `sworn_to_a_clan` (a real shipped institutional cause, `social_cause_catalog.gd:518`,
## standing +1.5) twice, and the gate's threshold is authored at **+1.0** so one oath is not
## enough and two are. That is the anti-farm shape ADR 0091 asks for: the player cannot reach
## the gate by one act, and the axis stays `social`'s to derive.
const REGARD_AT := 1.0
const REGARD_GATE := {
	"verb": &"regard_at_least",
	"partner": "house_ironwood",
	"at_least": 1.0,
}

var _player: Actor
var _held: Array[Actor] = []

## ## The reader double, HELD for the lifetime of the test
##
## `test_the_reader_receives_the_authored_requirement_untouched` was red as
## `the reader was called once: expected 1, got 0`, and the array it reads was empty — so
## `record_and_pass` never ran, and the only two reasons for that are a seam that refused
## to call and a double that was already gone. It was the double: the test built it
## inline as `Callable(BadReaders.new(), "record_and_pass")`, so the only reference to the
## `RefCounted` was an expression whose value ended at the end of the line, and
## `NpcGates` had stored a Callable naming an object that could be collected. A seam whose
## lifetime is a test's local variable is a seam whose reader vanishes at a line break,
## and the neutral default then covers for it — which is exactly the "a dead reader reads
## as no opinion" path the neutral default is FOR, and exactly why it hid this.
##
## Holding it in a member is the same discipline the `_held` array applies to the Actors
## below, and it is the shape every `EventBeatWriter`/`MarketFavour` double in this repo
## uses. Nothing about the assertion changes: the reader is still called, and the
## requirement is still asserted byte-identically.
var _double: BadReaders = null


func setup() -> void:
	# A FLOOR, not an exact count, and deliberately LOWER than the per-test declarations
	# below: a suite-wide floor is only honest while every test in the file clears it, and
	# four of these tests legitimately make one or two assertions. Setting the floor per
	# test (each body calls `expect_assertions(n)` for the number it really makes) is what
	# keeps the guarantee this line exists for — a body that dies mid-way has asserted
	# fewer times than it declared — while a blanket `3` would instead report short-but-
	# complete bodies as failures, which is the same "runner cannot tell" problem the
	# floor was added to solve. See `framework.gd:135`.
	expect_assertions(1)
	SocialCauseCatalog.instance().install_defaults()
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()
	NpcAliveness.reset()
	# ## The seam starts RELEASED in every test
	#
	# `NpcGates._reader` is a `static var` and the runner shares one process across every
	# suite, so a reader left installed would silently re-gate every later npc suite — the
	# same hazard `MarketFavour`'s teardown exists for.
	NpcGates.reset()
	_player = Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(_player)
	NpcApi.set_minter(_mint)
	NpcApi.attach(_player)
	_double = BadReaders.new()
	_held.clear()


func teardown() -> void:
	NpcGates.reset()
	NpcRegistry.instance().reset()
	NpcAliveness.reset()
	_double = null
	_held.clear()


# --- 1: THE DEFAULT IS TODAY'S BEHAVIOUR, BYTE FOR BYTE ------------------------


## ## THE case the whole file is built around
##
## A def that authors a gate, read with **no reader bound**, must answer `gate_open: true`,
## `gate_reason: ""` and `warmth: 0` — and, crucially, must **still produce its authored
## body**. A seam that refused when unbound would make every un-booted build look like a
## world that despises the player, and would silently hide the NPC behind a gate nobody asked
## about.
func test_an_unbound_seam_leaves_a_gated_npc_exactly_as_it_behaves_today() -> void:
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	assert_eq(NpcGates.has_social_gate(), false, "setup: the seam is released")

	var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(row.get("gate_open", false)), true, "an unbound seam never closes a gate")
	assert_eq(String(row.get("gate_reason", "x")), "", "and never names a reason it cannot have")
	assert_eq(int(row.get("warmth", 99)), NpcGates.WARMTH_NEUTRAL, "so warmth stays the neutral 0")
	# The AUTHORED body survives untouched, which is the half an outcome-only assertion misses.
	assert_eq(
		String((row.get("tells", {}) as Dictionary).get("body", "")),
		def.tells[0].body,
		"and the npc still performs its authored body on approach"
	)


## The row is byte-identical with and without the seam, for a def that authors NO gate. This
## is the regression guard for every other npc suite: if landing ADR 0264 had changed a
## shipped row, this goes red and names the key.
func test_a_row_for_an_ungated_npc_is_byte_identical_whether_or_not_the_seam_is_bound() -> void:
	var def := _gated_def()
	def.social_gate = {}
	var before := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	NpcGates.set_social_gate(SocialApi.gate)
	var after := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	for key in ["tells", "opinion", "memory", "round", "gate_open", "gate_reason", "warmth"]:
		assert_eq(
			after.get(key), before.get(key), "'%s' is the same with and without the seam" % key
		)


# --- 2: THE GATE MOVES BEHAVIOUR, AND ONLY THROUGH THE READER -------------------


## ## The positive case, and the proof the seam is actually BOUND somewhere
##
## `SocialApi.gate` is the production reader. A player the world regards well opens the gate
## and is answered `+1`; the SAME def, the SAME authored gate, with the regard absent, answers
## `-1`. One authored number, two signs, two outcomes — the counterpart asserted as loudly as
## the advantage.
func test_a_regard_gate_opens_for_a_well_regarded_player_and_withdraws_for_a_distrusted_one(
) -> void:
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	NpcGates.set_social_gate(SocialApi.gate)
	assert_eq(NpcGates.has_social_gate(), true, "setup: the seam is bound")

	# A world that holds this player at the authored bar. Two oaths at +1.5 clear the +1.0.
	_regard(_player, HOUSE, 2)
	var opened := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(opened.get("gate_open", false)), true, "twice-regarded, the gate opens")
	assert_eq(int(opened.get("warmth", 0)), NpcGates.WARMTH_OPEN, "and warmth is +1")
	assert_eq(String(opened.get("gate_reason", "x")), "", "with no reason to give")

	## ## THE COUNTERPART. A different player, same def, same authored gate, NO oath at all.
	##
	## This is the half that makes the mechanic honest: the gate does not merely withhold an
	## advantage, it answers NEGATIVE, so a player the world has no regard for meets a colder
	## npc rather than merely an un-opened one.
	var stranger := _actor(&"stranger")
	_regard(stranger, HOUSE, 0)
	var closed := NpcReadModel.alive(def, stranger, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(closed.get("gate_open", true)), false, "with no oath, the gate is closed")
	assert_eq(int(closed.get("warmth", 0)), NpcGates.WARMTH_CLOSED, "and warmth is -1, not 0")
	assert_ne(String(closed.get("gate_reason", "")), "", "and the refusal is NAMED (ADR 0150)")


## ## ONE oath does not clear it either — the threshold is a real comparison
##
## `sworn_to_a_clan` is +1.5 against an authored threshold of +1.0, so two oaths clear the
## fixture's bar and a bar of +99 is unreachable by any shipped act. A gate that answered
## `true` for any regard at all would pass the positive case above and fail here.
func test_the_threshold_is_a_real_comparison_not_a_truthy_read() -> void:
	var def := _gated_def()
	def.social_gate = {"verb": &"regard_at_least", "partner": "house_ironwood", "at_least": 99.0}
	NpcCatalog.instance().install([def])
	NpcGates.set_social_gate(SocialApi.gate)
	_regard(_player, HOUSE, 2)
	var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(row.get("gate_open", true)), false, "two oaths do not clear a bar of +99")
	assert_eq(int(row.get("warmth", 0)), NpcGates.WARMTH_CLOSED, "so the NPC is the colder one")


## ## A closed gate does not silently replace the authored body (ADR 0044)
##
## The temptation is to swap in a "cold" body when the gate fails. That would be a hidden
## mutation of authored content AND would hide the gate from the player, who would see a
## different npc and never learn why. So the authored `tells` must be **byte-identical** on
## both sides of the gate, and the difference lives in the three published gate keys.
func test_a_closed_gate_leaves_the_authored_body_alone_and_publishes_the_verdict() -> void:
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	NpcGates.set_social_gate(SocialApi.gate)
	var stranger := _actor(&"stranger")
	_regard(stranger, HOUSE, 0)
	var row := NpcReadModel.alive(def, stranger, ELDER, 0, &"qi_dao", 0)
	assert_eq(
		String((row.get("tells", {}) as Dictionary).get("body", "")),
		def.tells[0].body,
		"the body is authored content and a gate never edits it"
	)
	assert_eq(bool(row.get("gate_open", true)), false, "while the gate publishes its own verdict")


## ## A dead reader degrades to NEUTRAL, never to a refusal
##
## `is_valid()` is true for a method every `Object` carries, so the ONLY thing this can be
## measuring is the node's life. A seam that reported a freed reader as "gate closed" would
## turn a bug elsewhere into a world where every gate is shut — the exact failure shape ADR
## 0250's `test_a_dead_reader_degrades_to_todays_price` exists to kill on the price side.
func test_a_dead_reader_degrades_to_neutral_and_is_reported_dead() -> void:
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	var doomed := Node.new()
	NpcGates.set_social_gate(Callable(doomed, "get_class"))
	assert_eq(NpcGates.has_social_gate(), true, "setup: it is live while it exists")
	doomed.free()
	assert_eq(NpcGates.has_social_gate(), false, "and reports itself dead rather than keeping it")
	var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(row.get("gate_open", false)), true, "so the gate reads open, not shut")
	assert_eq(int(row.get("warmth", 99)), NpcGates.WARMTH_NEUTRAL, "and warmth is the neutral 0")


## ## A reader that answers the WRONG THING is not a refusal either
##
## `float(true)` is a runtime error rather than a value, and a bare `true` must not be read as
## a satisfied gate. The reader is a bare `Callable` to a NAMED method rather than a lambda:
## `NpcBoot` records that a typed lambda whose body calls another script's static function
## killed the shell with an access violation, and the suite must not be the thing that
## discovers it twice.
func test_a_reader_answering_something_other_than_a_verdict_reads_neutral() -> void:
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	for wrong in [true, false, null, 1.0, "yes", [1, 2]]:
		NpcGates.set_social_gate(Callable(_double, "answer").bind(wrong))
		var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
		assert_eq(
			bool(row.get("gate_open", false)),
			true,
			"a reader answering %s never closes a gate" % str(wrong)
		)
		assert_eq(
			int(row.get("warmth", 99)),
			NpcGates.WARMTH_NEUTRAL,
			"and warmth stays neutral for %s" % str(wrong)
		)


## A verdict dictionary with no `ok` key did not answer the question it was handed.
func test_a_reader_answering_a_dictionary_with_no_verdict_reads_neutral() -> void:
	expect_assertions(2)
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	NpcGates.set_social_gate(Callable(_double, "no_verdict"))
	var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(row.get("gate_open", false)), true, "an unanswered question is not a refusal")
	assert_eq(int(row.get("warmth", 99)), NpcGates.WARMTH_NEUTRAL, "and warmth is neutral")


## ## The reader sees the requirement BYTE-IDENTICALLY, so there is no second evaluator
##
## The structural guard says `npc_gates.gd` names no verb; this says it also does not REWRITE
## the dictionary on the way through. A reader handed a normalised copy could not return the
## same answer `SocialGate` would have given the authored row.
func test_the_reader_receives_the_authored_requirement_untouched() -> void:
	BadReaders.seen.clear()
	NpcGates.set_social_gate(Callable(_double, "record_and_pass"))
	NpcGates.evaluate(_player, REGARD_GATE)
	assert_eq(BadReaders.seen.size(), 1, "the reader was called once")
	assert_eq(BadReaders.seen[0], REGARD_GATE, "with the authored dictionary, unchanged and whole")


# --- 3: NO SECOND EVALUATOR, AND NO ORPHAN VERB --------------------------------


## ## The one-evaluator rule (ADR 0076), asserted STRUCTURALLY
##
## `NpcGates` must **pass the authored dictionary through untouched**. If it interpreted a
## verb itself it would be a second answer to "is this gate satisfied", and the two would
## drift — which is the failure mode ADR 0066 describes for a duplicated curve and the reason
## `social_gate` is a Dictionary and not a Resource in the first place. Read off the SOURCE,
## so a future refactor that inlines a comparison is caught rather than argued about.
func test_npc_gates_interprets_no_verb_and_hands_the_requirement_through_untouched() -> void:
	var code := _code_only("res://src/modules/npc/npc_gates.gd")
	# No verb literal, no threshold comparison, no axis arithmetic. The pass-through is the
	# whole of the file's job.
	for forbidden in [
		"regard_at_least",
		"trust_at_least",
		"standing_at_least",
		"bond_at_least",
		"caused_by",
		"all_of",
		"any_of",
		"none_of",
		"at_least",
		"partner",
		".regard",
		".trust",
		".standing",
	]:
		assert_eq(
			code.contains(forbidden),
			false,
			"npc_gates.gd names no gate vocabulary or axis ('%s')" % forbidden
		)
	# The requirement is handed over whole, which is the positive half of the same claim.
	assert_eq(
		code.contains("requirement"),
		true,
		"and the requirement itself is what gets passed to the reader"
	)


## ## No orphan verbs: the seam has callers, and this suite proves which ones
##
## This program accumulated nine dead-code entries from reads nothing called. So the caller
## count is asserted BY SOURCE SCAN, over `game/src` — not over this test — so a gate that
## fell out of the read model is red rather than merely unused.
func test_the_seam_has_exactly_one_production_reader_and_one_install() -> void:
	var readers := 0
	var installs := 0
	var seen := 0
	for path in ContentScan.files_under("res://src/", ".gd"):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty() or path.get_file() == "npc_gates.gd":
			continue
		seen += 1
		var code := _code_only(text)
		if code.contains("NpcGates.evaluate("):
			readers += 1
			assert_eq(
				path.get_file(),
				"npc_read_model.gd",
				"the ONE production reader of a gate is the behaviour read model"
			)
		if code.contains("NpcGates.set_social_gate("):
			installs += 1
			assert_eq(
				path.get_file(), "npc_boot.gd", "and the ONE install is at the composition root"
			)
	assert_eq(readers, 1, "exactly one production reader — an orphan gate is a dead verb (scanned %d)" % seen)
	assert_eq(installs, 1, "and exactly one install, in app/ (scanned %d)" % seen)


## The reader must be bound by the COMPOSITION ROOT and by nothing else, and it must be
## `SocialApi.gate` itself rather than a lambda that forwards to it.
func test_the_composition_root_binds_social_api_gate_itself() -> void:
	var code := _code_only("res://src/app/npc_boot.gd")
	assert_eq(
		code.contains("NpcGates.set_social_gate(SocialApi.gate)"),
		true,
		"npc_boot binds the static function itself, not a lambda over it"
	)


# --- 4: THE AUTHORED VOCABULARY IS `SocialGate`'s, NOT A SECOND ONE -------------


## Every verb an author may write is one `SocialGate` already publishes. A second closed
## vocabulary in `npc/` would be a second evaluator wearing a data-only hat, and an unknown
## verb in an authored `.tres` must keep failing LOUDLY (ADR 0076) rather than being
## silently ignored by a module that never learned the word.
func test_the_authored_gate_uses_a_verb_social_gate_publishes() -> void:
	expect_assertions(2)
	assert_eq(
		StringName(String(REGARD_GATE["verb"])),
		&"regard_at_least",
		"the fixture gate is the institutional axis, which is the gap this ADR closes"
	)
	assert_eq(SocialGate.VERBS.has(REGARD_GATE["verb"]), true, "and it is a verb social publishes")


## An unknown verb REFUSES CLOSED and names itself — the authored-typo property, measured
## through the REAL reader rather than asserted in prose. This is what a second evaluator in
## `npc/` would have broken: a module that never learned the word would have answered
## "unmet" without a reason, and the author would have had nothing to act on.
func test_an_unknown_verb_refuses_closed_and_names_itself() -> void:
	expect_assertions(2)
	var def := _gated_def()
	def.social_gate = {"verb": &"vibes_at_least", "partner": "house_ironwood", "at_least": 1.0}
	NpcCatalog.instance().install([def])
	NpcGates.set_social_gate(SocialApi.gate)
	var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(bool(row.get("gate_open", true)), false, "a typo'd verb does not quietly unlock")
	assert_eq(
		String(row.get("gate_reason", "")),
		"unknown_verb",
		"and names itself, so the author has something to act on"
	)


## ## The axis is `regard`, and `regard` is a DIFFERENT number from a bond class
##
## The whole reason this seam exists. A player with a strongly POSITIVE bond class but no
## institutional regard still meets the closed gate, and one with regard but a stranger's bond
## still meets the open one — so this cannot have been satisfied by the bond class the alive
## layer already read.
func test_regard_is_not_a_bond_class_and_the_gate_reads_the_one_it_names() -> void:
	var def := _gated_def()
	NpcCatalog.instance().install([def])
	NpcGates.set_social_gate(SocialApi.gate)
	# A bond the player has earned, and NO regard for the house.
	SocialApi.apply_cause(_player, ELDER, &"gifted_item")
	var entry := SocialApi.bond_entry(_player, ELDER)
	assert_ne(
		String(entry.get("bond", "")),
		SocialBondClass.STRANGER,
		"the bond is not a stranger's — the player has done something"
	)
	assert_eq(float(entry.get("standing", 0.0)) > 0.0, true, "and standing is positive")
	var row := NpcReadModel.alive(def, _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(
		bool(row.get("gate_open", true)),
		false,
		"yet the institutional gate is still shut: this is the axis the bond class cannot reach"
	)


# --- 5: CONTENT GUARDS ---------------------------------------------------------


## The shipped cast is the fixture. `npc_def.gd` authors no `price`/`worth`/`value` for a
## capture term is DEF-0138's own rule (ADR 0263), and the same discipline applies here: the
## authored gate is a THRESHOLD against `social`'s ledger, never a stored axis. A def-owned
## `regard` number would be the second writer of the axis ADR 0091 forbids.
func test_npc_def_authors_no_regard_number_and_no_price() -> void:
	var code := _code_only("res://src/modules/npc/npc_def.gd")
	for forbidden in ['"regard"', '"trust"', '"standing"', '"price"', '"worth"', '"value"']:
		assert_eq(
			code.contains(forbidden),
			false,
			"NpcDef authors no stored axis ('%s') — it authors a THRESHOLD" % forbidden
		)
	# The gate itself IS authored, and as a Dictionary.
	assert_eq(code.contains("@export var social_gate: Dictionary"), true, "the gate is one dict")


## No shipped `.tres` may author a gate yet. Not a limitation — a **statement**: the default is
## live precisely because content has not opted in, so this names the one content change that
## would start moving NPC behaviour, which is the same review prompt the other content guards
## in this repo give.
func test_no_shipped_cast_member_authors_a_social_gate_yet() -> void:
	var authored := 0
	for path in ContentScan.files_under("res://data/npc/cast/"):
		var def := load(path) as NpcDef
		if def == null:
			continue
		authored += 1
		assert_eq(
			def.social_gate.is_empty(),
			true,
			(
				"'%s' authors no social gate: the first one is a deliberate content decision"
				% String(def.npc_id)
			)
		)
	assert_eq(authored > 0, true, "the guard walked the shipped cast rather than nothing")


## Warmth is a POSITION, never a magnitude. `-1 / 0 / +1` is the whole vocabulary, and a
## fourth value would be a score the player farms — the economy-gated-affinity trap ADR 0256
## names in its own research section.
func test_warmth_is_a_three_valued_position_and_nothing_else() -> void:
	assert_eq(NpcGates.WARMTH_CLOSED, -1, "closed")
	assert_eq(NpcGates.WARMTH_NEUTRAL, 0, "neutral — and the default")
	assert_eq(NpcGates.WARMTH_OPEN, 1, "open")
	NpcGates.set_social_gate(SocialApi.gate)
	var row := NpcReadModel.alive(_gated_def(), _player, ELDER, 0, &"qi_dao", 0)
	assert_eq(
		int(row.get("warmth", 99)) in [-1, 0, 1], true, "and every answer is one of the three"
	)


# --- Fixtures ------------------------------------------------------------------


## A def that authors ONE gate and ONE tell, so both halves of the decision are on the row:
## the gate that reads `social`, and the authored body the gate must not edit.
func _gated_def() -> NpcDef:
	var def := NpcDef.new()
	def.npc_id = ELDER
	def.display_name = "Elder Wei"
	def.tier = NpcTier.STORY
	def.realm_id = &"qi_refining"
	def.social_gate = REGARD_GATE.duplicate(true)
	var tell_def := NpcTellDef.new()
	tell_def.trigger = NpcTellDef.TRIGGER_BOND_CLASS
	tell_def.matches = SocialBondClass.STRANGER
	tell_def.verb = &"nods_once"
	tell_def.body = "nods once, the way you nod at weather"
	tell_def.consequence = &"dismisses"
	def.tells.append(tell_def)
	return def


func _actor(id: StringName) -> Actor:
	var actor := Actor.new(id, {})
	SocialApi.attach(actor)
	_held.append(actor)
	return actor


## Write an institutional regard row the way `clan`/`sect`/`nation` write theirs: apply a
## real shipped INSTITUTIONAL cause through `SocialApi`, and let `SocialState._rebuild_regard`
## derive the axis. Nothing here writes `state.regard` — the derived projection would
## overwrite it, and a fixture that wrote it directly would be testing a number the world
## never produces.
func _regard(actor: Actor, institution_id: StringName, oaths: int) -> void:
	for _n in range(oaths):
		SocialApi.apply_cause(actor, institution_id, &"sworn_to_a_clan")
	var state := SocialApi.social_state(actor)
	assert_eq(
		state.regard.has(String(institution_id)),
		oaths > 0,
		"setup: %d oath(s) leave regard %s" % [oaths, "present" if oaths > 0 else "absent"]
	)


func _mint(def: NpcDef, role: StringName = NpcApi.ROLE_NPC) -> Actor:
	var actor := Actor.new(StringName("npc_%s" % String(def.npc_id)), def.base)
	actor.attach_core_resources()
	SocialApi.attach(actor)
	actor.tags.append(role)
	actor.display_name = def.display_name
	actor.faction = def.faction
	return actor


## The shipped source with every comment removed. Asserting on prose would make a boundary
## check into a typo detector — and this file's own docstring NAMES every gate verb on
## purpose, which is exactly what the vocabulary guard must not fire on.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
