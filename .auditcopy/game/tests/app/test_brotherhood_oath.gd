extends TestCase

## ## The app-layer verb's vocabulary is AUTHORED, and its ids are reachable in production
##
## `BrotherhoodOathApp` is the only place `npc/` and `social/` are allowed to meet (both
## facades are at their cap, and `social/` may not name `npc/`), so it is where a cause
## id can be written that the catalog does not ship. `SocialApi.apply_cause` answers
## `unknown_cause` for such an id — a bridge built on unauthored vocabulary refuses at
## play time, which is the inert-vocabulary defect in its worst form: the code reads
## correct and the feature never fires.
##
## This suite pins the two halves of "the verb is wired": every id it can apply is
## authored, and every id it can apply is applied by **some** path here — so a future
## refactor cannot silently re-block `sworn` by dropping the call that writes it.

const ELDER := &"elder_wei"


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)


## ## Every cause the verb can apply is authored, and none is the promotion.
##
## `promotes_to` is read off the def rather than hardcoded, so this asserts the SHIPPED
## authoring and not a restatement of it. Delete `"promotes_to"` from
## `shared_brotherhood` in the catalog and this is red — which is the guard against the
## ladder's top rung being silently renamed into a dead rung.
func test_every_cause_the_verb_applies_is_authored_and_sworn_promotes() -> void:
	var catalog := SocialCauseCatalog.instance()
	for cause_id in BrotherhoodOathApp.cause_ids():
		assert_ne(
			catalog.cause_definition(cause_id),
			null,
			"'%s' is applied by BrotherhoodOathApp and must exist in the catalog" % String(cause_id)
		)
	var sworn := catalog.cause_definition(BrotherhoodOath.CAUSE_SWORN)
	assert_ne(sworn, null, "the promotion cause is authored")
	assert_eq(
		sworn.promotes_to,
		SocialBondClass.SWORN,
		"and it still names the top rung — the promise is what makes the act reach it"
	)


## ## `shared_brotherhood` has a PRODUCTION producer, at last.
##
## The finding BL-0745 recorded was that this cause existed in the catalog with no
## producer anywhere in `game/src` outside tests. This scans the production tree for the
## id and asserts the only writer is `BrotherhoodOath.swear_brotherhood` — which is what
## "reachable by a player, through production" means as a fact about the tree rather
## than about one test.
func test_shared_brotherhood_has_a_production_producer_and_not_only_tests() -> void:
	var producers: Array[String] = []
	for path in ContentScan.files_under("res://src/", ".gd"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("BrotherhoodOath.CAUSE_SWORN"):
			producers.append(path)
	assert_eq(
		producers.size(),
		1,
		(
			"exactly one production site writes the cause, and it is the exchange. Found: %s"
			% str(producers)
		)
	)
	assert_eq(
		producers[0],
		"res://src/modules/social/social_brotherhood.gd",
		"which is BrotherhoodOath — not a test, and not a facade nobody reaches"
	)


## ## The cause is applied only ONCE per answer, so the top rung is not re-mintable.
##
## Restated at the `app/` layer because this is where the trust boundary sits: a verb a
## panel can call twice is a verb that grants the top of the ladder twice, and the only
## thing standing between a player and that is the anti-repeat rule the second call
## hits.
func test_the_production_verb_applies_the_promise_exactly_once() -> void:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	NpcApi.spawn(ELDER)
	for cause_id in [
		&"helped_in_combat", &"spared_in_combat", &"taught_technique", &"protected_from_death"
	]:
		SocialApi.apply_cause(player, ELDER, cause_id)

	assert_eq(BrotherhoodOathApp.offer(player, ELDER)["outcome"], "accepted", "sworn")
	var second := BrotherhoodOathApp.offer(player, ELDER)
	assert_eq(second["ok"], false, "a second press is refused")
	assert_eq(
		SocialApi.social_state(player).bond(ELDER).causes.get("shared_brotherhood", 0),
		1,
		"and the promise is on the ledger exactly once"
	)


## ## A read on an id this process holds no body for refuses, and says which.
##
## The read model a panel polls is a read and must never invent an affordance: an empty
## answer would grey nothing out and let the player press a verb that will refuse.
func test_the_read_model_refuses_an_unknown_npc_rather_than_reading_empty() -> void:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	var read := BrotherhoodOathApp.read(player, &"nobody_at_all")
	assert_eq(read["ok"], false, "no body, no oath")
	assert_eq(read["reason"], "unknown_npc", "naming itself")
	assert_eq(read["will_swear"], false, "and the reckoning is absent, not optimistic")
