extends TestCase

## ## The deliverable: an actor-scoped institution surface, and the round trip a player
## performs
##
## Everything above this file shipped and nothing could reach it. `InstitutionRegistry`,
## `InstitutionDefCatalog`, `InstitutionFounding`, `InstitutionLedger` and
## `InstitutionProjection` are all real, all tested, and `core/` published **no surface
## answering "what does THIS actor hold"** — `InstitutionLedger` has exactly two writers
## (`promote`, `move_standing`) and neither enrols anybody. The screen's three Callables
## were therefore unbound and every verb refused by name.
##
## The five measurements this suite exists to pin:
##
##   1. **join → leave → join** round-trips, and leaving costs.
##   2. **A refused verb writes NOTHING**, byte for byte (ADR 0044).
##   3. **`capacity_full` is a refused admit**, never a silent trim (ADR 0084).
##   4. **The three states are distinguishable** from `summary(actor)`.
##   5. **Strip-then-rebuild does not compound** at five rebuilds — the 2, 4, 6, 8, 10, 12
##      regression `test_institution_projection.gd` measured.
##
## ## Three organizations, and WHY they are three
##
##   - **The shipped guild** drives rosters, capacity, obligations, refusals, the three
##     states and the save round trip. It needs no allowlist for any of those.
##   - **Two AUTHORED guilds** drive recognition. All three shipped guild `.tres` files
##     author an EMPTY `standing_percent_stats`, so a guild's recognition is
##     authored-but-unreachable in shipped content until somebody writes ids into it.
##     Rather than edit shipped content from a suite — a leak with no owner — the content is
##     written under the OS temp directory and published through `set_overlay_roots`, which
##     is the MOD SEAM: nothing in `game/src` was touched to make them appear, so ADR
##     0184's headline claim is measured here rather than asserted. They carry DIFFERENT
##     authored caps (150 and 120), so the two-house case can show each institution's cap is
##     its own rather than a shared one.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over a fixed literal, a fixed `range`, or a
## materialised key list, and none appends to the container it walks — so no bound here can
## grow in lockstep with its own body and `test_no_unbounded_wait.gd` has nothing to reject.

## The shipped organizations, read and NEVER written.
const LANTERN := "res://data/institutions/lantern_exchange.tres"
const HUNT := "res://data/institutions/grey_horizon_hunt.tres"

## ## The shipped organization ids
##
## Authored in exactly one `.tres` each, and a rename there must fail here rather than leave
## a case quietly driving nothing.
const LANTERN_ID := &"lantern_exchange"
const HUNT_ID := &"grey_horizon_hunt"
const CIRCLE_ID := &"torrent_field_circle"

## The single seat a founder is placed in, and the UNCAPPED ordinary office a newcomer is
## seated in. Both are AUTHORED CONTENT, not policy — the shipped guild says so in prose.
const SEAT := &"first_ledger"
const CLERK := &"clerk"
const TRACKER := &"tracker"
## A CAPPED room: five factors, so a sixth admit is refused rather than trimmed.
const FACTOR := &"factor"

## The authored organizations this suite publishes through the mod seam.
const AUTHORED_ID := &"wiring_guild"
const CHAPTER_ID := &"wiring_chapter"
const AUTHORED_SEAT := &"founding_seat"
const AUTHORED_FLOOR := &"floor"
const CHAPTER_SEAT := &"chapter_seat"
const CHAPTER_FLOOR := &"gallery"

## The stats the authored offices recognise. `insight_gain` derives to
## `1.0 + comprehension * 0.01` and `poise` to `physique * 0.5 + will * 0.5`, so both have
## a non-zero baseline on every actor here and a PERCENT on either is a real edge rather
## than ADR 0068's silent no-op. TWO ids, so the allowlist is a set and a rebuild that
## dropped one of them fails rather than halving.
const RECOGNISED := Stat.INSIGHT_GAIN
const ALSO := Stat.POISE

const MEMBERSHIP_FILE := "res://src/core/institution_membership.gd"
const TEMP_DIR := "cw_institution_membership_test"
const OWNER := "wiring_test"

var _registry: InstitutionRegistry = null
## An actor carrying no grant at all, so "nothing outside the allowlist moved" is measured
## against the same sheet rather than against a hand-written number.
var _reference: Actor = null
## The directory the authored `.tres` files live under, published as the family's overlay.
var _overlay: String = ""
## Everything this suite mints. **`free()` is never called on an entry**: `Actor` and
## `Resource` both extend `RefCounted`, and `Object.free()` on one is a SCRIPT ERROR that
## aborts the rest of teardown (measured in `test_institution_foundation`). This suite
## mints no `Node` at all, which is why dropping the array IS the release.
var _born: Array = []


func setup() -> void:
	_registry = InstitutionRegistry.new()
	# ## BOTH process singletons are cleared in `setup` AND in `teardown`
	#
	# The runner drives every suite in ONE process. `setup` clears what a PREVIOUS suite
	# left; `teardown` clears what THIS one leaves. Relying on teardown alone means a case
	# that aborts mid-way hands its fixtures to every suite after it.
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	InstitutionBoot.install(_registry)
	_reference = _actor(&"reference")
	_publish_authored_organizations()


func teardown() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	# `InstitutionRegistry.shared` is PROCESS state and every suite shares one process, so
	# the shared instance is dropped here as well as this suite's own — a registration a
	# suite forgets to clear is handed to every suite after it.
	if InstitutionRegistry.shared != null:
		InstitutionRegistry.shared.clear()
	_born.clear()
	if _registry != null:
		_registry.clear()
		_registry = null
	if _overlay != "":
		for file in ContentScan.files_under(_overlay):
			DirAccess.remove_absolute(file)
		DirAccess.remove_absolute(_overlay)
		_overlay = ""


# --- The round trip a player performs ------------------------------------------


## ## join, then leave, then join again
##
## The whole point of the surface, and the three halves a player actually presses. The
## standing a member earned goes with the claim, so the second join starts where the first
## did rather than where the first left off — and the recognition comes off the sheet on the
## leave, which is measured rather than assumed.
func test_join_leave_then_join_again_round_trips_and_the_recognition_follows_it() -> void:
	var actor := _actor(&"joiner")
	var entered := InstitutionMembership.join(_registry, actor, AUTHORED_ID)
	assert_eq(bool(entered["ok"]), true, "a member walks into the guild: %s" % str(entered))
	assert_eq(String(entered["position"]), String(AUTHORED_FLOOR), "seated in the ordinary office")
	assert_eq(int(entered["ledger"]["standing"]), 0, "on zero standing: recognition is earned")
	assert_eq(InstitutionMembership.holds(actor, AUTHORED_ID), true, "and the claim is the actor's")

	# The RECOGNITION is on the stack and worth the percent a standing of zero is worth — a
	# grant of nothing, which is still a grant: it is what makes the contribution invertible
	# later. A member who has invested nothing is not a broken grant.
	assert_almost_eq(
		actor.stats.derived(RECOGNISED), _bare(RECOGNISED), "at zero standing the sheet is bare"
	)
	assert_eq(_own_modifiers(actor), 2, "with the office's two ids tagged on the stack")

	# Earn it. The stat moves by the bounded percent, and the office did not move with it:
	# standing is the only writer of standing and it never reads the office (ADR 0064).
	var earned := InstitutionMembership.move_standing(_registry, actor, AUTHORED_ID, 50)
	assert_eq(bool(earned["ok"]), true, "standing is earned")
	assert_eq(int(earned["applied"]), 50, "by exactly the amount asked")
	assert_almost_eq(
		_own_percent(actor, String(RECOGNISED)),
		0.05,
		"the stack carries that standing's own percent, tagged under this family"
	)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		_bare(RECOGNISED) * 1.05,
		"so the recognised stat moved by it and by nothing else"
	)
	assert_eq(
		String(InstitutionMembership.claim_of(actor, AUTHORED_ID)["position"]),
		String(AUTHORED_FLOOR),
		"and the office is unchanged by a standing move"
	)

	# ## LEAVE. Always permitted, and it costs.
	var left := InstitutionMembership.leave(_registry, actor)
	assert_eq(bool(left["ok"]), true, "walking out is never refused")
	assert_eq(int(left["count"]), 1, "and it left the one house held")
	assert_eq(InstitutionMembership.holds(actor, AUTHORED_ID), false, "no claim survives")
	assert_eq(_own_modifiers(actor), 0, "the whole recognition came off the stack")
	assert_almost_eq(
		actor.stats.derived(RECOGNISED), _bare(RECOGNISED), "restoring the sheet exactly"
	)
	# The COST is the standing: it went with the claim rather than being kept in reserve, so
	# a member with no exit has nothing to walk out TO either.
	assert_eq(
		InstitutionMembership.claim_of(actor, AUTHORED_ID), {}, "and the earned number is gone"
	)

	# ## And back in. Starting from zero, because nothing was banked.
	var again := InstitutionMembership.join(_registry, actor, AUTHORED_ID)
	assert_eq(bool(again["ok"]), true, "the member may walk back in")
	assert_eq(int(again["ledger"]["standing"]), 0, "on zero again")
	assert_eq(
		_own_percent(actor, String(RECOGNISED)),
		0.0,
		"and the recognition is back at nothing, rather than compounding what it had"
	)


## ## A member of a guild the hero FOUNDED can be a second member of it, and a member of a
## guild they joined sees the roster too
##
## This is the sect defect, measured as a pass: the roster was on the FOUNDER's ledger, so a
## member who joined rather than founded saw no roster at all and every office of a guild
## they belonged to read as unpublished. The world roster is the fix, and this case says the
## fix works from the joiner's side rather than the founder's.
func test_a_joiners_roster_is_the_worlds_and_not_the_founders_body() -> void:
	var founder := _actor(&"founder")
	var joiner := _actor(&"joiner")
	var founded := InstitutionMembership.found(_registry, founder, _guild(), "founder")
	assert_eq(bool(founded["ok"]), true, "the guild is founded and persisted")
	assert_eq(String(founded["position"]), String(SEAT), "with the founder in the single seat")
	assert_eq(
		(founded["ledger"] as Dictionary).has("roster"),
		false,
		"and the founder's OWN claim carries no roster, so it is not in one person's body"
	)

	assert_eq(
		bool(InstitutionMembership.join(_registry, joiner, LANTERN_ID)["ok"]),
		true,
		"a second actor joins"
	)

	# The JOINER sees both offices: the one they hold, and the founder's seat. A roster a
	# member cannot see is a succession nobody can watch, which is the whole of ADR 0084's
	# vacancy design.
	var seen := InstitutionMembership.roster_of(LANTERN_ID)
	assert_eq((seen[String(SEAT)] as Array).size(), 1, "the seat names its one holder")
	assert_eq(String((seen[String(SEAT)] as Array)[0]), "founder", "and names them")
	assert_eq((seen[String(CLERK)] as Array).size(), 1, "the ordinary office names its holder")
	# And the FOUNDER sees the same roster, which is the half a founder's own body could
	# never have carried: an office filled after they founded it.
	assert_eq(
		(InstitutionMembership.roster_of(LANTERN_ID)[String(CLERK)] as Array).size(),
		1,
		"the founder sees the joiner too, so the roster is world state"
	)
	# An office nobody holds is VACANT, not absent: the family publishes every authored
	# office so an unfilled one reads as a fact about the world rather than as a roster
	# nobody told us about (ADR 0083's middle state).
	assert_eq(seen.has(String(FACTOR)), true, "the room nobody filled is still published")
	assert_eq((seen[String(FACTOR)] as Array).size(), 0, "with nobody holding it")


# --- Refusals, and the one thing that writes nothing ---------------------------


## ## ADR 0044 as a MEASUREMENT: every refused verb leaves the ledger byte for byte
##
## Each case is refused on a DIFFERENT fault, and each compares the actor's whole sheet, whole
## modifier stack and whole store before and after. A refusal that took something first and
## refused second would show here as a changed fingerprint.
func test_every_refused_verb_writes_nothing_byte_for_byte() -> void:
	var actor := _actor(&"refused")
	# Give it something to lose, so "writes nothing" is measured against a NON-empty store
	# and a NON-empty stack rather than against `{}`.
	InstitutionMembership.found(_registry, actor, _authored_def(), "me")
	InstitutionMembership.move_standing(_registry, actor, AUTHORED_ID, 20)
	var established := _fingerprint(actor)
	assert_eq(int(established["own"]) > 0, true, "so there IS something to lose")

	var stranger := _actor(&"stranger")
	var stranger_before := _fingerprint(stranger)
	# A `for` over a FIXED literal table calling into the verb under test: the body never
	# appends to `refusals`, so the bound is the table's own length. Each row carries the
	# fingerprint its SUBJECT must be unchanged against — a single shared one would compare a
	# stranger's bare sheet against a member's granted sheet and report the member's own
	# grant as a leak, which is exactly what the first version of this case did.
	for entry in [
		[
			"no actor",
			null,
			null,
			InstitutionMembership.R_NO_ACTOR,
			func(): return InstitutionMembership.join(_registry, null, AUTHORED_ID),
		],
		[
			"already a member",
			actor,
			established,
			InstitutionMembership.R_ALREADY_A_MEMBER,
			func(): return InstitutionMembership.join(_registry, actor, AUTHORED_ID),
		],
		[
			"unknown organization",
			actor,
			established,
			InstitutionMembership.R_UNKNOWN_INSTITUTION,
			func(): return InstitutionMembership.join(_registry, actor, &"no_such_house"),
		],
		[
			"an empty organization",
			actor,
			established,
			InstitutionMembership.R_UNKNOWN_INSTITUTION,
			func(): return InstitutionMembership.join(_registry, actor, &""),
		],
		[
			"an office the content does not author",
			stranger,
			stranger_before,
			InstitutionMembership.R_UNKNOWN_POSITION,
			func():
				return InstitutionMembership.join(_registry, stranger, AUTHORED_ID, &"audit_office"),
		],
		[
			"a standing move on a house not held",
			actor,
			established,
			InstitutionMembership.R_NOT_A_MEMBER,
			func(): return InstitutionMembership.move_standing(_registry, actor, HUNT_ID, 5),
		],
		[
			"a zero standing move",
			actor,
			established,
			InstitutionLedger.R_NON_POSITIVE,
			func(): return InstitutionMembership.move_standing(_registry, actor, AUTHORED_ID, 0),
		],
	]:
		var label: String = entry[0]
		var subject: Actor = entry[1]
		var answer: Dictionary = (entry[4] as Callable).call()
		assert_eq(bool(answer["ok"]), false, "%s is refused" % label)
		assert_eq(String(answer["reason"]), String(entry[3]), "%s names its own cause" % label)
		if subject != null:
			assert_eq(_fingerprint(subject), entry[2], "%s changed nothing at all" % label)


## ## `leave` refuses ONE thing, and it is `not_a_member`
##
## The whole refusal vocabulary of an exit, asserted as a surface rather than as examples:
## a verb that could refuse for a reason the player cannot act on is a trap, and one added
## later must fail here. `no_actor` is the one other answer, because a verb handed nothing has
## no subject to walk out of.
func test_leaving_refuses_only_not_a_member_and_always_permits_the_rest() -> void:
	var actor := _actor(&"leaver")
	var stranger := _actor(&"stranger")
	for entry in [
		["a stranger", func(): return InstitutionMembership.leave(_registry, stranger)],
		["an empty id", func(): return InstitutionMembership.leave(_registry, actor, &"")],
		[
			"an unknown id",
			func(): return InstitutionMembership.leave(_registry, actor, &"no_such_house"),
		],
		[
			"a house never joined",
			func(): return InstitutionMembership.leave(_registry, actor, HUNT_ID),
		],
		["no actor", func(): return InstitutionMembership.leave(_registry, null)],
	]:
		var answer: Dictionary = (entry[1] as Callable).call()
		assert_eq(bool(answer["ok"]), false, "%s is refused" % entry[0])
		assert_ne(String(answer["reason"]), "", "%s names a reason" % entry[0])
	assert_eq(
		InstitutionMembership.leave(_registry, actor, HUNT_ID)["reason"],
		InstitutionMembership.R_NOT_A_MEMBER,
		"and a house not held is the not_a_member case by name"
	)
	# And NOTHING stands between a member and the door: an actor holding two houses walks out
	# of both in one press, with no refusal available.
	var busy := _actor(&"busy")
	InstitutionMembership.join(_registry, busy, LANTERN_ID)
	InstitutionMembership.join(_registry, busy, HUNT_ID)
	assert_eq(
		(InstitutionMembership.summary(busy)["institutions"] as Dictionary).size(),
		2,
		"the member holds two houses"
	)
	var out := InstitutionMembership.leave(_registry, busy)
	assert_eq(bool(out["ok"]), true, "and walks out of both in one press")
	assert_eq(int(out["count"]), 2, "both houses, not an arbitrary one of them")
	assert_eq(InstitutionMembership.summary(busy), {}, "with nothing left to answer")


## ## `capacity_full` is a REFUSED ADMIT, and nobody is silently trimmed
##
## ADR 0084 makes the overflow a refusal rather than a queue or a displacement: a member
## quietly removed from a roster nobody voted to reduce is a fact the world cannot explain.
## The room is filled through the verb itself, so the case measures the GATE on real
## admissions rather than on a hand-written roster.
func test_a_full_office_is_a_refused_admit_and_never_a_silent_trim() -> void:
	var guild := _guild()
	var room := int(guild.position(FACTOR).room())
	assert_eq(room, 5, "the room holds five by authored content")
	# Fill it to its cap through the verb itself, so every holder is a real admission. The
	# ACTORS are kept, not just their ids: `leave` acts on a body, so re-minting an actor
	# with a matching id would hand it an empty store and the leave would refuse
	# `not_a_member` — a case that reads as "the room never frees itself" rather than as the
	# test's own mistake.
	var seated: Array[String] = []
	var bodies: Array[Actor] = []
	for index in room:
		var who := _actor(StringName("factor_%d" % index))
		var answer := InstitutionMembership.join(_registry, who, LANTERN_ID, FACTOR)
		assert_eq(bool(answer["ok"]), true, "holder %d is admitted" % index)
		seated.append(String(who.id))
		bodies.append(who)
	var refused := InstitutionMembership.join(_registry, _actor(&"sixth"), LANTERN_ID, FACTOR)
	assert_eq(bool(refused["ok"]), false, "the sixth is refused")
	assert_eq(
		String(refused["reason"]), InstitutionMembership.R_CAPACITY_FULL, "and named capacity_full"
	)
	assert_eq(
		InstitutionMembership.summary(_actor(&"nobody")), {}, "an untouched actor answers nothing"
	)
	# And nobody was moved: the roster is exactly the five admitted, in admission order.
	var held: Array = InstitutionMembership.roster_of(LANTERN_ID)[String(FACTOR)]
	assert_eq(held.size(), 5, "the room still holds exactly its cap")
	assert_eq(held, seated, "and holds the five who were admitted, untrimmed")
	# A seat that frees itself is the mirror of a refusal: the refusal is about the ROOM, not
	# about the actor, so somebody else leaving admits the next applicant.
	assert_eq(
		bool(InstitutionMembership.leave(_registry, bodies[0])["ok"]), true, "one of them leaves"
	)
	assert_eq(
		(InstitutionMembership.roster_of(LANTERN_ID)[String(FACTOR)] as Array).size(),
		room - 1,
		"and the roster says so without anybody being told to remove a row"
	)
	assert_eq(
		bool(InstitutionMembership.join(_registry, _actor(&"seventh"), LANTERN_ID, FACTOR)["ok"]),
		true,
		"and the room has room again, so the next applicant is admitted"
	)


## ## `capacity == 0` is an UNBOUNDED room and is never full
##
## The other half of ADR 0084's cap: `0` is a room with no walls, `1` is a seat, and above 1
## is a room that can fill. The shipped guilds author their ordinary office unbounded on
## purpose — a guild that limited its ordinary members would be charging to belong — so this
## is the shape PLAY actually admits through, and an unbounded office that filled up would
## close the only door the shipped content has.
func test_an_unbounded_office_is_never_full_and_is_the_authored_entry() -> void:
	assert_eq(int(_guild().position(CLERK).room()), 0, "the ordinary office is authored unbounded")
	# More admissions than any authored cap could survive, on one roster.
	var seated := 0
	for index in 8:
		var who := _actor(StringName("clerk_%d" % index))
		assert_eq(
			bool(InstitutionMembership.join(_registry, who, LANTERN_ID, CLERK)["ok"]),
			true,
			"member %d is admitted to an unbounded office" % index
		)
		seated += 1
	assert_eq(
		(InstitutionMembership.roster_of(LANTERN_ID)[String(CLERK)] as Array).size(),
		seated,
		"every one of them is on the roster"
	)
	# And the entry rule is CONTENT: with no office named, a newcomer goes to the authored
	# unbounded office and nowhere else. A capped room is never chosen by default, because a
	# guild that admits everybody into its five-seat room is not a guild.
	assert_eq(
		String(InstitutionMembership.join(_registry, _actor(&"newcomer"), HUNT_ID)["position"]),
		String(TRACKER),
		"the entry office is the authored ordinary one, never the single seat"
	)


## ## Admission is never free: the joiner OWES what the office and the house ask
##
## The yin-yang pair, and the reason the entry office is not the top one. A member who walks
## into a guild is immediately in debt to it, on the office's own lines beside the
## organization's — merged by the LARGER count per term, which is the same merge
## `InstitutionFounding` applies to a founder because a joiner's row is built by that same
## writer rather than by a second rule here.
func test_admission_opens_the_office_and_membership_obligation_lines() -> void:
	var joined := InstitutionMembership.join(_registry, _actor(&"indebted"), LANTERN_ID, CLERK)
	assert_eq(bool(joined["ok"]), true, "admitted")
	var owed: Dictionary = joined["obligation"]
	assert_eq(int(owed["duty_lantern_exchange"]), 1, "the house's own membership duty opens")
	assert_eq(int(owed["duty_clerk"]), 1, "and the office's duty beside it")
	assert_eq(
		InstitutionClaim.from_dict(joined["ledger"]).settled(), false, "so nothing is settled"
	)
	# A FOUNDER opens the TREASURY, which a joiner must not: founding is the only verb that
	# opens one, and a member walking in must not open the institution's books.
	assert_eq(
		(joined["ledger"] as Dictionary).has("treasury"), false, "a joiner opens no treasury line"
	)
	var found := InstitutionMembership.found(_registry, _actor(&"founder"), _guild(), "founder")
	assert_eq(
		(found["ledger"] as Dictionary).has("treasury"), true, "while founding still opens one"
	)


# --- The three states, and the read model ---------------------------------------


## ## ADR 0083's three states are THREE DISTINGUISHABLE answers
##
## `{}` is "this does not exist", a published empty roster is "it exists and your place in it
## is absent", and `{"ok": false, "reason": R}` is a refusal. Collapsing any two of them is
## how a house you belong to and hold no seat in reads as a spare widget row — the exact
## confusion `InstitutionCard`'s class note is written against.
func test_the_three_states_are_distinguishable_from_summary() -> void:
	# State one: an actor who belongs to nothing answers `{}` — which is a STATE, not a
	# failure, and the same value an unbound reader publishes.
	var stranger := _actor(&"stranger")
	assert_eq(InstitutionMembership.summary(stranger), {}, "no institutions is an empty answer")
	assert_eq(InstitutionMembership.summary(null), {}, "and so is no actor at all")

	# State two: the organization EXISTS and the viewer is in it, and one authored office is
	# VACANT because the world published a roster and nobody is standing in that one. That is
	# a different fact from an office nobody published a roster for, and both are reachable.
	var joiner := _actor(&"joiner")
	InstitutionMembership.join(_registry, joiner, LANTERN_ID)
	var view: Dictionary = InstitutionMembership.summary(joiner)["institutions"][String(LANTERN_ID)]
	assert_eq(bool(view["exists"]), true, "the organization exists")
	assert_eq(view["roster"][String(FACTOR)].size(), 0, "and the unfilled room is vacant")
	assert_eq(view["roster"].has(String(FACTOR)), true, "a visible row, never a hidden one")
	# The office the joiner IS in names them, because the world published that roster.
	assert_eq(
		(view["roster"][String(CLERK)] as Array).size(), 1, "while the office they hold names them"
	)

	# State three: a REFUSAL is `{ok: false, reason}` and is never `{}` and never a zero.
	var refused := InstitutionMembership.join(_registry, joiner, LANTERN_ID)
	assert_eq(refused.is_empty(), false, "a refusal is not an empty answer")
	assert_eq(bool(refused["ok"]), false, "it is refused")
	assert_ne(String(refused["reason"]), "", "and it names a cause")
	assert_eq(
		String(refused["reason"]),
		InstitutionMembership.R_ALREADY_A_MEMBER,
		"which is the member's own situation and not a default"
	)


## ## `normalized` is the CLAIM's ratio, and `ui/` never divides it
##
## The formula is authored once in `InstitutionClaim.normalized()`, so a caller publishing
## `standing / standing_cap` would be a second copy of it that could drift. Both sides of this
## comparison come off the SAME claim, so a restatement anywhere on the path fails here
## rather than reading as a rounding difference.
func test_normalized_is_the_claims_own_ratio() -> void:
	var actor := _actor(&"ratio")
	var founded := InstitutionMembership.found(_registry, actor, _guild(), "me")
	assert_eq(int(founded["ledger"]["standing"]), 40, "on the authored founder standing")
	assert_eq(int(founded["ledger"]["standing_cap"]), 150, "under a cap above 100")
	var view: Dictionary = InstitutionMembership.summary(actor)["institutions"][String(LANTERN_ID)]
	assert_eq(int(view["standing"]), 40, "the raw numbers are published for a panel to print")
	assert_eq(int(view["standing_cap"]), 150, "under the authored cap")
	assert_almost_eq(
		float(view["normalized"]),
		InstitutionClaim.from_dict(view).normalized(),
		"so the published ratio IS InstitutionClaim.normalized() and not a restatement"
	)
	assert_almost_eq(float(view["normalized"]), 40.0 / 150.0, "and it is the share of the cap")
	# The ratio is a RATIO, not the percent recognition: the two answer different questions,
	# and a caller that read one for the other would print a standing as a bonus.
	assert_ne(
		float(view["normalized"]),
		InstitutionClaim.standing_percent(int(view["standing"])),
		"the standing's share of its cap is not the recognition it projects"
	)


# --- Recognition, and the compounding regression ---------------------------------


## ## A guild member's allowlisted stat moves BY THE BOUNDED PERCENT, and moves again when
## the standing falls
##
## The percent rides the member's own sheet, so this is one edge at every realm rather than a
## flat that is decisive at R2 and noise by roughly realm 12 (ADR 0063), and a falling
## standing is the ONLY way a member ever loses a grant. The cap saturates long before the
## authored cap is reached, and the LEDGER keeps the politics.
func test_a_recognised_stat_moves_by_the_bounded_percent_and_falls_again() -> void:
	var actor := _actor(&"recognised")
	var def := _authored_def()
	var before := _sheet(actor, def.position(AUTHORED_SEAT).standing_percent_stats)
	InstitutionMembership.found(_registry, actor, def, "me")
	# The founder's authored standing of 40 under a cap of 150 is 0.04 — the percent is the
	# standing's own RATE, not a fraction of the cap, and nothing reads the cap.
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		before[String(RECOGNISED)] * 1.04,
		"the first stat moved by the founder's standing percent"
	)
	assert_almost_eq(
		actor.stats.derived(ALSO),
		before[String(ALSO)] * 1.04,
		"and so did the second, so the allowlist is a set and a rebuild that dropped one fails"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH), _bare(Stat.MAX_HEALTH), "and nothing else moved"
	)
	# The rise: at the authored cap of 150 the percent saturates at the ceiling, so this is
	# where a member stops gaining recognition — while the LEDGER still reads 150.
	InstitutionMembership.move_standing(_registry, actor, AUTHORED_ID, 110)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		before[String(RECOGNISED)] * (1.0 + InstitutionClaim.STANDING_PERCENT_CAP),
		"recognition saturates at the authored ceiling"
	)
	assert_eq(
		int(InstitutionMembership.claim_of(actor, AUTHORED_ID)["standing"]),
		150,
		"while the ledger says 150"
	)
	# ## And DOWN again, which is the only exit recognition has.
	InstitutionMembership.move_standing(_registry, actor, AUTHORED_ID, -100)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		before[String(RECOGNISED)] * 1.05,
		"a falling standing falls back with it"
	)
	assert_eq(
		int(InstitutionMembership.claim_of(actor, AUTHORED_ID)["standing"]), 50, "the ledger agrees"
	)
	# And to nothing at all, exactly: a strip that only nearly works strands the grant.
	assert_eq(
		bool(InstitutionMembership.leave(_registry, actor)["ok"]), true, "leaving is permitted"
	)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED), before[String(RECOGNISED)], "restoring the sheet exactly"
	)
	assert_eq(_own_modifiers(actor), 0, "with nothing of ours left on the stack")


## ## The 2, 4, 6, 8, 10, 12 regression, pinned at FIVE rebuilds
##
## `InstitutionProjection` strips its own tag before it writes, and this is the measurement
## that made that necessary: delegating the old loop unchanged climbed the modifier stack
## 2, 4, 6, 8, 10, 12 over five rebuilds while every assertion about the sheet still read
## plausibly. The stack COUNT and the stack ITSELF are the only observations that saw it, so
## both are asserted after every cycle rather than once at the end.
func test_five_rebuilds_leave_the_modifier_fingerprint_identical() -> void:
	var actor := _actor(&"rebuilt")
	InstitutionMembership.found(_registry, actor, _authored_def(), "me")
	var before := _fingerprint(actor)
	assert_eq(int(before["own"]), 2, "two ids on the stack after the founding")
	# A `for` over a FIXED range: the body writes to the actor and never to the range being
	# walked, so the bound is the literal and nothing can grow it. Five, because five is where
	# the climb became visible.
	for cycle in range(5):
		assert_eq(
			bool(InstitutionMembership.reproject(_registry, actor)["ok"]), true, "cycle %d" % cycle
		)
		assert_eq(_fingerprint(actor), before, "cycle %d leaves the actor identical" % cycle)
		assert_eq(int(_fingerprint(actor)["own"]), 2, "cycle %d leaves two ids" % cycle)
	# And the whole point: the standing never moved through any of those five rebuilds, so a
	# climb would be a COMPOUNDED grant rather than five equal ones.
	assert_eq(
		int(InstitutionMembership.claim_of(actor, AUTHORED_ID)["standing"]),
		40,
		"standing fixed through every rebuild"
	)


## ## The grant survives the defining content being GONE — the TAG is the inversion
##
## ADR 0063's case: a `.tres` that no longer exists still leaves a contribution that can be
## taken back, and that is exactly when losing an office would otherwise strand it.
##
## **The content is DELETED, not emptied.** An earlier version emptied the def's offices in
## place and it poisoned every LATER case: `load()` caches process-wide, `set_overlay_roots`
## nulls the CATALOG but cannot reload a mutated `Resource`, so the catalog then served an
## organization with no offices and no allowlist to every suite after this one — in ONE
## process. Damaging shared state is INC-0041 pointed the other way, and a genuinely absent
## file is both the honest version of the case and the one the ADR is about.
func test_the_grant_is_invertible_after_the_defining_content_is_gone() -> void:
	var doomed := &"doomed_guild"
	var root := _write_guild(doomed, &"doomed_seat", &"doomed_floor", 100, 40, 100)
	_republish()
	var actor := _actor(&"orphaned")
	var founded := InstitutionMembership.found(
		_registry, actor, InstitutionDefCatalog.instance().definition(doomed), "me"
	)
	assert_eq(bool(founded["ok"]), true, "the guild is founded with an authored allowlist")
	assert_eq(_own_modifiers(actor), 2, "so the recognition is on the stack")

	## The content goes away, and the CATALOG is asked again — the whole family, not one row.
	DirAccess.remove_absolute(root)
	_republish()
	assert_eq(
		InstitutionDefCatalog.instance().has(doomed), false, "the organization no longer exists"
	)

	# A REBUILD strips by TAG, so it takes back exactly what it added even though nothing can
	# name the office that granted it — which is the inversion, and the reason the claim
	# records the contribution rather than re-reading the definition.
	var rebuilt := InstitutionMembership.reproject(_registry, actor)
	assert_eq(bool(rebuilt["ok"]), true, "a rebuild with no definition is not a refusal")
	assert_eq(_own_modifiers(actor), 0, "and the whole contribution came back off")
	assert_almost_eq(actor.stats.derived(RECOGNISED), _bare(RECOGNISED), "restoring the sheet")
	# And leaving still works with no definition at all, for the same reason.
	assert_eq(
		bool(InstitutionMembership.leave(_registry, actor)["ok"]),
		true,
		"leaving needs no definition either"
	)
	# The surviving guilds are UNTOUCHED by the deletion, which is the difference between a
	# missing file and a corrupted catalog.
	assert_eq(
		InstitutionDefCatalog.instance().has(AUTHORED_ID), true, "while its neighbours survive"
	)


## ## Two houses each contribute their own bounded percent, and the sum is INVERTIBLE
##
## Each organization contributes its own bounded percent under its OWN source tag, so the
## stack sums them: a member of two guilds at the ceiling carries `0.10 + 0.10`. Nothing is
## violated — ADR 0084's "no ladder of positions can add up" is about positions WITHIN one
## institution, and the cap bounds each claim rather than the sum.
##
## ## It is ACCEPTED, and pinned rather than bounded, for three reasons
##
##   1. Bounding the SUM needs a second authority that knows every organization at once —
##      which is a stat composer, the machinery ADR 0084 refuses in a projector that is a
##      pure function of four arguments.
##   2. Bounding the INPUT would be a cap on how many institutions a player may join, and
##      AGENTS.md's yin-yang rule binds the OUTPUT and never the INPUT: an input cap on
##      membership is a tax on whoever has fewer houses.
##   3. The tags are namespaced, so the composition is EXPLICIT and every term of it is
##      invertible: `leave` removes exactly one organization's share and the other survives.
##      So the worst case is measured and named here rather than discovered at a review.
func test_two_houses_each_contribute_their_own_bounded_percent() -> void:
	var actor := _actor(&"dual")
	var before := actor.stats.derived(RECOGNISED)
	InstitutionMembership.found(_registry, actor, _authored_def(), "me")
	assert_eq(
		bool(InstitutionMembership.join(_registry, actor, CHAPTER_ID)["ok"]),
		true,
		"and joins a second house"
	)
	# Drive both to the ceiling so the sum is the worst case the family can produce.
	InstitutionMembership.move_standing(_registry, actor, AUTHORED_ID, 200)
	InstitutionMembership.move_standing(_registry, actor, CHAPTER_ID, 200)
	assert_eq(
		int(InstitutionMembership.claim_of(actor, AUTHORED_ID)["standing"]),
		150,
		"the first house is at ITS authored cap"
	)
	assert_eq(
		int(InstitutionMembership.claim_of(actor, CHAPTER_ID)["standing"]),
		120,
		"and the second at its OWN, so neither cap is read as a shared one"
	)
	# ## THE MEASUREMENT: two ceilings, added by the stack, and nothing beyond.
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		before * (1.0 + 2.0 * InstitutionClaim.STANDING_PERCENT_CAP),
		"two houses at the ceiling contribute exactly two bounded percents"
	)
	assert_eq(_own_modifiers(actor), 4, "two ids per house, under two distinct tags")
	# And the sum is INVERTIBLE one term at a time: leaving one house leaves the other's
	# recognition standing, which is what makes the accepted composition reviewable rather
	# than a single lump nobody can take back.
	InstitutionMembership.leave(_registry, actor, CHAPTER_ID)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		before * (1.0 + InstitutionClaim.STANDING_PERCENT_CAP),
		"leaving one house leaves exactly one house's recognition"
	)
	assert_eq(_own_modifiers(actor), 2, "and half the stack came off")


## ## An organization that authors NO office grants nothing, and that is a SUCCESS
##
## The farmers' circle authors offices for nobody: recognition begins where office begins,
## which `InstitutionPositionDef`'s note calls a design rather than an omission. An empty
## grant is ADR 0083's FIRST state, so it is `ok` with nothing granted — never a refusal, and
## never a modifier on `&""` that no reader could look up.
func test_a_organization_authoring_no_office_grants_nothing_and_is_not_a_refusal() -> void:
	var actor := _actor(&"circle")
	var joined := InstitutionMembership.join(_registry, actor, CIRCLE_ID)
	assert_eq(bool(joined["ok"]), true, "the circle admits a member")
	assert_eq(String(joined["position"]), "", "who holds no office, which is a legitimate state")
	assert_eq(
		_own_modifiers(actor), 0, "and is recognised for nothing, because nothing is authored"
	)
	assert_eq((joined["granted"] as Dictionary).size(), 0, "the grant is empty, not a refusal")
	# But the member still OWES the house's duty, so admission is not free either.
	assert_eq(int(joined["obligation"]["duty_torrent_field_circle"]), 1, "the circle's duty opens")
	# And the read model answers for it anyway, because "belongs to nothing" and "belongs to
	# a circle holding no seat" are different facts.
	var view: Dictionary = InstitutionMembership.summary(actor)["institutions"][String(CIRCLE_ID)]
	assert_eq(bool(view["exists"]), true, "the claim exists")
	assert_eq(String(view["position"]), "", "in no office")
	assert_eq(
		(view["roster"] as Dictionary).size(),
		0,
		"and the circle publishes no office for one to be vacant in"
	)


# --- Helpers ---------------------------------------------------------------------


## ## The shipped guild, loaded and read
##
## Nothing is written to it: `load()` caches process-wide and the runner drives every suite in
## ONE process, so a write here would leak into every suite that follows.
func _guild() -> InstitutionDef:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	return def


## The authored guild as the CATALOG serves it — the same object `join` resolves, so a case
## driving it drives the production path rather than a copy the verb never sees.
func _authored_def() -> InstitutionDef:
	var def := InstitutionDefCatalog.instance().definition(AUTHORED_ID)
	assert_ne(def, null, "the authored guild is in the catalog")
	return def


## ## Publish two AUTHORED guilds through the MOD SEAM
##
## All three shipped guild `.tres` files author an EMPTY `standing_percent_stats`, so a
## guild's recognition is authored-but-unreachable in shipped content until somebody writes
## ids into it. Rather than edit shipped content from a suite — a leak with no owner — the
## content is written under the OS temp directory and pushed through `set_overlay_roots`.
## **This is the mod path itself, exercised from a test**: nothing in `game/src` was touched
## to make these appear, which is ADR 0184's headline claim measured rather than asserted.
##
## The two carry DIFFERENT authored caps (150 and 120), because the two-house case can only
## show that each institution's cap is its own if the caps disagree.
func _publish_authored_organizations() -> void:
	_overlay = OS.get_environment("TEMP").path_join(TEMP_DIR).path_join("guilds")
	if not DirAccess.dir_exists_absolute(_overlay):
		DirAccess.make_dir_recursive_absolute(_overlay)
	_write_guild(AUTHORED_ID, AUTHORED_SEAT, AUTHORED_FLOOR, 150, 40, 100)
	_write_guild(CHAPTER_ID, CHAPTER_SEAT, CHAPTER_FLOOR, 120, 30, 60)
	_republish()
	# The base family is still visible after the overlay, so the three shipped organizations
	# AND the two authored ones are both answerable — the merge is additive, never a
	# replacement of the whole family.
	var catalog := InstitutionDefCatalog.instance()
	assert_eq(catalog.is_loaded(), true, "the overlay merge is accepted")
	assert_eq(catalog.has(LANTERN_ID), true, "and the shipped family is still there")
	assert_eq(catalog.has(AUTHORED_ID), true, "alongside the authored organizations")
	assert_eq(
		String(catalog.owner_of(AUTHORED_ID)), OWNER, "which the merge attributes to the overlay"
	)


## Push the overlay row and drop the catalog, which is the ONLY way to make the family
## re-read what is on disk now. A `for` over nothing — one row — so there is no loop to bound.
func _republish() -> void:
	InstitutionDefCatalog.set_overlay_roots(
		[{"dir": _overlay, "owner": OWNER, "declared_overrides": [], "id_field": "id"}]
	)


## One authored `.tres`, written as TEXT rather than built as a `Resource` and saved: the
## family loads by scanning a directory, so a fixture that skipped the file would prove
## nothing about the path a mod actually takes. **The path is returned** so a case can delete
## the file and ask the catalog again — the honest form of the deleted-content case.
func _write_guild(
	id: StringName, seat: StringName, floor: StringName, cap: int, standing: int, cost: int
) -> String:
	var seat_id := String(seat)
	var floor_id := String(floor)
	var text := (
		'[gd_resource type="Resource" script_class="InstitutionDef" load_steps=5 format=3]\n\n'
		+ '[ext_resource type="Script" path="res://src/core/institution_def.gd" id="1_def"]\n'
		+ '[ext_resource type="Script" path="res://src/core/institution_position_def.gd" id="2"]\n\n'
		+ '[sub_resource type="Resource" id="seat"]\n'
		+ 'script = ExtResource("2")\n'
		+ 'id = &"%s"\n' % seat_id
		+ 'display_name = "Seat"\n'
		+ "capacity = 1\n"
		+ "duty_per_period = 2\n"
		+ "patronage_per_period = 2\n"
		+ 'standing_percent_stats = {"insight_gain": 0.0, "poise": 0.0}\n\n'
		+ '[sub_resource type="Resource" id="floor"]\n'
		+ 'script = ExtResource("2")\n'
		+ 'id = &"%s"\n' % floor_id
		+ 'display_name = "Floor"\n'
		+ "capacity = 0\n"
		+ "duty_per_period = 1\n"
		+ "patronage_per_period = 0\n"
		+ 'standing_percent_stats = {"insight_gain": 0.0, "poise": 0.0}\n\n'
		+ "[resource]\n"
		+ 'script = ExtResource("1_def")\n'
		+ 'kind = &"trading_guild"\n'
		+ 'capabilities = Array[StringName]([&"has_offices"])\n'
		+ 'id = &"%s"\n' % String(id)
		+ 'display_name = "Wiring Guild"\n'
		+ 'positions = Array[InstitutionPositionDef]([SubResource("seat"), SubResource("floor")])\n'
		+ 'top_position_id = &"%s"\n' % seat_id
		+ "standing_cap = %d\n" % cap
		+ "founder_standing = %d\n" % standing
		+ "founding_cost = %d\n" % cost
		+ "member_duty_per_period = 1\n"
	)
	var path := _overlay.path_join("%s.tres" % String(id))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_ne(file, null, "the authored '%s' is writable" % id)
	file.store_string(text)
	file.close()
	return path


## An actor with a funded founding pool and EVERY base attribute at one realm's authored
## power, so a derived stat reads non-zero for want of an investment the author never intended.
## Built from the real ladder, so a retune of the realm table cannot quietly break a ratio.
func _actor(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {})
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 9000.0))
	_born.append(actor)
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var realm: RealmDef = realms[0]
	var power := maxf(1.0, realm.power)
	for attribute in Stat.BASE_ATTRIBUTES:
		actor.stats.set_base(attribute, 10.0 * power)
	return actor


## Every value on `allowlist` before any grant, keyed by string id — the BEFORE a percent is
## measured against. A derived stat is recomputed from its attributes, so its BASE is not the
## value a percent rides.
func _sheet(actor: Actor, allowlist: Dictionary) -> Dictionary:
	var out := {}
	for stat_id in allowlist.keys():
		out[String(stat_id)] = actor.stats.derived(StringName(stat_id))
	return out


## A stat's value on an actor carrying no grant at all, read off the reference actor so the
## "nothing else moved" claim is measured against the same sheet.
func _bare(stat_id: StringName) -> float:
	return _reference.stats.derived(stat_id)


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it — this
## subject names the verbs it refuses inside its own class docs, so a raw `contains` scan
## would fail on those sentences while reading the code beside them as clean.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## Every public method name on the membership class, underscore-prefixed names dropped exactly
## as `tools/arch/enforce.py` drops them, so this suite and the gate count the same surface.
## `load()` is the one way in: GDScript refuses a non-static call on a class reference.
func _published() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load(MEMBERSHIP_FILE)
	if script == null:
		return out
	for method in script.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## Both the sheet and the whole modifier stack, so a climb or a wipe cannot hide behind a
## derived number that still reads plausibly — the exact shape of the 2/4/6/8/10/12 defect.
func _fingerprint(actor: Actor) -> Dictionary:
	var sheet := {}
	for stat_id in actor.stats.derived_all().keys():
		sheet[String(stat_id)] = actor.stats.derived(stat_id)
	var stack: Array = []
	for modifier in actor.stats._modifiers:
		stack.append("%s:%s:%f" % [modifier.source, modifier.stat, modifier.value])
	return {
		"sheet": sheet,
		"mods": actor.stats.modifier_count(),
		"own": _own_modifiers(actor),
		"stack": stack,
	}


## Every modifier on `actor` under this family's own namespace.
func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if InstitutionLedger.owns_source(InstitutionMembership.SOURCE_PREFIX, modifier.source):
			total += 1
	return total


## The percent one recognized id currently carries from this family, summed over every
## organization contributing it — the N-fold sum, read off the stack rather than recomputed.
func _own_percent(actor: Actor, stat_id: String) -> float:
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if String(modifier.stat) != stat_id:
			continue
		if not InstitutionLedger.owns_source(InstitutionMembership.SOURCE_PREFIX, modifier.source):
			continue
		total += float(modifier.value)
	return total
