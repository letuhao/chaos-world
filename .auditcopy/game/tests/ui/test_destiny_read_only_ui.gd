extends TestCase

## ## The gap, and why it is a GAP rather than a missing feature
##
## ADR 0065 makes fate **earned, never chosen, never equipped, never removed**, and
## `game/src/ui/screens/destiny_screen.gd` honours it today: it renders
## `DestinyApi.summary(actor)`, subscribes to `DestinyApi.events()`, and publishes no
## picker. A grep of `game/src/ui/**` finds the only two `DestinyApi` calls in
## executable code, and both are reads.
##
## But nothing MAKES that true. Three holes, each individually sufficient to let a
## picker ship:
##
##  1. `tools/arch/rules.py` lists `destiny` in `UI_MODULES` with an EMPTY
##     restriction list, so `ui/` may legally reach `DestinyApi` at all.
##  2. `earn_fate` / `earn_destiny` / `record` are PUBLIC methods on the SAME facade
##     the codex reads `summary()` and `events()` from, so a screen that wants to
##     write has exactly one legal way in, and nothing says it may not.
##  3. `tests/ui/test_ui_conventions.gd` checks the UI program's other invariants
##     (`theme_override`, `@onready`, the facade cap) but nothing checked for a WRITE.
##
## Read-only under `ui/` is therefore **convention only** — true today, unguarded,
## and one commit away from a `picker.gd` that grants itself destinies. This file is
## the mechanical guard.
##
## ## WHY the ALLOWED / FORBIDDEN split is the right one
##
## A screen's job is to TELL a player what the world has already decided, and a
## game-system module's job is to DECIDE. That single distinction is what the two
## lists encode, and it is not invented here: it is ADR 0134 §1's own table of
## `DestinyApi`'s twelve verbs, which classifies every one of them by kind —
## `mutate`, `read`, `evaluate`, `lifecycle`.
##
##   ALLOWED — `summary`, `events`, `gate`, `has_fate`, `has_destiny`, `state`,
##             `destinies`, `fates`, `attach`
##
##     Every one is a verb that **changes nothing**. `summary()` is the screen seam
##     (ADR 0134: "`state()` is the save seam, `summary()` is the screen seam, and
##     `gate()` is the content seam"), `events()` is how a consumer OBSERVES an earn
##     rather than causing one, and `gate()` evaluates authored data and writes only a
##     telemetry signal — ADR 0136 records `gate_failed` as firing once per
##     EVALUATION, so it is explicitly not a player-facing notice. A screen that
##     called all nine is still a codex: it reports, it announces, it explains why a
##     destiny has not arrived, and it has written no ledger entry.
##
##   FORBIDDEN — `earn_fate`, `earn_destiny`, `record`
##
##     These are the `mutate` rows of the same ADR 0134 table, and that same table
##     says of them: "**Write verbs belong to the owner of the moment, never to
##     `destiny`.**" A fate is a consequence of a deed a SYSTEM decided happened — a
##     duel the combat module decided, a house the clan module registered, a term the
##     sect module discharged. A screen that calls `earn_fate` is not reporting the
##     world's memory; it is **appending to it**, from a widget, on behalf of whoever
##     pressed what.
##
##     That is the exact shape ADR 0065 exists to forbid, and the reason this is a
##     SOURCE-SCAN rather than a runtime check is the irreversibility: the grant lands
##     in the ledger and in the save **forever**. By the time a call has executed, the
##     harm is already written, and no amount of refusing afterwards unwinds it. ADR
##     0134 §4 is blunt about it — "a refused earn records nothing ... There is no
##     queue, no pending flag, no deferred grant, no retry" — so there is not even a
##     later hook that could take it back.
##
## `attach` is in ALLOWED rather than in neither, and the reason is its own
## docstring: it normalizes the ledger, rebuilds the stat projection and the
## `Actor.traits` mirror, and **grants nothing**. It is the `lifecycle` row of ADR
## 0134's table. Listing it means an explicit `DestinyApi.attach(actor)` in `ui/` is a
## decision a reader can see and this file has thought about, rather than something
## that slipped past a rule nobody wrote down.

## `ui/`'s own root, walked the way `test_ui_conventions.gd` walks it.
const UI_ROOT := "res://src/ui"

## Extensions, not suffixes: `String.get_extension()` omits the leading dot, and a
## filter comparing against `".gd"` is TRUE OF EVERY SCRIPT IN THE TREE — which is how
## `test_ui_conventions.gd`'s `@onready` guard once skipped everything it existed to
## check and reported a green run on a broken one.
const SCANNED_SUFFIXES := ["gd"]

## Directories that are not the shipped UI program. Mirrors `test_ui_conventions.gd`'s
## `EXCLUDED_DIRS` for the same reason: a rule about shipped code does not apply to
## the suite that enforces it.
const EXCLUDED_DIRS := ["tests", "addons", "data", "assets"]

## The facade whose verbs are being split.
const FACADE := "res://src/modules/destiny/api.gd"

## ## The verbs `ui/` may name on `DestinyApi`
##
## Each entry is a `FACADE.` prefix followed by an OPEN PARENTHESIS, so the scan looks
## for a CALL and not for a substring: `DestinyApi.summary(` is the verb, and
## `DestinyApi.summary_editor(` — a name no build has — could not satisfy it. The
## closing paren is not part of the token, because the check is "is this verb called
## here", and the argument list is the author's to shape.
const ALLOWED := [
	"DestinyApi.summary(",
	"DestinyApi.events(",
	"DestinyApi.gate(",
	"DestinyApi.has_fate(",
	"DestinyApi.has_destiny(",
	"DestinyApi.state(",
	"DestinyApi.destinies(",
	"DestinyApi.fates(",
	"DestinyApi.attach(",
]

## ## The verbs `ui/` may NEVER name
##
## The three `mutate` rows of ADR 0134 §1. `earn_fate` appends a fate,
## `earn_destiny` appends a branch AND may carry `grants_fates` with it, and `record`
## moves a counter. None of them has an undo; none of them is refused by anything
## outside the callee; and a refusal is byte-identical to a success on the ledger
## (ADR 0134 §1a — every refusal path "returns the ledger unchanged"), so a picker
## that asked for a destiny nobody earned does not crash and does not report. It
## simply does not work, which is the worst shape for the bug it is.
const FORBIDDEN := [
	"DestinyApi.earn_fate(",
	"DestinyApi.earn_destiny(",
	"DestinyApi.record(",
]

## ## The widgets and handlers a READ-ONLY surface may not publish
##
## A fate is earned and cannot be chosen, equipped or given up (ADR 0065), so a button
## on a codex row is a promise the module cannot keep whatever the button does.
## `pressed.` is the handler connection that would fire one; `gui_input` is the other
## way a Godot widget becomes actionable without one.
const PRESSABLE := ["Button", "OptionButton", "pressed.", "gui_input"]

## The fate and destiny codex, and the two rows it is built from. Spelled as paths
## rather than discovered, because the rule is about THESE three files: they are the
## whole of the player-facing destiny surface, and a scan that asked `res://src/ui`
## which files are "destiny files" would be satisfied by an empty answer.
const CODEX_SCRIPTS := [
	"res://src/ui/screens/destiny_screen.gd",
	"res://src/ui/panels/destiny_branch_row.gd",
	"res://src/ui/panels/fate_row.gd",
]

## `FateRow`'s class name, read off the file so a rename that emptied the codex would
## fail the coverage case by NAME rather than passing on a file that no longer mounts.
const BRANCH_ROW_CLASS := "DestinyBranchRow"
const FATE_ROW_CLASS := "FateRow"

# --- Fixtures: one violation and one control per guard ------------------------
#
# Synthetic TEXT, never files. Nothing here is loaded, only scanned: Godot pairs every
# `.gd` with a `.uid` sibling and parses every `.tscn` under `res://` as a resource,
# so a fixture file would be two extra artifacts to keep in step with a string. Held
# in this file rather than under `tests/ui/fixtures/` so a fixture lives beside the
# assertion that reads it and neither can be deleted alone — the same choice
# `test_ui_conventions.gd` records.

## A picker. The one shape this whole file exists to keep out of `ui/`: a screen that
## reads the codex and then GRANTS itself a destiny from a button. Its own comment
## names the forbidden verb on purpose — the guard must skip that comment and still
## catch the call two lines below it, which is the leg that proves the strip is not
## simply deleting the evidence.
const EARN_FIXTURE := {
	"path": "res://src/ui/screens/destiny_picker_fixture.gd",
	"text":
	(
		"extends UiScreen\n"
		+ "\n"
		+ "var _actor: Actor = null\n"
		+ "\n"
		+ "## A codex may not call DestinyApi.earn_destiny: the earn belongs to the\n"
		+ "## system that decided the deed happened, not to a screen.\n"
		+ "func _grant(destiny_id: StringName) -> void:\n"
		+ "\tvar live := DestinyApi.summary(_actor)\n"
		+ '\tvar ledger := DestinyApi.earn_destiny(_actor, destiny_id, "ui")\n'
		+ "\tif not DestinyApi.has_destiny(_actor, destiny_id):\n"
		+ "\t\treturn\n"
		+ "\tprint(live.size() + ledger.size())\n"
	),
}

## The same screen without the write: reads `summary()`, answers `has_destiny()`, and
## stops there. Every real screen in `ui/` looks like this, so this is the control
## that stops the forbidden-list scan from being satisfied by a predicate that flags
## every `DestinyApi` call it is shown.
const EARN_FIXTURE_CLEAN := {
	"path": "res://src/ui/screens/destiny_read_only_fixture.gd",
	"text":
	(
		"extends UiScreen\n"
		+ "\n"
		+ "var _actor: Actor = null\n"
		+ "\n"
		+ "## A codex reads. It never calls DestinyApi.earn_destiny, and this comment\n"
		+ "## is not what the guard is looking for either.\n"
		+ "func _refresh() -> void:\n"
		+ "\tvar live := DestinyApi.summary(_actor)\n"
		+ '\tif DestinyApi.has_destiny(_actor, &"the_severed"):\n'
		+ "\t\trefresh()\n"
	),
}

## A screen that only NAMES the forbidden verbs, in its doc comment, because every
## honest screen documents the rule it follows. This is the shape the comment strip
## exists for: the words are there, and they are not a violation.
const EARN_FIXTURE_NAMED := {
	"path": "res://src/ui/screens/destiny_named_fixture.gd",
	"text":
	(
		"extends UiScreen\n"
		+ "\n"
		+ "## No earn call here. This codex must never reach DestinyApi.earn_fate or\n"
		+ "## DestinyApi.record, and it documents that by naming them, which is exactly\n"
		+ "## what the guard is for.\n"
		+ "func _refresh() -> void:\n"
		+ "\tvar live := DestinyApi.summary(_actor)\n"
		+ "\tprint(live.size())\n"
	),
}

## A codex row that mounts a Button — the other half of ADR 0065. Even a button that
## "only refreshes" is a widget that offers the player a choice this surface is not
## allowed to have.
const BUTTON_FIXTURE := {
	"path": "res://src/ui/panels/destiny_button_fixture.gd",
	"text":
	(
		"extends PanelContainer\n"
		+ "\n"
		+ "var _equip: Button = null\n"
		+ "\n"
		+ "func _bind_nodes() -> void:\n"
		+ '\t_equip = get_node_or_null("%Equip") as Button\n'
		+ "\t_equip.pressed.connect(_on_equip)\n"
		+ "\n"
		+ "func _on_equip() -> void:\n"
		+ "\tpass\n"
	),
}

## The same row without a control: a report, which is what every shipped destiny row
## is. Its comment names the forbidden widget on purpose, so the strip is proved on
## this leg too.
const BUTTON_FIXTURE_CLEAN := {
	"path": "res://src/ui/panels/destiny_report_fixture.gd",
	"text":
	(
		"extends PanelContainer\n"
		+ "\n"
		+ "var _head_label: Label = null\n"
		+ "\n"
		+ "## No Button here, and this comment is not what the guard is looking for.\n"
		+ "func _bind_nodes() -> void:\n"
		+ '\t_head_label = get_node_or_null("%HeadLabel") as Label\n'
	),
}

# --- 1. no UI script may earn --------------------------------------------------


## The guard itself.
##
## Asked of every `.gd` under `res://src/ui/`, over the COMMENT HALF STRIPPED. The
## strip is what makes this a convention check rather than a prose search: a doc
## comment naming `DestinyApi.earn_fate` to explain why the screen does not call it is
## the correct thing to write, and punishing the file for documenting its own rule
## teaches the next author to delete the explanation instead. It is also what closes
## the reverse failure — a real call cannot hide in a comment, because the executable
## part of a line always precedes its comment.
##
## The walk count is asserted non-empty first. A walk that visited nothing would
## report every screen as clean, and "no files" and "no violations" are the same
## number in the tally.
func test_no_ui_script_earns_or_records_through_the_destiny_facade() -> void:
	var scanned := _source_texts(UI_ROOT)
	assert_eq(
		scanned.size() > 0,
		true,
		"the walk visited res://src/ui, so the verdict below is about real files"
	)
	assert_eq(
		scanned.size() > 20, true, "and it visited the whole UI program, not one directory of it"
	)
	var offenders: Array[String] = []
	for entry in scanned:
		var code := _code_only(entry["text"] as String)
		for verb in FORBIDDEN:
			if code.contains(String(verb)):
				offenders.append("%s calls %s" % [entry["path"], verb])
	offenders.sort()
	assert_eq(
		offenders,
		[],
		(
			(
				'ui/ may READ fate and it may never WRITE it: ADR 0065, and ADR 0134 §1 — "write '
				+ 'verbs belong to the owner of the moment, never to destiny". Found: %s'
			)
			% str(offenders)
		)
	)


## ## Why `ui/` is not simply BLOCKED from naming `destiny`
##
## It is not, and this is the case that says so. A codex that reads
## `DestinyApi.summary()` is doing exactly what a codex is for, and a screen has to be
## able to say "you have not earned this yet, and here is what is holding it back" —
## which is `has_destiny` plus `gate`, both ALLOWED. A guard written as "`ui/` may not
## name DestinyApi at all" would be red on a correct tree and would send the next
## agent to delete the codex rather than to fix the picker.
##
## So the ALLOWED list is asserted POSITIVELY against the real facade: these verbs
## really are reachable from a screen, every one of them changes nothing, and the scan
## above is the thing that keeps the reach read-only. This is the control that keeps
## [constant FORBIDDEN] from being satisfied by a predicate that flags every
## `DestinyApi` call it is shown.
func test_the_codex_reaches_the_facade_through_reads_and_that_is_allowed() -> void:
	var screen := _read(CODEX_SCRIPTS[0])
	assert_ne(screen, "", "%s ships, so this is not a silent skip" % CODEX_SCRIPTS[0])
	assert_eq(
		_code_only(screen).contains("DestinyApi.summary("),
		true,
		"the codex reads DestinyApi.summary(), which is the screen seam (ADR 0134)"
	)
	assert_eq(
		_code_only(screen).contains("DestinyApi.events("),
		true,
		(
			"and it subscribes through DestinyApi.events(), which is how a screen is ALLOWED "
			+ "to learn fate was earned without being the thing that earned it"
		)
	)
	assert_eq(
		_uses_only_allowed(screen),
		true,
		(
			"and every DestinyApi verb the codex names is on the ALLOWED list, so the screen "
			+ "reaches the facade without crossing the read/write line"
		)
	)
	# The codex uses TWO of the nine, and that is the honest measurement of the surface
	# today: measured over executable lines on 2026-10-05, `summary()` and `events()` are
	# the only `DestinyApi` calls anywhere under `res://src/ui/`. Asserted so this case
	# cannot be satisfied by a codex that grew a fourth verb — and so a reader knows the
	# other seven ALLOWED entries are PERMISSION, not current usage. That is the point of
	# naming them: `gate()` is how a screen explains a shut quest and `has_destiny()` is
	# how it answers "do I have this", and a future screen doing either is conforming,
	# not regressing.
	assert_eq(
		_destiny_verbs(screen),
		["events", "summary"],
		"the codex reaches the facade through exactly these verbs today, and both are " + "reads"
	)


## Every `DestinyApi.<verb>(` `text` actually CALLS, sorted. Used to state the shipped
## surface as a measurement rather than as a restatement of [constant ALLOWED], so the
## difference between "permitted" and "used" is an assertion.
func _destiny_verbs(text: String) -> Array[String]:
	var prefix := String("DestinyApi.")
	var out: Array[String] = []
	var code := _code_only(text)
	var cursor := 0
	while true:
		var at := code.find(prefix, cursor)
		if at < 0:
			break
		cursor = at + 1
		var tail := code.substr(at)
		var stop := tail.find("(")
		if stop < 0:
			continue
		var verb := tail.substr(prefix.length(), stop - prefix.length())
		if not out.has(verb):
			out.append(verb)
	out.sort()
	return out


## Whether every `DestinyApi.<verb>(` in `text` is an ALLOWED call. Asked of the codex
## and of the fixtures, so the definition of "a screen may do this" is written ONCE and
## a fixture cannot satisfy it by a predicate the scan never consults.
##
## A verb that is on NEITHER list counts as a violation here, which is deliberately
## stricter than the scan above: the scan checks three known mutators, and this checks
## that nothing else is being called at all. A thirteenth verb would need to be taught
## to this file in the same change that adds it — which is the point.
func _uses_only_allowed(text: String) -> bool:
	var code := _code_only(text)
	var cursor := 0
	var allowed := true
	while allowed:
		var at := code.find("DestinyApi.", cursor)
		if at < 0:
			break
		cursor = at + 1
		var tail := code.substr(at)
		var stop := tail.find("(")
		# A bare `DestinyApi.` mention with no `(` is not a verb being called, so it is
		# not a call this file can judge; the cursor has already moved past it.
		if stop < 0:
			continue
		if not ALLOWED.has(tail.substr(0, stop + 1)):
			allowed = false
	return allowed


## The forbidden half is asserted against the REAL facade, so the list above cannot
## drift from it silently: every `mutate` row of ADR 0134 §1 is named here, and the
## read surface is named here too. This is the two-sided check — a list of forbidden
## verbs is only as good as the facade it guards, and if a thirteenth `mutate` verb
## were added to `DestinyApi` the scan above would not notice, because it does not know
## about a verb it has never heard of.
func test_the_split_covers_the_facades_whole_public_surface() -> void:
	var published := _public_methods(FACADE)
	assert_eq(
		published.is_empty(), false, "the facade publishes methods, so this case is not vacuous"
	)
	var uncovered: Array[String] = []
	for method_name in published:
		var covered := false
		for prefix in ALLOWED:
			if prefix == "DestinyApi.%s(" % method_name:
				covered = true
		for prefix in FORBIDDEN:
			if prefix == "DestinyApi.%s(" % method_name:
				covered = true
		if not covered:
			uncovered.append(method_name)
	assert_eq(
		uncovered,
		[],
		(
			"every public verb of DestinyApi is classified as an allowed read or a "
			+ "forbidden write. An unclassified verb is the dangerous case: the scan does "
			+ "not know it exists, so a screen could call it and this suite would be green"
		)
	)
	assert_eq(
		published.size(),
		12,
		(
			"and the facade is still at its twelve-method cap (ADR 0134 §1b): a thirteenth "
			+ "verb fails `tools arch` loudly, and this suite has to be taught about it in "
			+ "the same change"
		)
	)


## ## The split itself, asserted rather than left in prose
##
## The whole file's argument is the read/write line, so it is checked as data: the two
## lists must be DISJOINT (a verb on both would make the verdict depend on which loop
## ran first) and every entry must name a verb the facade really publishes (a typo
## would silently leave the verb unguarded).
func test_the_allowed_and_forbidden_lists_are_disjoint_and_real() -> void:
	var published := _public_methods(FACADE)

	var unrecognised: Array[String] = []
	for prefix in ALLOWED + FORBIDDEN:
		var verb := String(prefix).substr(String("DestinyApi.").length(), String(prefix).length())
		verb = verb.substr(0, verb.length() - 1)
		if not published.has(verb):
			unrecognised.append(String(prefix))
	assert_eq(
		unrecognised,
		[],
		(
			"every prefix on both lists names a real method of the facade, so the scan is "
			+ "looking for calls that could compile rather than for typos"
		)
	)

	var overlap: Array[String] = []
	for prefix in ALLOWED:
		if FORBIDDEN.has(prefix):
			overlap.append(String(prefix))
	assert_eq(
		overlap,
		[],
		"and no verb is on both lists, so the verdict never depends on which loop ran first"
	)

	# Named here exactly as the header names them, so the three mutators cannot be
	# quietly swapped for three reads.
	assert_eq(
		FORBIDDEN,
		[
			"DestinyApi.earn_fate(",
			"DestinyApi.earn_destiny(",
			"DestinyApi.record(",
		],
		"and the forbidden half is exactly ADR 0134 §1's mutate row"
	)
	assert_eq(
		ALLOWED,
		[
			"DestinyApi.summary(",
			"DestinyApi.events(",
			"DestinyApi.gate(",
			"DestinyApi.has_fate(",
			"DestinyApi.has_destiny(",
			"DestinyApi.state(",
			"DestinyApi.destinies(",
			"DestinyApi.fates(",
			"DestinyApi.attach(",
		],
		(
			"and the allowed half is exactly the reads ADR 0134 §1 calls the save seam, the "
			+ "screen seam, the content seam, and the lifecycle verb that grants nothing"
		)
	)


## The proof the forbidden-verb scan can still SEE. Four legs, as in
## `test_ui_conventions.gd`: the fixture DOES call an earn in executable code and IS
## caught; the clean screen is NOT caught; the screen that only NAMES the verbs in a
## doc comment is NOT caught either — which is the leg that keeps the first from being
## satisfied by a predicate that flags the word wherever it finds it; and the strict
## `_uses_only_allowed` rejects a verb that is on NEITHER list, which is the case the
## three-name scan alone cannot see.
func test_the_earn_guard_still_sees_an_earn_and_ignores_a_comment_that_names_one() -> void:
	assert_eq(
		String(EARN_FIXTURE["path"]).get_extension(),
		"gd",
		"the fixture is the shape the scan above filters for"
	)
	var picking := _code_only(String(EARN_FIXTURE["text"]))
	assert_eq(
		picking.contains("DestinyApi.earn_destiny("),
		true,
		"a picker that grants itself a destiny really does call earn_destiny in code"
	)
	assert_eq(
		_uses_only_allowed(String(EARN_FIXTURE["text"])),
		false,
		"so the forbidden-verb scan reads it, and the strict read/write check rejects it"
	)
	# The same fixture also READS, so a predicate that flags every `DestinyApi` call
	# cannot be what caught it.
	assert_eq(
		picking.contains("DestinyApi.summary(") and picking.contains("DestinyApi.has_destiny("),
		true,
		"and it reads summary() and has_destiny() too, which are ALLOWED"
	)

	assert_eq(
		_uses_only_allowed(String(EARN_FIXTURE_CLEAN["text"])),
		true,
		"and a screen that only reads the facade is NOT caught, which every real one is"
	)

	# The leg that makes the comment strip load-bearing. The RAW text names both
	# forbidden verbs; the STRIPPED text names neither. Asserted on both halves,
	# because a strip that removed nothing would satisfy the second and a strip that
	# removed too much would satisfy the first — together they are the only pair that
	# proves the strip does what its docstring says.
	var named_raw := String(EARN_FIXTURE_NAMED["text"])
	assert_eq(
		named_raw.contains("DestinyApi.earn_fate") and named_raw.contains("DestinyApi.record"),
		true,
		"the naming fixture really does spell both forbidden verbs, so the next leg is real"
	)
	assert_eq(
		_code_only(named_raw).contains("DestinyApi.earn_fate"),
		false,
		"a screen that NAMES earn_fate in a doc comment is not a violation: stripping"
	)
	assert_eq(
		_code_only(named_raw).contains("DestinyApi.record"),
		false,
		"nor is naming record in one — the comments that document the rule must survive"
	)
	assert_eq(
		_uses_only_allowed(String(EARN_FIXTURE_NAMED["text"])),
		true,
		"so the strict check passes it too, and the strip is what did the work"
	)
	assert_eq(
		_uses_only_allowed(String(BUTTON_FIXTURE["text"])),
		true,
		(
			"and a Button fixture is not an earn fixture: the two guards are separate "
			+ "questions, and a violation of one is not a violation of the other"
		)
	)


# --- 2. the read-only shape of the codex --------------------------------------


## ## The codex surface, as a property of the SHIPPED FILES
##
## The verb scan above is about what `ui/` CALLS. This is about what the codex
## BUILDS: no `Button`, no `OptionButton`, no `pressed.` connection, no `gui_input`
## handler, on the screen or on either row it is built from. A codex that mounted an
## equip button would pass the verb scan cleanly and still break ADR 0065 — the write
## would just live behind a signal instead of a call.
##
## Asserted over [constant CODEX_SCRIPTS], three NAMED files, so a rename that emptied
## the surface would fail here naming the path rather than passing on an empty list.
func test_the_codex_mounts_no_pressable_widget_and_handles_no_press() -> void:
	for path in CODEX_SCRIPTS:
		var body := _read(path)
		assert_ne(body, "", "%s ships, so this is not a silent skip" % path)
		if body.is_empty():
			continue
		var found := _pressables_in(_code_only(body))
		assert_eq(
			found,
			[],
			(
				(
					"%s carries %s; a fate is earned and cannot be chosen, equipped or given up "
					% [path, str(found)]
				)
				+ (
					"(ADR 0065), so the codex publishes no control and handles no press — the "
					+ 'codex screen\'s own header says "There is no button anywhere on this surface"'
				)
			)
		)


## ## The proof the control scan can still SEE
##
## Every one of the three shipped destiny files is clean, so the scan above runs to
## completion having asserted nothing and reports a tree that satisfies the rule. That
## is the whole rule, so the guard protecting it — the architectural invariant the
## player-facing destiny surface is written against — could go blind with nothing to
## say so. Three legs: the fixture DOES mount a Button and IS caught; the report row is
## NOT caught; and the fixture is the shape the scan filters for. The last leg is on
## the SHIPPED files, so it cannot be satisfied by a predicate that flags every file it
## is shown.
func test_the_control_guard_still_sees_a_codex_row_that_mounts_a_button() -> void:
	assert_eq(
		String(BUTTON_FIXTURE["path"]).get_extension(),
		"gd",
		"the fixture is the shape the scan above filters for"
	)
	var pressing := _code_only(String(BUTTON_FIXTURE["text"]))
	assert_eq(
		pressing.contains("Button"),
		true,
		"a codex row that mounts a Button really does carry the token in executable code"
	)
	assert_eq(
		pressing.contains("pressed."), true, "and connecting it really does carry the handler token"
	)
	assert_eq(
		_pressables_in(pressing).has("gui_input"),
		false,
		"while a fixture that does not handle gui_input is not reported for one"
	)
	assert_eq(
		_pressables_in(_code_only(String(BUTTON_FIXTURE_CLEAN["text"]))).has("Button"),
		false,
		"and a report row that only names the widget in a comment is NOT caught"
	)
	for path in CODEX_SCRIPTS:
		assert_eq(
			_pressables_in(_code_only(_read(path))),
			[],
			"and every shipped destiny file really is free of every token the scan looks for"
		)


## ## The codex really is the surface, and it really mounts what it claims to
##
## The two guards above both run clean over three named paths. If the screen stopped
## mounting rows — a refactor that dropped the branch pool and the fate pool — the
## files would still be control-free and still pass, while the codex would show
## nothing. This case asserts the other half: the screen still names both row classes,
## so "read-only" is a claim about a real surface rather than about three empty files.
func test_the_codex_still_mounts_the_two_rows_it_is_read_only_about() -> void:
	var screen := _code_only(_read(CODEX_SCRIPTS[0]))
	assert_eq(
		screen.contains("DestinyBranchRow"),
		true,
		"the codex screen still builds destiny rows, so its read-only shape is a live claim"
	)
	assert_eq(
		screen.contains("FateRow"), true, "and fate rows, which is the other half of the codex"
	)
	assert_eq(
		screen.contains(BRANCH_ROW_CLASS) and screen.contains(FATE_ROW_CLASS),
		true,
		"and both row CLASSES by name, not only the row scenes"
	)
	assert_eq(
		screen.contains("on_stack_input"),
		true,
		(
			"and the screen still owns an on_stack_input that consumes nothing: nothing here "
			+ "is actionable, so ui_cancel stays free for ScreenStack to pop"
		)
	)


# --- 3. a `tagged` gate must not grow the codex an affordance ------------------


## ## The `tagged` verb (ADR 0196, fate tag vocabulary) changed the GATE language, not the codex.
##
## A lineage gate is the obvious seed for a codex feature: "show me the fates that
## satisfy this gate", or a tag chip per row the player can filter by. Both would
## be a player-facing AFFORDANCE on a surface that is read-only by construction, and
## both would be legal — a filter is a `Control` property, not a `Button`, and
## `gate()` is on the ALLOWED list above, so neither guard above would catch them.
##
## So the property is asserted directly rather than inferred from the two scans:
## the row still MIRRORS `tags` (a published field a panel may carry) and nothing
## more — it does not sort, group or select by them — and the screen still publishes
## `read_only: true` with NO filter state of any kind.
func test_a_tag_gate_adds_no_affordance_to_the_read_only_codex() -> void:
	# The row still mirrors the published field. This is the CONTROL half: a guard
	# satisfied by an empty result proves nothing, so the row must demonstrably
	# carry tags through, or the "and nothing more" below is vacuous.
	var row_source := _code_only(_read(CODEX_SCRIPTS[2]))
	assert_ne(row_source, "", "%s ships, so this is not a silent skip" % CODEX_SCRIPTS[2])
	assert_eq(
		row_source.contains('"tags"'),
		true,
		"the fate row still mirrors the published `tags` field, which is a report and not a control"
	)
	assert_eq(
		_pressables_in(row_source),
		[],
		"and it still mounts no widget a tag could be attached to as a pressable affordance"
	)
	# The row does not ACT on a tag. A row that sorted, filtered, grouped or
	# highlighted by lineage would be building the affordance this case forbids.
	for verb in ["sort", "filter", "group", "select", "pressed", "gui_input", "Button"]:
		assert_eq(
			_code_only(_read(CODEX_SCRIPTS[2])).contains(verb),
			false,
			(
				(
					"the fate row never acts on a tag: it may REPORT 'oath' but must not offer, order or "
					+ "switch on it, because a fate is earned and never chosen (ADR 0065)"
				)
				if verb in ["sort", "filter", "group", "select"]
				else "and carries no %s, as the control scan already requires" % verb
			)
		)
	# The screen: still exactly the two facade verbs it used before the verb landed.
	# `gate()` is on ALLOWED and a lineage gate is precisely the thing a codex might
	# be tempted to call, so this is the leg that says it still does not.
	assert_eq(
		_destiny_verbs(_read(CODEX_SCRIPTS[0])),
		["events", "summary"],
		(
			"the codex still reaches the facade through exactly `events` and `summary`; a `tagged` "
			+ "gate is evaluated by the quest/event that owns it, never by a read-only screen"
		)
	)
	# And no filter state at all: the whole of `_summary()`'s keys, so a future
	# `filter_tag` or `selected_tag` is a visible diff against this list rather
	# than a silent new affordance.
	var screen := _read(CODEX_SCRIPTS[0])
	for token in ["filter", "selected_tag", "active_tag", "tag_filter", "sort_mode"]:
		assert_eq(
			_code_only(screen).contains(token),
			false,
			(
				(
					"the codex publishes no '%s': a read-only surface has nothing to filter, because "
					% token
				)
				+ "nothing here is a player choice (ADR 0065)"
			)
		)
	assert_eq(
		_code_only(screen).contains('"read_only": true'),
		true,
		"and it still declares itself read-only in its own published summary"
	)


# --- Plumbing ------------------------------------------------------------------


## Every `.gd` under `root`, as `{path, text}`, sorted so a failure names the same
## file twice in the same order.
##
## Iterative rather than recursive, and for the reason `test_ui_conventions.gd` gives:
## a recursive `DirAccess` walk silently returned an empty list under the headless
## runner, which would make every "no UI script earns" assertion pass VACUOUSLY. The
## worklist is explicit so an empty result is a real result, and the scan asserts the
## count is non-zero for the same reason.
func _source_texts(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path := current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with(".") and not EXCLUDED_DIRS.has(entry):
					pending.append(path)
			elif SCANNED_SUFFIXES.has(path.get_extension()):
				out.append({"path": path, "text": _read(path)})
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["path"] < b["path"])
	return out


## `text` with the comment half of every line removed. This is the whole of "a
## convention check must read CODE, not prose".
##
## **`test_ui_conventions.gd` once searched raw source for `theme_override`, so a
## screen whose comment read "styled by variation, never by a `theme_override_*`"
## FAILED the check** — punishing the file for documenting the rule it follows. The
## same mistake would be worse here: `destiny_screen.gd`'s own header says "it renders
## `DestinyApi.summary(actor)` and names nothing else in the module", which is the
## correct sentence to write and would otherwise be a violation of this file's own
## rule.
##
## The strip is per line and stops at the first `#` outside a double-quoted string, so
## a `#` inside a message the code emits is not mistaken for a comment. A real call
## cannot hide in one: the executable part of a line always precedes its comment, so
## removing from the `#` onwards removes prose and never code.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var out := ""
		var quoted := false
		for i in line.length():
			var ch := line[i]
			if ch == '"':
				quoted = not quoted
			elif ch == "#" and not quoted:
				break
			out += ch
		kept.append(out)
	return "\n".join(kept)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Every pressable token `code` carries, sorted. Asked of both the fixtures and the
## shipped files by the two control guards, so the rule is spelled ONCE and the proof
## cannot be satisfied by a predicate the scan never consults.
func _pressables_in(code: String) -> Array[String]:
	var out: Array[String] = []
	for token in PRESSABLE:
		if code.contains(String(token)):
			out.append(String(token))
	out.sort()
	return out


## Every PUBLIC method `path` publishes, sorted — the whole surface the split above is
## checked against.
func _public_methods(path: String) -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load(path)
	if script == null:
		return out
	for method in script.get_script_method_list():
		var method_name := String(method.name)
		if method_name.begins_with("_"):
			continue
		out.append(method_name)
	out.sort()
	return out
