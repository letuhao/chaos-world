extends TestCase

## ## The shape of the institution surface: what it stores, what it publishes, what it may
## never grow
##
## `test_institution_membership.gd` proves the VERBS. This file proves the three properties
## that are invisible from a verb's answer and are the ones ADR 0084, ADR 0083 and ADR 0044
## actually turn on:
##
##   1. **The store round-trips the save hop.** `Actor.to_dict` copies `module_data`
##      VERBATIM and converts only the OUTER key, so an inner `StringName` key, a `Resource`,
##      an `Actor` or a `Vector2` reaches the save untouched — and **no checker in this repo
##      can see it**, because `tools arch` reads references and `JSON.parse_string` fails at
##      LOAD time in front of the player rather than at write time in front of the author.
##   2. **The published surface grants no power.** "Recognition, access and transmission only
##      — never power" is a claim about METHODS, and a checker cannot see a method that does
##      not exist. So the whole surface is asserted by name, not merely by the absence of a
##      forbidden word.
##   3. **Nothing in the family owns a clock** (DEF-0111): a ledger whose contents depended
##      on when the save was written is not a ledger.
##
## ## The shipped guilds only, deliberately
##
## This suite needs no authored allowlist, so it drives SHIPPED content and touches no
## fixture tree — the overlay fixtures and their teardown live in the verbs suite, and a
## second copy of them here would be a second thing that can leak.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over a fixed literal or over a materialised key
## list, and none appends to the container it walks.

## The shipped organizations, read and NEVER written. `load()` caches process-wide and the
## runner drives every suite in ONE process, so a write here leaks into every suite after it.
const LANTERN := "res://data/institutions/lantern_exchange.tres"
const LANTERN_ID := &"lantern_exchange"
const HUNT_ID := &"grey_horizon_hunt"
const SEAT := &"first_ledger"

const MEMBERSHIP_FILE := "res://src/core/institution_membership.gd"

## The verbs this surface must never grow. **`add_modifier` is on the list** because the
## projector is the ONE place allowed to write a modifier, so a second writer here would be a
## second stat composer — the machinery ADR 0084 refuses.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"grant_modifier",
	"add_modifier",
	"contribute",
]

## The WHOLE published surface, asserted as a whole rather than only by the absence of the
## forbidden names, so a verb added later fails here rather than slipping past a word list.
const PUBLISHED := [
	"claim_of",
	"clear",
	"found",
	"holds",
	"join",
	"leave",
	"move_standing",
	"reproject",
	"roster_of",
	"rosters",
	"source_tag",
	"summary",
]

## Every file the family owns. A `for` over a FIXED literal list, reading each: the body never
## appends to the list, and the bound is the list's own length.
const FAMILY_FILES := [
	MEMBERSHIP_FILE,
	"res://src/core/institution_ledger.gd",
	"res://src/core/institution_claim.gd",
	"res://src/core/institution_founding.gd",
	"res://src/core/institution_projection.gd",
	"res://src/core/institution_registry.gd",
	"res://src/core/institution_def.gd",
	"res://src/core/institution_def_catalog.gd",
]

## An actor carrying no grant at all, so "nothing else moved" is measured against the same
## sheet rather than against a hand-written number.
var _reference: Actor = null
## Everything this suite mints. **`free()` is never called on an entry**: `Actor` and
## `Resource` both extend `RefCounted`, and `Object.free()` on one is a SCRIPT ERROR that
## aborts the rest of teardown. Dropping the array IS the release.
var _born: Array = []


func setup() -> void:
	# BOTH singletons, in setup AND teardown: the runner drives every suite in ONE process,
	# so `setup` clears what a PREVIOUS suite left and `teardown` clears what this one does.
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	_reference = _actor(&"reference")


func teardown() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	if InstitutionRegistry.shared != null:
		InstitutionRegistry.shared.clear()
	_born.clear()


# --- The store and the save ------------------------------------------------------


## ## The membership store survives the JSON hop
##
## `JSON.parse_string` returns every number as a float, so BOTH sides go through the hop and
## the FACTS are compared rather than the representation — a byte-for-byte comparison across
## this boundary is not achievable and pretending otherwise is how a round-trip assertion
## passes while the data differs.
func test_the_membership_store_round_trips_through_the_actor_save() -> void:
	var registry := InstitutionRegistry.new()
	InstitutionBoot.install(registry)
	var actor := _actor(&"saved")
	InstitutionMembership.found(registry, actor, _guild(), "me")
	InstitutionMembership.move_standing(registry, actor, LANTERN_ID, 33)
	InstitutionMembership.join(registry, actor, HUNT_ID)
	var before := InstitutionMembership.summary(actor)
	assert_eq((before["institutions"] as Dictionary).size() > 0, true, "there is something to save")

	var parsed = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(parsed, null, "the payload parses")
	var restored := Actor.from_dict(parsed as Dictionary)
	assert_ne(restored, null, "and the body comes back")
	_born.append(restored)
	assert_eq(
		_through_json(InstitutionMembership.summary(restored)),
		_through_json(before),
		"the read model survives the hop unchanged, facts and not representation"
	)
	# AND the store is save-SAFE by the SHARED callable, which is the only check in this repo
	# that can see an inner value type at all. A `StringName` VALUE is legal (every id in this
	# repo is one in memory and every payload converts it on the way out); a `StringName` KEY
	# is not, and that is the branch this exercises.
	var slot: Variant = restored.module_data.get(InstitutionMembership.MEMBERSHIP_KEY)
	assert_eq(
		InstitutionLedger.is_save_safe(slot),
		true,
		"the slot carries only what a save can round-trip"
	)
	# And the claim is still the actor's, read back through the same verb.
	assert_eq(InstitutionMembership.holds(restored, LANTERN_ID), true, "so the body still belongs")
	registry.clear()


## ## The ROSTER is process state, and what a RESTART loses is measured
##
## The claims ride the save; the roster does not, because no world save slot can accept one —
## `WorldPolityLedger`'s row normalizer keeps `kind`, `standing`, `standing_cap` and
## `sequence` and DROPS everything else, and its own boundary rule forbids an actor id on a
## row. So `clear()` stands in for the quit: the question is what a player sees after they
## close the game.
##
## The answer is an EMPTY roster for a house that exists — ADR 0083's FIRST state, which the
## card renders as `holders not published` and never as a vacancy nobody declared. The CLAIMS
## are unaffected, so an exit loses the ROSTER and not the membership.
func test_a_restart_loses_the_world_roster_and_not_the_membership() -> void:
	var registry := InstitutionRegistry.new()
	InstitutionBoot.install(registry)
	var actor := _actor(&"quit")
	InstitutionMembership.found(registry, actor, _guild(), "me")
	var held: Array = InstitutionMembership.roster_of(LANTERN_ID)[String(SEAT)]
	assert_eq(held.size(), 1, "while the process runs the seat names its holder")

	InstitutionMembership.clear()
	assert_eq(InstitutionMembership.rosters(), {}, "the world publishes nothing")
	assert_eq(
		InstitutionMembership.roster_of(LANTERN_ID),
		{},
		"and an organization nobody published a roster for answers {} rather than an empty one"
	)
	assert_eq(
		(InstitutionMembership.roster_of(LANTERN_ID) as Dictionary).get(String(SEAT)),
		null,
		"so no office claims to be held, and none is declared vacant either"
	)
	assert_eq(
		InstitutionMembership.holds(actor, LANTERN_ID),
		true,
		"while the membership itself came back off the save untouched"
	)
	registry.clear()


# --- The structural half: it grants no power --------------------------------------


## ## ADR 0084's structural half, which `tools arch` CANNOT see
##
## "Recognition, access and transmission only — never power" is a claim about METHODS, and a
## checker reading references cannot see a method that does not exist. So the whole published
## surface is asserted, name for name, against the forbidden list AND as a whole: a verb
## added later fails here rather than slipping past a word list.
func test_the_published_surface_grants_no_power() -> void:
	var body := FileAccess.get_file_as_string(MEMBERSHIP_FILE)
	assert_ne(body, "", "the membership file is readable")
	for verb in FORBIDDEN_VERBS:
		assert_eq(_calls(body, verb), 0, "'%s' is never written in code" % verb)
	assert_eq(_published(), PUBLISHED, "the published surface is exactly this one")
	# A module facade's cap does not apply here — `core/` is a LAYER, not a module — but the
	# published set is short on purpose: every name is a verb a caller presses or a read it
	# could not have reached through another verb.
	assert_eq(PUBLISHED.size(), 12, "twelve verbs, each with a caller or a named reason")


## ## NOTHING IN THE FAMILY OWNS A CLOCK
##
## No institution owns a clock (DEF-0111, ADR 0083). The rule is a property of the LAYER, so
## it is asserted over every file the family owns and not over this subject alone.
##
## **Counted over CODE, not prose.** Every one of these files names the three verbs it refuses
## in its own class docs — "no `_process`, no `Time.get_ticks*`, no `get_tree()`" is the
## sentence the rule is written in — so a raw `contains` reads the documentation as a
## violation. `_calls` skips the `##` lines and counts the rest.
func test_nothing_in_the_family_owns_a_clock() -> void:
	for path in FAMILY_FILES:
		var body := FileAccess.get_file_as_string(path)
		assert_ne(body, "", "%s is readable" % path)
		assert_eq(_calls(body, "Time.get_ticks"), 0, "%s owns no clock" % path)
		assert_eq(_calls(body, "func _process"), 0, "%s declares no process" % path)
		assert_eq(_calls(body, "get_tree()"), 0, "%s reaches for no tree" % path)


# --- Helpers ----------------------------------------------------------------------


## The shipped guild, loaded and read. Nothing is written to it — see the file note.
func _guild() -> InstitutionDef:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	return def


## An actor with a funded founding pool and every base attribute at one realm's authored
## power, so a derived stat reads non-zero for want of an investment the author never intended.
func _actor(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {})
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 9000.0))
	_born.append(actor)
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var power := maxf(1.0, (realms[0] as RealmDef).power)
	for attribute in Stat.BASE_ATTRIBUTES:
		actor.stats.set_base(attribute, 10.0 * power)
	return actor


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


## A payload through the JSON hop, so both sides of a round-trip assertion are the same
## representation. `JSON.parse_string` returns every number as a float, which is why a
## byte-for-byte comparison across the hop is not achievable and the FACTS are compared.
func _through_json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))
