extends TestCase

## DEF-0315: `EventApi.resolve` had ZERO production callers, so a declared sect war could
## never be settled — no shipped moment named a winner, and ADR 0085 forbids the political
## layer deciding one.
##
## The moment now ships as CONTENT: the tournament's final stage authors a `resolves`
## verdict, and the director delivers it through `EventApi.resolve` at the end of the
## advance that reaches it. So a contest that RAN elsewhere names the winner, which is
## exactly "a verdict arrives from outside".

const WAR := &"war_of_the_nine_fords"
const TOURNAMENT := &"tournament_of_the_spirit_peaks"
const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"


func _actor() -> Actor:
	var actor := Actor.new(&"t_verdict_actor", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	NationApi.attach(actor)
	EventApi.attach(actor)
	NationApi.found(actor, MARCH, String(actor.id))
	EventApi.set_location(actor, &"mortal_plains")
	return actor


## The shipped war declares a standoff against the Court of the Star.
func test_the_war_opens_and_declares() -> void:
	var actor := _actor()
	WorldFact.record(actor, &"sect_war_called", 1)
	var war := EventApi.begin(actor, WAR, 0)
	assert_eq(bool(war["ok"]), true, "the war opens: %s" % str(war))
	assert_eq(bool(war.get("declared", false)), true, "and declares its standoff")


## The tournament's final stage delivers a verdict to the open war through
## `EventApi.resolve` — the caller that verb never had.
func test_the_tournament_final_delivers_a_verdict() -> void:
	var actor := _actor()
	WorldFact.record(actor, &"sect_war_called", 1)
	assert_eq(bool(EventApi.begin(actor, WAR, 0)["ok"]), true, "the war opens")

	# The war stays open when the hero travels, so the tournament can run at the peaks.
	EventApi.set_location(actor, &"spirit_peaks")
	WorldFact.record(actor, &"tournament_called", 1)
	assert_eq(
		bool(EventApi.begin(actor, TOURNAMENT, 0)["ok"]), true, "the tournament opens"
	)

	# Four periods walks registered -> first_round -> final.
	var report := EventApi.advance(actor, 4)
	var verdicts := report.get("verdicts", []) as Array
	assert_eq(verdicts.is_empty(), false, "the final delivered a verdict: %s" % str(report))
	var row := verdicts[0] as Dictionary
	assert_eq(String(row["war_id"]), String(WAR), "the verdict names the war")
	assert_eq(String(row["winner_id"]), String(COURT), "for the authored winner")

	# And the verdict really reached `nation`: `resolve_conflict` accepted it.
	var outcome := row["outcome"] as Dictionary
	assert_eq(bool(outcome.get("ok", false)), true, "nation accepted the verdict: %s" % str(outcome))


## A war with no verdict authored stays open — the director does not invent a winner.
func test_a_war_without_a_verdict_stays_open() -> void:
	var actor := _actor()
	WorldFact.record(actor, &"sect_war_called", 1)
	EventApi.begin(actor, WAR, 0)
	var report := EventApi.advance(actor, 2)
	assert_eq((report.get("verdicts", []) as Array).is_empty(), true, "no verdict was delivered")
	var active := EventApi.active(actor)
	var still_open := false
	for row in active:
		if String((row as Dictionary).get("event_id", "")) == String(WAR):
			still_open = true
	assert_eq(still_open, true, "the war is still open")


## The verb settles a war directly, so the quota path is exercised end to end: five
## verdicts meet a siege's quota and the war closes.
func test_five_verdicts_settle_the_siege() -> void:
	var actor := _actor()
	WorldFact.record(actor, &"sect_war_called", 1)
	assert_eq(bool(EventApi.begin(actor, WAR, 0)["ok"]), true, "the war opens")
	var last := {}
	for index in 5:
		last = EventApi.resolve(actor, WAR, String(COURT))
	# The resolving call pays the prize through `_pay`, whose shape carries `closed`/`paid`
	# rather than `ok` — assert the flags the resolution actually reports.
	assert_eq(
		bool(last.get("closed", false)),
		true,
		"the fifth verdict closes the war: %s" % str(last)
	)
	assert_eq(bool(last.get("paid", false)), true, "and pays the declared prize")
