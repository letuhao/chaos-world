class_name SocialCauseCatalog
extends RefCounted

## The authored cause catalog (ADR 0076). Every relationship change is one of these ids,
## so the ledger is a closed vocabulary rather than an accumulating set of magic numbers.
##
## Ships with the causes the cultivation fiction actually needs. A cause is a `Resource`
## so a designer can author more; this catalog is only the default set.

static var _shared: SocialCauseCatalog = null

var _causes: Dictionary = {}


static func instance() -> SocialCauseCatalog:
	if _shared == null:
		_shared = SocialCauseCatalog.new()
		_shared._install_defaults()
	return _shared


func _install_defaults() -> void:
	_add(&"gifted_item", {"standing": 1.0, "trust": 0.02, "tags": [&"gift"]})
	_add(&"helped_in_combat", {"standing": 3.0, "trust": 0.08, "tags": [&"combat"]})
	_add(&"spared_in_combat", {"standing": 4.0, "trust": 0.1, "tags": [&"combat"]})
	_add(&"protected_from_death", {"standing": 6.0, "trust": 0.12, "persistent": true})
	_add(&"taught_technique", {"standing": 3.0, "trust": 0.06, "persistent": true})
	_add(&"honoured_a_debt", {"standing": 3.0, "trust": 0.08, "persistent": true})
	# `shared_brotherhood` is the ONLY cause in the shipped catalog that names a class,
	# and it is the only one that can reach `sworn` — the top of the ladder. Two things
	# keep that from being a shortcut to the end of the ladder, and neither is this file's
	# job: `SocialBond.apply` records the promise on the bond, and `SocialBondClass.classify`
	# honours it only once the axes have earned a confidant. A brotherhood sworn by a pair
	# the world has not seen trust in is recorded and not granted — which is the whole
	# reason `promotes_to` is a ceiling and not an outcome (BL-0659).
	#
	# **`kind` is named explicitly, and it is load-bearing rather than cosmetic.** Left to
	# the `_first_tag` fallback this cause has NO authored tag at all, so its kind became
	# its own id `shared_brotherhood` — a bucket that does not exist anywhere else in the
	# catalog — while `accepted_the_oath` / `refused_the_oath` / `witnessed_an_oath` all
	# carry `kind: oath`. The result was that four oaths filed under FOUR kinds, so
	# `SocialBondClass.FRIEND_DISTINCT_CAUSES` counted an oath farm as four different acts
	# of act and cleared a friendship. **The rule counts distinct KINDS precisely so that
	# the same act wearing two labels cannot buy a rung** (ADR 0091), so the name is
	# authored here rather than derived, and the guard is
	# `tests/modules/social/test_brotherhood_exchange.gd`
	# `::test_a_history_of_nothing_but_oaths_never_reaches_sworn`.
	_add(
		&"shared_brotherhood",
		{
			"standing": 5.0,
			"trust": 0.15,
			"persistent": true,
			"kind": &"oath",
			"tags": [&"oath", &"deed"],
			"promotes_to": SocialBondClass.SWORN
		}
	)
	_add(&"robbed", {"standing": -6.0, "tags": [&"harm"]})
	_add(&"attacked_unprovoked", {"standing": -8.0, "tags": [&"combat", &"harm"]})
	_add(&"killed_their_kin", {"standing": -10.0, "tags": [&"combat", &"harm"]})
	_add(&"betrayed_oath", {"standing": -12.0, "trust": -0.4, "tags": [&"oath", &"harm"]})
	_add(&"slandered", {"standing": -4.0, "trust": -0.12, "tags": [&"harm"]})
	_add_intimacy()
	_add_oath()
	_add_auction()
	_install_institutional()


## ## The auction causes: three acts at a sale, authored so `app/` has something to apply
##
## ADR 0102 promises the four auction signals "reach `SocialApi.apply_cause` with an
## authored cause id" — and `apply_cause` refuses `unknown_cause` for an id this catalog
## does not ship. Before these existed the bridge had nothing to apply, which is DEF-0217's
## other half: a subscriber that would refuse on every event is not a subscriber.
##
## ## Three causes for four signals, and the fourth is deliberately absent
##
## `bid_placed` gets **none**. Placing a bid is an act a player repeats freely, so a cause
## for it would be a per-click standing faucet against every counterparty in the auction —
## and `SocialBondClass.FRIEND_DISTINCT_CAUSES` counts distinct KINDS, so a bid cause in
## its own kind would make the whole ladder buyable from a merchant. The signal is recorded
## by `AuctionLedger` and credited nothing. That is ADR 0093's rule that an event announces
## a fact and the consumer decides what it is worth, taken literally.
##
## ## They share ONE kind, and that is the anti-farm rule doing its job
##
## All three carry `kind: market`, so a bidder who wins, outbids and defaults at a hundred
## auctions has still recorded **one kind of act**, and `SocialBondClass` tops that bond at
## an acquaintance however large the total. A friendship has to rest on two different acts,
## and no amount of shopping is a second one. The tag is `market` rather than `auction` so
## an author who later adds a plain trade can gate the whole commerce tier on one tag.
##
## ## The magnitudes are single figures, sized against the ladder
##
## `FRIEND_AT` is 6.0, so `won_auction` at 3.0 is one sale short of a friendship — and it
## CANNOT get there alone, because one kind is one kind. `defaulted_on_a_bid` is the harsh
## one at -6.0: a broken bid is a promise made in public and not kept, which is worse than
## `robbed` (-6.0) on a merchant and worse than `attacked_unprovoked` (-8.0) only in that
## it costs no blood. `outbid_in_auction` is small and transient (-1.5, no `persistent`):
## being outbid at a sale is ordinary commerce, and a big persistent negative would make
## winning an auction from someone a grudge instead of a rivalry.
##
## `won_auction` IS persistent — the coins have moved and the goods are delivered, so the
## sale is a fact the world keeps (ADR 0102 fires it only after both purses have settled).
func _add_auction() -> void:
	_add(
		&"won_auction",
		{
			"standing": 3.0,
			"trust": 0.05,
			"persistent": true,
			"kind": &"market",
			"tags": [&"market", &"auction", &"deed"],
		}
	)
	_add(
		&"outbid_in_auction", {"standing": -1.5, "kind": &"market", "tags": [&"market", &"auction"]}
	)
	_add(
		&"defaulted_on_a_bid",
		{
			"standing": -6.0,
			"trust": -0.1,
			"kind": &"market",
			"tags": [&"market", &"auction", &"harm"],
		}
	)


## ## `bound_in_intimacy`: the one cause that writes a PERSON'S standing for an act
## two people share
##
## Every shipped cause is an act one actor did to another: a gift, a rescue, an oath.
## Conception is the exception, and it is recorded here as an ordinary personal cause
## rather than kept out of the vocabulary, because the ledger is the only place the
## world can read "what is the history of these two" from (ADR 0091) — and a bond
## whose one permanent, un-erasable entry is missing from that ledger is a bond the
## save cannot explain.
##
## ## It is NOT institutional, and that is the whole decision
##
## `institutional` is a stored FLAG, not a tag (ADR 0091): a row carrying it is
## projected into `SocialState.regard`, which is the read model for an actor's
## standing with a SECT or a NATION. This cause's `partner_id` is a person, so the
## row must stay out of `regard` — a partner is not an institution the world holds an
## opinion about, and folding one in would make "how well is this actor regarded"
## answer a question nobody asked. `_institutional()` is therefore NOT used: the flag
## is what decides the projection, and leaving it off is a property of the call site.
##
## ## The magnitudes are sized against the ladder, not for effect
##
## Standing lands at `FRIEND_AT` (6.0) on the first application — see
## `SocialBondClass`. `Seduction.REQUIRED_STANDING` reads exactly this figure, so one
## recorded conception is what promotes the pair past the social floor the attempt
## itself demands. That is a deliberate circularity and it is the safe direction: the
## gate can only ever be opened by an act that has already happened, so conception can
## never reach a stranger and no chain of unearned attempts can walk the ladder.
##
## `persistent` is true because the act is a fact, and `SocialBond.apply` raises the
## floor on a persistent cause — so time moves this bond toward the record rather than
## back toward a stranger. `trust` is large: this is the one act that cannot be
## withdrawn or disputed, and a bond that quietly undid it would misreport the
## partner's history.
func _add_intimacy() -> void:
	_add(
		&"bound_in_intimacy",
		{
			"standing": 6.0,
			"trust": 0.5,
			"persistent": true,
			"tags": [&"intimacy"],
		}
	)


## ## The oath vocabulary: the promise, the mirror, the refusal and the witness
##
## `shared_brotherhood` itself is authored inline at the top of this file, where every
## other personal cause lives, because it predates the exchange and three tests read it
## there by name. These three are what make it **reachable**: a cause no production verb
## applies is inert vocabulary (the mirror defect), and `BrotherhoodOath` / `BrotherhoodOathApp`
## apply each of these exactly where its docstring says.
##
## ## All four share `kind: oath`, and that is the anti-farm rule doing its job
##
## An oath made, an oath answered, an oath refused and an oath witnessed are all **one
## kind of act**. So a pair whose entire relationship history is oaths — made, broken,
## renewed, refused — still tops out at an acquaintance however large the total, because
## `SocialBondClass.FRIEND_DISTINCT_CAUSES` counts distinct KINDS and that history has
## one. The ladder is climbed by deeds and gifts alongside the oath, never by the oath
## itself.
##
## ## The magnitudes are the refusal-cost argument, in data
##
## `refused_the_oath` is **-4.0 standing and -0.15 trust**. Sized against the ladder:
## - `FRIEND_AT` is 6.0, so a single refusal is a real dent in a working friendship.
## - `CONFIDANT_TRUST` is 0.5, so refusing costs **a third of the trust the player has
##   with a confidant** — a refusal is not free, and the axis it bites is the axis that
##   gates teaching and future oaths, so it compounds.
## - `CONFIDANT_AT` is 14.0, and `shared_brotherhood` itself is +5.0. So refusing cannot
##   by itself demote a confidant out of range under ordinary play — the cost is felt,
##   not fatal, which is the right register for "he said not yet" rather than "you have
##   been cast out".
##
## `accepted_the_oath` and `witnessed_an_oath` are **not persistent**: a mirror of an
## oath and a witness who stood surety are both facts that mean more than any scalar,
## and the class ladder already refuses to let an unearned oath lift a bond (that is what
## `promotes_to` being a ceiling means). Keeping them transient means the *only* promise
## that can lift a rung is `shared_brotherhood`, so a future author cannot quietly grant
## the top of the ladder by mirroring the act onto the wrong ledger.
func _add_oath() -> void:
	_add(
		&"accepted_the_oath",
		{
			"standing": 5.0,
			"trust": 0.15,
			"kind": &"oath",
			"tags": [&"oath", &"deed"],
		}
	)
	_add(
		&"refused_the_oath",
		{
			"standing": -4.0,
			"trust": -0.15,
			"kind": &"oath",
			"tags": [&"oath", &"harm"],
		}
	)
	_add(
		&"witnessed_an_oath",
		{"standing": 1.0, "trust": 0.04, "kind": &"oath", "tags": [&"oath", &"deed"]}
	)


## ## Institutional causes: the bond between an actor and an INSTITUTION
##
## ## An institution is a legal `partner_id`, and that is the whole trick
##
## `SocialBond.partner_id` is a `StringName` and `SocialApi.apply_cause` performs
## no actor-identity check, so `&"jade_court"` is already a perfectly valid partner
## (ADR 0091). A player regards a sect without having met a single member, which is
## exactly why `SocialState.regard` exists separately from bonds — so an
## institution's row IS a bond, and it carries the cause ledger that makes the
## question "why does the world think well of you here" answerable from a save.
##
## ## `institution` is a TAG, not a key
##
## Every cause below is tagged `institution` plus its kind, so an author gates on
## the KIND (`&"sect"`, `&"nation"`) rather than on a hundred membership ids, and
## the `caused_by` gate still names one exact act. Nothing here is namespaced to a
## particular sect, so `sect/` and `nation/` reach these as plain ids — the
## discipline that keeps `sect -> social` a single `preload` and every other
## identifier a string (ADR 0083's edge the checker cannot see).
##
## ## `persistent` on the ones an institution can never take back
##
## An oath sworn to a sect, a war fought for a nation and entry into a house are
## facts the world keeps after the membership ends; a resignation and an expulsion
## are the institution's verdict and decay with it. The FLOOR is the mechanism
## (ADR 0091's decay clause): `SocialBond.apply` raises the floor only on a
## persistent cause, so time moves a broken bond toward the promise it was given
## rather than back to a stranger.
##
## ## The magnitudes are deliberately SMALL
##
## ADR 0091's ladder tops out at 14 for a confidant, and the bond axis is clamped
## to [-100, 100]. A membership is one act in a ledger meant to hold a career of
## them, so these are single figures: nothing here is buyable and nothing here is
## a duplicate of the institution's own standing — that is a separate number with a
## separate owner (ADR 0083).
func _install_institutional() -> void:
	# ## Joining and leaving a sect
	#
	# `sworn_to_sect` is persistent and modest: an oath is remembered. `left_a_sect`
	# is small and transient — walking out is not a disgrace, it is a choice, and a
	# big negative would make the exit the punishing choice (ADR 0083: leaving is
	# always permitted and always costs, but the cost is the standing).
	_institutional(
		&"sworn_to_sect",
		{"standing": 2.0, "trust": 0.04, "persistent": true, "tags": [&"institution", &"sect"]}
	)
	_institutional(&"left_a_sect", {"standing": -1.0, "tags": [&"institution", &"sect"]})
	# Expulsion is the harsh one, and it is *someone else's* act: the sect decided,
	# not the member. ADR 0084 makes an inquisition a political act, and the ledger
	# has to say which of the two happened.
	_institutional(
		&"expelled_from_sect",
		{"standing": -6.0, "trust": -0.2, "tags": [&"institution", &"sect", &"harm"]}
	)
	# ## Holding office, and doing the job
	#
	# `held_office` is what a promotion MOVES: an office is public recognition, which
	# is precisely the thing ADR 0083 says is separate from the office's own
	# recognition-within-the-institution. `defended_territory` is the deed a sect
	# records publicly.
	_institutional(&"held_office", {"standing": 1.5, "tags": [&"institution", &"office"]})
	_institutional(
		&"defended_territory",
		{"standing": 3.0, "trust": 0.06, "persistent": true, "tags": [&"institution", &"deed"]}
	)
	# ## A nation
	#
	# The same four shapes, spelled for the third tier: living under a polity, the
	# polity's own verdict, holding one of its seats, and standing in a war for it.
	_institutional(
		&"lived_under_nation",
		{"standing": 1.5, "trust": 0.03, "persistent": true, "tags": [&"institution", &"nation"]}
	)
	_institutional(&"left_a_nation", {"standing": -1.0, "tags": [&"institution", &"nation"]})
	_institutional(
		&"expelled_from_nation",
		{"standing": -5.0, "trust": -0.15, "tags": [&"institution", &"nation", &"harm"]}
	)
	_institutional(
		&"held_nation_office", {"standing": 1.0, "tags": [&"institution", &"nation", &"office"]}
	)
	_institutional(
		&"fought_for_a_nation",
		{
			"standing": 3.0,
			"trust": 0.05,
			"persistent": true,
			"tags": [&"institution", &"nation", &"deed"],
		}
	)
	# ## A clan — the third leg, and the one that shipped last
	#
	# ADR 0064 calls a clan's relationship to a member "a standing with obligations",
	# and `SocialState.regard`'s own note already named a clan as the institution this
	# read model was opened for. `sect/` and `nation/` bridged; `clan/` held no regard
	# number at all, so the social advantage a house was designed to confer existed in
	# prose only. These are the two acts that close it.
	#
	# **The magnitudes are a deliberate tier BELOW the sect pair.** A sworn oath is a
	# chosen public commitment; entry to a house is usually inherited, bought or
	# arranged by someone else before the member could refuse it, and a line persists
	# across generations in a way a sect's roster does not. So entry is worth 1.5 where
	# `sworn_to_sect` is 2.0, and a member who never chose the house starts slightly
	# ahead of a stranger rather than a third of the way to a friendship.
	#
	# `sworn_to_a_clan` is persistent for the same reason `sworn_to_sect` is: the house
	# remembers having had you, and ADR 0091's floor is what makes time drift toward
	# that record rather than back to a stranger. `left_a_clan` is transient and small,
	# matching `left_a_sect` exactly — walking out of a house is a choice and always
	# permitted, so the cost is the standing and nothing else. There is deliberately no
	# `expelled_from_clan`: the clan module publishes no expulsion verb, and authoring a
	# cause no call site can apply is the inert-vocabulary defect ADR 0076's catalog
	# exists to prevent.
	#
	# `kind` is `clan` for both, so the anti-farm rule counts a whole career of house
	# membership as ONE kind of act and the class ladder can never be climbed by
	# re-joining houses.
	_institutional(
		&"sworn_to_a_clan", {"standing": 1.5, "trust": 0.03, "persistent": true, "kind": &"clan"}
	)
	_institutional(&"left_a_clan", {"standing": -1.0, "kind": &"clan"})


## `_add` with `institutional` forced on. **The flag is set here rather than in each
## field map** so that being institutional is a property of the CALL SITE rather than
## a key a future author can omit: a membership cause added without it would silently
## never appear in `regard`, which is precisely the unwritten-field defect this
## catalog exists to close, reappearing one entry down.
func _institutional(cause_id: StringName, fields: Dictionary) -> void:
	var authored := fields.duplicate()
	authored["institutional"] = true
	_add(cause_id, authored)


func _add(cause_id: StringName, fields: Dictionary) -> void:
	var cause := SocialCauseDef.new()
	cause.id = cause_id
	cause.persistent = bool(fields.get("persistent", false))
	cause.institutional = bool(fields.get("institutional", false))
	# The kind the anti-farm rule counts. Falls back to the first authored tag so a
	# gift-tier cause and a combat-tier cause never land in the same bucket.
	cause.kind = StringName(fields.get("kind", _first_tag(fields)))
	cause.standing = float(fields.get("standing", 0.0))
	cause.trust = float(fields.get("trust", 0.0))
	for tag in fields.get("tags", []):
		cause.tags.append(StringName(tag))
	cause.promotes_to = StringName(fields.get("promotes_to", ""))
	_causes[String(cause_id)] = cause


## The first authored tag, used as the cause's `kind` when none is named. The shipped
## causes already tag themselves `gift` / `combat` / `oath` / `harm`, which is exactly the
## axis the anti-farm rule wants, so deriving from it costs no new authoring.
func _first_tag(fields: Dictionary) -> String:
	var tags: Array = fields.get("tags", [])
	if tags.is_empty():
		return ""
	return String(tags[0])


func cause_definition(cause_id: StringName) -> SocialCauseDef:
	return _causes.get(String(cause_id))


func cause_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for cause_id in _causes.keys():
		out.append(StringName(cause_id))
	out.sort()
	return out


## Test seam: drop the authored set entirely, so a suite installs exactly what it needs.
## Note this clears the DEFAULT causes too — a test that then uses `gifted_item` without
## installing it will correctly find nothing, which is why the social suite authors its
## own causes rather than leaning on the shipped ones.
func reset() -> void:
	_causes.clear()


## Test seam: restore the shipped default set, for a suite that only overrode one cause.
func install_defaults() -> void:
	_causes.clear()
	_install_defaults()


func install(defs: Array[SocialCauseDef]) -> void:
	for cause in defs:
		_causes[String(cause.id)] = cause
