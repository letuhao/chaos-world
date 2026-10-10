extends TestCase

## Shared fixture for `test_npc_alive.gd`. NOT a suite itself: the runner discovers
## `test_*.gd` only (`run_tests.gd::_find_tests`), so this file is never executed alone.
##
## Split out of the suite purely for size -- gdlint's `max-file-lines` is 1000. Nothing
## was rewritten, no assertion changed and no case renamed: every constant, the five
## pieces of state `setup` fills and each helper now live here, which the suite `extends`.
## A test file can only move HELPERS, which is why the moved bodies are exactly the ones
## no `test_` function names.
##
## `setup` / `teardown` MUST live here rather than in the suite: `NpcCatalog`,
## `NpcRegistry`, `NpcAliveness` and the minter seam are PROCESS-WIDE and the runner
## shares one process across every suite, calling `teardown` after EVERY test -- so a
## registry installed by one case and cleared by another outlives the suite and is
## inherited by everything after it.

const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"
const DRIFTER := &"drifter"
const GATE_KEEPER := &"gate_keeper_bo"

## The shipped cast, read off disk. **The shipped `.tres` is the fixture**: this suite
## asserts on the content a player actually meets, which is what makes a mutation to the
## authored data red instead of invisible.
const CAST_DIR := "res://data/npc/cast/"

## One authored slot of Elder Wei's day (`round_slot_ratio_periods` on the `.tres`).
const SLOT_PERIODS := 6

## A cause the shipped catalog ships but no def authors prose for — the "an act happened
## and nobody wrote a sentence for it" case.
const UNVOICED_CAUSE := &"slandered"

## An un-authored place. Composing there must fall back to the CONSTANTS rather than
## inventing a belief, which is what keeps the composer from being a dice roll.
const VOICELESS := &"a_road_with_no_voice"

## How many times a read is POLLED when the claim is about its cost. Named rather than
## written into three `range()` calls, because a per-pass cost multiplied by an unnamed
## repetition is a number nobody can check by eye — which is how the gate assertion below
## came to compare eight passes against one pass's cost and answer 8 against 1.
const POLL_PASSES := 8

## The spellings of "somebody is here" that would gate an advance, named rather than
## written inline so the guard and its docstring cannot drift apart.
const GATED_ADVANCE_PATTERNS: Array[String] = [
	"someone_is_here",
	"anyone_is_here",
	"if observed",
	"if is_observed",
	"player_present",
	"if anyone_present",
	"if is_present",
]

## The cap is a REPORTED surplus, never a silent swallow. A panel is not a diary; a save is
## not a log — and "N of M" is the honest shape here in the way `RowBudget` uses it,
## because a rendered line can be asked for again.
## ## The surplus is made of REAL cause ids, not invented ones
##
## This used to apply `cause_00 … cause_05` and expect a bond. `SocialApi.apply_cause`
## refuses an id the catalog does not ship (`unknown_cause`, `api.gd:120`), so none of the
## six was ever written and the read answered its honest empty. **Six REAL shipped causes**
## is the same fixture with the property under test intact: what this pins is the CAP and
## the REPORTED surplus, not the ability to invent a cause, and inventing one was testing
## `social`'s refusal instead.
##
## Each is applied at `scale` high enough to count; the cap counts CAUSES, not weight.
const OVER_CAP_CAUSES: Array[StringName] = [
	&"gifted_item",
	&"helped_in_combat",
	&"spared_in_combat",
	&"taught_technique",
	&"protected_from_death",
	&"slandered",
]

var _player: Actor
var _elder: NpcDef
var _minor: NpcDef
var _transient: NpcDef
## Bound once because `Callable` on a static is the `is_connected`-safe form the rest of
## this repo uses, and holding one object is one fewer thing to re-derive per assertion.
var _bound: Callable = Callable()


func setup() -> void:
	# A FLOOR, not an exact count: one assertion every test in this suite must clear, so a
	# body that died on its first line cannot be reported as a pass (framework.gd:135).
	#
	# **One, not three.** The floor is a floor, so declaring 3 here charged a failure to
	# every test in the file that legitimately makes one or two assertions — thirteen of
	# them, each reported as `it did not finish its body` when it in fact finished. That
	# sentence is only true when the body DIED, so a floor high enough to flag short
	# bodies flags complete ones too and the signal stops meaning anything. Tests whose
	# bodies make several assertions declare their own `expect_assertions(n)`, which is
	# where the mid-body-abort detection actually lives.
	expect_assertions(1)
	SocialCauseCatalog.instance().install_defaults()
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()
	NpcAliveness.reset()
	for def in _shipped_cast():
		NpcCatalog.instance().install([def])
	_elder = NpcCatalog.instance().definition(ELDER)
	_minor = NpcCatalog.instance().definition(GATE_KEEPER)
	_transient = NpcCatalog.instance().definition(DRIFTER)
	_player = Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(_player)
	# The injected constructor, `test_npc_tier.gd`'s lambda shape verbatim: every verb on
	# the factory is static and binding one through a class object is not a Callable.
	NpcApi.set_minter(_mint)
	NpcApi.attach(_player)
	_bound = Callable(NpcAliveness, "round_syncs")


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcAliveness.reset()


## The `manner` of the one row in `alive` carrying `tier`, or `""` when the room has none.
## A helper rather than an index because which row the minor is depends on registry order,
## and a test that hardcodes an index breaks the moment a peer stocks one more npc.
func _manner_of_tier(rows: Array, tier: StringName) -> String:
	for row in rows:
		var cast := row as Dictionary
		if String(cast.get("tier", "")) == String(tier):
			return String(cast.get("manner", ""))
	return ""


## How many composes ONE `presence_here` pass costs for this room, read from the live
## registry rather than hardcoded: the number of rows whose TIER composes. Computed through
## `NpcTier.COMPOSED` — the same named set the gate reads — so a change to what composes
## moves this helper and the gate together instead of letting the two drift. `UNTRACKED` is
## the wrong set to count and saying so is the point: a `transient` is untracked and
## composes nothing, which is why the two sets are not interchangeable.
func _presence_here_composable_rows() -> int:
	var composable := 0
	for key in NpcRegistry.instance().present_ids():
		var def := NpcCatalog.instance().definition(String(String(key).get_slice("#", 0)))
		if def != null and NpcTier.COMPOSED.has(def.normalized_tier()):
			composable += 1
	return composable


## The dead pattern in the spellings an author might reach for, matched as CODE — a `##`
## comment naming the hazard is exactly what this must NOT fire on, or the guard would go
## red the first time somebody documented it.
func _assert_no_gated_advance(path: String, text: String) -> void:
	var code := _code_only(text)
	for gate in GATED_ADVANCE_PATTERNS:
		assert_eq(
			code.contains(gate),
			false,
			"%s has no `%s` gate on an advance" % [path.get_file(), gate]
		)


# --- Fixtures --------------------------------------------------------------------


## Stock a room through the PRODUCTION verb, so a test cannot pass against a cast the game
## never stands up.
func _room(def_ids: Array[StringName]) -> void:
	var spawned := NpcApi.populate(def_ids, &"npc", true, &"qi_dao")
	assert_ne(spawned.size(), 0, "the fixture really did stock the room")


## The `alive` half of `presence_here`, read through the PRODUCTION verb rather than
## through a helper this suite built — `NpcApi._presence_here_alive` is the interior of
## that read and is private because the registry's `drifter#3` instance key is its own
## spelling. The public shape is the `alive` KEY, so that is what the fixture calls.
func _alive_rows(location_id: StringName) -> Array:
	return NpcApi.presence_here(location_id).get("alive", []) as Array


func _alive_row(npc_id: StringName, location_id: StringName, ordinal: int) -> Dictionary:
	return NpcReadModel.alive(
		NpcCatalog.instance().definition(npc_id), _player, npc_id, 0, location_id, ordinal
	)


func _cause_ids(memory: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row in memory.get("rows", []) as Array:
		out.append(String((row as Dictionary).get("cause_id", "")))
	return out


func _prose_for(memory: Dictionary, cause_id: String) -> String:
	for row in memory.get("rows", []) as Array:
		if String((row as Dictionary).get("cause_id", "")) == cause_id:
			return String((row as Dictionary).get("prose", ""))
	return ""


## The module's CODE with its comments dropped. A docstring that NAMES the deadlock
## hazard is exactly what this guard must not fire on, so the comments have to go before
## the text is matched.
func _code_only(text: String) -> String:
	var out: String = ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		out += line + "\n"
	return out


func _shipped_cast() -> Array[NpcDef]:
	var out: Array[NpcDef] = []
	for path in ContentScan.files_under(CAST_DIR):
		var def := load(path) as NpcDef
		if def != null:
			out.append(def)
	return out


func _def(npc_id: StringName, tier: StringName, stages: Array) -> NpcDef:
	var def := NpcDef.new()
	def.npc_id = npc_id
	def.display_name = String(npc_id)
	def.tier = tier
	def.realm_id = &"qi_refining"
	for stage in stages:
		def.stages.append(stage)
	return def


func _recall(cause_id: String) -> NpcRecallDef:
	var recall_def := NpcRecallDef.new()
	recall_def.cause_id = StringName(cause_id)
	recall_def.prose = "a thing that happened"
	return recall_def


func _opinion_def(subject: StringName, stance: StringName, prose: String) -> NpcOpinionDef:
	var opinion := NpcOpinionDef.new()
	opinion.subject_id = subject
	opinion.stance = stance
	opinion.prose = prose
	return opinion


func _tell(matches: StringName, trigger: StringName, priority: int) -> NpcTellDef:
	var tell_def := NpcTellDef.new()
	tell_def.trigger = trigger
	tell_def.matches = matches
	tell_def.priority = priority
	tell_def.verb = &"steps_back"
	tell_def.body = "steps back"
	tell_def.consequence = &"refuses"
	return tell_def


## The injected constructor. `test_npc_tier.gd`'s shape verbatim, and for its reason: every
## verb on the factory is static and binding one through a class object is not a Callable.
func _mint(def: NpcDef, role: StringName = NpcApi.ROLE_NPC) -> Actor:
	var actor := Actor.new(StringName("npc_%s" % String(def.npc_id)), def.base)
	actor.attach_core_resources()
	SocialApi.attach(actor)
	actor.tags.append(role)
	actor.display_name = def.display_name
	actor.faction = def.faction
	return actor
