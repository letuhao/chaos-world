extends TestCase

## The roster is structural (ADR 0881): three postures of four, ported verbatim from
## Keepverse's `AptitudeCatalog`. These pin the SHAPE, not a balance number.


func test_the_roster_is_three_postures_of_four_by_construction() -> void:
	assert_eq(Aptitude.POSTURES.size(), 3, "three postures")
	assert_eq(
		Aptitude.all_ids().size(),
		Aptitude.POSTURES.size() * Aptitude.PER_POSTURE,
		"twelve, by construction rather than by a number"
	)
	for posture in Aptitude.POSTURES:
		assert_eq(Aptitude.in_posture(posture).size(), Aptitude.PER_POSTURE, "four per posture")


func test_ids_are_unique_and_append_ordered() -> void:
	var ids := Aptitude.all_ids()
	var seen := {}
	for index in range(ids.size()):
		assert_eq(seen.has(ids[index]), false, "id %s appears once" % String(ids[index]))
		seen[ids[index]] = true
		assert_eq(Aptitude.ordinal_of(ids[index]), index, "ordinal is the append-only position")
	assert_eq(
		Aptitude.ordinal_of(&"no_such_aptitude"), -1, "an id outside the roster has no ordinal"
	)


func test_the_ordinals_are_keepverse_s_own() -> void:
	assert_eq(Aptitude.ordinal_of(&"might"), 0, "the roster starts where Keepverse's does")
	assert_eq(Aptitude.ordinal_of(&"bulwark"), 8, "bastion opens at the ninth ordinal")
	assert_eq(Aptitude.ordinal_of(&"ferocity"), 11, "and ends where Keepverse's does")


func test_posture_of_round_trips_for_every_id() -> void:
	for posture in Aptitude.POSTURES:
		for id in Aptitude.in_posture(posture):
			assert_eq(Aptitude.posture_of(id), posture, "%s is %s" % [String(id), String(posture)])
	assert_eq(Aptitude.posture_of(&"no_such_aptitude"), &"", "an unknown id belongs to no posture")


func test_the_one_shared_spelling_with_the_attribute_layer_is_deliberate() -> void:
	# `&"agility"` is BOTH `Stat.AGILITY` (a stored attribute) and an aptitude id. The
	# layers are different — an attribute value versus a matrix share — and the overlap
	# is exactly one id wide; anything wider is a port decision nobody made.
	var overlap: Array[StringName] = []
	for id in Aptitude.all_ids():
		if Stat.BASE_ATTRIBUTES.has(id):
			overlap.append(id)
	assert_eq(overlap.size(), 1, "exactly one spelling is shared with the attribute layer")
	assert_eq(overlap[0], Stat.AGILITY, "and it is the agility spelling")
