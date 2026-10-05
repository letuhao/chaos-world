extends TestCase

## ## `tagged` — the lineage gate verb (ADR 0196, fate tag vocabulary)
##
## A fate tag is not a free label. It is a closed vocabulary of KINDS of deed
## (`FateDef.TAGS`) that ONE verb reads: `{verb: "tagged", id: "<tag>"}` is
## satisfied by holding ANY ONE fate carrying that tag.
##
## This suite exists because `tags` was for a long time authored, published into
## `summary()` and read by NOTHING — so the whole of its behaviour is "a gate can
## test it", and the failure modes are all ways that test could be wrong in a way
## no content author would notice:
##
##  - **AND instead of OR.** A gate that required every tagged fate would be
##    unopenable for a player who earned one of two, and the author would see
##    "unmet" forever.
##  - **`unmet` instead of `unknown_tag`.** A coined lineage is a content bug, not
##    something a player can go and earn; reporting it as `unmet` is a lie with no
##    cause.
##  - **`malformed` instead of "any tag satisfies this."** The default that makes a
##    half-written gate silently open is the most dangerous one here, because it
##    fails OPEN.
##  - **A bad tag nested in a composite degrading to `unmet`.** This is the miss
##    most likely to ship, because the leaf refuses correctly on its own and only
##    the PARENT loses the reason.
##
## Fixtures are built through `DestinyFixtureCatalog.install` exactly as
## `test_destiny_gate.gd` does, so this suite proves the verb's logic. The shipped
## tree is proved in `test_destiny_hub_contract.gd`, which uses the real catalog.

## Two fixture fates carrying the SAME tag, which is the only way the OR test can
## be wrong and still look right: a gate that quietly required both would refuse
## a player who earned either one.
const TAGGED := &"t_tagged_oath"
const TAGGED_TWIN := &"t_tagged_oath_twin"

## A fixture fate carrying a DIFFERENT lineage, and one carrying none at all —
## `empty tags` is legal (ADR 0196, fate tag vocabulary) and must not be read as a match for
## anything.
const OTHER := &"t_tagged_mercy"
const UNTAGGED := &"t_tagged_none"

## The one shape an unmet entry may have, matching what `test_destiny_gate.gd`
## pins: enough for a panel to render a reason it did not have to invent.
const UNMET_KEYS := ["kind", "id", "required", "actual", "label"]


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				_tagged_fate(TAGGED, [&"oath"]),
				_tagged_fate(TAGGED_TWIN, [&"oath", &"duel"]),
				_tagged_fate(OTHER, [&"mercy"]),
				_tagged_fate(UNTAGGED, []),
			],
			[]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


## A pure-narrative fixture fate carrying `tags`. No stat, so nothing about the
## verdict below can be a stat answering instead of the ledger.
func _tagged_fate(fate_id: StringName, tags: Array[StringName]) -> FateDef:
	var def := FateDef.new()
	def.id = fate_id
	def.display_name = String(fate_id)
	def.description = "A fixture fate used by the tagged gate suite."
	def.category = &"fixture"
	def.tier = 1
	def.visibility = FateDef.REVEALED
	def.tags = tags
	return def


func _hero() -> Actor:
	var actor := Actor.new(&"tagged_hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


func _verdict(actor: Actor, requirement: Dictionary) -> Dictionary:
	return DestinyApi.gate(actor, requirement)


func _entry(verdict: Dictionary, index: int = 0) -> Dictionary:
	var unmet := verdict["unmet"] as Array
	var entry = unmet[index] if index < unmet.size() else null
	if entry is Dictionary and not (entry as Dictionary).is_empty():
		return entry as Dictionary
	assert_eq(
		entry is Dictionary and not (entry as Dictionary).is_empty(),
		true,
		(
			"the verdict (%s) reports a readable unmet entry at %d, and has %d in total"
			% [String(verdict.get("reason", "")), index, unmet.size()]
		)
	)
	return {}


# --- OR across fates ------------------------------------------------------------


## ## The OR test, and the reason it needs TWO tagged fates
##
## Earn EITHER one, and the gate opens. The twin exists so that an
## implementation which ANDed the fates — the reading "this actor must carry the
## whole lineage" — fails here instead of passing on a single-tag catalog.
func test_a_tag_gate_opens_for_any_one_fate_carrying_the_tag() -> void:
	for earned in [TAGGED, TAGGED_TWIN]:
		var actor := _hero()
		DestinyApi.earn_fate(actor, earned, "combat")
		var verdict := _verdict(actor, {"verb": &"tagged", "id": "oath"})
		assert_eq(
			bool(verdict["ok"]),
			true,
			(
				(
					"holding '%s' alone opens a gate on the `oath` lineage, because `tagged` is OR "
					% earned
				)
				+ "across fates and not AND"
			)
		)
		assert_eq(verdict["unmet"] as Array, [], "and an open gate reports nothing")


## The mirror: the second fate carries a tag the first does not, and both must be
## separately askable. This is the half that proves the verb reads the catalog
## rather than a hardcoded id list.
func test_a_fate_answers_only_the_lineages_it_carries() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, TAGGED_TWIN, "combat")
	assert_eq(
		bool(_verdict(actor, {"verb": &"tagged", "id": "duel"})["ok"]),
		true,
		"a gate on the second tag of a twin opens too"
	)
	assert_eq(
		bool(_verdict(actor, {"verb": &"tagged", "id": "mercy"})["ok"]),
		false,
		"and a gate on a tag this fate does not carry stays shut"
	)
	# A fate with NO tags answers nothing, which is legal and is not a wildcard.
	var bare := _hero()
	DestinyApi.earn_fate(bare, UNTAGGED, "combat")
	for tag in ["oath", "duel", "mercy"]:
		assert_eq(
			bool(_verdict(bare, {"verb": &"tagged", "id": tag})["ok"]),
			false,
			"an empty `tags` answers no lineage question at all (asked '%s')" % tag
		)


# --- The unmet shape -------------------------------------------------------------


## The ordinary failure, and every field of it. `id` is THE TAG THE AUTHOR WROTE,
## matching the rule `unmet_prerequisites` states for aliases: the entry is
## rendered back to whoever wrote the requirement.
func test_a_tag_the_actor_does_not_carry_is_an_ordinary_five_key_unmet() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OTHER, "combat")
	var verdict := _verdict(actor, {"verb": &"tagged", "id": "oath"})
	assert_eq(bool(verdict["ok"]), false, "a lineage nobody carries is shut")
	assert_eq(String(verdict["reason"]), "unmet", "and it is an unmet, NOT a refusal")
	var entry := _entry(verdict)
	assert_eq(String(entry["kind"]), "tag", "the entry names the kind")
	assert_eq(String(entry["id"]), "oath", "and the tag the AUTHOR wrote")
	assert_eq(bool(entry["required"]), true, "it is required")
	assert_eq(bool(entry["actual"]), false, "and not carried")
	assert_eq(String(entry["label"]), "Requires a fate marked 'oath'", "with a renderable label")
	assert_eq(entry.keys().size(), UNMET_KEYS.size(), "and exactly the five keys a panel needs")
	for key in UNMET_KEYS:
		assert_eq(entry.has(key), true, "the entry carries '%s'" % key)


## A null actor holds nothing, so every tag gate is an ordinary unmet rather than
## a crash — the same null-safety every other verb already has.
func test_a_tag_gate_on_a_null_actor_is_unmet_not_an_error() -> void:
	var verdict := _verdict(null, {"verb": &"tagged", "id": "oath"})
	assert_eq(bool(verdict["ok"]), false, "no actor holds a lineage")
	assert_eq(String(verdict["reason"]), "unmet", "and it is an ordinary unmet")
	assert_eq((verdict["unmet"] as Array).size(), 1, "with something a panel can render")


# --- Adversarial: the refusals --------------------------------------------------


## ## A coined lineage REFUSES. It must never degrade to a plain unmet.
##
## Nothing in the tree can ever carry `not_a_tag`, so `unmet` would report a door
## that no amount of play opens — a permanent lie with no cause an author could
## act on. This is the same refusal `unknown_verb` gets, and it NAMES ITSELF.
func test_a_tag_outside_the_vocabulary_refuses_unknown_tag_and_names_itself() -> void:
	for tag in ["not_a_tag", "heavy", "first", "heaven", "OATH", "aggressive"]:
		var verdict := _verdict(_hero(), {"verb": &"tagged", "id": tag})
		assert_eq(bool(verdict["ok"]), false, "'%s' never opens a door" % tag)
		assert_eq(
			String(verdict["reason"]),
			"unknown_tag",
			"'%s' is refused as an unknown TAG, not reported as an unmet" % tag
		)
		var entry := _entry(verdict)
		assert_eq(String(entry["kind"]), "gate", "a refusal is about the gate itself")
		assert_eq(
			String(entry["label"]).contains(tag),
			true,
			"and the label names the tag it read ('%s')" % tag
		)


## ## `{verb:"tagged"}` with no `id` is MALFORMED, and the most important case here.
##
## The tempting default is "any tagged fate satisfies this" — and it fails OPEN,
## which is the one direction a gate may never fail. An author who typed the verb
## and forgot the id would get a gate that opens for anyone holding a single fate
## carrying any tag at all, and nothing in the content tree would look wrong.
func test_a_tagged_gate_naming_no_tag_refuses_rather_than_defaulting_open() -> void:
	for requirement in [
		{"verb": &"tagged"},
		{"verb": &"tagged", "id": ""},
		{"verb": &"tagged", "id": &""},
	]:
		var actor := _hero()
		# The actor holds TWO tagged fates, so a "any tag satisfies this" default
		# would open every case below and the assertion would catch it.
		DestinyApi.earn_fate(actor, TAGGED, "combat")
		DestinyApi.earn_fate(actor, TAGGED_TWIN, "combat")
		var verdict := _verdict(actor, requirement)
		assert_eq(
			bool(verdict["ok"]),
			false,
			"%s refuses closed even though the actor holds tagged fates" % [requirement]
		)
		assert_eq(
			String(verdict["reason"]),
			"malformed",
			"and %s is malformed, never an implicit 'any tagged fate'" % [requirement]
		)
		assert_ne(String(_entry(verdict)["label"]), "", "with a reason to render")


## A tag outside the vocabulary poisons its parent, for the same reason a malformed
## child does. Without this in `POISON_REASONS`, the leaf refuses correctly on its
## own and the composite silently degrades it to an unmet the moment it nests —
## which is the single most likely way this feature ships broken.
func test_a_malformed_or_unknown_tag_child_poisons_the_whole_composite() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, TAGGED, "combat")
	for child in [{"verb": &"tagged", "id": "not_a_tag"}, {"verb": &"tagged"}]:
		for outer in [&"all_of", &"any_of", &"none_of"]:
			var verdict := _verdict(
				actor, {"verb": outer, "of": [{"verb": &"tagged", "id": "oath"}, child]}
			)
			assert_eq(bool(verdict["ok"]), false, "a %s holding %s is shut" % [outer, child])
			assert_ne(
				String(verdict["reason"]),
				"unmet",
				(
					(
						"the %s CAUSE survives the nesting: %s must not degrade to an unmet, "
						% [String(verdict["reason"]), child]
					)
					+ "because an unmet names something the player could go and earn"
				)
			)
	# The exact row from the ADR, asserted as a whole rather than by loop.
	var all_of := _verdict(
		actor,
		{
			"verb": &"all_of",
			"of": [{"verb": &"tagged", "id": "oath"}, {"verb": &"tagged", "id": "not_a_tag"}],
		},
	)
	assert_eq(bool(all_of["ok"]), false, "the oath leaf is satisfied")
	assert_eq(String(all_of["reason"]), "unknown_tag", "and the bad sibling is the verdict")


## The nesting is not only one level down. A bad tag three composites deep still
## arrives as itself, because every level refuses for its own child rather than
## counting it.
func test_a_tag_leaf_still_names_itself_when_nested_to_any_depth() -> void:
	var actor := _hero()
	var deep := {
		"verb": &"all_of",
		"of":
		[
			{
				"verb": &"any_of",
				"of":
				[
					{"verb": &"all_of", "of": [{"verb": &"tagged", "id": "oath"}]},
					{"verb": &"tagged", "id": "mercy"},
				],
			},
			{"verb": &"tagged", "id": "not_a_tag"},
		],
	}
	var verdict := _verdict(actor, deep)
	assert_eq(bool(verdict["ok"]), false, "the deep bad tag shuts the whole tree")
	assert_eq(String(verdict["reason"]), "unknown_tag", "and it is still its own cause")


## ## A readable tag leaf inside a composite still reports its TAG ENTRY.
##
## The poison case above is about an unreadable leaf. This is the opposite: a
## leaf that is perfectly readable and simply unmet must contribute its
## `{kind:"tag", ...}` entry to the parent, so a panel rendering `all_of` can name
## the lineage rather than saying "unmet" and nothing.
func test_a_tagged_row_nested_in_any_of_or_none_of_still_reports_the_tag_leaf() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OTHER, "combat")

	var any_of := _verdict(
		actor,
		{
			"verb": &"any_of",
			"of": [{"verb": &"tagged", "id": "oath"}, {"verb": &"tagged", "id": "mercy"}],
		},
	)
	assert_eq(bool(any_of["ok"]), true, "one branch carries the tag, so any_of opens")
	assert_eq(any_of["unmet"] as Array, [], "and an open gate reports nothing")

	var none_of := _verdict(actor, {"verb": &"none_of", "of": [{"verb": &"tagged", "id": "oath"}]})
	assert_eq(bool(none_of["ok"]), true, "an unmet tag leaf satisfies none_of")

	# The case with something to read: both branches unmet under an `all_of`.
	var all_of := _verdict(
		actor,
		{
			"verb": &"all_of",
			"of": [{"verb": &"tagged", "id": "oath"}, {"verb": &"tagged", "id": "duel"}],
		},
	)
	assert_eq(bool(all_of["ok"]), false, "neither lineage is held")
	assert_eq((all_of["unmet"] as Array).size(), 2, "and both tag leaves are reported")
	var entry := _entry(all_of, 0)
	assert_eq(String(entry["kind"]), "tag", "as `tag` entries a panel can render")
	assert_eq(
		String(entry["label"]),
		"Requires a fate marked 'oath'",
		"naming the lineage the author wrote"
	)


# --- Earn-only: reading the gate takes nothing ----------------------------------


## ## A tag gate is MONOTONE and removes nothing.
##
## A fate is permanent (ADR 0065), so evaluating a gate over it must be a pure
## read. This compares the ledger byte-for-byte through
## `DestinyApi.state()` — which is the save payload — before and after, and also
## asserts the gate answers identically on both sides, so a gate that quietly
## consumed a tag would fail rather than merely leave the ledger alone.
func test_reading_a_tag_gate_leaves_the_ledger_byte_identical() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, TAGGED, "combat")
	DestinyApi.earn_fate(actor, OTHER, "story")
	DestinyApi.record(actor, &"oaths_sworn", 2)
	var before := DestinyApi.state(actor)
	assert_ne(DestinyApi.has_fate(actor, TAGGED), false, "the premise: a fate is really held")

	# Every shape of the verb, read repeatedly and in both directions.
	for requirement in [
		{"verb": &"tagged", "id": "oath"},
		{"verb": &"tagged", "id": "duel"},
		{"verb": &"tagged", "id": "mercy"},
		{"verb": &"tagged", "id": "not_a_tag"},
		{"verb": &"tagged"},
		{
			"verb": &"all_of",
			"of": [{"verb": &"tagged", "id": "oath"}, {"verb": &"tagged", "id": "mercy"}],
		},
	]:
		var first := _verdict(actor, requirement)
		var second := _verdict(actor, requirement)
		assert_eq(second, first, "reading %s twice is stable" % [requirement])
		assert_eq(
			DestinyApi.state(actor),
			before,
			"reading the gate %s wrote nothing to the ledger" % [requirement]
		)

	# And the held fates are all still held, in the same order and the same
	# entries — no tag was consumed, and no fate was rewritten.
	assert_eq(DestinyApi.state(actor)["fates"], before["fates"], "the fates are untouched")
	assert_eq(
		DestinyApi.has_fate(actor, TAGGED),
		true,
		"and the fate that answered the gate is still held afterwards"
	)
	assert_eq(
		bool(_verdict(actor, {"verb": &"tagged", "id": "oath"})["ok"]),
		true,
		"so the gate still opens: it consumed nothing"
	)


## The mirror of the previous case: the gate answers about the LEDGER, so a fate
## earned afterwards opens it and one that was never earned never does. If `tagged`
## were reading a stat or a trait it would not move with the earn.
func test_a_tag_gate_moves_only_with_the_ledger() -> void:
	var actor := _hero()
	var before := _verdict(actor, {"verb": &"tagged", "id": "oath"})
	assert_eq(bool(before["ok"]), false, "nothing is held yet")
	DestinyApi.earn_fate(actor, TAGGED_TWIN, "combat")
	var after := _verdict(actor, {"verb": &"tagged", "id": "oath"})
	assert_eq(bool(after["ok"]), true, "earning a tagged fate opens it, with no re-attach")
	assert_eq(
		after["unmet"] as Array,
		[],
		"and an open gate reports nothing, so a panel has no stale row to render"
	)


# --- The published summary ------------------------------------------------------


## ## A HIDDEN fate's tags are a spoiler once a `tagged` gate exists.
##
## `the_third_man_spared` is `visibility: hidden` and carries `[mercy, duel]`.
## While nothing read `tags` that was harmless. Now a gate can display "you need a
## duel-marked fate", and any codex row publishing an unheld hidden fate's tags
## hands a player the existence of a fate they never earned. So `_fate_view`
## publishes `[]` for an unheld hidden fate and the real tags once it is held.
##
## This is a published-key contract change, asserted on both halves: a leak and an
## omission are opposite answers to one assertion, so a helper that reported "no
## view" as a failure could not prove it (the same reasoning
## `test_destiny_hub_contract.gd` states about its teaser case).
func test_an_unheld_hidden_fate_publishes_no_tags_and_a_held_one_does() -> void:
	# A HIDDEN fixture fate, declared here rather than reached through the shipped
	# tree so the premise is the fixture's own.
	var hidden := FateDef.new()
	hidden.id = &"t_hidden_tagged"
	hidden.display_name = "Never Named"
	hidden.description = "A hidden fixture fate."
	hidden.category = &"fixture"
	hidden.tier = 1
	hidden.visibility = FateDef.HIDDEN
	hidden.teaser = "Something happened once."
	hidden.tags = [&"duel"]
	DestinyFixtureCatalog.install([hidden], [])

	var actor := _hero()
	var locked := DestinyApi.summary(actor)["fates"] as Dictionary
	assert_eq(locked.has("t_hidden_tagged"), true, "a hidden fate IS listed in the codex")
	var before := locked["t_hidden_tagged"] as Dictionary
	assert_eq(String(before["display_name"]), "", "but it is unnamed before it is earned")
	assert_eq(
		before["tags"],
		[] as Array,
		(
			"and it publishes NO tags: a `tagged` gate can name any of the seven lineages, so a "
			+ "published tag list tells a player which hidden fates exist"
		)
	)

	DestinyApi.earn_fate(actor, &"t_hidden_tagged", "story")
	var held_view: Dictionary = (
		(DestinyApi.summary(actor)["fates"] as Dictionary)["t_hidden_tagged"] as Dictionary
	)
	assert_eq(bool(held_view["held"]), true, "the fate is held now")
	assert_eq(
		held_view["tags"],
		["duel"] as Array,
		"and its real tags are published, because holding it revealed it"
	)


## A REVEALED fate publishes its tags whether or not it is held — the gate above is
## specific to `hidden`, and a codex that lost every tag on every locked fate would
## be a different and equally wrong answer.
func test_a_revealed_fate_publishes_its_tags_before_it_is_earned() -> void:
	var actor := _hero()
	var view: Dictionary = (
		(DestinyApi.summary(actor)["fates"] as Dictionary)[String(TAGGED_TWIN)] as Dictionary
	)
	assert_eq(bool(view["held"]), false, "the premise: nothing is earned yet")
	assert_eq(
		view["tags"],
		["oath", "duel"] as Array,
		"a revealed fate publishes its tags even while locked"
	)


# --- The vocabulary itself -------------------------------------------------------


## ## The vocabulary is CLOSED, and the shipped fixtures stay inside it.
##
## `FateDef.TAGS` is the whole vocabulary. An implementation that discovered tags
## by scanning what content happened to author would pass every behavioural case
## above and fail only here — which is the point: the closure is the property that
## makes `unknown_tag` a meaningful refusal rather than a coin flip.
func test_the_vocabulary_is_exactly_the_seven_named_lineages() -> void:
	assert_eq(
		FateDef.TAGS,
		(
			[
				&"oath",
				&"blood",
				&"mercy",
				&"severance",
				&"desertion",
				&"rebirth",
				&"duel",
			]
			as Array[StringName]
		),
		"the lineage vocabulary is exactly these seven, in this order"
	)
	# No duplicates: a duplicated entry would make `TAGS.size()` a lie about how
	# many lineages exist.
	var seen: Array[StringName] = []
	for tag in FateDef.TAGS:
		assert_eq(seen.has(tag), false, "'%s' appears once" % tag)
		seen.append(tag)


## Every tag the shipped tree authors is inside the vocabulary. Asserted over the
## REAL catalog rather than the fixture, because the eleven `.tres` files are where
## a coined lineage would actually arrive — and a `.tres` carrying `heavy` would
## otherwise make every `{verb:"tagged", id:"heavy"}` gate in content a permanent
## lie.
func test_every_shipped_fate_tag_is_inside_the_vocabulary() -> void:
	var catalog := FateCatalog.instance()
	assert_ne(catalog, null, "the real catalog is reachable")
	var tagged := 0
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		for tag in def.tags:
			tagged += 1
			assert_eq(
				FateDef.TAGS.has(tag),
				true,
				(
					(
						"shipped fate '%s' declares tag '%s', which is not in FateDef.TAGS — drop it or "
						% [fate_id, tag]
					)
					+ "add it to the vocabulary in the same change (ADR 0196, fate tag vocabulary)"
				)
			)
	# The premise, not a nicety: a scan of an empty catalog passes vacuously, and
	# this suite's only content assertion is that shipped tags are in vocabulary.
	assert_eq(tagged > 0, true, "the shipped tree declares tags at all (so this is not vacuous)")
