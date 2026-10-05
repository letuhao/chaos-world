extends TestCase

## `lifespan` is AUTHORED, CONTRIBUTED, PUBLISHED — and INERT. This file states those
## four facts as tests and names what the fourth one would need (BL-0772).
##
## ## Why this is a separate file and not a paragraph in a content suite
##
## ADR 0062's Context lists the questions a race answers in combat and at every
## breakthrough, and one of them is *"how long does it live"*. The answer is on every
## `.tres`. Nothing in the game asks the question.
##
## A test that only asserted "authored" and "contributed" would read like enforcement
## and be none, which is the failure mode this file exists to make impossible. So the
## claim is the whole pipeline: published on every surface a future system could
## consume, and read by nothing that ages anyone.
##
## ## What was measured before any of this was written
##
## `grep -n "RaceStats.LIFESPAN\|race_lifespan" game/src` over the whole tree returns
## **three** hits, all in this module and all writes or a probe name:
##
## - `race/stats.gd:23` — the constant's own declaration.
## - `race/provider.gd:44` — the single `contribute` line that writes it.
## - `race/provider.gd:67` — the string `"race_lifespan_probe"`, an `Actor.new` id for
##   the one-collection bridge `RealmLifespan` reads. A name, not a read.
##
## So the stat has no production reader at all, and the exposure is narrower than the
## backlog entry recorded: not even the character-creation screen renders it (see
## `test_the_only_production_reader_reads_the_name_and_the_paths` below, which is a
## statement about today that is expected to become wrong the moment a panel formats
## the number).
##
## There is no `age` field anywhere to compare it against: `grep` for `age_days`,
## `age_years`, `elapsed_days`, `born_year`, `born_on` over `game/src` returns zero
## hits, and the only `age` in the tree is `FightLoop.age(delta)` (a combat rate gate),
## `BossEncounter.age(delta)` (the same thing behind the module seam), and
## `SocialBond.age` (a bond-strengthening counter). None is an age. `Actor.to_dict()`
## serializes none. That absence is BL-0037 and belongs to whoever owns time — this
## suite asserts it is still absent so the gap cannot close quietly.


## Every authored race publishes its lifespan on the read model, which is where a time
## system would take it from.
##
## `RaceApi.summary` is what production already calls
## (`app/character_creation_flow.gd:472,477`), it is the module's only screen-facing
## surface, and it carries `lifespan` in two places: the top-level value for the
## actor's own body (`api.gd:158`) and the per-race row a picker reads
## (`api.gd:197`). A clock that wanted a lifespan would take it from here without this
## module growing a new verb — so this is the shape worth pinning.
##
## Asserted against the catalog rather than a literal count, and with a floor, because
## a call that stopped publishing would leave an empty dictionary on a smaller roster
## and still look like a loop that ran.
func test_every_authored_race_publishes_its_lifespan_on_the_summary() -> void:
	var catalog := RaceCatalog.instance()
	var races := RaceApi.summary(null).get("races", {}) as Dictionary
	assert_eq(
		races.size(), catalog.race_ids().size(), "the summary row exists for every authored race"
	)
	var published := 0
	for race_id in catalog.race_ids():
		var def := catalog.race_definition(race_id)
		var row := races[String(race_id)] as Dictionary
		# Not "equals the authored value" alone: the point is that a CONSUMER can
		# find a number, so an absent key is the failure, whatever the number is.
		assert_eq(row.has("lifespan"), true, "'%s' publishes a lifespan in its row" % [race_id])
		assert_almost_eq(
			float(row.get("lifespan", -1.0)),
			def.lifespan,
			"'%s' publishes the lifespan its author wrote" % [race_id]
		)
		if float(row.get("lifespan", 0.0)) > 0.0:
			published += 1
	assert_eq(
		published, catalog.race_ids().size(), "and every published lifespan is a real duration"
	)


## The actor's OWN lifespan is published too, and the no-actor shape says `0.0`
## rather than omitting the key — a screen that formats a number needs the key to be
## there before it needs it to be right, and `summary` is a read model, not a query.
func test_the_actors_own_lifespan_is_published_and_the_no_actor_shape_is_explicit() -> void:
	var catalog := RaceCatalog.instance()
	var body := catalog.baseline_race()
	var actor := Actor.new(&"lifespan_reader")
	RaceApi.attach(actor)
	RaceApi.set_race(actor, body)

	assert_almost_eq(
		float(RaceApi.summary(actor).get("lifespan", -1.0)),
		(catalog.race_definition(body)).lifespan,
		"'%s' reports its own authored lifespan" % [body]
	)
	# With no actor there is no body, so there is no lifespan — and the key is present
	# at `0.0` rather than missing, which is `api.gd:133`'s authored default.
	var empty := RaceApi.summary(null)
	assert_eq(empty.has("lifespan"), true, "the no-actor shape still carries the key")
	assert_almost_eq(float(empty.get("lifespan", -1.0)), 0.0, "at zero, not absent")


## **The gap, stated as an assertion: nothing ages the actor, so the number is inert.**
##
## A test cannot prove a negative about the whole engine, so this proves the
## PRECONDITION a lifespan would need — somewhere for an age to live — and names what is
## missing. The alternative, asserting that `race_lifespan` has no reader, would have to
## reach through the facade into `ActorStats` and `StatContext` internals, and would
## break on a rename without catching anything a grep does not.
##
## ## This is designed to go RED when BL-0037 lands, and that is the point
##
## The day a clock adds an age field, this returns false and the test fails. That is the
## correct outcome: the assertion stops being true, and whoever lands the clock has to
## come here and decide what replaces it. A gap should become a failing test the day
## it stops being a gap, rather than drift quietly closed.
##
## The fields named are the ones a time system would author. They are a LIST rather
## than a single name because the schema is deliberately undecided — pinning one would
## be guessing at BL-0037's answer from the outside.
func test_nothing_ages_an_actor_so_the_lifespan_it_publishes_changes_nothing() -> void:
	for race_id in _catalog().race_ids():
		assert_ne(
			(_catalog().race_definition(race_id)).lifespan,
			0.0,
			"'%s' authors a lifespan" % [race_id]
		)
		assert_eq(
			_no_age_field_on(_born_into(race_id)),
			true,
			"'%s' has no age to be outlived by, so its lifespan is inert" % [race_id]
		)


## Whether this actor carries a field an age could be kept in at all.
##
## Deliberately mechanical and deliberately narrow: it asks whether a lifespan COULD be
## compared against anything today, which is the precondition for the stat meaning
## anything. `Actor` is not a Dictionary, so `in` is the engine's own property probe.
func _no_age_field_on(actor: Actor) -> bool:
	for field in ["age", "age_days", "age_years", "elapsed_days", "born_year", "born_on"]:
		if field in actor:
			return false
	return true


## ## The one production reader of `RaceApi.summary`, and what it reads.
##
## `character_creation_flow.gd` is the only caller in `game/src` (`:472`, `:477`), and it
## reads two things off a null-actor row: `display_name` and `closed_paths`. It does not
## read `lifespan` — nothing does.
##
## ## What this test does and does NOT claim
##
## **It claims only where the number is NOT published today**, so the report stays
## accurate and the next agent does not go looking for a reader that is not there. It
## deliberately does NOT grep the source: a text search for `"lifespan"` would match the
## `RaceApi.summary` call line itself and prove nothing about what the caller reads.
##
## **It will go red the moment a panel formats the number, and that red is correct.** A
## character-creation screen that shows a body its lifespan is an improvement over one
## that does not, and it would make this suite's headline claim — "published, read by
## nothing" — false in exactly the way the file exists to prevent. The replacement is
## one line: move `lifespan` from the unused list to the used list.
func test_the_only_production_reader_reads_the_name_and_the_paths() -> void:
	var flow := FileAccess.get_file_as_string("res://src/app/character_creation_flow.gd")
	assert_eq(_read_summary_keys(flow).size() > 0, true, "the flow reads summary rows at all")
	var read := _read_summary_keys(flow)
	for key in ["display_name", "closed_paths"]:
		assert_eq(read.has(key), true, "the flow reads '%s'" % [key])
	for key in ["lifespan", "realm_ceiling"]:
		assert_eq(read.has(key), false, "and does NOT read '%s' yet" % [key])


## The row keys the creation flow pulls off a `RaceApi.summary` row.
##
## The regex is anchored on `view.get(` rather than on the literal key, so it reads the
## value a caller asks FOR and not the shape of the dictionary that hands it over. It is
## scanned with `search_all` rather than `search` because the flow has two call sites and
## the claim is about both — `search` alone would report only the first, and a half-read
## would pass this suite for the wrong reason.
func _read_summary_keys(source: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var key_pattern := RegEx.create_from_string('view\\.get\\(\\s*"([a-z_]+)"')
	for hit in key_pattern.search_all(source):
		var key := StringName(hit.get_string(1))
		if not out.has(key):
			out.append(key)
	return out


# --- Helpers -----------------------------------------------------------------


func _catalog() -> RaceCatalog:
	return RaceCatalog.instance()


func setup() -> void:
	RaceFixtureCatalog.teardown()
	# `tests/framework.gd:113-120`: the floor is per SUITE and is declared in `setup`
	# (the runner calls `_test_begin` first, so this is a reset and then the floor). It
	# is the smallest floor every body in this file clears, so a body that aborts on its
	# first line is charged a failure rather than reporting green having proved nothing.


## A bare actor born into `race_id`, with no build of its own — so every number read off
## it is the body plan's contribution and nothing else.
func _born_into(race_id: StringName) -> Actor:
	var actor := Actor.new(&"lifespan_probe")
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	return actor
