extends TestCase

## The generic `found`, the shared ledger machinery, and the invariants that hold for
## every institution kind.
##
## ## The cases that would have failed before this slice
##
##   - `test_a_kind_without_teaching_has_no_fit_axis_at_all` — the ABSENCE of a key,
##     not a zero. A `fit: 0` reads as a gate answering from a default rather than
##     from what the kind IS.
##   - `test_a_refused_found_writes_nothing_byte_for_byte` — ADR 0044 as a
##     measurement on the actor and the pool together.
##   - `test_position_and_standing_never_derive_from_each_other` — ADR 0064 carried
##     forward by ADR 0083, in both directions.
##   - `test_the_recognition_is_realm_invariant_in_ratio_at_r1_and_at_r30` — ADR 0084's
##     own second measurement, so "a percent, never a flat" is a property here rather
##     than a hope.

const DEF := preload("res://tests/core/institution_registry_fixture_def.gd")

const SECT := &"sect"
const CLAN := &"clan"
const NATION := &"nation"
const COMPACT := &"compact"

const HOUSE := "t_house"
const FOUNDER := "t_founder"

## A stat this suite reads, because ADR 0084's whole content is that the ONE allowed
## percent lands on an authored allowlist and nothing else moves.
const RECOGNISED := Stat.INSIGHT_GAIN
const UNTOUCHED := Stat.MAX_HEALTH

const POOL := &"t_founding_pool"

## Every verb an institution foundation must never grow. If one of these appears on any
## of the four foundation classes, an institution has grown a way to hand out a stat,
## and ADR 0084 says it never may. `tools arch` cannot see a method that does not
## exist, so the guard is this test — the same shape `test_sect_no_power.gd` uses.
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

## The published surface of the founding verb, asserted as a WHOLE rather than only by
## the absence of the forbidden ones — so a verb added later fails here rather than
## slipping past the word list.
const PUBLISHED_FOUNDING := [
	"can_pay",
	"cost",
	"draw",
	"found",
	"founded",
	"funds",
	"has_fit_axis",
	"write",
]

## The shared ledger machinery's surface, asserted as a whole for the same reason.
const PUBLISHED_LEDGER := [
	"is_save_safe",
	"is_text",
	"move_standing",
	"ok",
	"owns_source",
	"positive_lines",
	"promote",
	"read",
	"refuse",
	"sorted_keys",
	"source_tagged",
	"standing_percent",
	"text",
]

## The registry's surface, asserted as a whole.
const PUBLISHED_REGISTRY := [
	"capabilities_of",
	"clear",
	"def_script_bound",
	"def_script_of",
	"def_type_of",
	"has_capability",
	"instance",
	"kinds",
	"knows",
	"register",
	"row",
]

## The three foundation files plus the claim they all speak, as `res://` paths. Read
## rather than named, because a source scan is what turns "never calls `set_base`"
## from a claim into a measurement.
const FOUNDATION_FILES := [
	"res://src/core/institution_founding.gd",
	"res://src/core/institution_registry.gd",
	"res://src/core/institution_ledger.gd",
]

var _registry: InstitutionRegistry = null
var _born: Array = []


func setup() -> void:
	_registry = InstitutionRegistry.new()
	# A sect: teaches, authors offices, claims territory.
	(
		_registry
		. register(
			SECT,
			"SectDef",
			[
				InstitutionRegistry.CAP_TEACHES,
				InstitutionRegistry.CAP_HAS_OFFICES,
				InstitutionRegistry.CAP_HAS_TERRITORY,
			],
			DEF
		)
	)
	# A clan: born to, authors offices, NO fit axis.
	_registry.register(
		CLAN,
		"ClanDef",
		[InstitutionRegistry.CAP_IS_BORN_TO, InstitutionRegistry.CAP_HAS_OFFICES],
		DEF
	)
	# A nation: lived under, offices may be vacant, NO fit axis.
	_registry.register(
		NATION,
		"NationDef",
		[InstitutionRegistry.CAP_HAS_OFFICES, InstitutionRegistry.CAP_HAS_TERRITORY],
		DEF
	)


## ## Everything instantiated here is released here
##
## The runner drives every suite from `SceneTree._initialize()` **in one process**,
## so a value a case builds and never drops is a leak that reaches every suite after
## it — `RAM_CEILING_BYTES` exists because a silent allocating loop reached 67 GB on
## this machine and the machine had to be power-cycled. `_born` is the tracking array
## and `teardown` releases from it, because the call sites are interleaved and
## releasing at each one is skipped by any case that returns early.
##
## **`free()` is called only on `Node`s, and that is measured, not stylistic.**
## `Actor` extends `RefCounted`, and `Object.free()` on a `RefCounted` is a SCRIPT
## ERROR — which ABORTS the rest of `teardown`, so a version of this suite that called
## `free()` unconditionally never reached its `clear()` and every later case ran
## against a registry nobody had rebuilt. A `Node` needs the explicit call
## (`queue_free()` is banned in `res://src` and never runs under `tools test`); a
## `RefCounted` needs only that this array stop holding it.
func teardown() -> void:
	for held in _born:
		if held is Node and is_instance_valid(held):
			held.free()
	_born.clear()
	if _registry != null:
		_registry.clear()
		_registry = null


## An actor with a founding pool. Tracked in `_born` so `teardown` frees it.
func _actor(actor_id: StringName = &"founder", funds: float = 0.0) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(POOL, funds))
	_born.append(actor)
	return actor


## The profile a sect's founding hands in. A plain `Dictionary` of primitives, because
## `core/` may not name a `SectDef`: the tier assembles this from its own defs.
func _profile(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"kind": String(SECT),
		"institution_id": HOUSE,
		"standing_cap": 100,
		"founder_standing": 100,
		"founding_cost": 250,
		"top_position": "t_steward",
		"funding_pool": String(POOL),
		"obligation": {"duty_t_house": 1},
		"office_obligation": {"duty_t_steward": 2},
		"fit": {"t_iron_vine": 35},
		"treasury": {"treasury_t_house_patronage_t_steward": 1},
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


## ## An empty `profile` argument means "the default sect profile", NOT "no profile"
##
## The first version defaulted the parameter to `{}` and passed it straight through, so
## every `_found(actor)` call handed `found` an empty dictionary and was refused
## `unknown_kind` — for a profile key that was MISSING rather than for a kind that was.
## Five cases reported the wrong cause and three of them then aborted on a missing
## `"ledger"` key, which reads like a broken verb rather than a broken helper. Resolving
## the default HERE, where the profile is built, is the only place that knows the intent.
func _found(actor: Actor, profile: Dictionary = {}, founder: String = FOUNDER) -> Dictionary:
	var resolved := _profile() if profile.is_empty() else profile
	return InstitutionFounding.found(_registry, actor, resolved, founder)


# --- The happy path ------------------------------------------------------------


## The whole verb: it costs, it seats the founder, it opens the treasury, and it
## writes the institution.
func test_found_costs_seats_the_founder_and_opens_the_treasury() -> void:
	var actor := _actor(&"founder", 1000.0)
	var report := _found(actor)
	assert_eq(bool(report["ok"]), true, "the founding landed: %s" % str(report.get("reason", "")))
	assert_eq(int(report["charged"]), 250, "it charged the authored cost")
	# The cost came out of the pool, which is what makes founding not free.
	assert_almost_eq(_pool(actor).current, 750.0, "and took it off the funding pool")
	var ledger: Dictionary = report["ledger"]
	assert_eq(String(ledger["institution"]), HOUSE, "the ledger names the institution")
	assert_eq(String(ledger["kind"]), String(SECT), "and the kind it is")
	assert_eq(String(ledger["position"]), "t_steward", "the founder is seated in the top office")
	assert_eq(String(ledger["founder_id"]), FOUNDER, "and named as the founder")
	assert_eq(int(ledger["standing"]), 100, "with the authored founder standing")
	assert_eq(int(ledger["standing_cap"]), 100, "against the authored cap")
	assert_eq(
		(ledger["roster"] as Dictionary)["t_steward"], [FOUNDER], "the founder is in the roster"
	)
	# A treasury is a LEDGER OF OBLIGATION LINES ON IDS, never a pile of items — so
	# the whole thing is Strings and ints and nothing a save cannot carry.
	assert_eq(
		(ledger["treasury"] as Dictionary)["treasury_t_house_all"], 1, "the opening line opened"
	)
	assert_eq(
		(ledger["treasury"] as Dictionary)["treasury_t_house_patronage_t_steward"],
		1,
		"and the tier's own line survived"
	)
	assert_eq(InstitutionLedger.is_save_safe(ledger), true, "and the ledger is save-safe")


## The founder's obligation is the LARGER of the membership line and the office line per
## term, not their sum — two authored statements about the same term are one debt, and
## summing them would make the price depend on how an author split one number.
func test_the_founder_owes_the_larger_of_the_membership_and_office_rates_per_term() -> void:
	# The office authors a line on the membership's OWN term, which is the only way to
	# make the merge observable: with two different term ids both survive untouched and
	# the rule would never be exercised at all.
	var profile := _profile({"office_obligation": {"duty_t_house": 3, "duty_t_steward": 2}})
	var report := _found(_actor(&"founder", 1000.0), profile)
	var duties: Dictionary = (report["ledger"] as Dictionary)["obligation"]
	assert_eq(int(duties["duty_t_house"]), 3, "the LARGER rate wins where both speak")
	assert_ne(int(duties["duty_t_house"]), 4, "and they are NOT summed into one debt")
	assert_eq(int(duties["duty_t_steward"]), 2, "a term only the office opens is taken whole")


# --- The optional capabilities -------------------------------------------------


## ## A kind WITHOUT `teaches` has NO FIT AXIS AT ALL
##
## Not `fit: 0`, not `fit: {}` — **the key is absent**. ADR 0084's fit is a GATE that
## projects zero stat modifiers, and a gate reading a zero it was handed is a gate
## answering from a default rather than from what the kind IS. A clan authors no
## doctrine, so it has no transmission to gate: the absence is the authored state, and
## `has_fit_axis` tells "no fit axis" apart from "nothing taught yet".
func test_a_kind_without_teaching_has_no_fit_axis_at_all() -> void:
	var profile := _profile({"kind": String(CLAN), "founding_cost": 0, "top_position": "t_head"})
	var report := _found(_actor(&"founder", 1000.0), profile)
	assert_eq(bool(report["ok"]), false, "a clan cannot be founded at all (born to)")
	# So the case that matters is the WRITER, which is what the migration calls.
	var clan_ledger := InstitutionFounding.write(_registry, profile, FOUNDER, "t_head")
	assert_eq(clan_ledger.has("fit"), false, "a clan's ledger has NO fit key — not zero, ABSENT")
	assert_eq(
		InstitutionFounding.has_fit_axis(clan_ledger), false, "so the reader reports no fit axis"
	)
	# And a nation: the same shape, a different reason. `has_offices` is present, so a
	# nation CAN be founded and its ledger also carries no fit axis.
	var nation := _profile(
		{"kind": String(NATION), "founding_cost": 0, "top_position": "t_steward"}
	)
	var nation_report := _found(_actor(&"founder", 1000.0), nation)
	assert_eq(
		bool(nation_report["ok"]), true, "a nation can be founded: it is lived under, not born to"
	)
	var nation_ledger: Dictionary = nation_report["ledger"]
	assert_eq(nation_ledger.has("fit"), false, "and its ledger carries no fit key either")
	assert_eq(InstitutionFounding.has_fit_axis(nation_ledger), false, "no fit axis")


## The positive half: a sect's fit axis IS written, from the profile's own lines, and
## the TIER owns the points. The cap that bounds them is a doctrine's floor and
## `core/` may not name a doctrine, so the tier has already applied it before the
## profile reaches this file.
func test_a_kind_that_teaches_writes_its_fit_axis_from_the_profile() -> void:
	var report := _found(_actor(&"founder", 1000.0))
	var ledger: Dictionary = report["ledger"]
	assert_eq(InstitutionFounding.has_fit_axis(ledger), true, "a sect HAS a fit axis")
	assert_eq(int((ledger["fit"] as Dictionary)["t_iron_vine"]), 35, "holding the tier's points")
	# An empty fit profile yields NO axis rather than an empty one, for the same reason
	# the absent kind has none: nothing was granted, so nothing is recorded as granted.
	var bare := _profile({"fit": {}})
	var bare_ledger := InstitutionFounding.write(_registry, bare, FOUNDER, "t_steward")
	assert_eq(bare_ledger.has("fit"), false, "and nothing granted writes no axis")


## A kind WITHOUT `has_offices` is refused `no_top_position`, and the reason is that a
## profile naming a position the kind does not author is a content BUG. It is not a
## no-op and it is not a zero.
func test_a_kind_that_authors_offices_but_names_no_top_position_is_refused() -> void:
	var profile := _profile({"top_position": ""})
	var report := _found(_actor(&"founder", 1000.0), profile)
	assert_eq(bool(report["ok"]), false, "it refused")
	assert_eq(String(report["reason"]), InstitutionFounding.R_NO_TOP_POSITION, "naming the cause")


## ## `is_born_to` is the ONLY place the foundable answer is written
##
## A clan is inherited, so no actor founds one. This refusal is read off that one flag
## rather than a second `can_found` flag that could disagree with it.
func test_a_born_to_kind_cannot_be_founded_at_all() -> void:
	var profile := _profile({"kind": String(CLAN), "founding_cost": 0})
	var report := _found(_actor(&"founder", 1000.0), profile)
	assert_eq(bool(report["ok"]), false, "a clan is born to, never founded")
	assert_eq(
		String(report["reason"]),
		InstitutionFounding.R_KIND_CANNOT_BE_FOUNDED,
		"and it names the flag-derived cause"
	)


# --- Refusals write nothing ----------------------------------------------------


## ## ADR 0044 as a MEASUREMENT: a refused `found` writes nothing, byte for byte
##
## Every refusal returns above the point at which the pool is touched and the ledger
## is built, so there is no branch on which a refusal has already moved a number. This
## case compares the actor's whole save payload AND the pool balance across every
## refusal, so it is a property of the control flow rather than a promise in a
## docstring.
func test_a_refused_found_writes_nothing_byte_for_byte() -> void:
	var refusals := [
		["no actor", _profile(), null],
		["unknown kind", _profile({"kind": String(COMPACT)}), _actor(&"a", 1000.0)],
		["born to", _profile({"kind": String(CLAN), "founding_cost": 0}), _actor(&"b", 1000.0)],
		["no institution", _profile({"institution_id": ""}), _actor(&"c", 1000.0)],
		["no top position", _profile({"top_position": ""}), _actor(&"d", 1000.0)],
		["cost unmet", _profile(), _actor(&"e", 10.0)],
	]
	for entry in refusals:
		var label: String = entry[0]
		var profile: Dictionary = entry[1]
		var actor: Actor = entry[2]
		var before := {} if actor == null else _fingerprint(actor)
		var report := _found(actor, profile)
		assert_eq(bool(report["ok"]), false, "%s refused" % label)
		assert_ne(String(report["reason"]), "", "%s names a reason" % label)
		if actor != null:
			assert_eq(_fingerprint(actor), before, "%s changed nothing at all" % label)


## Founding twice is refused. The tiers are PEERS, not a containment tree (ADR 0083),
## so founding twice is leaving and then founding — never a second institution.
func test_founding_twice_is_refused() -> void:
	var actor := _actor(&"founder", 1000.0)
	var first := _found(actor)
	assert_eq(bool(first["ok"]), true, "the first founding landed")
	var ledger: Dictionary = first["ledger"]
	var before := _fingerprint(actor)
	var second := InstitutionFounding.found(_registry, actor, _profile(), FOUNDER, ledger)
	assert_eq(bool(second["ok"]), false, "the second refused")
	assert_eq(String(second["reason"]), InstitutionFounding.R_ALREADY_FOUNDED, "naming the cause")
	assert_eq(_fingerprint(actor), before, "and it wrote nothing")


## Founding is NOT free. A shortfall names the cost, and the pool is untouched — the
## refusal happens above the draw.
func test_a_found_with_a_shortfall_refuses_and_takes_nothing() -> void:
	var actor := _actor(&"founder", 249.0)
	var report := _found(actor)
	assert_eq(bool(report["ok"]), false, "249 of 250 is a shortfall")
	assert_eq(
		String(report["reason"]), InstitutionFounding.R_FOUNDING_COST_UNMET, "naming the cause"
	)
	assert_almost_eq(_pool(actor).current, 249.0, "and the pool is untouched")
	# One more fund and it lands, so the gate is a real price rather than a wall.
	# `set_maximum` FIRST: `ResourcePool.change` clamps to `maximum`, and the pool was
	# built at 249 — so a bare `change(1.0)` is a silent no-op and this case would report
	# "still unaffordable" against a gate that is working perfectly.
	_pool(actor).set_maximum(250.0)
	_pool(actor).change(1.0)
	var funded := _found(actor)
	assert_eq(
		bool(funded["ok"]), true, "the exact cost is affordable: %s" % str(funded.get("reason", ""))
	)
	assert_eq(int(funded["charged"]), 250, "and it charged the authored price")
	assert_almost_eq(_pool(actor).current, 0.0, "leaving the pool empty")


## An author may deliberately author a FREE institution, and the zero is not read as
## "missing". This is why the cost is a clamp and not a refusal.
func test_an_authored_zero_cost_is_a_free_institution_and_not_an_error() -> void:
	var actor := _actor(&"founder", 0.0)
	var report := _found(actor, _profile({"founding_cost": 0}))
	assert_eq(bool(report["ok"]), true, "a free institution is authored content")
	assert_eq(int(report["charged"]), 0, "and it charged nothing")
	assert_almost_eq(_pool(actor).current, 0.0, "and the pool is untouched")


## ## ADR 0084: `fit` is TRANSMISSION and projects ZERO stat modifiers
##
## This is the structural case, the way `test_sect_no_power.gd` pins it: neither
## `InstitutionFounding` nor `InstitutionRegistry` nor `InstitutionLedger` publishes a
## verb that can touch a stat. `tools arch` cannot see a method that does not exist, so
## the guard has to be a test.
func test_no_institution_foundation_verb_can_touch_a_stat() -> void:
	for klass in [
		InstitutionFounding,
		InstitutionRegistry,
		InstitutionLedger,
		InstitutionClaim,
	]:
		var published := _published(klass)
		assert_eq(published.is_empty(), false, "%s publishes a readable method list" % klass)
		for verb in FORBIDDEN_VERBS:
			assert_eq(published.has(verb), false, "%s publishes no '%s'" % [klass, verb])
	# And each surface is asserted as a WHOLE, so a verb added later fails here rather
	# than slipping past the word list.
	assert_eq(
		_published(InstitutionFounding),
		PUBLISHED_FOUNDING,
		"the founding surface is exactly this one"
	)
	assert_eq(
		_published(InstitutionLedger), PUBLISHED_LEDGER, "the ledger surface is exactly this one"
	)
	assert_eq(
		_published(InstitutionRegistry),
		PUBLISHED_REGISTRY,
		"the registry surface is exactly this one"
	)
	# Nothing in the three foundation files reaches for a base write either: `set_base`
	# bypasses the modifier stack, cannot be stripped, and DOES satisfy `get_base`,
	# which is exactly how an institution would smuggle a member past a gate.
	for rel in FOUNDATION_FILES:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for forbidden in ["set_base", "add_base", "add_provider", "add_modifier"]:
			assert_eq(_calls(body, forbidden), 0, "%s never calls %s" % [rel.get_file(), forbidden])


## ## ADR 0084's SECOND MEASUREMENT: realm-invariance in ratio
##
## `standing_percent` is a bounded PERCENT, so the derived-stat ratio it produces is
## identical at R1 and at R30. That is what makes "a percent, never a flat" a
## property rather than a hope: a flat is decisive on a shallow sheet and noise on a
## deep one, across the 1.0x–551x ladder.
##
## The measurement uses the real realm ladder rather than a hand-written factor, so a
## retune of `realm_power_table.tres` cannot quietly break the ratio.
func test_the_recognition_is_realm_invariant_in_ratio_at_r1_and_at_r30() -> void:
	var shallow := _realm_scaled_actor(&"shallow", 1)
	var deep := _realm_scaled_actor(&"deep", 30)
	assert_ne(
		deep.stats.derived(RECOGNISED),
		shallow.stats.derived(RECOGNISED),
		"R30 really is a deeper sheet than R1"
	)
	# The BEFORE values, read off the DERIVED stat rather than `get_base`. A derived stat
	# is recomputed from its attributes, so its base is not the value a percent rides:
	# dividing the after by the base is a ratio of two unrelated numbers, which is how
	# the first version of this case produced 0.0225 and 0.297 and still looked like a
	# measurement.
	var shallow_before := shallow.stats.derived(RECOGNISED)
	var deep_before := deep.stats.derived(RECOGNISED)
	# The ONE percent an institution may contribute, applied as the modifier ADR 0084
	# specifies and a founder's standing earned.
	var percent := InstitutionClaim.standing_percent(100)
	for actor in [shallow, deep]:
		actor.stats.add_modifier(
			StatModifier.new(RECOGNISED, Stat.Op.PERCENT, percent, &"sect:" + HOUSE)
		)
	var at_r1 := _ratio(shallow, RECOGNISED, shallow_before)
	var at_r30 := _ratio(deep, RECOGNISED, deep_before)
	assert_almost_eq(at_r1, at_r30, "the ratio is identical at R1 and at R30")
	# `1.0` here would be the claim that a percent moves nothing, which is the
	# OPPOSITE of what ADR 0084 grants: the bounded percent is the one thing an
	# institution is allowed to hand out, and asserting it moved nothing would be
	# asserting the recognition is not there.
	assert_almost_eq(
		at_r1,
		1.0 + InstitutionClaim.STANDING_PERCENT_CAP,
		"and it is the recognition itself, and only the recognition"
	)
	# And the cap is a CAP: no ladder of authored positions can sum past it.
	assert_almost_eq(
		InstitutionClaim.standing_percent(1000000),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"a standing of a million still projects only the capped percent"
	)


## A kind WITHOUT `teaches` grants nothing even when its profile carries fit lines.
## The capability, not the profile's contents, decides whether a fit axis exists —
## otherwise a profile could smuggle transmission onto a kind that has none.
func test_a_kind_without_teaching_grants_nothing_even_when_the_profile_names_fit() -> void:
	var actor := _actor(&"founder", 1000.0)
	var profile := _profile({"kind": String(NATION), "founding_cost": 0, "fit": {"t_any": 99}})
	var before := _derived(actor)
	var report := _found(actor, profile)
	assert_eq(bool(report["ok"]), true, "the nation was founded")
	assert_eq((report["ledger"] as Dictionary).has("fit"), false, "and no fit axis was written")
	assert_eq(_derived(actor), before, "so no derived stat moved")


# --- Position and standing never derive from each other -------------------------


## ## ADR 0064 carried forward by ADR 0083: the two numbers are INDEPENDENT
##
## Each direction is asserted separately, because a design that collapsed the pair into
## one number would pass a single combined check: it would simply have no second number
## to contradict. A member may hold a high position on thin standing and may hold
## thick standing in no position at all, and that gap is the whole politics layer.
func test_position_and_standing_never_derive_from_each_other() -> void:
	# A founder on 50 of a 100 cap, so there is ROOM to move standing in the second
	# direction. At the cap the clamp would answer 100 either way and the case would
	# pass against a `move_standing` that did nothing at all — which is the same
	# vacuous assertion the whole case exists to avoid.
	var ledger := InstitutionFounding.write(
		_registry, _profile({"founder_standing": 50}), FOUNDER, "t_steward"
	)
	var read := InstitutionLedger.read(ledger)
	assert_eq(String(read["position"]), "t_steward", "the founder holds the top office")
	assert_eq(int(read["standing"]), 50, "with half the authored cap earned")

	# Direction one: a promotion writes the POSITION and leaves standing alone.
	# Every writer RETURNS its replacement under `"ledger"` and mutates nothing, so the
	# assignment is the caller's half of the contract and skipping it IS the failure.
	var before_standing := int(InstitutionLedger.read(ledger)["standing"])
	var promoted := InstitutionLedger.promote(ledger, "t_archivist")
	assert_eq(bool(promoted["ok"]), true, "the promotion landed")
	ledger = promoted["ledger"]
	assert_eq(
		String(InstitutionLedger.read(ledger)["position"]), "t_archivist", "the position moved"
	)
	assert_eq(
		int(InstitutionLedger.read(ledger)["standing"]), before_standing, "and standing did NOT"
	)

	# Direction two: a standing change moves STANDING and leaves the position alone.
	var before_position := String(InstitutionLedger.read(ledger)["position"])
	var moved := InstitutionLedger.move_standing(ledger, 25)
	assert_eq(bool(moved["ok"]), true, "the standing change landed")
	ledger = moved["ledger"]
	assert_eq(
		int(InstitutionLedger.read(ledger)["standing"]), before_standing + 25, "standing moved"
	)
	assert_eq(
		String(InstitutionLedger.read(ledger)["position"]),
		before_position,
		"and the position did NOT"
	)


## A member with thick standing and NO position is the state ADR 0064's split exists
## to make expressible. It is a legitimate ledger, never an error and never a zero
## standing.
func test_thick_standing_in_no_position_is_a_legitimate_state() -> void:
	var ledger := InstitutionFounding.write(_registry, _profile(), FOUNDER, "t_steward")
	var demoted := InstitutionLedger.promote(ledger, &"")
	assert_eq(bool(demoted["ok"]), true, "a member may hold no office at all")
	ledger = demoted["ledger"]
	var read := InstitutionLedger.read(ledger)
	assert_eq(String(read["position"]), "", "holds no position")
	assert_eq(int(read["standing"]), 100, "with the standing they already earned")
	assert_eq(bool(read["holds_position"]), false, "and `holds_position` answers false")
	assert_eq(bool(read["exists"]), true, "while the institution still exists")


## Standing is clamped at zero and NEVER goes negative. An institution that has been
## wronged is one that has lost something, and a member with nothing left has nothing
## to lose — which is what makes a demotion a real cost.
func test_standing_clamps_at_zero_and_never_goes_negative() -> void:
	var ledger := InstitutionFounding.write(_registry, _profile(), FOUNDER, "t_steward")
	var moved := InstitutionLedger.move_standing(ledger, -1000)
	assert_eq(bool(moved["ok"]), true, "the fall landed")
	assert_eq(int(InstitutionLedger.read(moved["ledger"])["standing"]), 0, "clamped at zero")
	assert_eq(int(moved["applied"]), -100, "and it reports what actually landed")
	# And it clamps at the CAP too, so a ladder of authored positions cannot sum past it.
	var capped := InstitutionLedger.move_standing(moved["ledger"], 100000)
	assert_eq(
		int(InstitutionLedger.read(capped["ledger"])["standing"]),
		100,
		"clamped at the authored cap"
	)
	# A zero delta is refused rather than absorbed, because a caller computing one has a
	# bug and absorbing it would claim a move that did not happen.
	assert_eq(
		String(InstitutionLedger.move_standing(ledger, 0)["reason"]),
		InstitutionLedger.R_NON_POSITIVE,
		"a zero delta refuses by name"
	)
	# A forged ledger carrying a negative standing reads as zero, not as a debt.
	var forged := InstitutionLedger.read({"institution": HOUSE, "standing": -50})
	assert_eq(int(forged["standing"]), 0, "a corrupt negative reads as zero")


# --- Save safety ---------------------------------------------------------------


## ## A ledger round-trips through the JSON hop, and a corrupt payload is diagnosed as
## EMPTY rather than partially applied
##
## `Actor.to_dict` copies `module_data` VERBATIM and converts only the OUTER key, so a
## `StringName` key, a `Resource`, an `Actor` or a `Vector2` reaches the save untouched
## and breaks every round trip — and **no checker in this repo can see it**. So the
## property is asserted here, on a real save hop, not asserted in a docstring.
func test_a_ledger_round_trips_through_the_json_hop() -> void:
	var actor := _actor(&"founder", 1000.0)
	var report := _found(actor)
	var ledger: Dictionary = report["ledger"]
	actor.set_module_data(&"t_institution", ledger)
	var encoded := JSON.stringify(actor.to_dict())
	var parsed = JSON.parse_string(encoded)
	assert_ne(parsed, null, "the payload parses")
	var restored := Actor.from_dict(parsed as Dictionary)
	var read_back: Dictionary = restored.get_module_data(&"t_institution")
	# ## The comparison is the FACTS, not the Dictionary, and that is a FORMAT fact
	#
	# `JSON.parse_string` returns **every number as a float** and `JSON.stringify` renders
	# a float as `35.0`, so `assert_eq` on the raw Dictionary reports a difference on every
	# count in the ledger. That is the save format, not a bug in the ledger — and it is
	# exactly why every normalizer in this repo COERCES on the way in. Both sides go
	# through `_through_json`, which compares the facts rather than the representation.
	assert_eq(
		JSON.stringify(_through_json(ledger)),
		JSON.stringify(_through_json(read_back)),
		"the ledger came back with the same facts"
	)
	assert_eq(int(read_back["standing"]), 100, "standing reads back as the authored count")
	assert_eq(
		int((read_back["obligation"] as Dictionary)["duty_t_steward"]),
		2,
		"and an obligation line too"
	)
	assert_eq(
		(read_back["roster"] as Dictionary)["t_steward"], ["t_founder"], "and the roster of ids"
	)
	# And the values are primitives, so a second hop is a fixed point rather than a slow
	# drift: stringifying what came back equals stringifying what went in.
	assert_eq(InstitutionLedger.is_save_safe(read_back), true, "and it is save-safe")
	assert_eq(
		JSON.stringify(_through_json(read_back)),
		JSON.stringify(_through_json(ledger)),
		"a second hop changes nothing"
	)


## `value` after one JSON round trip.
##
## **BOTH sides of every round-trip identity must go through this**, because
## `JSON.parse_string` returns every number as a `float` AND `JSON.stringify` renders a
## float as `35.0`. So the first version of the case compared `JSON.stringify(read_back)`
## against `JSON.stringify(ledger)` and reported a difference on every count in the
## ledger — which is the save format talking, not the ledger. Normalising both sides
## through the same hop compares the FACTS, which is what "it round-trips" means.
func _through_json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value)) as Dictionary


## ## A corrupt payload is diagnosed as EMPTY, never partially applied
##
## Half a ledger is worse than none: it silently changes what the player is owed. This
## is the whole of `ClanState.normalize`'s stated rule and it is the rule
## `InstitutionLedger.read` inherits.
func test_a_corrupt_payload_is_diagnosed_as_empty_and_never_partially_applied() -> void:
	# Each of these would RAISE under a raw `String(...)` cast — `String(42.0)` is a
	# script error in GDScript, not `"42.0"` — so a normalizer that cast would abort
	# the load instead of reading as empty.
	for bad in [
		{"institution": 42.0},
		{"institution": HOUSE, "position": Vector2(1.0, 2.0)},
		{"institution": HOUSE, "standing": "not a number"},
		{"institution": HOUSE, "treasury": 42.0},
		{"institution": HOUSE, "obligation": "not a dictionary"},
	]:
		var read := InstitutionLedger.read(bad)
		assert_eq(String(read["institution"]), "", "a corrupt field discards the record")
		assert_eq(bool(read["corrupt"]), true, "and says so rather than half-reading it")
		assert_eq(bool(read["ok"]), false, "and refuses rather than answering")
		assert_eq(String(read["reason"]), InstitutionLedger.R_CORRUPT_PAYLOAD, "naming the cause")
		assert_eq(int(read["standing"]), 0, "so no half state survives")
	# The element shape INSIDE a container is the writer's guarantee, not `read`'s: only
	# `write` ever authors a ledger, and it emits `String -> Array[String]` and nothing
	# else. `read` validates the CONTAINERS, and a `Resource` inside a roster is caught
	# by `is_save_safe` rather than silently coerced here.
	# A `standing_cap` of zero or less is REPAIRED rather than persisted, because a cap
	# that cannot be computed reports a normalized ratio of zero and reads as an
	# institution nobody respects.
	var repaired := InstitutionLedger.read(
		{"institution": HOUSE, "standing": 10, "standing_cap": 0}
	)
	assert_eq(int(repaired["standing_cap"]), 1, "the cap is repaired to at least one")
	assert_ne(float(repaired["normalized"]), 0.0, "so the ratio is computable")
	# An ABSENT field is different and normal: a member who holds no position simply
	# has none, and that is not corruption.
	var absent := InstitutionLedger.read({"institution": HOUSE})
	assert_eq(bool(absent["corrupt"]), false, "an absent field is not corruption")
	assert_eq(String(absent["position"]), "", "it reads as no position")


## ## `is_save_safe` is a callable, and it is RED on each of the four hazards
##
## `core/actor.gd` names the trap and says no checker can see it, so the property is a
## function a caller may ask — and each of its false arms is exercised here, because a
## guard nobody has seen fire is a guard nobody knows works.
func test_is_save_safe_is_red_on_each_of_the_four_hazards() -> void:
	assert_eq(InstitutionLedger.is_save_safe({}), true, "an empty payload is safe")
	assert_eq(
		InstitutionLedger.is_save_safe(
			{"a": 1, "b": "two", "c": [1, 2], "d": {"e": true}, "f": 1.5}
		),
		true,
		"primitives and plain containers are safe"
	)
	# A `StringName` VALUE is legal — every id in this repo is one in memory and every
	# payload converts it on the way out.
	assert_eq(
		InstitutionLedger.is_save_safe({"id": StringName("t_house")}),
		true,
		"a StringName VALUE is legal"
	)
	# A `StringName` KEY is not: it reaches the save untouched.
	assert_eq(
		InstitutionLedger.is_save_safe({StringName("t_house"): 1}), false, "a StringName KEY is not"
	)
	# A `Resource`, an `Actor` and a `Vector2` all reach the save untouched.
	assert_eq(
		InstitutionLedger.is_save_safe({"def": InstitutionClaim.new()}), false, "a Resource is not"
	)
	assert_eq(InstitutionLedger.is_save_safe({"actor": _actor(&"leak")}), false, "an Actor is not")
	assert_eq(InstitutionLedger.is_save_safe({"v": Vector2(1.0, 2.0)}), false, "a Vector2 is not")
	# And nested: a hazard one level down is a hazard, which is the whole point of a
	# walk rather than a top-level check.
	assert_eq(
		InstitutionLedger.is_save_safe({"outer": {"inner": Vector2(1.0, 1.0)}}),
		false,
		"and one nested deep is still a hazard"
	)
	# The depth cap is a CAP, not a fallback: a self-referential dictionary is refused
	# rather than recursing until the stack dies. This is the `ContentScan.MAX_DEPTH`
	# reasoning — a recursive walk is a `while` in disguise, so the arch rule cannot
	# see it.
	var deep: Dictionary = {}
	var cursor := deep
	for _level in range(InstitutionLedger.SAVE_SAFE_MAX_DEPTH + 4):
		var nxt: Dictionary = {}
		cursor["n"] = nxt
		cursor = nxt
	assert_eq(InstitutionLedger.is_save_safe(deep), false, "a too-deep payload is refused")
	# And a cyclic one, which is the case the cap exists for.
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	assert_eq(
		InstitutionLedger.is_save_safe(cyclic), false, "a cyclic payload is refused, not stacked"
	)


## ## `positive_lines` snapshots its bound BEFORE the loop
##
## The bound is a PARAMETER rather than a size of the container being built, because a
## limit read as `rows.size()` rises in lockstep with the body and never terminates —
## the loop that filled a 10 GB disk (INC-0002). This case pins both: the cap is
## honoured, and a payload far larger than the cap costs the cap and no more.
func test_positive_lines_honours_a_cap_and_a_payload_cannot_make_it_loop() -> void:
	var rows: Dictionary = {}
	# A `for` over a FIXED count building a NEW dictionary: the bound is a literal, so
	# there is no shape here for a `while` scan to reject.
	for index in range(500):
		rows["term_%d" % index] = index + 1
	var capped := InstitutionLedger.positive_lines(rows, 10)
	assert_eq(capped.size(), 10, "the cap bounds the result")
	# Zeros and non-integers drop out, because "nobody opened this debt" and "this
	# debt is settled" are the same state.
	var mixed := InstitutionLedger.positive_lines(
		{"a": 3, "b": 0, "c": -2, "d": "not a number", "e": 5}
	)
	assert_eq(mixed.keys().size(), 2, "only strictly positive counts survive")
	assert_eq(int(mixed["a"]), 3, "kept as an int")
	# The count cap bounds a corrupt value so arithmetic on it cannot be correct and
	# enormous at the same time.
	assert_eq(
		int(InstitutionLedger.positive_lines({"a": 99999}, 0, 100)["a"]), 100, "a count is clamped"
	)


## The `_text` reason is preserved verbatim in the source, because this is the ONE
## place it is written and a paraphrase is how it decays. The case asserts the text is
## still there rather than trusting a reader to have absorbed it.
func test_the_text_coercion_reasoning_is_still_written_down() -> void:
	var body := FileAccess.get_file_as_string("res://src/core/institution_ledger.gd")
	assert_ne(body, "", "the ledger file is readable")
	assert_eq(
		body.contains("String(42.0)"), true, "the coercion hazard is still named in the source"
	)
	assert_eq(body.contains("RAISES"), true, "and the word that carries the reasoning")


## ## No institution foundation file owns a CLOCK
##
## Nothing in `sect/` or `nation/` may read `Time.get_ticks*`, declare `_process` or
## call `get_tree()`: a ledger that counted periods from the wall clock would make a
## save's contents depend on when it was written (DEF-0111, ADR 0083). This is the
## check that keeps the generic `found` honest, and it reads CODE, not prose.
func test_no_institution_foundation_file_reads_a_clock() -> void:
	for rel in FOUNDATION_FILES:
		var body := FileAccess.get_file_as_string(rel)
		for needle in ["Time.get_ticks", "_process(", "get_tree("]:
			assert_eq(_calls(body, needle), 0, "%s never calls %s" % [rel.get_file(), needle])


# --- Helpers -------------------------------------------------------------------


func _pool(actor: Actor) -> ResourcePool:
	return actor.resource(POOL) as ResourcePool


## An actor whose base stats carry one realm's authored power, so R1 and R30 are two
## genuinely different sheets rather than two hand-written numbers. Built from the real
## ladder: a retune of `realm_power_table.tres` must not be able to quietly break the
## ratio this suite measures.
func _realm_scaled_actor(actor_id: StringName, ordinal: int) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	_born.append(actor)
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var realm: RealmDef = realms[clampi(ordinal - 1, 0, realms.size() - 1)]
	var power := maxf(1.0, realm.power)
	actor.stats.set_base(Stat.PHYSIQUE, 10.0 * power)
	actor.stats.set_base(Stat.COMPREHENSION, 8.0 * power)
	actor.stats.set_base(RECOGNISED, 4.0 * power)
	return actor


## The derived-stat ratio on `stat_id`, read as `after / before` against a `before`
## the caller took. A percent rides the sheet, so this is the same number at every
## realm; a flat would be enormous on a shallow sheet and negligible on a deep one.
func _ratio(actor: Actor, stat_id: StringName, before: float) -> float:
	if before == 0.0:
		return 1.0
	return actor.stats.derived(stat_id) / before


## Every derived stat, keyed by its string id. The comparison that matters is
## `assert_eq` on the whole map: byte-identical, not approximately equal.
func _derived(actor: Actor) -> Dictionary:
	var out := {}
	for stat_id in actor.stats.derived_all().keys():
		out[String(stat_id)] = actor.stats.derived(stat_id)
	return out


## Everything a `found` could possibly have written: the pool balance and the whole
## save payload. A refused verb must leave both identical, so both are in the
## fingerprint.
func _fingerprint(actor: Actor) -> Dictionary:
	return {"pool": _pool(actor).current, "save": actor.to_dict()}


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it.
## These files name the verbs they refuse inside their own class docs — ADR 0084's
## whole argument is WHICH writes are forbidden — so a raw `contains` scan fails on
## those sentences while reading the code beside them as clean.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## Every public method name on `klass`. The classes are all static-function shapes and
## GDScript refuses a non-static call on a class reference, so `load()` is the one way
## in.
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
