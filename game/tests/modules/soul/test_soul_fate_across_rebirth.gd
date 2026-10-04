extends TestCase

## ADR 0181: "Fate belongs to the soul. A rebirth carries the entire destiny ledger — fates,
## destinies, counters and history — onto the new body, and re-derives every projection from
## it. Nothing is reset, nothing is re-earned, and nothing is copied by hand."
##
## ## The claim, and why it needed its own file rather than another case in
## `test_soul_death_world_fact`
##
## The world fact ledger already rides the body swap (`SoulDeath._carry_facts`), and that suite
## proves it. The FATE ledger — the derived copy of those same facts — did not, so after one death
## `WorldFact.count(body, "duels_won")` read 3 while `DestinyApi.state(body)["counters"]
## ["duels_won"]` read 0, permanently, because the only verb that has ever moved a counter is
## monotone and there is no re-derive. A case bolted onto the world-fact suite would have shared
## its harness and hidden which of the two carries was under test; this file names the claim and
## asserts it in one invariant plus four guards, each of which is RED without `_carry_destiny`.
##
## ## Why the bridge is installed here by hand
##
## A counter only moves through `WorldFact.record` firing `DestinyProjection.on_fact_recorded`,
## and that subscription is installed by the composition root (`item_workbench_app.gd`). A test
## that skipped it would earn nothing and assert `0 == 0` — the exact shape DEF-0121 took. So
## `setup()` installs it through the module's own verb, ASSERTS the install is live, and
## `teardown()` removes it again by identity: the runner shares one process, and a subscriber left
## behind moves counters for every later suite in the run.
##
## ## Assertion style
##
## `assert_eq` / `assert_ne` / `assert_almost_eq`, each with a label; a boolean asserts against its
## own negation so a failure prints the value rather than "expected true".

const DUELS := &"duels_won"
## The authored origin whose `grants_fates` carry stat modifiers, so guard 2 has something to
## project. Read from the shipped catalog in the body rather than restated, so a content rename
## fails this suite by name instead of silently emptying it.
const CARRYING_ORIGIN := &"the_one_who_returned"

var _actor: Actor
var _soul_store: SoulWorldLedger
var _death: SoulDeath
var _minted: Array = []
## The body that fell, kept so a guard can read what the ledger held BEFORE the swap rather than
## inferring it from what survived.
var _fallen: Actor
## How many `WorldFact` subscribers this suite found. A DELTA is observable here, a zero is not:
## a sibling suite may legitimately hold one of its own.
var _baseline_subscribers: int = 0


func setup() -> void:
	_soul_store = SoulWorldLedger.new()
	SoulApi.set_store(_soul_store)
	_minted.clear()
	_fallen = null
	_baseline_subscribers = WorldFact.subscriber_count()
	# The real bridge, installed the way the composition root installs it and for the reason
	# `item_workbench_app.gd` installs it: a subscriber installed after the first `record` has
	# already missed that occurrence, and the ledger is monotone, so there is no going back.
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		(
			"the fact->counter bridge is LIVE: every counter below is read through it, so a false "
			+ "here names the wiring rather than a zero"
		)
	)
	_actor = _hero(&"fate_bearer")
	DifficultyApi.attach(_actor)
	SoulApi.attach(_actor)
	_death = SoulDeath.new(_mint, _adopt)


## Leave the process exactly as this suite found it. Only the bridge THIS suite installed is
## removed, by identity — never by asserting a count of zero, which a sibling suite's legitimate
## subscriber would break.
func teardown() -> void:
	DestinyProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		WorldFact.subscriber_count(),
		_baseline_subscribers,
		"the bridge is REMOVED again and the subscriber slot is back to what this test found"
	)
	for born in _minted:
		(born as Actor).resources.clear()
	_minted.clear()
	_actor = null
	_fallen = null
	_soul_store = null
	SoulApi.set_store(null)


# --- 1. THE INVARIANT: the two ledgers agree on the new body ------------------


func test_a_counter_and_the_fact_behind_it_are_both_three_on_the_reborn_body() -> void:
	# The whole decision in one case. `duels_won` is recorded through the REAL bridge, not by
	# writing the destiny ledger by hand, because a hand-written ledger would not prove that the
	# number in `counters` and the number in `world_facts` are the same occurrence seen twice.
	WorldFact.record(_actor, DUELS, 3)
	assert_eq(_counter(_actor, DUELS), 3, "the counter moved with the fact, through the bridge")
	assert_eq(WorldFact.count(_actor, DUELS), 3, "and the world agrees")
	# And the promise the ADR makes to a consumer, stated before the swap: for every row of
	# `COUNTER_FACTS` the counter is at least the fact. Asserted once on the first body so a
	# red here names the bridge rather than the carry.
	var ledger := DestinyApi.state(_actor)
	var counters: Dictionary = ledger["counters"] as Dictionary
	for row in DestinyProjection.COUNTER_FACTS:
		var fact_id := StringName(row.get("fact", &""))
		var held := int(counters.get(String(DestinyProjection.counter_for_fact(fact_id)), 0))
		assert_eq(held, WorldFact.count(_actor, fact_id), "counter %s matches its fact" % fact_id)
	var fallen := _die()
	assert_eq(
		_fallen.id,
		fallen.id,
		"the body that fell is kept by name, so both sides of the swap are readable"
	)
	assert_ne(
		_actor.id,
		fallen.id,
		"and the actor under test really is the re-embodied body, not the one in the grave"
	)
	assert_eq(
		_counter(_actor, DUELS),
		3,
		(
			"THE CASE THAT IS RED WITHOUT THE CARRY: the counter reads 0 on the new body. A fate "
			+ "counter is a DERIVATION of the fact ledger and the only verb that moves one is "
			+ "monotone, so nothing can ever put the 3 back"
		)
	)
	assert_eq(
		WorldFact.count(_actor, DUELS),
		3,
		"and the world fact ledger already carried it, which is what made the two disagree"
	)


# --- 2. THE PROJECTION IS REBUILT, NOT COPIED --------------------------------


func test_fate_and_destiny_cross_and_their_projection_is_rebuilt_on_the_new_body() -> void:
	# Earn through the REAL creation path — `CharacterCreationFlow.build` /
	# `grant_origin` — so the ledger under test is the one a player earns rather than a
	# dictionary this file wrote.
	var flow := CharacterCreationFlow.new()
	var hero := _arriving_hero(CARRYING_ORIGIN, flow)
	var fates_before := DestinyApi.fates(hero)
	var destinies_before := DestinyApi.destinies(hero)
	assert_ne(fates_before.is_empty(), true, "the origin granted fates")
	assert_ne(destinies_before.is_empty(), true, "and a destiny")
	var modifiers_before := DestinyProjection.modifier_count(hero)
	assert_ne(
		modifiers_before,
		0,
		(
			"and at least one of those fates carries a stat modifier, read off the shipped `.tres` "
			+ "rather than asserted from this file: a modifier count of 0 would make the whole "
			+ "guard vacuous"
		)
	)
	_actor = hero
	_die()
	assert_eq(DestinyApi.fates(_actor), fates_before, "every fate crossed the death")
	assert_eq(DestinyApi.destinies(_actor), destinies_before, "and every destiny with it")
	# THE OTHER HALF, and the reason this is one test rather than two: a carry that copied the
	# rows without letting `attach` re-project would satisfy the two lines above and fail here.
	# The numbers would be in the ledger and missing from the stat stack, and nothing else in
	# the repo can see that shape.
	assert_eq(
		DestinyProjection.modifier_count(_actor),
		modifiers_before,
		(
			"the modifiers are on the new body's OWN stat stack. `DestinyProjection.apply` strips "
			+ "before it rebuilds, so a carried fate is applied once per body, never twice"
		)
	)
	assert_eq(
		DestinyApi.state(_actor)["counters"] as Dictionary,
		{},
		"this earn path moves no counter, so a carried one here would be a copy bug, not a gain"
	)


# --- 3. THE EARN-ONLY INVARIANT IS STILL ONE-WAY -----------------------------


func test_the_normalized_ledger_is_byte_equal_across_the_swap_and_a_second_death_lowers_nothing(
) -> void:
	# ADR 0065: nothing the game does takes a fate back. A carry is not a removal — it ADDS rows
	# to the new body's ledger — so the whole normalized ledger must be identical on both sides
	# of the swap and identical again after the next death.
	WorldFact.record(_actor, DUELS, 2)
	DestinyApi.earn_fate(_actor, &"first_blood_duel", "combat")
	var held := DestinyApi.state(_actor)
	_die()
	assert_eq(
		DestinyApi.state(_actor),
		held,
		"the new body's normalized ledger is the falling body's, row for row"
	)
	_die()
	assert_eq(
		DestinyApi.state(_actor),
		held,
		"a second death lowers no counter and drops no entry: the ledger is only ever a copy"
	)
	assert_eq(
		_world_fact_ledger(),
		{
			"duels_won": 2,
			"soul_died": 2,
		},
		(
			"and the fact ledger under it is the same: two duels survived both swaps, and the two "
			+ "deaths stacked rather than restarting. A SUM would read 4 duels for 2. Compared as "
			+ "a WHOLE `{id: count}` map rather than one id at a time, because that is the shape "
			+ "a merge corrupts — and it is a dictionary the CARRIED ledger was measured from, "
			+ "never one this file wrote"
		)
	)


# --- 4. AN ARRIVAL STILL GRANTS NOTHING --------------------------------------


func test_a_rebirth_grants_no_origin_destiny_the_first_body_did_not_earn() -> void:
	# ADR 0159 and ADR 0065, held through the change: an arrival is a RECEIPT recorded in
	# `SoulState.origins`, not a claim in the `origin` exclusivity group. The held set after the
	# swap must be EXACTLY the held set before it — nothing granted, nothing lost.
	var flow := CharacterCreationFlow.new()
	var hero := _arriving_hero(CARRYING_ORIGIN, flow)
	var held_before := DestinyApi.destinies(hero)
	_actor = hero
	var owed := String(SoulApi.next_arrival(_actor))
	assert_ne(owed, "", "the gate owes an arrival for the death under test")
	var minted := CharacterCreationFlow.build_forced(StringName(owed), 1)
	assert_eq(bool(minted.get("ok", false)), true, "and the arrival mints a real body")
	var orphan: Actor = minted["actor"] as Actor
	_minted.append(orphan)
	assert_eq(
		DestinyApi.destinies(orphan),
		[],
		(
			"a minted rebirth body holds NOTHING before the carry — which is why the carry has to "
			+ "happen at all, and why `build_forced`'s empty ledger is true of the MINT only"
		)
	)
	var origins := flow.origin_ids()
	assert_ne(origins.is_empty(), true, "the content ships origin-group destinies to compare")
	var granted := 0
	for origin_id in origins:
		if DestinyApi.has_destiny(_actor, origin_id):
			granted += 1
	_die()
	var held_after := DestinyApi.destinies(_actor)
	assert_eq(held_after, held_before, "the new body's held set is exactly the old body's")
	assert_eq(
		granted,
		1,
		(
			"and exactly one `origin`-group destiny is held: the one the first body earned, so the "
			+ "exclusivity set did not grow and no picker was handed to the player"
		)
	)
	for origin_id in origins:
		if held_before.has(origin_id):
			continue
		assert_eq(
			DestinyApi.has_destiny(_actor, origin_id),
			false,
			"the rebirth granted no other origin: %s" % String(origin_id)
		)


# --- 5. NO soul -> destiny EDGE ------------------------------------------------


func test_soul_declares_no_destiny_dependency_and_the_carry_lives_in_app() -> void:
	# ADR 0127's refusal, kept honest by the way this decision took it: `soul/api.gd` says the
	# edge "becomes legal only when the soul carries the whole destiny ledger, which is a
	# separate decision". ADR 0181 took that decision and took it the OTHER way — by doing the
	# carry in `app/`, which `LAYER_DEPS["app"] == {"*"}` exempts — so `soul` must still declare
	# exactly `contracts`, `core` and `items`. A second place to remember a fate is precisely
	# what ADR 0065 refuses.
	var declared := _declared_deps(&"soul")
	# Compared as `Array[StringName]` against `Array[StringName]`, not as strings: a GDScript
	# typed array does not compare equal to a differently-typed one even element for element, so
	# the expected side is built by the same helper that built the actual side rather than
	# written as a literal. That is also why [method _declared_deps] returns what it returns.
	assert_eq(
		declared,
		_names(["contracts", "core", "items"]),
		"soul declares contracts, core and items — no destiny, and no edge invented by this change"
	)
	assert_eq(
		_declared_deps(&"destiny").has("soul"),
		false,
		"and destiny declares no back edge to the module that may not know it exists"
	)
	var soul_tree := ""
	for path in [
		"res://src/modules/soul/api.gd",
		"res://src/modules/soul/soul_state.gd",
		"res://src/modules/soul/soul_gate.gd",
		"res://src/modules/soul/soul_def.gd",
		"res://src/modules/soul/soul_catalog.gd",
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s was read, so a missing file cannot pass this" % path)
		soul_tree += _code_only(text)
	assert_eq(
		soul_tree.contains("DestinyApi") or soul_tree.contains("DestinyState"),
		false,
		(
			"no CODE under soul/ names destiny at all. `tools arch` cannot see a bare reference "
			+ "from modules/* — `BARE_REF_UNITS` excludes them — so the registry alone is not the "
			+ "guard, and the source is. Comments are stripped FIRST: the soul ledger's own prose "
			+ "cites `DestinyState.normalize` and `DestinyApi.record` as precedent, which is a "
			+ "cross-reference a reader follows, never an edge the compiler resolves"
		)
	)
	var death := FileAccess.get_file_as_string("res://src/app/soul_death.gd")
	assert_eq(
		death.contains("_carry_destiny("), true, "the carry is performed in app/, not in soul/"
	)
	assert_eq(
		death.contains("func _carry_destiny"),
		true,
		"which is why `app/` is the layer that owns it: it is the one that may depend on anything"
	)


# --- Internals ---------------------------------------------------------------


## Kill the body that stands and resolve it, exactly as the frame driver does, keeping a
## reference to the one that FELL so a case can read both sides of the swap.
func _die() -> Actor:
	_fallen = _actor
	var pool := _actor.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	_death.resolve(_actor)
	return _fallen


## The composition root's mint callback, through the real arrival table.
func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built


## The composition root's adopt callback, and the half of the production path this suite has to
## reproduce by hand: `_attach_body_modules` runs `DestinyApi.attach(actor)` on every body it
## adopts (fresh, restore and rebirth alike), and that call is what normalizes the carried ledger
## and re-derives the projection from it. Guard 2 asserts the outcome of THAT call, so it has to
## be here — an adopt that skipped it would leave a ledger whose numbers were never projected, and
## the suite would be measuring its own stub rather than the rule.
func _adopt(body: Actor) -> void:
	if body == null:
		return
	DestinyApi.attach(body)
	_actor = body


## A hero built through the REAL creation commit, so the ledger under test is the one a player
## earns. `CharacterCreationFlow` attaches `destiny` itself, and `build` earns the origin through
## the facade exactly as the creation screen does. The caller's own flow is passed in because
## `build` refuses `already_created` on a second call — a suite that minted one flow per hero
## could not say anything about which of them was the player's.
func _arriving_hero(choice_id: StringName, flow: CharacterCreationFlow) -> Actor:
	var built := flow.build(choice_id)
	assert_eq(
		bool(built.get("ok", false)),
		true,
		"the creation commit is open for %s: %s" % [choice_id, built.get("reason", "")]
	)
	var hero: Actor = built["actor"] as Actor
	_minted.append(hero)
	SoulApi.attach(hero)
	DifficultyApi.attach(hero)
	return hero


## An actor with a body plan and core pools, built without the composition root. Tracked so
## `teardown` can release its pools.
func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	_minted.append(body)
	return body


## `values` as the `Array[StringName]` [method _declared_deps] answers in, so an expected side is
## never a differently-typed literal. Typed explicitly: `:=` on a `Variant` is a
## warning-as-error in this project.
func _names(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in values:
		out.append(StringName(value))
	return out


## A GDScript source with every comment line removed, so a cross-reference in prose cannot be
## mistaken for a reference the compiler resolves.
##
## `##` documents a declaration and `#` comments a line out; both are stripped whole-line, and a
## `#` inside a string literal is left alone because this only ever drops lines whose first
## non-whitespace character is a `#`. That is coarser than a real tokenizer and deliberately so:
## the guard below asks whether a NAME appears in code at all, and a line that opens with a hash
## is a comment in every case this file reads.
func _code_only(text: String) -> String:
	var out: PackedStringArray = []
	for line in text.split("\n"):
		var trimmed := String(line).strip_edges()
		if trimmed.begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


## One counter, read off the ledger `DestinyApi.state` publishes rather than off a facade verb.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


## The world fact ledger on the body that stands, as plain `{id: count}` — the payload a save
## carries, so a case can compare WHOLE ledgers rather than one id at a time. A SUM would double
## every row here, which is the failure a merge instead of a move produces.
func _world_fact_ledger() -> Dictionary:
	var out := {}
	var rows: Dictionary = WorldFact.normalize(_actor).get("facts", {}) as Dictionary
	for fact_id in rows.keys():
		var row = rows[fact_id]
		if row is Dictionary and int((row as Dictionary).get("count", 0)) > 0:
			out[String(fact_id)] = int((row as Dictionary).get("count", 0))
	return out


## `tools/arch/registry.json`'s declared deps for `module_name`, read from disk.
##
## That file is OUTSIDE `res://` and is reached by GLOBALIZING `res://..` — a `res://../tools/…`
## resource path resolves to nothing, and `FileAccess` answers an empty string for a missing file
## with no error, so a naive read asserts that its own failure. `res://..` must be simplified
## before it reaches any path comparison, which is the rule `tests/arch_rules` states by name.
## Empty when the registry cannot be read, so a suite that cannot see it fails the edge assertion
## above rather than passing on an empty set.
func _declared_deps(module_name: StringName) -> Array:
	var root := ProjectSettings.globalize_path("res://..").replace("\\", "/")
	var path := root.simplify_path().path_join("tools/arch/registry.json")
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return []
	var modules: Variant = (parsed as Dictionary).get("modules", {})
	if not (modules is Dictionary):
		return []
	var entry: Variant = (modules as Dictionary).get(String(module_name), {})
	if not (entry is Dictionary):
		return []
	var out: Array = []
	for dep in (entry as Dictionary).get("deps", []) as Array:
		out.append(StringName(dep))
	return out
