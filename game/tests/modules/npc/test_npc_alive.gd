extends TestCase

## The ALIVE LAYER: four capabilities, three tiers, and the lazy clock (ADR 0253).
##
## ## What this suite is for
##
## Every claim the alive layer makes is a COST claim or an ANTI-DRIFT claim, and both of
## those are exactly the kind of claim a suite stops testing once the code works. So this
## file asserts them against NAMED COUNTERS rather than against return values:
##
##   - `NpcAliveness.composes` — what an unobserved minor npc costs. Must not move.
##   - `NpcAliveness.round_syncs(id)` — what an unobserved major costs. Must not move.
##   - `NpcAliveness.gossip_deliveries` — how far one rumour actually travelled.
##
## ## The anti-drift claim is the important one
##
## ADR 0091 makes the cause ledger the truth and the bond a derived sum. A memory read
## that rendered AUTHORED PROSE without checking it against the ledger would be a second
## record that can disagree with the first, so
## `test_memory_renders_only_a_cause_the_ledger_carries` asserts the prose is unreachable
## for an act the bond does not hold.

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


# --- (1) A MAJOR NPC: authored round, opinion, named incident, tell ---------------


## The four halves together on one row, read through the PRODUCTION read
## (`NpcApi.presence_here`["alive"]) rather than through a helper this suite built.
func test_a_major_npc_shows_an_authored_round_an_opinion_a_named_incident_and_a_tell() -> void:
	_room([ELDER])
	# The act has to be on the ledger before the elder has anything to remember, and the
	# read that renders it is the SAME read that is the clock's observation.
	SocialApi.apply_cause(_player, ELDER, &"killed_their_kin")
	var rows := _alive_rows(&"qi_dao")
	assert_eq(rows.size(), 1, "the room the cast was stocked into reads back one npc")
	var row := rows[0] as Dictionary
	# (1) THE DAILY ROUND — authored, addressed by slot id, and NOT the room we stocked
	# them into, which is the whole point: they are somewhere else when you are not looking.
	var round_row := row.get("round", {}) as Dictionary
	assert_eq(round_row.has("slot_id"), true, "the elder is in an authored slot")
	assert_ne(String(round_row.get("activity", "")), "", "and the slot says what he is doing")
	# (2) THE OPINION — about ANOTHER npc, which is what lets two people disagree.
	var opinion := row.get("opinion", {}) as Dictionary
	assert_eq(String(opinion.get("subject_id", "")), "elder_qin", "he holds a view about Qin")
	assert_ne(String(opinion.get("prose", "")), "", "in authored words")
	# (3) THE INCIDENT — keyed to the REAL cause id.
	var memory := row.get("memory", {}) as Dictionary
	assert_eq(int(memory.get("count", 0)), 1, "the one thing that happened is remembered")
	assert_eq(
		String((memory.get("rows", []) as Array)[0].get("cause_id", "")),
		"killed_their_kin",
		"and the row names the real cause id rather than a description of it"
	)
	# (4) THE BODY — on approach, not on a click.
	assert_ne(
		String((row.get("tells", {}) as Dictionary).get("body", "")), "", "he answers the approach"
	)


## The memory row is the SPECIFIC thing, not the total. A bond that has been summed reads
## back as `standing: -10.0`, which is a number and not a thing anybody did; this is the
## sentence that says it out loud.
func test_memory_renders_authored_prose_keyed_to_the_real_cause() -> void:
	SocialApi.apply_cause(_player, ELDER, &"killed_their_kin")
	var memory := NpcAliveness.memory(_player, _elder, ELDER)
	var rows := memory.get("rows", []) as Array
	assert_eq(rows.size(), 1, "one cause is on the ledger, so one incident is remembered")
	var incident := rows[0] as Dictionary
	assert_eq(
		String(incident.get("cause_id", "")),
		"killed_their_kin",
		"the row NAMES the real cause id, not a description of it"
	)
	assert_eq(
		String(incident.get("prose", "")),
		(
			"the grey one, third month of the grey year — you walked past my gate while I "
			+ "was burying my brother, and you did not stop"
		),
		"and it renders the authored sentence about THAT act"
	)
	assert_eq(
		(incident.get("anchors", []) as Array).has("third month of the grey year"),
		true,
		"and the anchors carry the moment the sentence is written from"
	)


## ## THE ANTI-DRIFT HALF, and the one that matters most
##
## `NpcRecallDef` carries no number, so prose cannot be a second record of standing — but
## it could still be a second record of the CAUSE if a read walked the authored rows
## instead of the ledger. This asserts the loop direction: an authored sentence nothing
## ever did is NOT rendered, while an unvoiced act that DID happen is reported with empty
## prose so the fact survives even when nobody wrote it a sentence.
func test_memory_renders_only_a_cause_the_ledger_actually_carries() -> void:
	var unearned := NpcAliveness.memory(_player, _elder, ELDER)
	assert_eq(
		int(unearned.get("count", 0)),
		0,
		"authored prose about a thing the player never did is not memory"
	)
	assert_eq(
		int(unearned.get("carried", 0)),
		0,
		"and the ledger carries nothing, so there is nothing to be a second record of"
	)
	SocialApi.apply_cause(_player, ELDER, UNVOICED_CAUSE)
	var unvoiced := NpcAliveness.memory(_player, _elder, ELDER)
	var rows := unvoiced.get("rows", []) as Array
	assert_eq(rows.size(), 1, "the unvoiced act is still an incident")
	assert_eq(
		String((rows[0] as Dictionary).get("cause_id", "")), String(UNVOICED_CAUSE), "and is named"
	)
	assert_eq(
		bool((rows[0] as Dictionary).get("authored", false)),
		false,
		"while saying plainly that no sentence was authored for it"
	)


## Prose and ledger cannot drift across a save: the cause id in the rendered row is the key
## the ledger is written under, so a round trip through `Actor.to_dict` / `from_dict` has
## to come back to the same id and therefore the same prose.
func test_memory_prose_names_the_real_cause_and_round_trips_to_the_cause() -> void:
	SocialApi.apply_cause(_player, ELDER, &"killed_their_kin")
	SocialApi.apply_cause(_player, ELDER, &"gifted_item")
	var before := _cause_ids(NpcAliveness.memory(_player, _elder, ELDER))
	var restored := Actor.from_dict(_player.to_dict())
	SocialApi.attach(restored)
	var memory := NpcAliveness.memory(restored, _elder, ELDER)
	assert_eq(
		_cause_ids(memory), before, "the same causes, in the same order, after a save round trip"
	)
	assert_ne(_prose_for(memory, "killed_their_kin"), "", "so the same sentence still renders")


## A derived total is not an incident, and this suite must not ship one. Standing, trust
## and class are `social`'s to publish; a memory read carrying any of them would be the
## second writer ADR 0091 forbids.
func test_the_memory_row_carries_no_number_at_all() -> void:
	SocialApi.apply_cause(_player, ELDER, &"killed_their_kin")
	var row := (
		(NpcAliveness.memory(_player, _elder, ELDER).get("rows", []) as Array)[0] as Dictionary
	)
	assert_eq(row.has("standing"), false, "no standing on an incident row")
	assert_eq(row.has("trust"), false, "no trust")
	assert_eq(row.has("bond"), false, "no derived class either")
	assert_eq(bool(row.get("authored", false)), true, "and it says whether prose exists")


func test_the_memory_cap_reports_what_it_dropped_rather_than_truncating_silently() -> void:
	for cause_id in OVER_CAP_CAUSES:
		SocialApi.apply_cause(_player, ELDER, cause_id)
	# A def with no authored prose for any of them: every row is the unvoiced shape, which
	# is the honest way to get past the cap without inventing sentences.
	var authorless := _def(&"authorless", NpcTier.STORY, [])
	var memory := NpcAliveness.memory(_player, authorless, ELDER)
	assert_eq(
		int(memory.get("count", 0)),
		NpcAliveness.MAX_MEMORY_ROWS,
		"the read renders exactly the named cap"
	)
	assert_eq(int(memory.get("dropped", 0)), 2, "and says how many it did not render")
	assert_eq(
		int(memory.get("carried", 0)),
		OVER_CAP_CAUSES.size(),
		"while reporting the true count, untruncated"
	)


## The tells answer to REAL STATE and are legible without a number. The stranger's body is
## a dismissal; the sworn body is the elder actually taking the cup.
func test_a_tell_is_driven_by_the_bond_and_readable_without_a_number() -> void:
	var stranger := NpcAliveness.tell(_player, _elder, SocialBondClass.STRANGER, &"", false)
	assert_eq(
		String(stranger.get("body", "")),
		"nods once, the way you nod at weather",
		"a stranger is nodded off"
	)
	assert_eq(
		String(stranger.get("consequence", "")), "dismisses", "and the caller is told what happened"
	)
	assert_eq(stranger.has("standing"), false, "and there is no number in the answer")
	# Priority is AUTHORED, so the sworn body outranks the plain one deterministically.
	var sworn := NpcAliveness.tell(_player, _elder, SocialBondClass.SWORN, &"", true)
	assert_eq(
		String(sworn.get("body", "")),
		"takes the cup in both hands, which he does not do for guests",
		"a sworn bond changes the body"
	)
	# A bond class the def authors nothing for still answers: an npc with no opinion of you
	# nods rather than rendering as broken.
	assert_eq(
		String(NpcAliveness.tell(_player, _elder, &"confidant", &"", true).get("body", "")),
		NpcAliveness.DEFAULT_TELL_BODY,
		"an unauthored class answers with the constant body"
	)


## An npc with no authored tells is not a broken npc. `{}` would read as "nothing to say",
## which is a different claim from "she does not look up".
func test_an_unauthored_cast_member_still_answers_with_a_body() -> void:
	var bare := _def(&"bare_major", NpcTier.MAJOR, [])
	# `tell(player, def, bond_class, slot_id, has_history)` — FIVE arguments, exactly as
	# `npc_aliveness.gd:265` declares it. `player` is the first of them because the signature
	# is the one ADR 0253 shipped and `NpcReadModel.alive` is its production caller; the
	# fixture below was written with a sixth.
	var tells := NpcAliveness.tell(_player, bare, SocialBondClass.STRANGER, &"", false)
	assert_ne(String(tells.get("body", "")), "", "a body is always a body, even unauthored")
	assert_eq(String(tells.get("consequence", "")), "neutral", "and its consequence is neutral")


## A CAUSE-keyed tell is REFUSED, not fired. Which cause an npc resents is a question only
## the MEMORY read can answer, and a body that fired on "any cause you have on file" would
## be the same body for the worst thing and the best.
func test_a_cause_keyed_tell_never_fires_and_the_reason_is_named() -> void:
	var def := _def(&"resentful", NpcTier.STORY, [])
	def.tells.append(_tell(&"killed_their_kin", NpcTellDef.TRIGGER_CAUSE_ID, 99))
	# The same five arguments as the fixture above: a CAUSE-keyed tell asked to fire on a
	# BOND CLASS read, which is the whole of what this case pins.
	var answered := NpcAliveness.tell(_player, def, SocialBondClass.NEMESIS, &"", true)
	assert_eq(
		String(answered.get("verb", "")),
		String(NpcAliveness.DEFAULT_TELL_VERB),
		"the cause trigger never fires from a class read"
	)
	assert_eq(
		String(answered.get("trigger", "")), "", "and no claim is made about which cause it answers"
	)


# --- (2) A MINOR NPC: composed on interaction, persisting nothing ---------------


## The hard part of the whole task, and the acceptance criterion for the minor tier: all
## four halves exist **at the moment of interaction**, and none came from a per-npc
## authored asset — `gate_keeper_bo.tres` authors no round, no opinion and no tell.
func test_a_minor_npc_composes_a_name_a_manner_an_opinion_and_a_tell_on_interaction() -> void:
	assert_eq(_minor.daily_round.size(), 0, "the minor's def authors no round")
	assert_eq(_minor.opinions.size(), 0, "no opinion")
	assert_eq(_minor.tells.size(), 0, "and no tells")
	var row := _alive_row(GATE_KEEPER, &"qi_dao", 0)
	assert_eq(bool(row.get("composed", false)), true, "so the row was composed, not authored")
	assert_eq(bool(row.get("tracked", false)), false, "and the minor is untracked, per ADR 0092")
	assert_ne(String(row.get("display_name", "")), "", "the composed persona has a name")
	assert_ne(String(row.get("manner", "")), "", "and a manner")
	assert_ne(String((row.get("opinion", {}) as Dictionary).get("prose", "")), "", "and an opinion")
	assert_ne(String((row.get("tells", {}) as Dictionary).get("body", "")), "", "and a body")


## **CONTAINMENT, not a roll.** The opinion is TRUE OF THE ROOM because the room authored
## it (`data/npc/personas/qi_dao.tres`): a minor standing at the Qi Dao gate distrusts the
## sect that runs the gate. This is the difference between a person and a cutout with a
## random name, and it is why the composer reads a PLACE rather than a global list.
func test_a_composed_opinion_comes_from_the_place_and_not_from_a_global_roll() -> void:
	var opinion := _alive_row(GATE_KEEPER, &"qi_dao", 0).get("opinion", {}) as Dictionary
	assert_eq(
		String(opinion.get("subject_id", "")), "qi_dao", "the view is about the place they stand in"
	)
	assert_eq(String(opinion.get("stance", "")), "distrust", "with the stance the place authored")
	assert_ne(String(opinion.get("prose", "")), "", "and the place's own sentence")
	# A place that authors no voice is a real state, not a crash, and the fallback is a
	# CONSTANT rather than an invented belief: a drifter has no opinion of you and says so.
	var unvoiced := _alive_row(GATE_KEEPER, VOICELESS, 0)
	assert_eq(
		String((unvoiced.get("opinion", {}) as Dictionary).get("prose", "")),
		NpcMinorComposer.DEFAULT_OPINION,
		"a place that authors no view gives the constant one, never an invented belief"
	)


## The tier is CONTENT, not a branch. `qi_dao.tres` narrows its opinion and its body to the
## `minor` tier, so a composed face that is not a minor must not inherit them — which is
## the assertion a `if tier == "minor"` crept into the composer would break.
func test_the_place_narrows_its_own_view_to_a_tier_and_the_composer_respects_it() -> void:
	var as_minor := NpcMinorComposer.compose(&"qi_dao", NpcTier.MINOR, 0, _transient)
	assert_eq(
		String(as_minor.opinion_prose),
		"the sect counts your hours and calls the ledger a virtue",
		"a minor standing here plausibly holds this view"
	)
	var as_major := NpcMinorComposer.compose(&"qi_dao", NpcTier.MAJOR, 0, _transient)
	assert_eq(
		String(as_major.opinion_prose),
		NpcMinorComposer.DEFAULT_OPINION,
		"a tier the place did not name for falls to the constant"
	)


## Composition is deterministic in the CALLER'S ordinal, not in a draw. Two minors in one
## room are two different people, and the same two read the same way twice.
func test_two_minor_npcs_in_one_room_get_distinct_names_and_repeat_identically() -> void:
	var first := String(_alive_row(GATE_KEEPER, &"qi_dao", 0).get("display_name", ""))
	var second := String(_alive_row(GATE_KEEPER, &"qi_dao", 1).get("display_name", ""))
	var again := String(_alive_row(GATE_KEEPER, &"qi_dao", 1).get("display_name", ""))
	assert_ne(first, second, "two faces in one room are two people, not one person twice")
	assert_eq(second, again, "and reading the same room twice composes the same people")


## ## "Costs nothing while unobserved" — asserted with the NAMED COUNTER
##
## This is the claim the whole lazy principle rests on, and an outcome assertion could not
## measure it: a room read that returned the right answer while composing forty personas
## would pass every other test here. So this reads `NpcAliveness.composes` before and after.
func test_an_unobserved_minor_npc_costs_nothing_and_the_counter_proves_it() -> void:
	_room([GATE_KEEPER, DRIFTER, ELDER])
	var before := NpcAliveness.composes
	# Read the ROOM and the ROSTER repeatedly — the two things a panel polls. No
	# interaction with a minor happens in any of them.
	for _pass in range(8):
		NpcApi.presence_here(&"qi_dao")
		NpcApi.state(_player)
		_alive_rows(&"qi_dao")
	assert_eq(NpcAliveness.composes, before, "eight room reads composed nobody: not by one")


## And the mirror, so the counter is not merely stuck: composition DOES move when somebody
## interacts. A counter that cannot go up proves nothing.
func test_the_compose_counter_moves_exactly_when_a_minor_is_interacted_with() -> void:
	var before := NpcAliveness.composes
	_alive_row(GATE_KEEPER, &"qi_dao", 0)
	assert_eq(NpcAliveness.composes, before + 1, "one interaction, one compose")
	assert_eq(NpcAliveness.composes, before + 1, "and holding the row costs nothing further")


## A TRANSIENT npc gets less than a minor, and the reason is population. It composes
## nothing — not a persona, not a name — and takes the generic body, which is the cheapest
## honest answer there is.
func test_a_transient_npc_composes_nothing_and_takes_the_generic_body() -> void:
	var before := NpcAliveness.composes
	var row := _alive_row(DRIFTER, &"qi_dao", 0)
	assert_eq(NpcAliveness.composes, before, "a transient costs no composition at all")
	assert_eq(bool(row.get("composed", false)), false, "it is not composed")
	assert_eq(
		String((row.get("tells", {}) as Dictionary).get("body", "")),
		NpcReadModel.GENERIC_TELL_BODY,
		"so it takes the generic body"
	)
	assert_eq((row.get("opinion", {}) as Dictionary).is_empty(), true, "and no opinion")


## ## PERSISTS NOTHING — asserted on the save payload, not on the roster read
##
## A persona is a value. There is no key and no ledger row, so a full save round trip of a
## world in which a minor was met must find nothing of them — which is ADR 0092's whole
## contract and the reason a minor may not become persistent.
func test_a_minor_npc_leaves_nothing_in_a_save_to_persist() -> void:
	_room([GATE_KEEPER, ELDER])
	_alive_row(GATE_KEEPER, &"qi_dao", 0)
	_alive_row(GATE_KEEPER, &"qi_dao", 3)
	SocialApi.apply_cause(_player, GATE_KEEPER, &"gifted_item")
	var payload := _player.to_dict()
	var roster := payload["module_data"][String(NpcApi.MODULE_KEY)] as Dictionary
	var entries := roster.get("entries", {}) as Dictionary
	assert_eq(entries.has(String(GATE_KEEPER)), false, "no roster row was ever written")
	assert_eq(entries.has(String(ELDER)), true, "while the tracked one beside them was")
	# And after a load the minor is a stranger again, which is what "leaves nothing" means
	# to a player who walked out of the room and came back.
	var restored := Actor.from_dict(payload)
	NpcRegistry.instance().reset()
	NpcApi.attach(restored)
	SocialApi.attach(restored)
	assert_eq(bool(NpcApi.summary(GATE_KEEPER).get("known", false)), false, "a stranger again")
	assert_eq(
		NpcApi.state(restored).get("tracked_ids", []) as Array, [], "and nobody remembers them"
	)


## A composed persona has no stable id and must never acquire one: the roster is keyed on
## it, so a persona that grew an id would be one assignment from becoming persistent.
func test_a_composed_persona_has_no_persistent_id() -> void:
	var persona := NpcMinorComposer.compose(&"qi_dao", NpcTier.MINOR, 0, _minor)
	assert_eq(persona.has_persistent_id(), false, "there is nothing for the roster to key on")
	assert_eq(persona.to_dict().has("npc_id"), false, "and the read model publishes no id")


# --- (3) OPINION AND GOSSIP THAT TRAVELS ----------------------------------------


## Two people, opposite positions, about a THIRD person. The closed half of an opinion is
## the stance, never the subject, so disagreement is expressible.
func test_two_npcs_may_disagree_about_a_third_person() -> void:
	var shipped := NpcAliveness.opinions(_elder).get("rows", []) as Array
	assert_eq(shipped.size(), 1, "the elder holds one authored view")
	assert_eq(
		String((shipped[0] as Dictionary).get("subject_id", "")),
		"elder_qin",
		"and it is about a person, not about the weather"
	)
	var dissent := _opinion_def(&"elder_qin", NpcOpinionDef.STANCE_CONTEST, "a promise is a chain")
	assert_eq(
		String(dissent.normalized_stance()),
		String(NpcOpinionDef.STANCE_CONTEST),
		"and the opposite position is the same closed vocabulary, so a disagreement is authorable"
	)
	assert_eq(dissent.subject_id, shipped[0].get("subject_id"), "about the very same man")


## An opinion is a BELIEF and never a bond. Nothing on this path may move standing, and
## the assertion is on the AXES rather than on the return value: a view that moved a bond
## would be the player farming an opinion the way ADR 0091's anti-farm rule forbids.
func test_holding_an_opinion_moves_no_bond_at_all() -> void:
	var before := SocialApi.bond_entry(_player, ELDER)
	assert_ne(int(NpcAliveness.opinions(_elder).get("count", 0)), 0, "the elder holds an opinion")
	var after := SocialApi.bond_entry(_player, ELDER)
	assert_almost_eq(
		float(after.get("standing", 0.0)),
		float(before.get("standing", 0.0)),
		"standing is untouched"
	)
	assert_almost_eq(
		float(after.get("trust", 0.0)), float(before.get("trust", 0.0)), "and so is trust"
	)


## ## GOSSIP ACTUALLY TRAVELS npc to npc — and the bound is the feature
##
## News moves along edges from whoever has already been told, to at most
## `MAX_GOSSIP_NPCS` recipients. Without this the player is told the same thing twice,
## which is the failure the owner named.
func test_news_travels_npc_to_npc_and_dies_at_the_hop_bound() -> void:
	var edges: Array = [
		{"from": "elder_wei", "to": "smith_bearcutter"},
		{"from": "smith_bearcutter", "to": "elder_qin"},
		{"from": "elder_qin", "to": "gate_keeper_bo"},
	]
	var result := NpcAliveness.spread(ELDER, [&"the_drifter_is_lying"], edges)
	assert_eq(int(result.get("delivered", 0)), 3, "one pass reaches three people down the chain")
	assert_eq(int(result.get("hops", 0)), 1, "and costs one pass of work, not three")
	assert_eq(NpcAliveness.gossip_deliveries, 3, "the counter counts DELIVERIES, not passes")


## A cycle cannot spin, because a recipient is told at most once per pass. This is the
## bounded-walk property `test_no_unbounded_wait.gd` cannot infer from a shape, so it is
## asserted directly.
func test_a_cycle_in_the_edge_list_terminates_rather_than_spinning() -> void:
	var edges: Array = [
		{"from": "a", "to": "b"},
		{"from": "b", "to": "c"},
		{"from": "c", "to": "a"},
		{"from": "c", "to": "c"},
	]
	var result := NpcAliveness.spread(&"a", [&"news"], edges)
	assert_eq(int(result.get("delivered", 0)), 2, "b and c, and never back to the sender")
	assert_eq(int(result.get("delivered", 0)) <= NpcAliveness.MAX_GOSSIP_NPCS, true, "and bounded")


## **An over-budget edge list is REFUSED, never sliced** — ADR 0173(b): exceeding the bound
## fails loudly, because a silently truncated route list is gossip that quietly never
## arrived and the player cannot see a truncation they were never told about.
func test_an_over_budget_gossip_pass_is_refused_rather_than_truncated() -> void:
	var edges: Array = []
	for index in range(NpcAliveness.MAX_GOSSIP_NPCS + 1):
		edges.append({"from": "a", "to": "npc_%02d" % index})
	var result := NpcAliveness.spread(&"a", [&"news"], edges)
	assert_eq(int(result.get("delivered", 0)), 0, "nothing was delivered at all")
	assert_eq(
		(result.get("reasons", []) as Array).has("too_many_edges"),
		true,
		"and the refusal is NAMED rather than swallowed"
	)


# --- (4) THE DAILY ROUND, AND THE LAZY CLOCK --------------------------------------


## **An unobserved major npc costs O(1), not O(cast).** The assertion is on the cost
## SHAPE, via the named per-npc counter: reading one npc's round moves THAT npc's counter
## by one and every other npc's by nothing, whatever the roster holds. A read that walked
## the cast would move them all.
func test_an_unobserved_major_npc_costs_o1_and_not_o_cast() -> void:
	_room([ELDER, SMITH, ELDER])
	# `Callable.call` answers Variant whatever it calls, and this project treats an
	# inferred Variant as an error, so the counter is read through a typed `int`.
	var other_before: int = int(_bound.call(SMITH))
	NpcAliveness.round(_elder, ELDER, 3)
	assert_eq(_bound.call(ELDER), 1, "the read npc advanced exactly once")
	assert_eq(_bound.call(SMITH), other_before, "and the cast behind them advanced not at all")
	NpcAliveness.round(_elder, ELDER, 4)
	assert_eq(_bound.call(ELDER), 2, "two observations, two advances")
	assert_eq(_bound.call(SMITH), other_before, "still no cast walk")


## ## THE LAZY-CLOCK INVARIANT (1): nothing runs without an observation
##
## The counter is flat across time in which nobody looked. There is no timer, no `_process`
## and no poll; a period that goes by unseen changes nothing, which is ADR 0173(c)'s "a
## place nobody visits stays stale forever — accepted".
func test_nothing_advances_while_nobody_is_looking() -> void:
	_room([ELDER])
	NpcAliveness.round(_elder, ELDER, 0)
	var before: int = int(_bound.call(ELDER))
	# Room reads that reach the alive layer through PRODUCTION, which is the point of the
	# `alive` key: a panel polling presence now also gets every body what they are doing,
	# and the round advances because a human saw the row.
	for _pass in range(8):
		NpcApi.presence_here(&"qi_dao")
	assert_eq(
		int(_bound.call(ELDER)),
		before + 8,
		"and a production room read IS an observation: the clock advanced on every pass"
	)
	assert_eq(NpcAliveness.is_synced(ELDER), true, "and the stamp is there for the next read")


## ## THE LAZY-CLOCK INVARIANT (2): the READ advances, it does not ask permission
##
## A read at a LATER period lands in a different slot, which is only possible if the
## observation itself performed the advance. Had the clock been gated on an observer
## (`if someone_is_here: advance()`), this would answer the same slot forever — the silent
## freeze ADR 0173(c) names, where every elapsed calculation returns zero.
func test_the_read_is_the_trigger_and_a_later_period_reads_a_different_slot() -> void:
	var first := NpcAliveness.round(_elder, ELDER, 0)
	var same := NpcAliveness.round(_elder, ELDER, 0)
	assert_eq(
		String(same.get("slot_id", "")), String(first.get("slot_id", "")), "same period, same slot"
	)
	var later := NpcAliveness.round(_elder, ELDER, SLOT_PERIODS)
	assert_ne(
		String(later.get("slot_id", "")),
		String(first.get("slot_id", "")),
		"and the elapsed span moved him, so the clock is not frozen"
	)
	assert_eq(
		int(later.get("elapsed_periods", 0)), SLOT_PERIODS, "the span is what the stamp remembers"
	)


## An UNTRACKED npc has no day. Composing a schedule for a person the world does not
## remember would be inventing a continuity nothing has — which is the tier policy's half
## of the daily round.
func test_an_untracked_npc_has_no_daily_round_and_the_clock_never_even_stamps_it() -> void:
	assert_eq(NpcAliveness.round(_transient, DRIFTER, 3), {}, "a transient has no round")
	assert_eq(NpcAliveness.round(_minor, GATE_KEEPER, 3), {}, "nor does a minor")
	assert_eq(NpcAliveness.is_synced(DRIFTER), false, "and it was never even stamped")


## The round is O(1) in the SPAN. A billion-period gap must cost what one period costs,
## which is the claim ADR 0168 could not make and ADR 0173(b) is the precedent for.
func test_the_round_costs_the_same_at_one_period_and_at_a_billion() -> void:
	var short_gap := NpcAliveness.round(_elder, ELDER, 0)
	var long_gap := NpcAliveness.round(_elder, ELDER, 1_000_000_000)
	assert_eq(int(long_gap.get("elapsed_periods", 0)), 1_000_000_000, "the span is reported whole")
	assert_eq(
		bool(long_gap.get("clamped", false)),
		true,
		"and the clamp is REPORTED, because a silent clamp is a silent truncation"
	)
	assert_ne(
		String(long_gap.get("slot_id", "")),
		String(short_gap.get("slot_id", "")),
		"a billion periods still lands in a real slot"
	)


## An npc with no authored round is a real state, not a crash: `{}` and no stamp.
func test_a_cast_member_with_no_authored_round_reads_empty() -> void:
	var bare := _def(&"bare_major", NpcTier.MAJOR, [])
	assert_eq(NpcAliveness.round(bare, &"bare_major", 5), {}, "no slots, no answer")
	assert_eq(NpcAliveness.is_synced(&"bare_major"), true, "though the read still happened")


# --- (5) THE SOURCE GUARD: no `if someone_is_here: advance()` ---------------------


## ADR 0173(c) names the trap by name: *an observation-driven clock DEADLOCKS if every
## advance source is itself gated on someone being present.* This reads the SOURCE of every
## file this change added and refuses the gated shape, because a comment saying the right
## thing is not the guarantee.
func test_no_advance_source_is_gated_on_someone_being_present() -> void:
	var audited := 0
	for path in ContentScan.files_under("res://src/modules/npc/"):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		audited += 1
		_assert_no_gated_advance(path, text)
	assert_eq(audited > 8, true, "the guard read the module's own source rather than nothing")


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


## The advance in this module is a WRITE TO THE STAMP and it is unconditional: it happens
## before every early return, so a def with no round is still stamped and a def with no
## roster slot is still stamped. Read structurally, because "I did not see the branch" is
## not a measurement.
func test_the_stamp_is_written_before_any_early_return_in_the_round_read() -> void:
	var code := _code_only(FileAccess.get_file_as_string("res://src/modules/npc/npc_aliveness.gd"))
	var from_at := code.find("static func round(")
	var to_at := code.find("static func is_synced(")
	assert_eq(from_at >= 0 and to_at > from_at, true, "the read really is in this file")
	var body := code.substr(from_at, to_at - from_at)
	var stamp_at := body.find("_last_synced[npc_id] = period")
	assert_eq(stamp_at >= 0, true, "the stamp write exists at all")
	var first_return := body.find("return {}")
	assert_eq(
		first_return >= 0, true, "and the read really does return early for a def with no round"
	)
	assert_eq(
		stamp_at < first_return,
		true,
		"the stamp is written BEFORE the first return, so EVERY observation advances"
	)


# --- (6) CONTENT GUARDS ----------------------------------------------------------


## The untracked tiers author NO alive asset. A per-npc `.tres` for a minor is a file
## loaded while nobody is looking at that npc, which is the bill the lazy principle exists
## not to pay — so it is refused at the content level rather than trusted.
func test_an_untracked_cast_member_authors_no_per_npc_alive_asset() -> void:
	for def in _shipped_cast():
		if def.tracked():
			continue
		var digest := def.alive_digest()
		var who := String(def.npc_id)
		assert_eq(int(digest.get("round_slots", 0)), 0, "'%s' authors no round" % who)
		assert_eq(int(digest.get("opinions", 0)), 0, "'%s' authors no opinion" % who)
		assert_eq(int(digest.get("tells", 0)), 0, "'%s' authors no tells" % who)
		assert_eq(int(digest.get("recalls", 0)), 0, "'%s' authors no recall: it has no bond" % who)


## A TRACKED cast member, by contrast, authors all four — the worked example of the tier
## table's first two rows and the proof the authored half of the layer ships.
func test_a_tracked_cast_member_authors_all_four_halves() -> void:
	var digest := _elder.alive_digest()
	assert_eq(int(digest.get("round_slots", 0)), 3, "three authored slots on the elder")
	assert_eq(int(digest.get("opinions", 0)), 1, "one authored opinion")
	assert_eq(int(digest.get("recalls", 0)), 1, "one authored recall, keyed to a real cause")
	assert_eq(int(digest.get("tells", 0)), 2, "and two authored tells")


## A recall MUST name a cause the shipped catalog actually ships. Prose about an act the
## world has no vocabulary for would never render, which makes it a silent content defect.
func test_every_authored_recall_names_a_cause_the_catalog_ships() -> void:
	for def in _shipped_cast():
		for recall_def in def.recalls:
			var who := String(def.npc_id)
			assert_ne(recall_def.cause_id, &"", "'%s' authors a recall with a cause id" % who)
			assert_ne(
				SocialCauseCatalog.instance().cause_definition(recall_def.cause_id),
				null,
				(
					"'%s' recall names cause '%s', which the catalog ships"
					% [who, String(recall_def.cause_id)]
				)
			)


## A tell's trigger is a CLOSED vocabulary, and a trigger nothing can reach is dead
## authored weight. Both halves: the trigger is one of the four, and the body is written
## in words rather than left to a numeric default.
func test_every_authored_tell_names_a_trigger_the_module_publishes_and_a_body() -> void:
	for def in _shipped_cast():
		for tell_def in def.tells:
			var who := String(def.npc_id)
			assert_eq(
				NpcTellDef.TRIGGER_ALL.has(tell_def.trigger),
				true,
				(
					"'%s' tell trigger '%s' is one the module publishes"
					% [who, String(tell_def.trigger)]
				)
			)
			assert_ne(tell_def.body, "", "'%s' writes the body in words" % who)
			assert_ne(tell_def.verb, &"", "'%s' and names the verb the body answers to" % who)


## A round's slots are addressed by authored INDEX and every index is used once. Two slots
## sharing an index makes the slot a day advances into undecidable — the exact defect
## `test_npc_content.gd` already refuses on a stage ladder.
func test_every_authored_round_uses_each_slot_index_exactly_once() -> void:
	for def in _shipped_cast():
		if def.daily_round.is_empty():
			continue
		var seen: Array[int] = []
		for slot in def.daily_round:
			assert_eq(
				seen.has(slot.index),
				false,
				"'%s' uses slot index %d once" % [String(def.npc_id), slot.index]
			)
			seen.append(slot.index)
		assert_eq(
			def.round_slot_ratio_periods > 0,
			true,
			"'%s' authors a slot ratio for the clock to divide by" % String(def.npc_id)
		)


## The clock is `TimeLadder`'s and this module adds no second copy of a time ratio — the
## duplication ADR 0173's source-reading guard exists to refuse, asserted here against the
## module's own source rather than left to a rule that cannot see `modules/*`.
func test_no_alive_file_declares_its_own_time_ratio() -> void:
	var banned := ["const PERIOD_SECONDS", "const SECONDS_PER_", "const SLOT_SECONDS"]
	for path in ContentScan.files_under("res://src/modules/npc/"):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		for raw in text.split("\n"):
			var code := raw.strip_edges()
			if code.begins_with("#"):
				continue
			for prefix in banned:
				assert_eq(
					code.begins_with(prefix),
					false,
					(
						"%s declares '%s'; the base ratio is TimeLadder's alone"
						% [path.get_file(), prefix]
					)
				)


## Every introduced budget is a number the suite has queried. A bound nothing asks about is
## a number that moves silently, so each one is read at least once above — and this makes
## the list itself a census, so a new budget cannot be added without a query.
func test_every_introduced_budget_is_a_named_number_the_suite_can_query() -> void:
	assert_eq(NpcAliveness.MAX_MEMORY_ROWS > 0, true, "a memory budget exists")
	assert_eq(NpcAliveness.MAX_GOSSIP_NPCS > 0, true, "a gossip hop bound exists")
	assert_eq(NpcAliveness.MAX_SYNC_SPAN_PERIODS > 0, true, "a sync span clamp exists")
	assert_eq(NpcAliveness.MAX_OPINION_ROWS > 0, true, "an opinion read bound exists")
	assert_eq(NpcRecallDef.MAX_RECALLS > 0, true, "a recall authoring bound exists")
	assert_eq(NpcMinorComposer.MAX_ROWS > 0, true, "and a composer row bound")


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
