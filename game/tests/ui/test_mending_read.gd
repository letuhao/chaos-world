extends TestCase

## BL-0951 / ADR 0939, S15: the shared mending read — the whole web in one place.
##
## The read names the actor's WEAKEST scar and one row per avenue, so a foundation readout
## can render what is available and at what price while each avenue's INVOCATION stays in its
## own screen. It is the composition root's read (only `app/` may name every module), so this
## drives it directly rather than through a screen.

const LIFESPAN_DAYS := 36500.0

const AVENUES: Array[String] = [
	"miracle_elixir",
	"heaven_defying_rite",
	"forbidden_lifespan_art",
	"karmic_virtue",
	"secret_realm",
	"master_sacrifice",
	"dual_cultivation_aid",
	"rebirth",
]


func _hero() -> Actor:
	var actor := Actor.new(&"mending_hero", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0})
	FoundationApi.snapshot(actor, &"qi_refining", 0.1)
	return actor


func _row(read: Dictionary, id: String) -> Dictionary:
	for row in read.get("avenues", []):
		if String((row as Dictionary).get("id", "")) == id:
			return row
	return {}


func test_a_null_actor_reads_empty() -> void:
	assert_eq(MendingRead.for_actor(null), {}, "no actor, no read")


func test_a_fresh_actor_has_no_scar_to_mend() -> void:
	var actor := Actor.new(&"fresh", {Stat.PHYSIQUE: 10.0})
	assert_eq(
		int(MendingRead.for_actor(actor).get("count", -1)), 0, "nothing left, nothing to mend"
	)


func test_the_read_names_the_scar_and_every_avenue() -> void:
	var read := MendingRead.for_actor(_hero())
	assert_eq(String(read.get("scar", "")), "qi_refining", "the weakest scar is named")
	assert_eq(int(read.get("count", -1)), AVENUES.size(), "all eight avenues are listed")
	var ids: Array = []
	for row in read.get("avenues", []):
		ids.append(String((row as Dictionary).get("id", "")))
	for expected in AVENUES:
		assert_eq(ids.has(expected), true, "avenue '%s' is listed" % expected)


## The forbidden art is the avenue whose availability the read can decide from the actor
## alone, and it is the one the final band closes (S6): available before, refused inside.
func test_the_forbidden_art_reads_available_off_the_final_band() -> void:
	var actor := _hero()
	actor.stats.add_modifier(
		StatModifier.new(&"race_lifespan", Stat.Op.FLAT, LIFESPAN_DAYS, &"test")
	)
	assert_eq(
		bool(_row(MendingRead.for_actor(actor), "forbidden_lifespan_art").get("available", false)),
		true,
		"available before the final band"
	)
	actor.age_years = 0.9 * LIFESPAN_DAYS / 365.0
	assert_eq(
		AgeBandTable.band_for_actor(actor),
		AgeBandTable.LASTLIGHT,
		"the fixture is in the last band"
	)
	assert_eq(
		bool(_row(MendingRead.for_actor(actor), "forbidden_lifespan_art").get("available", true)),
		false,
		"and refused inside it"
	)


## The avenues that need a partner, a mentor or a site read unavailable and SAY why, rather
## than pretending — the three-state vocabulary (ADR 0083) applied to the web.
func test_the_avenues_needing_another_read_unavailable_with_a_note() -> void:
	var read := MendingRead.for_actor(_hero())
	for id in ["secret_realm", "master_sacrifice"]:
		var row := _row(read, id)
		assert_eq(bool(row.get("available", true)), false, "'%s' needs another party" % id)
		assert_eq(String(row.get("note", "")).is_empty(), false, "and '%s' says what it needs" % id)


func test_the_read_is_json_clean() -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(MendingRead.for_actor(_hero())))
	assert_eq(parsed is Dictionary, true, "the read is primitives only")
