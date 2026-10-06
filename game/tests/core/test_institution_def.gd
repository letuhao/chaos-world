extends TestCase

## ## The PROOF: a brand-new kind of organization, authored as pure content
##
## ADR 0271 says the generic mod content family is named `institutions`, that each
## `.tres` declares its own `kind`, and that the catalog dispatches on it. This suite
## is the evidence that the claim is true **for a kind nobody has ever written a
## module for**: three organizations — a trading guild, a hunting guild and a farmers'
## circle — load off disk, register themselves, are foundable by the GENERIC
## `InstitutionFounding.found`, and no line of GDScript anywhere in the path names
## any of them.
##
## The two cases that decide the slice:
##
##   - `test_the_directory_is_discovered_with_no_kind_written_down_anywhere` — the
##     boot names no kind, no organization and no def path, so "add a kind" is a file
##     drop and nothing else.
##   - `test_a_trading_guild_is_founded_generically_and_produces_a_real_ledger` —
##     `found` works for a kind that has no module. A foundation that only worked for
##     sects would be the single most important thing this slice could have found.
##
## **Nothing loaded off disk is ever mutated here.** Godot caches a `load()`ed
## resource process-wide and the runner drives every suite in ONE process, so writing
## to a shipped `.tres` would leak the edit into every suite after this one. The defs
## a case edits are built in code instead.

const BOOT_FILE := "res://src/app/institution_boot.gd"
const DEF_FILE := "res://src/core/institution_def.gd"
const POSITION_FILE := "res://src/core/institution_position_def.gd"

## The three shipped organizations, by path, and the kinds they declare. Written
## here as EXPECTATIONS to compare against — never as a list the boot reads.
const LANTERN := "res://data/institutions/lantern_exchange.tres"
const GREY_HORIZON := "res://data/institutions/grey_horizon_hunt.tres"
const TORRENT_FIELD := "res://data/institutions/torrent_field_circle.tres"

const TRADING_GUILD := &"trading_guild"
const HUNTING_GUILD := &"hunting_guild"
const FARMERS_CIRCLE := &"farmers_circle"
const CLAN := &"clan"
const CARAVAN := &"caravan_company"

const FOUNDER := "t_founder"
const POOL := InstitutionFounding.DEFAULT_FUNDING_POOL
## A stat this suite reads, because ADR 0084's content is that the ONE allowed
## percent lands on an authored allowlist and nothing else moves.
const RECOGNISED := Stat.INSIGHT_GAIN

## Every verb a generic institution def or its boot must never grow. If one of these
## appears, a modder's `.tres` has grown a way to hand out a stat, and ADR 0084 says
## an institution never may. `tools arch` cannot see a method that does not exist, so
## the guard is this test — the shape `test_sect_no_power.gd` uses.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"grant_modifier",
	"contribute",
]

## Each surface asserted as a WHOLE rather than only by the absence of the forbidden
## ones, so a verb added later fails here rather than slipping past the word list.
const PUBLISHED_DEF := [
	"authored_capabilities",
	"check",
	"check_content",
	"claimed_territories",
	"declares",
	"declares_locally",
	"founding_profile",
	"funding_pool",
	"has_position",
	"has_tag",
	"has_territory_claim",
	"has_top_position",
	"member_obligation_lines",
	"position",
	"position_ids",
	"top_position",
	"treasury_prefix",
]

const PUBLISHED_POSITION := [
	"duty_terms",
	"grants",
	"has_room",
	"is_seat",
	"obligation_lines",
	"room",
]

const PUBLISHED_BOOT := [
	"install",
	"register_def",
	"summary",
]

var _registry: InstitutionRegistry = null
var _born: Array = []


func setup() -> void:
	_registry = InstitutionRegistry.new()
	InstitutionBoot.install(_registry)
	# A clan, for the bloodline contrast: the ONE tier that cannot be founded, and so
	# the one a guild's answer has to be told apart from.
	_registry.register(
		CLAN,
		"ClanDef",
		[InstitutionRegistry.CAP_IS_BORN_TO, InstitutionRegistry.CAP_HAS_OFFICES],
		null
	)


## Everything instantiated here is released here, and **`free()` is called only on
## `Node`s** — `Actor` extends `RefCounted` and `Object.free()` on one is a SCRIPT
## ERROR that ABORTS the rest of `teardown` (measured in `test_institution_foundation`).
## This suite mints no `Node` at all: an `Actor` and a `Resource` are both released by
## dropping this array, which is why `_born` exists and not a `free()` per case.
func teardown() -> void:
	_born.clear()
	if _registry != null:
		_registry.clear()
		_registry = null


## An actor with a founding fund. `ResourcePool.new(id, maximum)` starts FULL, so the
## second argument is both the ceiling and the balance.
func _actor(actor_id: StringName = &"founder", funds: float = 5000.0) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(POOL, funds))
	_born.append(actor)
	return actor


## A def built in code, so a case can author content no `.tres` on disk holds. Never
## mutate a `load()`ed one — see the class note.
func _def(
	kind_id: StringName,
	inst_id: StringName,
	caps: Array[StringName],
	positions: Array[InstitutionPositionDef] = [],
	top: StringName = &""
) -> InstitutionDef:
	var def := InstitutionDef.new()
	def.kind = kind_id
	def.id = inst_id
	def.capabilities = caps
	def.positions = positions
	def.top_position_id = top
	_born.append(def)
	return def


func _position(position_id: StringName, capacity: int = 0, duty: int = 0) -> InstitutionPositionDef:
	var office := InstitutionPositionDef.new()
	office.id = position_id
	office.capacity = capacity
	office.duty_per_period = duty
	office.patronage_per_period = duty
	_born.append(office)
	return office


# --- The discovery proof: a new kind is a file, not a code change ----------------


## ## The whole slice in one case: three organizations, three kinds, no code
##
## `install()` walks ONE directory and registers whatever it finds. The registry then
## answers for all three kinds, each bound to a real def script and each labelled by
## the `class_name` the `.tres` was actually authored on.
func test_the_directory_is_discovered_with_no_kind_written_down_anywhere() -> void:
	var report := InstitutionBoot.install(_registry)
	assert_eq(
		bool(report["ok"]), true, "every shipped file was accepted: %s" % str(report["refused"])
	)
	assert_eq((report["refused"] as Array).size(), 0, "and nothing was refused")
	assert_eq(
		_sorted(_registry.kinds()),
		["clan", "farmers_circle", "hunting_guild", "trading_guild"],
		"three content kinds were discovered, plus this suite's clan fixture"
	)
	# The def SCRIPT is read off the loaded resource, so each row is bound and named
	# without this repo's boot file knowing what `InstitutionDef` is.
	for kind in [TRADING_GUILD, HUNTING_GUILD, FARMERS_CIRCLE]:
		assert_eq(_registry.def_type_of(kind), "InstitutionDef", "%s names its def type" % kind)
		assert_eq(_registry.def_script_bound(kind), true, "%s is bound to a def script" % kind)


## ## The structural half: the boot names NO kind, no organization and no def path
##
## This is what makes "a modder adds a kind by dropping in a `.tres`" a measurement
## rather than a claim. Were the boot to enumerate its rows, dropping a file in would
## do nothing and every one of these assertions would still pass while the feature
## was quietly manual — so the shipped kind ids and file names are read out of the
## source and must be absent from it.
func test_the_boot_source_names_no_kind_no_organization_and_no_def_path() -> void:
	var body := FileAccess.get_file_as_string(BOOT_FILE)
	assert_ne(body, "", "the boot file is readable")
	for authored in [
		String(TRADING_GUILD),
		String(HUNTING_GUILD),
		String(FARMERS_CIRCLE),
		"lantern_exchange",
		"grey_horizon_hunt",
		"torrent_field_circle",
		"institution_def.gd",
	]:
		assert_eq(_calls(body, authored), 0, "the boot never writes '%s' down" % authored)
	# ## And it walks NO directory of its own — the catalog does, and there is one loader
	#
	# The assertion used to be that the boot NAMES the content root, which proved it walked
	# one. It is now the stronger half: the boot holds no root constant and no scan at all,
	# because `InstitutionDefCatalog` merges the family and the boot reads it. Two loaders
	# naming one directory from two layers is the duplication `test_institution_def_catalog.gd`
	# had to assert in step so it could not rot; with the second one gone the boot's source
	# must be UNABLE to name a directory at all, which is what makes a reintroduced second
	# scan a red assertion rather than a silent split.
	assert_eq(_calls(body, "res://data/institutions"), 0, "and it names no content root of its own")
	assert_eq(_calls(body, "ContentScan"), 0, "and it walks no directory itself")


## The shipped content, loaded and read back. Three DIFFERENT capability sets, chosen
## so each exercises a different branch of the generic `found`: an organization with
## offices, one with offices AND a claim over ground, and one with a claim and NO
## offices at all. **None of them claims `is_born_to` or `teaches`** — a guild you
## join is not a family you are born into, and none of the three teaches anything.
func test_all_three_shipped_organizations_load_and_read_their_capability_sets() -> void:
	# Expectations are PLAIN strings and sorted by the case, never `StringName`
	# literals: `InstitutionRegistry.capabilities_of` sorts an `Array[StringName]` and
	# this engine does not order interned ids by their string value, so a positional
	# expectation against it would be testing the registry rather than the content.
	var expected := {
		String(LANTERN): [String(TRADING_GUILD), ["has_offices"]],
		String(GREY_HORIZON): [String(HUNTING_GUILD), ["has_offices", "has_territory"]],
		String(TORRENT_FIELD): [String(FARMERS_CIRCLE), ["has_territory"]],
	}
	for path in expected.keys():
		var row: Array = expected[path]
		var def := load(String(path)) as InstitutionDef
		assert_ne(def, null, "%s loads" % path)
		assert_eq(String(def.kind), String(row[0]), "%s declares its kind" % path)
		assert_eq(_sorted(_registry.capabilities_of(def.kind)), row[1], "%s's capabilities" % path)
		# The def's OWN ordered read is string-canonical, which is what `register_def`
		# compares against: a set, in a stable order, whatever the registry returns.
		assert_eq(
			_names(def.authored_capabilities()), row[1], "%s declares them itself, sorted" % path
		)
		# And the def itself is not merely loadable but CONSISTENT with the row.
		var verdict := def.check(_registry)
		assert_eq(
			bool(verdict["ok"]), true, "%s passes check(): %s" % [path, str(verdict["reason"])]
		)
		assert_eq(
			bool(_registry.has_capability(def.kind, InstitutionRegistry.CAP_IS_BORN_TO)["has"]),
			false,
			"%s is not born to" % path
		)
		assert_eq(
			bool(_registry.has_capability(def.kind, InstitutionRegistry.CAP_TEACHES)["has"]),
			false,
			"%s does not teach" % path
		)
	# The three sets are genuinely different from one another, which is the whole
	# point: a family that all reduce to "a guild" would prove nothing.
	var shapes := [
		_sorted(_registry.capabilities_of(TRADING_GUILD)),
		_sorted(_registry.capabilities_of(HUNTING_GUILD)),
		_sorted(_registry.capabilities_of(FARMERS_CIRCLE))
	]
	for left in range(shapes.size()):
		for right in range(left + 1, shapes.size()):
			assert_ne(shapes[left], shapes[right], "kinds %d and %d differ" % [left, right])


# --- An unregistered kind refuses by name, and never loads as a default -----------


## ## A def whose `kind` no boot registered REFUSES, and is never a generic default
##
## The failure this exists against is a catalog that treats "no such kind" as "some
## kind that cannot X" and then gates on an institution that does not exist. So the
## refusal carries a NAME, `def.check` returns it, and nothing anywhere substitutes a
## default kind, a default capability set or a default def type.
func test_a_def_whose_kind_nobody_registered_refuses_by_name_and_never_defaults() -> void:
	var office := _position(&"captain", 1, 1)
	var caravan := _def(
		CARAVAN, &"t_caravan", [InstitutionRegistry.CAP_HAS_OFFICES], [office], &"captain"
	)
	var verdict := caravan.check(_registry)
	assert_eq(bool(verdict["ok"]), false, "an unregistered kind is refused")
	assert_eq(String(verdict["reason"]), InstitutionRegistry.R_UNKNOWN_KIND, "and names the cause")
	# The registry's own answer is a refusal too, never a `false` that reads as "this
	# kind lacks the capability".
	var ask := _registry.has_capability(CARAVAN, InstitutionRegistry.CAP_HAS_OFFICES)
	assert_eq(bool(ask["ok"]), false, "the registry does not know the kind")
	assert_eq(String(ask["reason"]), InstitutionRegistry.R_UNKNOWN_KIND, "and names it")
	assert_eq(bool(ask["has"]), false, "so it grants nothing")
	# And a `found` against it writes nothing at all — no ledger, no charge.
	var actor := _actor(&"founder", 5000.0)
	var before := _fingerprint(actor)
	var report := InstitutionFounding.found(_registry, actor, caravan.founding_profile(), FOUNDER)
	assert_eq(bool(report["ok"]), false, "and founding one is refused")
	assert_eq(String(report["reason"]), InstitutionRegistry.R_UNKNOWN_KIND, "naming the cause")
	assert_eq(_fingerprint(actor), before, "having changed nothing whatever")
	# A def naming NO kind is a different fault with its own name.
	var nameless := _def(&"", &"t_nameless", [])
	assert_eq(
		String(nameless.check(_registry)["reason"]),
		InstitutionDef.R_NO_KIND,
		"a kindless def says so"
	)


## ## A guild is a LEGITIMATE kind, and a bloodline-shaped answer refuses
##
## The three-state vocabulary is the whole of this case. `{}` is "does not exist";
## `{ok: true, has: false}` is "this kind exists and does not do that" — a legitimate
## authored state, not a zero; `{ok: false, reason: R}` is "refused". A guild asking
## whether it is born to gets the SECOND, and `found` on it lands. A clan gets the
## THIRD, because it genuinely cannot be founded by anybody at all.
func test_a_guild_is_a_legitimate_kind_and_a_bloodline_shaped_answer_refuses() -> void:
	var ask := _registry.has_capability(TRADING_GUILD, InstitutionRegistry.CAP_IS_BORN_TO)
	assert_eq(bool(ask["ok"]), true, "the guild is a kind that exists")
	assert_eq(bool(ask["has"]), false, "which is not born to anyone")
	assert_eq(String(ask["reason"]), "", "so there is no refusal to report")
	# So a guild is FOUNDABLE, and the ledger names the kind it actually is.
	var actor := _actor(&"guild_founder", 5000.0)
	var guild := load(LANTERN) as InstitutionDef
	var report := InstitutionFounding.found(_registry, actor, guild.founding_profile(), FOUNDER)
	assert_eq(
		bool(report["ok"]), true, "a guild is founded by an actor: %s" % str(report["reason"])
	)
	assert_eq(
		String((report["ledger"] as Dictionary)["kind"]),
		String(TRADING_GUILD),
		"and it is a trading guild"
	)
	# The contrast: a clan is refused the SAME question, by NAME, from the ONE flag
	# that writes the answer (ADR 0271: no second `can_found` that could disagree).
	var clan := _def(
		CLAN, &"t_house", [InstitutionRegistry.CAP_HAS_OFFICES], [_position(&"head", 1, 1)], &"head"
	)
	var refused := InstitutionFounding.found(
		_registry, _actor(&"heir", 5000.0), clan.founding_profile(), FOUNDER
	)
	assert_eq(bool(refused["ok"]), false, "a clan is inherited, never founded")
	assert_eq(
		String(refused["reason"]),
		InstitutionFounding.R_KIND_CANNOT_BE_FOUNDED,
		"and the flag-derived refusal names itself"
	)


# --- The headline: generic `found` works for a guild ------------------------------


## ## `found` works for a kind that has NO MODULE. This is the slice.
##
## The authored `.tres` alone produces the profile; the GENERIC verb costs the
## authored price, seats the founder in the authored top office, opens the treasury
## lines the authored offices carry and writes the membership line. Nothing in this
## path names a guild, a sect, or any other module.
func test_a_trading_guild_is_founded_generically_and_produces_a_real_ledger() -> void:
	var actor := _actor(&"guild_founder", 5000.0)
	var guild := load(LANTERN) as InstitutionDef
	var report := InstitutionFounding.found(_registry, actor, guild.founding_profile(), FOUNDER)
	assert_eq(bool(report["ok"]), true, "the founding landed: %s" % str(report.get("reason", "")))
	assert_eq(int(report["charged"]), 2400, "it charged the authored cost")
	assert_almost_eq(actor.resource(POOL).current, 2600.0, "and took it off the fund")
	var ledger: Dictionary = report["ledger"]
	assert_eq(
		String(ledger["institution"]), "lantern_exchange", "the ledger names the organization"
	)
	assert_eq(String(ledger["kind"]), String(TRADING_GUILD), "and the kind it is")
	assert_eq(String(ledger["position"]), "first_ledger", "the founder is seated in the top office")
	assert_eq(String(ledger["founder_id"]), FOUNDER, "and named as the founder")
	assert_eq(int(ledger["standing"]), 40, "with the authored founder standing")
	assert_eq(int(ledger["standing_cap"]), 150, "against the authored cap")
	assert_eq(
		(ledger["roster"] as Dictionary)["first_ledger"], [FOUNDER], "and in the roster of ids"
	)
	# A treasury is a LEDGER OF OBLIGATION LINES ON IDS, never a pile of items.
	var treasury: Dictionary = ledger["treasury"]
	assert_eq(int(treasury["treasury_lantern_exchange_all"]), 1, "the opening line opened")
	assert_eq(
		int(treasury["treasury_lantern_exchange_duty_first_ledger"]), 3, "the seat's duty line"
	)
	assert_eq(
		int(treasury["treasury_lantern_exchange_patronage_first_ledger"]),
		3,
		"and the seat's patronage"
	)
	assert_eq(
		int(treasury["treasury_lantern_exchange_duty_clerk"]),
		1,
		"plus every other office's own rate"
	)
	# The founder owes the membership line AND the office's, merged per term by the
	# LARGER count (two authored statements about one debt are one debt).
	var owed: Dictionary = ledger["obligation"]
	assert_eq(int(owed["duty_lantern_exchange"]), 1, "the price of belonging at all")
	assert_eq(int(owed["duty_first_ledger"]), 3, "and what the seat itself costs")
	assert_eq(InstitutionLedger.is_save_safe(ledger), true, "and the ledger is save-safe")
	# A guild teaches nothing, so its ledger has NO FIT AXIS AT ALL — not zero, absent.
	assert_eq(ledger.has("fit"), false, "a kind that cannot teach has no fit key")
	assert_eq(InstitutionFounding.has_fit_axis(ledger), false, "and no fit axis")


## ## The organization that authors NO offices: thick standing, no position
##
## The farmers' circle declares `has_territory` and nothing else. `found` therefore
## does NOT refuse it for naming no top office — that refusal belongs to a kind that
## AUTHORS offices — and the founder holds standing in no position at all. That is
## the state ADR 0064's two-part split exists to make expressible, and it is the
## cheapest organization in the directory (land and a ditch) with the thinnest
## recognition: worth is priced in effort.
func test_a_kind_that_authors_no_offices_seats_nobody_and_that_is_a_legitimate_state() -> void:
	var actor := _actor(&"ditch_builder", 2000.0)
	var circle := load(TORRENT_FIELD) as InstitutionDef
	var report := InstitutionFounding.found(_registry, actor, circle.founding_profile(), FOUNDER)
	assert_eq(
		bool(report["ok"]),
		true,
		"a circle with no offices is still foundable: %s" % str(report.get("reason", ""))
	)
	assert_eq(int(report["charged"]), 700, "it charges the authored price")
	assert_almost_eq(actor.resource(POOL).current, 1300.0, "and takes it off the fund")
	var ledger: Dictionary = report["ledger"]
	assert_eq(String(ledger["position"]), "", "the founder holds no position at all")
	assert_eq(
		(ledger["roster"] as Dictionary).size(), 0, "so the roster is empty rather than a fake row"
	)
	assert_eq(int(ledger["standing"]), 25, "while holding real standing")
	var read := InstitutionLedger.read(ledger)
	assert_eq(bool(read["holds_position"]), false, "so `holds_position` answers false")
	assert_eq(bool(read["exists"]), true, "while the institution still exists")
	assert_eq(bool(read["corrupt"]), false, "and is not corrupt — this is a state, not a fault")
	# The treasury still opens its one line: everybody in them something from the day
	# they walk in, even a circle with no offices to fund them.
	assert_eq(
		int((ledger["treasury"] as Dictionary)["treasury_torrent_field_circle_all"]),
		1,
		"the opening line still opened"
	)
	assert_eq(
		int((ledger["obligation"] as Dictionary)["duty_torrent_field_circle"]),
		1,
		"and the price of belonging"
	)


# --- Position and standing never derive from each other ---------------------------


## ADR 0064 carried forward by ADR 0083: the two numbers are INDEPENDENT. Each
## direction is asserted separately, because a design that collapsed the pair into one
## number would pass a single combined check — it would have no second number to
## contradict. A guild member may hold a room on thin standing, and may hold thick
## standing in no office at all; that gap is the whole politics layer.
func test_position_and_standing_never_derive_from_each_other_for_a_guild() -> void:
	var guild := load(LANTERN) as InstitutionDef
	var ledger := InstitutionFounding.write(
		_registry, guild.founding_profile(), FOUNDER, "first_ledger"
	)
	assert_eq(
		int(InstitutionLedger.read(ledger)["standing"]), 40, "the founder stands at 40 of 150"
	)

	# Direction one: a promotion writes the POSITION and leaves standing alone. Every
	# writer RETURNS its replacement under `"ledger"` and mutates nothing, so the
	# assignment IS the caller's half of the contract.
	var promoted := InstitutionLedger.promote(ledger, &"clerk")
	assert_eq(bool(promoted["ok"]), true, "the promotion landed")
	ledger = promoted["ledger"]
	assert_eq(String(InstitutionLedger.read(ledger)["position"]), "clerk", "the position moved")
	assert_eq(int(InstitutionLedger.read(ledger)["standing"]), 40, "and standing did NOT")

	# Direction two: a standing change moves STANDING and leaves the position alone.
	var moved := InstitutionLedger.move_standing(ledger, 25)
	assert_eq(bool(moved["ok"]), true, "the standing change landed")
	ledger = moved["ledger"]
	assert_eq(int(InstitutionLedger.read(ledger)["standing"]), 65, "standing moved")
	assert_eq(
		String(InstitutionLedger.read(ledger)["position"]), "clerk", "and the position did NOT"
	)


# --- Refusals, save safety and corruption -----------------------------------------


## ## ADR 0044 as a MEASUREMENT: a refused `found` writes nothing, byte for byte
##
## Every refusal returns above the point at which the pool is touched and the ledger
## is built, so there is no branch on which a refusal has already moved a number. This
## compares the actor's WHOLE save payload and the pool balance across every way a
## guild founding can refuse.
func test_a_refused_guild_founding_writes_nothing_byte_for_byte() -> void:
	var guild := load(LANTERN) as InstitutionDef
	var nameless := guild.founding_profile()
	nameless["institution_id"] = ""
	var seatless := guild.founding_profile()
	seatless["top_position"] = ""
	var refusals := [
		["no actor", null, guild.founding_profile()],
		[
			"unregistered kind",
			_actor(&"a", 5000.0),
			(
				_def(
					CARAVAN,
					&"t_c",
					[InstitutionRegistry.CAP_HAS_OFFICES],
					[_position(&"c", 1, 1)],
					&"c"
				)
				. founding_profile()
			),
		],
		[
			"born to",
			_actor(&"b", 5000.0),
			(
				_def(
					CLAN,
					&"t_h",
					[InstitutionRegistry.CAP_HAS_OFFICES],
					[_position(&"h", 1, 1)],
					&"h"
				)
				. founding_profile()
			),
		],
		["no institution", _actor(&"c", 5000.0), nameless],
		["no top position", _actor(&"d", 5000.0), seatless],
		["cost unmet", _actor(&"e", 10.0), guild.founding_profile()],
	]
	for entry in refusals:
		var label: String = entry[0]
		var actor: Actor = entry[1]
		var profile: Dictionary = entry[2]
		var before := {} if actor == null else _fingerprint(actor)
		var report := InstitutionFounding.found(_registry, actor, profile, FOUNDER)
		assert_eq(bool(report["ok"]), false, "%s refused" % label)
		assert_ne(String(report["reason"]), "", "%s names a reason" % label)
		if actor != null:
			assert_eq(_fingerprint(actor), before, "%s changed nothing at all" % label)


## ## The guild ledger round-trips through the JSON hop
##
## `Actor.to_dict` copies `module_data` VERBATIM and converts only the OUTER key, so a
## `StringName` key, a `Resource`, an `Actor` or a `Vector2` would reach the save
## untouched and break every round trip — **and no checker in this repo can see it**.
## `JSON.parse_string` returns every number as a float and `JSON.stringify` renders a
## float as `35.0`, so BOTH sides go through `_through_json` and the FACTS are
## compared rather than the representation.
func test_a_guild_ledger_round_trips_through_the_json_hop() -> void:
	var actor := _actor(&"guild_founder", 5000.0)
	var guild := load(LANTERN) as InstitutionDef
	var ledger: Dictionary = (
		InstitutionFounding.found(_registry, actor, guild.founding_profile(), FOUNDER)["ledger"]
	)
	actor.set_module_data(&"t_institution", ledger)
	var parsed = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(parsed, null, "the payload parses")
	var restored := Actor.from_dict(parsed as Dictionary)
	assert_ne(restored, null, "and the body comes back")
	var read_back: Dictionary = restored.get_module_data(&"t_institution")
	assert_eq(
		JSON.stringify(_through_json(read_back)),
		JSON.stringify(_through_json(ledger)),
		"the guild ledger came back with the same facts"
	)
	assert_eq(String(read_back["kind"]), String(TRADING_GUILD), "and still names the guild")
	assert_eq(int(read_back["standing"]), 40, "with its standing")
	assert_eq(InstitutionLedger.is_save_safe(read_back), true, "and is still save-safe")
	assert_eq(
		JSON.stringify(_through_json(read_back)),
		JSON.stringify(_through_json(ledger)),
		"a second hop changes nothing"
	)


## ## A corrupt payload is diagnosed as EMPTY, never partially applied
##
## Half a guild ledger is worse than none: it silently changes what the player owes.
## Each of these would RAISE under a raw `String(...)` cast — `String(42.0)` is a
## script error in GDScript, not `"42.0"` — so a reader that cast would abort the load
## instead of reading as empty.
func test_a_corrupt_guild_payload_is_diagnosed_as_empty_and_never_partially_applied() -> void:
	for bad in [
		{"institution": 42.0, "position": "first_ledger", "standing": 40},
		{"institution": "lantern_exchange", "position": Vector2(1.0, 2.0)},
		{"institution": "lantern_exchange", "standing": "not a number"},
		{"institution": "lantern_exchange", "treasury": 42.0},
		{"institution": "lantern_exchange", "obligation": "not a dictionary"},
	]:
		var read := InstitutionLedger.read(bad)
		assert_eq(String(read["institution"]), "", "a corrupt field discards the whole record")
		assert_eq(bool(read["corrupt"]), true, "and says so rather than half-reading it")
		assert_eq(String(read["reason"]), InstitutionLedger.R_CORRUPT_PAYLOAD, "naming the cause")
		assert_eq(int(read["standing"]), 0, "so no half state survives")
	# An ABSENT field is different and normal: a member who holds no position has none.
	var absent := InstitutionLedger.read({"institution": "lantern_exchange"})
	assert_eq(bool(absent["corrupt"]), false, "an absent field is not corruption")
	assert_eq(String(absent["position"]), "", "it reads as no position")


# --- The two invariants nothing in code can see -----------------------------------


## ## ADR 0084: an institution grants recognition, access and transmission, and NEVER
## power. Neither generic def type nor the boot publishes a verb that can touch a
## stat — so a modder's `.tres` has no way to buy one, however it is authored.
func test_no_generic_institution_verb_can_touch_a_stat() -> void:
	for pair in [
		[InstitutionDef, PUBLISHED_DEF],
		[InstitutionPositionDef, PUBLISHED_POSITION],
		[InstitutionBoot, PUBLISHED_BOOT],
	]:
		var klass: GDScript = pair[0]
		var published := _published(klass)
		assert_eq(published.is_empty(), false, "%s publishes a readable method list" % klass)
		for verb in FORBIDDEN_VERBS:
			assert_eq(published.has(verb), false, "%s publishes no '%s'" % [klass, verb])
		assert_eq(published, pair[1], "%s is exactly the surface it claims" % klass)
	# And neither core file reaches for a base write or a modifier either: `set_base`
	# bypasses the stack, cannot be stripped, and DOES satisfy `get_base` — exactly how
	# an institution would smuggle a member past the gates meant to test them.
	for rel in [DEF_FILE, POSITION_FILE, BOOT_FILE]:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for forbidden in ["set_base", "add_base", "add_provider", "add_modifier", "add_status"]:
			assert_eq(_calls(body, forbidden), 0, "%s never calls %s" % [rel.get_file(), forbidden])


## ## ADR 0084's SECOND MEASUREMENT, applied to a guild's own number
##
## Two halves, and both matter. **First: founding a guild grants nothing at all** — no
## derived stat moves, because the generic def has no stat field and the generic boot
## writes no modifier. **Second: the ONE recognition number that does exist
## (`InstitutionClaim.standing_percent`) is realm-invariant in RATIO**, so a percent
## rides the member's own sheet instead of being folded into a base — which is what
## makes "a percent, never a flat" a property rather than a hope.
func test_a_guilds_recognition_is_realm_invariant_in_ratio_and_founding_writes_no_modifier(
) -> void:
	var shallow := _realm_scaled_actor(&"shallow", 1)
	var deep := _realm_scaled_actor(&"deep", 30)
	# The BEFORE values, read off the DERIVED stat rather than `get_base`: a derived
	# stat is recomputed from its attributes, so its base is not the value a percent
	# rides, and dividing the after by the base is a ratio of two unrelated numbers.
	var shallow_before := shallow.stats.derived(RECOGNISED)
	var deep_before := deep.stats.derived(RECOGNISED)
	assert_ne(deep_before, shallow_before, "R30 really is a deeper sheet than R1")
	var guild := load(LANTERN) as InstitutionDef
	var profile := guild.founding_profile()
	var founded_shallow := InstitutionFounding.found(_registry, shallow, profile, FOUNDER)
	var founded_deep := InstitutionFounding.found(_registry, deep, profile, FOUNDER)
	assert_eq(bool(founded_shallow["ok"]), true, "the guild founded at R1")
	assert_eq(bool(founded_deep["ok"]), true, "and at R30")
	assert_almost_eq(
		shallow.stats.derived(RECOGNISED), shallow_before, "founding moved no stat at R1"
	)
	assert_almost_eq(deep.stats.derived(RECOGNISED), deep_before, "nor at R30")

	# The recognition the founder's standing earned, applied as the ONE permitted
	# PERCENT. A `1.0` ratio would be the claim that a percent moves nothing, which is
	# the opposite of what ADR 0084 grants — so it is asserted at exactly its value.
	var standing := int((founded_shallow["ledger"] as Dictionary)["standing"])
	var percent := InstitutionClaim.standing_percent(standing)
	assert_ne(percent, 0.0, "a founder's standing really is recognised")
	assert_almost_eq(percent, 0.04, "as the standing's own rate, well under the cap")
	for actor in [shallow, deep]:
		actor.stats.add_modifier(
			StatModifier.new(RECOGNISED, Stat.Op.PERCENT, percent, &"guild:lantern_exchange")
		)
	var at_r1 := _ratio(shallow, RECOGNISED, shallow_before)
	var at_r30 := _ratio(deep, RECOGNISED, deep_before)
	assert_almost_eq(at_r1, at_r30, "the recognition is the same RATIO at R1 and at R30")
	assert_almost_eq(at_r1, 1.0 + percent, "and the ratio IS the recognition itself, and only it")


# --- The two authoring slips the def refuses --------------------------------------


## The registry holds ONE row per kind, so it cannot see that a second `.tres` claimed
## an id whose row is already bound to a DIFFERENT def class. Folding it would be the
## silent id collision ADR 0184 §5 forbids — a modder reusing a shipped kind id on
## their own subclass would watch it be ignored with nothing said, while the row kept
## instantiating the first class. Refused by name instead.
func test_a_second_def_class_claiming_a_registered_kind_is_refused_and_never_folded() -> void:
	var foreign := InstitutionRegistry.new()
	foreign.register(
		FARMERS_CIRCLE,
		"ModCircleDef",
		[InstitutionRegistry.CAP_HAS_TERRITORY],
		load("res://src/core/institution_def.gd")
	)
	var mine := _def(FARMERS_CIRCLE, &"t_mod_circle", [InstitutionRegistry.CAP_HAS_TERRITORY])
	var clash := InstitutionBoot.register_def(foreign, mine)
	assert_eq(bool(clash["ok"]), false, "a different def class on one kind is refused")
	assert_eq(String(clash["reason"]), InstitutionBoot.R_DEF_TYPE_DISAGREEMENT, "and named")
	assert_eq(
		foreign.def_type_of(FARMERS_CIRCLE),
		"ModCircleDef",
		"and the row still names the class that got there first"
	)


## ## The registry-FREE half is askable with no registry at all
##
## `check(registry)` cannot gate a first `.tres`, because its registry half asks
## whether the kind is registered and a brand-new kind is not. `check_content()` is
## what a boot runs before a row exists, and it must answer on a def alone — so the
## split is a property, not a convenience, and this case is what holds it up.
func test_the_content_half_of_the_check_needs_no_registry_and_the_full_one_still_does() -> void:
	var guild := load(LANTERN) as InstitutionDef
	assert_eq(bool(guild.check_content()["ok"]), true, "a shipped guild passes with no registry")
	assert_eq(
		String(guild.check(null)["reason"]),
		InstitutionDef.R_UNKNOWN_KIND,
		"while the full check still needs one, and says so"
	)
	var nameless := _def(TRADING_GUILD, &"", [InstitutionRegistry.CAP_HAS_OFFICES])
	assert_eq(
		String(nameless.check_content()["reason"]),
		InstitutionDef.R_NO_ID,
		"and the content half still refuses an id-less def"
	)
	var invented := _def(TRADING_GUILD, &"t_invented", [&"has_fleets"] as Array[StringName])
	assert_eq(
		String(invented.check_content()["reason"]),
		InstitutionDef.R_UNKNOWN_CAPABILITY,
		"an invented capability name fails where it was written"
	)


## Positions authored under a kind that declares no offices would seat nobody and
## gate nothing, and territory ids under a kind that declares no claim would decide
## nothing — the exact ADR 0085 rule a `.tres` can break silently. Both are named at
## the place they were written rather than surfacing as a guild that mysteriously has
## no effect.
func test_content_that_contradicts_its_kind_is_refused_by_name() -> void:
	_offices_case()
	_territory_case()


func _offices_case() -> void:
	var silent := _def(
		FARMERS_CIRCLE,
		&"t_ledger_circle",
		[InstitutionRegistry.CAP_HAS_TERRITORY],
		[_position(&"reeve", 1, 1)],
		&"reeve"
	)
	var verdict := silent.check(_registry)
	assert_eq(
		bool(verdict["ok"]), false, "offices under a kind with no offices capability is refused"
	)
	assert_eq(String(verdict["reason"]), InstitutionDef.R_OFFICES_NOT_DECLARED, "and named")


func _territory_case() -> void:
	var claimant := _def(
		TRADING_GUILD,
		&"t_claiming_exchange",
		[InstitutionRegistry.CAP_HAS_OFFICES],
		[_position(&"factor", 3, 1)],
		&"factor"
	)
	claimant.territory_ids.append(&"mortal_plains_road")
	var verdict := claimant.check(_registry)
	assert_eq(
		bool(verdict["ok"]), false, "claims under a kind with no territory capability is refused"
	)
	assert_eq(String(verdict["reason"]), InstitutionDef.R_TERRITORY_NOT_DECLARED, "and named")
	assert_eq(bool(claimant.has_territory_claim()), true, "so the claim is authored and legible")


## Two `.tres` of ONE kind declaring different capability sets are the one way the
## directory could hold two sources of truth for a per-kind fact. The first registers;
## the second is refused by name rather than folded into the row that already exists.
func test_a_second_organization_of_one_kind_that_disagrees_about_capabilities_is_refused() -> void:
	var first := _def(FARMERS_CIRCLE, &"t_one", [InstitutionRegistry.CAP_HAS_TERRITORY])
	# The disagreeing def is CONTENT-CONSISTENT on purpose: it declares offices AND
	# authors one with a reachable top, so the only fault left in it is the collision
	# this case is about. A def that ALSO broke its own content would be refused for
	# that first — which is the order `register_def` runs them in, and a content fault
	# is the more useful thing to hear.
	var second := _def(
		FARMERS_CIRCLE,
		&"t_two",
		[InstitutionRegistry.CAP_HAS_TERRITORY, InstitutionRegistry.CAP_HAS_OFFICES],
		[_position(&"reeve", 1, 1)],
		&"reeve"
	)
	# Against the registry `setup()` installed from disk: the shipped farmers' circle
	# already registered this kind, so this def is a SECOND REGULATION of a known
	# kind. It is accepted — a guild may have many houses of one kind — and it reports
	# itself as not-new rather than as a duplicate registration.
	var repeat_of_shipped := InstitutionBoot.register_def(_registry, first)
	assert_eq(bool(repeat_of_shipped["ok"]), true, "another regulation of a known kind is accepted")
	assert_eq(bool(repeat_of_shipped["new"]), false, "and reports that it is not a new row")
	# `register_def` against a FRESH registry so the first registration is genuinely
	# the first, rather than reading the row a previous test installed.
	var clean := InstitutionRegistry.new()
	var registered := InstitutionBoot.register_def(clean, first)
	assert_eq(bool(registered["ok"]), true, "the first def registers its kind")
	assert_eq(bool(registered["new"]), true, "and reports itself as new")
	var repeat := InstitutionBoot.register_def(
		clean, _def(FARMERS_CIRCLE, &"t_three", [InstitutionRegistry.CAP_HAS_TERRITORY])
	)
	assert_eq(bool(repeat["ok"]), true, "an IDENTICAL repeat is another regulation of the kind")
	var clash := InstitutionBoot.register_def(clean, second)
	assert_eq(bool(clash["ok"]), false, "a DISAGREEMENT is refused")
	assert_eq(String(clash["reason"]), InstitutionBoot.R_CAPABILITY_DISAGREEMENT, "and named")
	assert_eq(
		_sorted(clean.capabilities_of(FARMERS_CIRCLE)),
		["has_territory"],
		"and the row still carries the set that was registered"
	)


# --- Helpers ---------------------------------------------------------------------


func _pool_balance(actor: Actor) -> float:
	var pool := actor.resource(POOL)
	return 0.0 if pool == null else pool.current


## Everything a `found` could have written: the pool balance and the whole save
## payload. A refused verb must leave both identical.
func _fingerprint(actor: Actor) -> Dictionary:
	return {"pool": _pool_balance(actor), "save": actor.to_dict()}


## `value` after one JSON round trip. **BOTH sides of every round-trip identity go
## through this**, because `JSON.parse_string` returns every number as a `float`.
func _through_json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value)) as Dictionary


## An actor whose base stats carry one realm's authored power, so R1 and R30 are two
## genuinely different sheets rather than two hand-written numbers. Built from the
## real ladder, so a retune of the realm table cannot quietly break the ratio.
func _realm_scaled_actor(actor_id: StringName, ordinal: int) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(POOL, 9000.0))
	_born.append(actor)
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var realm: RealmDef = realms[clampi(ordinal - 1, 0, realms.size() - 1)]
	var power := maxf(1.0, realm.power)
	actor.stats.set_base(Stat.PHYSIQUE, 10.0 * power)
	actor.stats.set_base(Stat.COMPREHENSION, 8.0 * power)
	actor.stats.set_base(RECOGNISED, 4.0 * power)
	return actor


## The derived-stat ratio on `stat_id`, read as `after / before` against the value
## the caller took. A percent rides the sheet, so this is the same number at every
## realm.
func _ratio(actor: Actor, stat_id: StringName, before: float) -> float:
	if before == 0.0:
		return 1.0
	return actor.stats.derived(stat_id) / before


## How many times `needle` appears in CODE, ignoring the `##` prose that documents
## it — the boot's own docblock names the shipped kinds to explain why it does not,
## which is precisely the sentence a raw `contains` scan would fail on.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## Every public method name on `klass`, underscore-prefixed names dropped exactly as
## `tools/arch/enforce.py` drops them, so this suite and the gate count the same
## surface. `load()` is the one way in: GDScript refuses a non-static call on a class
## reference.
func _published(klass: GDScript) -> Array[String]:
	var out: Array[String] = []
	if klass == null:
		return out
	for method in klass.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


func _names(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id in ids:
		out.append(String(id))
	return out


## `ids` as plain strings in canonical STRING order. Every comparison against a
## registry read goes through here, and that is a measurement rather than caution:
## `InstitutionRegistry.capabilities_of` and `kinds` both sort an `Array[StringName]`,
## and on this engine two interned ids do not compare by their string value — a def
## declaring `[has_offices, has_territory]` reads back `[has_territory, has_offices]`.
## Sorting the strings on this side makes the expectation a statement about CONTENT
## instead of a statement about an engine detail.
func _sorted(ids: Array[StringName]) -> Array:
	var out := _names(ids)
	out.sort()
	return out
