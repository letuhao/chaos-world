extends TestCase

## The SHAPE of one row in `DestinyApi.summary()`'s codex payload.
##
## `test_destiny_summary.gd` owns what a row SAYS. This file owns what a row
## CARRIES — the key set and the reveal rules — and it exists because
## `DestinyApi._destiny_view` did not publish `teaser` at all while
## `DestinyBranchRow._teaser()` read `_view.get("teaser", "")` and fell through
## to `description`. Nothing failed, because for an unheld HIDDEN branch
## `description` is written to be the teaser: the fall-through returned the
## right string by accident. That is a masked hole, not an absent one, and it
## opens the first time a hidden destiny is authored with an EMPTY `teaser` —
## `description` is then `""` too, and the codex renders a blank card for a
## branch whose whole job is to hint.
##
## The masked kind is the dangerous kind, and it is worth being precise about
## why it hid for as long as it did: the missing key produced the CORRECT
## output under the authored content that shipped. A test that only checked
## output would never see it. So the contract pinned here is the key set and the
## teaser VALUE, which is the part that survives the next content drop.
##
## `_fate_view` already published `teaser`, which is why the row's shape looked
## symmetric on paper — the asymmetry was in one function of one facade.

const FATE := &"t_shaped_fate"
const DESTINY := &"t_shaped_destiny"
const HIDDEN_DESTINY := &"t_shaped_hidden"
const BLANK_TEASER_DESTINY := &"t_shaped_blank_teaser"
const TEASER_ONLY_DESTINY := &"t_shaped_never_shown"

## The teaser the hidden fixture is authored with. Spelled as a constant so an
## assertion can name the string it expects rather than repeat it.
const HIDDEN_TEASER := "A shape worth hiding."
const BLANK_TEASER := ""


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[DestinyFixtureCatalog.story_fate(FATE)],
			[
				DestinyFixtureCatalog.plain_destiny(DESTINY),
				_hidden_destiny(HIDDEN_DESTINY, HIDDEN_TEASER),
				# THE REGRESSION CASE. Teaser visibility with an empty teaser: every
				# masking coincidence in the original defect holds here too
				# (description is the teaser, and the teaser is empty), so an
				# output-only assertion sees nothing wrong. The key set is the
				# only thing that can tell.
				_hidden_destiny(BLANK_TEASER_DESTINY, BLANK_TEASER),
				# `teaser` visibility: filtered out of `summary()` entirely, so the
				# assertions below never see it. Present to prove the filter still
				# holds rather than assuming it.
				_never_shown_destiny(TEASER_ONLY_DESTINY),
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


## `_destiny_view` publishes `teaser`, and publishes it on EVERY destiny row —
## revealed, held and hidden alike.
##
## The first assertion is the whole point of this file: the key was absent, and
## an absent key is the one thing a `.get(..., default)` silently tolerates.
func test_every_destiny_row_publishes_a_teaser_key() -> void:
	var view := DestinyApi.summary(_hero())
	for destiny_id in (view["destinies"] as Dictionary).keys():
		var row: Dictionary = (view["destinies"] as Dictionary)[destiny_id]
		assert_eq(
			row.has("teaser"),
			true,
			(
				(
					"destiny row '%s' publishes a 'teaser' key — the codex row reads it with a "
					+ "default, so a missing key is invisible to every consumer but this one"
				)
				% [destiny_id]
			)
		)


## A hidden branch's teaser is the AUTHORED teaser, and it is the same string
## `description` carries while the branch is locked.
##
## This is precisely why the missing key was masked, and it is pinned on both
## sides so the masking is documented rather than left to be re-discovered: if a
## future change makes `description` say something else while locked, THIS
## assertion fails and the row's real source of truth is noticed.
func test_a_hidden_branch_carries_its_authored_teaser() -> void:
	var row := _destiny(DestinyApi.summary(_hero()), HIDDEN_DESTINY)
	assert_eq(row["teaser"], HIDDEN_TEASER, "the hidden branch publishes its authored teaser")
	assert_eq(
		row["description"],
		HIDDEN_TEASER,
		"and while locked `description` is that same teaser, which is what masked the missing key"
	)


## THE REGRESSION. A hidden branch with an EMPTY teaser must publish an empty
## `teaser` — not fall back to `description`, and not omit the key.
##
## Under the defect this destination row carried no `teaser` at all, and its
## `description` was `""` as well, so a consumer reading either got an empty
## string and no way to tell "authored nothing" from "the facade forgot". The
## row renders a blank card either way; the difference is that the code can now
## tell, and this test says so.
func test_a_hidden_branch_with_an_empty_teaser_still_publishes_the_key() -> void:
	var row := _destiny(DestinyApi.summary(_hero()), BLANK_TEASER_DESTINY)
	assert_eq(
		row.has("teaser"),
		true,
		"an empty authored teaser still publishes the KEY, so 'authored nothing' is distinguishable"
	)
	assert_eq(row["teaser"], BLANK_TEASER, "and its value is the authored empty teaser")
	assert_eq(
		bool(row["held"]),
		false,
		"the branch is unheld, so nothing about its row depends on an earn having happened"
	)


## A REVEALED branch publishes a teaser too — the key is present on every row,
## not just the hidden ones.
##
## `_fate_view` has always done this, so the two codex rows now agree on what a
## view carries. A `.get()` consumer cannot tell these apart from the outside, so
## the symmetry is a contract rather than a convenience.
func test_a_revealed_branch_publishes_its_teaser_too() -> void:
	var row := _destiny(DestinyApi.summary(_hero()), DESTINY)
	assert_eq(row.has("teaser"), true, "a revealed branch publishes a 'teaser' key as well")
	assert_eq(
		row["teaser"],
		BLANK_TEASER,
		"and `plain_destiny` authors no teaser, so the value is the empty string, not the description"
	)


## The keys the codex row reads are ALL present on every destiny row — the
## shape as an INCLUSION, not an equality.
##
## `DestinyBranchRow.show_destiny` documents this row as
## `{id, held, group, display_name, description, bearing, grants_fate_count}` —
## which is the list as it stood BEFORE `teaser` was published, and is the second
## half of why the hole survived: the row's own docstring agreed with the
## facade's actual output, because neither of them mentioned the key the other
## one read.
##
## **Inclusion, deliberately, not an exact set.** `summary()` folds `available`
## and `blocked_by` onto an UNHELD destiny AFTER `_destiny_view` returns
## (`api.gd:288-290`), so a held row and an unheld one do not carry the same
## keys — which is exactly the "use `.get()`" caveat ADR 0134's `summary` row
## states. Pinning an exact set would have to pick one of the two shapes or
## forbid a key the facade is documented to add. The property worth pinning is
## the one that actually broke: a key the consumer reads is present rather than
## silently defaulted. `test_every_destiny_row_publishes_a_teaser_key` pins that
## one key exactly; this asserts the rest of the row's vocabulary still resolves.
func test_the_destiny_row_carries_the_keys_the_codex_row_reads() -> void:
	var row := _destiny(DestinyApi.summary(_hero()), DESTINY)
	for key in [
		"id",
		"held",
		"visible",
		"group",
		"display_name",
		"description",
		"teaser",
		"bearing",
		"grants_fate_count",
	]:
		assert_eq(row.has(key), true, "a destiny row publishes '%s'" % [key])


## A held branch reveals its real description and STILL publishes the teaser.
##
## `reveal` is true once held, so `description` stops being the teaser. If the
## two keys ever collapse — the failure mode a "just reuse description" fix would
## introduce — this assertion is what notices.
func test_holding_a_branch_reveals_the_description_but_keeps_the_teaser_key() -> void:
	var hero := _hero()
	DestinyApi.earn_destiny(hero, HIDDEN_DESTINY, "story")
	var row := _destiny(DestinyApi.summary(hero), HIDDEN_DESTINY)
	assert_eq(
		row["description"],
		"A fixture destiny.",
		"holding a hidden branch reveals its real description"
	)
	assert_eq(
		row["teaser"],
		HIDDEN_TEASER,
		"and the teaser is still published beside it, ungated — _fate_view publishes it the same way"
	)


## The reason matters and the filter still holds: a `teaser`-visibility destiny
## never reaches `summary()` at all, so none of the assertions above can see
## this one. Asserted so "every row publishes teaser" is not read as "a hidden
## branch can be seen at all".
func test_a_teaser_visibility_destiny_is_still_absent_from_the_summary() -> void:
	var view := DestinyApi.summary(_hero())
	assert_eq(
		(view["destinies"] as Dictionary).has(TEASER_ONLY_DESTINY),
		false,
		"a `teaser`-visibility destiny is filtered out of the summary entirely, earned or not"
	)


# --- Helpers ------------------------------------------------------------------


## The teaser-bearing fixture, built here rather than through the shared
## catalog helper because `DestinyFixtureCatalog` has no hidden-destiny builder:
## adding one would touch a file this suite does not own, and the only consumer
## that needs it is here.
func _hidden_destiny(destiny_id: StringName, teaser: String) -> DestinyDef:
	var def := DestinyFixtureCatalog.plain_destiny(destiny_id)
	def.visibility = DestinyDef.HIDDEN
	def.teaser = teaser
	return def


func _never_shown_destiny(destiny_id: StringName) -> DestinyDef:
	var def := DestinyFixtureCatalog.plain_destiny(destiny_id)
	def.visibility = DestinyDef.TEASER
	def.teaser = "Never shown."
	return def


func _hero(actor_id: StringName = &"shaped") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


## The row for `destiny_id`, asserting it is present BEFORE reading it, so a
## filtered-out fixture fails with a name instead of a null access.
func _destiny(view: Dictionary, destiny_id: StringName) -> Dictionary:
	var destinies := view["destinies"] as Dictionary
	var row = destinies.get(String(destiny_id), null)
	if row is Dictionary:
		return row as Dictionary
	assert_eq(destiny_id in destinies, true, "the summary lists a row for '%s'" % [destiny_id])
	return {}
