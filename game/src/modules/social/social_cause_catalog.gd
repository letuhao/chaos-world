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
	_add(
		&"shared_brotherhood",
		{"standing": 5.0, "trust": 0.15, "persistent": true, "promotes_to": SocialBondClass.SWORN}
	)
	_add(&"robbed", {"standing": -6.0, "tags": [&"harm"]})
	_add(&"attacked_unprovoked", {"standing": -8.0, "tags": [&"combat", &"harm"]})
	_add(&"killed_their_kin", {"standing": -10.0, "tags": [&"combat", &"harm"]})
	_add(&"betrayed_oath", {"standing": -12.0, "trust": -0.4, "tags": [&"oath", &"harm"]})
	_add(&"slandered", {"standing": -4.0, "trust": -0.12, "tags": [&"harm"]})
	_install_institutional()


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
## An oath sworn to a sect and a war fought for a nation are facts the world keeps
## after the membership ends; a resignation and an expulsion are the institution's
## verdict and decay with it. The FLOOR is the mechanism (ADR 0091's decay clause):
## `SocialBond.apply` raises the floor only on a persistent cause, so time moves a
## broken bond toward the promise it was given rather than back to a stranger.
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
			"tags": [&"institution", &"nation", &"deed"]
		}
	)


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
	cause.standing = float(fields.get("standing", 0.0))
	cause.trust = float(fields.get("trust", 0.0))
	for tag in fields.get("tags", []):
		cause.tags.append(StringName(tag))
	cause.promotes_to = StringName(fields.get("promotes_to", ""))
	_causes[String(cause_id)] = cause


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
