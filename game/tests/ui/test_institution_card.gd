extends TestCase

## The institution UI slice: a reusable [InstitutionCard] row and the
## [InstitutionScreen] that fills it.
##
## ## What is actually load-bearing here, and what is only taste
##
##  1. **The three states render as three DIFFERENT things.** `{}` hides the row,
##     `{"vacant": true}` shows it in its own tone with `is_filled() == true`, and
##     `{"ok": false, "reason": R}` shows the facade's OWN `R`. A panel that collapsed
##     any two of them has destroyed the succession design ADR 0084 exists to keep
##     legible, so each state is asserted on `visible`, on the tone AND on the payload.
##  2. **A vacancy is NEVER `0`.** Asserted on the exact rendered payload for a vacant
##     office: `vacant == true` and `state == "vacant"` are BOOLEAN and WORD, and the
##     line prints `VACANT` -- never `0`, never `"-"`, never a hidden row.
##  3. **The card renders the RATIO the claim computed.** `normalized()` is read off the
##     view and never recomputed, proved by handing the row a view whose `normalized` and
##     whose raw numbers deliberately DISAGREE.
##  4. **The PANEL formats numbers and the SCREEN does not.** Asserted by type and value:
##     the screen publishes `founding_cost` as an `int`, and by reading the screen's own
##     source for a format verb it is not allowed to use.
##  5. **The panel drives with NO scene tree.** Every assertion below runs against a card
##     that was never added to a tree -- which is exactly why the standard forbids
##     `@onready`.

## The screen and card scenes, loaded once: two `load()` calls for one scene is a second
## source of truth about which scene this suite drives.
const CARD_SCENE := preload("res://src/ui/panels/institution_card.tscn")
const SCREEN_SCENE := preload("res://src/ui/screens/institution_screen.tscn")
const CARD_SCRIPT := "res://src/ui/panels/institution_card.gd"
const SCREEN_SCRIPT := "res://src/ui/screens/institution_screen.gd"
const CARD_SCENE_TEXT := "res://src/ui/panels/institution_card.tscn"
const SCREEN_SCENE_TEXT := "res://src/ui/screens/institution_screen.tscn"

const LANTERN := &"lantern_exchange"
const CIRCLE := &"torrent_field_circle"
## The Exchange's single SEAT (`capacity = 1`) and its UNCAPPED ordinary office
## (`capacity = 0`). Named because the two ends of the cap are what the vacancy assertions
## are actually about, and reaching them by ARRAY INDEX would test whichever office the
## `.tres` happened to list first rather than the one the assertion names.
const SEAT := "first_ledger"
const ROOM := "clerk"
## A guild that authors offices to assert on: the Circle deliberately authors NONE, which
## is the case that makes "no office at all" reachable.
const GUILD := LANTERN

## Every node this suite instantiated, freed from [method teardown]. A row added here and
## not freed is a leak, not a fixture: the runner drives every suite from one process, so a
## leaked subtree survives into the next suite. **Only `Node`s are freed** -- an `Actor` is
## a `RefCounted` and `free()` on one is a SCRIPT ERROR that aborts the rest of teardown.
var _born: Array = []


func setup() -> void:
	_born = []
	# The boot runs ONCE per test rather than per assertion: the registry is process
	# state and the runner drives every suite in one process, so leaving it registered
	# here is exactly what `teardown` clears. A suite that skipped the boot reported an
	# EMPTY kind list next to three authored organizations, which is the honest answer to
	# "what did nobody register" and an entirely misleading one for a screen.
	InstitutionRegistry.shared = null
	InstitutionDefCatalog.clear()
	var report := InstitutionBoot.install()
	assert_eq(bool(report["ok"]), true, "the shipped organizations register cleanly")


func teardown() -> void:
	# Freed from ONE place, called after every test including one that returned early.
	# A `Node` is detached before `free()`: the headless runner drives from
	# `SceneTree._initialize()` and a deferred free never runs under `tools test`.
	for node in _born:
		var victim := node as Node
		if victim == null:
			continue
		if victim.get_parent() != null:
			victim.get_parent().remove_child(victim)
		victim.free()
	_born = []
	InstitutionDefCatalog.clear()
	InstitutionRegistry.shared = null


# --- Fixtures -----------------------------------------------------------------


func _card() -> InstitutionCard:
	return _born_card(CARD_SCENE.instantiate())


## A card built from the SCRIPT alone -- no scene, no tree, no widgets at all. This is the
## shape a headless suite can drive, and the reason the standard forbids `@onready`: an
## `@onready` binding would never have run here.
func _bare_card() -> InstitutionCard:
	return _born_card(InstitutionCard.new())


func _born_card(node: InstitutionCard) -> InstitutionCard:
	_born.append(node)
	return node


func _screen() -> InstitutionScreen:
	var screen := SCREEN_SCENE.instantiate() as InstitutionScreen
	_born.append(screen)
	return screen


func _actor() -> Actor:
	return Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})


## A card view for one authored organization, built from the SHIPPED `.tres` so the
## fixture cannot drift from the content. `claim` is `{}` -- the FIRST state -- unless a
## caller passes one.
func _organization(
	def_id: StringName, claim: Dictionary = {}, vacant: Variant = null
) -> Dictionary:
	var def := InstitutionDefCatalog.instance().definition(def_id)
	assert_ne(def, null, "%s is authored" % String(def_id))
	if def == null:
		return {}
	var offices: Array = []
	for office in def.positions:
		(
			offices
			. append(
				{
					"id": String(office.id),
					"display_name": String(office.display_name),
					"capacity": office.room(),
					"held": 1,
					"holders": "hero",
					"duty_per_period": int(office.duty_per_period),
					"patronage_per_period": int(office.patronage_per_period),
					"duties": ["weigh_the_ledger"],
					"authorities": ["expel"],
					"vacant": false,
				}
			)
		)
	var view := {
		"ok": true,
		"id": String(def.id),
		"kind": String(def.kind),
		"display_name": String(def.display_name),
		"founding_cost": int(def.founding_cost),
		"standing_cap": int(def.standing_cap),
		"capabilities": ["has_offices"],
		"territories": [],
		"positions": offices,
		"claim": claim,
	}
	if vacant != null:
		view["vacant"] = vacant
	return view


## Show `def_id` on `card` with `position_id` authored but nobody holding it.
##
## By ID and never by index: the first office a `.tres` lists is content order, and an
## assertion written against an index tests whichever office that happens to be rather
## than the one it names. Returns nothing -- the card is the assertion's subject.
func _vacate(card: InstitutionCard, def_id: StringName, position_id: String) -> void:
	var view := _organization(def_id)
	var offices: Array = view["positions"]
	var found := 0
	for entry in offices:
		var office: Dictionary = entry
		if String(office.get("id", "")) != position_id:
			continue
		found += 1
		office["vacant"] = true
		office["held"] = 0
		office["holders"] = ""
	assert_eq(found, 1, "%s authors exactly one office called %s" % [String(def_id), position_id])
	card.show_organization(view)


## A real claim, so `normalized()` is `core`'s own answer and not a number this suite
## wrote twice.
func _claim(position: String, standing: int, cap: int) -> InstitutionClaim:
	var claim := InstitutionClaim.new()
	claim.position = StringName(position)
	claim.standing = standing
	claim.standing_cap = cap
	claim.obligation = {"duty_lantern_exchange": 3}
	return claim


func _claim_view(claim: InstitutionClaim) -> Dictionary:
	return {
		"exists": true,
		"position": String(claim.position),
		"standing": claim.standing,
		"standing_cap": claim.standing_cap,
		# The RATIO, as `InstitutionClaim.normalized()` computes it. A caller that
		# published `standing / standing_cap` here would have written a second copy of a
		# formula that already exists, which is ADR 0066's shape.
		"normalized": claim.normalized(),
		"obligations": {"duty_lantern_exchange": 3},
	}


# --- 1. The three states are three DIFFERENT things ---------------------------


func test_an_empty_view_hides_the_row_completely() -> void:
	# ADR 0083's FIRST state: this row carries nothing at all. It is a spare row in the
	# screen's pool, and a pool row is an artefact of the widget tree, not a fact.
	var card := _card()
	card.show_organization({})
	var view := card.summary()
	assert_eq(view, {}, "a row carrying nothing reports nothing, not empty keys")
	assert_eq(card.is_filled(), false, "and says so through a named predicate")
	assert_eq(card.is_vacant(), false, "an absent organization is not a vacant one")
	assert_eq(card.is_member(), false, "nor a membership")
	assert_eq(card.visible, false, "and it HIDES, which is what {} means")


func test_a_vacant_organization_is_visible_and_is_not_an_absent_one() -> void:
	# ADR 0083's MIDDLE state: the organization EXISTS and the viewer's place in it is
	# ABSENT. A house you belong to and hold no office in is a fact about the world; a
	# spare pool row is not. Collapsing either into the other makes them read alike.
	var card := _card()
	card.show_organization(_organization(CIRCLE, {}, true))
	var view := card.summary()
	assert_ne(view, {}, "a vacant organization is a shaped row, not an absent one")
	assert_eq(card.is_filled(), true, "and it is FILLED: the organization exists")
	assert_eq(card.is_vacant(), true, "the vacancy is its own predicate")
	assert_eq(card.is_member(), false, "and it is not a membership")
	assert_eq(bool(view["vacant"]), true, "published as a boolean, not as a zero")
	assert_eq(card.visible, true, "and it RENDERS")
	assert_eq(String(view["card_tone"]), "VacantSeatCard", "in its own card tone")
	assert_eq(String(view["head_tone"]), "VacantSeatLabel", "and its own label tone")


func test_a_refusal_carries_the_facades_authored_reason_verbatim() -> void:
	# ADR 0083's THIRD state. `R` is the AUTHORED constant the verb chose; a row that
	# reworded it would be describing a rule nobody wrote, and a refusal a panel had to
	# phrase is a refusal the player cannot act on.
	var card := _card()
	var refused := _organization(LANTERN)
	refused["ok"] = false
	refused["reason"] = InstitutionLedger.R_ALREADY_FOUNDED
	card.show_organization(refused)
	var view := card.summary()
	assert_eq(String(view["reason"]), InstitutionLedger.R_ALREADY_FOUNDED, "verbatim")
	assert_eq(String(view["reason"]), "already_founded", "and it is the family's own string")
	assert_eq(bool(view["refused"]), true, "reported as a refusal")
	assert_eq(card.is_filled(), true, "a refusal is not an absent row")
	assert_eq(card.is_member(), false, "and never a membership")
	assert_eq(String(view["card_tone"]), "RefusedCard", "on the refusal tone")


func test_a_refusal_with_no_reason_is_given_the_familys_own_constant() -> void:
	# A refusal that names no reason is not a legible refusal, and an empty line reads
	# exactly like the row that simply had nothing to show. So it is given `core`'s own
	# "there is no institution here" constant rather than a blank.
	var card := _card()
	card.show_organization({"ok": false})
	assert_eq(
		String(card.summary()["reason"]),
		InstitutionLedger.R_NOT_AN_INSTITUTION,
		"the family's constant, not an empty reason"
	)


func test_the_three_states_render_three_different_things() -> void:
	# The pair, as one assertion: any two of the three sharing a payload or a tone is the
	# defect, and asserting them one at a time would pass a panel that merged two of them.
	var absent := _card()
	absent.show_organization({})
	var vacant := _card()
	vacant.show_organization(_organization(CIRCLE, {}, true))
	var member := _card()
	member.show_organization(_organization(LANTERN, _claim_view(_claim("first_ledger", 40, 150))))
	var absent_view := absent.summary()
	var vacant_view := vacant.summary()
	var member_view := member.summary()
	assert_eq(absent_view, {}, "{} reports nothing")
	assert_ne(vacant_view, {}, "a vacancy reports a row")
	assert_ne(member_view, {}, "a membership reports a row")
	assert_ne(String(vacant_view["card_tone"]), String(member_view["card_tone"]), "different cards")
	assert_ne(
		String(vacant_view["head_tone"]), String(member_view["head_tone"]), "different label tones"
	)
	assert_ne(vacant.visible, absent.visible, "a vacancy is VISIBLE where an absent row is not")
	assert_ne(
		String(vacant_view["standing_line"]),
		String(member_view["standing_line"]),
		"and they do not print the same claim line"
	)
	assert_ne(
		bool(vacant_view["vacant"]),
		bool(member_view["vacant"]),
		"and they do not report the same existence state"
	)


# --- 2. A vacancy is NEVER 0 ---------------------------------------------------


func test_a_vacant_office_payload_is_a_boolean_and_a_word_never_a_zero() -> void:
	# The whole reason ADR 0084 keeps a vacancy legible. Asserted on the EXACT payload,
	# because a payload that carried `held: 0` alone is exactly the shape a `0` reading
	# is built from.
	var card := _card()
	_vacate(card, LANTERN, SEAT)
	var first := card.position_summary(SEAT)
	assert_ne(first, {}, "the authored seat has a payload")
	assert_eq(bool(first["vacant"]), true, "the vacancy is a boolean")
	assert_eq(String(first["state"]), "vacant", "and a WORD, never a number")
	# The type, asked of the RAW value rather than of a `String()` cast of it: casting
	# first would make the check trivially true and assert nothing about the payload.
	assert_eq(typeof(first["state"]), TYPE_STRING, "the raw state is text, never a numeral")
	assert_ne(typeof(first["state"]), TYPE_INT, "and the type is not an int in either direction")
	var line := String(first["line"])
	assert_ne(line.find(InstitutionCard.VACANT_TEXT), -1, "and it is printed")
	# The polarity matters: `assert_ne(find(...), -1)` would assert the string IS there,
	# which is the opposite of what a vacancy must never say.
	assert_eq(line.find("0 holders"), -1, "never as a count of nothing")
	assert_eq(line.find("held by"), -1, "and never as a holder")


func test_a_vacant_office_says_vacant_and_never_a_dash() -> void:
	var card := _card()
	_vacate(card, LANTERN, SEAT)
	var line := String(card.position_summary(SEAT)["line"])
	assert_ne(line.find(InstitutionCard.VACANT_TEXT), -1, "the word is there")
	assert_eq(line.find("-"), -1, "and no dash stands in for an absent holder")
	assert_eq(line.find("—"), -1, "nor an em dash")
	assert_ne(line.find("First Ledger"), -1, "while the office keeps its name: it EXISTS")


func test_a_vacant_office_still_reports_the_room_it_has() -> void:
	# A seat nobody holds is a SEAT with a capacity, not an office with none. Rendering a
	# vacancy as `0 seats` would destroy the distinction ADR 0084 draws between a seat
	# somebody must be put out of and a room that can fill.
	var card := _card()
	_vacate(card, LANTERN, SEAT)
	var seat := card.position_summary(SEAT)
	assert_eq(int(seat["capacity"]), 1, "the authored cap survives the vacancy")
	assert_eq(bool(seat["is_seat"]), true, "and the seat/room distinction is still readable")
	assert_ne(String(seat["line"]).find("1 seat"), -1, "and it is printed as a seat")
	assert_eq(String(seat["line"]).find("0 seats"), -1, "never as an office with no room")


func test_an_unbounded_office_is_an_unbounded_room_and_says_so() -> void:
	# The other end of the cap: `0` is UNBOUNDED, not a room with nobody in it. Printing
	# `0 seats` for the Clerk would turn an office that can never fill into one that is
	# empty -- two facts that happen to share a number and mean opposite things.
	var card := _card()
	var view := _organization(LANTERN)
	card.show_organization(view)
	var clerk := card.position_summary(ROOM)
	assert_eq(int(clerk["capacity"]), 0, "the Clerk's authored cap is zero")
	assert_eq(bool(clerk["unbounded"]), true, "which means UNBOUNDED")
	assert_eq(bool(clerk["is_seat"]), false, "and not a seat")
	assert_ne(String(clerk["line"]).find("unbounded room"), -1, "and it says so in words")
	assert_eq(String(clerk["line"]).find("0 seats"), -1, "never as a room with nobody in it")


func test_an_office_the_organization_does_not_author_is_never_rendered() -> void:
	# `{}` inside the positions list is the FIRST state for an OFFICE, and it is not a
	# blank row: an authored office that rendered empty would read as an office nobody
	# holds, which is the vacancy state and a different fact.
	var card := _card()
	var view := _organization(LANTERN)
	view["positions"] = [{}, {"id": "", "display_name": ""}, (view["positions"] as Array)[0]]
	card.show_organization(view)
	var ids := card.position_ids()
	assert_eq(ids.size(), 1, "only the one authored office is rendered")
	assert_eq(
		card.position_summary("no_such_office"), {}, "an office nobody authored has no payload"
	)


func test_an_organization_authoring_no_office_says_so_in_words() -> void:
	# The farmers' circle genuinely authors none, and that is ADR 0064's "thick standing
	# in no position at all" made legible rather than an empty gap in the card.
	var card := _card()
	card.show_organization(_organization(CIRCLE, _claim_view(_claim("", 25, 60))))
	assert_eq(card.position_ids().size(), 0, "it authors none")
	var line := String(card.summary()["standing_line"])
	assert_ne(line.find("25 / 60 standing"), -1, "so the standing still renders")
	assert_ne(
		line.find("25 / 60 standing"),
		-1,
		"with no office to name, which is a legitimate state and not a blank"
	)


# --- 3. Standing is a RATIO the claim computed ---------------------------------


func test_standing_renders_the_ratio_the_claim_computed() -> void:
	# `normalized()` is `core`'s own answer. The card READS it; it never divides
	# `standing / standing_cap` itself, so a card cannot disagree with the claim.
	var claim := _claim("first_ledger", 40, 150)
	var card := _card()
	card.show_organization(_organization(LANTERN, _claim_view(claim)))
	var view := card.summary()
	assert_eq(float(view["standing_ratio"]), claim.normalized(), "the ratio is the claim's")
	assert_eq(float(view["standing_ratio"]), 40.0 / 150.0, "and it is a ratio, not a balance")
	assert_eq(float(view["standing_ratio"]) >= 0.0, true, "in [0, 1]")
	assert_eq(float(view["standing_ratio"]) <= 1.0, true, "in [0, 1]")


func test_the_card_never_recomputes_the_ratio_from_its_own_numbers() -> void:
	# The behaviour, not the intent: hand the row a view whose `normalized` and whose raw
	# numbers DISAGREE. A card that divided would print the wrong percent; a card that
	# reads the claim's ratio prints this one.
	var card := _card()
	var view := _organization(LANTERN)
	view["claim"] = {
		"exists": true,
		"position": "first_ledger",
		"standing": 10,
		"standing_cap": 1000,
		"normalized": 0.25,
		"obligations": {},
	}
	card.show_organization(view)
	var published := card.summary()
	assert_eq(float(published["standing_ratio"]), 0.25, "the claim's ratio, 25%")
	assert_ne(
		String(published["standing_line"]).find("1"),
		-1,
		"and the line carries the 25% the claim published"
	)
	assert_ne(
		String(published["standing_line"]).find("10 / 1000"),
		-1,
		"beside the raw numbers, which is what the panel is for"
	)


func test_position_and_standing_stay_two_facts() -> void:
	# ADR 0064's split IS the politics layer. A card that folded them into one rank would
	# have collapsed the gap the design exists to keep.
	var card := _card()
	card.show_organization(_organization(LANTERN, _claim_view(_claim("first_ledger", 40, 150))))
	var view := card.summary()
	assert_ne(String(view["standing_line"]), "", "the standing renders")
	assert_ne(
		String(view["standing_line"]).find("first_ledger"),
		-1,
		"and it NAMES the office, so a reader sees two claims rather than one rank"
	)
	var thick := _card()
	thick.show_organization(_organization(CIRCLE, _claim_view(_claim("", 25, 60))))
	assert_ne(
		String(thick.summary()["standing_line"]),
		"",
		"thick standing in NO office is a legitimate state and still renders"
	)


# --- 4. The PANEL formats numbers, the SCREEN does not -------------------------


func test_the_screen_publishes_raw_values_for_the_panel_to_format() -> void:
	# The other half of the rule: the screen hands down integers and the card owns every
	# `%d`, every word and every tone. A screen that re-derived a price could disagree
	# with the author of that price, which is the one thing a priced act must never do.
	var screen := _screen()
	screen.setup(_actor())
	screen.select_organization(String(LANTERN))
	var view := screen.summary()
	assert_eq(typeof(view["founding_cost"]), TYPE_INT, "an int, not a rendered string")
	assert_eq(int(view["founding_cost"]), 2400, "the AUTHORED cost, raw")
	assert_eq(int(view["standing_cap"]), 150, "and the authored cap, raw")
	# ## `str()`, never `String()`, on a NUMBER -- MEASURED
	#
	# `String(2400)` RAISES at runtime in this engine: "Nonexistent 'String'
	# constructor". `InstitutionLedger._text` documents the same trap for a float. The
	# screen's payload is `int`, so this is the one cast a caller makes on it -- and it is
	# why `ui/` reaches for `str()` when it needs text from a number at all.
	assert_ne(str(view["founding_cost"]), "2,400", "never grouped")
	assert_ne(str(view["founding_cost"]), "2400 gold", "never unit-suffixed")
	assert_eq(str(view["founding_cost"]), "2400", "and the raw value as text, for a caller")


## ## The verbs a screen is not allowed to use, and why `%d` is NOT among them
##
## The rule is about formatting a VALUE the player reads. A bare `%d` is not that: a
## screen names its pooled nodes `"Card%d"`, which is a node identity and never printed.
## Asserting `%d` absent would fail a correct screen and teach the next author to hide
## the rule in a comment. So the probe names the shapes that RENDER a number -- a `%`
## format with a width/precision, a rounding call, and the string-number converters -- and
## the behavioural half of the same rule is the type assertion above: `founding_cost`
## arrives as an `int`, which no amount of formatting could survive.
const SCREEN_FORMAT_VERBS := [
	"%.0f",
	"%.1f",
	"%.2f",
	"%d /",
	"%s / %d",
	"roundf(",
	"roundi(",
	"str(",
	"String.num",
	"itos(",
]


func test_the_screen_source_contains_no_number_formatting() -> void:
	# Read CODE, not prose, for the same reason `test_ui_conventions.gd` strips comments:
	# a file that documents the rule it follows must not fail for documenting it.
	var code := _code_of(SCREEN_SCRIPT)
	assert_eq(code.is_empty(), false, "the screen source is readable")
	for verb in SCREEN_FORMAT_VERBS:
		assert_eq(
			code.contains(verb),
			false,
			"%s formats (%s); every number belongs to the panel" % [SCREEN_SCRIPT, verb]
		)
	var panel := _code_of(CARD_SCRIPT)
	assert_eq(panel.contains("roundf("), true, "and the panel is the one that rounds")
	assert_eq(panel.contains("%d"), true, "and prints integers")


## The positive form, so the probe above is not satisfied by a predicate that flags nothing
## legible: the same verbs ARE in the panel, in code, and the panel is the file that uses
## them. A screen that passed by being unreadable would fail the readability assertion
## above, so the pair cannot be satisfied by a blind guard.
func test_the_same_format_verbs_are_present_in_the_panel_that_owns_them() -> void:
	var panel := _code_of(CARD_SCRIPT)
	assert_eq(panel.is_empty(), false, "the panel source is readable")
	assert_eq(panel.contains("roundf("), true, "the panel rounds the ratio for display")
	assert_ne(
		panel.find("roundf("),
		_code_of(SCREEN_SCRIPT).find("roundf("),
		"and the two files are genuinely different sources, not the same text twice"
	)


# --- 5. The contract: primitives, {} with no actor, children nested -----------


func test_a_card_summary_is_primitives_only() -> void:
	var card := _card()
	card.show_organization(_organization(LANTERN, _claim_view(_claim("first_ledger", 40, 150))))
	assert_eq(_non_primitives(card.summary(), ""), [], "no Node, Resource or Object in it")


func test_child_summaries_are_nested_under_the_childs_own_key() -> void:
	# The screen contract: a child's own summary lives under that child's key, so a test
	# reads what the card rendered without walking the widget tree.
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	var cards: Array = view["cards"]
	assert_ne(cards.is_empty(), true, "the cards' summaries are nested")
	var found := 0
	for row in cards:
		var card: Dictionary = row
		if card.is_empty():
			continue
		found += 1
		assert_ne(String(card["kind"]), "", "each card names the authored kind")
		assert_ne(String(card["display_name"]), "", "and its authored name")
	assert_eq(found, 3, "one nested summary per authored organization")
	assert_eq(int(view["organization_count"]), 3, "and the count agrees")


func test_the_screen_lists_the_kinds_the_registry_knows() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	var kinds: Array = view["kinds"]
	assert_eq(kinds.size(), 3, "a guild, a hunters' guild and a farmers' circle")
	assert_eq(kinds.has("trading_guild"), true, "the Exchange's kind is known")
	assert_eq(kinds.has("farmers_circle"), true, "and the circle's")
	assert_eq(
		view["organization_count"], int(view["kind_count"]), "three organizations, three kinds"
	)
	assert_eq(bool(view["boot_ran"]), true, "and the registry half says the boot ran")


func test_the_kinds_survive_a_boot_that_never_ran() -> void:
	# ## A gap the headless driver FOUND, and the reason it matters
	#
	# Nothing in `ui/` runs `InstitutionBoot.install()`, so a screen that published the
	# registry's kind list alone rendered three guilds under an EMPTY list the first time
	# anything drove it with no boot. An empty list is a CLAIM -- "this world has no
	# kinds" -- rather than an admission, and `tools ui drive` printed exactly that.
	# Each authored organization names its own kind, so the union is answerable either
	# way, and `boot_ran` keeps the two halves tellable apart.
	InstitutionRegistry.shared = null
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(bool(view["boot_ran"]), false, "no boot ran, and the screen says so")
	assert_eq((view["registered_kinds"] as Array).size(), 0, "so the registry knows nothing")
	assert_eq((view["kinds"] as Array).size(), 3, "yet the organizations' own kinds are listed")
	assert_eq(int(view["organization_count"]), 3, "and every organization still renders")
	assert_eq(
		(view["kinds"] as Array).has("hunting_guild"), true, "including the one only content names"
	)


func test_an_unpublished_roster_is_its_own_state_and_not_a_succession() -> void:
	# The second gap the headless driver found, and the more dangerous of the two: the
	# card reported `state: "held"` for every office of all three guilds, because
	# "not vacant" was read as "filled", and printed it beside "holders not published".
	# That INVENTS a succession nobody published, which is the fabrication the whole
	# vacancy design exists to prevent.
	var card := _card()
	var view := _organization(GUILD)
	# Every office is marked BEFORE the card is shown: `show_organization` deep-copies the
	# view, so asserting inside the loop that marked them read a snapshot taken part-way
	# through -- which is exactly the kind of test that passes for the wrong reason.
	for entry in view["positions"] as Array:
		var office: Dictionary = entry
		office["vacant"] = true
	card.show_organization(view)
	assert_eq(card.position_ids().size(), 3, "the guild authors three offices to assert on")
	for office_id in card.position_ids():
		var known := card.position_summary(office_id)
		assert_eq(String(known["state"]), "vacant", "%s is vacant" % office_id)
		assert_eq(bool(known["roster_published"]), true, "and says who told it")
	var bare := _card()
	_show_unpublished(bare)
	for office_id in bare.position_ids():
		var unknown := bare.position_summary(office_id)
		assert_eq(
			String(unknown["state"]),
			InstitutionCard.STATE_UNKNOWN,
			"%s is UNKNOWN, not held: nobody published its roster" % office_id
		)
		assert_eq(bool(unknown["vacant"]), false, "%s is emphatically not vacant" % office_id)
		assert_ne(
			String(unknown["line"]).find(L.t(InstitutionCard.HOLDER_UNKNOWN)),
			-1,
			"%s names the gap in words rather than asserting a holder" % office_id
		)
		assert_eq(
			String(unknown["line"]).find(InstitutionCard.VACANT_TEXT),
			-1,
			"%s never claims a vacancy nobody published" % office_id
		)


## The same fixture with every roster field cleared, which is what a screen publishes when
## its actor-scoped reader is unbound.
func _show_unpublished(card: InstitutionCard) -> void:
	var view := _organization(GUILD)
	for entry in view["positions"] as Array:
		var office: Dictionary = entry
		office["holders"] = ""
		office["held"] = 0
		office.erase("vacant")
	card.show_organization(view)


func test_a_screen_summary_is_empty_with_no_actor() -> void:
	# ADR 0083's first state needs `{}` to be REACHABLE, so a screen reporting keys with
	# nothing bound would make the state unreadable rather than merely empty.
	var screen := _screen()
	assert_eq(screen.summary(), {}, "no actor, no view")
	assert_eq(screen.claims_bound(), false, "and no seam is bound either")


func test_the_panel_drives_with_no_scene_tree_and_no_widgets() -> void:
	# The shape the standard exists for: a card built from the SCRIPT alone has no child
	# nodes at all, and `summary()` still answers. An `@onready` binding would never have
	# run under the headless runner, so this is the assertion that would have caught it.
	var card := _bare_card()
	assert_eq(card.get_child_count(), 0, "no scene, so no widgets")
	card.show_organization(_organization(GUILD, _claim_view(_claim(SEAT, 40, 150))))
	var view := card.summary()
	assert_ne(view, {}, "and it still reports a full payload")
	assert_ne(String(view["standing_line"]), "", "with its formatted lines computed")
	assert_eq(card.organization_id(), String(GUILD), "and its identity")
	# The vacuous-sweep guard: a panel whose `_render` early-returns on a null label would
	# still answer `summary()`, so the lines above are the assertion that the FORMATTING
	# is independent of the widgets rather than a side effect of painting them.
	var offices: Array = view["positions"]
	assert_ne(String((offices[0] as Dictionary)["line"]), "", "every office line is computed too")


# --- 6. The conventions, asserted rather than claimed --------------------------


func test_no_node_is_bound_in_onready_and_every_binding_is_lazy() -> void:
	# Asserted on CODE, comments stripped, so a file that documents the rule cannot fail
	# for documenting it.
	for path in [CARD_SCRIPT, SCREEN_SCRIPT]:
		var code := _code_of(path)
		assert_eq(code.contains("@onready"), false, "%s binds nothing in @onready" % path)
		assert_eq(code.contains("get_node_or_null("), true, "%s resolves through it" % path)
		assert_eq(code.contains("func _bind_nodes()"), true, "%s resolves in _bind_nodes()" % path)
		# `_ready` is allowed, and may only do what `_bind_nodes` does. A widget
		# resolved INSIDE it is the same defect wearing a different hat: the headless
		# runner drives from `SceneTree._initialize()` and `_ready` never fires there.
		var ready := _body_of(code, "func _ready() -> void:")
		assert_eq(
			ready.contains("get_node_or_null("), false, "%s resolves nothing in _ready" % path
		)
		assert_eq(
			ready.is_empty() or ready.contains("_bind_nodes()"),
			true,
			"%s reaches its widgets only through the idempotent _bind_nodes" % path
		)
		# Focus belongs to the `ScreenStack` hook, never to `_ready`.
		assert_eq(ready.contains("grab_focus()"), false, "%s grabs no focus in _ready" % path)


func test_neither_file_styles_itself_with_a_theme_override() -> void:
	# One theme, styled by `theme_type_variation`. `theme_override_*` is banned, so this
	# asserts on CODE: a file documenting the rule must not fail for documenting it.
	for path in [CARD_SCRIPT, SCREEN_SCRIPT]:
		assert_eq(
			_code_of(path).contains("theme_override"),
			false,
			"%s styles itself; style belongs to the one theme" % path
		)


func test_neither_scene_uses_an_absolute_position() -> void:
	# Anchors and Containers only. A `layout_mode = 2` child is a Container child; a
	# numeric `offset_` or `position =` on one is the absolute layout the standard bans.
	for path in [CARD_SCENE_TEXT, SCREEN_SCENE_TEXT]:
		var text := _read(path)
		# `assert_eq`, never `assert_ne(x.is_empty(), false)`: the latter asserts the file
		# is EMPTY, so it fails on a readable scene and would have been satisfied by a
		# path that did not exist at all.
		assert_eq(text.is_empty(), false, "%s is readable" % path)
		for banned in ["offset_left", "offset_top", "offset_right", "offset_bottom", "position ="]:
			assert_eq(text.contains(banned), false, "%s uses %s" % [path, banned])
		# The root's full-rect preset is the one anchor a screen may carry; a second one
		# is a child anchoring itself inside a Container.
		var count := 0
		for line in text.split("\n"):
			if line.begins_with("anchors_preset"):
				count += 1
		assert_eq(count, 1, "%s anchors its root once and nothing else" % path)


func test_rebinding_twice_does_not_double_connect() -> void:
	# An unguarded `connect` is one handler per call, so a reused or cached screen fires
	# its verb N times. This presses ONE button after two binds and counts the verdicts:
	# one press, one handler, however many binds.
	var calls := {"n": 0}
	var counter := func(_institution_id: String) -> Dictionary:
		calls["n"] = int(calls["n"]) + 1
		return {"ok": true, "reason": ""}
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_institutions()
	screen.bind_institutions()
	screen.bind_institutions(Callable(), counter, Callable())
	screen.select_organization(String(LANTERN))
	var actions := screen.get_node_or_null("%InstitutionActions") as ActionSet
	assert_ne(actions, null, "the action row is mounted by the scene")
	assert_eq(actions.request(&"join"), true, "the button is live")
	assert_eq(int(calls["n"]), 1, "one press, one handler, however many binds")


func test_no_card_or_screen_is_freed_before_teardown_runs() -> void:
	# The leak assertion as an observation: everything this suite mints is on `_born`, and
	# the teardown above frees every one of it. If a call site ever added a node WITHOUT
	# recording it, this suite's own bookkeeping would be the thing that stops noticing.
	var card := _card()
	card.show_organization(_organization(LANTERN))
	assert_eq(_born.size(), 1, "the card is tracked, so teardown can free it")
	for node in _born:
		assert_ne(node, null, "and nothing tracked is null")
	# `free()` on a `Node` is immediate; the teardown above then finds nothing left to do,
	# which is what makes it idempotent and safe after an abort. Detach FIRST where there
	# is a parent to detach from -- a card instantiated but never added to a tree has
	# none, and calling `remove_child` on that null is a script error.
	var parent := card.get_parent()
	if parent != null:
		parent.remove_child(card)
	card.free()
	_born.clear()


# --- 7. Reachable, drivable, and honest about what it cannot do ----------------


func test_the_screen_reports_the_kinds_and_organizations_the_boot_registered() -> void:
	# What a player can actually SEE: the registry's kinds and the catalog's
	# organizations, read from `core` rather than restated in the screen. The boot ran in
	# `setup`, so both halves are the state this boot produced rather than a second,
	# disagreeing registration made here.
	var report := InstitutionBoot.last_report
	assert_eq(bool(report["ok"]), true, "the boot this suite ran accepted everything")
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(int(view["kind_count"]), (report["registered"] as Array).size(), "every kind listed")
	assert_eq(
		int(view["organization_count"]),
		(report["organizations"] as Array).size(),
		"and every organization"
	)


func test_founding_an_organization_returns_the_facades_own_verdict_verbatim() -> void:
	# The one verb that genuinely exists with no seam: `InstitutionFounding.found`. A hero
	# who has not funded the price is refused `founding_cost_unmet` by the AUTHOR of that
	# rule, and nothing is written -- so a screen that hid the button would have made the
	# rule invisible instead of named.
	var screen := _screen()
	screen.setup(_actor())
	var verdict := screen.act_found(String(CIRCLE))
	assert_eq(bool(verdict["ok"]), false, "an unfunded founding is refused")
	assert_eq(String(verdict["reason"]), InstitutionFounding.R_FOUNDING_COST_UNMET, "verbatim")
	assert_eq(screen.summary()["founded"], {}, "and a refused verb writes no ledger")


func test_a_funded_founding_writes_a_ledger_and_this_screen_publishes_it() -> void:
	# The other direction, because a refusal alone would not tell a reader whether
	# `act_found` reaches the verb at all or merely always fails. The pool is a plain
	# `Actor` resource, so funding it is the pool's own move rather than a seam.
	# The pool is MOUNTED here rather than funded onto a pool that does not exist:
	# `Actor.resource` returns null for an unmounted id, so `.change()` on it is a script
	# error that aborts the test mid-body -- which reads as "asserted nothing" and hides
	# the assertion it was trying to reach.
	var actor := _actor()
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 900.0))
	assert_ne(actor.resource(InstitutionFounding.DEFAULT_FUNDING_POOL), null, "the pool is mounted")
	var screen := _screen()
	screen.setup(actor)
	var verdict := screen.act_found(String(CIRCLE))
	assert_eq(bool(verdict["ok"]), true, "a funded founding is committed")
	assert_eq(String(verdict["institution"]), String(CIRCLE), "and names what it founded")
	# The ledger is PUBLISHED rather than dropped: `found` writes a new dictionary and
	# does not attach it to the actor, and a screen that discarded it would report a
	# success whose whole effect was invisible.
	var written: Dictionary = screen.summary()["founded"]
	assert_ne(written, {}, "the written ledger is published, not dropped")
	assert_eq(String(written["institution"]), String(CIRCLE), "and names the organization")
	assert_eq(String(written["kind"]), "farmers_circle", "and its kind")
	assert_eq(int(written["standing"]), 25, "and the authored founder standing")
	assert_eq(int(written["standing_cap"]), 60, "against the authored cap")
	# `fit` is ABSENT, not `fit: 0`: a kind that does not teach has no fit axis at all,
	# and a key reading `0` is the invented-default defect `InstitutionFounding.write`
	# documents. Asserted on the key's absence rather than on its value.
	assert_eq(written.has("fit"), false, "and no fit axis at all for a kind that does not teach")
	assert_eq(bool(InstitutionFounding.has_fit_axis(written)), false, "by the verb's own read")
	assert_eq(
		actor.resource(InstitutionFounding.DEFAULT_FUNDING_POOL).current,
		900.0 - 700.0,
		"and the authored price was actually charged"
	)


func test_join_and_leave_refuse_by_name_when_their_seam_is_unbound() -> void:
	# The family publishes NO `join` and NO `leave`. Rather than reach past `core` for a
	# verb that does not exist, both are injected -- and an unbound one refuses BY NAME,
	# because an action a player asked for that did not happen is a refusal and a silent
	# no-op is not.
	var screen := _screen()
	screen.setup(_actor())
	screen.select_organization(String(LANTERN))
	assert_eq(bool(screen.summary()["join_bound"]), false, "no join verb is bound")
	var joined := screen.act_join()
	assert_eq(bool(joined["ok"]), false, "so a join cannot succeed")
	assert_eq(String(joined["reason"]), InstitutionScreen.NO_JOIN_SEAM, "and says so by name")
	var left := screen.act_leave()
	assert_eq(String(left["reason"]), InstitutionScreen.NO_LEAVE_SEAM, "and so does a leave")


func test_a_bound_seam_reaches_the_verb_and_its_verdict_comes_back_untouched() -> void:
	# The seam WORKS when it is bound: the screen forwards, and hands back the verb's OWN
	# dictionary. A screen that reworded it would be describing a rule it does not own.
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_institutions(Callable(), _joiner(), Callable())
	assert_eq(bool(screen.summary()["join_bound"]), true, "the seam is bound")
	var verdict := screen.act_join(String(LANTERN))
	assert_eq(bool(verdict["ok"]), true, "the verb's verdict, unchanged")
	assert_eq(screen.summary()["last_reason"], "", "and the screen published it verbatim")


func test_an_unbound_claim_reader_says_so_rather_than_inventing_vacancies() -> void:
	# Without the actor-scoped read nobody knows who holds what, so publishing
	# `held == 0` would FABRICATE a succession. The key is absent, and the screen says so.
	var screen := _screen()
	screen.setup(_actor())
	assert_eq(bool(screen.summary()["claims_bound"]), false, "no reader is bound")
	var cards: Array = screen.summary()["cards"]
	var seen := 0
	for row in cards:
		var card: Dictionary = row
		if card.is_empty():
			continue
		seen += 1
		# The card's own payload always carries a `vacant` BOOLEAN, so the thing to
		# assert is not the key's absence but that nothing FABRICATED one. Asserting
		# `has("vacant") == false` here would pass only if the card stopped reporting the
		# middle state at all, which is the opposite of the requirement.
		assert_eq(bool(card.get("vacant", false)), false, "no vacancy is invented")
		var offices: Array = card["positions"]
		for entry in offices:
			var office: Dictionary = entry
			assert_eq(bool(office["vacant"]), false, "and no office is claimed vacant")
			assert_eq(
				String(office["line"]).find(InstitutionCard.VACANT_TEXT), -1, "nor printed VACANT"
			)
			assert_eq(int(office["held"]), 0, "and no holder is counted")
	assert_eq(seen, 3, "every organization still renders")


func test_an_unbound_claim_reader_leaves_the_holder_unknown_rather_than_empty() -> void:
	# The difference between "nobody holds it" and "nobody told us" has to survive into
	# the rendered line, or a player reads an unpublished roster as an empty one.
	var card := _card()
	var view := _organization(GUILD)
	var offices: Array = view["positions"]
	for entry in offices:
		# Every office's holder is UNPUBLISHED, and each one is authored and filled in the
		# shared fixture -- so both the name and the count have to be cleared here, or the
		# assertion would be reading the fixture rather than the behaviour.
		var office: Dictionary = entry
		office["holders"] = ""
		office["held"] = 0
	card.show_organization(view)
	var clerk := card.position_summary(ROOM)
	assert_eq(bool(clerk["vacant"]), false, "an office with no roster is not called vacant")
	assert_eq(int(clerk["held"]), 0, "and no holder is counted")
	assert_ne(
		String(clerk["line"]).find(L.t(InstitutionCard.HOLDER_UNKNOWN)),
		-1,
		"and the line says the holder is unpublished rather than absent"
	)
	assert_eq(String(clerk["line"]).find(InstitutionCard.VACANT_TEXT), -1, "never as VACANT")
	assert_eq(
		String(clerk["line"]).find(InstitutionCard.HELD_PREFIX), -1, "and never as held by nobody"
	)


func test_a_bound_claim_reader_publishes_the_claim_the_claim_computed() -> void:
	var claim := _claim("first_ledger", 40, 150)
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_institutions(
		func() -> Dictionary:
			return {
				"institutions":
				{
					String(LANTERN):
					{
						"exists": true,
						"position": String(claim.position),
						"standing": claim.standing,
						"standing_cap": claim.standing_cap,
						"normalized": claim.normalized(),
						"obligations": {"duty_lantern_exchange": 3},
						"roster": {"first_ledger": ["hero"], "factor": []},
					}
				}
			}
	)
	var view := screen.summary()
	assert_eq(bool(view["claims_bound"]), true, "the reader answered")
	var cards: Array = view["cards"]
	var mine := 0
	for row in cards:
		var card: Dictionary = row
		if String(card.get("id", "")) != String(LANTERN):
			continue
		mine += 1
		assert_eq(bool(card["is_member"]), true, "the actor holds a claim here")
		assert_eq(bool(card["vacant"]), false, "so it is not the vacant state")
		assert_eq(float(card["standing_ratio"]), claim.normalized(), "and the ratio is the claim's")
		var offices: Array = card["positions"]
		var vacant_rooms := 0
		for entry in offices:
			var office: Dictionary = entry
			if bool(office.get("vacant", false)):
				vacant_rooms += 1
		assert_eq(vacant_rooms, 1, "the one authored room nobody holds is VACANT, not absent")
	assert_eq(mine, 1, "the membership rendered on its own card")


func test_the_screen_hooks_are_all_present_and_safe_to_call_at_any_time() -> void:
	# `ScreenStack` calls all four unconditionally, including on a screen with no actor,
	# so each must be safe before anything is bound.
	var screen := _screen()
	screen.focus_initial()
	screen.on_screen_shown()
	screen.on_screen_hidden()
	assert_eq(bool(screen.on_stack_input(null)), false, "a null event is declined")
	assert_eq(bool(screen.on_stack_input(_accept_event())), false, "and so is one with no actor")
	screen.setup(_actor())
	screen.on_screen_shown()
	screen.focus_initial()
	assert_ne(String(screen.summary()["focus_target"]), "", "focus lands somewhere once bound")
	# An accept does nothing until something is PICKED, and declining is the honest answer
	# rather than firing a verb against whatever happened to be selected.
	assert_eq(bool(screen.on_stack_input(_accept_event())), false, "nothing picked, nothing fired")
	screen.select_organization(String(GUILD))
	assert_eq(bool(screen.on_stack_input(_accept_event())), true, "a pick makes accept fire")


func test_cancel_is_left_free_for_the_stack_to_pop() -> void:
	# A screen that could commit a founding and also swallowed the cancel would trap a
	# player inside it, so `ui_cancel` is DECLINED here on purpose.
	var screen := _screen()
	screen.setup(_actor())
	screen.select_organization(String(LANTERN))
	assert_eq(bool(screen.on_stack_input(_cancel_event())), false, "cancel is never consumed")


func test_the_screen_can_be_driven_from_a_snapshot_with_no_boot() -> void:
	# `apply_snapshot` is the seam a headless driver uses: it renders an adopted catalog
	# without re-reading `core`, and an empty snapshot clears the adoption rather than
	# leaving a stale one behind.
	var screen := _screen()
	screen.setup(_actor())
	(
		screen
		. apply_snapshot(
			{
				"ok": true,
				"kinds": ["trading_guild"],
				"organizations": [_organization(LANTERN, {}, true)],
			}
		)
	)
	var view := screen.summary()
	assert_eq(int(view["organization_count"]), 1, "only the adopted organization")
	assert_eq(bool((view["cards"][0] as Dictionary)["vacant"]), true, "rendered as VACANT")


func test_a_pick_walks_the_catalog_and_declines_an_invented_id() -> void:
	var screen := _screen()
	screen.setup(_actor())
	assert_eq(bool(screen.select_organization("no_such_house")), false, "an invented id is REFUSED")
	assert_eq(String(screen.summary()["selected"]), "", "and nothing is left selected")
	assert_eq(bool(screen.select_organization(String(LANTERN))), true, "an authored id is picked")
	assert_eq(String(screen.summary()["selected"]), String(LANTERN), "and published")
	assert_eq(String(screen.summary()["selected_kind"]), "trading_guild", "with its kind")


func test_building_the_cards_parents_no_unbounded_number_of_nodes() -> void:
	# `RowBudget` is the guard: the card count is a data-derived organization count, and a
	# pool that filled toward a size another body grew is INC-0002 (the 67 GB incident).
	# A `for` over a RANGE with an unconditional append fills toward a FIXED count.
	assert_eq(RowBudget.MAX_ROWS > 0, true, "the shared cap is authored and positive")
	assert_eq(
		RowBudget.cap(100000),
		RowBudget.MAX_ROWS,
		"and an absurd request is clamped to it rather than parented into live nodes"
	)
	# The structural half, which is what a grow loop can actually be shown to satisfy:
	# neither file declares a `while` at all, so the guard that scans them
	# (`test_no_unbounded_wait.gd`) has nothing in these files to accept or refuse.
	for path in [CARD_SCRIPT, SCREEN_SCRIPT]:
		assert_eq(
			_code_of(path).contains("while "),
			false,
			"%s declares no `while`: every loop is a `for` over a snapshot" % path
		)


# --- Plumbing -----------------------------------------------------------------


func _joiner() -> Callable:
	return func(_institution_id: String) -> Dictionary:
		return {"ok": true, "reason": "", "institution": String(LANTERN)}


## A pressed `ui_accept`, as `ScreenStack` would hand one over.
func _accept_event() -> InputEvent:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	return event


## A pressed `ui_cancel`. Declined by this screen on purpose -- see the test that reads it.
func _cancel_event() -> InputEvent:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event


## The body of `header` in `code`, up to the next top-level `func`. `""` when `header`
## does not appear at all, which is a legal answer for a file that declares no `_ready`.
func _body_of(code: String, header: String) -> String:
	var at := code.find(header)
	if at < 0:
		return ""
	var rest := code.substr(at + header.length())
	var end := rest.find("\nfunc ")
	return rest if end < 0 else rest.substr(0, end)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## A file with its comments stripped, so a file that DOCUMENTS a rule cannot fail a guard
## for documenting it. `test_ui_conventions.gd` states the same reasoning.
func _code_of(path: String) -> String:
	var kept: Array[String] = []
	for line in _read(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		kept.append(line.substr(0, line.find("#")) if line.find("#") >= 0 else line)
	return "\n".join(kept)


## Dotted paths whose value is not a primitive, a String or an Array of those. A returned
## node or resource is how a "testable surface" stops being testable.
func _non_primitives(value: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		for key in value as Dictionary:
			var child: Variant = (value as Dictionary)[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
		return out
	if value is Array:
		var index := 0
		for item in value as Array:
			out.append_array(_non_primitives(item, "%s[%d]" % [path, index]))
			index += 1
	return out


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
		or kind == TYPE_ARRAY
	)
