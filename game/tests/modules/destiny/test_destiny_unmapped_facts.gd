extends TestCase

## BL-0600, closed as a DECISION: the facts the tree produces that no authored fate reads
## are NAMED in `DestinyProjection.FACTS_NO_FATE_READS`, so "deliberately unmapped" cannot
## be confused with "somebody forgot".
##
## The finding was that `sect_post_held` has a real producer (`SectFacts.record_post_held`)
## and four shipped quest steps watch it, yet it moves no fate counter — and nothing said
## whether that was intended. This suite is what says so.

## The module that owns the one unmapped fact's producer.
const SECT_FACTS := "res://src/modules/sect/sect_facts.gd"


## A fact is either mapped in the table or named as unmapped — never both, or the list
## would be a second opinion about a row that already exists.
func test_the_unmapped_list_does_not_overlap_the_mapped_table() -> void:
	var mapped: Dictionary = {}
	for row in DestinyProjection.COUNTER_FACTS:
		mapped[String((row as Dictionary).get("fact", ""))] = true
	for fact in DestinyProjection.FACTS_NO_FATE_READS:
		assert_eq(
			mapped.has(String(fact)),
			false,
			"'%s' is named unmapped, so it must not also be a COUNTER_FACTS row" % String(fact)
		)


## The list is EXACTLY the known gap. Adding a second unmapped fact — or dropping the one
## — fails here, so the decision is re-made rather than inherited.
func test_the_unmapped_list_is_exactly_the_known_gap() -> void:
	var names: Array[String] = []
	for fact in DestinyProjection.FACTS_NO_FATE_READS:
		names.append(String(fact))
	names.sort()
	assert_eq(
		names,
		["sect_post_held"],
		(
			"the only produced-but-unread fact is sect_post_held; a change to this list must "
			+ "say why, and a new unmapped fact belongs here in its own change (BL-0600)"
		)
	)


## The named fact really is PRODUCED by the shipped tree — the list names a live fact, not
## a dead id kept alive by a comment. Read from the module that claims the producer rather
## than restated.
func test_the_unmapped_fact_has_a_real_producer() -> void:
	var body := FileAccess.get_file_as_string(SECT_FACTS)
	assert_ne(body, "", "%s ships, so this is not a silent skip" % SECT_FACTS)
	for fact in DestinyProjection.FACTS_NO_FATE_READS:
		assert_eq(
			body.contains('&"%s"' % String(fact)),
			true,
			"%s names '%s' as its own producer" % [SECT_FACTS, String(fact)]
		)
