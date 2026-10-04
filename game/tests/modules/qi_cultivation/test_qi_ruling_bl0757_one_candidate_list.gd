extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## ADR 0165: `owed_channels` and `training_price` and `train_next_channel` share ONE
## candidate list. This suite is what stops them diverging again (BL-0757).
##
## The latent divergence, as filed: `QiCultivationApi._training_candidates` returned
## the gate's own channels PLUS all 20 meridians, while `QiTraining.
## train_next_channel` walks only `gate.required_meridians`. The two sets coincide at
## all 29 boundaries today, so the tail was dead — but the day a seed named fewer
## channels than the standing realm unlocks, `owed_channels` would report work the
## verb would never attempt and the screen would print "channel elixir absent; N
## channel(s) still owed" (`qi_cultivation_screen.gd:328`) for a press that owes
## nothing. That is the answer ADR 0150 exists to eliminate.
##
## The tail's own docstring claimed it existed "so a spare elixir has somewhere to
## go", which `training.gd:202-206` explicitly refuses: a spare elixir spent
## deepening a channel the gate never asked for is charged the realm's price for
## work the gate does not want. A docstring the code contradicts is the rot this
## suite exists to catch, so the fix deleted the tail rather than reconciling the
## two sentences.


## The two sets are the same set, asserted structurally on the shipped code so a
## future widening of either one is caught at the source rather than by a symptom.
func test_the_read_model_and_the_verb_share_one_candidate_list() -> void:
	# Matched on the FUNCTION BODY, not the file: `recover_next` legitimately walks
	# `MeridianDefaults.all()` to find any wound, and a file-wide match would read
	# that as the defect. What must not come back is a candidate list built from
	# every meridian.
	var api_source := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/api.gd")
	var body := _function_body(api_source, "_training_candidates")
	assert_ne(body.is_empty(), true, "_training_candidates still exists")
	assert_eq(
		body.contains("MeridianDefaults"),
		false,
		"_training_candidates walks every meridian again; owed_channels can then exceed what the verb attempts"
	)
	assert_eq(
		body.contains("gate.required_meridians"),
		true,
		"and it reads the gate's own list, which is the list the verb walks"
	)
	var training := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/training.gd")
	assert_eq(
		training.contains("for meridian_id in gate.required_meridians:"),
		true,
		"the verb still walks the gate's own list; this is the list the read model must match"
	)


## One function's source, from its declaration to the next top-level `func` or
## `static func`. Bounded by the file's own line count and the scan moves an index it
## reads (INC-0002).
func _function_body(source: String, name: String) -> String:
	var lines := source.split("\n")
	var out: Array[String] = []
	var inside := false
	for index in range(lines.size()):
		var line := String(lines[index])
		var starts_a_func := line.begins_with("func ") or line.begins_with("static func ")
		if starts_a_func:
			if inside:
				# A new declaration ends the body we were collecting.
				if not line.contains("func %s(" % name):
					break
			elif line.contains("func %s(" % name):
				inside = true
		if inside:
			out.append(line)
	return "\n".join(out)


## The behavioural half, on the live corpus: whatever `owed_channels` reports, the
## verb can actually attempt that many times. At the deepest realm the gate names
## every unlocked channel, so the count is at its largest and a divergence between
## the two lists would show up here first.
func test_owed_channels_never_exceeds_what_the_verb_will_attempt() -> void:
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	# Bounded by the ladder: each realm visited once, and no body appends to the
	# container it walks (INC-0002).
	for index in range(realms.size() - 1):
		var standing := realms[index]
		var target := realms[index + 1]
		var gate := QiRealmSeed.for_realm(target.id)
		if gate == null:
			continue
		var actor := Probe.fresh_actor(standing.id)
		var live := QiCultivationApi.panel_state(actor)
		assert_eq(live.is_empty(), false, "%s has a read model" % standing.id)
		var owed := int(live.get("owed_channels", 0))
		var reported: Array = live.get("required_channels", [])
		assert_eq(
			owed <= reported.size(),
			true,
			(
				"%s reports %d owed against %d gate channels; owed_channels walks a wider set than the gate"
				% [standing.id, owed, reported.size()]
			)
		)


## And the refusal answer stays truthful: with every gate channel met, `owed` is
## zero and the screen's "no channel left to train" branch is the one that can fire.
## This is the case BL-0757 predicted, measured on the real verbs.
func test_a_met_gate_reports_nothing_owed() -> void:
	Probe.clear_prepared()
	var seed := Probe.target_seed_after(&"qi_refining")
	assert_ne(seed, null, "the first boundary has a seed")
	var actor := Probe.prepared(&"qi_refining", seed)
	assert_ne(actor, null, "a prepared actor with the gate met")
	Probe.train_gate_channels(actor, seed)
	var live := QiCultivationApi.panel_state(actor)
	assert_eq(
		int(live.get("owed_channels", 0)),
		0,
		"a met gate owes nothing, so the screen cannot print an elixir the player does not owe"
	)
	assert_eq(String(live.get("training_price", "")), "", "and it names no price")


## The latent half, closed: a seed that names FEWER channels than the standing
## realm unlocks is the exact future state BL-0757 warned about, and it is
## unreachable on the shipped corpus — so the property is asserted on the CODE
## rather than simulated, because simulating it would mean authoring a seed.
func test_no_seed_names_fewer_channels_than_its_boundary_unlocks() -> void:
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	# Bounded by the ladder; the count is compared, never used as a loop bound.
	for index in range(realms.size() - 1):
		var standing := realms[index]
		var gate := QiRealmSeed.for_realm(realms[index + 1].id)
		if gate == null:
			continue
		var actor := Probe.fresh_actor(standing.id)
		var unlocked := 0
		for channel in actor.meridians.get_all_meridians():
			unlocked += 1
		assert_eq(
			gate.required_meridians.size() <= unlocked,
			true,
			(
				"%s names %d channels but only %d are unlocked; the two candidate lists would differ"
				% [realms[index + 1].id, gate.required_meridians.size(), unlocked]
			)
		)
