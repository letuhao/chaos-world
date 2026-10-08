extends TestCase

## ## The deliverable: an institution that is NOT a sect grants recognition
##
## DEF-0337 measured the gap and it was structural. The code that turns standing into
## a stat modifier lived inside `SectProjection._grant`, in `sect`, so a trading guild
## under the generic institutions directory could author no allowlist at all: the
## field that would carry one had no reader outside one module, and a generic
## allowlist with no projection is an author writing numbers that go nowhere.
##
## This suite is the evidence that the gap is closed **for a kind nobody ever wrote a
## module for**: it founds The Lantern Exchange off its own `.tres`, seats a member
## in a seat carrying an authored allowlist, and measures the one stat the guild
## recognises moving by exactly the bounded percent — then moving AGAIN when the member
## is demoted, because a falling number is the only way a member ever loses a grant
## (ADR 0084) and a demotion path that is not tested is not a demotion.
##
## ## The two measurements ADR 0084 says are OWED
##
##   - **realm-invariance in RATIO**, on the guild rather than on a sect: a percent
##     rides the member's own sheet, so the ratio is identical at R1 and at R30.
##   - **strip-then-rebuild idempotence**, including that stripping still works after
##     the defining `.tres` is gone.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over authored dictionaries, over a fixed
## list of shipped paths, or over a `for` over a literal range, and none of them
## appends to the container it is walking — so there is no bound to grow in lockstep
## and no shape `test_no_unbounded_wait.gd` could reject.

## The shipped guild this suite founds. Read, never mutated — see
## `_guild_with_an_allowlist`.
const LANTERN := "res://data/packs/guilds/organizations/lantern_exchange.tres"
## The office the allowlist is authored onto, and the office recognition STARTS at,
## so a case can show that a seat and a standing are two independent facts.
const SEAT := &"first_ledger"
const FLOOR := &"clerk"
## The stat this suite has the guild recognise. `insight_gain` derives to
## `1.0 + comprehension * 0.01` and `poise` to `physique * 0.5 + will * 0.5`, so both
## have a non-zero baseline on every actor here and a PERCENT on either is a real edge
## rather than ADR 0068's silent no-op. TWO ids, so the allowlist is a set and a
## rebuild that dropped one of them fails rather than halving.
const RECOGNISED := Stat.INSIGHT_GAIN
const ALSO := Stat.POISE
## The namespace a guild driver contributes under. The TAG itself is built at runtime
## through `InstitutionLedger.source_tagged`, because a GDScript `const` cannot hold a
## function call and a hand-spelled `"guild:lantern_exchange"` would be a third
## construction the shared helper exists to prevent.
const PREFIX := "guild:"

## Every verb this file's subject must never grow. `tools arch` cannot see a method
## that does not exist, so the structural half of ADR 0084 is a test — the shape
## `test_sect_no_power.gd` and `test_institution_def.gd` already use.
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

## The whole published surface, asserted as a WHOLE rather than only by the absence of
## the forbidden names, so a verb added later fails here rather than slipping past the
## word list.
const PUBLISHED := ["apply", "grant", "recognises", "strip", "unknown_stat"]

const PROJECTION_FILE := "res://src/core/institution_projection.gd"
const POSITION_FILE := "res://src/core/institution_position_def.gd"

## What a CONTENT file may never call. `add_modifier` is absent on purpose and the
## reason is the pair: the projector is the ONE place allowed to write a modifier and
## the position def is allowed to write none at all, so each is scanned against its own
## half and the projector cannot smuggle a `set_base` past the check that lets its
## `add_modifier` through.
const FORBIDDEN_CONTENT_CALLS := ["set_base", "add_base", "add_provider", "add_status"]

## Every shipped office allowlist outside `sect`/`nation`, so the extraction is
## measured against content rather than against a fixture written for it. Both shipped
## nations are included because `NationOfficeDef` is a THIRD copy of the field and the
## measurement has to cover all three families at once.
const SHIPPED_ALLOWLISTS := [
	"res://data/packs/sect/organizations/jade_court.tres",
	"res://data/packs/sect/organizations/iron_vine.tres",
	"res://data/packs/nation/organizations/march_of_the_nine_provinces.tres",
	"res://data/packs/nation/organizations/court_of_the_star.tres",
]

var _registry: InstitutionRegistry = null
## The source tag a guild driver would namespace under, built through
## `InstitutionLedger.source_tagged` rather than spelled out — so the construction and
## the prefix cannot drift, and the namespace stays the CALLER's.
var _source: StringName = &""
## An actor with no grant at all, for a stat this suite did not capture a BEFORE for.
var _reference: Actor = null
## Everything this suite mints, so teardown can drop it. **`free()` is never called on
## an entry**: `Actor` and `Resource` both extend `RefCounted`, and `Object.free()` on
## one is a SCRIPT ERROR that ABORTS the rest of teardown (measured in
## `test_institution_foundation`). This suite mints no `Node` at all, which is why
## dropping the array IS the release.
var _born: Array = []


func setup() -> void:
	_registry = InstitutionRegistry.new()
	InstitutionBoot.install(_registry)
	_source = InstitutionLedger.source_tagged(PREFIX, &"lantern_exchange")
	_reference = _actor(&"reference", 1)


func teardown() -> void:
	_born.clear()
	if _registry != null:
		_registry.clear()
		_registry = null


# --- The deliverable: a trading guild recognises a member ------------------------


## ## THE case. A guild member's recognised stat moves by the bounded percent, and
## moves AGAIN when standing falls.
##
## Every step is generic: the registry comes from `InstitutionBoot.install`, the
## founding verb is `InstitutionFounding.found`, the standing changes go through
## `InstitutionLedger.move_standing`, and the projection is the shared
## `InstitutionProjection`. No line of this case names a sect, and no guild module
## exists.
func test_a_trading_guild_member_is_recognised_and_the_grant_falls_when_standing_falls() -> void:
	var guild := _guild_with_an_allowlist()
	var allowlist := _allowlist(guild)
	var actor := _actor(&"factor", 1)
	var founded := InstitutionFounding.found(_registry, actor, guild.founding_profile(), "me")
	assert_eq(bool(founded["ok"]), true, "the guild is foundable by the generic verb")
	var ledger: Dictionary = founded["ledger"]
	# Pin the authored shape the rest of the case leans on: a founding seats the
	# founder in the TOP office and starts them on the authored standing under the
	# authored cap — and that cap is ABOVE 100, which is the whole of the cap case.
	assert_eq(String(ledger["position"]), String(SEAT), "the founder is seated in the seat")
	assert_eq(int(ledger["standing"]), 40, "on the authored founder standing")
	assert_eq(int(ledger["standing_cap"]), 150, "under a cap above 100")

	# The BEFORE is read off the DERIVED stat, not the base: a derived stat is
	# recomputed from its attributes, so its base is not the value a percent rides.
	var insight_before := actor.stats.derived(RECOGNISED)
	var poise_before := actor.stats.derived(ALSO)
	var granted := InstitutionProjection.apply(actor, ledger, allowlist, _source)
	assert_eq(bool(granted["ok"]), true, "the shared projection accepts the guild's office")
	assert_almost_eq(
		float((granted["granted"] as Dictionary)[String(RECOGNISED)]),
		0.04,
		"the percent is the standing's own rate, well under the cap"
	)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED), insight_before * 1.04, "so the first stat moved by it"
	)
	assert_almost_eq(actor.stats.derived(ALSO), poise_before * 1.04, "and so did the second")
	# Nothing outside the allowlist moved. An allowlist is a partition, not "something
	# changed", and that is the only claim a bounded percent on two ids can make.
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH), _bare(Stat.MAX_HEALTH), "and nothing else did"
	)

	# The rise: at the authored cap of 150 the percent saturates at
	# `STANDING_PERCENT_CAP` long before the cap is reached, so this is where a member
	# stops gaining recognition — while the LEDGER still reads 150.
	var raised := InstitutionLedger.move_standing(ledger, 110)
	assert_eq(int(raised["applied"]), 110, "standing rose to the authored cap")
	var after_rise := InstitutionProjection.apply(actor, raised["ledger"], allowlist, _source)
	assert_almost_eq(
		float((after_rise["granted"] as Dictionary)[String(RECOGNISED)]),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"recognition saturates at the authored ceiling"
	)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		insight_before * (1.0 + InstitutionClaim.STANDING_PERCENT_CAP),
		"and the sheet reflects the ceiling and no more"
	)
	assert_eq(int((raised["ledger"] as Dictionary)["standing"]), 150, "the ledger still says 150")

	# ## THE DEMOTION — the half ADR 0084 says must be as well tested as the
	# promotion, because a falling number is the ONLY way a member ever loses a grant:
	# standing is clamped at zero rather than allowed to run down, so it is a real cost.
	var dropped := InstitutionLedger.move_standing(raised["ledger"], -100)
	assert_eq(int(dropped["applied"]), -100, "standing fell")
	assert_eq(int((dropped["ledger"] as Dictionary)["standing"]), 50, "and the ledger says so")
	var after_fall := InstitutionProjection.apply(actor, dropped["ledger"], allowlist, _source)
	assert_almost_eq(
		float((after_fall["granted"] as Dictionary)[String(RECOGNISED)]),
		0.05,
		"so the granted percent fell with it"
	)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED), insight_before * 1.05, "and the recognised stat fell too"
	)
	# The position did not move. `move_standing` is the ONLY writer of `standing` and it
	# never reads `position`, so a member can sit on a seat on thin standing — which is
	# ADR 0064's split, asserted here because this is the one case where both numbers
	# are in hand at once.
	assert_eq(
		String((dropped["ledger"] as Dictionary)["position"]), String(SEAT), "the seat is unchanged"
	)

	# And to nothing at all — the third state of a falling number, exact rather than
	# approximate, because a strip that only nearly works strands the grant forever.
	InstitutionProjection.strip(actor, _source)
	assert_almost_eq(actor.stats.derived(RECOGNISED), insight_before, "leaving restores the sheet")
	assert_eq(_own_modifiers(actor), 0, "with nothing of ours left on the stack")


## ## The owed measurement, on a guild: realm-invariance in RATIO
##
## For one actor, the derived-stat ratio on every allowlisted id is identical at R1 and
## at R30. That is what makes "a percent, never a flat" a **property** rather than a
## hope: a flat is decisive on a shallow sheet and rounds to nothing on a deep one
## across the ladder that spans 1.0x to 551x (ADR 0063), whereas a percent rides the
## sheet and means the same thing at both ends.
func test_a_guilds_recognition_is_realm_invariant_in_ratio_at_r1_and_at_r30() -> void:
	var guild := _guild_with_an_allowlist()
	var allowlist := _allowlist(guild)
	assert_eq(allowlist.size(), 2, "the office recognises two ids, so this is not a single row")
	var standing := 90
	var percent := InstitutionClaim.standing_percent(standing)
	var shallow := _actor(&"shallow", 1)
	var deep := _actor(&"deep", 30)
	var shallow_before := _sheet(shallow, allowlist)
	var deep_before := _sheet(deep, allowlist)
	# Measured, not asserted: R30 really is a deeper sheet, or the ratio is trivially
	# equal and the case proves nothing.
	assert_ne(deep_before[String(RECOGNISED)], shallow_before[String(RECOGNISED)], "two sheets")
	InstitutionProjection.apply(shallow, {"standing": standing}, allowlist, _source)
	InstitutionProjection.apply(deep, {"standing": standing}, allowlist, _source)
	for stat_id in allowlist.keys():
		var id := StringName(stat_id)
		var at_r1 := _ratio(shallow, id, shallow_before[String(stat_id)])
		var at_r30 := _ratio(deep, id, deep_before[String(stat_id)])
		assert_almost_eq(at_r1, at_r30, "'%s' is the same ratio at R1 and at R30" % stat_id)
		# And the ratio IS the recognition, at its own value. `1.0` here would assert
		# that a percent moves nothing, the opposite of what ADR 0084 grants.
		assert_almost_eq(
			at_r1, 1.0 + percent, "'%s' moved by the recognition and only it" % stat_id
		)


## ## The owed measurement: strip-then-rebuild idempotence
##
## Re-attaching must leave the actor exactly where one attach left it, and a rebuild
## must still be INVERTIBLE after the defining `.tres` is deleted — the case ADR 0063
## raises, and the reason a claim records what it granted rather than re-reading the
## definition.
func test_rebuilding_never_compounds_and_stripping_survives_a_deleted_definition() -> void:
	var guild := _guild_with_an_allowlist()
	var office := guild.position(SEAT)
	var actor := _actor(&"rebuilt", 1)
	var ledger := {"standing": 60, "standing_cap": 150}
	InstitutionProjection.apply(actor, ledger, office.standing_percent_stats, _source)
	var before := _fingerprint(actor)
	# A `for` over a FIXED range: the body writes to the actor and never to the range
	# being walked, so the bound is the literal and there is nothing that could grow.
	for cycle in range(5):
		InstitutionProjection.apply(actor, ledger, office.standing_percent_stats, _source)
		assert_eq(_fingerprint(actor), before, "cycle %d leaves the actor identical" % cycle)
	assert_eq(_own_modifiers(actor), 2, "two ids, two modifiers, however many rebuilds")

	# ## The definition goes away. The tag is recorded on the claim rather than re-read
	# from the office, so the contribution is still exactly invertible — which is
	# precisely when a dropped `.tres` would otherwise leave it welded to whoever held
	# it. `guild` is a copy, so emptying its office cannot leak into another suite.
	office.standing_percent_stats = {}
	assert_eq(office.standing_percent_stats.size(), 0, "the office now recognises nothing")
	assert_eq(
		InstitutionProjection.unknown_stat(actor, office.standing_percent_stats),
		null,
		"so there is nothing left to refuse"
	)
	InstitutionProjection.strip(actor, _source)
	assert_eq(_own_modifiers(actor), 0, "and the whole contribution came back off")
	assert_almost_eq(
		actor.stats.derived(RECOGNISED), _bare(RECOGNISED), "restoring the sheet exactly"
	)


## The cap bounds the RATIO and **never truncates the ledger's number**. A guild
## publishing a cap above 100 is an authored choice, and a member sitting above what
## their standing reads as is ADR 0064's politics layer — a projector that clamped the
## standing into the cap would delete it, so nothing here reads `standing_cap` at all.
func test_the_cap_bounds_the_ratio_and_the_ledger_number_is_never_truncated() -> void:
	var guild := _guild_with_an_allowlist()
	var allowlist := _allowlist(guild)
	var actor := _actor(&"oversubscribed", 1)
	# Ten thousand standing under a cap of 150: the number the ledger publishes is the
	# politics and the projector has no opinion about it.
	var ledger := {"standing": 10000, "standing_cap": 150}
	var out := InstitutionProjection.apply(actor, ledger, allowlist, _source)
	assert_eq(bool(out["ok"]), true, "so the grant lands")
	assert_almost_eq(
		float((out["granted"] as Dictionary)[String(RECOGNISED)]),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"the percent is the ceiling and not standing's own rate"
	)
	assert_almost_eq(
		actor.stats.derived(RECOGNISED),
		_bare(RECOGNISED) * (1.0 + InstitutionClaim.STANDING_PERCENT_CAP),
		"and the sheet moved by the ceiling and no further"
	)
	assert_eq(int(ledger["standing"]), 10000, "while the ledger's own number is untouched")
	# The measurable form of "it never reads a cap": the same ledger with the key
	# absent grants the identical percent, so the cap provably has no path into the
	# percent at all — the bound is `STANDING_PERCENT_CAP`, authored in one place.
	var uncapped := InstitutionProjection.apply(actor, {"standing": 10000}, allowlist, _source)
	assert_almost_eq(
		float((uncapped["granted"] as Dictionary)[String(RECOGNISED)]),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"a cap of any value, or none at all, grants the same recognition"
	)


# --- Refusals, and the two states that are not refusals ---------------------------


## An allowlist id this stat sheet cannot NAME is refused **by name** and writes
## nothing at all. A PERCENT on a stat with no derivation evaluates to
## `(0.0 + 0.0) * (1 + p) = 0.0`, so projecting it would put a grant in the ledger that
## reads as landed and moves nothing — the silent no-op ADR 0068 measured on 44 items,
## and the failure ADR 0084's percent choice exists to avoid.
func test_an_allowlisted_stat_nothing_can_derive_is_refused_by_name_and_writes_nothing() -> void:
	var actor := _actor(&"typo", 1)
	var insight_before := actor.stats.derived(RECOGNISED)
	var seated := {"insight_gan": 0.0, String(RECOGNISED): 0.0}
	var report := InstitutionProjection.apply(actor, {"standing": 100}, seated, _source)
	assert_eq(bool(report["ok"]), false, "a stat nothing can derive is refused")
	assert_eq(
		String(report["reason"]),
		InstitutionProjection.R_UNKNOWN_RECOGNISED_STAT,
		"and the refusal names its own cause"
	)
	assert_eq(String(report["unknown"]), "insight_gan", "and names the offending id, not swallowed")
	assert_eq(_own_modifiers(actor), 0, "and nothing was written to the stack")
	assert_almost_eq(actor.stats.derived(RECOGNISED), insight_before, "so the sheet never moved")
	assert_almost_eq(
		actor.stats.derived(&"insight_gan"), 0.0, "and the invented id derives nothing"
	)
	# It refuses the WHOLE allowlist rather than skipping the one bad id, because half
	# an allowlist landing is how "the office recognises nothing" and "the office was
	# never consulted" come to look identical from outside.
	var mixed := seated.duplicate()
	(mixed as Dictionary)[String(RECOGNISED)] = 0.0
	assert_eq(
		InstitutionProjection.unknown_stat(actor, mixed),
		"insight_gan",
		"one bad id names the office"
	)
	# A BASE ATTRIBUTE is a legal target even on a sheet that carries none of it, because
	# an attribute is a real derivation this particular member has not bought. Refusing
	# it would make recognition depend on an unrelated investment.
	assert_eq(
		InstitutionProjection.unknown_stat(actor, {String(Stat.COMPREHENSION): 0.0}),
		null,
		"while an unbought attribute is still a derivation"
	)
	# ## An EMPTY-STRING key is a content fault and is NAMED, which is why "no fault" is
	# `null` and not `""`. The first version returned `""` from both answers, so
	# `{"": 0.0}` — a `.tres` Godot loads without complaint — reported itself clean and
	# the projector went on to write a modifier on `&""` that no reader can ever look up.
	# This is the one defect the adversarial pass on this slice found that the suite did
	# not, so it is pinned here rather than left to a future reader's luck.
	var blank := {"": 0.0, String(RECOGNISED): 0.0}
	assert_eq(
		InstitutionProjection.unknown_stat(actor, blank),
		"",
		"an empty key is named as the offender"
	)
	var blanked := InstitutionProjection.apply(actor, {"standing": 100}, blank, _source)
	assert_eq(bool(blanked["ok"]), false, "and a blank key is refused, not granted")
	assert_eq(
		String(blanked["reason"]),
		InstitutionProjection.R_UNKNOWN_RECOGNISED_STAT,
		"naming the same cause as any other unnameable id"
	)
	assert_eq(String(blanked["unknown"]), "", "with the empty id itself as the name")
	# ## The refusal is NON-DESTRUCTIVE, which is the order `grant` runs its two halves
	# in and the reason a member's standing recognition does not vanish because a modder
	# mistyped an id. The previous good pass stands; ADR 0083's third state is "this was
	# refused", and taking back a working grant would be a write (ADR 0044).
	InstitutionProjection.apply(actor, {"standing": 100}, {String(RECOGNISED): 0.0}, _source)
	var held := actor.stats.derived(RECOGNISED)
	assert_ne(_own_modifiers(actor), 0, "so a good pass is standing")
	var refused := InstitutionProjection.apply(actor, {"standing": 100}, seated, _source)
	assert_eq(bool(refused["ok"]), false, "and a broken allowlist is still refused")
	assert_eq(actor.stats.derived(RECOGNISED), held, "while the recognition already granted stands")
	# The next good rebuild after the broken one is exact, so the refusal left no debris.
	InstitutionProjection.apply(actor, {"standing": 100}, {String(RECOGNISED): 0.0}, _source)
	assert_eq(actor.stats.derived(RECOGNISED), held, "and a good pass rebuilds to the same value")
	assert_eq(_own_modifiers(actor), 1, "with exactly one modifier, never two")


## An office with an EMPTY allowlist is an authored choice and not a fault. It is
## ADR 0083's FIRST state — "this does not exist" — rather than its third, so it
## succeeds carrying an empty grant and never a reason. Every shipped guild `.tres`
## authors exactly this, and recognition beginning where office begins is a design.
func test_an_office_with_an_empty_allowlist_is_authored_content_and_not_a_fault() -> void:
	var actor := _actor(&"clerk", 1)
	var insight_before := actor.stats.derived(RECOGNISED)
	var seated := InstitutionProjection.apply(
		actor, {"standing": 100, "standing_cap": 150}, {}, _source
	)
	assert_eq(bool(seated["ok"]), true, "an empty allowlist succeeds")
	assert_eq(String(seated["reason"]), "", "with no reason to report")
	assert_eq((seated["granted"] as Dictionary).size(), 0, "and nothing granted")
	assert_eq(_own_modifiers(actor), 0, "so the stack carries nothing")
	# Thick standing in an office that recognises nothing recognises nothing, however
	# much is earned — the two-part split made expressible.
	assert_almost_eq(actor.stats.derived(RECOGNISED), insight_before, "so however earned, no")
	# An entry with no tag cannot be granted at all, because it could never be taken
	# back: ADR 0084's source-tagging is what makes a rebuild invertible, so a grant
	# without one is refused at the only place that could have produced it.
	assert_eq(
		String(InstitutionProjection.grant(actor, {String(RECOGNISED): 0.0}, 100, &"")["reason"]),
		InstitutionProjection.R_NO_SOURCE_TAG,
		"an untagged grant is refused by name"
	)
	assert_eq(
		String(
			InstitutionProjection.grant(null, {String(RECOGNISED): 0.0}, 100, _source)["reason"]
		),
		InstitutionLedger.R_NO_ACTOR,
		"and a grant with no sheet is a DIFFERENT named refusal"
	)


# --- The extraction itself: same rules, and the same result on shipped content -----


## ## ADR 0084's rules are STRUCTURAL here, because nothing else can see them
##
## `tools arch` cannot see a method that does not exist, so the whole-surface
## assertion is the guard. And nothing may reach for `set_base` — it bypasses the
## stack, so it cannot be stripped, cannot be rebuilt idempotently, and DOES satisfy
## `get_base`, which is exactly how an institution would smuggle a member past the
## gates meant to test them. The position def is held to the stricter half, because a
## CONTENT file must not write a modifier at all: two readers of an allowlist is ADR
## 0066's failure mode, and the prior slice deleted a method rather than add one.
func test_the_projection_publishes_no_power_granting_verb_and_writes_no_base() -> void:
	var published := _published()
	assert_eq(published.is_empty(), false, "the class publishes a readable method list")
	for verb in FORBIDDEN_VERBS:
		assert_eq(published.has(verb), false, "InstitutionProjection publishes no '%s'" % verb)
	assert_eq(published, PUBLISHED, "and the surface is exactly the five verbs it claims")
	for rel in [PROJECTION_FILE, POSITION_FILE]:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for forbidden in FORBIDDEN_CONTENT_CALLS:
			assert_eq(_calls(body, forbidden), 0, "%s never calls %s" % [rel.get_file(), forbidden])
	# The one call the projector IS allowed, and the position def is not.
	assert_eq(
		_calls(FileAccess.get_file_as_string(POSITION_FILE), "add_modifier"),
		0,
		"a content file writes no modifier of any op"
	)
	assert_eq(
		_calls(FileAccess.get_file_as_string(PROJECTION_FILE), "standing_percent_stats"),
		0,
		"and the projector never reads a def type, so any kind can drive it"
	)
	# The field is DECLARED here and read only by the projection, so there is exactly
	# one place in the tree that knows what an allowlist is.
	assert_eq(
		_calls(FileAccess.get_file_as_string(POSITION_FILE), "standing_percent_stats"),
		1,
		"the allowlist is declared once and has no second reader"
	)


## ## Every modifier this file writes is a source-tagged PERCENT at the capped value
func test_every_modifier_written_is_a_source_tagged_percent_at_the_capped_value() -> void:
	var guild := _guild_with_an_allowlist()
	var actor := _actor(&"stacked", 1)
	InstitutionProjection.apply(
		actor, {"standing": 900, "standing_cap": 150}, _allowlist(guild), _source
	)
	assert_ne(_own_modifiers(actor), 0, "the seat does carry a grant")
	var seen := 0
	for modifier in actor.stats._modifiers:
		if not InstitutionLedger.owns_source(PREFIX, modifier.source):
			continue
		seen += 1
		assert_eq(modifier.op, Stat.Op.PERCENT, "a grant is PERCENT, never FLAT or MULT")
		assert_eq(modifier.source, _source, "and carries the caller's own tag")
		assert_almost_eq(
			modifier.value, InstitutionClaim.STANDING_PERCENT_CAP, "and it is the capped percent"
		)
	assert_eq(seen, 2, "and both authored ids are on the stack")
	# The tag is NAMESPACE-scoped, which is the whole of `source_tagged`: a strip under
	# the guild prefix must not take a sect's contribution with it, or one tier would
	# silently unwrite another's grant.
	var foreign := InstitutionLedger.source_tagged("sect:", &"t_house")
	actor.stats.add_modifier(StatModifier.new(RECOGNISED, Stat.Op.FLAT, 5.0, foreign))
	var with_foreign := actor.stats.derived(RECOGNISED)
	InstitutionProjection.strip(actor, _source)
	assert_ne(actor.stats.derived(RECOGNISED), with_foreign, "a foreign source survives the strip")
	assert_eq(_own_modifiers(actor), 0, "and the guild's own two modifiers are gone")


## ## The extraction is MEASURED against the content it is lifted out of
##
## Every allowlist any shipped sect or nation office authors is pushed through the
## shared projection, and each must produce exactly one PERCENT per id at exactly the
## standing's own percent. This is the measurement that says the drop-in is safe for
## `SectProjection._grant` to delegate: the loop's whole behaviour is "one capped
## percent per authored id, under my tag", and this walks all of it against the real
## `.tres` files rather than a fixture — including `NationOfficeDef`, which is a THIRD
## copy of the field and would not be covered by a sect-only sweep.
func test_the_shared_projection_reproduces_every_shipped_office_allowlist() -> void:
	var checked := 0
	var actor := _actor(&"carrier", 1)
	for path in SHIPPED_ALLOWLISTS:
		var def := load(path)
		assert_ne(def, null, "%s loads" % path)
		var standing := 70
		var percent := InstitutionClaim.standing_percent(standing)
		for office in _offices_of(def):
			var allowlist: Dictionary = office.get("standing_percent_stats")
			if allowlist == null or allowlist.is_empty():
				continue
			var report := InstitutionProjection.apply(
				actor, {"standing": standing}, allowlist, _source
			)
			assert_eq(bool(report["ok"]), true, "%s/%s is grantable" % [path.get_file(), office.id])
			assert_eq(
				(report["granted"] as Dictionary).size(),
				allowlist.size(),
				"one grant per authored id on %s/%s" % [path.get_file(), office.id]
			)
			for stat_id in allowlist.keys():
				assert_almost_eq(
					float((report["granted"] as Dictionary)[String(stat_id)]),
					percent,
					"and '%s' is the standing's own percent" % stat_id
				)
				assert_eq(
					InstitutionProjection.recognises(allowlist, StringName(stat_id)),
					true,
					"so '%s' is recognised by name too" % stat_id
				)
			checked += 1
	assert_eq(checked > 0, true, "the shipped content really does carry allowlists")


## ## ADR 0084's "every id must have a non-zero baseline in its derivation"
##
## `tools arch` cannot validate an allowlist, and the projector deliberately cannot at
## RUNTIME either: an id this sheet happens to carry can still read zero on a member
## who invested nothing in it, which is an ordinary sheet rather than a content fault.
## So the rule is enforced where it IS decidable — over the ids the shipped content
## names, on an actor who has invested in **every** attribute. An id that still derives
## zero there has no scale for a percent at all, and its grant would be the guaranteed
## `(0.0 + 0.0) * (1 + p) = 0.0` no-op. This is ADR 0068's shape test applied to the
## allowlist field, and the last assertion proves the test can still go red.
func test_every_id_the_shipped_content_names_has_a_derivation_on_a_full_sheet() -> void:
	assert_eq(_own_modifiers(_reference), 0, "so the reference actor carries no grant of its own")
	assert_eq(_reference.stats.get_base(Stat.PHYSIQUE), 10.0, "and it is a fully invested sheet")
	var named := 0
	for path in SHIPPED_ALLOWLISTS:
		var def := load(path)
		for office in _offices_of(def):
			var allowlist: Dictionary = office.get("standing_percent_stats")
			if allowlist == null:
				continue
			for stat_id in allowlist.keys():
				named += 1
				assert_ne(
					_reference.stats.derived(StringName(stat_id)),
					0.0,
					"'%s' on %s/%s has a baseline to scale" % [stat_id, path.get_file(), office.id]
				)
				# And the projector can NAME it, so the runtime refusal would not fire on
				# shipped content — the two halves of the rule are separately decidable
				# and neither is inferred from the other.
				assert_eq(
					InstitutionProjection.unknown_stat(_reference, {String(stat_id): 0.0}),
					null,
					"so the projector can name it too"
				)
	assert_eq(named > 0, true, "the shipped content really does name stat ids")
	# ## The RED path, asserted in the same breath. `Stat.DAMAGE_REDUCTION` is the id
	# ADR 0068 documents as deriving a literal `0.0`, which is why it is deliberately
	## absent from `Stat.RATE_STATS`; a percent on it is the no-op. Nothing shipped
	## allowlists it, so without this line the case would pass on any tree and prove
	## nothing (INC-0016).
	assert_almost_eq(
		_reference.stats.derived(Stat.DAMAGE_REDUCTION),
		0.0,
		"the shape test would still catch the one id with no scale"
	)


## ## Position and standing NEVER derive from each other, in either direction
##
## ADR 0064's split, carried forward by ADR 0083 and by this whole file: the allowlist
## is the OFFICE's and the percent is the STANDING's, so seating somebody grants
## recognition and earning standing does not. A design that collapsed the pair into one
## number has built a spreadsheet, and this suite exists so that number never ships.
func test_the_office_carries_the_allowlist_and_the_standing_carries_the_percent() -> void:
	var guild := _guild_with_an_allowlist()
	var actor := _actor(&"split", 1)
	var ledger := {"standing": 150, "standing_cap": 150}
	# Thick standing in the ORDINARY office recognises nothing, which is the state the
	# split exists to make expressible.
	var ordinary := _allowlist_of(guild, FLOOR)
	assert_eq(ordinary.size(), 0, "the guild's ordinary office recognises nothing at all")
	var thick := InstitutionProjection.apply(actor, ledger, ordinary, _source)
	assert_eq(bool(thick["ok"]), true, "an empty office allowlist is content, not a fault")
	assert_eq((thick["granted"] as Dictionary).size(), 0, "so thick standing recognises nothing")
	# Gaining the seat grants it, at exactly what the standing had already earned and
	# not one point of standing more — the two halves of the split in one measurement.
	var seated := InstitutionProjection.apply(actor, ledger, _allowlist(guild), _source)
	assert_eq((seated["granted"] as Dictionary).size(), 2, "the seat's own allowlist grants it")
	assert_almost_eq(
		float((seated["granted"] as Dictionary)[String(RECOGNISED)]),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"at exactly the cap the standing earns, never more"
	)
	assert_almost_eq(
		float((thick["granted"] as Dictionary).get(String(RECOGNISED), 0.0)),
		0.0,
		"and the ordinary office granted none of it"
	)


# --- Save safety and layering -----------------------------------------------------


## A ledger must round-trip through `JSON.parse_string(JSON.stringify(...))`, and
## `core/actor.gd` copies `module_data` VERBATIM, converting only the OUTER key — so an
## inner `StringName` key, a `Resource`, an `Actor` or a `Vector2` reaches the save
## untouched and **no checker in this repo can see it**. The grant record is primitives
## with `String` keys by construction, and this asserts it through the same hop a real
## save takes.
func test_the_grant_record_is_save_safe_and_round_trips_a_ledger() -> void:
	var guild := _guild_with_an_allowlist()
	var actor := _actor(&"saved", 1)
	actor.set_module_data(&"institution_state", {"standing": 80, "standing_cap": 150})
	var report := InstitutionProjection.apply(
		actor, actor.get_module_data(&"institution_state"), _allowlist(guild), _source
	)
	var granted: Dictionary = report["granted"]
	assert_eq(InstitutionLedger.is_save_safe(granted), true, "the grant record is save safe")
	# The red half of the same guard, so this is not a test that passes on any tree: an
	# inner `StringName` key is exactly what no checker sees, and this is the shape it
	# must refuse.
	assert_eq(
		InstitutionLedger.is_save_safe({StringName("insight_gain"): 0.04}),
		false,
		"and the shape it forbids is still the shape it refuses"
	)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(actor.to_dict()))
	var ledger: Dictionary = restored["module_data"]["institution_state"]
	# **Both sides of every round-trip identity go through the hop**, because
	# `JSON.parse_string` returns every number as a `float` and a byte-for-byte
	# assertion here is unachievable.
	assert_almost_eq(float(ledger["standing"]), 80.0, "the standing survived the save")
	assert_eq(int(ledger["standing_cap"]), 150, "and the authored cap with it")
	var replayed := InstitutionProjection.apply(actor, ledger, _allowlist(guild), _source)
	assert_almost_eq(
		float((replayed["granted"] as Dictionary)[String(RECOGNISED)]),
		float(granted[String(RECOGNISED)]),
		"so a restored ledger rebuilds to the same percent"
	)


## ## `core/` reads nothing outside itself, and owns no clock
##
## The whole reason the consumer could move down here is that it needs nothing from a
## module, and that is an assumption a later refactor could quietly break. Asserted
## against the SOURCE, because the thing that would break it IS a refactor: a bare class
## name, a `preload` or a path literal, and the guarantee goes with it. No clock either —
## a ledger whose contents depended on when the save was written is not a ledger
## (DEF-0111).
func test_the_projection_names_no_module_no_app_and_no_clock() -> void:
	var body := FileAccess.get_file_as_string(PROJECTION_FILE)
	assert_ne(body, "", "the projection file is readable")
	for forbidden in [
		"modules/",
		"src/app/",
		"Time.get_ticks",
		"_process",
		"get_tree(",
		"extends Node",
		"set_base",
		"add_provider",
	]:
		assert_eq(_calls(body, forbidden), 0, "the projector never names '%s'" % forbidden)


# --- Helpers ----------------------------------------------------------------------


## The shipped guild, with an allowlist authored onto its seat.
##
## **The shipped `.tres` is read and never written.** `load()` caches process-wide and
## the runner drives every suite in ONE process, so writing to a shipped resource
## leaks the edit into every suite that follows. So the offices are COPIED into a fresh
## array rather than mutated in place — which is also why this builds a def: the shipped
## file authors NO allowlist, and authoring one is content, so the content is built here
## where it cannot escape.
func _guild_with_an_allowlist() -> InstitutionDef:
	var shipped := load(LANTERN) as InstitutionDef
	assert_ne(shipped, null, "the shipped guild loads")
	var mine := shipped.duplicate() as InstitutionDef
	var offices: Array[InstitutionPositionDef] = []
	for office in shipped.positions:
		var fresh := _copy_office(office)
		if fresh.id == SEAT:
			fresh.standing_percent_stats = {RECOGNISED: 0.0, ALSO: 0.0}
		offices.append(fresh)
	mine.positions = offices
	mine.top_position_id = SEAT
	_born.append(mine)
	return mine


## A copy of one authored office, so a test may author content no `.tres` on disk holds
## without writing to the shipped one.
func _copy_office(office: InstitutionPositionDef) -> InstitutionPositionDef:
	var out := InstitutionPositionDef.new()
	out.id = office.id
	out.display_name = office.display_name
	out.description = office.description
	out.capacity = office.capacity
	out.duties = office.duties.duplicate()
	out.authorities = office.authorities.duplicate()
	out.duty_per_period = office.duty_per_period
	out.patronage_per_period = office.patronage_per_period
	_born.append(out)
	return out


func _allowlist(guild: InstitutionDef) -> Dictionary:
	return _allowlist_of(guild, SEAT)


func _allowlist_of(guild: InstitutionDef, position_id: StringName) -> Dictionary:
	var office := guild.position(position_id)
	assert_ne(office, null, "the guild authors the '%s' office" % position_id)
	return office.standing_percent_stats


func _actor(actor_id: StringName, ordinal: int) -> Actor:
	var actor := Actor.new(actor_id, {})
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 9000.0))
	_born.append(actor)
	# EVERY base attribute, at one realm's authored power, so R1 and R30 are two
	# genuinely different sheets rather than two hand-written numbers AND no derived
	# stat reads zero for want of an investment the author never intended. Built from
	# the real ladder, so a retune of the realm table cannot quietly break the ratio.
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var realm: RealmDef = realms[clampi(ordinal - 1, 0, realms.size() - 1)]
	var power := maxf(1.0, realm.power)
	for attribute in Stat.BASE_ATTRIBUTES:
		actor.stats.set_base(attribute, 10.0 * power)
	return actor


## Every authored office under any def, whatever its type. Read through `Resource.get`
## on both spellings rather than through two typed walks, because `SectDef` and
## `InstitutionDef` call the list `positions` and `NationDef` calls it `offices`, and a
## sweep that only knew one of them would report "every shipped allowlist" while
## measuring a third of them.
func _offices_of(def) -> Array:
	var out: Array = []
	if def == null:
		return out
	for key in ["positions", "offices"]:
		var row = def.get(key)
		if not (row is Array):
			continue
		for office in row as Array:
			if office != null:
				out.append(office)
	return out


## Every value on `allowlist` before any grant, keyed by string id — the BEFORE a ratio
## is measured against. A derived stat is recomputed from its attributes, so its BASE is
## not the value a percent rides and dividing one by the other would be a ratio of two
## unrelated numbers.
func _sheet(actor: Actor, allowlist: Dictionary) -> Dictionary:
	var out := {}
	for stat_id in allowlist.keys():
		out[String(stat_id)] = actor.stats.derived(StringName(stat_id))
	return out


func _ratio(actor: Actor, stat_id: StringName, before: float) -> float:
	if before == 0.0:
		return 1.0
	return actor.stats.derived(stat_id) / before


## A stat's value on an actor carrying no grant at all, for a stat this suite did not
## capture a BEFORE for. Read off the reference actor rather than the subject, so the
## "nothing else moved" claim is measured against the same sheet.
func _bare(stat_id: StringName) -> float:
	return _reference.stats.derived(stat_id)


## Every modifier on `actor` under this suite's own guild namespace.
func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if InstitutionLedger.owns_source(PREFIX, modifier.source):
			total += 1
	return total


## Everything a rebuild could have changed: the whole sheet, the stack, and the traits.
func _fingerprint(actor: Actor) -> Dictionary:
	var sheet := {}
	for stat_id in actor.stats.derived_all().keys():
		sheet[String(stat_id)] = actor.stats.derived(stat_id)
	return {"sheet": sheet, "mods": actor.stats.modifier_count(), "own": _own_modifiers(actor)}


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it —
## this subject names the verbs it refuses inside its own class docs, so a raw
## `contains` scan would fail on those sentences while reading the code beside them as
## clean.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## Every public method name on this class, underscore-prefixed names dropped exactly as
## `tools/arch/enforce.py` drops them, so this suite and the gate count the same surface.
## `load()` is the one way in: GDScript refuses a non-static call on a class reference.
func _published() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load(PROJECTION_FILE)
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
