extends TestCase

## BL-0797: **five of the six npc contract signals now have a production subscriber, and
## each one is proved to HEAR rather than merely to be connected.**
##
## ## Why this file exists at all
##
## The previous audit round's central finding was that a `.connect(` line is not a
## subscriber. ADR 0093's N2 correction says it outright: a guard satisfiable by a line
## nobody runs "is exactly the failure mode the previous audit round found." So this suite
## asserts the OBSERVABLE EFFECT for every signal — a production emit, then the
## subscriber's answer — and never the presence of a connection as its own evidence.
##
## The other half is the risk the work was warned about: *"a bounded log duplicating what
## `NpcApi.state()` already answers exactly. That is a second copy of the truth."* The
## owner chose to wire anyway, so avoiding that risk is the DESIGN constraint, and
## `test_the_ledger_holds_no_roster_and_no_bond_numbers` is the assertion that makes it
## mechanical rather than a promise in a docstring.
##
## ## Nothing here calls a handler directly
##
## Every test drives the signal through the production producer — `NpcApi.spawn`,
## `NpcApi.advance_stage`, `NpcApi.attach`, `SocialApi.apply_cause` — so a subscriber that
## is never wired cannot pass. `NpcLedger.tracked(...)` called by hand would prove the
## handler writes a row and prove nothing about the seam.
##
## ## What it writes, and why both resets are needed
##
## `NpcApi.attach` pins a process-wide player and `NpcEvents.shared()` is one bus for the
## whole process, so every facet this suite drives is cleared in BOTH `setup()` and
## `teardown()`. `reset()` clears all four facets in one call, which is why the bond
## ledger written here cannot leak into the next npc suite.

const ELDER := &"elder_wei"
## A tracked def in the shipped cast, used where the elder's ladder would also move a
## stage and pollute `NpcLedger.rows()`.
const SMITH := &"smith_bearcutter"
## An UNTRACKED def: it has no roster entry and leaves none behind, which is what makes
## it the interesting half for `npc_tracked`'s arrival log.
const DRIFTER := &"drifter"
const LOCATION := "mortal_plains"
## Causes read off `social_cause_catalog.gd` rather than invented, because
## `SocialApi.apply_cause` refuses `unknown_cause` and a suite that used a made-up id
## would go red on the catalog rather than on the seam.
const CAUSE_SMALL := &"helped_in_combat"
const CAUSE_LARGE := &"spared_in_combat"
## An institutional cause, so the "a sect id is a legal partner" claim is exercised with
## one that actually projects into `SocialState.regard`.
const CAUSE_SECT := &"sworn_to_sect"


func setup() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcCatalog.instance().reset()
	NpcCatalog.instance().load_authored()
	NpcApi._current_player = null
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcApi.attach(null)


# --- The connections exist at all ------------------------------------------------


## The mechanical half, stated once. Every subscriber hangs off the SHARED bus, which is
## the only bus `social/` can reach — a subscriber on a facade-owned instance would hear
## four signals and never the fifth.
func test_every_wired_signal_reaches_the_shared_bus_from_the_boot_seam() -> void:
	NpcBoot.install(null)
	var events := NpcApi.events()
	assert_eq(events, NpcEvents.shared(), "the bus is the shared one social/ publishes on")
	assert_eq(events.stage_advanced.is_connected(NpcLedger.advanced), true, "stage_advanced")
	assert_eq(events.npc_tracked.is_connected(NpcLedger.tracked), true, "npc_tracked")
	assert_eq(events.npc_restored.is_connected(NpcLedger.restored), true, "npc_restored")
	assert_eq(events.bond_changed.is_connected(NpcLedger.bond), true, "bond_changed")
	assert_eq(events.presence_changed.is_connected(NpcLedger.presence), true, "presence_changed")


## The sixth signal is NOT connected, and that is the decision rather than an oversight.
## BL-0797 asked for a real consumer or a deletion; this pins that nothing quietly grew
## one, so the reservation in `test_npc_event_contract.gd` stays honest.
func test_npc_transient_is_still_the_one_unwired_signal() -> void:
	NpcBoot.install(null)
	assert_eq(
		NpcApi.events().npc_transient.is_connected(NpcLedger.tracked),
		false,
		"npc_transient has no consumer, so nothing may connect to it yet"
	)
	assert_eq(
		NpcEvents.new().get_script().get_script_signal_list().size(),
		6,
		"the contract still declares six signals; BL-0797 wired five and deleted none"
	)


## A reused subscriber accumulates connections and fires N times, and `install` is
## idempotent and re-runs after every load. One arrival, however many boots happened.
func test_installing_many_times_still_connects_exactly_one_subscriber() -> void:
	var player := _player()
	for _boot in range(5):
		NpcBoot.install(player)
	NpcLedger.reset()
	NpcApi.spawn(SMITH)
	assert_eq(
		NpcLedger.arrival_count(),
		1,
		"five installs and one spawn produce ONE arrival row, not five"
	)


# --- npc_tracked ------------------------------------------------------------------


## A tracked spawn emits, the arrival log hears it, and the row carries the tier the
## roster gave the entry — primitives only, as ADR 0093 requires of every row.
func test_a_tracked_spawn_arrives_in_the_ledger_without_being_asked() -> void:
	var player := _player()
	NpcLedger.reset()
	var actor := NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	assert_ne(actor, null, "the smith was minted")
	assert_eq(NpcLedger.arrival_count(), 1, "the bus reached the subscriber unaided")
	var row: Dictionary = NpcLedger.arrivals()[0]
	assert_eq(String(row.get("npc_id", "")), String(SMITH), "primitives: who arrived")
	assert_ne(String(row.get("tier", "")), "", "and the tier the roster gave them")


## **The arrival log is an EDGE, not a roster.** `NpcApi.state()` keeps the truth; this
## records only the addition. An npc already on the roster is re-spawnable all session and
## `spawn` emits only when it CREATES the entry, so a second meeting writes no row — which
## is what separates this facet from `state().tracked_ids`.
func test_meeting_an_npc_twice_arrives_once_and_the_roster_stays_the_truth() -> void:
	var player := _player()
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	NpcApi.despawn(SMITH)
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	assert_eq(
		NpcLedger.arrival_count(),
		1,
		"a re-meeting is not an arrival; only the roster addition is recorded"
	)
	# And the roster itself still answers the broader question, uncapped and unbounded.
	assert_eq(
		(NpcApi.state(player).get("tracked_ids", []) as Array).has(String(SMITH)),
		true,
		"NpcApi.state() remains the authority on who is known, and the log does not shadow it"
	)


## An untracked npc leaves no roster entry, so `npc_tracked` never fires for one — and
## `arrival_count` therefore stays the answer to a roster question rather than drifting
## into a population count. The untracked case is what `npc_transient` announces instead.
func test_an_untracked_npc_writes_no_arrival_because_it_joins_no_roster() -> void:
	var player := _player()
	NpcLedger.reset()
	NpcApi.spawn(DRIFTER, NpcApi.ROLE_NPC, LOCATION)
	assert_eq(NpcLedger.arrival_count(), 0, "an untracked npc joins no roster, so nothing arrives")
	assert_eq(
		NpcLedger.seen(String(DRIFTER)),
		false,
		"and no signal announced it, so it is not in the seen set either"
	)


# --- npc_restored -----------------------------------------------------------------


## `attach` is the save-restore path and it emits one `npc_restored` per roster entry.
## The subscriber hears it and reports a CENSUS — how big was the roster this process came
## back up with — which is a count no read model is asked for at boot.
func test_attaching_after_a_save_reports_the_roster_size_to_the_subscriber() -> void:
	var player := _player()
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	NpcApi.spawn(ELDER, NpcApi.ROLE_NPC, LOCATION)
	# Round-trip the roster through the save payload the way a load would, then attach a
	# FRESH actor built from it. This is the migration-shaped question: how big was it?
	var loaded := Actor.from_dict(player.to_dict())
	NpcLedger.reset()
	NpcBoot.install(loaded)
	assert_eq(NpcLedger.restored_count(), 2, "the subscriber heard both restores and counts them")
	assert_eq(
		NpcLedger.restored_summary().get("count", 0),
		2,
		"and the envelope answers the same question in one call"
	)
	assert_eq(
		NpcLedger.restored_ids().has(String(SMITH)), true, "naming the smith, who is on the roster"
	)


## **`attach` emits on EVERY call, so a set is the honest shape and a log would lie.**
## `install` calls `attach` at boot AND after every load, so a migration tool reading an
## ordered restore log would see the same npc "restored" three times in one session. The
## count is therefore asserted flat across three attaches, which is the property a log
## would fail on its first re-attach.
func test_re_attach_does_not_count_one_npc_as_three_restores() -> void:
	var player := _player()
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	NpcLedger.reset()
	NpcApi.attach(player)
	NpcApi.attach(player)
	NpcApi.attach(player)
	assert_eq(
		NpcLedger.restored_count(),
		1,
		"three attaches of a one-npc roster is ONE npc, not three restore events"
	)


# --- bond_changed -----------------------------------------------------------------


## `social/` publishes `bond_changed` on the shared bus because it may not depend on
## `npc/`. This is the whole point of the bus living in `contracts/`: the subscriber hears
## a fact announced by a module that cannot reach the npc facade at all.
func test_a_social_cause_reaches_the_npc_subscribers_without_social_knowing_npc() -> void:
	var player := _player()
	NpcLedger.reset()
	var outcome := SocialApi.apply_cause(player, SMITH, CAUSE_SMALL, 1.0)
	assert_eq(bool(outcome.get("ok", false)), true, "the cause applied: %s" % str(outcome))
	assert_eq(NpcLedger.bond_edge_total(), 1, "the bus reached an app/ subscriber")
	assert_eq(
		NpcLedger.last_cause_for(String(SMITH)),
		String(CAUSE_SMALL),
		"and the cause id is readable, which is what ADR 0093's anti-farm rule publishes"
	)


## **Why the edge is not a duplicate of the bond.** `SocialApi.summary` publishes what a
## bond IS; no read model publishes which causes moved it, or in what order. So the row is
## `{partner, cause, ordinal}` and the newest cause wins — a question only the announcement
## order can answer.
func test_the_bond_log_records_the_cause_and_the_order_the_ledger_does_not_keep() -> void:
	var player := _player()
	NpcLedger.reset()
	SocialApi.apply_cause(player, SMITH, CAUSE_SMALL, 1.0)
	SocialApi.apply_cause(player, SMITH, CAUSE_LARGE, 1.0)
	assert_eq(
		NpcLedger.last_cause_for(String(SMITH)),
		String(CAUSE_LARGE),
		"the NEWEST announced cause wins, which summary() cannot tell you"
	)
	var edges: Array[Dictionary] = NpcLedger.bond_edges()
	assert_eq(edges.size(), 2, "both edges are held")
	assert_eq(int(edges[0].get("ordinal", -1)), 1, "newest first, carrying its order")
	assert_eq(
		String(edges[1].get("cause", "")),
		String(CAUSE_SMALL),
		"and the earlier one is still readable"
	)
	# The ledger's own answer is unaffected by, and unduplicated by, the log.
	assert_ne(
		SocialApi.summary(player).get("bonds", {}).has(String(SMITH)),
		false,
		"the bond itself lives in social/ and is still published there"
	)


## An institutional partner — a sect, not a person — reaches here too, because
## `apply_cause` treats both the same way. The subscriber records the partner id it was
## given and does NOT care which kind it is, which is why it needs no npc vocabulary.
func test_an_institution_bond_also_reaches_the_subscriber_as_a_plain_partner_id() -> void:
	var player := _player()
	NpcLedger.reset()
	var outcome := SocialApi.apply_cause(player, &"jade_court", CAUSE_SECT, 1.0)
	assert_eq(bool(outcome.get("ok", false)), true, "a sect is a legal partner: %s" % str(outcome))
	assert_eq(
		NpcLedger.last_cause_for("jade_court"),
		String(CAUSE_SECT),
		"a sect id is recorded as the partner it is; no npc-side type is needed"
	)
	# And `social/` still owns the regard projection — the log did not take it over.
	assert_ne(
		SocialApi.summary(player).get("regard", {}).has("jade_court"),
		false,
		"regard is still social/'s read model; the subscriber added only the cause edge"
	)


# --- presence_changed -------------------------------------------------------------


## `advance_stage` to a terminal stage emits `presence_changed(RETIRED)`, and this is the
## join no read model offers: "this npc has left". `presence_here` reports who is HERE
## right now and never that somebody was announced and is no longer standing anywhere.
func test_a_retirement_reaches_the_subscriber_as_a_roster_membership_edge() -> void:
	var player := _player()
	NpcLedger.reset()
	# **Track the elder first.** `advance_stage` refuses `unknown_npc` for an npc with no
	# roster entry, so a bare `advance_stage(ELDER, &"retired")` is refused before the bus
	# is reached — and it returns `ok`, silently, because the equality short-circuit at
	# `api.gd:315` compares two indices of -1. The elder has to MEET the smith for this to
	# be the retirement test rather than a no-op test.
	NpcApi.spawn(ELDER, NpcApi.ROLE_NPC, LOCATION)
	NpcLedger.reset()
	assert_eq(NpcLedger.seen(String(ELDER)), false, "nobody announced the elder yet")
	NpcApi.advance_stage(ELDER, &"retired", "test:presence")
	assert_eq(
		NpcLedger.presence_seen(String(ELDER)),
		true,
		"the roster no longer contains him and the subscriber knows he left"
	)


## **This is the facet most at risk of being the recorded risk, so the exclusion is
## asserted.** The ledger holds no presence table at all: `presence_changed` adds the npc
## to the seen SET and stores nothing else. A presence VALUE is never kept, so nothing here
## can contradict `NpcApi.presence_here()`.
func test_the_ledger_holds_no_roster_and_no_bond_numbers() -> void:
	var player := _player()
	NpcLedger.reset()
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	NpcApi.advance_stage(ELDER, &"sworn_servant", "test:no_copy")
	SocialApi.apply_cause(player, SMITH, CAUSE_SMALL, 1.0)
	# Every string this file retains is an id or an authored cause. No numeric bond or
	# roster value appears on ANY facet, which is what makes it impossible for it to be a
	# second writer of either.
	#
	# `tier` is exempt because it is a CLASS the roster handed over at the moment of
	# arrival, not a value about the npc: the arrivals facet is the one facet that
	# answers "what was announced", and the tier is part of that announcement. The stage
	# facet bans `stage_id` because a stage is a fact about the npc NOW, which
	# `NpcApi.state` owns; `test_a_tracked_spawn_arrives_in_the_ledger_without_being_asked`
	# pins the arrival row's tier as deliberately present.
	var banned := ["standing", "trust", "stage_id", "presence", "payload"]
	for row: Dictionary in NpcLedger.arrivals() + NpcLedger.rows() + NpcLedger.bond_edges():
		for key in banned:
			assert_eq(
				row.has(key),
				false,
				"no row carries '%s', so this file cannot be a second copy of a ledger" % key
			)
	# And the restored facet is ids and a count, nothing that describes an npc.
	var restored: Dictionary = NpcLedger.restored_summary()
	assert_eq(restored.keys().has("count"), true, "a count of the restore, and nothing else")
	assert_eq(restored.keys().has("entries"), false, "never a per-npc row")


## The truth still belongs to the read models: after every signal above, `state()` and
## `presence_here()` answer the current questions, and the ledger answers none of them.
## Asserted as a pair so "the ledger has a copy" cannot pass by the read models going
## quiet.
func test_the_read_models_still_answer_what_the_ledger_does_not() -> void:
	var player := _player()
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, LOCATION)
	# Who is here: the registry, read live.
	assert_eq(
		int(NpcApi.presence_here(LOCATION).get("count", -1)),
		1,
		"presence_here answers who is here, which the ledger never tries to answer"
	)
	# Who do I know: the roster, read on demand.
	assert_eq(
		(NpcApi.state(player).get("tracked_ids", []) as Array).size(),
		1,
		"state() answers who is known, unbounded and uncapped"
	)
	# What a bond is: social's own read model, untouched by the subscriber.
	SocialApi.apply_cause(player, SMITH, CAUSE_SMALL, 1.0)
	var entry := SocialApi.bond_entry(player, SMITH)
	assert_eq(bool(entry.get("present", false)), true, "social/ still publishes the bond")
	assert_ne(
		NpcLedger.last_cause_for(String(SMITH)), "", "...and the ledger only adds the cause edge"
	)


# --- The bounds -------------------------------------------------------------------


## Every facet drops its oldest row at a NAMED constant, which is what keeps `app/` a
## wiring root rather than the stateful table `tools/arch/rules.py` rejects. Driven
## through the production signal for each facet, so the bound is a property of the
## SUBSCRIBER rather than of a loop in this file.
func test_every_facet_drops_its_oldest_row_at_a_named_bound() -> void:
	var events := NpcEvents.shared()
	# A distinct id per emission, so "the oldest survivor" is identifiable.
	for index in range(NpcLedger.MAX_ROWS + 5):
		events.stage_advanced.emit(String(ELDER), &"sworn_servant", "test:bound_%02d" % index)
	for index in range(NpcLedger.MAX_ARRIVALS + 5):
		events.npc_tracked.emit("arriver_%02d" % index, &"minor")
	for index in range(NpcLedger.MAX_CAUSES + 5):
		events.bond_changed.emit("partner_%02d" % index, CAUSE_SMALL)
	assert_eq(NpcLedger.count(), NpcLedger.MAX_ROWS, "the stage trail is capped")
	assert_eq(NpcLedger.arrival_count(), NpcLedger.MAX_ARRIVALS, "the arrival log is capped")
	assert_eq(NpcLedger.bond_edge_count(), NpcLedger.MAX_CAUSES, "the bond edge log is capped")
	# The OLDEST SURVIVOR is the newest row past the bound, not emission zero: a cap that
	# kept the wrong end would leave `bound_00` at the bottom and fail here.
	assert_eq(
		String(NpcLedger.rows()[NpcLedger.rows().size() - 1].get("source", "")),
		"test:bound_%02d" % (NpcLedger.MAX_ROWS + 5 - NpcLedger.MAX_ROWS),
		"the oldest surviving stage row is the oldest one still inside the bound"
	)
	assert_eq(
		String(NpcLedger.arrivals()[NpcLedger.arrivals().size() - 1].get("npc_id", "")),
		"arriver_%02d" % (NpcLedger.MAX_ARRIVALS + 5 - NpcLedger.MAX_ARRIVALS),
		"and the arrival log drops the same end"
	)


## The uncapped total keeps moving past the capped table. A counter that counted the
## held rows would freeze at the bound and read as "nothing has happened since", which is
## the failure a bounded log in `app/` invites.
func test_the_uncapped_bond_total_keeps_counting_past_the_held_bound() -> void:
	var events := NpcEvents.shared()
	var emitted: int = NpcLedger.MAX_CAUSES + 9
	for index in range(emitted):
		events.bond_changed.emit("partner_%02d" % index, CAUSE_SMALL)
	assert_eq(NpcLedger.bond_edge_total(), emitted, "the total counts every edge observed")
	assert_eq(
		NpcLedger.bond_edge_count(), NpcLedger.MAX_CAUSES, "while the held table stays bounded"
	)


## One `reset()` clears all four facets. A reset that forgot one would let the next suite
## read an arrival or a bond edge it did not write — the cross-suite leak the process-wide
## bus invites, and the reason `setup()` and `teardown()` both call it.
func test_one_reset_clears_every_facet() -> void:
	var events := NpcEvents.shared()
	events.stage_advanced.emit(String(ELDER), &"sworn_servant", "test:reset")
	events.npc_tracked.emit("arriver", &"minor")
	events.npc_restored.emit("restored_one", &"major", &"gatekeeper", true)
	events.bond_changed.emit("partner", CAUSE_SMALL)
	events.presence_changed.emit("present_one", &"retired")
	NpcLedger.reset()
	assert_eq(NpcLedger.count(), 0, "the stage trail is cleared")
	assert_eq(NpcLedger.arrival_count(), 0, "the arrival log is cleared")
	assert_eq(NpcLedger.restored_count(), 0, "the restore census is cleared")
	assert_eq(NpcLedger.bond_edge_total(), 0, "the bond total is cleared, not just the table")
	assert_eq(NpcLedger.seen_ids().size(), 0, "and so is the seen set every facet shares")
	assert_eq(NpcLedger.bond_edge_count(), 0, "and the held bond table")


# --- Fixtures ---------------------------------------------------------------------


## A player with the roster bound and the catalogue installed, the way the composition
## root installs one (`NpcBoot`, not a raw `set_minter`) so the seams under test are the
## production ones. `NpcBoot.install` also installs the five subscribers, so no test here
## has to connect anything by hand.
func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	NpcBoot.install(actor)
	return actor
