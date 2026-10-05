extends TestCase

## `DestinyApi.summary()` is the codex screen's only data source: one call has to
## answer what the actor holds, what exists but is still hidden, and what is
## holding the rest back. It had zero calls in the whole test tree, so a change to
## its shape — a renamed key, a leaked `Resource`, a hidden entry that revealed its
## name — would have reached the UI as an empty panel.
##
## The contract these assert:
##   - the payload is primitive-only, and a null actor is answered rather than
##     crashed on;
##   - a HELD entry shows its authored name and description even when it is hidden;
##   - an UNHELD hidden entry shows an EMPTY `display_name` and the teaser in
##     `description` — the teaser is not a leak;
##   - a `teaser`-visibility entry is absent entirely, so the codex cannot even
##     render a row for it;
##   - an unearned destiny carries `available` / `blocked_by`, and a held one does
##     not need them.

const OATH := &"t_oath_breaker"
const WHISPER := &"t_whisper"
const GHOST := &"t_unspeakable"
const SEAL := &"t_sealed_blood"
const CHOSEN := &"t_chosen_one"
const APPRENTICE := &"t_apprentice"
const RISEN := &"t_chosen_of_the_risen"
const DUELS := &"duels_won"
const MODULE_KEY := DestinyState.MODULE_KEY


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				# HIDDEN, and with a real teaser: this is the row that must not leak.
				DestinyFixtureCatalog.story_fate(WHISPER),
				# A pure-narrative fate nothing in this suite earns, so APPRENTICE is
				# blocked for an actor that has earned everything else.
				DestinyFixtureCatalog.story_fate(SEAL),
				# TEASER visibility: omitted from the codex entirely, even once earned.
				DestinyFixtureCatalog.silent_fate(GHOST),
			],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
				DestinyFixtureCatalog.plain_destiny(RISEN),
				DestinyFixtureCatalog.gated_destiny(APPRENTICE, [SEAL], []),
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


func _earned(actor_id: StringName = &"keeper") -> Actor:
	var actor := _hero(actor_id)
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, WHISPER, "story")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.record(actor, DUELS, 2)
	return actor


func _fate(view: Dictionary, fate_id: String) -> Dictionary:
	var fates := view["fates"] as Dictionary
	var row = fates.get(fate_id, null)
	if row is Dictionary:
		return row as Dictionary
	assert_eq(
		fate_id in fates,
		true,
		"the summary lists a fate row for '%s', and has %s" % [fate_id, str(fates.keys())]
	)
	return {}


func _destiny(view: Dictionary, destiny_id: String) -> Dictionary:
	var destinies := view["destinies"] as Dictionary
	var row = destinies.get(destiny_id, null)
	if row is Dictionary:
		return row as Dictionary
	assert_eq(
		destiny_id in destinies,
		true,
		"the summary lists a destiny row for '%s', and has %s" % [destiny_id, str(destinies.keys())]
	)
	return {}


# --- The shape of the payload -------------------------------------------------


func test_the_summary_always_carries_the_same_top_level_keys() -> void:
	for view in [DestinyApi.summary(_hero()), DestinyApi.summary(null)]:
		var keys: Array = view.keys()
		keys.sort()
		assert_eq(
			keys,
			[
				"actor_id",
				"counters",
				"destinies",
				"destiny_count",
				"fate_count",
				"fates",
				"has_actor",
				"hidden_destiny_count",
				"hidden_fate_count"
			],
			"the same nine keys whether or not there is an actor"
		)


func test_a_null_actor_yields_the_empty_ledger_rather_than_a_crash() -> void:
	var view := DestinyApi.summary(null)
	assert_eq(bool(view["has_actor"]), false, "and it says so")
	assert_eq(String(view["actor_id"]), "", "with no actor id")
	assert_eq(int(view["fate_count"]), 0, "no fates")
	assert_eq(int(view["destiny_count"]), 0, "no destinies")
	assert_eq(view["counters"] as Dictionary, {}, "and no counters")
	# The authored block is still offered: an empty codex should show what there is
	# to inherit, so a null actor costs the player nothing but their own entries.
	assert_eq(int(view["hidden_fate_count"]), 3, "the content is still listed, unheld")
	assert_eq(int(view["hidden_destiny_count"]), 3, "all three destinies too")


func test_the_counts_echo_what_the_ledger_actually_holds() -> void:
	var actor := _earned()
	var view := DestinyApi.summary(actor)
	assert_eq(bool(view["has_actor"]), true, "there is an actor")
	assert_eq(String(view["actor_id"]), "keeper", "named")
	assert_eq(int(view["fate_count"]), 2, "two fates held")
	assert_eq(int(view["destiny_count"]), 1, "one destiny held")
	assert_eq(view["counters"] as Dictionary, {String(DUELS): 2}, "and the counter, echoed")
	# The counts are read off the same ledger the facade reports, so a drift between
	# them would leave the codex header disagreeing with its own rows.
	assert_eq(int(view["fate_count"]), DestinyApi.fates(actor).size(), "fate_count matches fates()")
	assert_eq(
		int(view["destiny_count"]),
		DestinyApi.destinies(actor).size(),
		"destiny_count matches destinies()"
	)


func test_every_value_in_the_summary_is_a_primitive() -> void:
	# A panel binds to this dictionary. A `StringName`, a `Resource` or an `Actor`
	# in it is a rendering bug the type system would not catch.
	assert_eq(_primitives_only(DestinyApi.summary(_earned())), true, "the whole payload")
	assert_eq(_primitives_only(DestinyApi.summary(null)), true, "and the empty one")
	# It has to survive the hop a codex makes when it hands the view to a theme
	# file or a worker thread.
	var view := DestinyApi.summary(_earned())
	assert_ne(JSON.parse_string(JSON.stringify(view)), null, "and it is JSON-safe")


# --- Held and unheld rows -----------------------------------------------------


func test_a_held_row_says_so_and_carries_its_authored_copy() -> void:
	var view := DestinyApi.summary(_earned())
	var oath := _fate(view, String(OATH))
	assert_eq(bool(oath["held"]), true, "the fate is held")
	assert_eq(String(oath["id"]), String(OATH), "named by id")
	assert_eq(String(oath["display_name"]), String(OATH), "with its authored name")
	assert_eq(String(oath["description"]), "A fixture fate.", "and its authored description")
	assert_eq(int(oath["modifier_count"]), 2, "and the two modifiers it pays out")
	assert_eq(int(oath["tier"]), 1, "with its tier")
	assert_eq(String(oath["category"]), "fixture", "and its category")
	assert_eq(oath["tags"] as Array, ["fixture"], "and its tags, as strings")


func test_an_unheld_row_says_not_held_and_shows_only_its_teaser() -> void:
	var view := DestinyApi.summary(_hero())
	var oath := _fate(view, String(OATH))
	assert_eq(bool(oath["held"]), false, "nothing is earned yet")
	# A revealed fate is listed in full whether or not it is held — that is what
	# "revealed" means, and a codex has nothing to tease about it.
	assert_eq(String(oath["display_name"]), String(OATH), "a revealed fate shows its name")
	assert_eq(String(oath["description"]), "A fixture fate.", "and its description")
	assert_eq(int(oath["modifier_count"]), 2, "what it would pay, so a player can aim")


## The spoiler boundary: a HIDDEN fate may be listed — a codex needs a silhouette
## to fill in — but neither its name nor its description may appear until it is
## earned. The teaser is the ONE text allowed through, and it goes in `description`
## because that is the field a panel already knows how to render.
func test_a_hidden_unheld_fate_shows_no_name_and_only_its_teaser_as_description() -> void:
	var view := DestinyApi.summary(_hero())
	var whisper := _fate(view, String(WHISPER))
	assert_eq(bool(whisper["visible"]), true, "a hidden fate is still listed")
	assert_eq(bool(whisper["held"]), false, "but it is not held")
	assert_eq(String(whisper["display_name"]), "", "and its name is withheld")
	assert_eq(String(whisper["description"]), "Something happened once.", "the teaser replaces it")
	assert_eq(
		String(whisper["description"]).contains(String(WHISPER)),
		false,
		"and the teaser does not spell the id back out"
	)
	assert_eq(String(whisper["teaser"]), "Something happened once.", "the teaser field agrees")


func test_earning_a_hidden_fate_is_what_reveals_it() -> void:
	var actor := _hero()
	var before := _fate(DestinyApi.summary(actor), String(WHISPER))
	assert_eq(String(before["display_name"]), "", "hidden while unearned")
	DestinyApi.earn_fate(actor, WHISPER, "story")
	var after := _fate(DestinyApi.summary(actor), String(WHISPER))
	assert_eq(bool(after["held"]), true, "held once earned")
	assert_eq(String(after["display_name"]), String(WHISPER), "and named")
	assert_eq(String(after["description"]), "A fixture fate that grants nothing.", "in full")
	# The hidden counter falls by exactly one when the fate is earned: a held fate is
	# no longer one of the silhouettes waiting to be filled in. Three fates are
	# listed (GHOST is teaser-visibility and omitted) and only WHISPER is held, so
	# two are still counted.
	assert_eq(
		int(DestinyApi.summary(actor)["hidden_fate_count"]),
		2,
		"one fewer than before, and still both unheld listed fates"
	)


## `teaser` visibility is the third level and it is ABSENCE, not redaction. A
## hidden row carries a teaser so a codex can draw a silhouette; a teaser row has
## nothing to draw, so listing it — even with its name blanked — would tell the
## player that a fate exists.
func test_a_teaser_visibility_fate_is_absent_from_the_summary_entirely() -> void:
	for view in [DestinyApi.summary(_hero()), DestinyApi.summary(_earned())]:
		var fates := view["fates"] as Dictionary
		assert_eq(
			fates.has(String(GHOST)),
			false,
			"no row for a teaser-visibility fate, and the rows are %s" % str(fates.keys())
		)
		assert_eq(
			String(JSON.stringify(fates)).contains(String(GHOST)),
			false,
			"nor any mention of its id anywhere in the payload"
		)
	# Even an EARNED teaser fate is omitted: visibility governs the listing, and the
	# earn path has no special case for it.
	var actor := _earned()
	DestinyApi.earn_fate(actor, GHOST, "dream")
	assert_eq(
		(DestinyApi.summary(actor)["fates"] as Dictionary).has(String(GHOST)),
		false,
		"earning one does not put it in the codex"
	)


func test_the_hidden_counts_cover_every_listed_row_the_actor_has_not_earned() -> void:
	# Nothing held: every visible row is still owed.
	var empty := DestinyApi.summary(_hero())
	var fates := empty["fates"] as Dictionary
	var destinies := empty["destinies"] as Dictionary
	assert_eq(int(empty["hidden_fate_count"]), fates.size(), "every listed fate is unheld")
	assert_eq(int(empty["hidden_destiny_count"]), destinies.size(), "and every listed destiny")
	# The held ones fall out of the count, one for one.
	var full := DestinyApi.summary(_earned())
	assert_eq(
		int(full["hidden_fate_count"]),
		(full["fates"] as Dictionary).size() - 2,
		"two fates are held, so two fewer are hidden"
	)
	assert_eq(
		int(full["hidden_destiny_count"]),
		(full["destinies"] as Dictionary).size() - 1,
		"and one destiny"
	)


# --- What is still owed, and what is holding it back --------------------------


func test_an_unearned_destiny_reports_what_is_holding_it_back() -> void:
	var view := DestinyApi.summary(_hero())
	var apprentice := _destiny(view, String(APPRENTICE))
	assert_eq(bool(apprentice["held"]), false, "it was not earned")
	assert_eq(bool(apprentice["available"]), false, "and it is not available")
	var blocked = apprentice["blocked_by"] as Array
	assert_eq(blocked.size(), 1, "one thing stands in the way")
	assert_eq(String(blocked[0]["kind"]), "fate", "a fate")
	assert_eq(String(blocked[0]["id"]), String(SEAL), "named")
	assert_eq(String(blocked[0]["label"]), "Requires the fate 't_sealed_blood'", "with a label")
	# The row a panel would render is the same shape a gate refuses with, so the
	# codex does not re-derive the reason.
	assert_eq(
		blocked,
		DestinyGate.unmet_prerequisites(
			DestinyApi.state(_hero()), FateCatalog.instance().destiny_definition(APPRENTICE)
		),
		"and it is exactly what the gate reports as unmet"
	)


func test_a_destiny_is_available_once_nothing_is_holding_it_back() -> void:
	var actor := _hero()
	assert_eq(
		bool(_destiny(DestinyApi.summary(actor), String(APPRENTICE))["available"]),
		false,
		"blocked while the fate is unheld"
	)
	DestinyApi.earn_fate(actor, SEAL, "story")
	var row := _destiny(DestinyApi.summary(actor), String(APPRENTICE))
	assert_eq(bool(row["available"]), true, "available once it is held")
	assert_eq(row["blocked_by"] as Array, [], "with nothing outstanding")
	# And it really is available, not merely reported so: the facade agrees.
	assert_eq(
		DestinyGate.earnable(
			DestinyApi.state(actor), FateCatalog.instance().destiny_definition(APPRENTICE)
		),
		true,
		"and the gate the earn path uses agrees"
	)
	# `SEAL` is HIDDEN, and holding it is exactly what un-hides it — the earn is the
	# only thing that reveals it, which is why the same fate is listed-but-blank
	# above and named here.
	assert_eq(bool(_fate(DestinyApi.summary(actor), String(SEAL))["held"]), true, "SEAL is held")
	assert_eq(
		String(_fate(DestinyApi.summary(actor), String(SEAL))["display_name"]),
		String(SEAL),
		"and holding it revealed it"
	)


func test_a_held_destiny_carries_its_bearing_and_owes_nothing_further() -> void:
	var view := DestinyApi.summary(_earned())
	var chosen := _destiny(view, String(CHOSEN))
	assert_eq(bool(chosen["held"]), true, "the destiny is held")
	assert_eq(
		String(chosen["bearing"]), "You are bound to t_chosen_one.", "with its authored bearing"
	)
	assert_eq(String(chosen["display_name"]), String(CHOSEN), "and its authored name")
	# `available` / `blocked_by` are folded in only for the UNHELD ones: a destiny
	# already earned has nothing outstanding, so the pair would be dead weight on
	# every row a player already owns.
	assert_eq(
		chosen.has("available"), false, "a held destiny does not carry the availability pair at all"
	)
	assert_eq(chosen.has("blocked_by"), false, "neither half of it")


func test_an_unearned_destiny_with_no_prerequisites_is_available_and_owes_nothing() -> void:
	var row := _destiny(DestinyApi.summary(_hero()), String(RISEN))
	assert_eq(bool(row["available"]), true, "nothing stands in its way")
	assert_eq(row["blocked_by"] as Array, [], "and nothing to render")
	assert_eq(String(row["bearing"]), "", "an unearned destiny has no bearing yet")
	# The exclusivity half is a prerequisite too, and it reaches the same pair: a
	# branch closed by a held sibling is blocked, not merely unearnable.
	var closed := _hero()
	DestinyApi.earn_destiny(closed, CHOSEN, "story")
	assert_eq(
		DestinyApi.earn_destiny(closed, RISEN, "story"),
		DestinyApi.state(closed),
		"the sibling branch is still refused by the earn path"
	)


func test_the_summary_reads_the_ledger_rather_than_the_trait_mirror() -> void:
	# The mirror is derived and can be stale for an instant; the ledger is the only
	# truth (ADR 0065). A summary that read the mirror would report a held fate the
	# moment one was added and before the ledger was persisted.
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	assert_eq(actor.traits.has(DestinyState.trait_for(OATH)), true, "the mirror has it")
	actor.set_module_data(MODULE_KEY, DestinyState.empty())
	assert_eq(
		bool(_fate(DestinyApi.summary(actor), String(OATH))["held"]),
		false,
		"with the ledger cleared and the mirror still set, the codex reports nothing held"
	)


func _primitives_only(value) -> bool:
	if value is String or value is StringName or value is float or value is int or value is bool:
		return true
	if value is Array:
		for entry in value as Array:
			if not _primitives_only(entry):
				return false
		return true
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			if not (key is String) or not _primitives_only((value as Dictionary)[key]):
				return false
		return true
	return false
