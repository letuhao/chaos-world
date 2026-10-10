extends TestCase

## ## The graph-shape and exclusivity half of the reachability guard
##
## The sibling `test_destiny_reach_from_arrivals.gd` proves the load-bearing claim
## — every authored fate and destiny is obtainable from SOME arrival — and the
## census that names what is stranded. This suite asks the SHORTER, more useful
## structural questions about the same shipped graph:
##
##   - is any fate or destiny an ORPHAN (nothing grants it)? — DEF-0181's own shape
##   - does any rule form a CYCLE the player cannot enter? — DEF-0181/0182's shapes
##   - is EXCLUSIVITY satisfiable (is any member reachable only through a sibling)?
##   - does the group close its members FOR GOOD, as the origin table depends on?
##
## All of them walk the SAME authored graph through the SAME engine, reached by
## `preload` from `destiny_reach_walker.gd`. Neither suite re-implements the
## walker: the fixpoint and the gate verdict live in exactly one place, so the two
## halves of this guard cannot drift into disagreeing about what "reachable" means.
##
## ## Why these are stated separately from the union walk
##
## A reader looking at one unreachable id wants the shorter answer: is it an
## orphan (nothing grants it), or is it behind a gate that waits on itself? The
## fixpoint walk answers "it was not reached", which is the symptom; these state
## the cause. DEF-0181 is exactly the orphan rule (six fates with no earn path),
## and a gate cycle (`the_severed` requiring a fate only a quest gated on
## `the_severed` pays) is a shape a future author can reintroduce while every
## individual rule still reads as legal — which is why each is stated directly
## rather than left to the fixpoint.

## The walker: the shipped graph, the gate answering and every shared helper.
const Walker := preload("res://tests/modules/destiny/destiny_reach_walker.gd")
## The walk: `reachable_from`, `reachable_bare`, the fixpoint and the census reads.
const Walks := preload("res://tests/modules/destiny/destiny_reach_walks.gd")

## The exclusivity group whose members close each other, read from the catalog.
const ORIGIN_GROUP := &"origin"


## No node is an ORPHAN: every authored fate and destiny is handed over by at
## least one authored rule.
##
## Stated separately from reachability because it is the shorter, more useful
## answer to "why can I not get this": nothing grants it. DEF-0181 is exactly
## this — six fates with no earn path — and a reader looking at one unreachable
## id should be told that rather than handed a fixpoint.
##
## **`grants_fates` counts as a route, through `grant_route`.** A fate a destiny
## carries is handed over by `DestinyApi.earn_destiny` in the SAME call, so a scan
## that reads only quest and event `grants`/`pay` calls `oath_of_the_empty_hand`
## and `oath_kept_under_witness` orphans — both of which ARE reachable, via
## `the_one_who_stayed`'s own `grants_fates` — and reports content as broken that
## is not. An orphan hunt that answers "nothing grants this" must not answer it
## with a subset of the grant rules.
func test_no_authored_fate_or_destiny_is_an_orphan_with_no_earn_path() -> void:
	var nodes := Walker.graph()
	var orphans: Array[String] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		var node = nodes.get(Walker.key(destiny_id, true), null)
		if node != null and Walker.grant_route(node as Walker.ReachNode).is_empty():
			orphans.append(String(destiny_id))
	for fate_id in FateCatalog.instance().fate_ids():
		var node = nodes.get(String(fate_id), null)
		if node != null and Walker.grant_route(node as Walker.ReachNode).is_empty():
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
		for gate_id in Walker.gates_on(def.requirement, true):
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
	var nodes := Walker.graph()
	var offending: Array[String] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		var node = nodes.get(Walker.key(destiny_id, true), null)
		if node == null:
			continue
		for fate_id in (node as Walker.ReachNode).needs_fates:
			var fate_node = nodes.get(String(fate_id), null)
			if fate_node == null:
				continue
			for source in (fate_node as Walker.ReachNode).sources.keys():
				var label := String(source)
				if not label.begins_with("quest:"):
					continue
				var quest := QuestCatalog.instance().definition(
					StringName(label.substr("quest:".length()))
				)
				if quest == null:
					continue
				if Walker.gates_on(quest.requirement, true).has(String(destiny_id)):
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
## Walker.granted_by_arrival] for why that was also true the other way round, and
## what the seed is now.
##
## ## The member is now the seed, and only its own prerequisites sit beside it
##
## A third version passed `[destiny_id]` too and let the FIXPOINT supply it —
## which is this assertion asking exactly the question it exists to catch. It
## answered honestly once `Walker.verdict` stopped inventing gates, because
## `the_station_you_held.tres` pays an ungated row and
## `tournament_of_the_spirit_peaks.tres` pays this very destiny; but a rule that
## comes out right for the wrong reason is one content edit away from coming out
## wrong, and "every member is reachable" would then be reporting the tournament's
## `pay` row rather than the arrival. Read [method Walks.reachable_bare] for the
## division.
func test_every_grouped_destiny_is_reachable_without_holding_a_sibling() -> void:
	var groups := Walker.groups()
	assert_eq(groups.is_empty(), false, "the shipped tree still has an exclusivity group")

	for group in groups.keys():
		var members: Array = groups[group]
		for destiny_id in members:
			var def := FateCatalog.instance().destiny_definition(destiny_id)
			if def == null:
				continue
			# THIS MEMBER is what the hero is handed, plus nothing else of its own
			# kind: a prerequisite that is a SIBLING would show up in the loop below
			# as a sibling held, which is the defect. See
			# [method Walker.granted_by_arrival] for the fates an arrival brings with
			# it, and [method Walks.reachable_bare] for why the member itself is
			# granted here rather than waited for.
			var held := Walks.reachable_bare(
				Walker.strings(def.requires_fates),
				[String(destiny_id)],
				Walker.granted_by_arrival(destiny_id)
			)
			assert_eq(
				Walker.unreached_reason(held),
				"",
				(
					(
						"the exclusivity walk for '%s' stopped after its pass cap instead of"
						+ " reaching a fixpoint: %s"
					)
					% [destiny_id, Walker.unreached_reason(held)]
				)
			)
			assert_eq(
				held.has("destiny:" + String(destiny_id)),
				true,
				(
					(
						"destiny '%s' (group '%s') is reachable from a hero holding nothing, so"
						+ " exclusivity is satisfiable. Held: %s"
					)
					% [destiny_id, group, ", ".join(PackedStringArray(Walker.sorted_tags(held)))]
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


## The group closes its members FOR GOOD, which is the design the origin table
## depends on. Asserted so the reachability walk in the sibling suite cannot be
## read as "any of the three will do eventually": holding two is not a slow path
## to a third.
##
## Read straight off the catalog rather than off `group[0]` / `group[1]`, and it is
## a walker's answer to "is this member reachable" on the cheapest hero there is.
##
## **Seeded through the REAL flow, because "holding nothing" does not mean
## "unarrived".** An earlier draft of this guard seeded the hero with its own
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
	var probe := Walker.probe()
	var origin_id: StringName = group[0]
	var seeded := CharacterCreationFlow.new().grant_origin(probe, origin_id)
	assert_eq(
		bool(seeded.get("ok", false)),
		true,
		"creation grants the first arrival to a hero holding nothing: %s" % JSON.stringify(seeded)
	)
	assert_eq(DestinyApi.has_destiny(probe, origin_id), true, "the first arrival is held")
	var before := DestinyApi.state(probe)["destinies"] as Dictionary
	var other: StringName = group[1]
	DestinyApi.earn_destiny(probe, other, "reachability")
	assert_eq(
		DestinyApi.state(probe)["destinies"] as Dictionary,
		before,
		"and the earn that would add a sibling changes nothing"
	)
	assert_eq(DestinyApi.has_destiny(probe, other), false, "the sibling is refused")
