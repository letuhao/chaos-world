extends TestCase

## ## The npc event contract is a PROMISE, and a promise nothing keeps is a rumour
##
## `contracts/npc_events.gd` is a published seam (ADR 0093). Every signal on it is read by
## a consumer as *the npc module will tell me when this happens* — and the first audit
## wave found the seventh, `decision_answered`, had **no producer and no subscriber at
## all**. It was the seam for "an npc asks the player a question and the player answers",
## a concept the original design review rejected as ceremony; the signal outlived the
## rejection. Every agent that touched this contract had to grep the tree before they
## could conclude the signal was dead, and it survived several audits precisely because
## nothing made "is this reachable?" a testable question.
##
## So this file makes it one. It is a CENSUS with two rules, and the rules are stated here
## as narrowly as they are enforced — because **a guard that overclaims is worse than a
## narrow one**: a reader who discovers a check cannot fail stops reading the rest of it.
##
## ## Rule 1 — the EMITTER OWNS THE CONTRACT: it lives under `src/modules/`
##
## Every signal declared on `NpcEvents` must be emitted from a file under
## `res://src/modules/`. `app/` is where SUBSCRIBERS live (ADR 0093 line 21: "a subscriber
## connects from its own boot function, which `app/` calls") and `ui/` is where panels
## read. A module that owns a fact announces it; a composition root does not. `bond_changed`
## is emitted by `social/api.gd` and not `npc/api.gd`, which is correct — `npc_events.gd`
## says so and explains why — and `social/` is still under `src/modules/`.
##
## ## Rule 2 — every signal is OBSERVED, or the gap is WRITTEN DOWN
##
## Every signal must have a production `.connect(` under `res://src`, **or** an entry in
## [constant RESERVATIONS] carrying a non-blank reason. A producer with no subscriber is a
## legitimate half-built seam; a producer with no subscriber and no written reason is an
## accident, and the reason field is where the next reader argues with it.
##
## ## ## WHY RULE 1 IS NOT "AND THE PRODUCER RUNS" (audit N2 — this is the honest limit)
##
## An earlier version of this guard asked only whether `<name>.emit(` appeared anywhere
## under `res://src`, and the audit answered it with a line in dead code: `signal
## npc_introduced` declared, its only emit placed inside `NpcLedger.rows()` — a function
## **no production file calls** — and `--suite test_npc` returned `509 passed, 0 failed`.
##
## The brief offered a stronger repair (option a): compute a call-graph reachability set
## from a production entry point and require the emitting function to be in it. **That was
## built, measured against this tree, and rejected — not for effort but because it does not
## survive contact with the real code.** Measured before any of it was written:
##
##   - `NpcApi.advance_stage` — which emits `stage_advanced`, the ONE signal with a real
##     production subscriber — has **no qualified call site anywhere in `src/`**. It is
##     reached only by a bare `advance_stage(...)` at `npc/api.gd:360` inside `tally`, and
##     `tally` reaches production solely through the INJECTED `Callable(NpcApi, "tally")` at
##     `app/npc_boot.gd:61`. Every static shape that resolves that indirection — bare call,
##     `Class.method`, name literal — reports `stage_advanced`'s own producer as dead.
##   - `NpcLedger.rows` is the mirror image: the bare name `rows` IS called from another
##     file (`auction_ledger.gd:123`), so a name-keyed rule calls the auditor's dead
##     function REACHABLE while a receiver-aware rule calls the real producer DEAD.
##
## The two candidate approximations therefore each fail on a different true fact, and a
## guard that reported those backwards would be worse than the honest narrow one. This file
## takes **option (b)/(c): the emit-scan is dropped and rule 1 + rule 2 replace it.**
##
## **What this file claims, exactly:** every signal on the contract is published by the
## layer that owns it, and every one is either observed by production code or carries a
## written reason saying it is not yet. **What it does not claim:** that any particular emit
## executes on any particular run. A function under `src/modules/` that nothing calls can
## still satisfy rule 1 — the seam is real, the producer is wired, and only a coverage run
## would say more. That residual hole is stated here rather than papered over, and it is
## much smaller than the one this guard was written to close: the audit's dead emit lived
## in `app/`, which is where a subscriber belongs and a producer does not, so rule 1
## refuses it by construction.
##
## ## The reservation list, and why it now has five entries rather than none
##
## A reservation is "this signal is published on purpose and nothing observes it yet" — a
## licence to carry a promise, with the promise written down. It holds no BLANK entry by
## rule 2 and no STALE name, by the test at the bottom of this file.
##
## Five of the six signals are reserved, and every reason is the same measured fact: they
## have a producer under `src/modules/` and **no `.connect(` anywhere under `res://src`**.
## `stage_advanced` is the only one with a subscriber (`app/npc_boot.gd:67`, `NpcLedger`).
## Recording that as five reservations with reasons is the honest bookkeeping — the
## alternative, a blanket "no subscriber required" exemption, is exactly the overclaim this
## audit exists to remove.
##
## ## The one candidate that was REFUSED rather than reserved
##
## `decision_answered` is the signal the elder's ladder *could* use — BL-0745
## (`shared_brotherhood`, the only cause reaching SWORN) needs the player to offer a
## brotherhood and the npc to be able to refuse it. That gap is real and it is still open.
## But BL-0745 is recorded as **blocked on a product ruling only the repo owner can make**
## (what player act offers a brotherhood, what refusal costs, whether it is mutual), and
## a test constant is not the place to pre-empt that ruling. Listing the signal here would
## have been a back door around it: a published, blessed seam waiting for someone to bolt
## a producer onto it. The gap was closed instead (F2 → BL-0793), and the trigger that
## would reopen it is written in `npc_events.gd` and in ADR 0093 line 28 — a second
## consumer must genuinely *ask a question and wait for an answer*.
##
## ## Why a source scan and not a runtime observation
##
## Emitting each signal at runtime would need a producer to exist, which is the thing being
## tested. So a producer is found by reading the tree. `res://tests` deliberately does NOT
## count — a test that emits a signal to prove it works is not production, and letting it
## count would let this suite justify itself.
##
## The producer is matched as the literal `.name.emit(`, which is the only shape the tree
## writes. Comments AND string literals are stripped first, and both must be: `npc_events.gd`
## NAMES `decision_answered` while explaining why it is gone, so a line that only
## documents a signal must never be read as emitting it. The FIRST test below reads a known
## producer back, so a scan that silently matched nothing cannot read as six green "is it
## dead" answers.

## Signals published on purpose that production code does not yet observe, each with the
## reason it may exist. A `Dictionary` rather than an array because a reservation WITHOUT an
## argument is a licence with nothing attached, and rule 2 exists to refuse exactly that.
## Blank entries and blank reasons are both test failures.
##
## ## WHY THIS HOLDS ONE ENTRY AND NOT FIVE (BL-0797 — the count changed deliberately)
##
## It held five until the repo owner reversed the ruling that produced them. Four were
## wired to a real subscriber in `game/src/app/npc_ledger.gd` (connected from
## `app/npc_boot.gd:_install_event_seams`), and **their reservations were removed in the
## same change** — leaving a reservation behind a live subscriber is the exact drift
## BL-0797 warns about, where this guard stays green and ADR 0093 goes stale.
##
## **`npc_transient` is the one that stays reserved.** It is the only signal on this
## contract with no consumer anywhere in the tree. The owner asked for either a named real
## consumer or a recommendation to delete the signal, and explicitly refused an invented
## one. No real consumer exists — an untracked npc leaves no roster entry by ADR 0092 and
## `NpcApi.presence_here` already reports every live body, tracked or not — so a log here
## would be the strictly worse copy of a read model that this audit exists to prevent.
## The owner has NOT ruled on deleting it, so it stays reserved rather than deleted, which
## is the one honest difference from `decision_answered` (BL-0793) whose ruling is closed.
const RESERVATIONS: Dictionary = {
	"npc_transient":
	(
		"npc/api.gd:195 emits it from spawn() on the untracked branch. BL-0797 asked for "
		+ "either a named real consumer or a recommendation to delete this signal, and no "
		+ "real consumer exists: an untracked npc has no roster entry by ADR 0092, leaves "
		+ "none behind when it leaves, and NpcApi.presence_here already reports every live "
		+ "body tracked or not, so a bounded log here would be a strictly worse copy of "
		+ "that read model. The producer is real and stays; the owner has not ruled on "
		+ "deleting the signal, so it is reserved rather than deleted."
	),
}

const SRC_ROOT := "res://src"
## The layer rule 1 requires an emitter to live in. `app/` and `ui/` are excluded ON
## PURPOSE: they are where subscribers and readers live, and an announce from there is a
## composition root speaking for a module.
const MODULES_ROOT := "res://src/modules/"

## The six facts the contract exists for, each with the verb that publishes it. Written out
## rather than derived, because a census that checks only its own discovery reports green
## when it has discovered nothing.
const KNOWN_PRODUCERS := {
	"bond_changed": "src/modules/social/api.gd:111",
	"npc_restored": "src/modules/npc/api.gd:96",
	"npc_tracked": "src/modules/npc/api.gd:175",
	"npc_transient": "src/modules/npc/api.gd:195",
	"presence_changed": "src/modules/npc/api.gd:287",
	"stage_advanced": "src/modules/npc/api.gd:327",
}

## A complete double-quoted literal, escapes included. Built by [method _compile_patterns]
## on first use rather than in a field initialiser, which would run once per instance.
var _string_re: RegEx


## ## The positive control, and why it is a test rather than a comment
##
## A census that finds no producers anywhere is indistinguishable, assertion by assertion,
## from a census that correctly finds no producers. Both print "this signal is dead". So
## the first assertion is that the scan CAN find one: `stage_advanced` has been emitted by
## `npc/api.gd` since ADR 0093 shipped. If that ever goes red, the other answers in this
## file are measuring nothing and the tree walk has broken.
func test_the_scan_can_still_find_a_real_producer() -> void:
	assert_ne(_gdscript_files(SRC_ROOT).size(), 0, "the production tree is walkable at all")
	assert_eq(
		_emitting_files("stage_advanced"),
		["res://src/modules/npc/api.gd"],
		"stage_advanced is emitted by npc/api.gd, so a dead reading here means the scan broke"
	)


## ## Rule 1, asserted on its own so a failure names WHICH half failed.
##
## A signal with no producer at all and a signal whose producer lives in the wrong layer
## are different bugs with different fixes, so they are two assertions rather than one
## boolean. The auditor's mutation — an emit inside `app/npc_ledger.gd rows()` — fails the
## SECOND one and names the path the scan found.
func test_every_declared_signal_is_emitted_by_a_module_that_owns_it() -> void:
	var declared := _declared_signals()
	# A live declaration list is the precondition. If this reads zero, the census is
	# measuring nothing and would pass green over an empty contract.
	assert_ne(declared.size(), 0, "NpcEvents declares signals at all")
	for name in declared:
		var files := _emitting_files(name)
		assert_ne(
			files.size(),
			0,
			(
				(
					"%s is declared on NpcEvents but emitted by no production code under "
					+ "res://src; emit it, or reserve it with a written reason"
				)
				% name
			)
		)
		if files.is_empty():
			continue
		var in_modules: Array[String] = []
		for path in files:
			if path.begins_with(MODULES_ROOT):
				in_modules.append(path)
		assert_ne(
			in_modules.size(),
			0,
			(
				(
					"%s is emitted only from %s, which is outside src/modules/. A module that "
					+ "owns a contract signal announces it; app/ is where SUBSCRIBERS live "
					+ "(ADR 0093 line 21), so an announce from there is a composition root "
					+ "speaking for a module it does not own."
				)
				% [name, str(files)]
			)
		)


## ## Rule 2, asserted on its own: observed, or written down.
##
## This is the half that was absent before. Only `stage_advanced` has a subscriber today,
## so the other five are RESERVED rather than quietly exempted — each with the measured
## fact that no `.connect(` exists for it written into the constant.
func test_every_declared_signal_has_a_production_subscriber_or_a_written_reservation() -> void:
	for name in _declared_signals():
		if RESERVATIONS.has(name):
			continue
		assert_eq(
			_has_production_subscriber(name),
			true,
			(
				"%s has neither a production .connect( under res://src nor a RESERVATIONS " % name
				+ "entry — add a subscriber, or record the gap with a reason somebody can argue with"
			)
		)


## The reservation list is not a place to hide, and it is not a place to be vague.
##
## A name left behind after its signal was deleted is a quieter version of the same drift:
## the next agent reads the licence, believes the contract is bigger than it is, and wires
## to something absent. A BLANK reason is the same drift wearing a form: a licence with no
## argument, which is indistinguishable from the accident rule 2 exists to catch.
func test_every_reservation_names_a_real_signal_and_carries_a_reason() -> void:
	var declared := _declared_signals()
	assert_ne(RESERVATIONS.has(""), true, "RESERVATIONS holds no blank entry")
	# Asserted unconditionally so the reasons loop is never a loop over nothing, and so a
	# future edit that empties the constant is visible here rather than in the census.
	assert_ne(RESERVATIONS.size(), 0, "the unobserved signal is recorded, not exempted")
	for name in RESERVATIONS:
		assert_ne(
			name in declared,
			false,
			"RESERVATIONS names '%s', which NpcEvents does not declare" % name
		)
		var reason := String(RESERVATIONS[name]).strip_edges()
		assert_ne(reason, "", "the reservation for '%s' carries a written reason" % name)
		assert_eq(
			reason.length() >= 20,
			true,
			"the reservation for '%s' says WHY, not merely that it is reserved: %s" % [name, reason]
		)


## ## The rule BL-0797's own `next` field warns about, made mechanical
##
## That field said it: the entry "cannot be closed by adding a consumer - doing so is a
## DESIGN decision and needs the reservation removed in the same commit, or the guard still
## passes but the ADR goes stale." **Rule 2 cannot catch that, by construction** — it is
## satisfied by a subscriber OR a reservation, so a signal carrying BOTH reads as observed
## and every pre-existing assertion stays green while ADR 0093's census describes a tree
## that no longer exists.
##
## So the stale half is asserted separately. A reservation naming a signal production code
## connects to is a licence describing a gap that has since been closed.
func test_no_reservation_survives_a_subscriber_for_the_same_signal() -> void:
	for name in RESERVATIONS:
		assert_eq(
			_has_production_subscriber(name),
			false,
			(
				(
					"'%s' is BOTH reserved and subscribed. The reservation is now false: "
					+ "remove it, so this census describes the tree that exists."
				)
				% name
			)
		)


## ## And the honest limit: a `.connect(` is not yet an effect
##
## Rule 2 counts `.connect(` lines. It cannot see that a subscriber whose only job is
## re-recording what `NpcApi.state()` / `presence_here()` already answers is "a second
## copy of the truth" — ADR 0093's own recorded risk, and the reason this file may not be
## read as saying the seam is closed merely because five signals are now observed. The
## observable half is enforced where an emit can actually be driven:
## `tests/app/test_npc_event_subscribers.gd` performs each production emit and reads the
## subscriber's ANSWER, so a handler that connects and does nothing is red there.


## The six facts the contract exists for are still on it, and each still has its producer.
## This is the shape half of the guard: it NAMES every signal, so losing a real fact is as
## loud as adding a dead one. A seventh signal with a real producer passes this test — the
## bound is a floor, not an equality, so a legitimate addition does not fight this line.
func test_the_contract_still_publishes_the_six_facts_it_exists_for() -> void:
	var declared := _declared_signals()
	for name in KNOWN_PRODUCERS:
		assert_ne(name in declared, false, "NpcEvents still publishes %s" % name)
		assert_ne(
			_emitting_files(name).size(),
			0,
			"%s still has its producer at %s" % [name, KNOWN_PRODUCERS[name]]
		)
	assert_ne(
		declared.size() < KNOWN_PRODUCERS.size(),
		true,
		"the six named facts are all present on the contract"
	)


## The signal the first audit removed must stay removed. The census above already fails if
## it comes back unemitted; this fails if it comes back *emitted* — a producer bolted onto it
## from under BL-0745's open product ruling, which is the one way this hole could be
## closed by accident. The replacement is written in `npc_events.gd` and ADR 0093 line 28.
func test_the_removed_decision_signal_stays_removed() -> void:
	var declared := _declared_signals()
	assert_ne(
		"decision_answered" in declared,
		true,
		"decision_answered is refused by ADR 0093 line 28; its gap is a product ruling"
	)
	assert_ne(
		RESERVATIONS.has("decision_answered"),
		true,
		"decision_answered must not be reserved either; BL-0745 is not ours to pre-empt"
	)


## ## The scan


## The production files that emit `name`, in walk order. Comments and string literals are
## stripped before matching, because a `.emit(` inside a quoted line is a sentence.
func _emitting_files(name: String) -> Array[String]:
	var needle := ".%s.emit(" % name
	var out: Array[String] = []
	for path in _gdscript_files(SRC_ROOT):
		for line in _code_lines(path):
			if line.find(needle) < 0:
				continue
			if not out.has(path):
				out.append(path)
	return out


## Whether any production file under `res://src` connects to `name`.
func _has_production_subscriber(name: String) -> bool:
	var needle := ".%s.connect(" % name
	for path in _gdscript_files(SRC_ROOT):
		for line in _code_lines(path):
			if line.find(needle) >= 0:
				return true
	return false


## The comment-stripped, string-blanked lines of one script, or nothing if it cannot be read.
##
## Blanking strings as well as comments matters more than it looks: both needles are
## substrings, and the tree's docstrings quote call shapes verbatim. `npc_events.gd` names
## `decision_answered` in prose and `npc_boot.gd` quotes the `.connect(` shape it writes, so
## a comment-only strip would let a sentence satisfy the census.
func _code_lines(path: String) -> Array[String]:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []
	var out: Array[String] = []
	for line in text.split("\n"):
		out.append(_blank_strings(line.split("#")[0]))
	return out


## Replace every `"…"` pair with `""`, so an identifier inside a literal is neither an emit
## nor a subscribe. `RegEx` rather than a character loop: this runs once per line of the
## whole production tree, for every signal the census asks about, and it is the only
## bounded-shape search in the file.
func _blank_strings(line: String) -> String:
	if not line.contains('"'):
		return line
	_string_re.search(line)
	return _string_re.sub(line, '""', true)


func _compile_patterns() -> void:
	if _string_re != null:
		return
	_string_re = RegEx.new()
	_string_re.compile('"(?:[^"\\\\]|\\\\.)*"')


## Every `.gd` under `root`, recursively.
##
## The same `DirAccess` walk `tests/arch_rules/test_fact_ledger_writers.gd` performs: a
## `while` over `DirAccess` terminating on the empty sentinel is the one drain shape
## `test_no_unbounded_wait.gd` accepts, and the collected list is then walked with a
## `for` over a finite range.
func _gdscript_files(root: String) -> Array[String]:
	_compile_patterns()
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Every signal the `NpcEvents` SCRIPT declares, by name.
##
## `get_script_signal_list()` rather than `get_signal_list()`: the latter reports the
## instance's inherited signals too, so `Object`'s own would be read as contract members
## nobody may produce. And the script's list rather than a hand-maintained copy of the
## `signal` lines, because a second copy of the declaration list is exactly the
## duplication that let `decision_answered` drift out of the file it claimed to describe.
func _declared_signals() -> Array[String]:
	var names: Array[String] = []
	for entry in NpcEvents.new().get_script().get_script_signal_list():
		names.append(String(entry.name))
	return names
