extends TestCase

## ## Reachability over the SHIPPED content graph — the guard for DEF-0181/0182
##
## Two authored quests shipped permanently unopenable and nothing noticed:
##
##   - `the_severed_calling` was gated on `has_destiny the_severed` AND
##     `has_fate oath_breaker`, then PAID `bound_name_called_once` — which
##     `the_severed` itself required. Quest → fate → destiny → quest, no entry.
##   - `the_returned_instrument` was gated on `has_destiny the_one_who_returned`,
##     which no authored `grants`/`pay` row named.
##
## Every other suite in this module installs `DestinyFixtureCatalog` and gates on
## `t_`-prefixed ids it builds in code. That is right for proving LOGIC and it is
## exactly why a broken authored `.tres` is invisible to all of them: a fixture
## catalog is a different universe from `res://data/`. `test_quest_content.gd`
## walks the shipped ids but never runs a hero through them.
##
## ## What this suite does
##
## It builds the grant/gate graph from the SHIPPED `.tres` trees and proves every
## authored fate and destiny is reachable from a fresh actor through real content.
## It is a STATIC analysis of authored content: nothing is ever earned here. The
## graph is walked to its fixpoint and the result compared against the catalog.
##
## ## Why the fixpoint, and not "does this quest open?"
##
## `DestinyApi.gate` answers ONE requirement against ONE ledger. A quest can pass
## its own gate and still be unobtainable, because the fate or destiny its gate
## names may itself have no earn path. So the walk starts from a hero who has
## earned nothing and repeatedly applies whichever authored rule is satisfiable
## RIGHT NOW — pay out an open quest, resolve an openable event, earn an unblocked
## destiny. Every pass only grows the held set, so it terminates at the set a
## player could actually accumulate. Anything the catalog ships that the fixpoint
## does not contain is unreachable, and that is the assertion.
##
## ## What is deliberately NOT modelled, and why
##
## **World facts.** A step's fact is written by the system that owns the moment
## (ADR 0113), not by destiny content, and `tools gate_reach check` is the census
## that judges fact supply. Answering `fact` false here would report every shipped
## quest and say nothing about destiny.
##
## **Counters.** `{verb: counter}` reads `DestinyState`, whose producers are
## DEF-0105/0106. Same reasoning: openable here, with the missing producer tracked
## in the deferred log rather than re-litigated in a content suite.
##
## **`declare`.** An event payload, not a question about the hero
## (`EventGate._declaration`). Read locally, never handed to `DestinyApi.gate`,
## which does not own the verb.
##
## ## Exclusivity is real and enforced here
##
## A destiny in a group is refused once a sibling is held, exactly as
## `DestinyGate.earnable` refuses it. So reachability is proved PER ARRIVAL: each
## `group = "origin"` destiny is grown from its own fresh hero, and the two
## siblings that hero can never hold are excluded from ITS obligation rather than
## asserted reachable. A member reachable only through a sibling would be
## unreachable in every real playthrough, and `test_every_grouped_destiny_is_...`
## below states that as its own rule.

## The exclusivity group whose members close each other. Read from the catalog so
## this suite covers a fourth arrival without editing itself.
const ORIGIN_GROUP := &"origin"

## The composition root that earns an arrival. It is the ONLY `earn_destiny` call
## site outside quest and event, so a walk ignoring it would report the three
## arrivals unreachable when the player is handed one at creation.
const ARRIVAL_SOURCE := "arrival"


## One node of the authored graph: a fate or a destiny the catalog ships.
##
## `grants` are the nodes this one hands over the moment it is earned, and
## `needs_*` are what its own gate demands first. Both are read off the SHIPPED
## `.tres` through the real catalogs, never parsed out of text: a text scan would
## re-implement the catalog's loader and could disagree with what actually ships.
class ReachNode:
	var id: StringName
	## Fate ids handed over when this node is earned. Never a destiny: a destiny
	## grants fates, never the reverse.
	var grants: Array = []
	var needs_fates: Array = []
	var needs_destinies: Array = []
	var is_destiny: bool = false
	var group: StringName = &""
	## `source -> authored requirement`. An EMPTY requirement means ungated, which
	## is the difference between a node a player can reach for free and one that
	## waits on something.
	var sources: Dictionary = {}

	func _init(node_id: StringName, destiny: bool = false) -> void:
		id = node_id
		is_destiny = destiny

	## Whether this node could be added to a hero already holding `have_fates` and
	## `have_destinies`.
	##
	## Exclusivity is asked of the catalog through the module's own group rule
	## rather than re-derived, and the prerequisites are the two exported arrays
	## `DestinyGate.earnable` iterates — so this mirrors the engine's condition
	## exactly, and a second opinion here could not disagree with the real earn.
	func satisfiable(have_fates: Dictionary, have_destinies: Dictionary) -> bool:
		for fate_id in needs_fates:
			if not have_fates.has(fate_id):
				return false
		for destiny_id in needs_destinies:
			if not have_destinies.has(destiny_id):
				return false
		if not is_destiny or group == &"":
			return true
		# **String, not StringName — this is the bug that made 13 assertions fail.**
		# `FateCatalog.destinies_in_group` hands back `Array[StringName]`, so the
		# loop compared a StringName against a dictionary keyed by String and the
		# membership test was ALWAYS false: exclusivity never fired anywhere in
		# this walk. That is not a near-miss, it is the opposite answer — it let a
		# hero hold a whole group at once and report members reachable that no real
		# playthrough can produce, and it hid members that ARE reachable. It is
		# also why a from-a-fresh-hero walk appeared to need no arrival: every
		# branch looked open.
		for other in FateCatalog.instance().destinies_in_group(group):
			if String(other) != String(id) and have_destinies.has(String(other)):
				return false
		return true


## The shipped graph: every fate and destiny, and every rule that hands one over
## or demands one first. Keyed with a `d` prefix on destinies so a fate and a
## destiny sharing an id could not collide in one dictionary.
func _graph() -> Dictionary:
	var nodes: Dictionary = {}
	var catalog := FateCatalog.instance()
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		var node := ReachNode.new(fate_id, false)
		nodes[String(fate_id)] = node
	for destiny_id in catalog.destiny_ids():
		var def := catalog.destiny_definition(destiny_id)
		if def == null:
			continue
		var node := ReachNode.new(destiny_id, true)
		node.group = def.group
		node.needs_fates = _strings(def.requires_fates)
		node.needs_destinies = _strings(def.requires_destinies)
		# `earn_destiny` appends `grants_fates` in the SAME call, so they are a
		# grant edge on the destiny rather than a separate authored rule.
		for fate_id in def.grants_fates:
			if nodes.has(String(fate_id)):
				node.grants.append(String(fate_id))
		nodes[_key(destiny_id, true)] = node
	# A quest pays on completion, which needs only its own gate.
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		_add_grants(nodes, def.grants, "quest:" + String(quest_id), def.requirement)
	# An event pays once at resolution, which needs only its trigger.
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		_add_grants(nodes, def.pay, "event:" + String(event_id), def.trigger)
	# The arrivals. `candidates()` is the flow's own published table, so nothing
	# here duplicates the arrival list — adding a fourth arrival needs no edit
	# here, and deleting one cannot leave a stale entry behind.
	for entry in CharacterCreationFlow.new().candidates():
		var view: Dictionary = entry
		var arrival_id := StringName(view.get("id", ""))
		var key := _key(arrival_id, true)
		var node = nodes.get(key, null)
		if node == null:
			continue
		var source := ARRIVAL_SOURCE
		if not (node as ReachNode).sources.has(source):
			(node as ReachNode).sources[source] = {}
		# The fates an arrival brings with it: a destiny naming one of them in its
		# own `requires_fates` can never be earned otherwise (DEF-0109), so
		# creation earns it first, under the same `source`.
		for fate_id in view.get("arrival_fates", []) as Array:
			var fate_node = nodes.get(String(fate_id), null)
			if fate_node != null and not (fate_node as ReachNode).sources.has(source):
				(fate_node as ReachNode).sources[source] = {}
	return nodes


## Record `rows` as grant edges on whichever nodes they name.
func _add_grants(nodes: Dictionary, rows: Array, source: String, requirement: Dictionary) -> void:
	for row in rows:
		var kind := String(row.get("kind", ""))
		var id := String(row.get("id", ""))
		if kind != "fate" and kind != "destiny":
			continue
		var node = nodes.get(_key(StringName(id), kind == "destiny"), null)
		if node == null:
			continue
		if not (node as ReachNode).sources.has(source):
			(node as ReachNode).sources[source] = requirement


## The catalog key for one id.
func _key(id: StringName, is_destiny: bool) -> String:
	return ("d" + String(id)) if is_destiny else String(id)


## Whether one authored requirement is satisfied by what the hero holds, with
## `probe` carrying exactly that.
##
## `has_fate` / `has_destiny` are the MODULE's verdict, asked through
## `DestinyApi.gate`, so this suite holds no second opinion about a gate: an
## authored `gate_aliases` is honoured for free rather than being re-implemented,
## and a gate that opens in the engine cannot be reported closed here.
##
## The three verbs destiny does not own — `fact`, `counter`, `declare` — are
## answered here, and the class note says why each is answered the way it is.
func _open(requirement: Dictionary, probe: Actor) -> bool:
	if requirement == null or requirement.is_empty():
		return true
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		# Unreadable: refuse closed, exactly as `DestinyGate.evaluate` does. An
		# unreadable gate is a content bug, and treating it as open would let it
		# silently hand over a destiny.
		return false
	if verb == &"has_fate" or verb == &"has_destiny":
		return bool(DestinyApi.gate(probe, requirement)["ok"])
	if verb == &"fact" or verb == &"counter":
		return true
	if verb == &"declare":
		return String(requirement.get("other_id", "")) != ""
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		var children = requirement.get("of", [])
		if not (children is Array) or (children as Array).is_empty():
			# A composite naming no children is refused by both evaluators.
			return false
		var any_passed := false
		for child in children as Array:
			if not (child is Dictionary):
				return false
			var passed := _open(child as Dictionary, probe)
			if verb == &"all_of" and not passed:
				return false
			if verb == &"none_of" and passed:
				return false
			if passed:
				any_passed = true
		return any_passed if verb != &"none_of" else true
	return false


## Everything a hero arriving as `origin_id` can ever come to hold.
##
## `probe` is a real `Actor` kept in step with the walk, so `_open` can ask the
## module's own gate rather than a copy of it. The arrival is granted through the
## REAL flow, so an arrival the engine would refuse is not silently seeded here.
func _reachable_from(origin_id: StringName) -> Dictionary:
	var probe := _probe()
	var held: Dictionary = {}
	var outcome := CharacterCreationFlow.new().grant_origin(probe, origin_id)
	if bool(outcome.get("ok", false)):
		held["destiny:" + String(origin_id)] = true
		# Whatever creation brought with the arrival, read back off the hero
		# rather than restated: `ARRIVAL_FATES` is code the walk must not mirror.
		for fate_id in DestinyApi.fates(probe):
			held["fate:" + String(fate_id)] = true
	return _fixpoint(probe, held)


## The same fixpoint from a hero holding nothing but what it is handed here —
## used to show a destiny is reachable WITHOUT a sibling of its group, which an
## arrival walk cannot show, because an arrival is handed rather than gated.
##
## ## The seed is recorded only where the engine actually granted it
##
## `DestinyApi.earn_destiny` REFUSES an arrival whose `requires_fates` are unmet
## (DestinyGate.earnable), so a seed naming an unearned prerequisite would be a
## silent no-op: the previous version appended the ids it WISHED for, which is
## the one thing this walk must never do — it is how a walk reports content
## reachable on a hero the real earn path refused.
##
## That is exactly what the caller seeded. `the_chosen_instrument` requires
## `reborn_in_a_lesser_vessel`, which creation supplies through `ARRIVAL_FATES`,
## so seeding `[the_chosen_instrument]` alone earned nothing, recorded it anyway,
## and the fixpoint below found no way back to it — the arrival being handed to a
## player at creation was reported as something content has to unlock. The seed is
## taken here and recorded here instead: `_grant_route`'s truth about which rules
## are open at fixpoint time, and this hero's own ledger after each earn.
func _reachable_bare(seed_fates: Array, seed_destinies: Array, arrival_fates: Array = []) -> Dictionary:
	var probe := _probe()
	var held: Dictionary = {}
	for fate_id in seed_fates:
		DestinyApi.earn_fate(probe, StringName(fate_id), "reachability")
		if DestinyApi.has_fate(probe, StringName(fate_id)):
			held["fate:" + String(fate_id)] = true
	# The arrival's own prerequisites, granted before it and only when it is the
	# arrival that brings them — a seed for any other destiny is handed nothing.
	for fate_id in arrival_fates:
		DestinyApi.earn_fate(probe, StringName(fate_id), "reachability")
		if DestinyApi.has_fate(probe, StringName(fate_id)):
			held["fate:" + String(fate_id)] = true
	for destiny_id in seed_destinies:
		DestinyApi.earn_destiny(probe, StringName(destiny_id), "reachability")
		if DestinyApi.has_destiny(probe, StringName(destiny_id)):
			held["destiny:" + String(destiny_id)] = true
	return _fixpoint(probe, held)


## THE FIXPOINT. Repeatedly take whichever authored rule is satisfiable right now
## and add what it yields, until a whole pass adds nothing.
##
## One implementation for both walks, because two copies of a reachability walk
## are two answers to the same question and one of them will drift. Each pass
## only ever grows `held`, so this terminates; the set it stops at is exactly what
## a player could accumulate by playing the authored content, which is the only
## honest definition of reachable for content nobody chooses.
func _fixpoint(probe: Actor, held: Dictionary) -> Dictionary:
	var nodes := _graph()
	var changed := true
	while changed:
		changed = false
		for key in nodes.keys():
			if held.has(_tag(key)):
				continue
			var node = nodes[key]
			# A node nothing grants is an ORPHAN — DEF-0181's own defect. Treating
			# it as available would let the walk agree with itself.
			var offered := false
			for source in (node as ReachNode).sources.keys():
				if _open((node as ReachNode).sources[source], probe):
					offered = true
					break
			if not offered:
				continue
			if not node.satisfiable(_half(held, false), _half(held, true)):
				continue
			if not _earn(probe, node as ReachNode, held):
				continue
			changed = true
	return held


## Earn `node` on `probe` through the module's own facade, and record it in
## `held` only if the engine actually granted it.
##
## Refusing to record on a refusal is the whole point: a walk that recorded what
## it WANTED would pass on a hero the real earn path refused. That divergence is
## the unsatisfiable-cycle shape, so it has to be visible rather than absorbed.
func _earn(probe: Actor, node: ReachNode, held: Dictionary) -> bool:
	if node.is_destiny:
		DestinyApi.earn_destiny(probe, node.id, "reachability")
		if not DestinyApi.has_destiny(probe, node.id):
			return false
		held["destiny:" + String(node.id)] = true
	else:
		DestinyApi.earn_fate(probe, node.id, "reachability")
		if not DestinyApi.has_fate(probe, node.id):
			return false
		held["fate:" + String(node.id)] = true
	# A destiny carries its `grants_fates` with it in the same call, so they
	# arrive here rather than needing another pass.
	for fate_id in node.grants:
		held["fate:" + String(fate_id)] = true
	return true


## The `kind:id` tag a node key carries, so `held` can say what kind it holds.
func _tag(key: String) -> String:
	if key.begins_with("d"):
		return "destiny:" + key.substr(1)
	return "fate:" + key


## The fates, or the destinies, `held` currently carries — the two ledgers
## `Node.satisfiable` reads.
func _half(held: Dictionary, want_destiny: bool) -> Dictionary:
	var prefix := "destiny:" if want_destiny else "fate:"
	var out: Dictionary = {}
	for tag in held.keys():
		if String(tag).begins_with(prefix):
			out[String(tag).substr(prefix.length())] = true
	return out


## A throwaway hero with the destiny ledger attached and nothing earned.
func _probe() -> Actor:
	var actor := Actor.new(&"reachability_probe", {Stat.PHYSIQUE: 1.0, Stat.SPIRIT: 1.0})
	DestinyApi.attach(actor)
	return actor


## The fates and destinies the shipped catalog defines, as id strings.
func _shipped() -> Dictionary:
	var fates: Array[String] = []
	for fate_id in FateCatalog.instance().fate_ids():
		fates.append(String(fate_id))
	var destinies: Array[String] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		destinies.append(String(destiny_id))
	return {"fates": fates, "destinies": destinies}


## The ids a requirement names, split by the kind of node they name.
##
## `QuestDef.required_gate_ids` flattens all six verbs into one id list, which
## loses WHICH verb named what. A quest gated on `has_fate oath_breaker` and
## paying the DESTINY `oath_breaker` would read as a cycle under that list, so
## the verb is honoured here. Small and explicit rather than another flattened
## helper, because the two questions below both need the distinction.
func _gates_on(requirement: Dictionary, want_destiny: bool) -> Array:
	var out: Array = []
	_walk_gates(requirement, want_destiny, out)
	return out


func _walk_gates(node, want_destiny: bool, out: Array) -> void:
	if not (node is Dictionary):
		return
	var entry := node as Dictionary
	var verb := StringName(entry.get("verb", ""))
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		var children = entry.get("of", [])
		if not (children is Array):
			return
		# Bounded by the authored nesting, never an unbounded search.
		for child in children as Array:
			_walk_gates(child, want_destiny, out)
		return
	var wanted := (
		want_destiny if verb == &"has_destiny" else (verb == &"has_fate" and not want_destiny)
	)
	if not wanted:
		return
	var id := String(entry.get("id", ""))
	if id != "" and not out.has(id):
		out.append(id)


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## Every source that hands `node` over: its authored `sources` (quest `grants`,
## event `pay`, an arrival) PLUS the `grants_fates` of every shipped destiny, each
## labelled with that destiny so the reason names a file rather than just "yes".
##
## The label is `destiny:<id>` rather than a plain `{}` because an orphan report
## is only actionable if it can say which `.tres` to open; `_graph` already models
## the edge separately as `ReachNode.grants` for the fixpoint to consume.
func _grant_route(node: ReachNode) -> Dictionary:
	var out: Dictionary = node.sources.duplicate()
	for destiny_id in FateCatalog.instance().destiny_ids():
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null or not def.grants_fates.has(node.id):
			continue
		var source := "destiny:%s" % destiny_id
		if not out.has(source):
			out[source] = {}
	return out


# --- The assertions ----------------------------------------------------------


## The load-bearing one. Every authored fate and destiny is obtainable, from
## every arrival, by playing the authored content.
##
## Both cycles this suite exists for fail HERE and nowhere else: `the_severed`
## required the fate only `the_severed_calling` paid, and no authored row granted
## `the_one_who_returned`. Per arrival, because a member closed by another
## arrival's exclusivity is legitimately unreachable from the wrong one and a
## whole-tree check would call the design a defect.
func test_every_authored_fate_and_destiny_is_reachable_from_every_arrival() -> void:
	var shipped := _shipped()
	var fates: Array = shipped["fates"]
	var destinies: Array = shipped["destinies"]
	# Both sets asserted NON-EMPTY first: a fixpoint over an empty catalog is
	# vacuously true, and a suite that measured nothing must not report green.
	assert_eq(fates.is_empty(), false, "the shipped fate tree is not empty")
	assert_eq(destinies.is_empty(), false, "the shipped destiny tree is not empty")

	var arrivals := _arrivals()
	assert_eq(arrivals.is_empty(), false, "the composition root still ships an arrival")
	var unreachable := 0
	for origin_id in arrivals:
		var held := _reachable_from(origin_id)
		var missing_fates: Array[String] = []
		for fate_id in fates:
			if not held.has("fate:" + String(fate_id)):
				missing_fates.append(String(fate_id))
		var missing_destinies: Array[String] = []
		for destiny_id in destinies:
			# A sibling arrival can never be held once this one is: `group` closes
			# it for good, which is the design (ADR 0065), not a defect.
			if arrivals.has(destiny_id) and destiny_id != origin_id:
				continue
			if not held.has("destiny:" + String(destiny_id)):
				missing_destinies.append(String(destiny_id))
		unreachable += missing_fates.size() + missing_destinies.size()
		assert_eq(
			missing_fates,
			[],
			(
				"every authored fate is reachable from the arrival '%s'. Unreachable: %s"
				% [origin_id, ", ".join(missing_fates)]
			)
		)
		assert_eq(
			missing_destinies,
			[],
			(
				(
					"every authored destiny outside the '%s' group is reachable from '%s'."
					+ " Unreachable: %s"
				)
				% [ORIGIN_GROUP, origin_id, ", ".join(missing_destinies)]
			)
		)
	assert_eq(
		unreachable,
		0,
		"no authored fate or destiny is unreachable from any arrival (DEF-0181, DEF-0182)"
	)


## Every arrival the composition root ships, canonically ordered. Asked of the
## flow's own group so a fourth arrival is covered without editing this suite.
func _arrivals() -> Array:
	var out: Array = []
	for destiny_id in FateCatalog.instance().destinies_in_group(ORIGIN_GROUP):
		out.append(destiny_id)
	return out


## No node is an ORPHAN: every authored fate and destiny is handed over by at
## least one authored rule.
##
## Stated separately from reachability because it is the shorter, more useful
## answer to "why can I not get this": nothing grants it. DEF-0181 is exactly
## this — six fates with no earn path — and a reader looking at one unreachable
## id should be told that rather than handed a fixpoint.
##
## **`grants_fates` counts as a route, through `_grant_route`.** A fate a destiny
## carries is handed over by `DestinyApi.earn_destiny` in the SAME call, so a scan
## that reads only quest and event `grants`/`pay` calls `oath_of_the_empty_hand`
## and `oath_kept_under_witness` orphans — both of which ARE reachable, via
## `the_one_who_stayed`'s own `grants_fates` — and reports content as broken that
## is not. An orphan hunt that answers "nothing grants this" must not answer it
## with a subset of the grant rules.
func test_no_authored_fate_or_destiny_is_an_orphan_with_no_earn_path() -> void:
	var nodes := _graph()
	var orphans: Array[String] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		var node = nodes.get(_key(destiny_id, true), null)
		if node != null and _grant_route(node as ReachNode).is_empty():
			orphans.append(String(destiny_id))
	for fate_id in FateCatalog.instance().fate_ids():
		var node = nodes.get(String(fate_id), null)
		if node != null and _grant_route(node as ReachNode).is_empty():
			orphans.append(String(fate_id))
	assert_eq(
		orphans,
		[],
		(
			"every authored fate and destiny is granted by some quest, event, arrival or"
			+ " destiny: %s" % ", ".join(orphans)
		)
	)


## A quest is never gated on a destiny it grants itself.
##
## DEF-0182's shape in one rule: the reward the gate is waiting on cannot be the
## thing the reward pays. A quest may be gated on a destiny ANOTHER rule grants —
## that is ordinary, and `the_returned_instrument` gated on
## `the_one_who_returned` is legitimate because creation grants that destiny.
## What it may not do is be the only route to the destiny it is gated behind.
func test_no_quest_is_gated_on_a_destiny_it_grants_itself() -> void:
	var offending: Array[String] = []
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for gate_id in _gates_on(def.requirement, true):
			for grant in def.grants:
				if (
					String(grant.get("kind", "")) == QuestDef.GRANT_DESTINY
					and String(grant.get("id", "")) == gate_id
				):
					offending.append("%s gates on and grants destiny '%s'" % [quest_id, gate_id])
	assert_eq(
		offending, [], "no quest is gated on a destiny it pays itself: %s" % " | ".join(offending)
	)


## A destiny never requires a fate whose only supply is a quest gated on that
## destiny. The hard cycle DEF-0181 found, asserted as a shape.
##
## `the_severed` required `bound_name_called_once`, and the only authored rule
## paying it was `the_severed_calling` — the quest gated on `the_severed`. The
## prerequisite's only route waits on the prerequisite, so there is no entry.
## Stated directly rather than left to the fixpoint because it is the one shape a
## future author can reintroduce while every individual rule still looks legal.
func test_no_destiny_requires_a_fate_supplied_only_by_a_gate_that_waits_on_it() -> void:
	var nodes := _graph()
	var offending: Array[String] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		var node = nodes.get(_key(destiny_id, true), null)
		if node == null:
			continue
		for fate_id in (node as ReachNode).needs_fates:
			var fate_node = nodes.get(String(fate_id), null)
			if fate_node == null:
				continue
			for source in (fate_node as ReachNode).sources.keys():
				var label := String(source)
				if not label.begins_with("quest:"):
					continue
				var quest := QuestCatalog.instance().definition(
					StringName(label.substr("quest:".length()))
				)
				if quest == null:
					continue
				if _gates_on(quest.requirement, true).has(String(destiny_id)):
					offending.append(
						(
							(
								"destiny '%s' requires fate '%s', whose only supply is the quest"
								+ " gated on '%s'"
							)
							% [destiny_id, fate_id, destiny_id]
						)
					)
	assert_eq(
		offending,
		[],
		(
			"no destiny requires a fate whose only route waits on that destiny: %s"
			% " | ".join(offending)
		)
	)


## EXCLUSIVITY IS SATISFIABLE: no destiny in a group is reachable ONLY through a
## sibling.
##
## This is the failure mode exclusivity invites, and it is invisible to an
## ordinary reachability check: holding a sibling closes the member permanently,
## so a member whose only route runs through a sibling can never be earned in any
## real playthrough, while every rule in the file still reads as legal. The test
## walks each member from a hero holding NOTHING, and fails if a sibling has to
## be held to reach it.
##
## The group itself is asserted to exist, so this is a claim about the shipped
## design rather than a vacuous loop over nothing.
##
## **A hero holding nothing INCLUDES a hero who has just arrived, and excluding
## that is the bug this assertion used to carry.** For the `origin` group every
## member is HANDED OVER at creation: `CharacterCreationFlow.grant_origin` is the
## earn, and ADR 0065 forbids earning one by playing toward it. So seeding only
## `requires_*` and asking whether the member turns up cannot be answered true
## for any real arrival, and the failure it produced
## ("'the_one_who_returned' is reachable from a hero holding nothing") was the
## TEST being wrong, not the content.
##
## The previous seed was worse than a too-strict question: it admitted one of
## this member's SIBLINGS, which is precisely the dependency the assertion exists
## to catch. It read the arrival list and handed over `group[1]` and `group[2]`
## around whatever member it was asked about — so for every member it asked
## whether a sibling was reachable, and answered yes. Read [method
## _granted_by_arrival] for why that was also true the other way round, and what
## the seed is now.
func test_every_grouped_destiny_is_reachable_without_holding_a_sibling() -> void:
	var groups := _groups()
	assert_eq(groups.is_empty(), false, "the shipped tree still has an exclusivity group")

	for group in groups.keys():
		var members: Array = groups[group]
		for destiny_id in members:
			var def := FateCatalog.instance().destiny_definition(destiny_id)
			if def == null:
				continue
			# Seeded with this member's OWN prerequisites, and with nothing of its
			# own kind beside them: a prerequisite that is a SIBLING would show up
			# in the loop below as a sibling held, which is the defect. See
			# `_granted_by_arrival` for the arrival itself.
			var held := _reachable_bare(
				_strings(def.requires_fates),
				_strings(def.requires_destinies),
				_granted_by_arrival(destiny_id)
			)
			assert_eq(
				held.has("destiny:" + String(destiny_id)),
				true,
				(
					(
						"destiny '%s' (group '%s') is reachable from a hero holding nothing, so"
						+ " exclusivity is satisfiable"
					)
					% [destiny_id, group]
				)
			)
			for sibling in members:
				if sibling == destiny_id:
					continue
				assert_eq(
					held.has("destiny:" + String(sibling)),
					false,
					(
						(
							"'%s' is reached without holding '%s', so it does not depend on the"
							+ " branch it permanently excludes"
						)
						% [destiny_id, sibling]
					)
				)


## The destiny to seed a bare walk with so that `destiny_id` can be reached
## WITHOUT holding any of its siblings — `[destiny_id]`, and nothing else.
##
## ## Why this is not simply `[destiny_id]`
##
## `the_chosen_instrument` names `reborn_in_a_lesser_vessel` in its own
## `requires_fates`, and that fate's only grant routes in the shipped tree are
## the quest `the_short_road` and `ARRIVAL_FATES` in `character_creation_flow.gd`
## — creation hands it over on the player's behalf (DEF-0109). So the seed is the
## arrival's OWN prerequisite set, taken from the flow's published
## `candidates()[].arrival_fates`, never from the constant: the walk must not
## mirror `ARRIVAL_FATES`, and a constant restated here would drift from it.
## `_reachable_bare` earns the seed through the real facade, so a fate whose
## definition is gone is refused rather than recorded.
##
## ## Why it could not be "every other member of the group"
##
## That is what the previous version did, by walking `group[1]` and `group[2]`
## around whichever member it was asked about. It failed BOTH halves of the
## assertion, and neither half could ever have passed:
##
##   - every seed it chose was a SIBLING of the member, so the member was
##     permanently closed and "is reachable from a hero holding nothing" was false
##     for every `origin` destiny, including the one a fresh hero is handed;
##   - and because `tournament_of_the_spirit_peaks.tres` pays BOTH
##     `first_blood_duel` and `the_chosen_instrument`, the bare fixpoint reached
##     `the_chosen_instrument` THROUGH that event. Holding it closed its two
##     siblings, so the sibling loop reported "reached while holding" for all of
##     them — a second-order failure caused by the first.
##
## It is also a stronger claim than the design makes. An arrival is offered to
## the player as one of three choices, so the honest statement is per member, not
## for the group as a whole: **every member of the group is reachable on its
## own.** That is what [method test_every_grouped_destiny_is_reachable_without_holding_a_sibling]
## asks, and it is what this seed feeds it.
func _granted_by_arrival(destiny_id: StringName) -> Array[String]:
	for entry in CharacterCreationFlow.new().candidates():
		var view: Dictionary = entry
		if StringName(view.get("id", "")) != destiny_id:
			continue
		var out: Array[String] = []
		for fate_id in view.get("arrival_fates", []) as Array:
			out.append(String(fate_id))
		return out
	# Not an arrival: no creation hand-over exists, so nothing is seeded and the
	# walk must reach it from its own authored prerequisites alone. That is the
	# ordinary case and it is what makes the helper safe for a group whose
	# members are earned rather than handed over.
	return []


## Every exclusivity group in the shipped tree, as `group -> [member ids]`.
func _groups() -> Dictionary:
	var out: Dictionary = {}
	for destiny_id in FateCatalog.instance().destiny_ids():
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null or def.group == &"":
			continue
		var members: Array = out.get(def.group, [])
		members.append(destiny_id)
		out[def.group] = members
	return out


## The group closes its members FOR GOOD, which is the design the origin table
## depends on. Asserted so the reachability walk above cannot be read as "any of
## the three will do eventually": holding two is not a slow path to a third.
##
## Read straight off the catalog rather than off `group[0]` / `group[1]`, and it is
## a 31-line walker's answer to "is this member reachable" on the cheapest hero
## there is.
##
## **Seeded through the REAL flow, because "holding nothing" does not mean
## "unarrived".** An earlier draft of this suite seeded the hero with its own
## `DestinyApi.earn_destiny` and read the result off `has_destiny`, and it was
## failing as "the first arrival is held: expected true, got false" for a
## straight, boring reason — `group[0]` is `the_chosen_instrument`, whose
## `requires_fates` name `reborn_in_a_lesser_vessel`. A bare earn is REFUSED for
## it, and that refusal is correct: DEF-0109 is closed by creation handing that
## fate over (`ARRIVAL_FATES`), which is the only way any player ever gets this
## arrival. `CharacterCreationFlow.grant_origin` grants the fate first and the
## destiny second, in that order, so it is the only honest seed — an arrival the
## engine would refuse is never recorded as held here either.
func test_the_exclusivity_group_closes_its_members_permanently() -> void:
	var group := FateCatalog.instance().destinies_in_group(ORIGIN_GROUP)
	assert_eq(group.size(), 3, "the origin group still has its three arrivals")
	var actor := _probe()
	var origin_id: StringName = group[0]
	var seeded := CharacterCreationFlow.new().grant_origin(actor, origin_id)
	assert_eq(
		bool(seeded.get("ok", false)),
		true,
		"creation grants the first arrival to a hero holding nothing: %s" % JSON.stringify(seeded)
	)
	assert_eq(DestinyApi.has_destiny(actor, origin_id), true, "the first arrival is held")
	var before := DestinyApi.state(actor)["destinies"] as Dictionary
	var other: StringName = group[1]
	DestinyApi.earn_destiny(actor, other, "reachability")
	assert_eq(
		DestinyApi.state(actor)["destinies"] as Dictionary,
		before,
		"and the earn that would add a sibling changes nothing"
	)
	assert_eq(DestinyApi.has_destiny(actor, other), false, "the sibling is refused")
