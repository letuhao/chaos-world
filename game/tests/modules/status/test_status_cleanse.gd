extends TestCase

## ADR 0107's deferred verb, and the trigger that FIRED.
##
## The ADR refused to build `StatusApi.cleanse` until an authored CONSUMABLE named a
## mitigation lever, and restated that as a greppable predicate: a `.tres` under
## `game/data/items` carrying `subcategory = "pill"` AND a non-empty `cleanse_lever`
## whose id is a member of `StatusDef.LEVERS`. The census behind the deferral found 237
## pills and 0 of them carrying a lever. `cleansing_jade_pill.tres` is the first, so the
## verb exists in the same change that authored it — which is the ordering the ADR named.
##
## ## Why the tests are a LEVER and not a population
##
## ADR 0107 asked for exactly this shape: a status tagged `pill` is removed by
## `cleanse(actor, &"pill")`, one tagged only `gear` is NOT, and a cleanse naming an
## unknown lever changes nothing and says so. A population test would prove the same
## thing about whatever twenty defs ship today and would stop proving it the moment a
## designer retagged one. So the tests below drive the verbs, and the ONE content
## assertion is that the trigger predicate is still true over the shipped corpus.

const CLEANSE_PILL := "res://data/items/consumable/cleansing_jade_pill.tres"

var _actor: Actor


func setup() -> void:
	_actor = ActorFactory.build(&"cleanse_probe")


# --- the trigger predicate ADR 0107 made checkable -----------------------------


func test_the_authored_pill_that_fired_the_trigger_still_names_a_lever() -> void:
	# The deferral's own predicate, run against the corpus. If a designer renames the
	# field, empties it, or retypes the pill, the verb loses its only production caller
	# and this fails — which is the guard ADR 0107 asked for and did not have.
	var def := load(CLEANSE_PILL) as ItemDef
	assert_ne(def, null, "the pill that fired ADR 0107's trigger still exists")
	assert_eq(String(def.subcategory), "pill", "and it is still a pill")
	assert_eq(
		def.cleanse_lever != &"",
		true,
		"and it still names a lever, so the verb has a production caller"
	)
	assert_eq(
		StatusDef.LEVERS.has(def.cleanse_lever),
		true,
		"and that lever is a member of the closed vocabulary"
	)


# --- the verb: a lever, not a percentage ---------------------------------------


func test_a_status_tagged_pill_is_removed_by_cleanse_on_pill() -> void:
	# `metal_sever` authors `[affinity, technique, pill]`, so the pill lever answers it.
	StatusApi.apply(_actor, &"metal_sever", 1.0)
	assert_eq(_actor.has_status(&"metal_sever"), true, "the bleed landed")
	var result := StatusApi.cleanse(_actor, &"pill")
	assert_eq(bool(result["ok"]), true, "the cleanse is ok")
	assert_eq(result["cleared"].has("metal_sever"), true, "and it names the status it removed")
	assert_eq(_actor.has_status(&"metal_sever"), false, "which is gone from the actor")


func test_a_status_tagged_only_gear_is_not_removed_by_cleanse_on_pill() -> void:
	# The boundary half, and the one a percentage implementation would fail: a pill
	# does not remove a status that did not publish `pill` as its counterplay.
	# `fire_pyre` authors `[affinity, technique]` — no `pill`.
	StatusApi.apply(_actor, &"fire_pyre", 1.0)
	assert_eq(_actor.has_status(&"fire_pyre"), true, "the amplifier landed")
	var result := StatusApi.cleanse(_actor, &"pill")
	assert_eq(bool(result["ok"]), true, "the cleanse itself is ok")
	assert_eq(int(result["count"]), 0, "and it removed nothing")
	assert_eq(
		_actor.has_status(&"fire_pyre"),
		true,
		"so a status that published no pill counterplay is untouched"
	)


func test_one_cleanse_removes_every_status_that_names_the_lever() -> void:
	# `cleanse` is a SWEEP over the authored tag set, not a single-id removal: a pill
	# that answered one poison but left the three others it also answers would be a
	# weaker item than its own `mitigation_tags` promise. Both halves of the vocabulary
	# are exercised: three `pill`-tagged and one `gear`-tagged.
	for id in [&"metal_sever", &"ice_rime", &"fire_immolation"]:
		StatusApi.apply(_actor, id, 1.0)
	StatusApi.apply(_actor, &"fire_pyre", 1.0)
	var result := StatusApi.cleanse(_actor, &"pill")
	assert_eq(int(result["count"]), 3, "three statuses published the pill lever")
	for id in [&"metal_sever", &"ice_rime", &"fire_immolation"]:
		assert_eq(_actor.has_status(id), false, "%s is gone" % String(id))
	assert_eq(
		_actor.has_status(&"fire_pyre"), true, "and the one that did not publish it is untouched"
	)


# --- refusals are named --------------------------------------------------------


func test_an_unknown_lever_is_refused_and_says_so() -> void:
	# The refusal half ADR 0107 asked for by name: a cleanse naming a lever this game
	# does not have changes nothing AND says so. A silent no-op here is the defect.
	StatusApi.apply(_actor, &"metal_sever", 1.0)
	var result := StatusApi.cleanse(_actor, &"luck")
	assert_eq(bool(result["ok"]), false, "a lever outside the closed set is refused")
	assert_eq(
		String(result["reason"]), "unknown_lever", "with the module's own named-reason vocabulary"
	)
	assert_eq(
		_actor.has_status(&"metal_sever"), true, "and nothing was removed on the way to the refusal"
	)


func test_cleanse_without_an_actor_is_refused() -> void:
	var result := StatusApi.cleanse(null, &"pill")
	assert_eq(bool(result["ok"]), false, "no actor is refused")
	assert_eq(String(result["reason"]), "no_actor", "with the same reason `apply` uses")


# --- the modifiers come off -----------------------------------------------------


func test_cleanse_releases_the_modifiers_the_status_was_holding() -> void:
	# The half that makes a purge a purge rather than a rename: if the modifier stayed,
	# the debuff would keep costing the player with nothing left to look at. ADR 0107
	# required the modifiers released "exactly as clear_combat_scope does".
	StatusApi.apply(_actor, &"metal_sever", 1.0)
	var held := _actor.stats.modifier_count()
	assert_eq(held > 0, true, "the applied status is holding modifiers")
	StatusApi.cleanse(_actor, &"pill")
	assert_eq(_actor.stats.modifier_count(), 0, "and the cleanse released every one of them")


# --- the pill is a real in-fight answer, not just a .tres -----------------------


func test_spending_the_authored_pill_actually_cleanses_through_the_production_verb() -> void:
	# The predicate being TRUE is necessary and not sufficient. This drives the real
	# player path -- `ItemUse.apply`, the verb `ItemsApi.use_item` calls -- and proves
	# the authored lever reaches `StatusApi.cleanse` and removes a live debuff. Without
	# this, a pill carrying a lever field would satisfy ADR 0107's greppable trigger
	# while doing nothing in a fight, which is the exact "authored counterplay the game
	# cannot deliver" failure the whole deferral was about.
	var def := load(CLEANSE_PILL) as ItemDef
	var instance := ItemsApi.generate(_actor, def, 20261004)
	StatusApi.apply(_actor, &"metal_sever", 1.0)
	assert_eq(_actor.has_status(&"metal_sever"), true, "the bleed landed")
	var used := ItemUse.apply(_actor, def, instance)
	assert_eq(bool(used["ok"]), true, "spending the pill is ok")
	assert_eq(
		int((used["cleansed"] as Dictionary)["count"]), 1, "and it reported the cleanse that landed"
	)
	assert_eq(
		_actor.has_status(&"metal_sever"),
		false,
		"so the player has an in-fight answer to a debuff for the first time"
	)


func test_spending_the_pill_on_an_unafflicted_actor_is_refused_not_silently_ok() -> void:
	# BL-0110's rule applied to the new channel: spending a pill that removed nothing
	# decrements the stack and leaves the actor identical, so it must NOT report `ok`.
	var def := load(CLEANSE_PILL) as ItemDef
	var instance := ItemsApi.generate(_actor, def, 20261005)
	var used := ItemUse.apply(_actor, def, instance)
	assert_eq(bool(used["ok"]), false, "a pill with nothing to cleanse does not report success")
	assert_eq(String(used["reason"]), ItemUse.REASON_NO_EFFECT, "it names the same reason")
	assert_eq(
		int((used["cleansed"] as Dictionary)["count"]),
		0,
		"and reports the empty cleanse so a caller can tell why"
	)


func test_the_two_purges_stay_two_verbs() -> void:
	# ADR 0107's sharpest line: `clear_combat_scope` is a combat-lifecycle fact and
	# `cleanse` is a player action. If a cleanse could reach a COMBAT status's scope
	# question, or combat exit could answer a lever, the two would have been conflated.
	# Both halves are asserted: combat exit removes COMBAT scope regardless of tags,
	# and a cleanse removes by tag regardless of scope.
	StatusApi.apply(_actor, &"fire_pyre", 1.0)  # COMBAT, tags [affinity, technique]
	StatusApi.apply(_actor, &"wood_bloom", 1.0)  # CULTIVATION, tags [..., pill]
	var cleansed := StatusApi.cleanse(_actor, &"pill")
	assert_eq(
		_actor.has_status(&"wood_bloom"),
		false,
		"a cleanse removes by TAG even when the status is CULTIVATION scope"
	)
	var cleared := StatusApi.clear_combat_scope(_actor)
	assert_eq(
		cleared.has("fire_pyre"),
		true,
		"and combat exit still removes by SCOPE even when no pill answers it"
	)
